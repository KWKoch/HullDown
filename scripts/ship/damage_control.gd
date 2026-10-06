class_name DamageControl
extends RefCounted
## A ship's damage-control organisation: repair parties that fight fires, plug and shore leaks and
## jury-rig damaged equipment, plus powered pumps that drain flooded spaces once the inflow is
## stopped. How fast any of it goes depends on crew efficacy (`skill`), which the captain type feeds
## and which erodes as the ship is battered. Destroyed compartments cannot be repaired -- a wrecked
## hull section can only be shored to slow the flooding, never stopped.

const REPAIR_CAP := 0.7            ## jury repairs restore at most this fraction of a part's hit points
const PARTY_SPEED := 6.0           ## metres per second a party moves through the ship (ship-model metres)
const PRIORITIES := ["AUTO", "FLOOD", "FIRE", "REPAIR"]

var ship: Ship
var skill := 1.0                    ## crew efficacy: ~0.6 green, 1.0 trained, ~1.4 elite
var priority := "AUTO"              ## the DC officer's emphasis; the player can change it
var parties: Array[Dictionary] = []   ## {task, target, progress, need, pos, label}
var pump_rate := 0.0                ## t/s capacity at full power and skill 1.0
var pumping_now := 0.0              ## t/s actually being pumped (for the HUD)
var note_count := 0                 ## total events ever logged (log itself is capped)
var log: Array[String] = []         ## recent events the HUD can show ("Fire out: magazine_1")


func setup(p_ship: Ship, p_skill: float = 1.0) -> void:
	ship = p_ship
	skill = p_skill
	var n := clampi(int(round(2.0 + ship.displacement_t / 16000.0)), 2, 6)
	for i in n:
		parties.append({"task": "IDLE", "target": null, "progress": 0.0, "need": 1.0, "pos": Vector3.ZERO, "travel": 0.0})
	# Pump capacity scales with the ship: a destroyer ~3 t/s, an Iowa ~25 t/s.
	pump_rate = 1.5 + ship.displacement_t * 0.0004


## Efficacy right now: crew skill discounted by how badly the ship has been hurt.
func efficacy() -> float:
	var hp := 0.0
	var mx := 0.0
	for c in ship.compartments:
		hp += c.hp
		mx += c.max_hp
	return skill * ship.crew_skill * lerpf(0.55, 1.0, clampf(hp / maxf(mx, 1.0), 0.0, 1.0))


func cycle_priority() -> void:
	priority = PRIORITIES[(PRIORITIES.find(priority) + 1) % PRIORITIES.size()]


func idle_parties() -> int:
	var n := 0
	for p in parties:
		if p["task"] == "IDLE":
			n += 1
	return n


func update(delta: float) -> void:
	var eff := efficacy()
	for p in parties:
		_work(p, delta, eff)
	_pump(delta, eff)


# --- Parties -------------------------------------------------------------------------

func _work(p: Dictionary, delta: float, eff: float) -> void:
	if p["task"] == "IDLE":
		_assign(p)
		return
	var c: Compartment = p["target"]
	# Task is moot if the target went away: the fire died, the leak stopped, the space was destroyed.
	if c == null or _moot(p["task"], c):
		p["task"] = "IDLE"
		p["target"] = null
		return
	if p["travel"] > 0.0:
		p["travel"] = maxf(0.0, float(p["travel"]) - delta)
		return
	p["pos"] = c.center
	p["progress"] = float(p["progress"]) + delta * eff
	if p["progress"] >= float(p["need"]):
		_finish(p, c)
	elif p["task"] == "REPAIR":
		# Repairs restore hit points continuously rather than all at the end.
		var cap_hp := c.max_hp * REPAIR_CAP
		if c.hp < cap_hp:
			c.hp = minf(cap_hp, c.hp + c.max_hp * 0.012 * eff * delta)
	elif p["task"] == "FIRE":
		c.heat = maxf(0.0, c.heat - 0.7 * delta * eff)       # hose down the ammunition


func _moot(task: String, c: Compartment) -> bool:
	match task:
		"FIRE":
			return not c.on_fire or c.destroyed and c.ammo_stored <= 0.0
		"LEAK":
			return c.flood_rate <= 0.0 or c.flooded_tonnes >= c.capacity_tonnes
		"REPAIR":
			return c.destroyed or c.hp >= c.max_hp * REPAIR_CAP
	return true


func _finish(p: Dictionary, c: Compartment) -> void:
	match p["task"]:
		"FIRE":
			c.on_fire = false
			c.heat = 0.0
			_note("Fire out: " + c.id)
		"LEAK":
			if c.destroyed and c.has_meta("shored"):
				pass
			elif c.destroyed:
				c.flood_rate *= 0.4            # a blown-out section can only be shored, not sealed
				c.set_meta("shored", true)
				_note("Shored: " + c.id)
			else:
				c.flood_rate = 0.0
				_note("Leak stopped: " + c.id)
		"REPAIR":
			_note("Jury repair done: " + c.id)
	p["task"] = "IDLE"
	p["target"] = null


func _assign(p: Dictionary) -> void:
	var best_score := 0.0
	var best: Compartment = null
	var best_task := ""
	var taken := {}
	for q in parties:
		if q["target"] != null:
			taken[q["target"]] = q["task"]
	var pri := priority
	for c in ship.compartments:
		var w := 1.0
		# FIRE: magazines first -- a cook-off is the worst thing that can happen.
		if c.on_fire and not (c.destroyed and c.ammo_stored <= 0.0) and taken.get(c, "") != "FIRE":
			var s := 60.0 + (200.0 if c.ammo_stored > 0.0 else 0.0) + c.heat * 4.0
			if pri == "FIRE":
				s *= 3.0
			elif pri != "AUTO":
				s *= 0.6
			if s > best_score:
				best_score = s
				best = c
				best_task = "FIRE"
		# LEAK: bigger inflow first; skip if already being shored.
		if c.flood_rate > 0.0 and c.flooded_tonnes < c.capacity_tonnes and taken.get(c, "") != "LEAK" \
				and not (c.destroyed and c.has_meta("shored")):
			var s2 := 30.0 + c.flood_rate * 14.0
			if pri == "FLOOD":
				s2 *= 3.0
			elif pri != "AUTO":
				s2 *= 0.6
			if s2 > best_score:
				best_score = s2
				best = c
				best_task = "LEAK"
		# REPAIR: only worth it for something that matters and is hurt but not wrecked.
		if not c.destroyed and c.hp < c.max_hp * REPAIR_CAP and taken.get(c, "") != "REPAIR":
			var s3 := (1.0 - c.health_fraction()) * 25.0 * _importance(c)
			if pri == "REPAIR":
				s3 *= 4.0
			if s3 > best_score and s3 > 4.0:
				best_score = s3
				best = c
				best_task = "REPAIR"
	if best == null:
		return
	var dist := (p["pos"] as Vector3).distance_to(best.center)
	p["task"] = best_task
	p["target"] = best
	p["progress"] = 0.0
	p["travel"] = 1.5 + dist / PARTY_SPEED
	p["need"] = _need(best_task, best)


func _need(task: String, c: Compartment) -> float:
	match task:
		"FIRE":
			return 12.0 + (8.0 if c.ammo_stored > 0.0 else 0.0)
		"LEAK":
			return (8.0 + c.flood_rate * 6.0) * (1.6 if c.destroyed else 1.0)
		"REPAIR":
			return 20.0 + 60.0 * (1.0 - c.health_fraction())
	return 10.0


func _importance(c: Compartment) -> float:
	match c.kind:
		Compartment.Kind.ENGINE_ROOM, Compartment.Kind.BOILER_ROOM, Compartment.Kind.STEERING_GEAR, Compartment.Kind.RUDDER, Compartment.Kind.SCREW:
			return 2.0
		Compartment.Kind.TURRET, Compartment.Kind.MAGAZINE, Compartment.Kind.BRIDGE:
			return 1.5
		Compartment.Kind.HULL_SECTION, Compartment.Kind.BOW:
			return 1.2
	return 0.6


# --- Pumps ---------------------------------------------------------------------------

## Drains flooded spaces whose inflow has been stopped, biggest first. Pumps need power, so they
## weaken as engineering is lost, and a flooded engine room can't help itself.
func _pump(delta: float, eff: float) -> void:
	pumping_now = 0.0
	var power := 0.4 + 0.6 * clampf(ship.propulsion_fraction(), 0.0, 1.0)
	var budget := pump_rate * power * (0.6 + 0.4 * eff) * delta
	if budget <= 0.0:
		return
	var wet: Array[Compartment] = []
	for c in ship.compartments:
		if c.flooded_tonnes > 0.0 and c.flood_rate <= 0.0:
			wet.append(c)
	wet.sort_custom(func(a: Compartment, b: Compartment) -> bool: return a.flooded_tonnes > b.flooded_tonnes)
	var used := 0.0
	for c in wet:
		if budget <= 0.0:
			break
		var take := minf(budget, c.flooded_tonnes)
		c.flooded_tonnes -= take
		budget -= take
		used += take
	if delta > 0.0:
		pumping_now = used / delta


func _note(text: String) -> void:
	log.append(text)
	note_count += 1
	while log.size() > 8:
		log.pop_front()
