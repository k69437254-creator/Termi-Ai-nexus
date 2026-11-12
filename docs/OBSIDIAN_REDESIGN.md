# TermiAI-Nexus — Obsidian UI Redesign

Base revision: `5b64db07db34e88ea82ebf4f9a192760395bf212`
Target branch: `integration/aram-ai-engine`

## What this package changes

- Establishes the Obsidian dark palette and Electric Violet accent as the shared Material 3 design system.
- Adds reusable translucent glass panels, page/section headers, icon tiles and status pills.
- Reworks the application shell, drawer, bottom navigation and page transitions.
- Rebuilds the primary assistant screen as a full-screen conversation with chat bubbles, an anchored composer and project-plan cards inside the conversation.
- Keeps the project planner's approval gate and coordinator execution flow intact. The current gateway does not expose a cancellable request handle, so this redesign does not present a fake Stop action.
- Restyles the office, agents, project list, control center, terminal, GitHub, settings and Aram AI engine center.
- Adds the existing Aram AI engine center to the app drawer so it can be opened from the interface.
- Retunes the existing 3D office palette toward dark violet without altering its geometry, gestures or rendering logic.

## Intentionally unchanged

- AI gateway and coordinator behavior.
- Approval policy, workspace patch validation, checkpoints, retry and rollback logic.
- Android PTY bridge and native shell implementation.
- Aram AI model/runtime lifecycle and model download/import method calls.
- GitHub API operations and secure storage keys.

## Apply from Termux

1. Extract this package into a folder in Termux storage.
2. From the repository root, run the included `apply_obsidian_redesign.sh` and pass the repository path.
3. The installer requires the exact base commit and branch, refuses to overwrite locally modified target files, and creates an external backup before copying.
4. It does not stage, commit, push, merge, or delete repository files.

After installation, run `flutter pub get` only if package resolution is needed, then run `flutter analyze`. Build and device validation are still required before treating the redesign as complete.
