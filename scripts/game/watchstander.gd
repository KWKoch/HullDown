class_name Watchstander
extends Node3D
## A bridge lookout in a greatcoat and steel helmet, raising binoculars. Built to real
## human proportions (about 1.78 m tall, feet at local y=0, facing +Z) from tapered
## primitives; replace with a rigged mesh when real assets arrive.

var wool: StandardMaterial3D
var skin: StandardMaterial3D
var helmet_mat: StandardMaterial3D
var optics: StandardMaterial3D
var _head: Node3D
var _t := 0.0


func _ready() -> void:
	wool = _mat(Color(0.075, 0.085, 0.11), 0.95, 0.0)
	skin = _mat(Color(0.28, 0.19, 0.15), 0.8, 0.0)
	helmet_mat = _mat(Color(0.12, 0.135, 0.105), 0.55, 0.25)
	optics = _mat(Color(0.03, 0.03, 0.035), 0.4, 0.5)
	_build()


func _mat(c: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	m.rim_enabled = true          # edge light so the silhouette separates from the dark sea
	m.rim = 0.9
	m.rim_tint = 0.35
	return m


func _add(mi: MeshInstance3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi


func _cyl(top_r: float, bot_r: float, h: float, pos: Vector3, mat: Material, depth_scale := 1.0) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = top_r
	m.bottom_radius = bot_r
	m.height = h
	m.radial_segments = 20
	m.rings = 1
	var mi := _add(MeshInstance3D.new(), m, mat, pos)
	mi.scale = Vector3(1.0, 1.0, depth_scale)
	return mi


func _sphere(r: float, scale3: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 20
	m.rings = 12
	var mi := _add(MeshInstance3D.new(), m, mat, pos)
	mi.scale = scale3
	return mi


## A capsule limb running from point a to point b.
func _limb(a: Vector3, b: Vector3, r: float, mat: Material) -> MeshInstance3D:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = a.distance_to(b) + r * 2.0
	m.radial_segments = 14
	var mi := _add(MeshInstance3D.new(), m, mat, (a + b) * 0.5)
	mi.basis = Basis(Quaternion(Vector3.UP, (b - a).normalized()))
	return mi


func _build() -> void:
	# Legs and boots.
	for s in [-1.0, 1.0]:
		_cyl(0.085, 0.058, 0.86, Vector3(s * 0.105, 0.47, 0.0), wool)
		_add(MeshInstance3D.new(), _box(0.105, 0.09, 0.27), optics, Vector3(s * 0.105, 0.045, 0.05))
	# Greatcoat skirt and torso (narrower front-to-back than side-to-side).
	_cyl(0.205, 0.245, 0.64, Vector3(0.0, 0.88, 0.0), wool, 0.66)
	_cyl(0.215, 0.195, 0.52, Vector3(0.0, 1.38, 0.0), wool, 0.64)
	# Shoulders, collar and neck.
	var sh := _limb(Vector3(-0.2, 1.6, 0.0), Vector3(0.2, 1.6, 0.0), 0.085, wool)
	sh.scale = Vector3(1.0, 1.0, 0.8)
	_cyl(0.09, 0.105, 0.09, Vector3(0.0, 1.66, -0.01), wool, 0.9)       # turned-up collar
	_cyl(0.048, 0.055, 0.09, Vector3(0.0, 1.71, 0.0), skin)
	# Head, helmet and brim.
	_head = Node3D.new()
	_head.position = Vector3(0.0, 1.0, 0.0)
	add_child(_head)
	var head := _sphere(0.098, Vector3(0.92, 1.12, 1.0), Vector3(0.0, 0.79, 0.01), skin)
	head.reparent(_head, false)
	head.position = Vector3(0.0, 0.79 + 0.0, 0.01)
	var hel := _sphere(0.125, Vector3(1.0, 0.66, 1.08), Vector3(0.0, 0.855, 0.0), helmet_mat)
	hel.reparent(_head, false)
	hel.position = Vector3(0.0, 0.855, 0.0)
	var brim := _cyl(0.16, 0.172, 0.014, Vector3(0.0, 0.815, 0.0), helmet_mat, 1.12)
	brim.reparent(_head, false)
	brim.position = Vector3(0.0, 0.815, 0.0)
	# Arms: shoulder -> elbow -> hand at the glasses.
	for s in [-1.0, 1.0]:
		var shoulder := Vector3(s * 0.235, 1.56, 0.0)
		var elbow := Vector3(s * 0.285, 1.31, 0.09)
		var hand := Vector3(s * 0.075, 1.775, 0.285)
		_limb(shoulder, elbow, 0.058, wool)
		_limb(elbow, hand, 0.047, wool)
		_sphere(0.05, Vector3.ONE, hand, skin)
	# Binoculars: two barrels and a bridge.
	for s in [-1.0, 1.0]:
		var barrel := _cyl(0.04, 0.034, 0.18, Vector3(s * 0.044, 1.775, 0.30), optics)
		barrel.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	_add(MeshInstance3D.new(), _box(0.05, 0.04, 0.07), optics, Vector3(0.0, 1.775, 0.27))


func _box(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(x, y, z)
	return b


func _process(delta: float) -> void:
	_t += delta
	# Breathing, and a slow sweep of the horizon with the glasses.
	scale.y = 1.0 + sin(_t * 1.3) * 0.004
	if _head != null:
		_head.rotation.y = sin(_t * 0.35) * 0.07
