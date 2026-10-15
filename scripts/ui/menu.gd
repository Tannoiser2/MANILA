extends Control
## Menu principale: il dipinto della scatola, la ciurma su una pergamena (Umano / IA / Assente),
## livello e velocità dell'IA, varianti, gioco online.

const MODES := ["Umano", "IA", "Assente"]
const D = preload("res://scripts/data/mn_data.gd")

var main
var seat_mode := [0, 1, 1, 1, 2]      # 0 umano, 1 IA, 2 assente
var tiles := {}
var level := 1
var speed := 1
var mods := {}
var msg: Label
var mods_lbl: Label

const MOD_LIST := [
	["bgg", "Variante consigliata di BGG", "Asta a mano chiusa (offerte segrete rivelate insieme; a parità vince il primo a sinistra del capitano uscente) e giro di piazzamento dopo il primo tiro in senso antiorario, partendo sempre dal capitano del porto."],
	["pirates", "Pirati forti", "Regola opzionale del regolamento: all'abbordaggio, se non ci sono posti liberi, il pirata può scalzare un complice."],
	["five", "Scelte extra per 5 giocatori", "Solo in 5 (variante BGG): piloti scontati nell'ultimo giro (1 e 3), scommessa 1-3 pesos con un dado su un proprio molo/cantiere (vinci il doppio), casella Malattia gratuita (1 peso). Attiva anche i pirati forti."],
	["nohints", "Niente consigli dell'IA", "Non evidenzia la mossa che l'IA consiglia."],
]

const NICK := ["Il Corvo", "La Volpe d'Oro", "Sole di Luzon", "Onda Blu", "Corallo Rosso"]


func _ready() -> void:
	size = Vector2(1920, 1080)
	if main.menu_state.has("seat_mode"):
		seat_mode = main.menu_state["seat_mode"].duplicate()
		level = main.menu_state["level"]
		speed = main.menu_state["speed"]
		mods = main.menu_state.get("mods", {}).duplicate()
	# mare turchese dietro, dipinto della scatola a destra
	var sea_bg := TextureRect.new()
	var grad := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color("#0d6e74"))
	g.set_color(1, Color("#06333a"))
	grad.gradient = g
	grad.fill_from = Vector2(0, 0)
	grad.fill_to = Vector2(0.4, 1)
	sea_bg.texture = grad
	sea_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sea_bg.stretch_mode = TextureRect.STRETCH_SCALE
	sea_bg.size = Vector2(1920, 1080)
	add_child(sea_bg)
	var art := TextureRect.new()
	var at := AtlasTexture.new()
	at.atlas = UI.tex("res://assets/ui/cover.jpg")
	at.region = Rect2(40, 250, 840, 630)
	art.texture = at
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.position = Vector2(820, 0)
	art.size = Vector2(1100, 1080)
	add_child(art)
	var fade := TextureRect.new()
	var fg := GradientTexture2D.new()
	var g2 := Gradient.new()
	g2.set_color(0, Color(0.03, 0.25, 0.27, 1.0))
	g2.set_color(1, Color(0.03, 0.25, 0.27, 0.0))
	fg.gradient = g2
	fg.fill_from = Vector2(0, 0)
	fg.fill_to = Vector2(1, 0)
	fade.texture = fg
	fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fade.stretch_mode = TextureRect.STRETCH_SCALE
	fade.position = Vector2(820, 0)
	fade.size = Vector2(300, 1080)
	add_child(fade)

	var logo := UI.icon_rect(UI.tex("res://assets/ui/logo.png"), Vector2(640, 180))
	logo.position = Vector2(80, 14)
	add_child(logo)
	var tag := UI.label("Contrabbando, pirati e pesos nel porto più losco delle Indie", 24, UI.SAND, UI.font_italic)
	tag.position = Vector2(96, 186)
	add_child(tag)

	# pergamena della ciurma
	var scroll := PanelContainer.new()
	scroll.add_theme_stylebox_override("panel", UI.paper(false, 30))
	scroll.position = Vector2(50, 236)
	scroll.custom_minimum_size = Vector2(800, 0)
	add_child(scroll)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	scroll.add_child(vb)
	var hh := HBoxContainer.new()
	hh.add_child(UI.title("La ciurma", 44))
	var sub := UI.label("   da 3 a 5 bande di contrabbandieri", 20, UI.INK2, UI.font_italic)
	sub.size_flags_vertical = Control.SIZE_SHRINK_END
	hh.add_child(sub)
	vb.add_child(hh)
	for c in D.COLORS:
		vb.add_child(_crew_row(c))
	var sep := HSeparator.new()
	vb.add_child(sep)
	vb.add_child(_segmented("Astuzia dell'IA", ["Facile", "Normale", "Difficile"], level, func(k): level = k))
	vb.add_child(_segmented("Velocità dell'IA", ["Lenta", "Normale", "Veloce", "Subito"], speed, func(k): speed = k))
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 12)
	var ml := UI.label("Varianti", 24, UI.INK, UI.font_bold)
	ml.custom_minimum_size = Vector2(190, 0)
	mrow.add_child(ml)
	var mb := UI.button("Scegli…", 150, 46, 21)
	mb.pressed.connect(_mods_panel)
	mrow.add_child(mb)
	mods_lbl = UI.label("", 19, UI.INK2, UI.font_italic)
	mods_lbl.custom_minimum_size = Vector2(380, 0)
	mods_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mrow.add_child(mods_lbl)
	vb.add_child(mrow)
	_mods_text()

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 18)
	btns.position = Vector2(60, 940)
	add_child(btns)
	var b_start := _big_button("Salpa!", 360, true)
	b_start.pressed.connect(_on_start)
	btns.add_child(b_start)
	var b_rules := _big_button("Regole", 220)
	b_rules.pressed.connect(func():
		_store()
		main.show_rules())
	btns.add_child(b_rules)
	if not OS.has_feature("web"):
		var b_quit := _big_button("Esci", 170)
		b_quit.pressed.connect(func(): get_tree().quit())
		btns.add_child(b_quit)

	msg = UI.label("", 24, Color("#ffb4a0"), UI.font_bold)
	msg.position = Vector2(64, 1030)
	add_child(msg)

	# gioco online: cartello sul dipinto
	var on_box := PanelContainer.new()
	on_box.add_theme_stylebox_override("panel", UI.paper(true, 24))
	on_box.position = Vector2(1430, 780)
	on_box.custom_minimum_size = Vector2(440, 0)
	add_child(on_box)
	var ovb := VBoxContainer.new()
	ovb.add_theme_constant_override("separation", 8)
	on_box.add_child(ovb)
	ovb.add_child(UI.title("Con gli amici", 34))
	var on_note := UI.label("Ognuno dal suo dispositivo: crea una stanza e condividi il codice.", 20, UI.INK2)
	on_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	on_note.custom_minimum_size = Vector2(390, 0)
	ovb.add_child(on_note)
	var b_online := UI.sea(_big_button("Gioca online", 390))
	b_online.pressed.connect(_online_panel)
	ovb.add_child(b_online)
	if not main.lobby.is_empty():
		_online_panel.call_deferred()

	var credits := UI.label("Adattamento digitale non ufficiale per uso personale · Manila di Franz-Benno Delonge · illustrazioni di Victor Boden · © Zoch Verlag · F11 schermo intero", 16, Color("#cfe6e2"))
	credits.position = Vector2(830, 1050)
	add_child(credits)
	_refresh_tiles()


func _store() -> void:
	main.menu_state = {"seat_mode": seat_mode.duplicate(), "level": level, "speed": speed, "mods": mods.duplicate()}


func _mods_text() -> void:
	var names := []
	for m in MOD_LIST:
		if mods.get(m[0], false):
			names.append(m[1])
	mods_lbl.text = "Regole base del regolamento." if names.is_empty() else ", ".join(names) + "."


func _mods_panel() -> void:
	var layer := Control.new()
	layer.size = Vector2(1920, 1080)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(layer)
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.12, 0.13, 0.75)
	shade.size = layer.size
	layer.add_child(shade)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UI.paper(false, 34))
	box.position = Vector2(400, 190)
	box.custom_minimum_size = Vector2(1120, 0)
	layer.add_child(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	box.add_child(vb)
	vb.add_child(UI.title("Varianti", 48))
	vb.add_child(UI.label("Si possono combinare. Il foglio della variante BGG le raccomanda tutte (le scelte extra solo in 5).", 21, UI.INK2, UI.font_italic))
	var checks := {}
	for m in MOD_LIST:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var c := CheckBox.new()
		c.text = m[1]
		c.button_pressed = mods.get(m[0], false)
		c.custom_minimum_size = Vector2(380, 0)
		c.add_theme_font_size_override("font_size", 23)
		row.add_child(c)
		var d := UI.label(m[2], 19, UI.INK2)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(660, 0)
		row.add_child(d)
		vb.add_child(row)
		checks[m[0]] = c
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	var all := UI.button("Tutte", 150, 54, 23)
	all.pressed.connect(func():
		for k in ["bgg", "pirates", "five"]:
			checks[k].button_pressed = true)
	hb.add_child(all)
	var none := UI.button("Nessuna", 170, 54, 23)
	none.pressed.connect(func():
		for k in checks:
			checks[k].button_pressed = false)
	hb.add_child(none)
	var ok := UI.primary(UI.button("Fatto", 190, 54, 23))
	ok.pressed.connect(func():
		mods = {}
		for k in checks:
			if checks[k].button_pressed:
				mods[k] = true
		_mods_text()
		_store()
		layer.queue_free())
	hb.add_child(ok)
	vb.add_child(hb)


func _crew_row(c: Dictionary) -> Control:
	var i: int = c["id"]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var pw := UI.icon_rect(UI.pawn(i), Vector2(58, 58))
	pw.mouse_filter = Control.MOUSE_FILTER_STOP
	pw.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			seat_mode[i] = (seat_mode[i] + 1) % 3
			_refresh_tiles())
	row.add_child(pw)
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", -6)
	nv.custom_minimum_size = Vector2(250, 0)
	var nm := UI.title(c["name"], 32, c["color"].darkened(0.15) if i != 2 else Color("#a07d00"))
	nv.add_child(nm)
	nv.add_child(UI.label(NICK[i], 18, UI.INK2, UI.font_italic))
	row.add_child(nv)
	var buttons := []
	for k in range(3):
		var b := UI.button(MODES[k], 140, 50, 21)
		b.pressed.connect(func():
			seat_mode[i] = k
			msg.text = ""
			_refresh_tiles())
		row.add_child(b)
		buttons.append(b)
	tiles[i] = {"pawn": pw, "buttons": buttons, "name": nm}
	return row


func _refresh_tiles() -> void:
	for i in range(5):
		var t: Dictionary = tiles[i]
		var m: int = seat_mode[i]
		t["pawn"].modulate = Color.WHITE if m != 2 else Color(1, 1, 1, 0.3)
		t["name"].modulate = Color.WHITE if m != 2 else Color(1, 1, 1, 0.45)
		for k in range(3):
			var b: Button = t["buttons"][k]
			if k == m:
				UI.selected(b, "coral" if k == 0 else ("sea" if k == 1 else "wood_dark"))
			else:
				b.add_theme_stylebox_override("normal", UI.plank("wood"))
				b.add_theme_stylebox_override("hover", UI.plank("wood_hover"))


func _segmented(label_text: String, items: Array, cur: int, cb: Callable) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	var l := UI.label(label_text, 24, UI.INK, UI.font_bold)
	l.custom_minimum_size = Vector2(190, 0)
	hb.add_child(l)
	var btns := []
	for k in range(items.size()):
		var b := UI.button(items[k], 130, 46, 21)
		hb.add_child(b)
		btns.append(b)
	var paint := func(sel: int):
		for k in range(btns.size()):
			if k == sel:
				UI.selected(btns[k], "sea")
			else:
				btns[k].add_theme_stylebox_override("normal", UI.plank("wood"))
				btns[k].add_theme_stylebox_override("hover", UI.plank("wood_hover"))
	for k in range(btns.size()):
		btns[k].pressed.connect(func():
			cb.call(k)
			paint.call(k))
	paint.call(cur)
	return hb


func _big_button(text: String, w: float, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 76)
	b.add_theme_font_override("font", UI.font_title)
	b.add_theme_font_size_override("font_size", 40)
	if primary:
		UI.primary(b)
	return b


## Configurazione scelta nel menu (anche quella che, online, viaggia agli altri).
func _config() -> Dictionary:
	var seats := []
	for c in D.COLORS:
		var m: int = seat_mode[c["id"]]
		if m == 2:
			continue
		seats.append({"color": c["id"], "ai": m == 1, "name": c["name"], "level": level})
	var speeds := [1.0, 0.5, 0.15, 0.0]
	var o := {}
	for k in ["bgg", "pirates", "five"]:
		if mods.get(k, false):
			o[k] = true
	return {"seats": seats, "ai_level": level, "ai_delay": speeds[speed], "opts": o, "hints": not mods.get("nohints", false)}


func _on_start() -> void:
	var cfg := _config()
	if cfg["seats"].size() < 3:
		msg.text = "Manila si gioca da 3 a 5: metti in gioco almeno 3 colori."
		return
	_store()
	main.start_game(cfg)


# =================================================================== online

var on_panel: Control
var on_name: LineEdit
var on_code: LineEdit
var on_lbl: Label
var on_start: Button


func _online_panel() -> void:
	if is_instance_valid(on_panel):
		on_panel.queue_free()
	on_panel = Control.new()
	on_panel.size = Vector2(1920, 1080)
	on_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(on_panel)
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.12, 0.13, 0.78)
	shade.size = on_panel.size
	on_panel.add_child(shade)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UI.paper(false, 34))
	box.position = Vector2(560, 130)
	box.custom_minimum_size = Vector2(800, 0)
	on_panel.add_child(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	box.add_child(vb)
	vb.add_child(UI.title("Gioca online", 52))
	var info := UI.label("Chi crea la stanza sceglie prima nel menu colori, varianti e livello dell'IA: i colori su Umano diventano i posti per gli amici (il primo è il suo). Gli amici entrano con il codice. I posti rimasti liberi li gioca l'IA.", 21, UI.INK2)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(760, 0)
	vb.add_child(info)
	var ses: Dictionary = main.get_net().load_session()
	on_name = _line("Il tuo nome", 20)
	on_name.text = str(ses.get("name", ""))
	vb.add_child(on_name)
	var b_create := Button.new()
	b_create.text = "Crea una stanza"
	UI.sea(b_create)
	b_create.custom_minimum_size = Vector2(0, 60)
	b_create.add_theme_font_size_override("font_size", 28)
	b_create.pressed.connect(_online_create)
	vb.add_child(b_create)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	on_code = _line("Codice", 4)
	on_code.custom_minimum_size.x = 220
	on_code.text_changed.connect(func(t):
		on_code.text = t.to_upper()
		on_code.caret_column = t.length())
	row.add_child(on_code)
	var b_join := Button.new()
	b_join.text = "Entra"
	UI.sea(b_join)
	b_join.custom_minimum_size = Vector2(200, 60)
	b_join.add_theme_font_size_override("font_size", 28)
	b_join.pressed.connect(_online_join)
	row.add_child(b_join)
	vb.add_child(row)
	on_lbl = UI.label("", 23, UI.INK)
	on_lbl.custom_minimum_size = Vector2(760, 120)
	on_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(on_lbl)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 12)
	on_start = _big_button("Si salpa!", 360, true)
	on_start.pressed.connect(_online_start)
	on_start.visible = main.lobby.get("role", "") == "host"
	row2.add_child(on_start)
	var b_close := _big_button("Indietro", 260)
	b_close.pressed.connect(func():
		on_panel.queue_free())
	row2.add_child(b_close)
	vb.add_child(row2)
	if not main.lobby.is_empty():
		on_code.text = main.lobby["code"]
		on_lbl.text = "Stanza %s…" % main.lobby["code"]
	elif str(ses.get("room", "")) != "":
		on_code.text = str(ses["room"])
		on_lbl.text = "Eri nella stanza %s: premi Entra per rientrare." % ses["room"]


func _line(ph: String, maxlen: int) -> LineEdit:
	var le := LineEdit.new()
	le.placeholder_text = ph
	le.max_length = maxlen
	le.custom_minimum_size = Vector2(0, 60)
	le.add_theme_font_size_override("font_size", 28)
	return le


func _say(t: String) -> void:
	if is_instance_valid(on_lbl):
		on_lbl.text = t


func _seat_list() -> Array:
	return _config()["seats"]


func _seats_text(room: Dictionary) -> String:
	var seats := Net._as_dict(room.get("seats", {}))
	var list := _seat_list()
	var parts := []
	for idx in room.get("open", []):
		var k := str(int(idx))
		var who := str(seats[k].get("name", "?")) if seats.has(k) and seats[k] is Dictionary else "libero"
		var cname: String = list[int(idx)]["name"] if int(idx) < list.size() else "posto %d" % (int(idx) + 1)
		parts.append("%s: %s" % [cname, who])
	return ", ".join(parts)


func _online_create() -> void:
	var nm := on_name.text.strip_edges()
	if nm == "":
		_say("Scrivi il tuo nome.")
		return
	var seats := []
	var list := _seat_list()
	for i in list.size():
		if not list[i]["ai"]:
			seats.append(i)
	if list.size() < 3 or seats.size() < 2:
		_say("Servono almeno 3 colori in gioco, di cui almeno due su Umano: il primo è il tuo, gli altri sono i posti per gli amici.")
		return
	_store()
	_say("Creo la stanza…")
	var net: Net = main.get_net()
	var code := await net.create_room(nm, seats)
	if code == "":
		_say("Non riesco a creare la stanza.\n%s" % net.last_error)
		return
	main.lobby = {"role": "host", "code": code, "seat": seats[0]}
	net.remember_room(code, seats[0])
	net._save({"name": nm})
	if is_instance_valid(on_code):
		on_code.text = code
	if is_instance_valid(on_start):
		on_start.visible = true
	_lobby_poll(code)


func _online_join() -> void:
	var code := on_code.text.strip_edges().to_upper()
	var nm := on_name.text.strip_edges()
	if nm == "" or code.length() != 4:
		_say("Scrivi il tuo nome e il codice di 4 lettere.")
		return
	_say("Entro nella stanza %s…" % code)
	var net: Net = main.get_net()
	var seat := await net.join_room(code, nm)
	if seat == -2:
		_say("Stanza %s non trovata, oppure la partita è già iniziata.%s" % [code, ("\n" + net.last_error) if net.last_error != "" else ""])
		return
	if seat == -1:
		_say("Nella stanza %s non ci sono posti liberi." % code)
		return
	var room: Dictionary = net.last_room
	main.lobby = {"role": "host" if room.get("host", "") == net.uid else "guest", "code": code, "seat": seat}
	net.remember_room(code, seat)
	net._save({"name": nm})
	if room.get("status", "") in ["playing", "over"] and room.has("game"):
		_say("Rientro nella partita della stanza %s…" % code)
		_begin(room["game"], true)
		return
	if is_instance_valid(on_start):
		on_start.visible = main.lobby["role"] == "host"
	_lobby_poll(code)


func _lobby_poll(code: String) -> void:
	var net: Net = main.get_net()
	while is_inside_tree() and main.lobby.get("code", "") == code:
		var room := await net.room(code)
		if not is_inside_tree() or main.lobby.get("code", "") != code:
			return
		if room.is_empty():
			_say("La stanza %s non esiste più." % code)
			main.lobby = {}
			return
		if main.lobby["role"] == "host":
			_say("Stanza [ %s ]: dai il codice ai tuoi amici.\nPosti: %s.\nQuando ci siete tutti premi Si salpa!: i posti liberi li gioca l'IA." % [code, _seats_text(room)])
		else:
			if room.get("status", "") == "playing" and room.has("game"):
				_begin(room["game"], false)
				return
			_say("Sei nella stanza [ %s ] (posto %d).\nPosti: %s.\nAspetta che chi l'ha creata avvii la partita." % [code, int(main.lobby["seat"]) + 1, _seats_text(room)])
		await get_tree().create_timer(2.0).timeout


## Chi ha creato la stanza avvia: colori, opzioni e seme valgono per tutti.
func _online_start() -> void:
	var code: String = main.lobby["code"]
	var net: Net = main.get_net()
	var room := await net.room(code)
	if room.is_empty():
		_say("La stanza %s non esiste più." % code)
		main.lobby = {}
		return
	var seats_db := Net._as_dict(room.get("seats", {}))
	var cfg := _config()
	var my_seat := int(main.lobby["seat"])
	if my_seat >= cfg["seats"].size() or not seats_db.has(str(my_seat)) or cfg["seats"][my_seat]["ai"]:
		_say("Hai cambiato i colori dopo aver creato la stanza: creane una nuova.")
		return
	for i in cfg["seats"].size():
		var k := str(i)
		if seats_db.has(k) and seats_db[k] is Dictionary and not cfg["seats"][i]["ai"]:
			cfg["seats"][i]["name"] = "%s" % str(seats_db[k].get("name", cfg["seats"][i]["name"]))
		else:
			cfg["seats"][i]["ai"] = true
	cfg["seed"] = 1 + randi() % 2000000000
	var g := {"cfg": var_to_str(cfg)}
	if not await net.start_room(code, g):
		_say("Non riesco ad avviare la partita (%s)." % net.last_error)
		return
	_begin(g, false)


## Avvio (o rientro) della partita online.
func _begin(g: Dictionary, rejoin: bool) -> void:
	var net: Net = main.get_net()
	var lob: Dictionary = main.lobby
	var backlog: Array = []
	if rejoin:
		backlog = await net.get_acts(lob["code"])
		net.set_away(lob["code"], int(lob["seat"]), false)
	var cfg = str_to_var(str(g.get("cfg", "")))
	if not (cfg is Dictionary):
		_say("Configurazione della partita non valida.")
		return
	var ses := OnlineSession.new()
	ses.setup(net, lob["code"], int(lob["seat"]), lob["role"], backlog)
	cfg["online"] = ses
	main.lobby = {}
	main.start_game(cfg)
