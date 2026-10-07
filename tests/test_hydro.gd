extends Node3D
## Hull dynamics: acceleration, coasting, crash-stop, turning circle, steerage way, shoals, roll.
## godot --headless --path . --fixed-fps 60 res://tests/test_hydro.tscn --quit-after 3000

var fails := 0
const DT := 1.0 / 60.0
const SHIPS := ["us_fletcher", "us_baltimore", "us_south_dakota", "jp_fubuki", "de_s_boat"]


func _check(ok: bool, label: String, detail: String = "") -> void:
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", label, detail])
	if not ok:
		fails += 1


func _mk(id: String) -> Ship:
	var s := Ship.new()
	add_child(s)
	s.setup_from_class(Roster.get_entry(id), 0)
	s.damage_control_enabled = false
	s.sea_state = 0.0
	s.global_position = Vector3.ZERO
	return s


func _step(s: Ship, secs: float, fn: Callable = Callable()) -> void:
	for i in int(secs / DT):
		s._move(DT)
		if fn.is_valid():
			fn.call(i * DT)


func _ready() -> void:
	for id in SHIPS:
		var e := Roster.get_entry(id)
		if e.is_empty():
			continue
		print("--- %s  (%s, %.0f t, %.0f kn, L %.0f m)" % [id, e["type"], e["displacement_t"], e["speed_kts"], e["length_m"]])
		await _one(id, e)
	print("DONE fails=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func _one(id: String, e: Dictionary) -> void:
	var vmax := float(e["speed_kts"]) * 0.5144
	var m := {}
	# 1. Standing start, full ahead
	var s := _mk(id)
	s.throttle = 1.0
	m = {"t50": -1.0, "t90": -1.0, "t99": -1.0}
	_step(s, 240.0, func(t: float):
		var x := s.speed_ms / vmax
		if m["t50"] < 0.0 and x >= 0.5: m["t50"] = t
		if m["t90"] < 0.0 and x >= 0.9: m["t90"] = t
		if m["t99"] < 0.0 and x >= 0.99: m["t99"] = t)
	print("  accel: 50%% %.0fs  90%% %.0fs  99%% %.0fs   top %.1f kn (rated %.1f)" % [m["t50"], m["t90"], m["t99"], s.speed_ms / 0.5144, vmax / 0.5144])
	_check(absf(s.speed_ms - vmax) / vmax < 0.03, id + " reaches rated speed", "")
	_check(m["t90"] > 1.0 and m["t90"] < 120.0, id + " 90%% speed in a believable time", "%.0fs" % m["t90"])
	# 2. Coast with engines stopped
	s.throttle = 0.0
	m = {"half": -1.0}
	var p0 := s.global_position
	_step(s, 400.0, func(t: float):
		if m["half"] < 0.0 and s.speed_ms <= vmax * 0.5: m["half"] = t)
	print("  coast: halves in %.0fs   after 400s speed %.1f kn  ran %.0f m" % [m["half"], s.speed_ms / 0.5144, s.global_position.distance_to(p0)])
	# 3. Crash stop from full
	s.speed_ms = vmax
	s.throttle = -0.3
	s.global_position = Vector3.ZERO
	var est: float = s.hydro.stop_distance()
	m = {"stop": -1.0, "dist": 0.0}
	_step(s, 200.0, func(t: float):
		if m["stop"] < 0.0 and s.speed_ms <= 0.3:
			m["stop"] = t
			m["dist"] = s.global_position.length())
	print("  crash-stop: %.0fs, %.0f m  (estimate said %.0f m)" % [m["stop"], m["dist"], est])
	_check(m["stop"] > 1.0 and m["stop"] < 150.0, id + " crash-stop time", "%.0fs" % m["stop"])
	# 4. Hard turn at full speed
	s = _mk(id)
	s.speed_ms = vmax
	s.throttle = 1.0
	s.rudder = 1.0
	m = {"roll": 0.0, "r": 0.0}
	_step(s, 150.0, func(t: float):
		m["roll"] = maxf(m["roll"], absf(s.hydro.roll))
		if t > 110.0: m["r"] = s.hydro.r)
	var speed_loss := 1.0 - s.speed_ms / vmax
	var drift := rad_to_deg(atan2(absf(s.sway_ms), maxf(s.speed_ms, 0.1)))
	var rad: float = s.speed_ms / maxf(absf(m["r"]), 0.0001)
	print("  hard turn: rate %.1f deg/s (rated %.1f)  radius %.0f m = %.1f lengths  speed loss %.0f%%  drift %.0f deg  max heel %.1f deg" % [
		rad_to_deg(m["r"]), rad_to_deg(float(e.get("turn_rate", 0.05))), rad, rad / s.wlen(), speed_loss * 100.0, drift, rad_to_deg(m["roll"])])
	_check(speed_loss > 0.05 and speed_loss < 0.55, id + " speed bleeds in a hard turn", "%.0f%%" % (speed_loss * 100.0))
	# 5. Steerage way
	s = _mk(id)
	s.rudder = 1.0
	s.throttle = 0.0
	s.speed_ms = 0.0
	_step(s, 25.0)
	var dead := rad_to_deg(absf(s.heading))
	s = _mk(id)
	s.rudder = 1.0
	s.throttle = 0.4
	_step(s, 25.0)
	var wash := rad_to_deg(absf(s.heading))
	s = _mk(id)
	s.rudder = 1.0
	s.throttle = -0.3
	_step(s, 25.0)
	var back := rad_to_deg(absf(s.heading))
	print("  steerage (25 s, hard over): engines stopped %.1f deg | 2/5 ahead from rest %.0f deg | astern %.0f deg" % [dead, wash, back])
	_check(dead < 1.0, id + " no steerage way when stopped", "%.1f deg" % dead)
	_check(wash > dead + 0.5, id + " propeller race gives steerage from rest", "%.0f deg" % wash)
	# 6. Shoals: same throttle, deep vs shallow
	var sd := _mk(id)
	sd.throttle = 1.0
	sd.speed_ms = vmax
	_step(sd, 90.0)
	var deep_v := sd.speed_ms
	var ss := _mk(id)
	ss.throttle = 1.0
	ss.speed_ms = vmax
	var depth_w := ss.wdraft() * 2.0
	_step(ss, 90.0, func(_t: float): ss.hydro.depth_world = depth_w)
	print("  shoal (depth = 2 x draft): speed %.1f -> %.1f kn  squat %.1f m (world)" % [deep_v / 0.5144, ss.speed_ms / 0.5144, ss.hydro.squat_world])
	_check(ss.speed_ms < deep_v * 0.97, id + " slows in shoal water", "")
	# 7. Sea state: roll cruising beam-on vs head-on
	var rolls := []
	for hdg in [PI * 0.5 + 0.6, 0.6]:
		var sr := _mk(id)
		sr.sea_state = 3.0
		sr.heading = hdg
		sr.speed_ms = vmax * 0.6
		sr.throttle = 0.6
		m = {"r": 0.0}
		_step(sr, 120.0, func(t: float):
			if t > 40.0: m["r"] = maxf(m["r"], absf(sr.hydro.roll)))
		rolls.append(rad_to_deg(m["r"]))
	print("  sea state 3: peak roll beam-on %.1f deg, head-on %.1f deg" % [rolls[0], rolls[1]])
	# 8. Own broadside kick
	var sk := _mk(id)
	var gun: Dictionary = e.get("main_gun", {})
	var imp := float(gun.get("barrels_per_turret", 1)) * (e["turret_z"] as Array).size() * float(gun.get("shell_kg", 0)) * float(gun.get("muzzle_ms", 0))
	sk.hydro.recoil(1.0, imp)
	m = {"k": 0.0}
	_step(sk, 12.0, func(_t: float): m["k"] = maxf(m["k"], absf(sk.hydro.roll)))
	print("  full broadside kick: peak roll %.1f deg   gun stabilisation %.2f" % [rad_to_deg(m["k"]), sk.hydro.gun_stab])
	for n in get_children():
		n.queue_free()
	await get_tree().process_frame
