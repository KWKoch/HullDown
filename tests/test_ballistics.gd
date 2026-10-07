extends Node3D
## Measures where shells land relative to a target: relative-motion leading, own-ship drift
## compensation and dispersion.
## godot --headless --path . --fixed-fps 60 res://tests/test_ballistics.tscn

const RANGE := 8000.0
var shooter: Ship
var target: Ship
var gun: Gunnery
var misses: Array[Vector3] = []     # landing point minus the target's position at landing (target frame, world axes)
var fails := 0


func _mk(class_id: String, team: int, pos: Vector3) -> Ship:
	var s := Ship.new()
	add_child(s)
	s.setup_from_class(Roster.get_entry(class_id), team)
	s.sea_state = 0.0                       # deck motion has its own test (test_hydro)
	s.global_position = pos
	s.add_to_group("ships")
	return s


func _ready() -> void:
	await _case("stationary target, stationary shooter, zero lead", 0.0, 0.0, false)
	await _case("stationary target, shooter at 25 kt (own drift compensated)", 25.0, 0.0, false)
	await _case("target 25 kt crossing, NO lead (player who forgets)", 0.0, 25.0, false)
	await _case("target 25 kt crossing, correct lead (AI solution)", 0.0, 25.0, true)
	
	
	
	print("BALLISTICS: %s" % ("OK" if fails == 0 else "%d FAILURES" % fails))
	get_tree().quit()


func _case(label: String, shooter_kt: float, target_kt: float, lead: bool) -> void:
	for n in get_children():
		n.queue_free()
	await get_tree().process_frame
	misses.clear()
	shooter = _mk("us_iowa", 0, Vector3.ZERO)
	shooter.heading = 0.0
	shooter.speed_ms = shooter_kt * 0.5144
	shooter.throttle = shooter.speed_ms / shooter.max_speed_ms
	target = _mk("us_fletcher", 1, Vector3(RANGE, 0, 0))     # due east: broadside to a north-heading shooter
	target.disarmed = true
	target.heading = 0.0                                      # steaming north => crossing the line of fire
	target.speed_ms = target_kt * 0.5144
	target.throttle = target.speed_ms / target.max_speed_ms
	gun = Gunnery.new()
	shooter.add_child(gun)
	gun.setup(shooter)
	# First let the turrets swing onto the target.
	for _i in 1800:
		gun.aim_at(target.global_position + Vector3(0, 4, 0))
		await get_tree().physics_frame
	for salvo in 12:
		var tvel := target.velocity_vec() if lead else Vector3.ZERO
		var tpos := target.global_position + Vector3(0, 4, 0)
		gun.aim_at(tpos)
		for t in gun.reload_left:
			gun.reload_left[t] = 0.0
		var before := get_tree().get_nodes_in_group("shells")
		gun.fire_at(tpos, tvel)
		for s in get_tree().get_nodes_in_group("shells"):
			if not before.has(s):
				(s as Shell).splash.connect(func(wp: Vector3, _c: float) -> void: _record(wp))
				(s as Shell).impact.connect(func(wp: Vector3, _sh: Ship, _c: float) -> void: _record(wp))
		for _i in 40:
			gun.aim_at(target.global_position + Vector3(0, 4, 0))
			await get_tree().physics_frame
	# Wait out the stragglers.
	for _i in 900:
		await get_tree().physics_frame
	var along := 0.0       # error along the line of fire (range)
	var across := 0.0      # error across it
	for m in misses:
		along += m.x
		across += m.z
	along /= misses.size()
	across /= misses.size()
	var sd_a := 0.0
	var sd_c := 0.0
	for m in misses:
		sd_a += (m.x - along) * (m.x - along)
		sd_c += (m.z - across) * (m.z - across)
	sd_a = sqrt(sd_a / misses.size())
	sd_c = sqrt(sd_c / misses.size())
	print("%-62s n=%d  mean miss: range %+6.0f m  deflection %+6.0f m | scatter 1-sigma: range %.0f m, deflection %.0f m" % [label, misses.size(), along, across, sd_a, sd_c])
	var bias := Vector2(along, across).length()
	if lead or target_kt == 0.0:
		if bias > 120.0:
			print("   FAIL: aimed shots should centre on the target (bias %.0f m)" % bias)
			fails += 1
	else:
		if bias < 120.0:
			print("   FAIL: with no lead a crossing target should be missed (bias %.0f m)" % bias)
			fails += 1


func _record(wp: Vector3) -> void:
	misses.append(wp - target.global_position)
