# The Scenic Route: project rules

The Scenic Route is Brian Clark's calm rally driving game. Godot 4.6, Android and browser. This repo is public.

## Pillars (never break these)

1. No races against opponents. No battles.
2. No way to lose. No damage, no fuel, no timers.
3. Driving through scenery is the reward.
4. A reset always puts the car back on a road with no penalty.

## Rules

- This repo is public. Never commit a signing key, keystore or password. The Android signing key lives in the private repo `keeper-of-the-hollow-source`.
- Original cars, names and art only. Nothing copied from art of rally or any other game.
- The car's front is +Z. Positive `steer_in` turns right.
- `--bot` must show `up_min` near 1.00 on every line (the car never rolls over).
- `--drive` and `--drive --auto` must each finish a lap with `resets 0`.
- `--reach` must print `finds 100, bad 0`. Never rename or remove a find id in `data/finds.json` (saves list found ids).
- Save file is `user://scenic_route.json`, format `v: 1`. Only add fields, each with a safe default.
- Every outside asset goes in `CREDITS.md` with its licence.
- `tests/web_m1.py` must print `errors []`. View the screenshots.
- The browser build lives in `docs/` for GitHub Pages.

## Reporting to Brian

Lead with the link or file to test. Segment the answer. Short active sentences. No em dashes, no semicolons, no Oxford comma. State plainly what was tested and where. List every judgment call.
