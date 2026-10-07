class_name TopoView
extends SubViewportContainer
## Interactive 3D topographic map of a battleground: hypsometric tint, contour lines, shaded relief,
## named waypoints, and a line-of-sight overlay that shows what an observer (click anywhere) can and
## cannot see -- i.e. where there is cover and concealment. Drag to orbit, wheel to zoom.

signal observer_changed(pos: Vector2)

const N := 129
const SHADER := """
shader_type spatial;
render_mode cull_back;
uniform sampler2D vis_tex : filter_linear;
uniform float arena = 14000.0;
uniform float show_vis = 1.0;
uniform float land_exag = 4.0;
uniform float sea_exag = 0.15;
varying float vh;
varying vec2 wuv;
void vertex() {
	float y = VERTEX.y;
	vh = y > 0.0 ? y / land_exag : y / sea_exag;
	wuv = VERTEX.xz / arena + 0.5;
}
void fragment() {
	vec3 col;
	if (vh > 0.5) {
		float t = clamp(vh / 700.0, 0.0, 1.0);
		col = mix(vec3(0.30, 0.46, 0.22), vec3(0.64, 0.57, 0.38), smoothstep(0.0, 0.5, t));
		col = mix(col, vec3(0.93, 0.93, 0.95), smoothstep(0.55, 1.0, t));
	} else if (vh > -1.0) {
		col = vec3(0.80, 0.74, 0.55);
	} else {
		col = mix(vec3(0.36, 0.76, 0.72), vec3(0.13, 0.36, 0.56), smoothstep(0.0, 40.0, -vh));
		col = mix(col, vec3(0.04, 0.10, 0.22), smoothstep(40.0, 250.0, -vh));
	}
	float interval = vh > 0.0 ? 50.0 : (vh > -60.0 ? 10.0 : 50.0);
	float f = vh / interval;
	float w = fwidth(f) + 0.0008;
	float line = 1.0 - smoothstep(0.0, w * 1.4, abs(fract(f - 0.5) - 0.5));
	float major = 1.0 - smoothstep(0.0, w * 1.4, abs(fract(f / 5.0 - 0.5) - 0.5));
	col = mix(col, col * 0.35, line * (vh > 0.0 ? 0.7 : 0.45) * clamp(1.0 / (w * 40.0), 0.0, 1.0));
	col = mix(col, col * 0.2, major * 0.4);
	if (show_vis > 0.5) {
		float v = texture(vis_tex, wuv).r;
		col = mix(col * 0.5 + vec3(0.0, 0.0, 0.06), mix(col, vec3(1.0, 0.75, 0.2), 0.45), v);
	}
	ALBEDO = col;
	ROUGHNESS = 1.0;
}
"""

var ground: Dictionary = {}
var vp: SubViewport
var cam: Camera3D
var terrain_mi: MeshInstance3D
var mat: ShaderMaterial
var vis_img: Image
var vis_tex: ImageTexture
var vis_on := true
var observer := Vector2.ZERO
var observer_node: Node3D
var hs := PackedFloat32Array()
var size_m := Vector2(14000, 14000)
var yaw := 0.0
var pitch := 0.75
var dist := 17000.0
var _drag_start := Vector2.ZERO
var _dragging := false
var _moved := false
var _labels: Array[Label3D] = []
var _marks: Array[Node3D] = []


func _init() -> void:
	stretch = true
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_2X
	add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.06, 0.1)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.66, 0.72)
	env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 135, 0)
	sun.light_energy = 0.9
	vp.add_child(sun)
	cam = Camera3D.new()
	cam.near = 200.0
	cam.far = 120000.0
	cam.fov = 45.0
	vp.add_child(cam)


func setup(g: Dictionary) -> void:
	ground = g
	size_m = g["size_m"]
	hs = MapData.grid(g, N)
	_build_mesh()
	if not OS.get_cmdline_user_args().has("--nowater"):
		_build_water()
	_build_waypoints()
	vis_img = Image.create(N, N, false, Image.FORMAT_R8)
	vis_tex = ImageTexture.create_from_image(vis_img)
	mat.set_shader_parameter("vis_tex", vis_tex)
	var sa: Vector3 = g["spawn_a"]
	set_observer(Vector2(sa.x, sa.z), false)
	if OS.get_cmdline_user_args().has("--novis"):
		set_vis_on(false)
	reset_camera()


func _build_mesh() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var vtx: Array[Vector3] = []
	for j in N:
		for i in N:
			vtx.append(Vector3((float(i) / (N - 1) - 0.5) * size_m.x, MapData.exag(hs[j * N + i]), (float(j) / (N - 1) - 0.5) * size_m.y))
	for j in N - 1:
		for i in N - 1:
			var a := vtx[j * N + i]
			var b := vtx[j * N + i + 1]
			var c := vtx[(j + 1) * N + i]
			var d := vtx[(j + 1) * N + i + 1]
			for v in [a, b, c, b, d, c]:
				st.add_vertex(v)
	st.generate_normals()
	terrain_mi = MeshInstance3D.new()
	terrain_mi.mesh = st.commit()
	var sh := Shader.new()
	sh.code = SHADER
	mat = ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("arena", size_m.x)
	mat.set_shader_parameter("land_exag", MapData.LAND_EXAG)
	mat.set_shader_parameter("sea_exag", MapData.SEA_EXAG)
	terrain_mi.material_override = mat
	vp.add_child(terrain_mi)


func _build_water() -> void:
	var pm := PlaneMesh.new()
	pm.size = size_m * 1.0
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.2, 0.45, 0.7, 0.28)
	m.roughness = 0.2
	m.metallic = 0.3
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = m
	mi.position.y = 1.0
	vp.add_child(mi)


func _build_waypoints() -> void:
	for wp in Battlegrounds.waypoints(ground["id"]):
		var p: Vector2 = wp["p"]
		var col := MapData.kind_color(wp["k"])
		var base_y := maxf(MapData.exag(surface_h(p)), 0.0)
		var root := Node3D.new()
		root.position = Vector3(p.x, base_y, p.y)
		var pole := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 18.0
		cm.bottom_radius = 18.0
		var ph := 500.0 + 450.0 * (_marks.size() % 3)
		cm.height = ph
		pole.mesh = cm
		pole.position.y = ph * 0.5
		var pm := StandardMaterial3D.new()
		pm.albedo_color = col
		pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pole.material_override = pm
		root.add_child(pole)
		var ball := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 70.0
		sm.height = 140.0
		ball.mesh = sm
		ball.position.y = ph + 20.0
		ball.material_override = pm
		root.add_child(ball)
		var lb := Label3D.new()
		lb.text = wp["n"]
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.fixed_size = true
		lb.no_depth_test = true
		lb.pixel_size = 0.00042
		lb.font_size = 40
		lb.outline_size = 14
		lb.modulate = col.lerp(Color.WHITE, 0.45)
		lb.outline_modulate = Color(0.02, 0.03, 0.05, 0.95)
		lb.position.y = ph + 260.0
		lb.render_priority = 5
		lb.outline_render_priority = 4
		root.add_child(lb)
		vp.add_child(root)
		_marks.append(root)
		_labels.append(lb)
	observer_node = Node3D.new()
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 150.0
	tm.outer_radius = 210.0
	ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(1.0, 0.8, 0.2)
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = rm
	observer_node.add_child(ring)
	var eye := MeshInstance3D.new()
	var em := CylinderMesh.new()
	em.top_radius = 6.0
	em.bottom_radius = 6.0
	em.height = 700.0
	eye.mesh = em
	eye.position.y = 350.0
	eye.material_override = rm
	observer_node.add_child(eye)
	vp.add_child(observer_node)


func surface_h(p: Vector2) -> float:
	var fi := clampf((p.x / size_m.x + 0.5) * (N - 1), 0.0, N - 1.001)
	var fj := clampf((p.y / size_m.y + 0.5) * (N - 1), 0.0, N - 1.001)
	var i := int(fi)
	var j := int(fj)
	var tx := fi - i
	var tz := fj - j
	return lerpf(lerpf(hs[j * N + i], hs[j * N + i + 1], tx), lerpf(hs[(j + 1) * N + i], hs[(j + 1) * N + i + 1], tx), tz)


func set_vis_on(on: bool) -> void:
	vis_on = on
	mat.set_shader_parameter("show_vis", 1.0 if on else 0.0)


func set_observer(p: Vector2, announce: bool = true) -> void:
	observer = p
	var h := maxf(MapData.exag(surface_h(p)), 0.0)
	observer_node.position = Vector3(p.x, h + 4.0, p.y)
	var bytes := MapData.visibility(hs, N, size_m, p, 25.0, 14.0)
	vis_img = Image.create_from_data(N, N, false, Image.FORMAT_R8, bytes)
	vis_tex.update(vis_img)
	if announce:
		observer_changed.emit(p)


## Percentage of open water the observer can see (for the info panel).
func exposed_water_pct() -> float:
	var bytes := vis_img.get_data()
	var sea := 0
	var seen := 0
	for k in N * N:
		if hs[k] <= 0.0:
			sea += 1
			if bytes[k] > 127:
				seen += 1
	return 100.0 * seen / maxf(sea, 1)


func reset_camera() -> void:
	yaw = 0.0
	pitch = 0.75
	dist = size_m.x * 1.2
	_apply_cam()


func zoom(f: float) -> void:
	dist = clampf(dist * f, 1500.0, size_m.x * 2.4)
	_apply_cam()


func _apply_cam() -> void:
	# yaw 0 looks north (+Z) from the south, so east (-X) is on the right of the screen.
	var d := Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
	cam.position = d * dist + Vector3(0, 0, 0)
	cam.look_at(Vector3.ZERO, Vector3.UP)


func _pick(pos: Vector2) -> Variant:
	var o := cam.project_ray_origin(pos)
	var dir := cam.project_ray_normal(pos)
	var t := 0.0
	var prev := 0.0
	var step := 80.0
	while t < 90000.0:
		var p := o + dir * t
		if absf(p.x) < size_m.x * 0.5 and absf(p.z) < size_m.y * 0.5:
			if p.y <= maxf(MapData.exag(surface_h(Vector2(p.x, p.z))), 0.0):
				var lo := prev
				var hi := t
				for k in 12:
					var mid := (lo + hi) * 0.5
					var q := o + dir * mid
					if q.y <= maxf(MapData.exag(surface_h(Vector2(q.x, q.z))), 0.0):
						hi = mid
					else:
						lo = mid
				var r := o + dir * hi
				return Vector2(r.x, r.z)
		prev = t
		t += step
	return null


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = true
				_moved = false
				_drag_start = mb.position
			else:
				if _dragging and not _moved:
					var hit: Variant = _pick(mb.position)
					if hit != null:
						set_observer(hit)
				_dragging = false
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom(0.88)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom(1.14)
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		if mm.position.distance_to(_drag_start) > 6.0:
			_moved = true
		if _moved:
			yaw -= mm.relative.x * 0.006
			pitch = clampf(pitch + mm.relative.y * 0.005, 0.12, 1.5)
			_apply_cam()
	elif event is InputEventMagnifyGesture:
		zoom(1.0 / maxf((event as InputEventMagnifyGesture).factor, 0.1))
