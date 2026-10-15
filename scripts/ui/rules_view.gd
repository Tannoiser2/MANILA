extends Control
## Regole in breve (dal regolamento italiano) e varianti. Si apre dal menu o durante la partita.

var main
var embedded := false
var on_close: Callable


func _ready() -> void:
	size = Vector2(1920, 1080)
	if not embedded:
		var bg := TextureRect.new()
		bg.texture = UI.tex("res://assets/ui/cover.jpg")
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.size = size
		bg.modulate = Color(0.5, 0.6, 0.6)
		add_child(bg)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UI.paper(false, 40))
	box.position = Vector2(120, 40)
	box.custom_minimum_size = Vector2(1680, 1000)
	box.size = Vector2(1680, 1000)
	add_child(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	box.add_child(vb)
	var hb := HBoxContainer.new()
	vb.add_child(hb)
	var t := UI.title("Le regole di Manila", 52)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(t)
	var close := UI.button("Chiudi" if embedded else "Indietro", 180, 52, 24)
	close.pressed.connect(func():
		if embedded:
			on_close.call()
		else:
			main.show_menu())
	hb.add_child(close)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	vb.add_child(cols)
	var left := RichTextLabel.new()
	left.bbcode_enabled = true
	left.custom_minimum_size = Vector2(790, 880)
	left.text = _rules_text()
	cols.add_child(left)
	var right := RichTextLabel.new()
	right.bbcode_enabled = true
	right.custom_minimum_size = Vector2(780, 880)
	right.text = _tables_text()
	cols.add_child(right)


func _rules_text() -> String:
	var g := "[color=#b8431f]"
	var e := "[/color]"
	return """[font_size=34][font=res://assets/fonts/PirataOne-Regular.ttf]%sScopo%s[/font][/font_size]
1821, Filippine: si contrabbandano noce moscata, seta, ginseng e giada verso il mercato nero di MANILA. La partita finisce quando una merce arriva a [b]30[/b] al mercato nero: vince chi ha il [b]patrimonio[/b] maggiore (pesos + valore delle quote − 15 per ogni quota ancora impegnata).

[font_size=34][font=res://assets/fonts/PirataOne-Regular.ttf]%sPreparazione%s[/font][/font_size]
Ognuno ha 30 pesos, 2 quote coperte e 3 complici (4 in tre giocatori). Le merci partono da 0.

[font_size=34][font=res://assets/fonts/PirataOne-Regular.ttf]%sOgni viaggio%s[/font][/font_size]
[b]1. Asta per la capitaneria.[/b] Comincia chi comandava il viaggio prima (al primo viaggio un giocatore sorteggiato); si rilancia o si passa, chi passa è fuori. Si può offrire fino a quanto si ha più i prestiti possibili. Se nessuno offre, il comando resta al capitano precedente.
[b]2. Il capitano del porto[/b] può comprare 1 quota (prezzo = valore al mercato nero, minimo 5), sceglie la merce che resta a terra e mette in acqua i 3 barconi su posizioni da 0 a 5 con [b]somma 9[/b].
[b]3. Complici e navigazione.[/b] Si alternano 3 giri di piazzamento e 3 tiri (in tre giocatori 2 giri di fila prima del primo tiro). Nel giro ognuno, a partire dal capitano, piazza un complice pagando il numero del cerchio, oppure passa (e non ne piazza più in questo viaggio). Il capitano tira i dadi dei colori delle merci: ogni barcone avanza esattamente del suo dado; oltre il 13 attracca ai moli A, B, C in ordine d'arrivo.
• Dopo il [b]2° tiro[/b] i pirati possono [b]abbordare[/b] un barcone fermo sul 13 (prima il capitano dei pirati) occupandone un posto libero.
• Prima del [b]3° tiro[/b] i piloti spostano i barconi ancora in mare: il vice di 1, il capo uno di 2 o due di 1, avanti o indietro.
• Dopo il [b]3° tiro[/b] i barconi sul 13 vengono [b]saccheggiati[/b] (se la nave pirata non è vuota): i complici a bordo tornano a casa, i pirati si dividono il valore e il capitano dei pirati decide se il barcone va al molo o in cantiere. Gli altri barconi non arrivati finiscono nei cantieri A, B, C.
[b]4. Profitti.[/b] I complici sui barconi attraccati si dividono il valore della merce; i moli e i cantieri occupati pagano il cerchio scuro (i cantieri li paga l'assicuratore, se c'è); l'assicuratore incassa 10 subito ma paga le riparazioni di tutti i cantieri occupati.
[b]5. Valori.[/b] Ogni merce arrivata al molo sale di una casella al mercato nero.

[font_size=34][font=res://assets/fonts/PirataOne-Regular.ttf]%sDenaro%s[/font][/font_size]
Quando non bastano i contanti si impegna una quota: 12 pesos subito, 15 da restituire a fine partita. Chi è al verde e non ha quote libere sale gratis su un barcone come [b]clandestino[/b].
""" % [g, e, g, e, g, e, g, e]


func _tables_text() -> String:
	var g := "[color=#b8431f]"
	var e := "[/color]"
	return """[font_size=34][font=res://assets/fonts/PirataOne-Regular.ttf]%sMerci e carichi%s[/font][/font_size]
[table=3]
[cell][b]Merce[/b]   [/cell][cell][b]Valore[/b]   [/cell][cell][b]Posti a bordo[/b][/cell]
[cell]Ginseng[/cell][cell]18[/cell][cell]1 · 2 · 3[/cell]
[cell]Noce moscata[/cell][cell]24[/cell][cell]2 · 3 · 4[/cell]
[cell]Seta[/cell][cell]30[/cell][cell]3 · 4 · 5[/cell]
[cell]Giada[/cell][cell]36[/cell][cell]3 · 4 · 5 · 5[/cell]
[/table]
Mercato nero: 0 → 5 → 10 → 20 → 30.

[font_size=34][font=res://assets/fonts/PirataOne-Regular.ttf]%sCaselle%s[/font][/font_size]
[table=3]
[cell][b]Casella[/b]   [/cell][cell][b]Costo[/b]   [/cell][cell][b]Rende[/b][/cell]
[cell]Molo A / B / C[/cell][cell]4 / 3 / 2[/cell][cell]6 / 8 / 15 se c'è un barcone[/cell]
[cell]Cantiere A / B / C[/cell][cell]4 / 3 / 2[/cell][cell]6 / 8 / 15 se c'è un barcone[/cell]
[cell]Pirati (2 posti)[/cell][cell]5 / 5[/cell][cell]abbordaggio e bottino[/cell]
[cell]Vice pilota[/cell][cell]2[/cell][cell]sposta 1 barcone di 1[/cell]
[cell]Capo pilota[/cell][cell]5[/cell][cell]1 barcone di 2 o 2 di 1[/cell]
[cell]Assicuratore[/cell][cell]riceve 10[/cell][cell]paga le riparazioni[/cell]
[/table]

[font_size=34][font=res://assets/fonts/PirataOne-Regular.ttf]%sVarianti%s[/font][/font_size]
[b]Variante consigliata di BGG (1.3).[/b] Asta a mano chiusa: tutti scelgono in segreto e si rivela insieme (anche 0); a parità vince il primo in senso orario a partire da sinistra del capitano uscente. Il giro di piazzamento dopo il primo tiro si fa in senso antiorario, cominciando sempre dal capitano del porto.
[b]Pirati forti.[/b] Se sui barconi fermi sul 13 non ci sono posti liberi, il pirata può scalzare un complice (rimandandolo al proprietario); i posti liberi vanno occupati prima. Il secondo pirata non può scalzare il capitano appena salito.
[b]Scelte extra per 5 giocatori (BGG).[/b] Nell'ultimo giro di piazzamento i piloti costano 1 e 3. Chi ha già un molo o un cantiere può, invece di piazzare un complice, scommettere 1-3 pesos con il dado avanzato su quella casella: se arriva un barcone vince il doppio. Casella Malattia gratuita: a fine viaggio dà 1 peso. Con le scelte extra valgono anche i pirati forti.

[font_size=34][font=res://assets/fonts/PirataOne-Regular.ttf]%sComandi%s[/font][/font_size]
Trascina per ruotare il porto, rotella o pizzico per lo zoom, tasto destro (o Maiusc+trascina) per spostare la vista; Q/E ruotano di 30°, Home rimette la vista. Clic su un anello luminoso per piazzare un complice. Sopra ogni barcone c'è la probabilità di arrivare e di fermarsi sul 13.
""" % [g, e, g, e, g, e, g, e]
