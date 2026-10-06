extends Node3D
## Surface-ship testbed: the player vs 30 AI opponents on one of the seven battlegrounds.
## Controls: W/S throttle, A/D rudder, hold RMB + move mouse to orbit, wheel to zoom,
## LMB fires the main battery at the cursor. [ / ] cycle your ship. F1-F7 pick a battleground.

const OPPONENTS := 30

@export var ground_id := "surigao_strait"
var player_index := 0

var terrain: BattleTerrain
var player: Ship
var gunnery: Dictionary = {}       ## Ship -> Gunnery
var cam: Camera3D
var cam_yaw := 0.0
var cam_pitch := 0.35
var cam_dist := 220.0
var hud: Label
var sun: DirectionalLight3D
var env: WorldEnvironment
var water: MeshInstance3D
var aim_point := Vector3.ZERO


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		ground_id = args[0]
	_report_on = args.has("--report")
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
	var ti := cl.find("--time")
	if ti >= 0 and ti + 1 < cl.size():
		tod = float(cl[ti + 1])
	var wi := cl.find("--weather")
	if wi >= 0 and wi + 1 < cl.size():
		weather = cl[wi + 1]
	var preset := SkySea.preset_for(tod, weather, float(ground["visibility_m"]))
	var built := SkySea.build(self, preset, Vector2(240000, 240000))
	sun = built["sun"]
	env = WorldEnvironment.new()   # (the environment node lives inside SkySea's build; kept for API compatibility)
	water = built["sea"]
	print("Sky preset: %s (time %.1f, weather %s)" % [preset, tod, weather])

	cam = Camera3D.new()
	cam.far = 30000.0
	cam.current = true
	add_child(cam)


func _spawn_fleet() -> void:
	var ground := Battlegrounds.get_ground(ground_id)
	var pool_a: Array = ground["team_a_pool"]
	var pool_b: Array = ground["team_b_pool"]
	var player_id: String = pool_a[player_index % pool_a.size()]
	player = _spawn(player_id, 0, _find_water(ground["spawn_a"]), true)

	for i in OPPONENTS:
		var cls: String = pool_b[i % pool_b.size()]
		var anchor: Vector3 = ground["spawn_b"]
		var offset := Vector3((i % 6 - 2.5) * 650.0, 0, (i / 6 - 2) * 650.0)
		var s := _spawn(cls, 1, _find_water(anchor + offset), false)
		s.heading = PI
	player.heading = 0.0
	# Test option: --allies N adds N AI-controlled ships on the player's side.
	var cl := OS.get_cmdline_user_args()
	var ai_i := cl.find("--allies")
	if ai_i >= 0 and ai_i + 1 < cl.size():
		for i in int(cl[ai_i + 1]):
			var cls_a: String = pool_a[(i + 1) % pool_a.size()]
			var off_a := Vector3((i % 6 - 2.5) * 650.0, 0, 650.0 + (i / 6) * 650.0)
			_spawn(cls_a, 0, _find_water((ground["spawn_a"] as Vector3) + off_a), false)
	if OS.get_cmdline_user_args().has("--auto"):
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
	s.global_position = pos
	s.add_to_group("ships")
	var vis := ShipVisual.new()
	s.add_child(vis)
	vis.setup(s)
	var g := Gunnery.new()
	s.add_child(g)
	g.setup(s)
	gunnery[s] = g
	if not is_player:
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

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		cam_yaw -= event.relative.x * 0.004
		cam_pitch = clampf(cam_pitch + event.relative.y * 0.004, 0.05, 1.4)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam_dist = maxf(cam_dist * 0.9, 40.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam_dist = minf(cam_dist * 1.1, 2500.0)
	elif event is InputEventKey and event.pressed:
		var k := (event as InputEventKey).keycode
		if k >= KEY_F1 and k <= KEY_F7:
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
	if not player.sunk:
		player.throttle = clampf(player.throttle + Input.get_axis("throttle_down", "throttle_up") * 0.4 * delta, -0.3, 1.0)
		player.rudder = Input.get_axis("rudder_left", "rudder_right") * -1.0
		_update_aim_point()
		if Input.is_action_pressed("fire_main"):
			(gunnery[player] as Gunnery).fire_at(aim_point, Vector3.ZERO)
	_update_camera()
	_update_hud()


func _update_camera() -> void:
	var focus := player.global_position + Vector3(0, 12, 0)
	var dir := Vector3(sin(cam_yaw) * cos(cam_pitch), sin(cam_pitch), cos(cam_yaw) * cos(cam_pitch))
	cam.global_position = focus + dir * cam_dist
	cam.look_at(focus, Vector3.UP)


func _update_aim_point() -> void:
	var mp := get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(mp)
	var dir := cam.project_ray_normal(mp)
	# March the ray until it meets the terrain or the water.
	var p := from
	for _i in 600:
		p += dir * 50.0
		if p.y <= maxf(terrain.height_at(p.x, p.z), 0.0):
			break
	aim_point = p


# --- HUD ----------------------------------------------------------------------

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(16, 12)
	hud.add_theme_font_size_override("font_size", 16)
	hud.add_theme_color_override("font_shadow_color", Color.BLACK)
	layer.add_child(hud)


func _update_hud() -> void:
	var enemies := 0
	for n in get_tree().get_nodes_in_group("ships"):
		var s := n as Ship
		if s != null and not s.sunk and s.team != player.team:
			enemies += 1
	var turrets := player.gun_turrets()
	var ok := 0
	for t in turrets:
		if t.is_functional():
			ok += 1
	var lines: Array[String] = []
	lines.append("%s  [%s]  -  %s" % [player.display_name, player.nation, Battlegrounds.get_ground(ground_id)["name"]])
	lines.append("Speed %.1f kts   Throttle %d%%   Hdg %d deg" % [absf(player.speed_ms) / 0.5144, player.throttle * 100.0, fposmod(rad_to_deg(player.heading), 360.0)])
	lines.append("Propulsion %d%%   Steering %d%%   Flooding %.0f / %.0f t   List %.1f deg" % [
		player.propulsion_fraction() * 100.0, player.steering_fraction() * 100.0, player.total_flooded_t,
		player.reserve_buoyancy_t, rad_to_deg(player.list_rad)])
	lines.append("Main battery %d / %d turrets   Hostiles afloat: %d / %d" % [ok, turrets.size(), enemies, OPPONENTS])
	var hurt: Array[String] = []
	for c in player.compartments:
		if c.destroyed and c.kind != Compartment.Kind.HULL_SECTION:
			hurt.append("%s: DESTROYED" % c.id)
		elif c.on_fire:
			hurt.append("%s: FIRE" % c.id)
		elif c.flood_rate > 0.0 and c.flooded_tonnes < c.capacity_tonnes:
			hurt.append("%s: FLOODING" % c.id)
	if hurt.size() > 0:
		lines.append("Damage control: " + ", ".join(hurt.slice(0, 8)))
	if player.sunk:
		lines.append("*** SHIP LOST ***  ([ / ] to pick a new ship, F1-F7 for a different battleground)")
	hud.text = "\n".join(lines)
