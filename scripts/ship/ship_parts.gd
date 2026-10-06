class_name ShipParts
extends RefCounted
## Detailed models for each damageable fitting, built from MeshKit solids in the compartment's own
## local frame (origin at the compartment centre, +Z bow, +Y up). Colours are baked into vertex
## colours; the visual multiplies them by a damage tint. Meshes are cached per class and part.

static var _cache := {}

const GLASS := Color(0.05, 0.07, 0.09)


static func palette(nation: String) -> Dictionary:
	var p := {
		"steel": Color(0.46, 0.50, 0.53), "deck": Color(0.28, 0.30, 0.33), "hull": Color(0.40, 0.44, 0.47),
		"gun": Color(0.34, 0.37, 0.39), "light": Color(0.70, 0.73, 0.75), "dark": Color(0.16, 0.17, 0.19),
		"funnel": Color(0.43, 0.47, 0.50), "cap": Color(0.07, 0.07, 0.08), "wood": Color(0.52, 0.42, 0.28),
	}
	match nation:
		"United Kingdom":
			p["steel"] = Color(0.60, 0.64, 0.66)
			p["hull"] = Color(0.52, 0.56, 0.58)
			p["funnel"] = Color(0.55, 0.58, 0.60)
			p["deck"] = Color(0.34, 0.33, 0.31)
		"Japan":
			p["steel"] = Color(0.40, 0.43, 0.43)
			p["hull"] = Color(0.33, 0.36, 0.36)
			p["funnel"] = Color(0.36, 0.39, 0.39)
			p["deck"] = Color(0.34, 0.27, 0.20)
		"Germany":
			p["steel"] = Color(0.50, 0.53, 0.56)
			p["hull"] = Color(0.42, 0.45, 0.48)
			p["funnel"] = Color(0.45, 0.48, 0.51)
			p["deck"] = Color(0.43, 0.37, 0.28)
		"Italy":
			p["steel"] = Color(0.62, 0.65, 0.66)
			p["hull"] = Color(0.52, 0.55, 0.57)
			p["funnel"] = Color(0.56, 0.58, 0.60)
			p["deck"] = Color(0.40, 0.34, 0.26)
		"France":
			p["steel"] = Color(0.50, 0.56, 0.62)
			p["hull"] = Color(0.42, 0.48, 0.55)
			p["funnel"] = Color(0.46, 0.52, 0.58)
			p["deck"] = Color(0.38, 0.33, 0.27)
		"USSR":
			p["steel"] = Color(0.48, 0.52, 0.52)
			p["hull"] = Color(0.40, 0.44, 0.44)
			p["funnel"] = Color(0.44, 0.48, 0.48)
	return p


static func part_mesh(ship_class: String, c: Compartment, entry: Dictionary, frame: ShipFrame) -> ArrayMesh:
	var key := "%s|%s" % [ship_class, c.id]
	if _cache.has(key):
		return _cache[key]
	var pal := palette(String(entry.get("nation", "USA")))
	var k := MeshKit.new()
	var h := c.half_extents
	var L := frame.length
	match c.kind:
		Compartment.Kind.TURRET:
			var gun: Dictionary = entry.get("main_gun", {})
			_turret(k, h, float(gun.get("caliber_mm", 100.0)), maxi(1, int(gun.get("barrels_per_turret", 1))), pal)
		Compartment.Kind.SECONDARY_MOUNT:
			k.push(Transform3D(Basis(Vector3.UP, signf(c.center.x) * PI * 0.5), Vector3.ZERO))
			_turret(k, h, 127.0 if L > 150.0 else 102.0, 2, pal)
			k.pop()
		Compartment.Kind.BRIDGE:
			_bridge(k, h, L, pal)
		Compartment.Kind.FUNNEL:
			_funnel(k, h, pal)
		Compartment.Kind.MAST:
			_mast(k, h, L, pal)
		Compartment.Kind.AA_MOUNT:
			k.push(Transform3D(Basis(Vector3.UP, signf(c.center.x) * PI * 0.5), Vector3.ZERO))
			_aa(k, h, pal)
			k.pop()
		Compartment.Kind.TORPEDO_TUBES:
			_tubes(k, h, pal)
		Compartment.Kind.HANGAR:
			_hangar(k, h, pal)
		_:
			k.box(Vector3.ZERO, h, pal["steel"])
	var m := k.commit()
	_cache[key] = m
	return m


# --- Gun turrets ---------------------------------------------------------------------------

static func _turret(k: MeshKit, h: Vector3, cal: float, n: int, pal: Dictionary) -> void:
	var hx := h.x
	var hy := h.y
	var hz := h.z
	var cal_m := cal / 1000.0
	var total := hy * 2.0
	var house_h := minf(total, clampf(2.2 + cal * 0.006, 2.4, 5.2))
	if hx < 1.4:
		house_h = minf(total, maxf(total * 0.9, 1.0))
	var barb_h := total - house_h
	var y0 := -hy + barb_h
	var yt := hy
	var gun_col: Color = pal["gun"]
	var dark: Color = pal["dark"]
	if barb_h > 0.25:
		k.cyl(Vector3(0, -hy, 0), Vector2(hx * 0.98, hz * 0.9), Vector2(hx * 0.98, hz * 0.9), barb_h, 20, pal["deck"], Vector3.ZERO, false)
		k.cyl(Vector3(0, y0 - 0.16, 0), Vector2(hx * 1.04, hz * 0.96), Vector2(hx * 1.04, hz * 0.96), 0.16, 20, dark, Vector3.ZERO, false)
	# Gun house: vertical aft, sides tapering a little, front face sloped back.
	var tw := hx * 0.88
	k.block(y0, yt, Rect2(-hx, -hz * 0.95, hx * 2.0, hz * 1.95), Rect2(-tw, -hz * 0.95, tw * 2.0, hz * 1.5), gun_col, gun_col.lightened(0.06))
	# Roof fittings: hatches and the sighting hoods at the front.
	k.box(Vector3(hx * 0.42, yt + 0.05, -hz * 0.25), Vector3(hx * 0.2, 0.06, hz * 0.14), dark)
	k.box(Vector3(-hx * 0.42, yt + 0.05, -hz * 0.25), Vector3(hx * 0.2, 0.06, hz * 0.14), dark)
	for sx in [-1.0, 1.0]:
		k.box(Vector3(sx * hx * 0.5, yt + 0.18, hz * 0.2), Vector3(hx * 0.14, 0.18, hz * 0.1), gun_col.lightened(0.12))
		k.box(Vector3(sx * hx * 0.5, yt + 0.2, hz * 0.31), Vector3(hx * 0.1, 0.05, 0.02), GLASS)
	# Rangefinder across the rear of the roof on big turrets, hoods at each end.
	if cal >= 150.0:
		var ry := y0 + house_h * 0.7
		k.tube_x(ry, -hz * 0.55, -hx * 1.12, hx * 1.12, house_h * 0.065, 8, gun_col.lightened(0.08))
		for sx in [-1.0, 1.0]:
			k.box(Vector3(sx * hx * 1.12, ry, -hz * 0.55), Vector3(0.12, house_h * 0.1, house_h * 0.1), gun_col.lightened(0.15))
		k.box(Vector3(0, ry - house_h * 0.12, -hz * 0.55), Vector3(hx * 0.12, house_h * 0.12, house_h * 0.1), gun_col)
	# Guns.
	var radius := maxf(cal_m * 1.35, 0.07)
	var length := clampf(cal_m * 45.0, 2.0, 22.0)
	var spacing := minf(hx * 1.8 / (n + 1), cal_m * 4.2)
	var gy := y0 + house_h * 0.4
	var gz := lerpf(hz, hz * 0.55, 0.4)
	for i in n:
		var x := (float(i) - (n - 1) * 0.5) * spacing
		k.box(Vector3(x, gy, gz - 0.05), Vector3(minf(spacing * 0.45, radius * 1.5), maxf(house_h * 0.13, radius * 1.4), 0.2), dark)
		k.push(Transform3D(Basis(Vector3.RIGHT, -0.07), Vector3(x, gy, gz - 0.1)))
		var seg := 12 if cal >= 150.0 else 8
		k.tube(0, 0, -0.5, length * 0.3, radius * 1.1, radius, seg, gun_col.darkened(0.1))
		k.tube(0, 0, length * 0.3, length * 0.96, radius * 0.88, radius * 0.6, seg, gun_col.darkened(0.05))
		k.tube(0, 0, length * 0.9, length, radius * 0.7, radius * 0.7, seg, dark)
		k.pop()


# --- Bridge / superstructure tower --------------------------------------------------------------

static func _bridge(k: MeshKit, h: Vector3, L: float, pal: Dictionary) -> void:
	var W := h.x * 2.0
	var Ln := h.z * 2.0
	var H := h.y * 2.0
	var steel: Color = pal["steel"]
	var light: Color = pal["light"]
	var n := clampi(roundi(H / 2.7), 2, 6)
	var th := H / n
	var y := -h.y
	var wing_tier := maxi(n - 2, 1)
	for i in n:
		var t := float(i)
		var wx := h.x * (1.0 - 0.1 * t)
		var z_aft := -h.z + Ln * 0.03 * t
		var z_fore := h.z - Ln * 0.07 * t
		var shade := steel.darkened(0.04 * t) if i % 2 == 0 else steel.lightened(0.03)
		# Tier with a raked (leaning-back) front face.
		var z_fore_top := z_fore - Ln * 0.03
		k.block(y, y + th, Rect2(-wx, z_aft, wx * 2.0, z_fore - z_aft), Rect2(-wx * 0.97, z_aft, wx * 1.94, z_fore_top - z_aft), shade, shade.lightened(0.08))
		# Window band (front and both sides) on the upper part of each tier above the first.
		if i >= 1:
			var wy := y + th * 0.62
			k.box(Vector3(0, wy, z_fore - Ln * 0.015), Vector3(wx * 0.9, th * 0.17, 0.06), GLASS)
			for sx in [-1.0, 1.0]:
				k.box(Vector3(sx * (wx + 0.02), wy, (z_aft + z_fore) * 0.5), Vector3(0.05, th * 0.15, (z_fore - z_aft) * 0.42), GLASS)
		# Roof rails.
		var rail_y := y + th + 0.25
		k.strut(Vector3(-wx, rail_y, z_fore), Vector3(wx, rail_y, z_fore), 0.05, light)
		k.strut(Vector3(-wx, rail_y, z_fore), Vector3(-wx, rail_y, z_aft), 0.05, light)
		k.strut(Vector3(wx, rail_y, z_fore), Vector3(wx, rail_y, z_aft), 0.05, light)
		# Bridge wings with their own rails and a searchlight.
		if i == wing_tier:
			var wing_y := y + th * 0.18
			var ww := wx * 1.7
			k.box(Vector3(0, wing_y, z_fore - Ln * 0.12), Vector3(ww, 0.12, Ln * 0.11), shade.darkened(0.12), shade)
			for sx in [-1.0, 1.0]:
				k.strut(Vector3(sx * ww, wing_y + 0.5, z_fore + Ln * 0.0), Vector3(sx * ww, wing_y + 0.5, z_fore - Ln * 0.23), 0.05, light)
				k.strut(Vector3(sx * ww, wing_y + 0.5, z_fore), Vector3(sx * wx, wing_y + 0.5, z_fore), 0.05, light)
				k.cyl(Vector3(sx * (wx + 0.4), wing_y + 0.1, z_aft + Ln * 0.2), Vector2(0.32, 0.32), Vector2(0.28, 0.28), 0.6, 10, pal["dark"])
		y += th
	# Pilot house cap, director and radar on top.
	var tx := h.x * (1.0 - 0.1 * (n - 1))
	var top_y := h.y
	var dir_w := tx * 0.55
	k.block(top_y, top_y + th * 0.45, Rect2(-dir_w, -h.z * 0.2, dir_w * 2.0, Ln * 0.45), Rect2(-dir_w * 0.8, -h.z * 0.1, dir_w * 1.6, Ln * 0.32), pal["dark"].lightened(0.2), steel)
	k.tube_x(top_y + th * 0.3, h.z * 0.12, -dir_w * 1.5, dir_w * 1.5, th * 0.06, 8, steel.lightened(0.1))
	var rad_y := top_y + th * 0.45
	k.strut(Vector3(0, rad_y, -h.z * 0.05), Vector3(0, rad_y + th * 0.8, -h.z * 0.05), 0.08, light)
	var rw := clampf(W * 0.38, 0.8, 3.0)
	k.box(Vector3(0, rad_y + th * 0.85, -h.z * 0.05), Vector3(rw, rw * 0.28, 0.07), pal["dark"].lightened(0.25))
	k.strut(Vector3(0, rad_y + th * 0.8, -h.z * 0.05), Vector3(0, rad_y + th * 1.6, -h.z * 0.05), 0.04, light)


# --- Funnel -----------------------------------------------------------------------------------------

static func _funnel(k: MeshKit, h: Vector3, pal: Dictionary) -> void:
	var H := h.y * 2.0
	var rx := h.x
	var rz := h.z
	var col: Color = pal["funnel"]
	var rake := -H * 0.09
	# Uptake casing at the base, wider than the stack.
	var cas_h := H * 0.26
	k.cyl(Vector3(0, -h.y, 0), Vector2(rx * 1.14, rz * 1.12), Vector2(rx * 1.02, rz * 1.02), cas_h, 20, col.darkened(0.08), Vector3(0, 0, rake * 0.2), false)
	# Main stack, raked aft, then the black cap.
	var y1 := -h.y + cas_h
	k.cyl(Vector3(0, y1, rake * 0.2), Vector2(rx * 1.02, rz * 1.02), Vector2(rx * 0.86, rz * 0.86), H * 0.60, 20, col, Vector3(0, 0, rake * 0.6), false)
	var y2 := y1 + H * 0.60
	var z2 := rake * 0.8
	k.cyl(Vector3(0, y2, z2), Vector2(rx * 0.86, rz * 0.86), Vector2(rx * 0.84, rz * 0.84), H * 0.14, 20, pal["cap"], Vector3(0, 0, rake * 0.2), false)
	# Rim and the dark opening.
	var y3 := y2 + H * 0.14
	var z3 := z2 + rake * 0.2
	k.cyl(Vector3(0, y3, z3), Vector2(rx * 0.90, rz * 0.90), Vector2(rx * 0.90, rz * 0.90), 0.12, 20, pal["light"].darkened(0.25), Vector3.ZERO, false)
	k.cyl(Vector3(0, y3 + 0.1, z3), Vector2(rx * 0.74, rz * 0.74), Vector2(rx * 0.74, rz * 0.74), 0.0, 16, Color(0.02, 0.02, 0.02), Vector3.ZERO, true)
	# Steam pipes and a siren on the forward face, and a ladder strip.
	var fz := rz * 0.95
	for sx in [-0.3, 0.3]:
		k.cyl(Vector3(rx * sx, -h.y + cas_h, fz), Vector2(0.12, 0.12), Vector2(0.10, 0.10), H * 0.5, 8, pal["light"].darkened(0.1), Vector3.ZERO, true)
	k.box(Vector3(0, -h.y + cas_h + H * 0.28, rz * 1.03), Vector3(0.12, H * 0.28, 0.04), pal["dark"].lightened(0.1))


# --- Mast ---------------------------------------------------------------------------------------------

static func _mast(k: MeshKit, h: Vector3, L: float, pal: Dictionary) -> void:
	var H := h.y * 2.0
	var base := -h.y
	var steel: Color = pal["steel"]
	var light: Color = pal["light"]
	var dark: Color = pal["dark"]
	var w := maxf(h.x, 0.5)
	if L > 140.0:
		# Lattice tower: four posts tapering to the top with horizontal frames, a fire-control top
		# with its windows, a yard and a radar array.
		var bw := w * 1.5
		var tw := w * 0.8
		var top_y := base + H * 0.80
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				k.strut(Vector3(sx * bw, base, sz * bw), Vector3(sx * tw, top_y, sz * tw), 0.16, steel)
		for f in [0.12, 0.3, 0.48, 0.66]:
			var yy: float = base + H * 0.8 * f
			var ww: float = lerpf(bw, tw, f)
			k.strut(Vector3(-ww, yy, -ww), Vector3(ww, yy, -ww), 0.1, steel.darkened(0.1))
			k.strut(Vector3(-ww, yy, ww), Vector3(ww, yy, ww), 0.1, steel.darkened(0.1))
			k.strut(Vector3(-ww, yy, -ww), Vector3(-ww, yy, ww), 0.1, steel.darkened(0.1))
			k.strut(Vector3(ww, yy, -ww), Vector3(ww, yy, ww), 0.1, steel.darkened(0.1))
			k.strut(Vector3(-ww, yy - H * 0.1, -ww), Vector3(ww, yy, -ww), 0.06, steel.darkened(0.2))
		# Fire-control top.
		var ft := base + H * 0.62
		var fw := bw * 2.3
		k.block(ft, ft + H * 0.09, Rect2(-fw, -fw, fw * 2.0, fw * 2.0), Rect2(-fw * 0.9, -fw * 0.9, fw * 1.8, fw * 1.8), steel.lightened(0.05))
		k.box(Vector3(0, ft + H * 0.045, fw * 0.92), Vector3(fw * 0.8, H * 0.018, 0.05), GLASS)
		k.box(Vector3(0, ft + H * 0.095, 0), Vector3(fw * 0.7, 0.07, fw * 0.7), dark)
		# Yard and top mast.
		k.tube_x(top_y + H * 0.03, 0.0, -bw * 3.5, bw * 3.5, 0.07, 6, light)
		k.strut(Vector3(0, top_y, 0), Vector3(0, base + H, 0), 0.08, light)
		var ry := base + H * 0.9
		k.box(Vector3(0, ry, bw * 0.4), Vector3(bw * 2.4, bw * 0.7, 0.06), dark.lightened(0.2))
		k.strut(Vector3(0, base + H * 0.98, 0), Vector3(0, base + H * 1.04, 0), 0.04, light)
	else:
		# Small ship: a pole mast with a yard, a platform and a whip.
		k.cyl(Vector3(0, base, 0), Vector2(w * 0.6, w * 0.6), Vector2(w * 0.35, w * 0.35), H * 0.85, 8, steel)
		k.tube_x(base + H * 0.62, 0.0, -w * 4.0, w * 4.0, 0.045, 6, light)
		k.box(Vector3(0, base + H * 0.78, 0), Vector3(w * 1.6, 0.06, w * 1.6), dark)
		k.strut(Vector3(0, base + H * 0.85, 0), Vector3(0, base + H * 1.1, 0), 0.04, light)
		k.box(Vector3(0, base + H * 0.9, w * 0.4), Vector3(w * 1.3, w * 0.5, 0.04), dark.lightened(0.2))


# --- AA mounts, torpedo tubes, hangar ---------------------------------------------------------------------

static func _aa(k: MeshKit, h: Vector3, pal: Dictionary) -> void:
	var r := maxf(h.x, h.z)
	var tub_h := h.y * 2.0 * 0.5
	var gun: Color = pal["gun"]
	# Circular gun tub with a rim, pedestal, shield and two barrels.
	k.cyl(Vector3(0, -h.y, 0), Vector2(r, r), Vector2(r * 0.95, r * 0.95), tub_h, 14, pal["deck"], Vector3.ZERO, false)
	k.cyl(Vector3(0, -h.y + tub_h, 0), Vector2(r * 1.02, r * 1.02), Vector2(r * 1.02, r * 1.02), 0.08, 14, pal["light"].darkened(0.3), Vector3.ZERO, false)
	k.cyl(Vector3(0, -h.y, 0), Vector2(r * 0.3, r * 0.3), Vector2(r * 0.25, r * 0.25), tub_h * 1.4, 8, gun)
	var by := -h.y + tub_h * 1.35
	k.box(Vector3(0, by, 0), Vector3(r * 0.32, r * 0.2, r * 0.38), gun.lightened(0.05))
	k.box(Vector3(0, by + r * 0.1, r * 0.48), Vector3(r * 0.55, r * 0.35, 0.04), gun.darkened(0.1))      # shield plate
	for sx in [-0.16, 0.16]:
		k.push(Transform3D(Basis(Vector3.RIGHT, -0.45), Vector3(sx * r, by, r * 0.3)))
		k.tube(0, 0, 0, r * 1.7, 0.06, 0.045, 6, pal["dark"])
		k.pop()
	k.box(Vector3(-r * 0.55, -h.y + tub_h + 0.15, -r * 0.2), Vector3(0.18, 0.15, 0.25), pal["dark"])       # ready-use lockers


static func _tubes(k: MeshKit, h: Vector3, pal: Dictionary) -> void:
	var gun: Color = pal["gun"]
	var base := -h.y
	k.cyl(Vector3(0, base, 0), Vector2(h.x * 0.7, h.x * 0.7), Vector2(h.x * 0.6, h.x * 0.6), h.y * 0.5, 12, pal["deck"], Vector3.ZERO, true)
	var r := minf(h.x * 0.34, 0.33)
	var n := 2
	for row in 2:
		for i in n:
			var x := (float(i) - 0.5) * r * 2.3
			var y := base + h.y * 0.55 + row * r * 2.0
			k.tube(x, y, -h.z * 0.95, h.z * 0.95, r, r, 10, gun)
			k.tube(x, y, h.z * 0.8, h.z * 0.98, r * 1.05, r * 1.05, 10, pal["dark"].lightened(0.25))       # warhead ring
	k.box(Vector3(0, base + h.y * 0.5, 0), Vector3(h.x * 0.9, 0.08, h.z * 0.75), pal["dark"])


static func _hangar(k: MeshKit, h: Vector3, pal: Dictionary) -> void:
	var steel: Color = pal["steel"]
	k.box(Vector3(0, -h.y * 0.1, 0), Vector3(h.x, h.y * 0.9, h.z), steel, steel.lightened(0.05))
	# Doors, a roof casing and a crane with a seaplane on the catapult.
	for sx in [-1.0, 1.0]:
		for i in 3:
			k.box(Vector3(sx * (h.x + 0.02), -h.y * 0.2, (float(i) - 1.0) * h.z * 0.6), Vector3(0.04, h.y * 0.6, h.z * 0.26), pal["dark"].lightened(0.1))
	k.box(Vector3(0, h.y * 0.95, 0), Vector3(h.x * 0.6, h.y * 0.15, h.z * 0.7), steel.darkened(0.08))
	var py := h.y * 1.05
	var wl := h.x * 1.5
	k.tube(0, py + 0.9, -h.z * 0.6, h.z * 0.55, 0.35, 0.28, 8, pal["light"].darkened(0.1))        # fuselage
	k.box(Vector3(0, py + 1.0, h.z * 0.15), Vector3(wl, 0.05, 0.9), pal["light"].darkened(0.15))   # wing
	k.box(Vector3(0, py + 1.2, -h.z * 0.6), Vector3(wl * 0.4, 0.04, 0.4), pal["light"].darkened(0.15))
	k.box(Vector3(0, py + 1.5, -h.z * 0.6), Vector3(0.03, 0.4, 0.4), pal["light"].darkened(0.15))
	k.tube(0, py + 0.35, -h.z * 0.4, h.z * 0.4, 0.22, 0.2, 8, pal["dark"])                          # float
	k.strut(Vector3(0, py, -h.z * 0.2), Vector3(0, py + 0.9, -h.z * 0.2), 0.06, pal["dark"])
	k.strut(Vector3(0, py, h.z * 0.3), Vector3(0, py + 0.9, h.z * 0.3), 0.06, pal["dark"])
