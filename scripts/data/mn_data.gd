class_name MNData
extends RefCounted
## Dati del gioco: merci, caselle del porto, colori dei giocatori, posizioni sul tabellone.

## Valori del mercato nero (indice 0..4). La partita finisce quando una merce arriva a 30.
const MARKET := [0, 5, 10, 20, 30]

## Le quattro merci, nell'ordine delle colonne del mercato nero.
const WARES := [
	{"key": "nutmeg", "name": "Noce moscata", "short": "Noce m.", "value": 24, "slots": [2, 3, 4], "color": Color("#8a5426"), "light": Color("#d39a5c"), "pip": Color("#f6e7c8")},
	{"key": "silk", "name": "Seta", "short": "Seta", "value": 30, "slots": [3, 4, 5], "color": Color("#2f56c9"), "light": Color("#7d9cf2"), "pip": Color("#ffffff")},
	{"key": "ginseng", "name": "Ginseng", "short": "Ginseng", "value": 18, "slots": [1, 2, 3], "color": Color("#e2d39a"), "light": Color("#f1e7bd"), "pip": Color("#5a4420")},
	{"key": "jade", "name": "Giada", "short": "Giada", "value": 36, "slots": [3, 4, 5, 5], "color": Color("#2c8a55"), "light": Color("#79d29b"), "pip": Color("#ffffff")},
]

## I cinque colori dei complici (quelli della scatola).
const COLORS := [
	{"id": 0, "key": "black", "name": "Nero", "color": Color("#2a2a2e"), "light": Color("#b8b8c4")},
	{"id": 1, "key": "orange", "name": "Arancione", "color": Color("#ef8a1d"), "light": Color("#ffb45c")},
	{"id": 2, "key": "yellow", "name": "Giallo", "color": Color("#f1cf1e"), "light": Color("#ffe56a")},
	{"id": 3, "key": "blue", "name": "Blu", "color": Color("#2149d4"), "light": Color("#7d9bff")},
	{"id": 4, "key": "red", "name": "Rosso", "color": Color("#d4292b"), "light": Color("#ff7474")},
]

## Caselle per i complici fuori dai barconi.
## cost: quanto si paga (l'assicuratore riceve 10: costo -10); reward: guadagno del molo/cantiere.
const SPOTS := {
	"H0": {"name": "Molo A", "cost": 4, "reward": 6, "kind": "harbor", "slot": 0},
	"H1": {"name": "Molo B", "cost": 3, "reward": 8, "kind": "harbor", "slot": 1},
	"H2": {"name": "Molo C", "cost": 2, "reward": 15, "kind": "harbor", "slot": 2},
	"Y0": {"name": "Cantiere A", "cost": 4, "reward": 6, "kind": "yard", "slot": 0},
	"Y1": {"name": "Cantiere B", "cost": 3, "reward": 8, "kind": "yard", "slot": 1},
	"Y2": {"name": "Cantiere C", "cost": 2, "reward": 15, "kind": "yard", "slot": 2},
	"P0": {"name": "Capitano dei pirati", "cost": 5, "kind": "pirate"},
	"P1": {"name": "Secondo pirata", "cost": 5, "kind": "pirate"},
	"L0": {"name": "Vice pilota", "cost": 2, "kind": "pilot"},
	"L1": {"name": "Capo pilota", "cost": 5, "kind": "pilot"},
	"I": {"name": "Assicuratore", "cost": -10, "kind": "insurance"},
	"S": {"name": "Malattia", "cost": 0, "kind": "sick"},
}
const SPOT_ORDER := ["H0", "H1", "H2", "Y0", "Y1", "Y2", "P0", "P1", "L0", "L1", "I", "S"]

## Posizioni sul tabellone (pixel dell'immagine 1112×2183).
const BOARD_PX := Vector2(1112, 2183)
const SPOT_PX := {
	"Y2": Vector2(144, 90), "Y1": Vector2(144, 250), "Y0": Vector2(144, 414),
	"H0": Vector2(1020, 406), "H1": Vector2(1016, 750), "H2": Vector2(1016, 1074),
	"P0": Vector2(128, 666), "P1": Vector2(62, 666),
	"L0": Vector2(50, 984), "L1": Vector2(50, 1126),
	"I": Vector2(990, 1400), "S": Vector2(1070, 1480),
}
## Riquadri dove attraccano i barconi: centro e orientamento (vero = barcone in verticale).
const HARBOR_BOX := [Vector2(950, 420), Vector2(936, 760), Vector2(910, 1070)]
const YARD_BOX := [Vector2(380, 456), Vector2(380, 296), Vector2(380, 150)]
const MARKET_COL := [835, 905, 975, 1048]
const MARKET_ROW := [2050, 1988, 1925, 1860, 1793]   # indice 0 (valore 0) .. 4 (valore 30)


## Centro della prua di un barcone sulla rotta `lane` alla posizione k (0..13), in pixel.
static func lane_px(lane: int, k: float) -> Vector2:
	var x0: float = [292.0, 452.0, 620.0][lane]
	var x1: float = [342.0, 516.0, 682.0][lane]
	var t := (k - 1.0) / 11.0
	var x := x0 + (x1 - x0) * t
	var y := 1810.0 - 91.0 * k + 0.1 * (x - 230.0)
	return Vector2(x, y)


static func ware_name(w: int) -> String:
	return WARES[w]["name"]


static func spot_cost(id: String, final_round: bool, five: bool) -> int:
	if five and final_round:
		if id == "L0":
			return 1
		if id == "L1":
			return 3
	return SPOTS[id]["cost"]


## Aumento di valore di una quota quando la merce sale di una casella.
static func delta(idx: int) -> int:
	if idx >= 4:
		return 0
	return MARKET[idx + 1] - MARKET[idx]
