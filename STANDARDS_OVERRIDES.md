# The Scenic Route: standards overrides

Standards: `handoff/GAME_STANDARDS.md` (rule ids start with G) and `handoff/ENGINEERING_STANDARDS.md` (rule ids start with E).
This file lists where this game does something else, and why. A rule not listed here applies in full.
Order of authority: Brian in the chat, then this file, then the standards.

Last reviewed: v0.5.2 (2026-11-14).

Note on E rule ids: the updated `handoff/ENGINEERING_STANDARDS.md` has not arrived yet. Until it does, E ids in this file point at the engineering file this repo holds today, `STANDARDS.md` at the repo root (E4.1 is its section 4, rule 1). Check every E id again when the updated file arrives.

## Overrides

| # | Rule | Standard says | This game does | Why | Ends when | Agreed |
|---|---|---|---|---|---|---|
| 1 | E4.1 | Physics engine: the default GodotPhysics3D. Avoid Jolt on browser builds. | Jolt Physics, the engine built into Godot 4.6. No add-on. | The car, every ramp and every jump are tuned on it. It passes every browser test. A switch means retuning all of it. | The updated engineering standards let each game choose its engine (G6.1 already says so), or the car is retuned on the default engine. | 2026-11-14 |
| 2 | E3.4 | Set a cull distance on every prop. Cull small details at 25 to 45 m. | No cull distance on props. | The camera sits 82 to 112 m from the car. A 25 to 45 m cutoff would hide every tree on screen. | The standard sets the cull distance from each game's camera distance, or a far cutoff is tuned on a phone. | 2026-11-14 |
| 3 | E4.3 | Primitive colliders only. Never trimesh on moving bodies or complex props. | Trimesh for the static terrain and the road beds only. Everything else uses primitive shapes. | Hills and roads are not a box or a sphere. They are static ground, not moving bodies or props. | The standard says plainly that trimesh is allowed for static terrain and roads. | 2026-11-14 |
| 4 | E6.4 | Write the save to a temp file, then rename it over the real save. | Android: as the standard says. Browser: write the save file directly, then ask the browser store for a sync. | In the test browser a renamed save did not reach the browser store. The browser store swaps a file in whole by itself. | The standard covers browser saves, or a rename is shown to reach the browser store. | Proposed |
| 5 | G5.2 | Nothing else sits on screen while playing except the speed or status readout, the find counter and touch controls. | Also shows the S-C-E-N-I-C letter row beside the find counter, a lap clock while a lap is running and the surface name under the speed. | Brian asked for the letters and for timed laps. The player needs to see both while driving. | G5.2 is widened to cover progress and lap readouts, or these move into the menu. | Proposed |
| 6 | G8.2 | Extra pictures and sounds come from the Patch.gg library. | 148 item pictures and the scenery models (trees, rocks, bush) come from Brian's own game Keeper of the Hollow. The other 44 pictures come from Patch.gg. | Brian asked for Keeper of the Hollow art to be reused for the first finds. | G8.2 is widened to allow art from Brian's own games, or the pictures are replaced. | Proposed |

A Proposed row is not in force. The standard applies until Brian agrees.

Rows 4, 5 and 6 describe what the game already does today. Under Brian's instructions of 2026-11-14 the game keeps doing it until he decides.

## Open items (rule applies, work not finished)

- G0.1 and G2.5: `handoff/ENGINEERING_STANDARDS.md` is not in the repo or the handoff zip yet. Brian is sending it. The engineering file here is still `STANDARDS.md` at the repo root.
- G4.6: `BACKLOG.md` has every required section, but the "Now" section is still titled for v0.3.x and needs a refresh.
- G5.4: the title card lists most keys. It does not list Esc for the menu or the controller Back button.
- G6.6: trees, rocks, bushes, railings, cones and boards have collision. Not every small prop was checked.
- E1.2: dictionaries and some arrays do not name their element types.
- E1.3: the world, the car and the HUD each run an always-on loop. New code follows the rule. Old loops change only if a phone shows lag.
- E1.5: checks that run during play use squared distances. World-building code that runs once at startup still uses `distance_to`.
- E2.3: materials are built at startup. The Christmas theme builds its hat material when it is first switched on.
- E2.4: the glow under each find is see-through. Overdraw is not measured.
- E3.1 and E4.6: triangle, draw call and memory budgets are not measured on a device yet.
- E4.5: collected finds are freed, not pooled.
- E6.3: music is `.ogg` and effects are `.wav`. Bitrates and sample rates are not checked.
- E6.5: in the test browser a second save took about 10 seconds to reach the browser store. A tab closed sooner loses the newest change. Not yet timed on a real phone.

## Rules met

Checked at v0.5.2.

G rules: G1.1, G1.2, G1.3, G1.4, G1.5, G1.6, G2.1, G2.2, G2.3, G2.4, G2.6, G3.1 to G3.5, G4.1, G4.2, G4.3, G4.4, G4.5, G5.1, G5.3, G5.5, G5.6, G5.7, G6.1, G6.2, G6.3, G6.4, G6.5, G7.1, G7.2, G7.3, G7.4, G7.5, G8.1, G8.3, G8.4.

E rules: E1.1, E1.2 (declarations), E1.4, E2.1, E2.2, E2.5, E3.2, E4.2, E5.1, E5.2, E5.3, E5.4, E6.1, E6.2, E6.5 (saves on pause, focus loss and close), E6.6.

Proposed rules (not in force, noted for Brian): G4.8 does not apply to a game already built. G4.9 is partly met: finds are data, biomes and circuits are code. G6.7 would change how this game is signed: today each release signs with Brian's key from the private repo, as G6.3 and this game's `CLAUDE.md` say. G7.6: this is not a game with rules, and the browser test uses wait times. G7.7 is done by hand at each release.

## Not in use in this game

Characters, skeletons, navigation, ORM textures, lightmaps. Retired rules G4.7, G6.8 and G6.9.

## How to add an override

1. Flag the conflict to Brian with the options. Do not override by yourself.
2. Add the row as Proposed and list it as a judgment call in the report to Brian.
3. Once he agrees, put the date in the Agreed column.
4. When an override ends, move its row to Ended overrides with the date.
5. When an override fits every game, ask Brian to make it a standard. Then end the override.

## Ended overrides

None yet.
