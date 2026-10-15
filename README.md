# Manila — adattamento digitale (Godot 4)

Versione digitale per uso personale di **Manila** di Franz-Benno Delonge (illustrazioni di Victor Boden,
© Zoch Verlag). Componenti, illustrazioni e regole © dei rispettivi autori: le immagini vengono dal
modulo Tabletop Simulator e non vanno distribuite pubblicamente.

**Gioca nel browser:** https://tannoiser2.github.io/MANILA/

## Avvio
1. Apri Godot 4 (testato su 4.7) → *Importa* → seleziona `project.godot`.
2. Premi **F5**. F11 alterna schermo intero e finestra.

## Cosa c'è
- **Da 3 a 5 contrabbandieri** (Nero, Arancione, Giallo, Blu, Rosso), ognuno Umano o IA. Con più
  umani sullo stesso dispositivo si gioca a turno; le quote di chi gioca si vedono solo quando decide e
  l'asta a mano chiusa passa da una schermata "tocca a…".
- **Grafica "caraibica"**: pergamene dai bordi strappati, assi di legno, mare turchese e corallo, titoli in
  Pirata One e testo in Alegreya Sans; il tabellone è un isolotto di sabbia con le palme in mezzo al mare,
  sotto un cielo tropicale.
- **Porto in 3D**: il tabellone del modulo TTS, i barconi dal modello `Manila_Boat_Correct.stl` con le
  tessere carico, complici col cappello conico, dadi dei colori delle merci, segnalini del mercato nero.
  Trascina col mouse per ruotare, rotella o pizzico per lo zoom, tasto destro (o Maiusc+trascina) per
  spostare; i pulsanti ◀ ▶ + − ruotano e zoomano, Vista alterna la vista dal fondo e quella di lato,
  Dall'alto guarda il tabellone in pianta.
  Le caselle in cui si può piazzare un complice si illuminano: basta un clic.
- **Regole complete** (regolamento italiano 2014): asta per la capitaneria con prestiti, acquisto della
  quota, carico e partenze a somma 9, giri di piazzamento (4 in tre giocatori), abbordaggio dopo il
  2° tiro, piloti prima del 3°, saccheggio e scelta molo/cantiere del capitano dei pirati, naufragi,
  assicuratore che incassa 10 e paga le riparazioni (anche con i prestiti, il resto lo copre la cassa),
  clandestini, quote impegnate (12/15), aumento dei valori e fine a 30.
- **Varianti** (menu → VARIANTI…), combinabili:
  - *Variante consigliata di BGG 1.3*: asta a mano chiusa con spareggio dal capitano uscente, giro di
    piazzamento dopo il primo tiro in senso antiorario a partire dal capitano;
  - *Pirati forti* (regola opzionale del regolamento): all'abbordaggio si scalza un complice;
  - *Scelte extra per 5 giocatori* (BGG): piloti a 1 e 3 nell'ultimo giro, scommessa 1-3 pesos su un
    proprio molo/cantiere, casella Malattia; attiva anche i pirati forti.
- **IA** su tre livelli. Calcola in modo esatto, per ogni barcone e per i tiri che restano, la probabilità
  di arrivare, di fermarsi sul 13 o di naufragare, e valuta ogni mossa come guadagno atteso (carichi,
  moli, cantieri, assicurazione, pirati, aumento delle proprie quote). La capitaneria si valuta per
  quello che rende davvero (miglior carico per sé contro quello che sceglierebbe un avversario, quota
  esclusiva da comprare e spingere, primo complice): i fattori d'offerta sono tarati con centinaia di
  partite IA contro IA. La Difficile considera anche chi potrebbe salire dopo sul barcone e simula
  l'azione dei piloti; vince circa metà delle partite contro tre IA Normali, che a loro volta battono
  nettamente le Facili. Non sbircia le quote coperte degli avversari.
- **Aiuti**: sopra ogni barcone la probabilità di arrivare e di fermarsi sul 13; in verde la mossa
  consigliata dall'IA (si spegne con *Niente consigli dell'IA*); riepilogo a fine viaggio, cronaca,
  diario completo e regole in breve.

## Gioco online
Dal menu, **GIOCA ONLINE** (anche dalla versione web). Usa lo stesso progetto Firebase degli altri giochi
(Realtime Database, piano gratuito), con le stanze sotto `manila/rooms`.

- **Chi crea la stanza** sceglie prima nel menu colori, varianti e livello dell'IA: i colori su UMANO
  diventano i posti per gli amici (il primo è il suo). Scrive il nome, preme *Crea una stanza* e comunica
  il codice di 4 lettere. Quando ci sono tutti preme *Inizia online*: i posti liberi li gioca l'IA.
- **Gli amici** scrivono il nome e il codice e premono *Entra*.
- Ogni decisione (offerta, quota, barconi, complice, abbordaggio, pilota…) è una mossa numerata nel
  database (`acts/0`, `acts/1`, …). Tutti i dispositivi fanno girare lo stesso motore con lo stesso seme
  (anche i dadi) e applicano le stesse mosse, quindi la partita è identica ovunque. I colori IA li gioca
  il dispositivo di chi ha creato la stanza.
- **Se cade la linea** si rientra con lo stesso codice e *Entra*. Se un giocatore tace per un minuto, al
  suo posto gioca l'IA finché non rientra.

**Configurazione Firebase.** Le regole sono in `firebase/database.rules.json`: comprendono quelle di tutti
gli altri giochi (Ultimo chilometro, Snow Tails, STATUS, World Order, Kingsburg, Churchill, Burning Banners,
BEAST, Mage Knight, Endeavor, Endeavor: Deep Sea) più la nuova sezione `manila` e una sezione generica `$game`: qualunque gioco futuro che
salva le stanze in `<nome>/rooms` con lo stesso schema (host, seats, acts…) funziona senza toccare più le regole.
Vanno pubblicate nella console di Firebase (Realtime Database → Regole) sostituendo tutto il testo
(Cmd+A, incolla, Pubblica); senza questo passaggio la creazione della stanza risponde "Permission denied".

**Prove senza Firebase.** `tests/firebase_mock.py` è un finto Firebase locale. Con `MN_DB_URL`,
`MN_AUTH_URL` e `MN_REFRESH_URL` che puntano lì, `tests/online_play.gd` fa giocare una partita intera a
due istanze (`MN_ROLE=host` e `guest`, più due colori IA; con `MN_PHASE=drop` e poi `back` l'ospite esce
a metà e rientra). Alla fine ognuna stampa l'impronta della partita, che deve coincidere.

## Struttura
```
scripts/data/mn_data.gd      merci, caselle, colori, coordinate del tabellone
scripts/core/engine.gd       motore delle regole (deterministico, ogni scelta passa da decide())
scripts/core/ai.gd           IA probabilistica
scripts/ui/board3d.gd        porto 3D, telecamera orbitale, caselle cliccabili
scripts/ui/game_view.gd      interfaccia di gioco
scripts/ui/menu.gd           menu, varianti, stanze online
scripts/net/                 Firebase (REST) e partita online in lockstep
assets/                      tabellone, tessere carico, carte quota, monete, barcone (OBJ dallo STL)
tests/                       sim.gd (IA contro IA), shot.gd (screenshot), online_play.gd + firebase_mock.py
```

## Test
```
godot --headless --path . -s res://tests/sim.gd -- 40 4 - 2,1,1,0          # 40 partite, livelli per posto
godot --headless --path . -s res://tests/sim.gd -- 30 5 bgg,five 1,1,1,1,1  # con le varianti
xvfb-run godot --path . -s res://tests/shot.gd -- game 4                     # screenshot in user://shots
```
