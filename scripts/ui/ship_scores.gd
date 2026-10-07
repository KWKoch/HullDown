class_name ShipScores
extends Control
## Five grouped scores (Firepower, Protection, Mobility, Anti-Air, Stealth), each a big bar with a
## 0-100 score. Tap a group to open its detail rows. With a compare ship set, every bar shows where
## that ship sits and the difference in green (better) or red (worse).

const GROUPS := ["FIREPOWER", "PROTECTION", "MOBILITY", "ANTI-AIR", "STEALTH"]

var entry: Dictionary = {}
var compare: Dictionary = {}
var expanded := 0
var _hits: Array = []            ## [y0, y1, group index]


func show_entry(e: Dictionary) -> void:
	entry = e
	queue_redraw()


func set_compare(e: Dictionary) -> void:
	compare = e
	queue_redraw()


static func scores(e: Dictionary) -> Array[float]:
	var m := ShipStats._norms()
	var g: Dictionary = e["main_gun"]
	var a: Dictionary = e["armor"]
	var disp: float = float(e["displacement_t"]) / float(m["disp"])
	var torp := minf(float(e.get("torpedo_tubes", 0)) / 16.0, 1.0)
	var fire: float = 0.55 * sqrt(ShipStats.firepower(e) / m["fp"]) + 0.30 * float(g["caliber_mm"]) / 460.0 + 0.15 * torp
	var prot: float = 0.40 * float(a.get("belt_mm", 0)) / 410.0 + 0.25 * float(a.get("deck_mm", 0)) / 200.0 + 0.10 * float(a.get("turret_mm", 0)) / 650.0 + 0.25 * pow(disp, 0.5)
	var mob: float = 0.55 * float(e["speed_kts"]) / m["spd"] + 0.45 * float(e.get("turn_rate", 0.05)) / m["turn"]
	var aa: float = 0.75 * float(e.get("aa_mounts", 0)) / m["aa"] + 0.25 * minf(float(e.get("secondary_mounts", 0)) / 20.0, 1.0)
	var stealth: float = 1.0 - 0.9 * pow(disp, 0.35) * clampf(float(e["length_m"]) / 260.0, 0.3, 1.0) ** 0.3
	var out: Array[float] = []
	for v in [fire, prot, mob, aa, stealth]:
		out.append(clampf(v, 0.03, 1.0))
	return out


static func details(e: Dictionary, group: int) -> Array:
	var g: Dictionary = e["main_gun"]
	var a: Dictionary = e["armor"]
	var turrets := (e["turret_z"] as Array).size()
	match group:
		0:
			return [["Main battery", "%d x %d mm" % [turrets * int(g["barrels_per_turret"]), int(g["caliber_mm"])]],
				["Shell weight", "%d kg" % int(g["shell_kg"])],
				["Broadside / min", "%s kg" % _fmt(ShipStats.firepower(e))],
				["Gun range", "%.1f km" % (float(g["range_m"]) / 1000.0)],
				["Torpedo tubes", str(int(e.get("torpedo_tubes", 0)))]]
		1:
			return [["Belt armour", "%d mm" % int(a.get("belt_mm", 0))], ["Deck armour", "%d mm" % int(a.get("deck_mm", 0))],
				["Turret armour", "%d mm" % int(a.get("turret_mm", 0))], ["Displacement", "%s t" % _fmt(float(e["displacement_t"]))]]
		2:
			return [["Top speed", "%.1f kn" % float(e["speed_kts"])], ["Turning", "%.1f deg/s" % rad_to_deg(float(e.get("turn_rate", 0.05)))],
				["Length", "%.0f m" % float(e["length_m"])], ["Screws / rudders", "%d / %d" % [int(e.get("screws", 2)), int(e.get("rudders", 1))]]]
		3:
			return [["AA mounts", str(int(e.get("aa_mounts", 0)))], ["Secondary mounts", str(int(e.get("secondary_mounts", 0)))]]
		_:
			return [["Length", "%.0f m" % float(e["length_m"])], ["Displacement", "%s t" % _fmt(float(e["displacement_t"]))],
				["Funnels", str(int(e.get("funnels", 1)))]]


static func _fmt(v: float) -> String:
	var s := str(int(round(v)))
	var out := ""
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0:
			out += ","
		out += s[i]
	return out


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var y := (ev as InputEventMouseButton).position.y
		for h in _hits:
			if y >= float(h[0]) and y <= float(h[1]):
				expanded = -1 if expanded == int(h[2]) else int(h[2])
				queue_redraw()
				accept_event()
				return


func _draw() -> void:
	_hits.clear()
	if entry.is_empty():
		return
	var fcaps := UIKit.font("caps")
	var fsemi := UIKit.font("semi")
	var fbody := UIKit.font("body")
	var gold := UIKit.GOLD
	var sc := scores(entry)
	var cs: Array[float] = []
	if not compare.is_empty():
		cs = scores(compare)
	var w := size.x
	var y := 4.0
	var row_h := 74.0
	for i in GROUPS.size():
		var y0 := y
		var open := i == expanded
		var v := sc[i]
		draw_string(fcaps, Vector2(4, y + 22), GROUPS[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 0.95, 0.85) if open else UIKit.INK)
		draw_string(fcaps, Vector2(w - 26, y + 22), "-" if open else "+", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, UIKit.DIM)
		var num := str(int(round(v * 100.0)))
		var nw := fsemi.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
		draw_string(fsemi, Vector2(w - 44 - nw, y + 28), num, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color(1, 0.97, 0.9))
		if not cs.is_empty():
			var d := int(round((v - cs[i]) * 100.0))
			var dt := ("+%d" % d) if d > 0 else str(d)
			var dc := UIKit.GREEN if d > 0 else (Color(1.0, 0.42, 0.38) if d < 0 else UIKit.DIM)
			var dw := fsemi.get_string_size(dt, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
			draw_string(fsemi, Vector2(w - 54 - nw - dw - 8, y + 26), dt, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, dc)
		var by := y + 42.0
		var bw := w - 8.0
		UIKit.fill_round(self, Rect2(4, by, bw, 16), 8.0, Color(1, 1, 1, 0.09), Color(1, 1, 1, 0.05))
		UIKit.fill_round(self, Rect2(4, by, maxf(bw * v, 16.0), 16), 8.0, Color("ffd77a"), Color("e8962a"))
		if not cs.is_empty():
			var cx := 4.0 + bw * cs[i]
			draw_line(Vector2(cx, by - 5), Vector2(cx, by + 21), Color(UIKit.CYAN.r, UIKit.CYAN.g, UIKit.CYAN.b, 0.95), 3.0)
		y += row_h
		if open:
			for r in details(entry, i):
				draw_string(fbody, Vector2(18, y + 18), String(r[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, UIKit.DIM)
				var vs := String(r[1])
				var vw := fsemi.get_string_size(vs, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
				draw_string(fsemi, Vector2(w - 8 - vw, y + 18), vs, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(1, 0.97, 0.9))
				y += 30.0
			y += 10.0
		draw_line(Vector2(4, y - 6), Vector2(w - 4, y - 6), Color(1, 1, 1, 0.06), 1.0)
		_hits.append([y0, y - 6, i])
	if not cs.is_empty():
		draw_string(fbody, Vector2(4, y + 20), "Cyan mark = comparison ship. Green = this ship is better.", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UIKit.DIM)
