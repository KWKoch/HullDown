class_name Hud
extends CanvasLayer
## Grouped, colour-coded heads-up display plus the on-screen controls (shared by touch and
## mouse). Each data family has its own colour so the eye can go straight to it:
##   NAVIGATION  teal    |  ENGINEERING  amber  |  WEAPONS  red  |  DAMAGE CONTROL  blue
## Values use one status scale everywhere: green = good, amber = degraded, red = critical.

signal camera_pressed
signal fire_changed(held: bool)
signal scope_changed(on: bool)

const C_NAV := Color(0.30, 0.82, 0.86)
const C_ENG := Color(1.00, 0.72, 0.22)
const C_WEP := Color(1.00, 0.36, 0.32)
const C_DMG := Color(0.42, 0.62, 1.00)
const C_GOOD := Color(0.45, 0.88, 0.50)
const C_WARN := Color(1.00, 0.78, 0.25)
const C_BAD := Color(1.00, 0.30, 0.28)
const C_DIM := Color(0.62, 0.68, 0.72)
const C_TEXT := Color(0.94, 0.96, 0.97)
const C_PANEL := Color(0.04, 0.06, 0.09, 0.72)

var camera: Camera3D
var sensors: SensorNet
var _plates: Control
var _mini: MapView
var _big: MapView
var _span_idx := 1
const MINI_SPANS := [3000.0, 6000.0, 10000.0, 14000.0]
var _reticle: Control
var _aim_text := ""
var _aim_color := Color.WHITE
var _aim_screen_ok := false
var ship: Ship
var gunnery: Gunnery
var controls: PlayerControls
var terrain: Node
var ground_name := ""
var opponents_total := 30
var camera_mode_name := "CHASE"

var _values: Dictionary = {}          ## key -> Label
var _ui_controls: Array[Control] = []
var _telegraph: DetentGauge
var _helm: DetentGauge
var _fire_button: Button
var _dc_seen := 0
var _cam_button: Button
var _compass: Control
var _profile: ShipProfile
var _alert_box: VBoxContainer
var _log_box: VBoxContainer
var _log: Array = []                  ## [text, color, age]
var _fire_state: Dictionary = {}      ## compartment id -> bool, for edge-detecting events
var _flood_state: Dictionary = {}
var _t := 0.0
var _last_aim := Vector3.ZERO

## Layout mode. Portrait phones get a tall control deck under the view; touch devices get larger
## gauges and buttons, and a fixed centre reticle that the player swings by dragging.
var portrait := false
var touch := false
var scope_on := false
var _fk := 1.0                        ## font scale
var _pk := 1.0                        ## nameplate / reticle scale
var _compass_sc := 1.0
var _reticle_c := Vector2(960, 540)
var _mouse_aiming := true
var _strip: PanelContainer
var _prop_tag: Control
var _steer_tag: Control
var _scope_button: Button
var _map_button: Button
var _zin: Button
var _zout: Button
var _covered: Array[Rect2] = []
var _ptr: Dictionary = {}             ## pointer index -> Control it is holding


func setup(p_ship: Ship, p_gun: Gunnery, p_controls: PlayerControls, p_terrain: Node, p_ground: String, p_opponents: int) -> void:
	ship = p_ship
	gunnery = p_gun
	controls = p_controls
	terrain = p_terrain
	ground_name = p_ground
	opponents_total = p_opponents
	layer = 10
	_decide_mode()
	_build()
	get_viewport().size_changed.connect(_on_size_changed)
	ship.compartment_destroyed.connect(_on_destroyed)
	ship.magazine_detonated.connect(func(_s: Ship, c: Compartment) -> void: _event("MAGAZINE DETONATED: " + c.id, C_BAD))
	ship.ship_sunk.connect(func(_s: Ship) -> void: _event("SHIP LOST", C_BAD))
	_event("General Quarters. Ship cleared for action.", C_DIM)


# --- Layout mode ----------------------------------------------------------------------

func _decide_mode() -> void:
	var win := get_window()
	var ws := Vector2(win.size)
	touch = DisplayServer.is_touchscreen_available() or OS.get_cmdline_user_args().has("--touchui")
	portrait = ws.y > ws.x * 1.05
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	win.content_scale_size = Vector2i(1080, 1920) if portrait else Vector2i(1920, 1080)
	_fk = 1.6 if portrait else (1.25 if touch else 1.0)
	_pk = 1.5 if portrait else (1.2 if touch else 1.0)
	_compass_sc = 1.5 if portrait else 1.0


func _exit_tree() -> void:
	var win := get_window()
	if win != null:
		win.content_scale_size = Vector2i(1920, 1080)
		win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP


func _on_size_changed() -> void:
	var ws := Vector2(get_window().size)
	if (ws.y > ws.x * 1.05) != portrait:
		_rebuild.call_deferred()
	else:
		_layout.call_deferred()


func _rebuild() -> void:
	_decide_mode()
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_ui_controls.clear()
	_values.clear()
	_ptr.clear()
	_build()


## Where the aim reticle sits on screen (canvas coordinates): the middle of the clear part of the view.
func reticle_center() -> Vector2:
	return _reticle_c


# --- Construction ---------------------------------------------------------------------

func _style(accent: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_PANEL
	sb.border_color = accent
	sb.border_width_left = 4
	sb.corner_radius_top_left = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_right = 4
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", roundi(size * _fk))
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## A titled panel in a group colour; returns the VBox rows go into.
func _panel(title: String, accent: Color, anchor: Control.LayoutPreset, offset: Vector2, width: float) -> VBoxContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _style(accent))
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pc)
	pc.set_anchors_and_offsets_preset(anchor, Control.PRESET_MODE_MINSIZE)
	pc.custom_minimum_size = Vector2(width, 0)
	pc.position += offset
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(vb)
	vb.add_child(_label(title, 14, accent))
	var sep := HSeparator.new()
	sep.modulate = Color(accent.r, accent.g, accent.b, 0.5)
	vb.add_child(sep)
	return vb


func _row(box: VBoxContainer, key: String, caption: String, accent: Color) -> void:
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var k := _label(caption, 14, C_DIM)
	k.custom_minimum_size = Vector2(112, 0)
	h.add_child(k)
	var v := _label("-", 18, C_TEXT)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	box.add_child(h)
	_values[key] = v


## A small status tag (e.g. "PROP 100%") that sits above a control gauge; returns its value label.
func _gauge_tag(pos: Vector2, width: float, caption: String) -> Label:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _style(C_ENG))
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pc)
	pc.position = pos
	pc.custom_minimum_size = Vector2(width, 0)
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(h)
	var k := _label(caption, 12, C_DIM)
	h.add_child(k)
	var v := _label("-", 14, C_TEXT)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(v)
	return v


func _build() -> void:
	_plates = Control.new()
	_plates.set_anchors_preset(Control.PRESET_FULL_RECT)
	_plates.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plates.draw.connect(_draw_plates)
	add_child(_plates)
	_reticle = Control.new()
	_reticle.set_anchors_preset(Control.PRESET_FULL_RECT)
	_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reticle.draw.connect(_draw_reticle)
	add_child(_reticle)
	# Navigation strip, centred under the compass: speed, heading, rudder, water under the keel.
	var strip := PanelContainer.new()
	_strip = strip
	strip.add_theme_stylebox_override("panel", _style(C_NAV))
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(strip)
	strip.position = Vector2(960.0 - 360.0, 62)
	strip.custom_minimum_size = Vector2(720, 0)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(hb)
	for it in [["speed", "SPEED"], ["heading", "HDG"], ["rudder", "RUDDER"], ["steerage", "STEERAGE"], ["depth", "KEEL"], ["plat", "GUN PLATFORM"]]:
		var cell := VBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_constant_override("separation", 0)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cap := _label(it[1], 12, C_DIM)
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(cap)
		var val := _label("-", 18, C_TEXT)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(val)
		hb.add_child(cell)
		_values[it[0]] = val
	_values["dyn"] = _label("", 13, C_DIM)
	_values["dyn"].position = Vector2(960.0 - 360.0, 62 + 52)
	_values["dyn"].custom_minimum_size = Vector2(720, 0)
	_values["dyn"].horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_values["dyn"])
	# Damage readouts above the engine telegraph and the helm.
	_values["prop"] = _gauge_tag(Vector2(960.0 - 170.0, 1080.0 - 12.0 - 190.0 - 34.0), 100.0, "PROP")
	_values["steer"] = _gauge_tag(Vector2(960.0 - 170.0 + 110.0, 1080.0 - 12.0 - 68.0 - 34.0), 230.0, "STEER")
	_prop_tag = (_values["prop"] as Label).get_parent().get_parent() as Control
	_steer_tag = (_values["steer"] as Label).get_parent().get_parent() as Control

	# Own-ship condition: broadside profile, repair-party hats and two lines of figures (top right).
	_profile = ShipProfile.new()
	_profile.ship = ship
	_profile.clicked.connect(func() -> void: ship.dc.cycle_priority())
	add_child(_profile)
	_ui_controls.append(_profile)

	# Compass strip and alerts (top centre)
	_compass = Control.new()
	_compass.custom_minimum_size = Vector2(520, 44)
	_compass.size = Vector2(520, 44)
	_compass.position = Vector2(1920.0 * 0.5 - 260.0, 12)
	_compass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_compass.draw.connect(_draw_compass)
	add_child(_compass)
	_alert_box = VBoxContainer.new()
	_alert_box.position = Vector2(1920.0 * 0.5 - 230.0, 140)
	_alert_box.custom_minimum_size = Vector2(460, 0)
	_alert_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_alert_box)

	# Event log (bottom centre)
	_log_box = VBoxContainer.new()
	_log_box.position = Vector2(320.0, 1080.0 - 170.0)
	_log_box.custom_minimum_size = Vector2(440, 0)
	_log_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_log_box)

	_build_controls()
	_build_maps()
	_layout()


func _build_maps() -> void:
	var t := terrain as BattleTerrain
	_mini = MapView.new()
	_mini.size = Vector2(290, 290)
	_mini.position = Vector2(14, 1080.0 - 14.0 - 290.0)
	add_child(_mini)
	_mini.setup(t, sensors, ship, false)
	_mini.title = "TACTICAL   [M] expand"
	_mini.span_m = MINI_SPANS[_span_idx]
	_mini.clicked.connect(toggle_map)
	_mini.wheel.connect(func(d: int) -> void: _zoom_mini(-d))
	_ui_controls.append(_mini)
	_zin = _btn("+", Vector2(30, 30), Vector2(14 + 290 - 34, 1080.0 - 14.0 - 290.0 + 4), C_NAV)
	_zin.pressed.connect(func() -> void: _zoom_mini(-1))
	_zout = _btn("-", Vector2(30, 30), Vector2(14 + 290 - 68, 1080.0 - 14.0 - 290.0 + 4), C_NAV)
	_zout.pressed.connect(func() -> void: _zoom_mini(1))
	_big = MapView.new()
	_big.size = Vector2(830, 830)
	_big.position = Vector2(960.0 - 415.0, 36)
	add_child(_big)
	_big.setup(t, sensors, ship, true)
	_big.title = "TACTICAL MAP   [M] close"
	_big.visible = false
	_big.clicked.connect(toggle_map)
	_ui_controls.append(_big)


func _zoom_mini(step: int) -> void:
	_span_idx = clampi(_span_idx + step, 0, MINI_SPANS.size() - 1)
	_mini.span_m = MINI_SPANS[_span_idx]


func toggle_map() -> void:
	_big.visible = not _big.visible
	if _big.visible:
		MapView.ensure_texture(terrain as BattleTerrain, true)     # terrain may have been cratered since


## Compass bearing (0-359, clockwise from north) for a game heading. Game headings grow toward
## +X (to port), so a compass bearing is the negative.
static func bearing_deg(heading_rad: float) -> float:
	return fposmod(-rad_to_deg(heading_rad), 360.0)


func _btn(text: String, size: Vector2, pos: Vector2, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = size
	b.size = size
	b.position = pos
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", roundi(16 * _fk))
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE        # pointers are routed by _input so several fingers work at once
	b.add_theme_color_override("font_color", C_TEXT)
	_set_btn_colors(b, color, false)
	add_child(b)
	_ui_controls.append(b)
	return b


func _set_btn_colors(b: Button, color: Color, active: bool) -> void:
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(color.r, color.g, color.b, 0.95 if active else 0.26)
		sb.border_color = Color(color.r, color.g, color.b, 1.0 if active else 0.55)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(6)
		if st == "pressed":
			sb.bg_color = Color(color.r, color.g, color.b, 0.85)
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_color_override("font_color", Color(0.04, 0.05, 0.07) if active else C_TEXT)
	b.add_theme_color_override("font_pressed_color", C_TEXT)
	b.add_theme_color_override("font_hover_color", Color(0.04, 0.05, 0.07) if active else C_TEXT)


func _build_controls() -> void:
	# Engine order telegraph and helm: small brass gauges, centred along the bottom edge so they
	# sit in the periphery. Port is red and starboard green, as on the ship's navigation lights.
	var el: Array[String] = []
	var ec: Array[Color] = []
	for o in EngineTelegraph.ENGINE_ORDERS:
		el.append(String(o[0]).replace("AHEAD ", "").replace("ASTERN ", "").replace("ALL ASTERN", "ALL"))
		ec.append(C_GOOD if float(o[1]) > 0.0 else (C_DIM if float(o[1]) == 0.0 else C_BAD))
	_telegraph = DetentGauge.new()
	_telegraph.size = Vector2(100, 190)
	_telegraph.position = Vector2(960.0 - 170.0, 1080.0 - 12.0 - 190.0)
	add_child(_telegraph)
	_telegraph.setup("ENGINE  W/S", true, el, ec, controls.engine_ordered)
	_telegraph.picked.connect(func(i: int) -> void: controls.ring_engine(i))
	_ui_controls.append(_telegraph)
	var hl: Array[String] = ["HARD", "20", "10", "MID", "10", "20", "HARD"]
	var hc: Array[Color] = []
	for o in EngineTelegraph.HELM_ORDERS:
		hc.append(C_BAD if float(o[1]) > 0.0 else (C_DIM if float(o[1]) == 0.0 else C_GOOD))
	_helm = DetentGauge.new()
	_helm.size = Vector2(230, 68)
	_helm.position = Vector2(960.0 - 170.0 + 100.0 + 10.0, 1080.0 - 12.0 - 68.0)
	add_child(_helm)
	_helm.setup("HELM  A/D  X", false, hl, hc, controls.helm_ordered)
	_helm.picked.connect(func(i: int) -> void: controls.set_helm(i))
	_ui_controls.append(_helm)
	# Fire button: touch screens only (on a PC the left mouse button fires). Camera sits above it on
	# touch, and drops to the corner on PC.
	_fire_button = _btn("FIRE\nMAIN BATTERY", Vector2(190, 120), Vector2(1920.0 - 14.0 - 190.0, 1080.0 - 14.0 - 120.0), C_WEP)
	if not touch:
		_fire_button.visible = false
	_fire_button.add_theme_font_size_override("font_size", roundi(20 * (1.5 if portrait else 1.0) * (1.0 if portrait else _fk)))
	_fire_button.button_down.connect(func() -> void: fire_changed.emit(true))
	_fire_button.button_up.connect(func() -> void: fire_changed.emit(false))
	_cam_button = _btn("CAMERA: CHASE  [C]", Vector2(190, 50), Vector2(1920.0 - 14.0 - 190.0, 14.0), C_NAV)
	_cam_button.pressed.connect(func() -> void: camera_pressed.emit())
	_scope_button = _btn("SCOPE", Vector2(190, 50), Vector2(0, 0), C_NAV)
	_scope_button.visible = touch
	_scope_button.pressed.connect(func() -> void:
		scope_on = not scope_on
		_set_btn_colors(_scope_button, C_NAV, scope_on)
		scope_changed.emit(scope_on))
	_scope_button.add_theme_font_size_override("font_size", roundi(18 * _fk))
	_set_btn_colors(_scope_button, C_NAV, scope_on)
	_map_button = _btn("MAP", Vector2(190, 50), Vector2(0, 0), C_NAV)
	_map_button.visible = portrait
	_map_button.pressed.connect(toggle_map)


## True when a screen position (in canvas coordinates) is over an on-screen control.
func is_over_ui(canvas_pos: Vector2) -> bool:
	for c in _ui_controls:
		if c.is_visible_in_tree() and Rect2(c.global_position, c.size * c.scale).has_point(canvas_pos):
			return true
	return false


func _place(c: Control, pos: Vector2, sz: Vector2) -> void:
	c.position = pos
	c.custom_minimum_size = sz
	c.size = sz


## Positions everything from the viewport size. Portrait: the 3D view on top, a control deck under it
## (mode buttons, big telegraph, FIRE and ship status, then a wide helm). Landscape: gauges centred
## along the bottom edge as before, enlarged on touch screens.
func _layout() -> void:
	if _telegraph == null or not is_inside_tree():
		return
	var V := get_viewport().get_visible_rect().size
	var W := V.x
	var H := V.y
	var pad := 16.0
	_covered.clear()
	_profile.scale = Vector2.ONE
	if portrait:
		var btn_h := 104.0
		var tel_w := 250.0
		var tel_h := 470.0
		var hel_h := 200.0
		var deck_h := pad * 4.0 + btn_h + tel_h + hel_h
		var yd := H - deck_h
		var bw := (W - pad * 4.0) / 3.0
		_place(_cam_button, Vector2(pad, yd + pad), Vector2(bw, btn_h))
		_place(_scope_button, Vector2(pad * 2.0 + bw, yd + pad), Vector2(bw, btn_h))
		_place(_map_button, Vector2(pad * 3.0 + bw * 2.0, yd + pad), Vector2(bw, btn_h))
		_scope_button.visible = true
		var yt := yd + pad * 2.0 + btn_h
		_telegraph.k = minf(tel_w / 100.0, tel_h / 190.0)
		_place(_telegraph, Vector2(pad, yt), Vector2(tel_w, tel_h))
		var fire_w := W - pad * 3.0 - tel_w
		var ps := minf(1.4, fire_w / ShipProfile.W)
		var prof_h := ShipProfile.H * ps
		var fire_h := tel_h - prof_h - pad
		var xf := pad * 2.0 + tel_w
		_place(_fire_button, Vector2(xf, yt), Vector2(fire_w, fire_h))
		_profile.scale = Vector2(ps, ps)
		_profile.position = Vector2(xf + (fire_w - ShipProfile.W * ps) * 0.5, yt + fire_h + pad)
		var yh := yt + tel_h + pad
		_helm.k = minf((W - pad * 2.0) / 230.0, hel_h / 68.0)
		_place(_helm, Vector2(pad, yh), Vector2(W - pad * 2.0, hel_h))
		_prop_tag.position = Vector2(pad, yd - 54.0)
		_prop_tag.custom_minimum_size = Vector2(360, 0)
		_steer_tag.position = Vector2(W - pad - 360.0, yd - 54.0)
		_steer_tag.custom_minimum_size = Vector2(360, 0)
		_compass.size = Vector2(W - pad * 2.0, 44.0 * _compass_sc)
		_compass.custom_minimum_size = _compass.size
		_compass.position = Vector2(pad, 12)
		_strip.position = Vector2(pad, 12.0 + 44.0 * _compass_sc + 8.0)
		_strip.custom_minimum_size = Vector2(W - pad * 2.0, 0)
		_strip.size = Vector2(W - pad * 2.0, 0)
		var ydyn := _strip.position.y + 96.0
		_values["dyn"].position = Vector2(pad, ydyn)
		_values["dyn"].custom_minimum_size = Vector2(W - pad * 2.0, 0)
		var ymap := ydyn + 40.0
		_mini.size = Vector2(300, 300)
		_mini.position = Vector2(pad, ymap)
		_place(_zin, Vector2(pad + 300.0 - 70.0, ymap + 6.0), Vector2(64, 64))
		_place(_zout, Vector2(pad + 300.0 - 140.0, ymap + 6.0), Vector2(64, 64))
		_alert_box.position = Vector2(pad * 2.0 + 300.0, ymap)
		_alert_box.custom_minimum_size = Vector2(W - 300.0 - pad * 3.0, 0)
		_log_box.position = Vector2(pad, yd - 54.0 - 215.0)
		_log_box.custom_minimum_size = Vector2(W - pad * 2.0, 0)
		_big.size = Vector2(W - pad * 2.0, W - pad * 2.0)
		_big.position = Vector2(pad, 130)
		_reticle_c = Vector2(W * 0.5, (ymap + yd - 60.0) * 0.5)
		_covered = [Rect2(0, 0, W, ymap), Rect2(0, yd - 60.0, W, deck_h + 60.0), Rect2(pad, ymap, 300, 300)]
	else:
		var tk := 1.4 if touch else 1.0
		var tel_x := W * 0.5 - (100.0 + 10.0 + 230.0) * tk * 0.5
		_telegraph.k = tk
		_place(_telegraph, Vector2(tel_x, H - 12.0 - 190.0 * tk), Vector2(100.0 * tk, 190.0 * tk))
		_helm.k = tk
		_place(_helm, Vector2(tel_x + 110.0 * tk, H - 12.0 - 68.0 * tk), Vector2(230.0 * tk, 68.0 * tk))
		_prop_tag.position = Vector2(tel_x, H - 12.0 - 190.0 * tk - 34.0)
		_prop_tag.custom_minimum_size = Vector2(100.0 * tk, 0)
		_steer_tag.position = Vector2(tel_x + 110.0 * tk, H - 12.0 - 68.0 * tk - 34.0)
		_steer_tag.custom_minimum_size = Vector2(230.0 * tk, 0)
		var fs := 1.3 if touch else 1.0
		var fw := 190.0 * fs
		var fh := 120.0 * fs
		_place(_fire_button, Vector2(W - 14.0 - fw, H - 14.0 - fh), Vector2(fw, fh))
		_place(_cam_button, Vector2(W - 14.0 - 190.0, 14), Vector2(190, 50))
		_place(_scope_button, Vector2(W - 14.0 - 190.0, 72), Vector2(190, 50))
		_scope_button.visible = touch
		_map_button.visible = false
		_profile.position = Vector2(W - 14.0 - ShipProfile.W - (fw + 12.0 if touch else 0.0), H - 12.0 - ShipProfile.H)
		_compass.size = Vector2(520, 44)
		_compass.custom_minimum_size = _compass.size
		_compass.position = Vector2(W * 0.5 - 260.0, 12)
		_strip.position = Vector2(W * 0.5 - 360.0, 62)
		_strip.custom_minimum_size = Vector2(720, 0)
		_values["dyn"].position = Vector2(W * 0.5 - 360.0, 62 + 52)
		_values["dyn"].custom_minimum_size = Vector2(720, 0)
		var zs := 44.0 if touch else 30.0
		_mini.size = Vector2(290, 290)
		_mini.position = Vector2(14, H - 14.0 - 290.0)
		_place(_zin, Vector2(14 + 290 - zs - 4.0, H - 14.0 - 290.0 + 4.0), Vector2(zs, zs))
		_place(_zout, Vector2(14 + 290 - zs * 2.0 - 8.0, H - 14.0 - 290.0 + 4.0), Vector2(zs, zs))
		_alert_box.position = Vector2(W * 0.5 - 230.0, 140)
		_alert_box.custom_minimum_size = Vector2(460, 0)
		_log_box.position = Vector2(320.0, H - 170.0)
		_log_box.custom_minimum_size = Vector2(440, 0)
		_big.size = Vector2(830, 830)
		_big.position = Vector2(W * 0.5 - 415.0, 36)
		_reticle_c = V * 0.5
		_covered = [Rect2(W * 0.5 - 260.0, 0, 520, 120), Rect2(W - 230.0, 0, 230, 125), Rect2(tel_x - 10.0, H - 280.0, 360.0 * tk, 280.0),
			Rect2(0, H - 320.0, 320, 320), Rect2(W - 400.0 - (fw if touch else 0.0), H - 190.0, 400.0 + (fw if touch else 0.0), 190.0)]


# --- Pointer routing --------------------------------------------------------------------
# Buttons and gauges are driven from raw touches, not GUI mouse events, because Godot only
# emulates a mouse from the first finger: with one thumb on FIRE a second finger could not steer.

func _target_at(pos: Vector2) -> Control:
	for i in range(_ui_controls.size() - 1, -1, -1):
		var c := _ui_controls[i]
		if c.is_visible_in_tree() and Rect2(c.global_position, c.size * c.scale).has_point(pos):
			return c if (c is Button or c is DetentGauge) else null
	return null


func _input(event: InputEvent) -> void:
	var idx := -999
	var pos := Vector2.ZERO
	var kind := ""
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		idx = st.index
		pos = st.position
		kind = "down" if st.pressed else "up"
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		idx = sd.index
		pos = sd.position
		kind = "move"
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		idx = -100
		pos = mb.position
		kind = "down" if mb.pressed else "up"
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION and _ptr.has(-100):
		idx = -100
		pos = (event as InputEventMouseMotion).position
		kind = "move"
	else:
		return
	match kind:
		"down":
			var t := _target_at(pos)
			if t == null:
				return
			_ptr[idx] = t
			get_viewport().set_input_as_handled()
			if t is DetentGauge:
				(t as DetentGauge).pick_at(pos)
			elif t == _fire_button:
				_set_btn_colors(_fire_button, C_WEP, true)
				fire_changed.emit(true)
			else:
				(t as Button).pressed.emit()
		"move":
			if _ptr.has(idx):
				get_viewport().set_input_as_handled()
				if _ptr[idx] is DetentGauge:
					(_ptr[idx] as DetentGauge).pick_at(pos)
		"up":
			if _ptr.has(idx):
				get_viewport().set_input_as_handled()
				if _ptr[idx] == _fire_button:
					_set_btn_colors(_fire_button, C_WEP, false)
					fire_changed.emit(false)
				_ptr.erase(idx)


# --- Per-frame update ------------------------------------------------------------------

func _status_color(f: float) -> Color:
	return C_GOOD if f >= 0.66 else (C_WARN if f >= 0.33 else C_BAD)


func _put(key: String, text: String, color: Color = C_TEXT) -> void:
	if not _values.has(key):
		return
	var l: Label = _values[key]
	l.text = text
	l.add_theme_color_override("font_color", color)


func _event(text: String, color: Color) -> void:
	_log.append([text, color, 0.0])
	while _log.size() > 6:
		_log.pop_front()


func _on_destroyed(_s: Ship, c: Compartment) -> void:
	if c.kind == Compartment.Kind.HULL_SECTION:
		_event("Hull breached: " + c.id, C_DMG)
	else:
		_event("DESTROYED: " + c.id, C_BAD)


func update_hud(aim_point: Vector3, mode_name: String, enemies: int, nearest: Ship, mouse_aiming: bool) -> void:
	_t += get_process_delta_time()
	camera_mode_name = mode_name
	_mouse_aiming = mouse_aiming
	_cam_button.text = ("CAMERA\n%s" % mode_name) if portrait else "CAMERA: %s  [C]" % mode_name
	_scope_button.text = "SCOPE ON" if scope_on else "SCOPE"
	_update_nav()
	_update_eng()
	_update_weapons(aim_point, enemies, nearest)
	_update_dmg()
	_update_buttons()
	_update_alerts()
	_update_log()
	_compass.queue_redraw()
	_profile.queue_redraw()
	_reticle.queue_redraw()
	_plates.queue_redraw()
	_last_aim = aim_point


func aim_color() -> Color:
	return _aim_color


func _water_below_keel() -> float:
	if terrain == null or not terrain.has_method("height_at"):
		return 999.0
	var p := ship.global_position
	var fwd := Vector3(sin(ship.heading), 0.0, cos(ship.heading))
	var squat: float = ship.hydro.squat_world if ship.hydro != null else 0.0
	var here: float = -float(terrain.height_at(p.x, p.z)) - ship.wdraft() - squat
	var ahead_p := p + fwd * 250.0
	var ahead: float = -float(terrain.height_at(ahead_p.x, ahead_p.z)) - ship.wdraft() - squat
	return minf(here, ahead)


func _update_nav() -> void:
	var kts := absf(ship.speed_ms) / 0.5144
	var astern := ship.speed_ms < -0.2
	_put("speed", "%.1f kts%s" % [kts, "  ASTERN" if astern else ""], C_NAV if not astern else C_WARN)
	_put("heading", "%03d°" % int(bearing_deg(ship.heading)), C_NAV)
	var rd := controls.rudder_degrees()
	_put("rudder", "%s %d°" % ["PORT" if rd > 0.5 else ("STBD" if rd < -0.5 else "MIDSHIPS"), int(roundf(absf(rd)))] if absf(rd) > 0.5 else "MIDSHIPS", C_NAV)
	var hy: Hydro = ship.hydro
	if hy != null:
		var st := hy.steerage
		_put("steerage", "NO WAY" if st < 0.08 else "%d%%" % int(st * 100.0), C_BAD if st < 0.08 else (C_WARN if st < 0.55 else C_GOOD))
		var pm := hy.platform_motion()
		_put("plat", ("STEADY" if pm < 0.25 else ("ROLLING" if pm < 0.6 else "UNSTEADY")) + "  %d°" % int(roundf(absf(rad_to_deg(hy.roll)))),
			C_GOOD if pm < 0.25 else (C_WARN if pm < 0.6 else C_BAD))
		var tr := hy.turn_radius()
		_put("dyn", "STOP IN %d m   |   TURN RADIUS %s   |   HULL DRAG x%.2f%s" % [int(hy.stop_distance()),
			"-" if tr > 5000.0 else "%d m" % int(tr), hy.drag_mult,
			"   |   SHOAL WATER: drag +, squat %.1f m" % hy.squat_world if hy.shallow > 0.15 else ""], C_DIM)
	var wb := _water_below_keel()
	if wb > 900.0:
		_put("depth", "-", C_DIM)
	elif wb < 0.0:
		_put("depth", "AGROUND", C_BAD)
	else:
		_put("depth", "%d m" % int(wb), C_BAD if wb < 6.0 else (C_WARN if wb < 20.0 else C_GOOD))


func _update_eng() -> void:
	var pf := ship.propulsion_fraction()
	var sf := ship.steering_fraction()
	_put("prop", "%d%%" % int(pf * 100.0), _status_color(pf))
	_put("steer", "%d%%" % int(sf * 100.0), _status_color(sf))


func _update_weapons(aim_point: Vector3, _enemies: int, _nearest: Ship) -> void:
	var aim_d := ship.global_position.distance_to(aim_point)
	var max_r := gunnery.max_range()
	var bs := gunnery.battery_status(aim_point)
	var btxt := ""
	var bcol := C_GOOD
	if int(bs["total"]) == 0:
		btxt = "NO GUNS"
		bcol = C_BAD
	elif aim_d > max_r:
		btxt = "OUT OF RANGE"
		bcol = C_BAD
	elif int(bs["in_arc"]) == 0:
		btxt = "DEAD ZONE"
		bcol = C_BAD
	elif int(bs["aligned"]) == int(bs["total"]):
		btxt = "ON TARGET %d/%d" % [bs["aligned"], bs["total"]]
	else:
		btxt = "TRAINING %d/%d" % [bs["aligned"], bs["total"]]
		bcol = C_WARN
		if int(bs["in_arc"]) < int(bs["total"]):
			btxt += "  (%d in arc)" % bs["in_arc"]
	_put("bearing", btxt, bcol)
	var tof := gunnery.flight_time(aim_point)
	var tof_txt := "" if tof < 0.0 else "  ToF %.1fs" % tof
	_aim_text = "%d yd%s  %s" % [int(aim_d * 1.0936), tof_txt, btxt]
	_aim_color = bcol


func _update_dmg() -> void:
	var fires := 0
	for c in ship.compartments:
		if c.on_fire and not c.destroyed:
			fires += 1
		var was: bool = _fire_state.get(c.id, false)
		if c.on_fire and not was and c.kind != Compartment.Kind.HULL_SECTION:
			_event("FIRE: " + c.id, C_WARN)
		_fire_state[c.id] = c.on_fire
		var wasf: bool = _flood_state.get(c.id, false)
		var flooding := c.flood_rate > 0.0 and c.flooded_tonnes < c.capacity_tonnes
		if flooding and not wasf:
			_event("Flooding: " + c.id, C_DMG)
		_flood_state[c.id] = flooding
	if ship.dc != null:
		var dc := ship.dc
		var fresh := mini(dc.note_count - _dc_seen, dc.log.size())
		for i in range(dc.log.size() - fresh, dc.log.size()):
			_event(dc.log[i], C_GOOD)
		_dc_seen = dc.note_count


func _update_buttons() -> void:
	_telegraph.ordered = controls.engine_ordered
	_telegraph.reply = float(controls.engine_answered)
	_telegraph.reply_matches = controls.engine_answered == controls.engine_ordered
	_helm.ordered = controls.helm_ordered
	# Actual rudder position as a fractional detent index (piecewise between the detent values).
	var r := ship.rudder
	var hv: Array = EngineTelegraph.HELM_ORDERS
	var fi := float(hv.size() - 1)
	for i in hv.size() - 1:
		var hi_v: float = hv[i][1]
		var lo_v: float = hv[i + 1][1]
		if r <= hi_v and r >= lo_v:
			fi = float(i) + (hi_v - r) / maxf(hi_v - lo_v, 0.0001)
			break
	_helm.reply = fi
	_helm.reply_matches = absf(r - float(hv[controls.helm_ordered][1])) < 0.02


func _update_alerts() -> void:
	for c in _alert_box.get_children():
		c.queue_free()
	var alerts: Array = []
	if ship.sunk:
		alerts.append(["SHIP LOST  -  [ / ] new ship,  F1-F7 new battleground", C_BAD])
	else:
		for c in ship.compartments:
			if c.kind == Compartment.Kind.MAGAZINE and not c.destroyed and (c.on_fire or c.heat > 0.5):
				alerts.append(["MAGAZINE FIRE: " + c.id + "  -  FLOOD IT", C_BAD])
				break
		var wb := _water_below_keel()
		if wb < 0.0:
			alerts.append(["AGROUND", C_BAD])
		elif wb < 8.0:
			alerts.append(["SHALLOW WATER  -  %d m below keel" % int(wb), C_WARN])
		if ship.total_flooded_t / maxf(ship.reserve_buoyancy_t, 1.0) > 0.4:
			alerts.append(["FLOODING CRITICAL", C_BAD])
		if ship.propulsion_fraction() < 0.05:
			alerts.append(["DEAD IN THE WATER", C_BAD])
		elif ship.steering_fraction() < 0.2:
			alerts.append(["STEERING LOST", C_WARN])
		if ship.gun_turrets().size() > 0 and ship.battery_fraction() < 0.01:
			alerts.append(["MAIN BATTERY OUT OF ACTION", C_BAD])
	var pulse := 0.65 + 0.35 * sin(_t * 8.0)
	for a in alerts.slice(0, 3):
		var pc := PanelContainer.new()
		var col: Color = a[1]
		var sb := _style(col)
		sb.bg_color = Color(col.r * 0.25, col.g * 0.25, col.b * 0.25, 0.85)
		sb.border_width_left = 0
		sb.set_border_width_all(2)
		pc.add_theme_stylebox_override("panel", sb)
		pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var l := _label(a[0], 20, Color(col.r, col.g, col.b, pulse if col == C_BAD else 1.0))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(maxf(_alert_box.custom_minimum_size.x - 24.0, 200.0), 0)
		pc.add_child(l)
		_alert_box.add_child(pc)


func _update_log() -> void:
	var dt := get_process_delta_time()
	for e in _log:
		e[2] += dt
	while _log.size() > 0 and float(_log[0][2]) > 14.0:
		_log.pop_front()
	for c in _log_box.get_children():
		c.queue_free()
	for e in _log:
		var col: Color = e[1]
		col.a = clampf(1.0 - (float(e[2]) - 9.0) / 5.0, 0.0, 1.0)
		var l := _label("%s" % e[0], 16, col)
		_log_box.add_child(l)


# --- Custom drawing ---------------------------------------------------------------------

func _draw_compass() -> void:
	var sc := _compass_sc
	var w := _compass.size.x / sc
	var h := 44.0
	_compass.draw_set_transform(Vector2.ZERO, 0.0, Vector2(sc, sc))
	var hdg := bearing_deg(ship.heading)
	_compass.draw_rect(Rect2(0, 0, w, h), C_PANEL)
	_compass.draw_rect(Rect2(0, 0, w, 3), C_NAV)
	var font := ThemeDB.fallback_font
	var px_per_deg := 4.0
	var span := int(w / 8.0) + 2
	for d in range(-span, span + 1):
		var deg := int(roundf(hdg)) + d
		var x := w * 0.5 + (float(deg) - hdg) * px_per_deg
		if x < 4.0 or x > w - 4.0:
			continue
		var dd := posmod(deg, 360)
		if dd % 10 == 0:
			var major := dd % 30 == 0
			_compass.draw_line(Vector2(x, 6), Vector2(x, 20 if major else 14), C_NAV, 2.0 if major else 1.0)
			if major:
				var txt: String = {0: "N", 90: "E", 180: "S", 270: "W"}.get(dd, "%03d" % dd)
				var ts := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
				_compass.draw_string(font, Vector2(x - ts.x * 0.5, 36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
					C_TEXT if txt.length() == 1 else C_DIM)
	_compass.draw_colored_polygon(PackedVector2Array([Vector2(w * 0.5 - 7, 0), Vector2(w * 0.5 + 7, 0), Vector2(w * 0.5, 10)]), C_ENG)


func _health_color(c: Compartment) -> Color:
	if c.destroyed:
		return Color(0.18, 0.18, 0.2)
	return _status_color(c.health_fraction()) * Color(1, 1, 1, 0.9)


func _draw_reticle() -> void:
	if not _mouse_aiming and ship != null:
		# Touch aiming: the view is the sight. A faint ring marks where the swing is pointing.
		var rc := _reticle_c
		_reticle.draw_arc(rc, 34.0 * _pk, 0.0, TAU, 56, Color(1, 1, 1, 0.30), 2.0, true)
		for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			_reticle.draw_line(rc + d * 34.0 * _pk, rc + d * 48.0 * _pk, Color(1, 1, 1, 0.30), 2.0)
	if camera == null or ship == null or ship.sunk or camera.is_position_behind(_last_aim):
		return
	var p := camera.unproject_position(_last_aim)
	var vp := _reticle.get_viewport_rect().size
	if p.x < 0 or p.y < 0 or p.x > vp.x or p.y > vp.y:
		return
	var c := _aim_color
	var r := 18.0
	_draw_splash_ellipse(p, c)
	var font := ThemeDB.fallback_font
	_reticle.draw_set_transform(p * (1.0 - _pk), 0.0, Vector2(_pk, _pk))
	_draw_battery_lamps(p, r)
	var ts := font.get_string_size(_aim_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
	var tp := p + Vector2(-ts.x * 0.5, r + 28.0)
	_reticle.draw_string(font, tp + Vector2(1, 1), _aim_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0, 0, 0, 0.9))
	_reticle.draw_string(font, tp, _aim_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, c)
	_reticle.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The scatter ellipse seen from the camera: the same shape the AimMarker lays on the water, projected
## to the screen with a fixed line weight so it stays legible when the view is nearly edge-on.
func _draw_splash_ellipse(p: Vector2, c: Color) -> void:
	var sh := ship.global_position
	var flat := Vector2(_last_aim.x - sh.x, _last_aim.z - sh.z)
	var along := flat.normalized() if flat.length() > 1.0 else Vector2(sin(ship.heading), cos(ship.heading))
	var across := Vector2(-along.y, along.x)
	var sg := gunnery.dispersion_sigma(flat.length())
	var a := maxf(sg.x * 2.0, 9.0)
	var b := maxf(sg.y * 2.0, 6.0)
	var pts := PackedVector2Array()
	for i in 41:
		var th := TAU * float(i) / 40.0
		var w := Vector2(_last_aim.x, _last_aim.z) + along * (a * cos(th)) + across * (b * sin(th))
		var wp := Vector3(w.x, _last_aim.y, w.y)
		if camera.is_position_behind(wp):
			return
		pts.append(camera.unproject_position(wp))
	_reticle.draw_polyline(pts, Color(0, 0, 0, 0.55), 4.0, true)
	_reticle.draw_polyline(pts, c, 2.0, true)
	# Crosshair arms of fixed pixel length through the centre, with a gap.
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		_reticle.draw_line(p + d * 5.0, p + d * 15.0, Color(0, 0, 0, 0.55), 4.0)
		_reticle.draw_line(p + d * 5.0, p + d * 15.0, c, 2.0)


## A lamp per turret above the reticle, bow to stern: loaded and clear to fire (green), reloading
## (amber, fills as it loads), swinging onto the aim point (blue) or the point is in its dead zone (red X).
func _draw_battery_lamps(p: Vector2, r: float) -> void:
	var states := gunnery.turret_states(_last_aim)
	if states.is_empty():
		return
	var font := ThemeDB.fallback_font
	var n := states.size()
	var w := 24.0
	var gap := 5.0
	var x0 := p.x - (n * w + (n - 1) * gap) * 0.5
	var y0 := p.y - r - 16.0 - w
	var ready := 0
	for i in n:
		var e: Dictionary = states[i]
		var box := Rect2(Vector2(x0 + i * (w + gap), y0), Vector2(w, w))
		var st: String = e["state"]
		_reticle.draw_rect(box, Color(0.03, 0.05, 0.08, 0.85))
		var col := C_DIM
		match st:
			"READY":
				col = C_GOOD
				ready += 1
				_reticle.draw_rect(box.grow(-3.0), col)
			"RELOAD":
				col = C_WARN
				var fh := (w - 6.0) * float(e["reload"])
				_reticle.draw_rect(Rect2(box.position + Vector2(3, w - 3.0 - fh), Vector2(w - 6.0, fh)), col)
			"TRAINING":
				col = C_NAV
				_reticle.draw_rect(box.grow(-6.0), Color(col.r, col.g, col.b, 0.55))
			"DEAD":
				col = C_BAD
				_reticle.draw_line(box.position + Vector2(4, 4), box.position + Vector2(w - 4, w - 4), col, 3.0)
				_reticle.draw_line(box.position + Vector2(w - 4, 4), box.position + Vector2(4, w - 4), col, 3.0)
			_:
				_reticle.draw_line(box.position + Vector2(6, w * 0.5), box.position + Vector2(w - 6, w * 0.5), col, 2.0)
		_reticle.draw_rect(box, col, false, 2.0)
		var lbl := str(i + 1)
		_reticle.draw_string(font, box.position + Vector2(w * 0.5 - 3.0, -3.0), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.7))
	var cap := "CLEAR TO FIRE" if ready == n else "%d/%d READY" % [ready, n]
	var cc := C_GOOD if ready == n else (C_WARN if ready > 0 else C_BAD)
	var cs := font.get_string_size(cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	_reticle.draw_string(font, Vector2(p.x - cs.x * 0.5 + 1, y0 - 13.0 + 1), cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0, 0, 0, 0.9))
	_reticle.draw_string(font, Vector2(p.x - cs.x * 0.5, y0 - 13.0), cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, cc)


## Floating nameplates over every ship we can see: class icon, name and a health bar.
var _plate_t := 0.0


func _draw_plates() -> void:
	_plate_t = Time.get_ticks_msec() / 1000.0
	if camera == null or sensors == null or ship == null:
		return
	var font := ThemeDB.fallback_font
	var vp := _plates.get_viewport_rect().size
	for k in sensors.picture:
		var s := k as Ship
		if s == null or not is_instance_valid(s) or s.sunk or not bool(sensors.picture[k]["live"]):
			continue
		var friend := s.team == ship.team
		var wp := s.global_position + Vector3(0, clampf(s.wlen() * 0.1, 20.0, 60.0), 0)
		if camera.is_position_behind(wp):
			continue
		var p := camera.unproject_position(wp)
		if p.x < -60 or p.y < -40 or p.x > vp.x + 60 or p.y > vp.y + 40:
			continue
		var covered := false
		for r in _covered:
			if r.has_point(p):
				covered = true
		if covered or (_big != null and _big.visible):
			continue
		_plates.draw_set_transform(p * (1.0 - _pk), 0.0, Vector2(_pk, _pk))
		var col := C_GOOD if friend else C_BAD
		if s == ship:
			col = C_NAV
		var nm := s.display_name.get_slice(" (", 0)
		var dist_txt := ""
		if s != ship:
			# Range, plus the target's own course and speed so the player can work out a lead.
			dist_txt = "  %d yd  %03d/%dkt" % [int(s.global_position.distance_to(ship.global_position) * 1.0936),
				int(bearing_deg(s.heading)), int(absf(s.speed_ms) / 0.5144)]
		var label := nm + dist_txt
		var ts := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
		var w := maxf(ts.x + 26.0, 92.0)
		var top := p + Vector2(-w * 0.5, -30.0)
		var bg := Rect2(top, Vector2(w, 26.0))
		_plates.draw_rect(bg, Color(0.03, 0.05, 0.08, 0.7))
		_plates.draw_rect(Rect2(top, Vector2(3, 26)), col)
		ShipIcon.draw(_plates, top + Vector2(15, 12), Vector2(0, -1), s.ship_type, 18.0, col)
		_plates.draw_string(font, top + Vector2(26, 11), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, C_TEXT)
		var integ := s.integrity()
		var bar := Rect2(top + Vector2(26, 16), Vector2(w - 32.0, 5.0))
		_plates.draw_rect(bar, Color(0.1, 0.12, 0.15, 0.95))
		_plates.draw_rect(Rect2(bar.position, Vector2(bar.size.x * integ, bar.size.y)), _status_color(integ))
		_plates.draw_rect(bar, Color(0, 0, 0, 0.8), false, 1.0)
		_plates.draw_line(p + Vector2(0, -4), p, Color(col.r, col.g, col.b, 0.7), 1.0)
		# Status chips under the plate: fire, flooding, list, lost steering/power/guns.
		var chips := StatusIcons.compute(s)
		var cx := top.x + 26.0
		for st in chips:
			StatusIcons.draw(_plates, Vector2(cx, top.y + 28.0), 17.0, st, _plate_t)
			cx += 20.0
	_plates.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
