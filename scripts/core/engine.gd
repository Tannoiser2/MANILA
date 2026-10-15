class_name MNEngine
extends Node
## Motore delle regole di Manila (Franz-Benno Delonge, Zoch). Nessuna dipendenza dalla UI.
## Ogni scelta passa da `decide()`: l'IA risponde subito, per i giocatori umani viene emesso
## `decision_requested` e si attende `provide_decision()`. Online le scelte passano dal registro di
## mosse (OnlineSession): con lo stesso seme ogni dispositivo ottiene la stessa partita.
##
## Varianti (config["opts"]):
##   bgg      variante consigliata di BGG (v1.3): asta a mano chiusa, giro di piazzamento dopo il
##            primo tiro in senso antiorario (comincia sempre il capitano del porto)
##   pirates  pirati forti (regola opzionale del regolamento): all'abbordaggio si può scalzare un complice
##   five     scelte extra per 5 giocatori (BGG): piloti scontati nell'ultimo giro, scommessa 1-3
##            su un proprio molo/cantiere, casella Malattia; con 5 giocatori attiva anche i pirati forti

signal changed
signal log_added(text: String)
signal decision_requested(req: Dictionary)
signal decision_provided(result)
signal game_ended(results: Array)
signal fx(kind: String, data: Dictionary)
signal pause_requested(req: Dictionary)

const D = preload("res://scripts/data/mn_data.gd")

var rng := RandomNumberGenerator.new()
var ai_delay := 0.0
var headless := false
var ais := {}
var opts := {}

var players: Array = []          # {color, ai, name, level, cash, shares:[{w, m}], pawns}
var n := 0
var supply := [0, 0, 0, 0]       # quote ancora disponibili per merce
var market := [0, 0, 0, 0]       # indice nel mercato nero (0..4)
var hm := -1                     # capitano del porto (chi comanda la capitaneria)
var start_player := 0
var voyage := 0
var phase := ""                  # auction, hm, place, roll, pilot, board, plunder, payout, end
var boats: Array = []            # {w, lane, pos, at:"sea"|"harbor"|"yard", slot, riders:[posto o -1], plundered}
var spots := {}                  # id casella -> posto (-1 libera)
var harbor := [-1, -1, -1]       # barcone attraccato in ciascun molo
var yard := [-1, -1, -1]         # barcone in ciascun cantiere
var hand: Array = []             # complici ancora da piazzare
var passed: Array = []
var roll_no := 0                 # tiri già fatti in questo viaggio
var dice: Array = []             # ultimo tiro (per barcone)
var wager := {}                  # {seat, id, v} scommessa sul molo/cantiere (variante 5 giocatori)
var excluded := -1               # merce lasciata a terra
var place_round := 0             # giro di piazzamento in corso (1..)
var place_rounds := 3
var auction := {}                # per la UI: {cur, leader, out:{}, blind:{}}
var income := {}                 # guadagni dell'ultimo viaggio per posto
var game_over := false
var results: Array = []
var log_lines: Array = []
var current := -1
var abort := false
var pause_enabled := false
var online = null
var setup_done := false


# ------------------------------------------------------------------ setup

## config: {"seats":[{"color","ai","name","level"}], "seed", "opts":{}}
func setup(config: Dictionary) -> void:
	if config.has("seed"):
		rng.seed = int(config["seed"])
	else:
		rng.randomize()
	opts = config.get("opts", {}).duplicate()
	ai_delay = float(config.get("ai_delay", 0.0))
	players.clear()
	for st in config["seats"]:
		players.append({"color": int(st["color"]), "ai": bool(st["ai"]), "name": str(st["name"]),
			"level": int(st.get("level", 1)), "cash": 30, "shares": []})
	n = players.size()
	if n == 5 and opts.get("five", false):
		opts["pirates"] = true
	if n != 5:
		opts.erase("five")
	var deck := []
	for w in 4:
		for k in 5:
			deck.append(w)
	_shuffle(deck)
	supply = [5, 5, 5, 5]
	for s in n:
		for k in 2:
			var w: int = deck.pop_back()
			players[s]["shares"].append({"w": w, "m": false})
			supply[w] -= 1
		players[s]["pawns"] = 4 if n == 3 else 3
	market = [0, 0, 0, 0]
	place_rounds = 4 if n == 3 else 3
	for s in n:
		var a := MNAI.new()
		a.level = players[s]["level"]
		a.rng.seed = rng.seed + 7919 * (s + 1)
		ais[s] = a
	start_player = rng.randi() % n
	_reset_voyage()
	setup_done = true


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


func _reset_voyage() -> void:
	boats.clear()
	spots.clear()
	for id in D.SPOT_ORDER:
		spots[id] = -1
	harbor = [-1, -1, -1]
	yard = [-1, -1, -1]
	hand.clear()
	passed.clear()
	for s in n:
		hand.append(players[s]["pawns"])
		passed.append(false)
	roll_no = 0
	dice = []
	wager = {}
	excluded = -1
	place_round = 0
	auction = {}


func pname(seat: int) -> String:
	if seat < 0 or seat >= n:
		return "la cassa"
	return players[seat]["name"]


func log_msg(t: String) -> void:
	log_lines.append(t)
	log_added.emit(t)


func left_of(s: int) -> int:
	return (s + 1) % n


func right_of(s: int) -> int:
	return (s - 1 + n) % n


func any_local_human() -> bool:
	if online != null:
		return true
	for p in players:
		if not p["ai"]:
			return true
	return false


# ------------------------------------------------------------------ denaro e quote

func free_shares(s: int) -> int:
	var c := 0
	for sh in players[s]["shares"]:
		if not sh["m"]:
			c += 1
	return c


func mortgaged(s: int) -> int:
	return players[s]["shares"].size() - free_shares(s)


## Denaro disponibile contando i prestiti possibili (12 pesos per quota libera).
func funds(s: int) -> int:
	return int(players[s]["cash"]) + 12 * free_shares(s)


## Paga `amt` alla cassa (o a chi riceve, gestito da chi chiama). Se i contanti non bastano impegna
## le quote necessarie. Restituisce quanto è stato pagato davvero.
func pay(s: int, amt: int) -> int:
	if amt <= 0:
		return 0
	var p: Dictionary = players[s]
	while p["cash"] < amt and free_shares(s) > 0:
		_mortgage_one(s)
	var paid := mini(int(p["cash"]), amt)
	p["cash"] -= paid
	return paid


func _mortgage_one(s: int) -> void:
	var best := -1
	var bv := 999
	var sh: Array = players[s]["shares"]
	for i in sh.size():
		if not sh[i]["m"]:
			var v: int = D.MARKET[market[sh[i]["w"]]]
			if v < bv:
				bv = v
				best = i
	if best < 0:
		return
	sh[best]["m"] = true
	players[s]["cash"] += 12
	log_msg("%s impegna una quota (+12 pesos)." % pname(s))


func gain(s: int, amt: int) -> void:
	if s >= 0 and amt > 0:
		players[s]["cash"] += amt


func share_count(s: int, w: int) -> int:
	var c := 0
	for sh in players[s]["shares"]:
		if sh["w"] == w:
			c += 1
	return c


## Patrimonio: pesos + valore delle quote - 15 per ogni quota impegnata.
func wealth(s: int) -> int:
	var v: int = players[s]["cash"]
	for sh in players[s]["shares"]:
		v += D.MARKET[market[sh["w"]]]
		if sh["m"]:
			v -= 15
	return v


func share_price(w: int) -> int:
	return maxi(5, D.MARKET[market[w]])


# ------------------------------------------------------------------ decisioni

func decide(seat: int, req: Dictionary):
	req["seat"] = seat
	current = seat
	if abort:
		return ais[seat].decide(self, seat, req)
	if online != null:
		var r0 = await online.decide(self, seat, req)
		return r0
	if players[seat]["ai"]:
		if ai_delay > 0.0 and not headless and is_inside_tree():
			await get_tree().create_timer(ai_delay).timeout
		return ais[seat].decide(self, seat, req)
	decision_requested.emit(req)
	var r = await decision_provided
	return r


func provide_decision(r) -> void:
	decision_provided.emit(r)


func _idx(r, size: int) -> int:
	var i := int(r) if (r is int or r is float) else 0
	return clampi(i, 0, maxi(0, size - 1))


## Pausa per far leggere qualcosa (fine viaggio): solo se c'è qualcuno davanti allo schermo.
func pause_point(req: Dictionary) -> void:
	if headless or abort or not pause_enabled:
		return
	if online != null and online.catchup:
		return
	if not any_local_human():
		return
	pause_requested.emit(req)
	await decision_provided


## Attesa per le animazioni (dadi, barconi).
func _wait(sec: float) -> void:
	if headless or abort or not is_inside_tree():
		return
	if online != null and online.catchup:
		return
	if ai_delay <= 0.0 and not any_local_human():
		return
	await get_tree().create_timer(sec).timeout


func _d6() -> int:
	return rng.randi_range(1, 6)


# ------------------------------------------------------------------ partita

func run() -> void:
	log_msg("Si salpa per Manila! %d contrabbandieri, 30 pesos e 2 quote a testa." % n)
	if opts.get("bgg", false):
		log_msg("Variante BGG: asta a mano chiusa e secondo giro di piazzamento in senso antiorario.")
	if opts.get("pirates", false):
		log_msg("Pirati forti: all'abbordaggio possono scalzare un complice.")
	if opts.get("five", false):
		log_msg("Scelte extra per 5 giocatori: piloti scontati, scommessa sui moli, Malattia.")
	while not game_over and not abort:
		voyage += 1
		_reset_voyage()
		log_msg("— Viaggio %d —" % voyage)
		changed.emit()
		await _auction()
		if abort: return
		await _hm_phase()
		if abort: return
		await _sail()
		if abort: return
		await _resolve_end()
		if abort: return
		_payout()
		_raise_values()
		changed.emit()
		var top := 0
		for w in 4:
			top = maxi(top, market[w])
		if top >= 4:
			game_over = true
		await pause_point({"type": "voyage_end", "voyage": voyage, "over": game_over})
	if not abort:
		_final()


# ------------------------------------------------------------------ 1. asta

func _auction() -> void:
	phase = "auction"
	var prev := hm if hm >= 0 else start_player
	auction = {"cur": 0, "leader": -1, "out": {}, "blind": {}}
	changed.emit()
	if opts.get("bgg", false):
		await _auction_blind(prev)
	else:
		await _auction_open(prev)
	auction = {}
	changed.emit()


func _auction_open(first: int) -> void:
	var cur := 0
	var leader := -1
	var out := {}
	var i := first
	var guard := 0
	while guard < 400:
		guard += 1
		if out.size() >= n:
			break
		if leader >= 0 and out.size() >= n - 1:
			break
		if out.has(i) or i == leader:
			i = left_of(i)
			continue
		var mx := funds(i)
		if mx <= cur:
			out[i] = true
			auction["out"] = out.duplicate()
			i = left_of(i)
			continue
		var r = await decide(i, {"type": "bid", "cur": cur, "max": mx, "leader": leader,
			"title": "Asta per la capitaneria: offri più di %d pesos o passa" % cur})
		if abort: return
		var b := int(r) if (r is int or r is float) else 0
		if b > cur and b <= mx:
			cur = b
			leader = i
			log_msg("%s offre %d." % [pname(i), b])
		else:
			out[i] = true
			log_msg("%s passa." % pname(i))
		auction = {"cur": cur, "leader": leader, "out": out.duplicate(), "blind": {}}
		changed.emit()
		i = left_of(i)
	if leader >= 0:
		pay(leader, cur)
		hm = leader
		log_msg("%s comanda la capitaneria per %d pesos." % [pname(hm), cur])
	else:
		hm = first
		log_msg("Nessuna offerta: %s comanda la capitaneria gratis." % pname(hm))


func _auction_blind(prev: int) -> void:
	var bids := {}
	var order := []
	var s := left_of(prev)
	for k in n:
		order.append(s)
		s = left_of(s)
	for t in order:
		var mx := funds(t)
		var r = await decide(t, {"type": "bid_blind", "max": mx, "secret": true,
			"title": "Asta a mano chiusa: quanto offri in segreto per la capitaneria?"})
		if abort: return
		bids[t] = clampi(int(r) if (r is int or r is float) else 0, 0, mx)
		auction["blind"] = {"done": bids.size()}
		changed.emit()
	var best := -1
	var bv := -1
	for t in order:
		if bids[t] > bv:
			bv = bids[t]
			best = t
	var parts := []
	for t in order:
		parts.append("%s %d" % [pname(t), bids[t]])
	log_msg("Offerte segrete: " + ", ".join(parts) + ".")
	auction = {"cur": bv, "leader": best, "out": {}, "blind": {"shown": bids.duplicate()}}
	hm = best
	pay(best, bv)
	log_msg("%s comanda la capitaneria per %d pesos." % [pname(hm), bv])
	changed.emit()
	await _wait(1.2)


# ------------------------------------------------------------------ 2. capitaneria

func _hm_phase() -> void:
	phase = "hm"
	changed.emit()
	# a) comprare una quota
	var options := []
	for w in 4:
		if supply[w] > 0 and share_price(w) <= funds(hm):
			options.append(w)
	if not options.is_empty():
		var r = await decide(hm, {"type": "buy", "options": options,
			"title": "Capitano del porto: vuoi comprare una quota?"})
		if abort: return
		var w := int(r) if (r is int or r is float) else -1
		if w in options:
			var price := share_price(w)
			pay(hm, price)
			supply[w] -= 1
			players[hm]["shares"].append({"w": w, "m": false})
			log_msg("%s compra una quota di %s per %d pesos." % [pname(hm), D.ware_name(w), price])
			changed.emit()
	# b) c) caricare le merci e mettere in acqua i barconi
	var r2 = await decide(hm, {"type": "load", "title": "Scegli la merce da lasciare a terra e le posizioni di partenza (somma 9)"})
	if abort: return
	var cfg = _valid_load(r2)
	if cfg.is_empty():
		cfg = ais[hm].default_load(self, hm)
	excluded = int(cfg["ex"])
	var lane := 0
	for w in 4:
		if w == excluded:
			continue
		var b := {"w": w, "lane": lane, "pos": int(cfg["p"][lane]), "at": "sea", "slot": -1, "plundered": false, "riders": []}
		for k in D.WARES[w]["slots"].size():
			b["riders"].append(-1)
		boats.append(b)
		lane += 1
	var parts := []
	for b in boats:
		parts.append("%s %d" % [D.ware_name(b["w"]), b["pos"]])
	log_msg("Resta a terra: %s. Partenze: %s." % [D.ware_name(excluded), ", ".join(parts)])
	fx.emit("launch", {})
	changed.emit()
	await _wait(0.8)


## Controlla la configurazione dei barconi: {"ex": merce esclusa, "p": [3 posizioni]}.
func _valid_load(r) -> Dictionary:
	if not (r is Dictionary):
		return {}
	var ex := int(r.get("ex", -1))
	var p = r.get("p", [])
	if ex < 0 or ex > 3 or not (p is Array) or p.size() != 3:
		return {}
	var sum := 0
	for v in p:
		var iv := int(v)
		if iv < 0 or iv > 5:
			return {}
		sum += iv
	if sum != 9:
		return {}
	return {"ex": ex, "p": [int(p[0]), int(p[1]), int(p[2])]}


# ------------------------------------------------------------------ 3. complici e navigazione

func _sail() -> void:
	var seq := ["P", "P", "R", "P", "R", "P", "R"] if n == 3 else ["P", "R", "P", "R", "P", "R"]
	var last_p := seq.rfind("P")
	for i in seq.size():
		if abort: return
		if seq[i] == "P":
			place_round += 1
			var reverse: bool = opts.get("bgg", false) and roll_no == 1
			await _placement_round(reverse, i == last_p)
			if i == last_p:
				await _pilots()
		else:
			await _roll()


func _placement_round(reverse: bool, final: bool) -> void:
	phase = "place"
	changed.emit()
	var s := hm
	for k in n:
		if abort: return
		if not passed[s] and hand[s] > 0:
			var options := legal_placements(s, final)
			if options.size() > 1:
				var r = await decide(s, {"type": "place", "options": options, "final": final, "reverse": reverse,
					"title": "Piazza un complice (giro %d di %d)" % [place_round, place_rounds]})
				if abort: return
				_apply_placement(s, options[_idx(r, options.size())], final)
				changed.emit()
				await _wait(0.25)
		s = right_of(s) if reverse else left_of(s)


func owns_dock(s: int) -> Array:
	var out := []
	for id in ["H0", "H1", "H2", "Y0", "Y1", "Y2"]:
		if spots[id] == s:
			out.append(id)
	return out


## Elenco delle mosse di piazzamento possibili per il posto s (l'ultima voce è sempre "passa").
func legal_placements(s: int, final := false) -> Array:
	var five: bool = opts.get("five", false)
	var cands := []
	for bi in boats.size():
		var b: Dictionary = boats[bi]
		if b["at"] != "sea":
			continue
		var slot: int = b["riders"].find(-1)
		if slot < 0:
			continue
		var c: int = D.WARES[b["w"]]["slots"][slot]
		cands.append({"k": "boat", "b": bi, "slot": slot, "cost": c,
			"label": "%s · posto %d" % [D.ware_name(b["w"]), slot + 1]})
	for id in D.SPOT_ORDER:
		if spots[id] != -1:
			continue
		if id == "S" and not five:
			continue
		if id == "P1" and spots["P0"] == -1:
			continue
		var cost := D.spot_cost(id, final, five)
		cands.append({"k": "spot", "id": id, "cost": cost, "label": D.SPOTS[id]["name"]})
	var f := funds(s)
	var out := []
	for c in cands:
		if c["cost"] <= f:
			out.append(c)
	if out.is_empty():
		if f == 0:
			# clandestino: sale gratis su un barcone
			for c in cands:
				if c["k"] == "boat":
					var c2: Dictionary = c.duplicate()
					c2["cost"] = 0
					c2["stow"] = true
					c2["label"] = c["label"] + " (clandestino)"
					out.append(c2)
		elif free_shares(s) == 0:
			var mn := 999
			for c in cands:
				mn = mini(mn, int(c["cost"]))
			for c in cands:
				if c["cost"] == mn:
					var c3: Dictionary = c.duplicate()
					c3["cost"] = int(players[s]["cash"])
					c3["label"] = c["label"] + " (con tutto quel che hai)"
					out.append(c3)
	if five and wager.is_empty():
		var docks := owns_dock(s)
		for id in docks:
			for v in [1, 2, 3]:
				if v <= f:
					out.append({"k": "wager", "id": id, "v": v, "cost": v,
						"label": "Scommessa %d su %s" % [v, D.SPOTS[id]["name"]]})
	out.append({"k": "pass", "cost": 0, "label": "Passa (niente più complici in questo viaggio)"})
	return out


func _apply_placement(s: int, o: Dictionary, _final: bool) -> void:
	match o["k"]:
		"pass":
			passed[s] = true
			log_msg("%s passa e non piazzerà altri complici." % pname(s))
		"boat":
			var paid := pay(s, int(o["cost"]))
			var b: Dictionary = boats[int(o["b"])]
			var slot := int(b["riders"].find(-1))
			if slot < 0:
				return
			b["riders"][slot] = s
			hand[s] -= 1
			log_msg("%s sale sul barcone di %s%s." % [pname(s), D.ware_name(b["w"]),
				(" (%d pesos)" % paid) if paid > 0 else (" da clandestino" if o.get("stow", false) else "")])
			fx.emit("place", {"seat": s, "boat": int(o["b"]), "slot": slot})
		"spot":
			var id: String = o["id"]
			if spots[id] != -1:
				return
			if id == "I":
				gain(s, 10)
				log_msg("%s fa l'assicuratore e incassa subito 10 pesos." % pname(s))
			else:
				var paid2 := pay(s, int(o["cost"]))
				log_msg("%s occupa %s%s." % [pname(s), D.SPOTS[id]["name"], (" (%d pesos)" % paid2) if paid2 > 0 else ""])
			spots[id] = s
			hand[s] -= 1
			fx.emit("place", {"seat": s, "spot": id})
		"wager":
			var v := int(o["v"])
			pay(s, v)
			wager = {"seat": s, "id": o["id"], "v": v}
			log_msg("%s scommette %d pesos su %s." % [pname(s), v, D.SPOTS[o["id"]]["name"]])
			fx.emit("place", {"seat": s, "wager": o["id"]})


func _roll() -> void:
	phase = "roll"
	roll_no += 1
	dice = []
	for b in boats:
		dice.append(_d6())
	var parts := []
	for bi in boats.size():
		parts.append("%s %d" % [D.WARES[boats[bi]["w"]]["short"], dice[bi]])
	log_msg("Tiro %d: %s." % [roll_no, ", ".join(parts)])
	fx.emit("roll", {"dice": dice.duplicate(), "n": roll_no})
	changed.emit()
	await _wait(1.3)
	for bi in boats.size():
		if boats[bi]["at"] == "sea":
			_move(bi, dice[bi])
	changed.emit()
	await _wait(0.9)
	if roll_no == 2:
		await _boarding()


func _move(bi: int, steps: int) -> void:
	var b: Dictionary = boats[bi]
	b["pos"] = maxi(0, int(b["pos"]) + steps)
	if b["pos"] > 13:
		_dock(bi)


func _dock(bi: int) -> void:
	var b: Dictionary = boats[bi]
	var k := harbor.find(-1)
	if k < 0:
		return
	harbor[k] = bi
	b["at"] = "harbor"
	b["slot"] = k
	b["pos"] = 14
	log_msg("Il barcone di %s attracca al %s." % [D.ware_name(b["w"]), D.SPOTS["H%d" % k]["name"]])
	fx.emit("dock", {"boat": bi, "slot": k})


func _to_yard(bi: int) -> void:
	var b: Dictionary = boats[bi]
	var k := yard.find(-1)
	if k < 0:
		_dock(bi)
		return
	yard[k] = bi
	b["at"] = "yard"
	b["slot"] = k
	log_msg("Il barcone di %s finisce nel %s." % [D.ware_name(b["w"]), D.SPOTS["Y%d" % k]["name"]])


func pirates() -> Array:
	var out := []
	for id in ["P0", "P1"]:
		if spots[id] != -1:
			out.append(spots[id])
	return out


## Abbordaggio dopo il secondo tiro: i pirati possono salire sui barconi fermi sul 13.
func _boarding() -> void:
	var at13 := []
	for bi in boats.size():
		if boats[bi]["at"] == "sea" and boats[bi]["pos"] == 13:
			at13.append(bi)
	if at13.is_empty() or pirates().is_empty():
		return
	phase = "board"
	changed.emit()
	var just := {}    # posti appena occupati da un pirata (non si possono scalzare)
	for id in ["P0", "P1"]:
		var s: int = spots[id]
		if s == -1:
			continue
		var options := boarding_options(at13, just)
		if options.size() <= 1:
			continue
		var r = await decide(s, {"type": "board", "options": options, "pirate": id,
			"title": "Abbordaggio: sali su un barcone fermo sul 13 o resti sulla nave pirata?"})
		if abort: return
		var o: Dictionary = options[_idx(r, options.size())]
		if o["k"] == "stay":
			log_msg("%s resta sulla nave pirata." % pname(s))
			continue
		var b: Dictionary = boats[int(o["b"])]
		var slot := int(o["slot"])
		if o["k"] == "kick":
			var victim: int = b["riders"][slot]
			hand[victim] += 1
			log_msg("%s abborda il barcone di %s e scalza il complice di %s." % [pname(s), D.ware_name(b["w"]), pname(victim)])
		else:
			log_msg("%s abborda il barcone di %s." % [pname(s), D.ware_name(b["w"])])
		b["riders"][slot] = s
		just["%d_%d" % [int(o["b"]), slot]] = true
		spots[id] = -1
		fx.emit("place", {"seat": s, "boat": int(o["b"]), "slot": slot})
		changed.emit()
	if spots["P0"] == -1 and spots["P1"] != -1:
		spots["P0"] = spots["P1"]
		spots["P1"] = -1
		log_msg("%s diventa il capitano dei pirati." % pname(spots["P0"]))
	changed.emit()


func boarding_options(at13: Array, just: Dictionary) -> Array:
	var options := [{"k": "stay", "label": "Resta sulla nave pirata"}]
	var any_free := false
	for bi in at13:
		var slot: int = boats[bi]["riders"].find(-1)
		if slot >= 0:
			any_free = true
			options.append({"k": "board", "b": bi, "slot": slot, "label": "Abborda %s" % D.ware_name(boats[bi]["w"])})
	if not any_free and opts.get("pirates", false):
		for bi in at13:
			var rd: Array = boats[bi]["riders"]
			for k in rd.size():
				if rd[k] != -1 and not just.has("%d_%d" % [bi, k]):
					options.append({"k": "kick", "b": bi, "slot": k,
						"label": "Abborda %s scalzando %s" % [D.ware_name(boats[bi]["w"]), pname(rd[k])]})
	return options


## I piloti entrano in azione prima dell'ultimo tiro: prima il vice, poi il capo.
func _pilots() -> void:
	for id in ["L0", "L1"]:
		var s: int = spots[id]
		if s == -1:
			continue
		var moves := pilot_moves(id)
		if moves.size() <= 1:
			continue
		phase = "pilot"
		changed.emit()
		var r = await decide(s, {"type": "pilot", "id": id, "options": moves,
			"title": "%s: sposta i barconi ancora in mare" % D.SPOTS[id]["name"]})
		if abort: return
		var mv: Dictionary = moves[_idx(r, moves.size())]
		if mv["m"].is_empty():
			log_msg("%s (%s) non sposta nulla." % [pname(s), D.SPOTS[id]["name"]])
			continue
		log_msg("%s (%s): %s." % [pname(s), D.SPOTS[id]["name"], mv["label"]])
		for step in mv["m"]:
			var bi := int(step[0])
			if boats[bi]["at"] == "sea":
				_move(bi, int(step[1]))
		changed.emit()
		await _wait(0.6)


func pilot_moves(id: String) -> Array:
	var sea := []
	for bi in boats.size():
		if boats[bi]["at"] == "sea":
			sea.append(bi)
	var out := [{"m": [], "label": "Nessuno spostamento"}]
	var deltas := [1, -1] if id == "L0" else [2, -2, 1, -1]
	for bi in sea:
		for dd in deltas:
			if boats[bi]["pos"] + dd < 0:
				continue
			out.append({"m": [[bi, dd]], "label": "%s %s%d" % [D.ware_name(boats[bi]["w"]), "+" if dd > 0 else "", dd]})
	if id == "L1":
		for i in sea.size():
			for j in range(i + 1, sea.size()):
				var a: int = sea[i]
				var b: int = sea[j]
				for da in [1, -1]:
					for db in [1, -1]:
						if boats[a]["pos"] + da < 0 or boats[b]["pos"] + db < 0:
							continue
						out.append({"m": [[a, da], [b, db]], "label": "%s %s%d e %s %s%d" % [
							D.ware_name(boats[a]["w"]), "+" if da > 0 else "", da,
							D.ware_name(boats[b]["w"]), "+" if db > 0 else "", db]})
	return out


# ------------------------------------------------------------------ fine della navigazione

func _resolve_end() -> void:
	var pir := pirates()
	# naufragi
	for bi in boats.size():
		var b: Dictionary = boats[bi]
		if b["at"] == "sea" and b["pos"] < 13:
			_to_yard(bi)
	# barconi fermi sul 13: saccheggio
	for bi in boats.size():
		var b: Dictionary = boats[bi]
		if b["at"] != "sea":
			continue
		if pir.is_empty():
			log_msg("Il barcone di %s è sul 13 ma la nave pirata è vuota." % D.ware_name(b["w"]))
			_dock(bi)
			continue
		phase = "plunder"
		b["plundered"] = true
		for k in b["riders"].size():
			b["riders"][k] = -1
		log_msg("I pirati saccheggiano il barcone di %s!" % D.ware_name(b["w"]))
		changed.emit()
		var cap: int = spots["P0"] if spots["P0"] != -1 else spots["P1"]
		var r = await decide(cap, {"type": "plunder", "b": bi,
			"options": [{"k": "harbor", "label": "Al molo (la merce sale di valore)"}, {"k": "yard", "label": "In cantiere"}],
			"title": "Capitano dei pirati: dove porti il barcone di %s?" % D.ware_name(b["w"])})
		if abort: return
		if _idx(r, 2) == 0 and harbor.find(-1) >= 0:
			_dock(bi)
		else:
			_to_yard(bi)
	changed.emit()
	await _wait(0.8)


# ------------------------------------------------------------------ 4. profitti, 5. valori

func _payout() -> void:
	phase = "payout"
	income = {}
	var add := func(s: int, v: int, why: String):
		if s < 0 or v <= 0:
			return
		gain(s, v)
		if not income.has(s):
			income[s] = []
		income[s].append([why, v])
	var pir := pirates()
	for bi in boats.size():
		var b: Dictionary = boats[bi]
		var val: int = D.WARES[b["w"]]["value"]
		if b["plundered"]:
			for s in pir:
				add.call(s, val / pir.size(), "bottino %s" % D.ware_name(b["w"]))
		elif b["at"] == "harbor":
			var riders := []
			for s in b["riders"]:
				if s != -1:
					riders.append(s)
			for s in riders:
				add.call(s, val / riders.size(), "carico %s" % D.ware_name(b["w"]))
	for k in 3:
		var hs: int = spots["H%d" % k]
		if hs != -1 and harbor[k] != -1:
			add.call(hs, D.SPOTS["H%d" % k]["reward"], D.SPOTS["H%d" % k]["name"])
	var insurer: int = spots["I"]
	var debts := []     # [creditore (-1 = cassa), importo, voce]
	for k in 3:
		if yard[k] == -1:
			continue
		var id := "Y%d" % k
		var owner: int = spots[id]
		var rew: int = D.SPOTS[id]["reward"]
		if owner != -1:
			if insurer == -1:
				add.call(owner, rew, D.SPOTS[id]["name"])
			elif insurer != owner:
				debts.append([owner, rew, D.SPOTS[id]["name"]])
		elif insurer != -1:
			debts.append([-1, rew, "riparazione %s" % D.SPOTS[id]["name"]])
	if not wager.is_empty():
		var wid: String = wager["id"]
		var occ: bool = (harbor[D.SPOTS[wid]["slot"]] != -1) if wid.begins_with("H") else (yard[D.SPOTS[wid]["slot"]] != -1)
		if occ:
			add.call(int(wager["seat"]), 2 * int(wager["v"]), "scommessa")
	if spots["S"] != -1:
		add.call(spots["S"], 1, "Malattia")
	for s in income:
		var tot := 0
		var parts := []
		for it in income[s]:
			tot += it[1]
			parts.append("%s %d" % [it[0], it[1]])
		log_msg("%s incassa %d (%s)." % [pname(s), tot, ", ".join(parts)])
	# l'assicuratore paga dopo aver incassato
	for d in debts:
		var paid := pay(insurer, int(d[1]))
		if d[0] != -1:
			gain(int(d[0]), int(d[1]))
			if not income.has(d[0]):
				income[d[0]] = []
			income[d[0]].append([d[2], int(d[1])])
			log_msg("L'assicuratore %s paga %d a %s per il %s%s." % [pname(insurer), paid, pname(d[0]), d[2],
				"" if paid == d[1] else " (il resto lo mette la cassa)"])
		else:
			log_msg("L'assicuratore %s paga %d alla cassa per la %s." % [pname(insurer), paid, d[2]])
		if not income.has(insurer):
			income[insurer] = []
		income[insurer].append(["assicurazione", -paid])
	if insurer != -1:
		if not income.has(insurer):
			income[insurer] = []
		income[insurer].push_front(["premio assicurativo", 10])
	changed.emit()


func _raise_values() -> void:
	for b in boats:
		if b["at"] == "harbor":
			var w: int = b["w"]
			if market[w] < 4:
				market[w] += 1
				log_msg("%s sale a %d al mercato nero." % [D.ware_name(w), D.MARKET[market[w]]])
	fx.emit("market", {})


func _final() -> void:
	phase = "end"
	results = []
	for s in n:
		var shares_v := 0
		for sh in players[s]["shares"]:
			shares_v += D.MARKET[market[sh["w"]]]
		results.append({"seat": s, "wealth": wealth(s), "cash": players[s]["cash"], "shares": shares_v,
			"mort": mortgaged(s)})
	results.sort_custom(func(a, b): return a["wealth"] > b["wealth"] or (a["wealth"] == b["wealth"] and a["cash"] > b["cash"]))
	var parts := []
	for r in results:
		parts.append("%s %d" % [pname(r["seat"]), r["wealth"]])
	log_msg("Fine della partita! Patrimoni: " + ", ".join(parts) + ".")
	log_msg("%s è il contrabbandiere più bravo di Manila!" % pname(results[0]["seat"]))
	changed.emit()
	game_ended.emit(results)


## Impronta della partita (per confrontare le partite online fra dispositivi).
func fingerprint() -> String:
	var parts := [str(voyage), str(market)]
	for p in players:
		parts.append("%d/%d" % [p["cash"], p["shares"].size()])
	return "|".join(parts)
