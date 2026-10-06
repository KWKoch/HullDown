class_name Fx
extends RefCounted
## One-shot and persistent visual effects built from CPUParticles3D (works on every
## renderer including web). All bursts are parented to the current scene and free themselves.

static var _soft: Texture2D
static var _mats: Dictionary = {}
static var enabled := true


static func soft_tex() -> Texture2D:
	if _soft == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0.0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_soft = t
	return _soft


static func _material(additive: bool, flat: bool) -> StandardMaterial3D:
	var key := "%s_%s" % [additive, flat]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = soft_tex()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if not flat:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.billboard_keep_scale = true
	_mats[key] = m
	return m


static func _ramp(c0: Color, c1: Color, c2: Color) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	g.colors = PackedColorArray([c0, c1, c2])
	return g


static func _grow(start: float, end: float) -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, start))
	c.add_point(Vector2(1.0, end))
	return c


## Creates a CPUParticles3D with sane defaults. Caller adds it to the tree.
static func make(count: int, life: float, size: float, ramp: Gradient, speed: float, spread_deg: float,
		dir: Vector3, gravity: float, additive: bool, grow_to: float = 2.0, one_shot: bool = true) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = count
	p.lifetime = life
	p.one_shot = one_shot
	p.explosiveness = 0.92 if one_shot else 0.0
	p.randomness = 0.6
	p.local_coords = false
	p.direction = dir
	p.spread = spread_deg
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -gravity, 0)
	p.damping_min = speed * 0.1
	p.damping_max = speed * 0.4
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size * 1.2
	p.scale_amount_curve = _grow(0.5, grow_to)
	p.color_ramp = ramp
	p.angle_min = -180.0
	p.angle_max = 180.0
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.material = _material(additive, false)
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


static func _scene(ctx: Node) -> Node:
	if ctx == null or not ctx.is_inside_tree():
		return null
	return ctx.get_tree().current_scene


static func _place(ctx: Node, p: Node3D, pos: Vector3, life: float) -> void:
	var scn := _scene(ctx)
	if scn == null:
		p.queue_free()
		return
	scn.add_child(p)
	p.global_position = pos
	if p is CPUParticles3D:
		(p as CPUParticles3D).emitting = true
	var pid := p.get_instance_id()          # id, not the node: the node may be freed before the timer fires
	var t := scn.get_tree().create_timer(life + 0.6)
	t.timeout.connect(func() -> void:
		var n := instance_from_id(pid)
		if n != null:
			n.queue_free())


static func _flash(ctx: Node, pos: Vector3, energy: float, range_m: float, color: Color, dur: float) -> void:
	var scn := _scene(ctx)
	if scn == null:
		return
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = range_m
	l.shadow_enabled = false
	scn.add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, dur)
	tw.tween_callback(l.queue_free)


# --- One-shot effects ---------------------------------------------------------

## Shell hits water: a white column that collapses into spray and a drifting mist.
static func splash(ctx: Node, pos: Vector3, caliber_mm: float) -> void:
	if not enabled:
		return
	var k := clampf(caliber_mm / 200.0, 0.3, 2.5)
	var white := _ramp(Color(1, 1, 1, 0.85), Color(0.85, 0.92, 0.97, 0.55), Color(0.8, 0.88, 0.95, 0.0))
	var col := make(int(24 + 26 * k), 2.2 * k + 0.8, 3.0 * k, white, 22.0 * k, 10.0, Vector3.UP, 9.8, false, 1.8)
	_place(ctx, col, Vector3(pos.x, 0.5, pos.z), 3.0 * k + 1.0)
	var mist := make(int(14 + 12 * k), 3.5 * k + 1.0, 6.0 * k, _ramp(Color(0.9, 0.95, 1, 0.35), Color(0.9, 0.95, 1, 0.2), Color(0.9, 0.95, 1, 0.0)),
		7.0 * k, 85.0, Vector3.UP, 0.5, false, 3.5)
	_place(ctx, mist, Vector3(pos.x, 1.0, pos.z), 4.5 * k + 1.0)


## Gun muzzle blast: fire, a smoke puff that drifts upward, and a brief light.
static func muzzle(ctx: Node, pos: Vector3, dir: Vector3, caliber_mm: float) -> void:
	if not enabled:
		return
	var k := clampf(caliber_mm / 200.0, 0.15, 2.0)
	var fire := make(int(10 + 10 * k), 0.22 + 0.15 * k, 2.2 * k + 0.5, _ramp(Color(1, 0.95, 0.7, 1), Color(1, 0.5, 0.15, 0.8), Color(0.3, 0.1, 0.05, 0)),
		26.0 * k, 14.0, dir, 0.0, true, 1.8)
	_place(ctx, fire, pos + dir * 3.0, 0.8)
	var smoke := make(int(6 + 8 * k), 3.0 + 2.0 * k, 3.5 * k + 1.0, _ramp(Color(0.45, 0.42, 0.4, 0.55), Color(0.4, 0.4, 0.4, 0.35), Color(0.4, 0.4, 0.4, 0)),
		9.0 * k, 25.0, dir, -1.2, false, 3.0)
	_place(ctx, smoke, pos + dir * 4.0, 6.0 * k + 2.0)
	_flash(ctx, pos + dir * 5.0, 4.0 + 8.0 * k, 40.0 + 80.0 * k, Color(1.0, 0.75, 0.4), 0.12)


## Shell strikes a ship: fireball, sparks and smoke scaled to the shell.
static func impact(ctx: Node, pos: Vector3, caliber_mm: float) -> void:
	if not enabled:
		return
	explosion(ctx, pos, pow(caliber_mm / 10.0, 1.6) * 0.25)


## Generic explosion; yield_kg ~ explosive-equivalent. A magazine is 100s-1000s.
static func explosion(ctx: Node, pos: Vector3, yield_kg: float) -> void:
	if not enabled:
		return
	var k := clampf(pow(maxf(yield_kg, 1.0), 0.4) * 0.35, 0.5, 14.0)
	var fireball := make(int(18 + 4 * k), 0.7 + 0.18 * k, 5.0 * k, _ramp(Color(1, 0.95, 0.75, 1), Color(1, 0.45, 0.1, 0.85), Color(0.2, 0.06, 0.03, 0)),
		9.0 * k, 70.0, Vector3.UP, -1.0, true, 1.8)
	_place(ctx, fireball, pos, 0.9 + 0.2 * k)
	var smoke := make(int(14 + 3 * k), 5.0 + 0.8 * k, 6.0 * k, _ramp(Color(0.12, 0.11, 0.1, 0.9), Color(0.2, 0.19, 0.18, 0.6), Color(0.35, 0.35, 0.35, 0)),
		6.0 * k, 55.0, Vector3.UP, -2.5, false, 3.2)
	_place(ctx, smoke, pos, 6.0 + k)
	var sparks := make(int(14 + 2 * k), 1.4, 0.35, _ramp(Color(1, 0.9, 0.5, 1), Color(1, 0.4, 0.1, 0.8), Color(0.4, 0.1, 0.0, 0)),
		30.0 * minf(k, 4.0), 90.0, Vector3.UP, 12.0, true, 0.6)
	_place(ctx, sparks, pos, 1.8)
	_flash(ctx, pos, 8.0 + 3.0 * k, 60.0 + 25.0 * k, Color(1.0, 0.65, 0.3), 0.3 + 0.05 * k)


## Shell strikes land: brown dust and debris.
static func dust(ctx: Node, pos: Vector3, caliber_mm: float) -> void:
	if not enabled:
		return
	var k := clampf(caliber_mm / 200.0, 0.3, 2.5)
	var d := make(int(14 + 14 * k), 3.0 * k + 1.5, 5.0 * k, _ramp(Color(0.5, 0.42, 0.33, 0.7), Color(0.45, 0.4, 0.34, 0.45), Color(0.45, 0.42, 0.38, 0)),
		12.0 * k, 60.0, Vector3.UP, 2.0, false, 3.0)
	_place(ctx, d, pos, 4.0 * k + 2.0)


# --- Persistent effects ---------------------------------------------------------

## Continuous smoke (and optional flames) for a burning or wrecked compartment.
## `intensity` 0..1 scales the plume. Returns the emitter (parented to `parent`).
static func burning(parent: Node3D, local_pos: Vector3, size: float) -> Node3D:
	var root := Node3D.new()
	root.position = local_pos
	var smoke := make(36, 7.0, size * 2.2, _ramp(Color(0.1, 0.09, 0.09, 0.85), Color(0.22, 0.21, 0.2, 0.55), Color(0.4, 0.4, 0.4, 0)),
		5.0, 12.0, Vector3.UP, -1.5, false, 3.5, false)
	smoke.name = "Smoke"
	var flame := make(14, 0.6, size * 1.4, _ramp(Color(1, 0.9, 0.6, 0.9), Color(1, 0.4, 0.08, 0.7), Color(0.3, 0.08, 0.02, 0)),
		3.0, 18.0, Vector3.UP, -3.0, true, 0.5, false)
	flame.name = "Flame"
	root.add_child(smoke)
	root.add_child(flame)
	parent.add_child(root)
	smoke.emitting = true
	flame.emitting = true
	return root
