class_name ShipProfile
extends Control
## The player's own-ship condition readout: a small broadside (profile) view with every compartment
## coloured by health -- hull, machinery, magazines, turrets, bridge, funnels, masts -- flooding shown
## as a blue wash, fires as flames, then a row of sailor-hat icons for the repair parties (colour =
## what each is doing) and two colourised lines of figures directly beneath.

signal clicked          ## the lower part of the widget was pressed (cycles damage-control priority)

const C_PANEL := Color(0.025, 0.04, 0.055, 0.70)
const C_EDGE := Color(0.75, 0.88, 1.0, 0.16)
const C_ACCENT := Color(0.55, 0.85, 0.95, 0.9)
const C_OK := Color(0.40, 0.80, 0.68)
const C_MID := Color(0.93, 0.74, 0.32)
const C_LOW := Color(0.93, 0.34, 0.30)
const W := 330.0
const H := 150.0
const PROFILE_H := 78.0
const CUP_IDLE := Color(0.90, 0.94, 0.97)
const CUP_TRAVEL := Color(0.95, 0.76, 0.30)
const CUP_FIRE := Color(0.98, 0.45, 0.20)
const CUP_LEAK := Color(0.38, 0.65, 0.98)
const CUP_REPAIR := Color(0.42, 0.85, 0.55)

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
	return C_OK if f >= 0.66 else (C_MID if f >= 0.33 else C_LOW)


func _health_color(c: Compartment) -> Color:
	if c.destroyed:
		return Color(0.22, 0.24, 0.28)
	return status_color(c.health_fraction())


func _process(delta: float) -> void:
	_t += delta


func _draw() -> void:
	if ship == null:
		return
	draw_rect(Rect2(0, 0, W, H), C_PANEL)
	draw_rect(Rect2(0, 0, W, H), C_EDGE, false, 1.0)
	# Corner brackets.
	var bl := 10.0
	for c in [[Vector2(0, 0), Vector2(1, 1)], [Vector2(W, 0), Vector2(-1, 1)], [Vector2(0, H), Vector2(1, -1)], [Vector2(W, H), Vector2(-1, -1)]]:
		var o: Vector2 = c[0]
		var d: Vector2 = c[1]
		draw_line(o, o + Vector2(d.x * bl, 0), C_ACCENT, 1.5)
		draw_line(o, o + Vector2(0, d.y * bl), C_ACCENT, 1.5)
	_draw_profile()
	_draw_cups(PROFILE_H + 14.0)
	_draw_figures(PROFILE_H + 14.0 + 30.0)


func _quad_poly(pts: Array, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array(pts), col)


func _draw_profile() -> void:
	var f := ShipFrame.for_entry(Roster.get_entry(ship.class_id))
	var len_m := ship.length_m
	var top := ship.top_y
	var draft := ship.draft_m
	var sc := minf((W - 28.0) / len_m, (PROFILE_H - 6.0) / (top + draft * 0.55))
	var cx := W * 0.5
	var wl := 6.0 + top * sc                         # waterline y in pixels
	var to_s := func(z: float, y: float) -> Vector2: return Vector2(cx + z * sc, wl - y * sc)
	var hl := len_m * 0.5
	# Waterline.
	draw_line(Vector2(8, wl), Vector2(W - 8, wl), Color(0.45, 0.75, 1.0, 0.35), 1.0)
	# Hull outline: sheer line above, a shallow keel below, a raked stem and a transom.
	var top_pts: Array = []
	var steps := 24
	for i in steps + 1:
		var z := -hl + len_m * float(i) / steps
		top_pts.append(to_s.call(z, f.deck_y(z)))
	var hull: Array = []
	hull.append_array(top_pts)
	hull.append(to_s.call(hl * 0.97, -draft * 0.25))
	hull.append(to_s.call(hl * 0.82, -draft * 0.55))
	hull.append(to_s.call(hl * 0.55, -draft * 0.55))
	hull.append(to_s.call(-hl * 0.6, -draft * 0.55))
	hull.append(to_s.call(-hl * 0.93, -draft * 0.35))
	hull.append(to_s.call(-hl, -draft * 0.05))
	_quad_poly(hull, Color(0.10, 0.14, 0.19, 0.95))
	# Hull sections as health-coloured bands along the keel.
	var secs := {}
	for c in ship.compartments:
		if c.kind == Compartment.Kind.HULL_SECTION:
			var key := snappedf(c.center.z, 0.01)
			if not secs.has(key):
				secs[key] = []
			secs[key].append(c)
	for key in secs:
		var list: Array = secs[key]
		var hp := 0.0
		for c in list:
			hp += 0.0 if c.destroyed else (c as Compartment).health_fraction()
		hp /= list.size()
		var c0: Compartment = list[0]
		var z0 := c0.center.z - c0.half_extents.z + 0.3
		var z1 := c0.center.z + c0.half_extents.z - 0.3
		var col := status_color(hp)
		col.a = 0.20
		var ya := f.deck_y(c0.center.z)
		_quad_poly([to_s.call(z0, ya), to_s.call(z1, ya), to_s.call(z1, -draft * 0.5), to_s.call(z0, -draft * 0.5)], col)
		col.a = 0.9
		draw_line(to_s.call(z0, ya), to_s.call(z1, ya), col, 2.0)
	draw_polyline(PackedVector2Array(hull + [hull[0]]), Color(0.70, 0.82, 0.95, 0.55), 1.0, true)
	# Flooding as a cyan fill climbing the hull from the keel.
	if ship.total_flooded_t > 1.0:
		var fr := clampf(ship.flood_ratio(), 0.0, 1.0)
		var yw := -draft * 0.5 + (draft * 0.5 + f.freeboard) * fr
		draw_line(to_s.call(-hl * 0.9, yw), to_s.call(hl * 0.8, yw), Color(0.35, 0.68, 1.0, 0.8), 1.5)
	# Compartments: internals first (small chips inside the hull), then the topside fittings.
	var order: Array[Compartment] = ship.compartments.duplicate()
	order.sort_custom(func(a: Compartment, b: Compartment) -> bool:
		return a.center.y < b.center.y)
	for c in order:
		var big := c.kind == Compartment.Kind.HULL_SECTION or c.kind == Compartment.Kind.BOW or c.kind == Compartment.Kind.STERN
		if big:
			continue
		var tl: Vector2 = to_s.call(c.center.z - c.half_extents.z, c.center.y + c.half_extents.y)
		var br: Vector2 = to_s.call(c.center.z + c.half_extents.z, c.center.y - c.half_extents.y)
		var r := Rect2(tl, br - tl).abs()
		if r.size.x < 2.5:
			r = r.grow_individual(1.25 - r.size.x * 0.5, 0, 1.25 - r.size.x * 0.5, 0)
		if r.size.y < 2.5:
			r = r.grow_individual(0, 1.25 - r.size.y * 0.5, 0, 1.25 - r.size.y * 0.5)
		var col := _health_color(c)
		var below := c.center.y + c.half_extents.y <= f.freeboard * 0.6
		match c.kind:
			Compartment.Kind.BRIDGE:
				_draw_tower(r, col)
			Compartment.Kind.FUNNEL:
				var rk := r.size.x * 0.35
				_quad_poly([r.position + Vector2(0, 0), Vector2(r.end.x - rk, r.position.y), Vector2(r.end.x, r.end.y), Vector2(r.position.x, r.end.y)].map(func(v): return v), col)
				draw_line(Vector2(r.position.x - 0.5, r.position.y), Vector2(r.end.x - rk + 0.5, r.position.y), Color(0.05, 0.06, 0.08, 0.9), 2.0)
			Compartment.Kind.MAST:
				var mx := r.position.x + r.size.x * 0.5
				draw_line(Vector2(mx, r.end.y), Vector2(mx, r.position.y), col, 1.5)
				draw_line(Vector2(mx - 3.5, r.position.y + r.size.y * 0.3), Vector2(mx + 3.5, r.position.y + r.size.y * 0.3), col, 1.2)
			Compartment.Kind.TURRET:
				var fwd := 1.0 if c.center.z >= 0.0 else -1.0
				_quad_poly([Vector2(r.position.x, r.end.y), Vector2(r.position.x, r.position.y + r.size.y * 0.4), Vector2(r.position.x + r.size.x * 0.25, r.position.y), Vector2(r.end.x - r.size.x * 0.25, r.position.y), Vector2(r.end.x, r.position.y + r.size.y * 0.4), Vector2(r.end.x, r.end.y)], col)
				var by := r.position.y + r.size.y * 0.45
				var bx := r.end.x if fwd > 0.0 else r.position.x
				draw_line(Vector2(bx, by), Vector2(bx + fwd * (r.size.x * 0.9 + 3.0), by - 1.0), col.darkened(0.15), 1.6)
			Compartment.Kind.AA_MOUNT, Compartment.Kind.SECONDARY_MOUNT, Compartment.Kind.TORPEDO_TUBES:
				draw_rect(r, col)
			Compartment.Kind.HANGAR:
				draw_rect(r, col.darkened(0.1))
				draw_rect(r, Color(0, 0, 0, 0.35), false, 1.0)
			_:
				var cc := col
				cc.a = 0.55 if below else 0.9
				draw_rect(r.grow(-0.3), cc)
				if c.kind == Compartment.Kind.MAGAZINE:
					draw_rect(r, Color(0.95, 0.72, 0.30, 0.9), false, 1.0)
		if c.flooded_tonnes > 0.0:
			var fr2 := clampf(c.flooded_tonnes / maxf(c.capacity_tonnes, 1.0), 0.0, 1.0)
			draw_rect(Rect2(r.position.x, r.end.y - r.size.y * fr2, r.size.x, r.size.y * fr2), Color(0.30, 0.62, 1.0, 0.75))
		if c.flood_rate > 0.0 and c.flooded_tonnes < c.capacity_tonnes:
			draw_rect(r.grow(1.0), Color(0.40, 0.70, 1.0, 0.95), false, 1.2)
		if c.on_fire and not c.destroyed:
			var flick := 0.6 + 0.4 * sin(_t * 12.0 + c.center.z)
			var fx := r.position.x + r.size.x * 0.5
			var fy := r.position.y
			_quad_poly([Vector2(fx - 2.5, fy), Vector2(fx + 2.5, fy), Vector2(fx, fy - 6.0 * flick - 3.0)], Color(1.0, 0.55, 0.15, flick))


## The bridge tower as stepped tiers rather than one slab.
func _draw_tower(r: Rect2, col: Color) -> void:
	var tiers := 3
	var th := r.size.y / tiers
	for i in tiers:
		var shrink := r.size.x * 0.14 * i
		var tr := Rect2(r.position.x + shrink * 0.5, r.end.y - th * (i + 1), r.size.x - shrink, th - 0.6)
		draw_rect(tr, col)
	draw_line(Vector2(r.position.x + r.size.x * 0.5, r.position.y), Vector2(r.position.x + r.size.x * 0.5, r.position.y - 3.0), col, 1.2)


func _cup(pos: Vector2, col: Color) -> void:
	# A Dixie cup, flat style: a turned-up brim band above a tapering crown.
	var crown := PackedVector2Array([pos + Vector2(2.5, 5), pos + Vector2(17.5, 5), pos + Vector2(14.5, 15), pos + Vector2(5.5, 15)])
	draw_colored_polygon(crown, col)
	draw_rect(Rect2(pos + Vector2(0, 0), Vector2(20, 5)), col.lightened(0.18))
	draw_line(pos + Vector2(0, 5.2), pos + Vector2(20, 5.2), Color(0, 0, 0, 0.35), 1.0)


func _draw_cups(y: float) -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(12, y + 12), "REPAIR", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Hud.C_DIM)
	if ship.dc == null:
		return
	var x := 68.0
	for p in ship.dc.parties:
		var col := CUP_IDLE
		var task: String = p["task"]
		if task != "IDLE":
			col = CUP_TRAVEL if float(p["travel"]) > 0.0 else (CUP_FIRE if task == "FIRE" else (CUP_LEAK if task == "LEAK" else CUP_REPAIR))
		_cup(Vector2(x, y), col)
		x += 27.0
	# Key to the hat colours, small and at the right.
	var kx := W - 12.0
	for k in [["idle", CUP_IDLE], ["fire", CUP_FIRE], ["leak", CUP_LEAK], ["fix", CUP_REPAIR]]:
		var ts := font.get_string_size(k[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 9)
		kx -= ts.x
		draw_string(font, Vector2(kx, y + 12), k[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, k[1])
		kx -= 8.0


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
	var x := 12.0
	x = _seg(x, y, "INTEG ", Hud.C_DIM)
	x = _seg(x, y, "%d%%" % int(integ * 100.0), status_color(integ))
	x = _seg(x + 10, y, "FLOOD ", Hud.C_DIM)
	x = _seg(x, y, "%.0f/%.0f t" % [ship.total_flooded_t, ship.reserve_buoyancy_t], C_OK if ratio < 0.15 else (C_MID if ratio < 0.5 else C_LOW))
	x = _seg(x + 10, y, "LIST ", Hud.C_DIM)
	x = _seg(x, y, "%.1f°" % ld, C_OK if ld < 3.0 else (C_MID if ld < 8.0 else C_LOW))
	x = _seg(x + 10, y, "FIRES ", Hud.C_DIM)
	var fc := C_OK if fires == 0 else (C_MID if fires < 3 else C_LOW)
	x = _seg(x, y, "%d" % fires, fc)
	var y2 := y + 17.0
	x = 12.0
	if ship.dc != null:
		var dc := ship.dc
		var busy := dc.parties.size() - dc.idle_parties()
		x = _seg(x, y2, "LEAKS ", Hud.C_DIM)
		x = _seg(x, y2, "%d" % leaks, C_OK if leaks == 0 else C_LOW)
		x = _seg(x + 10, y2, "PUMPS ", Hud.C_DIM)
		x = _seg(x, y2, "%.0f t/s" % dc.pumping_now if dc.pumping_now > 0.05 else "idle", C_OK if dc.pumping_now > 0.05 else Hud.C_DIM)
		x = _seg(x + 10, y2, "CREW ", Hud.C_DIM)
		x = _seg(x, y2, "%d%%" % int(dc.efficacy() * 100.0), status_color(clampf(dc.efficacy(), 0.0, 1.0)))
		x = _seg(x + 10, y2, "DC ", Hud.C_DIM)
		_seg(x, y2, "%s [V]" % dc.priority, Hud.C_NAV)
