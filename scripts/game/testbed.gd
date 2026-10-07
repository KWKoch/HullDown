extends Node3D
## Surface-ship testbed: the player vs 30 AI opponents on one of the seven battlegrounds.
## Controls (keyboard and the identical on-screen buttons): W/S ring the engine telegraph,
## A/D step the helm (X centres), Space / LMB / FIRE button fire at the aim point, C cycles the camera.
## PC: hold RMB + move to orbit, wheel zooms, the cursor aims.  Touch: one-finger drag orbits,
## pinch zooms, tap designates the aim point.  [ / ] cycle your ship. F1-F7 pick a battleground.

const TEAM_SIZE := 15            ## ships per side: the player plus 14 AI allies against 15 AI opponents
const OPPONENTS := TEAM_SIZE

@export var ground_id := "surigao_strait"
var player_index := 0

var terrain: BattleTerrain
var player: Ship
var gunnery: Dictionary = {}       ## Ship -> Gunnery
var cam: Camera3D
enum CamMode { CHASE, BROADSIDE, OVERHEAD, BRIDGE }
const CAM_NAMES := ["CHASE", "BROADSIDE", "OVERHEAD", "BRIDGE"]
var cam_mode := CamMode.CHASE
var cam_yaw := PI + 0.55    ## relative to the ship's heading: PI = dead astern; offset gives a 3/4 quarter view
var cam_pitch := 0.24
var cam_dist := 170.0       ## set from the player's length at spawn (unless --dist is given)
var cam_heading := 0.0      ## smoothed heading the camera follows
var bridge_yaw := 0.0
var bridge_pitch := 0.0
var _dist_forced := false
var _yaw_forced := false
var look_up := 0.0           ## test option: raise the look-at point to inspect the sky
var hud: Hud
var controls: PlayerControls
var track: TrackProjection
var marker: AimMarker
var sensors: SensorNet
var tod_final := 12.0
var peace := true           ## UI-testing mode: AI ships neither move nor fire. Use --hot for a live battle.
var fire_held := false
var touch_aim_world := Vector3.ZERO
var touch_aiming := false
var _touches: Dictionary = {}
var _pinch_last := 0.0
var _tap_start := {}
var sun: DirectionalLight3D
var env: WorldEnvironment
var water: MeshInstance3D
var aim_point := Vector3.ZERO


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and not args[0].begins_with("--"):
		ground_id = args[0]
	_report_on = args.has("--report")
	peace = not (args.has("--hot") or args.has("--report") or args.has("--auto"))
	if GameSession.launched:
		ground_id = GameSession.ground_id
		peace = false                    # a battle launched from the menu is always live
	Gunnery.ceasefire = peace
	_build_world()
	_spawn_fleet()
	_build_hud()
	if _report_on:
		for k in range(0, terrain.heights.size(), 97):
			_h0 += terrain.heights[k]


# --- World ----------------------------------------------------------------

func _build_world() -> void:
	var ground := Battlegrounds.get_ground(ground_id)
	assert(not ground.is_empty(), "Unknown battleground: " + ground_id)
	terrain = BattleTerrain.new()
	add_child(terrain)
	terrain.build(ground)

	var tod: float = ground["time_of_day"]
	var weather: String = ground.get("weather", "clear")
	# Test overrides: --time 14  --weather overcast
	var cl := OS.get_cmdline_user_args()
	if peace:
		tod = 12.0           # UI testing is done in daylight; --time overrides
	var ti := cl.find("--time")
	if ti >= 0 and ti + 1 < cl.size():
		tod = float(cl[ti + 1])
	var wi := cl.find("--weather")
	if wi >= 0 and wi + 1 < cl.size():
		weather = cl[wi + 1]
	for k in ["--yaw", "--pitch", "--dist", "--lookup"]:
		var ki := cl.find(k)
		if ki >= 0 and ki + 1 < cl.size():
			match k:
				"--yaw": cam_yaw = deg_to_rad(float(cl[ki + 1])); _yaw_forced = true
				"--pitch": cam_pitch = deg_to_rad(float(cl[ki + 1]))
				"--dist": cam_dist = float(cl[ki + 1]); _dist_forced = true
				"--lookup": look_up = float(cl[ki + 1])
	tod_final = tod
	var preset := SkySea.preset_for(tod, weather, float(ground["visibility_m"]))
	var built := SkySea.build(self, preset, Vector2(240000, 240000))
	sun = built["sun"]
	env = WorldEnvironment.new()   # (the environment node lives inside SkySea's build; kept for API compatibility)
	water = built["sea"]
	var wx := Weather.new()
	add_child(wx)
	wx.setup(weather if weather in ["rain", "snow"] else "")
	print("Sky preset: %s (time %.1f, weather %s)" % [preset, tod, weather])

	cam = Camera3D.new()
	cam.far = 30000.0
	cam.current = true
	add_child(cam)


func _spawn_fleet() -> void:
	var ground := Battlegrounds.get_ground(ground_id)
	var pool_a: Array = ground["team_a_pool"]
	var pool_b: Array = ground["team_b_pool"]
	var spawn_a: Vector3 = ground["spawn_a"]
	var spawn_b: Vector3 = ground["spawn_b"]
	var player_id: String = pool_a[player_index % pool_a.size()]
	if GameSession.launched and GameSession.ship_id != "":
		player_id = GameSession.ship_id
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ship="):
			player_id = a.substr(7)
	# A ship from the ground's second faction fights on that side: swap the sides.
	var pnat: String = Roster.get_entry(player_id).get("nation", "")
	if pnat in ground["factions"]["team_b"] and not pnat in ground["factions"]["team_a"]:
		var tp := pool_a
		pool_a = pool_b
		pool_b = tp
		var ts := spawn_a
		spawn_a = spawn_b
		spawn_b = ts
		ground = ground.duplicate()
		ground["spawn_a"] = spawn_a
		ground["spawn_b"] = spawn_b
	var own_head := 0.0 if spawn_a.z <= spawn_b.z else PI
	player = _spawn(player_id, 0, _find_water(spawn_a), true)

	for i in OPPONENTS:
		var cls: String = pool_b[i % pool_b.size()]
		var anchor: Vector3 = spawn_b
		var offset := Vector3((i % 6 - 2.5) * 650.0, 0, (i / 6 - 2) * 650.0)
		var s := _spawn(cls, 1, _find_water(anchor + offset), false)
		s.heading = own_head + PI
	player.heading = own_head
	if peace:
		# Two practice targets close ahead: real ships with their magazines emptied and guns disarmed.
		for k in 2:
			var cls_t: String = pool_b[(k * 2) % pool_b.size()]
			var side := -1.0 if k == 0 else 1.0
			var tpos := _find_water(player.global_position + Vector3(side * 650.0, 0, 1900.0 + k * 900.0), 300.0)
			var tgt := _spawn(cls_t, 1, tpos, false)
			tgt.heading = PI * 0.5 * side
			tgt.disarmed = true
			for c in tgt.compartments:
				c.ammo_stored = 0.0
	cam_heading = own_head
	if not _dist_forced:
		cam_dist = maxf(70.0, player.wlen() * 1.15)
	track = TrackProjection.new()
	add_child(track)
	marker = AimMarker.new()
	add_child(marker)
	sensors = SensorNet.new()
	add_child(sensors)
	sensors.setup(terrain, player.team, float(ground["visibility_m"]), tod_final < 5.5 or tod_final > 19.5)
	if peace:
		# Two friendly ships steaming slowly on station, spread out so their radar coverage adds up.
		for k in 2:
			var cls_f: String = pool_a[(k + 1) % pool_a.size()]
			var fside := 1.0 if k == 0 else -1.0
			var fpos := _find_water(player.global_position + Vector3(fside * 3200.0, 0, 1200.0 - k * 1800.0), 300.0)
			var fs := _spawn(cls_f, 0, fpos, false)
			fs.heading = 0.0
			fs.throttle = 0.3
	controls = PlayerControls.new()
	add_child(controls)
	controls.setup(player)
	var oi := OS.get_cmdline_user_args().find("--order")      # test: ring an engine order (index into ENGINE_ORDERS)
	if oi >= 0:
		controls.ring_engine(int(OS.get_cmdline_user_args()[oi + 1]))
	var hi := OS.get_cmdline_user_args().find("--helm")
	if hi >= 0:
		controls.set_helm(int(OS.get_cmdline_user_args()[hi + 1]))
	# Test option: --allies N adds N AI-controlled ships on the player's side.
	var cl := OS.get_cmdline_user_args()
	var ai_i := cl.find("--allies")
	var n_allies := TEAM_SIZE - 1
	if peace:
		n_allies = 0
	if ai_i >= 0 and ai_i + 1 < cl.size():
		n_allies = int(cl[ai_i + 1])
	if n_allies > 0:
		for i in n_allies:
			var cls_a: String = pool_a[(i + 1) % pool_a.size()]
			var off_a := Vector3((i % 6 - 2.5) * 650.0, 0, 650.0 + (i / 6) * 650.0)
			var sa := _spawn(cls_a, 0, _find_water((ground["spawn_a"] as Vector3) + off_a * (1.0 if own_head == 0.0 else -1.0)), false)
			sa.heading = own_head
	var cnt := [0, 0]
	for n in get_tree().get_nodes_in_group("ships"):
		cnt[clampi((n as Ship).team, 0, 1)] += 1
	print("Fleets: team 0 = %d ships, team 1 = %d ships" % [cnt[0], cnt[1]])
	if OS.get_cmdline_user_args().has("--auto"):
		controls.set_physics_process(false)     # the AI captain drives the player ship in tests
		var ai := AICaptain.new()
		player.add_child(ai)
		ai.setup(player, gunnery[player])


func _spawn(class_id: String, team: int, pos: Vector3, is_player: bool) -> Ship:
	var entry := Roster.get_entry(class_id)
	assert(not entry.is_empty(), "Unknown ship class: " + class_id)
	var s := Ship.new()
	s.name = "%s_%d" % [class_id, get_child_count()]
	add_child(s)
	s.setup_from_class(entry, team)
	s.terrain = terrain
	s.is_player = is_player
	s.crew_skill = 1.0 if is_player else randf_range(0.7, 1.3)    # AI crews vary in efficacy
	if s.dc != null:
		s.dc.skill = 1.0
	s.global_position = pos
	s.add_to_group("ships")
	var vis := ShipVisual.new()
	s.add_child(vis)
	vis.setup(s)
	var wk := Wake.new()
	s.add_child(wk)
	wk.setup(s)
	var g := Gunnery.new()
	s.add_child(g)
	g.setup(s)
	gunnery[s] = g
	if not is_player and not peace:
		var ai := AICaptain.new()
		s.add_child(ai)
		ai.setup(s, g)
	return s


## Nearest open water to `want` that is deep enough for any ship AND at least `min_sep`
## metres from every ship already placed (so fleets never spawn stacked on one spot).
var _placed: Array[Vector3] = []


func _find_water(want: Vector3, min_sep: float = 450.0) -> Vector3:
	var half := (terrain.size * 0.5) - Vector2(300, 300)
	var p := Vector2(clampf(want.x, -half.x, half.x), clampf(want.z, -half.y, half.y))
	for ring in 90:
		var steps := maxi(8, ring * 6)
		for k in steps:
			var a := TAU * k / float(steps)
			var q := p + Vector2(cos(a), sin(a)) * ring * 150.0
			if absf(q.x) > half.x or absf(q.y) > half.y:
				continue
			if terrain.height_at(q.x, q.y) > -26.0:
				continue
			var ok := true
			for other in _placed:
				if Vector2(other.x - q.x, other.z - q.y).length() < min_sep:
					ok = false
					break
			if ok:
				var pos := Vector3(q.x, 0, q.y)
				_placed.append(pos)
				return pos
	push_warning("No clear water found near %s" % str(want))
	return Vector3(p.x, 0, p.y)


# --- Input & camera --------------------------------------------------------

func _is_emulated(event: InputEvent) -> bool:
	return event.device == InputEvent.DEVICE_ID_EMULATION


func _orbit(rel: Vector2) -> void:
	if cam_mode == CamMode.BRIDGE:
		bridge_yaw -= rel.x * 0.004
		bridge_pitch = clampf(bridge_pitch - rel.y * 0.004, -0.5, 0.7)
	else:
		cam_yaw -= rel.x * 0.004
		cam_pitch = clampf(cam_pitch + rel.y * 0.004, 0.05, 1.45)


func _zoom(factor: float) -> void:
	cam_dist = clampf(cam_dist * factor, 25.0, 2500.0)


func _cycle_camera() -> void:
	cam_mode = ((cam_mode + 1) % CAM_NAMES.size()) as CamMode
	var len_m := player.wlen()
	match cam_mode:
		CamMode.CHASE:
			cam_yaw = PI + 0.55
			cam_pitch = 0.24
			cam_dist = maxf(70.0, len_m * 1.15)
		CamMode.BROADSIDE:
			cam_yaw = PI * 0.5
			cam_pitch = 0.12
			cam_dist = maxf(80.0, len_m * 1.5)
		CamMode.OVERHEAD:
			cam_yaw = PI
			cam_pitch = 1.3
			cam_dist = maxf(120.0, len_m * 1.7)
		CamMode.BRIDGE:
			bridge_yaw = 0.0
			bridge_pitch = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if player == null:
		return
	# Touch (real fingers only; emulated mouse events from touch are ignored here).
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			if hud != null and hud.is_over_ui(st.position):
				return
			_touches[st.index] = st.position
			_tap_start[st.index] = {"pos": st.position, "t": Time.get_ticks_msec()}
			if _touches.size() == 2:
				var ps: Array = _touches.values()
				_pinch_last = (ps[0] as Vector2).distance_to(ps[1])
		else:
			if _tap_start.has(st.index):
				var ts: Dictionary = _tap_start[st.index]
				var moved := (ts["pos"] as Vector2).distance_to(st.position)
				if moved < 14.0 and Time.get_ticks_msec() - int(ts["t"]) < 350 and _touches.size() == 1:
					_designate_aim(st.position)
			_touches.erase(st.index)
			_tap_start.erase(st.index)
		return
	if event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if not _touches.has(sd.index):
			return
		_touches[sd.index] = sd.position
		if _touches.size() == 1:
			_orbit(sd.relative)
		elif _touches.size() == 2:
			var ps2: Array = _touches.values()
			var d: float = (ps2[0] as Vector2).distance_to(ps2[1])
			if _pinch_last > 1.0 and d > 1.0:
				_zoom(_pinch_last / d)
			_pinch_last = d
		return
	if _is_emulated(event):
		return
	# Mouse.
	if event is InputEventMouseMotion:
		touch_aiming = false
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			_orbit((event as InputEventMouseMotion).relative)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			fire_held = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(0.9)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(1.1)
	elif event is InputEventKey:
		var ke := event as InputEventKey
		var k := ke.keycode
		if not ke.pressed:
			if k == KEY_SPACE:
				fire_held = false
			return
		if ke.echo:
			return
		if k == KEY_SPACE:
			fire_held = true
		elif ke.is_action_pressed("throttle_up"):
			controls.step_engine(1)
		elif ke.is_action_pressed("throttle_down"):
			controls.step_engine(-1)
		elif ke.is_action_pressed("rudder_left"):
			controls.step_helm(1)
		elif ke.is_action_pressed("rudder_right"):
			controls.step_helm(-1)
		elif k == KEY_X:
			controls.center_helm()
		elif k == KEY_V:
			if player.dc != null:
				player.dc.cycle_priority()
		elif k == KEY_C:
			_cycle_camera()
		elif k == KEY_M:
			hud.toggle_map()
		elif k == KEY_ESCAPE and GameSession.launched:
			GameSession.back_to_menu(get_tree())
		elif k >= KEY_F1 and k <= KEY_F7:
			ground_id = Battlegrounds.all_grounds()[k - KEY_F1]["id"]
			get_tree().reload_current_scene()
		elif k == KEY_BRACKETRIGHT or k == KEY_BRACKETLEFT:
			player_index += 1 if k == KEY_BRACKETRIGHT else -1
			get_tree().reload_current_scene()


var _report_t := 0.0
var _report_on := false
var _h0 := 0.0
var _shells_seen := 0


var _sim_t := 0.0


func _report(delta: float) -> void:
	_sim_t += delta
	_report_t += delta
	if _report_t < 10.0:
		return
	_report_t = 0.0
	var alive := 0
	var sunk := 0
	var moving := 0
	var fires := 0
	var floods := 0
	var dead_parts := 0
	for n in get_tree().get_nodes_in_group("ships"):
		var sh := n as Ship
		if sh == null:
			continue
		if sh.sunk:
			sunk += 1
		else:
			alive += 1
		if absf(sh.speed_ms) > 1.0:
			moving += 1
		for c in sh.compartments:
			if c.on_fire: fires += 1
			if c.flood_rate > 0.0: floods += 1
			if c.destroyed: dead_parts += 1
	var hsum := 0.0
	for k in range(0, terrain.heights.size(), 97):
		hsum += terrain.heights[k]
	print("[sim %ds] ships alive %d sunk %d moving %d | shells in flight %d | fires %d flooding %d destroyed parts %d | player: %s spd %.1fkt flood %.0ft dmgparts %d | terrain delta %.2f" % [
		int(_sim_t), alive, sunk, moving, get_tree().get_nodes_in_group("shells").size(), fires, floods, dead_parts,
		"SUNK" if player.sunk else "afloat", absf(player.speed_ms) / 0.5144, player.total_flooded_t, _count_dead(player), hsum - _h0])
	_type_report()
	print("        hits %d (friendly %d) | AI held fire %d, unsafe shots (botched checks) %d | explosions %d, chain %d" % [
		Shell.total_hits, Shell.friendly_hits, AICaptain.held_fire, AICaptain.unsafe_shots, Ship.explosions, Ship.chain_explosions])


func _type_report() -> void:
	var by_type := {}
	for n in get_tree().get_nodes_in_group("captains"):
		var c := n as AICaptain
		if c == null or c.ship.sunk:
			continue
		var t: String = c.ship.ship_type
		var e: Dictionary = by_type.get(t, {"n": 0, "d": 0.0, "dn": 0, "states": {}})
		e["n"] += 1
		if c.target != null and not c.target.sunk:
			e["d"] += c.ship.global_position.distance_to(c.target.global_position)
			e["dn"] += 1
		var sn: String = AICaptain.State.keys()[c.state]
		(e["states"] as Dictionary)[sn] = (e["states"] as Dictionary).get(sn, 0) + 1
		by_type[t] = e
	for t in by_type:
		var e: Dictionary = by_type[t]
		var avg: float = (float(e["d"]) / float(e["dn"])) if int(e["dn"]) > 0 else 0.0
		print("          %-19s n=%2d  avg range to target %6.0f m  states %s" % [t, e["n"], avg, str(e["states"])])


func _count_dead(sh: Ship) -> int:
	var n := 0
	for c in sh.compartments:
		if c.destroyed:
			n += 1
	return n


func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	if _report_on:
		_report(delta)
	if OS.get_cmdline_user_args().has("--stat"):
		_sim_t += delta
		if fmod(_sim_t, 10.0) < delta:
			print("[stat %ds] shells %d  trails %d  hits on anyone %d  overpens %d  player damaged parts %d" % [int(_sim_t), get_tree().get_nodes_in_group("shells").size(), get_tree().get_nodes_in_group("trails").size(), Shell.total_hits, Ship.overpenetrations, _count_dead(player)])
	if OS.get_cmdline_user_args().has("--wound") and not _wounded:
		_wounded = true
		_wound()
	if not player.sunk:
		var fwd := ""
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--aimfwd="):
				fwd = a.substr(9)
		if fwd != "":
			var d := float(fwd)
			aim_point = player.global_position + Vector3(sin(player.heading + 0.12), 0, cos(player.heading + 0.12)) * d
		elif OS.get_cmdline_user_args().has("--autoaim"):
			_autoaim()
		elif touch_aiming:
			aim_point = touch_aim_world
		else:
			_update_aim_point(get_viewport().get_mouse_position())
		(gunnery[player] as Gunnery).aim_at(aim_point)      # the turrets always swing toward the aim point
		if fire_held:
			(gunnery[player] as Gunnery).fire_at(aim_point, Vector3.ZERO)
	else:
		fire_held = false
	track.update_for(player, float(EngineTelegraph.HELM_ORDERS[controls.helm_ordered][1]), float(EngineTelegraph.ENGINE_ORDERS[controls.engine_ordered][1]))
	_update_camera(delta)
	_update_hud()
	var g := gunnery[player] as Gunnery
	marker.update_for(aim_point, player, g.dispersion_sigma(player.global_position.distance_to(aim_point)), hud.aim_color(), terrain, g.flight_time(aim_point))


## Test aid (--autoaim): fire at the nearest hostile as a stationary world point, i.e. with no lead.
## Test aid (--wound): batter the player's ship at the waterline so damage control has work to do.
func _wound() -> void:
	if OS.get_cmdline_user_args().has("--cripple"):
		var victims: Array = [player]
		if OS.get_cmdline_user_args().has("--cripple-foes"):
			victims = get_tree().get_nodes_in_group("ships").filter(func(n): return (n as Ship).team != player.team)
		for v in victims:
			var vs := v as Ship
			for c in vs.compartments:
				if c.kind in [Compartment.Kind.RUDDER, Compartment.Kind.STEERING_GEAR, Compartment.Kind.SCREW, Compartment.Kind.MAGAZINE, Compartment.Kind.TURRET]:
					c.hp = 0.0
					c.destroyed = true
					if c.kind == Compartment.Kind.MAGAZINE:
						c.on_fire = true
			vs.list_rad = deg_to_rad(9.0)
	for n in 7:
		var side := 1.0 if n % 2 == 0 else -1.0
		var pt := Vector3(side * player.beam_m * 0.5, -1.0, randf_range(-0.4, 0.4) * player.length_m)
		player.take_hit(player.to_global(pt), {"pen_mm": 150.0, "damage": 900.0, "fuse_m": 5.0, "radius": 9.0, "dir": Vector3(-side, -0.1, 0.0)})


func _autoaim() -> void:
	var best: Ship = null
	for n in get_tree().get_nodes_in_group("ships"):
		var sh := n as Ship
		if sh == null or sh.team == player.team or sh.sunk:
			continue
		if best == null or sh.global_position.distance_to(player.global_position) < best.global_position.distance_to(player.global_position):
			best = sh
	if best != null:
		aim_point = best.global_position + Vector3(0, 6.0, 0)
		fire_held = true


## Test aid (--shot=path,seconds): save a screenshot after some seconds and quit.
func _process(delta: float) -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			var parts := a.substr(7).split(",")
			_shot_t += delta
			var ready := _shot_t > float(parts[1])
			if ready and OS.get_cmdline_user_args().has("--await-trail"):
				ready = false
				for tr in get_tree().get_nodes_in_group("trails"):
					if (tr as ShellTrail).point_count() >= 12:
						ready = true
			if ready:
				get_viewport().get_texture().get_image().save_png(parts[0])
				get_tree().quit()


var _shot_t := 0.0
var _wounded := false


func _update_camera(delta: float) -> void:
	cam_heading = lerp_angle(cam_heading, player.heading, 1.0 - exp(-2.5 * delta))
	if cam_mode == CamMode.BRIDGE:
		var bp := player.global_position + Vector3(0, player.wlen() * 0.05 + 6.0, 0)
		for c in player.compartments:
			if c.kind == Compartment.Kind.BRIDGE:
				bp = player.to_global(c.center + Vector3(0, c.half_extents.y + 1.6, 0))
				break
		var a := player.heading + bridge_yaw
		var look := Vector3(sin(a) * cos(bridge_pitch), sin(bridge_pitch), cos(a) * cos(bridge_pitch))
		cam.global_position = bp
		cam.look_at(bp + look * 100.0, Vector3.UP)
		cam.fov = 70.0
		return
	cam.fov = 70.0
	var focus_h := clampf(player.wlen() * 0.04, 4.0, 28.0)
	var focus := player.global_position + Vector3(0, focus_h, 0)
	var yaw := cam_heading + cam_yaw
	var dir := Vector3(sin(yaw) * cos(cam_pitch), sin(cam_pitch), cos(yaw) * cos(cam_pitch))
	cam.global_position = focus + dir * cam_dist
	cam.look_at(focus + Vector3(0, look_up, 0), Vector3.UP)


func _march(from: Vector3, dir: Vector3) -> Vector3:
	# Free fire: the aim point is wherever the ray meets the terrain or the water.
	var p := from
	for _i in 600:
		p += dir * 50.0
		if p.y <= maxf(terrain.height_at(p.x, p.z), 0.0):
			break
	return p


func _update_aim_point(screen_pos: Vector2) -> void:
	aim_point = _march(cam.project_ray_origin(screen_pos), cam.project_ray_normal(screen_pos))


func _designate_aim(screen_pos: Vector2) -> void:
	touch_aim_world = _march(cam.project_ray_origin(screen_pos), cam.project_ray_normal(screen_pos))
	touch_aiming = true
	# A tap also fires, so touch play needs no separate aim step.
	if not player.sunk:
		(gunnery[player] as Gunnery).fire_at(touch_aim_world, Vector3.ZERO)


# --- HUD ----------------------------------------------------------------------

func _build_hud() -> void:
	sensors.scan_now()
	hud = Hud.new()
	add_child(hud)
	hud.camera = cam
	hud.sensors = sensors
	var foes := 0
	for n in get_tree().get_nodes_in_group("ships"):
		if (n as Ship).team != player.team:
			foes += 1
	hud.setup(player, gunnery[player], controls, terrain, String(Battlegrounds.get_ground(ground_id)["name"]), foes)
	if OS.get_cmdline_user_args().has("--openmap"):
		hud.toggle_map()
	hud.camera_pressed.connect(_cycle_camera)
	hud.fire_changed.connect(func(held: bool) -> void: fire_held = held)


func _update_hud() -> void:
	var live := sensors.contacts_live(true)
	var nearest: Ship = null
	var best := INF
	for e in live:
		var d := e.global_position.distance_to(player.global_position)
		if d < best:
			best = d
			nearest = e
	hud.update_hud(aim_point, CAM_NAMES[cam_mode], live.size(), nearest, not touch_aiming)
