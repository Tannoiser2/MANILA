class_name Audio
extends Node
## Musica (calypso morbido con steel drum, in loop) ed effetti sonori. Tutto sintetizzato da
## tools/sintetizza_audio.py. Musica ed effetti si spengono separatamente; le scelte restano salvate.

const SETTINGS := "user://suoni.cfg"
const SFX := ["click", "pawn", "dice", "coin", "splash", "bell", "cannon", "market", "turn", "voyage", "win"]
const MUSIC_DB := -11.0

static var me: Audio
## Vero mentre si rigioca una partita online già in corso: niente raffica di suoni.
static var suspended := false

var music_on := true
var sfx_on := true
var music: AudioStreamPlayer
var pool: Array = []
var streams := {}


func _ready() -> void:
	me = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	var c := ConfigFile.new()
	if c.load(SETTINGS) == OK:
		music_on = bool(c.get_value("s", "music", true))
		sfx_on = bool(c.get_value("s", "sfx", true))
	for n in SFX:
		streams[n] = load("res://assets/audio/%s.wav" % n)
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		pool.append(p)
	music = AudioStreamPlayer.new()
	var st: AudioStreamOggVorbis = load("res://assets/audio/musica.ogg")
	st.loop = true
	music.stream = st
	music.volume_db = MUSIC_DB
	add_child(music)
	if music_on:
		music.play()


func _save() -> void:
	var c := ConfigFile.new()
	c.set_value("s", "music", music_on)
	c.set_value("s", "sfx", sfx_on)
	c.save(SETTINGS)


## Suona un effetto (se gli effetti sono accesi). vol in dB.
static func play(name: String, vol := 0.0) -> void:
	if me == null or suspended or not me.sfx_on or not me.streams.has(name):
		return
	for p in me.pool:
		if not p.playing:
			p.stream = me.streams[name]
			p.volume_db = vol - 4.0
			p.pitch_scale = randf_range(0.96, 1.04) if name in ["click", "pawn", "coin", "dice"] else 1.0
			p.play()
			return


static func set_music(on: bool) -> void:
	if me == null:
		return
	me.music_on = on
	if on and not me.music.playing:
		me.music.play()
	elif not on:
		me.music.stop()
	me._save()


static func set_sfx(on: bool) -> void:
	if me == null:
		return
	me.sfx_on = on
	me._save()


static func music_enabled() -> bool:
	return me != null and me.music_on


static func sfx_enabled() -> bool:
	return me != null and me.sfx_on


## Pulsante che accende/spegne musica o effetti, con l'etichetta aggiornata.
static func toggle_button(kind: String, w := 150.0, h := 46.0) -> Button:
	var b := UI.button("", w, h, 20)
	var paint := func():
		var on := music_enabled() if kind == "music" else sfx_enabled()
		b.text = ("Musica" if kind == "music" else "Effetti") + (": sì" if on else ": no")
		if on:
			UI.selected(b, "sea")
		else:
			b.add_theme_stylebox_override("normal", UI.plank("wood_off"))
			b.add_theme_stylebox_override("hover", UI.plank("wood_hover"))
	b.pressed.connect(func():
		if kind == "music":
			set_music(not music_enabled())
		else:
			set_sfx(not sfx_enabled())
		paint.call())
	b.tooltip_text = "Accende o spegne la musica caraibica" if kind == "music" else "Accende o spegne gli effetti sonori"
	paint.call()
	return b
