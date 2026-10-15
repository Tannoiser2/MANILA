extends Control
## Vista di gioco: il porto in 3D al centro, i contrabbandieri a sinistra, mercato nero, dadi e
## cronaca a destra, le decisioni in basso. Le caselle selezionabili si illuminano sul tabellone.

const D = preload("res://scripts/data/mn_data.gd")
const LX := 12.0
const LW := 372.0
const RX := 1540.0
const RW := 368.0

var main
var config: Dictionary
var engine: MNEngine
var online = null
var humans: Array = []
var pending: Dictionary = {}
var board: Board3D

# nodi
var top_lbl: Label
var sub_lbl: Label
var rows_box: VBoxContainer
var market_box: VBoxContainer
var dice_box: HBoxContainer
var chron: RichTextLabel
var act_panel: PanelContainer
var act_title: Label
var act_body: VBoxContainer
var modal: Control
var tip: PanelContainer
var tip_lbl: Label
var online_lbl: Label
var odds_on := true
var target_map := {}          # chiave 3D -> indice dell'opzione
var target_info := {}         # chiave 3D -> testo del suggerimento
var load_sel := {}            # scelta in corso dei barconi
var last_dice: Array = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size = Vector2(1920, 1080)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	online = config.get("online", null)

	engine = MNEngine.new()
	add_child(engine)
	engine.setup(config)
	engine.ai_delay = config.get("ai_delay", 0.5)
	if online != null:
		humans = [online.seat]
		online.view = self
		add_child(online)
		engine.online = online
		if online.role != "host":
			online.heartbeat_loop()
	else:
		for s in engine.n:
			if not engine.players[s]["ai"]:
				humans.append(s)
	engine.pause_enabled = humans.size() > 0

	board = Board3D.new()
	board.eng = engine
	add_child(board)
	board.target_clicked.connect(_on_target)
	board.target_hovered.connect(_on_hover)

	_build_top()
	_build_left()
	_build_right()
	_build_action()
	modal = Control.new()
	modal.size = Vector2(1920, 1080)
	modal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(modal)
	tip = PanelContainer.new()
	tip.add_theme_stylebox_override("panel", UI.panel_style(Color("#06181aee"), UI.GOLD, 1, 6))
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_lbl = UI.label("", 20)
	tip.add_child(tip_lbl)
	tip.visible = false
	add_child(tip)
	_build_online_label()

	engine.changed.connect(refresh)
	engine.log_added.connect(_on_log)
	engine.decision_requested.connect(_on_decision)
	engine.pause_requested.connect(_on_pause)
	engine.game_ended.connect(_on_game_end)
	engine.fx.connect(_on_fx)
	refresh()
	if online != null and online.catchup:
		online_status("Riprendo la partita dal punto in cui era…")
	engine.run.call_deferred()


func _exit_tree() -> void:
	if engine != null:
		engine.abort = true


# =================================================================== costruzione

func _panel(pos: Vector2, sz: Vector2, alpha := 0.86) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.panel_style(Color(0.03, 0.09, 0.09, alpha), Color("#2f5d57"), 1, 8))
	p.position = pos
	p.size = sz
	p.custom_minimum_size = sz
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(p)
	return p


func _build_top() -> void:
	var p := _panel(Vector2(LX + LW + 10, 8), Vector2(RX - LX - LW - 20, 70), 0.8)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	p.add_child(hb)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 0)
	hb.add_child(vb)
	top_lbl = UI.title("MANILA", 26)
	vb.add_child(top_lbl)
	sub_lbl = UI.label("", 20, Color("#cfe3dc"))
	vb.add_child(sub_lbl)
	for spec in [["VISTA", func(): board.cycle_view()], ["DALL'ALTO", func(): board.reset_view(true)],
			["REGOLE", _show_rules_popup], ["DIARIO", _show_log], ["MENU", _ask_quit]]:
		var b := UI.button(spec[0], 0, 50, 20)
		b.custom_minimum_size.x = 96 if spec[0] != "DALL'ALTO" else 124
		b.pressed.connect(spec[1])
		hb.add_child(b)


func _build_left() -> void:
	var sc := ScrollContainer.new()
	sc.position = Vector2(LX, 8)
	sc.size = Vector2(LW, 1064)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(sc)
	rows_box = VBoxContainer.new()
	rows_box.add_theme_constant_override("separation", 8)
	rows_box.custom_minimum_size = Vector2(LW - 6, 0)
	sc.add_child(rows_box)


func _build_right() -> void:
	var p := _panel(Vector2(RX, 8), Vector2(RW, 1064))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	p.add_child(vb)
	vb.add_child(UI.title("MERCATO NERO", 24))
	market_box = VBoxContainer.new()
	market_box.add_theme_constant_override("separation", 4)
	vb.add_child(market_box)
	vb.add_child(HSeparator.new())
	var dl := UI.label("Ultimo tiro", 22, UI.GOLD, UI.font_bold)
	vb.add_child(dl)
	dice_box = HBoxContainer.new()
	dice_box.add_theme_constant_override("separation", 10)
	dice_box.custom_minimum_size = Vector2(0, 64)
	vb.add_child(dice_box)
	var odds := CheckBox.new()
	odds.text = "Probabilità sui barconi"
	odds.button_pressed = true
	odds.add_theme_font_size_override("font_size", 20)
	odds.toggled.connect(func(on):
		odds_on = on
		refresh())
	vb.add_child(odds)
	vb.add_child(HSeparator.new())
	vb.add_child(UI.label("Cronaca", 22, UI.GOLD, UI.font_bold))
	chron = RichTextLabel.new()
	chron.bbcode_enabled = true
	chron.scroll_following = true
	chron.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chron.add_theme_font_size_override("normal_font_size", 18)
	chron.add_theme_font_size_override("bold_font_size", 18)
	vb.add_child(chron)
	var help := UI.label("Trascina: ruota · rotella/pizzico: zoom\nTasto destro o Maiusc+trascina: sposta", 16, Color("#8fb3aa"))
	vb.add_child(help)


func _build_action() -> void:
	act_panel = PanelContainer.new()
	act_panel.add_theme_stylebox_override("panel", UI.panel_style(Color("#061615f0"), UI.GOLD, 2, 10))
	act_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	act_panel.custom_minimum_size = Vector2(RX - LX - LW - 40, 0)
	add_child(act_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	act_panel.add_child(vb)
	act_title = UI.label("", 24, Color.WHITE, UI.font_bold)
	act_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	act_title.custom_minimum_size = Vector2(RX - LX - LW - 70, 0)
	vb.add_child(act_title)
	act_body = VBoxContainer.new()
	act_body.add_theme_constant_override("separation", 8)
	vb.add_child(act_body)
	_place_action.call_deferred()


func _place_action() -> void:
	await get_tree().process_frame
	act_panel.size = Vector2.ZERO
	act_panel.reset_size()
	act_panel.position = Vector2(LX + LW + 20, 1072 - act_panel.size.y)


# =================================================================== aggiornamento

func refresh() -> void:
	if engine == null or not engine.setup_done:
		return
	board.refresh()
	_refresh_odds()
	_refresh_top()
	_refresh_rows()
	_refresh_market()
	if pending.is_empty():
		_idle_message()


func _phase_text() -> String:
	match engine.phase:
		"auction": return "Asta per la capitaneria"
		"hm": return "Il capitano del porto prepara i barconi"
		"place": return "Piazzamento dei complici · giro %d di %d" % [engine.place_round, engine.place_rounds]
		"roll": return "Navigazione · tiro %d di 3" % engine.roll_no
		"board": return "Abbordaggio dei pirati"
		"pilot": return "I piloti entrano in azione"
		"plunder": return "Saccheggio"
		"payout": return "Incasso dei profitti"
		"end": return "Fine della partita"
	return ""


func _refresh_top() -> void:
	top_lbl.text = "MANILA · VIAGGIO %d" % maxi(1, engine.voyage)
	var t := _phase_text()
	if engine.hm >= 0 and engine.phase != "auction":
		t += " · capitano del porto: %s" % engine.pname(engine.hm)
	if engine.phase == "auction" and not engine.auction.is_empty():
		if engine.opts.get("bgg", false):
			t += " · offerte segrete"
		elif int(engine.auction.get("leader", -1)) >= 0:
			t += " · offerta più alta: %d (%s)" % [engine.auction["cur"], engine.pname(engine.auction["leader"])]
	if engine.roll_no > 0 and engine.phase in ["place", "pilot"]:
		t += " · tiri fatti: %d" % engine.roll_no
	sub_lbl.text = t


func _can_see(s: int) -> bool:
	if online != null:
		return s == online.seat
	if engine.players[s]["ai"]:
		return engine.game_over
	if humans.size() == 1:
		return true
	return engine.current == s and not pending.is_empty() or engine.game_over


func _refresh_rows() -> void:
	for c in rows_box.get_children():
		rows_box.remove_child(c)
		c.queue_free()
	for s in engine.n:
		rows_box.add_child(_player_row(s))


func _player_row(s: int) -> Control:
	var p: Dictionary = engine.players[s]
	var col: Color = D.COLORS[p["color"]]["light"]
	var box := PanelContainer.new()
	var active: bool = engine.current == s and not engine.game_over
	box.add_theme_stylebox_override("panel", UI.panel_style(Color(0.03, 0.09, 0.09, 0.9), col if active else Color("#2f5d57"), 3 if active else 1, 8))
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	box.add_child(vb)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	vb.add_child(hb)
	hb.add_child(UI.icon_rect(UI.pawn(p["color"]), Vector2(44, 44)))
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", -4)
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(nv)
	var nm := UI.label(p["name"] + ("  (IA)" if p["ai"] else ""), 24, col, UI.font_bold)
	nm.clip_text = true
	nm.custom_minimum_size = Vector2(150, 0)
	nv.add_child(nm)
	var tags := []
	if engine.hm == s:
		tags.append("CAPITANO DEL PORTO")
	if engine.phase in ["place", "roll", "pilot", "board"] and engine.passed.size() > s and engine.passed[s]:
		tags.append("ha passato")
	if engine.phase == "auction" and engine.auction.get("out", {}).has(s):
		tags.append("fuori dall'asta")
	if engine.phase == "auction" and int(engine.auction.get("leader", -1)) == s and not engine.opts.get("bgg", false):
		tags.append("offre %d" % engine.auction["cur"])
	nv.add_child(UI.label(" · ".join(tags), 17, UI.GOLD))
	var money := HBoxContainer.new()
	money.add_theme_constant_override("separation", 4)
	money.add_child(UI.icon_rect(UI.coin(1), Vector2(30, 30)))
	money.add_child(UI.label("%d" % p["cash"], 28, Color.WHITE, UI.font_bold))
	hb.add_child(money)
	# quote
	var sh := HBoxContainer.new()
	sh.add_theme_constant_override("separation", 3)
	vb.add_child(sh)
	var see := _can_see(s)
	var shares: Array = p["shares"].duplicate()
	shares.sort_custom(func(a, b): return a["w"] < b["w"])
	for x in shares:
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(34, 56)
		var r := UI.icon_rect(UI.card(x["w"]) if see else UI.card_back(), Vector2(34, 56))
		if x["m"]:
			r.modulate = Color(0.55, 0.45, 0.45)
		holder.add_child(r)
		if x["m"]:
			var ml := UI.label("12", 16, UI.RED, UI.font_bold)
			ml.position = Vector2(6, 34)
			ml.add_theme_color_override("font_outline_color", Color.BLACK)
			ml.add_theme_constant_override("outline_size", 4)
			holder.add_child(ml)
		holder.tooltip_text = ("%s, %s" % [D.ware_name(x["w"]), "impegnata (12 ricevuti, 15 da restituire)" if x["m"] else "libera"]) if see else ("quota coperta" + (", impegnata" if x["m"] else ""))
		holder.mouse_filter = Control.MOUSE_FILTER_STOP
		sh.add_child(holder)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sh.add_child(sp)
	# complici ancora in mano
	var hand := 0
	if engine.hand.size() > s:
		hand = engine.hand[s]
	for k in hand:
		sh.add_child(UI.icon_rect(UI.pawn(p["color"]), Vector2(26, 34)))
	if see:
		vb.add_child(UI.label("Patrimonio ora: %d" % engine.wealth(s), 17, Color("#9fc4ba")))
	return box


func _refresh_market() -> void:
	for c in market_box.get_children():
		market_box.remove_child(c)
		c.queue_free()
	for w in 4:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		hb.add_child(UI.icon_rect(UI.card(w), Vector2(30, 48)))
		var nm := UI.label(D.ware_name(w), 22, D.WARES[w]["light"], UI.font_bold)
		nm.custom_minimum_size = Vector2(130, 0)
		hb.add_child(nm)
		var idx: int = engine.market[w]
		var bar := HBoxContainer.new()
		bar.add_theme_constant_override("separation", 2)
		for k in 5:
			var cell := Panel.new()
			cell.custom_minimum_size = Vector2(24, 26)
			var on := k == idx
			cell.add_theme_stylebox_override("panel", UI.panel_style(D.WARES[w]["color"] if k <= idx else Color("#0a1716"), UI.GOLD if on else Color("#2f5d57"), 2 if on else 1, 3))
			cell.tooltip_text = "%d" % D.MARKET[k]
			bar.add_child(cell)
		hb.add_child(bar)
		var vl := UI.label("%d" % D.MARKET[idx], 26, Color.WHITE, UI.font_bold)
		vl.custom_minimum_size = Vector2(36, 0)
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hb.add_child(vl)
		hb.tooltip_text = "%s: vale %d · quote disponibili %d · prezzo %d" % [D.ware_name(w), D.MARKET[idx], engine.supply[w], engine.share_price(w)]
		hb.mouse_filter = Control.MOUSE_FILTER_STOP
		market_box.add_child(hb)
	market_box.add_child(UI.label("Quote in vendita: %s" % "  ".join(range(4).map(func(w): return "%s %d" % [D.WARES[w]["short"], engine.supply[w]])), 17, Color("#9fc4ba")))


func _refresh_dice() -> void:
	for c in dice_box.get_children():
		c.queue_free()
	for i in last_dice.size():
		if i >= engine.boats.size():
			break
		dice_box.add_child(UI.icon_rect(UI.die_tex(engine.boats[i]["w"], last_dice[i]), Vector2(58, 58)))


## Probabilità di arrivo sopra i barconi in mare.
func _refresh_odds() -> void:
	for bn in board.boat_nodes:
		var l: Label3D = bn.get_node_or_null("Odds")
		if l != null:
			l.visible = false
	if not odds_on or engine.boats.is_empty():
		return
	var r := 3 - engine.roll_no
	for i in engine.boats.size():
		if i >= board.boat_nodes.size():
			break
		var b: Dictionary = engine.boats[i]
		var bn2: Node3D = board.boat_nodes[i]
		var l2: Label3D = bn2.get_node_or_null("Odds")
		if l2 == null:
			l2 = Label3D.new()
			l2.name = "Odds"
			l2.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			l2.font_size = 52
			l2.pixel_size = 0.006
			l2.outline_size = 14
			l2.modulate = Color("#fff2c0")
			l2.position = Vector3(0, 1.1, BOAT_TOP)
			l2.no_depth_test = true
			bn2.add_child(l2)
		if b["at"] != "sea":
			continue
		var dd := MNAI.dist(int(b["pos"]), r)
		l2.text = "arriva %d%%\nsul 13: %d%%" % [roundi(dd[0] * 100), roundi(dd[1] * 100)]
		l2.visible = true

const BOAT_TOP := -1.9


func _idle_message() -> void:
	_clear_body()
	board.set_targets({})
	if engine.game_over:
		act_title.text = "Partita finita."
		_place_action.call_deferred()
		return
	var s := engine.current
	var t := ""
	var thinking: bool = engine.phase in ["auction", "hm", "place", "board", "pilot", "plunder"]
	if thinking and s >= 0 and s < engine.n and engine.players[s]["ai"]:
		t = "%s sta pensando…" % engine.pname(s)
	elif thinking and online != null and s >= 0 and s != online.seat:
		t = "Tocca a %s…" % engine.pname(s)
	if engine.log_lines.size() > 0:
		t = (t + "\n" if t != "" else "") + str(engine.log_lines[-1])
	act_title.text = t
	_place_action.call_deferred()


func _on_log(t: String) -> void:
	var line := t
	if t.begins_with("—"):
		line = "\n[b][color=#f0c24f]%s[/color][/b]" % t
	chron.append_text(line + "\n")
	if pending.is_empty():
		_idle_message()


func _on_fx(kind: String, data: Dictionary) -> void:
	match kind:
		"roll":
			last_dice = data["dice"]
			board.roll_dice(last_dice)
			_refresh_dice()
		"launch":
			last_dice = []
			_refresh_dice()
			board.set_preview({})


# =================================================================== decisioni

func _who() -> String:
	return "%s, tocca a te: " % engine.pname(int(pending["seat"])) if humans.size() > 1 else ""


func _clear_body() -> void:
	for c in act_body.get_children():
		act_body.remove_child(c)
		c.queue_free()
	target_map = {}
	target_info = {}


func _on_decision(req: Dictionary) -> void:
	if req.get("secret", false) and humans.size() > 1 and online == null and not req.get("_shown", false):
		req["_shown"] = true
		_curtain(int(req["seat"]), func(): _on_decision(req))
		return
	pending = req
	refresh()
	_clear_body()
	act_title.text = _who() + str(req.get("title", "")) + ("  ·  clic su un anello luminoso o su un pulsante" if req["type"] == "place" else "")
	match str(req["type"]):
		"bid":
			_bid_ui(req, false)
		"bid_blind":
			_bid_ui(req, true)
		"buy":
			_buy_ui(req)
		"load":
			_load_ui(req)
		"place":
			_place_ui(req)
		"board", "pilot", "plunder":
			_options_ui(req)
		_:
			_provide(null)
			return
	_place_action.call_deferred()


func _provide(r) -> void:
	pending = {}
	_clear_body()
	board.set_targets({})
	tip.visible = false
	refresh()
	engine.provide_decision(r)


func _flow() -> HFlowContainer:
	var f := HFlowContainer.new()
	f.custom_minimum_size = Vector2(RX - LX - LW - 70, 0)
	f.add_theme_constant_override("h_separation", 8)
	f.add_theme_constant_override("v_separation", 8)
	act_body.add_child(f)
	return f


func _bid_ui(req: Dictionary, blind: bool) -> void:
	var mx: int = req["max"]
	var mn: int = 0 if blind else int(req["cur"]) + 1
	var cash: int = engine.players[req["seat"]]["cash"]
	var val := [clampi(mn, mn, mx)]
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	act_body.add_child(hb)
	var lbl := UI.label("", 34, UI.GOLD, UI.font_bold)
	lbl.custom_minimum_size = Vector2(90, 0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var info := UI.label("", 19, Color("#9fc4ba"))
	var upd := func():
		lbl.text = str(val[0])
		info.text = "contanti %d · massimo con i prestiti %d" % [cash, mx] + ("  (dovrai impegnare quote)" if val[0] > cash else "")
	for d in [-5, -1]:
		var b := UI.button("%d" % d, 70, 52, 22)
		b.pressed.connect(func():
			val[0] = clampi(val[0] + d, mn, mx)
			upd.call())
		hb.add_child(b)
	hb.add_child(lbl)
	for d in [1, 5]:
		var b2 := UI.button("+%d" % d, 70, 52, 22)
		b2.pressed.connect(func():
			val[0] = clampi(val[0] + d, mn, mx)
			upd.call())
		hb.add_child(b2)
	var ok := UI.primary(UI.button("CONFERMA" if blind else "OFFRI", 180, 52, 22))
	ok.pressed.connect(func(): _provide(val[0]))
	hb.add_child(ok)
	if not blind:
		var ps := UI.button("PASSA", 150, 52, 22)
		ps.pressed.connect(func(): _provide(0))
		hb.add_child(ps)
	act_body.add_child(info)
	upd.call()


func _buy_ui(req: Dictionary) -> void:
	var f := _flow()
	for w in req["options"]:
		var b := Button.new()
		b.custom_minimum_size = Vector2(150, 120)
		b.icon = UI.card(w)
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "%s\n%d pesos" % [D.WARES[w]["short"], engine.share_price(w)]
		b.add_theme_font_size_override("font_size", 20)
		b.tooltip_text = "%s vale ora %d al mercato nero; ne restano %d." % [D.ware_name(w), D.MARKET[engine.market[w]], engine.supply[w]]
		b.pressed.connect(func(): _provide(w))
		f.add_child(b)
	var no := UI.button("NESSUNA QUOTA", 220, 120, 22)
	no.pressed.connect(func(): _provide(-1))
	f.add_child(no)


func _load_ui(req: Dictionary) -> void:
	var s: int = req["seat"]
	var sugg: Dictionary = engine.ais[s].default_load(engine, s) if engine.players[s]["level"] >= 0 else {}
	load_sel = {"ex": int(sugg.get("ex", 1)), "p": sugg.get("p", [3, 3, 3]).duplicate()}
	_load_body()


func _load_body() -> void:
	_clear_body()
	act_body.add_child(UI.label("Merce che resta a terra:", 20, Color("#cfe3dc")))
	var f := _flow()
	for w in 4:
		var b := Button.new()
		b.custom_minimum_size = Vector2(150, 64)
		b.text = D.WARES[w]["short"]
		b.icon = UI.card(w)
		b.expand_icon = true
		b.add_theme_font_size_override("font_size", 20)
		if w == load_sel["ex"]:
			b.add_theme_stylebox_override("normal", UI.panel_style(Color("#5a2a1a"), UI.RED, 3, 5))
			b.text += " (a terra)"
		b.pressed.connect(func():
			load_sel["ex"] = w
			_load_body())
		f.add_child(b)
	var sum := 0
	for v in load_sel["p"]:
		sum += int(v)
	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 24)
	act_body.add_child(grid)
	var lane := 0
	for w in 4:
		if w == load_sel["ex"]:
			continue
		var li := lane
		var col := VBoxContainer.new()
		col.add_child(UI.label(D.ware_name(w), 20, D.WARES[w]["light"], UI.font_bold))
		var row := HBoxContainer.new()
		var m := UI.button("−", 48, 46, 24)
		m.text = "-"
		m.pressed.connect(func():
			load_sel["p"][li] = maxi(0, int(load_sel["p"][li]) - 1)
			_load_body())
		row.add_child(m)
		var vl := UI.label(str(load_sel["p"][li]), 30, Color.WHITE, UI.font_bold)
		vl.custom_minimum_size = Vector2(40, 0)
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(vl)
		var pl := UI.button("+", 48, 46, 24)
		pl.pressed.connect(func():
			load_sel["p"][li] = mini(5, int(load_sel["p"][li]) + 1)
			_load_body())
		row.add_child(pl)
		col.add_child(row)
		var dd := MNAI.dist(int(load_sel["p"][li]), 3)
		col.add_child(UI.label("arriva %d%%" % roundi(dd[0] * 100), 17, Color("#9fc4ba")))
		grid.add_child(col)
		lane += 1
	var right := VBoxContainer.new()
	right.add_child(UI.label("Somma: %d / 9" % sum, 24, UI.GREEN if sum == 9 else UI.RED, UI.font_bold))
	var ok := UI.primary(UI.button("METTI IN ACQUA", 230, 52, 22))
	ok.disabled = sum != 9
	ok.pressed.connect(func():
		board.set_preview({})
		_provide({"ex": load_sel["ex"], "p": load_sel["p"].duplicate()}))
	right.add_child(ok)
	grid.add_child(right)
	board.set_preview({"ex": load_sel["ex"], "p": load_sel["p"].duplicate()})
	_place_action.call_deferred()


func _spot_tip(id: String) -> String:
	var sp: Dictionary = D.SPOTS[id]
	match sp["kind"]:
		"harbor":
			var nth: String = ["primo", "secondo", "terzo"][int(sp["slot"])]
			return "%s: costa %d, rende %d se attracca il %s barcone." % [sp["name"], sp["cost"], sp["reward"], nth]
		"yard":
			var nth2: String = ["primo", "secondo", "terzo"][int(sp["slot"])]
			return "%s: costa %d, rende %d se naufraga il %s barcone (paga l'assicuratore)." % [sp["name"], sp["cost"], sp["reward"], nth2]
		"pirate":
			return "%s: costa 5. Dopo il 2° tiro può abbordare un barcone sul 13; dopo il 3° saccheggia i barconi sul 13." % sp["name"]
		"pilot":
			return "Vice pilota: sposta un barcone di 1." if id == "L0" else "Capo pilota: sposta un barcone di 2 o due barconi di 1."
		"insurance":
			return "Assicuratore: incassi subito 10, ma paghi le riparazioni dei barconi in cantiere (6, 8, 15)."
		"sick":
			return "Malattia: gratis, a fine viaggio prendi 1 peso."
	return sp["name"]


func _place_ui(req: Dictionary) -> void:
	var options: Array = req["options"]
	var s: int = req["seat"]
	var targets := {}
	var f := _flow()
	var ai: MNAI = engine.ais[s]
	for i in options.size():
		var o: Dictionary = options[i]
		var txt: String = o["label"]
		if o["k"] != "pass":
			if int(o["cost"]) < 0:
				txt += "  (+%d)" % -int(o["cost"])
			elif int(o["cost"]) > 0:
				txt += "  (%d)" % int(o["cost"])
		var b := UI.button(txt, 0, 44, 19)
		var idx := i
		b.pressed.connect(func(): _provide(idx))
		var tipt := ""
		if o["k"] == "boat":
			var key := "b%d" % int(o["b"])
			targets[key] = board.boat_slot_pos(int(o["b"]), int(o["slot"]))
			target_map[key] = i
			var bb: Dictionary = engine.boats[int(o["b"])]
			var cnt := 0
			for rr in bb["riders"]:
				if rr != -1:
					cnt += 1
			tipt = "%s (vale %d): posto da %d. Se arriva, il carico si divide fra %d o più complici." % [D.ware_name(bb["w"]), D.WARES[bb["w"]]["value"], int(o["cost"]), cnt + 1]
			target_info[key] = tipt
		elif o["k"] == "spot":
			targets[o["id"]] = board.spot_pos(o["id"])
			target_map[o["id"]] = i
			tipt = _spot_tip(o["id"])
			if int(o["cost"]) != int(D.SPOTS[o["id"]]["cost"]) and o["id"] != "I":
				tipt += " (ora costa %d)" % int(o["cost"])
			target_info[o["id"]] = tipt
		elif o["k"] == "wager":
			tipt = "Se un barcone arriva in quella casella guadagni il doppio della scommessa."
		b.tooltip_text = tipt
		if o["k"] == "pass":
			b.add_theme_color_override("font_color", Color("#ffb0a0"))
		f.add_child(b)
	board.set_targets(targets)
	# suggerimento leggero: la mossa che l'IA giudica migliore
	var best: int = ai._place(engine, s, req) if config.get("hints", true) else -1
	if best >= 0 and best < f.get_child_count():
		var bb2: Button = f.get_child(best)
		bb2.add_theme_stylebox_override("normal", UI.panel_style(Color("#173f2c"), UI.GREEN, 2, 5))
		bb2.tooltip_text += "\n(consiglio dell'IA)"


func _options_ui(req: Dictionary) -> void:
	var options: Array = req["options"]
	var targets := {}
	var f := _flow()
	for i in options.size():
		var o: Dictionary = options[i]
		var b := UI.button(str(o["label"]), 0, 48, 20)
		var idx := i
		b.pressed.connect(func(): _provide(idx))
		f.add_child(b)
		if req["type"] == "board" and o["k"] == "board":
			var key := "b%d" % int(o["b"])
			targets[key] = board.boat_slot_pos(int(o["b"]), int(o["slot"]))
			target_map[key] = i
			target_info[key] = o["label"]
	if req["type"] == "pilot":
		var s: int = req["seat"]
		var best: int = engine.ais[s]._pilot(engine, s, req)
		if best >= 0 and best < f.get_child_count():
			(f.get_child(best) as Button).add_theme_stylebox_override("normal", UI.panel_style(Color("#173f2c"), UI.GREEN, 2, 5))
	board.set_targets(targets)


func _on_target(key: String) -> void:
	if pending.is_empty() or not target_map.has(key):
		return
	_provide(target_map[key])


func _on_hover(key: String) -> void:
	if key == "" or not target_info.has(key):
		tip.visible = false
		return
	tip_lbl.text = target_info[key]
	tip.reset_size()
	var mp := get_viewport().get_mouse_position()
	tip.position = (mp + Vector2(18, 18)).clamp(Vector2.ZERO, Vector2(1920, 1080) - tip.size)
	tip.visible = true


# =================================================================== finestre

func _clear_modal() -> void:
	for c in modal.get_children():
		modal.remove_child(c)
		c.queue_free()
	modal.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _open_modal(title_text: String, w := 700.0) -> VBoxContainer:
	_clear_modal()
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.5)
	shade.size = Vector2(1920, 1080)
	modal.add_child(shade)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UI.panel_style(Color("#061615f6"), UI.GOLD, 2, 10))
	box.custom_minimum_size = Vector2(w, 0)
	modal.add_child(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	box.add_child(vb)
	var t := UI.title(title_text, 32)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(w - 30, 0)
	vb.add_child(t)
	_center_full.call_deferred(box)
	return vb


func _center_full(box: Control) -> void:
	if not is_instance_valid(box):
		return
	box.reset_size()
	box.position = Vector2(960, 520) - box.size / 2.0


func _curtain(s: int, then: Callable) -> void:
	_clear_modal()
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.03, 0.03, 0.97)
	shade.size = Vector2(1920, 1080)
	modal.add_child(shade)
	var vb := VBoxContainer.new()
	vb.position = Vector2(700, 360)
	vb.add_theme_constant_override("separation", 20)
	modal.add_child(vb)
	vb.add_child(UI.icon_rect(UI.pawn(engine.players[s]["color"]), Vector2(120, 120)))
	vb.add_child(UI.title("Tocca a %s" % engine.pname(s), 44))
	vb.add_child(UI.label("Offerta segreta: gli altri non guardino lo schermo.", 24))
	var b := UI.primary(UI.button("SONO PRONTO", 280, 60, 26))
	b.pressed.connect(func():
		_clear_modal()
		then.call())
	vb.add_child(b)


func _on_pause(req: Dictionary) -> void:
	if req.get("type", "") != "voyage_end":
		engine.provide_decision(null)
		return
	var vb := _open_modal("Fine del viaggio %d" % int(req["voyage"]), 760)
	for s in engine.n:
		var items: Array = engine.income.get(s, [])
		var tot := 0
		var parts := []
		for it in items:
			tot += int(it[1])
			parts.append("%s %s%d" % [it[0], "+" if it[1] >= 0 else "", it[1]])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(UI.icon_rect(UI.pawn(engine.players[s]["color"]), Vector2(40, 40)))
		var nm := UI.label(engine.pname(s), 24, D.COLORS[engine.players[s]["color"]]["light"], UI.font_bold)
		nm.custom_minimum_size = Vector2(170, 0)
		row.add_child(nm)
		var tl := UI.label(("%s%d" % ["+" if tot >= 0 else "", tot]) if not items.is_empty() else "—", 26, UI.GOLD if tot > 0 else Color.WHITE, UI.font_bold)
		tl.custom_minimum_size = Vector2(70, 0)
		row.add_child(tl)
		var dl := UI.label(", ".join(parts), 18, Color("#cfe3dc"))
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dl.custom_minimum_size = Vector2(430, 0)
		row.add_child(dl)
		vb.add_child(row)
	var mk := []
	for w in 4:
		mk.append("%s %d" % [D.WARES[w]["short"], D.MARKET[engine.market[w]]])
	vb.add_child(UI.label("Mercato nero: " + "  ·  ".join(mk), 21, Color("#9fc4ba")))
	if req.get("over", false):
		vb.add_child(UI.label("Una merce ha raggiunto 30: la partita è finita!", 24, UI.GOLD, UI.font_bold))
	var ok := UI.primary(UI.button("RISULTATI" if req.get("over", false) else "PROSSIMO VIAGGIO", 300, 58, 24))
	ok.pressed.connect(func():
		_clear_modal()
		engine.provide_decision(null))
	vb.add_child(ok)


func _on_game_end(results: Array) -> void:
	if online != null:
		online.finish()
		online_status("")
	refresh()
	var vb := _open_modal("%s è il contrabbandiere più bravo di Manila!" % engine.pname(results[0]["seat"]), 900)
	vb.add_child(UI.label("Patrimonio = pesos + valore delle quote − 15 per ogni quota ancora impegnata.", 20, Color("#cfe3dc")))
	var place := 1
	for e in results:
		var p: Dictionary = engine.players[e["seat"]]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		row.add_child(UI.title("%d°" % place, 34, Color.WHITE))
		row.add_child(UI.icon_rect(UI.pawn(p["color"]), Vector2(52, 52)))
		var nm := UI.label(p["name"] + (" (IA)" if p["ai"] else ""), 28, D.COLORS[p["color"]]["light"], UI.font_bold)
		nm.custom_minimum_size = Vector2(300, 0)
		row.add_child(nm)
		var wl := UI.label("%d" % e["wealth"], 32, UI.GOLD, UI.font_bold)
		wl.custom_minimum_size = Vector2(70, 0)
		wl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(wl)
		row.add_child(UI.label("   pesos %d · quote %d%s" % [e["cash"], e["shares"], (" · prestiti −%d" % (15 * e["mort"])) if e["mort"] > 0 else ""], 22, Color("#cfe3dc")))
		vb.add_child(row)
		place += 1
	var br := HBoxContainer.new()
	br.add_theme_constant_override("separation", 16)
	br.alignment = BoxContainer.ALIGNMENT_CENTER
	if online == null:
		var again := UI.primary(UI.button("RIGIOCA", 220, 60, 26))
		again.pressed.connect(func():
			var cfg := config.duplicate(true)
			cfg.erase("seed")
			main.start_game(cfg))
		br.add_child(again)
	var see := UI.button("GUARDA IL PORTO", 260, 60, 24)
	see.pressed.connect(func():
		_clear_modal()
		_clear_body()
		act_title.text = "Partita finita."
		var m := UI.button("RISULTATI", 180, 50, 22)
		m.pressed.connect(func(): _on_game_end(results))
		var f := _flow()
		f.add_child(m)
		var mm := UI.button("MENU", 140, 50, 22)
		mm.pressed.connect(func(): main.show_menu())
		f.add_child(mm)
		_place_action.call_deferred())
	br.add_child(see)
	var menu := UI.button("MENU", 180, 60, 26)
	menu.pressed.connect(func(): main.show_menu())
	br.add_child(menu)
	vb.add_child(br)


func _ask_quit() -> void:
	var layer := Control.new()
	layer.size = Vector2(1920, 1080)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(layer)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.size = layer.size
	layer.add_child(shade)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UI.panel_style(Color("#061615f8"), UI.GOLD, 2, 10))
	box.position = Vector2(660, 400)
	layer.add_child(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	box.add_child(vb)
	vb.add_child(UI.title("Tornare al menu?", 32))
	vb.add_child(UI.label("La partita in corso andrà persa." if online == null else "Potrai rientrare nella stanza con lo stesso codice.", 22))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	var y := UI.primary(UI.button("SÌ, AL MENU", 240, 56, 24))
	y.pressed.connect(func(): main.show_menu())
	var no := UI.button("CONTINUA A GIOCARE", 300, 56, 24)
	no.pressed.connect(func(): layer.queue_free())
	hb.add_child(y)
	hb.add_child(no)
	vb.add_child(hb)


func _show_rules_popup() -> void:
	var layer := Control.new()
	layer.size = Vector2(1920, 1080)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(layer)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.75)
	shade.size = layer.size
	layer.add_child(shade)
	var rv := preload("res://scripts/ui/rules_view.gd").new()
	rv.embedded = true
	rv.on_close = func(): layer.queue_free()
	layer.add_child(rv)


func _show_log() -> void:
	var layer := Control.new()
	layer.size = Vector2(1920, 1080)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(layer)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.7)
	shade.size = layer.size
	layer.add_child(shade)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UI.panel_style(Color("#061615f8"), UI.GOLD, 2, 10))
	box.position = Vector2(360, 70)
	box.size = Vector2(1200, 940)
	layer.add_child(box)
	var vb := VBoxContainer.new()
	box.add_child(vb)
	vb.add_child(UI.title("DIARIO DELLA PARTITA", 30))
	var t := RichTextLabel.new()
	t.custom_minimum_size = Vector2(1170, 800)
	t.scroll_following = true
	t.add_theme_font_size_override("normal_font_size", 20)
	t.text = "\n".join(engine.log_lines)
	vb.add_child(t)
	var c := UI.button("CHIUDI", 180, 50, 22)
	c.pressed.connect(func(): layer.queue_free())
	vb.add_child(c)


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed:
		match ev.keycode:
			KEY_Q: board.rotate_view(-30)
			KEY_E: board.rotate_view(30)
			KEY_HOME: board.reset_view(false)


# =================================================================== online

func _build_online_label() -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.panel_style(Color("#000000cc"), UI.GOLD, 2, 8))
	p.position = Vector2(LX + LW + 20, 90)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	online_lbl = UI.label("", 22, Color.WHITE)
	p.add_child(online_lbl)
	add_child(p)
	p.visible = false
	online_lbl.set_meta("box", p)


func online_status(t: String) -> void:
	if online_lbl == null:
		return
	online_lbl.text = t
	(online_lbl.get_meta("box") as Control).visible = t != ""


func online_waiting(seat: int, is_slow: bool) -> void:
	if seat < 0:
		online_status("")
		return
	var t := "Online · stanza %s · tocca a %s" % [online.code, engine.pname(seat)]
	if is_slow:
		t += " (sta pensando da più di un minuto)"
	online_status(t)


func online_caught_up() -> void:
	online_status("")
	refresh()


## L'IA ha già giocato al posto di questo giocatore: si chiude il dialogo aperto.
func online_cancel_decision(t: String) -> void:
	pending = {}
	_clear_modal()
	_clear_body()
	board.set_targets({})
	refresh()
	online_status(t)
