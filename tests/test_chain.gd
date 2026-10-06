extends Node3D
## Headless checks for explosions, chain reactions and the AI's hazard awareness.
## godot --headless --path . --fixed-fps 60 res://tests/test_chain.tscn

var fails := 0


func _mk(class_id: String, team: int, pos: Vector3, ai := false, err := 0.0) -> Ship:
	var s := Ship.new()
	add_child(s)
	s.setup_from_class(Roster.get_entry(class_id), team)
	s.damage_control_enabled = false      # these tests measure unattended fires and blasts
	s.global_position = pos
	s.add_to_group("ships")
	var g := Gunnery.new()
	s.add_child(g)
	g.setup(s)
	if ai:
		var c := AICaptain.new()
		s.add_child(c)
		c.setup(s, g)
		c.error_rate = err
		c.position_noise_m = 0.0
	return s


func _mag(s: Ship) -> Compartment:
	for c in s.compartments:
		if c.kind == Compartment.Kind.MAGAZINE:
			return c
	return null


func _dead(s: Ship) -> int:
	var n := 0
	for c in s.compartments:
		if c.destroyed:
			n += 1
	return n


func _hp(s: Ship) -> float:
	var t := 0.0
	for c in s.compartments:
		t += c.hp
	return t


func _check(name: String, ok: bool, detail := "") -> void:
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", name, detail])
	if not ok:
		fails += 1


func _clear() -> void:
	for n in get_children():
		n.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame


func _ready() -> void:
	await get_tree().physics_frame

	# 1. A battleship magazine detonation damages a close neighbour but not a distant one.
	var big := _mk("us_iowa", 0, Vector3.ZERO)
	var m := _mag(big)
	# Place the neighbour 45 m abeam of the magazine itself (the magazine sits well forward of midships).
	var near := _mk("us_fletcher", 0, Vector3(45, 0, m.center.z))
	var far := _mk("us_fletcher", 0, Vector3(1500, 0, 0))
	var hp_near := _hp(near)
	var hp_far := _hp(far)
	m.apply_damage(m.hp)
	big._post_damage(m)
	await get_tree().physics_frame
	_check("1a. neighbour 45 m from the magazine is damaged by the blast", _hp(near) < hp_near - 50.0, "hp %.0f -> %.0f, destroyed parts %d" % [hp_near, _hp(near), _dead(near)])
	_check("1b. ship 1500 m away is untouched", is_equal_approx(_hp(far), hp_far))
	await _clear()

	# 2. Chain reaction is probabilistic: a magazine that is burning AND already badly hurt
	# should sympathetically detonate far more often than an undamaged one at the same distance.
	var trials := 40
	var hot_hits := 0
	var cold_hits := 0
	for i in trials:
		for hot in [true, false]:
			var a := _mk("us_fletcher", 0, Vector3.ZERO)
			var b := _mk("us_fletcher", 0, Vector3(25, 0, 0))
			var mb := _mag(b)
			if hot:
				mb.on_fire = true
				mb.apply_damage(mb.max_hp * 0.6)
			var ma := _mag(a)
			ma.apply_damage(ma.hp)
			a._post_damage(ma)
			if mb.ammo_stored <= 0.0:
				if hot:
					hot_hits += 1
				else:
					cold_hits += 1
			# Remove immediately (queue_free is deferred, and leftovers would contaminate the next trial).
			for sh in [a, b]:
				sh.remove_from_group("ships")
				remove_child(sh)
				sh.free()
	_check("2a. burning + wounded magazine 25 m away often cooks off (chain reaction)", hot_hits >= trials * 0.25, "%d / %d trials" % [hot_hits, trials])
	_check("2b. an undamaged magazine at the same distance rarely does", cold_hits <= hot_hits * 0.5, "%d / %d trials" % [cold_hits, trials])
	await _clear()

	# 3. Cook-off timing: a burning magazine eventually goes up; armour delays it; flooding saves it.
	var dd := _mk("us_fletcher", 0, Vector3(0, 0, 0))
	var bb := _mk("us_iowa", 0, Vector3(3000, 0, 0))
	var wet := _mk("us_fletcher", 0, Vector3(6000, 0, 0))
	for s in [dd, bb, wet]:
		_mag(s).on_fire = true
	_mag(wet).flooded_tonnes = _mag(wet).capacity_tonnes * 0.5
	var t_dd := -1.0
	var t_bb := -1.0
	var t := 0.0
	var mdd := _mag(dd)
	var mbb := _mag(bb)
	var mwet := _mag(wet)
	var ammo_dd := mdd.ammo_stored
	var ammo_bb := mbb.ammo_stored
	while t < 90.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		if t_dd < 0.0 and mdd.ammo_stored < ammo_dd:
			t_dd = t
		if t_bb < 0.0 and mbb.ammo_stored < ammo_bb:
			t_bb = t
	_check("3a. unarmoured destroyer magazine cooks off while burning", t_dd > 0.0, "after %.0f s" % t_dd)
	_check("3b. armoured battleship magazine holds out longer", t_bb < 0.0 or t_bb > t_dd, "destroyer %.0f s, battleship %s" % [t_dd, ("%.0f s" % t_bb) if t_bb > 0.0 else "survived 90 s"])
	_check("3c. flooded magazine extinguishes and does not explode", not mwet.on_fire and mwet.ammo_stored > 0.0)
	await _clear()

	# 4. AI hazard awareness: a captain steaming straight at a burning ship turns away and keeps
	# clear of the blast radius. (The bomb's magazine is armoured so it burns for the whole test.)
	var bomb := _mk("us_iowa", 0, Vector3.ZERO)
	var bm := _mag(bomb)
	bm.armor_mm = 5000.0
	bm.on_fire = true
	var watcher := _mk("us_baltimore", 0, Vector3(500, 0, bm.center.z), true, 0.0)
	watcher.heading = -PI / 2.0           # pointing straight at the bomb
	watcher.speed_ms = 13.0
	await get_tree().physics_frame
	var closest := 99999.0
	var hz_max := 0.0
	var t4 := 0.0
	var mpos := bomb.to_global(bm.center)
	while t4 < 40.0 and bm.ammo_stored > 0.0:
		await get_tree().physics_frame
		t4 += 1.0 / 60.0
		closest = minf(closest, watcher.global_position.distance_to(mpos))
		hz_max = maxf(hz_max, bomb.hazard_r)
	var radius := bomb.blast_radius_for(1800.0)
	_check("4a. a burning magazine is flagged as a hazard", hz_max > 0.0, "hazard radius %.0f m" % hz_max)
	_check("4b. captain turns away and stays outside the blast radius (%.0f m)" % radius, closest > radius + 40.0, "closest approach %.0f m over %.0f s" % [closest, t4])
	await _clear()

	print("\nRESULT: %s" % ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))
	get_tree().quit(1 if fails > 0 else 0)
