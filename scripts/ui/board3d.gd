class_name Board3D
extends Node3D
## Il porto di Manila in 3D: tabellone, barconi (dal modello STL), complici, dadi, segnalini del
## mercato nero. Telecamera orbitale: trascina per ruotare, rotella/pizzico per lo zoom,
## tasto destro o centrale (o due dita) per spostare la vista. Clic sulle caselle evidenziate.

signal target_clicked(key: String)
signal target_hovered(key: String)

const D = preload("res://scripts/data/mn_data.gd")
const BOAT_LEN := 3.3
const BOAT_SCALE := Vector3(3.3, 1.8, 3.3)
const DECK_Y := 0.40
const TILE_SIZE := Vector2(0.78, 2.95)

var eng: MNEngine
var cam: Camera3D
var yaw := 0.0
var pitch := 62.0
var dist := 28.0
var focus := Vector3(0, 0, 2.3)
var _yaw_t := 0.0
var _pitch_t := 62.0
var _dist_t := 28.0
var _focus_t := Vector3(0, 0, 2.3)
var view_mode := 0

var boat_mesh: Mesh
var boat_nodes := []         # Node3D per barcone
var boat_state := []         # ultima posizione disegnata
var spot_pawns := {}         # id -> Node3D
var rider_pawns := {}        # "b_slot" -> Node3D
var market_discs := []
var dice_nodes := []
var targets := {}            # key -> Vector3 (punti cliccabili)
var rings := {}              # key -> MeshInstance3D
var preview_cfg := {}
var hover_key := ""
var _drag := false
var _drag_moved := 0.0
var _pan := false
var _touches := {}
var _pinch_d := 0.0
var _t := 0.0
var wager_node: Node3D
var mats := {}


static func px(p: Vector2) -> Vector3:
	return Vector3((p.x - D.BOARD_PX.x / 2.0) / 100.0, 0.0, (p.y - D.BOARD_PX.y / 2.0) / 100.0)


func _ready() -> void:
	_build_env()
	_build_board()
	boat_mesh = load("res://assets/models/boat.obj")
	for w in 4:
		var disc := _disc_mesh(0.24, 0.12, D.WARES[w]["color"])
		add_child(disc)
		market_discs.append(disc)
	for i in 3:
		var dn := _make_die()
		dn.visible = false
		add_child(dn)
		dice_nodes.append(dn)
	wager_node = _make_die()
	wager_node.scale = Vector3.ONE * 0.6
	wager_node.visible = false
	add_child(wager_node)
	_apply_cam(true)


func _process(delta: float) -> void:
	_t += delta
	var k := minf(1.0, delta * 9.0)
	yaw = lerpf(yaw, _yaw_t, k)
	pitch = lerpf(pitch, _pitch_t, k)
	dist = lerpf(dist, _dist_t, k)
	focus = focus.lerp(_focus_t, k)
	_apply_cam(false)
	var pulse := 0.75 + 0.25 * sin(_t * 5.0)
	for key in rings:
		var r: MeshInstance3D = rings[key]
		var s := (1.25 if key == hover_key else 1.0) * (0.95 + 0.08 * sin(_t * 5.0))
		r.scale = Vector3(s, 1, s)
		var m: StandardMaterial3D = r.material_override
		m.albedo_color.a = pulse


# ------------------------------------------------------------------ scena

func _build_env() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	# cielo tropicale
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("#2f86c9")
	sm.sky_horizon_color = Color("#c5ecf0")
	sm.ground_horizon_color = Color("#79cfd2")
	sm.ground_bottom_color = Color("#0d5560")
	sm.sun_angle_max = 20.0
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#b9d8d0")
	e.ambient_light_energy = 0.28
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	e.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	e.background_energy_multiplier = 0.9
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -32, 0)
	sun.light_energy = 0.72
	sun.light_color = Color("#fff0d0")
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-35, 150, 0)
	fill.light_energy = 0.28
	fill.light_color = Color("#a8e0ff")
	add_child(fill)
	cam = Camera3D.new()
	cam.fov = 42.0
	cam.far = 200.0
	add_child(cam)
	cam.current = true


func _build_board() -> void:
	_build_island()
	# tabellone (spessore con bordo scuro, faccia superiore con l'immagine)
	var w := D.BOARD_PX.x / 100.0
	var h := D.BOARD_PX.y / 100.0
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w + 0.3, 0.14, h + 0.3)
	body.mesh = bm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color("#5a3519")
	bmat.roughness = 0.9
	body.material_override = bmat
	body.position.y = -0.075
	add_child(body)
	var top := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(w, h)
	top.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/board/board.jpg")
	mat.roughness = 1.0
	mat.metallic_specular = 0.0
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	top.material_override = mat
	top.position.y = 0.002
	add_child(top)


const SEA_SHADER := """
shader_type spatial;
render_mode specular_schlick_ggx;
uniform vec3 deep : source_color = vec3(0.01, 0.22, 0.30);
uniform vec3 shallow : source_color = vec3(0.10, 0.55, 0.56);
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float d = length(wpos.xz / vec2(9.5, 14.5));
	float t = TIME * 0.6;
	float w = sin(wpos.x * 1.3 + t) * 0.5 + sin(wpos.z * 1.7 - t * 1.3) * 0.5 + sin((wpos.x + wpos.z) * 0.6 + t * 0.7);
	float shore = clamp(1.6 - d, 0.0, 1.0);
	vec3 c = mix(deep, shallow, shore * 0.85 + 0.1);
	float foam = smoothstep(0.92, 1.0, 1.25 - abs(d - 1.12) * 6.0 + w * 0.08);
	ALBEDO = mix(c + w * 0.015, vec3(0.95, 0.98, 0.96), foam * 0.7);
	ROUGHNESS = 0.18;
	METALLIC = 0.0;
	SPECULAR = 0.35;
	NORMAL_MAP = normalize(vec3(0.5 + 0.06 * cos(wpos.x * 1.3 + t), 0.5 + 0.06 * cos(wpos.z * 1.7 - t * 1.3), 1.0));
}
"""


## Isolotto di sabbia nel mare dei Caraibi con qualche palma: il tabellone ci sta sopra.
func _build_island() -> void:
	var sea := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(240, 240)
	pm.subdivide_width = 4
	pm.subdivide_depth = 4
	sea.mesh = pm
	var sh := Shader.new()
	sh.code = SEA_SHADER
	var smat := ShaderMaterial.new()
	smat.shader = sh
	sea.material_override = smat
	sea.position.y = -0.55
	add_child(sea)
	var island := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.12
	cm.height = 0.6
	cm.radial_segments = 48
	island.mesh = cm
	island.material_override = _mat(Color("#a88a52"), 1.0)
	island.scale = Vector3(9.4, 1.0, 14.6)
	island.position.y = -0.46
	add_child(island)
	var rnd := RandomNumberGenerator.new()
	rnd.seed = 1821
	for spot in [Vector3(-7.3, -0.16, -9.6), Vector3(7.6, -0.16, -8.4), Vector3(-7.8, -0.16, 6.5), Vector3(7.9, -0.16, 9.8), Vector3(-8.4, -0.16, -1.5)]:
		var palm := _make_palm(rnd)
		palm.position = spot
		palm.rotation.y = rnd.randf() * TAU
		add_child(palm)
	for k in 7:
		var rock := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = 0.5
		sp.height = 0.6
		rock.mesh = sp
		rock.material_override = _mat(Color("#7d7468"), 0.9)
		var ang := rnd.randf() * TAU
		rock.position = Vector3(cos(ang) * 9.6, -0.3, sin(ang) * 15.0)
		rock.scale = Vector3(rnd.randf_range(0.6, 1.4), rnd.randf_range(0.4, 0.8), rnd.randf_range(0.6, 1.4))
		add_child(rock)


func _make_palm(rnd: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var trunk_m := _mat(Color("#8a6a45"), 0.95)
	var leaf_m := _mat(Color("#1f6b2c"), 0.9).duplicate()
	leaf_m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var lean := Vector3(rnd.randf_range(-0.25, 0.25), 1.0, rnd.randf_range(-0.25, 0.25)).normalized()
	var p := Vector3.ZERO
	var segs := 7
	for i in segs:
		var seg := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = 0.13 - i * 0.008
		c.bottom_radius = 0.16 - i * 0.008
		c.height = 0.62
		seg.mesh = c
		seg.material_override = trunk_m
		var dir := (lean + Vector3(lean.x, 0, lean.z) * i * 0.12).normalized()
		seg.position = p + dir * 0.31
		seg.basis = Basis(Vector3.UP.cross(dir).normalized() if Vector3.UP.cross(dir).length() > 0.001 else Vector3.RIGHT, Vector3.UP.angle_to(dir))
		root.add_child(seg)
		p += dir * 0.58
	for k in 8:
		var leaf := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.42, 0.03, 1.9)
		leaf.mesh = bm
		leaf.material_override = leaf_m
		var holder := Node3D.new()
		holder.position = p
		holder.rotation = Vector3(0, k * TAU / 8 + rnd.randf_range(-0.2, 0.2), 0)
		leaf.position = Vector3(0, -0.25, 0.85)
		leaf.rotation = Vector3(deg_to_rad(rnd.randf_range(24, 42)), 0, 0)
		holder.add_child(leaf)
		root.add_child(holder)
	var nut := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.3
	nut.mesh = sm
	nut.material_override = _mat(Color("#4a3018"), 0.8)
	nut.position = p + Vector3(0, -0.15, 0)
	root.add_child(nut)
	return root


func _mat(c: Color, rough := 0.55) -> StandardMaterial3D:
	var key := "%s_%f" % [c.to_html(), rough]
	if mats.has(key):
		return mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	mats[key] = m
	return m


func _disc_mesh(r: float, hgt: float, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = hgt
	mi.mesh = cm
	mi.material_override = _mat(c, 0.35)
	return mi


## Complice: corpo a cono, testa e cappello conico, come i pedoni della scatola.
func make_pawn(color_id: int) -> Node3D:
	var root := Node3D.new()
	var c: Color = D.COLORS[color_id]["color"]
	var m := _mat(c, 0.45)
	var body := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.09
	cm.bottom_radius = 0.2
	cm.height = 0.42
	body.mesh = cm
	body.material_override = m
	body.position.y = 0.21
	root.add_child(body)
	var head := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.24
	head.mesh = sm
	head.material_override = m
	head.position.y = 0.5
	root.add_child(head)
	var hat := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.0
	hm.bottom_radius = 0.22
	hm.height = 0.16
	hat.mesh = hm
	hat.material_override = m
	hat.position.y = 0.64
	root.add_child(hat)
	return root


func _make_die() -> Node3D:
	var root := Node3D.new()
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5, 0.5, 0.5)
	box.mesh = bm
	box.name = "Box"
	root.add_child(box)
	# sei facce: +Y 1, -Y 6, +X 2, -X 5, +Z 3, -Z 4
	var faces := [[Vector3(0, 1, 0), 1], [Vector3(0, -1, 0), 6], [Vector3(1, 0, 0), 2],
		[Vector3(-1, 0, 0), 5], [Vector3(0, 0, 1), 3], [Vector3(0, 0, -1), 4]]
	for f in faces:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.49, 0.49)
		q.mesh = qm
		q.name = "F%d" % f[1]
		var nrm: Vector3 = f[0]
		q.position = nrm * 0.252
		if nrm.y > 0.5:
			q.rotation_degrees = Vector3(-90, 0, 0)
		elif nrm.y < -0.5:
			q.rotation_degrees = Vector3(90, 0, 0)
		elif nrm.x > 0.5:
			q.rotation_degrees = Vector3(0, 90, 0)
		elif nrm.x < -0.5:
			q.rotation_degrees = Vector3(0, -90, 0)
		elif nrm.z < -0.5:
			q.rotation_degrees = Vector3(0, 180, 0)
		root.add_child(q)
	return root


func _paint_die(dn: Node3D, w: int) -> void:
	(dn.get_node("Box") as MeshInstance3D).material_override = _mat(D.WARES[w]["color"], 0.4)
	for v in range(1, 7):
		var q: MeshInstance3D = dn.get_node("F%d" % v)
		var m := StandardMaterial3D.new()
		m.albedo_texture = UI.die_tex(w, v)
		m.roughness = 0.4
		q.material_override = m


static func die_rot(v: int) -> Vector3:
	match v:
		6: return Vector3(180, 0, 0)
		2: return Vector3(0, 0, 90)
		5: return Vector3(0, 0, -90)
		3: return Vector3(-90, 0, 0)
		4: return Vector3(90, 0, 0)
	return Vector3.ZERO


func _make_boat(w: int) -> Node3D:
	var root := Node3D.new()
	var hull := MeshInstance3D.new()
	hull.mesh = boat_mesh
	hull.scale = BOAT_SCALE
	var hm := _mat(Color("#8a5a32"), 0.7).duplicate()
	hm.cull_mode = BaseMaterial3D.CULL_DISABLED
	hull.material_override = hm
	root.add_child(hull)
	var tile := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = TILE_SIZE
	tile.mesh = qm
	var tmat := StandardMaterial3D.new()
	tmat.albedo_texture = load("res://assets/cargo/w%d.png" % w)
	tmat.roughness = 0.6
	tile.material_override = tmat
	tile.rotation_degrees = Vector3(-90, 0, 0)
	tile.position = Vector3(0, DECK_Y, 0)
	root.add_child(tile)
	return root


## Posizione locale (sul barcone) del cerchio del posto `slot` sulla tessera carico.
static func slot_local(w: int, slot: int) -> Vector3:
	var ys := [135.0, 240.0, 345.0, 450.0] if w == 3 else [160.0, 295.0, 425.0]
	var y: float = ys[slot] / 512.0
	return Vector3(0, DECK_Y, (y - 0.5) * TILE_SIZE.y)


## Trasformazione di un barcone: in mare (prua sulla casella), al molo o in cantiere.
func boat_xform(b: Dictionary) -> Transform3D:
	var t := Transform3D()
	if b["at"] == "harbor" and int(b["slot"]) >= 0:
		var c := px(D.HARBOR_BOX[int(b["slot"])])
		t = Transform3D(Basis(Vector3.UP, deg_to_rad(-8)), c)
	elif b["at"] == "yard" and int(b["slot"]) >= 0:
		var c2 := px(D.YARD_BOX[int(b["slot"])])
		t = Transform3D(Basis(Vector3.UP, deg_to_rad(90)), c2)
	else:
		var bow := px(D.lane_px(int(b["lane"]), clampf(float(b["pos"]), 0.0, 13.0)))
		t = Transform3D(Basis(), bow + Vector3(0, 0, BOAT_LEN / 2.0 - 0.15))
	t.origin.y = 0.0
	return t


# ------------------------------------------------------------------ aggiornamento

func refresh() -> void:
	if eng == null:
		return
	var bs: Array = eng.boats
	if not preview_cfg.is_empty() and bs.is_empty():
		bs = _preview_boats()
	# barconi
	while boat_nodes.size() > bs.size():
		boat_nodes.pop_back().queue_free()
		boat_state.pop_back()
	for i in bs.size():
		var b: Dictionary = bs[i]
		if i >= boat_nodes.size() or boat_nodes[i].get_meta("w") != b["w"]:
			if i < boat_nodes.size():
				boat_nodes[i].queue_free()
				var nb := _make_boat(b["w"])
				nb.set_meta("w", b["w"])
				add_child(nb)
				boat_nodes[i] = nb
				boat_state[i] = ""
			else:
				var nb2 := _make_boat(b["w"])
				nb2.set_meta("w", b["w"])
				add_child(nb2)
				boat_nodes.append(nb2)
				boat_state.append("")
			boat_nodes[i].transform = boat_xform(b)
			if b["at"] == "sea" and preview_cfg.is_empty():
				# entra in acqua dal fondo del tabellone
				boat_nodes[i].position.z += 3.0
		var key := "%s_%s_%s" % [b["at"], b["pos"], b["slot"]]
		if boat_state[i] != key:
			boat_state[i] = key
			var tw := create_tween()
			tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			tw.tween_property(boat_nodes[i], "transform", boat_xform(b), 0.7)
		boat_nodes[i].visible = true
	# complici sui barconi
	var seen := {}
	for i in eng.boats.size():
		var b: Dictionary = eng.boats[i]
		for k in b["riders"].size():
			var s: int = b["riders"][k]
			var key2 := "%d_%d" % [i, k]
			if s == -1:
				continue
			seen[key2] = true
			var pn: Node3D = rider_pawns.get(key2, null)
			if pn == null or pn.get_meta("seat") != s:
				if pn != null:
					pn.queue_free()
				pn = make_pawn(eng.players[s]["color"])
				pn.set_meta("seat", s)
				boat_nodes[i].add_child(pn)
				rider_pawns[key2] = pn
				pn.position = slot_local(b["w"], k) + Vector3(0, 1.2, 0)
				var tw2 := create_tween()
				tw2.tween_property(pn, "position", slot_local(b["w"], k), 0.35).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	for key3 in rider_pawns.keys():
		if not seen.has(key3):
			var pn2: Node3D = rider_pawns[key3]
			if is_instance_valid(pn2):
				pn2.queue_free()
			rider_pawns.erase(key3)
	# complici sulle caselle
	for id in D.SPOT_ORDER:
		var s2: int = eng.spots.get(id, -1)
		var cur: Node3D = spot_pawns.get(id, null)
		if s2 == -1:
			if cur != null:
				cur.queue_free()
				spot_pawns.erase(id)
			continue
		if cur == null or cur.get_meta("seat") != s2:
			if cur != null:
				cur.queue_free()
			cur = make_pawn(eng.players[s2]["color"])
			cur.set_meta("seat", s2)
			add_child(cur)
			spot_pawns[id] = cur
			var p := px(D.SPOT_PX[id])
			cur.position = p + Vector3(0, 1.2, 0)
			var tw3 := create_tween()
			tw3.tween_property(cur, "position", p, 0.35).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	# scommessa (variante 5 giocatori): dado accanto al complice
	if not eng.wager.is_empty():
		_paint_die(wager_node, 0)
		wager_node.visible = true
		wager_node.position = px(D.SPOT_PX[eng.wager["id"]]) + Vector3(-0.55, 0.15, 0)
		wager_node.rotation_degrees = die_rot(int(eng.wager["v"]))
	else:
		wager_node.visible = false
	# mercato nero
	for w in 4:
		var target := px(Vector2(D.MARKET_COL[w], D.MARKET_ROW[eng.market[w]])) + Vector3(0, 0.07, 0)
		var disc: MeshInstance3D = market_discs[w]
		if disc.position.distance_to(target) > 0.01:
			if disc.position == Vector3.ZERO:
				disc.position = target
			else:
				var tw4 := create_tween()
				tw4.tween_property(disc, "position", target + Vector3(0, 0.6, 0), 0.25)
				tw4.tween_property(disc, "position", target, 0.3).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	if eng.boats.is_empty() and preview_cfg.is_empty():
		for dn in dice_nodes:
			dn.visible = false


func _preview_boats() -> Array:
	var out := []
	var lane := 0
	for w in 4:
		if w == int(preview_cfg.get("ex", -1)):
			continue
		out.append({"w": w, "lane": lane, "pos": int(preview_cfg["p"][lane]), "at": "sea", "slot": -1, "riders": []})
		lane += 1
	return out


func set_preview(cfg: Dictionary) -> void:
	preview_cfg = cfg
	refresh()


## Tiro dei dadi: rotolano accanto al mercato nero e si fermano sul risultato.
func roll_dice(vals: Array) -> void:
	for i in dice_nodes.size():
		var dn: Node3D = dice_nodes[i]
		if i >= vals.size() or i >= eng.boats.size():
			dn.visible = false
			continue
		_paint_die(dn, eng.boats[i]["w"])
		dn.visible = true
		var end := Vector3(6.7 + 0.0 * i, 0.25, 4.6 + i * 0.85)
		var start := end + Vector3(-1.5 + randf() * 0.4, 2.2, -2.5 + randf())
		dn.position = start
		dn.rotation_degrees = Vector3(randf() * 360, randf() * 360, randf() * 360)
		var final_rot := die_rot(int(vals[i]))
		var yaw_r := randf_range(-25, 25)
		var tw := create_tween().set_parallel(true)
		tw.tween_property(dn, "position", end, 0.8).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		tw.tween_property(dn, "rotation_degrees", final_rot + Vector3(720, 360 + yaw_r, 360) * 0.0 + Vector3(0, yaw_r, 0), 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


# ------------------------------------------------------------------ caselle cliccabili

## Mostra gli anelli sulle caselle selezionabili. keys: chiave -> posizione 3D.
func set_targets(t: Dictionary) -> void:
	for k in rings:
		rings[k].queue_free()
	rings.clear()
	targets = t
	hover_key = ""
	for k in t:
		var r := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.34
		tm.outer_radius = 0.46
		r.mesh = tm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.35, 1.0, 1.0, 0.95)
		m.emission_enabled = true
		m.emission = Color(0.3, 1.0, 1.0)
		m.emission_energy_multiplier = 2.0
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		r.material_override = m
		r.position = t[k] + Vector3(0, 0.08, 0)
		add_child(r)
		rings[k] = r


## Posizione 3D del prossimo posto libero di un barcone.
func boat_slot_pos(bi: int, slot: int) -> Vector3:
	if bi >= boat_nodes.size():
		return Vector3.ZERO
	var b: Dictionary = eng.boats[bi]
	return boat_xform(b) * slot_local(b["w"], slot)


func spot_pos(id: String) -> Vector3:
	return px(D.SPOT_PX[id])


func _pick(pos: Vector2) -> String:
	var best := ""
	var bd := 46.0
	for k in targets:
		var p3: Vector3 = targets[k]
		if cam.is_position_behind(p3):
			continue
		var sp := cam.unproject_position(p3)
		var dd := sp.distance_to(pos)
		if dd < bd:
			bd = dd
			best = k
	return best


# ------------------------------------------------------------------ telecamera

func _apply_cam(_snap: bool) -> void:
	if cam == null:
		return
	var p := deg_to_rad(pitch)
	var yw := deg_to_rad(yaw)
	var off := Vector3(sin(yw) * cos(p), sin(p), cos(yw) * cos(p)) * dist
	cam.position = focus + off
	if pitch > 88.5:
		cam.look_at(focus, Vector3(-sin(yw), 0, -cos(yw)))
	else:
		cam.look_at(focus, Vector3.UP)


## Viste predefinite: 0 dal fondo del tabellone, 1 di lato (rotta da sinistra a destra), 2 dall'alto.
func reset_view(top := false) -> void:
	set_view(2 if top else 0)


func set_view(m: int) -> void:
	view_mode = m
	match m:
		0:
			_yaw_t = _near_yaw(0.0)
			_pitch_t = 62.0
			_dist_t = 28.0
			_focus_t = Vector3(0, 0, 2.3)
		1:
			_yaw_t = _near_yaw(-90.0)
			_pitch_t = 55.0
			_dist_t = 21.0
			_focus_t = Vector3(0.6, 0, 0.0)
		2:
			_yaw_t = _near_yaw(0.0)
			_pitch_t = 89.0
			_dist_t = 30.0
			_focus_t = Vector3(0, 0, 1.6)


func cycle_view() -> void:
	set_view((view_mode + 1) % 2)


## Angolo equivalente più vicino a quello attuale (per non fare giri inutili).
func _near_yaw(a: float) -> float:
	while a - _yaw_t > 180.0:
		a -= 360.0
	while _yaw_t - a > 180.0:
		a += 360.0
	return a


func rotate_view(dy: float) -> void:
	_yaw_t += dy


func zoom(f: float) -> void:
	_dist_t = clampf(_dist_t * f, 6.0, 40.0)


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			zoom(0.9)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			zoom(1.1)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag = true
				_drag_moved = 0.0
			else:
				if _drag and _drag_moved < 8.0:
					var k := _pick(mb.position)
					if k != "":
						target_clicked.emit(k)
				_drag = false
		elif mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_pan = mb.pressed
	elif ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		if _touches.size() >= 2:
			return
		if _drag and not mm.shift_pressed:
			_drag_moved += mm.relative.length()
			_yaw_t -= mm.relative.x * 0.3
			_pitch_t = clampf(_pitch_t + mm.relative.y * 0.25, 18.0, 89.0)
		elif _pan or (_drag and mm.shift_pressed):
			_drag_moved += mm.relative.length()
			var yw := deg_to_rad(yaw)
			var right := Vector3(cos(yw), 0, -sin(yw))
			var fwd := Vector3(-sin(yw), 0, -cos(yw))
			var f := dist * 0.0016
			_focus_t += (-right * mm.relative.x + fwd * mm.relative.y) * f
			_focus_t.x = clampf(_focus_t.x, -8, 8)
			_focus_t.z = clampf(_focus_t.z, -12, 12)
		else:
			var k2 := _pick(mm.position)
			if k2 != hover_key:
				hover_key = k2
				target_hovered.emit(k2)
	elif ev is InputEventScreenTouch:
		var st := ev as InputEventScreenTouch
		if st.pressed:
			_touches[st.index] = st.position
		else:
			_touches.erase(st.index)
		_pinch_d = 0.0
	elif ev is InputEventScreenDrag:
		var sd := ev as InputEventScreenDrag
		_touches[sd.index] = sd.position
		if _touches.size() >= 2:
			var ks := _touches.keys()
			var d2: float = (_touches[ks[0]] as Vector2).distance_to(_touches[ks[1]])
			if _pinch_d > 0.0:
				_dist_t = clampf(_dist_t * _pinch_d / maxf(1.0, d2), 6.0, 40.0)
			_pinch_d = d2
			_drag_moved = 99.0
	elif ev is InputEventMagnifyGesture:
		zoom(1.0 / (ev as InputEventMagnifyGesture).factor)
	elif ev is InputEventPanGesture:
		_focus_t += Vector3((ev as InputEventPanGesture).delta.x, 0, (ev as InputEventPanGesture).delta.y) * 0.05
