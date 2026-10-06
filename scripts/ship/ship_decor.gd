class_name ShipDecor
extends RefCounted
## Deck furniture and finishing touches that are not separately damageable: windlass and anchors,
## bollards, deck houses and ventilators, boats on davits, life rafts, the ensign staff and flag,
## and a flight deck on carriers. Built once per class as a single static mesh, placed so nothing
## overlaps a damageable fitting. Also builds the hull-number and name labels.

static var _cache := {}


static func mesh_for(class_id: String, entry: Dictionary, frame: ShipFrame, comps: Array) -> ArrayMesh:
	if _cache.has(class_id):
		return _cache[class_id]
	var m := _build(class_id, entry, frame, comps)
	_cache[class_id] = m
	return m


static func _blocked(comps: Array, x: float, z: float, hx: float, hz: float, margin: float) -> bool:
	for c in comps:
		var cc: Compartment = c
		if cc.below_waterline or cc.kind in ShipBuilder.STRUCTURAL:
			continue
		if absf(x - cc.center.x) < hx + cc.half_extents.x + margin and absf(z - cc.center.z) < hz + cc.half_extents.z + margin:
			return true
	return false


static func _build(class_id: String, entry: Dictionary, f: ShipFrame, comps: Array) -> ArrayMesh:
	var k := MeshKit.new()
	var pal := ShipParts.palette(String(entry.get("nation", "USA")))
	var L := f.length
	var B := f.beam
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(class_id)
	var steel: Color = pal["steel"]
	var dark: Color = pal["dark"]
	var light: Color = pal["light"]
	var small := L < 60.0
	var is_carrier := String(entry.get("type", "")) == "carrier"
	var bh := clampf(f.freeboard * 0.12, 0.6, 1.1) if L > 40.0 else 0.0

	# --- Forecastle: windlass, capstans, hawse pipes, anchors, chain ------------------------------
	var bz := L * 0.5 * 0.86
	var by := f.deck_y(bz)
	if not is_carrier and not small:
		k.cyl(Vector3(0, by, bz), Vector2(0.6, 0.6), Vector2(0.5, 0.5), 0.7, 10, dark.lightened(0.15))
		k.box(Vector3(0, by + 0.25, bz - 2.2), Vector3(B * 0.07, 0.25, 0.9), dark.lightened(0.1))
		k.cyl(Vector3(0, by, bz - 4.2), Vector2(0.5, 0.5), Vector2(0.45, 0.45), 0.55, 10, dark.lightened(0.15))
		for sx in [-1.0, 1.0]:
			var ax := f.half_width_at(bz + 3.0, f.deck_y(bz + 3.0) * 0.6) + 0.1
			k.box(Vector3(sx * (ax - 0.4), f.deck_y(bz + 3.0) * 0.6, bz + 3.0), Vector3(0.42, 0.55, 0.5), dark)
			# Anchor stowed in the hawse: shank, stock, flukes.
			k.strut(Vector3(sx * ax, f.deck_y(bz + 3.0) * 0.6 + 0.6, bz + 3.0), Vector3(sx * ax, f.deck_y(bz + 3.0) * 0.6 - 0.8, bz + 3.0), 0.16, dark.lightened(0.2))
			k.box(Vector3(sx * ax, f.deck_y(bz + 3.0) * 0.6 - 0.9, bz + 3.0), Vector3(0.05, 0.1, 0.55), dark.lightened(0.2))
			# Chain run to the windlass.
			k.strut(Vector3(sx * (ax - 0.5), by + 0.08, bz + 3.0), Vector3(sx * 0.3, by + 0.08, bz), 0.12, dark.lightened(0.1))

	# --- Bollards and fairleads along the deck edge -------------------------------------------------
	if L > 40.0:
		var nb := int(clampf(L / 14.0, 4.0, 18.0))
		for i in nb:
			var z := lerpf(-L * 0.46, L * 0.44, float(i) / (nb - 1))
			var dy := f.deck_y(z)
			var hw := f.half_breadth(z)
			for sx in [-1.0, 1.0]:
				k.cyl(Vector3(sx * (hw - 0.7), dy, z), Vector2(0.14, 0.14), Vector2(0.11, 0.11), 0.4, 8, dark.lightened(0.2))

	# --- Deck houses with ventilators ---------------------------------------------------------------
	var n_houses := clampi(int(L / 35.0), 1, 8)
	for i in n_houses:
		var hl := clampf(L * 0.03, 2.2, 8.0) * rng.randf_range(0.8, 1.2)
		var hwid := clampf(B * 0.22, 1.2, 5.0)
		var hh := f.deck_height * rng.randf_range(0.55, 0.85)
		var placed := false
		for attempt in 14:
			var z := rng.randf_range(-L * 0.38, L * 0.34)
			var x := rng.randf_range(-B * 0.18, B * 0.18)
			if _blocked(comps, x, z, hwid, hl * 0.5, 1.0):
				continue
			var dy := f.deck_y(z)
			k.block(dy, dy + hh, Rect2(x - hwid, z - hl * 0.5, hwid * 2.0, hl), Rect2(x - hwid * 0.92, z - hl * 0.5, hwid * 1.84, hl * 0.94), steel.darkened(0.06), steel.lightened(0.05))
			k.box(Vector3(x, dy + hh * 0.55, z + hl * 0.5 + 0.02), Vector3(hwid * 0.5, hh * 0.18, 0.03), ShipParts.GLASS)
			# Mushroom ventilator on the roof.
			var vx := x + hwid * 0.45
			k.cyl(Vector3(vx, dy + hh, z), Vector2(0.22, 0.22), Vector2(0.18, 0.18), 0.55, 8, dark.lightened(0.15))
			k.cyl(Vector3(vx, dy + hh + 0.55, z), Vector2(0.22, 0.22), Vector2(0.4, 0.4), 0.18, 8, dark.lightened(0.25), Vector3.ZERO, true)
			placed = true
			break
		if not placed:
			continue

	# --- Boats on davits and life rafts ------------------------------------------------------------------
	if not small:
		var blen := clampf(L * 0.04, 4.5, 10.0)
		var bw := blen * 0.26
		var n_boats := clampi(int(L / 60.0), 1, 3)
		for sx in [-1.0, 1.0]:
			for i in n_boats:
				var z := -L * 0.08 + (i - (n_boats - 1) * 0.5) * (blen + 2.5) + (L * 0.1 if sx > 0.0 else -L * 0.02)
				var hw := f.half_breadth(z)
				var x: float = sx * (hw - bw - 1.0)
				if _blocked(comps, x, z, bw, blen * 0.5, 0.6):
					continue
				var dy := f.deck_y(z) + 0.6
				# Hull of the boat: pointed bow, flat transom, light canopy and two davit arms.
				k.block(dy, dy + bw * 0.55, Rect2(x - bw, z - blen * 0.5, bw * 2.0, blen * 0.82), Rect2(x - bw * 1.1, z - blen * 0.5, bw * 2.2, blen * 0.82), light.darkened(0.15), light.darkened(0.3))
				k.tri(Vector3(x - bw, dy + bw * 0.55, z + blen * 0.32), Vector3(x + bw, dy + bw * 0.55, z + blen * 0.32), Vector3(x, dy + bw * 0.55, z + blen * 0.5), Vector3.UP, light.darkened(0.3))
				k.box(Vector3(x, dy + bw * 0.75, z - blen * 0.1), Vector3(bw * 0.8, bw * 0.2, blen * 0.2), steel.lightened(0.1))
				for dz in [-0.28, 0.28]:
					k.strut(Vector3(x - sx * bw * 1.1, f.deck_y(z) , z + blen * dz), Vector3(x - sx * bw * 0.3, dy + bw * 1.5, z + blen * dz), 0.1, dark.lightened(0.2))
		# Life rafts: floats stowed along the bulwark.
		var nr := clampi(int(L / 25.0), 2, 10)
		for i in nr:
			var z := lerpf(-L * 0.3, L * 0.2, float(i) / maxf(nr - 1, 1))
			var hw := f.half_breadth(z)
			for sx in [-1.0, 1.0]:
				var x: float = sx * (hw - 0.55)
				if _blocked(comps, x, z, 0.45, 0.8, 0.5):
					continue
				k.tube(x, f.deck_y(z) + 0.5, z - 0.8, z + 0.8, 0.28, 0.28, 8, Color(0.78, 0.76, 0.68))

	# --- Carrier flight deck -------------------------------------------------------------------------------
	if is_carrier:
		var fy := f.deck("d01") + 0.35
		var fl := L * 0.96
		var fw := B * 0.5 * 1.08
		var deckc: Color = pal["deck"].darkened(0.1)
		k.block(fy - 0.5, fy, Rect2(-fw, -fl * 0.5, fw * 2.0, fl), Rect2(-fw, -fl * 0.5, fw * 2.0, fl), steel.darkened(0.15), deckc)
		k.box(Vector3(0, fy + 0.02, 0), Vector3(0.12, 0.02, fl * 0.46), Color(0.9, 0.9, 0.85))        # centreline
		for sx in [-1.0, 1.0]:
			k.box(Vector3(sx * (fw - 0.5), fy + 0.02, 0), Vector3(0.08, 0.02, fl * 0.47), Color(0.9, 0.9, 0.85))
			# Gallery walkway under the deck edge.
			k.box(Vector3(sx * (fw + 0.5), fy - 0.9, 0), Vector3(0.6, 0.15, fl * 0.42), steel.darkened(0.2))
		for i in 8:
			k.box(Vector3(0, fy + 0.015, -fl * 0.38 + float(i) * fl * 0.06), Vector3(fw * 0.5, 0.012, 0.05), Color(0.8, 0.8, 0.78))   # arrestor wires

	# --- Ensign staff and flag at the stern ------------------------------------------------------------
	var sz := -L * 0.5 + 2.0
	var sy := f.deck_y(sz)
	var sh := clampf(L * 0.03, 2.2, 5.0)
	k.strut(Vector3(0, sy, sz), Vector3(0, sy + sh, sz), 0.08, light)
	_flag(k, String(entry.get("nation", "USA")), Vector3(0, sy + sh, sz), clampf(L * 0.012, 1.2, 3.6))
	return k.commit()


## A flag trailing aft (-Z) from a staff top, built as coloured quads in the flag's own plane.
static func _flag(k: MeshKit, nation: String, top: Vector3, h: float) -> void:
	var w := h * 1.6
	var stripes: Array = []        # [u0, v0, u1, v1, colour]  (u: 0 hoist .. 1 fly, v: 0 bottom .. 1 top)
	var white := Color(0.94, 0.94, 0.92)
	var red := Color(0.74, 0.12, 0.12)
	var blue := Color(0.10, 0.18, 0.46)
	match nation:
		"USA":
			stripes.append([0, 0, 1, 1, white])
			for i in 7:
				stripes.append([0, float(2 * i) / 13.0, 1, float(2 * i + 1) / 13.0, red])
			stripes.append([0, 6.0 / 13.0, 0.42, 1, blue])
		"United Kingdom":
			stripes.append([0, 0, 1, 1, white])
			stripes.append([0, 0.5, 0.5, 1, blue])
			stripes.append([0.44, 0, 0.58, 1, red])
			stripes.append([0, 0.43, 1, 0.57, red])
		"Japan":
			stripes.append([0, 0, 1, 1, white])
			stripes.append([0.3, 0.3, 0.55, 0.7, red])
		"Germany":
			stripes.append([0, 0, 1, 1, red])
			stripes.append([0, 0.4, 1, 0.6, white])
			stripes.append([0.35, 0, 0.55, 1, white])
			stripes.append([0, 0.45, 1, 0.55, Color(0.05, 0.05, 0.05)])
			stripes.append([0.4, 0, 0.5, 1, Color(0.05, 0.05, 0.05)])
		"Italy":
			stripes.append([0, 0, 0.34, 1, Color(0.10, 0.50, 0.25)])
			stripes.append([0.34, 0, 0.67, 1, white])
			stripes.append([0.67, 0, 1, 1, red])
		"France":
			stripes.append([0, 0, 0.34, 1, blue])
			stripes.append([0.34, 0, 0.67, 1, white])
			stripes.append([0.67, 0, 1, 1, red])
		_:
			stripes.append([0, 0, 1, 1, white])
			stripes.append([0, 0, 1, 0.18, blue])
			stripes.append([0.1, 0.5, 0.35, 0.95, red])
	var segs := 4
	var layer := 0.0
	for s in stripes:
		layer += 0.004
		for j in segs:
			var u0: float = lerpf(float(s[0]), float(s[2]), float(j) / segs)
			var u1: float = lerpf(float(s[0]), float(s[2]), float(j + 1) / segs)
			var a := _flag_pt(top, u0, float(s[1]), w, h, layer)
			var b := _flag_pt(top, u1, float(s[1]), w, h, layer)
			var c := _flag_pt(top, u1, float(s[3]), w, h, layer)
			var d := _flag_pt(top, u0, float(s[3]), w, h, layer)
			k.tri(a, b, c, Vector3(1, 0, 0), s[4])
			k.tri(a, c, d, Vector3(1, 0, 0), s[4])


static func _flag_pt(top: Vector3, u: float, v: float, w: float, h: float, layer: float) -> Vector3:
	# Trails aft with a gentle ripple.
	return top + Vector3(sin(u * 5.0) * 0.08 * h + layer, -h + v * h, -u * w)


# --- Labels ---------------------------------------------------------------------------------------------------

## Hull number on both bows and the ship's name on the transom. Returns the Label3D nodes.
static func labels(entry: Dictionary, f: ShipFrame) -> Array[Label3D]:
	var out: Array[Label3D] = []
	var nm := String(entry.get("name", ""))
	var number := ""
	var re := RegEx.new()
	re.compile("\\(([A-Z]+)-?(\\d+)\\)")
	var mt := re.search(nm)
	if mt != null:
		number = mt.get_string(2)
		nm = nm.substr(0, mt.get_start()).strip_edges()
	for pre in ["USS ", "HMS ", "HMAS ", "IJN ", "KMS ", "RN ", "FNS "]:
		if nm.begins_with(pre):
			nm = nm.substr(pre.length())
	if f.freeboard < 1.4 or f.length < 40.0:
		return out
	var th := clampf(f.freeboard * 0.6, 0.9, 4.5)
	if number != "":
		for side in [1.0, -1.0]:
			var z := f.length * 0.5 * 0.55
			var y := f.freeboard * 0.55
			var lab := _label(number, th)
			lab.position = Vector3(side * (f.half_width_at(z, y) + 0.3), y, z)
			lab.rotation.y = side * PI * 0.5
			out.append(lab)
	if nm != "":
		var lab2 := _label(nm.to_upper(), th * 0.7)
		var z2 := -f.length * 0.5
		lab2.position = Vector3(0, f.freeboard * 0.55, z2 - 0.04)
		lab2.rotation.y = PI
		out.append(lab2)
	return out


static func _label(text: String, height_m: float) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = 64
	l.pixel_size = height_m / 64.0 / 0.72
	l.modulate = Color(0.95, 0.95, 0.93)
	l.outline_size = 0
	l.shaded = true
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	return l
