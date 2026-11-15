extends VehicleBody3D
## The car. Front is +Z (Godot's vehicle forward). Built in code: body, wheels, dust and engine sound.
## No damage, no fuel, no way to break it. main.gd sets steer_in, gas_in, brake_in and hand_in every frame.

const TARMAC := 0
const GRAVEL := 1
const GRASS := 2
const SNOW := 3        # packed snow road
const DEEP_SNOW := 4   # off the road in the snow
const SAND := 5        # off the road in the desert
const SURF_NAME := ["Tarmac", "Gravel", "Grass", "Snow", "Deep snow", "Sand"]
# grip is the tyre hold, drag slows the car, top is the speed (m/s) where the engine runs out
const SURF := [
	{"grip": 1.55, "drag": 0.0, "top": 50.0},
	{"grip": 0.98, "drag": 18.0, "top": 42.0},
	{"grip": 0.92, "drag": 20.0, "top": 41.0},   # grass: nearly as quick as gravel, so off-road jumps work
	{"grip": 0.80, "drag": 26.0, "top": 38.0},
	{"grip": 0.76, "drag": 24.0, "top": 39.0},
	{"grip": 0.84, "drag": 22.0, "top": 40.0},
]
# three handling choices for the feel test
const PRESETS := [
	{"name": "Easy", "grip": 1.2, "power": 0.85, "assist": 1.0, "rear": 1.0},
	{"name": "Rally", "grip": 1.0, "power": 1.0, "assist": 0.45, "rear": 0.88},
	{"name": "Loose", "grip": 0.8, "power": 1.1, "assist": 0.0, "rear": 0.78},
]
const POWER := 2050.0      # engine force per wheel at a standstill
const BRAKE := 38.0
const WHEEL_AT := [Vector3(0.8, 0.42, 1.28), Vector3(-0.8, 0.42, 1.28), Vector3(0.8, 0.42, -1.25), Vector3(-0.8, 0.42, -1.25)]

var preset := 1
var steer_in := 0.0
var gas_in := 0.0
var brake_in := 0.0
var hand_in := false
var surface_fn: Callable   # (x, z) -> surface id
var surface := TARMAC      # what most wheels stand on
var speed := 0.0           # m/s
var fwd_speed := 0.0
var grounded := 0
var slide := 0.0           # 0 to 1, how sideways the car is going
var wheels: Array[VehicleWheel3D] = []
var shell: Node3D
var dust: Array[CPUParticles3D] = []
var engine: AudioStreamPlayer
var skid: AudioStreamPlayer
var sound_on := true
var _lean := Vector2.ZERO
var _last_v := Vector3.ZERO
var _flip_t := 0.0
var wants_reset := false

func _ready() -> void:
	mass = 1150.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.18, 0.05)
	angular_damp = 0.35
	linear_damp = 0.02
	continuous_cd = true
	var pm := PhysicsMaterial.new()
	pm.friction = 0.25
	pm.bounce = 0.0
	physics_material_override = pm
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.66, 0.5, 3.8)
	cs.shape = bs
	cs.position = Vector3(0, 0.62, 0)
	add_child(cs)
	var cs2 := CollisionShape3D.new()
	var bs2 := BoxShape3D.new()
	bs2.size = Vector3(1.4, 0.45, 1.7)
	cs2.shape = bs2
	cs2.position = Vector3(0, 1.05, -0.3)
	add_child(cs2)
	for i in 4:
		var w := VehicleWheel3D.new()
		w.position = WHEEL_AT[i]
		w.wheel_radius = 0.33
		w.wheel_rest_length = 0.22
		w.suspension_travel = 0.24
		w.suspension_stiffness = 42.0
		w.suspension_max_force = 16000.0
		w.damping_compression = 2.6
		w.damping_relaxation = 3.4
		w.wheel_roll_influence = 0.04
		w.wheel_friction_slip = 2.0
		w.use_as_traction = true
		w.use_as_steering = i < 2
		w.add_child(_wheel_look(WHEEL_AT[i].x > 0))
		add_child(w)
		wheels.append(w)
	shell = Node3D.new()
	add_child(shell)
	_build_shell()
	for i in 2:
		var d := _make_dust()
		d.position = Vector3(0.8 if i == 0 else -0.8, 0.12, -1.5)
		add_child(d)
		dust.append(d)
	engine = AudioStreamPlayer.new()
	engine.stream = _engine_stream()
	engine.volume_db = -60.0
	add_child(engine)
	skid = AudioStreamPlayer.new()
	skid.stream = _noise_stream()
	skid.volume_db = -60.0
	add_child(skid)

var _hat: Node3D

## A Santa hat on the roof for the Christmas theme.
func set_hat(on: bool) -> void:
	if _hat == null and on:
		_hat = Node3D.new()
		_hat.position = Vector3(0, 1.36, -0.2)
		for part in [[0.46, 0.5, 0.16, Color("f6f3ee"), 0.08, 0.0], [0.05, 0.42, 0.7, Color("d42a2a"), 0.5, 0.0], [0.14, 0.14, 0.24, Color("f6f3ee"), 0.92, 0.0]]:
			var mi := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = part[0]; cm.bottom_radius = part[1]; cm.height = part[2]; cm.radial_segments = 10; cm.rings = 1
			mi.mesh = cm
			var m := StandardMaterial3D.new()
			m.albedo_color = part[3]
			mi.material_override = m
			mi.position.y = part[4]
			_hat.add_child(mi)
		shell.add_child(_hat)
	if _hat != null:
		_hat.visible = on

func start_sound() -> void:
	if not engine.playing:
		engine.play()
		skid.play()

func _physics_process(dt: float) -> void:
	var p: Dictionary = PRESETS[preset]
	var b := global_transform.basis
	var v := linear_velocity
	speed = v.length()
	fwd_speed = v.dot(b.z)
	var side_speed := v.dot(b.x)
	slide = clampf(absf(side_speed) / maxf(speed, 4.0), 0.0, 1.0) if speed > 3.0 else 0.0

	# what is under the wheels
	grounded = 0
	var count := [0, 0, 0, 0, 0, 0]
	for i in 4:
		var w := wheels[i]
		var s := TARMAC
		if surface_fn.is_valid():
			var wp := w.global_position
			s = surface_fn.call(wp.x, wp.z)
		count[s] += 1
		if w.is_in_contact():
			grounded += 1
		var g: float = SURF[s].grip * p.grip
		if i >= 2:
			g *= p.rear
			if hand_in:
				g *= 0.34   # handbrake: the rear lets go so the car swings round
		w.wheel_friction_slip = g
	surface = TARMAC
	for si in 6:   # what most wheels stand on, the road on a tie
		if count[si] > count[surface]:
			surface = si
	var sf: Dictionary = SURF[surface]

	# steering: full lock when slow, a gentle hand at speed
	var lock := lerpf(0.58, 0.13, clampf(speed / 36.0, 0.0, 1.0))
	steering = move_toward(steering, -steer_in * lock, dt * (2.6 if absf(steer_in) > 0.05 else 3.6))

	# engine, brake and reverse
	var force := 0.0
	var brk := 0.0
	if gas_in > 0.01:
		if fwd_speed < -1.0:
			brk = BRAKE * gas_in
		else:
			var k := clampf(1.0 - pow(maxf(fwd_speed, 0.0) / float(sf.top), 2.0), 0.0, 1.0)
			force = POWER * p.power * gas_in * (0.35 + 0.65 * k) * (1.0 if k > 0.0 else 0.0)
	if brake_in > 0.01:
		if fwd_speed > 1.2:
			brk = BRAKE * brake_in
		else:
			var kr := clampf(1.0 - absf(fwd_speed) / 9.0, 0.0, 1.0)
			force = -POWER * 0.6 * brake_in * kr
	if gas_in < 0.01 and brake_in < 0.01 and speed < 0.6:
		brk = 6.0  # holds the car still on a slope
	for i in 4:
		wheels[i].engine_force = force
		wheels[i].brake = brk * (0.6 if i >= 2 else 1.0)
	if hand_in:
		wheels[2].brake = 60.0
		wheels[3].brake = 60.0
		wheels[0].engine_force *= 0.5
		wheels[1].engine_force *= 0.5
		wheels[2].engine_force = 0.0
		wheels[3].engine_force = 0.0

	# surface drag, air drag and a little downforce
	if speed > 0.1:
		apply_central_force(-v * (float(sf.drag) + 0.3 * speed) * (1.0 if grounded > 0 else 0.15))
	if true:
		# keeps the car off its roof, on the ground and in the air: a firm push back to level, stronger the further it tips
		apply_torque(b.z * b.x.y * -9000.0 + b.z * -angular_velocity.dot(b.z) * 1400.0)
	if grounded >= 2:
		apply_central_force(-b.y * speed * 22.0)
		# the helper: calms a spin when the driver is not asking for one
		var want := -steer_in * clampf(fwd_speed, -8.0, 30.0) * 0.045
		var yaw := angular_velocity.dot(b.y)
		var calm: float = p.assist * (0.25 if hand_in else 1.0)
		apply_torque(b.y * (want - yaw) * calm * 2600.0 * clampf(speed / 6.0, 0.0, 1.0))
	else:
		# in the air: stay level, land on the wheels
		apply_torque(b.x * -angular_velocity.dot(b.x) * 900.0 + b.z * -angular_velocity.dot(b.z) * 900.0)

	# on its roof or side for a while: ask for a gentle put-back
	if b.y.y < 0.35 and speed < 6.0:
		_flip_t += dt
		if _flip_t > 1.6:
			wants_reset = true
	else:
		_flip_t = 0.0

	# body lean (look only)
	var acc := (v - _last_v) / maxf(dt, 0.001)
	_last_v = v
	var want_lean := Vector2(clampf(acc.dot(b.x) * 0.006, -0.085, 0.085), clampf(-acc.dot(b.z) * 0.004, -0.05, 0.06))
	if grounded == 0:
		want_lean = Vector2.ZERO
	_lean = _lean.lerp(want_lean, clampf(dt * 6.0, 0.0, 1.0))
	shell.rotation = Vector3(_lean.y, 0, _lean.x)

	# dust and sound
	var kick := clampf((speed - 3.0) / 14.0, 0.0, 1.0) * (1.0 if surface != TARMAC else 0.0)
	kick = maxf(kick, slide * 0.9 if surface != TARMAC else 0.0)
	for i in 2:
		var d := dust[i]
		d.emitting = kick > 0.05 and wheels[2 + i].is_in_contact()
		d.color = Color(0.80, 0.72, 0.58, 0.55) if surface == GRAVEL else (Color(0.9, 0.72, 0.5, 0.55) if surface == SAND else (Color(0.96, 0.97, 1.0, 0.6) if surface >= SNOW else Color(0.62, 0.66, 0.46, 0.4)))
		d.initial_velocity_max = 1.5 + speed * 0.12
	if engine.playing:
		var gear_span := 11.5
		var gear := minf(floorf(maxf(fwd_speed, 0.0) / gear_span), 3.0)
		var rev := clampf((absf(fwd_speed) - gear * gear_span) / gear_span, 0.0, 1.3)
		engine.pitch_scale = lerpf(engine.pitch_scale, 0.62 + rev * 0.62 + gear * 0.07 + gas_in * 0.06, clampf(dt * 9.0, 0.0, 1.0))
		var vol := -17.0 + gas_in * 5.0 + clampf(speed / 30.0, 0.0, 1.0) * 2.0
		engine.volume_db = lerpf(engine.volume_db, vol if sound_on else -60.0, clampf(dt * 8.0, 0.0, 1.0))
		var sk := clampf(slide * 2.2 - 0.25, 0.0, 1.0) * clampf(speed / 8.0, 0.0, 1.0)
		if grounded < 2:
			sk = 0.0
		var roll := clampf(speed / 30.0, 0.0, 1.0) * (0.5 if surface != TARMAC else 0.12)
		var sv := lerpf(-60.0, -15.0 if surface != TARMAC else -20.0, clampf(maxf(sk, roll), 0.0, 1.0))
		skid.volume_db = lerpf(skid.volume_db, sv if sound_on else -60.0, clampf(dt * 10.0, 0.0, 1.0))
		skid.pitch_scale = 0.7 + clampf(speed / 40.0, 0.0, 1.0) * 0.6

## Sets the car down, level and still.
func place(pos: Vector3, yaw: float) -> void:
	var t := Transform3D(Basis(Vector3.UP, yaw), pos)
	global_transform = t
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, t)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	steering = 0.0
	_last_v = Vector3.ZERO
	_flip_t = 0.0
	wants_reset = false

# ---------- look ----------

func _mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.75
	return m

## A six-sided block from 8 corners: bottom ring then top ring, each going round the same way.
func _hex(st: SurfaceTool, c: Array, col: Color) -> void:
	var quads := [[0, 1, 2, 3], [7, 6, 5, 4], [0, 4, 5, 1], [1, 5, 6, 2], [2, 6, 7, 3], [3, 7, 4, 0]]
	var mid := Vector3.ZERO
	for p in c:
		mid += p
	mid /= 8.0
	for q in quads:
		var a: Vector3 = c[q[0]]; var b2: Vector3 = c[q[1]]; var c2: Vector3 = c[q[2]]; var d: Vector3 = c[q[3]]
		var n := (b2 - a).cross(c2 - a)
		var out := ((a + c2) * 0.5 - mid).dot(n) < 0.0   # Godot front faces wind clockwise
		var tris := [a, b2, c2, a, c2, d] if out else [a, c2, b2, a, d, c2]
		for p in tris:
			st.set_color(col)
			st.add_vertex(p)

## Block between two z values with its own half-width and height at each end.
func _slab(st: SurfaceTool, z0: float, z1: float, w0: float, w1: float, y0a: float, y1a: float, y0b: float, y1b: float, col: Color) -> void:
	_hex(st, [Vector3(-w0, y0a, z0), Vector3(w0, y0a, z0), Vector3(w1, y0b, z1), Vector3(-w1, y0b, z1),
		Vector3(-w0, y1a, z0), Vector3(w0, y1a, z0), Vector3(w1, y1b, z1), Vector3(-w1, y1b, z1)], col)

func _build_shell() -> void:
	var paint := Color("d9452b")
	var paint2 := Color("b83a24")
	var cream := Color("f1e6cf")
	var glass := Color("26323d")
	var dark := Color("23252a")
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	# lower body: boot, doors, bonnet and nose
	_slab(st, -1.92, -1.2, 0.80, 0.85, 0.36, 0.86, 0.30, 0.90, paint)
	_slab(st, -1.2, 0.75, 0.85, 0.85, 0.30, 0.90, 0.30, 0.88, paint)
	_slab(st, 0.75, 1.72, 0.85, 0.80, 0.30, 0.88, 0.34, 0.78, paint)
	_slab(st, 1.72, 1.95, 0.80, 0.74, 0.36, 0.76, 0.40, 0.66, paint2)
	# cabin glass and roof
	_slab(st, -1.22, -0.72, 0.74, 0.66, 0.88, 0.90, 0.88, 1.30, glass)
	_slab(st, -0.72, 0.30, 0.66, 0.66, 0.88, 1.30, 0.88, 1.30, glass)
	_slab(st, 0.30, 0.86, 0.66, 0.76, 0.88, 1.30, 0.88, 0.90, glass)
	_slab(st, -0.80, 0.36, 0.68, 0.68, 1.30, 1.35, 1.30, 1.35, paint)
	# pillars
	for sx in [-1.0, 1.0]:
		_hex(st, [Vector3(sx * 0.63, 0.88, -0.20), Vector3(sx * 0.80, 0.88, -0.20), Vector3(sx * 0.80, 0.88, -0.08), Vector3(sx * 0.63, 0.88, -0.08),
			Vector3(sx * 0.63, 1.31, -0.20), Vector3(sx * 0.69, 1.31, -0.20), Vector3(sx * 0.69, 1.31, -0.08), Vector3(sx * 0.63, 1.31, -0.08)], paint)
	# cream stripe over bonnet and roof, bumpers, wing, lights, mud flaps
	_slab(st, 0.76, 1.72, 0.22, 0.22, 0.885, 0.895, 0.785, 0.795, cream)
	_slab(st, -0.78, 0.34, 0.22, 0.22, 1.35, 1.362, 1.35, 1.362, cream)
	_slab(st, -1.90, -1.22, 0.22, 0.22, 0.865, 0.875, 0.905, 0.915, cream)
	_slab(st, 1.93, 2.02, 0.80, 0.78, 0.30, 0.46, 0.32, 0.44, dark)
	_slab(st, -2.0, -1.90, 0.80, 0.82, 0.32, 0.48, 0.30, 0.50, dark)
	_slab(st, -1.98, -1.62, 0.80, 0.80, 1.04, 1.07, 1.02, 1.05, dark)
	st.generate_normals()
	var m := st.commit()
	var body := MeshInstance3D.new()
	body.mesh = m
	body.material_override = _mat()
	shell.add_child(body)
	# small parts as boxes
	_boxp(Vector3(0.56, 0.62, 1.94), Vector3(0.30, 0.13, 0.05), Color("ffe9a8"), true)
	_boxp(Vector3(-0.56, 0.62, 1.94), Vector3(0.30, 0.13, 0.05), Color("ffe9a8"), true)
	_boxp(Vector3(0.58, 0.70, -1.93), Vector3(0.34, 0.12, 0.05), Color("d92a2a"), true)
	_boxp(Vector3(-0.58, 0.70, -1.93), Vector3(0.34, 0.12, 0.05), Color("d92a2a"), true)
	for x in [-0.33, -0.11, 0.11, 0.33]:   # rally lamp pod
		_boxp(Vector3(x, 0.60, 2.05), Vector3(0.17, 0.17, 0.08), Color("fff4c9"), true)
		_boxp(Vector3(x, 0.60, 2.0), Vector3(0.20, 0.20, 0.06), dark, false)
	for sx in [-1.0, 1.0]:
		_boxp(Vector3(sx * 0.66, 0.92, -1.80), Vector3(0.05, 0.22, 0.14), dark, false)   # wing posts
		_boxp(Vector3(sx * 0.82, 0.22, -1.72), Vector3(0.04, 0.26, 0.30), Color("c23b25"), false)   # mud flaps
		_boxp(Vector3(sx * 0.82, 0.22, 0.82), Vector3(0.04, 0.22, 0.26), Color("c23b25"), false)
		_boxp(Vector3(sx * 0.86, 0.60, 0.0), Vector3(0.02, 0.34, 0.5), cream, false)   # door number plate
		_boxp(Vector3(sx * 0.90, 0.96, 0.62), Vector3(0.12, 0.08, 0.06), dark, false)   # mirrors

func _boxp(pos: Vector3, size: Vector3, col: Color, glow: bool) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.7
	if glow:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 0.55
	mi.material_override = m
	mi.position = pos
	shell.add_child(mi)

func _wheel_look(right: bool) -> Node3D:
	var n := Node3D.new()
	var tyre := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.33; cm.bottom_radius = 0.33; cm.height = 0.24; cm.radial_segments = 14; cm.rings = 1
	tyre.mesh = cm
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color("1d1e21"); tm.roughness = 0.95
	tyre.material_override = tm
	tyre.rotation.z = PI / 2
	n.add_child(tyre)
	var hub := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.2; hm.bottom_radius = 0.2; hm.height = 0.26; hm.radial_segments = 6; hm.rings = 1
	hub.mesh = hm
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color("efe9da"); hmat.roughness = 0.6
	hub.material_override = hmat
	hub.rotation.z = PI / 2
	hub.position.x = 0.01 if right else -0.01
	n.add_child(hub)
	return n

func _make_dust() -> CPUParticles3D:
	var d := CPUParticles3D.new()
	d.amount = 26
	d.lifetime = 1.3
	d.local_coords = false
	d.emitting = false
	d.direction = Vector3(0, 1, -0.4)
	d.spread = 28.0
	d.gravity = Vector3(0, 0.5, 0)
	d.initial_velocity_min = 0.8
	d.initial_velocity_max = 2.5
	d.scale_amount_min = 0.5
	d.scale_amount_max = 1.1
	var cv := Curve.new()
	cv.add_point(Vector2(0, 0.35)); cv.add_point(Vector2(1, 1.0))
	d.scale_amount_curve = cv
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 1, 1, 1)); gr.set_color(1, Color(1, 1, 1, 0))
	d.color_ramp = gr
	var sm := SphereMesh.new()
	sm.radius = 0.55; sm.height = 0.9; sm.radial_segments = 6; sm.rings = 3
	d.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	d.material_override = m
	return d

# ---------- sound, made in code ----------

func _engine_stream() -> AudioStreamWAV:
	var rate := 22050
	var n := rate  # one second, a whole number of cycles of every part
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in n:
		var t := float(i) / rate
		var s := 0.0
		s += 0.50 * sin(TAU * 62.0 * t)
		s += 0.30 * sin(TAU * 124.0 * t + 0.6)
		s += 0.16 * sin(TAU * 186.0 * t + 1.1)
		s += 0.10 * sin(TAU * 31.0 * t)
		s += 0.08 * signf(sin(TAU * 62.0 * t)) * (0.5 + 0.5 * sin(TAU * 4.0 * t))
		s += rng.randf_range(-0.03, 0.03)
		data.encode_s16(i * 2, int(clampf(s * 0.8, -1.0, 1.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_end = n
	w.data = data
	return w

func _noise_stream() -> AudioStreamWAV:
	var rate := 22050
	var n := rate * 2
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var lp := 0.0
	for i in n:
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.22)
		var edge := minf(float(i), float(n - i)) / 800.0   # soft join at the loop point
		data.encode_s16(i * 2, int(clampf(lp * 1.6 * clampf(edge, 0.0, 1.0), -1.0, 1.0) * 26000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_end = n
	w.data = data
	return w
