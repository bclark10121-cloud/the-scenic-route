extends Node3D
## The Scenic Route: a calm rally drive across three biomes with 100 things to find.
## The whole world is built in code at start-up: ground, water, roads, scenery and finds.
## Run with "-- --bot" for handling numbers, "-- --drive" for a lap of the main loop
## (add "--auto" to let auto drive work the pedals) and "-- --reach" for the finds report.

const Car := preload("res://scripts/car.gd")
const Hud := preload("res://scripts/hud.gd")

const SIZE := 1320.0    # metres across
const CELL := 6.0
const N := 220          # cells per side
const HASH := 16.0
const WATER := -3.2     # lake level
const CHUNK := 220.0    # scenery is grouped in squares this size so far-off trees are skipped
const CAMS := [[82.0, 47.0], [54.0, 42.0], [112.0, 55.0]]   # distance, tilt down in degrees. High and far first, like a diorama
const SAVE := "user://scenic_route.json"
const LETTERS := "SCENIC"
const BIOME := [
	{"name": "Pine Lakes", "music": "pine_lakes", "g1": Color("4f9150"), "g2": Color("6ea858"), "dry": Color("86b062"), "shoulder": Color("b39a72"),
		"bg": Color("cfe3e6"), "fog": Color("d6e6e2"), "amb": Color("b6c8d4"), "road": Car.GRAVEL},
	{"name": "Golden Hills", "music": "golden_hills", "g1": Color("cdbd68"), "g2": Color("dbc878"), "dry": Color("e3c670"), "shoulder": Color("cfae7c"),
		"bg": Color("f1e2bd"), "fog": Color("f0e4c6"), "amb": Color("d6ccb4"), "road": Car.TARMAC},
	{"name": "Snow Pass", "music": "snow_pass", "g1": Color("d9e3ec"), "g2": Color("c9d6e2"), "dry": Color("e6edf3"), "shoulder": Color("bccad8"),
		"bg": Color("e4edf5"), "fog": Color("e6eef4"), "amb": Color("c6d2e2"), "road": Car.SNOW},
]
const ROAD_COL := {Car.TARMAC: [Color("626a76"), Color("535a65")], Car.GRAVEL: [Color("e6cc9f"), Color("cfb287")], Car.SNOW: [Color("aab6c4"), Color("98a6b6")]}

var H := PackedFloat32Array()   # heights, (N+1) x (N+1)
var C := PackedColorArray()     # ground colour at each height point
var roads: Array = []
var road_hash := {}
var solid_hash := {}            # trees and rocks, so finds keep clear of them
var reach := PackedByteArray()  # coarse grid of ground the car can get to
var finds: Array = []
var found_ids := {}
var biome_spot := [[0, 0], [0, 0], [0, 0]]
var noise := FastNoiseLite.new()
var noise2 := FastNoiseLite.new()
var car: Car
var cam: Camera3D
var hud: Hud
var sun: DirectionalLight3D
var env: Environment
var music: AudioStreamPlayer
var sfx: AudioStreamPlayer
var music_on := true
var music_now := ""
var cur_biome := 0
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
var auto_drive := false   # the car handles gas and brake, the player only steers
var tree_count := 0
var _spin := 0.0
var _bt := 0.0
var _bstep := -1
var _blog := {}
var _drive_i := 0
var _drive_far := 0.0
var _drive_dist := 0.0
var _drive_stuck := 0.0

func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	var args := OS.get_cmdline_user_args()
	for b in ["bot", "drive", "reach"]:
		if args.has("--" + b):
			bot = b
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
	if bot != "":
		pass   # test runs start from a clean slate
	else:
		load_game()
	if bot == "bot":
		_flat_pad()
	else:
		for step in [_roads, _heights, _terrain, _water, _ribbons, _scenery, _walls, _reach, _finds]:
			var t1 := Time.get_ticks_msec()
			step.call()
			if args.has("--times"):
				print("TIME %s %d ms" % [step.get_method(), Time.get_ticks_msec() - t1])
	_light()
	_sound()
	car = Car.new()
	car.surface_fn = surface_at
	add_child(car)
	cam = Camera3D.new()
	cam.fov = 30.0
	cam.near = 0.6
	cam.far = 900.0
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
	hud.auto_pressed.connect(toggle_auto)
	hud.music_pressed.connect(toggle_music)
	hud.journal_pressed.connect(func(): hud.toggle_journal(finds))
	if _cfg.has("preset"):
		car.preset = clampi(int(_cfg.preset), 0, Car.PRESETS.size() - 1)
		cam_mode = clampi(int(_cfg.get("cam", 0)), 0, CAMS.size() - 1)
		car.sound_on = bool(_cfg.get("sound", true))
		if not args.has("--auto"):
			auto_drive = bool(_cfg.get("auto", false))
		music_on = bool(_cfg.get("music", true))
	if args.has("--auto"):
		auto_drive = true
	hud.set_preset(Car.PRESETS[car.preset].name)
	hud.set_auto(auto_drive)
	hud.set_music(music_on)
	hud.set_sound(car.sound_on)
	_spawn()
	_show_finds()
	if bot != "":
		hud.hide_title()
		started = true
	if bot == "reach":
		_reach_report(Time.get_ticks_msec() - t0)

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
	_key("auto", [KEY_G], [JOY_BUTTON_B])
	_key("start", [KEY_ENTER, KEY_SPACE], [JOY_BUTTON_A, JOY_BUTTON_START])
	_key("journal", [KEY_J, KEY_TAB], [JOY_BUTTON_START])
	_key("music", [KEY_M], [])
	_key("go1", [KEY_1]); _key("go2", [KEY_2]); _key("go3", [KEY_3])

func _start() -> void:
	started = true
	hud.hide_title()
	car.start_sound()
	music.play()
	hud.message(BIOME[cur_biome].name)

func _toggle_sound() -> void:
	car.sound_on = not car.sound_on
	hud.set_sound(car.sound_on)
	save_game()

func toggle_auto() -> void:
	auto_drive = not auto_drive
	hud.set_auto(auto_drive)
	save_game()

func toggle_music() -> void:
	music_on = not music_on
	hud.set_music(music_on)
	save_game()

## Auto drive: the speed the car holds by itself. It eases off before bends when it is on a road,
## and when the player turns the wheel hard.
func _auto_target(steer: float) -> float:
	var target := 15.0
	var pos := car.global_position
	var rn := road_near(pos.x, pos.z)
	if rn[1] >= 0 and rn[0] < roads[rn[1]].hw + 3.0:
		var r: Dictionary = roads[rn[1]]
		var p: PackedVector2Array = r.p
		var n := p.size()
		var i: int = rn[2]
		var nxt := (i + 1) % n if r.closed else mini(i + 1, n - 1)
		var prv := (i - 1 + n) % n if r.closed else maxi(i - 1, 0)
		var tan := (p[nxt] - p[prv]).normalized()
		var f := car.global_transform.basis.z
		var step := 1 if Vector2(f.x, f.z).dot(tan) >= 0.0 else -1
		var reach := 8 + int(car.speed * 0.9)   # samples are 2 m apart
		var bend := 0.0
		var last := tan * step
		for k in [reach / 2, reach]:
			var a: int = i + step * int(k)
			var b: int = a + step * 3
			if r.closed:
				a = (a % n + n) % n; b = (b % n + n) % n
			else:
				a = clampi(a, 0, n - 1); b = clampi(b, 0, n - 1)
			if a == b:
				target = minf(target, 9.0)   # the road ends ahead
				break
			var d := (p[b] - p[a]).normalized()
			bend += absf(last.angle_to(d))
			last = d
		target = clampf(25.0 - bend * 17.0, 10.0, 25.0) if target > 9.5 else target
		if r.s[i] == Car.TARMAC:
			target *= 1.08
		elif r.s[i] == Car.SNOW:
			target *= 0.85
	return target * (1.0 - 0.3 * absf(steer))

## Gas and brake for auto drive. The player's own brake or handbrake always wins.
func _auto_pedals(steer: float, gas: float, brake: float, hand: bool) -> Array:
	if brake > 0.05 or hand:
		return [0.0, brake]
	var target := _auto_target(steer)
	var g := maxf(gas, clampf((target - car.speed) * 0.45, 0.0, 1.0))
	var b := clampf((car.speed - target - 3.0) * 0.25, 0.0, 0.8)
	return [g if b <= 0.0 else 0.0, b]

func next_cam() -> void:
	cam_mode = (cam_mode + 1) % CAMS.size()
	save_game()

func next_preset() -> void:
	car.preset = (car.preset + 1) % Car.PRESETS.size()
	hud.set_preset(Car.PRESETS[car.preset].name)
	save_game()

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
	elif e.is_action_pressed("auto"):
		toggle_auto()
	elif e.is_action_pressed("journal"):
		hud.toggle_journal(finds)
	elif e.is_action_pressed("music"):
		toggle_music()
	else:
		for b in 3:   # test keys 1, 2 and 3: jump to a road in each biome
			if e.is_action_pressed("go%d" % (b + 1)):
				resets += 1
				_place_on_road(biome_spot[b][0], biome_spot[b][1])

# ---------- biomes ----------

## How much of each biome a spot is: x Pine Lakes, y Golden Hills, z Snow Pass. The three add up to 1.
func biome_w(x: float, z: float) -> Vector3:
	var n := noise2.get_noise_2d(x * 0.25 + 700.0, z * 0.25 - 300.0) * 70.0
	var ws := smoothstep(-150.0, -270.0, z + n)
	var wp := (1.0 - ws) * smoothstep(70.0, -70.0, x + n * 0.8)
	return Vector3(wp, 1.0 - ws - wp, ws)

func biome_at(x: float, z: float) -> int:
	var w := biome_w(x, z)
	return 2 if (w.z >= w.x and w.z >= w.y) else (0 if w.x >= w.y else 1)

func _base_h(x: float, z: float) -> float:
	var w := biome_w(x, z)
	var n := noise.get_noise_2d(x, z)
	var d := noise2.get_noise_2d(x, z)
	var h := w.x * (n * 11.0 - 1.0 + d * 1.2) + w.y * (n * 15.0 + 4.0 + d * 1.8) + w.z * (n * 19.0 + 27.0 + d * 2.6)
	var edge := maxf(absf(x), absf(z)) - (SIZE / 2.0 - 60.0)
	if edge > 0.0:
		h += edge * edge * 0.012   # hills ring the world
	return h

# ---------- roads ----------

func _add_road(p: PackedVector2Array, hw: float, closed: bool) -> Dictionary:
	var n := p.size()
	var h := PackedFloat32Array()
	h.resize(n)
	var s := PackedByteArray()
	s.resize(n)
	for i in n:
		h[i] = maxf(_base_h(p[i].x, p[i].y), WATER + 1.0)   # a causeway where the road meets a lake
		s[i] = BIOME[biome_at(p[i].x, p[i].y)].road
	for pass_i in 3:   # smooth the height along the road so it rolls instead of bumps
		var h2 := PackedFloat32Array()
		h2.resize(n)
		for i in n:
			var sum := 0.0
			var c := 0
			for k in range(-9, 10):
				var j := i + k
				if closed:
					j = (j + n) % n
				elif j < 0 or j >= n:
					continue
				sum += h[j]
				c += 1
			h2[i] = sum / c
		h = h2
	# where this road meets one laid earlier, it takes that road's height
	if not roads.is_empty():
		for i in n:
			var rn := road_near(p[i].x, p[i].y)
			if rn[1] >= 0 and rn[0] < 30.0:
				h[i] = lerpf(roads[rn[1]].h[rn[2]], h[i], smoothstep(6.0, 30.0, rn[0]))
	var r := {"p": p, "h": h, "s": s, "hw": hw, "closed": closed}
	roads.append(r)
	var ri := roads.size() - 1
	for i in n:
		var key := Vector2i(floori(p[i].x / HASH), floori(p[i].y / HASH))
		if not road_hash.has(key):
			road_hash[key] = PackedInt32Array()
		road_hash[key].append(ri * 100000 + i)
	return r

func _roads() -> void:
	var ctrl := PackedVector2Array()
	for i in 18:
		var a := i / 18.0 * TAU
		var r := 430.0 + 70.0 * sin(3.0 * a + 0.7) + 40.0 * sin(5.0 * a + 2.1)
		ctrl.append(Vector2(cos(a), sin(a)) * r)
	var loop := _add_road(_catmull(ctrl, true), 3.8, true)
	# east to west across the middle, then north to south from the snow to the lakes
	_add_road(_catmull(PackedVector2Array([ctrl[0], Vector2(230, 40), Vector2(70, -30), Vector2(-80, 30), Vector2(-250, -20), ctrl[9]]), false), 3.8, false)
	_add_road(_catmull(PackedVector2Array([ctrl[13], Vector2(20, -300), Vector2(-30, -150), Vector2(15, -20), Vector2(-10, 130), Vector2(30, 290), ctrl[4]]), false), 3.8, false)
	# a road point deep inside each biome, for the banner, the test keys and the letters
	var lp: PackedVector2Array = loop.p
	for b in 3:
		var best := -1.0
		for i in range(0, lp.size(), 5):
			var w := biome_w(lp[i].x, lp[i].y)
			if w[b] > best:
				best = w[b]
				biome_spot[b] = [0, i]

## Nearest road sample: [distance, road index, sample index]. Distance is INF when no road is within reach.
func road_near(x: float, z: float) -> Array:
	var best := INF
	var br := -1
	var bi := -1
	var cx := floori(x / HASH)
	var cz := floori(z / HASH)
	var q := Vector2(x, z)
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			var key := Vector2i(cx + dx, cz + dz)
			if road_hash.has(key):
				for code in road_hash[key]:
					var ri: int = code / 100000
					var i: int = code % 100000
					var d: float = roads[ri].p[i].distance_squared_to(q)
					if d < best:
						best = d; br = ri; bi = i
	return [sqrt(best), br, bi]

func surface_at(x: float, z: float) -> int:
	if flat_surface >= 0:
		return flat_surface
	var best := 99
	var cx := floori(x / HASH)
	var cz := floori(z / HASH)
	var q := Vector2(x, z)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var key := Vector2i(cx + dx, cz + dz)
			if road_hash.has(key):
				for code in road_hash[key]:
					var r: Dictionary = roads[code / 100000]
					var i: int = code % 100000
					if r.s[i] < best and r.p[i].distance_squared_to(q) < r.hw * r.hw:
						best = r.s[i]
	if best < 99:
		return best
	return Car.DEEP_SNOW if biome_w(x, z).z > 0.5 else Car.GRASS

# ---------- ground ----------

func _heights() -> void:
	H.resize((N + 1) * (N + 1))
	C.resize((N + 1) * (N + 1))
	for iz in N + 1:
		for ix in N + 1:
			var x := (ix - N / 2.0) * CELL
			var z := (iz - N / 2.0) * CELL
			var h := _base_h(x, z)
			var w := biome_w(x, z)
			var a := noise2.get_noise_2d(x * 0.4 + 300.0, z * 0.4) * 0.5 + 0.5
			var b := noise.get_noise_2d(x * 1.7 - 500.0, z * 1.7) * 0.5 + 0.5
			var c := Color(0, 0, 0)
			var sh := Color(0, 0, 0)
			for bi in 3:
				var bd: Dictionary = BIOME[bi]
				c += bd.g1.lerp(bd.g2, a).lerp(bd.dry, b * 0.55) * w[bi]
				sh += bd.shoulder * w[bi]
			var rn := road_near(x, z)
			if rn[1] >= 0:
				var r: Dictionary = roads[rn[1]]
				h = lerpf(r.h[rn[2]], h, smoothstep(r.hw + 1.5, r.hw + 14.0, rn[0]))
				c = c.lerp(sh, 1.0 - smoothstep(r.hw - 0.5, r.hw + 5.0, rn[0]))
			c = c.lerp(Color("cdbf92"), smoothstep(WATER + 0.7, WATER - 0.3, h))   # sandy shore
			c.a = 1.0
			H[iz * (N + 1) + ix] = h
			C[iz * (N + 1) + ix] = c

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

func _terrain() -> void:
	var count := N * N * 6
	var verts := PackedVector3Array(); verts.resize(count)
	var norms := PackedVector3Array(); norms.resize(count)
	var cols := PackedColorArray(); cols.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var rock := Color("9c917b")
	var k := 0
	for iz in N:
		for ix in N:
			var x0 := (ix - N / 2.0) * CELL
			var z0 := (iz - N / 2.0) * CELL
			var i00 := iz * (N + 1) + ix
			var p00 := Vector3(x0, H[i00], z0)
			var p10 := Vector3(x0 + CELL, H[i00 + 1], z0)
			var p01 := Vector3(x0, H[i00 + N + 1], z0 + CELL)
			var p11 := Vector3(x0 + CELL, H[i00 + N + 2], z0 + CELL)
			for t in 2:
				var a: Vector3 = p00 if t == 0 else p10
				var b: Vector3 = p10 if t == 0 else p11
				var n: Vector3 = -(b - a).cross(p01 - a).normalized()
				var col: Color = C[i00] if t == 0 else C[i00 + N + 2]
				col = col.lerp(rock, smoothstep(0.42, 0.75, 1.0 - n.y * n.y))
				var jit := rng.randf_range(-0.035, 0.035)
				col = col.lightened(jit) if jit > 0.0 else col.darkened(-jit)
				verts[k] = a; norms[k] = n; cols[k] = col
				verts[k + 1] = b; norms[k + 1] = n; cols[k + 1] = col
				verts[k + 2] = p01; norms[k + 2] = n; cols[k + 2] = col
				k += 3
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

func _water() -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(SIZE, SIZE)
	mi.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.33, 0.62, 0.72, 0.84)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.25
	m.metallic = 0.1
	mi.material_override = m
	mi.position.y = WATER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func _ribbons() -> void:
	for ri in roads.size():
		var r: Dictionary = roads[ri]
		var p: PackedVector2Array = r.p
		var n := p.size()
		var hw: float = r.hw
		var lift := 0.04 + 0.025 * ri
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
			var rc: Array = ROAD_COL[r.s[i % n]]
			for j in 5:
				var q: Vector2 = a + side * hw * offs[j]
				st.set_normal(Vector3.UP)
				var shade := 0.03 * sin(i * 0.9 + j * 2.1)
				var c: Color = rc[1] if (j == 0 or j == 4) else rc[0]
				st.set_color(c.lightened(maxf(shade, 0.0)).darkened(maxf(-shade, 0.0)))
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
	var groups := {}    # "kind|chunk x|chunk z" -> transforms
	var bodies := {}    # chunk -> StaticBody3D
	var trunk := CylinderShape3D.new()
	trunk.radius = 0.38
	trunk.height = 5.0
	var spawn: Vector2 = roads[1].p[roads[1].p.size() / 2]
	var lim := SIZE / 2.0 - 30.0
	for i in 9000:
		var x := rng.randf_range(-lim, lim)
		var z := rng.randf_range(-lim, lim)
		var wood := noise2.get_noise_2d(x * 0.35 + 900.0, z * 0.35 - 200.0)
		var roll := rng.randf()
		var pick := rng.randf()
		var s := rng.randf()
		var yaw := rng.randf() * TAU
		var y := height_at(x, z)
		if y < WATER + 0.5:
			continue
		var rn := road_near(x, z)
		var rd: float = rn[0] - (roads[rn[1]].hw if rn[1] >= 0 else 0.0)
		if rd < 5.0 or Vector2(x, z).distance_to(spawn) < 16.0:
			continue
		var b := biome_at(x, z)
		var kind := ""
		var solid := 0.0
		var sc := Vector3.ONE
		if roll < 0.06:
			kind = ["rock", "rock_sand", "rock_ice"][b]
			var rs := lerpf(0.8, 2.4, s)
			sc = Vector3(rs * 1.3, rs, rs * 1.3)
			solid = rs * 0.55
			y -= 0.12 * rs
		elif roll < 0.17:
			if b == 2 or wood < -0.25:
				continue
			kind = "bush"
			var bs := lerpf(0.9, 1.7, s)
			sc = Vector3(bs * 1.4, bs, bs * 1.4)
		else:
			var need: float = [-0.02, 0.3, 0.12][b]
			if not (wood > need or (rd < 18.0 and roll > 0.93)):
				continue
			if b == 0:
				kind = "tree_pine" if pick < 0.85 else "tree_leafy"
			elif b == 1:
				kind = "tree_autumn_gold" if pick < 0.5 else ("tree_leafy" if pick < 0.8 else "tree_autumn_red")
			else:
				kind = "tree_pine_snow"
			var ts := lerpf(6.5, 10.5, s) if kind.begins_with("tree_pine") else lerpf(5.5, 8.5, s)
			sc = Vector3(ts, ts, ts)
			solid = 0.38
			y -= 0.15
			tree_count += 1
		var ck := Vector2i(floori(x / CHUNK), floori(z / CHUNK))
		var gk := "%s|%d|%d" % [kind, ck.x, ck.y]
		if not groups.has(gk):
			groups[gk] = []
		groups[gk].append(Transform3D(Basis(Vector3.UP, yaw).scaled(sc), Vector3(x, y, z)))
		if solid > 0.0:
			if not bodies.has(ck):
				bodies[ck] = StaticBody3D.new()
				add_child(bodies[ck])
			var cs := CollisionShape3D.new()
			if kind.begins_with("tree"):
				cs.shape = trunk
				cs.position = Vector3(x, y + 2.4, z)
			else:
				var sp := SphereShape3D.new()
				sp.radius = solid
				cs.shape = sp
				cs.position = Vector3(x, y + solid * 0.5, z)
			bodies[ck].add_child(cs)
			var hk := Vector2i(floori(x / 8.0), floori(z / 8.0))
			if not solid_hash.has(hk):
				solid_hash[hk] = []
			solid_hash[hk].append(Vector3(x, z, solid))
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	var meshes := {}
	for gk in groups:
		var kind: String = gk.split("|")[0]
		if not meshes.has(kind):
			meshes[kind] = _scenery_mesh(kind)
		var mesh: Mesh = meshes[kind]
		if mesh == null:
			continue
		var list: Array = groups[gk]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		if kind == "bush" or fast:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)

func _light() -> void:
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -52, 0)
	sun.light_color = Color("fff0d2")
	sun.light_energy = 0.6
	sun.shadow_enabled = not fast
	sun.directional_shadow_max_distance = 280.0
	sun.shadow_bias = 0.06
	add_child(sun)
	if fast:
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BIOME[0].bg
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.04
	env.adjustment_saturation = 1.06
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = BIOME[0].amb
	env.ambient_light_energy = 0.36
	env.fog_enabled = true
	env.fog_light_color = BIOME[0].fog
	env.fog_density = 0.0007
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

func _sound() -> void:
	music = AudioStreamPlayer.new()
	music.volume_db = -50.0
	add_child(music)
	sfx = AudioStreamPlayer.new()
	sfx.volume_db = -6.0
	add_child(sfx)

# ---------- things to find ----------

## Marks the ground the car can drive to from the start: a coarse flood fill that stops at deep water.
func _reach() -> void:
	var g := int(SIZE / 12.0)
	reach.resize(g * g)
	var ok := PackedByteArray()
	ok.resize(g * g)
	var lim := SIZE / 2.0 - 72.0
	for iz in g:
		for ix in g:
			var x := (ix + 0.5) * 12.0 - SIZE / 2.0
			var z := (iz + 0.5) * 12.0 - SIZE / 2.0
			ok[iz * g + ix] = 1 if (height_at(x, z) > WATER - 0.4 and absf(x) < lim and absf(z) < lim) else 0
	var sp: Vector2 = roads[1].p[roads[1].p.size() / 2]
	var start := int((sp.y + SIZE / 2.0) / 12.0) * g + int((sp.x + SIZE / 2.0) / 12.0)
	var stack := PackedInt32Array([start])
	reach[start] = 1
	while not stack.is_empty():
		var c := stack[stack.size() - 1]
		stack.remove_at(stack.size() - 1)
		var cx := c % g
		var cz := c / g
		for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			var nx: int = cx + d[0]
			var nz: int = cz + d[1]
			if nx < 0 or nz < 0 or nx >= g or nz >= g:
				continue
			var ni := nz * g + nx
			if ok[ni] == 1 and reach[ni] == 0:
				reach[ni] = 1
				stack.append(ni)

func can_reach(x: float, z: float) -> bool:
	var g := int(SIZE / 12.0)
	var ix := int((x + SIZE / 2.0) / 12.0)
	var iz := int((z + SIZE / 2.0) / 12.0)
	return ix >= 0 and iz >= 0 and ix < g and iz < g and reach[iz * g + ix] == 1

func _clear_of_solids(x: float, z: float, gap: float) -> bool:
	var hk := Vector2i(floori(x / 8.0), floori(z / 8.0))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var key := hk + Vector2i(dx, dz)
			if solid_hash.has(key):
				for s in solid_hash[key]:
					if Vector2(s.x, s.y).distance_to(Vector2(x, z)) < gap + s.z:
						return false
	return true

## A good place for a find. where: "road" on a road, "far" well away from any road, "" anywhere.
func _find_spot(rng: RandomNumberGenerator, biome: int, where: String, taken: Array) -> Vector3:
	var lim := SIZE / 2.0 - 90.0
	for attempt in 600:
		var x := rng.randf_range(-lim, lim)
		var z := rng.randf_range(-lim, lim)
		if where == "road":
			var r: Dictionary = roads[rng.randi() % roads.size()]
			var i: int = rng.randi() % int(r.p.size())
			var side: float = rng.randf_range(-0.5, 0.5) * float(r.hw)
			x = r.p[i].x + side
			z = r.p[i].y + side
		if biome >= 0 and (biome_w(x, z)[biome] < 0.7):
			continue
		if not can_reach(x, z) or height_at(x, z) < WATER + 0.7:
			continue
		if where == "far" and road_near(x, z)[0] < 45.0:
			continue
		if not _clear_of_solids(x, z, 4.0):
			continue
		var close := false
		for t in taken:
			if Vector2(t.x, t.z).distance_to(Vector2(x, z)) < 42.0:
				close = true
				break
		if close:
			continue
		return Vector3(x, height_at(x, z), z)
	return Vector3.INF

func _finds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var taken: Array = []
	# two letters in each biome: one waiting on a road, one hidden off the beaten track
	for k in 6:
		var pos := _find_spot(rng, [0, 0, 1, 1, 2, 2][k], "road" if k % 2 == 0 else "far", taken)
		if pos == Vector3.INF:
			pos = _find_spot(rng, -1, "road", taken)
		taken.append(pos)
		finds.append({"id": "letter%d" % k, "name": "the letter " + LETTERS[k], "kind": "letter", "k": k, "pos": pos, "found": false, "node": null})
	var f := FileAccess.open("res://data/finds.json", FileAccess.READ)
	var list: Array = JSON.parse_string(f.get_as_text()).finds if f != null else []
	for it in list:
		var pos := _find_spot(rng, -1, "road" if rng.randf() < 0.3 else "", taken)
		if pos == Vector3.INF:
			continue
		taken.append(pos)
		finds.append({"id": it.id, "name": it.name, "kind": "item", "k": -1, "pos": pos, "found": false, "node": null})
	for fd in finds:
		fd.found = found_ids.has(fd.id)

func _show_finds() -> void:
	var beam := CylinderMesh.new()
	beam.top_radius = 0.3; beam.bottom_radius = 0.3; beam.height = 22.0; beam.radial_segments = 6; beam.rings = 1
	var beam_mat := {}
	for c in [Color(1.0, 0.95, 0.75, 0.2), Color(1.0, 0.8, 0.25, 0.34)]:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = c
		beam_mat[beam_mat.size()] = m
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color("ffcf4a")
	gold.emission_enabled = true
	gold.emission = Color("ffb92e")
	gold.emission_energy_multiplier = 0.5
	gold.roughness = 0.5
	for fd in finds:
		if fd.found or bot == "bot":
			continue
		var root := Node3D.new()
		root.position = fd.pos
		var bm := MeshInstance3D.new()
		bm.mesh = beam
		bm.material_override = beam_mat[1 if fd.kind == "letter" else 0]
		bm.position.y = 11.5
		bm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(bm)
		if fd.kind == "letter":
			var tm := TextMesh.new()
			tm.text = LETTERS[fd.k]
			tm.font_size = 64
			tm.pixel_size = 0.075
			tm.depth = 0.5
			var mi := MeshInstance3D.new()
			mi.mesh = tm
			mi.material_override = gold
			mi.position.y = 3.2
			mi.name = "spin"
			root.add_child(mi)
		else:
			var sp := Sprite3D.new()
			sp.texture = load("res://icons/%s.png" % fd.id)
			sp.pixel_size = 0.042
			sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			sp.shaded = false
			sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
			sp.position.y = 2.8
			sp.name = "bob"
			root.add_child(sp)
		add_child(root)
		fd.node = root
	hud.set_finds(_found_count(), finds.size(), _letter_mask())

func _found_count() -> int:
	var n := 0
	for fd in finds:
		if fd.found:
			n += 1
	return n

func _letter_mask() -> Array:
	var out := [false, false, false, false, false, false]
	for fd in finds:
		if fd.kind == "letter":
			out[fd.k] = fd.found
	return out

func _collect(fd: Dictionary) -> void:
	fd.found = true
	found_ids[fd.id] = true
	if fd.node != null:
		fd.node.queue_free()
		fd.node = null
	var n := _found_count()
	var mask := _letter_mask()
	hud.set_finds(n, finds.size(), mask)
	var text := "Found %s   ·   %d of %d" % [fd.name, n, finds.size()]
	if fd.kind == "letter" and not mask.has(false):
		text = "S-C-E-N-I-C complete! All six letters found."
	if n == finds.size():
		text = "Everything found: %d of %d. What a drive." % [n, n]
	hud.message(text)
	if car.sound_on:
		sfx.stream = load("res://audio/letter.wav" if fd.kind == "letter" else "res://audio/pickup.wav")
		sfx.play()
	save_game()

# ---------- save ----------

var _cfg := {}

func load_game() -> void:
	if not FileAccess.file_exists(SAVE):
		return
	var f := FileAccess.open(SAVE, FileAccess.READ)
	var d: Variant = JSON.parse_string(f.get_as_text()) if f != null else null
	if d is Dictionary:
		_cfg = d
		for id in d.get("found", []):
			found_ids[str(id)] = true

func save_game() -> void:
	if bot != "" or car == null:
		return
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"v": 1, "found": found_ids.keys(), "preset": car.preset, "cam": cam_mode, "auto": auto_drive, "music": music_on, "sound": car.sound_on}))

# ---------- car placing ----------

func _spawn() -> void:
	if roads.is_empty():
		car.place(Vector3(0, 0.3, 0), 0.0)
	else:
		_place_on_road(1, roads[1].p.size() / 2)
		cur_biome = biome_at(car.global_position.x, car.global_position.z)
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
		if hud.journal_open:
			steer = 0.0; gas = 0.0; brake = 1.0
		elif auto_drive:
			var ped := _auto_pedals(steer, gas, brake, hand)
			gas = ped[0]; brake = ped[1]
		car.steer_in = steer
		car.gas_in = gas
		car.brake_in = brake
		car.hand_in = hand
	var pos := car.global_position
	if car.wants_reset or pos.y < -80.0:
		reset_car()
	elif not roads.is_empty() and pos.y < WATER - 0.9:
		reset_car()   # a swim puts the car back on the road, no penalty
		if bot == "":
			hud.message("Back on the road")
	for fd in finds:
		if not fd.found and absf(fd.pos.x - pos.x) < 4.5 and absf(fd.pos.z - pos.z) < 4.5 and absf(fd.pos.y - pos.y) < 6.0:
			_collect(fd)

func _process(dt: float) -> void:
	var b := car.global_transform.basis
	var heading := atan2(b.z.x, b.z.z)
	var v := car.linear_velocity
	if car.speed > 7.0 and car.fwd_speed > 2.0:
		heading = lerp_angle(heading, atan2(v.x, v.z), 0.45)
	if car.fwd_speed > -1.5:
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
	if roads.is_empty():
		return
	# the place: colours drift with the biome, and crossing into a new one changes the tune
	var cp := car.global_position
	var w := biome_w(cp.x, cp.z)
	var k := 1.0 - exp(-dt * 1.5)
	var bg := Color(0, 0, 0); var fog := Color(0, 0, 0); var amb := Color(0, 0, 0)
	for bi in 3:
		bg += BIOME[bi].bg * w[bi]; fog += BIOME[bi].fog * w[bi]; amb += BIOME[bi].amb * w[bi]
	env.background_color = env.background_color.lerp(bg, k)
	env.fog_light_color = env.fog_light_color.lerp(fog, k)
	env.ambient_light_color = env.ambient_light_color.lerp(amb, k)
	for bi in 3:
		if bi != cur_biome and w[bi] > 0.62:
			cur_biome = bi
			if started and bot == "":
				hud.message(BIOME[bi].name)
	var want_music: String = BIOME[cur_biome].music
	if started and music_on and music_now == want_music:
		music.volume_db = lerpf(music.volume_db, -11.0, 1.0 - exp(-dt * 1.2))
	else:
		music.volume_db = lerpf(music.volume_db, -60.0, 1.0 - exp(-dt * 2.0))
		if started and music_on and music.volume_db < -45.0:
			var st: AudioStream = load("res://audio/%s.ogg" % want_music)
			if st is AudioStreamOggVorbis:
				st.loop = true
			music.stream = st
			music.play()
			music_now = want_music
	# finds turn and bob so they catch the eye
	_spin += dt
	for fd in finds:
		if fd.node != null and absf(fd.pos.x - cp.x) < 160.0 and absf(fd.pos.z - cp.z) < 160.0:
			var n: Node3D = fd.node.get_child(1)
			if fd.kind == "letter":
				n.rotation.y = _spin * 1.6
			n.position.y = (3.2 if fd.kind == "letter" else 2.8) + sin(_spin * 2.2 + fd.pos.x) * 0.25

func _reach_report(ms: int) -> void:
	var per := [0, 0, 0]
	var bad := 0
	var on_road := 0
	for fd in finds:
		per[biome_at(fd.pos.x, fd.pos.z)] += 1
		if not can_reach(fd.pos.x, fd.pos.z) or fd.pos.y < WATER + 0.7 or not _clear_of_solids(fd.pos.x, fd.pos.z, 3.5):
			bad += 1
		if road_near(fd.pos.x, fd.pos.z)[0] < 4.0:
			on_road += 1
	var letters := []
	for fd in finds:
		if fd.kind == "letter":
			letters.append("%s %s (%d, %d)" % [LETTERS[fd.k], BIOME[biome_at(fd.pos.x, fd.pos.z)].name, int(fd.pos.x), int(fd.pos.z)])
	var total := 0
	for r in roads:
		total += r.p.size() * 2
	print("REACH finds %d, bad %d, on a road %d, by biome %s, trees %d, road %d m, built in %d ms" % [finds.size(), bad, on_road, str(per), tree_count, total, ms])
	print("REACH letters: " + ", ".join(letters))
	get_tree().quit()

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
	if auto_drive:   # the test driver only steers, auto drive works the pedals
		var ped := _auto_pedals(car.steer_in, 0.0, 0.0, false)
		car.gas_in = ped[0]; car.brake_in = ped[1]
	_drive_far = maxf(_drive_far, p[_drive_i].distance_to(pos))
	if car.speed < 1.0 and _bt > 3.0:
		_drive_stuck += dt
		if _drive_stuck > 3.0:
			reset_car()
			_drive_stuck = 0.0
	else:
		_drive_stuck = 0.0
	if _drive_dist >= n * 2.0 or _bt > 480.0:
		print("DRIVE lap %.0f m of %.0f m in %.0f s, average %.0f mph, farthest from road centre %.1f m, resets %d, cross %.2f" % [
			_drive_dist, n * 2.0, _bt, _drive_dist / _bt * 2.237, _drive_far, resets, cross])
		get_tree().quit()
