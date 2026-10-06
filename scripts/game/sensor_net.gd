class_name SensorNet
extends Node
## Who can see whom. Every ship carries a radar whose range depends on its class and its
## navy's radar quality (and on its mast surviving), plus visual lookout limited by weather,
## visibility and night. Detections need a clear line of sight over the terrain. Friendly
## ships share what they see, so spreading radar ships out widens the picture ("dispersion").
##
## `picture` is the player side's fused tactical picture: Ship -> info dictionary
##   {live, pos, heading, speed, src ("DATALINK" | "RADAR" | "VISUAL"), t}
## Enemies that drop out of detection linger as "last known" ghosts for GHOST_S seconds.

## Surface-search radar range by class, in metres. These are gameplay-scaled (the real sets
## could reach further than a 14 km battleground), so no one ship sees the whole map.
const TYPE_RANGE := {
	"battleship": 9000.0, "battlecruiser": 9000.0, "heavy_cruiser": 8500.0, "light_cruiser": 8000.0,
	"destroyer": 7000.0, "escort": 6000.0, "carrier": 8500.0, "motor_torpedo_boat": 3500.0,
	"submarine": 2500.0,
}
## Radar quality by navy (US sets were the best; Italy had almost none).
const NATION_FACTOR := {
	"USA": 1.0, "United Kingdom": 0.95, "Germany": 0.85, "Japan": 0.7, "France": 0.6, "USSR": 0.5, "Italy": 0.45,
}
const GHOST_S := 30.0
const MAST_HEIGHT_M := 25.0

var terrain: Node
var team := 0
var visibility_m := 9000.0
var night := false
var picture: Dictionary = {}
var observers: Array = []              ## [{ship, radar, visual}] for the player's side
var _acc := 0.0


func setup(p_terrain: Node, p_team: int, p_visibility_m: float, p_night: bool) -> void:
	terrain = p_terrain
	team = p_team
	visibility_m = p_visibility_m
	night = p_night


static func radar_range(s: Ship) -> float:
	if s == null or s.sunk:
		return 0.0
	var r: float = float(TYPE_RANGE.get(s.ship_type, 6000.0)) * float(NATION_FACTOR.get(s.nation, 0.6))
	# The radar lives on the mast: lose every mast and the set is nearly blind.
	var masts := 0
	var working := 0
	for c in s.compartments:
		if c.kind == Compartment.Kind.MAST:
			masts += 1
			if c.is_functional():
				working += 1
	if masts > 0 and working == 0:
		r *= 0.3
	return r


func visual_range() -> float:
	var v := minf(visibility_m, 10000.0) * 0.5
	return v * (0.4 if night else 1.0)


func contacts_live(enemy_only := true) -> Array[Ship]:
	var out: Array[Ship] = []
	for k in picture:
		var s := k as Ship
		if s == null or not is_instance_valid(s):
			continue
		if enemy_only and s.team == team:
			continue
		if bool(picture[k]["live"]):
			out.append(s)
	return out


func _physics_process(delta: float) -> void:
	_acc += delta
	if _acc >= 0.5:
		_acc = 0.0
		_scan()


func scan_now() -> void:
	_scan()


func _scan() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	observers.clear()
	var friends: Array[Ship] = []
	var enemies: Array[Ship] = []
	for n in get_tree().get_nodes_in_group("ships"):
		var s := n as Ship
		if s == null or s.sunk:
			continue
		if s.team == team:
			friends.append(s)
		else:
			enemies.append(s)
	var vis := visual_range()
	for f in friends:
		observers.append({"ship": f, "radar": radar_range(f), "visual": vis})
		picture[f] = {"live": true, "pos": f.global_position, "heading": f.heading, "speed": f.speed_ms, "src": "DATALINK", "t": now}
	for e in enemies:
		var src := ""
		var size_factor := clampf(pow(e.length_m / 150.0, 0.25), 0.7, 1.25)
		for o in observers:
			var f2: Ship = o["ship"]
			var d := Vector2(e.global_position.x - f2.global_position.x, e.global_position.z - f2.global_position.z).length()
			var rr: float = float(o["radar"]) * size_factor
			var vr: float = float(o["visual"]) * size_factor
			if d > maxf(rr, vr) or not _los(f2.global_position, e.global_position):
				continue
			if d <= rr:
				src = "RADAR"
				break
			src = "VISUAL"
		if src != "":
			picture[e] = {"live": true, "pos": e.global_position, "heading": e.heading, "speed": e.speed_ms, "src": src, "t": now}
		elif picture.has(e):
			var info: Dictionary = picture[e]
			info["live"] = false
			if now - float(info["t"]) > GHOST_S:
				picture.erase(e)
	for k in picture.keys():
		if not is_instance_valid(k) or (k as Ship).sunk:
			picture.erase(k)


## Clear line of sight over the terrain (islands and headlands block radar and eyes).
func _los(a: Vector3, b: Vector3) -> bool:
	if terrain == null or not terrain.has_method("height_at"):
		return true
	var d := Vector2(b.x - a.x, b.z - a.z).length()
	var steps := int(d / 250.0)
	for i in range(1, steps):
		var t := float(i) / float(steps)
		if float(terrain.height_at(lerpf(a.x, b.x, t), lerpf(a.z, b.z, t))) > MAST_HEIGHT_M:
			return false
	return true
