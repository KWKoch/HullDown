class_name CombatProfiles
extends RefCounted
## Baseline combat behaviour per ship TYPE (the roster "type" field). Pure data: AICaptain reads
## these and decides how to move, who to shoot, and when to break off.
##
## Captain types (later) will not replace these. They will scale them through
## `AICaptain.captain_mods`, e.g. {"aggression": 1.3, "error_rate": 0.5, "engage_cap_m": 1.1},
## so a timid captain in a battleship still behaves like a battleship, only more cautiously.
##
## Fields (ranges in metres; fractions are of "effective range" = min(main-gun range, engage_cap_m)):
##   style             movement doctrine: line_of_battle | cruiser | flotilla | screen_and_strike |
##                     convoy_guard | evade | hit_and_run
##   engage_cap_m      realistic fighting range for this type (guns reach further than crews fought)
##   fire_cap_factor   opens fire out to engage_cap_m * this
##   range_band        [min, max] fraction of effective range the ship tries to hold while engaged
##   exposure_deg      how much tangential (circling) motion vs closing: 15 = nose-on, 90 = broadside.
##                     Nose-on genuinely shrinks the hit box (hull-down thinking).
##   cruise/close/hold throttle    speed when station-keeping / closing / engaged
##   aggression        0..1 willingness to take risks (also biases when to start a run)
##   target_weights    value of each enemy type as a target (1.0 = prime target)
##   wounded_bonus     extra priority for already damaged targets (finish the kill)
##   cohesion          {types, station_m, weight}: stay within station_m of the nearest friendly of these types
##   retreat           {flood, propulsion, battery}: withdraw when flooding fraction exceeds `flood`, or propulsion /
##                     main-battery fraction falls below the given value
##   attack-run fields (screen_and_strike, hit_and_run): strike_trigger_m, strike_min_weight, run_range_m,
##                     break_s (seconds spent breaking away), cooldown_s (before the next run)
##   evade_trigger_m   (evade style) run when any enemy is nearer than this

const DEFAULTS := {
	"style": "cruiser", "engage_cap_m": 15000.0, "fire_cap_factor": 1.15, "range_band": [0.5, 0.8],
	"exposure_deg": 70.0, "cruise_throttle": 0.6, "close_throttle": 0.9, "hold_throttle": 0.6,
	"aggression": 0.5, "wounded_bonus": 0.6, "default_weight": 0.4,
	"target_weights": {}, "cohesion": {},
	"retreat": {"flood": 0.6, "propulsion": 0.35, "battery": 0.2},
}

const PROFILES := {
	"battleship": {
		"style": "line_of_battle", "engage_cap_m": 22000.0, "range_band": [0.6, 0.85], "exposure_deg": 60.0,
		"cruise_throttle": 0.55, "close_throttle": 0.85, "hold_throttle": 0.55, "aggression": 0.5, "wounded_bonus": 0.8,
		"target_weights": {"battleship": 1.0, "battlecruiser": 1.0, "carrier": 0.9, "heavy_cruiser": 0.8, "light_cruiser": 0.55,
			"destroyer": 0.3, "escort": 0.2, "motor_torpedo_boat": 0.1},
		"cohesion": {"types": ["battleship", "battlecruiser"], "station_m": 2500.0, "weight": 0.5},
		"retreat": {"flood": 0.7, "propulsion": 0.3, "battery": 0.15},
	},
	"battlecruiser": {
		"style": "line_of_battle", "engage_cap_m": 22000.0, "range_band": [0.65, 0.9], "exposure_deg": 55.0,
		"cruise_throttle": 0.7, "close_throttle": 1.0, "hold_throttle": 0.7, "aggression": 0.6, "wounded_bonus": 0.8,
		"target_weights": {"battleship": 0.9, "battlecruiser": 1.0, "carrier": 0.9, "heavy_cruiser": 0.9, "light_cruiser": 0.6,
			"destroyer": 0.35, "escort": 0.2, "motor_torpedo_boat": 0.1},
		"cohesion": {"types": ["battleship", "battlecruiser"], "station_m": 2500.0, "weight": 0.5},
		"retreat": {"flood": 0.6, "propulsion": 0.35, "battery": 0.25},   # thin armour: breaks off earlier
	},
	"heavy_cruiser": {
		"style": "cruiser", "engage_cap_m": 16000.0, "range_band": [0.5, 0.8], "exposure_deg": 75.0,
		"cruise_throttle": 0.7, "close_throttle": 0.95, "hold_throttle": 0.7, "aggression": 0.6,
		"target_weights": {"carrier": 1.0, "destroyer": 0.9, "light_cruiser": 0.9, "heavy_cruiser": 0.9, "battlecruiser": 0.7,
			"battleship": 0.6, "escort": 0.5, "motor_torpedo_boat": 0.6},
		"cohesion": {"types": ["battleship", "battlecruiser", "heavy_cruiser"], "station_m": 3000.0, "weight": 0.35},
		"retreat": {"flood": 0.55, "propulsion": 0.4, "battery": 0.25},
	},
	"light_cruiser": {
		"style": "flotilla", "engage_cap_m": 12000.0, "range_band": [0.4, 0.7], "exposure_deg": 80.0,
		"cruise_throttle": 0.8, "close_throttle": 1.0, "hold_throttle": 0.8, "aggression": 0.7,
		"target_weights": {"destroyer": 1.0, "motor_torpedo_boat": 0.9, "carrier": 0.9, "light_cruiser": 0.8, "heavy_cruiser": 0.6,
			"escort": 0.6, "battlecruiser": 0.45, "battleship": 0.35},
		"cohesion": {"types": ["heavy_cruiser", "light_cruiser", "battleship"], "station_m": 3500.0, "weight": 0.3},
		"retreat": {"flood": 0.5, "propulsion": 0.45, "battery": 0.3},
	},
	"destroyer": {
		"style": "screen_and_strike", "engage_cap_m": 8000.0, "range_band": [0.35, 0.65], "exposure_deg": 40.0,
		"cruise_throttle": 0.7, "close_throttle": 1.0, "hold_throttle": 0.8, "aggression": 0.8,
		"strike_trigger_m": 9000.0, "strike_min_weight": 0.6, "run_range_m": 3500.0, "break_s": 25.0, "cooldown_s": 30.0,
		"target_weights": {"battleship": 1.0, "battlecruiser": 1.0, "carrier": 1.0, "heavy_cruiser": 0.9, "light_cruiser": 0.7,
			"motor_torpedo_boat": 0.5, "destroyer": 0.45, "escort": 0.3},
		"cohesion": {"types": ["battleship", "battlecruiser", "heavy_cruiser", "light_cruiser", "carrier"], "station_m": 3000.0, "weight": 0.6},
		"retreat": {"flood": 0.45, "propulsion": 0.5, "battery": 0.3},
	},
	"escort": {
		"style": "convoy_guard", "engage_cap_m": 6000.0, "range_band": [0.4, 0.7], "exposure_deg": 60.0,
		"cruise_throttle": 0.6, "close_throttle": 0.9, "hold_throttle": 0.6, "aggression": 0.3,
		"target_weights": {"motor_torpedo_boat": 0.9, "destroyer": 0.8, "escort": 0.6, "light_cruiser": 0.5, "carrier": 0.5,
			"heavy_cruiser": 0.4, "battleship": 0.3, "battlecruiser": 0.3},
		"cohesion": {"types": ["carrier", "battleship", "heavy_cruiser", "light_cruiser"], "station_m": 2200.0, "weight": 0.8},
		"retreat": {"flood": 0.45, "propulsion": 0.4, "battery": 0.3},
	},
	"carrier": {
		"style": "evade", "engage_cap_m": 14000.0, "range_band": [0.85, 1.0], "exposure_deg": 90.0,
		"cruise_throttle": 0.6, "close_throttle": 0.8, "hold_throttle": 0.6, "aggression": 0.05, "evade_trigger_m": 14000.0,
		"cohesion": {"types": ["battleship", "battlecruiser", "heavy_cruiser", "light_cruiser"], "station_m": 4000.0, "weight": 0.5},
		"retreat": {"flood": 0.5, "propulsion": 0.4, "battery": 0.0},
	},
	"motor_torpedo_boat": {
		"style": "hit_and_run", "engage_cap_m": 2500.0, "range_band": [0.3, 0.7], "exposure_deg": 15.0,
		"cruise_throttle": 0.8, "close_throttle": 1.0, "hold_throttle": 1.0, "aggression": 0.95,
		"strike_trigger_m": 6000.0, "strike_min_weight": 0.3, "run_range_m": 1100.0, "break_s": 15.0, "cooldown_s": 12.0,
		"target_weights": {"battleship": 1.0, "battlecruiser": 1.0, "carrier": 1.0, "heavy_cruiser": 0.9, "light_cruiser": 0.8,
			"destroyer": 0.6, "escort": 0.5, "motor_torpedo_boat": 0.3},
		"retreat": {"flood": 0.35, "propulsion": 0.5, "battery": 0.2},
	},
	# Submarines are disabled in the surface testbed; their ambush / sonar behaviour comes with the subsurface layer.
	"submarine": {"style": "cruiser", "engage_cap_m": 4000.0, "aggression": 0.3},
}


## Defaults merged with the type's overrides. Returns a deep copy the caller may modify.
static func for_type(ship_type: String) -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate(true)
	var over: Dictionary = PROFILES.get(ship_type, {})
	for k in over:
		out[k] = (over[k] as Variant).duplicate(true) if (over[k] is Dictionary or over[k] is Array) else over[k]
	return out
