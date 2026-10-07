extends CanvasLayer
## Autoload "MobileMode": Hull Down is landscape-only. On a phone it goes fullscreen on the first
## touch (and asks the browser to lock landscape), and a "rotate your phone" card covers the game,
## pausing it, while the device is held upright.

var _overlay: ColorRect
var _fs_done := false
var phone := false          ## true on phones/tablets: also switches on the lighter rendering tier


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	phone = OS.has_feature("mobile")
	if OS.has_feature("web"):
		phone = bool(JavaScriptBridge.eval("/Android|iPhone|iPad|iPod/i.test(navigator.userAgent)"))
	# Phone rendering tier: draw the 3D scene at 60% resolution (the HUD stays sharp), no MSAA.
	if phone or OS.get_cmdline_user_args().has("--lowfx"):
		phone = true
		var root := get_tree().root
		root.msaa_3d = Viewport.MSAA_DISABLED
		root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		root.scaling_3d_scale = 0.6
	_overlay = ColorRect.new()
	_overlay.color = Color(0.03, 0.05, 0.08, 1.0)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)
	var l := Label.new()
	l.text = "ROTATE YOUR PHONE\n\nHull Down is played in landscape"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.add_theme_font_size_override("font_size", 56)
	l.add_theme_color_override("font_color", Color(0.94, 0.96, 0.97))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_overlay.add_child(l)
	get_window().size_changed.connect(_check)
	_check()


func _check() -> void:
	var ws := Vector2(get_window().size)
	var upright := phone and ws.y > ws.x
	_overlay.visible = upright
	get_tree().paused = upright


func _input(e: InputEvent) -> void:
	if _fs_done or not phone:
		return
	if (e is InputEventScreenTouch and (e as InputEventScreenTouch).pressed) or (e is InputEventMouseButton and (e as InputEventMouseButton).pressed):
		_fs_done = true
		if OS.has_feature("web"):
			JavaScriptBridge.eval("(function(){var d=document.documentElement;var f=d.requestFullscreen||d.webkitRequestFullscreen;if(f){Promise.resolve(f.call(d)).then(function(){if(screen.orientation&&screen.orientation.lock){return screen.orientation.lock('landscape');}}).catch(function(){});}})()")
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
