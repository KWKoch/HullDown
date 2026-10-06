class_name Ship
extends Node3D
## A modular WWII surface ship. Built from a Roster class entry; every part is a
## Compartment that takes damage on its own and feeds back into ship performance.

signal compartment_destroyed(ship: Ship, comp: Compartment)
signal ship_sunk(ship: Ship)
signal magazine_detonated(ship: Ship, comp: Compartment)

const WATER_DENSITY := 1.025 # t/m3

var class_id: String
var ship_type: String = ""         ## roster type: battleship, destroyer, ... (selects the combat profile)
var display_name: String
var nation: String
var team: int = 0
var is_player: bool = false
var disarmed: bool = false           ## true: cannot fire (ammunition emptied)

var compartments: Array[Compartment] = []
var length_m: float = 150.0
var beam_m: float = 15.0
var draft_m: float = 5.0
var displacement_t: float = 8000.0
var max_speed_ms: float = 17.0       ## metres/sec at full power
var turn_rate_rad: float = 0.05      ## rad/s at full rudder, full speed
var reserve_buoyancy_t: float = 3000.0

# Dynamic state
var heading: float = 0.0             ## radians, 0 = +Z
var speed_ms: float = 0.0
var throttle: float = 0.0            ## -0.3 .. 1.0
var rudder: float = 0.0             ## -1 .. 1
var list_rad: float = 0.0            ## heel from asymmetric flooding
var trim_rad: float = 0.0
var total_flooded_t: float = 0.0
var sunk: bool = false
var dead_in_water: bool = false

var terrain: Node = null             ## set by the battleground; see terrain.gd
var hazard_r: float = 0.0            ## metres: how far this ship's blast could reach if it went up now

## Test counters
static var explosions := 0
static var chain_explosions := 0

## Ships are modelled at real size but shown/fought at WORLD_SCALE x so they are big enough to aim at.
## Local (compartment) coordinates stay in real metres; the node scale does the rest.
const WORLD_SCALE := 2.0
## Toughness over the raw compartment hit points, calibrated against history (see tests/test_durability.gd).
const DURABILITY := {
	"destroyer": 7.5, "escort": 7.5, "motor_torpedo_boat": 3.0, "light_cruiser": 4.2, "heavy_cruiser": 4.6,
	"battlecruiser": 5.4, "battleship": 6.0, "carrier": 5.0, "submarine": 3.0,
}
static var overpenetrations := 0
var crew_skill: float = 1.0          ## damage-control crew efficacy (captain type feeds this)
var dc: DamageControl
var damage_control_enabled := true
var top_y: float = 20.0              ## local height of the highest compartment (hit ceiling)

const COOKOFF_SECONDS := 14.0       ## fire exposure that sets off an unprotected ammo space


func setup_from_class(entry: Dictionary, p_team: int) -> void:
	class_id = entry["id"]
	ship_type = entry["type"]
	display_name = entry["name"]
	nation = entry["nation"]
	team = p_team
	length_m = entry["length_m"]
	beam_m = entry["beam_m"]
	draft_m = entry["draft_m"]
	displacement_t = entry["displacement_t"]
	max_speed_ms = entry["speed_kts"] * 0.5144
	turn_rate_rad = entry.get("turn_rate", 0.05)
	reserve_buoyancy_t = displacement_t * entry.get("reserve_buoyancy", 0.35)
	compartments = ShipBuilder.build(entry)
	var tough: float = DURABILITY.get(ship_type, 2.0)
	top_y = 8.0
	for c in compartments:
		c.max_hp *= tough
		c.hp = c.max_hp
		top_y = maxf(top_y, c.center.y + c.half_extents.y)
	top_y += 4.0                      # masts / rigging above the highest compartment
	scale = Vector3.ONE * WORLD_SCALE
	dc = DamageControl.new()
	dc.setup(self, crew_skill)


## World-space dimensions (what the eye and the sensors see).
## World-space velocity vector of the ship.
func velocity_vec() -> Vector3:
	return Vector3(sin(heading), 0.0, cos(heading)) * speed_ms


func wlen() -> float:
	return length_m * WORLD_SCALE


func wbeam() -> float:
	return beam_m * WORLD_SCALE


func wdraft() -> float:
	return draft_m * WORLD_SCALE


# --- Derived performance --------------------------------------------------

func _count_functional(kind: Compartment.Kind) -> Vector2:
	var total := 0
	var ok := 0
	for c in compartments:
		if c.kind == kind:
			total += 1
			if c.is_functional():
				ok += 1
	return Vector2(ok, total)


## 0..1: how much of the ship's reserve buoyancy is gone to flooding.
func flood_ratio() -> float:
	return clampf(total_flooded_t / maxf(reserve_buoyancy_t, 1.0), 0.0, 1.0)


## 0.25..1: how well the ship answers her helm and holds her way. A ship full of water is
## sluggish and wallows; a heavily listing one barely turns.
func handling_fraction() -> float:
	var list_f := clampf(absf(list_rad) / 0.4, 0.0, 1.0)
	return clampf(1.0 - 0.5 * flood_ratio() - 0.3 * list_f, 0.25, 1.0)


## 0..1 overall condition: surviving hit points, discounted by flooding. Used for target
## selection ("finish the wounded") and by the AI's retreat logic.
func integrity() -> float:
	var hp := 0.0
	var mx := 0.0
	for c in compartments:
		hp += c.hp
		mx += c.max_hp
	var flood := clampf(total_flooded_t / maxf(reserve_buoyancy_t, 1.0), 0.0, 1.0)
	return clampf(hp / maxf(mx, 1.0), 0.0, 1.0) * (1.0 - flood)


## Fraction of the main battery still working (1.0 for ships without turrets).
func battery_fraction() -> float:
	var t := gun_turrets()
	if t.is_empty():
		return 1.0
	var ok := 0
	for c in t:
		if c.is_functional():
			ok += 1
	return float(ok) / t.size()


func propulsion_fraction() -> float:
	var eng := _count_functional(Compartment.Kind.ENGINE_ROOM)
	var boil := _count_functional(Compartment.Kind.BOILER_ROOM)
	var screws := _count_functional(Compartment.Kind.SCREW)
	if eng.y == 0 or boil.y == 0:
		return 1.0
	var power := minf(eng.x / eng.y, boil.x / boil.y)
	var screw_f := 1.0 if screws.y == 0 else screws.x / screws.y
	# Flooding drags speed down further.
	var drag := clampf(1.0 - total_flooded_t / maxf(reserve_buoyancy_t, 1.0) * 0.5, 0.3, 1.0)
	return power * screw_f * drag


func steering_fraction() -> float:
	var r := _count_functional(Compartment.Kind.RUDDER)
	var g := _count_functional(Compartment.Kind.STEERING_GEAR)
	var f := 1.0
	if r.y > 0:
		f *= r.x / r.y
	if g.y > 0:
		f *= 1.0 if g.x > 0 else 0.0
	return f


func gun_turrets() -> Array[Compartment]:
	var out: Array[Compartment] = []
	for c in compartments:
		if c.kind == Compartment.Kind.TURRET:
			out.append(c)
	return out


# --- Damage ---------------------------------------------------------------

## shell keys: pen_mm, damage, he_kg, fuse_m (travel after impact before it
## detonates), dir (world Vector3), radius (blast radius m).
func take_hit(world_point: Vector3, shell: Dictionary) -> bool:
	if sunk:
		return false
	var local := to_local(world_point)
	var dir_local: Vector3 = (global_transform.basis.inverse() * (shell["dir"] as Vector3)).normalized()
	var pen: float = shell["pen_mm"]
	var fuse: float = shell.get("fuse_m", 0.0)
	var travelled := 0.0
	var pos := local
	var detonated_at := local
	var stopped := false
	var exited := false
	while travelled < 80.0 and pen > 0.0 and not stopped:
		var hit := _compartment_at(pos)
		if hit != null and not hit.destroyed:
			var armor := hit.armor_mm
			if armor > pen:
				# Shell shatters/defeated on the plate: only surface damage.
				hit.apply_damage(shell["damage"] * 0.1)
				detonated_at = pos
				stopped = true
				break
			pen -= armor
			hit.apply_damage(shell["damage"] * 0.15) # passage damage
			_post_damage(hit)
		if travelled >= fuse:
			detonated_at = pos
			stopped = true
			break
		pos += dir_local * 0.5
		travelled += 0.5
		detonated_at = pos
		# Out through the far side (or the deck/bottom) before the fuse ran: an over-penetration.
		if absf(pos.x) > beam_m * 0.5 + 0.5 or absf(pos.z) > length_m * 0.5 + 0.5 \
				or pos.y > top_y or pos.y < -draft_m - 0.5:
			exited = true
			break
	if exited:
		overpenetrations += 1
		return false
	_detonate(detonated_at, shell)
	return true


func _compartment_at(local_pt: Vector3) -> Compartment:
	for c in compartments:
		if not c.destroyed and c.contains(local_pt):
			return c
	return null


func _detonate(local_pt: Vector3, shell: Dictionary) -> void:
	var radius: float = shell.get("radius", 4.0)
	var dmg: float = shell["damage"]
	for c in compartments:
		if c.destroyed:
			continue
		var d := c.distance_to(local_pt)
		if d <= radius:
			var falloff := 1.0 - d / radius
			var applied := c.apply_damage(dmg * falloff)
			if applied > 0.0:
				_post_damage(c)
			# Fires start from hot fragments in fuel/ammo/boiler spaces.
			if falloff > 0.3 and c.kind in [Compartment.Kind.FUEL_TANK, Compartment.Kind.BOILER_ROOM,
					Compartment.Kind.HANGAR, Compartment.Kind.MAGAZINE]:
				if randf() < 0.45:
					c.on_fire = true


func _post_damage(c: Compartment) -> void:
	if c.below_waterline and c.health_fraction() < 0.8 and c.flood_rate <= 0.0:
		c.flood_rate = (1.0 - c.health_fraction()) * 6.0
	if c.destroyed:
		compartment_destroyed.emit(self, c)
		if c.ammo_stored > 0.0:
			# Fuel vapour only goes up if the tank is actually burning (or by bad luck).
			if c.kind != Compartment.Kind.FUEL_TANK or c.on_fire or randf() < 0.25:
				_magazine_explosion(c)


func _magazine_explosion(c: Compartment) -> void:
	var yield_kg := c.ammo_stored
	c.ammo_stored = 0.0
	Ship.explosions += 1
	Fx.explosion(self, to_global(c.center), yield_kg)
	magazine_detonated.emit(self, c)
	# Intra-ship chain reaction: heavy damage to everything within ~25 m of the space.
	var chain := {"damage": yield_kg * 0.6, "radius": 25.0, "pen_mm": 0, "dir": Vector3.DOWN}
	_detonate(c.center, chain)
	# Catastrophic if the magazine is large: break the ship's back.
	if c.max_hp > 800.0 * float(DURABILITY.get(ship_type, 2.0)):
		for other in compartments:
			if other.kind == Compartment.Kind.HULL_SECTION and other.distance_to(c.center) < 40.0:
				other.apply_damage(other.max_hp)
				other.flood_rate = 40.0
	_blast_neighbors(to_global(c.center), yield_kg)


func blast_radius_for(yield_kg: float) -> float:
	return 15.0 + pow(yield_kg, 0.45) * 1.6   # 1800 kg ~ 62 m, 300 kg ~ 36 m, 60 kg ~ 25 m


## Overpressure and fragments reach other ships close enough to the detonation.
func _blast_neighbors(pos: Vector3, yield_kg: float) -> void:
	if not is_inside_tree():
		return
	var radius := blast_radius_for(yield_kg)
	for n in get_tree().get_nodes_in_group("ships"):
		var other := n as Ship
		if other == null or other == self or other.sunk:
			continue
		if other.global_position.distance_to(pos) > radius + other.wlen() * 0.5:
			continue
		other.take_blast(pos, yield_kg, radius)


## A detonation elsewhere. Damage falls off with the square of closeness; armour screens
## interior spaces. Ammunition spaces can cook off when they are already burning, already
## badly hurt, or hit by a big enough overpressure -- which is how chain reactions spread.
func take_blast(world_pos: Vector3, yield_kg: float, radius: float) -> void:
	if sunk:
		return
	for c in compartments:
		if c.destroyed:
			continue
		var d := maxf(to_global(c.center).distance_to(world_pos) - c.half_extents.length() * 0.5, 0.0)
		if d >= radius:
			continue
		var falloff := 1.0 - d / radius
		var dmg := yield_kg * 2.0 * falloff * falloff
		dmg *= clampf(1.0 - c.armor_mm / 600.0, 0.25, 1.0)
		var had_ammo := c.ammo_stored > 0.0
		if c.apply_damage(dmg) > 0.0:
			_post_damage(c)
		if had_ammo and c.ammo_stored <= 0.0:
			Ship.chain_explosions += 1
			continue
		if c.destroyed:
			continue
		if falloff > 0.25 and c.kind in [Compartment.Kind.FUEL_TANK, Compartment.Kind.BOILER_ROOM,
				Compartment.Kind.HANGAR, Compartment.Kind.MAGAZINE, Compartment.Kind.TORPEDO_TUBES]:
			if randf() < 0.6 * falloff:
				c.on_fire = true
		if c.ammo_stored > 0.0:
			var risk := dmg / c.max_hp * 0.5
			if c.on_fire:
				risk += 0.25
			if c.health_fraction() < 0.5:
				risk += 0.25
			if randf() < risk:
				c.apply_damage(c.hp)         # sympathetic detonation
				_post_damage(c)
				if c.ammo_stored <= 0.0:
					Ship.chain_explosions += 1


## Collision with terrain (reef, shoal, island, wreck). Damages the hull under
## the contact point proportional to kinetic energy.
func take_grounding(local_contact: Vector3, impact_speed: float, hardness: float) -> void:
	# Kinetic energy in joules; ~3e-7 converts to compartment hit points so a 10 m/s
	# strike by a battleship wrecks the hull under the contact point, while scraping
	# along at 1-2 m/s only dents it.
	var energy := 0.5 * displacement_t * 1000.0 * impact_speed * impact_speed * hardness
	var shell := {"damage": energy * 3.0e-7, "radius": 6.0, "pen_mm": 0, "dir": Vector3.UP}
	local_contact.y = 0.0
	_detonate(local_contact, shell)
	# Opened hull plates below the contact point flood.
	for c in compartments:
		if c.below_waterline and c.distance_to(local_contact) < 6.0 and c.health_fraction() < 0.9:
			c.flood_rate = maxf(c.flood_rate, (1.0 - c.health_fraction()) * 8.0)
	speed_ms *= 0.4


# --- Simulation -----------------------------------------------------------

func _physics_process(delta: float) -> void:
	if sunk:
		_sink(delta)
		return
	_damage_control(delta)
	_move(delta)
	_check_terrain(delta)
	_check_sinking()


func _damage_control(delta: float) -> void:
	if damage_control_enabled and dc != null:
		dc.update(delta)
	total_flooded_t = 0.0
	var hazard := 0.0
	var port_water := 0.0
	var stbd_water := 0.0
	var fwd_water := 0.0
	var aft_water := 0.0
	for c in compartments:
		if c.destroyed and c.kind != Compartment.Kind.HULL_SECTION and c.kind != Compartment.Kind.BOW:
			pass
		if c.flood_rate > 0.0 and c.flooded_tonnes < c.capacity_tonnes:
			c.flooded_tonnes = minf(c.capacity_tonnes, c.flooded_tonnes + c.flood_rate * delta)
		if c.on_fire:
			# Fire burns the part (2%/s) until damage control or seawater puts it out.
			c.apply_damage(c.max_hp * 0.02 * delta)
			_post_damage(c)
			if c.ammo_stored > 0.0 and not c.destroyed:
				# Armour slows the heating of the ammunition inside.
				c.heat += delta * (1.0 + (1.0 - c.health_fraction()) * 2.0) / (1.0 + c.armor_mm / 250.0)
				if c.heat >= COOKOFF_SECONDS:
					c.apply_damage(c.hp)
					_post_damage(c)
			if c.flooded_tonnes > c.capacity_tonnes * 0.25 or c.destroyed and randf() < 0.1 * delta:
				c.on_fire = false
			elif randf() < 0.01 * delta:        # crew gets it under control
				c.on_fire = false
			else:
				_spread_fire(c, delta)
		total_flooded_t += c.flooded_tonnes
		if not c.on_fire and c.heat > 0.0:
			c.heat = maxf(0.0, c.heat - 0.5 * delta)
		if c.ammo_stored > 0.0 and not c.destroyed and (c.on_fire or c.health_fraction() < 0.6):
			hazard = maxf(hazard, blast_radius_for(c.ammo_stored))
		if c.center.x > 0.0:
			stbd_water += c.flooded_tonnes
		else:
			port_water += c.flooded_tonnes
		if c.center.z > 0.0:
			fwd_water += c.flooded_tonnes
		else:
			aft_water += c.flooded_tonnes
	hazard_r = hazard
	_progressive_flooding(delta)
	var gm := maxf(beam_m * 0.08 * displacement_t, 1.0)
	list_rad = lerpf(list_rad, clampf((stbd_water - port_water) / gm, -0.6, 0.6), delta)
	trim_rad = lerpf(trim_rad, clampf((fwd_water - aft_water) / (length_m * 40.0), -0.35, 0.35), delta)


## A space that is nearly full of water pushes it through the bulkheads into its neighbours below the
## waterline, slowly: flooding spreads unless the inflow is stopped and the water pumped out.
func _progressive_flooding(delta: float) -> void:
	if randf() > 2.0 * delta:
		return                              # evaluated ~twice a second
	for c in compartments:
		if not c.below_waterline or c.flooded_tonnes < c.capacity_tonnes * 0.85 or c.flood_rate <= 0.0:
			continue
		for n in compartments:
			if n == c or not n.below_waterline or n.flood_rate > 0.0 or n.flooded_tonnes >= n.capacity_tonnes:
				continue
			if c.distance_to(n.center) < 4.0 and not n.destroyed:
				n.flood_rate = 0.3 + n.capacity_tonnes * 0.002


## Burning spaces heat neighbours; ammunition and fuel nearby can catch.
func _spread_fire(src: Compartment, delta: float) -> void:
	for n in compartments:
		if n == src or n.on_fire or n.destroyed:
			continue
		if n.kind in [Compartment.Kind.MAGAZINE, Compartment.Kind.FUEL_TANK, Compartment.Kind.TORPEDO_TUBES, Compartment.Kind.HANGAR]:
			if src.distance_to(n.center) < 10.0 and randf() < 0.03 * delta:
				n.on_fire = true


func _move(delta: float) -> void:
	var list_drag := 1.0 - 0.25 * clampf(absf(list_rad) / 0.4, 0.0, 1.0)     # a heeled hull plough through the water
	var target := throttle * max_speed_ms * propulsion_fraction() * list_drag
	var accel := 0.04 * max_speed_ms * (1.0 + propulsion_fraction()) * (1.0 - 0.5 * flood_ratio())
	speed_ms = move_toward(speed_ms, target, accel * delta)
	var steer := rudder * steering_fraction()
	var speed_factor := clampf(absf(speed_ms) / maxf(max_speed_ms, 0.01), 0.0, 1.0)
	heading += steer * turn_rate_rad * handling_fraction() * speed_factor * delta * signf(speed_ms if speed_ms != 0.0 else 1.0)
	var fwd := Vector3(sin(heading), 0.0, cos(heading))
	global_position += fwd * speed_ms * delta
	rotation = Vector3(trim_rad, heading, list_rad)
	dead_in_water = propulsion_fraction() < 0.05


var _ground_cd := 0.0


func _check_terrain(delta: float) -> void:
	if terrain == null or not terrain.has_method("height_at"):
		return
	_ground_cd = maxf(0.0, _ground_cd - delta)
	# Sample bow, midships and stern keel points for grounding.
	var fwd := Vector3(sin(heading), 0.0, cos(heading))
	for f in [0.5, 0.0, -0.5]:
		var p: Vector3 = global_position + fwd * (wlen() * f)
		var floor_y: float = terrain.height_at(p.x, p.z)
		if floor_y > -wdraft():
			var hardness: float = terrain.hardness_at(p.x, p.z) if terrain.has_method("hardness_at") else 1.0
			# Damage only on actual contact at speed, with a cooldown; a ship that is
			# stuck on the bottom just stays stuck (it can reverse off).
			if _ground_cd <= 0.0 and absf(speed_ms) > 0.5:
				take_grounding(to_local(p), absf(speed_ms), hardness)
				_ground_cd = 0.6
			if speed_ms > 0.0 and f > 0.0 or speed_ms < 0.0 and f < 0.0:
				speed_ms = move_toward(speed_ms, 0.0, 6.0 * delta)
				global_position -= fwd * signf(speed_ms) * 0.0
			break


func _check_sinking() -> void:
	if total_flooded_t >= reserve_buoyancy_t:
		sunk = true
		ship_sunk.emit(self)
		return
	var hull_alive := false
	for c in compartments:
		if c.kind == Compartment.Kind.HULL_SECTION and not c.destroyed:
			hull_alive = true
	if not hull_alive:
		sunk = true
		ship_sunk.emit(self)


func _sink(delta: float) -> void:
	position.y -= delta * 1.2
	rotation.z = move_toward(rotation.z, signf(list_rad if list_rad != 0.0 else 1.0) * 1.4, delta * 0.15)
	if position.y < -wdraft() * 4.0 - 40.0:
		queue_free()
