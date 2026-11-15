# Game standards (Brian Clark)

Updated with every release of every game. Start a new game by reading this file first.
Source of truth: this file in the newest game repo. Today: `the-scenic-route/handoff/`.

## 1. Repos and pages

1. Every game gets its own public GitHub repo under `bclark10121-cloud`. No shared repos.
2. Never commit a signing key, keystore or password to a public repo. The Android key `wandervalley.jks` lives in the private repo `keeper-of-the-hollow-source`.
3. Every game gets a game page on GitHub Pages: `docs/index.html` in the repo, served from `main` `/docs`.
4. The game page has: a short description, a Play in your browser button, the Android APK download, three screenshots, what kind of game it is, things to do, controls, install steps, a feedback list and links to release notes, backlog and source.
5. The browser build lives in `docs/play/`. APKs live in `docs/downloads/`. Release notes live in `docs/release-notes/v<version>.md`.
6. Brian shares the game page with other people and tests from it. Give him the game page link, never a direct link into the game.

## 2. Deliver with every release

1. Game page link.
2. GitHub repo link.
3. APK, named `<GameName>-v<version>.apk`, sent as a file and live on the game page.
4. Backlog document, updated, sent as a file and linked.
5. Game standards handoff zip (this folder, zipped), sent as a file.
6. Game page updated: version line, what is new, APK link. Release notes with a test checklist.

## 3. Reporting to Brian

1. Lead with the links and files.
2. Segment the answer. Short active sentences. No em dashes, no semicolons, no Oxford comma.
3. Say plainly what was tested and where, and what was not tested.
4. List every judgment call.
5. When Brian reports a bug from a screenshot, fix it before new features.

## 4. Game design defaults

1. Calm games. No combat. No way to lose. A reset never costs anything.
2. Write the pillars in the repo's `CLAUDE.md`. Flag any request that changes a pillar, then reword the pillar once Brian confirms.
3. Things to find, with a counter, a journal and a save file. Finds show a short message near the top third of the screen.
4. Records and achievements are personal bests only. No leaderboards, no opponents.
5. A seasonal theme (Christmas) is a toggle that stays off until turned on.
6. Keep a `BACKLOG.md`: Done, Now, Asked for by Brian, Ideas to choose from, Later, Not planned and Decisions. Offer numbered ideas so Brian picks by number.

## 5. Interface standards

1. Top menu: one Menu button at the top right. It opens every option in a row across the top. It reads Close while open. Esc on a keyboard and Back on a controller toggle it.
2. Nothing else sits on screen while playing except the speed or status readout, the find counter and touch controls.
3. Touch: steer by dragging on the left half. Action buttons on the right. Touch controls appear after the first touch.
4. Controller and keyboard always work. Show the keys on the title card.
5. Title card: name, version line, one line on what the game is, controls and a Start button.
6. Settings and progress save on the device. Only add fields to a save file, each with a safe default. Never rename or remove a saved id.
7. US units: mph and feet.

## 6. Build standards (Godot 4.6)

1. Compatibility renderer, Jolt physics, landscape, 1280 x 720 base, stretch `canvas_items`, aspect `expand`.
2. Exports: Web (no threads) and Android (arm64, package `com.brianclark.<game>`). Raise the version code by one on every build.
3. Sign the APK with `wandervalley.jks`. The signature SHA-256 starts with `5db69ffb`.
4. Build the world in code where possible. Group scenery in chunks so far-off objects are skipped.
5. Phones draw depth coarsely. Never lay a road or decal as a thin layer on the ground. Give it its own raised mesh and collision.
6. Anything a player can touch has collision. Anything on a road can be knocked over or driven round.

### Engineering standards files

Every Godot game repo has two files at its root.

1. `STANDARDS.md`: the Godot 3D engineering standards for browser and Android (code, rendering, assets, physics, display and input, audio and saves). Brian supplied it on 2026-11-14. It is the same in every game. Never edit it for one game. The master copy is in this handoff.
2. `STANDARDS_OVERRIDES.md`: where that one game differs from the standards. Each override names the rule number, what the game does instead and why. Brian approves each one. The file also lists open items and the rules already met. A blank copy is in `templates/`.

Review both with each release. Games that are not Godot 3D do not carry these files.

## 7. Test gate before every release

1. A headless test driver proves the main route is drivable with 0 resets.
2. A report proves every find is reachable.
3. A browser test loads the web build in headless Chrome with `errors []`, and the screenshots are viewed.
4. The live game page and APK link are checked after the push.
5. State what could not be tested (real devices, sound).

## 8. Assets

1. Music: tracks from the Patch.gg library only. Prefer CC0. The search API needs no login: `https://patch.gg/api/v1/assets/search?q=<words>&type=music`.
2. Extra pictures and sounds: Patch.gg library. Check each batch by eye. Styles vary a lot. Loose keyword searches return mismatched art. Pull a whole themed pack from one maker instead (for example the Kenney fish pack) so a batch shares one style.
3. Every outside asset goes in `CREDITS.md` with its source and licence.
4. Original names, cars and art only. Inspiration from other games stays as ideas.

## 9. What is in this handoff

- `GAME_STANDARDS.md`: this file.
- `templates/`: starting points for a new game (`CLAUDE.md`, game page, backlog, release notes, credits, Godot project and export settings, `.gitignore`).
- `reusable/`: code that carries over (`hud.gd` with the Menu button, touch pads, messages and journal. `web_test.py` browser test. `make_sfx.py` chimes. `patch_assets.py` to search and fetch Patch.gg assets).
- `games/`: each game's current rules, backlog and credits for reference.
