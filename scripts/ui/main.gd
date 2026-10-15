extends Control
## Radice dell'applicazione: alterna menu, partita e regole.

var current: Control
## Collegamento a Firebase per il gioco online (resta vivo fra menu e partita).
var net: Net
## Stanza online in preparazione: {role, code, seat}. Vuota se non si è in una stanza.
var lobby := {}
## Ultime scelte del menu (si ritrovano tornando al menu).
var menu_state := {}
var bg: ColorRect


func get_net() -> Net:
	if net == null:
		net = Net.new()
		add_child(net)
	return net


func _ready() -> void:
	theme = UI.make_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# la radice non deve trattenere il mouse: altrimenti il porto 3D non riceve trascinamenti e rotella
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg = ColorRect.new()
	bg.color = Color("#06100f")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	show_menu()


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and ev.keycode == KEY_F11:
		if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _clear() -> void:
	if current != null:
		current.queue_free()
		current = null


func show_menu() -> void:
	_clear()
	bg.visible = true
	var m := preload("res://scripts/ui/menu.gd").new()
	m.main = self
	add_child(m)
	current = m


func start_game(config: Dictionary) -> void:
	_clear()
	bg.visible = false
	var g := preload("res://scripts/ui/game_view.gd").new()
	g.main = self
	g.config = config
	add_child(g)
	current = g


func show_rules() -> void:
	_clear()
	bg.visible = true
	var t := preload("res://scripts/ui/rules_view.gd").new()
	t.main = self
	add_child(t)
	current = t
