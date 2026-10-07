class_name ShipStats
extends Control
## Fleet-store infographic: a six-axis radar plus labelled bars, all normalised against the roster.

static var _max := {}

const AXES := ["FIREPOWER", "ARMOUR", "SPEED", "AGILITY", "AA", "SIZE"]
var entry: Dictionary = {}


static func firepower(e: Dictionary) -> float:
	var g: Dictionary = e["main_gun"]
	var turrets := (e["turret_z"] as Array).size()
	return turrets * float(g["barrels_per_turret"]) * float(g["shell_kg"]) * float(g["rpm"])


static func _norms() -> Dictionary:
	if not _max.is_empty():
		return _max
	var m := {"fp": 1.0, "arm": 1.0, "spd": 1.0, "turn": 1.0, "aa": 1.0, "disp": 1.0, "range": 1.0}
	for e in Roster.available():
		m["fp"] = maxf(m["fp"], firepower(e))
		m["arm"] = maxf(m["arm"], _armour(e))
		m["spd"] = maxf(m["spd"], float(e["speed_kts"]))
		m["turn"] = maxf(m["turn"], float(e.get("turn_rate", 0.05)))
		m["aa"] = maxf(m["aa"], float(e.get("aa_mounts", 0)))
		m["disp"] = maxf(m["disp"], float(e["displacement_t"]))
		m["range"] = maxf(m["range"], float(e["main_gun"]["range_m"]))
	_max = m
	return m


static func _armour(e: Dictionary) -> float:
	var a: Dictionary = e["armor"]
	return float(a.get("belt_mm", 0)) * 0.5 + float(a.get("deck_mm", 0)) * 0.7 + float(a.get("turret_mm", 0)) * 0.3


func show_entry(e: Dictionary) -> void:
	entry = e
	queue_redraw()


func _radar_values() -> Array[float]:
	var m := _norms()
	return [
		sqrt(firepower(entry) / m["fp"]),
		_armour(entry) / m["arm"],
		float(entry["speed_kts"]) / m["spd"],
		float(entry.get("turn_rate", 0.05)) / m["turn"],
		float(entry.get("aa_mounts", 0)) / m["aa"],
		pow(float(entry["displacement_t"]) / m["disp"], 0.45),
	]


func _draw() -> void:
	if entry.is_empty():
		return
	var fsemi := UIKit.font("semi")
	var fcaps := UIKit.font("caps")
	var fbody := UIKit.font("body")
	var m := _norms()
	var gold := UIKit.GOLD
	# --- radar ---
	var c := Vector2(150, 150)
	var rad := 100.0
	var vals := _radar_values()
	for ring in [0.25, 0.5, 0.75, 1.0]:
		var pts := PackedVector2Array()
		for k in 6:
			var a := -PI * 0.5 + TAU * k / 6.0
			pts.append(c + Vector2(cos(a), sin(a)) * rad * ring)
		pts.append(pts[0])
		draw_polyline(pts, Color(0.6, 0.75, 0.95, 0.10 if ring < 1.0 else 0.30), 1.0, true)
	if true:
		var back := PackedVector2Array()
		for k in 6:
			var a0 := -PI * 0.5 + TAU * k / 6.0
			back.append(c + Vector2(cos(a0), sin(a0)) * rad)
		draw_colored_polygon(back, Color(1, 1, 1, 0.025))
	var poly := PackedVector2Array()
	for k in 6:
		var a2 := -PI * 0.5 + TAU * k / 6.0
		var dir := Vector2(cos(a2), sin(a2))
		draw_line(c, c + dir * rad, Color(0.6, 0.75, 0.95, 0.14), 1.0, true)
		poly.append(c + dir * rad * clampf(vals[k], 0.05, 1.0))
		var lp := c + dir * (rad + 24.0)
		var w := fcaps.get_string_size(AXES[k], HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(fcaps, lp + Vector2(-w * 0.5, 4), AXES[k], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIKit.DIM)
	# glow layers then the shape
	var glow_loop := poly.duplicate()
	glow_loop.append(poly[0])
	draw_polyline(glow_loop, Color(gold.r, gold.g, gold.b, 0.12), 9.0, true)
	draw_polyline(glow_loop, Color(gold.r, gold.g, gold.b, 0.18), 5.0, true)
	var fills := PackedColorArray()
	for p in poly:
		fills.append(Color(gold.r, gold.g, gold.b, 0.18 + 0.30 * (1.0 - p.distance_to(c) / rad)))
	draw_polygon(poly, fills)
	draw_polyline(glow_loop, gold, 2.0, true)
	for p in poly:
		draw_circle(p, 4.5, Color(0, 0, 0, 0.45))
		draw_circle(p, 3.5, Color(1, 0.92, 0.7))
	# --- bars ---
	var g: Dictionary = entry["main_gun"]
	var a: Dictionary = entry["armor"]
	var turrets := (entry["turret_z"] as Array).size()
	var rows: Array = [
		["MAIN BATTERY", "%d x %d mm" % [turrets * int(g["barrels_per_turret"]), int(g["caliber_mm"])], float(g["caliber_mm"]) / 460.0],
		["BROADSIDE / MIN", "%s kg" % _fmt(firepower(entry)), sqrt(firepower(entry) / m["fp"])],
		["GUN RANGE", "%.1f km" % (float(g["range_m"]) / 1000.0), float(g["range_m"]) / m["range"]],
		["BELT ARMOUR", "%d mm" % int(a.get("belt_mm", 0)), float(a.get("belt_mm", 0)) / 400.0],
		["DECK ARMOUR", "%d mm" % int(a.get("deck_mm", 0)), float(a.get("deck_mm", 0)) / 200.0],
		["TURRET ARMOUR", "%d mm" % int(a.get("turret_mm", 0)), float(a.get("turret_mm", 0)) / 500.0],
		["TOP SPEED", "%.1f kn" % float(entry["speed_kts"]), float(entry["speed_kts"]) / m["spd"]],
		["TURNING", "%.1f deg/s" % rad_to_deg(float(entry.get("turn_rate", 0.05))), float(entry.get("turn_rate", 0.05)) / m["turn"]],
		["AA MOUNTS", "%d" % int(entry.get("aa_mounts", 0)), float(entry.get("aa_mounts", 0)) / m["aa"]],
		["SECONDARIES", "%d" % int(entry.get("secondary_mounts", 0)), float(entry.get("secondary_mounts", 0)) / 20.0],
		["DISPLACEMENT", "%s t" % _fmt(float(entry["displacement_t"])), pow(float(entry["displacement_t"]) / m["disp"], 0.6)],
		["LENGTH", "%.0f m" % float(entry["length_m"]), float(entry["length_m"]) / 280.0],
	]
	var x0 := 320.0
	var y := 28.0
	var bw := size.x - x0 - 10.0
	for r in rows:
		draw_string(fcaps, Vector2(x0, y), r[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIKit.DIM)
		var vs: String = r[1]
		var vw := fsemi.get_string_size(vs, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_string(fsemi, Vector2(size.x - 10.0 - vw, y), vs, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.97, 0.9))
		UIKit.fill_round(self, Rect2(x0, y + 6, bw, 6), 3.0, Color(1, 1, 1, 0.09), Color(1, 1, 1, 0.05))
		var fw := maxf(bw * clampf(float(r[2]), 0.02, 1.0), 6.0)
		UIKit.fill_round(self, Rect2(x0, y + 6, fw, 6), 3.0, Color("ffd77a"), Color("e8962a"))
		y += 26.0


func _fmt(v: float) -> String:
	var s := str(int(round(v)))
	var out := ""
	for k in s.length():
		if k > 0 and (s.length() - k) % 3 == 0:
			out += ","
		out += s[k]
	return out
