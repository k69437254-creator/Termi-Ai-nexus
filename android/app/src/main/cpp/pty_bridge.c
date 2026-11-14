#define _GNU_SOURCE
#include <jni.h>
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

#ifndef TIOCSCTTY
#define TIOCSCTTY 0x540E
#endif

typedef struct PtyHandle {
    int master_fd;
    pid_t child_pid;
    int closed;
    pthread_mutex_t mutex;
} PtyHandle;

static PtyHandle *from_handle(jlong value) {
    return (PtyHandle *)(intptr_t)value;
}

JNIEXPORT jlong JNICALL Java_com_aram_termaix_PtyNative_nativeSpawn(
    JNIEnv *env, jclass clazz, jstring working_directory, jint rows, jint columns, jstring github_token) {
    (void)clazz;
    const char *cwd = NULL;
    const char *token = NULL;
    if (working_directory != NULL) cwd = (*env)->GetStringUTFChars(env, working_directory, NULL);
    if (github_token != NULL) token = (*env)->GetStringUTFChars(env, github_token, NULL);
    if (github_token != NULL && token == NULL) {
        if (cwd != NULL) (*env)->ReleaseStringUTFChars(env, working_directory, cwd);
        if (token != NULL) (*env)->ReleaseStringUTFChars(env, github_token, token);
        return 0;
    }

    int master = posix_openpt(O_RDWR | O_NOCTTY);
    if (master < 0 || grantpt(master) != 0 || unlockpt(master) != 0) {
        if (master >= 0) close(master);
        if (cwd != NULL) (*env)->ReleaseStringUTFChars(env, working_directory, cwd);
        if (token != NULL) (*env)->ReleaseStringUTFChars(env, github_token, token);
        return 0;
    }

    char *slave_name = ptsname(master);
    if (slave_name == NULL) {
        close(master);
        if (cwd != NULL) (*env)->ReleaseStringUTFChars(env, working_directory, cwd);
        if (token != NULL) (*env)->ReleaseStringUTFChars(env, github_token, token);
        return 0;
    }
    char slave_path[256];
    snprintf(slave_path, sizeof(slave_path), "%s", slave_name);

    pid_t child = fork();
    if (child < 0) {
        close(master);
        if (cwd != NULL) (*env)->ReleaseStringUTFChars(env, working_directory, cwd);
        if (token != NULL) (*env)->ReleaseStringUTFChars(env, github_token, token);
        return 0;
    }

    if (child == 0) {
        close(master);
        if (setsid() < 0) _exit(126);
        int slave = open(slave_path, O_RDWR | O_NOCTTY);
        if (slave < 0) _exit(126);
        (void)ioctl(slave, TIOCSCTTY, 0);
        (void)dup2(slave, STDIN_FILENO);
        (void)dup2(slave, STDOUT_FILENO);
        (void)dup2(slave, STDERR_FILENO);
        if (slave > STDERR_FILENO) close(slave);
        struct winsize window;
        memset(&window, 0, sizeof(window));
        window.ws_row = (unsigned short)(rows > 0 ? rows : 28);
        window.ws_col = (unsigned short)(columns > 0 ? columns : 100);
        (void)ioctl(STDIN_FILENO, TIOCSWINSZ, &window);
        (void)setenv("TERM", "xterm-256color", 1);
        (void)setenv("HOME", "/data/local/tmp", 0);
        if (token != NULL) {
            size_t token_length = strlen(token);
            int valid = token_length >= 20 && token_length <= 256;
            for (size_t i = 0; valid && i < token_length; ++i) {
                unsigned char ch = (unsigned char)token[i];
                int allowed = (ch >= 65 && ch <= 90) || (ch >= 97 && ch <= 122) ||
                    (ch >= 48 && ch <= 57) || ch == 95 || ch == 45;
                if (!allowed) valid = 0;
            }
            if (valid) {
                (void)setenv("GH_TOKEN", token, 1);
                (void)setenv("GITHUB_TOKEN", token, 1);
                (void)setenv("GIT_TERMINAL_PROMPT", "0", 1);
            }
        }
        if (cwd != NULL && cwd[0] != '\0') (void)chdir(cwd);
        execl("/system/bin/sh", "sh", "-i", (char *)NULL);
        _exit(127);
    }

    if (cwd != NULL) (*env)->ReleaseStringUTFChars(env, working_directory, cwd);
    if (token != NULL) (*env)->ReleaseStringUTFChars(env, github_token, token);
    struct winsize window;
    memset(&window, 0, sizeof(window));
    window.ws_row = (unsigned short)(rows > 0 ? rows : 28);
    window.ws_col = (unsigned short)(columns > 0 ? columns : 100);
    (void)ioctl(master, TIOCSWINSZ, &window);

    PtyHandle *handle = (PtyHandle *)calloc(1, sizeof(PtyHandle));
    if (handle == NULL) {
        close(master);
        (void)kill(-child, SIGKILL);
        (void)waitpid(child, NULL, 0);
        return 0;
    }
    handle->master_fd = master;
    handle->child_pid = child;
    handle->closed = 0;
    if (pthread_mutex_init(&handle->mutex, NULL) != 0) {
        close(master);
        (void)kill(-child, SIGKILL);
        (void)waitpid(child, NULL, 0);
        free(handle);
        return 0;
    }
    return (jlong)(intptr_t)handle;
}

JNIEXPORT jint JNICALL Java_com_aram_termaix_PtyNative_nativeRead(
    JNIEnv *env, jclass clazz, jlong value, jbyteArray destination) {
    (void)clazz;
    PtyHandle *handle = from_handle(value);
    if (handle == NULL || destination == NULL) return -1;
    pthread_mutex_lock(&handle->mutex);
    int fd = handle->closed ? -1 : handle->master_fd;
    pthread_mutex_unlock(&handle->mutex);
    if (fd < 0) return 0;

    jsize capacity = (*env)->GetArrayLength(env, destination);
    if (capacity <= 0) return 0;
    jbyte *buffer = (jbyte *)malloc((size_t)capacity);
    if (buffer == NULL) return -1;
    ssize_t count;
    do { count = read(fd, buffer, (size_t)capacity); } while (count < 0 && errno == EINTR);
    if (count > 0) (*env)->SetByteArrayRegion(env, destination, 0, (jsize)count, buffer);
    free(buffer);
    if (count < 0 && (errno == EIO || errno == EBADF || errno == EINTR)) return 0;
    return (jint)count;
}

JNIEXPORT jint JNICALL Java_com_aram_termaix_PtyNative_nativeWrite(
    JNIEnv *env, jclass clazz, jlong value, jbyteArray source) {
    (void)clazz;
    PtyHandle *handle = from_handle(value);
    if (handle == NULL || source == NULL) return -1;
    pthread_mutex_lock(&handle->mutex);
    int fd = handle->closed ? -1 : handle->master_fd;
    pthread_mutex_unlock(&handle->mutex);
    if (fd < 0) return -1;
    jsize length = (*env)->GetArrayLength(env, source);
    jbyte *buffer = (*env)->GetByteArrayElements(env, source, NULL);
    if (buffer == NULL) return -1;
    size_t total = 0;
    while (total < (size_t)length) {
        ssize_t count = write(fd, buffer + total, (size_t)length - total);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) break;
        total += (size_t)count;
    }
    (*env)->ReleaseByteArrayElements(env, source, buffer, JNI_ABORT);
    return total == (size_t)length ? (jint)total : -1;
}

JNIEXPORT void JNICALL Java_com_aram_termaix_PtyNative_nativeResize(
    JNIEnv *env, jclass clazz, jlong value, jint rows, jint columns) {
    (void)env; (void)clazz;
    PtyHandle *handle = from_handle(value);
    if (handle == NULL) return;
    pthread_mutex_lock(&handle->mutex);
    int fd = handle->closed ? -1 : handle->master_fd;
    pthread_mutex_unlock(&handle->mutex);
    if (fd < 0) return;
    struct winsize window;
    memset(&window, 0, sizeof(window));
    window.ws_row = (unsigned short)(rows > 0 ? rows : 28);
    window.ws_col = (unsigned short)(columns > 0 ? columns : 100);
    (void)ioctl(fd, TIOCSWINSZ, &window);
}

JNIEXPORT void JNICALL Java_com_aram_termaix_PtyNative_nativeClose(
    JNIEnv *env, jclass clazz, jlong value) {
    (void)env; (void)clazz;
    PtyHandle *handle = from_handle(value);
    if (handle == NULL) return;
    pthread_mutex_lock(&handle->mutex);
    pid_t child = -1;
    if (!handle->closed) {
        handle->closed = 1;
        child = handle->child_pid;
        handle->child_pid = -1;
    }
    pthread_mutex_unlock(&handle->mutex);

    // Keep the master fd open until the reader wakes and calls nativeRelease.
    // Terminating the foreground shell causes the blocked PTY read to return EIO.
    if (child > 0) {
        (void)kill(-child, SIGTERM);
        int status = 0;
        pid_t waited = 0;
        for (int i = 0; i < 10 && waited == 0; ++i) {
            waited = waitpid(child, &status, WNOHANG);
            if (waited == 0) { struct timespec delay = {0, 20000000L}; nanosleep(&delay, NULL); }
        }
        if (waited == 0) {
            (void)kill(-child, SIGKILL);
            (void)waitpid(child, &status, 0);
        }
    }
}

JNIEXPORT void JNICALL Java_com_aram_termaix_PtyNative_nativeRelease(
    JNIEnv *env, jclass clazz, jlong value) {
    (void)env; (void)clazz;
    PtyHandle *handle = from_handle(value);
    if (handle == NULL) return;
    Java_com_aram_termaix_PtyNative_nativeClose(env, clazz, value);
    pthread_mutex_lock(&handle->mutex);
    if (handle->master_fd >= 0) {
        close(handle->master_fd);
        handle->master_fd = -1;
    }
    pthread_mutex_unlock(&handle->mutex);
    pthread_mutex_destroy(&handle->mutex);
    free(handle);
}
