extends Node3D
## "Hull Down" title cinematic.
##  1. Dawn haze at sea. A watchstander on the bridge wing reports a contact.
##  2. Cut to the captain's scope: the contact shows only masts and superstructure above
##     the horizon -- the hull is below it. He verifies the silhouette.
##  3. Pull back, title card, then on to the testbed. Space / Enter / click skips.
## All lines are on-screen captions for now; hook voice clips into `_say()` later.

const NEXT_SCENE := "res://scenes/testbed.tscn"

## Captions. Speed: ~20 characters/second typed, then held long enough to read twice over.
const TYPE_SECONDS_PER_CHAR := 0.05
const HOLD_BASE := 1.8
const HOLD_PER_CHAR := 0.045

const CONTACT_BEARING := 323.0
const CONTACT_RANGE_YDS := 2000
const CONTACT_DISTANCE_M := 9000.0    ## where the model actually sits (flat world: hull-down is faked by sinking it)

var cam: Camera3D
var contact: Node3D
var caption: Label
var title_label: Label
var studio_label: Label
var fade: ColorRect
var scope: ScopeOverlay
var _t := 0.0
var _scope_on := false
var _skipped := false


class ScopeOverlay extends Control:
	## Black surround with a circular eyepiece opening, plus reticle and readout. Drawn directly
	## (no shader) so it behaves the same on every renderer.
	var strength := 0.0          ## 0 = hidden, 1 = fully in the scope
	var bearing := 323.0
	var range_yds := 2000
	var overlay_font: Font

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay_font = ThemeDB.fallback_font

	func _process(_dt: float) -> void:
		position = Vector2.ZERO
		size = get_viewport_rect().size
		queue_redraw()

	func _draw() -> void:
		if strength < 0.01:
			return
		var c := size * 0.5
		var r := size.y * 0.42
		# Everything outside the eyepiece circle is black: a very thick ring starting at radius r.
		var reach := size.length()
		draw_arc(c, r + reach * 0.5, 0.0, TAU, 256, Color(0, 0, 0, strength), reach, true)
		var col := Color(0.04, 0.04, 0.04, strength * 0.9)
		draw_line(Vector2(c.x - r, c.y), Vector2(c.x - 16, c.y), col, 1.5)
		draw_line(Vector2(c.x + 16, c.y), Vector2(c.x + r, c.y), col, 1.5)
		draw_line(Vector2(c.x, c.y + 16), Vector2(c.x, c.y + r), col, 1.5)
		for k in range(-8, 9):
			if k == 0:
				continue
			var x := c.x + k * r / 9.0
			var h := 7.0 if k % 2 == 0 else 3.5
			draw_line(Vector2(x, c.y - h), Vector2(x, c.y + h), col, 1.2)
		draw_arc(c, r, 0.0, TAU, 128, col, 3.0, true)
		var txt := "BRG %03d   RNG %04d YDS   SCOPE 6X" % [int(bearing), range_yds]
		draw_string(overlay_font, Vector2(c.x - r * 0.6, c.y + r - 78), txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.92, 0.9, 0.78, strength))


func _ready() -> void:
	_build_sea_and_sky()
	_build_contact()
	_build_bridge_wing()
	_build_ui()
	cam.look_at(contact.global_position + Vector3(0, 30, 0), Vector3.UP)
	_run_sequence()


# --- Scene ------------------------------------------------------------------

func _build_sea_and_sky() -> void:
	# Grey, hazy North Atlantic dawn: reads as a real horizon and keeps the contact a dark silhouette.
	var built := SkySea.build(self, "dawn_overcast", Vector2(160000, 160000), false)
	(built["env"] as Environment).fog_density = 0.00005

	cam = Camera3D.new()
	cam.far = 90000.0
	cam.fov = 70.0
	cam.position = Vector3(0, 16, 0)
	cam.current = true
	add_child(cam)


## The contact: only the superstructure clears the horizon; the hull sits below the waterline.
func _build_contact() -> void:
	contact = Node3D.new()
	add_child(contact)
	var brg := deg_to_rad(CONTACT_BEARING)
	# Hull sunk below the sea plane so only the mast and the top of the bridge and funnel clear the horizon.
	contact.position = Vector3(sin(brg) * CONTACT_DISTANCE_M, -9.0, cos(brg) * CONTACT_DISTANCE_M)
	contact.rotation.y = brg + deg_to_rad(90.0 + 18.0)     # near-broadside to the observer
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.14, 0.14, 0.16)
	_box(contact, Vector3(11, 8, 95), Vector3(0, 4, 0), dark)             # hull (below the horizon)
	_box(contact, Vector3(4.5, 2.5, 5), Vector3(0, 9.3, 28), dark)        # forward gun mount
	_box(contact, Vector3(4.5, 2.5, 5), Vector3(0, 9.3, -30), dark)       # after gun mount
	_box(contact, Vector3(8, 6, 12), Vector3(0, 11.0, 12), dark)          # bridge
	_box(contact, Vector3(4.5, 7, 5), Vector3(0, 13.5, -6), dark)         # single funnel
	_box(contact, Vector3(2.4, 24, 2.4), Vector3(0, 23.0, 10), dark)      # the single mast
	_box(contact, Vector3(9.0, 1.2, 1.2), Vector3(0, 29.0, 10), dark)     # yardarm
	_box(contact, Vector3(3.5, 1.4, 2.5), Vector3(0, 35.5, 10), dark)     # top mark / radar
	var smoke := StandardMaterial3D.new()
	smoke.albedo_color = Color(0.25, 0.23, 0.22, 0.45)
	smoke.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_box(contact, Vector3(4, 4, 55), Vector3(-2, 21, -32), smoke)           # thin funnel smoke


func _build_bridge_wing() -> void:
	## The lookout, close to camera on the bridge wing, plus the wing's deck edge and rail.
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.035, 0.035, 0.04)
	dark.roughness = 0.85
	var wing := Node3D.new()
	wing.name = "Watchstander"
	cam.add_child(wing)
	wing.position = Vector3(1.05, -1.72, -2.6)          # feet on the deck, eye height about level with the camera
	wing.rotation_degrees = Vector3(0, 180.0 - 28.0, 0)  # back to us, turned toward the contact
	wing.add_child(Watchstander.new())
	var rail := Node3D.new()
	cam.add_child(rail)
	rail.position = Vector3(0, -1.72, -4.6)
	_box(rail, Vector3(14, 0.06, 0.06), Vector3(0, 1.0, 0), dark)           # top rail
	_box(rail, Vector3(14, 0.04, 0.04), Vector3(0, 0.55, 0), dark)          # mid rail
	for k in range(-6, 7):
		_box(rail, Vector3(0.04, 1.0, 0.04), Vector3(k * 1.1, 0.5, 0), dark)  # stanchions
	_box(rail, Vector3(14, 0.3, 0.5), Vector3(0, -0.15, 0.3), dark)          # deck edge / coaming
	_box(cam, Vector3(14, 0.1, 6.0), Vector3(0, -1.77, -2.6), dark)           # bridge wing deck under his feet


func _shape(parent: Node3D, mesh: Mesh, pos: Vector3, scale3: Vector3, mat: Material, rot_deg := Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.scale = scale3
	mi.rotation_degrees = rot_deg
	mi.material_override = mat
	parent.add_child(mi)


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)


# --- UI -----------------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	scope = ScopeOverlay.new()
	layer.add_child(scope)

	caption = Label.new()
	caption.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	caption.offset_top = -110
	caption.offset_bottom = -40
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.add_theme_font_size_override("font_size", 26)
	caption.add_theme_color_override("font_color", Color(0.96, 0.94, 0.86))
	caption.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	caption.add_theme_constant_override("shadow_offset_x", 2)
	caption.add_theme_constant_override("shadow_offset_y", 2)
	layer.add_child(caption)

	title_label = Label.new()
	title_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.text = "H U L L   D O W N"
	title_label.add_theme_font_size_override("font_size", 120)
	title_label.add_theme_color_override("font_color", Color(0.93, 0.91, 0.84))
	title_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	title_label.modulate.a = 0.0
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(title_label)

	studio_label = Label.new()
	studio_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	studio_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	studio_label.offset_bottom = -300
	studio_label.text = "SQUATCH SQUAD STUDIOS PRESENTS"
	studio_label.add_theme_font_size_override("font_size", 22)
	studio_label.modulate.a = 0.0
	studio_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(studio_label)

	fade = ColorRect.new()
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.color = Color.BLACK
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(fade)


# --- Sequence --------------------------------------------------------------------

func _say(speaker: String, text: String) -> void:
	## Typewriter caption: "SPEAKER: line". Swap in an AudioStreamPlayer here when VO is recorded.
	var full := "%s: %s" % [speaker.to_upper(), text]
	caption.text = ""
	for i in full.length():
		if _skipped:
			return
		caption.text = full.substr(0, i + 1)
		await get_tree().create_timer(TYPE_SECONDS_PER_CHAR).timeout
	await get_tree().create_timer(HOLD_BASE + HOLD_PER_CHAR * full.length()).timeout


func _run_sequence() -> void:
	# Opening: studio card on black.
	await _tween_alpha(studio_label, 1.0, 1.4)
	await _wait(1.6)
	await _tween_alpha(studio_label, 0.0, 0.8)

	# Fade in on the bridge wing.
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 0.0, 3.0)
	await _wait(2.4)
	await _say("Forward Lookout", "Bridge, Lookout. Contact bearing 323, range 2000 yards.")
	await _wait(0.8)
	caption.text = ""

	# Cut to the captain's scope: tight FOV, reticle, hull below the horizon.
	cam.get_node("Watchstander").visible = false
	var zoom := create_tween().set_parallel(true)
	zoom.tween_property(cam, "fov", 4.5, 2.6).set_trans(Tween.TRANS_SINE)
	zoom.tween_property(scope, "strength", 1.0, 2.0)
	cam.look_at(contact.global_position + Vector3(0, 14, 0), Vector3.UP)
	_scope_on = true
	await _wait(3.2)
	await _say("Captain", "Single mast. Possible frigate, can't be sure yet.")
	await _wait(0.6)
	await _say("Captain", "She's hull down.")
	await _wait(0.8)
	await _say("Captain", "Boatswain, sound General Quarters.")

	# Slow rise of the contact as range closes, then pull back to the title.
	var rise := create_tween()
	rise.tween_property(contact, "position:y", -5.5, 4.0)
	await _wait(2.4)
	var out := create_tween().set_parallel(true)
	out.tween_property(scope, "strength", 0.0, 1.4)
	out.tween_property(cam, "fov", 55.0, 2.0).set_trans(Tween.TRANS_SINE)
	caption.text = ""
	await _wait(1.6)
	await _tween_alpha(title_label, 1.0, 2.0)
	await _wait(2.8)
	_finish()


func _tween_alpha(node: CanvasItem, target: float, secs: float) -> void:
	var tw := create_tween()
	tw.tween_property(node, "modulate:a", target, secs)
	await tw.finished


func _wait(secs: float) -> void:
	if _skipped:
		return
	await get_tree().create_timer(secs).timeout


func _process(delta: float) -> void:
	_t += delta
	# Idle sway on the bridge, tighter breathing in the scope.
	var sway := 0.0015 if not _scope_on else 0.0004
	cam.rotation.z = sin(_t * 0.9) * sway * 6.0
	scope.bearing = CONTACT_BEARING + sin(_t * 0.2) * 0.4


func _unhandled_input(event: InputEvent) -> void:
	var skip := event.is_action_pressed("skip_cinematic")
	if event is InputEventMouseButton and event.pressed:
		skip = true
	if event is InputEventKey and event.pressed and (event.keycode == KEY_SPACE or event.keycode == KEY_ESCAPE):
		skip = true
	if skip:
		_finish()


func _finish() -> void:
	if _skipped:
		return
	_skipped = true
	get_tree().change_scene_to_file(NEXT_SCENE)
