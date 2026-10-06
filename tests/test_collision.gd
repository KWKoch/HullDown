extends Node3D
## Ship-on-ship collisions: ramming arrests the rammer, damages both, never lets hulls interpenetrate.
## godot --headless --path . --fixed-fps 60 res://tests/test_collision.tscn

var fails := 0


func _check(ok: bool, label: String, detail: String = "") -> void:
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", label, detail])
	if not ok:
		fails += 1


func _mk(class_id: String, pos: Vector3, heading: float, knots: float) -> Ship:
	var s := Ship.new()
	add_child(s)
	s.setup_from_class(Roster.get_entry(class_id), 0)
	s.damage_control_enabled = false
	s.global_position = pos
	s.heading = heading
	s.add_to_group("ships")
	s.speed_ms = knots * 0.5144
	s.throttle = 1.0                                   # keeps driving into it
	return s


func _lost(s: Ship) -> float:
	var hp := 0.0
	var mx := 0.0
	for c in s.compartments:
		hp += c.hp
		mx += c.max_hp
	return 1.0 - hp / mx


func _case(label: String, rammer_id: String, victim_id: String, knots: float, head_on: bool) -> Dictionary:
	for n in get_children():
		n.queue_free()
	await get_tree().process_frame
	Ship.collisions = 0
	var victim := _mk(victim_id, Vector3(0, 0, 0), 0.0 if not head_on else PI, 0.0)
	victim.throttle = 0.0
	if head_on:
		victim.heading = 0.0
	# Rammer starts 600 m to port of the victim, steering east at it (broadside hit) or ahead of it (head-on).
	var rammer: Ship
	if head_on:
		rammer = _mk(rammer_id, Vector3(0, 0, 900), PI, knots)
	else:
		rammer = _mk(rammer_id, Vector3(700, 0, 0), -PI * 0.5, knots)      # heading -90 deg = toward -X
	var min_sep := INF
	var speed_after := 99.0
	var t := 0.0
	var first_hit_t := -1.0
	for _i in 60 * 70:
		rammer._physics_process(1.0 / 60.0)
		victim._physics_process(1.0 / 60.0)
		t += 1.0 / 60.0
		min_sep = minf(min_sep, rammer.global_position.distance_to(victim.global_position))
		if Ship.collisions > 0 and first_hit_t < 0.0:
			first_hit_t = t
		if first_hit_t > 0.0 and t > first_hit_t + 3.0:
			speed_after = minf(speed_after, absf(rammer.speed_ms) / 0.5144)
		if _i % 6 == 0 and _i < 60 * 70 - 1:
			if _i % 60 == 0:
				await get_tree().process_frame
	var res := {"min_sep": min_sep, "speed_after": speed_after, "r_loss": _lost(rammer), "v_loss": _lost(victim),
		"hits": Ship.collisions, "end_sep": rammer.global_position.distance_to(victim.global_position), "rammer": rammer, "victim": victim}
	print("%s: rammer %s at %.0f kt -> %s | collisions %d | rammer speed 3 s after impact %.1f kt | closest centres %.0f m | damage: rammer %.1f%%, victim %.1f%%" % [
		label, rammer_id, knots, victim_id, res["hits"], speed_after, min_sep, res["r_loss"] * 100.0, res["v_loss"] * 100.0])
	return res


func _ready() -> void:
	var r1 := await _case("destroyer into cruiser's side", "us_fletcher", "us_cleveland", 25.0, false)
	var v: Ship = r1["victim"]
	var r: Ship = r1["rammer"]
	var half_beam_sum := (v.wbeam() + r.wlen()) * 0.5
	_check(r1["hits"] >= 1, "impact registered")
	_check(r1["min_sep"] > v.wbeam() * 0.4, "rammer does not drive through the victim", "closest centres %.0f m vs victim beam %.0f m" % [r1["min_sep"], v.wbeam()])
	_check(r1["speed_after"] < 6.0, "rammer's speed is arrested", "%.1f kt" % r1["speed_after"])
	_check(r1["r_loss"] > 0.005 and r1["v_loss"] > 0.001, "both ships are damaged")
	var r2 := await _case("cruiser into destroyer's side", "us_cleveland", "us_fletcher", 20.0, false)
	_check(r2["min_sep"] > (r2["victim"] as Ship).wbeam() * 0.4, "heavy rammer does not pass through a destroyer")
	_check(r2["v_loss"] > r2["r_loss"], "the lighter ship is hurt worse", "victim %.1f%% vs rammer %.1f%%" % [r2["v_loss"] * 100.0, r2["r_loss"] * 100.0])
	var r3 := await _case("head-on, destroyer vs destroyer", "us_fletcher", "us_fletcher", 20.0, true)
	_check(r3["hits"] >= 1 and r3["min_sep"] > 30.0, "head-on collision stops both", "closest %.0f m" % r3["min_sep"])
	print("COLLISION: %s" % ("OK" if fails == 0 else "%d FAILURES" % fails))
	get_tree().quit()
