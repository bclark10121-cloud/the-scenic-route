# The Scenic Route: standards overrides

Standards: `GAME_STANDARDS.md` (rule ids start with G) and `ENGINEERING_STANDARDS.md` (rule ids start with E) in the private repo `bclark10121-cloud/game-standards`. This repo holds no copies.
This file lists where this game does something else, and why. A rule not listed here applies in full.
Order of authority: Brian in the chat, then this file, then the standards.

Last reviewed: v0.5.2 (2026-11-15).
Checked against: game-standards version 2026-11-14 standards review (commit e4688a1), kit 1.3.0.

## Overrides

| # | Rule | Standard says | This game does | Why | Ends when | Agreed |
|---|---|---|---|---|---|---|
| 1 | E4.1 | The default physics engine is GodotPhysics3D. Avoid Jolt on browser builds. Choose per game and record the choice here. | Jolt Physics, the engine built into Godot 4.6. No add-on. | The car, every ramp and every jump are tuned on it. It passes every browser test. A switch means retuning all of it. | The car is retuned on GodotPhysics3D, or Brian makes built-in Jolt an allowed default. | 2026-11-14 |
| 2 | E3.4 | Set a cull distance on every prop. Cull small details at 25 to 45 m. | No cull distance on props. | The camera sits 82 to 112 m from the car. A 25 to 45 m cutoff would hide every tree on screen. | The standard sets the cull distance from each game's camera distance, or a far cutoff is tuned on a phone. | 2026-11-14 |
| 3 | E4.3 | Primitive colliders only. Never trimesh on moving bodies or complex props. | Trimesh for the static terrain and the road beds only. Everything else uses primitive shapes. | Hills and roads are not a box or a sphere. They are static ground, not moving bodies or props. | The standard says plainly that trimesh is allowed for static terrain and roads. | 2026-11-14 |
| 4 | G5.2 | Nothing else sits on screen while playing except the speed or status readout, the find counter and touch controls. | Also shows the S-C-E-N-I-C letter row beside the find counter, a lap clock while a lap is running and the surface name under the speed. | Brian asked for the letters and for timed laps. The player needs to see both while driving. | G5.2 is widened to cover progress and lap readouts, or these move into the menu. | Proposed |
| 5 | G8.2 | Extra pictures and sounds come from the Patch.gg library. | 148 item pictures and the scenery models (trees, rocks, bush) come from Brian's own game Keeper of the Hollow. The other 44 pictures come from Patch.gg. | Brian asked for Keeper of the Hollow art to be reused for the first finds. | G8.2 is widened to allow art from Brian's own games, or the pictures are replaced. | Proposed |

A Proposed row is not in force. The standard applies until Brian agrees.

Rows 4 and 5 describe what the game already does today. Under Brian's instructions of 2026-11-14 the game keeps doing it until he decides.

## Open items (rule applies, work not finished)

- G4.6: `BACKLOG.md` has every required section, but the "Now" section is still titled for v0.3.x and needs a refresh.
- G5.4: the title card lists most keys. It does not list Esc for the menu or the controller Back button.
- G6.6: trees, rocks, bushes, railings, cones and boards have collision. Not every small prop was checked.
- G7.8: done in the source and checked in a local browser build on 2026-11-15. Without `?test` the page ignores `?safe` and `?fast` and the test keys do nothing. `?contest` does not switch test mode on. The live v0.5.2 browser build and APK still have the old switches and test keys until the next release ships.
- G10.1: the game reads its browser test switches with the kit's `TestBridge.has_flag`. It does not publish its state through `test_bridge.gd` yet, and its save code does the same job as the kit's `save_store.gd`. Switch on the next release and run the full test gate (Brian, 2026-11-14).
- G10.4: on the next release, pull the newest kit and name its version in the release notes.
- E1.2: dictionaries and some arrays do not name their element types.
- E1.3: the world, the car and the HUD each run an always-on loop. New code follows the rule. Old loops change only if a phone shows lag.
- E1.5: checks that run during play use squared distances. World-building code that runs once at startup still uses `distance_to`.
- E2.3: materials are built at startup. The Christmas theme builds its hat material when it is first switched on.
- E2.4: the glow under each find is see-through. Overdraw is not measured.
- E3.1 and E4.6: triangle, draw call and memory budgets are not measured on a device yet.
- E4.5: collected finds are freed, not pooled.
- E6.3: music is `.ogg` and effects are `.wav`. Bitrates and sample rates are not checked.
- E6.5: the save moments are in place. How long a browser save takes to reach the browser store is not timed on a real phone. The kit notes about half a second at 60 frames a second.

## Rules met

Checked at v0.5.2 against commit e4688a1.

G rules: G0.1 to G0.12, G1.1 to G1.9, G2.1 to G2.6, G3.1 to G3.5, G4.1 to G4.5, G5.1, G5.3, G5.5, G5.6, G5.7, G6.1 to G6.5, G7.1 to G7.5, G8.1, G8.3, G8.4, G10.2, G10.3, G10.5.

E rules: E1.1, E1.2 (declarations), E1.4, E2.1, E2.2, E2.5, E3.2, E4.2, E5.1, E5.2, E5.3, E5.4, E6.1, E6.2, E6.4, E6.5 (saves on pause, focus loss and close), E6.6.

Notes on the checks:

- G0.10: no copy of either standards file is left in this repo.
- G1.7 and G6.3: a test build signed with `tools/common/sign_android.sh` and the key from `game-signing` showed a signature starting with `5db69ffb` (2026-11-14). That test build was not published.
- G1.8: the line under the buttons reads `Version 0.5.2. Release notes · Backlog · Source on GitHub`. `tests/common/page_check.py` checks it after each push.
- G2.5: `tools/common/make_handoff.sh` built a test zip for this game with no key or password in it.
- G1.9: `bash tools/common/check_secrets.sh` prints `SECRETS check ok`. No key, signing settings file or password is in this repo. The APK build reads the key and its settings from a fresh clone of `game-signing`, outside this repo. `.gitignore` blocks `signing.properties` and `game-signing/`.
- G10.3: `bash tools/common/sync_common.sh --check .` prints `COMMON check ok: 1.3.0 e4688a1`.

Proposed rules (not in force, noted for Brian):

- G4.8: does not apply to a game already built.
- G4.9: partly met. Finds are data. Biomes and circuits are code.
- G6.7: this game signs with the key from `game-signing`, as Brian's update of 2026-11-14 says.
- G7.6: this is not a game with rules. The browser tests open `index.html?test` and use wait times. Publishing state through `test_bridge.gd` would fix this (open item G10.1).
- G7.7: done by hand at each release.
- E5.5: this game runs physics at a fixed 60 steps a second.

## Not in use in this game

Characters, skeletons, navigation, ORM textures, lightmaps. Retired rules G4.7, G6.8 and G6.9. G10.6 and G10.7 cover kit code, not game code. G10.8 covers new games.

## How to add an override

1. Flag the conflict to Brian with the options. Do not override by yourself.
2. Add the row as Proposed and list it as a judgment call in the report to Brian.
3. Once he agrees, put the date in the Agreed column.
4. When an override ends, move its row to Ended overrides with the date.
5. When an override fits every game, ask Brian to make it a standard. Then end the override.

## Ended overrides

| # | Rule | What it was | Ended | Why it ended |
|---|---|---|---|---|
| 4 (old) | E6.4 | Browser saves written directly, then synced, with no temp file and rename. Proposed, never agreed. | 2026-11-14 | `ENGINEERING_STANDARDS.md` now says the same for the browser. The game meets E6.4 as written. |
