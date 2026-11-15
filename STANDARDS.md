# Godot 3D engineering standards (browser and Android)

These rules apply to every Godot 3D game Brian makes for the browser (HTML5, WebGL 2.0) and Android (phones, tablets and handhelds such as the Retroid). Brian supplied them on 2026-11-14.

This file is the same in every game repo. Never edit it for one game. The master copy travels in the game standards handoff zip.

Every script, scene, shader and design choice follows these rules. When a rule does not fit a game, the game's `STANDARDS_OVERRIDES.md` says so. An override names the rule number, what the game does instead and why. Brian approves each override. A rule with no override applies in full. Never skip a rule silently.

Godot version: 4.3 or newer.

## 1. GDScript and code rules

1. Godot 4 syntax only. Never use Godot 3 names (`KinematicBody`, `Spatial`, `yield`, `export`, `onready`, string-based `.connect()`). Use `CharacterBody3D`, `Node3D`, `await`, `@export`, `@onready` and callable signals (`signal_name.connect(_on_callable)`).
2. Static typing everywhere. Type every variable, array (`Array[Node3D]`), dictionary, parameter and return value (`-> void:`).
3. No idle polling. Do not write `_process` or `_physics_process` functions that poll while nothing happens. Sleeping things call `set_process(false)` and `set_physics_process(false)` in `_ready()` and wake on a signal (`Area3D.body_entered`, a timer or `VisibleOnScreenEnabler3D`).
4. Cache node references. Never call `get_node()`, `$Path` or `find_child()` inside `_process`, `_physics_process` or a busy loop. Cache them in `@onready` variables or pass them in with `@export`.
5. Squared distances. In checks that run during play, use `distance_squared_to()` instead of `distance_to()`.

## 2. Rendering and shaders

1. Renderer: `gl_compatibility` (WebGL 2.0 and OpenGL ES 3.0) on both targets. Do not rely on Forward+ features (volumetric fog, SDFGI, SSR, SSAO, SSIL or `GPUParticles3D` compute shaders).
2. Particles: `CPUParticles3D` or animated mesh flipbooks. Never `GPUParticles3D`.
3. No new materials during play. Never call `material.duplicate()` or create a `StandardMaterial3D` or `ShaderMaterial` while the game runs. Build them at load time. For per-object changes (flashes, tints, dissolve, wind sway) use an `instance uniform` and `set_instance_shader_parameter()`.
4. No see-through overdraw. Use opaque geometry where possible, or alpha scissor for foliage and cutouts. Avoid stacked alpha-blended quads.
5. Lights and shadows:
   - One `DirectionalLight3D` casts real-time shadows (orthogonal or PSSM 2 splits, 2048 atlas at most).
   - `shadow_enabled = false` on every `OmniLight3D` and `SpotLight3D`.
   - At most 8 local lights per mesh. Prefer `LightmapGI` or vertex colours for static mood.

## 3. Assets, geometry and draw calls

1. Triangle budgets:
   - Hero or player character: 3,000 to 5,000 triangles. Fewer than 40 bones.
   - Props and NPCs: 150 to 1,500 triangles each.
   - Whole visible scene: under 150,000 triangles and under 300 draw calls per frame.
2. Batching. The renderer does not batch separate `MeshInstance3D` nodes. Any repeated static prop (trees, grass, rocks, fences, coins) uses `MultiMeshInstance3D` or is merged by material.
3. Textures and materials:
   - 1 or 2 materials per mesh.
   - Pack ambient occlusion (R), roughness (G) and metallic (B) into one ORM texture.
   - 2048 x 2048 at most for atlases and terrain. 512 to 1024 for props. VRAM compression (ETC2 and ASTC) and mipmaps on.
4. Culling and level of detail:
   - Set `visibility_range_end` (hard cutoff, fade mode disabled) on every prop. Cull small details at 25 to 45 m.
   - Raise the viewport `mesh_lod_threshold` to 2.5 to 3.5 on browser and Android.
   - Every animated character has a `VisibleOnScreenEnabler3D` so its animation stops off screen. This applies when the game has characters.

## 4. Physics, navigation and memory

1. Physics engine: the default GodotPhysics3D. Avoid Jolt on browser builds.
2. Physics runs at 60 Hz with physics interpolation on (`physics/common/physics_interpolation = true`), so motion is smooth on 90 and 120 Hz screens. Nodes moved every drawn frame (cameras, spinning pickups) turn interpolation off for themselves and read the smoothed transform of what they follow.
3. Primitive colliders only: box, capsule, sphere and cylinder shapes. Never use `ConcavePolygonShape3D` (trimesh) on moving bodies or complex props.
4. Navigation (when the game has it): never call `NavigationAgent3D.set_target_position()` every frame. Stagger path updates with a random 0.25 to 0.5 second timer per agent.
5. Object pooling: do not call `.instantiate()` or `.queue_free()` in active play loops for things that recur (effects, pickups, floating text). Make a pool up front and toggle `visible`, `process_mode` and collision.
6. Memory and loading:
   - Do not `preload()` large scenes, textures or audio in global scripts. Use `ResourceLoader.load_threaded_request()` for scene changes.
   - Runtime VRAM under 250 MB in the browser and under 400 MB on Android. No orphan nodes after a scene unloads.
   - Keyframe compression on for every imported `.glb` animation.

## 5. Display, safe areas and input

1. Stretch mode `canvas_items` and aspect `expand`, so the UI stays crisp.
2. Scale 3D rendering (`Viewport.scaling_3d_scale`) to 0.80 to 0.85 on browser and Android. Cap the frame rate at 60 on mobile.
3. Safe areas. Every HUD root takes its margins from `DisplayServer.get_display_safe_area()` to stay clear of camera notches, rounded corners and gesture bars. Full screen panels still cover the whole screen.
4. Three kinds of input in every game: touch, gamepad and keyboard.
   - Read movement through input actions (`Input.get_vector` or `Input.get_axis`), never raw keys.
   - Hide the on-screen touch controls when a key or gamepad input arrives. Show them again on a screen touch.
   - Every button and touch target is at least 48 x 48 logical pixels.

## 6. Audio, saves and export

1. Browser export: thread support off and audio playback type Sample.
2. Start audio only after the first input from the player.
3. Music and ambient loops are `.ogg` at 96 to 128 kbps. Short sound effects are mono `.wav` at 22.05 to 32 kHz.
4. Saves go to `user://` as JSON or `ConfigFile`. Write to a temp file first, then rename it over the real save. Never use `.tres` or `ResourceSaver` for save data.
5. Save at once on `NOTIFICATION_APPLICATION_PAUSED`, `NOTIFICATION_APPLICATION_FOCUS_OUT` and `NOTIFICATION_WM_CLOSE_REQUEST`. In the browser, write the save file directly and call `JavaScriptBridge.force_fs_sync()` after it, so the save reaches IndexedDB without waiting.
6. Set `quit_on_go_back = false` and handle `NOTIFICATION_WM_GO_BACK_REQUEST`: the Android back button opens or closes the in-game menu.

## Release checklist

Tick these before every release.

- [ ] No Godot 3 syntax. Every declaration typed.
- [ ] No `GPUParticles3D`. No material made during play.
- [ ] Repeated props are in a `MultiMeshInstance3D`.
- [ ] One shadow-casting light.
- [ ] HUD checked with a pretend notch. Touch targets at least 48 px.
- [ ] Touch controls hide on keyboard or gamepad input.
- [ ] Save survives a page reload in the browser.
- [ ] Back button opens the menu on Android.
- [ ] Browser export: threads off.
- [ ] `STANDARDS_OVERRIDES.md` is up to date: every override still needed, every open item still true.
