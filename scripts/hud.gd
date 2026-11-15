extends Control

const TestBridge := preload("res://addons/bc_common/test_bridge.gd")
## Speed readout, the few buttons, the title card and the touch controls.
## Touch: drag anywhere on the left half to steer. Gas, brake and handbrake sit on the right.

signal start_pressed
signal reset_pressed
signal cam_pressed
signal preset_pressed
signal sound_pressed
signal auto_pressed
signal music_pressed
signal xmas_pressed
signal journal_pressed

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
var _auto_btn: Button
var _music_btn: Button
var _xmas_btn: Button
var _finds: Label
var _letters: Array[Label] = []
var _msg: Label
var _lap: Label
var _msg_t := 0.0
var _journal: Control
var journal_open := false
var _full_btn: Button
var _bar: HFlowContainer
var _menu_btn: Button
var _live := false
var _safe: Array[float] = [0.0, 0.0, 0.0, 0.0]   # left, top, right, bottom margins that keep the HUD clear of notches and rounded corners

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

	_bar = HFlowContainer.new()   # wraps onto a second row on narrow screens
	_bar.add_theme_constant_override("h_separation", 8)
	_bar.add_theme_constant_override("v_separation", 8)
	_bar.alignment = FlowContainer.ALIGNMENT_END
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar)
	_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_bar.offset_left = 190
	_bar.offset_right = -118   # room for the Menu button
	_bar.offset_top = 14
	_auto_btn = _btn("Auto drive: off", func(): auto_pressed.emit())
	_btn("Reset", func(): reset_pressed.emit())
	_btn("Camera", func(): cam_pressed.emit())
	_preset_btn = _btn("Handling", func(): preset_pressed.emit())
	_btn("Journal", func(): journal_pressed.emit())
	_sound_btn = _btn("Sound: on", func(): sound_pressed.emit())
	_music_btn = _btn("Music: on", func(): music_pressed.emit())
	_xmas_btn = _btn("Christmas: off", func(): xmas_pressed.emit())
	_full_btn = _btn("Full screen", _toggle_full)
	_bar.visible = false
	# one Menu button, top right. It opens the row of options across the top.
	_menu_btn = Button.new()
	_menu_btn.text = "  Menu  "
	_menu_btn.focus_mode = Control.FOCUS_NONE
	_menu_btn.custom_minimum_size = Vector2(92, 48)
	_menu_btn.pressed.connect(toggle_menu)
	add_child(_menu_btn)
	_menu_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_menu_btn.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_menu_btn.offset_right = -16
	_menu_btn.offset_top = 14
	_menu_btn.visible = false

	# the six letters and the count, top centre
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.grow_vertical = Control.GROW_DIRECTION_BEGIN
	top.offset_bottom = -14
	for ch in "SCENIC":
		var l := _label(ch, 30, Color(1, 1, 1, 0.28))
		top.add_child(l)
		_letters.append(l)
	_finds = _label("", 22, Color("fffaf0"))
	top.add_child(_finds)

	# messages sit a third of the way down, near the car
	_msg = _label("", 30, Color("fff3cf"))
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_msg)
	_msg.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_msg.anchor_top = 0.27
	_msg.anchor_bottom = 0.27
	_msg.offset_left = 40
	_msg.offset_right = -40
	_msg.modulate.a = 0.0

	# the lap clock, only while a circuit lap is running
	_lap = _label("", 26, Color("fffaf0"))
	_lap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_lap)
	_lap.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_lap.offset_top = 112

	_title = ColorRect.new()
	_title.color = Color(0.11, 0.14, 0.17, 0.72)
	add_child(_title)
	_title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fit_safe()
	get_viewport().size_changed.connect(_fit_safe)
	var box := VBoxContainer.new()
	_title.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	box.add_child(_centered("The Scenic Route", 64, Color("f6e7c8")))
	box.add_child(_centered("v0.5.2  ·  six biomes  ·  198 things to find", 20, Color("c9d6d6")))
	box.add_child(_centered(" ", 8, Color.WHITE))
	box.add_child(_centered("No opponents. No damage. No way to lose. Find the letters S-C-E-N-I-C, hit a ramp or time a lap.", 22, Color("fffaf0")))
	box.add_child(_centered(" ", 8, Color.WHITE))
	box.add_child(_centered("Keyboard: arrows or WASD drive  ·  Space drift (handbrake)  ·  R reset  ·  C camera  ·  H handling  ·  G auto drive  ·  J journal  ·  M music  ·  X Christmas  ·  Esc menu", 18, Color("dfe8e6")))
	box.add_child(_centered("Controller: left stick steer  ·  RT gas  ·  LT brake  ·  A drift (handbrake)  ·  Y reset  ·  X camera  ·  B auto drive", 18, Color("dfe8e6")))
	box.add_child(_centered("Touch: drag on the left half to steer  ·  buttons on the right", 18, Color("dfe8e6")))
	box.add_child(_centered("Auto drive: the car works the pedals. You only steer. Brake still works.", 18, Color("f6e7c8")))
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
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _btn(text: String, fn: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 48)
	b.pressed.connect(fn)
	_bar.add_child(b)
	return b

func _toggle_full() -> void:
	var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)

## Keeps the HUD inside the screen's safe area: clear of camera notches, rounded corners and gesture bars.
func _fit_safe() -> void:
	var m: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var win := Vector2(DisplayServer.window_get_size())
	var view := get_viewport_rect().size
	if OS.has_feature("mobile") and win.x > 0.0 and win.y > 0.0:
		var sa := DisplayServer.get_display_safe_area()
		if sa.size.x > 0 and sa.size.y > 0:
			var k := view.x / win.x
			m = [sa.position.x * k, sa.position.y * k, (win.x - sa.end.x) * k, (win.y - sa.end.y) * k]
	if TestBridge.has_flag("test") and TestBridge.has_flag("safe"):   # browser test switch, only with ?test (G7.8): pretend the screen has a notch
		m = [70.0, 30.0, 70.0, 24.0]
	for i in 4:
		m[i] = clampf(m[i], 0.0, (view.x if i % 2 == 0 else view.y) * 0.12)
	_safe = m
	offset_left = m[0]; offset_top = m[1]; offset_right = -m[2]; offset_bottom = -m[3]
	for full: Control in [_title, _journal]:   # full screen panels still cover the whole screen
		if full != null:
			full.offset_left = -m[0]; full.offset_top = -m[1]; full.offset_right = m[2]; full.offset_bottom = m[3]
	queue_redraw()

## True when the menu or the journal is open. The Android back button closes them.
func back() -> void:
	if journal_open:
		journal_pressed.emit()
	else:
		toggle_menu()

func toggle_menu() -> void:
	if not _live:
		return
	_bar.visible = not _bar.visible
	_menu_btn.text = "  Close  " if _bar.visible else "  Menu  "

func hide_title() -> void:
	_title.visible = false
	_menu_btn.visible = true
	_live = true

func set_preset(n: String) -> void:
	_preset_btn.text = "Handling: " + n

func set_auto(on: bool) -> void:
	_auto_btn.text = "Auto drive: on" if on else "Auto drive: off"

func set_lap(text: String) -> void:
	if _lap.text != text:
		_lap.text = text

func set_xmas(on: bool) -> void:
	_xmas_btn.text = "Christmas: on" if on else "Christmas: off"

func set_music(on: bool) -> void:
	_music_btn.text = "Music: on" if on else "Music: off"

func set_finds(n: int, total: int, letters: Array) -> void:
	_finds.text = "   %d / %d" % [n, total]
	for i in mini(letters.size(), _letters.size()):
		_letters[i].add_theme_color_override("font_color", Color("ffcf4a") if letters[i] else Color(1, 1, 1, 0.28))

## A short line a third of the way down the screen. It fades by itself.
func message(text: String) -> void:
	_msg.text = text
	_msg_t = 2.6

func _process(dt: float) -> void:
	if _msg_t > 0.0:
		_msg_t -= dt
	_msg.modulate.a = move_toward(_msg.modulate.a, 1.0 if _msg_t > 0.0 else 0.0, dt * 3.0)

## The journal: every find as a grid. Found ones show their picture, the rest stay as shadows.
func toggle_journal(finds: Array, records: String = "") -> void:
	if not _live:
		return
	if _journal != null:
		_journal.queue_free()
		_journal = null
		journal_open = false
		return
	journal_open = true
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.13, 0.16, 0.9)
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_journal = bg
	bg.offset_left = -_safe[0]; bg.offset_top = -_safe[1]; bg.offset_right = _safe[2]; bg.offset_bottom = _safe[3]
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	bg.add_child(col)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 24)
	col.offset_left += _safe[0]; col.offset_top += _safe[1]; col.offset_right -= _safe[2]; col.offset_bottom -= _safe[3]
	var n := 0
	for fd in finds:
		if fd.found:
			n += 1
	var head := HBoxContainer.new()
	col.add_child(head)
	var title := _label("Journal   ·   %d of %d found" % [n, finds.size()], 30, Color("f6e7c8"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "  Close  "
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(0, 48)
	close.pressed.connect(func(): toggle_journal([]))
	head.add_child(close)
	var word := ""
	for fd in finds:
		if fd.kind == "letter":
			word += ("SCENIC"[fd.k] if fd.found else "_") + " "
	col.add_child(_label("Letters:  " + word, 26, Color("ffcf4a")))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var grid := HFlowContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	var inner := VBoxContainer.new()   # records and pictures scroll together, and long lines wrap, so nothing runs off the screen
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 12)
	scroll.add_child(inner)
	var rec := _label(records, 20, Color("dfe8e6"))
	rec.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(rec)
	inner.add_child(grid)
	for fd in finds:
		if fd.kind != "item":
			continue
		var tr := TextureRect.new()
		tr.texture = load("res://icons/%s.png" % fd.id)
		tr.custom_minimum_size = Vector2(72, 72)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.tooltip_text = fd.name if fd.found else "Not found yet"
		if not fd.found:
			tr.modulate = Color(0, 0, 0, 0.35)
		grid.add_child(tr)

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
	if p.distance_squared_to(_gas_at()) < 95.0 * 95.0:
		return "gas"
	if p.distance_squared_to(_brake_at()) < 82.0 * 82.0:
		return "brake"
	if p.distance_squared_to(_hand_at()) < 68.0 * 68.0:
		return "hand"
	if p.x < size.x * 0.5 and p.y > 90.0:
		return "steer"
	return ""

func _input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		var at: Vector2 = e.position - position   # the HUD sits inside the safe area
		if not touch_on:
			touch_on = true
		if e.pressed:
			if _live:
				_touches[e.index] = {"role": _role_at(at), "start": at, "pos": at}
		else:
			_touches.erase(e.index)
		_sum()
	elif e is InputEventScreenDrag and _touches.has(e.index):
		var t: Dictionary = _touches[e.index]
		var at2: Vector2 = e.position - position
		t.pos = at2
		if t.role != "steer":
			t.role = _role_at(at2) if _role_at(at2) != "steer" else ""
		_sum()
	elif touch_on and ((e is InputEventKey and e.pressed) or (e is InputEventJoypadButton and e.pressed) or (e is InputEventJoypadMotion and absf(e.axis_value) > 0.5)):
		# a keyboard or gamepad took over: put the touch pads away until a finger comes back
		touch_on = false
		_touches.clear()
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
	_pad(_hand_at(), 58.0, "DRIFT", touch_hand, Color(0.98, 0.84, 0.45, 0.5), font)
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
