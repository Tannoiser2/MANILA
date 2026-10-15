class_name MNAI
extends RefCounted
## Intelligenza artificiale di Manila.
## Il cuore è un calcolo esatto delle probabilità: ogni barcone in mare, con i tiri che restano,
## finisce attraccato (D), fermo sul 13 (T) o naufragato (W); i barconi sono indipendenti, quindi
## le 27 combinazioni di esiti si pesano e si valuta il guadagno atteso di ogni scelta
## (carichi, moli, cantieri, assicurazione, pirati, valore delle proprie quote).
## Livelli: 0 Facile (rumore, niente finezze), 1 Normale, 2 Difficile (diluizione dei carichi,
## valore dei piloti con simulazione, gestione del denaro più attenta).
## L'IA non sbircia le quote degli avversari: usa solo le proprie e le informazioni pubbliche.

const D = preload("res://scripts/data/mn_data.gd")
const OD := 0
const OT := 1
const OW := 2

var level := 1
var rng := RandomNumberGenerator.new()

# distribuzione della somma di r dadi: _sum[r][s] = probabilità
static var _sum := []
static var _tab := {}


static func _init_tables() -> void:
	if not _sum.is_empty():
		return
	_sum = [[1.0]]
	for r in range(1, 4):
		var prev: Array = _sum[r - 1]
		var cur := []
		cur.resize(prev.size() + 6)
		cur.fill(0.0)
		for s in prev.size():
			if prev[s] == 0.0:
				continue
			for d in range(1, 7):
				cur[s + d] += prev[s] / 6.0
		_sum.append(cur)


## [pD, pT, pW] per un barcone in mare alla posizione pos con r tiri da fare.
static func dist(pos: int, r: int) -> Array:
	_init_tables()
	var key := pos * 10 + r
	if _tab.has(key):
		return _tab[key]
	var sd: Array = _sum[r]
	var pd := 0.0
	var pt := 0.0
	for s in sd.size():
		if pos + s >= 14:
			pd += sd[s]
		elif pos + s == 13:
			pt += sd[s]
	var out := [pd, pt, maxf(0.0, 1.0 - pd - pt)]
	_tab[key] = out
	return out


## Probabilità di essere esattamente sul 13 dopo r tiri (senza aver superato prima: i dadi sono positivi).
static func p_exact13(pos: int, r: int) -> float:
	_init_tables()
	var need := 13 - pos
	var sd: Array = _sum[r]
	if need < 0 or need >= sd.size():
		return 0.0
	return sd[need]


# ------------------------------------------------------------------ contesto di valutazione

## Fotografia dello stato utile alla valutazione (si può modificare per le ipotesi).
func ctx_of(eng: MNEngine, p: int) -> Dictionary:
	var bs := []
	for b in eng.boats:
		bs.append({"w": b["w"], "pos": b["pos"], "at": b["at"], "riders": b["riders"].duplicate(), "slot": b["slot"]})
	var sh := [0, 0, 0, 0]
	for s in eng.players[p]["shares"]:
		sh[s["w"]] += 1
	return {"boats": bs, "spots": eng.spots.duplicate(), "market": eng.market.duplicate(), "shares": sh,
		"harbor": eng.harbor.duplicate(), "yard": eng.yard.duplicate(), "wager": eng.wager.duplicate(),
		"rolls": 3 - eng.roll_no, "endgame": _endgame(eng)}


## Peso del valore delle quote: più la fine è vicina, più l'aumento è "vero".
func _endgame(eng: MNEngine) -> float:
	var top := 0
	for w in 4:
		top = maxi(top, eng.market[w])
	return 0.75 + 0.08 * top


## Guadagno atteso del giocatore p nel contesto c, considerando i tiri che restano.
func ev(p: int, c: Dictionary) -> float:
	var bs: Array = c["boats"]
	var probs := []
	for b in bs:
		if b["at"] == "sea":
			probs.append(dist(int(b["pos"]), int(c["rolls"])))
		elif b["at"] == "harbor":
			probs.append([1.0, 0.0, 0.0])
		else:
			probs.append([0.0, 0.0, 1.0])
	var total := 0.0
	var outc := [0, 0, 0]
	for o0 in 3:
		var p0: float = probs[0][o0] if bs.size() > 0 else 1.0
		if p0 == 0.0:
			continue
		for o1 in 3:
			var p1: float = probs[1][o1] if bs.size() > 1 else (1.0 if o1 == 0 else 0.0)
			if p1 == 0.0:
				continue
			for o2 in 3:
				var p2: float = probs[2][o2] if bs.size() > 2 else (1.0 if o2 == 0 else 0.0)
				if p2 == 0.0:
					continue
				outc[0] = o0
				outc[1] = o1
				outc[2] = o2
				total += p0 * p1 * p2 * payoff(p, c, outc)
	return total


## Guadagno di p per una data combinazione di esiti finali dei barconi.
func payoff(p: int, c: Dictionary, outc: Array) -> float:
	var bs: Array = c["boats"]
	var sp: Dictionary = c["spots"]
	var pir := []
	for id in ["P0", "P1"]:
		if sp[id] != -1:
			pir.append(sp[id])
	var nh := 0
	var ny := 0
	var v := 0.0
	var sw: float = c["endgame"]
	var mk: Array = c["market"]
	var sh: Array = c["shares"]
	for bi in bs.size():
		var b: Dictionary = bs[bi]
		var o: int = outc[bi]
		var val: float = D.WARES[b["w"]]["value"]
		var docked := false
		if o == OD:
			docked = true
		elif o == OT:
			if pir.is_empty():
				docked = true
			else:
				# saccheggio: il bottino ai pirati; il capitano lo porta al molo (merce in aumento)
				var mine := pir.count(p)
				v += val * mine / pir.size()
				docked = true
				nh += 1
				v += sh[b["w"]] * D.delta(mk[b["w"]]) * sw
				continue
		else:
			ny += 1
			continue
		if docked:
			nh += 1
			var cnt := 0
			var my := 0
			for r in b["riders"]:
				if r != -1:
					cnt += 1
					if r == p:
						my += 1
			if cnt > 0:
				v += val * my / cnt
			v += sh[b["w"]] * D.delta(mk[b["w"]]) * sw
	var ins: int = sp["I"]
	for k in 3:
		if k < nh and sp["H%d" % k] == p:
			v += D.SPOTS["H%d" % k]["reward"]
		if k < ny:
			var owner: int = sp["Y%d" % k]
			var rew: float = D.SPOTS["Y%d" % k]["reward"]
			if owner == p and ins != p:
				v += rew
			elif ins == p and owner != p:
				v -= rew
	var wg: Dictionary = c["wager"]
	if not wg.is_empty() and int(wg["seat"]) == p:
		var k2: int = D.SPOTS[wg["id"]]["slot"]
		var occ := (k2 < nh) if str(wg["id"]).begins_with("H") else (k2 < ny)
		if occ:
			v += 2 * int(wg["v"])
	return v


# ------------------------------------------------------------------ decisioni

func decide(eng: MNEngine, s: int, req: Dictionary):
	match req.get("type", ""):
		"bid":
			return _bid_open(eng, s, req)
		"bid_blind":
			return _bid_blind(eng, s, req)
		"buy":
			return _buy(eng, s, req)
		"load":
			return default_load(eng, s)
		"place":
			return _place(eng, s, req)
		"board":
			return _board(eng, s, req)
		"pilot":
			return _pilot(eng, s, req)
		"plunder":
			return _plunder(eng, s, req)
	return 0


func _noise() -> float:
	match level:
		0: return rng.randf_range(-4.0, 4.0)
		1: return rng.randf_range(-1.0, 1.0)
	return rng.randf_range(-0.15, 0.15)


## Configurazioni possibili dei barconi: [esclusa, [p0,p1,p2]].
static func load_configs() -> Array:
	var out := []
	for ex in 4:
		for a in 6:
			for b in 6:
				var c := 9 - a - b
				if c < 0 or c > 5:
					continue
				out.append([ex, [a, b, c]])
	return out


## Interesse del giocatore per una configurazione: aumento atteso delle proprie quote.
func _stake(eng: MNEngine, s: int, cfg: Array) -> float:
	var sh := [0, 0, 0, 0]
	for x in eng.players[s]["shares"]:
		sh[x["w"]] += 1
	var lane := 0
	var v := 0.0
	var sw := _endgame(eng)
	for w in 4:
		if w == cfg[0]:
			continue
		var pd: float = dist(int(cfg[1][lane]), 3)[0]
		v += sh[w] * D.delta(eng.market[w]) * pd * sw
		lane += 1
	return v


## Valore del primo piazzamento (il capitano piazza per primo): il miglior carico singolo.
func _first_pick(eng: MNEngine, cfg: Array) -> float:
	var lane := 0
	var best := 0.0
	for w in 4:
		if w == cfg[0]:
			continue
		var pd: float = dist(int(cfg[1][lane]), 3)[0]
		var val: float = D.WARES[w]["value"]
		# con altri che salgono il carico si divide: stima prudente
		best = maxf(best, val * pd * 0.55 - D.WARES[w]["slots"][0])
		lane += 1
	return best


func default_load(eng: MNEngine, s: int) -> Dictionary:
	var best: Array = []
	var bv := -1e9
	for cfg in load_configs():
		var v := _stake(eng, s, cfg) + 0.5 * _first_pick(eng, cfg) + _noise() * 0.5
		if v > bv:
			bv = v
			best = cfg
	return {"ex": best[0], "p": best[1].duplicate()}


## Quanto vale per s comandare la capitaneria in questo viaggio.
func hm_value(eng: MNEngine, s: int) -> float:
	var sts := []
	var best := -1e9
	for cfg in load_configs():
		var st := _stake(eng, s, cfg)
		sts.append(st)
		best = maxf(best, st + 0.5 * _first_pick(eng, cfg))
	sts.sort()
	var tot := 0.0
	for x in sts:
		tot += x
	var mean := tot / sts.size()
	var low := 0.0
	var q := maxi(1, sts.size() / 4)
	for i in q:
		low += sts[i]
	low /= q
	# se vince un altro sceglie per sé: in media una configurazione qualunque, a volte contro di me
	var other := lerpf(mean, low, 0.35)
	if level == 0:
		# Facile: guarda solo le proprie quote
		return 4.5 + (sts[sts.size() - 1] - mean)
	var v := best - other
	# la quota che solo il capitano può comprare (e poi favorire)
	var buy := 0.0
	for w in 4:
		if eng.supply[w] > 0:
			var g := _share_end_value(eng, w) - eng.share_price(w)
			# con la capitaneria posso spingere proprio quella merce
			g += D.delta(eng.market[w]) * 0.6 * _endgame(eng)
			buy = maxf(buy, g)
	v += maxf(0.0, buy) * 0.8
	return maxf(2.0, v)


func _bid_cap(eng: MNEngine, s: int) -> int:
	var v := hm_value(eng, s)
	# fattori tarati con centinaia di partite IA contro IA: la capitaneria vale molto
	# (scelta dei carichi, quota esclusiva, primo complice) e la Difficile la paga di più
	var f: float = [0.6, 0.45, 0.7][level]
	var cash: int = eng.players[s]["cash"]
	# chi ha molto denaro può permettersi di spendere: il denaro conta solo quanto rende
	var reserve := 4 if level == 0 else 8
	return int(clampf(floorf(v * f), 0.0, maxf(0.0, cash - reserve)))


func _bid_open(eng: MNEngine, s: int, req: Dictionary) -> int:
	var cur: int = req["cur"]
	var cap := _bid_cap(eng, s)
	if level == 0:
		cap += rng.randi_range(-2, 2)
	if cur + 1 <= cap and cur + 1 <= int(req["max"]):
		return cur + 1
	return 0


func _bid_blind(eng: MNEngine, s: int, req: Dictionary) -> int:
	var cap := _bid_cap(eng, s)
	var b := int(round(cap * rng.randf_range(0.55, 0.9)))
	return clampi(b, 0, int(req["max"]))


## Quanto vale alla fine una quota di w (stima del valore finale atteso).
func _share_end_value(eng: MNEngine, w: int) -> float:
	var top := 0
	for x in 4:
		top = maxi(top, eng.market[x])
	var left := maxf(1.0, (4.0 - top) / 0.8)   # viaggi che restano, all'incirca
	var steps := minf(4.0 - eng.market[w], left * 0.55)
	var idx: float = eng.market[w] + steps
	var lo := int(floor(idx))
	var hi := mini(4, lo + 1)
	var t: float = idx - lo
	return lerpf(D.MARKET[mini(4, lo)], D.MARKET[hi], t)


func _buy(eng: MNEngine, s: int, req: Dictionary) -> int:
	var best := -1
	var bv := 2.0 if level > 0 else 0.0
	var cash: int = eng.players[s]["cash"]
	for w in req["options"]:
		var price := eng.share_price(w)
		if cash - price < (10 if level > 0 else 4):
			continue
		var v := _share_end_value(eng, w) - price + 1.5 * eng.share_count(s, w) + _noise()
		if v > bv:
			bv = v
			best = w
	return best


## Valore (atteso, al netto del costo) di una mossa di piazzamento.
func placement_value(eng: MNEngine, s: int, o: Dictionary, base_ev: float, c0: Dictionary) -> float:
	var k: String = o["k"]
	if k == "pass":
		return -2.0
	var c: Dictionary = c0.duplicate(true)
	var cost := float(o["cost"])
	var extra := 0.0
	if k == "boat":
		var b: Dictionary = c["boats"][int(o["b"])]
		b["riders"][int(o["slot"])] = s
	elif k == "spot":
		c["spots"][o["id"]] = s
		if o["id"] == "P0" or o["id"] == "P1":
			extra += _boarding_bonus(eng, s, c0)
		if o["id"] == "L0" or o["id"] == "L1":
			extra += _pilot_value(eng, s, c, o["id"])
	elif k == "wager":
		c["wager"] = {"seat": s, "id": o["id"], "v": o["v"]}
	var gain := ev(s, c) - base_ev
	if k == "boat" and level > 0:
		# altri complici potrebbero salire dopo e dividere il carico
		var b2: Dictionary = c["boats"][int(o["b"])]
		var free: int = b2["riders"].count(-1)
		var turns_left := _turns_left(eng, s)
		var exp_more := minf(float(free), turns_left * 0.22)
		var cnt: int = b2["riders"].size() - free
		gain *= float(cnt) / (cnt + exp_more)
	# impegnare quote costa 3 pesos ciascuna alla fine (12 ricevuti, 15 da restituire)
	var cash: int = eng.players[s]["cash"]
	if cost > cash:
		cost += 3.0 * ceilf((cost - cash) / 12.0)
	# tenere qualche pesos per i viaggi successivi (asta, piazzamenti)
	if level == 2 and cash - cost < 6 and cost > 0:
		cost += 1.0
	return gain + extra - cost


func _turns_left(eng: MNEngine, s: int) -> float:
	var t := 0.0
	for x in eng.n:
		if x != s and not eng.passed[x]:
			t += mini(eng.hand[x], eng.place_rounds - eng.place_round)
	return t


func _boarding_bonus(eng: MNEngine, s: int, c: Dictionary) -> float:
	if eng.roll_no >= 2:
		return 0.0
	var r := 2 - eng.roll_no
	var v := 0.0
	for b in c["boats"]:
		if b["at"] != "sea":
			continue
		var free: int = b["riders"].count(-1)
		if free <= 0:
			continue
		var cnt: int = b["riders"].size() - free
		v += p_exact13(int(b["pos"]), r) * float(D.WARES[b["w"]]["value"]) / (cnt + 1) * 0.6
	return v


## Valore di poter pilotare: miglioramento atteso del guadagno con la mossa migliore prima dell'ultimo tiro.
func _pilot_value(eng: MNEngine, s: int, c: Dictionary, id: String) -> float:
	var before := 2 - eng.roll_no    # tiri prima dell'azione dei piloti
	if before < 0:
		return 0.0
	if level == 0:
		return 3.0 if id == "L1" else 1.5
	var samples := 1 if before == 0 else (8 if level == 1 else 16)
	var tot := 0.0
	for k in samples:
		var c2: Dictionary = c.duplicate(true)
		for b in c2["boats"]:
			if b["at"] != "sea":
				continue
			for t in before:
				b["pos"] = int(b["pos"]) + rng.randi_range(1, 6)
			if b["pos"] > 13:
				b["at"] = "harbor"
		c2["rolls"] = 1
		var base := ev(s, c2)
		var best := base
		for mv in _moves_for(c2, id):
			var c3: Dictionary = c2.duplicate(true)
			_apply_moves(c3, mv)
			best = maxf(best, ev(s, c3))
		tot += best - base
	return tot / samples * 0.85


func _moves_for(c: Dictionary, id: String) -> Array:
	var sea := []
	for bi in c["boats"].size():
		if c["boats"][bi]["at"] == "sea":
			sea.append(bi)
	var out := []
	var deltas := [1, -1] if id == "L0" else [2, -2, 1, -1]
	for bi in sea:
		for dd in deltas:
			if c["boats"][bi]["pos"] + dd >= 0:
				out.append([[bi, dd]])
	if id == "L1":
		for i in sea.size():
			for j in range(i + 1, sea.size()):
				for da in [1, -1]:
					for db in [1, -1]:
						if c["boats"][sea[i]]["pos"] + da >= 0 and c["boats"][sea[j]]["pos"] + db >= 0:
							out.append([[sea[i], da], [sea[j], db]])
	return out


func _apply_moves(c: Dictionary, mv: Array) -> void:
	for st in mv:
		var b: Dictionary = c["boats"][int(st[0])]
		if b["at"] != "sea":
			continue
		b["pos"] = maxi(0, int(b["pos"]) + int(st[1]))
		if b["pos"] > 13:
			b["at"] = "harbor"


func _place(eng: MNEngine, s: int, req: Dictionary) -> int:
	var options: Array = req["options"]
	var c0 := ctx_of(eng, s)
	var base := ev(s, c0)
	var best := options.size() - 1
	var bv := -1e9
	for i in options.size():
		var v := placement_value(eng, s, options[i], base, c0) + _noise()
		if v > bv:
			bv = v
			best = i
	return best


func _board(eng: MNEngine, s: int, req: Dictionary) -> int:
	var options: Array = req["options"]
	var best := 0
	var bv := -1e9
	for i in options.size():
		var o: Dictionary = options[i]
		var c := ctx_of(eng, s)
		c["rolls"] = 1
		if o["k"] != "stay":
			c["boats"][int(o["b"])]["riders"][int(o["slot"])] = s
			var id: String = req.get("pirate", "P0")
			c["spots"][id] = -1
			if id == "P0" and c["spots"]["P1"] != -1:
				c["spots"]["P0"] = c["spots"]["P1"]
				c["spots"]["P1"] = -1
		var v := ev(s, c) + _noise() * 0.3
		if v > bv:
			bv = v
			best = i
	return best


func _pilot(eng: MNEngine, s: int, req: Dictionary) -> int:
	var options: Array = req["options"]
	var best := 0
	var bv := -1e9
	for i in options.size():
		var c := ctx_of(eng, s)
		c["rolls"] = 1
		_apply_moves(c, options[i]["m"])
		var v := ev(s, c) + (_noise() * 0.5 if i > 0 else 0.0)
		if v > bv + 0.01:
			bv = v
			best = i
	return best


func _plunder(eng: MNEngine, s: int, req: Dictionary) -> int:
	var bi: int = req["b"]
	var w: int = eng.boats[bi]["w"]
	# al molo: la merce sale (bene se ho quote) e si riempie un molo; in cantiere paga l'assicuratore
	var v_h := float(eng.share_count(s, w) * D.delta(eng.market[w]))
	var k := eng.harbor.find(-1)
	if k >= 0 and eng.spots["H%d" % k] == s:
		v_h += D.SPOTS["H%d" % k]["reward"]
	var v_y := 0.0
	var ky := eng.yard.find(-1)
	if ky >= 0:
		var owner: int = eng.spots["Y%d" % ky]
		var rew: float = D.SPOTS["Y%d" % ky]["reward"]
		if owner == s and eng.spots["I"] != s:
			v_y += rew
		if eng.spots["I"] == s and owner != s:
			v_y -= rew
	return 0 if v_h >= v_y else 1
