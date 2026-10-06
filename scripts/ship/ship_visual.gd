class_name ShipVisual
extends Node3D
## Builds a procedural 3D model from a ship's compartments so every damageable part is
## visibly its own piece. Destroyed parts go charred and drop away; fires glow.
## (Placeholder art: swap each box for a proper mesh later, keyed by compartment id.)

var ship: Ship
var parts := {}          ## Compartment -> MeshInstance3D
var _mats := {}          ## Compartment -> StandardMaterial3D
var _t := 0.0

const COLORS := {
	Compartment.Kind.HULL_SECTION: Color(0.38, 0.40, 0.42),
	Compartment.Kind.BOW: Color(0.36, 0.38, 0.40),
	Compartment.Kind.STERN: Color(0.36, 0.38, 0.40),
	Compartment.Kind.TURRET: Color(0.30, 0.32, 0.33),
	Compartment.Kind.BRIDGE: Color(0.45, 0.47, 0.48),
	Compartment.Kind.FUNNEL: Color(0.15, 0.15, 0.16),
	Compartment.Kind.MAST: Color(0.5, 0.5, 0.5),
	Compartment.Kind.SECONDARY_MOUNT: Color(0.33, 0.35, 0.36),
	Compartment.Kind.AA_MOUNT: Color(0.28, 0.30, 0.31),
	Compartment.Kind.TORPEDO_TUBES: Color(0.25, 0.28, 0.25),
	Compartment.Kind.HANGAR: Color(0.42, 0.44, 0.45),
}
const INTERNAL := [Compartment.Kind.ENGINE_ROOM, Compartment.Kind.BOILER_ROOM, Compartment.Kind.MAGAZINE,
	Compartment.Kind.FUEL_TANK, Compartment.Kind.STEERING_GEAR, Compartment.Kind.SCREW, Compartment.Kind.RUDDER]


const STRUCT := [Compartment.Kind.HULL_SECTION, Compartment.Kind.BOW, Compartment.Kind.STERN]


func setup(p_ship: Ship) -> void:
	ship = p_ship
	# One smooth lofted hull from the standard frame (red below the waterline, grey above).
	var frame := ShipFrame.for_entry(Roster.get_entry(ship.class_id))
	var hull := MeshInstance3D.new()
	hull.mesh = frame.hull_mesh()
	var hm := StandardMaterial3D.new()
	hm.vertex_color_use_as_albedo = true
	hm.roughness = 0.75
	hm.cull_mode = BaseMaterial3D.CULL_DISABLED
	hull.material_override = hm
	add_child(hull)
	for c in ship.compartments:
		if c.kind in INTERNAL:
			continue                     # hidden inside the hull; still simulated
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = c.half_extents * 2.0
		mi.mesh = box
		mi.position = c.center
		if c.kind in STRUCT:
			mi.scale = Vector3(0.9, 1.0, 0.97)
			mi.visible = false           # hull sections only show as dark wounds once damaged
		var mat := StandardMaterial3D.new()
		mat.albedo_color = COLORS.get(c.kind, Color(0.4, 0.4, 0.4))
		mat.roughness = 0.8
		mi.material_override = mat
		add_child(mi)
		parts[c] = mi
		_mats[c] = mat


var _plumes: Dictionary = {}     ## Compartment -> Node3D (smoke/flame emitter)


func _plume(c: Compartment, mi: MeshInstance3D, on: bool) -> void:
	if on and not _plumes.has(c):
		var sz := clampf((c.half_extents.x + c.half_extents.z) * 0.5, 1.5, 9.0)
		_plumes[c] = Fx.burning(self, c.center + Vector3(0, c.half_extents.y, 0), sz)
	if _plumes.has(c):
		var node: Node3D = _plumes[c]
		for ch in node.get_children():
			(ch as CPUParticles3D).emitting = on


func _process(delta: float) -> void:
	_t += delta
	for c in parts:
		var mi: MeshInstance3D = parts[c]
		var mat: StandardMaterial3D = _mats[c]
		_plume(c, mi, (c.on_fire or (c.destroyed and c.kind != Compartment.Kind.HULL_SECTION)) and not ship.sunk)
		if c.kind in STRUCT:
			mi.visible = c.destroyed or c.health_fraction() < 0.55
			mat.albedo_color = Color(0.06, 0.05, 0.05)
			continue
		if c.destroyed:
			mat.albedo_color = Color(0.06, 0.05, 0.05)
			if c.kind in [Compartment.Kind.MAST, Compartment.Kind.FUNNEL, Compartment.Kind.TURRET]:
				mi.rotation.z = lerpf(mi.rotation.z, 0.7, delta)
				mi.position.y = lerpf(mi.position.y, c.center.y - 1.0, delta * 0.5)
		elif c.on_fire:
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.45, 0.1) * (0.6 + 0.4 * sin(_t * 12.0 + c.center.z))
		else:
			mat.emission_enabled = false
			var damage: float = 1.0 - c.health_fraction()
			var base: Color = COLORS.get(c.kind, Color(0.4, 0.4, 0.4))
			mat.albedo_color = base.lerp(Color(0.1, 0.08, 0.07), damage * 0.8)
