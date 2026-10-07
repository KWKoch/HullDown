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
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07, 0.11, 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.62, 0.72)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 40, 0)
	sun.light_energy = 1.25
	vp.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15, 220, 0)
	fill.light_energy = 0.35
	vp.add_child(fill)
	# a calm sea disc
	var disc := CylinderMesh.new()
	disc.top_radius = 2600.0
	disc.bottom_radius = 2600.0
	disc.height = 1.0
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.06, 0.16, 0.25)
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var sea := MeshInstance3D.new()
	sea.mesh = disc
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
