class_name ShipBuilder
extends RefCounted
## Builds the compartment list for a ship from its roster entry.
## Layout is generated procedurally along the keel so every class gets a distinct,
## plausible internal arrangement driven by its data (turret positions, number of
## boiler/engine rooms, armour scheme, etc).

static func build(e: Dictionary) -> Array[Compartment]:
	var out: Array[Compartment] = []
	var L: float = e["length_m"]
	var B: float = e["beam_m"]
	var D: float = e["draft_m"]
	var hb := B * 0.5
	var armor: Dictionary = e.get("armor", {})
	var belt: float = armor.get("belt_mm", 0.0)
	var deck: float = armor.get("deck_mm", 0.0)
	var turret_armor: float = armor.get("turret_mm", 0.0)
	var cit: float = armor.get("citadel_mm", belt)
	var scale: float = e["displacement_t"] / 1000.0   # hp scale

	# Hull sections (the structural backbone). Port/starboard pairs along the keel.
	var n_sections: int = clampi(int(L / 18.0), 4, 14)
	var sec_len := L / n_sections
	for i in n_sections:
		var z := -L * 0.5 + sec_len * (i + 0.5)
		var in_citadel := absf(z) < L * 0.3
		for side in [-1, 1]:
			var c := Compartment.new("hull_%d_%s" % [i, "s" if side > 0 else "p"],
				Compartment.Kind.HULL_SECTION, 120.0 * pow(scale, 0.8),
				Vector3(side * hb * 0.5, -D * 0.4, z), Vector3(hb * 0.5, D * 0.6, sec_len * 0.5))
			c.armor_mm = cit if in_citadel else belt * 0.1
			c.below_waterline = true
			c.capacity_tonnes = (hb * D * sec_len * 0.8) * Ship.WATER_DENSITY
			out.append(c)

	# Bow and stern ends.
	var bow := Compartment.new("bow", Compartment.Kind.BOW, 90.0 * pow(scale, 0.8),
		Vector3(0, -D * 0.3, L * 0.5 - 6.0), Vector3(hb * 0.6, D * 0.7, 6.0))
	bow.below_waterline = true
	bow.capacity_tonnes = 200.0
	out.append(bow)
	var stern := Compartment.new("stern", Compartment.Kind.STERN, 90.0 * pow(scale, 0.8),
		Vector3(0, -D * 0.3, -L * 0.5 + 6.0), Vector3(hb * 0.7, D * 0.7, 6.0))
	stern.below_waterline = true
	stern.capacity_tonnes = 200.0
	out.append(stern)

	# Machinery: boiler rooms and engine rooms alternate amidships.
	var n_boil: int = e.get("boiler_rooms", 2)
	var n_eng: int = e.get("engine_rooms", 2)
	var n_mach := n_boil + n_eng
	var mach_span := L * 0.38
	for i in n_mach:
		var z := -mach_span * 0.5 + mach_span * (i + 0.5) / n_mach
		var is_boiler := i % 2 == 0 and i / 2 < n_boil
		var kind := Compartment.Kind.BOILER_ROOM if is_boiler else Compartment.Kind.ENGINE_ROOM
		var m := Compartment.new("%s_%d" % ["boiler" if is_boiler else "engine", i], kind,
			150.0 * pow(scale, 0.7), Vector3(0, -D * 0.2, z), Vector3(hb * 0.8, D * 0.5, mach_span / n_mach * 0.5))
		m.armor_mm = deck
		m.below_waterline = true
		m.capacity_tonnes = 160.0
		out.append(m)

	# Fuel tanks flank the machinery.
	for side in [-1, 1]:
		var f := Compartment.new("fuel_%s" % ("s" if side > 0 else "p"), Compartment.Kind.FUEL_TANK,
			80.0 * pow(scale, 0.6), Vector3(side * hb * 0.85, -D * 0.5, 0), Vector3(hb * 0.15, D * 0.4, mach_span * 0.5))
		f.below_waterline = true
		f.capacity_tonnes = 90.0
		f.ammo_stored = 150.0 # fuel vapour: only goes up if the tank is burning
		out.append(f)

	# Main gun turrets, each with a magazine/handling room directly beneath.
	var turret_z: Array = e.get("turret_z", [])
	var turret_hp: float = e.get("turret_hp", 120.0)
	var shell_kg: float = e.get("shell_kg_per_turret", 400.0)
	for i in turret_z.size():
		var tz: float = turret_z[i] * L
		var t := Compartment.new("turret_%d" % i, Compartment.Kind.TURRET, turret_hp,
			Vector3(0, 4.0, tz), Vector3(3.5, 2.0, 4.0))
		t.armor_mm = turret_armor
		out.append(t)
		var mag := Compartment.new("magazine_%d" % i, Compartment.Kind.MAGAZINE, turret_hp * 2.0,
			Vector3(0, -D * 0.5, tz), Vector3(4.0, D * 0.35, 4.5))
		mag.armor_mm = maxf(deck, cit * 0.5)
		mag.ammo_stored = shell_kg
		mag.below_waterline = true
		mag.capacity_tonnes = 70.0
		out.append(mag)

	# Secondary and AA mounts distributed along the sides.
	var n_sec: int = e.get("secondary_mounts", 0)
	for i in n_sec:
		var sz := lerpf(-L * 0.25, L * 0.25, float(i) / maxf(n_sec - 1, 1))
		var side := -1 if i % 2 == 0 else 1
		out.append(Compartment.new("secondary_%d" % i, Compartment.Kind.SECONDARY_MOUNT, 35.0,
			Vector3(side * hb * 0.7, 3.5, sz), Vector3(1.5, 1.2, 1.5)))
	var n_aa: int = e.get("aa_mounts", 4)
	for i in n_aa:
		var az := lerpf(-L * 0.3, L * 0.3, float(i) / maxf(n_aa - 1, 1))
		var side := 1 if i % 2 == 0 else -1
		out.append(Compartment.new("aa_%d" % i, Compartment.Kind.AA_MOUNT, 20.0,
			Vector3(side * hb * 0.6, 6.0, az), Vector3(1.2, 1.0, 1.2)))

	# Torpedo tubes.
	if e.get("torpedo_tubes", 0) > 0:
		for side in [-1, 1]:
			var tt := Compartment.new("tubes_%s" % ("s" if side > 0 else "p"), Compartment.Kind.TORPEDO_TUBES, 45.0,
				Vector3(side * hb * 0.6, 4.0, -L * 0.05), Vector3(1.5, 1.0, 4.0))
			tt.ammo_stored = 300.0 # warhead mass: tubes can cook off
			out.append(tt)

	# Superstructure: bridge, funnels, mast.
	var bridge_z: float = e.get("bridge_z", 0.15) * L
	out.append(_make("bridge", Compartment.Kind.BRIDGE, 100.0, Vector3(0, 9.0, bridge_z), Vector3(4.0, 3.0, 4.0), cit * 0.2))
	var n_fun: int = e.get("funnels", 1)
	for i in n_fun:
		var fz := lerpf(-L * 0.12, L * 0.12, float(i) / maxf(n_fun - 1, 1))
		out.append(_make("funnel_%d" % i, Compartment.Kind.FUNNEL, 40.0, Vector3(0, 9.0, fz), Vector3(2.0, 4.0, 3.0), 0.0))
	out.append(_make("mast", Compartment.Kind.MAST, 30.0, Vector3(0, 14.0, bridge_z), Vector3(0.8, 6.0, 0.8), 0.0))

	if e.get("hangar", false):
		var h := _make("hangar", Compartment.Kind.HANGAR, 120.0 * pow(scale, 0.6), Vector3(0, 6.0, -L * 0.25), Vector3(hb * 0.8, 3.0, 12.0), 0.0)
		h.ammo_stored = 80.0
		out.append(h)

	# Steering and propulsion hardware aft.
	var steer := _make("steering_gear", Compartment.Kind.STEERING_GEAR, 60.0, Vector3(0, -D * 0.4, -L * 0.45), Vector3(2.5, D * 0.4, 2.5), deck)
	steer.below_waterline = true
	out.append(steer)
	var n_rud: int = e.get("rudders", 1)
	for i in n_rud:
		var rx := 0.0 if n_rud == 1 else lerpf(-hb * 0.4, hb * 0.4, float(i) / (n_rud - 1))
		var r := _make("rudder_%d" % i, Compartment.Kind.RUDDER, 50.0, Vector3(rx, -D * 0.7, -L * 0.5 + 1.5), Vector3(0.4, D * 0.5, 1.5), 0.0)
		r.below_waterline = true
		out.append(r)
	var n_screw: int = e.get("screws", 2)
	for i in n_screw:
		var sx := 0.0 if n_screw == 1 else lerpf(-hb * 0.55, hb * 0.55, float(i) / (n_screw - 1))
		var s := _make("screw_%d" % i, Compartment.Kind.SCREW, 45.0, Vector3(sx, -D * 0.8, -L * 0.5 + 3.0), Vector3(0.9, 1.5, 1.5), 0.0)
		s.below_waterline = true
		out.append(s)
	return out


static func _make(id: String, kind: Compartment.Kind, hp: float, center: Vector3, half: Vector3, armor: float) -> Compartment:
	var c := Compartment.new(id, kind, hp, center, half)
	c.armor_mm = armor
	return c
