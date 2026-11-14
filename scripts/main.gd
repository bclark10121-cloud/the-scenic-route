extends Node3D
## The Scenic Route: a calm rally drive across three biomes with 100 things to find.
## The whole world is built in code at start-up: ground, water, roads, scenery and finds.
## Run with "-- --bot" for handling numbers, "-- --drive" for a lap of the main loop
## (add "--auto" to let auto drive work the pedals) and "-- --reach" for the finds report.

const Car := preload("res://scripts/car.gd")
const Hud := preload("res://scripts/hud.gd")

const SIZE := 1680.0    # metres across
const CELL := 6.0
const N := 280          # cells per side
const HASH := 16.0
const WATER := -3.2     # lake level
const CHUNK := 220.0    # scenery is grouped in squares this size so far-off trees are skipped
const CAMS := [[82.0, 47.0], [54.0, 42.0], [112.0, 55.0]]   # distance, tilt down in degrees. High and far first, like a diorama
const SAVE := "user://scenic_route.json"
const LETTERS := "SCENIC"
const BIOME := [
	{"name": "Pine Lakes", "music": "pine_lakes", "g1": Color("4f9150"), "g2": Color("6ea858"), "dry": Color("86b062"), "shoulder": Color("b39a72"),
		"bg": Color("cfe3e6"), "fog": Color("d6e6e2"), "amb": Color("b6c8d4"), "road": Car.GRAVEL, "off": Car.GRASS, "rc": [Color("e6cc9f"), Color("cfb287")]},
	{"name": "Golden Hills", "music": "golden_hills", "g1": Color("cdbd68"), "g2": Color("dbc878"), "dry": Color("e3c670"), "shoulder": Color("cfae7c"),
		"bg": Color("f1e2bd"), "fog": Color("f0e4c6"), "amb": Color("d6ccb4"), "road": Car.TARMAC, "off": Car.GRASS, "rc": [Color("626a76"), Color("535a65")]},
	{"name": "Snow Pass", "music": "snow_pass", "g1": Color("d9e3ec"), "g2": Color("c9d6e2"), "dry": Color("e6edf3"), "shoulder": Color("bccad8"),
		"bg": Color("e4edf5"), "fog": Color("e6eef4"), "amb": Color("c6d2e2"), "road": Car.SNOW, "off": Car.DEEP_SNOW, "rc": [Color("aab6c4"), Color("98a6b6")]},
	{"name": "Red Desert", "music": "desert", "g1": Color("e2a66a"), "g2": Color("ecb97a"), "dry": Color("d9925c"), "shoulder": Color("cf9a66"),
		"bg": Color("f7dcb4"), "fog": Color("f3dcbd"), "amb": Color("e0c8aa"), "road": Car.GRAVEL, "off": Car.SAND, "rc": [Color("b9794a"), Color("a2673d")]},
]
const BIOMES := 4

var H := PackedFloat32Array()   # heights, (N+1) x (N+1)
var C := PackedColorArray()     # ground colour at each height point
var roads: Array = []
var road_hash := {}
var solid_hash := {}            # trees and rocks, so finds keep clear of them
var reach := PackedByteArray()  # coarse grid of ground the car can get to
var finds: Array = []
var found_ids := {}
var biome_spot := [[0, 0], [0, 0], [0, 0], [0, 0]]
var tracks: Array = []      # one lap circuit per biome: {"road", "biome", "name"}
var best_laps := {}         # biome index as text -> seconds
var lap_track := -1         # the circuit being timed, or -1
var lap_t := 0.0
var lap_marks := 0          # bit 1 and bit 2: the two far checkpoints
var lap_armed := false
var last_lap := 0.0
var drive_road := 0
var works: Array = []       # road works sites: [road, first sample]
var ramps: Array = []
var ramp_yaw: Array = []
var best_jump := 0.0     # feet
var best_drift := 0.0    # feet
var top_speed := 0.0     # mph
var odo := 0.0           # miles
var _air_t := 0.0
var _jump_from := Vector3.ZERO
var _drift_d := 0.0
var _save_t := 0.0
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
	for b in ["bot", "drive", "reach", "jump"]:
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
		for step in [_roads, _heights, _terrain, _water, _ribbons, _gates, _road_dress, _scenery, _ramps, _walls, _reach, _finds]:
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
	hud.journal_pressed.connect(func(): hud.toggle_journal(finds, records_text()))
	if _cfg.has("preset"):
		car.preset = clampi(int(_cfg.preset), 0, Car.PRESETS.size() - 1)
		cam_mode = clampi(int(_cfg.get("cam", 0)), 0, CAMS.size() - 1)
		car.sound_on = bool(_cfg.get("sound", true))
		if not args.has("--auto"):
			auto_drive = bool(_cfg.get("auto", false))
		music_on = bool(_cfg.get("music", true))
	var saved_laps: Variant = _cfg.get("laps", {})
	if saved_laps is Dictionary:
		for k in saved_laps:
			best_laps[str(k)] = float(saved_laps[k])
	best_jump = float(_cfg.get("best_jump", 0.0))
	best_drift = float(_cfg.get("best_drift", 0.0))
	top_speed = float(_cfg.get("top_speed", 0.0))
	odo = float(_cfg.get("odo", 0.0))
	if args.has("--auto"):
		auto_drive = true
	for b in BIOMES:
		if args.has("--track%d" % b):
			drive_road = tracks[b].road
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
	_key("go1", [KEY_1]); _key("go2", [KEY_2]); _key("go3", [KEY_3]); _key("go4", [KEY_4])
	_key("go9", [KEY_9]); _key("go0", [KEY_0])
	_key("go5", [KEY_5]); _key("go6", [KEY_6]); _key("go7", [KEY_7]); _key("go8", [KEY_8])

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
	if brake > 0.05:
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
		hud.toggle_journal(finds, records_text())
	elif e.is_action_pressed("music"):
		toggle_music()
	else:
		if e.is_action_pressed("go9"):   # test key 9: to the first bridge
			for ri in roads.size():
				var at: int = roads[ri].br.find(1)
				if at >= 0:
					resets += 1
					_place_on_road(ri, maxi(at - 12, 0))
					break
		elif e.is_action_pressed("go0") and not works.is_empty():   # test key 0: to the first road works
			resets += 1
			_place_on_road(works[0][0], maxi(works[0][1] - 14, 0))
		for b in BIOMES:   # test keys 1 to 4: jump to a road in each biome
			if e.is_action_pressed("go%d" % (b + 1)):
				resets += 1
				_place_on_road(biome_spot[b][0], biome_spot[b][1])
			elif e.is_action_pressed("go%d" % (b + 5)):   # keys 5 to 8: to each circuit, a little before its gate
				resets += 1
				lap_track = -1
				_place_on_road(tracks[b].road, roads[tracks[b].road].p.size() - 14)

# ---------- biomes ----------

## How much of each biome a spot is: x Pine Lakes, y Golden Hills, z Snow Pass, w Red Desert. They add up to 1.
func biome_w(x: float, z: float) -> Vector4:
	var n := noise2.get_noise_2d(x * 0.25 + 700.0, z * 0.25 - 300.0) * 70.0
	var ws := smoothstep(-150.0, -270.0, z + n)
	var wd := smoothstep(400.0, 520.0, z + n)
	var wp := (1.0 - ws - wd) * smoothstep(70.0, -70.0, x + n * 0.8)
	return Vector4(wp, 1.0 - ws - wd - wp, ws, wd)

func biome_at(x: float, z: float) -> int:
	var w := biome_w(x, z)
	var best := 0
	for b in BIOMES:
		if w[b] > w[best]:
			best = b
	return best

func _base_h(x: float, z: float) -> float:
	var w := biome_w(x, z)
	var n := noise.get_noise_2d(x, z)
	var d := noise2.get_noise_2d(x, z)
	var h := w.x * (n * 11.0 - 1.0 + d * 1.2) + w.y * (n * 15.0 + 4.0 + d * 1.8) + w.z * (n * 19.0 + 27.0 + d * 2.6) + w.w * (n * 8.0 + 7.0 + absf(d) * 7.0)
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
	var br := PackedByteArray()   # 1 where the road crosses water: a bridge
	br.resize(n)
	var wk := PackedByteArray()   # 1 where road works have dug the road up
	wk.resize(n)
	for i in n:
		var bh := _base_h(p[i].x, p[i].y)
		br[i] = 1 if bh < WATER + 0.15 else 0
		h[i] = maxf(bh, WATER + 1.3)   # the deck sits clear of the lake
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
	var r := {"p": p, "h": h, "s": s, "hw": hw, "closed": closed, "br": br, "wk": wk}
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
	# a long bend out through the desert and back
	_add_road(_catmull(PackedVector2Array([ctrl[3], Vector2(340, 570), Vector2(210, 700), Vector2(0, 745), Vector2(-220, 695), Vector2(-345, 570), ctrl[6]]), false), 3.8, false)
	# a lap circuit in each biome, with a short link road to the nearest main road
	var centres := [Vector2(-200, 170), Vector2(210, 190), Vector2(0, -660), Vector2(0, 600)]
	for b in BIOMES:
		var cc := PackedVector2Array()
		for i in 10:
			var a := i / 10.0 * TAU
			var rr := 68.0 + 20.0 * sin(2.0 * a + b * 1.7) + 12.0 * sin(3.0 * a + b * 0.9)
			cc.append(centres[b] + Vector2(cos(a), sin(a)) * rr)
		_add_road(_catmull(cc, true), 4.6, true)
		tracks.append({"road": roads.size() - 1, "biome": b, "name": BIOME[b].name + " Circuit"})
	for b in BIOMES:
		var tp: PackedVector2Array = roads[tracks[b].road].p
		var best_d := INF
		var from := Vector2.ZERO
		var to := Vector2.ZERO
		for i in range(0, tp.size(), 4):
			for ri in 4:
				var mp: PackedVector2Array = roads[ri].p
				for j in range(0, mp.size(), 4):
					var d := tp[i].distance_squared_to(mp[j])
					if d < best_d:
						best_d = d; from = tp[i]; to = mp[j]
		var midp := (from + to) * 0.5 + (to - from).orthogonal().normalized() * 12.0
		_add_road(_catmull(PackedVector2Array([from, midp, to]), false), 3.6, false)
	# road works: two stretches on each main road where the surface is dug up to gravel
	for ri in 4:
		var r: Dictionary = roads[ri]
		var n: int = r.p.size()
		for frac in [0.27, 0.71]:
			var i0 := int(n * frac)
			var ok := true
			for j in range(i0 - 5, i0 + 40):
				if r.br[j % n] == 1:
					ok = false
			for rj in roads.size():
				if rj != ri and ok:
					for q in range(0, roads[rj].p.size(), 6):
						if roads[rj].p[q].distance_to(r.p[i0 + 15]) < 60.0:
							ok = false
							break
			if ok:
				works.append([ri, i0])
				for j in range(i0, i0 + 32):
					r.wk[j % n] = 1
					r.s[j % n] = Car.GRAVEL
	# a road point deep inside each biome, for the banner, the test keys and the letters
	for b in BIOMES:
		var best := -1.0
		for ri in 4:
			var lp: PackedVector2Array = roads[ri].p
			for i in range(10, lp.size() - 10, 5):
				var w := biome_w(lp[i].x, lp[i].y)
				if w[b] > best + 0.001:
					best = w[b]
					biome_spot[b] = [ri, i]

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
	return BIOME[biome_at(x, z)].off

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
			for bi in BIOMES:
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
		var lift := 0.04 + 0.015 * ri if ri < 4 else (0.1 if ri < 8 else 0.115)
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
			var bw := biome_w(a.x, a.y)   # the road colour blends where two biomes meet
			var rc := [Color(0, 0, 0), Color(0, 0, 0)]
			for bi in BIOMES:
				rc[0] += BIOME[bi].rc[0] * bw[bi]
				rc[1] += BIOME[bi].rc[1] * bw[bi]
			rc[0].a = 1.0; rc[1].a = 1.0
			if r.br[i % n] == 1:   # bridge deck: wooden planks
				rc = [Color("c9a26e") if i % 2 == 0 else Color("b98f5c"), Color("7d5f3e")]
			elif r.wk[i % n] == 1:   # road works: bare dirt
				rc = [Color("b08a5e"), Color("9a7650")]
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
	for i in 14500:
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
			kind = ["rock", "rock_sand", "rock_ice", "rock_sand"][b]
			var rs := lerpf(0.8, 2.4, s)
			sc = Vector3(rs * 1.3, rs, rs * 1.3)
			solid = rs * 0.55
			y -= 0.12 * rs
		elif roll < 0.17:
			if b >= 2 or wood < -0.25:
				continue
			kind = "bush"
			var bs := lerpf(0.9, 1.7, s)
			sc = Vector3(bs * 1.4, bs, bs * 1.4)
		else:
			var need: float = [-0.02, 0.3, 0.12, 0.2][b]
			if not (wood > need or (rd < 18.0 and roll > 0.93)):
				continue
			if b == 0:
				kind = "tree_pine" if pick < 0.85 else "tree_leafy"
			elif b == 1:
				kind = "tree_autumn_gold" if pick < 0.5 else ("tree_leafy" if pick < 0.8 else "tree_autumn_red")
			elif b == 2:
				kind = "tree_pine_snow"
			else:
				kind = "cactus"
			var ts := lerpf(6.5, 10.5, s) if kind.begins_with("tree_pine") else (lerpf(3.2, 5.6, s) if kind == "cactus" else lerpf(5.5, 8.5, s))
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
			if kind.begins_with("tree") or kind == "cactus":
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
	var cactus_mat := StandardMaterial3D.new()
	cactus_mat.albedo_color = Color("5c9c5e")
	cactus_mat.roughness = 1.0
	var meshes := {"cactus": _cactus_mesh()}
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
		mmi.material_override = cactus_mat if kind == "cactus" else mat
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

# ---------- ramps, jumps and records ----------

func _cactus_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part in [[Vector3(0, 0.5, 0), 0.11, 1.0, 0.0], [Vector3(0.2, 0.55, 0), 0.07, 0.34, 0.0], [Vector3(0.11, 0.42, 0), 0.07, 0.24, PI / 2],
			[Vector3(-0.19, 0.7, 0), 0.065, 0.3, 0.0], [Vector3(-0.1, 0.58, 0), 0.065, 0.22, PI / 2]]:
		var cm := CylinderMesh.new()
		cm.top_radius = part[1]; cm.bottom_radius = part[1]; cm.height = part[2]; cm.radial_segments = 7; cm.rings = 1
		st.append_from(cm, 0, Transform3D(Basis(Vector3(0, 0, 1), part[3]), part[0]))
	return st.commit()

func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, mid: Vector3, col: Color) -> void:
	var n := (b - a).cross(c - a)
	var pts := [a, b, c] if ((a + b + c) / 3.0 - mid).dot(n) < 0.0 else [a, c, b]
	for p in pts:
		st.set_color(col)
		st.add_vertex(p)

## Wooden ramps beside the roads, every so often. Optional fun: the road itself stays clear.
func _ramps() -> void:
	var w := 2.6; var l := 9.0; var h := 2.3
	var A := Vector3(-w, 0, 0); var B := Vector3(w, 0, 0); var Cc := Vector3(-w, 0, l); var D := Vector3(w, 0, l); var E := Vector3(-w, h, l); var F := Vector3(w, h, l)
	var mid := (A + B + Cc + D + E + F) / 6.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var plank := Color("e7cf9c"); var side := Color("a97f52"); var edge := Color("d9452b")
	_tri(st, A, B, F, mid, plank); _tri(st, A, F, E, mid, plank)
	_tri(st, Cc, D, F, mid, side); _tri(st, Cc, F, E, mid, side)
	_tri(st, A, Cc, E, mid, edge); _tri(st, B, D, F, mid, edge)
	st.generate_normals()
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([A, B, Cc, D, E, F])
	var cone_mesh := CylinderMesh.new()
	cone_mesh.top_radius = 0.06; cone_mesh.bottom_radius = 0.3; cone_mesh.height = 0.8; cone_mesh.radial_segments = 8; cone_mesh.rings = 1
	var cone_mat := StandardMaterial3D.new()
	cone_mat.albedo_color = Color("ff7a1a")
	var cone_shape := CylinderShape3D.new()
	cone_shape.radius = 0.22; cone_shape.height = 0.8
	for ri in 4:   # main roads only: the circuits stay clear
		var r: Dictionary = roads[ri]
		var p: PackedVector2Array = r.p
		var n := p.size()
		var i := 70
		while i < n - 40:
			var tan: Vector2 = (p[i + 1] - p[i - 1]).normalized()
			var sd := Vector2(-tan.y, tan.x)
			var c: Vector2 = p[i] + sd * (float(r.hw) + 5.2)
			var land: Vector2 = c + tan * 26.0
			var start: Vector2 = c - tan * (l * 0.5)
			var ok := height_at(c.x, c.y) > WATER + 1.2 and height_at(land.x, land.y) > WATER + 1.2
			ok = ok and _clear_of_solids(c.x, c.y, 7.0) and _clear_of_solids(land.x, land.y, 6.0)
			ok = ok and absf(height_at(land.x, land.y) - height_at(start.x, start.y)) < 4.0
			if ok:   # keep clear of junctions
				for rj in roads.size():
					if rj != ri:
						for q in range(0, roads[rj].p.size(), 6):
							if roads[rj].p[q].distance_to(c) < 45.0:
								ok = false
								break
			if not ok:
				i += 25
				continue
			var body := StaticBody3D.new()
			body.transform = Transform3D(Basis(Vector3.UP, atan2(tan.x, tan.y)), Vector3(start.x, height_at(start.x, start.y) - 0.2, start.y))
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = mat
			body.add_child(mi)
			var cs := CollisionShape3D.new()
			cs.shape = shape
			body.add_child(cs)
			add_child(body)
			ramps.append(Vector3(c.x, height_at(c.x, c.y), c.y))
			ramp_yaw.append(atan2(tan.x, tan.y))
			var hk := Vector2i(floori(c.x / 8.0), floori(c.y / 8.0))
			if not solid_hash.has(hk):
				solid_hash[hk] = []
			solid_hash[hk].append(Vector3(c.x, c.y, 7.0))
			if bot == "":   # cones to knock over mark the run-up
				for k in 4:
					var cp: Vector2 = start - tan * (4.0 + 6.0 * (k / 2)) + sd * (3.4 if k % 2 == 0 else -3.4)
					var cone := RigidBody3D.new()
					cone.mass = 2.0
					cone.position = Vector3(cp.x, height_at(cp.x, cp.y) + 0.45, cp.y)
					var cmi := MeshInstance3D.new()
					cmi.mesh = cone_mesh
					cmi.material_override = cone_mat
					cone.add_child(cmi)
					var ccs := CollisionShape3D.new()
					ccs.shape = cone_shape
					cone.add_child(ccs)
					add_child(cone)
			i += 190

func records_text() -> String:
	var laps := ""
	for t in tracks:
		var key := str(t.biome)
		laps += "%s %s   " % [t.name, lap_text(best_laps[key]) if best_laps.has(key) else "no lap yet"]
	return laps + "\nBest jump %d ft   ·   Longest drift %d ft   ·   Top speed %d mph   ·   %.1f miles driven" % [int(best_jump), int(best_drift), int(top_speed), odo]

## Jumps, drifts, top speed and miles. Personal bests only: nothing to beat but yourself.
func _records(dt: float, pos: Vector3) -> void:
	odo += car.speed * dt / 1609.34
	var mph := car.speed * 2.23694
	if mph > top_speed + 1.0 and car.grounded >= 2:
		top_speed = mph
	if car.grounded == 0:
		if _air_t == 0.0:
			_jump_from = pos
		_air_t += dt
	elif car.grounded >= 2:
		if _air_t > 0.45:
			var ft := Vector2(pos.x - _jump_from.x, pos.z - _jump_from.z).length() * 3.281
			if ft >= 15.0:
				if ft > best_jump:
					best_jump = ft
					hud.message("Jump %d ft   ·   new best!" % int(ft))
					save_game()
				else:
					hud.message("Jump %d ft   ·   best %d ft" % [int(ft), int(best_jump)])
		_air_t = 0.0
	if car.slide > 0.3 and car.speed > 7.0 and car.grounded >= 2:
		_drift_d += car.speed * dt
	else:
		var dft := _drift_d * 3.281
		_drift_d = 0.0
		if dft >= 80.0:
			if dft > best_drift:
				best_drift = dft
				hud.message("Drift %d ft   ·   new best!" % int(dft))
				save_game()
			else:
				hud.message("Drift %d ft" % int(dft))
	_save_t += dt
	if _save_t > 45.0:
		_save_t = 0.0
		save_game()

# ---------- bridges and road works ----------

func _knock(mesh: Mesh, mat: Material, shape: Shape3D, pos: Vector3, yaw: float, mass: float) -> void:
	var b := RigidBody3D.new()
	b.mass = mass
	b.transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	b.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	b.add_child(cs)
	add_child(b)

## Railings on the bridges, and cones, barriers and a dirt pile at the road works.
## Everything at the road works can be knocked over: nothing there can stop the car for good.
func _road_dress() -> void:
	var posts: Array = []
	var rails: Array = []
	for r in roads:
		var p: PackedVector2Array = r.p
		var n := p.size()
		for i in n:
			if r.br[i] == 0:
				continue
			var nx := p[(i + 1) % n] if (r.closed or i < n - 1) else p[i]
			var pv := p[(i - 1 + n) % n] if (r.closed or i > 0) else p[i]
			var tan := (nx - pv).normalized()
			var sd := Vector2(-tan.y, tan.x)
			for sx in [-1.0, 1.0]:
				var q: Vector2 = p[i] + sd * sx * (float(r.hw) + 0.25)
				var y := height_at(q.x, q.y)
				var basis := Basis(Vector3.UP, atan2(tan.x, tan.y))
				rails.append(Transform3D(basis, Vector3(q.x, y + 1.05, q.y)))
				if i % 3 == 0:
					posts.append(Transform3D(basis, Vector3(q.x, y + 0.55, q.y)))
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("f1e6cf")
	wood.roughness = 0.9
	for pair in [[posts, Vector3(0.28, 1.3, 0.28)], [rails, Vector3(0.16, 0.16, 2.15)]]:
		var list: Array = pair[0]
		if list.is_empty():
			continue
		var bm := BoxMesh.new()
		bm.size = pair[1]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = bm
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = wood
		add_child(mmi)
	if bot == "bot":
		return
	var cone_mesh := CylinderMesh.new()
	cone_mesh.top_radius = 0.06; cone_mesh.bottom_radius = 0.3; cone_mesh.height = 0.8; cone_mesh.radial_segments = 8; cone_mesh.rings = 1
	var orange := StandardMaterial3D.new()
	orange.albedo_color = Color("ff7a1a")
	var cone_shape := CylinderShape3D.new()
	cone_shape.radius = 0.22; cone_shape.height = 0.8
	var board_mesh := BoxMesh.new()
	board_mesh.size = Vector3(2.4, 1.0, 0.22)
	var board_shape := BoxShape3D.new()
	board_shape.size = Vector3(2.4, 1.0, 0.22)
	var stripe := StandardMaterial3D.new()
	stripe.albedo_color = Color("ffd23a")
	var pile_mesh := SphereMesh.new()
	pile_mesh.radius = 1.7; pile_mesh.height = 1.9; pile_mesh.radial_segments = 8; pile_mesh.rings = 4
	var dirt := StandardMaterial3D.new()
	dirt.albedo_color = Color("9a7650")
	dirt.roughness = 1.0
	for site in works:
		var r: Dictionary = roads[site[0]]
		var p: PackedVector2Array = r.p
		var n := p.size()
		var hw: float = r.hw
		for k in 16:   # cones narrow the road to one lane, then hold the line
			var i: int = (site[1] + k * 2) % n
			var tan: Vector2 = (p[(i + 1) % n] - p[(i - 1 + n) % n]).normalized()
			var sd := Vector2(-tan.y, tan.x)
			var q: Vector2 = p[i] + sd * hw * lerpf(0.95, 0.42, minf(k / 5.0, 1.0))
			_knock(cone_mesh, orange, cone_shape, Vector3(q.x, height_at(q.x, q.y) + 0.45, q.y), 0.0, 2.0)
			if k == 6 or k == 11:   # striped boards across the closed lane
				var bq: Vector2 = p[i] + sd * hw * 0.72
				_knock(board_mesh, stripe, board_shape, Vector3(bq.x, height_at(bq.x, bq.y) + 0.55, bq.y), atan2(tan.x, tan.y), 9.0)
			if k == 9:   # a pile of dirt on the verge
				var dq: Vector2 = p[i] + sd * (hw + 2.4)
				var mi := MeshInstance3D.new()
				mi.mesh = pile_mesh
				mi.material_override = dirt
				mi.position = Vector3(dq.x, height_at(dq.x, dq.y) + 0.1, dq.y)
				add_child(mi)

# ---------- lap circuits ----------

func lap_text(sec: float) -> String:
	return "%d:%05.2f" % [int(sec / 60.0), fmod(sec, 60.0)]

## Start gates for the circuits: two posts and a banner over the start line.
func _gates() -> void:
	var red := StandardMaterial3D.new()
	red.albedo_color = Color("d9452b")
	var cream := StandardMaterial3D.new()
	cream.albedo_color = Color("f6ecd6")
	for t in tracks:
		var r: Dictionary = roads[t.road]
		var a: Vector2 = r.p[0]
		var tan: Vector2 = (r.p[1] - r.p[r.p.size() - 1]).normalized()
		var root := Node3D.new()
		root.transform = Transform3D(Basis(Vector3.UP, atan2(tan.x, tan.y)), Vector3(a.x, height_at(a.x, a.y), a.y))
		for sx in [-1.0, 1.0]:
			var post := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.5, 6.0, 0.5)
			post.mesh = bm
			post.material_override = red
			post.position = Vector3(sx * (float(r.hw) + 1.2), 3.0, 0)
			root.add_child(post)
		for k in 6:   # a banner of red and cream blocks
			var blk := MeshInstance3D.new()
			var bb := BoxMesh.new()
			var span := (float(r.hw) + 1.2) * 2.0 / 6.0
			bb.size = Vector3(span, 1.1, 0.3)
			blk.mesh = bb
			blk.material_override = cream if k % 2 == 0 else red
			blk.position = Vector3(-(float(r.hw) + 1.2) + span * (k + 0.5), 5.6, 0)
			root.add_child(blk)
		add_child(root)

## Times a lap on a circuit. Drive through the gate to start, round the circuit either way, and
## through the gate again to finish. Only your own best is kept. Leave the circuit and the lap is dropped.
func _laps(dt: float, pos: Vector3) -> void:
	var q := Vector2(pos.x, pos.z)
	if lap_track < 0:
		for ti in tracks.size():
			var r: Dictionary = roads[tracks[ti].road]
			var d: float = r.p[0].distance_to(q)
			if d < 7.5 and lap_armed and car.speed > 2.0:
				lap_track = ti; lap_t = 0.0; lap_marks = 0; lap_armed = false
				hud.message(tracks[ti].name + "   ·   lap started")
				return
		var near_gate := false
		for t in tracks:
			if roads[t.road].p[0].distance_to(q) < 16.0:
				near_gate = true
		if not near_gate:
			lap_armed = true
		hud.set_lap("")
		return
	var tr: Dictionary = tracks[lap_track]
	var r2: Dictionary = roads[tr.road]
	var p: PackedVector2Array = r2.p
	var n := p.size()
	lap_t += dt
	if p[n / 3].distance_to(q) < 14.0:
		lap_marks |= 1
	if p[2 * n / 3].distance_to(q) < 14.0:
		lap_marks |= 2
	var gate := p[0].distance_to(q)
	if gate > 16.0:
		lap_armed = true
	var key := str(tr.biome)
	var best: float = best_laps.get(key, 0.0)
	hud.set_lap("%s   %s%s" % [tr.name, lap_text(lap_t), ("   ·   best " + lap_text(best)) if best > 0.0 else ""])
	if gate < 7.5 and lap_armed and lap_marks == 3:
		last_lap = lap_t
		if best <= 0.0 or lap_t < best:
			best_laps[key] = lap_t
			hud.message("Lap %s   ·   new best!" % lap_text(lap_t))
			save_game()
		else:
			hud.message("Lap %s   ·   best %s" % [lap_text(lap_t), lap_text(best)])
		lap_t = 0.0; lap_marks = 0; lap_armed = false   # straight into the next lap
	elif road_near(pos.x, pos.z)[0] > 60.0 or (gate > 16.0 and _track_dist(p, q) > 45.0):
		lap_track = -1
		hud.message("Lap dropped")

func _track_dist(p: PackedVector2Array, q: Vector2) -> float:
	var best := INF
	for i in range(0, p.size(), 5):
		best = minf(best, p[i].distance_squared_to(q))
	return sqrt(best)

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
		var pos := _find_spot(rng, int(it.get("biome", -1)), "road" if rng.randf() < 0.3 else "", taken)
		if pos == Vector3.INF:
			pos = _find_spot(rng, -1, "", taken)
		if pos == Vector3.INF:
			continue
		taken.append(pos)
		finds.append({"id": it.id, "name": it.name, "kind": "item", "k": -1, "pos": pos, "found": false, "node": null})
	for fd in finds:
		fd.found = found_ids.has(fd.id)

func _show_finds() -> void:
	# a soft glow on the ground under each find, so it catches the eye without a beam in the air
	var beam := CylinderMesh.new()
	beam.top_radius = 2.0; beam.bottom_radius = 2.0; beam.height = 0.06; beam.radial_segments = 20; beam.rings = 1
	var beam_mat := {}
	for c in [Color(1.0, 0.97, 0.8, 0.28), Color(1.0, 0.8, 0.25, 0.42)]:
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
		bm.position.y = 0.3
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
		f.store_string(JSON.stringify({"v": 1, "found": found_ids.keys(), "preset": car.preset, "cam": cam_mode, "auto": auto_drive, "music": music_on, "sound": car.sound_on,
			"laps": best_laps, "best_jump": best_jump, "best_drift": best_drift, "top_speed": top_speed, "odo": odo}))

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
	_air_t = 0.0
	_drift_d = 0.0
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
	elif bot == "jump":
		_jump_bot(dt)
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
	if bot == "" and started:
		_records(dt, pos)
	if (bot == "" and started) or bot == "drive":
		_laps(dt, pos)

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
	cam.near = maxf(4.0, cam_dist * 0.3)   # a far-off near plane keeps roads from flickering on phones
	cam.far = cam_dist * 8.0 + 300.0
	cam.look_at(cam_at + Vector3.UP * 0.6)
	hud.set_speed(car.speed * 2.23694, Car.SURF_NAME[car.surface])
	if roads.is_empty():
		return
	# the place: colours drift with the biome, and crossing into a new one changes the tune
	var cp := car.global_position
	var w := biome_w(cp.x, cp.z)
	var k := 1.0 - exp(-dt * 1.5)
	var bg := Color(0, 0, 0); var fog := Color(0, 0, 0); var amb := Color(0, 0, 0)
	for bi in BIOMES:
		bg += BIOME[bi].bg * w[bi]; fog += BIOME[bi].fog * w[bi]; amb += BIOME[bi].amb * w[bi]
	env.background_color = env.background_color.lerp(bg, k)
	env.fog_light_color = env.fog_light_color.lerp(fog, k)
	env.ambient_light_color = env.ambient_light_color.lerp(amb, k)
	for bi in BIOMES:
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

## Drives at every ramp in turn and reports the jump: distance, air time and whether the car stayed upright.
func _jump_bot(dt: float) -> void:
	if _bstep < 0:
		_bstep = 0; _bt = 0.0
	if _bstep >= ramps.size():
		print("JUMP done, ramps %d, shortest %d ft, longest %d ft, rolled %d" % [ramps.size(), int(_blog.get("lo", 0)), int(_blog.get("hi", 0)), int(_blog.get("rolled", 0))])
		get_tree().quit()
		return
	var c: Vector3 = ramps[_bstep]
	var yaw: float = ramp_yaw[_bstep]
	var dir := Vector3(sin(yaw), 0, cos(yaw))
	if _bt == 0.0:
		var st := c - dir * 55.0
		car.place(Vector3(st.x, height_at(st.x, st.z) + 0.3, st.z), yaw)
		_air_t = 0.0
		_blog["ft"] = 0.0; _blog["up"] = 1.0
	_bt += dt
	var pos := car.global_position
	var to := (c + dir * 6.0) - pos
	var f := car.global_transform.basis.z
	var before := to.dot(dir) > 0.0
	car.steer_in = clampf(atan2(Vector2(f.x, f.z).cross(Vector2(to.x, to.z)), Vector2(f.x, f.z).dot(Vector2(to.x, to.z))) * 2.0, -1.0, 1.0) if before else 0.0
	car.gas_in = 1.0 if before else 0.0
	car.brake_in = 0.0 if before or car.grounded == 0 else 1.0
	_blog["up"] = minf(_blog["up"], car.global_transform.basis.y.y)
	if car.grounded == 0:
		if _air_t == 0.0:
			_jump_from = pos
		_air_t += dt
	elif car.grounded >= 2:
		if _air_t > 0.3:
			_blog["ft"] = maxf(_blog["ft"], Vector2(pos.x - _jump_from.x, pos.z - _jump_from.z).length() * 3.281)
		_air_t = 0.0
	if _bt > 9.0:
		var ft: float = _blog["ft"]
		_blog["lo"] = ft if not _blog.has("lo") else minf(_blog["lo"], ft)
		_blog["hi"] = maxf(_blog.get("hi", 0.0), ft)
		if _blog["up"] < 0.3 or resets > int(_blog.get("r0", 0)):
			_blog["rolled"] = int(_blog.get("rolled", 0)) + 1
		_blog["r0"] = resets
		_bstep += 1
		_bt = 0.0

func _reach_report(ms: int) -> void:
	var per := [0, 0, 0, 0]
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
	var bridge_m := 0
	for r in roads:
		for i in r.br.size():
			bridge_m += 2 * int(r.br[i])
	print("REACH finds %d, bad %d, on a road %d, by biome %s, trees %d, ramps %d, road works %d, bridge %d m, road %d m, built in %d ms" % [finds.size(), bad, on_road, str(per), tree_count, ramps.size(), works.size(), bridge_m, total, ms])
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
	var r: Dictionary = roads[drive_road]
	var p: PackedVector2Array = r.p
	var n := p.size()
	var pos := Vector2(car.global_position.x, car.global_position.z)
	if _bstep < 0:
		_bstep = 0
		_drive_i = 0
		_place_on_road(drive_road, (p.size() - 14) if drive_road > 0 else 0)
		_drive_i = (p.size() - 14) if drive_road > 0 else 0
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
		if drive_road > 0 and last_lap <= 0.0 and _bt < 200.0:
			return   # on a circuit, keep going until the lap timer has seen a full lap
		print("DRIVE timed lap %s on road %d. " % [lap_text(last_lap) if last_lap > 0.0 else "none", drive_road] + "lap %.0f m of %.0f m in %.0f s, average %.0f mph, farthest from road centre %.1f m, resets %d, cross %.2f" % [
			_drive_dist, n * 2.0, _bt, _drive_dist / _bt * 2.237, _drive_far, resets, cross])
		get_tree().quit()
