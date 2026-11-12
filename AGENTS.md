# AGENTS.md — guide for AI coding agents

Instructions for AI agents (Claude Code, Codex, Cursor, etc.) working on this
repository. Humans: start with [README.md](README.md) instead.

## What this project is

Lintel — a macOS menu-notch file shelf (AppKit, Swift) with optional
folder sync to a second Mac over Tailscale (rsync/ssh, push-only).
Architecture rationale: [docs/architecture/decisions/ADR-0001](docs/architecture/decisions/ADR-0001-notch-shelf-sync.md).

## Commands

```bash
make build    # debug build (swift build)
make test     # ALL tests — run before every commit; must print «Все проверки прошли»
make app      # assemble build/Lintel.app (icon .icns is generated here)
make install  # build + install to /Applications + relaunch
make deploy   # install + push the build to a second machine over ssh
```

`make deploy` needs a peer host: `make deploy PEER=<host>` or a stored
default (`defaults write dev.mike.Lintel deployPeer <host>`). Never hardcode
host names in the repo (see "Repo hygiene").

There is **no Xcode project**: plain SwiftPM, built with Command Line Tools
only. XCTest/Swift Testing are unavailable — tests live in the executable
target `Sources/lintel-selftest` (plain assertions, non-zero exit on failure).

## Code map

| Path | Role |
|---|---|
| `Sources/LintelCore/` | pure logic, no AppKit — every function here must be covered in selftest |
| `Sources/LintelCore/Naming.swift` | unique file names on collision |
| `Sources/LintelCore/ShelfGeometry.swift` | panel geometry, animation progress |
| `Sources/LintelCore/PeerHost.swift` | peerHost validation (security boundary) |
| `Sources/LintelCore/Sync.swift` | which shelf files count as newly-arrived |
| `Sources/Lintel/AppDelegate.swift` | panel lifecycle, screens, frame animation |
| `Sources/Lintel/ShelfPanel.swift` | NSPanel above the notch (`.nonactivatingPanel`) |
| `Sources/Lintel/ShelfView.swift` | drop target + drag source + drawing + context menu |
| `Sources/Lintel/ShelfStore.swift` | `~/Shelf` folder, watcher, quarantine marking |
| `Sources/Lintel/ThumbnailCache.swift` | QuickLook previews (async) |
| `Sources/Lintel/Transport.swift` | rsync/ssh push, retries, delivery status |
| `Sources/lintel-selftest/` | the whole test suite |
| `Sources/lintel-mcp/` | MCP server (stdio JSON-RPC, no deps): shelf_list/grab/put/remove for agents |
| `scripts/lintel-receive.sh` | forced-command wrapper for the transport ssh key |
| `Sources/LintelCore/Settings.swift` | settings domain + one-time migration from the old `dev.mike.Chelka` domain |
| `scripts/make-icon.swift` | draws the app icon in code → `Resources/AppIcon-1024.png` (macOS grid: 824×824 body on 1024 canvas) |

## Invariants — do not break these

Security (each one is audited and tested; see [docs/security/index.md](docs/security/index.md)):

1. **`Transport.peerHost` must stay validated** by `PeerHost.isValid` before
   reaching ssh/rsync arguments. Never pass user-controlled strings into
   process arguments without validation.
2. **No shell, ever.** External processes are spawned via `Process` with
   argument arrays. Do not introduce `sh -c`, string interpolation into
   commands, or `system()`.
3. **The wrapper contract**: the transport key on a receiver may only run
   `mkdir -p Shelf`, `lintel-clear` (Shelf contents → Trash, recoverable; the
   pre-rename name `chelka-clear` is accepted too, for peers still on Chelka) and
   `rsync --server … . Shelf/` (no `--sender`). If you
   change Transport's remote commands, update `scripts/lintel-receive.sh`
   and its tests together, and mind setups with the old wrapper deployed.
4. **`StrictHostKeyChecking=yes`** in transport — pinning happens at
   `ssh-copy-id` time. Do not relax to `accept-new`/`no`.
5. **`--ignore-existing`** on rsync — receiver files are never overwritten.
6. **Quarantine on arrivals**: `ShelfStore.reload` marks files that appeared
   without a local drop (`Sync.newcomers` + `Quarantine.markIfNeeded`).
7. Deletion goes to the Trash only (`trashItem`), never permanent.

UI:

8. `ShelfPanel` must keep `.nonactivatingPanel` — otherwise drags from Finder
   break (window steals focus).
9. Collapse of the shelf goes through the 150 ms hysteresis
   (`requestCollapse`) — AppKit emits spurious mouseExited during frame
   animation; naive collapse causes visible flicker.
10. Drawing is progress-driven (`ShelfGeometry.expandProgress` from the
    current window height), so content grows/fades with the frame animation.

## Working rules

- **Tests first-class**: new pure logic goes to `LintelCore` and gets selftest
  coverage in the same commit. `make test` green before every commit.
- **Docs ship with code**: user-visible changes update README.md **and**
  README.ru.md (they mirror each other); every change lands in
  `docs/CHANGELOG.md` (Keep a Changelog); security-relevant changes update
  `docs/security/index.md`; test changes update `docs/testing/index.md`.
- **Repo hygiene**: no personal data in tracked files — no real hostnames,
  tailnet names, IPs or usernames; use `<peer>`-style placeholders in docs
  and defaults/parameters in tooling.
- **Commits**: meaningful units, message explains what and why, **always in English**.

## Verifying changes

- Logic: `make test`.
- UI (needs a human or a screenshot): `make install`, hover the notch —
  shelf slides out; drop a file — it lands on the shelf and in `~/Shelf`.
  Manual checklist: [docs/testing/index.md](docs/testing/index.md).
- Transport without the app: simulate exactly what Transport runs:
  ```bash
  ssh -o BatchMode=yes <peer> 'mkdir -p Shelf'
  rsync -a --ignore-existing -e "ssh -o BatchMode=yes -o StrictHostKeyChecking=yes" <file> <peer>:Shelf/
  ```
- App logs: `log show --last 30m --predicate 'eventMessage CONTAINS "Lintel"' --style compact`.
- MCP: the server ships inside the app bundle
  (`/Applications/Lintel.app/Contents/MacOS/lintel-mcp`); the repo's `.mcp.json`
  registers it for Claude Code in-project. Smoke test: pipe JSON-RPC lines
  (initialize → tools/list → tools/call) into the binary. shelf_put send:true
  must keep using PushPlan — same security invariants as Transport.

## Common tasks

- **Change shelf UI/behavior** → `ShelfView.swift` (+ geometry in
  `ShelfGeometry` with tests if sizes/layout change).
- **Change transport** → `Transport.swift`; re-read invariants 1–5; update
  wrapper + its tests if remote commands change.
- **New app icon** → edit the drawing in `scripts/make-icon.swift`, run
  `swift scripts/make-icon.swift Resources/AppIcon-1024.png` and commit the PNG
  (icon must fill the 824×824 body, no margins inside it), `make install`,
  visually verify at small sizes (16/32 px).
- **Release/deploy to own machines** → `make deploy` (peer via defaults).

## Documentation map

```
README.md / README.ru.md      # users: what it is, install (1 or 2 Macs), usage
AGENTS.md (this file)         # AI agents; CLAUDE.md points here
docs/
├─ index.md                   # docs index
├─ CHANGELOG.md               # Keep a Changelog
├─ architecture/decisions/    # ADRs: folder-sync design (0001), rename Chelka → Lintel (0002)
├─ testing/index.md           # test strategy + manual checklist
└─ security/index.md          # threat model, audit findings, verification
```
