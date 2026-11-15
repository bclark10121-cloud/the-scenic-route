# The Scenic Route: project rules

The Scenic Route is Brian Clark's calm rally driving game. Godot 4.6, Android and browser. This repo is public.

## Standards (G0.10, G10)

- Read `GAME_STANDARDS.md` (rule ids start with G) and `ENGINEERING_STANDARDS.md` (rule ids start with E) first. Both live only in the private repo `bclark10121-cloud/game-standards`. Clone it outside this repo (`../game-standards`). This repo holds no copies. Never edit them. Propose a change to Brian instead.
- Overrides, open items and the standards version this game was checked against live in `STANDARDS_OVERRIDES.md`. Order of authority: Brian in the chat, then `STANDARDS_OVERRIDES.md`, then the standards. Only Brian approves an override. Propose it, mark it Proposed and list it as a judgment call. Always write rule ids with their prefix (G4.1, E4.1). A rule that applies but is not finished is an open item, not an override.
- The shared kit is pulled into `addons/bc_common/`, `tools/common/` and `tests/common/` with `bash ../game-standards/common/sync_common.sh ../game-standards .` Never edit those files here. Propose changes to Brian for `game-standards/common`. Pull the newest kit before each release and name its version in the release notes (G10.4).
- Signing: the key and its settings live in the private repo `bclark10121-cloud/game-signing` (G1.7). Clone it outside this repo (`../game-signing`). Build the APK with `APKSIGNER=<path to apksigner> tools/common/sign_android.sh <apk path>`. Never commit a key, a password or `signing.properties`.
- Game-only rules and pillars stay in this file.

## Pillars (never break these)

1. No opponents. No battles.
2. No way to lose. No damage, no fuel, no countdowns. Lap circuits are optional and timed against your own best only (Brian asked for them on 2026-11-14).
3. Driving through scenery is the reward.
4. A reset always puts the car back on a road with no penalty.

## Rules

- Top menu: one Menu button at the top right opens all options in a row across the top.
- This repo is public. Never commit a signing key, keystore or password (G1.2).
- Original cars, names and art only. Nothing copied from art of rally or any other game.
- The car's front is +Z. Positive `steer_in` turns right.
- Roads are raised beds with their own collision (`_ribbons`). The ground under a road sits `ROAD_BED` lower. Never draw a road as a thin layer on the ground: it flickers and tears on phones.
- Railings never cross another road (`_on_other_road`).
- Never rename or remove a find id in `data/finds.json` (saves list found ids).
- Save file is `user://scenic_route.json`, format `v: 1`. Only add fields, each with a safe default.
- Every outside asset goes in `CREDITS.md` with its licence.
- Test hooks stay off for players (G7.8). Browser test switches (`fast`, `safe`) and the test keys (1 to 9, 0, minus and equals) work only with the whole-word `?test` flag, read with `TestBridge.has_flag` from the kit, or in the editor and the headless test drivers. Every browser test opens `index.html?test`. Never let a test hook write a save outside test mode.
- `docs/` is the GitHub Pages site: landing page at the root, the game in `docs/play/`, APKs in `docs/downloads/`.

## Test gate (every release)

- `bash tools/common/sync_common.sh --check .` must print `COMMON check ok` (G10.3).
- `bash tools/common/check_secrets.sh` must print `SECRETS check ok` (G1.9).
- `--bot` must show `up_min` near 1.00 on every line (the car never rolls over).
- `--drive` and `--drive --auto` must each finish a lap with `resets 0`.
- `--reach` must print `bad 0` and the full find count (198 in v0.5).
- `--drive --track0` to `--track5` must each print a timed lap. Aim for `resets 0`. A reset from running wide into a bridge railing is a known limit of the test driver.
- `--jump` must print `rolled 0`.
- `tests/web_m1.py` must print `errors []`. View the screenshots.
- `tests/web_std.py` must print `errors []`. View its screenshots: the HUD inside the pretend notch, touch pads hidden on keyboard input and the setting kept after a reload.
- After the push, `python3 tests/common/page_check.py https://bclark10121-cloud.github.io/the-scenic-route/` must print `errors []` (G1.8, G7.4).

## Deliver every time (every release)

1. The game page link: https://bclark10121-cloud.github.io/the-scenic-route/ (landing page with Play and Download buttons). Give Brian this link, not the direct play link.
2. The GitHub repo link: https://github.com/bclark10121-cloud/the-scenic-route
3. The APK, named `TheScenicRoute-v<version>.apk`, in `docs/downloads/` and sent to Brian as a file. Package id `com.brianclark.thescenicroute`. Raise `version/code` by one on every build. Build and sign it with `tools/common/sign_android.sh` (key from `game-signing`, signature SHA-256 starts with `5db69ffb`).
4. The backlog: `BACKLOG.md`, updated, linked and sent to Brian as a file.
5. `docs/index.html` updated: the line under the buttons reads exactly `Version <version>. Release notes · Backlog · Source on GitHub` (G1.8), and the APK link. What is new goes in `docs/release-notes/v<version>.md`, with a test checklist and the kit version.
6. The browser build goes in `docs/play/`.
7. The game standards handoff zip: run `tools/common/make_handoff.sh ../game-standards ../scenic-out` and send `Game_Standards_handoff.zip` to Brian as a file (G2.5).

## Reporting to Brian

Lead with the link or file to test. Segment the answer. Short active sentences. No em dashes, no semicolons, no Oxford comma. State plainly what was tested and where. List every judgment call.
