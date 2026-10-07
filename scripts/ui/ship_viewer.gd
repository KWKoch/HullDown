class_name ShipViewer
extends SubViewportContainer
## 3D turntable showing a roster ship with the real in-battle model. Drag to rotate, wheel to zoom.

var vp: SubViewport
var cam: Camera3D
var holder: Node3D
var ship: Ship
var yaw := -0.6
var pitch := 0.22
var dist := 300.0
var auto_spin := true
var _dragging := false
var _len := 150.0


func _init() -> void:
	stretch = true
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	add_child(vp)
	var env := Environment.new()
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.04, 0.09, 0.18)
	psm.sky_horizon_color = Color(0.32, 0.42, 0.55)
	psm.ground_horizon_color = Color(0.32, 0.42, 0.55)
	psm.ground_bottom_color = Color(0.10, 0.20, 0.30)
	psm.sun_angle_max = 8.0
	sky.sky_material = psm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.30, 0.40, 0.52)
	env.fog_density = 0.00035
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-34, 40, 0)
	sun.light_energy = 1.35
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	vp.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15, 220, 0)
	fill.light_energy = 0.3
	fill.light_color = Color(0.7, 0.8, 1.0)
	fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	vp.add_child(fill)
	# glossy sea that fades into the horizon fog
	var plane := PlaneMesh.new()
	plane.size = Vector2(30000, 30000)
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_disabled;
void fragment() {
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float d = length(wp.xz);
	vec3 deep = vec3(0.02, 0.10, 0.17);
	vec3 shallow = vec3(0.06, 0.24, 0.34);
	float rip = sin(wp.x * 0.05 + wp.z * 0.03) * sin(wp.z * 0.07 - wp.x * 0.02);
	ALBEDO = mix(shallow, deep, clamp(d / 1500.0, 0.0, 1.0)) + vec3(0.02) * rip;
	ROUGHNESS = 0.55;
	METALLIC = 0.0;
	SPECULAR = 0.25;
}
"""
	var sm := ShaderMaterial.new()
	sm.shader = sh
	var sea := MeshInstance3D.new()
	sea.mesh = plane
	sea.material_override = sm
	sea.position.y = -0.6
	vp.add_child(sea)
	holder = Node3D.new()
	vp.add_child(holder)
	cam = Camera3D.new()
	cam.far = 20000.0
	cam.fov = 38.0
	vp.add_child(cam)


func show_ship(entry: Dictionary) -> void:
	if ship != null:
		ship.queue_free()
		ship = null
	ship = Ship.new()
	holder.add_child(ship)
	ship.setup_from_class(entry, 0)
	ship.set_physics_process(false)
	var vis := ShipVisual.new()
	ship.add_child(vis)
	vis.setup(ship)
	_len = float(entry["length_m"]) * 2.0
	dist = _len * 1.6
	_apply()


func _process(delta: float) -> void:
	if auto_spin and not _dragging:
		yaw += delta * 0.25
		_apply()


func _apply() -> void:
	var look := Vector3(0, _len * 0.07, 0)
	cam.position = look + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
	cam.look_at(look, Vector3.UP)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			dist = clampf(dist * 0.9, _len * 0.5, _len * 4.0)
			_apply()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			dist = clampf(dist * 1.1, _len * 0.5, _len * 4.0)
			_apply()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		yaw -= mm.relative.x * 0.01
		pitch = clampf(pitch + mm.relative.y * 0.006, -0.1, 1.2)
		_apply()


## Harbour backdrop for the Port home screen: quay, sheds, cranes and hills on the far (+X) side.
func add_harbor() -> void:
	var mat := func(c: Color) -> StandardMaterial3D:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.9
		return m
	var box := func(size: Vector3, pos: Vector3, c: Color) -> void:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.material_override = mat.call(c)
		mi.position = pos
		vp.add_child(mi)
	var concrete := Color(0.46, 0.48, 0.5)
	box.call(Vector3(160, 10, 5200), Vector3(820, 3, 0), concrete)                  # quay
	box.call(Vector3(40, 2, 5200), Vector3(750, 0.5, 0), Color(0.2, 0.22, 0.24))   # quay edge shadow
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var z := -2400.0
	while z < 2400.0:
		var w := rng.randf_range(90, 220)
		var h := rng.randf_range(24, 70)
		var tint := rng.randf_range(0.0, 1.0)
		var col := Color(0.62, 0.64, 0.66).lerp(Color(0.55, 0.42, 0.34), tint * 0.5)
		box.call(Vector3(rng.randf_range(80, 140), h, w), Vector3(980 + rng.randf_range(0, 120), h * 0.5 + 8, z + w * 0.5), col)
		z += w + rng.randf_range(20, 90)
	for cz in [-900.0, -300.0, 450.0, 1100.0]:
		var cc := Color(0.20, 0.42, 0.62) if int(cz) % 2 == 0 else Color(0.85, 0.42, 0.18)
		box.call(Vector3(10, 120, 10), Vector3(800, 68, cz), cc)
		box.call(Vector3(10, 120, 10), Vector3(840, 68, cz), cc)
		box.call(Vector3(150, 9, 9), Vector3(770, 128, cz), cc)
	for k in 7:
		var hz := -3600.0 + k * 1200.0
		var hill := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = rng.randf_range(700, 1300)
		sm.height = sm.radius * rng.randf_range(0.5, 0.8)
		hill.mesh = sm
		hill.material_override = mat.call(Color(0.24, 0.32, 0.27).lerp(Color(0.35, 0.40, 0.44), rng.randf()))
		hill.position = Vector3(rng.randf_range(2600, 3600), 0, hz)
		vp.add_child(hill)
