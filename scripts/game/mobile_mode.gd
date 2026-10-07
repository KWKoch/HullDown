extends CanvasLayer
## Autoload "MobileMode": Hull Down is landscape-only. On a phone it goes fullscreen on the first
## touch (and asks the browser to lock landscape), and a "rotate your phone" card covers the game,
## pausing it, while the device is held upright.

var _overlay: ColorRect
var _fs_done := false
var _fs_button: Button
var _fs_poll := 0.0

## Browser side: fullscreen may only be requested inside a real user gesture, and Godot handles
## input a frame later. So a capture-phase listener on the page does the request on pointerup
## whenever the game has asked for it (window.hdWantFS). The very first tap asks automatically.
const FS_JS := "(function(){if(window.__hdfs)return;window.__hdfs=true;window.hdWantFS=true;function go(){if(!window.hdWantFS)return;window.hdWantFS=false;if(document.fullscreenElement||document.webkitFullscreenElement)return;var d=document.documentElement;var f=d.requestFullscreen||d.webkitRequestFullscreen;if(!f)return;try{Promise.resolve(f.call(d,{navigationUI:'hide'})).then(function(){if(screen.orientation&&screen.orientation.lock){return screen.orientation.lock('landscape');}}).catch(function(){});}catch(e){}}document.addEventListener('pointerup',go,true);document.addEventListener('touchend',go,true);document.addEventListener('click',go,true);})()"
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
	# Fullscreen toggle (top-left), like a video app's expand button.
	_fs_button = Button.new()
	_fs_button.text = "⛶"
	_fs_button.tooltip_text = "Full screen"
	_fs_button.focus_mode = Control.FOCUS_NONE
	_fs_button.add_theme_font_size_override("font_size", 38)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.05, 0.08, 0.55)
	sb.border_color = Color(0.78, 0.60, 0.26, 0.9)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	for st in ["normal", "hover", "pressed", "focus"]:
		_fs_button.add_theme_stylebox_override(st, sb)
	_fs_button.add_theme_color_override("font_color", Color(0.95, 0.85, 0.6))
	_fs_button.size = Vector2(64, 60)
	_fs_button.button_down.connect(_toggle_fullscreen)
	_fs_button.visible = false
	add_child(_fs_button)
	if OS.has_feature("web") and phone:
		JavaScriptBridge.eval(FS_JS)
	get_window().size_changed.connect(_check)
	_check()


func _check() -> void:
	var ws := Vector2(get_window().size)
	var upright := phone and ws.y > ws.x
	_overlay.visible = upright
	get_tree().paused = upright


func is_fullscreen() -> bool:
	if OS.has_feature("web"):
		return bool(JavaScriptBridge.eval("!!(document.fullscreenElement||document.webkitFullscreenElement)||window.matchMedia('(display-mode: fullscreen)').matches||window.navigator.standalone===true"))
	return DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN


func _toggle_fullscreen() -> void:
	if OS.has_feature("web"):
		if is_fullscreen():
			JavaScriptBridge.eval("(document.exitFullscreen||document.webkitExitFullscreen||function(){}).call(document)")
		else:
			JavaScriptBridge.eval("window.hdWantFS=true")      # the page listener goes fullscreen as this tap lifts
	else:
		var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)


func _process(delta: float) -> void:
	if not phone or _fs_button == null:
		return
	_fs_poll -= delta
	if _fs_poll <= 0.0:
		_fs_poll = 0.5
		# Shown while not fullscreen (to enter); hidden when fullscreen so it never clutters the game.
		_fs_button.visible = not is_fullscreen() and not _overlay.visible
		# Top bar, just right of centre: clear of the menu tabs and the battle compass strip.
		var cs := get_tree().current_scene
		if cs != null and cs.has_method("fullscreen_button_pos"):
			_fs_button.position = cs.fullscreen_button_pos()
		else:
			_fs_button.position = Vector2(get_viewport().get_visible_rect().size.x * 0.5 + 380.0, 8.0)


func _input(e: InputEvent) -> void:
	if OS.has_feature("web"):
		return                   # the page listener handles the first-tap fullscreen on the web
	if _fs_done or not phone:
		return
	if (e is InputEventScreenTouch and (e as InputEventScreenTouch).pressed) or (e is InputEventMouseButton and (e as InputEventMouseButton).pressed):
		_fs_done = true
		if OS.has_feature("web"):
			JavaScriptBridge.eval("(function(){var d=document.documentElement;var f=d.requestFullscreen||d.webkitRequestFullscreen;if(f){Promise.resolve(f.call(d)).then(function(){if(screen.orientation&&screen.orientation.lock){return screen.orientation.lock('landscape');}}).catch(function(){});}})()")
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
