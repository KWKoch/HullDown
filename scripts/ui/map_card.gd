class_name MapCard
extends Control
## A map thumbnail card: shaded relief, start positions and named waypoints, title, date, blurb.

signal opened(ground_id: String)

var ground: Dictionary = {}
var tex: Texture2D
var selected := false
var _hover := false
var _lift := 0.0


func setup(g: Dictionary) -> void:
	ground = g
	custom_minimum_size = Vector2(360, 560)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func(): _hover = true)
	mouse_exited.connect(func(): _hover = false)


func set_texture(t: Texture2D) -> void:
	tex = t
	queue_redraw()


func _process(d: float) -> void:
	var target := 1.0 if _hover else 0.0
	if absf(_lift - target) > 0.005:
		_lift = move_toward(_lift, target, d * 7.0)
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		opened.emit(ground["id"])
	elif event is InputEventScreenTouch and event.pressed:
		opened.emit(ground["id"])


func _draw() -> void:
	var gold := UIKit.GOLD
	var body := Rect2(Vector2(4, 8 - 5.0 * _lift), size - Vector2(8, 18))
	var sb := UIKit.box(Color(0.14, 0.20, 0.30, 0.94).lerp(Color(0.2, 0.28, 0.4, 0.97), _lift), Color(0.06, 0.09, 0.14, 0.96), 
		Color(gold.r, gold.g, gold.b, 0.85) if selected else Color(1, 1, 1, 0.16 + 0.3 * _lift), 18.0, 0.8,
		Color(gold.r, gold.g, gold.b, 0.28) if selected else Color(UIKit.CYAN.r, UIKit.CYAN.g, UIKit.CYAN.b, 0.22 * _lift), 0.0)
	sb.border_w = 1.8 if selected else 1.3
	draw_style_box(sb, body)
	var img := Rect2(body.position + Vector2(10, 10), Vector2(body.size.x - 20, body.size.x - 20))
	var rp := UIKit.rrect(img, 12.0, 8)
	if tex != null:
		var uvs := PackedVector2Array()
		var cols := PackedColorArray()
		for p in rp:
			uvs.append((p - img.position) / img.size)
			cols.append(Color(1, 1, 1, 1))
		draw_polygon(rp, cols, uvs, tex)
	else:
		draw_colored_polygon(rp, Color(0.06, 0.1, 0.15))
		draw_string(UIKit.font("body"), img.position + Vector2(img.size.x * 0.5 - 60, img.size.y * 0.5), "rendering map...", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UIKit.DIM)
	# inner vignette + border on the map image
	var edge := rp.duplicate()
	edge.append(rp[0])
	draw_polyline(edge, Color(1, 1, 1, 0.22), 1.2, true)
	var sz: Vector2 = ground["size_m"]
	for wp in Battlegrounds.waypoints(ground["id"]):
		var u := MapData.to_card(wp["p"], sz)
		var pt := img.position + Vector2(u.x * img.size.x, u.y * img.size.y)
		var col := MapData.kind_color(wp["k"])
		draw_circle(pt + Vector2(0, 1.5), 7.5, Color(0, 0, 0, 0.35))
		draw_circle(pt, 6.5, Color(1, 1, 1, 0.95))
		draw_circle(pt, 4.6, col)
	var locked := not Progress.is_unlocked(String(ground["id"]))
	if locked:
		var shade := PackedColorArray()
		for _p in rp:
			shade.append(Color(0.03, 0.05, 0.09, 0.78))
		draw_polygon(rp, shade)
		_draw_lock(img.get_center() + Vector2(0, -26), 1.0)
		var ut := Battlegrounds.unlock_text(String(ground["id"]))
		var parts := ut.split("  -  ")
		draw_string(UIKit.font("caps"), Vector2(img.position.x, img.get_center().y + 40), "CAMPAIGN UNLOCK", HORIZONTAL_ALIGNMENT_CENTER, img.size.x, 14, UIKit.GOLD)
		draw_string(UIKit.font("semi"), Vector2(img.position.x, img.get_center().y + 64), parts[0], HORIZONTAL_ALIGNMENT_CENTER, img.size.x, 17, UIKit.INK)
		if parts.size() > 1:
			draw_string(UIKit.font("body"), Vector2(img.position.x, img.get_center().y + 86), parts[1], HORIZONTAL_ALIGNMENT_CENTER, img.size.x, 13, UIKit.DIM.lightened(0.25))
	# mode badge
	var pvp := Battlegrounds.is_pvp(String(ground["id"]))
	var btxt := "PVP  READY" if pvp else "CAMPAIGN"
	var bcol := Color(0.30, 0.55, 0.95) if pvp else Color(0.55, 0.42, 0.9)
	var bw := UIKit.font("caps").get_string_size(btxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 22
	UIKit.fill_round(self, Rect2(img.position + Vector2(10, 10), Vector2(bw, 24)), 12.0, bcol.lightened(0.1), bcol.darkened(0.3))
	draw_string(UIKit.font("caps"), img.position + Vector2(21, 27), btxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
	# compass tag
	UIKit.fill_round(self, Rect2(img.position + Vector2(8, img.size.y - 34), Vector2(26, 26)), 13.0, Color(0, 0, 0, 0.55), Color(0, 0, 0, 0.55))
	draw_string(UIKit.font("semi"), img.position + Vector2(15.5, img.size.y - 15), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.95))
	var y := img.end.y + 30.0
	draw_string(UIKit.font("semi"), Vector2(body.position.x + 16, y), String(ground["name"]), HORIZONTAL_ALIGNMENT_LEFT, body.size.x - 30, 19, UIKit.INK)
	# chips
	var chips := [String(ground["date"]), String(ground.get("weather", "clear")).capitalize(), _tod(float(ground["time_of_day"]))]
	var cx := body.position.x + 16.0
	var cy := y + 12.0
	for c in chips:
		var tw := UIKit.font("body").get_string_size(c, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var cr := Rect2(cx, cy, tw + 18, 22)
		if cx + cr.size.x > body.end.x - 12:
			break
		UIKit.fill_round(self, cr, 11.0, Color(1, 1, 1, 0.10), Color(1, 1, 1, 0.05))
		draw_string(UIKit.font("body"), Vector2(cx + 9, cy + 15), c, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIKit.DIM.lightened(0.2))
		cx += cr.size.x + 6
	draw_multiline_string(UIKit.font("body"), Vector2(body.position.x + 16, cy + 46), String(ground["blurb"]), HORIZONTAL_ALIGNMENT_LEFT, body.size.x - 32, 13, 4, Color(0.78, 0.84, 0.9))
	var hint := "3D TOPO MAP"
	draw_string(UIKit.font("caps"), Vector2(body.end.x - 16 - UIKit.font("caps").get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x - 14, body.end.y - 14), hint + "  >", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, gold)
	if selected:
		UIKit.fill_round(self, Rect2(body.position + Vector2(14, body.size.y - 34), Vector2(84, 22)), 11.0, Color(0.2, 0.55, 0.3, 0.9), Color(0.12, 0.4, 0.22, 0.9))
		draw_string(UIKit.font("caps"), body.position + Vector2(24, body.size.y - 18), "SELECTED", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)


func _draw_lock(c: Vector2, k: float) -> void:
	var body := Rect2(c + Vector2(-22, -2) * k, Vector2(44, 34) * k)
	draw_arc(c + Vector2(0, -4) * k, 14.0 * k, PI, TAU, 24, Color(0.85, 0.88, 0.95, 0.95), 6.0 * k, true)
	UIKit.fill_round(self, body, 8.0 * k, Color(0.96, 0.78, 0.30), Color(0.78, 0.55, 0.12))
	draw_circle(body.get_center() + Vector2(0, -2) * k, 4.5 * k, Color(0.25, 0.17, 0.04))
	draw_rect(Rect2(body.get_center() + Vector2(-1.8, 0) * k, Vector2(3.6, 10) * k), Color(0.25, 0.17, 0.04))


func _tod(h: float) -> String:
	if h < 5.0 or h > 20.0:
		return "Night"
	if h < 8.0:
		return "Dawn"
	if h > 16.5:
		return "Dusk"
	return "Day"
