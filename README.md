# The Scenic Route

A calm rally driving game. No races, no timers, no damage. Drive anywhere.

Built in Godot 4.6 for Android and the browser.

## Status

Milestone 1: car feel test. One car, a small test ground, three handling choices.

Play in the browser: https://bclark10121-cloud.github.io/the-scenic-route/

## Layout

- `project.godot`, `main.tscn`: the Godot project. Compatibility renderer and Jolt physics.
- `scripts/car.gd`: the car. Handling, body, dust and engine sound, all made in code.
- `scripts/main.gd`: test ground, roads, scenery, camera and the two test drivers.
- `scripts/hud.gd`: speed readout, buttons, title card and touch controls.
- `models/`: low-poly trees, rock and bush reused from Keeper of the Hollow.
- `tests/web_m1.py`: browser check with screenshots.
- `docs/`: the browser build served by GitHub Pages.
- `BACKLOG.md`: the backlog.

## Build and test

    godot --headless --path . --import
    godot --headless --fixed-fps 60 --path . -- --bot      # handling numbers on a flat pad
    godot --headless --fixed-fps 60 --path . -- --drive    # drives one lap of the gravel loop
    godot --headless --path . --export-release "Web" ../scenic-out/web/index.html
    python3 tests/web_m1.py ../scenic-out/web ../scenic-out/shots

To publish: copy the web build into `docs/`. Settings > Pages > Deploy from a branch > main, folder /docs.
