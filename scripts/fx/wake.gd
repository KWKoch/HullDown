class_name Wake
extends Node3D
## Foam wake behind a moving ship plus bow spray. Particles live in world space so the
## trail stays where the ship was. Emission is switched off when the ship is slow or far away.

var ship: Ship
var _stern: CPUParticles3D
var _bow: CPUParticles3D
var _t := 0.0


func setup(p_ship: Ship) -> void:
	ship = p_ship
	_stern = Fx.make(160, 16.0, 1.0, Fx._ramp(Color(0.95, 0.98, 1.0, 0.55), Color(0.9, 0.95, 0.98, 0.65), Color(0.8, 0.9, 0.95, 0.0)),
		0.4, 180.0, Vector3.BACK, 0.0, false, 5.0, false)
	_stern.mesh = _flat_quad()
	_stern.flatness = 1.0
	_stern.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_stern.emission_box_extents = Vector3(ship.wbeam() * 0.32, 0.0, 2.0)
	_stern.scale_amount_min = maxf(ship.wbeam() * 0.45, 3.0)
	_stern.scale_amount_max = maxf(ship.wbeam() * 0.7, 4.0)
	_stern.angle_min = -180.0
	_stern.angle_max = 180.0
	_stern.emitting = false
	add_child(_stern)

	_bow = Fx.make(60, 1.1, maxf(ship.wbeam() * 0.12, 1.2), Fx._ramp(Color(1, 1, 1, 0.75), Color(0.92, 0.96, 1.0, 0.4), Color(0.9, 0.95, 1.0, 0.0)),
		7.0, 38.0, Vector3.UP, 9.0, false, 1.6, false)
	_bow.emitting = false
	add_child(_bow)


func _flat_quad() -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.orientation = PlaneMesh.FACE_Y
	q.material = Fx._material(false, true)
	return q


func _process(delta: float) -> void:
	if ship == null or not is_instance_valid(ship) or ship.sunk:
		if _stern != null:
			_stern.emitting = false
			_bow.emitting = false
		return
	_t += delta
	var cam := get_viewport().get_camera_3d()
	var near := true
	if cam != null:
		near = cam.global_position.distance_to(ship.global_position) < 6000.0
	var spd := absf(ship.speed_ms)
	var fwd := Vector3(sin(ship.heading), 0.0, cos(ship.heading))
	_stern.emitting = near and spd > 1.5
	if OS.get_cmdline_user_args().has("--wakedebug") and ship.is_player and int(_t * 10.0) % 20 == 0:
		print("WAKE spd=%.1f emit=%s near=%s pos=%s vis=%s amt=%d" % [spd, _stern.emitting, near, str(_stern.global_position), str(_stern.is_visible_in_tree()), _stern.amount])
	_stern.global_position = ship.global_position - fwd * ship.wlen() * 0.42 + Vector3(0, 0.35, 0)
	_stern.speed_scale = clampf(spd / 10.0, 0.5, 1.5)
	_stern.initial_velocity_max = 0.4 + spd * 0.02
	_bow.emitting = near and spd > 6.0
	_bow.global_position = ship.global_position + fwd * ship.wlen() * 0.46 + Vector3(0, 0.8, 0)
	_bow.direction = (Vector3.UP + fwd * 0.5).normalized()
	_bow.initial_velocity_max = 3.0 + spd * 0.35
