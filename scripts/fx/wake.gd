class_name Wake
extends Node3D
## Foam wake behind a moving ship plus bow spray. Particles live in world space so the
## trail stays where the ship was. Emission is switched off when the ship is slow or far away.

var ship: Ship
var _stern: CPUParticles3D
var _bow: CPUParticles3D
var _t := 0.0
var _bow_scale0 := 1.0
var _kelvin: MeshInstance3D
var _kmat: ShaderMaterial

## The pattern a hull leaves on the water: two diverging arms at 19.5 degrees (wider as the keel nears
## the bottom and the ship approaches the critical depth speed) with transverse waves between them,
## whose wavelength is set by speed (lambda = 2 pi v^2 / g). Drawn in the ship's frame, where it is
## stationary for steady motion, and faded with energy (Froude number).
const KELVIN_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
uniform float hull_len = 400.0;
uniform float beam = 30.0;
uniform float lam = 60.0;
uniform float tan_t = 0.354;
uniform float amp = 1.0;
uniform vec2 extent = vec2(2000.0, 3000.0);
varying vec2 lp;
void vertex() { lp = VERTEX.xz; }
void fragment() {
	float s = max(-lp.y, 0.0);
	float x = lp.x;
	float ax = abs(x);
	float cos_t = inversesqrt(1.0 + tan_t * tan_t);
	float dperp = abs(ax - tan_t * s) * cos_t;
	float w = 0.9 * beam + 0.05 * s;
	float arm = exp(-pow(dperp / w, 2.0));
	float ripple = 0.55 + 0.45 * cos(s * 6.2832 / (lam * 0.62) + ax * 0.01);
	float decay = exp(-s / (hull_len * 6.0)) / sqrt(1.0 + s / (hull_len * 1.5));
	float inside = smoothstep(tan_t * s, tan_t * s * 0.55, ax);
	float trans = inside * (0.5 + 0.5 * cos(s * 6.2832 / lam)) * exp(-s / (hull_len * 3.0)) * smoothstep(0.0, hull_len * 0.4, s);
	float a = (arm * ripple * 0.65 + trans * 0.32) * decay * amp;
	a *= smoothstep(extent.x * 0.5, extent.x * 0.38, ax) * smoothstep(extent.y, extent.y * 0.8, s);
	ALBEDO = vec3(0.86, 0.93, 0.97);
	ALPHA = clamp(a * 1.7, 0.0, 0.62);
}
"""


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
	_bow_scale0 = _bow.scale_amount_max
	add_child(_bow)
	_build_kelvin()


func _build_kelvin() -> void:
	var L := ship.wlen()
	var ext := Vector2(L * 5.0, L * 9.0)
	var pm := PlaneMesh.new()
	pm.size = ext
	pm.center_offset = Vector3(0.0, 0.0, -ext.y * 0.5)
	pm.subdivide_width = 1
	pm.subdivide_depth = 1
	var sh := Shader.new()
	sh.code = KELVIN_SHADER
	_kmat = ShaderMaterial.new()
	_kmat.shader = sh
	_kmat.set_shader_parameter("hull_len", L)
	_kmat.set_shader_parameter("beam", ship.wbeam())
	_kmat.set_shader_parameter("extent", ext)
	pm.material = _kmat
	_kelvin = MeshInstance3D.new()
	_kelvin.mesh = pm
	_kelvin.top_level = true
	_kelvin.visible = false
	_kelvin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_kelvin)


func _update_kelvin(near: bool, spd: float) -> void:
	var hy: Hydro = ship.hydro
	if hy == null or not near or spd < 2.5:
		_kelvin.visible = false
		return
	_kelvin.visible = true
	var fwd := Vector3(sin(ship.heading), 0.0, cos(ship.heading))
	_kelvin.global_transform = Transform3D(Basis(Vector3.UP, ship.heading), ship.global_position - fwd * ship.wlen() * 0.44 + Vector3(0, 0.22, 0))
	var fh := hy.depth_froude
	var open := smoothstep(0.55, 1.0, fh) * hy.shallow * 1.4
	var tan_t := lerpf(0.354, 1.8, clampf(open, 0.0, 1.0))        # the arms open toward 90 deg at critical depth speed
	_kmat.set_shader_parameter("tan_t", tan_t)
	_kmat.set_shader_parameter("lam", maxf(TAU * spd * spd / 9.81 * Ship.WORLD_SCALE, 14.0))
	_kmat.set_shader_parameter("amp", clampf(smoothstep(0.08, 0.5, hy.froude) * (1.0 + 0.8 * hy.shallow), 0.0, 1.4))


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
			_kelvin.visible = false
		return
	_t += delta
	var cam := get_viewport().get_camera_3d()
	var near := true
	if cam != null:
		near = cam.global_position.distance_to(ship.global_position) < 6000.0
	var spd := absf(ship.speed_ms)
	var fwd := Vector3(sin(ship.heading), 0.0, cos(ship.heading))
	_update_kelvin(near, spd)
	var wash: float = ship.hydro.prop_wash if ship.hydro != null else 0.0
	# Propellers churning the water show even when the hull has barely any way on.
	_stern.emitting = near and (spd > 1.5 or wash > 0.2)
	if OS.get_cmdline_user_args().has("--wakedebug") and ship.is_player and int(_t * 10.0) % 20 == 0:
		print("WAKE spd=%.1f emit=%s near=%s pos=%s vis=%s amt=%d" % [spd, _stern.emitting, near, str(_stern.global_position), str(_stern.is_visible_in_tree()), _stern.amount])
	_stern.global_position = ship.global_position - fwd * ship.wlen() * 0.42 + Vector3(0, 0.35, 0)
	_stern.speed_scale = clampf(spd / 10.0, 0.5, 1.5)
	_stern.initial_velocity_max = 0.4 + spd * 0.02 + 3.0 * wash * (1.0 - clampf(spd / 12.0, 0.0, 1.0))
	_bow.emitting = near and spd > 6.0
	if ship.hydro != null:
		var g := clampf(0.35 + ship.hydro.froude * 2.0, 0.35, 1.5)           # bow wave grows with Froude number
		_bow.scale_amount_min = _bow_scale0 * g * 0.8
		_bow.scale_amount_max = _bow_scale0 * g
	_bow.global_position = ship.global_position + fwd * ship.wlen() * 0.46 + Vector3(0, 0.8, 0)
	_bow.direction = (Vector3.UP + fwd * 0.5).normalized()
	_bow.initial_velocity_max = 3.0 + spd * 0.35
