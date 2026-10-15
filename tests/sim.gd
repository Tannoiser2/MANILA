extends SceneTree
## Partite IA contro IA senza grafica, per provare le regole e tarare l'IA.
## godot --headless --path . -s res://tests/sim.gd -- <partite> <giocatori> [varianti: bgg,pirates,five] [livelli es. 2,1,1,0,0]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var games := int(args[0]) if args.size() > 0 else 20
	var np := int(args[1]) if args.size() > 1 else 4
	var o := {}
	if args.size() > 2 and args[2] != "-":
		for k in args[2].split(","):
			o[k] = true
	var levels := [1, 1, 1, 1, 1]
	if args.size() > 3:
		var parts: PackedStringArray = args[3].split(",")
		for i in parts.size():
			levels[i] = int(parts[i])
	var wins := [0, 0, 0, 0, 0]
	var wsum := [0, 0, 0, 0, 0]
	var voy := 0
	var t0 := Time.get_ticks_msec()
	for g in games:
		var e := MNEngine.new()
		e.headless = true
		root.add_child(e)
		var seats := []
		for i in np:
			seats.append({"color": i, "ai": true, "name": "IA%d" % i, "level": levels[i]})
		e.setup({"seats": seats, "seed": 1000 + g, "opts": o})
		await e.run()
		wins[e.results[0]["seat"]] += 1
		for r in e.results:
			wsum[r["seat"]] += r["wealth"]
		voy += e.voyage
		if g == 0:
			for l in e.log_lines:
				print(l)
		e.queue_free()
	print("vittorie per posto: ", wins.slice(0, np), "  patrimonio medio: ", wsum.slice(0, np).map(func(x): return x / games))
	print("viaggi medi: %.1f   tempo %d ms" % [float(voy) / games, Time.get_ticks_msec() - t0])
	quit()
