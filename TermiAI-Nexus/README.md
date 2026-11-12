# TermiAI-Nexus

**A mobile AI development workspace for Android** — an interactive 3D-inspired agent headquarters, natural-language project planning, multi-agent orchestration, an Android PTY shell, GitHub REST integration, project-scoped memory, approval gates, checkpoints and bounded automatic recovery.

> This repository is a real Flutter/Android source project, not a prebuilt APK. Flutter, Android SDK, Android NDK and CMake are required to build it. This environment did not contain Flutter/Dart, so a Flutter/Gradle build could not be executed here. See `docs/IMPLEMENTATION_STATUS.md` for tested and environment-dependent parts.

## What's included

- Arabic-first RTL Flutter application with a dark Material 3 interface.
- Interactive isometric 3D office scene. Drag to orbit and pinch to zoom; agent stations and a central meeting table are drawn from 3D coordinates.
- Project brief → AI-generated plan → user approval → agent task execution workflow.
- Five role-based agents, each with an independent API key slot and private memory, plus shared team/project memory.
- OpenAI-compatible chat-completions adapter. Configure a local endpoint or your Aram AI-compatible gateway; no API URL or secret is invented or bundled.
- Android native PTY bridge using `posix_openpt`/`fork` and `/system/bin/sh` for an interactive Android shell session.
- GitHub REST API support for listing repositories, creating repositories, creating issues and opening pull requests.
- Project-aware agent prompts built from a bounded snapshot of the workspace; secret-like files, key stores, environment files and generated folders are excluded. Patches are constrained to the project root and symlink destinations are rejected.
- Approval classification for high-risk shell commands and external/destructive operations.
- Automatic bounded repair/retry workflow with verification hooks and rollback to the last task checkpoint.
- Secure storage for API keys and GitHub token; app preferences and memories are stored separately. Agent/team/project memories are local and project-scoped.
- Agent-to-user chat can continue independently while the sequential project coordinator runs; the agent's output is stored in its own memory.

## Quick start

1. Install Flutter stable with Dart 3.11+, Android Studio, Android SDK Platform Tools, Android NDK `27.0.12077973` and CMake `3.22.1`.
2. From this folder run `flutter pub get`.
3. Copy `android/local.properties.example` to `android/local.properties` and set both `flutter.sdk` and `sdk.dir` to your installed Flutter and Android SDK paths. Android Studio may create this file automatically.
4. Open the folder in Android Studio or run `flutter run` on an Android device (Android 8.0 / API 26 or newer).
5. Open **Settings → AI Engine** and enter the OpenAI-compatible base URL, model name and owner API key. Add independent keys for agents if your gateway issues them. A local model service can be connected through a local compatible endpoint; no model weights or inference runtime are bundled.
6. Note that source context is sent to the configured AI endpoint. The snapshot is limited to 32 files / about 80,000 characters and skips common secret file names, environment files, credentials and generated folders; review your project and gateway privacy policy before use.
7. Open **Settings → GitHub** and add a GitHub Personal Access Token with the least permissions required by the operations you plan to use.

## API configuration

The app expects an OpenAI-compatible endpoint ending in `/chat/completions` or a base URL to which that path can be appended. Example base URL shape: `https://your-gateway.example/v1`. This is documentation, not a live endpoint. The model name and all keys are user-supplied. Secrets are never written into source files. Agent/team/project memory uses the secure storage layer; the project catalog stores local project metadata in app preferences. Each agent can have a distinct key, but the app does not mint keys through Aram AI; issue those in your gateway and enter them here.

## Terminal and Linux note

The included native PTY starts Android's `/system/bin/sh`. That is a genuine interactive pseudo-terminal, but it is **not** a bundled Debian/Ubuntu GNU/Linux distribution. A complete Linux userland requires a separate, legally redistributable bootstrap and storage setup (for example, a proot-based distribution). This archive does not falsely claim that such a distribution is bundled. Git commands require a `git` executable available in the shell environment; GitHub's REST features currently cover repository listing/creation, issue creation and pull-request creation. Full local clone/commit/push orchestration, repository code-review automation and CI management are not implemented in this archive.

## Safety model

- The planner displays a plan before execution.
- Shell operations matching destructive, privilege, remote execution, credential or external-write patterns are flagged for explicit approval.
- AI-generated file patches are restricted to the active workspace and a checkpoint is created before applying them.
- Repair attempts are bounded (default: 3); failed processing restores only files written by the task; files that no longer match the agent output are treated as concurrent user edits and are not overwritten.
- File verification currently checks path safety, existence and size only. It does not execute Flutter builds, tests, static analysis or runtime checks. Retry history is retained in memory for later agent context; no model weights are trained.
- API keys and GitHub tokens are stored using `flutter_secure_storage` on Android.

## Developer

**Aram Aoyal**  
Telegram: https://t.me/ro_gy

## License

Private project scaffold. Review third-party dependency licenses before redistribution.

### Gradle wrapper

The `android/gradlew` scripts are a small bootstrap wrapper that downloads the pinned official Gradle 8.13 distribution from `services.gradle.org` on first use when it is not already cached. The wrapper JAR is intentionally not vendored. A working internet connection is therefore needed for the first Gradle invocation unless Gradle 8.13 is already cached in the configured Gradle home.
