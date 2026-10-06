class_name ShipProfile
extends Control
## The player's own-ship condition readout: a small broadside (profile) view with every compartment
## coloured by health -- hull, machinery, magazines, turrets, bridge, funnels, masts -- flooding shown
## as a blue wash, fires as flames, then a row of sailor-hat icons for the repair parties (colour =
## what each is doing) and two colourised lines of figures directly beneath.

signal clicked          ## the lower part of the widget was pressed (cycles damage-control priority)

const C_PANEL := Color(0.05, 0.08, 0.11, 0.82)
const C_ACCENT := Color(0.40, 0.62, 1.0)
const W := 340.0
const H := 150.0
const PROFILE_H := 76.0
const CUP_IDLE := Color(0.93, 0.95, 0.97)
const CUP_TRAVEL := Color(1.00, 0.78, 0.25)
const CUP_FIRE := Color(1.00, 0.42, 0.12)
const CUP_LEAK := Color(0.36, 0.62, 1.00)
const CUP_REPAIR := Color(0.45, 0.88, 0.50)

var ship: Ship
var _t := 0.0


func _init() -> void:
	custom_minimum_size = Vector2(W, H)
	size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and event.position.y > PROFILE_H + 8.0:
		clicked.emit()
		accept_event()


static func status_color(f: float) -> Color:
	return Hud.C_GOOD if f >= 0.66 else (Hud.C_WARN if f >= 0.33 else Hud.C_BAD)


func _health_color(c: Compartment) -> Color:
	if c.destroyed:
		return Color(0.20, 0.20, 0.23)
	return status_color(c.health_fraction())


func _process(delta: float) -> void:
	_t += delta


func _draw() -> void:
	if ship == null:
		return
	draw_rect(Rect2(0, 0, W, H), C_PANEL)
	draw_rect(Rect2(0, 0, W, 3), C_ACCENT)
	_draw_profile()
	_draw_cups(PROFILE_H + 12.0)
	_draw_figures(PROFILE_H + 12.0 + 26.0)


func _draw_profile() -> void:
	var len_m := ship.length_m
	var top := ship.top_y
	var draft := ship.draft_m
	var sc := minf((W - 16.0) / len_m, (PROFILE_H - 8.0) / (top + draft))
	var cx := W * 0.5
	var wl := 6.0 + top * sc                         # waterline y in pixels
	var to_s := func(z: float, y: float) -> Vector2: return Vector2(cx + z * sc, wl - y * sc)
	# Sea.
	draw_rect(Rect2(6, wl, W - 12, PROFILE_H - wl + 4.0), Color(0.12, 0.28, 0.45, 0.35))
	# Hull silhouette (bow to the right).
	var deck := 5.0
	for c in ship.compartments:
		if c.kind == Compartment.Kind.HULL_SECTION:
			deck = maxf(deck, c.center.y + c.half_extents.y)
	var hl := len_m * 0.5
	var hull := PackedVector2Array([
		to_s.call(-hl, deck), to_s.call(-hl, -draft * 0.4), to_s.call(-hl * 0.86, -draft),
		to_s.call(hl * 0.80, -draft), to_s.call(hl * 0.94, 0.0), to_s.call(hl, deck)])
	draw_colored_polygon(hull, Color(0.13, 0.17, 0.23, 0.95))
	# Compartments, biggest first so small parts show on top.
	var order: Array[Compartment] = ship.compartments.duplicate()
	order.sort_custom(func(a: Compartment, b: Compartment) -> bool:
		return a.half_extents.x * a.half_extents.y * a.half_extents.z > b.half_extents.x * b.half_extents.y * b.half_extents.z)
	for c in order:
		var tl: Vector2 = to_s.call(c.center.z - c.half_extents.z, c.center.y + c.half_extents.y)
		var br: Vector2 = to_s.call(c.center.z + c.half_extents.z, c.center.y - c.half_extents.y)
		var r := Rect2(tl, br - tl).abs()
		if r.size.x < 3.0:
			r = r.grow_individual(1.5 - r.size.x * 0.5, 0, 1.5 - r.size.x * 0.5, 0)
		if r.size.y < 3.0:
			r = r.grow_individual(0, 1.5 - r.size.y * 0.5, 0, 1.5 - r.size.y * 0.5)
		var col := _health_color(c)
		var big := c.kind == Compartment.Kind.HULL_SECTION or c.kind == Compartment.Kind.BOW or c.kind == Compartment.Kind.STERN
		col.a = 0.5 if big else 0.92
		draw_rect(r.grow(-0.4), col)
		if c.flooded_tonnes > 0.0:
			var fr := clampf(c.flooded_tonnes / maxf(c.capacity_tonnes, 1.0), 0.0, 1.0)
			draw_rect(Rect2(r.position.x, r.end.y - r.size.y * fr, r.size.x, r.size.y * fr), Color(0.30, 0.56, 1.0, 0.7))
		if c.kind == Compartment.Kind.MAGAZINE:
			draw_rect(r, Hud.C_WARN, false, 1.2)
		elif not big:
			draw_rect(r, Color(0, 0, 0, 0.6), false, 1.0)
		if c.flood_rate > 0.0 and c.flooded_tonnes < c.capacity_tonnes:
			draw_rect(r.grow(1.0), Color(0.35, 0.62, 1.0, 0.95), false, 1.6)
		if c.on_fire and not c.destroyed:
			var flick := 0.6 + 0.4 * sin(_t * 12.0 + c.center.z)
			draw_rect(r.grow(1.5), Color(1.0, 0.45, 0.1, flick), false, 2.0)
			var fx := r.position.x + r.size.x * 0.5
			draw_colored_polygon(PackedVector2Array([Vector2(fx - 3, r.position.y), Vector2(fx + 3, r.position.y), Vector2(fx, r.position.y - 7.0 * flick - 3.0)]), Color(1.0, 0.5, 0.1, flick))
	draw_polyline(hull + PackedVector2Array([hull[0]]), Color(0.55, 0.65, 0.78, 0.8), 1.2)
	draw_line(Vector2(6, wl), Vector2(W - 6, wl), Color(0.45, 0.7, 1.0, 0.7), 1.0)


func _cup(pos: Vector2, col: Color) -> void:
	# A Dixie cup: wide rolled brim on top tapering to the crown.
	var body := PackedVector2Array([pos + Vector2(0, 0), pos + Vector2(20, 0), pos + Vector2(16.5, 13), pos + Vector2(3.5, 13)])
	draw_colored_polygon(body, col)
	draw_polyline(body + PackedVector2Array([body[0]]), Color(0, 0, 0, 0.7), 1.3)
	draw_line(pos + Vector2(2.5, 4), pos + Vector2(17.5, 4), Color(0, 0, 0, 0.35), 1.0)    # the turned-up brim
	draw_line(pos + Vector2(6, 8), pos + Vector2(8, 11), Color(1, 1, 1, 0.55), 1.5)       # highlight


func _draw_cups(y: float) -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(8, y + 11), "REPAIR", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Hud.C_DIM)
	if ship.dc == null:
		return
	var x := 62.0
	for p in ship.dc.parties:
		var col := CUP_IDLE
		var task: String = p["task"]
		if task != "IDLE":
			col = CUP_TRAVEL if float(p["travel"]) > 0.0 else (CUP_FIRE if task == "FIRE" else (CUP_LEAK if task == "LEAK" else CUP_REPAIR))
		_cup(Vector2(x, y), col)
		x += 26.0
	# Key to the hat colours, small and at the right.
	var kx := W - 8.0
	for k in [["idle", CUP_IDLE], ["fire", CUP_FIRE], ["leak", CUP_LEAK], ["fix", CUP_REPAIR]]:
		var ts := font.get_string_size(k[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 9)
		kx -= ts.x
		draw_string(font, Vector2(kx, y + 11), k[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, k[1])
		kx -= 6.0


## Draws coloured text segments left to right; returns the new x.
func _seg(x: float, y: float, text: String, col: Color, size: int = 12) -> float:
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	return x + font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


func _draw_figures(y: float) -> void:
	var integ := ship.integrity()
	var ratio := ship.flood_ratio()
	var ld := absf(rad_to_deg(ship.list_rad))
	var fires := 0
	var leaks := 0
	for c in ship.compartments:
		if c.on_fire and not c.destroyed:
			fires += 1
		if c.flood_rate > 0.0 and c.flooded_tonnes < c.capacity_tonnes:
			leaks += 1
	var x := 8.0
	x = _seg(x, y, "INTEG ", Hud.C_DIM)
	x = _seg(x, y, "%d%%" % int(integ * 100.0), status_color(integ))
	x = _seg(x + 10, y, "FLOOD ", Hud.C_DIM)
	x = _seg(x, y, "%.0f/%.0f t" % [ship.total_flooded_t, ship.reserve_buoyancy_t], Hud.C_GOOD if ratio < 0.15 else (Hud.C_WARN if ratio < 0.5 else Hud.C_BAD))
	x = _seg(x + 10, y, "LIST ", Hud.C_DIM)
	x = _seg(x, y, "%.1f°" % ld, Hud.C_GOOD if ld < 3.0 else (Hud.C_WARN if ld < 8.0 else Hud.C_BAD))
	x = _seg(x + 10, y, "FIRES ", Hud.C_DIM)
	var fc := Hud.C_GOOD if fires == 0 else (Hud.C_WARN if fires < 3 else Hud.C_BAD)
	x = _seg(x, y, "%d" % fires, fc)
	var y2 := y + 17.0
	x = 8.0
	if ship.dc != null:
		var dc := ship.dc
		var busy := dc.parties.size() - dc.idle_parties()
		x = _seg(x, y2, "LEAKS ", Hud.C_DIM)
		x = _seg(x, y2, "%d" % leaks, Hud.C_GOOD if leaks == 0 else Hud.C_BAD)
		x = _seg(x + 10, y2, "PUMPS ", Hud.C_DIM)
		x = _seg(x, y2, "%.0f t/s" % dc.pumping_now if dc.pumping_now > 0.05 else "idle", Hud.C_GOOD if dc.pumping_now > 0.05 else Hud.C_DIM)
		x = _seg(x + 10, y2, "CREW ", Hud.C_DIM)
		x = _seg(x, y2, "%d%%" % int(dc.efficacy() * 100.0), status_color(clampf(dc.efficacy(), 0.0, 1.0)))
		x = _seg(x + 10, y2, "DC ", Hud.C_DIM)
		_seg(x, y2, "%s [V]" % dc.priority, Hud.C_NAV)
