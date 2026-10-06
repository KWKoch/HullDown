extends Node3D
## Damage control: parties stop leaks and fires, pumps drain, skill matters, wrecks can't be fully
## repaired, and flooding degrades speed and handling.
## godot --headless --path . --fixed-fps 60 res://tests/test_damage_control.tscn

var fails := 0


func _check(ok: bool, label: String, detail: String = "") -> void:
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", label, detail])
	if not ok:
		fails += 1


func _ship(class_id: String, dc_on: bool, skill: float, seed_v: int) -> Ship:
	seed(seed_v)
	var s := Ship.new()
	add_child(s)
	s.setup_from_class(Roster.get_entry(class_id), 0)
	s.damage_control_enabled = dc_on
	s.crew_skill = skill
	return s


## A few moderate hits along the waterline, as an enemy cruiser would land.
func _batter(s: Ship, hits: int) -> void:
	for n in hits:
		var side := 1.0 if n % 2 == 0 else -1.0
		var pt := Vector3(side * s.beam_m * 0.5, -1.0, randf_range(-0.4, 0.4) * s.length_m)
		s.take_hit(s.to_global(pt), {"pen_mm": 150.0, "damage": 600.0, "fuse_m": 5.0, "radius": 8.0,
			"dir": Vector3(-side, -0.1, 0.0)})


func _run(s: Ship, seconds: float) -> void:
	for _i in int(seconds * 4.0):
		for _k in 15:
			if s.sunk or not is_instance_valid(s):
				return
			s._physics_process(1.0 / 60.0)   # 0.25 s per outer step
		await get_tree().process_frame


func _leaks(s: Ship) -> int:
	var n := 0
	for c in s.compartments:
		if c.flood_rate > 0.0 and c.flooded_tonnes < c.capacity_tonnes:
			n += 1
	return n


func _ready() -> void:
	# 1. Crew vs no crew on the same battering.
	var a := _ship("us_cleveland", false, 1.0, 11)
	var b := _ship("us_cleveland", true, 1.0, 11)
	_batter(a, 5)
	_batter(b, 5)
	var flood0 := b.total_flooded_t
	var leaks0 := _leaks(b)
	await _run(a, 240.0)
	await _run(b, 240.0)
	print("   no crew: flooded %.0f t, %d leaks, sunk %s | with crew: flooded %.0f t, %d leaks, sunk %s | started with %d leaks" % [
		a.total_flooded_t, _leaks(a), a.sunk, b.total_flooded_t, _leaks(b), b.sunk, leaks0])
	_check(leaks0 > 0, "battering opens leaks", "%d" % leaks0)
	_check(_leaks(b) < _leaks(a) or a.sunk, "repair parties stop leaks that run on without them")
	_check(b.total_flooded_t < a.total_flooded_t or a.sunk, "pumps and parties leave the crewed ship less flooded")
	# 2. Skill matters.
	var green := _ship("us_cleveland", true, 0.6, 5)
	var elite := _ship("us_cleveland", true, 1.4, 5)
	_batter(green, 8)
	_batter(elite, 8)
	await _run(green, 90.0)
	await _run(elite, 90.0)
	print("   after 90 s: green crew flooded %.0f t (%d leaks) | elite crew flooded %.0f t (%d leaks)" % [green.total_flooded_t, _leaks(green), elite.total_flooded_t, _leaks(elite)])
	_check(_leaks(elite) <= _leaks(green) and elite.total_flooded_t <= green.total_flooded_t, "better crew copes faster")
	# 3. Wrecks stay wrecked.
	var w := _ship("us_fletcher", true, 1.4, 3)
	var hull: Compartment = null
	for c in w.compartments:
		if c.kind == Compartment.Kind.HULL_SECTION:
			hull = c
			break
	hull.apply_damage(hull.max_hp * 2.0)
	hull.flood_rate = 5.0
	await _run(w, 300.0)
	_check(hull.destroyed and hull.hp <= 0.0, "a destroyed hull section is never repaired", "hp %.0f" % hull.hp)
	_check(hull.flood_rate > 0.0, "a blown-out section can be shored but not sealed", "inflow %.1f t/s" % hull.flood_rate)
	# 4. Handling.
	var h := _ship("us_cleveland", false, 1.0, 1)
	var h0 := h.handling_fraction()
	h.total_flooded_t = h.reserve_buoyancy_t * 0.6
	h.list_rad = 0.2
	_check(h.handling_fraction() < h0 * 0.75, "a flooded, listing ship handles worse", "%.2f -> %.2f" % [h0, h.handling_fraction()])
	print("DAMAGE CONTROL: %s" % ("OK" if fails == 0 else "%d FAILURES" % fails))
	get_tree().quit()
