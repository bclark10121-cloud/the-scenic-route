# The Scenic Route

A calm rally driving game. No races, no timers, no damage. Drive anywhere.

Built in Godot 4.6 for Android and the browser.

## Standards

This game follows Brian's shared standards, kept in the private repo `bclark10121-cloud/game-standards`: `GAME_STANDARDS.md` (G rules) and `ENGINEERING_STANDARDS.md` (E rules). This repo holds no copies. `STANDARDS_OVERRIDES.md` lists where this game differs, why, and which standards version it was checked against.

Shared code from that repo's kit lives in `addons/bc_common/`, `tools/common/` and `tests/common/`. `common.lock` pins its version. Never edit those files here.

## Status

v0.5.2: six biomes, 198 things to find, ramps, broken bridges to jump, lap circuits, achievements, a Christmas theme, music and auto drive.

Game page (play in the browser or download the Android APK): https://bclark10121-cloud.github.io/the-scenic-route/

## Layout

- `project.godot`, `main.tscn`: the Godot project. Compatibility renderer and Jolt physics.
- `scripts/car.gd`: the car. Handling, body, dust and engine sound, all made in code.
- `scripts/main.gd`: biomes, ground, water, roads, scenery, finds, save, camera and the test drivers.
- `scripts/hud.gd`: speed readout, buttons, letters, messages, journal, title card and touch controls.
- `audio/`: music (see CREDITS.md) and chimes made by `tools/make_chimes.py`.
- `icons/`, `data/finds.json`: the 94 keepsakes, reused from Keeper of the Hollow.
- `models/`: low-poly trees, rock and bush reused from Keeper of the Hollow.
- `tests/web_m1.py`, `tests/web_std.py`, `tests/web_dress.py`: browser checks with screenshots. They use the kit's `tests/common/webkit.py`.
- `tools/common/`, `tests/common/`, `addons/bc_common/`: the shared kit (see Standards).
- `docs/`: the GitHub Pages site. Landing page at the root, the game in `docs/play/`, APKs in `docs/downloads/`.
- `BACKLOG.md`: the backlog.

## Build and test

    godot --headless --path . --import
    godot --headless --fixed-fps 60 --path . -- --bot      # handling numbers on a flat pad
    godot --headless --fixed-fps 60 --path . -- --drive    # drives one lap of the main loop (add --auto for auto drive)
    godot --headless --fixed-fps 60 --path . -- --reach    # finds report: 198 finds, bad 0
    godot --headless --fixed-fps 60 --path . -- --drive --track0   # a timed lap on a circuit (track0 to track5)
    godot --headless --fixed-fps 60 --path . -- --jump     # drives every ramp
    godot --headless --path . --export-release "Web" ../scenic-out/web/index.html
    python3 tests/web_m1.py ../scenic-out/web ../scenic-out/shots

    bash tools/common/sync_common.sh --check .              # the shared kit is unedited
    bash tools/common/check_secrets.sh                       # no key or password in the repo
    APKSIGNER=<path to apksigner> tools/common/sign_android.sh ../scenic-out/TheScenicRoute.apk   # needs ../game-signing (private)
    python3 tests/common/page_check.py https://bclark10121-cloud.github.io/the-scenic-route/      # after a push

To publish: copy the web build into `docs/play/` and the APK into `docs/downloads/`. Settings > Pages > Deploy from a branch > main, folder /docs.
