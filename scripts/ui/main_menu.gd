extends Control
## Main menu: PLAY (PvP / Story headers + Skirmish launcher), FLEET STORE (roster, 3D viewer,
## infographics), MAPS (thumbnails that open a 3D topographic map with waypoints and concealment).

const GOLD := Color(1.0, 0.76, 0.28)
const INK := Color(0.9, 0.94, 0.98)
const DIM := Color(0.62, 0.72, 0.84)
const PANEL := Color(0.075, 0.11, 0.16, 0.96)

const TYPE_BLURB := {
	"battleship": "Capital ship. Heavy guns and armour; slow to turn and a big target.",
	"heavy_cruiser": "Fast, long-legged gun platform. Balanced armour, strong main battery.",
	"light_cruiser": "Rapid-fire 6-inch guns. Fast and tough for its size; weak against battleship shells.",
	"destroyer": "Small, quick and agile. Torpedoes and smoke; falls apart under heavy fire.",
	"escort": "Light escort. Slow and fragile, but cheap and hard to spot.",
	"carrier": "Aircraft carrier. Little gun power; its strength is its air group.",
	"submarine": "Stealth hunter beneath the waves.",
}

var tab_btns: Array[Button] = []
var pages: Array[Control] = []
var _tab := 0
var credits_lbl: Label

# play page
var play_map_thumb: TextureRect
var play_map_lbl: Label
var play_ship_lbl: Label
var play_ship_sub: Label

# fleet page
var viewer: ShipViewer
var stats: ShipStats
var ship_list: VBoxContainer
var ship_title: Label
var ship_sub: Label
var ship_desc: Label
var ship_price: Label
var select_btn: Button
var nation_filter: OptionButton
var type_filter: OptionButton
var _browse_id := ""
var _row_btns := {}

# maps page
var cards: Array[MapCard] = []
var _thumb_queue: Array[int] = []
var overlay: Control
var topo: TopoView
var topo_info: Label
var topo_gid := ""
var vis_btn: Button


func _ready() -> void:
	GameSession.launched = false
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_bg()
	_build_top()
	pages = [_build_play(), _build_fleet(), _build_maps()]
	for p in pages:
		add_child(p)
	_build_overlay()
	_browse_id = GameSession.ship_id
	_refresh_selection()
	_show_tab(_start_tab())
	_fill_list()
	_browse(GameSession.ship_id)
	_test_args()


var _shot_t := 0.0
var _shot_path := ""
var _shot_secs := 0.0


func _test_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			var parts := a.substr(7).split(",")
			_shot_path = parts[0]
			_shot_secs = float(parts[1])
		elif a.begins_with("--topo="):
			_open_topo(a.substr(7))
		elif a.begins_with("--obs="):
			var xy := a.substr(6).split(",")
			await get_tree().create_timer(2.5).timeout
			if topo != null:
				topo.set_observer(Vector2(float(xy[0]), float(xy[1])))
		elif a.begins_with("--pick="):
			GameSession.ship_id = a.substr(7)
		elif a.begins_with("--map="):
			GameSession.ground_id = a.substr(6)
		elif a == "--launch":
			_launch.call_deferred()
		elif a.begins_with("--browse="):
			_browse(a.substr(9))


func _start_tab() -> int:
	var cl := OS.get_cmdline_user_args()
	var i := cl.find("--tab")
	if i >= 0 and i + 1 < cl.size():
		return clampi(int(cl[i + 1]), 0, 2)
	return 0


# --- chrome ------------------------------------------------------------------

func _style(bg: Color, border: Color = Color(0.25, 0.35, 0.48), bw: int = 1, rad: int = 4) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(rad)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


func _lbl(text: String, size: int, col: Color = INK, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _btn(text: String, cb: Callable, accent: Color = GOLD, size: int = 20) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(0.45, 0.5, 0.56))
	b.add_theme_stylebox_override("normal", _style(Color(0.12, 0.17, 0.24), accent.darkened(0.2), 2))
	b.add_theme_stylebox_override("hover", _style(Color(0.17, 0.24, 0.34), accent, 2))
	b.add_theme_stylebox_override("pressed", _style(accent.darkened(0.55), accent, 2))
	b.add_theme_stylebox_override("disabled", _style(Color(0.09, 0.11, 0.14), Color(0.22, 0.26, 0.32), 1))
	b.pressed.connect(cb)
	return b


func _build_bg() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.06, 0.1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var grad := TextureRect.new()
	var gt := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.set_color(0, Color(0.10, 0.17, 0.26, 0.9))
	gr.set_color(1, Color(0.02, 0.03, 0.05, 0.0))
	gt.gradient = gr
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 1.0)
	gt.width = 512
	gt.height = 512
	grad.texture = gt
	grad.stretch_mode = TextureRect.STRETCH_SCALE
	grad.set_anchors_preset(Control.PRESET_FULL_RECT)
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(grad)


func _build_top() -> void:
	var bar := Panel.new()
	bar.add_theme_stylebox_override("panel", _style(Color(0.05, 0.08, 0.12, 0.98), Color(0.2, 0.3, 0.42), 0, 0))
	bar.position = Vector2.ZERO
	bar.size = Vector2(1920, 92)
	add_child(bar)
	var t := _lbl("HULL DOWN", 44, GOLD)
	t.position = Vector2(36, 8)
	add_child(t)
	var st := _lbl("SQUATCH SQUAD STUDIOS  -  WWII NAVAL COMBAT", 13, DIM)
	st.position = Vector2(40, 66)
	add_child(st)
	var names := ["PLAY", "FLEET STORE", "MAPS"]
	for k in 3:
		var b := _btn(names[k], _show_tab.bind(k), GOLD, 22)
		b.position = Vector2(620 + k * 230, 18)
		b.size = Vector2(212, 56)
		add_child(b)
		tab_btns.append(b)
	credits_lbl = _lbl("TEST BUILD  -  ALL SHIPS UNLOCKED", 15, DIM)
	credits_lbl.position = Vector2(1500, 34)
	add_child(credits_lbl)


func _show_tab(k: int) -> void:
	_tab = k
	for i in pages.size():
		pages[i].visible = (i == k)
	for i in tab_btns.size():
		tab_btns[i].add_theme_stylebox_override("normal", _style(Color(0.28, 0.2, 0.06) if i == k else Color(0.12, 0.17, 0.24), GOLD if i == k else GOLD.darkened(0.45), 2))
	if k == 2:
		_queue_thumbs()


# --- PLAY ---------------------------------------------------------------------

func _build_play() -> Control:
	var page := Control.new()
	page.position = Vector2(0, 92)
	page.size = Vector2(1920, 988)
	var cx := 30.0
	var w := 600.0
	# PvP
	_mode_card(page, Vector2(cx, 40), w, "PVP", "FLEET BATTLES  -  15 v 15", Color(0.35, 0.6, 1.0),
		["Human captains on both sides, one ship each.", "Seasonal ladders: rank, rewards and earnings reset each season.",
		"Live matches once the player base can fill both fleets.", "Fleet and ship progression carries across seasons."],
		"SEASON 1  -  COMING SOON")
	# Story
	_mode_card(page, Vector2(cx + w + 30, 40), w, "STORY MODE", "THE WAR AT SEA  -  CAMPAIGN", Color(0.5, 0.85, 0.5),
		["Fight the war's great surface actions in sequence.", "Command a flotilla through historical scenarios.",
		"Earn commendations, refits and new hulls.", "Built on the same ships and maps as Skirmish."],
		"IN DEVELOPMENT  -  COMING SOON")
	# Skirmish
	var x3 := cx + (w + 30) * 2
	var card := Panel.new()
	card.add_theme_stylebox_override("panel", _style(PANEL, GOLD, 2))
	card.position = Vector2(x3, 40)
	card.size = Vector2(w, 880)
	page.add_child(card)
	var head := _lbl("SKIRMISH", 38, GOLD)
	head.position = Vector2(24, 18)
	card.add_child(head)
	var sub := _lbl("TEST RANGE  -  15 v 15 AGAINST AI", 16, DIM)
	sub.position = Vector2(26, 70)
	card.add_child(sub)
	play_map_thumb = TextureRect.new()
	play_map_thumb.position = Vector2(24, 110)
	play_map_thumb.size = Vector2(w - 48, 300)
	play_map_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	play_map_thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	card.add_child(play_map_thumb)
	play_map_lbl = _lbl("", 22, INK)
	play_map_lbl.position = Vector2(24, 422)
	play_map_lbl.size = Vector2(w - 48, 60)
	card.add_child(play_map_lbl)
	play_ship_lbl = _lbl("", 22, GOLD)
	play_ship_lbl.position = Vector2(24, 500)
	play_ship_lbl.size = Vector2(w - 48, 30)
	card.add_child(play_ship_lbl)
	play_ship_sub = _lbl("", 15, DIM)
	play_ship_sub.position = Vector2(24, 534)
	play_ship_sub.size = Vector2(w - 48, 30)
	card.add_child(play_ship_sub)
	var bm := _btn("CHANGE MAP", _show_tab.bind(2), GOLD.darkened(0.2), 18)
	bm.position = Vector2(24, 600)
	bm.size = Vector2((w - 60) * 0.5, 50)
	card.add_child(bm)
	var bs := _btn("CHANGE SHIP", _show_tab.bind(1), GOLD.darkened(0.2), 18)
	bs.position = Vector2(24 + (w - 60) * 0.5 + 12, 600)
	bs.size = Vector2((w - 60) * 0.5, 50)
	card.add_child(bs)
	var go := _btn("LAUNCH BATTLE", _launch, Color(0.4, 0.9, 0.5), 30)
	go.position = Vector2(24, 700)
	go.size = Vector2(w - 48, 90)
	card.add_child(go)
	var note := _lbl("ESC returns to this menu during battle.", 14, DIM)
	note.position = Vector2(24, 810)
	card.add_child(note)
	return page


func _mode_card(page: Control, pos: Vector2, w: float, title: String, tag: String, col: Color, bullets: Array, status: String) -> void:
	var card := Panel.new()
	card.add_theme_stylebox_override("panel", _style(PANEL, col.darkened(0.45), 2))
	card.position = pos
	card.size = Vector2(w, 880)
	page.add_child(card)
	var band := ColorRect.new()
	band.color = col.darkened(0.55)
	band.position = Vector2(2, 2)
	band.size = Vector2(w - 4, 130)
	card.add_child(band)
	var h := _lbl(title, 46, col.lightened(0.2))
	h.position = Vector2(26, 14)
	card.add_child(h)
	var tg := _lbl(tag, 17, INK)
	tg.position = Vector2(28, 84)
	card.add_child(tg)
	var y := 170.0
	for b in bullets:
		var bl := _lbl("-  " + String(b), 18, Color(0.8, 0.85, 0.9), true)
		bl.position = Vector2(30, y)
		bl.size = Vector2(w - 60, 60)
		card.add_child(bl)
		y += 78.0
	var dis := _btn(status, func(): pass, col, 22)
	dis.disabled = true
	dis.position = Vector2(30, 760)
	dis.size = Vector2(w - 60, 70)
	card.add_child(dis)


func _refresh_selection() -> void:
	var g := Battlegrounds.get_ground(GameSession.ground_id)
	var e := Roster.get_entry(GameSession.ship_id)
	if play_map_thumb != null and not g.is_empty():
		play_map_thumb.texture = MapData.thumbnail(g, 80)
		play_map_lbl.text = "%s\n%s" % [g["name"], g["date"]]
	if play_ship_lbl != null and not e.is_empty():
		play_ship_lbl.text = String(e["name"])
		play_ship_sub.text = "%s  -  %s" % [String(e["type"]).replace("_", " ").capitalize(), e["nation"]]
	for c in cards:
		c.selected = (c.ground["id"] == GameSession.ground_id)
		c.queue_redraw()


func _launch() -> void:
	GameSession.launch(GameSession.ground_id, GameSession.ship_id, get_tree())


# --- FLEET STORE ----------------------------------------------------------------

func _build_fleet() -> Control:
	var page := Control.new()
	page.position = Vector2(0, 92)
	page.size = Vector2(1920, 988)
	var left := Panel.new()
	left.add_theme_stylebox_override("panel", _style(PANEL, Color(0.25, 0.35, 0.48), 1))
	left.position = Vector2(24, 20)
	left.size = Vector2(420, 944)
	page.add_child(left)
	nation_filter = OptionButton.new()
	nation_filter.add_item("All nations")
	for n in Roster.nations():
		nation_filter.add_item(String(n))
	nation_filter.position = Vector2(14, 14)
	nation_filter.size = Vector2(190, 38)
	nation_filter.item_selected.connect(func(_i): _fill_list())
	left.add_child(nation_filter)
	type_filter = OptionButton.new()
	type_filter.add_item("All classes")
	for t in ["battleship", "heavy_cruiser", "light_cruiser", "destroyer", "escort", "carrier"]:
		type_filter.add_item(t.replace("_", " ").capitalize())
	type_filter.position = Vector2(216, 14)
	type_filter.size = Vector2(190, 38)
	type_filter.item_selected.connect(func(_i): _fill_list())
	left.add_child(type_filter)
	var sc := ScrollContainer.new()
	sc.position = Vector2(8, 64)
	sc.size = Vector2(404, 870)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(sc)
	ship_list = VBoxContainer.new()
	ship_list.custom_minimum_size = Vector2(392, 0)
	ship_list.add_theme_constant_override("separation", 6)
	sc.add_child(ship_list)

	viewer = ShipViewer.new()
	viewer.position = Vector2(460, 20)
	viewer.size = Vector2(800, 944)
	page.add_child(viewer)
	var vframe := Panel.new()
	vframe.add_theme_stylebox_override("panel", _style(Color(0, 0, 0, 0), Color(0.25, 0.35, 0.48), 1))
	vframe.position = viewer.position
	vframe.size = viewer.size
	vframe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(vframe)
	var hint := _lbl("drag to rotate  -  wheel to zoom", 13, DIM)
	hint.position = Vector2(480, 936)
	page.add_child(hint)

	var right := Panel.new()
	right.add_theme_stylebox_override("panel", _style(PANEL, Color(0.25, 0.35, 0.48), 1))
	right.position = Vector2(1276, 20)
	right.size = Vector2(620, 944)
	page.add_child(right)
	ship_title = _lbl("", 28, GOLD, true)
	ship_title.position = Vector2(20, 14)
	ship_title.size = Vector2(580, 40)
	right.add_child(ship_title)
	ship_sub = _lbl("", 16, DIM)
	ship_sub.position = Vector2(22, 56)
	right.add_child(ship_sub)
	stats = ShipStats.new()
	stats.position = Vector2(14, 100)
	stats.size = Vector2(596, 330)
	right.add_child(stats)
	ship_desc = _lbl("", 17, Color(0.82, 0.87, 0.92), true)
	ship_desc.position = Vector2(22, 450)
	ship_desc.size = Vector2(576, 150)
	right.add_child(ship_desc)
	ship_price = _lbl("", 26, INK)
	ship_price.position = Vector2(22, 760)
	right.add_child(ship_price)
	var own := _lbl("OWNED  (test build: every ship is unlocked)", 15, Color(0.5, 1.0, 0.6))
	own.position = Vector2(22, 800)
	right.add_child(own)
	select_btn = _btn("SELECT FOR SKIRMISH", _select_ship, Color(0.4, 0.9, 0.5), 24)
	select_btn.position = Vector2(22, 840)
	select_btn.size = Vector2(576, 78)
	right.add_child(select_btn)
	return page


func _fill_list() -> void:
	for c in ship_list.get_children():
		c.queue_free()
	_row_btns.clear()
	var nat := "" if nation_filter.selected <= 0 else nation_filter.get_item_text(nation_filter.selected)
	var typ := "" if type_filter.selected <= 0 else type_filter.get_item_text(type_filter.selected).to_lower().replace(" ", "_")
	var list: Array = Roster.available().duplicate()
	var order := ["battleship", "heavy_cruiser", "light_cruiser", "destroyer", "escort", "carrier", "submarine"]
	list.sort_custom(func(a, b):
		if a["nation"] != b["nation"]:
			return String(a["nation"]) < String(b["nation"])
		var ia := order.find(a["type"])
		var ib := order.find(b["type"])
		if ia != ib:
			return ia < ib
		return float(a["displacement_t"]) > float(b["displacement_t"]))
	for e in list:
		if nat != "" and e["nation"] != nat:
			continue
		if typ != "" and e["type"] != typ:
			continue
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(388, 66)
		b.text = "%s\n%s  -  %s" % [e["name"], String(e["type"]).replace("_", " ").capitalize(), e["nation"]]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 16)
		b.add_theme_color_override("font_color", INK)
		var id: String = e["id"]
		b.pressed.connect(_browse.bind(id))
		ship_list.add_child(b)
		_row_btns[id] = b
	_style_rows()


func _style_rows() -> void:
	for id in _row_btns:
		var b: Button = _row_btns[id]
		var sel: bool = (id == _browse_id)
		var chosen: bool = (id == GameSession.ship_id)
		var border := GOLD if sel else (Color(0.4, 0.9, 0.5) if chosen else Color(0.22, 0.3, 0.4))
		b.add_theme_stylebox_override("normal", _style(Color(0.2, 0.15, 0.06) if sel else Color(0.1, 0.14, 0.2), border, 2 if (sel or chosen) else 1))
		b.add_theme_stylebox_override("hover", _style(Color(0.16, 0.22, 0.31), GOLD, 2))
		b.add_theme_stylebox_override("pressed", _style(Color(0.25, 0.18, 0.06), GOLD, 2))


func _browse(id: String) -> void:
	var e := Roster.get_entry(id)
	if e.is_empty():
		return
	_browse_id = id
	ship_title.text = String(e["name"])
	ship_sub.text = "%s  -  %s  -  %s" % [e["nation"], String(e["type"]).replace("_", " ").capitalize(), "launched class"]
	ship_sub.text = "%s  -  %s" % [e["nation"], String(e["type"]).replace("_", " ").capitalize()]
	stats.show_entry(e)
	ship_desc.text = String(TYPE_BLURB.get(e["type"], "")) + "\n\n" + _detail(e)
	ship_price.text = "PRICE   %s credits  (placeholder)" % _price_str(e)
	viewer.show_ship(e)
	_style_rows()
	_update_select_btn()


func _detail(e: Dictionary) -> String:
	var g: Dictionary = e["main_gun"]
	var turrets := (e["turret_z"] as Array).size()
	return "%d turrets x %d guns, %d mm shells of %d kg at %d m/s. %d boiler rooms, %d engine rooms, %d screws, %d funnel(s)." % [
		turrets, int(g["barrels_per_turret"]), int(g["caliber_mm"]), int(g["shell_kg"]), int(g["muzzle_ms"]),
		int(e.get("boiler_rooms", 0)), int(e.get("engine_rooms", 0)), int(e.get("screws", 2)), int(e.get("funnels", 1))]


func _price_str(e: Dictionary) -> String:
	var mult := {"battleship": 3.2, "heavy_cruiser": 2.2, "light_cruiser": 1.6, "destroyer": 1.0, "escort": 0.7, "carrier": 3.0}
	var p := int(round(pow(float(e["displacement_t"]), 0.8) * float(mult.get(e["type"], 1.5)) / 50.0)) * 50
	var s := str(p)
	if s.length() > 3:
		s = s.insert(s.length() - 3, ",")
	return s


func _select_ship() -> void:
	GameSession.ship_id = _browse_id
	_refresh_selection()
	_style_rows()
	_update_select_btn()


func _update_select_btn() -> void:
	var on := (_browse_id == GameSession.ship_id)
	select_btn.text = "SELECTED FOR SKIRMISH" if on else "SELECT FOR SKIRMISH"
	select_btn.disabled = on


# --- MAPS -----------------------------------------------------------------------

func _build_maps() -> Control:
	var page := Control.new()
	page.position = Vector2(0, 92)
	page.size = Vector2(1920, 988)
	var title := _lbl("BATTLEGROUNDS  -  click a map for the 3D topographic view", 20, DIM)
	title.position = Vector2(36, 14)
	page.add_child(title)
	var sc := ScrollContainer.new()
	sc.position = Vector2(24, 54)
	sc.size = Vector2(1872, 920)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(sc)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	sc.add_child(grid)
	for g in Battlegrounds.all_grounds():
		var c := MapCard.new()
		c.setup(g)
		c.opened.connect(_open_topo)
		grid.add_child(c)
		cards.append(c)
	return page


func _queue_thumbs() -> void:
	_thumb_queue.clear()
	for i in cards.size():
		if cards[i].tex == null:
			_thumb_queue.append(i)


func _process(d: float) -> void:
	if _shot_path != "":
		_shot_t += d
		if _shot_t > _shot_secs:
			get_viewport().get_texture().get_image().save_png(_shot_path)
			get_tree().quit()
	if _tab == 2 and not _thumb_queue.is_empty() and not overlay.visible:
		var i: int = _thumb_queue.pop_front()
		cards[i].set_texture(MapData.thumbnail(cards[i].ground, 96))


func _build_overlay() -> void:
	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)


func _open_topo(gid: String) -> void:
	topo_gid = gid
	var g := Battlegrounds.get_ground(gid)
	for c in overlay.get_children():
		if c is ColorRect:
			continue
		c.queue_free()
	overlay.visible = true
	var wait := _lbl("Building 3D terrain...", 28, GOLD)
	wait.position = Vector2(780, 500)
	overlay.add_child(wait)
	await get_tree().process_frame
	await get_tree().process_frame
	topo = TopoView.new()
	topo.position = Vector2(30, 30)
	topo.size = Vector2(1290, 1020)
	overlay.add_child(topo)
	topo.setup(g)
	topo.observer_changed.connect(func(_p): _update_topo_info())
	wait.queue_free()
	var frame := Panel.new()
	frame.add_theme_stylebox_override("panel", _style(Color(0, 0, 0, 0), GOLD.darkened(0.3), 2))
	frame.position = topo.position
	frame.size = topo.size
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(frame)
	# side panel
	var side := Panel.new()
	side.add_theme_stylebox_override("panel", _style(PANEL, Color(0.25, 0.35, 0.48), 1))
	side.position = Vector2(1336, 30)
	side.size = Vector2(556, 1020)
	overlay.add_child(side)
	var t := _lbl(String(g["name"]), 28, GOLD, true)
	t.position = Vector2(20, 14)
	t.size = Vector2(516, 80)
	side.add_child(t)
	var d := _lbl("%s  -  %s" % [g["date"], String(g.get("weather", "clear")).capitalize()], 16, DIM)
	d.position = Vector2(22, 90)
	side.add_child(d)
	var bl := _lbl(String(g["blurb"]), 16, Color(0.82, 0.87, 0.92), true)
	bl.position = Vector2(22, 120)
	bl.size = Vector2(512, 80)
	side.add_child(bl)
	# legend + waypoint list
	var y := 215.0
	var sh := _lbl("LANDMARKS", 15, GOLD)
	sh.position = Vector2(22, y)
	side.add_child(sh)
	y += 26.0
	for wp in Battlegrounds.waypoints(gid):
		var sw := ColorRect.new()
		sw.color = MapData.kind_color(wp["k"])
		sw.position = Vector2(24, y + 6)
		sw.size = Vector2(12, 12)
		side.add_child(sw)
		var wl := _lbl("%s   (%s)" % [wp["n"], MapData.kind_label(wp["k"])], 15, INK)
		wl.position = Vector2(46, y)
		side.add_child(wl)
		y += 25.0
	y += 14.0
	var cv := _lbl("COVER AND CONCEALMENT", 15, GOLD)
	cv.position = Vector2(22, y)
	side.add_child(cv)
	y += 26.0
	var ex := _lbl("Click anywhere on the map to place a spotter (25 m eye height).\nAmber = in his line of sight. Dark = hidden behind land: cover for ships to hide and ambush.\nContours: land every 50 m; shallow water every 10 m (shoals).", 14, Color(0.78, 0.84, 0.9), true)
	ex.position = Vector2(22, y)
	ex.size = Vector2(512, 100)
	side.add_child(ex)
	y += 108.0
	topo_info = _lbl("", 16, Color(1.0, 0.9, 0.6), true)
	topo_info.position = Vector2(22, y)
	topo_info.size = Vector2(512, 70)
	side.add_child(topo_info)
	_update_topo_info()
	vis_btn = _btn("CONCEALMENT OVERLAY: ON", _toggle_vis, Color(1.0, 0.72, 0.15), 17)
	vis_btn.position = Vector2(22, 790)
	vis_btn.size = Vector2(512, 46)
	side.add_child(vis_btn)
	var zi := _btn("ZOOM +", func(): topo.zoom(0.8), GOLD.darkened(0.2), 17)
	zi.position = Vector2(22, 846)
	zi.size = Vector2(160, 42)
	side.add_child(zi)
	var zo := _btn("ZOOM -", func(): topo.zoom(1.25), GOLD.darkened(0.2), 17)
	zo.position = Vector2(194, 846)
	zo.size = Vector2(160, 42)
	side.add_child(zo)
	var rs := _btn("RESET", func(): topo.reset_camera(), GOLD.darkened(0.2), 17)
	rs.position = Vector2(366, 846)
	rs.size = Vector2(168, 42)
	side.add_child(rs)
	var dep := _btn("USE FOR SKIRMISH", _use_map, Color(0.4, 0.9, 0.5), 20)
	dep.position = Vector2(22, 900)
	dep.size = Vector2(300, 56)
	side.add_child(dep)
	var cl := _btn("CLOSE", _close_topo, Color(1.0, 0.4, 0.35), 20)
	cl.position = Vector2(334, 900)
	cl.size = Vector2(200, 56)
	side.add_child(cl)
	var tip := _lbl("drag to orbit  -  wheel to zoom", 13, DIM)
	tip.position = Vector2(22, 970)
	side.add_child(tip)


func _update_topo_info() -> void:
	if topo == null or topo_info == null:
		return
	var near := ""
	var best := 1e9
	for wp in Battlegrounds.waypoints(topo_gid):
		var dd: float = (wp["p"] as Vector2).distance_to(topo.observer)
		if dd < best:
			best = dd
			near = wp["n"]
	topo_info.text = "Spotter near %s (%.1f km).  Sees %d%% of the open water." % [near, best / 1000.0, int(topo.exposed_water_pct())]


func _toggle_vis() -> void:
	topo.set_vis_on(not topo.vis_on)
	vis_btn.text = "CONCEALMENT OVERLAY: " + ("ON" if topo.vis_on else "OFF")


func _use_map() -> void:
	GameSession.ground_id = topo_gid
	_refresh_selection()
	_close_topo()


func _close_topo() -> void:
	overlay.visible = false
	topo = null
	for c in overlay.get_children():
		if not c is ColorRect:
			c.queue_free()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and overlay.visible:
		_close_topo()
