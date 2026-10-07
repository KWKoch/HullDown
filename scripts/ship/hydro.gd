class_name Hydro
extends RefCounted
## How a hull actually moves through water. Replaces "speed chases throttle, heading chases rudder".
##
##  * Surge: propeller thrust against hull resistance, F = m a. Thrust falls as the ship speeds up (a
##    propeller at constant power), resistance rises with speed squared plus a wave-making hump
##    near Froude 0.4, a shallow-water penalty and a turning/rudder penalty. Top speed, acceleration,
##    coasting and crash-stops all come out of that, with the ship's real mass behind them.
##  * Steerage way: a rudder only works on water flowing past it, from the ship's own speed or from
##    the propeller race while the engines push ahead. Stopped with engines stopped there is no
##    steering at all; going astern the rudder is in dead water.
##  * Yaw and drift: the turn rate builds and decays with a hull time constant, so the ship keeps
##    swinging after the rudder is centred, and the hull slides sideways in a turn (drift angle).
##  * Roll and pitch: second-order oscillators driven by the turn (centrifugal heel), the swell
##    (encounter frequency, so beam seas and resonance matter), and the recoil of your own broadsides.
##  * Shallow water: resistance and squat rise as the keel nears the bottom, so a fast ship in shoal
##    water slows, settles by the stern and can touch where she would clear at rest.
##
## Units: real ship metres and seconds (the 2x visual WORLD_SCALE is divided out for depth).

const G := 9.81
const TIME_COMPRESSION := 3.0      ## game-time: inertia divided by this so ships answer in seconds, not minutes
const PROP_A := 0.6                ## how fast thrust falls off with advance speed
const ADMIRALTY_C := 190.0
const PROP_EFF := 0.65
const SWELL_DIR := 0.6             ## heading (rad, 0 = +Z, + toward +X) the swell travels toward

var ship: Ship

# state
var v := 0.0                       ## sway m/s, + to starboard (the outside of a port turn)
var r := 0.0                       ## yaw rate rad/s, + = turning to port (heading increasing)
var roll := 0.0                    ## rad, + = starboard side down
var roll_rate := 0.0
var pitch := 0.0                   ## rad, + = bow down
var pitch_rate := 0.0

# outputs the HUD / gunnery / wake read
var steerage := 1.0                ## 0..1 rudder authority right now
var rudder_flow := 0.0             ## m/s of water over the rudders
var froude := 0.0
var depth_world := 1.0e9           ## water under the keel at the shallowest of bow/mid/stern, world m
var depth_froude := 0.0            ## speed over sqrt(g * depth): 1.0 is the critical speed in shallow water
var shallow := 0.0                 ## 0..1 shallow-water effect strength
var squat_world := 0.0             ## extra draft at speed, world m
var thrust_n := 0.0
var resist_n := 0.0
var drag_mult := 1.0
var prop_wash := 0.0               ## 0..1 propeller race strength (wake visuals)

# constants fixed at setup
var mass_kg := 1.0
var t_max := 1.0                   ## thrust at full power and top speed (= resistance there)
var t0 := 1.0                      ## bollard-pull scale
var k_drag := 1.0
var roll_period := 9.0
var roll_zeta := 0.1
var heel_k := 1.0
var pitch_period := 6.0
var gun_stab := 0.7                ## 0 = guns follow the deck, 1 = perfectly stabilised
var _t := 0.0
var _phase := randf() * TAU


static func _wave_factor(fn: float) -> float:
	var x := (fn - 0.42) / 0.12
	return 1.0 + 0.4 * exp(-x * x)


func setup(p_ship: Ship) -> void:
	ship = p_ship
	var L := ship.length_m
	var vmax := maxf(ship.max_speed_ms, 1.0)
	var shp := pow(ship.displacement_t, 2.0 / 3.0) * pow(vmax / 0.5144, 3.0) / ADMIRALTY_C
	t_max = shp * 745.7 * PROP_EFF / vmax
	t0 = t_max / (1.0 - PROP_A)
	var fn_max := vmax / sqrt(G * L)
	k_drag = t_max / (vmax * vmax * _wave_factor(fn_max))
	mass_kg = ship.displacement_t * 1000.0 * 1.08
	match ship.ship_type:
		"destroyer", "escort", "motor_torpedo_boat":
			roll_period = 7.0; roll_zeta = 0.12; heel_k = 1.25
		"light_cruiser", "heavy_cruiser":
			roll_period = 10.0; roll_zeta = 0.10; heel_k = 1.0
		"battleship", "battlecruiser":
			roll_period = 13.0; roll_zeta = 0.08; heel_k = 0.75
		"carrier":
			roll_period = 12.0; roll_zeta = 0.09; heel_k = 0.9
		_:
			roll_period = 9.0; roll_zeta = 0.1; heel_k = 1.0
	pitch_period = clampf(L / 22.0, 4.0, 11.0)
	var base := 0.55
	match ship.ship_type:
		"battleship", "battlecruiser": base = 0.85
		"heavy_cruiser", "light_cruiser": base = 0.78
		"destroyer": base = 0.6
		"carrier": base = 0.5
		_: base = 0.4
	var nat := 1.0
	match ship.nation:
		"USA": nat = 1.0
		"United Kingdom", "Germany": nat = 0.94
		"Japan": nat = 0.86
		"Italy", "France": nat = 0.8
		"USSR": nat = 0.7
	gun_stab = clampf(base * nat, 0.2, 0.95)


## Advance the hull one physics step. Reads and writes ship.speed_ms, heading and sway.
func step(delta: float) -> void:
	_t += delta
	var L := ship.length_m
	var vmax := maxf(ship.max_speed_ms, 1.0)
	var u := ship.speed_ms
	var thr := ship.throttle
	var pf := ship.propulsion_fraction()
	var flood := ship.flood_ratio()

	# --- Shallow water ----------------------------------------------------------------------
	var h_real := maxf(depth_world / Ship.WORLD_SCALE, 0.5)
	var t_real := maxf(ship.draft_m, 0.5)
	var ht := h_real / t_real
	var s_h := clampf((3.5 - ht) / 2.3, 0.0, 1.0)
	var fh := absf(u) / sqrt(G * h_real)
	depth_froude = fh
	shallow = s_h * (0.35 + 0.65 * smoothstep(0.25, 0.85, fh))
	var fh_c := minf(fh, 0.7)
	var vol := ship.displacement_t / 1.025
	var squat_real := clampf(2.4 * vol / (L * L) * fh_c * fh_c / sqrt(1.0 - fh_c * fh_c), 0.0, 3.0) * (0.15 + 0.85 * s_h)
	squat_world = squat_real * Ship.WORLD_SCALE
	var shallow_drag := 1.0 + 1.6 * shallow + 0.7 * s_h * exp(-pow((fh - 0.95) / 0.15, 2.0))

	# --- Rudder flow and steerage way -------------------------------------------------------
	var wash := 0.0
	var sgn := 1.0
	var ur: float
	if u >= -0.2:
		wash = 0.40 * vmax * maxf(thr, 0.0) * sqrt(pf)
		var x_ahead := clampf(u / vmax, 0.0, 1.0)
		ur = sqrt(maxf(u, 0.0) * maxf(u, 0.0) + wash * wash * (1.0 - 0.7 * x_ahead))
	else:
		ur = absf(u) * 0.45
		sgn = -1.0
	rudder_flow = ur
	steerage = smoothstep(0.0, 0.22 * vmax, ur) * (1.0 - 0.3 * s_h)
	prop_wash = clampf(absf(thr) * sqrt(pf), 0.0, 1.0)

	# --- Yaw: first-order hull response (Nomoto) --------------------------------------------
	var delta_r := ship.rudder * ship.steering_fraction() * (1.0 - 0.3 * s_h)
	var n_flow := (ur * ur) / (vmax * maxf(absf(u), 0.28 * vmax))
	var r_ss := ship.turn_rate_rad * delta_r * sgn * minf(n_flow, 1.05) * ship.handling_fraction()
	var t_n := clampf(1.4 * L / maxf(maxf(ur, absf(u)), 3.0), 3.0, 35.0) * (1.0 + 0.8 * flood)
	r += (r_ss - r) / t_n * delta
	ship.heading += r * delta

	# --- Sway / drift: the hull slides outward in a turn ------------------------------------
	var v_target := 0.22 * r * L * (signf(u) if absf(u) > 0.3 else 1.0)
	v += (v_target - v) / (0.6 * t_n + 1.0) * delta

	# --- Surge: thrust vs resistance --------------------------------------------------------
	var x := u / vmax
	var s := signf(thr)
	var ahead_f := 1.0 if thr >= 0.0 else 0.25           # astern turbines are a fraction of ahead power
	var thr_mag := absf(thr) if thr >= 0.0 else minf(absf(thr) / 0.3, 1.0)
	thrust_n = s * t0 * pf * ahead_f * (thr_mag * thr_mag - PROP_A * thr_mag * (x * s))
	var rr := absf(r) * L / maxf(absf(u), 1.0)
	var turn_pen := 1.0 + 1.0 * minf(rr, 1.5) * minf(rr, 1.5) + 0.15 * delta_r * delta_r \
			+ 3.0 * pow(v / maxf(absf(u), 2.0), 2.0)
	var prop_drag := 1.0 + 0.25 * (1.0 - clampf(absf(thr) / 0.2, 0.0, 1.0))
	var list_pen := 1.0 + 0.5 * clampf(absf(ship.list_rad) / 0.4, 0.0, 1.0)
	drag_mult = shallow_drag * turn_pen * prop_drag * list_pen * (1.0 + 0.6 * flood)
	var fn := absf(u) / sqrt(G * L)
	froude = fn
	resist_n = k_drag * _wave_factor(fn) * drag_mult * u * absf(u)
	var m_eff := mass_kg * (1.0 + 0.3 * flood) / TIME_COMPRESSION
	u += (thrust_n - resist_n) / m_eff * delta
	ship.speed_ms = u
	ship.sway_ms = v

	_attitude(delta, u)


## Steady outward heel in a turn from the centrifugal force; saturates (a hull does not roll over).
func _heel(u: float) -> float:
	return 0.21 * tanh(heel_k * u * r / G / 0.21)


func _attitude(delta: float, u: float) -> void:
	var s := ship.sea_state
	var fwd := Vector2(sin(ship.heading), cos(ship.heading))
	var right := Vector2(-cos(ship.heading), sin(ship.heading))
	var slope_roll := 0.0
	var slope_pitch := 0.0
	if s > 0.05:
		var pos := Vector2(ship.global_position.x, ship.global_position.z)
		var nwaves := [[70.0 + 25.0 * s, SWELL_DIR, 1.0], [38.0 + 14.0 * s, SWELL_DIR + 0.55, 0.45]]
		for w in nwaves:
			var lam: float = w[0]
			var k := TAU / lam
			var wd := Vector2(sin(float(w[1])), cos(float(w[1])))
			var om := sqrt(G * k)
			var a := 0.22 * s * float(w[2])
			var slope := k * a * cos(k * pos.dot(wd) - om * _t + _phase)
			slope_roll += slope * wd.dot(right)
			slope_pitch += slope * wd.dot(fwd)
	var om_r := TAU / roll_period
	var heel := _heel(u)
	var roll_tgt := heel + slope_roll * 0.9
	var ra := om_r * om_r * (roll_tgt - roll) - 2.0 * roll_zeta * om_r * roll_rate
	roll_rate += ra * delta
	roll += roll_rate * delta
	var om_p := TAU / pitch_period
	var pitch_tgt := 3.0 * (squat_world / Ship.WORLD_SCALE) / maxf(ship.length_m, 1.0) - slope_pitch * 0.9
	var pa := om_p * om_p * (pitch_tgt - pitch) - 2.0 * 0.18 * om_p * pitch_rate
	pitch_rate += pa * delta
	pitch += pitch_rate * delta


## A broadside's recoil kicks the hull. `side` is +1 for guns firing to port, -1 to starboard
## (the ship heels away from the muzzle blast); impulse is the shell momentum in N s.
func recoil(side: float, impulse_ns: float) -> void:
	var arm := 8.0                                     # gun height above the roll axis, m
	var inertia := mass_kg * pow(0.38 * ship.beam_m, 2.0)
	roll_rate += side * impulse_ns * arm / inertia * 2.0


## Elevation error (rad, + = shell goes long) a turret trained `psi` radians off the bow
## (+ to port) suffers from deck motion that the fire-control stable element does not remove.
func gun_elevation_error(psi: float) -> float:
	var lag := 0.35                                    # seconds of fire-control latency
	var tilt := (roll + roll_rate * lag) * sin(psi) - (pitch + pitch_rate * lag) * cos(psi)
	return tilt * (1.0 - gun_stab) * 0.04               # long-range shells are brutally sensitive to elevation: 0.1 deg is ~500 m at 8 km


## 0 = rock steady, 1+ = the platform is moving enough to wreck a salvo.
func platform_motion() -> float:
	var heel := _heel(ship.speed_ms)
	return clampf(absf(roll_rate) / 0.07 + absf(pitch_rate) / 0.05 + absf(roll - heel) / 0.12, 0.0, 2.0) * 0.5


## Multiplier on shell scatter from deck motion the stabiliser cannot hold.
func scatter_factor() -> float:
	return 1.0 + (1.0 - gun_stab) * 5.0 * platform_motion()


## Estimated distance (world m) to stop with a crash-astern order from the current speed.
func stop_distance() -> float:
	var u := absf(ship.speed_ms)
	if u < 0.5:
		return 0.0
	var m_eff := mass_kg / TIME_COMPRESSION
	var v_i := u
	var d := 0.0
	var pf := ship.propulsion_fraction()
	for i in 600:
		var xx := v_i / maxf(ship.max_speed_ms, 1.0)
		var th := 0.25 * t0 * pf * (1.0 + PROP_A * xx)
		var rs := k_drag * _wave_factor(v_i / sqrt(G * ship.length_m)) * v_i * v_i * 1.25
		v_i -= (th + rs) / m_eff * 0.5
		d += maxf(v_i, 0.0) * 0.5
		if v_i <= 0.2:
			break
	return d


func turn_radius() -> float:
	return absf(ship.speed_ms / r) if absf(r) > 0.002 else INF


func kinetic_energy_mj() -> float:
	return 0.5 * mass_kg * ship.speed_ms * ship.speed_ms / 1.0e6
