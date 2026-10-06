class_name DetentGauge
extends Control
## A bridge-style order gauge: a brass-bezelled scale with fixed detents, a lever that slides
## to the ordered detent (drag it or tap a detent), and a reply pointer showing what the
## engine room / rudder is actually doing. Used for the engine order telegraph (vertical)
## and the helm (horizontal). Works the same with mouse and touch.

signal picked(idx: int)

const BRASS := Color(0.78, 0.60, 0.26)
const BRASS_LIGHT := Color(0.95, 0.80, 0.45)
const FACE := Color(0.05, 0.07, 0.08, 0.86)

var vertical := true
var title := ""
var labels: Array[String] = []
var colors: Array[Color] = []
var ordered := 0
var reply := 0.0            ## fractional detent index where the reply pointer sits
var reply_matches := true
var _vis := 0.0             ## animated lever position (fractional index)
var _drag := false
var _t := 0.0
var _bezel: StyleBoxFlat


func setup(p_title: String, p_vertical: bool, p_labels: Array[String], p_colors: Array[Color], start: int) -> void:
	title = p_title
	vertical = p_vertical
	labels = p_labels
	colors = p_colors
	ordered = start
	_vis = float(start)
	reply = float(start)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_bezel = StyleBoxFlat.new()
	_bezel.bg_color = FACE
	_bezel.border_color = BRASS
	_bezel.set_border_width_all(3)
	_bezel.set_corner_radius_all(10)


func _n() -> int:
	return labels.size()


func _track() -> Array[float]:
	## [start, end] coordinates of the first and last detent along the long axis.
	if vertical:
		return [30.0, size.y - 16.0]
	return [34.0, size.x - 34.0]


func _coord(idx: float) -> float:
	var t := _track()
	return lerpf(t[0], t[1], idx / maxf(float(_n() - 1), 1.0))


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_drag = (e as InputEventMouseButton).pressed
		if _drag:
			_pick((e as InputEventMouseButton).position)
		accept_event()
	elif e is InputEventMouseMotion and _drag:
		_pick((e as InputEventMouseMotion).position)
		accept_event()


func _pick(p: Vector2) -> void:
	var t := _track()
	var along := p.y if vertical else p.x
	var f := (along - t[0]) / (t[1] - t[0])
	var idx := clampi(roundi(f * float(_n() - 1)), 0, _n() - 1)
	picked.emit(idx)


func _process(delta: float) -> void:
	_t += delta
	_vis = move_toward(_vis, float(ordered), delta * 14.0)
	queue_redraw()


func _draw() -> void:
	if _bezel == null:
		return
	var font := ThemeDB.fallback_font
	draw_style_box(_bezel, Rect2(Vector2.ZERO, size))
	draw_string(font, Vector2(10, 17), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, BRASS_LIGHT)
	var n := _n()
	if vertical:
		var tx := size.x - 34.0
		# Slot the lever rides in.
		draw_rect(Rect2(tx - 3, _coord(0), 6, _coord(n - 1) - _coord(0)), Color(0.0, 0.0, 0.0, 0.7))
		draw_rect(Rect2(tx - 1, _coord(0), 2, _coord(n - 1) - _coord(0)), BRASS)
		for i in n:
			var y := _coord(i)
			var on := i == ordered
			var c := colors[i]
			draw_line(Vector2(tx - 28, y), Vector2(tx - 22, y), c, 2.0)
			var col := c.lightened(0.35) if on else c.darkened(0.15)
			var ts := font.get_string_size(labels[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
			draw_string(font, Vector2(tx - 32 - ts.x, y + 4), labels[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
		# Reply pointer (engine room's answer) on the right of the slot.
		var ry := _coord(reply)
		var rc := Color(0.45, 0.88, 0.5) if reply_matches else Color(1.0, 0.78, 0.25, 0.55 + 0.45 * sin(_t * 9.0))
		draw_colored_polygon(PackedVector2Array([Vector2(tx + 7, ry), Vector2(tx + 19, ry - 7), Vector2(tx + 19, ry + 7)]), rc)
		# The lever: brass handle with a pointer wedge touching the ordered detent.
		var ly := _coord(_vis)
		draw_colored_polygon(PackedVector2Array([Vector2(tx - 20, ly), Vector2(tx - 8, ly - 9), Vector2(tx + 6, ly - 9),
			Vector2(tx + 6, ly + 9), Vector2(tx - 8, ly + 9)]), BRASS)
		draw_polyline(PackedVector2Array([Vector2(tx - 20, ly), Vector2(tx - 8, ly - 9), Vector2(tx + 6, ly - 9),
			Vector2(tx + 6, ly + 9), Vector2(tx - 8, ly + 9), Vector2(tx - 20, ly)]), BRASS_LIGHT, 1.5)
		draw_line(Vector2(tx - 5, ly), Vector2(tx + 4, ly), Color(0.2, 0.14, 0.05), 2.0)
	else:
		var ty := 50.0
		draw_rect(Rect2(_coord(0), ty - 3, _coord(n - 1) - _coord(0), 6), Color(0.0, 0.0, 0.0, 0.7))
		draw_rect(Rect2(_coord(0), ty - 1, _coord(n - 1) - _coord(0), 2), BRASS)
		for i in n:
			var x := _coord(i)
			var on := i == ordered
			var c := colors[i]
			draw_line(Vector2(x, ty + 5), Vector2(x, ty + 13), c, 2.0)
			var col := c.lightened(0.35) if on else c.darkened(0.15)
			var ts := font.get_string_size(labels[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 10)
			draw_string(font, Vector2(x - ts.x * 0.5, ty + 26), labels[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)
		# Actual rudder pointer above the slot.
		var rx := _coord(reply)
		var rc2 := Color(0.45, 0.88, 0.5) if reply_matches else Color(1.0, 0.78, 0.25)
		draw_colored_polygon(PackedVector2Array([Vector2(rx, ty - 7), Vector2(rx - 7, ty - 19), Vector2(rx + 7, ty - 19)]), rc2)
		var lx := _coord(_vis)
		draw_colored_polygon(PackedVector2Array([Vector2(lx - 8, ty - 11), Vector2(lx + 8, ty - 11), Vector2(lx + 8, ty + 9),
			Vector2(lx, ty + 15), Vector2(lx - 8, ty + 9)]), BRASS)
		draw_polyline(PackedVector2Array([Vector2(lx - 8, ty - 11), Vector2(lx + 8, ty - 11), Vector2(lx + 8, ty + 9),
			Vector2(lx, ty + 15), Vector2(lx - 8, ty + 9), Vector2(lx - 8, ty - 11)]), BRASS_LIGHT, 1.5)
