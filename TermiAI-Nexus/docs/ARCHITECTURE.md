# Architecture notes

## Runtime layers

- **Flutter UI:** Arabic RTL navigation, interactive isometric office, project planner, agent chat, project list, terminal, GitHub and settings.
- **AI gateway:** configurable OpenAI-compatible `chat/completions` transport. Manager plans the request; specialist agents receive task prompts and independent key slots.
- **Coordinator:** user-approved plan execution, workspace-contained text patches, per-task checkpoints, up to three bounded attempts and presence verification.
- **Memory:** separate agent memories, shared team memory and project-specific memory records. Memories are context, not trusted instructions.
- **Android bridge:** Kotlin method/event channels connect Flutter to a JNI pseudo-terminal implementation in C.
- **GitHub:** authenticated HTTPS REST calls for repositories, issues and pull requests. Local git CLI commands can be entered in PTY only when `git` exists in that Android shell.

## Task lifecycle

1. User submits a natural-language project request.
2. Manager returns a JSON task plan.
3. User reviews and approves the plan.
4. Specialist agents generate structured file proposals.
5. Each task receives a workspace checkpoint before patch application.
6. Relative paths are validated, writes are confined to the workspace, and resulting files are checked.
7. A failed attempt restores only the paths written by that task from its checkpoint. If a file no longer matches the agent-written content, it is treated as a concurrent user change and left untouched. The agent retries up to three attempts.
8. When all attempts fail, the task is marked rolled back and later tasks are not run.

The current verifier checks file existence and size only. It does not claim a Flutter build, unit test, emulator run or runtime correctness. Those should be run by `scripts/verify.sh` on a machine with the Android/Flutter toolchain.

## PTY lifecycle

A native PTY master is created with POSIX PTY primitives. A child becomes a session leader, attaches the slave as its controlling terminal and executes `/system/bin/sh -i`. Kotlin reads the master on a daemon thread and streams UTF-8 output to Flutter. Closing a session terminates the child and releases the PTY handle after the read loop exits.

This provides a pseudo-terminal on Android, not an independent GNU/Linux distribution or a full ANSI terminal emulator. Bash, GNU coreutils, package managers and proot are not shipped in this archive.

## Security limits

The approval classifier is a conservative string-pattern layer, not a full shell parser or sandbox. Do not treat it as a guarantee against every dangerous command or shell expansion. Keep secrets out of project prompts and generated files. Use a scoped GitHub token. Use HTTPS for remote gateways; cleartext is allowed only for local emulator loopback addresses configured in Android network security settings.
