extends SceneTree
## Screenshot automatici dell'interfaccia (serve un display: xvfb-run).
## godot --path . -s res://tests/shot.gd -- <modo: menu|rules|game> [giocatori] [varianti]

var main
var n := 0

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir() + "/shots")
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func shot(name: String) -> void:
	await process_frame
	await process_frame
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	n += 1
	img.save_png(OS.get_user_data_dir() + "/shots/%02d_%s.png" % [n, name])
	print("shot ", name)


func wait(f := 10) -> void:
	for i in range(f):
		await process_frame


func gv():
	return main.current


## Risponde a una decisione con l'IA (come farebbe un giocatore).
func auto_answer() -> void:
	var g = gv()
	var req: Dictionary = g.pending
	if req.is_empty():
		return
	var r = g.engine.ais[int(req["seat"])].decide(g.engine, int(req["seat"]), req)
	# al primo viaggio la persona vince l'asta, per fotografare acquisto e carico
	if g.engine.voyage == 1 and req["type"] == "bid" and int(req["cur"]) < 12:
		r = int(req["cur"]) + 1
	g._provide(r)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var mode: String = args[0] if args.size() > 0 else "game"
	await wait(5)
	await shot("menu")
	if mode == "menu":
		quit()
		return
	if mode == "rules":
		main.show_rules()
		await wait(5)
		await shot("rules")
		quit()
		return
	var np := int(args[1]) if args.size() > 1 else 4
	var seats := []
	for i in range(np):
		seats.append({"color": i, "ai": i != 0, "name": ["Stefano", "Arancione", "Giallo", "Blu", "Rosso"][i], "level": 1})
	var o := {}
	if args.size() > 2:
		for k in args[2].split(","):
			o[k] = true
	main.start_game({"seats": seats, "seed": 42, "ai_delay": 0.0, "opts": o})
	await wait(20)
	var taken := {}
	var guard := 0
	while guard < 6000:
		guard += 1
		await wait(2)
		var g = gv()
		if g.engine.game_over and g.pending.is_empty() and g.modal.get_child_count() > 0 and g.engine.phase == "end":
			await wait(30)
			await shot("fine")
			break
		var req: Dictionary = g.pending
		if req.is_empty():
			if g.modal.get_child_count() > 0:
				if not taken.has("pause%d" % g.engine.voyage):
					taken["pause%d" % g.engine.voyage] = true
					await wait(20)
					await shot("fine_viaggio%d" % g.engine.voyage)
				g._clear_modal()
				g.engine.provide_decision(null)
			continue
		var key := "%s_v%d_r%d" % [req["type"], g.engine.voyage, g.engine.roll_no]
		if not taken.has(key) and g.engine.voyage <= 2:
			taken[key] = true
			await wait(45)
			await shot(key)
			if req["type"] == "place" and not taken.has("orbit"):
				taken["orbit"] = true
				g.board.rotate_view(60)
				g.board.zoom(0.6)
				await wait(60)
				await shot(key + "_ruotato")
				g.board.reset_view(false)
				await wait(40)
		auto_answer()
	quit()
