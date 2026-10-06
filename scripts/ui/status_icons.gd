class_name StatusIcons
extends RefCounted
## Small status glyphs shown under every ship's nameplate (and on the player's profile panel) for
## whatever is wrong with the ship: fire, magazine fire, flooding, list, no steering, no power,
## guns out. Amber = trouble, red (pulsing) = critical.

const WARN := Color(1.00, 0.78, 0.25)
const CRIT := Color(1.00, 0.32, 0.28)
const FIRE := Color(1.00, 0.52, 0.16)
const WATER := Color(0.42, 0.70, 1.00)


## Returns [{id, level (1 warn, 2 critical), n}] for a ship, most severe first.
static func compute(s: Ship) -> Array:
	var out: Array = []
	var fires := 0
	var mag_fire := false
	for c in s.compartments:
		if c.on_fire and not c.destroyed:
			fires += 1
			if c.kind == Compartment.Kind.MAGAZINE:
				mag_fire = true
	if mag_fire:
		out.append({"id": "mag", "level": 2, "n": 1})
	if fires > 0:
		out.append({"id": "fire", "level": 2 if fires >= 4 else 1, "n": fires})
	var fr := s.flood_ratio()
	if fr >= 0.03 or s.total_flooded_t > 5.0:
		out.append({"id": "flood", "level": 2 if fr >= 0.5 else 1, "n": 0})
	var ld := absf(rad_to_deg(s.list_rad))
	if ld >= 4.0:
		out.append({"id": "list", "level": 2 if ld >= 12.0 else 1, "n": 0})
	var st := s.steering_fraction()
	if st < 0.3:
		out.append({"id": "steer", "level": 2 if st < 0.05 else 1, "n": 0})
	var pr := s.propulsion_fraction()
	if pr < 0.6:
		out.append({"id": "power", "level": 2 if pr < 0.1 else 1, "n": 0})
	if not s.gun_turrets().is_empty():
		var bf := s.battery_fraction()
		if bf < 0.5:
			out.append({"id": "guns", "level": 2 if bf <= 0.0 else 1, "n": 0})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["level"]) > int(b["level"]))
	return out


## Draws one chip with its glyph; `pos` is the top-left, `sz` the side length in pixels.
static func draw(cv: CanvasItem, pos: Vector2, sz: float, st: Dictionary, t: float) -> void:
	var lvl: int = st["level"]
	var base := CRIT if lvl >= 2 else WARN
	var pulse := 1.0 if lvl < 2 else (0.7 + 0.3 * sin(t * 8.0))
	var edge := Color(base.r, base.g, base.b, 0.9 * pulse)
	cv.draw_rect(Rect2(pos, Vector2(sz, sz)), Color(0.03, 0.05, 0.08, 0.82))
	cv.draw_rect(Rect2(pos, Vector2(sz, sz)), edge, false, 1.0)
	var c := pos + Vector2(sz, sz) * 0.5
	var u := sz * 0.5 - 2.5          # glyph half-size
	match String(st["id"]):
		"fire":
			var pts := PackedVector2Array([c + Vector2(0, -u), c + Vector2(u * 0.55, -u * 0.1), c + Vector2(u * 0.75, u * 0.35),
				c + Vector2(u * 0.35, u), c + Vector2(-u * 0.35, u), c + Vector2(-u * 0.75, u * 0.35), c + Vector2(-u * 0.45, -u * 0.2),
				c + Vector2(-u * 0.1, u * 0.0)])
			cv.draw_colored_polygon(pts, FIRE)
			cv.draw_colored_polygon(PackedVector2Array([c + Vector2(0, u * 0.15), c + Vector2(u * 0.3, u * 0.6), c + Vector2(0, u * 0.95), c + Vector2(-u * 0.3, u * 0.6)]), Color(1.0, 0.88, 0.4))
		"mag":
			var star := PackedVector2Array()
			for i in 16:
				var a := TAU * float(i) / 16.0
				var r := u if i % 2 == 0 else u * 0.5
				star.append(c + Vector2(cos(a), sin(a)) * r)
			cv.draw_colored_polygon(star, CRIT)
			cv.draw_circle(c, u * 0.28, Color(1.0, 0.9, 0.6))
		"flood":
			for i in 2:
				var y := c.y - u * 0.15 + i * u * 0.7
				var pts2 := PackedVector2Array()
				for k in 9:
					var x := c.x - u + 2.0 * u * float(k) / 8.0
					pts2.append(Vector2(x, y + sin(float(k) * 1.6 + t * 3.0) * u * 0.22))
				cv.draw_polyline(pts2, WATER, 1.6, true)
			cv.draw_line(c + Vector2(-u * 0.6, -u * 0.55), c + Vector2(u * 0.6, -u * 0.55), WATER.darkened(0.2), 1.2)
		"list":
			cv.draw_set_transform(c, deg_to_rad(18.0), Vector2.ONE)
			cv.draw_colored_polygon(PackedVector2Array([Vector2(-u, -u * 0.1), Vector2(u, -u * 0.1), Vector2(u * 0.6, u * 0.5), Vector2(-u * 0.6, u * 0.5)]), WARN if lvl < 2 else CRIT)
			cv.draw_line(Vector2(0, -u * 0.1), Vector2(0, -u * 0.9), Color(0.9, 0.92, 0.95), 1.2)
			cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			cv.draw_line(c + Vector2(-u, u * 0.7), c + Vector2(u, u * 0.7), WATER, 1.0)
		"steer":
			cv.draw_arc(c, u * 0.62, 0.0, TAU, 14, Color(0.85, 0.9, 0.95), 1.4, true)
			for i in 4:
				var a2 := PI * 0.5 * i
				cv.draw_line(c + Vector2(cos(a2), sin(a2)) * u * 0.2, c + Vector2(cos(a2), sin(a2)) * u, Color(0.85, 0.9, 0.95), 1.4)
			cv.draw_line(c + Vector2(-u, u), c + Vector2(u, -u), edge, 1.8)
		"power":
			for i in 3:
				var a3 := TAU * float(i) / 3.0 - PI * 0.5
				var tip := c + Vector2(cos(a3), sin(a3)) * u
				var side := Vector2(-sin(a3), cos(a3)) * u * 0.35
				cv.draw_colored_polygon(PackedVector2Array([c + side * 0.4, tip + side, tip - side * 0.4, c - side * 0.4]), Color(0.85, 0.9, 0.95))
			cv.draw_line(c + Vector2(-u, u), c + Vector2(u, -u), edge, 1.8)
		"guns":
			cv.draw_rect(Rect2(c + Vector2(-u, -u * 0.15), Vector2(u * 1.4, u * 0.4)), Color(0.85, 0.9, 0.95))
			cv.draw_rect(Rect2(c + Vector2(-u * 0.6, u * 0.2), Vector2(u * 1.0, u * 0.55)), Color(0.85, 0.9, 0.95))
			cv.draw_line(c + Vector2(-u, u), c + Vector2(u, -u), edge, 1.8)
	if int(st["n"]) > 1:
		cv.draw_string(ThemeDB.fallback_font, pos + Vector2(sz - 6.0, sz + 9.0), str(int(st["n"])), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, FIRE)
