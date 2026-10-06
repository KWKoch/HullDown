class_name MapView
extends Control
## Top-down tactical map: terrain relief and depth (shoals are pale), the fused contact
## picture, and radar coverage. North is up and east is right (the game's +Z is north, and
## -X is east). One instance is the small local minimap, another the full-battleground view.

signal clicked
signal wheel(direction: int)

const C_FRIEND := Color(0.35, 0.92, 0.78)
const C_ENEMY := Color(1.0, 0.34, 0.30)
const C_NAV := Color(0.30, 0.82, 0.86)
const C_TEXT := Color(0.94, 0.96, 0.97)
const C_DIM := Color(0.62, 0.68, 0.72)

static var _tex: ImageTexture
static var _tex_owner := 0
const TEX_N := 160

var terrain: BattleTerrain
var sensors: SensorNet
var player: Ship
var span_m := 6000.0                 ## world width shown across the control
var follow_player := true
var big := false
var title := "TACTICAL"
var _center := Vector2.ZERO          ## world (x, z) at the middle of the view


func setup(p_terrain: BattleTerrain, p_sensors: SensorNet, p_player: Ship, p_big: bool) -> void:
	terrain = p_terrain
	sensors = p_sensors
	player = p_player
	big = p_big
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	follow_player = not p_big
	if p_big:
		span_m = maxf(terrain.size.x, terrain.size.y) * 1.04
	ensure_texture(terrain)


## Renders the whole battleground once: depth bands for water, relief-shaded land.
## Oriented north-up / east-right (image x grows toward -X, image y toward -Z).
static func ensure_texture(t: BattleTerrain, force := false) -> void:
	if _tex != null and _tex_owner == t.get_instance_id() and not force:
		return
	var n := TEX_N
	var hs := PackedFloat32Array()
	hs.resize(n * n)
	var hx := t.size.x * 0.5
	var hz := t.size.y * 0.5
	for j in n:
		for i in n:
			var wx := hx - (float(i) + 0.5) / n * t.size.x
			var wz := hz - (float(j) + 0.5) / n * t.size.y
			hs[j * n + i] = t.height_at(wx, wz)
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for j in n:
		for i in n:
			var h := hs[j * n + i]
			var c: Color
			if h < 0.0:
				if h < -80.0:
					c = Color(0.03, 0.10, 0.20)
				elif h < -26.0:
					c = Color(0.03, 0.10, 0.20).lerp(Color(0.06, 0.24, 0.36), (h + 80.0) / 54.0)
				elif h < -9.0:
					c = Color(0.06, 0.24, 0.36).lerp(Color(0.16, 0.44, 0.50), (h + 26.0) / 17.0)
				else:
					c = Color(0.16, 0.44, 0.50).lerp(Color(0.62, 0.78, 0.66), (h + 9.0) / 9.0)    # shoals: pale = danger
			else:
				if h < 4.0:
					c = Color(0.76, 0.70, 0.50)
				elif h < 60.0:
					c = Color(0.76, 0.70, 0.50).lerp(Color(0.24, 0.42, 0.22), clampf((h - 4.0) / 30.0, 0.0, 1.0))
				elif h < 200.0:
					c = Color(0.24, 0.42, 0.22).lerp(Color(0.46, 0.36, 0.26), clampf((h - 60.0) / 100.0, 0.0, 1.0))
				else:
					c = Color(0.46, 0.36, 0.26).lerp(Color(0.72, 0.72, 0.74), clampf((h - 200.0) / 300.0, 0.0, 1.0))
				# Relief shading from the local slope.
				var hl := hs[j * n + maxi(i - 1, 0)]
				var hr := hs[j * n + mini(i + 1, n - 1)]
				var hu := hs[maxi(j - 1, 0) * n + i]
				var hd := hs[mini(j + 1, n - 1) * n + i]
				var shade := clampf(((hl - hr) + (hu - hd)) * 0.004, -0.2, 0.2)
				c = c.lightened(shade) if shade > 0.0 else c.darkened(-shade)
			img.set_pixel(i, j, c)
	_tex = ImageTexture.create_from_image(img)
	_tex_owner = t.get_instance_id()


func _w2s(p: Vector3) -> Vector2:
	var sc := size.x / span_m
	return size * 0.5 + Vector2(-(p.x - _center.x), -(p.z - _center.y)) * sc


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			clicked.emit()
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			wheel.emit(1)
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			wheel.emit(-1)
			accept_event()


func _process(_d: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	if terrain == null or player == null or _tex == null:
		return
	_center = Vector2(player.global_position.x, player.global_position.z) if follow_player else Vector2.ZERO
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.05, 0.95))
	var tl := _w2s(Vector3(terrain.size.x * 0.5, 0.0, terrain.size.y * 0.5))
	var br := _w2s(Vector3(-terrain.size.x * 0.5, 0.0, -terrain.size.y * 0.5))
	draw_texture_rect(_tex, Rect2(tl, br - tl), false)
	var sc := size.x / span_m
	# Grid every 2 km (labelled in the big view).
	var grid := 2000.0
	var k0 := int(floor((_center.x - span_m * 0.5) / grid))
	var k1 := int(ceil((_center.x + span_m * 0.5) / grid))
	for k in range(k0, k1 + 1):
		var x := _w2s(Vector3(k * grid, 0, 0)).x
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color(1, 1, 1, 0.08), 1.0)
	var m0 := int(floor((_center.y - span_m * 0.5) / grid))
	var m1 := int(ceil((_center.y + span_m * 0.5) / grid))
	for m in range(m0, m1 + 1):
		var y := _w2s(Vector3(0, 0, m * grid)).y
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(1, 1, 1, 0.08), 1.0)
	# Radar coverage: every friendly set (the shared picture) in the big view, only your own in the mini.
	if sensors != null:
		for o in sensors.observers:
			var s: Ship = o["ship"]
			if not big and s != player:
				continue
			var p := _w2s(s.global_position)
			var rr: float = float(o["radar"]) * sc
			var own := s == player
			if big:
				draw_circle(p, rr, Color(C_NAV.r, C_NAV.g, C_NAV.b, 0.05 if not own else 0.08))
			draw_arc(p, rr, 0.0, TAU, 72, Color(C_NAV.r, C_NAV.g, C_NAV.b, 0.9 if own else 0.4), 1.6 if own else 1.0)
			if own:
				var vr: float = float(o["visual"]) * sc
				draw_arc(p, vr, 0.0, TAU, 56, Color(1, 1, 1, 0.3), 1.0)
	# Contacts.
	if sensors != null:
		for k in sensors.picture:
			var sh := k as Ship
			if sh == null or not is_instance_valid(sh):
				continue
			var info: Dictionary = sensors.picture[k]
			var friend := sh.team == player.team
			var live: bool = info["live"]
			var wp: Vector3 = sh.global_position if live else info["pos"]
			var h: float = sh.heading if live else float(info["heading"])
			var pos := _w2s(wp)
			if pos.x < -20 or pos.y < -20 or pos.x > size.x + 20 or pos.y > size.y + 20:
				continue
			var fwd := Vector2(-sin(h), -cos(h))
			var col := C_FRIEND if friend else C_ENEMY
			var spd: float = sh.speed_ms if live else float(info["speed"])
			if absf(spd) > 0.5:
				draw_line(pos, pos + fwd * clampf(spd * 45.0 * sc, 6.0, 70.0) * signf(spd), Color(col.r, col.g, col.b, 0.8), 1.2)
			var px := ShipIcon.default_px(sh.ship_type) * (1.15 if big else 0.85)
			if sh == player:
				ShipIcon.draw(self, pos, fwd, sh.ship_type, px, Color(1, 1, 1), C_NAV)
			elif live:
				ShipIcon.draw(self, pos, fwd, sh.ship_type, px, col)
			else:
				ShipIcon.draw(self, pos, fwd, sh.ship_type, px, Color(col.r, col.g, col.b, 0.55), col, true)
				var age := int(Time.get_ticks_msec() / 1000.0 - float(info["t"]))
				draw_string(font, pos + Vector2(10, -6), "last seen %ds" % age, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(col.r, col.g, col.b, 0.8))
			if big and live:
				var nm := sh.display_name.get_slice(" (", 0)
				draw_string(font, pos + Vector2(px * 0.5 + 4, 4), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(col.r, col.g, col.b, 0.95))
	# Frame, title, north arrow, scale bar.
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.78, 0.60, 0.26), false, 3.0)
	draw_string(font, Vector2(8, 16), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.95, 0.80, 0.45))
	draw_string(font, Vector2(size.x * 0.5 - 4, 30 if big else 28), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, C_TEXT)
	draw_line(Vector2(size.x * 0.5, 34), Vector2(size.x * 0.5, 44), C_TEXT, 1.5)
	var bar := 2000.0 * sc
	var by := size.y - 12.0
	draw_line(Vector2(10, by), Vector2(10 + bar, by), C_TEXT, 2.0)
	draw_string(font, Vector2(14 + bar, by + 4), "2 km", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, C_TEXT)
	if big:
		# Legend.
		var lx := 12.0
		var ly := 34.0
		draw_circle(Vector2(lx + 4, ly), 4, C_FRIEND)
		draw_string(font, Vector2(lx + 14, ly + 4), "friendly", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, C_TEXT)
		draw_circle(Vector2(lx + 4, ly + 16), 4, C_ENEMY)
		draw_string(font, Vector2(lx + 14, ly + 20), "enemy contact (radar / visual)", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, C_TEXT)
		draw_arc(Vector2(lx + 4, ly + 32), 4, 0.0, TAU, 16, C_NAV, 1.5)
		draw_string(font, Vector2(lx + 14, ly + 36), "friendly radar coverage", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, C_TEXT)
		draw_rect(Rect2(lx, ly + 46, 8, 8), Color(0.62, 0.78, 0.66))
		draw_string(font, Vector2(lx + 14, ly + 54), "shoal water (danger)", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, C_TEXT)
