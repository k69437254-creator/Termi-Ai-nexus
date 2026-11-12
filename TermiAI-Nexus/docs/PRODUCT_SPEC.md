# TermiAI-Nexus — product design and coverage matrix

This document preserves the intended product decisions alongside the current source implementation. It deliberately distinguishes implemented code from planned integration so the source archive is not mistaken for a finished, device-tested product.

| Agreed capability | Current source coverage |
|---|---|
| Default home is the virtual agent headquarters | Implemented as the app's initial page |
| 3D office with individual agent workstations | Implemented as an interactive isometric Canvas scene; agent activity is not yet animated from live task state |
| Free camera movement, rotation, zoom | Drag rotation and pinch zoom/pan implemented; automatic event-follow/focus is not yet wired |
| Central meeting room | Static central meeting table/hub rendered; live agent meeting orchestration is not yet implemented |
| Main natural-language assistant is the project entry point | Implemented: manager prepares a plan |
| Plan review and explicit approval before work starts | Implemented |
| Specialist team with distinct roles/personas | Implemented as five role profiles and role-specific prompts |
| Private text conversation with each agent | Implemented; can operate while project task execution continues |
| User can guide an agent without silently stopping current work | Chat is separate from the sequential task loop; there is no task-interruption command in this version |
| Independent agent memory, shared team memory and project-specific memory | Implemented using secure local storage; memory is not shared across projects except team memory |
| Agents learn from errors and improve | Error/success history is recorded and supplied as future context; automated lesson extraction and strategy scoring are not yet implemented. Model weights are never modified |
| Automatic bounded retries and selective rollback | Implemented in source with up to three attempts and path-level rollback guarded against overwriting concurrent changes |
| Validate fixes by running tests/builds | Not implemented: current verifier checks file presence/size only. Do not infer a passing build or test from a completed task |
| Linux terminal in the app | Native PTY implemented for Android `/system/bin/sh`; no Bash, Debian/Ubuntu, proot or GNU userland is bundled |
| Git and GitHub | GitHub REST list/create repository, create Issue and Pull Request are implemented. Full local Git clone/commit/push, repository review and CI control remain future work and require a Git executable or additional adapters |
| Two-layer control center | Basic control overview exists; a full advanced hardware/service/resource dashboard remains future work |
| Click notification to open office, focus agent and show task panel | Not implemented in this source archive; there is no notification event/router yet |
| Local model option | Compatible HTTP endpoint configuration supports a locally hosted gateway; model weights and inference runtime are not included |
| API keys per agent | Secure per-agent key slots are implemented with owner-key fallback. Issuing/provisioning the keys must happen in the configured gateway; the app does not invent an Aram AI issuance API |
| Developer identity | Aram Aoyal and https://t.me/ro_gy included in Settings |

## Current execution boundary

The project coordinator asks an OpenAI-compatible endpoint for a plan and specialist outputs. Agents receive a bounded workspace snapshot so they can reason about existing source files; common environment/credential/key-store files and generated folders are excluded. Output files are validated and written inside the project workspace. The coordinator does not execute agent-proposed shell commands. PTY commands are entered by the user and pass through a string-pattern approval prompt for known risky forms; this is not a complete shell parser or security sandbox.

## Future integration order

1. Add verified build/test runners in an isolated workspace process and use their real results as QA evidence.
2. Add local Git operations (clone/status/diff/commit/push) and repository review/CI adapters with approval gates.
3. Add live agent/task presence, office camera focus, notification routing and task side panels.
4. Add optional proot-based Linux userland installation and a full terminal emulator, with explicit storage and permission handling.
5. Add evidence-based strategy/lesson extraction from failed and successful repairs.
