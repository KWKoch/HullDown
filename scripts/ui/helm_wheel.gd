class_name HelmWheel
extends DetentGauge
## A literal ship's wheel as the steering indicator. It turns with the actual rudder (clockwise to
## starboard), a fixed pointer at the top marks midships, and the hub shows the ordered helm.
## Drag across it, or use the port / starboard buttons beside it, to order the helm.

const WOOD := Color(0.46, 0.29, 0.14)
const WOOD_LIGHT := Color(0.66, 0.44, 0.22)


func _geom() -> Array:
	var ls := size / k
	return [ls * 0.5, minf(ls.x, ls.y) * 0.5 - 6.0]


func _pick(p: Vector2) -> void:
	var g := _geom()
	var c: Vector2 = g[0]
	var r: float = g[1]
	var f := clampf((p.x - c.x) / (r * 0.9), -1.0, 1.0)
	var mid := float(_n() - 1) * 0.5
	picked.emit(clampi(roundi(mid + f * mid), 0, _n() - 1))


func _draw() -> void:
	if _bezel == null:
		return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(k, k))
	var font := ThemeDB.fallback_font
	var g := _geom()
	var c: Vector2 = g[0]
	var r: float = g[1]
	var mid := float(_n() - 1) * 0.5
	var theta := (reply - mid) / mid * deg_to_rad(270.0)
	var rim := r * 0.74
	draw_circle(c, r * 0.80, Color(0.03, 0.05, 0.07, 0.8))
	# Handles first (they stick out past the rim), then rim, inner ring, spokes, hub.
	for i in 8:
		var a := theta + float(i) * TAU / 8.0
		var d := Vector2(sin(a), -cos(a))
		draw_line(c + d * r * 0.2, c + d * r * 0.98, Color(0.1, 0.06, 0.02), 9.0, true)
		draw_line(c + d * r * 0.2, c + d * r * 0.98, WOOD, 6.5, true)
		draw_circle(c + d * r * 0.98, 5.5, WOOD_LIGHT)
	draw_arc(c, rim, 0.0, TAU, 64, Color(0.1, 0.06, 0.02), 11.0, true)
	draw_arc(c, rim, 0.0, TAU, 64, WOOD, 8.0, true)
	draw_arc(c, rim - 1.5, 0.0, TAU, 64, WOOD_LIGHT, 2.0, true)
	draw_arc(c, r * 0.30, 0.0, TAU, 40, BRASS, 4.0, true)
	# King spoke: a brass band on the rim so the turn reads at a glance.
	var kd := Vector2(sin(theta), -cos(theta))
	draw_line(c + kd * (rim - 6.0), c + kd * (rim + 6.0), BRASS_LIGHT, 5.0)
	draw_circle(c, r * 0.17, Color(0.15, 0.1, 0.03))
	draw_circle(c, r * 0.14, BRASS)
	# Fixed midships pointer at the top.
	var rc := Color(0.45, 0.88, 0.5) if reply_matches else Color(1.0, 0.78, 0.25)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 0.60), c + Vector2(-7, -r * 0.60 - 12), c + Vector2(7, -r * 0.60 - 12)]), rc)
	# Ordered helm in the hub.
	var oi := ordered
	var txt := "MID"
	var col: Color = colors[oi]
	if float(oi) < mid:
		txt = "P " + labels[oi]
	elif float(oi) > mid:
		txt = "S " + labels[oi]
	var ts := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	draw_string(font, Vector2(c.x - ts.x * 0.5, c.y + r * 0.50), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col.lightened(0.3))
