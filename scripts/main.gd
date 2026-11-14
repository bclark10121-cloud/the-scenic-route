extends Node3D
## The Scenic Route: milestone 1, the car feel test.
## Builds a small test ground in code: rolling grass, a gravel loop, a tarmac road across the middle,
## trees and rocks from the Hollow's scenery models. One car, an angled chase camera, no way to lose.
## Run with "-- --bot" for the handling numbers or "-- --drive" for the road-following check.

const Car := preload("res://scripts/car.gd")
const Hud := preload("res://scripts/hud.gd")

const SIZE := 720.0     # metres across
const CELL := 4.0
const N := 180          # cells per side
const HASH := 16.0
const CAMS := [[82.0, 47.0], [54.0, 42.0], [112.0, 55.0]]   # distance, tilt down in degrees. High and far first, like a diorama

var H := PackedFloat32Array()   # heights, (N+1) x (N+1)
var roads: Array = []
var road_hash := {}
var noise := FastNoiseLite.new()
var noise2 := FastNoiseLite.new()
var car: Car
var cam: Camera3D
var hud: Hud
var sun: DirectionalLight3D
var cam_mode := 0
var cam_yaw := 0.0
var cam_at := Vector3.ZERO
var cam_dist := 82.0
var cam_tilt := 47.0
var started := false
var fast := false
var bot := ""
var flat_surface := -1   # the bot's flat test pad uses one surface everywhere
var resets := 0
var _bt := 0.0
var _bstep := -1
var _blog := {}
var _drive_i := 0
var _drive_far := 0.0
var _drive_dist := 0.0
var _drive_stuck := 0.0

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--bot"):
		bot = "bot"
	if args.has("--drive"):
		bot = "drive"
	fast = args.has("--fast") or bot != ""
	if OS.has_feature("web"):
		var q: Variant = JavaScriptBridge.eval("location.search", true)
		if q is String and q.contains("fast"):
			fast = true
	_setup_input()
	noise.seed = 4
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.0042
	noise.fractal_octaves = 3
	noise2.seed = 19
	noise2.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise2.frequency = 0.011
	if bot == "bot":
		_flat_pad()
	else:
		_roads()
		_heights()
		_terrain()
		_ribbons()
		_scenery()
		_walls()
	_light()
	car = Car.new()
	car.surface_fn = surface_at
	add_child(car)
	cam = Camera3D.new()
	cam.fov = 30.0
	cam.near = 0.6
	cam.far = 800.0
	add_child(cam)
	cam.make_current()
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	layer.add_child(hud)
	hud.start_pressed.connect(_start)
	hud.reset_pressed.connect(reset_car)
	hud.cam_pressed.connect(next_cam)
	hud.preset_pressed.connect(next_preset)
	hud.sound_pressed.connect(_toggle_sound)
	hud.set_preset(Car.PRESETS[car.preset].name)
	_spawn()
	if bot != "":
		hud.hide_title()
		started = true

# ---------- input ----------

func _key(action: String, keys: Array, joy: Array = []) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)
	for b in joy:
		var j := InputEventJoypadButton.new()
		j.button_index = b
		InputMap.action_add_event(action, j)

func _axis(action: String, axis: int, v: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = v
	InputMap.action_add_event(action, e)

func _setup_input() -> void:
	_key("steer_left", [KEY_A, KEY_LEFT], [JOY_BUTTON_DPAD_LEFT]); _axis("steer_left", JOY_AXIS_LEFT_X, -1.0)
	_key("steer_right", [KEY_D, KEY_RIGHT], [JOY_BUTTON_DPAD_RIGHT]); _axis("steer_right", JOY_AXIS_LEFT_X, 1.0)
	_key("gas", [KEY_W, KEY_UP], [JOY_BUTTON_RIGHT_SHOULDER]); _axis("gas", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_key("brake", [KEY_S, KEY_DOWN], [JOY_BUTTON_LEFT_SHOULDER]); _axis("brake", JOY_AXIS_TRIGGER_LEFT, 1.0)
	_key("hand", [KEY_SPACE], [JOY_BUTTON_A])
	_key("reset", [KEY_R], [JOY_BUTTON_Y])
	_key("cam", [KEY_C], [JOY_BUTTON_X])
	_key("preset", [KEY_H], [JOY_BUTTON_BACK])
	_key("start", [KEY_ENTER, KEY_SPACE], [JOY_BUTTON_A, JOY_BUTTON_START])

func _start() -> void:
	started = true
	hud.hide_title()
	car.start_sound()

func _toggle_sound() -> void:
	car.sound_on = not car.sound_on
	hud.set_sound(car.sound_on)

func next_cam() -> void:
	cam_mode = (cam_mode + 1) % CAMS.size()

func next_preset() -> void:
	car.preset = (car.preset + 1) % Car.PRESETS.size()
	hud.set_preset(Car.PRESETS[car.preset].name)

func _unhandled_input(e: InputEvent) -> void:
	if not started:
		if e.is_action_pressed("start"):
			_start()
		return
	if e.is_action_pressed("reset"):
		reset_car()
	elif e.is_action_pressed("cam"):
		next_cam()
	elif e.is_action_pressed("preset"):
		next_preset()

# ---------- roads ----------

func _catmull(c: PackedVector2Array, closed: bool) -> PackedVector2Array:
	var dense := PackedVector2Array()
	var n := c.size()
	var segs := n if closed else n - 1
	for i in segs:
		var p0 := c[(i - 1 + n) % n] if closed else c[maxi(i - 1, 0)]
		var p1 := c[i]
		var p2 := c[(i + 1) % n] if closed else c[mini(i + 1, n - 1)]
		var p3 := c[(i + 2) % n] if closed else c[mini(i + 2, n - 1)]
		for k in 30:
			var t := k / 30.0
			dense.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t))
	if not closed:
		dense.append(c[n - 1])
	# even 2 m steps
	var out := PackedVector2Array([dense[0]])
	var carry := 0.0
	var m := dense.size()
	for i in (m if closed else m - 1):
		var a := dense[i]
		var b := dense[(i + 1) % m]
		var l := a.distance_to(b)
		var d := 2.0 - carry
		while d <= l:
			out.append(a.lerp(b, d / l))
			d += 2.0
		carry = l - (d - 2.0)
	return out

func _base_h(x: float, z: float) -> float:
	var h := noise.get_noise_2d(x, z) * 13.0 + noise2.get_noise_2d(x, z) * 1.6
	var edge := maxf(absf(x), absf(z)) - 300.0
	if edge > 0.0:
		h += edge * edge * 0.012   # hills ring the test ground
	return h

func _add_road(p: PackedVector2Array, hw: float, surf: int, closed: bool) -> Dictionary:
	var n := p.size()
	var h := PackedFloat32Array()
	h.resize(n)
	for i in n:
		h[i] = _base_h(p[i].x, p[i].y)
	for pass_i in 3:   # smooth the height along the road so it rolls instead of bumps
		var h2 := PackedFloat32Array()
		h2.resize(n)
		for i in n:
			var s := 0.0
			var c := 0
			for k in range(-9, 10):
				var j := i + k
				if closed:
					j = (j + n) % n
				elif j < 0 or j >= n:
					continue
				s += h[j]
				c += 1
			h2[i] = s / c
		h = h2
	var r := {"p": p, "h": h, "hw": hw, "surf": surf, "closed": closed}
	roads.append(r)
	return r

func _hash_roads() -> void:
	for ri in roads.size():
		var p: PackedVector2Array = roads[ri].p
		for i in p.size():
			var key := Vector2i(floori(p[i].x / HASH), floori(p[i].y / HASH))
			if not road_hash.has(key):
				road_hash[key] = PackedInt32Array()
			road_hash[key].append(ri * 100000 + i)

func _roads() -> void:
	var ctrl := PackedVector2Array()
	for i in 14:
		var a := i / 14.0 * TAU
		var r := 205.0 + 55.0 * sin(3.0 * a + 0.7) + 30.0 * sin(5.0 * a + 2.1)
		ctrl.append(Vector2(cos(a), sin(a)) * r)
	var loop := _add_road(_catmull(ctrl, true), 3.6, Car.GRAVEL, true)
	var cross_c := PackedVector2Array([ctrl[0], Vector2(120, 28), Vector2(40, -34), Vector2(-45, 26), Vector2(-125, -18), ctrl[7]])
	var cross := _add_road(_catmull(cross_c, false), 4.0, Car.TARMAC, false)
	# the tarmac meets the gravel at the loop's height
	var ch: PackedFloat32Array = cross.h
	var lh: PackedFloat32Array = loop.h
	var lp: PackedVector2Array = loop.p
	var cn := ch.size()
	for end in 2:
		var at: Vector2 = cross.p[0 if end == 0 else cn - 1]
		var best := 0
		for i in lp.size():
			if lp[i].distance_squared_to(at) < lp[best].distance_squared_to(at):
				best = i
		for k in 30:
			var i := k if end == 0 else cn - 1 - k
			ch[i] = lerpf(lh[best], ch[i], smoothstep(4.0, 29.0, float(k)))
	cross.h = ch
	_hash_roads()

## Nearest road sample: [distance, road index, sample index]. Distance is INF when no road is within reach.
func road_near(x: float, z: float) -> Array:
	var best := INF
	var br := -1
	var bi := -1
	var cx := floori(x / HASH)
	var cz := floori(z / HASH)
	var q := Vector2(x, z)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var key := Vector2i(cx + dx, cz + dz)
			if road_hash.has(key):
				for code in road_hash[key]:
					var ri: int = code / 100000
					var i: int = code % 100000
					var d: float = roads[ri].p[i].distance_squared_to(q)
					# tarmac wins where the two roads meet
					if d < best:
						best = d; br = ri; bi = i
	return [sqrt(best), br, bi]

func surface_at(x: float, z: float) -> int:
	if flat_surface >= 0:
		return flat_surface
	var best := Car.GRASS
	var cx := floori(x / HASH)
	var cz := floori(z / HASH)
	var q := Vector2(x, z)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var key := Vector2i(cx + dx, cz + dz)
			if road_hash.has(key):
				for code in road_hash[key]:
					var r: Dictionary = roads[code / 100000]
					if r.surf < best and r.p[code % 100000].distance_squared_to(q) < r.hw * r.hw:
						best = r.surf
	return best

# ---------- ground ----------

func _heights() -> void:
	H.resize((N + 1) * (N + 1))
	for iz in N + 1:
		for ix in N + 1:
			var x := (ix - N / 2.0) * CELL
			var z := (iz - N / 2.0) * CELL
			var h := _base_h(x, z)
			var rn := road_near(x, z)
			if rn[1] >= 0:
				var r: Dictionary = roads[rn[1]]
				h = lerpf(r.h[rn[2]], h, smoothstep(r.hw + 1.5, r.hw + 12.0, rn[0]))
			H[iz * (N + 1) + ix] = h

func height_at(x: float, z: float) -> float:
	if H.is_empty():
		return 0.0
	var gx := clampf(x / CELL + N / 2.0, 0.0, N - 0.001)
	var gz := clampf(z / CELL + N / 2.0, 0.0, N - 0.001)
	var ix := int(gx)
	var iz := int(gz)
	var fx := gx - ix
	var fz := gz - iz
	var h00 := H[iz * (N + 1) + ix]
	var h10 := H[iz * (N + 1) + ix + 1]
	var h01 := H[(iz + 1) * (N + 1) + ix]
	var h11 := H[(iz + 1) * (N + 1) + ix + 1]
	if fx + fz <= 1.0:
		return h00 + (h10 - h00) * fx + (h01 - h00) * fz
	return h11 + (h01 - h11) * (1.0 - fx) + (h10 - h11) * (1.0 - fz)

func _ground_col(x: float, z: float, slope: float, jit: float) -> Color:
	var a := noise2.get_noise_2d(x * 0.4 + 300.0, z * 0.4) * 0.5 + 0.5
	var b := noise.get_noise_2d(x * 1.7 - 500.0, z * 1.7) * 0.5 + 0.5
	var c := Color("7dab58").lerp(Color("98be62"), a).lerp(Color("b9c06e"), b * 0.55)
	c = c.lerp(Color("9c917b"), smoothstep(0.42, 0.75, slope))
	var rn := road_near(x, z)
	if rn[1] >= 0:
		var hw: float = roads[rn[1]].hw
		c = c.lerp(Color("b59a72"), 1.0 - smoothstep(hw - 0.5, hw + 4.5, rn[0]))
	return c.lightened(jit) if jit > 0.0 else c.darkened(-jit)

func _terrain() -> void:
	var count := N * N * 6
	var verts := PackedVector3Array(); verts.resize(count)
	var norms := PackedVector3Array(); norms.resize(count)
	var cols := PackedColorArray(); cols.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var k := 0
	for iz in N:
		for ix in N:
			var x0 := (ix - N / 2.0) * CELL
			var z0 := (iz - N / 2.0) * CELL
			var p00 := Vector3(x0, H[iz * (N + 1) + ix], z0)
			var p10 := Vector3(x0 + CELL, H[iz * (N + 1) + ix + 1], z0)
			var p01 := Vector3(x0, H[(iz + 1) * (N + 1) + ix], z0 + CELL)
			var p11 := Vector3(x0 + CELL, H[(iz + 1) * (N + 1) + ix + 1], z0 + CELL)
			for tri in [[p00, p10, p01], [p10, p11, p01]]:
				var n: Vector3 = -(tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
				var mid: Vector3 = (tri[0] + tri[1] + tri[2]) / 3.0
				var col := _ground_col(mid.x, mid.z, 1.0 - n.y * n.y, rng.randf_range(-0.035, 0.035))
				for p in tri:
					verts[k] = p; norms[k] = n; cols[k] = col
					k += 1
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(verts)
	cs.shape = shape
	body.add_child(cs)
	add_child(body)

func _ribbons() -> void:
	for ri in roads.size():
		var r: Dictionary = roads[ri]
		var p: PackedVector2Array = r.p
		var n := p.size()
		var hw: float = r.hw
		var lift := 0.07 if r.surf == Car.TARMAC else 0.04
		var mid_c := Color("d6b98e") if r.surf == Car.GRAVEL else Color("626a76")
		var edge_c := Color("bfa079") if r.surf == Car.GRAVEL else Color("535a65")
		var offs := [-1.0, -0.55, 0.0, 0.55, 1.0]
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var rows := n + 1 if r.closed else n
		for i in rows:
			var a := p[i % n]
			var nx := p[(i + 1) % n] if (r.closed or i < n - 1) else a
			var pv := p[(i - 1 + n) % n] if (r.closed or i > 0) else a
			var tan := (nx - pv).normalized()
			var side := Vector2(-tan.y, tan.x)
			for j in 5:
				var q: Vector2 = a + side * hw * offs[j]
				st.set_normal(Vector3.UP)
				var shade := 0.03 * sin(i * 0.9 + j * 2.1)
				st.set_color((edge_c if (j == 0 or j == 4) else mid_c).lightened(maxf(shade, 0.0)).darkened(maxf(-shade, 0.0)))
				st.add_vertex(Vector3(q.x, height_at(q.x, q.y) + lift, q.y))
		for i in rows - 1:
			for j in 4:
				var a0 := i * 5 + j
				var b0 := (i + 1) * 5 + j
				for idx in [a0, a0 + 1, b0, a0 + 1, b0 + 1, b0]:
					st.add_index(idx)
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 1.0
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)

func _flat_pad() -> void:
	flat_surface = Car.TARMAC
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(6000, 1, 6000)
	cs.shape = b
	cs.position.y = -0.5
	body.add_child(cs)
	add_child(body)

func _walls() -> void:
	var body := StaticBody3D.new()
	for i in 4:
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3(SIZE, 200, 2) if i < 2 else Vector3(2, 200, SIZE)
		cs.shape = b
		var e := SIZE / 2.0 - 6.0
		cs.position = [Vector3(0, 50, -e), Vector3(0, 50, e), Vector3(-e, 50, 0), Vector3(e, 50, 0)][i]
		body.add_child(cs)
	add_child(body)

# ---------- scenery (models reused from Keeper of the Hollow) ----------

func _scenery_mesh(n: String) -> Mesh:
	var path := "res://models/%s.glb" % n
	if not ResourceLoader.exists(path):
		return null
	var sc: Node = load(path).instantiate()
	var found := sc.find_children("*", "MeshInstance3D", true, false)
	var mesh: Mesh = found[0].mesh if found.size() > 0 else null
	sc.free()
	return mesh

func _scenery() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	var kinds := {"tree_pine": [], "tree_leafy": [], "tree_autumn_gold": [], "rock": [], "bush": []}
	var solids := StaticBody3D.new()
	add_child(solids)
	var trunk := CylinderShape3D.new()
	trunk.radius = 0.38
	trunk.height = 5.0
	var spawn: Vector2 = roads[1].p[roads[1].p.size() / 2]
	for i in 5200:
		var x := rng.randf_range(-345.0, 345.0)
		var z := rng.randf_range(-345.0, 345.0)
		var wood := noise2.get_noise_2d(x * 0.35 + 900.0, z * 0.35 - 200.0)
		var roll := rng.randf()
		var rn := road_near(x, z)
		var rd: float = rn[0] - (roads[rn[1]].hw if rn[1] >= 0 else 0.0)
		if rd < 4.5 or Vector2(x, z).distance_to(spawn) < 14.0:
			continue
		var y := height_at(x, z)
		var yaw := rng.randf() * TAU
		if roll < 0.06:
			var s := rng.randf_range(0.8, 2.4)
			kinds["rock"].append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s * 1.3, s, s * 1.3)), Vector3(x, y - 0.12 * s, z)))
			var cs := CollisionShape3D.new()
			var sp := SphereShape3D.new()
			sp.radius = s * 0.55
			cs.shape = sp
			cs.position = Vector3(x, y + s * 0.2, z)
			solids.add_child(cs)
		elif roll < 0.2:
			if wood > -0.25:
				var s2 := rng.randf_range(0.9, 1.7)
				kinds["bush"].append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s2 * 1.4, s2, s2 * 1.4)), Vector3(x, y - 0.05, z)))
		elif wood > 0.08 or (rd < 16.0 and roll > 0.9):
			var kind := "tree_pine" if (y > 3.0 or wood > 0.42) else "tree_leafy"
			if rng.randf() < 0.14:
				kind = "tree_autumn_gold"
			var s3 := rng.randf_range(6.5, 10.5) if kind == "tree_pine" else rng.randf_range(5.5, 8.5)
			kinds[kind].append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s3, s3, s3)), Vector3(x, y - 0.15, z)))
			var cs2 := CollisionShape3D.new()
			cs2.shape = trunk
			cs2.position = Vector3(x, y + 2.3, z)
			solids.add_child(cs2)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	for kname in kinds:
		var list: Array = kinds[kname]
		var mesh := _scenery_mesh(kname)
		if mesh == null or list.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		if kname == "bush" or fast:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)

func _light() -> void:
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -52, 0)
	sun.light_color = Color("fff0d2")
	sun.light_energy = 0.66
	sun.shadow_enabled = not fast
	sun.directional_shadow_max_distance = 280.0
	sun.shadow_bias = 0.06
	add_child(sun)
	if fast:
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("d5e6ea")
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.04
	env.adjustment_saturation = 0.96
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b9c8d6")
	env.ambient_light_energy = 0.46
	env.fog_enabled = true
	env.fog_light_color = Color("d9e7e6")
	env.fog_density = 0.0007
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

# ---------- car placing ----------

func _spawn() -> void:
	if roads.is_empty():
		car.place(Vector3(0, 0.3, 0), 0.0)
	else:
		_place_on_road(1, roads[1].p.size() / 2)
	cam_yaw = car.rotation.y
	cam_at = car.global_position

func _place_on_road(ri: int, i: int) -> void:
	var r: Dictionary = roads[ri]
	var p: PackedVector2Array = r.p
	var n := p.size()
	var a := p[i]
	var b := p[(i + 1) % n] if (r.closed or i < n - 1) else a + (a - p[i - 1])
	var dir := (b - a).normalized()
	# keep the nose pointing the way the car was already facing along the road
	var f := car.global_transform.basis.z
	if Vector2(f.x, f.z).dot(dir) < 0.0 and resets > 0:
		dir = -dir
	car.place(Vector3(a.x, height_at(a.x, a.y) + 0.25, a.y), atan2(dir.x, dir.y))

## Back on the nearest road, level and still. Never a penalty.
func reset_car() -> void:
	resets += 1
	if roads.is_empty():
		car.place(Vector3(0, 0.3, 0), 0.0)
		return
	var pos := car.global_position
	var best := INF
	var br := 0
	var bi := 0
	for ri in roads.size():
		var p: PackedVector2Array = roads[ri].p
		for i in p.size():
			var d := p[i].distance_squared_to(Vector2(pos.x, pos.z))
			if d < best:
				best = d; br = ri; bi = i
	_place_on_road(br, bi)

# ---------- every frame ----------

func _physics_process(dt: float) -> void:
	if bot == "bot":
		_bot(dt)
	elif bot == "drive":
		_drive(dt)
	elif started:
		var steer := Input.get_axis("steer_left", "steer_right")
		var gas := Input.get_action_strength("gas")
		var brake := Input.get_action_strength("brake")
		var hand := Input.is_action_pressed("hand")
		if hud.touch_on:
			steer = clampf(steer + hud.touch_steer, -1.0, 1.0)
			gas = maxf(gas, hud.touch_gas)
			brake = maxf(brake, hud.touch_brake)
			hand = hand or hud.touch_hand
		car.steer_in = steer
		car.gas_in = gas
		car.brake_in = brake
		car.hand_in = hand
	if car.wants_reset or car.global_position.y < -80.0:
		reset_car()

func _process(dt: float) -> void:
	var b := car.global_transform.basis
	var heading := atan2(b.z.x, b.z.z)
	var v := car.linear_velocity
	if car.speed > 7.0 and car.fwd_speed > 2.0:
		heading = lerp_angle(heading, atan2(v.x, v.z), 0.45)
	var back := car.fwd_speed < -1.5
	if not back:
		cam_yaw = lerp_angle(cam_yaw, heading, 1.0 - exp(-dt * 1.5))
	cam_dist = lerpf(cam_dist, CAMS[cam_mode][0], 1.0 - exp(-dt * 4.0))
	cam_tilt = lerpf(cam_tilt, CAMS[cam_mode][1], 1.0 - exp(-dt * 4.0))
	var f := Vector3(sin(cam_yaw), 0, cos(cam_yaw))
	var want := car.global_position + f * (7.0 + car.speed * 0.4)
	cam_at = cam_at.lerp(want, 1.0 - exp(-dt * 5.0))
	var tilt := deg_to_rad(cam_tilt)
	var pos := cam_at - f * cam_dist * cos(tilt) + Vector3.UP * cam_dist * sin(tilt)
	pos.y = maxf(pos.y, height_at(pos.x, pos.z) + 2.5)
	cam.global_position = pos
	cam.look_at(cam_at + Vector3.UP * 0.6)
	hud.set_speed(car.speed * 2.23694, Car.SURF_NAME[car.surface])

# ---------- test drivers ----------

func _bot(dt: float) -> void:
	# one pass per surface and handling choice on a flat pad: speed up, brake, turn, handbrake turn
	var runs := Car.SURF.size() * Car.PRESETS.size()
	if _bstep < 0:
		_bstep = 0; _bt = 0.0; _blog = {}
	var run := _bstep
	if run >= runs:
		print("BOT done")
		get_tree().quit()
		return
	flat_surface = run / Car.PRESETS.size()
	car.preset = run % Car.PRESETS.size()
	if _bt == 0.0:
		car.place(Vector3(0, 0.3, 0), 0.0)
		_blog = {"t60": -1.0, "top": 0.0, "stop_from": 0.0, "stop_x": 0.0, "stop_d": -1.0, "yaw": 0.0, "side": 0.0, "up_min": 1.0, "slide": 0.0, "hb_yaw": 0.0, "r": 0.0, "g": 0.0, "tv": 0.0}
	_bt += dt
	var t := _bt
	var up := car.global_transform.basis.y.y
	_blog.up_min = minf(_blog.up_min, up)
	car.steer_in = 0.0; car.gas_in = 0.0; car.brake_in = 0.0; car.hand_in = false
	if t < 14.0:   # full gas
		car.gas_in = 1.0
		_blog.top = maxf(_blog.top, car.speed)
		if _blog.t60 < 0.0 and car.speed >= 26.82:
			_blog.t60 = t
		_blog.stop_from = car.speed
		_blog.stop_x = car.global_position.z
	elif t < 22.0:   # full brake
		if car.fwd_speed > 1.0:
			car.brake_in = 1.0
		elif _blog.stop_d < 0.0:
			_blog.stop_d = car.global_position.z - _blog.stop_x
	elif t < 26.0:   # up to a steady 17 m/s
		car.gas_in = 1.0 if car.speed < 17.0 else 0.0
	elif t < 31.0:   # hard right turn at part gas
		car.steer_in = 1.0
		car.gas_in = 0.55 if car.speed < 17.0 else 0.0
		if t > 28.0:
			var yr := car.angular_velocity.y
			_blog.yaw = yr
			_blog.side = car.global_position.x
			_blog.slide = maxf(_blog.slide, car.slide)
			_blog.r = car.speed / maxf(absf(yr), 0.001)
			_blog.g = car.speed * absf(yr) / 9.8
			_blog.tv = car.speed
	elif t < 35.0:
		car.gas_in = 1.0 if car.speed < 17.0 else 0.0
		_blog.hb0 = car.rotation.y
	elif t < 36.6:   # handbrake turn
		car.steer_in = 1.0
		car.hand_in = true
		_blog.hb_yaw = absf(angle_difference(_blog.hb0, car.rotation.y))
	else:
		print("BOT %s %s: 0-60 %.1fs top %.0f mph, stop from %.0f mph in %.0f m, turn radius %.0f m at %.0f mph (%.2f g) yaw %.2f slide %.2f side %.0f, handbrake %.0f deg, up_min %.2f" % [
			Car.SURF_NAME[flat_surface], Car.PRESETS[car.preset].name, _blog.t60, _blog.top * 2.237, _blog.stop_from * 2.237, _blog.stop_d,
			_blog.r, _blog.tv * 2.237, _blog.g, _blog.yaw, _blog.slide, _blog.side, rad_to_deg(_blog.hb_yaw), _blog.up_min])
		_bstep += 1
		_bt = 0.0

func _drive(dt: float) -> void:
	# follows the gravel loop, then the tarmac, to prove the roads drive cleanly
	_bt += dt
	var r: Dictionary = roads[0]
	var p: PackedVector2Array = r.p
	var n := p.size()
	var pos := Vector2(car.global_position.x, car.global_position.z)
	if _bstep < 0:
		_bstep = 0
		_drive_i = 0
		_place_on_road(0, 0)
		return
	# nearest sample ahead
	for k in 40:
		var j := (_drive_i + 1) % n
		if p[j].distance_squared_to(pos) < p[_drive_i].distance_squared_to(pos):
			_drive_i = j
			_drive_dist += 2.0
		else:
			break
	var look := 6 + int(car.speed * 0.45)
	var aim := p[(_drive_i + look) % n]
	var f := car.global_transform.basis.z
	var to := (aim - pos).normalized()
	var cross := f.x * to.y - f.z * to.x   # positive when the aim point is to the right
	var ang := atan2(Vector2(f.x, f.z).cross(to), Vector2(f.x, f.z).dot(to))
	car.steer_in = clampf(ang * 2.2, -1.0, 1.0)
	var far_aim := p[(_drive_i + look * 3) % n]
	var bend := absf(angle_difference(atan2(to.x, to.y), atan2((far_aim - aim).x, (far_aim - aim).y)))
	var target := clampf(27.0 - bend * 22.0, 11.0, 27.0)
	car.gas_in = 1.0 if car.speed < target else 0.0
	car.brake_in = 1.0 if car.speed > target + 4.0 else 0.0
	car.hand_in = false
	_drive_far = maxf(_drive_far, p[_drive_i].distance_to(pos))
	if car.speed < 1.0 and _bt > 3.0:
		_drive_stuck += dt
		if _drive_stuck > 3.0:
			reset_car()
			_drive_stuck = 0.0
	else:
		_drive_stuck = 0.0
	if _drive_dist >= n * 2.0 or _bt > 240.0:
		print("DRIVE lap %.0f m of %.0f m in %.0f s, average %.0f mph, farthest from road centre %.1f m, resets %d, cross %.2f" % [
			_drive_dist, n * 2.0, _bt, _drive_dist / _bt * 2.237, _drive_far, resets, cross])
		get_tree().quit()
