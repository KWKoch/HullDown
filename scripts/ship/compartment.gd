class_name Compartment
extends RefCounted
## One individually damageable part or compartment of a ship.
## Positions/sizes are in ship-local metres (x = starboard, y = up from keel, z = bow).

enum Kind {
	BOW, STERN, HULL_SECTION, ENGINE_ROOM, BOILER_ROOM, MAGAZINE, TURRET,
	SECONDARY_MOUNT, TORPEDO_TUBES, BRIDGE, FUNNEL, MAST, RUDDER, SCREW,
	AA_MOUNT, FUEL_TANK, HANGAR, STEERING_GEAR
}

var id: String
var kind: Kind
var max_hp: float
var hp: float
var armor_mm: float = 0.0          ## effective armor over this compartment
var center: Vector3 = Vector3.ZERO
var half_extents: Vector3 = Vector3.ONE
var below_waterline: bool = false  ## true if hits here cause flooding

var on_fire: bool = false
var flood_rate: float = 0.0        ## tonnes/sec of water entering
var flooded_tonnes: float = 0.0
var capacity_tonnes: float = 100.0 ## water volume before the space is lost
var destroyed: bool = false
var ammo_stored: float = 0.0       ## magazines/ready-racks: explosive load (kg)
var heat: float = 0.0              ## seconds of accumulated fire exposure while holding ammo/fuel vapour


func _init(p_id: String, p_kind: Kind, p_hp: float, p_center: Vector3, p_half: Vector3) -> void:
	id = p_id
	kind = p_kind
	max_hp = p_hp
	hp = p_hp
	center = p_center
	half_extents = p_half


func contains(local_point: Vector3) -> bool:
	var d := (local_point - center).abs()
	return d.x <= half_extents.x and d.y <= half_extents.y and d.z <= half_extents.z


func distance_to(local_point: Vector3) -> float:
	var d := ((local_point - center).abs() - half_extents).max(Vector3.ZERO)
	return d.length()


func health_fraction() -> float:
	return clampf(hp / max_hp, 0.0, 1.0)


func is_functional() -> bool:
	## A compartment stops working at <25% hp, when destroyed, or when fully flooded.
	return not destroyed and health_fraction() > 0.25 and flooded_tonnes < capacity_tonnes


## Applies raw damage; returns the amount actually absorbed.
func apply_damage(amount: float) -> float:
	if destroyed:
		return 0.0
	var absorbed := minf(amount, hp)
	hp -= absorbed
	if hp <= 0.0:
		destroyed = true
	return absorbed
