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
func update_for(aim: Vector3, shooter: Ship, sigma: Vector2, col: Color, terrain: BattleTerrain, tof: float = -1.0) -> void:
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
	if tof > 0.5:
		_arc(aim, shooter, cam, terrain, tof)


## The shell's flight path from the guns to the aim point, so you can see what it will clear: a soft
## white ribbon that turns red where the path dips below the terrain.
func _arc(aim: Vector3, shooter: Ship, cam: Camera3D, terrain: BattleTerrain, tof: float) -> void:
	var from := shooter.global_position + Vector3(0, shooter.top_y * 0.5 * Ship.WORLD_SCALE + 6.0, 0)
	var rise := 0.5 * Shell.GRAVITY * tof * tof
	var n := 64
	var pts: Array[Vector3] = []
	var hit := -1
	for i in n + 1:
		var u := float(i) / n
		var pt := from.lerp(aim, u)
		pt.y += rise * u * (1.0 - u)
		pts.append(pt)
		if hit < 0 and terrain != null and i > 2 and i < n - 1 and terrain.height_at(pt.x, pt.z) > pt.y:
			hit = i
	var right_hint := cam.global_transform.basis.x
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	var prev_c := Color.WHITE
	for i in pts.size():
		var tan: Vector3 = (pts[mini(i + 1, n)] - pts[maxi(i - 1, 0)]).normalized()
		var side := tan.cross((cam.global_position - pts[i]).normalized())
		if side.length() < 0.001:
			side = right_hint
		var dd := cam.global_position.distance_to(pts[i])
		var hw := clampf(dd * 0.0011, 0.25, 9.0)
		side = side.normalized() * hw
		var blocked := hit >= 0 and i >= hit
		var base := Color(1.0, 0.3, 0.25) if blocked else Color(1, 1, 1)
		var al := 0.2 + 0.55 * float(i) / n
		var cc := Color(base.r, base.g, base.b, al)
		var l := pts[i] - side
		var r := pts[i] + side
		if i > 0:
			_tri3(prev_l, prev_r, r, prev_c, prev_c, cc)
			_tri3(prev_l, r, l, prev_c, cc, cc)
		prev_l = l
		prev_r = r
		prev_c = cc
	_mesh.surface_end()
	if hit >= 0:
		# A small diamond where the path meets the ground.
		var h := pts[hit]
		var q := clampf(cam.global_position.distance_to(h) * 0.01, 2.0, 60.0)
		var red := Color(1.0, 0.3, 0.25, 0.9)
		_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		var ax := cam.global_transform.basis.x * q
		var ay := cam.global_transform.basis.y * q
		_tri3(h + ax, h + ay, h - ax, red, red, red)
		_tri3(h + ax, h - ax, h - ay, red, red, red)
		_mesh.surface_end()


func _tri3(a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	_mesh.surface_set_color(ca)
	_mesh.surface_add_vertex(a)
	_mesh.surface_set_color(cb)
	_mesh.surface_add_vertex(b)
	_mesh.surface_set_color(cc)
	_mesh.surface_add_vertex(c)


func _tri(p0: Vector2, p1: Vector2, p2: Vector2, y: float, c0: Color, c1: Color, c2: Color) -> void:
	_mesh.surface_set_color(c0)
	_mesh.surface_add_vertex(Vector3(p0.x, y, p0.y))
	_mesh.surface_set_color(c1)
	_mesh.surface_add_vertex(Vector3(p1.x, y, p1.y))
	_mesh.surface_set_color(c2)
	_mesh.surface_add_vertex(Vector3(p2.x, y, p2.y))
