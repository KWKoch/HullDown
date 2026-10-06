class_name Hud
extends CanvasLayer
## Grouped, colour-coded heads-up display plus the on-screen controls (shared by touch and
## mouse). Each data family has its own colour so the eye can go straight to it:
##   NAVIGATION  teal    |  ENGINEERING  amber  |  WEAPONS  red  |  DAMAGE CONTROL  blue
## Values use one status scale everywhere: green = good, amber = degraded, red = critical.

signal camera_pressed
signal fire_changed(held: bool)

const C_NAV := Color(0.30, 0.82, 0.86)
const C_ENG := Color(1.00, 0.72, 0.22)
const C_WEP := Color(1.00, 0.36, 0.32)
const C_DMG := Color(0.42, 0.62, 1.00)
const C_GOOD := Color(0.45, 0.88, 0.50)
const C_WARN := Color(1.00, 0.78, 0.25)
const C_BAD := Color(1.00, 0.30, 0.28)
const C_DIM := Color(0.62, 0.68, 0.72)
const C_TEXT := Color(0.94, 0.96, 0.97)
const SHOW_DAMAGE_PANEL := true      ## damage-control panel + ship schematic
const C_PANEL := Color(0.04, 0.06, 0.09, 0.72)

var ship: Ship
var gunnery: Gunnery
var controls: PlayerControls
var terrain: Node
var ground_name := ""
var opponents_total := 30
var camera_mode_name := "CHASE"

var _values: Dictionary = {}          ## key -> Label
var _ui_controls: Array[Control] = []
var _telegraph_buttons: Array[Button] = []
var _helm_buttons: Array[Button] = []
var _fire_button: Button
var _cam_button: Button
var _compass: Control
var _schematic: Control
var _alert_box: VBoxContainer
var _log_box: VBoxContainer
var _log: Array = []                  ## [text, color, age]
var _turret_box: VBoxContainer
var _turret_bars: Array[ProgressBar] = []
var _fire_state: Dictionary = {}      ## compartment id -> bool, for edge-detecting events
var _flood_state: Dictionary = {}
var _t := 0.0


func setup(p_ship: Ship, p_gun: Gunnery, p_controls: PlayerControls, p_terrain: Node, p_ground: String, p_opponents: int) -> void:
	ship = p_ship
	gunnery = p_gun
	controls = p_controls
	terrain = p_terrain
	ground_name = p_ground
	opponents_total = p_opponents
	layer = 10
	_build()
	ship.compartment_destroyed.connect(_on_destroyed)
	ship.magazine_detonated.connect(func(_s: Ship, c: Compartment) -> void: _event("MAGAZINE DETONATED: " + c.id, C_BAD))
	ship.ship_sunk.connect(func(_s: Ship) -> void: _event("SHIP LOST", C_BAD))
	_event("General Quarters. Ship cleared for action.", C_DIM)


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
	l.add_theme_font_size_override("font_size", size)
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


func _build() -> void:
	# NAVIGATION (top-left, teal)
	var nav := _panel("NAVIGATION", C_NAV, Control.PRESET_TOP_LEFT, Vector2(14, 14), 330)
	var name_l := _label("", 17, C_TEXT)
	nav.add_child(name_l)
	_values["name"] = name_l
	_row(nav, "speed", "SPEED", C_NAV)
	_row(nav, "heading", "HEADING", C_NAV)
	_row(nav, "rudder", "RUDDER", C_NAV)
	_row(nav, "depth", "UNDER KEEL", C_NAV)

	# ENGINEERING (below navigation, amber)
	var eng := _panel("ENGINEERING", C_ENG, Control.PRESET_TOP_LEFT, Vector2(14, 262), 330)
	_row(eng, "order", "ORDERED", C_ENG)
	_row(eng, "answer", "ENGINES", C_ENG)
	_row(eng, "prop", "PROPULSION", C_ENG)
	_row(eng, "steer", "STEERING", C_ENG)

	# WEAPONS (top-right, red)
	var wep := _panel("WEAPONS", C_WEP, Control.PRESET_TOP_RIGHT, Vector2(-364, 14), 350)
	_row(wep, "battery", "MAIN BATTERY", C_WEP)
	_turret_box = VBoxContainer.new()
	_turret_box.add_theme_constant_override("separation", 3)
	_turret_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wep.add_child(_turret_box)
	_row(wep, "hostiles", "HOSTILES", C_WEP)
	_row(wep, "nearest", "NEAREST", C_WEP)
	_row(wep, "aim", "AIM RANGE", C_WEP)

	# DAMAGE CONTROL (right, blue) with the ship schematic
	var dmg := _panel("DAMAGE CONTROL", C_DMG, Control.PRESET_TOP_RIGHT, Vector2(-364, 330), 350)
	_row(dmg, "integrity", "INTEGRITY", C_DMG)
	_row(dmg, "flooding", "FLOODING", C_DMG)
	_row(dmg, "list", "LIST", C_DMG)
	_row(dmg, "fires", "FIRES", C_DMG)
	_schematic = Control.new()
	_schematic.custom_minimum_size = Vector2(326, 250)
	_schematic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_schematic.draw.connect(_draw_schematic)
	dmg.add_child(_schematic)
	dmg.get_parent().visible = SHOW_DAMAGE_PANEL

	# Compass strip and alerts (top centre)
	_compass = Control.new()
	_compass.custom_minimum_size = Vector2(520, 44)
	_compass.size = Vector2(520, 44)
	_compass.position = Vector2(1920.0 * 0.5 - 260.0, 12)
	_compass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_compass.draw.connect(_draw_compass)
	add_child(_compass)
	_alert_box = VBoxContainer.new()
	_alert_box.position = Vector2(1920.0 * 0.5 - 230.0, 64)
	_alert_box.custom_minimum_size = Vector2(460, 0)
	_alert_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_alert_box)

	# Event log (bottom centre)
	_log_box = VBoxContainer.new()
	_log_box.position = Vector2(1920.0 * 0.5 - 300.0, 1080.0 - 190.0)
	_log_box.custom_minimum_size = Vector2(600, 0)
	_log_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_log_box)

	_build_controls()


func _btn(text: String, size: Vector2, pos: Vector2, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = size
	b.size = size
	b.position = pos
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 16)
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
	# Engine order telegraph: a vertical column on the lower left (green ahead, grey stop, red astern).
	var n: int = EngineTelegraph.ENGINE_ORDERS.size()
	var bh := 50.0
	var gap := 4.0
	var top := 1080.0 - 14.0 - n * (bh + gap)
	var cap := _label("ENGINE ORDERS  [W / S]", 13, C_ENG)
	cap.position = Vector2(14, top - 22)
	add_child(cap)
	for i in n:
		var order: Array = EngineTelegraph.ENGINE_ORDERS[i]
		var col := C_GOOD if float(order[1]) > 0.0 else (C_DIM if float(order[1]) == 0.0 else C_BAD)
		var b := _btn(String(order[0]), Vector2(190, bh), Vector2(14, top + i * (bh + gap)), col)
		var idx := i
		b.pressed.connect(func() -> void: controls.ring_engine(idx))
		_telegraph_buttons.append(b)
	# Helm: a row along the bottom (port on the left, starboard on the right, like looking forward).
	var hn: int = EngineTelegraph.HELM_ORDERS.size()
	var hw := 112.0
	var hx := 236.0
	var hy := 1080.0 - 14.0 - 62.0
	var hcap := _label("HELM  [A / D]  [X centres]", 13, C_NAV)
	hcap.position = Vector2(hx, hy - 22)
	add_child(hcap)
	for i in hn:
		var h: Array = EngineTelegraph.HELM_ORDERS[i]
		var col2 := C_WEP if float(h[1]) > 0.0 else (C_DIM if float(h[1]) == 0.0 else C_GOOD)
		var hb := _btn(String(h[0]), Vector2(hw, 62), Vector2(hx + i * (hw + 4.0), hy), col2)
		var hidx := i
		hb.pressed.connect(func() -> void: controls.set_helm(hidx))
		_helm_buttons.append(hb)
	# Fire and camera on the lower right.
	_fire_button = _btn("FIRE\nMAIN BATTERY", Vector2(190, 120), Vector2(1920.0 - 14.0 - 190.0, 1080.0 - 14.0 - 120.0), C_WEP)
	_fire_button.add_theme_font_size_override("font_size", 20)
	_fire_button.button_down.connect(func() -> void: fire_changed.emit(true))
	_fire_button.button_up.connect(func() -> void: fire_changed.emit(false))
	_cam_button = _btn("CAMERA: CHASE  [C]", Vector2(190, 50), Vector2(1920.0 - 14.0 - 190.0, 1080.0 - 14.0 - 120.0 - 58.0), C_NAV)
	_cam_button.pressed.connect(func() -> void: camera_pressed.emit())


## True when a screen position (in canvas coordinates) is over an on-screen control.
func is_over_ui(canvas_pos: Vector2) -> bool:
	for c in _ui_controls:
		if c.get_global_rect().has_point(canvas_pos):
			return true
	return false


# --- Per-frame update ------------------------------------------------------------------

func _status_color(f: float) -> Color:
	return C_GOOD if f >= 0.66 else (C_WARN if f >= 0.33 else C_BAD)


func _put(key: String, text: String, color: Color = C_TEXT) -> void:
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
	_cam_button.text = "CAMERA: %s  [C]" % mode_name
	_update_nav()
	_update_eng()
	_update_weapons(aim_point, enemies, nearest)
	_update_dmg()
	_update_buttons()
	_update_alerts()
	_update_log()
	_compass.queue_redraw()
	_schematic.queue_redraw()


func _water_below_keel() -> float:
	if terrain == null or not terrain.has_method("height_at"):
		return 999.0
	var p := ship.global_position
	var fwd := Vector3(sin(ship.heading), 0.0, cos(ship.heading))
	var here: float = -float(terrain.height_at(p.x, p.z)) - ship.draft_m
	var ahead_p := p + fwd * 250.0
	var ahead: float = -float(terrain.height_at(ahead_p.x, ahead_p.z)) - ship.draft_m
	return minf(here, ahead)


func _update_nav() -> void:
	_put("name", "%s  [%s]\n%s" % [ship.display_name, ship.nation, ground_name], C_TEXT)
	var kts := absf(ship.speed_ms) / 0.5144
	var astern := ship.speed_ms < -0.2
	_put("speed", "%.1f kts%s" % [kts, "  ASTERN" if astern else ""], C_NAV if not astern else C_WARN)
	_put("heading", "%03d°" % int(fposmod(rad_to_deg(ship.heading), 360.0)), C_NAV)
	var rd := controls.rudder_degrees()
	_put("rudder", "%s %d°" % ["PORT" if rd > 0.5 else ("STBD" if rd < -0.5 else "MIDSHIPS"), int(roundf(absf(rd)))] if absf(rd) > 0.5 else "MIDSHIPS", C_NAV)
	var wb := _water_below_keel()
	if wb > 900.0:
		_put("depth", "-", C_DIM)
	elif wb < 0.0:
		_put("depth", "AGROUND", C_BAD)
	else:
		_put("depth", "%d m" % int(wb), C_BAD if wb < 6.0 else (C_WARN if wb < 20.0 else C_GOOD))


func _update_eng() -> void:
	_put("order", controls.engine_label(), C_ENG)
	var answered := controls.engine_answered == controls.engine_ordered
	_put("answer", "ANSWERED" if answered else "answering...", C_GOOD if answered else C_WARN)
	var pf := ship.propulsion_fraction()
	var sf := ship.steering_fraction()
	_put("prop", "%d%%" % int(pf * 100.0), _status_color(pf))
	_put("steer", "%d%%" % int(sf * 100.0), _status_color(sf))


func _update_weapons(aim_point: Vector3, enemies: int, nearest: Ship) -> void:
	var turrets := ship.gun_turrets()
	var ok := 0
	for t in turrets:
		if t.is_functional():
			ok += 1
	var frac := float(ok) / maxf(1.0, float(turrets.size()))
	_put("battery", "%d / %d turrets" % [ok, turrets.size()], _status_color(frac))
	while _turret_bars.size() < turrets.size():
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(300, 12)
		bar.show_percentage = false
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_turret_box.add_child(bar)
		_turret_bars.append(bar)
	for i in _turret_bars.size():
		var bar2 := _turret_bars[i]
		if i >= turrets.size():
			bar2.visible = false
			continue
		var t2: Compartment = turrets[i]
		var left: float = float(gunnery.reload_left.get(t2, 0.0))
		var full := 60.0 / maxf(0.1, float(gunnery.gun.get("rpm", 2.0)))
		bar2.max_value = 1.0
		var fill := 1.0 - clampf(left / maxf(full, 0.1), 0.0, 1.0)
		bar2.value = fill
		var col := C_BAD if not t2.is_functional() else (C_GOOD if left <= 0.0 else C_WARN)
		var sb := StyleBoxFlat.new()
		sb.bg_color = col
		sb.set_corner_radius_all(2)
		bar2.add_theme_stylebox_override("fill", sb)
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0.1, 0.12, 0.15, 0.9)
		bg.set_corner_radius_all(2)
		bar2.add_theme_stylebox_override("background", bg)
	_put("hostiles", "%d / %d afloat" % [enemies, opponents_total], C_WEP)
	if nearest != null:
		var d := ship.global_position.distance_to(nearest.global_position)
		var rel := nearest.global_position - ship.global_position
		var brg := fposmod(rad_to_deg(atan2(rel.x, rel.z)), 360.0)
		_put("nearest", "%s  %d yd  brg %03d" % [nearest.display_name.get_slice(" ", 0), int(d * 1.0936), int(brg)], C_TEXT)
	else:
		_put("nearest", "none", C_DIM)
	var aim_d := ship.global_position.distance_to(aim_point)
	var max_r := gunnery.max_range()
	_put("aim", "%d yd%s" % [int(aim_d * 1.0936), "  OUT OF RANGE" if aim_d > max_r else ""], C_BAD if aim_d > max_r else C_GOOD)


func _update_dmg() -> void:
	var integ := ship.integrity()
	_put("integrity", "%d%%" % int(integ * 100.0), _status_color(integ))
	var ratio := ship.total_flooded_t / maxf(ship.reserve_buoyancy_t, 1.0)
	_put("flooding", "%.0f / %.0f t" % [ship.total_flooded_t, ship.reserve_buoyancy_t], C_GOOD if ratio < 0.15 else (C_WARN if ratio < 0.5 else C_BAD))
	var ld := absf(rad_to_deg(ship.list_rad))
	_put("list", "%.1f°" % ld, C_GOOD if ld < 3.0 else (C_WARN if ld < 8.0 else C_BAD))
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
	_put("fires", "%d" % fires, C_GOOD if fires == 0 else (C_WARN if fires < 3 else C_BAD))


func _update_buttons() -> void:
	for i in _telegraph_buttons.size():
		var order: Array = EngineTelegraph.ENGINE_ORDERS[i]
		var col := C_GOOD if float(order[1]) > 0.0 else (C_DIM if float(order[1]) == 0.0 else C_BAD)
		var b := _telegraph_buttons[i]
		var active := i == controls.engine_ordered
		_set_btn_colors(b, col, active)
		# A small marker shows what the engine room is actually running while it catches up.
		b.text = ("%s%s" % [String(order[0]), "" if controls.engine_answered == i or not active else "  ..."])
	for i in _helm_buttons.size():
		var h: Array = EngineTelegraph.HELM_ORDERS[i]
		var col2 := C_WEP if float(h[1]) > 0.0 else (C_DIM if float(h[1]) == 0.0 else C_GOOD)
		_set_btn_colors(_helm_buttons[i], col2, i == controls.helm_ordered)


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
	var w := 520.0
	var h := 44.0
	var hdg := fposmod(rad_to_deg(ship.heading), 360.0)
	_compass.draw_rect(Rect2(0, 0, w, h), C_PANEL)
	_compass.draw_rect(Rect2(0, 0, w, 3), C_NAV)
	var font := ThemeDB.fallback_font
	var px_per_deg := 4.0
	for d in range(-65, 66):
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


func _draw_schematic() -> void:
	var sch := _schematic
	var size := sch.size
	var frame := ShipFrame.for_entry(Roster.get_entry(ship.class_id))
	var sc := minf((size.y - 14.0) / frame.length, (size.x * 0.5 - 10.0) / maxf(frame.beam * 0.5, 1.0))
	var cx := size.x * 0.5
	var cy := size.y * 0.5
	# Screen mapping: bow up; port (+X) on the left.
	var to_s := func(x: float, z: float) -> Vector2: return Vector2(cx - x * sc, cy - z * sc)
	# Hull outline.
	var pts := PackedVector2Array()
	var steps := 24
	for i in range(steps + 1):
		var z := -frame.length * 0.5 + frame.length * float(i) / steps
		pts.append(to_s.call(frame.half_breadth(z), z))
	for i in range(steps, -1, -1):
		var z2 := -frame.length * 0.5 + frame.length * float(i) / steps
		pts.append(to_s.call(-frame.half_breadth(z2), z2))
	sch.draw_colored_polygon(pts, Color(0.12, 0.16, 0.22, 0.9))
	sch.draw_polyline(pts + PackedVector2Array([pts[0]]), C_DMG, 1.5)
	# Flooded fraction as a blue wash from the keel up inside each compartment, then the part itself.
	for pass_i in 2:
		for c in ship.compartments:
			var is_hull := c.kind == Compartment.Kind.HULL_SECTION
			if (pass_i == 0) != is_hull:
				continue
			var tl: Vector2 = to_s.call(c.center.x + c.half_extents.x, c.center.z + c.half_extents.z)
			var br: Vector2 = to_s.call(c.center.x - c.half_extents.x, c.center.z - c.half_extents.z)
			var r := Rect2(tl, br - tl).abs()
			if is_hull:
				var hc := _health_color(c)
				hc.a = 0.45
				sch.draw_rect(r.grow(-0.5), hc)
			else:
				if r.size.x < 3.0:
					r = r.grow_individual(1.5 - r.size.x * 0.5, 0, 1.5 - r.size.x * 0.5, 0)
				if r.size.y < 3.0:
					r = r.grow_individual(0, 1.5 - r.size.y * 0.5, 0, 1.5 - r.size.y * 0.5)
				sch.draw_rect(r, _health_color(c))
				if c.kind == Compartment.Kind.MAGAZINE:
					sch.draw_rect(r, C_WARN, false, 1.5)
				else:
					sch.draw_rect(r, Color(0, 0, 0, 0.6), false, 1.0)
			if c.on_fire and not c.destroyed:
				var flick := 0.55 + 0.45 * sin(_t * 12.0 + c.center.z)
				sch.draw_rect(r.grow(2.0), Color(1.0, 0.45, 0.1, flick), false, 2.5)
			if c.flood_rate > 0.0 and c.flooded_tonnes < c.capacity_tonnes:
				sch.draw_rect(r.grow(1.0), Color(0.3, 0.55, 1.0, 0.9), false, 2.0)
	var font := ThemeDB.fallback_font
	sch.draw_string(font, Vector2(4, 14), "BOW", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, C_DIM)
	# Legend.
	var lx := 6.0
	var ly := size.y - 62.0
	for k in 3:
		var lc: Color = [C_GOOD, C_WARN, C_BAD][k]
		sch.draw_rect(Rect2(lx, ly + k * 14.0, 10, 10), lc)
		sch.draw_string(font, Vector2(lx + 15, ly + 9 + k * 14.0), ["sound", "damaged", "critical"][k], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, C_DIM)
	sch.draw_rect(Rect2(lx, ly + 42, 10, 10), C_WARN, false, 1.5)
	sch.draw_string(font, Vector2(lx + 15, ly + 51), "magazine", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, C_DIM)
