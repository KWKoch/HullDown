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
var dispersion_deg := 0.22   ## 1-sigma per-shell angular scatter at full health, steady ship
var _salvo_yaw := 0.0        ## error shared by every shell of the current salvo (rad)
var _salvo_pitch := 0.0
const MV_SIGMA := 0.0025      ## 1-sigma muzzle-velocity variation: the main source of range scatter
const SALVO_SIGMA_DEG := 0.12
const TURRET_SIGMA_DEG := 0.10
## The solver integrates in 0.2 s steps for speed; against Shell's 1/60 s that under-reads the
## range by a near-constant ~125 m, so it is added back (checked by tests/test_ballistics.gd).
const STEP_BIAS := 126.0


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


## One entry per working or wrecked turret, bow to stern, for the reticle's fire-safety display:
## state is READY (loaded, in arc, trained on the point), RELOAD, TRAINING (in arc, still swinging),
## DEAD (the point is in this mount's dead zone) or OUT (destroyed / not functional).
func turret_states(target: Vector3) -> Array:
	var out: Array = []
	for t in train:
		var turret: Compartment = t
		var e := {"z": turret.center.z, "state": "OUT", "reload": 0.0}
		if turret.is_functional():
			var sol := _solution(turret, target)
			var total := reload_seconds() * (1.0 + (1.0 - turret.health_fraction()) * 1.5)
			var left: float = reload_left.get(t, 0.0)
			e["reload"] = clampf(1.0 - left / maxf(total, 0.1), 0.0, 1.0)
			if not sol["in_arc"]:
				e["state"] = "DEAD"
			elif left > 0.0:
				e["state"] = "RELOAD"
			elif absf(float(train[t]) - float(sol["a"])) > ALIGN_TOL:
				e["state"] = "TRAINING"
			else:
				e["state"] = "READY"
		out.append(e)
	out.sort_custom(func(a, b): return a["z"] > b["z"])
	return out


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
	# One error common to the whole ship's salvo (layer/trainer, rangefinder, roll).
	_salvo_yaw = randfn(0.0, deg_to_rad(SALVO_SIGMA_DEG))
	_salvo_pitch = randfn(0.0, deg_to_rad(SALVO_SIGMA_DEG) * 0.2)
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


## Aim solution in the firing ship's own moving frame: the shell inherits our velocity, and the
## target moves at `tvel`, so the shot has to be placed at where the target will be relative to
## us when the shell arrives. A caller that passes a zero `tvel` is treating the target as
## stationary in the world (our own drift is still compensated) -- the player must lead by hand.
func _lead(muzzle: Vector3, target: Vector3, tvel: Vector3) -> Vector3:
	var v0: float = gun["muzzle_ms"]
	var rel := tvel - ship.velocity_vec()
	var t_guess := muzzle.distance_to(target) / (v0 * 0.8)
	var aim_pt := target
	for i in 3:
		aim_pt = target + rel * t_guess
		t_guess = _time_of_flight(muzzle, aim_pt, v0)
		if t_guess < 0.0:
			return Vector3.ZERO
	var elev := _solve_elevation(muzzle, aim_pt, v0)
	if elev < 0.0:
		return Vector3.ZERO
	var flat := Vector3(aim_pt.x - muzzle.x, 0.0, aim_pt.z - muzzle.z)
	var bearing := atan2(flat.x, flat.z)
	return Vector3(sin(bearing) * cos(elev), sin(elev), cos(bearing) * cos(elev))


## Seconds a shell takes to reach a world point from this ship's guns (-1 if out of range).
func flight_time(target: Vector3) -> float:
	if gun.is_empty():
		return -1.0
	var from := ship.to_global(Vector3(0, 2.0, 0))
	for t in reload_left:
		from = ship.to_global((t as Compartment).center + Vector3(0, 2.0, 0))
		break
	return _time_of_flight(from, target, float(gun["muzzle_ms"]))


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
			return pos.x + (np.x - pos.x) * t + STEP_BIAS
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
		var half_len := f.wlen() * 0.5
		for entry in paths:
			var muzzle: Vector3 = entry[0]
			for p in (entry[1] as Array):
				if p.y > 45.0 or p.y < -f.wdraft():
					continue                                    # over the masts / under the water
				var horiz := Vector2(p.x - believed.x, p.z - believed.z).length()
				var range_from_gun := Vector2(p.x - muzzle.x, p.z - muzzle.z).length()
				if horiz < half_len + 25.0 + uncertainty_m * 1.5 + range_from_gun * spread:
					return false
	return true


func _spawn_shell(muzzle: Vector3, dir: Vector3, turret: Compartment, salvo_yaw: float = 0.0, salvo_pitch: float = 0.0) -> void:
	# Shot-to-shot scatter grows with a damaged mount, a ship at speed and a ship turning hard.
	var motion := 1.0 + 0.6 * clampf(absf(ship.speed_ms) / maxf(ship.max_speed_ms, 1.0), 0.0, 1.0) \
			+ 0.8 * absf(ship.rudder) * clampf(absf(ship.speed_ms) / maxf(ship.max_speed_ms, 1.0), 0.0, 1.0)
	var wear := 1.0 + (1.0 - turret.health_fraction())
	var spread := deg_to_rad(dispersion_deg) * wear * motion
	var d := dir
	d = d.rotated(Vector3.UP, salvo_yaw * motion + randfn(0.0, spread))
	var right := d.cross(Vector3.UP).normalized()
	d = d.rotated(right, salvo_pitch * motion + randfn(0.0, spread * 0.15))
	var cal := float(gun["caliber_mm"])
	var spec := {
		"caliber_mm": cal, "shell_kg": gun["shell_kg"],
		# Muzzle velocity varies shell to shell (powder lot, barrel wear): the main source of range scatter.
		"muzzle_ms": float(gun["muzzle_ms"]) * (1.0 + randfn(0.0, MV_SIGMA * wear)),
		"he_kg": float(gun["shell_kg"]) * 0.06,
		# AP fuze delay runs ~0.03 s: roughly 3.5 cm of travel per mm of calibre, in ship-model metres.
		"fuse_m": clampf(cal * 0.035, 3.0, 16.0),
	}
	var shell := Shell.new()
	ship.get_tree().current_scene.add_child(shell)
	shell.launch(ship, ship.terrain as BattleTerrain, muzzle, d, spec, ship.velocity_vec())
