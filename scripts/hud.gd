extends Control
## Speed readout, the few buttons, the title card and the touch controls.
## Touch: drag anywhere on the left half to steer. Gas, brake and handbrake sit on the right.

signal start_pressed
signal reset_pressed
signal cam_pressed
signal preset_pressed
signal sound_pressed

var touch_on := false      # set once a finger touches the screen
var touch_steer := 0.0
var touch_gas := 0.0
var touch_brake := 0.0
var touch_hand := false
var _touches := {}         # finger index -> {"role": String, "start": Vector2, "pos": Vector2}
var _title: Control
var _speed: Label
var _unit: Label
var _surf: Label
var _preset_btn: Button
var _sound_btn: Button
var _full_btn: Button
var _bar: HBoxContainer
var _live := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var th := Theme.new()
	th.default_font_size = 20
	theme = th

	_speed = _label("0", 54, Color("fffaf0"))
	_speed.position = Vector2(26, 12)
	add_child(_speed)
	_unit = _label("mph", 20, Color("fffaf0"))
	add_child(_unit)
	_surf = _label("", 20, Color("fffaf0"))
	_surf.position = Vector2(28, 78)
	add_child(_surf)

	_bar = HBoxContainer.new()
	_bar.add_theme_constant_override("separation", 8)
	add_child(_bar)
	_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_bar.offset_right = -16
	_bar.offset_top = 14
	_btn("Reset", func(): reset_pressed.emit())
	_btn("Camera", func(): cam_pressed.emit())
	_preset_btn = _btn("Handling", func(): preset_pressed.emit())
	_sound_btn = _btn("Sound: on", func(): sound_pressed.emit())
	_full_btn = _btn("Full screen", _toggle_full)
	_bar.visible = false

	_title = ColorRect.new()
	_title.color = Color(0.11, 0.14, 0.17, 0.72)
	add_child(_title)
	_title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	_title.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	box.add_child(_centered("The Scenic Route", 64, Color("f6e7c8")))
	box.add_child(_centered("car feel test v0.1.1", 20, Color("c9d6d6")))
	box.add_child(_centered(" ", 8, Color.WHITE))
	box.add_child(_centered("No races. No timers. No damage. Drive anywhere.", 22, Color("fffaf0")))
	box.add_child(_centered(" ", 8, Color.WHITE))
	box.add_child(_centered("Keyboard: arrows or WASD drive  ·  Space handbrake  ·  R reset  ·  C camera  ·  H handling", 18, Color("dfe8e6")))
	box.add_child(_centered("Controller: left stick steer  ·  RT gas  ·  LT brake  ·  A handbrake  ·  Y reset  ·  X camera", 18, Color("dfe8e6")))
	box.add_child(_centered("Touch: drag on the left half to steer  ·  buttons on the right", 18, Color("dfe8e6")))
	box.add_child(_centered(" ", 8, Color.WHITE))
	var go := Button.new()
	go.text = "   Start driving   "
	go.add_theme_font_size_override("font_size", 28)
	go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	go.focus_mode = Control.FOCUS_NONE
	go.pressed.connect(func(): start_pressed.emit())
	box.add_child(go)

func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.12, 0.14, 0.75))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _centered(text: String, size: int, col: Color) -> Label:
	var l := _label(text, size, col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func _btn(text: String, fn: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 44)
	b.pressed.connect(fn)
	_bar.add_child(b)
	return b

func _toggle_full() -> void:
	var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)

func hide_title() -> void:
	_title.visible = false
	_bar.visible = true
	_live = true

func set_preset(n: String) -> void:
	_preset_btn.text = "Handling: " + n

func set_sound(on: bool) -> void:
	_sound_btn.text = "Sound: on" if on else "Sound: off"

func set_speed(mph: float, surface: String) -> void:
	_speed.text = str(int(round(mph)))
	_unit.position = Vector2(_speed.position.x + _speed.get_minimum_size().x + 8, 44)
	_surf.text = surface

# ---------- touch ----------

func _gas_at() -> Vector2:
	return Vector2(size.x - 120, size.y - 125)

func _brake_at() -> Vector2:
	return Vector2(size.x - 300, size.y - 105)

func _hand_at() -> Vector2:
	return Vector2(size.x - 150, size.y - 300)

func _role_at(p: Vector2) -> String:
	if p.distance_to(_gas_at()) < 95.0:
		return "gas"
	if p.distance_to(_brake_at()) < 82.0:
		return "brake"
	if p.distance_to(_hand_at()) < 68.0:
		return "hand"
	if p.x < size.x * 0.5 and p.y > 90.0:
		return "steer"
	return ""

func _input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if not touch_on:
			touch_on = true
		if e.pressed:
			if _live:
				_touches[e.index] = {"role": _role_at(e.position), "start": e.position, "pos": e.position}
		else:
			_touches.erase(e.index)
		_sum()
	elif e is InputEventScreenDrag and _touches.has(e.index):
		var t: Dictionary = _touches[e.index]
		t.pos = e.position
		if t.role != "steer":
			t.role = _role_at(e.position) if _role_at(e.position) != "steer" else ""
		_sum()

func _sum() -> void:
	touch_steer = 0.0; touch_gas = 0.0; touch_brake = 0.0; touch_hand = false
	for i in _touches:
		var t: Dictionary = _touches[i]
		match t.role:
			"steer":
				touch_steer = clampf((t.pos.x - t.start.x) / maxf(size.y * 0.17, 60.0), -1.0, 1.0)
			"gas":
				touch_gas = 1.0
			"brake":
				touch_brake = 1.0
			"hand":
				touch_hand = true
	queue_redraw()

func _draw() -> void:
	if not (touch_on and _live):
		return
	var font := get_theme_default_font()
	var pale := Color(1, 0.98, 0.94, 0.30)
	var lit := Color(1, 0.98, 0.94, 0.62)
	_pad(_gas_at(), 86.0, "GAS", touch_gas > 0.0, Color(0.55, 0.85, 0.5, 0.5), font)
	_pad(_brake_at(), 72.0, "BRAKE", touch_brake > 0.0, Color(0.95, 0.5, 0.42, 0.5), font)
	_pad(_hand_at(), 58.0, "HAND", touch_hand, Color(0.98, 0.84, 0.45, 0.5), font)
	var steering := false
	for i in _touches:
		var t: Dictionary = _touches[i]
		if t.role == "steer":
			steering = true
			var reach := maxf(size.y * 0.17, 60.0)
			draw_arc(t.start, reach, 0, TAU, 40, pale, 4.0, true)
			draw_circle(Vector2(t.start.x + touch_steer * reach, t.start.y), 34.0, lit)
	if not steering:
		var c := Vector2(170, size.y - 130)
		draw_arc(c, 70.0, 0, TAU, 40, pale, 4.0, true)
		draw_string(font, c + Vector2(-60, 8), "‹ STEER ›", HORIZONTAL_ALIGNMENT_CENTER, 120, 20, lit)

func _pad(c: Vector2, r: float, text: String, on: bool, col: Color, font: Font) -> void:
	draw_circle(c, r, Color(col.r, col.g, col.b, 0.62 if on else 0.3))
	draw_arc(c, r, 0, TAU, 40, Color(1, 1, 1, 0.5), 3.0, true)
	draw_string(font, c + Vector2(-r, 7), text, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 20, Color(1, 1, 1, 0.9))
