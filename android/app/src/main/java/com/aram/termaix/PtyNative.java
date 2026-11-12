package com.aram.termaix;

/** JNI wrapper for the native Android pseudo-terminal bridge. */
public final class PtyNative {
    static {
        System.loadLibrary("ptybridge");
    }

    private PtyNative() {}

    public static native long nativeSpawn(String workingDirectory, int rows, int columns);
    public static native int nativeRead(long handle, byte[] destination);
    public static native int nativeWrite(long handle, byte[] source);
    public static native void nativeResize(long handle, int rows, int columns);
    public static native void nativeClose(long handle);
    public static native void nativeRelease(long handle);
}
