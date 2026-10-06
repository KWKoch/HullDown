class_name EngineTelegraph
extends RefCounted
## Engine-room and helm orders, as a ship's bridge would call them. The player never sets a
## continuous throttle: they ring an order and the engine room answers it a moment later.

## [label, throttle fraction of full power]. Ordered ahead-fastest first (top of the telegraph).
const ENGINE_ORDERS := [
	["AHEAD FLANK", 1.0],
	["AHEAD FULL", 0.85],
	["AHEAD 3/4", 0.65],
	["AHEAD 1/2", 0.5],
	["AHEAD 1/4", 0.25],
	["STOP", 0.0],
	["ASTERN 1/3", -0.10],
	["ASTERN 2/3", -0.20],
	["ALL ASTERN", -0.30],
]
const STOP_INDEX := 5

## [label, rudder (-1 starboard .. +1 port, 35 deg = 1.0), angle in degrees (+ port)].
const HELM_ORDERS := [
	["HARD PORT", 1.0],
	["PORT 20", 20.0 / 35.0],
	["PORT 10", 10.0 / 35.0],
	["MIDSHIPS", 0.0],
	["STBD 10", -10.0 / 35.0],
	["STBD 20", -20.0 / 35.0],
	["HARD STBD", -1.0],
]
const MIDSHIPS_INDEX := 3
const RUDDER_RATE := 0.6          ## rudder travel per second (fraction of full throw)
const ENGINE_ANSWER_S := 0.9      ## engine room acknowledgement delay
const MAX_RUDDER_DEG := 35.0
