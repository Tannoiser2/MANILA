class_name UI
extends RefCounted
## Stile grafico di Manila: pergamene, assi di legno, mare turchese e corallo.
## Titoli in Pirata One, testo in Alegreya Sans.

const INK := Color("#3a2213")        # inchiostro sulla pergamena
const INK2 := Color("#6b4a2b")       # testo secondario
const SEA := Color("#138d90")
const SEA_DARK := Color("#0b5d63")
const CORAL := Color("#d4552b")
const SAND := Color("#f3e4c1")
const GOLD := Color("#e9a93a")
const LIGHT := Color("#fff3dc")      # testo chiaro sul legno
const RED := Color("#b3261e")
const GREEN := Color("#2e7d4f")
const DARK := Color("#24140a")

static var _tex := {}
static var font_title: Font
static var font_body: Font
static var font_bold: Font
static var font_heavy: Font
static var font_italic: Font


static func init_fonts() -> void:
	if font_title != null:
		return
	font_title = load("res://assets/fonts/PirataOne-Regular.ttf")
	font_body = load("res://assets/fonts/AlegreyaSans-Medium.ttf")
	font_bold = load("res://assets/fonts/AlegreyaSans-Bold.ttf")
	font_heavy = load("res://assets/fonts/AlegreyaSans-ExtraBold.ttf")
	font_italic = load("res://assets/fonts/AlegreyaSans-BoldItalic.ttf")


static func tex(path: String) -> Texture2D:
	if not _tex.has(path):
		_tex[path] = load(path)
	return _tex[path]


static func pawn(color_id: int) -> Texture2D:
	return tex("res://assets/pawns/%s.png" % MNData.COLORS[color_id]["key"])


static func card(w: int) -> Texture2D:
	return tex("res://assets/cards/w%d.jpg" % w)


static func card_back() -> Texture2D:
	return tex("res://assets/cards/back.jpg")


static func coin(v: int) -> Texture2D:
	return tex("res://assets/coins/c%d.png" % v)


static func die_tex(w: int, v: int) -> Texture2D:
	return tex("res://assets/dice/w%d_%d.png" % [w, clampi(v, 1, 6)])


## Riquadro piatto (evidenziazioni, celle).
static func panel_style(bg: Color, border: Color, bw := 1, radius := 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(10)
	return sb


## Pergamena con i bordi strappati.
static func paper(dark := false, margin := 18.0) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = tex("res://assets/ui/parchment_dark.png" if dark else "res://assets/ui/parchment.png")
	sb.set_texture_margin_all(40)
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	sb.set_content_margin_all(margin)
	return sb


## Asse di legno: "wood", "wood_hover", "wood_dark", "coral", "sea", "wood_off"…
static func plank(kind := "wood", margin := 12.0) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = tex("res://assets/ui/%s.png" % kind)
	sb.set_texture_margin_all(14)
	sb.content_margin_left = margin + 4
	sb.content_margin_right = margin + 4
	sb.content_margin_top = margin * 0.5
	sb.content_margin_bottom = margin * 0.5
	return sb


static func label(text: String, size := 20, col := INK, font: Font = null) -> Label:
	init_fonts()
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if font != null:
		l.add_theme_font_override("font", font)
	return l


## Titolo in Pirata One (le maiuscole gotiche si leggono male: meglio scrivere in minuscolo).
static func title(text: String, size := 40, col := INK) -> Label:
	init_fonts()
	var l := label(text, size, col, font_title)
	if col.get_luminance() > 0.6:
		l.add_theme_color_override("font_outline_color", Color(0.15, 0.08, 0.03, 0.9))
		l.add_theme_constant_override("outline_size", 8)
	return l


static func icon_rect(t: Texture2D, sz: Vector2) -> TextureRect:
	var r := TextureRect.new()
	r.texture = t
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = sz
	r.size = sz
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func button(text: String, w := 200.0, h := 54.0, size := 24) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, h)
	b.add_theme_font_size_override("font_size", size)
	return b


static func _skin(b: Button, base: String, hover: String) -> Button:
	b.add_theme_stylebox_override("normal", plank(base))
	b.add_theme_stylebox_override("hover", plank(hover))
	b.add_theme_stylebox_override("pressed", plank("wood_dark"))
	return b


## Pulsante principale (corallo).
static func primary(b: Button) -> Button:
	return _skin(b, "coral", "coral_hover")


## Pulsante "mare" (azioni online, conferme secondarie).
static func sea(b: Button) -> Button:
	return _skin(b, "sea", "sea_hover")


## Evidenzia un pulsante (selezione attiva o consiglio dell'IA).
static func selected(b: Button, kind := "sea") -> Button:
	return _skin(b, kind, kind + "_hover")


static func make_theme() -> Theme:
	init_fonts()
	var th := Theme.new()
	th.default_font = font_body
	th.default_font_size = 20
	th.set_stylebox("normal", "Button", plank("wood"))
	th.set_stylebox("hover", "Button", plank("wood_hover"))
	th.set_stylebox("pressed", "Button", plank("wood_dark"))
	th.set_stylebox("disabled", "Button", plank("wood_off"))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", LIGHT)
	th.set_color("font_hover_color", "Button", Color.WHITE)
	th.set_color("font_pressed_color", "Button", Color("#ffd98a"))
	th.set_color("font_disabled_color", "Button", Color("#d8cfc0"))
	th.set_color("font_outline_color", "Button", Color(0.18, 0.09, 0.03, 0.85))
	th.set_constant("outline_size", "Button", 5)
	th.set_font("font", "Button", font_bold)
	th.set_font_size("font_size", "Button", 22)
	th.set_color("font_color", "Label", INK)
	th.set_stylebox("panel", "Panel", paper())
	th.set_stylebox("panel", "PanelContainer", paper())
	th.set_font("normal_font", "RichTextLabel", font_body)
	th.set_font("bold_font", "RichTextLabel", font_bold)
	th.set_font("italics_font", "RichTextLabel", font_italic)
	th.set_font_size("normal_font_size", "RichTextLabel", 20)
	th.set_font_size("bold_font_size", "RichTextLabel", 20)
	th.set_font_size("italics_font_size", "RichTextLabel", 20)
	th.set_color("default_color", "RichTextLabel", INK)
	th.set_font("font", "LineEdit", font_bold)
	th.set_font_size("font_size", "LineEdit", 24)
	th.set_color("font_color", "LineEdit", INK)
	th.set_color("font_placeholder_color", "LineEdit", Color(0.42, 0.29, 0.17, 0.6))
	th.set_color("caret_color", "LineEdit", INK)
	th.set_stylebox("normal", "LineEdit", panel_style(Color("#fbf1dc"), Color("#8a6a45"), 2, 6))
	th.set_stylebox("focus", "LineEdit", panel_style(Color("#fffaf0"), SEA, 3, 6))
	th.set_font("font", "TooltipLabel", font_body)
	th.set_font_size("font_size", "TooltipLabel", 19)
	th.set_color("font_color", "TooltipLabel", INK)
	th.set_stylebox("panel", "TooltipPanel", paper(false, 12))
	th.set_font("font", "CheckBox", font_bold)
	th.set_font_size("font_size", "CheckBox", 22)
	th.set_color("font_color", "CheckBox", INK)
	th.set_color("font_hover_color", "CheckBox", SEA_DARK)
	th.set_color("font_pressed_color", "CheckBox", INK)
	th.set_color("font_hover_pressed_color", "CheckBox", SEA_DARK)
	th.set_stylebox("normal", "CheckBox", StyleBoxEmpty.new())
	th.set_stylebox("hover", "CheckBox", StyleBoxEmpty.new())
	th.set_stylebox("pressed", "CheckBox", StyleBoxEmpty.new())
	th.set_stylebox("hover_pressed", "CheckBox", StyleBoxEmpty.new())
	th.set_stylebox("focus", "CheckBox", StyleBoxEmpty.new())
	var sep := StyleBoxLine.new()
	sep.color = Color(0.42, 0.29, 0.17, 0.45)
	sep.thickness = 2
	th.set_stylebox("separator", "HSeparator", sep)
	return th
