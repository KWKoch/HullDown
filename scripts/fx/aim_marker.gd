class_name AimMarker
extends MeshInstance3D
## The aiming reticle as seen from above, like the landing marker in a golf game: an ellipse laid on
## the water where the shells will fall, sized to the battery's dispersion at that range (long axis
## along the line of fire) with a crosshair through it. Colour follows the battery status.

const RING_SEGS := 56

var _mesh := ImmediateMesh.new()


func _init() -> void:
	top_level = true
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 30000.0
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.render_priority = 10
	material_override = m


## `aim` is the world aim point; `sigma` the 1-sigma scatter (range, deflection) in metres there.
func update_for(aim: Vector3, shooter: Ship, sigma: Vector2, col: Color, terrain: BattleTerrain) -> void:
	_mesh.clear_surfaces()
	var cam := get_viewport().get_camera_3d()
	if cam == null or shooter == null or shooter.sunk:
		return
	var flat := Vector2(aim.x - shooter.global_position.x, aim.z - shooter.global_position.z)
	var along := flat.normalized() if flat.length() > 1.0 else Vector2(sin(shooter.heading), cos(shooter.heading))
	var across := Vector2(-along.y, along.x)
	var ground := 0.0 if terrain == null else maxf(terrain.height_at(aim.x, aim.z), 0.0)
	var y := ground + 2.5
	var centre := Vector2(aim.x, aim.z)
	var a := maxf(sigma.x * 2.0, 9.0)       # semi-axis along the line of fire
	var b := maxf(sigma.y * 2.0, 6.0)       # semi-axis across it
	var dist := cam.global_position.distance_to(aim)
	var w := clampf(dist * 0.0028, 0.35, 16.0)
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring_col := Color(col.r, col.g, col.b, 0.95)
	var glow := Color(col.r, col.g, col.b, 0.22)
	# Soft fill of the scatter ellipse.
	var prev := centre + along * a
	for i in range(1, RING_SEGS + 1):
		var th := TAU * float(i) / RING_SEGS
		var p := centre + along * (a * cos(th)) + across * (b * sin(th))
		_tri(centre, prev, p, y - 0.05, glow, glow, glow)
		prev = p
	# The ring itself, a ribbon of width w centred on the ellipse.
	var last_o := centre + along * (a + w * 0.5)
	var last_i := centre + along * (a - w * 0.5)
	for i in range(1, RING_SEGS + 1):
		var th2 := TAU * float(i) / RING_SEGS
		var dir_e := (along * cos(th2) * (1.0 / a) + across * sin(th2) * (1.0 / b)).normalized()     # outward normal
		var pe := centre + along * (a * cos(th2)) + across * (b * sin(th2))
		var po := pe + dir_e * (w * 0.5)
		var pi := pe - dir_e * (w * 0.5)
		_tri(last_i, last_o, po, y, ring_col, ring_col, ring_col)
		_tri(last_i, po, pi, y, ring_col, ring_col, ring_col)
		last_o = po
		last_i = pi
	# Crosshair through the ring, extended a little past it, with a gap at the middle.
	var gap := minf(a, b) * 0.18
	var la := maxf(a * 1.35, dist * 0.022)      # arms stay readable when the ellipse is a few pixels across
	var lb := maxf(b * 1.35, dist * 0.014)
	for seg in [[along, la], [-along, la], [across, lb], [-across, lb]]:
		var d: Vector2 = seg[0]
		var ln: float = seg[1]
		var side := Vector2(-d.y, d.x) * (w * 0.5)
		var p0 := centre + d * gap
		var p1 := centre + d * ln
		_tri(p0 - side, p0 + side, p1 + side, y, ring_col, ring_col, ring_col)
		_tri(p0 - side, p1 + side, p1 - side, y, ring_col, ring_col, ring_col)
	_mesh.surface_end()


func _tri(p0: Vector2, p1: Vector2, p2: Vector2, y: float, c0: Color, c1: Color, c2: Color) -> void:
	_mesh.surface_set_color(c0)
	_mesh.surface_add_vertex(Vector3(p0.x, y, p0.y))
	_mesh.surface_set_color(c1)
	_mesh.surface_add_vertex(Vector3(p1.x, y, p1.y))
	_mesh.surface_set_color(c2)
	_mesh.surface_add_vertex(Vector3(p2.x, y, p2.y))
