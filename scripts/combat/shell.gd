class_name Shell
extends Node3D
## A ballistic artillery shell. Integrates gravity + quadratic drag, tests against ships
## (oriented hull box), terrain (heightmap) and the water surface.

const GRAVITY := 9.81
const DRAG_K := 0.00004          ## per metre; tuned for ~0.35-0.4 muzzle-speed loss at max range

var velocity: Vector3
var spec: Dictionary             ## caliber_mm, shell_kg, muzzle_ms, he_kg, fuse_m
var owner_ship: Ship
var terrain: BattleTerrain
var age := 0.0
var _entered_water := false
var _passed: Array[Ship] = []     ## ships this shell already went clean through
var trail: ShellTrail

## Test counters
static var total_hits := 0
static var friendly_hits := 0

signal splash(world_pos: Vector3, caliber_mm: float)
signal impact(world_pos: Vector3, ship: Ship, caliber_mm: float)
signal terrain_hit(world_pos: Vector3, caliber_mm: float)


func launch(p_owner: Ship, p_terrain: BattleTerrain, from: Vector3, dir: Vector3, p_spec: Dictionary, inherit: Vector3 = Vector3.ZERO) -> void:
	owner_ship = p_owner
	terrain = p_terrain
	spec = p_spec
	global_position = from
	# The shell keeps the firing ship's own motion: a moving ship throws its shells sideways.
	velocity = dir.normalized() * float(p_spec["muzzle_ms"]) + inherit
	add_to_group("shells")
	if p_owner != null and p_owner.is_player:
		trail = ShellTrail.new()
		get_tree().current_scene.add_child(trail)
		trail.add_point(from, true)


func _exit_tree() -> void:
	if trail != null and is_instance_valid(trail):
		trail.finish(global_position)


func _physics_process(delta: float) -> void:
	age += delta
	if age > 90.0:
		queue_free()
		return
	var prev := global_position
	var speed := velocity.length()
	velocity += Vector3(0, -GRAVITY, 0) * delta
	velocity -= velocity * speed * DRAG_K * delta
	var next := prev + velocity * delta
	# Sub-step so fast shells don't tunnel through thin parts.
	var steps := maxi(1, int(ceil(prev.distance_to(next) / 8.0)))
	for s in range(1, steps + 1):
		var p := prev.lerp(next, float(s) / steps)
		if _check_hit(p):
			queue_free()
			return
	global_position = next
	if trail != null:
		trail.add_point(next)


func _check_hit(p: Vector3) -> bool:
	# Ships.
	for node in get_tree().get_nodes_in_group("ships"):
		var s := node as Ship
		if s == null or s.sunk or s == owner_ship or _passed.has(s):
			continue
		if s.global_position.distance_to(p) > s.wlen() * 0.7:
			continue
		var local := s.to_local(p)
		if absf(local.x) <= s.beam_m * 0.5 and absf(local.z) <= s.length_m * 0.5 \
				and local.y <= s.top_y and local.y >= -s.draft_m:
			var cal: float = spec["caliber_mm"]
			var v_frac := clampf(velocity.length() / float(spec["muzzle_ms"]), 0.2, 1.0)
			var kg: float = spec["shell_kg"]
			var hit := {
				"pen_mm": cal * v_frac * 1.05,
				"damage": kg * 3.0,
				"fuse_m": spec.get("fuse_m", 6.0),
				"radius": clampf(pow(kg, 0.33) * 1.2, 2.0, 18.0),
				"dir": velocity.normalized(),
			}
			Shell.total_hits += 1
			if owner_ship != null and s.team == owner_ship.team:
				Shell.friendly_hits += 1
				if Shell.friendly_hits <= 12 and OS.get_cmdline_user_args().has("--report"):
					print("FRIENDLY HIT: %s -> %s | shell y=%.0f age=%.1fs dist_from_shooter=%.0f m | shooter-victim sep=%.0f" % [
						owner_ship.class_id, s.class_id, p.y, age, owner_ship.global_position.distance_to(p), owner_ship.global_position.distance_to(s.global_position)])
			if s.take_hit(p, hit):
				Fx.impact(self, p, cal)
				impact.emit(p, s, cal)
				return true
			# Over-penetration: the shell went through the thin hull before its fuze ran and
			# carries on, to burst in the water beyond.
			_passed.append(s)
			velocity *= 0.8
			Fx.impact(self, p, cal * 0.4)
			continue
	# Terrain / seabed.
	if terrain != null:
		var h := terrain.height_at(p.x, p.z)
		if p.y <= h:
			terrain.apply_blast(p, float(spec.get("he_kg", spec["shell_kg"] * 0.1)), float(spec["caliber_mm"]), p.y)
			Fx.dust(self, p, float(spec["caliber_mm"]))
			terrain_hit.emit(p, spec["caliber_mm"])
			return true
	# Water surface. Deep water swallows the shell; in shallows it keeps going (slowed)
	# and can reach the seabed, which is how shoals get gouged.
	if p.y <= 0.0:
		if not _entered_water:
			_entered_water = true
			Fx.splash(self, p, float(spec["caliber_mm"]))
			splash.emit(p, spec["caliber_mm"])
			velocity *= 0.35
		var depth := 0.0
		if terrain != null:
			depth = -terrain.height_at(p.x, p.z)
		if depth > 25.0:
			return true
	return false
