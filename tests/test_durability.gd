extends Node3D
## Measures how many hits of each calibre it takes to cripple or sink each ship, with hits
## spread over the broadside the way real hits land (mostly above the waterline).
## godot --headless --path . --fixed-fps 60 res://tests/test_durability.tscn

const SHELLS := {          # calibre mm: [shell kg, label]
	127: [25.0, "5-inch"], 152: [47.0, "6-inch"], 203: [118.0, "8-inch"], 356: [635.0, "14-inch"], 406: [1225.0, "16-inch"],
}
const SHIPS := ["us_fletcher", "us_cleveland", "us_baltimore", "us_south_dakota", "us_iowa"]
const TRIALS := 8
const CAP := 600


func _ready() -> void:
	print("hits to: (P) lose propulsion, (G) lose main battery, (S) sink | mean of %d trials, cap %d" % [TRIALS, CAP])
	for id in SHIPS:
		var e := Roster.get_entry(id)
		print("\n%s  (%.0f m, %.0f t, %d compartments)" % [e["name"], e["length_m"], e["displacement_t"], ShipBuilder.build(e).size()])
		for cal in SHELLS:
			var kg: float = SHELLS[cal][0]
			var tot_p := 0.0
			var tot_g := 0.0
			var tot_s := 0.0
			for t in TRIALS:
				var r := _trial(e, float(cal), kg)
				tot_p += r[0]
				tot_g += r[1]
				tot_s += r[2]
			print("   %-8s  P %5.1f   G %5.1f   S %5.1f" % [SHELLS[cal][1], tot_p / TRIALS, tot_g / TRIALS, tot_s / TRIALS])
	get_tree().quit()


func _trial(e: Dictionary, cal: float, kg: float) -> Array:
	var s := Ship.new()
	add_child(s)
	s.setup_from_class(e, 0)
	s.global_position = Vector3.ZERO
	var had_guns := s.gun_turrets().size() > 0
	var p_at := -1
	var g_at := -1
	var s_at := CAP
	for n in range(1, CAP + 1):
		var side := 1.0 if randf() < 0.5 else -1.0
		var y := randf_range(-2.0, s.length_m * 0.09)
		var z := randf_range(-0.45, 0.45) * s.length_m
		var pt := Vector3(side * s.beam_m * 0.5, y, z)
		var dir := Vector3(-side, -0.12, randf_range(-0.35, 0.35)).normalized()
		var v_frac := 0.8
		var hit := {
			"pen_mm": cal * v_frac * 1.05, "damage": kg * 3.0, "fuse_m": 6.0,
			"radius": clampf(pow(kg, 0.33) * 1.2, 2.0, 18.0), "dir": dir,
		}
		s.take_hit(s.to_global(pt), hit)
		for _i in 30:
			s._physics_process(0.5)
		if p_at < 0 and s.propulsion_fraction() < 0.05:
			p_at = n
		if g_at < 0 and had_guns and s.battery_fraction() < 0.01:
			g_at = n
		if s.sunk:
			s_at = n
			break
	s.queue_free()
	return [p_at if p_at > 0 else CAP, g_at if g_at > 0 else CAP, s_at]
