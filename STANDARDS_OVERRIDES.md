# Standards overrides: The Scenic Route

`STANDARDS.md` holds the Godot 3D engineering standards for all of Brian's games. This file lists where The Scenic Route does something different, and why. A rule not listed here applies in full. Brian approves each override.

Last reviewed: v0.5.2 (2026-11-14).

## Overrides

| Rule | Standard says | This game does | Why | Approved |
|---|---|---|---|---|
| 4.1 Physics engine | Default GodotPhysics3D. Avoid Jolt on browser builds. | Jolt Physics, the engine built into Godot 4.6. No add-on. | The car, every ramp and every jump are tuned on it. It passes every browser test. A switch means retuning all of it. | Brian, 2026-11-14 |
| 3.4 Cull distance | Cull small details at 25 to 45 m. | No cull distance yet. Any future one sits beyond the camera distance. | The camera is 82 to 112 m from the car. A 25 to 45 m cutoff would hide every tree on screen. | Brian, 2026-11-14 |
| 4.3 Colliders | Primitive shapes only. No trimesh on moving bodies or complex props. | Trimesh for the static terrain and the road beds only. Everything else uses primitive shapes. | Hills and roads are not a box or a sphere. The rule targets moving bodies and props, and these are neither. | Brian, 2026-11-14 |
| 6.4 Temp file saves | Write a temp file, then rename it. | Android: as written. Browser: write the save directly, then ask for a sync. | In the browser a renamed file is not copied to IndexedDB reliably. IndexedDB swaps a file in whole by itself. | Proposed in v0.5.2 |

## Open items (rule applies, work not finished)

- 1.2: dictionaries and some arrays do not name their element types.
- 1.3: the world, the car and the HUD each run an always-on loop. New code follows the rule. Old loops change only if a phone shows lag.
- 1.5: checks that run during play use squared distances. World-building code that runs once at startup still uses `distance_to`.
- 2.3: materials are built at startup. The Christmas theme builds its hat material when it is first switched on.
- 2.4: the glow under each find is see-through. Overdraw is not measured.
- 3.1 and 4.6: triangle, draw call and memory budgets are not measured on a device yet.
- 4.5: collected finds are freed, not pooled.
- 6.3: music is `.ogg` and effects are `.wav`. Bitrates and sample rates are not checked.
- 6.5: in the test browser a second save took about 10 seconds to reach IndexedDB. A tab closed sooner than that loses the newest change. Not yet timed on a real phone.

## Rules met

1.1, 1.2 (declarations), 1.4, 2.1, 2.2, 2.5, 3.2, 4.2, 5.1, 5.2, 5.3, 5.4, 6.1, 6.2, 6.5 (pause, focus and close saves), 6.6.

## Not in use in this game

Characters, skeletons, navigation, ORM textures, lightmaps.
