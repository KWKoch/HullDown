class_name Gunnery
extends Node
## Fire control for a ship's main battery. Each turret is its own Compartment, so a
## destroyed turret stops firing and a damaged one reloads slower. Solutions are found by
## integrating the same ballistics Shell uses, so aiming accounts for drag and gravity.

static var ceasefire := false     ## when true, only the player's ship may fire (UI testing)
const RELOAD_SCALE := 0.5            ## reload time multiplier (0.5 = guns reload twice as fast)
const ARC_HALF := 2.6179938          ## 150 deg either side of the turret's centre line: a 60 deg dead zone
const ALIGN_TOL := 0.0436            ## 2.5 deg: a turret fires only when trained this close to the solution

var ship: Ship
var gun: Dictionary
var reload_left := {}        ## Compartment -> seconds until ready
var train := {}              ## Compartment -> training angle relative to the turret's centre line (rad)
var traverse_rate := 0.12    ## rad/s the turrets can swing
var _track_pos := Vector3.ZERO
var _track_t := 0.0
var dispersion_deg := 0.35   ## 1-sigma angular scatter at full health


func setup(p_ship: Ship) -> void:
	ship = p_ship
	var entry := Roster.get_entry(ship.class_id)
	gun = entry.get("main_gun", {})
	for t in ship.gun_turrets():
		reload_left[t] = randf() * 3.0
		train[t] = 0.0
	var cal := float(gun.get("caliber_mm", 150.0))
	traverse_rate = deg_to_rad(clampf(2500.0 / maxf(cal, 20.0), 4.0, 30.0))
	ship.set_meta("gunnery", self)


func max_range() -> float:
	return float(gun.get("range_m", 0.0))


func reload_seconds() -> float:
	return 60.0 / maxf(float(gun.get("rpm", 2.0)), 0.1) * RELOAD_SCALE


## Angle (world heading frame) of the centre line of a turret's firing arc, relative to the bow.
func arc_center(t: Compartment) -> float:
	return 0.0 if t.center.z >= 0.0 else PI


## Where a turret needs to point for a world target: the arc-relative training angle (clamped
## to the arc, because a turret cannot swing through its dead zone) and whether it is in arc.
func _solution(t: Compartment, target: Vector3) -> Dictionary:
	var d := target - ship.to_global(t.center)
	var rel := wrapf(atan2(d.x, d.z) - ship.heading, -PI, PI)
	var a := wrapf(rel - arc_center(t), -PI, PI)
	return {"a": clampf(a, -ARC_HALF, ARC_HALF), "in_arc": absf(a) <= ARC_HALF}


## Swing the turrets toward a world point (call every frame while aiming).
func aim_at(target_pos: Vector3) -> void:
	_track_pos = target_pos
	_track_t = 0.4


## How many working turrets can bear on a point (in arc) and are already trained on it.
func battery_status(target: Vector3) -> Dictionary:
	var total := 0
	var in_arc := 0
	var aligned := 0
	for t in train:
		var turret: Compartment = t
		if not turret.is_functional():
			continue
		total += 1
		var sol := _solution(turret, target)
		if sol["in_arc"]:
			in_arc += 1
			if absf(float(train[t]) - float(sol["a"])) <= ALIGN_TOL:
				aligned += 1
	return {"total": total, "in_arc": in_arc, "aligned": aligned}


func _physics_process(delta: float) -> void:
	for t in reload_left:
		reload_left[t] = maxf(0.0, reload_left[t] - delta)
	if _track_t > 0.0 and not ship.sunk:
		_track_t -= delta
		for t in train:
			var turret: Compartment = t
			if not turret.is_functional():
				continue
			var sol := _solution(turret, _track_pos)
			var rate := traverse_rate * (0.4 + 0.6 * turret.health_fraction())
			train[t] = move_toward(float(train[t]), float(sol["a"]), rate * delta)


## Fires every ready turret at `target_pos` (world). `target_vel` leads a moving target.
func fire_at(target_pos: Vector3, target_vel: Vector3) -> int:
	if gun.is_empty() or ship.sunk or ship.disarmed or (ceasefire and not ship.is_player):
		return 0
	aim_at(target_pos)
	var fired := 0
	for t in reload_left:
		var turret: Compartment = t
		if not turret.is_functional() or reload_left[t] > 0.0:
			continue
		# Respect the dead zone and the swing: the turret must be in arc and trained on target.
		var sol := _solution(turret, target_pos)
		if not sol["in_arc"] or absf(float(train[t]) - float(sol["a"])) > ALIGN_TOL:
			continue
		var muzzle := ship.to_global(turret.center + Vector3(0, 2.0, 0))
		var aim := _lead(muzzle, target_pos, target_vel)
		if aim == Vector3.ZERO:
			continue
		var barrels: int = gun.get("barrels_per_turret", 1)
		for b in barrels:
			_spawn_shell(muzzle, aim, turret)
		Fx.muzzle(ship, muzzle, aim, float(gun.get("caliber_mm", 100.0)))
		# A damaged turret reloads slower; rpm is per barrel salvo.
		var base := reload_seconds()
		reload_left[t] = base * (1.0 + (1.0 - turret.health_fraction()) * 1.5)
		fired += 1
	return fired


func _lead(muzzle: Vector3, target: Vector3, tvel: Vector3) -> Vector3:
	var v0: float = gun["muzzle_ms"]
	var t_guess := muzzle.distance_to(target) / (v0 * 0.8)
	var aim_pt := target
	for i in 3:
		aim_pt = target + tvel * t_guess
		t_guess = _time_of_flight(muzzle, aim_pt, v0)
		if t_guess < 0.0:
			return Vector3.ZERO
	var elev := _solve_elevation(muzzle, aim_pt, v0)
	if elev < 0.0:
		return Vector3.ZERO
	var flat := Vector3(aim_pt.x - muzzle.x, 0.0, aim_pt.z - muzzle.z)
	var bearing := atan2(flat.x, flat.z)
	return Vector3(sin(bearing) * cos(elev), sin(elev), cos(bearing) * cos(elev))


func _solve_elevation(from: Vector3, to: Vector3, v0: float) -> float:
	var flat := Vector2(to.x - from.x, to.z - from.z).length()
	var lo := 0.0
	var hi := deg_to_rad(40.0)
	var best := -1.0
	for _i in 14:
		var mid := (lo + hi) * 0.5
		var r := _range_at_height(mid, v0, to.y - from.y)
		if r < 0.0:
			return -1.0
		if r < flat:
			lo = mid
		else:
			hi = mid
		best = mid
	if _range_at_height(best, v0, to.y - from.y) < flat * 0.97:
		return -1.0
	return best


func _time_of_flight(from: Vector3, to: Vector3, v0: float) -> float:
	var el := _solve_elevation(from, to, v0)
	if el < 0.0:
		return -1.0
	var flat := Vector2(to.x - from.x, to.z - from.z).length()
	return flat / (v0 * cos(el) * 0.85)


## Horizontal distance travelled when the shell first descends through dy.
func _range_at_height(elev: float, v0: float, dy: float) -> float:
	var pos := Vector2.ZERO
	var vel := Vector2(cos(elev), sin(elev)) * v0
	var dt := 0.2
	for _s in 600:
		var sp := vel.length()
		vel += Vector2(0, -Shell.GRAVITY) * dt
		vel -= vel * sp * Shell.DRAG_K * dt
		var np := pos + vel * dt
		if vel.y < 0.0 and np.y <= dy:
			var t := (pos.y - dy) / maxf(pos.y - np.y, 0.0001)
			return pos.x + (np.x - pos.x) * t
		pos = np
	return -1.0


## Integrates the same ballistics Shell uses and returns the path as world points,
## ending where the shell reaches the water (y <= 0).
func predict_path(muzzle: Vector3, dir: Vector3) -> Array[Vector3]:
	var pts: Array[Vector3] = [muzzle]
	var pos := muzzle
	var vel := dir.normalized() * float(gun["muzzle_ms"])
	for i in 700:
		var dt := 0.04 if i < 50 else 0.25     # fine steps near the guns: point-blank shots matter
		var sp := vel.length()
		vel += Vector3(0, -Shell.GRAVITY, 0) * dt
		vel -= vel * sp * Shell.DRAG_K * dt
		pos += vel * dt
		pts.append(pos)
		if pos.y <= 0.0:
			break
	return pts


## Fire-safety check. Returns false if the shell's flight (or its splash area) crosses a
## friendly ship low enough to hit it. Shells passing above the masts are fine, which is
## why long, high-arc shots are rarely blocked but flat close-range ones often are.
## `offsets` maps Ship -> Vector3: the captain's (imperfect) error in where he believes each
## friendly ship is.
func clear_of_friendlies(target_pos: Vector3, target_vel: Vector3, offsets: Dictionary, uncertainty_m: float = 0.0) -> bool:
	if gun.is_empty():
		return true
	var live: Array[Compartment] = []
	for t in reload_left:
		if (t as Compartment).is_functional():
			live.append(t)
	if live.is_empty():
		return true
	var sample: Array[Compartment] = [live[0]]
	if live.size() > 2:
		sample.append(live[live.size() / 2])
	if live.size() > 1:
		sample.append(live[live.size() - 1])
	var spread := tan(deg_to_rad(dispersion_deg) * 2.0)     # lateral miss per metre of range
	var paths: Array = []                                    # [muzzle, path] per sampled turret
	for turret in sample:
		var muzzle := ship.to_global(turret.center + Vector3(0, 2.0, 0))
		var aim := _lead(muzzle, target_pos, target_vel)
		if aim != Vector3.ZERO:
			paths.append([muzzle, predict_path(muzzle, aim)])
	if paths.is_empty():
		return true
	for n in ship.get_tree().get_nodes_in_group("ships"):
		var f := n as Ship
		if f == null or f == ship or f.sunk or f.team != ship.team:
			continue
		var believed := f.global_position + (offsets.get(f, Vector3.ZERO) as Vector3)
		var half_len := f.length_m * 0.5
		for entry in paths:
			var muzzle: Vector3 = entry[0]
			for p in (entry[1] as Array):
				if p.y > 45.0 or p.y < -f.draft_m:
					continue                                    # over the masts / under the water
				var horiz := Vector2(p.x - believed.x, p.z - believed.z).length()
				var range_from_gun := Vector2(p.x - muzzle.x, p.z - muzzle.z).length()
				if horiz < half_len + 25.0 + uncertainty_m * 1.5 + range_from_gun * spread:
					return false
	return true


func _spawn_shell(muzzle: Vector3, dir: Vector3, turret: Compartment) -> void:
	var spread := deg_to_rad(dispersion_deg) * (1.0 + (1.0 - turret.health_fraction()))
	var d := dir
	d = d.rotated(Vector3.UP, randfn(0.0, spread))
	d = d.rotated(d.cross(Vector3.UP).normalized(), randfn(0.0, spread * 0.6))
	var shell := Shell.new()
	var spec := {
		"caliber_mm": gun["caliber_mm"], "shell_kg": gun["shell_kg"], "muzzle_ms": gun["muzzle_ms"],
		"he_kg": float(gun["shell_kg"]) * 0.06, "fuse_m": 6.0 if float(gun["caliber_mm"]) > 150.0 else 2.0,
	}
	ship.get_tree().current_scene.add_child(shell)
	shell.launch(ship, ship.terrain as BattleTerrain, muzzle, d, spec)
