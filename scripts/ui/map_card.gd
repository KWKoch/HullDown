class_name MapCard
extends Control
## A map thumbnail card: shaded relief, start positions and named waypoints, title, date, blurb.

signal opened(ground_id: String)

var ground: Dictionary = {}
var tex: Texture2D
var selected := false
var _hover := false


func setup(g: Dictionary) -> void:
	ground = g
	custom_minimum_size = Vector2(360, 540)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func(): _hover = true; queue_redraw())
	mouse_exited.connect(func(): _hover = false; queue_redraw())


func set_texture(t: Texture2D) -> void:
	tex = t
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		opened.emit(ground["id"])
	elif event is InputEventScreenTouch and event.pressed:
		opened.emit(ground["id"])


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0.09, 0.13, 0.19, 0.96) if not _hover else Color(0.12, 0.18, 0.26, 0.98))
	draw_rect(r, Color(1.0, 0.75, 0.25) if selected else (Color(0.55, 0.75, 1.0) if _hover else Color(0.28, 0.38, 0.5)), false, 3.0 if selected or _hover else 1.5)
	var img := Rect2(10, 10, size.x - 20, size.x - 20)
	if tex != null:
		draw_texture_rect(tex, img, false)
	else:
		draw_rect(img, Color(0.06, 0.1, 0.15))
		draw_string(font, img.position + Vector2(img.size.x * 0.5 - 60, 150), "rendering map...", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.6, 0.7, 0.8))
	# map is square; keep the image square-ish by drawing within a square fitted in the rect
	var sz: Vector2 = ground["size_m"]
	for wp in Battlegrounds.waypoints(ground["id"]):
		var u := MapData.to_card(wp["p"], sz)
		var pt := img.position + Vector2(u.x * img.size.x, u.y * img.size.y)
		var col := MapData.kind_color(wp["k"])
		draw_circle(pt, 5.5, Color(0, 0, 0, 0.7))
		draw_circle(pt, 4.0, col)
	draw_string(font, Vector2(20, img.end.y - 8), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.9))
	draw_string(font, Vector2(16, img.end.y + 32), String(ground["name"]), HORIZONTAL_ALIGNMENT_LEFT, size.x - 30, 20, Color(1, 0.95, 0.85))
	draw_string(font, Vector2(16, img.end.y + 56), "%s  -  %s  -  %s" % [ground["date"], String(ground.get("weather", "clear")).capitalize(), _tod(float(ground["time_of_day"]))], HORIZONTAL_ALIGNMENT_LEFT, size.x - 30, 13, Color(0.65, 0.78, 0.92))
	draw_multiline_string(font, Vector2(16, img.end.y + 80), String(ground["blurb"]), HORIZONTAL_ALIGNMENT_LEFT, size.x - 32, 13, 4, Color(0.82, 0.86, 0.9))
	var hint := "3D TOPO MAP  >"
	draw_string(font, Vector2(size.x - 20 - font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x, size.y - 14), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.78, 0.3))
	if selected:
		draw_string(font, Vector2(16, size.y - 14), "SELECTED", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.5, 1.0, 0.6))


func _tod(h: float) -> String:
	if h < 5.0 or h > 20.0:
		return "Night"
	if h < 8.0:
		return "Dawn"
	if h > 16.5:
		return "Dusk"
	return "Day"
