class_name ShipBuilder
extends RefCounted
## Builds a ship's compartments from its roster entry, in the standard ShipFrame
## (origin midships/centerline/waterline, +Z bow, +X port, +Y up).
##
## Everything is placed by deck and station, so a destroyer's bridge sits on its own small
## deck stack rather than at a fixed height, and sizes scale with the ship (turrets with gun
## caliber, funnels and masts with length). Spaces are placed in a fixed order of priority
## (magazines and machinery first, then superstructure, then fittings) and nudged along the
## keel until they clear anything already placed. ShipLayoutCheck verifies the result.

const STRUCTURAL := [Compartment.Kind.HULL_SECTION, Compartment.Kind.BOW, Compartment.Kind.STERN]


static func build(e: Dictionary) -> Array[Compartment]:
	var out: Array[Compartment] = []
	var f := ShipFrame.for_entry(e)
	var L := f.length
	var B := f.beam
	var D := f.draft
	var armor: Dictionary = e.get("armor", {})
	var belt: float = armor.get("belt_mm", 0.0)
	var deck_mm: float = armor.get("deck_mm", 0.0)
	var turret_armor: float = armor.get("turret_mm", 0.0)
	var cit: float = armor.get("citadel_mm", belt)
	var scale: float = e["displacement_t"] / 1000.0
	var gun: Dictionary = e.get("main_gun", {})
	var cal: float = gun.get("caliber_mm", 100.0)

	# --- 1. Hull: structural sections keel to weather deck, port and starboard ---------------
	var n_sections: int = clampi(int(L / 18.0), 4, 14)
	var sec_len := L / n_sections
	for i in n_sections:
		var z0 := -L * 0.5 + sec_len * i
		var zc := z0 + sec_len * 0.5
		var hbz := f.half_breadth(zc)
		var in_citadel := absf(zc) < L * 0.3
		for side in [1, -1]:                     # +1 = port (+X), -1 = starboard
			var sp := f.space(z0, z0 + sec_len, "keel", "main", side * hbz * 0.5, hbz)
			var c := Compartment.new("hull_%d_%s" % [i, _side_id(side)], Compartment.Kind.HULL_SECTION,
				120.0 * pow(scale, 0.8), sp["center"], sp["half"])
			c.armor_mm = cit if in_citadel else belt * 0.1
			c.below_waterline = true
			c.capacity_tonnes = (hbz * D * sec_len * 0.8) * Ship.WATER_DENSITY
			out.append(c)
	for end in [1, -1]:
		var ez: float = end * (L * 0.5 - 6.0)
		var sp := f.space_at(ez, 12.0, "keel", "main", 0.0, f.half_breadth(ez) * 1.8)
		var kind := Compartment.Kind.BOW if end > 0 else Compartment.Kind.STERN
		var cap := Compartment.new("bow" if end > 0 else "stern", kind, 90.0 * pow(scale, 0.8), sp["center"], sp["half"])
		cap.below_waterline = true
		cap.capacity_tonnes = 200.0
		out.append(cap)

	# --- 2. Gun turrets and the magazines beneath them (slots reserved first) -----------------
	var turret_fracs: Array = e.get("turret_z", [])
	var turret_hp: float = e.get("turret_hp", 120.0)
	var shell_kg: float = e.get("shell_kg_per_turret", 400.0)
	var t_half_w := clampf(cal * 0.0095 + 0.5, 1.0, 6.0)
	var t_half_l := t_half_w * 1.1
	var t_height := clampf(2.2 + cal * 0.006, 2.4, 5.2)
	var raised: Array[bool] = []
	var mag_slots: Array = []
	for i in turret_fracs.size():
		var tz := f.z_frac(turret_fracs[i])
		var hw := minf(t_half_w, f.half_breadth(tz) - 0.5)
		# Superfiring: a turret close behind/ahead of another at the same end sits one deck higher.
		var up := false
		for j in i:
			if not raised[j] and signf(turret_fracs[j]) == signf(turret_fracs[i]) \
					and absf(f.z_frac(turret_fracs[j]) - tz) < t_half_l * 2.0 * 3.2:
				up = true
		raised.append(up)
		var top_y: float = f.deck("d01") + t_height if up else f.deck("main") + t_height
		var tsp := f.space_at(tz, t_half_l * 2.0, "main", top_y, 0.0, hw * 2.0)
		var t := Compartment.new("turret_%d" % i, Compartment.Kind.TURRET, turret_hp, tsp["center"], tsp["half"])
		t.armor_mm = turret_armor
		out.append(t)
		var mz_c := clampf(tz, -L * 0.5 + 11.0 + t_half_l, L * 0.5 - 8.0 - t_half_l)
		var msp := f.space_at(mz_c, t_half_l * 2.1, "inner_bottom", "platform", 0.0, hw * 2.6)
		var mag := Compartment.new("magazine_%d" % i, Compartment.Kind.MAGAZINE, turret_hp * 2.0, msp["center"], msp["half"])
		mag.armor_mm = maxf(deck_mm, cit * 0.5)
		mag.ammo_stored = shell_kg
		mag.below_waterline = true
		mag.capacity_tonnes = 70.0
		out.append(mag)
		mag_slots.append([mz_c - t_half_l * 1.05 - 1.5, mz_c + t_half_l * 1.05 + 1.5])

	# --- 3. Machinery block: the largest clear stretch of keel near midships ------------------
	mag_slots.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var lim_lo := -L * 0.5 + maxf(L * 0.12, 9.0)
	var lim_hi := L * 0.5 - L * 0.14
	var free: Array = []
	var cursor := lim_lo
	for r in mag_slots:
		if r[0] > cursor:
			free.append([cursor, minf(r[0], lim_hi)])
		cursor = maxf(cursor, r[1])
	if cursor < lim_hi:
		free.append([cursor, lim_hi])
	var mz0 := -L * 0.19
	var mz1 := L * 0.19
	var best := -1e9
	for iv in free:
		var span: float = iv[1] - iv[0]
		if span <= 4.0:
			continue
		var score: float = span - absf((iv[0] + iv[1]) * 0.5) * 0.5
		if score > best:
			best = score
			mz0 = iv[0]
			mz1 = iv[1]
	var max_span := L * 0.42
	if mz1 - mz0 > max_span:
		var mid := (mz0 + mz1) * 0.5
		mz0 = mid - max_span * 0.5
		mz1 = mid + max_span * 0.5
	var n_boil: int = e.get("boiler_rooms", 2)
	var n_eng: int = e.get("engine_rooms", 2)
	var n_mach := maxi(n_boil + n_eng, 1)
	var room_len := (mz1 - mz0) / n_mach
	var mach_top: float = f.freeboard * 0.4
	for i in n_mach:
		var rz := mz0 + room_len * (i + 0.5)
		var is_boiler := i % 2 == 0 and i / 2 < n_boil
		var kind := Compartment.Kind.BOILER_ROOM if is_boiler else Compartment.Kind.ENGINE_ROOM
		var hbz := f.half_breadth(rz)
		var sp := f.space_at(rz, room_len, "inner_bottom", mach_top, 0.0, hbz * 1.24)
		var m := Compartment.new("%s_%d" % ["boiler" if is_boiler else "engine", i], kind,
			150.0 * pow(scale, 0.7), sp["center"], sp["half"])
		m.armor_mm = deck_mm
		m.below_waterline = true
		m.capacity_tonnes = 160.0
		out.append(m)
	var mz_mid := (mz0 + mz1) * 0.5
	var hb_m := f.half_breadth(mz_mid)
	for side in [1, -1]:
		var fsp := f.space(mz0, mz1, "inner_bottom", "waterline", side * hb_m * 0.81, hb_m * 0.34)
		var ft := Compartment.new("fuel_%s" % _side_id(side), Compartment.Kind.FUEL_TANK, 80.0 * pow(scale, 0.6), fsp["center"], fsp["half"])
		ft.below_waterline = true
		ft.capacity_tonnes = 90.0
		ft.ammo_stored = 150.0       # fuel vapour: only goes up if the tank is burning
		out.append(ft)

	# --- 4. Superstructure: bridge tower, mast, funnels ---------------------------------------
	var bridge_top := "d04" if L > 180.0 else ("d03" if L > 90.0 else "d02")
	var b_len := clampf(L * 0.055, 3.5, 18.0)
	var b_width := clampf(B * 0.38, 2.0, 14.0)
	var bz: float = e.get("bridge_z", 0.15) * L
	bz = _find_z(out, f, bz, b_len, "main", bridge_top, 0.0, b_width, L * 0.3, 1.0)
	var bsp := f.space_at(bz, b_len, "main", bridge_top, 0.0, b_width)
	out.append(_comp("bridge", Compartment.Kind.BRIDGE, 100.0, bsp, cit * 0.2))
	var mast_h := clampf(L * 0.11, 5.0, 32.0)
	var mast_w := clampf(L * 0.006, 0.8, 2.0)
	var msp2 := f.space_at(bz - b_len * 0.15, mast_w, bridge_top, f.deck(bridge_top) + mast_h, 0.0, mast_w)
	out.append(_comp("mast", Compartment.Kind.MAST, 30.0, msp2, 0.0))

	var n_fun: int = e.get("funnels", 1)
	var f_len := clampf(L * 0.035, 3.0, 10.0)
	var f_width := minf(B * 0.3, f_len * 0.85)
	var f_height := clampf(L * 0.05, 4.5, 15.0)
	var f_spacing := f_len * 2.6
	for i in n_fun:
		var fz := mz_mid + (i - (n_fun - 1) * 0.5) * f_spacing
		fz = _find_z(out, f, fz, f_len, "main", f.deck("main") + f_height, 0.0, f_width, L * 0.3, 1.0)
		var fsp := f.space_at(fz, f_len, "main", f.deck("main") + f_height, 0.0, f_width)
		out.append(_comp("funnel_%d" % i, Compartment.Kind.FUNNEL, 40.0, fsp, 0.0))

	if e.get("hangar", false):
		var h_width := clampf(B * 0.5, 4.0, 14.0)
		var h_len := clampf(L * 0.09, 8.0, 26.0)
		var hz := -L * 0.25
		for shrink in [1.0, 0.75, 0.55]:
			var try_len: float = h_len * shrink
			hz = _find_z(out, f, -L * 0.25, try_len, "main", "d01", 0.0, h_width, L * 0.4, 1.0)
			var tsp3 := f.space_at(hz, try_len, "main", "d01", 0.0, h_width)
			if not _blocked(out, tsp3["center"], tsp3["half"], 1.0):
				h_len = try_len
				break
		var hsp := f.space_at(hz, h_len, "main", "d01", 0.0, h_width)
		var hg := _comp("hangar", Compartment.Kind.HANGAR, 120.0 * pow(scale, 0.6), hsp, 0.0)
		hg.ammo_stored = 80.0
		out.append(hg)

	# --- 5. Fittings: secondary and AA mounts, torpedo tubes ----------------------------------
	var small := L < 60.0
	var mount := 1.8 if small else 3.0              # secondary mount footprint
	var aa_size := 1.6 if small else 2.4
	if e.get("torpedo_tubes", 0) > 0:
		var t_w := 1.8 if small else 2.6
		for side in [1, -1]:
			var xt: float = side * minf(f.half_breadth(0.0) * 0.5, maxf(f.half_breadth(0.0) - t_w * 0.5 - 0.6, 0.0))
			var t_len := clampf(L * 0.06, 3.0, 7.0)
			var tz2 := _find_z(out, f, -L * 0.05, t_len, "main", f.deck("main") + 2.2, xt, t_w, L * 0.4, 1.0)
			xt = side * minf(f.half_breadth(tz2) * 0.5, maxf(f.half_breadth(tz2) - t_w * 0.5 - 0.6, 0.0))
			var tsp2 := f.space_at(tz2, t_len, "main", f.deck("main") + 2.2, xt, t_w)
			var tt := _comp("tubes_%s" % _side_id(side), Compartment.Kind.TORPEDO_TUBES, 45.0, tsp2, 0.0)
			tt.ammo_stored = 300.0   # warhead mass: tubes can cook off
			out.append(tt)
	var n_sec: int = e.get("secondary_mounts", 0)
	for i in n_sec:
		var side := 1 if i % 2 == 0 else -1
		var sz := lerpf(-L * 0.25, L * 0.25, float(i) / maxf(n_sec - 1, 1))
		var xs: float = side * maxf(f.half_breadth(sz) - mount * 0.5 - 0.6, 0.0)
		sz = _find_z(out, f, sz, mount, "main", f.deck("main") + 2.4, xs, mount, L * 0.4, 1.0)
		xs = side * maxf(f.half_breadth(sz) - mount * 0.5 - 0.6, 0.0)
		var ssp := f.space_at(sz, mount, "main", f.deck("main") + 2.4, xs, mount)
		out.append(_comp("secondary_%d" % i, Compartment.Kind.SECONDARY_MOUNT, 35.0, ssp, 0.0))
	var n_aa: int = e.get("aa_mounts", 4)
	for i in n_aa:
		var side := -1 if i % 2 == 0 else 1
		var az := lerpf(-L * 0.3, L * 0.3, float(i) / maxf(n_aa - 1, 1))
		var xa: float = side * minf(f.half_breadth(az) * 0.62, maxf(f.half_breadth(az) - aa_size * 0.5 - 0.6, 0.0))
		az = _find_z(out, f, az, aa_size, "main", f.deck("main") + 2.0, xa, aa_size, L * 0.45, 0.6)
		xa = side * minf(f.half_breadth(az) * 0.62, maxf(f.half_breadth(az) - aa_size * 0.5 - 0.6, 0.0))
		var asp := f.space_at(az, aa_size, "main", f.deck("main") + 2.0, xa, aa_size)
		out.append(_comp("aa_%d" % i, Compartment.Kind.AA_MOUNT, 20.0, asp, 0.0))

	# --- 6. Steering and propulsion hardware aft ----------------------------------------------
	var stern_z := -L * 0.5
	var st_len := clampf(L * 0.035, 2.0, 5.0)
	var ssp2 := f.space_at(stern_z + 4.4 + st_len * 0.5, st_len, "inner_bottom", "waterline", 0.0, minf(5.0, B * 0.4))
	var steer := _comp("steering_gear", Compartment.Kind.STEERING_GEAR, 60.0, ssp2, deck_mm)
	steer.below_waterline = true
	out.append(steer)
	var hb_a := f.half_breadth(stern_z + 2.0)
	var n_rud: int = e.get("rudders", 1)
	for i in n_rud:
		var rx := 0.0 if n_rud == 1 else lerpf(-hb_a * 0.4, hb_a * 0.4, float(i) / (n_rud - 1))
		var rsp := f.space_at(stern_z + 1.5, 3.0, -D, -D * 0.35, rx, 0.8)
		var r := _comp("rudder_%d" % i, Compartment.Kind.RUDDER, 50.0, rsp, 0.0)
		r.below_waterline = true
		out.append(r)
	var n_screw: int = e.get("screws", 2)
	var screw_w := 1.2
	var span := minf(hb_a * 0.9 - screw_w * 0.5, hb_a * 0.55 + (n_screw - 2) * 0.6)
	for i in n_screw:
		var sx := 0.0 if n_screw == 1 else lerpf(-span, span, float(i) / (n_screw - 1))
		var scsp := f.space_at(stern_z + 2.5, 2.5, -D, -D * 0.5, sx, screw_w)
		var s := _comp("screw_%d" % i, Compartment.Kind.SCREW, 45.0, scsp, 0.0)
		s.below_waterline = true
		out.append(s)
	return out


static func _side_id(side: int) -> String:
	return "p" if side > 0 else "s"


static func _comp(id: String, kind: Compartment.Kind, hp: float, sp: Dictionary, armor: float) -> Compartment:
	var c := Compartment.new(id, kind, hp, sp["center"], sp["half"])
	c.armor_mm = armor
	return c


## True if the box (center, half) intersects any non-structural compartment already placed.
static func _blocked(out: Array[Compartment], center: Vector3, half: Vector3, margin: float) -> bool:
	for c in out:
		if c.kind in STRUCTURAL:
			continue
		var d := (center - c.center).abs()
		var reach := half + c.half_extents + Vector3(margin, margin, margin)
		if d.x < reach.x and d.y < reach.y and d.z < reach.z:
			return true
	return false


## Nudges a space along the keel (alternating forward/aft) until it clears everything placed so far.
## Returns the original z if nothing within `search` metres is clear.
static func _find_z(out: Array[Compartment], f: ShipFrame, z: float, length_m: float, lo, hi, x: float,
		width: float, search: float, margin: float) -> float:
	var step := maxf(length_m * 0.5, 1.0)
	var k := 0
	while k * step <= search:
		var signs: Array = [1.0] if k == 0 else [1.0, -1.0]
		for sgn in signs:
			var zz: float = z + float(sgn) * k * step
			if absf(zz) > f.length * 0.5 - length_m * 0.5:
				continue
			var sp := f.space_at(zz, length_m, lo, hi, x, width)
			if not _blocked(out, sp["center"], sp["half"], margin):
				return zz
		k += 1
	return z
