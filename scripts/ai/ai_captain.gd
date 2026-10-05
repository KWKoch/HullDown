class_name AICaptain
extends Node
## Surface-ship AI. WHAT the ship does comes from its type's profile (CombatProfiles):
## target priorities, preferred range band, stationing, attack runs, when to break off.
## HOW WELL it does it comes from the captain: error_rate, position noise, and (later)
## captain-type modifiers in `captain_mods`.
##
## Safety (always on, never perfect): checks that a salvo will not cross a friendly ship, keeps
## clear of ships that look ready to explode, and avoids terrain. Each check can be botched at
## `error_rate`, and friendly positions are only known to within `position_noise_m`.

enum State { FORM, APPROACH, ENGAGE, RUN, BREAK, WITHDRAW, EVADE }

var ship: Ship
var gunnery: Gunnery
var target: Ship
var profile: Dictionary = {}
var captain_mods: Dictionary = {}     ## multipliers on numeric profile keys, e.g. {"aggression": 1.3}
var state: State = State.FORM

var orbit_dir := 1.0
var _retarget_t := 0.0
var _fire_t := 0.0
var _state_t := 0.0                   ## time left in the current timed state (BREAK / WITHDRAW)
var _run_cooldown := 0.0
var _station_ship: Ship = null

# --- imperfection ---
var error_rate := 0.05                ## chance that any single safety check is botched/skipped
var position_noise_m := 35.0          ## 1-sigma error in where he believes friendly ships are
var _friend_offsets := {}
var _hazard_missed := {}
var _avoid_t := 0.0
var _avoid_push := Vector2.ZERO

# --- test counters ---
static var held_fire := 0
static var unsafe_shots := 0


func setup(p_ship: Ship, p_gunnery: Gunnery) -> void:
	ship = p_ship
	gunnery = p_gunnery
	profile = CombatProfiles.for_type(ship.ship_type)
	orbit_dir = 1.0 if randf() < 0.5 else -1.0
	error_rate = randf_range(0.01, 0.05)
	position_noise_m = randf_range(15.0, 60.0)
	_retarget_t = randf() * 2.0
	add_to_group("captains")


## Profile value with the captain's multiplier applied (numbers only).
func _v(key: String) -> Variant:
	var base: Variant = profile.get(key, CombatProfiles.DEFAULTS.get(key))
	if (base is float or base is int) and captain_mods.has(key):
		return float(base) * float(captain_mods[key])
	return base


func _range_eff() -> float:
	var cap: float = _v("engage_cap_m")
	var g := gunnery.max_range()
	return minf(g, cap) if g > 0.0 else cap


func _physics_process(delta: float) -> void:
	if ship.sunk:
		return
	_retarget_t -= delta
	_state_t -= delta
	_run_cooldown -= delta
	if _retarget_t <= 0.0:
		_retarget_t = 3.0 + randf()
		_pick_target()
		_pick_station()
		_refresh_beliefs()
	_update_state()
	_steer(delta)
	_fire(delta)


# --- Targeting ---------------------------------------------------------------

func _enemies() -> Array[Ship]:
	var out: Array[Ship] = []
	for n in get_tree().get_nodes_in_group("ships"):
		var s := n as Ship
		if s != null and not s.sunk and s.team != ship.team:
			out.append(s)
	return out


func _score(t: Ship) -> float:
	var weights: Dictionary = profile["target_weights"]
	var w: float = weights.get(t.ship_type, _v("default_weight"))
	var d := ship.global_position.distance_to(t.global_position)
	var r := _range_eff()
	var wounded := 1.0 + float(_v("wounded_bonus")) * (1.0 - t.integrity())
	var reach := 1.0 / (1.0 + pow(d / maxf(r, 1.0), 3.0))      # far targets matter less
	var in_range := 1.4 if d <= r * 1.1 else 1.0
	return w * wounded * reach * in_range


func _pick_target() -> void:
	var best: Ship = null
	var best_s := -1.0
	var cur_s := -1.0
	for e in _enemies():
		var sc := _score(e)
		if e == target:
			cur_s = sc
		if sc > best_s:
			best_s = sc
			best = e
	# Hysteresis: do not flip-flop between similar targets.
	if target != null and not target.sunk and cur_s >= 0.0 and best_s < cur_s * 1.3:
		return
	target = best


func _pick_station() -> void:
	_station_ship = null
	var coh: Dictionary = profile.get("cohesion", {})
	if coh.is_empty():
		return
	var types: Array = coh["types"]
	var best_d := INF
	for n in get_tree().get_nodes_in_group("ships"):
		var s := n as Ship
		if s == null or s == ship or s.sunk or s.team != ship.team or not (s.ship_type in types):
			continue
		var d := ship.global_position.distance_to(s.global_position)
		if d < best_d:
			best_d = d
			_station_ship = s


# --- State machine -------------------------------------------------------------

func _should_withdraw() -> bool:
	var r: Dictionary = profile["retreat"]
	var flood := ship.total_flooded_t / maxf(ship.reserve_buoyancy_t, 1.0)
	return flood > float(r["flood"]) or ship.propulsion_fraction() < float(r["propulsion"]) \
			or ship.battery_fraction() < float(r["battery"])


func _update_state() -> void:
	var style: String = profile["style"]
	if state == State.WITHDRAW and _state_t > 0.0:
		return
	if _should_withdraw():
		state = State.WITHDRAW
		_state_t = 25.0
		return
	if style == "evade":
		var near := false
		for e in _enemies():
			if ship.global_position.distance_to(e.global_position) < float(_v("evade_trigger_m")):
				near = true
				break
		state = State.EVADE if near else State.FORM
		return
	if target == null:
		state = State.FORM
		return
	var dist := ship.global_position.distance_to(target.global_position)
	var runs := style == "screen_and_strike" or style == "hit_and_run"
	if runs:
		match state:
			State.RUN:
				if dist < float(_v("run_range_m")):
					state = State.BREAK
					_state_t = float(_v("break_s"))
					_run_cooldown = float(_v("cooldown_s"))
				return
			State.BREAK:
				if _state_t > 0.0:
					return
				state = State.FORM
			_:
				var w: float = (profile["target_weights"] as Dictionary).get(target.ship_type, 0.0)
				var trigger := float(_v("strike_trigger_m")) * (0.7 + 0.6 * float(_v("aggression")))
				if _run_cooldown <= 0.0 and w >= float(_v("strike_min_weight")) and dist < trigger:
					state = State.RUN
					return
	var band: Array = profile["range_band"]
	var r := _range_eff()
	if dist > r * float(band[1]):
		# Screening ships hold station instead of charging in alone, if they have someone to guard.
		var guarding := (runs or style == "convoy_guard") and _station_ship != null and not _station_ship.sunk
		state = State.FORM if guarding else State.APPROACH
	else:
		state = State.ENGAGE


# --- Movement --------------------------------------------------------------------

func _steer(delta: float) -> void:
	var pos := Vector2(ship.global_position.x, ship.global_position.z)
	var heading_v := Vector2(sin(ship.heading), cos(ship.heading))
	var v := heading_v
	var thr: float = _v("cruise_throttle")

	var bearing := Vector2.ZERO
	var dist := 0.0
	if target != null and not target.sunk:
		var off := Vector2(target.global_position.x, target.global_position.z) - pos
		dist = off.length()
		bearing = off / maxf(dist, 0.01)
	var tangent := Vector2(bearing.y, -bearing.x) * orbit_dir
	var exposure := deg_to_rad(float(_v("exposure_deg")))

	match state:
		State.WITHDRAW:
			v = (-bearing + tangent * 0.3) if bearing != Vector2.ZERO else heading_v
			thr = 1.0
		State.EVADE:
			var away := Vector2.ZERO
			for e in _enemies():
				var o := pos - Vector2(e.global_position.x, e.global_position.z)
				var d := maxf(o.length(), 1.0)
				away += o / d * (1.0 / d) * 10000.0
			if away != Vector2.ZERO:
				v = away.normalized()
			thr = 1.0
		State.RUN:
			v = bearing + tangent * sin(exposure) * 0.5
			thr = 1.0
		State.BREAK:
			v = -bearing + tangent * 0.7
			thr = 1.0
		State.FORM:
			var station := _station_vector(pos)
			if station != Vector2.ZERO:
				v = station
				if _station_distance(pos) > 600.0:
					thr = float(_v("close_throttle"))
				else:
					thr = clampf(_station_ship_speed_frac() + 0.05, 0.25, float(_v("close_throttle")))
			elif bearing != Vector2.ZERO:
				v = bearing            # nobody to guard: act like APPROACH
				thr = float(_v("close_throttle"))
		State.APPROACH:
			v = bearing + tangent * sin(exposure) * 0.35
			thr = float(_v("close_throttle"))
		State.ENGAGE:
			var band: Array = profile["range_band"]
			var r := _range_eff()
			var lo: float = r * float(band[0])
			var hi: float = r * float(band[1])
			var mid := (lo + hi) * 0.5
			var radial := clampf((dist - mid) / maxf((hi - lo) * 0.5, 1.0), -1.0, 1.0)   # + = need to close
			var tang_w := clampf(sin(exposure), 0.2, 1.0) * (1.0 - absf(radial) * 0.6)
			v = bearing * radial + tangent * tang_w
			# Ships with a station do not drift away from the ships they guard / sail with.
			var st := _station_vector(pos)
			var coh: Dictionary = profile.get("cohesion", {})
			if st != Vector2.ZERO and not coh.is_empty():
				var pull := clampf((_station_distance(pos) - float(coh["station_m"])) / float(coh["station_m"]), 0.0, 1.0)
				v += st * float(coh["weight"]) * pull * 2.0
			thr = float(_v("hold_throttle")) if absf(radial) < 0.5 else float(_v("close_throttle"))
			if radial < -0.5:
				thr = float(_v("hold_throttle")) * 0.8

	if v == Vector2.ZERO:
		v = heading_v
	var desired := atan2(v.x, v.y)
	desired = _avoid_ships(desired, delta)
	desired = _avoid_terrain(desired)
	var err := wrapf(desired - ship.heading, -PI, PI)
	ship.rudder = clampf(err * 2.0, -1.0, 1.0)
	ship.throttle = clampf(thr, -0.3, 1.0)


func _station_distance(pos: Vector2) -> float:
	if _station_ship == null or _station_ship.sunk:
		return 0.0
	return pos.distance_to(Vector2(_station_ship.global_position.x, _station_ship.global_position.z))


func _station_ship_speed_frac() -> float:
	if _station_ship == null:
		return 0.5
	return absf(_station_ship.speed_ms) / maxf(ship.max_speed_ms, 0.01)


## Direction toward the ship's station: for screens and escorts, a point on the threatened side
## of the guarded ship (between it and the enemy); otherwise just toward the guarded ship.
func _station_vector(pos: Vector2) -> Vector2:
	if _station_ship == null or _station_ship.sunk:
		return Vector2.ZERO
	var coh: Dictionary = profile.get("cohesion", {})
	if coh.is_empty():
		return Vector2.ZERO
	var c := Vector2(_station_ship.global_position.x, _station_ship.global_position.z)
	var station_m: float = coh["station_m"]
	var threat := Vector2.ZERO
	var style: String = profile["style"]
	if (style == "screen_and_strike" or style == "convoy_guard") and target != null and not target.sunk:
		threat = (Vector2(target.global_position.x, target.global_position.z) - c).normalized()
	var goal := c + threat * station_m * 0.8 + Vector2(threat.y, -threat.x) * orbit_dir * station_m * 0.3
	var to_goal := goal - pos
	if to_goal.length() < 80.0:
		return Vector2.ZERO
	return to_goal.normalized()


# --- Fire control + safety ---------------------------------------------------------

func _fire(delta: float) -> void:
	_fire_t -= delta
	if target == null or target.sunk or _fire_t > 0.0:
		return
	var dist := ship.global_position.distance_to(target.global_position)
	var fire_range := minf(gunnery.max_range() * 0.95, float(_v("engage_cap_m")) * float(_v("fire_cap_factor")))
	if dist > fire_range:
		return
	var tvel := Vector3(sin(target.heading), 0.0, cos(target.heading)) * target.speed_ms
	var tpos := target.global_position + Vector3(0, 3.0, 0)
	var checked := randf() >= error_rate           # sometimes he just doesn't check
	var safe := true
	if checked:
		# A sensible captain widens his margin by how unsure he is of where his friends are.
		safe = gunnery.clear_of_friendlies(tpos, tvel, _friend_offsets, position_noise_m)
	if safe:
		if not checked and not gunnery.clear_of_friendlies(tpos, tvel, {}):
			AICaptain.unsafe_shots += 1
		gunnery.fire_at(tpos, tvel)
		_fire_t = 1.5
	else:
		AICaptain.held_fire += 1
		_fire_t = 0.7
		if randf() < 0.3:
			orbit_dir = -orbit_dir                    # change the geometry to unmask the guns


## The captain's picture of the battle is imperfect: friendly positions are estimated with
## noise and, now and then, a hazard goes unnoticed.
func _refresh_beliefs() -> void:
	_friend_offsets.clear()
	_hazard_missed.clear()
	for n in get_tree().get_nodes_in_group("ships"):
		var o := n as Ship
		if o == null or o == ship:
			continue
		_friend_offsets[o] = Vector3(randfn(0.0, position_noise_m), 0.0, randfn(0.0, position_noise_m))
		_hazard_missed[o] = randf() < error_rate


## Keeps clear of other ships (no ramming, no crowding) and, harder, of ships about to blow
## up: a burning magazine's blast radius plus a safety margin. Re-evaluated 4x a second.
func _avoid_ships(desired: float, delta: float) -> float:
	_avoid_t -= delta
	if _avoid_t <= 0.0:
		_avoid_t = 0.25
		_avoid_push = Vector2.ZERO
		for n in get_tree().get_nodes_in_group("ships"):
			var o := n as Ship
			if o == null or o == ship or o.sunk:
				continue
			var off := Vector2(ship.global_position.x - o.global_position.x, ship.global_position.z - o.global_position.z)
			var d := off.length()
			var keep := (ship.length_m + o.length_m) * 0.5 + 40.0
			if o.hazard_r > 0.0 and not _hazard_missed.get(o, false):
				keep = maxf(keep, o.hazard_r + 60.0 + o.length_m * 0.5)
			if d < keep and d > 0.1:
				_avoid_push += off / d * (1.0 - d / keep) * 2.5
	if _avoid_push == Vector2.ZERO:
		return desired
	var v := Vector2(sin(desired), cos(desired)) + _avoid_push
	return atan2(v.x, v.y)


## Probe ahead; if shallow/land is coming, bias the heading away from the nearer side.
func _avoid_terrain(desired: float) -> float:
	if ship.terrain == null:
		return desired
	var look := maxf(ship.speed_ms * 25.0, ship.length_m * 1.5)
	for off in [0.0, 0.35, -0.35]:
		var a: float = ship.heading + off
		var p := ship.global_position + Vector3(sin(a), 0, cos(a)) * look
		if ship.terrain.height_at(p.x, p.z) > -ship.draft_m * 1.6:
			var left_a := ship.heading + 0.6
			var right_a := ship.heading - 0.6
			var lp := ship.global_position + Vector3(sin(left_a), 0, cos(left_a)) * look
			var rp := ship.global_position + Vector3(sin(right_a), 0, cos(right_a)) * look
			var lh: float = ship.terrain.height_at(lp.x, lp.z)
			var rh: float = ship.terrain.height_at(rp.x, rp.z)
			return left_a if lh < rh else right_a
	return desired
