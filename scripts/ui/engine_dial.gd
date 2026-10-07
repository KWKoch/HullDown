class_name EngineDial
extends DetentGauge
## A round brass engine-order telegraph: cream face split into sectors (STOP at the top, ahead
## orders sweeping clockwise on the right, astern orders on the left), a brass lever that swings
## to the ordered sector and a small pointer on the rim for what the engine room has answered.
## Same interface as DetentGauge, so the HUD drives it identically. Drag or tap to ring an order.

const CREAM := Color(0.93, 0.90, 0.78)
const INK := Color(0.10, 0.09, 0.07)
## Dial angle (degrees clockwise from straight up) of each detent, in ENGINE_ORDERS order.
const ANGLES := [150.0, 120.0, 90.0, 60.0, 30.0, 0.0, -40.0, -80.0, -120.0]


func _angle_of(f: float) -> float:
	var n := _n()
	if n != ANGLES.size():
		return lerpf(150.0, -120.0, f / maxf(float(n - 1), 1.0))
	var i := clampi(int(floorf(f)), 0, n - 2)
	return lerpf(ANGLES[i], ANGLES[i + 1], clampf(f - float(i), 0.0, 1.0))


func _geom() -> Array:
	var ls := size / k
	var r := minf(ls.x * 0.5 - 4.0, ls.y - 34.0)
	r = minf(r, ls.y * 0.5 - 2.0) if ls.y < ls.x else r
	return [Vector2(ls.x * 0.5, ls.y - r - 4.0), r]


func _pick(p: Vector2) -> void:
	var g := _geom()
	var c: Vector2 = g[0]
	var d := p - c
	if d.length() < 14.0:
		return
	var a := rad_to_deg(atan2(d.x, -d.y))
	var best := 0
	var best_d := 1e9
	for i in _n():
		var diff := absf(fposmod(a - _angle_of(float(i)) + 180.0, 360.0) - 180.0)
		if diff < best_d:
			best_d = diff
			best = i
	picked.emit(best)


func _dir(a_deg: float) -> Vector2:
	var a := deg_to_rad(a_deg)
	return Vector2(sin(a), -cos(a))


func _draw() -> void:
	if _bezel == null:
		return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(k, k))
	var font := ThemeDB.fallback_font
	var g := _geom()
	var c: Vector2 = g[0]
	var r: float = g[1]
	# Bezel, face.
	draw_circle(c, r + 3.0, Color(0, 0, 0, 0.55))
	draw_circle(c, r, BRASS)
	draw_arc(c, r - 1.5, 0.0, TAU, 64, BRASS_LIGHT, 2.0, true)
	draw_circle(c, r - 8.0, CREAM)
	draw_arc(c, r - 8.0, 0.0, TAU, 64, Color(0.25, 0.18, 0.08), 1.5, true)
	var n := _n()
	# Sector dividers midway between detents; the gap at the bottom stays blank.
	for i in n - 1:
		var mid := (_angle_of(float(i)) + _angle_of(float(i + 1))) * 0.5
		draw_line(c + _dir(mid) * r * 0.34, c + _dir(mid) * (r - 8.0), INK, 1.5)
	draw_line(c + _dir(_angle_of(0.0) + 15.0) * r * 0.34, c + _dir(_angle_of(0.0) + 15.0) * (r - 8.0), INK, 1.5)
	draw_line(c + _dir(_angle_of(float(n - 1)) - 20.0) * r * 0.34, c + _dir(_angle_of(float(n - 1)) - 20.0) * (r - 8.0), INK, 1.5)
	# Order names, set along the radius.
	for i in n:
		var a := _angle_of(float(i))
		var on := i == ordered
		var col := colors[i].darkened(0.55) if colors[i] != Color(0.62, 0.68, 0.72) else INK
		var fs := 15 if on else 13
		var txt := labels[i]
		var ts := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var rot := deg_to_rad(a) - PI * 0.5
		if a < -1.0:
			rot += PI
		if absf(a) < 1.0:
			rot = 0.0
		var at := c + _dir(a) * r * 0.64
		draw_set_transform(at * k, rot, Vector2(k, k))
		draw_string(font, Vector2(-ts.x * 0.5, fs * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		if on:
			draw_line(Vector2(-ts.x * 0.5, fs * 0.36 + 3.0), Vector2(ts.x * 0.5, fs * 0.36 + 3.0), col, 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(k, k))
	var cap := "ENGINE"
	var cs := font.get_string_size(cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 10)
	draw_string(font, c + Vector2(-cs.x * 0.5, r * 0.34 + 16.0), cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, INK)
	# Reply pointer on the rim.
	var ra := _angle_of(reply)
	var rc := Color(0.15, 0.55, 0.2) if reply_matches else Color(0.85, 0.5, 0.0, 0.55 + 0.45 * sin(_t * 9.0))
	var rd := _dir(ra)
	var rp := Vector2(-rd.y, rd.x)
	draw_colored_polygon(PackedVector2Array([c + rd * (r - 9.0), c + rd * (r - 21.0) + rp * 7.0, c + rd * (r - 21.0) - rp * 7.0]), rc)
	# Lever: brass arm with a knob, and a short counterweight tail.
	var la := _angle_of(_vis)
	var ld := _dir(la)
	var tip := c + ld * (r * 0.86)
	var tail := c - ld * (r * 0.26)
	draw_line(tail, tip, Color(0.15, 0.1, 0.03), 11.0, true)
	draw_line(tail, tip, BRASS, 8.0, true)
	draw_line(tail, tip, BRASS_LIGHT, 2.0, true)
	draw_circle(tip, 8.0, Color(0.15, 0.1, 0.03))
	draw_circle(tip, 6.5, BRASS_LIGHT)
	draw_circle(c, 14.0, Color(0.15, 0.1, 0.03))
	draw_circle(c, 12.0, BRASS)
	draw_circle(c, 4.0, BRASS_LIGHT)
