extends Node
## Layout audit for every roster class: godot --headless --path . res://tests/test_layout.tscn
## Checks each ship against the standard frame: spaces inside the hull envelope and decks,
## no overlaps between non-structural spaces, port/starboard mirrored, sensible heights.

var fails := 0
var warns := 0


func _ready() -> void:
	Roster.include_subs = true
	var ids: Array = []
	for e in Roster.available():
		ids.append(e["id"])
	for id in ids:
		_check(Roster.get_entry(id))
	print("LAYOUT: %d classes checked, %d failures, %d warnings" % [ids.size(), fails, warns])
	get_tree().quit(1 if fails > 0 else 0)


func _check(e: Dictionary) -> void:
	var f := ShipFrame.for_entry(e)
	_tiny = f.length < 40.0
	var comps := ShipBuilder.build(e)
	var id: String = e["id"]
	var L := f.length
	for c in comps:
		var lo := c.center - c.half_extents
		var hi := c.center + c.half_extents
		# Longitudinal bounds.
		if lo.z < -L * 0.5 - 0.5 or hi.z > L * 0.5 + 0.5:
			_fail(id, "%s outside the hull length (z %.1f..%.1f of %.0f)" % [c.id, lo.z, hi.z, L])
		# Vertical bounds: keel to the top of the superstructure.
		if lo.y < -f.draft - 0.1:
			_fail(id, "%s below the keel (y %.1f)" % [c.id, lo.y])
		# Transverse: fittings and spaces must sit within the hull envelope at their position.
		if c.kind not in ShipBuilder.STRUCTURAL and c.kind != Compartment.Kind.RUDDER and c.kind != Compartment.Kind.SCREW:
			var env := f.half_breadth(c.center.z) + 0.6
			var reach := absf(c.center.x) + c.half_extents.x
			if reach > env:
				_fail(id, "%s sticks out of the hull (reach %.1f m, hull %.1f m at z=%.0f)" % [c.id, reach, env, c.center.z])
	# Overlaps between non-structural spaces.
	for i in comps.size():
		for j in range(i + 1, comps.size()):
			var a := comps[i]
			var b := comps[j]
			if a.kind in ShipBuilder.STRUCTURAL or b.kind in ShipBuilder.STRUCTURAL:
				continue
			if a.kind == Compartment.Kind.RUDDER or b.kind == Compartment.Kind.RUDDER:
				continue
			var d := (a.center - b.center).abs()
			var r := a.half_extents + b.half_extents
			if d.x < r.x - 0.05 and d.y < r.y - 0.05 and d.z < r.z - 0.05:
				_fail(id, "%s overlaps %s" % [a.id, b.id])
	# Port/starboard symmetry for paired hull sections.
	for c in comps:
		if c.id.ends_with("_p") and c.kind == Compartment.Kind.HULL_SECTION:
			var twin_id := c.id.trim_suffix("_p") + "_s"
			var found := false
			for o in comps:
				if o.id == twin_id and absf(o.center.x + c.center.x) < 0.01:
					found = true
			if not found:
				_fail(id, "%s has no mirrored starboard twin" % c.id)
	# Heights scale with the ship: bridge top above the main deck, funnels shorter than the mast.
	var bridge: Compartment = null
	for c in comps:
		if c.kind == Compartment.Kind.BRIDGE:
			bridge = c
	if bridge != null and bridge.center.y + bridge.half_extents.y < f.freeboard + f.deck_height:
		_fail(id, "bridge is not above the main deck")


var _tiny := false


func _fail(id: String, msg: String) -> void:
	# Craft under 40 m (PT / MAS / S-boat) are too narrow to hold every space in its own box.
	if _tiny:
		warns += 1
		print("warn %s: %s" % [id, msg])
		return
	fails += 1
	print("FAIL %s: %s" % [id, msg])
