#!/bin/bash
# Builds the game standards handoff zip from this repo. Run from the repo root: tools/make_handoff.sh [output folder]
# Never include a signing key or password.
set -e
OUT="${1:-..}"
S=$(mktemp -d)
D="$S/Game_Standards_handoff"
mkdir -p "$D/templates/godot" "$D/templates/game-page" "$D/reusable" "$D/games/the-scenic-route"
cp handoff/GAME_STANDARDS.md "$D/"
# the engineering standards: the master copy, the same for every game, and this game's overrides for reference
cp STANDARDS.md "$D/STANDARDS.md"
cp STANDARDS.md STANDARDS_OVERRIDES.md "$D/games/the-scenic-route/"
cp tests/web_std.py "$D/reusable/web_standards_test.py"
cp handoff/templates/* "$D/templates/"
cp project.godot export_presets.cfg .gitignore "$D/templates/godot/"
cp docs/index.html "$D/templates/game-page/index.html"
cp CREDITS.md "$D/templates/CREDITS.md"
cp scripts/hud.gd "$D/reusable/hud.gd"
cp tests/web_m1.py "$D/reusable/web_test.py"
cp tools/make_sfx.py tools/patch_assets.py tools/make_handoff.sh "$D/reusable/"
cp CLAUDE.md BACKLOG.md README.md CREDITS.md data/finds.json "$D/games/the-scenic-route/"
cp docs/release-notes/*.md "$D/games/the-scenic-route/" 2>/dev/null || true
(cd "$S" && zip -qr handoff.zip Game_Standards_handoff)
cp "$S/handoff.zip" "$OUT/Game_Standards_handoff.zip"
echo "built $OUT/Game_Standards_handoff.zip"
