class_name Weather
extends Node3D
## Rain or snow that follows the active camera. kind: "rain" | "snow" | "" (none).

var kind := ""
var _p: CPUParticles3D


func setup(p_kind: String) -> void:
	kind = p_kind
	if kind == "rain":
		_p = CPUParticles3D.new()
		_p.amount = 2200
		_p.lifetime = 0.7
		_p.local_coords = false
		_p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		_p.emission_box_extents = Vector3(70, 1, 70)
		_p.direction = Vector3.DOWN
		_p.spread = 3.0
		_p.initial_velocity_min = 36.0
		_p.initial_velocity_max = 44.0
		_p.gravity = Vector3(6, 0, 2)
		var b := BoxMesh.new()
		b.size = Vector3(0.012, 1.1, 0.012)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.75, 0.8, 0.88, 0.35)
		b.material = m
		_p.mesh = b
	elif kind == "snow":
		_p = CPUParticles3D.new()
		_p.amount = 2600
		_p.lifetime = 7.0
		_p.local_coords = false
		_p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		_p.emission_box_extents = Vector3(60, 1, 60)
		_p.direction = Vector3.DOWN
		_p.spread = 25.0
		_p.initial_velocity_min = 2.0
		_p.initial_velocity_max = 4.5
		_p.gravity = Vector3(1.5, 0, 0.5)
		_p.tangential_accel_min = -1.5
		_p.tangential_accel_max = 1.5
		_p.scale_amount_min = 0.08
		_p.scale_amount_max = 0.2
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		q.material = Fx._material(false, false)
		_p.mesh = q
		_p.color = Color(1, 1, 1, 0.9)
	if _p != null:
		_p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_p.preprocess = _p.lifetime
		add_child(_p)
		_p.emitting = true


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam != null and _p != null:
		global_position = cam.global_position + Vector3(0, 28, 0)
