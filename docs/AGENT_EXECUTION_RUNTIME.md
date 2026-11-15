# Agent execution runtime

## Execution pipeline

1. The manager creates a sequential plan and requires a developer task plus a final QA task.
2. Agents inspect the workspace and write source files into per-attempt staging storage using bounded `write_file_chunk` calls. Staged content is not exposed as completed project output until the manifest is validated.
3. The coordinator validates every path and size, checkpoints the workspace, applies the patch batch, and verifies the complete bytes. Partial writes are rolled back on failure; concurrent user edits are preserved and reported as an incomplete rollback.
4. `run_command` invokes argv directly inside the app-private Ubuntu/PRoot guest. The guest mounts the project workspace at `/workspace` and also exposes runtime/system mounts such as `/proc`, `/sys`, `/dev`, `/dev/pts`, and standard file descriptors. PRoot is not a hardened security sandbox and must not be treated as isolation from hostile code. It does not fall back to Android Toybox. Shell `-c`/`-lc`, destructive Git operations, and GitHub write operations are rejected. Package installation may execute maintainer scripts inside the guest and must be treated as trusted-code execution.
5. The final QA task must obtain at least one successful test, analysis, or build command result from the guest before it can be marked complete.

## Runtime prerequisites and limits

- Ubuntu/PRoot must be successfully installed inside the app before project commands can run. Without it, command execution fails explicitly; source files are not reported as a tested build.
- Flutter, Dart, Android SDK, Java, Node, Python packages, and other project toolchains are not all part of the Ubuntu Base installation. Install only the tools required by a project in the guest before expecting its build/test command to work. An unavailable tool is a failed verification, not a pass.
- Output is generated in bounded chunks. The native model output ceiling is 2048 tokens per inference call; large projects may require multiple tool calls and can still hit the task call limit.
- Git commit/push, GitHub issue/PR creation, destructive commands, and commands requiring host access are not autonomous capabilities in this update. They require separately designed approval and Git adapters.
- PRoot provides a Linux userland and path namespace, not a hardened security sandbox against malicious project scripts. Do not place credentials in project workspaces or run untrusted projects without explicit review.
- An in-flight guest command is bounded by a 900-second timeout; this update does not yet guarantee immediate process-tree termination when the user cancels during that command. Cancellation is honored at the next model boundary.
- A successful QA command proves only the command that actually ran. Device installation, UI behavior, and production readiness still require corresponding device-level tests.
