class_name ShellTrail
extends Node3D
## A soft white vapour trail marking a shell's flight so the player can see the arc of a shot
## and walk the next one onto the target. The trail lingers after the shell lands, then fades.

const LIFE := 8.0            ## seconds a point of the trail stays visible
const MIN_STEP := 22.0       ## metres between recorded points
const PEAK_ALPHA := 0.6

var _pts: Array[Vector3] = []
var _times: Array[float] = []
var _done := false
var _mesh := ImmediateMesh.new()
var _clock := 0.0


func _ready() -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 20000.0
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	add_child(mi)
	top_level = true
	add_to_group("trails")
	global_transform = Transform3D.IDENTITY


func add_point(p: Vector3, force: bool = false) -> void:
	if _pts.is_empty() or force or _pts[_pts.size() - 1].distance_to(p) >= MIN_STEP:
		_pts.append(p)
		_times.append(_clock)


func point_count() -> int:
	return _pts.size()


func finish(end: Vector3) -> void:
	add_point(end, true)
	_done = true


func _process(delta: float) -> void:
	_clock += delta
	# Drop points that have faded out entirely.
	while not _times.is_empty() and _clock - _times[0] > LIFE:
		_pts.remove_at(0)
		_times.remove_at(0)
	if _pts.size() < 2:
		_mesh.clear_surfaces()
		if _done and _pts.size() < 2:
			queue_free()
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp := cam.global_position
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := _pts.size()
	var left: Array[Vector3] = []
	var right: Array[Vector3] = []
	var cols: Array[float] = []
	for i in n:
		var p := _pts[i]
		var tang := (_pts[mini(i + 1, n - 1)] - _pts[maxi(i - 1, 0)]).normalized()
		var view := (cp - p).normalized()
		var side := tang.cross(view)
		if side.length() < 0.001:
			side = Vector3.UP.cross(tang)
		side = side.normalized()
		var w := clampf(cp.distance_to(p) * 0.0045, 0.5, 12.0)
		left.append(p - side * w)
		right.append(p + side * w)
		cols.append(clampf(1.0 - (_clock - _times[i]) / LIFE, 0.0, 1.0) * PEAK_ALPHA)
	for i in n - 1:
		_quad(left[i], _pts[i], left[i + 1], _pts[i + 1], 0.0, cols[i], 0.0, cols[i + 1])
		_quad(_pts[i], right[i], _pts[i + 1], right[i + 1], cols[i], 0.0, cols[i + 1], 0.0)
	_mesh.surface_end()


func _quad(a0: Vector3, b0: Vector3, a1: Vector3, b1: Vector3, ca0: float, cb0: float, ca1: float, cb1: float) -> void:
	# a0--b0 is the cross-section at point i, a1--b1 at point i+1.
	_vtx(a0, ca0)
	_vtx(b0, cb0)
	_vtx(a1, ca1)
	_vtx(b0, cb0)
	_vtx(b1, cb1)
	_vtx(a1, ca1)


func _vtx(p: Vector3, a: float) -> void:
	_mesh.surface_set_color(Color(1, 1, 1, a))
	_mesh.surface_add_vertex(p)
