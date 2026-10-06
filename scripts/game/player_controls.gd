class_name PlayerControls
extends Node
## Turns the player's discrete orders (engine telegraph, helm) into ship behaviour.
## Works identically from keyboard hotkeys and from the on-screen touch widgets.

signal order_changed

var ship: Ship
var engine_ordered := EngineTelegraph.STOP_INDEX      ## what the bridge rang
var engine_answered := EngineTelegraph.STOP_INDEX     ## what the engine room is running
var helm_ordered := EngineTelegraph.MIDSHIPS_INDEX
var _answer_timer := 0.0


func setup(p_ship: Ship) -> void:
	ship = p_ship


func ring_engine(idx: int) -> void:
	idx = clampi(idx, 0, EngineTelegraph.ENGINE_ORDERS.size() - 1)
	if idx == engine_ordered:
		return
	engine_ordered = idx
	_answer_timer = EngineTelegraph.ENGINE_ANSWER_S
	order_changed.emit()


func step_engine(delta_steps: int) -> void:
	## +1 = one detent faster ahead (toward FLANK), -1 = one detent toward ALL ASTERN.
	ring_engine(engine_ordered - delta_steps)


func set_helm(idx: int) -> void:
	idx = clampi(idx, 0, EngineTelegraph.HELM_ORDERS.size() - 1)
	if idx != helm_ordered:
		helm_ordered = idx
		order_changed.emit()


func step_helm(toward_port: int) -> void:
	set_helm(helm_ordered - toward_port)


func center_helm() -> void:
	set_helm(EngineTelegraph.MIDSHIPS_INDEX)


func engine_label() -> String:
	return EngineTelegraph.ENGINE_ORDERS[engine_ordered][0]


func helm_label() -> String:
	return EngineTelegraph.HELM_ORDERS[helm_ordered][0]


func rudder_degrees() -> float:
	return ship.rudder * EngineTelegraph.MAX_RUDDER_DEG


func _physics_process(delta: float) -> void:
	if ship == null or not is_instance_valid(ship) or ship.sunk:
		return
	if engine_answered != engine_ordered:
		_answer_timer -= delta
		if _answer_timer <= 0.0:
			engine_answered = engine_ordered
	ship.throttle = float(EngineTelegraph.ENGINE_ORDERS[engine_answered][1])
	var target: float = EngineTelegraph.HELM_ORDERS[helm_ordered][1]
	ship.rudder = move_toward(ship.rudder, target, EngineTelegraph.RUDDER_RATE * ship.handling_fraction() * delta)
