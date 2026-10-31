# ============================================================================
# MusicComposer.gd — TASK 110: motore compositore "arcade fantasy".
#
# PERCHE' QUESTO FILE ESISTE
#   Le vecchie tracce (AudioManager._gen_level_track / _gen_menu_track)
#   non erano composizioni: erano arpeggi automatici sulla scala con un
#   pattern di batteria fisso. Risultato (segnalazione utente): musica
#   "troppo semplice, monotona, breve e ripetitiva", timbro sempre uguale.
#
#   Questo modulo introduce un approccio da compositore/tracker:
#     1. MELODIE COMPOSTE A MANO (frasi M1..M4, B1..B4, riff del boss) come
#        sequenze di note [battito, durata, grado, ottava] — non generate.
#     2. LEITMOTIV: il "Canto del Labirinto" (tema principale) viene
#        presentato nel menu', variato nei 4 livelli (strumento/groove/
#        abbellimenti diversi) e CORROTTO nel tema del boss (stessa
#        intervallistica minore, trasposta + doppio tempo + ottoni).
#        All'ultimo stadio (vittoria) il tema RISOLVE in maggiore.
#     3. BANCO STRUMENTI esteso (oltre a pulse/tri/saw/noise):
#          lead ....... pulse 25% con vibrato 5.5Hz + bus eco
#          lead2 ...... pulse 50% caldo + bus eco
#          brass ...... pulse 50% detunato + ottava, attacco percussivo
#          bell ....... FM (sine + modulatore ratio 3.01), coda lunga + eco
#          harp ....... triangolo con decay veloce
#          strings .... 2 saw detunati, attacco lento (pad corale)
#          sub ........ sinusoidale grave (drone)
#          bass ....... triangolo con "punch"
#          bassP ...... pulse 50% guidato (groove veloce)
#          batteria .. kick pitchato, snare, hi-hat chiuso/aperto, toms,
#                      crash, timpani
#     4. ECHO BUS: lead e campane passano in un delay a 3 ripeti
#        (ottava puntata, feedback decrescente) — il classico "suono grande"
#        del chiptune a costo di un solo canale in piu'.
#     5. STRUTTURA A SEZIONI con dinamiche: intro / A / A' / B / drop /
#        climax / outro, fill di batteria ai confini, crash all'attacco
#        delle sezioni forti, basso che cambia pattern, pad che entra ed
#        esce. Ogni traccia dura 80-160 secondi prima del loop.
#
# ARCHITETTURA DI RENDERING
#   compose_*() costruisce una lista di EVENTI nota/tamburo, poi chiama
#   _render(): per ogni evento viene sintetizzata la nota in un buffer
#   float (tabelle d'onda 2048 campioni -> lookup, niente chiamate di
#   funzione per campione). Il bus eco viene piegato alla fine con 3 tap.
#   Normalizzazione finale a picco 0.88 + soft-clip. Loop senza click
#   (rampa di 5ms in coda, attacco da zero).
#
#   La sintesi gira nel thread in background dell'AudioManager (Task 76):
#   questo oggetto non tocca mai il scene tree. Le tabelle d'onda sono
#   costruite in _init() e poi SOLO LETTE (thread-safe).
#
# TONALITA'/TEMPO DELLE TRACCE
#   Menu' ....... Re minore,  84 BPM, 56 battute (~160s)  — tema completo
#   Livello 1 ... Re minore, 104 BPM, 64 battute (~148s)  "Esplorazione"
#   Livello 2 ... Do min. arm., 116 BPM, 64 battute (~133s) "Inseguimento"
#   Livello 3 ... Si minore,  96 BPM, 64 battute (~160s)  "Profondita'"
#   Livello 4 ... Mi min. arm., 112 BPM, 64 battute (~137s) "Ascesa"
#   Boss ........ Fa min. arm., 148 BPM, 48 battute (~78s) — tema corrotto
#   Portale ..... La minore,  72 BPM, 24 battute (~80s)   — mistico
#   Vittoria .... Re MAGGIORE, 112 BPM, 8 battute (~17s, one-shot): il tema
#                 risolve in maggiore (la "ricompensa" armonica dell'eroe).
#
# SR musicale: 22050 Hz (MUSIC_SR nell'AudioManager): il contenuto
# armonico utile del chiptune sta sotto ~10 kHz, e questo dimezza RAM e
# tempo di sintesi rispetto alle vecchie tracce a 44100.
# ============================================================================
class_name MusicComposer
extends RefCounted

# --- Sample rate usato per le tracce (passato dall'AudioManager) --------------
var sr: int = 22050

# --- Tabelle d'onda (2048 campioni, costruite UNA volta in _init) -------------
const TBL_SIZE: int = 2048
const TBL_MASK: int = 2047
var _t_pulse50: PackedFloat32Array
var _t_pulse25: PackedFloat32Array
var _t_pulse125: PackedFloat32Array
var _t_tri: PackedFloat32Array
var _t_saw: PackedFloat32Array
var _t_sine: PackedFloat32Array

# Generatore deterministico (seed fisso per traccia => output riproducibile,
# necessario per i test di regressione audio).
var _rng := RandomNumberGenerator.new()

# Gradi della scala minore naturale (0..6) + grado 7 = sensibile (min. arm.).
const DEG_NATURAL: PackedInt32Array = [0, 2, 3, 5, 7, 8, 10]
const DEG_HARMONIC: PackedInt32Array = [0, 2, 3, 5, 7, 8, 11]
# Scala maggiore (per il jingle di vittoria).
const DEG_MAJOR: PackedInt32Array = [0, 2, 4, 5, 7, 9, 11]


func _init(sample_rate: int = 22050) -> void:
        sr = sample_rate
        _t_pulse50 = _build_pulse_table(0.5)
        _t_pulse25 = _build_pulse_table(0.25)
        _t_pulse125 = _build_pulse_table(0.125)
        _t_tri = _build_tri_table()
        _t_saw = _build_saw_table()
        _t_sine = _build_sine_table()


# ---------------------------------------------------------------------------
# Costruzione tabelle d'onda
# ---------------------------------------------------------------------------
func _build_pulse_table(duty: float) -> PackedFloat32Array:
        var t := PackedFloat32Array()
        t.resize(TBL_SIZE)
        for i in TBL_SIZE:
                t[i] = 1.0 if float(i) / TBL_SIZE < duty else -1.0
        return t


func _build_tri_table() -> PackedFloat32Array:
        var t := PackedFloat32Array()
        t.resize(TBL_SIZE)
        for i in TBL_SIZE:
                var p: float = float(i) / TBL_SIZE
                t[i] = (4.0 * p - 1.0) if p < 0.5 else (3.0 - 4.0 * p)
        return t


func _build_saw_table() -> PackedFloat32Array:
        var t := PackedFloat32Array()
        t.resize(TBL_SIZE)
        for i in TBL_SIZE:
                t[i] = 2.0 * float(i) / TBL_SIZE - 1.0
        return t


func _build_sine_table() -> PackedFloat32Array:
        var t := PackedFloat32Array()
        t.resize(TBL_SIZE)
        for i in TBL_SIZE:
                t[i] = sin(TAU * float(i) / TBL_SIZE)
        return t


# ---------------------------------------------------------------------------
# API pubblica: una funzione per traccia. Ritornano PackedFloat32Array
# pronti per _samples_to_stream() nell'AudioManager.
# ---------------------------------------------------------------------------

## Tema principale — menu' (Re minore, 84 BPM, 56 battute, loop).
func compose_menu() -> PackedFloat32Array:
        _rng.seed = 110001
        # Accordi (semiToni relativi alla tonica Re):
        var dm := [0, 3, 7]      # i
        var gm := [7, 10, 12]    # iv  (Sol-Sib-Re)
        var bb := [10, 14, 17]   # VI  (Sib-Re-Fa)
        var fmaj := [5, 9, 12]   # III (Fa-La-Do)
        var amaj := [9, 13, 16]  # V   (La-Do#-Mi, minore armonica)
        var cmaj := [10, 14, 17] # VII (Do-Mi-Sol)
        var intro_prog := [bb, gm, dm, amaj]
        var a_prog := [dm, dm, gm, bb, dm, bb, gm, amaj]
        var b_prog := [fmaj, gm, bb, dm, fmaj, gm, cmaj, amaj]
        var q_prog := [bb, dm, gm, amaj]
        var ctx := {
                "root": 146.83,           # Re3
                "tempo": 84.0,
                "scale": DEG_NATURAL,
                "sections": [
                        {"bars": 4,  "chords": intro_prog, "drums": "heart",   "bass": "sub",
                                        "bell": "sparse", "pad": true,  "dyn": 0.55, "name": "intro"},
                        {"bars": 8,  "chords": a_prog, "melody": ["M1", "M2", "M3", "M4"],
                                        "inst": "lead2", "drums": "none", "bass": "half",
                                        "bell": "none", "pad": true,  "dyn": 0.72, "name": "A"},
                        {"bars": 8,  "chords": b_prog, "melody": ["B1", "B2", "B3", "B4"],
                                        "inst": "lead",  "drums": "soft",  "bass": "half",
                                        "bell": "harp",  "pad": true,  "dyn": 0.78, "name": "B"},
                        # Drop: si toglie quasi tutto — respiro prima del climax.
                        {"bars": 4,  "chords": q_prog, "melody": ["M3", "M4"],
                                        "inst": "bell",  "drums": "none",  "bass": "sub",
                                        "bell": "none", "pad": true,  "dyn": 0.42, "name": "drop"},
                        {"bars": 8,  "chords": a_prog, "melody": ["M1", "M2", "M3", "M4"],
                                        "inst": "lead2", "drums": "pop",   "bass": "walk",
                                        "bell": "eighth", "pad": true,  "dyn": 0.9,  "name": "A3"},
                        # Climax: tema armonizzato (terza sotto) con ottoni + campane 16esimi.
                        {"bars": 12, "chords": [dm, bb, gm, dm, fmaj, gm, bb, amaj, dm,
                                        bb, gm, amaj],
                                        "melody": ["M1", "M2", "M3", "M4", "M1", "M2"],
                                        "inst": "brass", "harm": true, "drums": "full",
                                        "bass": "walk", "bell": "sixteenth", "pad": true,
                                        "dyn": 1.0, "name": "climax"},
                        {"bars": 4,  "chords": [bb, gm, dm, dm], "melody": ["M4"],
                                        "inst": "lead2", "drums": "heart", "bass": "sub",
                                        "bell": "sparse", "pad": true, "dyn": 0.5, "name": "outro"},
                ],
        }
        return _render_song(ctx)


## Temi dei livelli 0..3 — variazioni del tema principale.
func compose_level(level_idx: int) -> PackedFloat32Array:
        match level_idx:
                0: return _compose_level1()
                1: return _compose_level2()
                2: return _compose_level3()
                3: return _compose_level4()
                _: return _compose_level1()


# --- Livello 1 "Esplorazione": Re minore, 104 BPM ---------------------------
func _compose_level1() -> PackedFloat32Array:
        _rng.seed = 110010
        var dm := [0, 3, 7]
        var gm := [7, 10, 12]
        var bb := [10, 14, 17]
        var amaj := [9, 13, 16]
        var ctx := {
                "root": 146.83, "tempo": 104.0, "scale": DEG_NATURAL,
                "sections": [
                        {"bars": 2,  "chords": [dm, amaj], "melody": [],
                                        "inst": "lead2", "drums": "none", "bass": "sub",
                                        "bell": "sparse", "pad": true, "dyn": 0.5, "name": "intro"},
                        {"bars": 8,  "chords": [dm, dm, gm, bb, dm, bb, gm, amaj],
                                        "melody": ["M1", "M2", "M3", "M4"], "inst": "lead2",
                                        "drums": "adventure", "bass": "walk", "bell": "eighth",
                                        "pad": false, "dyn": 0.85, "name": "A"},
                        {"bars": 8,  "chords": [dm, bb, gm, dm, bb, gm, dm, amaj],
                                        "melody": ["M2", "M1", "M4", "M3"], "inst": "lead2",
                                        "drums": "adventure", "bass": "walk", "bell": "eighth",
                                        "pad": false, "dyn": 0.85, "name": "A2"},
                        {"bars": 8,  "chords": [bb, gm, dm, amaj, bb, gm, dm, amaj],
                                        "melody": ["B1", "B2", "B3", "B4"], "inst": "lead",
                                        "drums": "soft", "bass": "half", "bell": "harp",
                                        "pad": true, "dyn": 0.75, "name": "B"},
                        {"bars": 4,  "chords": [dm, gm, bb, amaj], "melody": ["M3", "M4"],
                                        "inst": "bell", "drums": "none", "bass": "sub",
                                        "bell": "none", "pad": true, "dyn": 0.4, "name": "drop"},
                        {"bars": 8,  "chords": [dm, dm, gm, bb, dm, bb, gm, amaj],
                                        "melody": ["M1", "M2", "M3", "M4"], "inst": "lead2",
                                        "drums": "adventure", "bass": "walk", "bell": "eighth",
                                        "pad": true, "dyn": 0.92, "name": "A3"},
                        {"bars": 12, "chords": [dm, bb, gm, dm, bb, gm, dm, amaj, dm,
                                        bb, gm, amaj],
                                        "melody": ["M1", "M2", "M3", "M4", "M1", "M2"],
                                        "inst": "brass", "harm": true, "drums": "full",
                                        "bass": "drive", "bell": "sixteenth", "pad": true,
                                        "dyn": 1.0, "name": "climax"},
                        {"bars": 6,  "chords": [bb, gm, dm, amaj, dm, dm],
                                        "melody": ["B3", "B4", "M4"], "inst": "lead2",
                                        "drums": "adventure", "bass": "walk", "bell": "eighth",
                                        "pad": true, "dyn": 0.8, "name": "outro"},
                ],
        }
        return _render_song(ctx)


# --- Livello 2 "Inseguimento": Do min. armonica, 116 BPM --------------------
# Staccato: le durate delle note del tema vengono dimezzate (tema "ansimante")
# e gli attacchi sono percussivi — la stessa melodia sembra un'altra.
func _compose_level2() -> PackedFloat32Array:
        _rng.seed = 110020
        var cm := [0, 3, 7]       # i
        var fm := [5, 8, 12]      # iv
        var gmin := [7, 10, 12]   # v minore
        var ab := [8, 12, 15]     # VI
        var gmaj := [7, 11, 14]   # V maggiore (min. armonica)
        var ebdim := [4, 7, 10]   # ii°
        var ctx := {
                "root": 130.81, "tempo": 116.0, "scale": DEG_HARMONIC,
                "staccato": 0.5,
                "sections": [
                        {"bars": 2,  "chords": [cm, gmin], "melody": [],
                                        "inst": "brass", "drums": "chase", "bass": "drive",
                                        "bell": "none", "pad": false, "dyn": 0.6, "name": "intro"},
                        {"bars": 8,  "chords": [cm, cm, fm, ab, cm, ab, gmin, gmaj],
                                        "melody": ["M1", "M2", "M3", "M4"], "inst": "brass",
                                        "drums": "chase", "bass": "drive", "bell": "eighth",
                                        "pad": false, "dyn": 0.9, "name": "A"},
                        {"bars": 8,  "chords": [cm, ab, gmin, cm, fm, gmin, ab, gmaj],
                                        "melody": ["M2", "M4", "M1", "M3"], "inst": "brass",
                                        "drums": "chase", "bass": "drive", "bell": "eighth",
                                        "pad": false, "dyn": 0.9, "name": "A2"},
                        # Contrasto lirico: il tema rallenta e va al lead (respiro).
                        {"bars": 8,  "chords": [ab, fm, cm, gmin, ab, ebdim, fm, gmaj],
                                        "melody": ["B1", "B2", "B3", "B4"], "inst": "lead",
                                        "drums": "soft", "bass": "half", "bell": "harp",
                                        "pad": true, "dyn": 0.72, "name": "B"},
                        {"bars": 4,  "chords": [cm, fm, ab, gmin], "melody": ["M3", "M4"],
                                        "inst": "bell", "drums": "none", "bass": "sub",
                                        "bell": "none", "pad": true, "dyn": 0.4, "name": "drop"},
                        {"bars": 8,  "chords": [cm, cm, fm, ab, cm, ab, gmin, gmaj],
                                        "melody": ["M1", "M2", "M3", "M4"], "inst": "brass",
                                        "drums": "chase", "bass": "drive", "bell": "sixteenth",
                                        "pad": false, "dyn": 0.95, "name": "A3"},
                        {"bars": 12, "chords": [cm, ab, fm, cm, ab, gmin, cm, gmaj, cm,
                                        ab, gmin, gmaj],
                                        "melody": ["M1", "M2", "M3", "M4", "M1", "M2"],
                                        "inst": "brass", "harm": true, "drums": "full",
                                        "bass": "drive", "bell": "sixteenth", "pad": true,
                                        "dyn": 1.0, "name": "climax"},
                        {"bars": 6,  "chords": [ab, gmin, cm, gmaj, cm, cm],
                                        "melody": ["B3", "B4", "M4"], "inst": "brass",
                                        "drums": "chase", "bass": "drive", "bell": "eighth",
                                        "pad": false, "dyn": 0.85, "name": "outro"},
                ],
        }
        return _render_song(ctx)


# --- Livello 3 "Profondita'": Si minore, 96 BPM, half-time ------------------
# Tema AUMENTATO (durate x2) alle campane su tappeto d'archi: lento, cupo.
func _compose_level3() -> PackedFloat32Array:
        _rng.seed = 110030
        var bm := [0, 3, 7]
        var em := [5, 8, 12]
        var fsm := [7, 10, 12]
        var gmaj := [7, 11, 14]
        var d := [10, 14, 17]
        var ctx := {
                "root": 123.47, "tempo": 96.0, "scale": DEG_NATURAL,
                "augment": 2.0,
                "sections": [
                        {"bars": 2,  "chords": [bm, fsm], "melody": [],
                                        "inst": "bell", "drums": "none", "bass": "sub",
                                        "bell": "sparse", "pad": true, "dyn": 0.45, "name": "intro"},
                        {"bars": 8,  "chords": [bm, bm, em, d, bm, d, em, fsm],
                                        "melody": ["M1", "M2", "M3", "M4"], "inst": "bell",
                                        "drums": "doom", "bass": "doom", "bell": "none",
                                        "pad": true, "dyn": 0.75, "name": "A"},
                        {"bars": 8,  "chords": [bm, d, em, bm, d, em, bm, fsm],
                                        "melody": ["M2", "M1", "M4", "M3"], "inst": "bell",
                                        "drums": "doom", "bass": "doom", "bell": "none",
                                        "pad": true, "dyn": 0.75, "name": "A2"},
                        {"bars": 8,  "chords": [d, em, bm, fsm, d, em, gmaj, fsm],
                                        "melody": ["B1", "B2", "B3", "B4"], "inst": "lead2",
                                        "drums": "doom", "bass": "half", "bell": "harp",
                                        "pad": true, "dyn": 0.7, "name": "B"},
                        {"bars": 4,  "chords": [bm, em, d, fsm], "melody": ["M3", "M4"],
                                        "inst": "bell", "drums": "none", "bass": "sub",
                                        "bell": "none", "pad": true, "dyn": 0.35, "name": "drop"},
                        {"bars": 8,  "chords": [bm, bm, em, d, bm, d, em, fsm],
                                        "melody": ["M1", "M2", "M3", "M4"], "inst": "bell",
                                        "drums": "doom", "bass": "doom", "bell": "eighth",
                                        "pad": true, "dyn": 0.85, "name": "A3"},
                        {"bars": 12, "chords": [bm, d, em, bm, d, em, bm, fsm, bm, d,
                                        em, gmaj],
                                        "melody": ["M1", "M2", "M3", "M4", "M1", "M2"],
                                        "inst": "lead2", "harm": true, "drums": "full",
                                        "bass": "doom", "bell": "sixteenth", "pad": true,
                                        "dyn": 1.0, "name": "climax"},
                        {"bars": 6,  "chords": [d, em, bm, fsm, bm, bm],
                                        "melody": ["B3", "B4", "M4"], "inst": "bell",
                                        "drums": "doom", "bass": "doom", "bell": "none",
                                        "pad": true, "dyn": 0.7, "name": "outro"},
                ],
        }
        return _render_song(ctx)


# --- Livello 4 "Ascesa": Mi min. armonica, 112 BPM, marcia ------------------
func _compose_level4() -> PackedFloat32Array:
        _rng.seed = 110040
        var em := [0, 3, 7]
        var am := [5, 8, 12]
        var bm := [7, 10, 12]
        var cmaj := [8, 12, 15]
        var dmaj := [7, 11, 14]
        var ctx := {
                "root": 82.41, "tempo": 112.0, "scale": DEG_HARMONIC,
                "sections": [
                        {"bars": 2,  "chords": [em, dmaj], "melody": [],
                                        "inst": "brass", "drums": "march", "bass": "march",
                                        "bell": "none", "pad": true, "dyn": 0.55, "name": "intro"},
                        {"bars": 8,  "chords": [em, em, am, bm, em, cmaj, bm, dmaj],
                                        "melody": ["M1", "M2", "M3", "M4"], "inst": "brass",
                                        "harm": true, "drums": "march", "bass": "march",
                                        "bell": "eighth", "pad": false, "dyn": 0.9, "name": "A"},
                        {"bars": 8,  "chords": [em, cmaj, bm, em, am, bm, cmaj, dmaj],
                                        "melody": ["M2", "M1", "M4", "M3"], "inst": "brass",
                                        "harm": true, "drums": "march", "bass": "march",
                                        "bell": "eighth", "pad": false, "dyn": 0.9, "name": "A2"},
                        {"bars": 8,  "chords": [cmaj, am, em, bm, cmaj, am, bm, dmaj],
                                        "melody": ["B1", "B2", "B3", "B4"], "inst": "lead",
                                        "drums": "march", "bass": "half", "bell": "harp",
                                        "pad": true, "dyn": 0.75, "name": "B"},
                        {"bars": 4,  "chords": [em, am, bm, dmaj], "melody": ["M3", "M4"],
                                        "inst": "bell", "drums": "none", "bass": "sub",
                                        "bell": "none", "pad": true, "dyn": 0.4, "name": "drop"},
                        {"bars": 8,  "chords": [em, em, am, bm, em, cmaj, bm, dmaj],
                                        "melody": ["M1", "M2", "M3", "M4"], "inst": "brass",
                                        "harm": true, "drums": "march", "bass": "march",
                                        "bell": "sixteenth", "pad": true, "dyn": 0.95, "name": "A3"},
                        {"bars": 12, "chords": [em, cmaj, bm, em, am, bm, em, dmaj, em,
                                        cmaj, bm, dmaj],
                                        "melody": ["M1", "M2", "M3", "M4", "M1", "M2"],
                                        "inst": "brass", "harm": true, "drums": "full",
                                        "bass": "drive", "bell": "sixteenth", "pad": true,
                                        "dyn": 1.0, "name": "climax"},
                        {"bars": 6,  "chords": [cmaj, bm, em, dmaj, em, em],
                                        "melody": ["B3", "B4", "M4"], "inst": "brass",
                                        "harm": true, "drums": "march", "bass": "march",
                                        "bell": "eighth", "pad": true, "dyn": 0.85, "name": "outro"},
                ],
        }
        return _render_song(ctx)


## Tema del BOSS (Fa min. armonica, 148 BPM, 48 battute): il tema principale
## "corrotto" — stessa intervallistica trasposta, doppio tempo, galoppo,
## sensibile armonica martellata. Allarme in apertura, half-time minaccioso
## nel centro, climax col tema dell'eroe (in Fa minore) travolto dagli ottoni.
func compose_boss() -> PackedFloat32Array:
        _rng.seed = 110050
        var fm := [0, 3, 7]        # i
        var dbm := [8, 12, 15]     # VI  (Reb min... Reb-Fa-Lab)
        var cm := [5, 8, 12]       # iv
        var eb := [7, 10, 14]      # v minore
        var emaj := [7, 11, 14]    # V maggiore (sensibile Mi)
        var bdim := [2, 5, 8]      # ii°
        var ctx := {
                "root": 87.31, "tempo": 148.0, "scale": DEG_HARMONIC,
                "sections": [
                        # Allarme: sirena + rullo di timpani + riser.
                        {"bars": 2,  "chords": [fm, emaj], "melody": ["ALARM"],
                                        "inst": "lead", "drums": "roll", "bass": "drone",
                                        "bell": "none", "pad": true, "dyn": 0.85, "name": "alarm"},
                        # Riff principale (galoppo).
                        {"bars": 8,  "chords": [fm, fm, dbm, eb, fm, fm, dbm, emaj],
                                        "melody": ["R1", "R2", "R1", "R2"], "inst": "brass",
                                        "drums": "gallop", "bass": "gallop", "bell": "tritone",
                                        "pad": false, "dyn": 0.95, "name": "riffA"},
                        {"bars": 8,  "chords": [fm, dbm, eb, fm, cm, dbm, bdim, emaj],
                                        "melody": ["R2", "R1", "R2", "R1"], "inst": "brass",
                                        "drums": "gallop", "bass": "gallop", "bell": "tritone",
                                        "pad": false, "dyn": 0.95, "name": "riffA2"},
                        # Salita cromatica (pressione).
                        {"bars": 8,  "chords": [fm, fm, dbm, dbm, eb, eb, emaj, emaj],
                                        "melody": ["CHROM", "CHROM", "R2", "R1"], "inst": "brass",
                                        "drums": "gallop", "bass": "gallop", "bell": "tritone",
                                        "pad": true, "dyn": 1.0, "name": "chrom"},
                        # Half-time minaccioso: il tema rallenta e torce.
                        {"bars": 8,  "chords": [dbm, fm, dbm, cm, eb, fm, bdim, emaj],
                                        "melody": ["R2", "R1"], "inst": "lead2",
                                        "drums": "halftime", "bass": "doom", "bell": "sparse",
                                        "pad": true, "dyn": 0.7, "name": "menace"},
                        # Riser: 2 battute di build (solo rumore che sale + tom).
                        {"bars": 2,  "chords": [emaj, emaj], "melody": [],
                                        "inst": "lead", "drums": "roll", "bass": "drone",
                                        "bell": "none", "pad": true, "dyn": 0.9, "riser": true,
                                        "name": "riser"},
                        # CLIMAX: il tema dell'eroe in Fa minore, doppio tempo, corrotto.
                        {"bars": 12, "chords": [fm, dbm, eb, fm, cm, dbm, eb, emaj, fm,
                                        dbm, eb, emaj],
                                        "melody": ["M1", "M2", "M3", "M4", "M1", "M2"],
                                        "inst": "brass", "harm": true, "drums": "full",
                                        "bass": "gallop", "bell": "tritone", "pad": true,
                                        "dyn": 1.0, "name": "climax"},
                ],
        }
        return _render_song(ctx)


## Tema del portale magico (La minore, 72 BPM, 24 battute): campane che
## risalgono due ottave su drone, heartbeat lontano, shimmer.
func compose_portal() -> PackedFloat32Array:
        _rng.seed = 110060
        var am := [0, 3, 7]
        var fm := [5, 8, 12]
        var cmaj := [10, 14, 17]  # Do magg. sopra La? La-Do-Mi = am; usiamo III
        var gm := [7, 10, 14]     # v (Mi-Sol-Si → semis 7,10,11)? Sol sopra La:
        # La minore: III = Do magg [3,7,10], v = Mi min. [7,10,14]→ errato.
        # Semis corretti relativi a La: Do=3, Mi=7, Sol=10, Re=5, Fa=8.
        var c3 := [3, 7, 10]      # III (Do-Mi-Sol)
        var em := [7, 11, 14]     # v magg. armonica (Mi-Sol#-Si): 7,11,14
        var dm := [5, 8, 12]      # iv (Re-Fa-La)
        var ctx := {
                "root": 110.0, "tempo": 72.0, "scale": DEG_NATURAL,
                "sections": [
                        {"bars": 4,  "chords": [am, c3, dm, em], "melody": ["P1"],
                                        "inst": "bell", "drums": "heart", "bass": "sub",
                                        "bell": "sparse", "pad": true, "dyn": 0.5, "name": "intro"},
                        {"bars": 8,  "chords": [am, c3, dm, am, em, am, dm, em],
                                        "melody": ["P1", "P2", "P1", "P3"], "inst": "bell",
                                        "drums": "heart", "bass": "sub", "bell": "eighth",
                                        "pad": true, "dyn": 0.7, "name": "A"},
                        {"bars": 8,  "chords": [dm, am, c3, em, dm, am, em, em],
                                        "melody": ["P2", "P3", "P1", "P2"], "inst": "bell",
                                        "drums": "none", "bass": "sub", "bell": "eighth",
                                        "pad": true, "dyn": 0.62, "name": "B"},
                        {"bars": 4,  "chords": [am, dm, em, am], "melody": ["P3"],
                                        "inst": "bell", "drums": "heart", "bass": "sub",
                                        "bell": "sparse", "pad": true, "dyn": 0.48, "name": "outro"},
                ],
        }
        return _render_song(ctx)


## Jingle di VITTORIA (Re MAGGIORE, 112 BPM, 8 battute, one-shot ~17s):
## il tema dell'eroe risolve in maggiore — la "coda" armonica del gioco.
func compose_victory() -> PackedFloat32Array:
        _rng.seed = 110070
        var d := [0, 4, 7]        # I
        var g := [5, 9, 12]       # IV
        var a := [7, 11, 14]      # V
        var bm := [9, 12, 16]     # vi
        var ctx := {
                "root": 146.83, "tempo": 112.0, "scale": DEG_MAJOR, "major": true,
                "sections": [
                        # Fanfara d'attacco (2 battute): rullo + pickup.
                        {"bars": 2,  "chords": [g, a], "melody": ["V0"], "inst": "brass",
                                        "drums": "roll", "bass": "sub", "bell": "sparse",
                                        "pad": true, "dyn": 0.8, "name": "fanfara"},
                        # Tema in maggiore (4 battute).
                        {"bars": 4,  "chords": [d, g, a, d], "melody": ["M1", "M2"],
                                        "inst": "brass", "harm": true, "drums": "full",
                                        "bass": "walk", "bell": "sixteenth", "pad": true,
                                        "dyn": 1.0, "name": "tema"},
                        # Accordo finale tenuto (2 battute).
                        {"bars": 2,  "chords": [d, d], "melody": ["VEND"], "inst": "lead2",
                                        "drums": "heart", "bass": "sub", "bell": "sparse",
                                        "pad": true, "dyn": 0.75, "name": "finale"},
                ],
        }
        return _render_song(ctx)


# ---------------------------------------------------------------------------
# FRASI MUSICALI (composte a mano)
#   [battito_di_inizio, durata_in_battiti, grado, ottava]
#   grado: 0..6 = scala minore naturale (0=tonica .. 6=b7);
#          7 = sensibile (minore armonica); in maggiore 0..6 della maggiore.
#   ottava: 0 = tonica di riferimento (root), 1 = +12 semitoni.
# ---------------------------------------------------------------------------

# Tema principale "Il Canto del Labirinto" (4 frasi da 2 battute).
const PHRASES := {
        "M1": [
                [0.0, 1.0, 0, 2], [1.0, 0.5, 1, 2], [1.5, 0.5, 2, 2], [2.0, 1.0, 3, 2],
                [3.0, 1.0, 4, 2], [4.0, 1.0, 5, 2], [5.0, 1.0, 4, 2],
                [6.0, 1.5, 3, 2], [7.5, 0.5, 2, 2],
        ],
        "M2": [
                [0.0, 0.5, 1, 2], [0.5, 0.5, 2, 2], [1.0, 1.0, 3, 2], [2.0, 1.0, 4, 2],
                [3.0, 1.0, 7, 2], [4.0, 1.5, 4, 2], [5.5, 0.5, 3, 2], [6.0, 1.0, 2, 2],
                [7.0, 1.0, 1, 2],
        ],
        "M3": [
                [0.0, 1.5, 2, 2], [1.5, 0.5, 3, 2], [2.0, 1.0, 4, 2], [3.0, 1.0, 5, 2],
                [4.0, 1.0, 4, 2], [5.0, 1.0, 3, 2], [6.0, 2.0, 0, 2],
        ],
        "M4": [
                [0.0, 0.5, 6, 1], [0.5, 0.5, 0, 2], [1.0, 1.0, 1, 2], [2.0, 1.0, 3, 2],
                [3.0, 1.0, 4, 2], [4.0, 1.0, 2, 2], [5.0, 1.0, 4, 2], [6.0, 2.0, 1, 2],
        ],
        # Ponte lirico (4 frasi da 2 battute).
        "B1": [
                [0.0, 1.5, 2, 2], [1.5, 0.5, 1, 2], [2.0, 1.0, 0, 2], [3.0, 1.0, 6, 1],
                [4.0, 1.5, 3, 2], [5.5, 0.5, 2, 2], [6.0, 2.0, 4, 2],
        ],
        "B2": [
                [0.0, 1.0, 4, 2], [1.0, 0.5, 3, 2], [1.5, 0.5, 2, 2], [2.0, 1.0, 3, 2],
                [3.0, 1.0, 4, 2], [4.0, 2.0, 5, 2], [6.0, 2.0, 0, 2],
        ],
        "B3": [
                [0.0, 1.5, 5, 2], [1.5, 0.5, 4, 2], [2.0, 1.0, 3, 2], [3.0, 1.0, 2, 2],
                [4.0, 1.5, 1, 2], [5.5, 0.5, 0, 2], [6.0, 2.0, 1, 2],
        ],
        "B4": [
                [0.0, 1.0, 3, 2], [1.0, 1.0, 2, 2], [2.0, 1.0, 1, 2], [3.0, 1.0, 7, 1],
                [4.0, 3.0, 0, 2], [7.0, 1.0, 7, 1],
        ],
        # Frasi del BOSS.
        "R1": [
                [0.0, 0.5, 0, 2], [0.5, 0.5, 2, 2], [1.0, 0.5, 1, 2],
                [1.5, 0.5, 0, 2], [2.0, 1.0, 5, 2], [3.0, 1.0, 4, 2],
                [4.0, 0.5, 0, 2], [4.5, 0.5, 1, 2], [5.0, 0.5, 2, 2],
                [5.5, 0.5, 3, 2], [6.0, 1.0, 4, 2], [7.0, 1.0, 7, 2],
        ],
        "R2": [
                [0.0, 0.5, 4, 2], [0.5, 0.5, 3, 2], [1.0, 0.5, 2, 2],
                [1.5, 0.5, 1, 2], [2.0, 1.0, 2, 2], [3.0, 1.0, 0, 2],
                [4.0, 0.5, 5, 2], [4.5, 0.5, 4, 2], [5.0, 0.5, 3, 2],
                [5.5, 0.5, 2, 2], [6.0, 2.0, 0, 2],
        ],
        # Salita cromatica (4 battute, semitoni espliciti relativi alla tonica:
        # La scala non basta per i passaggi cromatici).
        "CHROM": [
                [0.0, 0.5, -1, 24], [0.5, 0.5, -1, 25], [1.0, 0.5, -1, 26],
                [1.5, 0.5, -1, 27], [2.0, 0.5, -1, 29], [2.5, 0.5, -1, 30],
                [3.0, 0.5, -1, 31], [3.5, 0.5, -1, 32],
                [4.0, 1.0, -1, 35], [5.0, 1.0, -1, 31], [6.0, 2.0, -1, 24],
        ],
        # Allarme d'apertura del boss (2 battute): sirena che sale e scende.
        "ALARM": [
                [0.0, 2.0, -1, 24], [2.0, 2.0, -1, 27], [4.0, 1.0, -1, 24],
                [5.0, 1.0, -1, 30], [6.0, 2.0, -1, 31],
        ],
        # Frasi del portale (4 battute lente, gradi).
        "P1": [
                [0.0, 2.0, 0, 2], [2.0, 1.0, 2, 2], [3.0, 1.0, 4, 2],
                [4.0, 2.0, 7, 2], [6.0, 2.0, 4, 2],
        ],
        "P2": [
                [0.0, 1.5, 4, 2], [1.5, 0.5, 2, 2], [2.0, 1.0, 0, 2],
                [3.0, 1.0, 2, 2], [4.0, 2.0, 5, 2], [6.0, 2.0, 2, 2],
        ],
        "P3": [
                [0.0, 2.0, 2, 2], [2.0, 2.0, 4, 2], [4.0, 2.0, 5, 2],
                [6.0, 2.0, 4, 2],
        ],
        # Vittoria: pickup di fanfara (2 battute) e nota finale.
        "V0": [
                [0.0, 0.5, 4, 1], [0.5, 0.5, 5, 1], [1.0, 0.5, 6, 1],
                [1.5, 0.5, 0, 2], [2.0, 1.0, 2, 2], [3.0, 1.0, 4, 2],
                [4.0, 2.0, 5, 2], [6.0, 2.0, 7, 2],
        ],
        "VEND": [
                [0.0, 4.0, 0, 2], [4.0, 4.0, 4, 2],
        ],
}


# ---------------------------------------------------------------------------
# Motore di rendering
# ---------------------------------------------------------------------------

func _render_song(ctx: Dictionary) -> PackedFloat32Array:
        var tempo: float = ctx.get("tempo", 100.0)
        var root: float = ctx.get("root", 146.83)
        var scale: PackedInt32Array = ctx.get("scale", DEG_NATURAL)
        var sections: Array = ctx["sections"]
        var major: bool = ctx.get("major", false)

        var beat_dur: float = 60.0 / tempo
        var spb: int = int(sr * beat_dur)              # campioni per battito
        var steps_per_bar: int = 16                    # sedicesimi per battuta
        var sp_step: int = spb / 4                     # campioni per sedicesimo
        var total_bars: int = 0
        for sec in sections:
                total_bars += int(sec["bars"])
        var total_samples: int = total_bars * 4 * spb

        var master := PackedFloat32Array()
        master.resize(total_samples)
        var echo := PackedFloat32Array()
        echo.resize(total_samples)

        var bar_idx: int = 0
        for sec in sections:
                var bars: int = int(sec["bars"])
                var chords: Array = sec["chords"]
                var dyn: float = sec.get("dyn", 0.8)
                var is_last_section: bool = bar_idx + bars >= total_bars
                # Crash all'inizio delle sezioni forti (dinamica >= 0.9).
                if dyn >= 0.9:
                        _render_drum(master, "crash", 0, spb, dyn, bar_idx * 4 * spb)
                for b in bars:
                        var bar_start: int = (bar_idx + b) * 4 * spb
                        var chord: Array = chords[b % chords.size()]
                        var bar_in_sec: int = b
                        var is_fill_bar: bool = bar_in_sec == bars - 1 \
                                        and not is_last_section and dyn >= 0.55
                        _render_bar(master, echo, ctx, sec, chord, bar_start, spb, sp_step,
                                        dyn, scale, root, major, is_fill_bar, bar_idx + b)
                bar_idx += bars

        # --- Bus eco: lead e campane (fold + 3 tap in ottava puntata) -----------
        var d_samp: int = int(float(spb) * 0.75)  # ottava puntata
        for i in total_samples:
                master[i] += echo[i]
        var taps: Array[float] = [0.34, 0.16, 0.08]
        for tap_i in taps.size():
                var off: int = d_samp * (tap_i + 1)
                var g: float = taps[tap_i]
                for i in total_samples - off:
                        master[i + off] += echo[i] * g

        # --- Riser di sezione (se richiesto) ------------------------------------
        # (gestito dentro _render_bar per il boss; qui solo il master finale)

        # --- Normalizzazione + soft clip + chiusura loop senza click ------------
        var peak: float = 0.001
        for i in total_samples:
                var a: float = absf(master[i])
                if a > peak:
                        peak = a
        var gain: float = 0.88 / peak
        var out := PackedFloat32Array()
        out.resize(total_samples)
        for i in total_samples:
                var v: float = master[i] * gain
                if v > 1.0:
                        v = 1.0
                elif v < -1.0:
                        v = -1.0
                out[i] = v
        # Ramp finale di 5 ms: il loop riparte da attacco a zero.
        var fade_n: int = mini(int(sr * 0.005), total_samples)
        for i in fade_n:
                var k: float = 1.0 - float(i) / float(fade_n)
                out[total_samples - 1 - i] *= k
        # Ramp iniziale di 5 ms (simmetrico): le sezioni forti possono partire
        # con un impatto pieno al campione 0 (crash/stab); senza ramp il
        # loop-wrap (coda a ~0 -> picco pieno) produrrebbe un click a ogni giro.
        for i in fade_n:
                out[i] *= float(i) / float(fade_n)
        return out


# Rendering di UNA battuta: melodia (se tocca), basso, batteria, campane, pad.
func _render_bar(master: PackedFloat32Array, echo: PackedFloat32Array,
                ctx: Dictionary, sec: Dictionary, chord: Array, bar_start: int,
                spb: int, sp_step: int, dyn: float, scale: PackedInt32Array,
                root: float, major: bool, is_fill_bar: bool, abs_bar: int) -> void:
        var root_hz: float = ctx.get("root", 146.83)
        var staccato: float = ctx.get("staccato", 0.0)
        var augment: float = ctx.get("augment", 0.0)
        var melody: Array = sec.get("melody", [])
        var inst: String = sec.get("inst", "lead2")
        var harm: bool = sec.get("harm", false)
        var bass_mode: String = sec.get("bass", "half")
        var drums: String = sec.get("drums", "none")
        var bell_mode: String = sec.get("bell", "none")
        var has_pad: bool = sec.get("pad", false)
        var riser: bool = sec.get("riser", false)

        # --- Melodia: le frasi coprono 2 battute; si affiancano nella sezione ----
        if not melody.is_empty():
                var phrase_len_beats: float = 8.0
                var phrase_names: Array = melody.duplicate()
                var beats_in_sec: int = int(sec["bars"]) * 4
                var beat_offset: int = 0
                while beat_offset < beats_in_sec:
                        var name_i: int = (beat_offset / 8) % phrase_names.size()
                        var phrase: Array = PHRASES.get(phrase_names[name_i], [])
                        for note in phrase:
                                var nb: float = float(note[0])
                                var nd: float = float(note[1])
                                if augment > 0.0:
                                        nb *= augment
                                        nd *= augment
                                var global_beat: float = float(beat_offset) + nb
                                if global_beat >= float(beats_in_sec):
                                        continue
                                var freq: float = _note_freq(note, scale, root_hz, major)
                                var dur_b: float = nd * (1.0 - staccato) if staccato > 0.0 \
                                                else nd
                                var start_s: int = bar_start + int(global_beat * float(spb))
                                var len_s: int = int(dur_b * float(spb)) - int(sp_step * 0.15)
                                if len_s <= 0:
                                        len_s = sp_step
                                _render_note(echo, inst, freq, start_s, len_s, 0.34 * dyn)
                                # Armonizzazione: terza sotto (grado -2 ≈ -3/-4 semitoni).
                                if harm:
                                        var h_freq: float = freq * pow(2.0, -3.0 / 12.0) \
                                                        if major else freq * pow(2.0, -3.0 / 12.0)
                                        _render_note(echo, inst, h_freq, start_s, len_s,
                                                        0.18 * dyn)
                        beat_offset += 8

        # --- Riser di sezione (noise sweep che sale per tutta la battuta) --------
        if riser:
                _render_riser(master, bar_start, spb * 4, 0.25 * dyn)

        # --- Bass ----------------------------------------------------------------
        match bass_mode:
                "sub":
                        _render_note(master, "sub", _cf(root_hz, chord[0]) * 0.5,
                                        bar_start, spb * 4 - sp_step, 0.30 * dyn)
                "half":
                        _render_note(master, "bass", _cf(root_hz, chord[0]) * 0.5,
                                        bar_start, spb * 2 - sp_step, 0.34 * dyn)
                        _render_note(master, "bass", _cf(root_hz, chord[0]) * 0.5,
                                        bar_start + spb * 2, spb * 2 - sp_step, 0.34 * dyn)
                "walk":
                        _render_bass_walk(master, chord, bar_start, spb, sp_step, dyn,
                                        root_hz)
                "doom":
                        _render_note(master, "bass", _cf(root_hz, chord[0]) * 0.25,
                                        bar_start, spb * 3 - sp_step, 0.40 * dyn)
                        _render_note(master, "bass", _cf(root_hz, chord[0]) * 0.25,
                                        bar_start + spb * 3, spb - sp_step, 0.30 * dyn)
                "drive":
                        _render_bass_drive(master, chord, bar_start, spb, sp_step, dyn,
                                        root_hz)
                "march":
                        _render_bass_march(master, chord, bar_start, spb, sp_step, dyn,
                                        root_hz)
                "gallop":
                        _render_bass_gallop(master, chord, bar_start, spb, sp_step, dyn,
                                        root_hz)
                "drone":
                        _render_note(master, "bassP", _cf(root_hz, chord[0]) * 0.5,
                                        bar_start, spb * 4 - sp_step, 0.30 * dyn)

        # --- Batteria ------------------------------------------------------------
        if drums != "none":
                _render_drums(master, drums, bar_start, spb, sp_step, dyn, is_fill_bar)

        # --- Campane / arpeggi di contrappunto ------------------------------------
        if bell_mode != "none":
                _render_bells(echo, bell_mode, chord, bar_start, spb, sp_step, dyn,
                                root_hz)

        # --- Pad (archi): triade tenuta con attacco lento ------------------------
        if has_pad:
                for semi in chord:
                        _render_note(master, "strings", _cf(root_hz, semi), bar_start,
                                        spb * 4 - sp_step, 0.10 * dyn)


# Frequenza di una nota della frase (grado o semitono esplicito).
func _note_freq(note: Array, scale: PackedInt32Array, root_hz: float,
                major: bool) -> float:
        var deg: int = int(note[2])
        var oct: int = int(note[3])
        if deg < 0:
                # semitono esplicito (frasi cromatiche): oct = semitoni assoluti.
                return root_hz * pow(2.0, float(oct) / 12.0)
        var semi: int
        if deg <= 6:
                semi = scale[deg]
        else:
                # grado 7 = sensibile (11 semitoni), anche in maggiore.
                semi = 11 if not major else 11
        return root_hz * pow(2.0, float(semi + 12 * oct) / 12.0)


# Frequenza di un semitono relativo alla tonica.
func _cf(root_hz: float, semi: int) -> float:
        return root_hz * pow(2.0, float(semi) / 12.0)


# ---------------------------------------------------------------------------
# Sintesi delle note (una nota = un loop di campioni)
# ---------------------------------------------------------------------------

func _render_note(buf: PackedFloat32Array, inst: String, freq: float,
                start: int, length: int, vol: float) -> void:
        var n: int = mini(length, buf.size() - start)
        if n <= 0 or vol <= 0.0:
                return
        var inc: float = freq / float(sr)
        match inst:
                "lead":
                        _render_lead(buf, _t_pulse25, freq, start, n, vol, true)
                "lead2":
                        _render_lead(buf, _t_pulse50, freq, start, n, vol, false)
                "brass":
                        _render_brass(buf, freq, start, n, vol)
                "bell":
                        _render_bell(buf, freq, start, n, vol)
                "harp":
                        _render_harp(buf, freq, start, n, vol)
                "strings":
                        _render_strings(buf, freq, start, n, vol)
                "sub":
                        _render_sub(buf, freq, start, n, vol)
                "bass":
                        _render_bass(buf, freq, start, n, vol)
                "bassP":
                        _render_bass_pulse(buf, freq, start, n, vol)
                _:
                        _render_lead(buf, _t_pulse50, freq, start, n, vol, false)


## Lead pulse con envelope percussivo + vibrato opzionale (5.5 Hz).
func _render_lead(buf: PackedFloat32Array, table: PackedFloat32Array,
                freq: float, start: int, n: int, vol: float, vibrato: bool) -> void:
        var inc: float = freq / float(sr)
        var ph: float = 0.0
        var attack: int = mini(int(sr * 0.012), n)
        var release: int = mini(int(sr * 0.03), n)
        var dk: float = 2.2
        for i in n:
                var t: float = float(i) / float(sr)
                var env: float = exp(-t * dk)
                if i < attack:
                        env *= float(i) / float(attack)
                if i > n - release:
                        env *= float(n - i) / float(release)
                var pitch: float = inc
                if vibrato:
                        pitch *= 1.0 + 0.006 * sin(TAU * 5.5 * t)
                var s: float = table[int(ph * TBL_SIZE) & TBL_MASK] * env * vol
                buf[start + i] += s
                ph += pitch


## Ottoni chiptune: pulse 50% detunato + ottava, attacco "spit".
func _render_brass(buf: PackedFloat32Array, freq: float, start: int, n: int,
                vol: float) -> void:
        var inc: float = freq / float(sr)
        var inc_d: float = inc * 1.003
        var ph: float = 0.0
        var ph2: float = 0.0
        var ph3: float = 0.0
        var attack: int = mini(int(sr * 0.02), n)
        var release: int = mini(int(sr * 0.05), n)
        var dk: float = 1.6
        for i in n:
                var t: float = float(i) / float(sr)
                var env: float = exp(-t * dk)
                if i < attack:
                        env *= 0.4 + 0.6 * float(i) / float(attack)
                if i > n - release:
                        env *= float(n - i) / float(release)
                var s: float = 0.5 * _t_pulse50[int(ph * TBL_SIZE) & TBL_MASK] \
                                + 0.3 * _t_pulse50[int(ph2 * TBL_SIZE) & TBL_MASK] \
                                + 0.2 * _t_pulse125[int(ph3 * TBL_SIZE) & TBL_MASK]
                buf[start + i] += s * env * vol
                ph += inc
                ph2 += inc_d
                ph3 += inc * 2.0


## Campana FM: portante sine + modulante (ratio 3.01) con indice che decade.
## Timbro "celesta/glockenspiel" fantasy, coda lunga.
func _render_bell(buf: PackedFloat32Array, freq: float, start: int, n: int,
                vol: float) -> void:
        var inc: float = freq / float(sr)
        var ph_c: float = 0.0
        var ph_m: float = 0.0
        var dk: float = 2.6
        var release: int = mini(int(sr * 0.06), n)
        for i in n:
                var t: float = float(i) / float(sr)
                var env: float = exp(-t * dk)
                if i > n - release:
                        env *= float(n - i) / float(release)
                # indice FM che decade: attacco metallico -> sine puro.
                var idx: float = 2.4 * exp(-t * 6.0)
                var mod_sample: float = _t_sine[int(ph_m * TBL_SIZE) & TBL_MASK] * idx
                var s: float = _t_sine[int((ph_c + mod_sample) * TBL_SIZE) & TBL_MASK]
                buf[start + i] += s * env * vol
                ph_c += inc
                ph_m += inc * 3.01


## Arpa: triangolo con decay molto veloce (pizzicato).
func _render_harp(buf: PackedFloat32Array, freq: float, start: int, n: int,
                vol: float) -> void:
        var inc: float = freq / float(sr)
        var ph: float = 0.0
        var dk: float = 6.0
        var attack: int = mini(int(sr * 0.004), n)
        for i in n:
                var t: float = float(i) / float(sr)
                var env: float = exp(-t * dk)
                if i < attack:
                        env *= float(i) / float(attack)
                buf[start + i] += _t_tri[int(ph * TBL_SIZE) & TBL_MASK] * env * vol
                ph += inc


## Archi (pad): 2 saw detunati, attacco lento, sustain pieno.
func _render_strings(buf: PackedFloat32Array, freq: float, start: int,
                n: int, vol: float) -> void:
        var inc: float = freq / float(sr)
        var inc2: float = inc * 0.996
        var ph: float = 0.0
        var ph2: float = 0.0
        var attack: int = mini(int(sr * 0.25), n)
        var release: int = mini(int(sr * 0.3), n)
        for i in n:
                var env: float = 1.0
                if i < attack:
                        env = float(i) / float(attack)
                elif i > n - release:
                        env = float(n - i) / float(release)
                var s: float = 0.5 * _t_saw[int(ph * TBL_SIZE) & TBL_MASK] \
                                + 0.5 * _t_saw[int(ph2 * TBL_SIZE) & TBL_MASK]
                buf[start + i] += s * env * vol
                ph += inc
                ph2 += inc2


## Sub basso sine (drone profondo).
func _render_sub(buf: PackedFloat32Array, freq: float, start: int, n: int,
                vol: float) -> void:
        var inc: float = freq / float(sr)
        var ph: float = 0.0
        var attack: int = mini(int(sr * 0.1), n)
        var release: int = mini(int(sr * 0.2), n)
        for i in n:
                var env: float = 1.0
                if i < attack:
                        env = float(i) / float(attack)
                elif i > n - release:
                        env = float(n - i) / float(release)
                buf[start + i] += _t_sine[int(ph * TBL_SIZE) & TBL_MASK] * env * vol
                ph += inc


## Basso triangolo con "punch" (attacco percussivo).
func _render_bass(buf: PackedFloat32Array, freq: float, start: int, n: int,
                vol: float) -> float:
        var inc: float = freq / float(sr)
        var ph: float = 0.0
        var attack: int = mini(int(sr * 0.008), n)
        var release: int = mini(int(sr * 0.04), n)
        var dk: float = 3.0
        for i in n:
                var t: float = float(i) / float(sr)
                var env: float = exp(-t * dk)
                if i < attack:
                        env *= float(i) / float(attack)
                if i > n - release:
                        env *= float(n - i) / float(release)
                buf[start + i] += _t_tri[int(ph * TBL_SIZE) & TBL_MASK] * env * vol
                ph += inc
        return 0.0


## Basso pulse 50% per groove guidati.
func _render_bass_pulse(buf: PackedFloat32Array, freq: float, start: int,
                n: int, vol: float) -> void:
        var inc: float = freq / float(sr)
        var ph: float = 0.0
        var attack: int = mini(int(sr * 0.006), n)
        var release: int = mini(int(sr * 0.03), n)
        var dk: float = 3.5
        for i in n:
                var t: float = float(i) / float(sr)
                var env: float = exp(-t * dk)
                if i < attack:
                        env *= float(i) / float(attack)
                if i > n - release:
                        env *= float(n - i) / float(release)
                buf[start + i] += _t_pulse50[int(ph * TBL_SIZE) & TBL_MASK] * env * vol
                ph += inc


# ---------------------------------------------------------------------------
# Pattern di basso (per battuta, semitoni relativi all'accordo)
# ---------------------------------------------------------------------------

func _render_bass_walk(master: PackedFloat32Array, chord: Array,
                bar_start: int, spb: int, sp_step: int, dyn: float,
                root_hz: float) -> void:
        # Quarti: root - root - 5a - ottava (walking leggero).
        var f0: float = _cf(root_hz, chord[0]) * 0.5
        var f5: float = _cf(root_hz, chord[2]) * 0.5
        var f8: float = f0 * 2.0
        _render_bass(master, f0, bar_start, spb - sp_step, 0.30 * dyn)
        _render_bass(master, f0, bar_start + spb, spb - sp_step, 0.26 * dyn)
        _render_bass(master, f5, bar_start + spb * 2, spb - sp_step, 0.30 * dyn)
        _render_bass(master, f8, bar_start + spb * 3, spb - sp_step, 0.26 * dyn)


func _render_bass_drive(master: PackedFloat32Array, chord: Array,
                bar_start: int, spb: int, sp_step: int, dyn: float,
                root_hz: float) -> void:
        # Ottavi: root root ott root root root 5a root (inseguimento).
        var f0: float = _cf(root_hz, chord[0]) * 0.5
        var f5: float = _cf(root_hz, chord[2]) * 0.5
        var half: int = spb / 2 - sp_step / 2
        var patt: Array = [0, 1, 1, 0, 1, 0, 2, 3]  # 0=root 1=root 2=5a 3=root+
        var f_table: Array = [f0, f0, f5, f0 * 2.0]
        for k in 8:
                _render_bass_pulse(master, f_table[patt[k]],
                                bar_start + k * spb / 8, half, 0.30 * dyn)


func _render_bass_march(master: PackedFloat32Array, chord: Array,
                bar_start: int, spb: int, sp_step: int, dyn: float,
                root_hz: float) -> void:
        # Marcia puntata: root(1.5) root(0.5) 5a(1.5) root(0.5).
        var f0: float = _cf(root_hz, chord[0]) * 0.5
        var f5: float = _cf(root_hz, chord[2]) * 0.5
        _render_bass(master, f0, bar_start, int(spb * 1.5) - sp_step, 0.32 * dyn)
        _render_bass(master, f0, bar_start + int(spb * 1.5), spb / 2 - sp_step,
                        0.26 * dyn)
        _render_bass(master, f5, bar_start + spb * 2, int(spb * 1.5) - sp_step,
                        0.32 * dyn)
        _render_bass(master, f0 * 2.0, bar_start + spb * 2 + int(spb * 1.5),
                        spb / 2 - sp_step, 0.26 * dyn)


func _render_bass_gallop(master: PackedFloat32Array, chord: Array,
                bar_start: int, spb: int, sp_step: int, dyn: float,
                root_hz: float) -> void:
        # Galoppo (stile "runa di ferro"): sedicesimi x..x per ogni quarto.
        var f0: float = _cf(root_hz, chord[0]) * 0.5
        var f_e: float = _cf(root_hz, 11) * 0.5 if chord[0] == 0 else f0
        var n_step: int = sp_step - sp_step / 4
        for q in 4:
                var base: int = bar_start + q * spb
                _render_bass_pulse(master, f0, base, n_step, 0.30 * dyn)
                _render_bass_pulse(master, f0, base + sp_step, n_step, 0.24 * dyn)
                _render_bass_pulse(master, f0, base + sp_step * 2, n_step, 0.24 * dyn)
                # Ultimo quarto: sensibile o quinta per spingere verso l'accordo dopo.
                if q == 3:
                        _render_bass_pulse(master, f_e, base + sp_step * 3, n_step,
                                        0.24 * dyn)
                else:
                        _render_bass_pulse(master, f0, base + sp_step * 3, n_step,
                                        0.18 * dyn)


# ---------------------------------------------------------------------------
# Batteria (pattern per battuta; fill sull'ultima battuta della sezione)
# ---------------------------------------------------------------------------

func _render_drums(master: PackedFloat32Array, mode: String, bar_start: int,
                spb: int, sp_step: int, dyn: float, fill: bool) -> void:
        if fill:
                _render_drum_fill(master, bar_start, spb, sp_step, dyn, mode)
                return
        match mode:
                "heart":
                        # Battito lontano: kick morbido sul beat 1 e 3.
                        _render_drum(master, "kick", 0, spb, 0.5 * dyn, bar_start)
                        _render_drum(master, "kick", 0, spb, 0.42 * dyn,
                                        bar_start + spb * 2)
                "soft":
                        # Kick 1/3 + rim leggero 2/4 + hat ottavi appena accennati.
                        _render_drum(master, "kick", 0, spb, 0.6 * dyn, bar_start)
                        _render_drum(master, "kick", 0, spb, 0.5 * dyn, bar_start + spb * 2)
                        _render_drum(master, "snare", 0, spb, 0.30 * dyn, bar_start + spb)
                        _render_drum(master, "snare", 0, spb, 0.30 * dyn,
                                        bar_start + spb * 3)
                        for k in 8:
                                var g: float = 0.10 if k % 2 == 0 else 0.06
                                _render_drum(master, "hat", 0, spb, g * dyn,
                                                bar_start + k * spb / 8)
                "pop":
                        # Pop 8bit: kick 1/3(+) snare 2/4, hat ottavi.
                        _render_drum(master, "kick", 0, spb, 0.8 * dyn, bar_start)
                        _render_drum(master, "kick", 0, spb, 0.6 * dyn, bar_start + spb * 2)
                        _render_drum(master, "kick", 0, spb, 0.5 * dyn,
                                        bar_start + spb * 3 + sp_step * 2)
                        _render_drum(master, "snare", 0, spb, 0.5 * dyn, bar_start + spb)
                        _render_drum(master, "snare", 0, spb, 0.5 * dyn, bar_start + spb * 3)
                        for k in 8:
                                _render_drum(master, "hat", 0, spb,
                                                (0.16 if k % 2 == 0 else 0.10) * dyn,
                                                bar_start + k * spb / 8)
                "adventure":
                        # Avventura: kick 1, 2.5, 3.75(?) snare 2/4, hat ottavi + open su 4.
                        _render_drum(master, "kick", 0, spb, 0.85 * dyn, bar_start)
                        _render_drum(master, "kick", 0, spb, 0.55 * dyn,
                                        bar_start + spb + sp_step * 2)
                        _render_drum(master, "kick", 0, spb, 0.75 * dyn, bar_start + spb * 2)
                        _render_drum(master, "snare", 0, spb, 0.55 * dyn, bar_start + spb)
                        _render_drum(master, "snare", 0, spb, 0.60 * dyn, bar_start + spb * 3)
                        for k in 8:
                                _render_drum(master, "hat", 0, spb,
                                                (0.15 if k % 2 == 0 else 0.09) * dyn,
                                                bar_start + k * spb / 8)
                        _render_drum(master, "ohat", 0, spb, 0.12 * dyn,
                                        bar_start + spb * 3 + sp_step * 2)
                "chase":
                        # Inseguimento: kick su tutti i quarti + sedicesimi, hat 16esimi.
                        for q in 4:
                                _render_drum(master, "kick", 0, spb, 0.8 * dyn,
                                                bar_start + q * spb)
                        _render_drum(master, "kick", 0, spb, 0.5 * dyn,
                                        bar_start + sp_step * 3)
                        _render_drum(master, "kick", 0, spb, 0.5 * dyn,
                                        bar_start + spb * 2 + sp_step * 3)
                        _render_drum(master, "snare", 0, spb, 0.55 * dyn, bar_start + spb)
                        _render_drum(master, "snare", 0, spb, 0.60 * dyn, bar_start + spb * 3)
                        _render_drum(master, "snare", 0, spb, 0.18 * dyn,
                                        bar_start + spb * 3 + sp_step * 2)
                        for k in 16:
                                _render_drum(master, "hat", 0, spb,
                                                (0.14 if k % 2 == 0 else 0.07) * dyn,
                                                bar_start + k * sp_step)
                "doom":
                        # Half-time pesante: kick 1, snare 3, tom su 4.
                        _render_drum(master, "kick", 0, spb, 1.0 * dyn, bar_start)
                        _render_drum(master, "kick", 0, spb, 0.45 * dyn,
                                        bar_start + spb + sp_step * 2)
                        _render_drum(master, "snare", 0, spb, 0.7 * dyn, bar_start + spb * 2)
                        _render_drum(master, "tomL", 0, spb, 0.5 * dyn,
                                        bar_start + spb * 3)
                        _render_drum(master, "tomL", 0, spb, 0.4 * dyn,
                                        bar_start + spb * 3 + sp_step * 2)
                        for k in 4:
                                _render_drum(master, "hat", 0, spb, 0.08 * dyn,
                                                bar_start + k * spb)
                "march":
                        # Marcia: rullata di cassa su 8esimi puntati + timpani 1/3.
                        _render_drum(master, "timpani", 0, spb, 0.8 * dyn, bar_start)
                        _render_drum(master, "timpani", 0, spb, 0.7 * dyn,
                                        bar_start + spb * 2)
                        var sn_pat: Array = [0, 3, 4, 6, 8, 11, 12, 14]
                        for k in sn_pat:
                                _render_drum(master, "snare", 0, spb,
                                                (0.5 if k == 0 or k == 8 else 0.34) * dyn,
                                                bar_start + k * sp_step)
                        _render_drum(master, "ohat", 0, spb, 0.1 * dyn,
                                        bar_start + spb * 2)
                "gallop":
                        # Boss: doppio kick 8esimi + snare 2/4 + ghost 16esimi.
                        for k in 8:
                                _render_drum(master, "kick", 0, spb, 0.85 * dyn,
                                                bar_start + k * spb / 8)
                        _render_drum(master, "snare", 0, spb, 0.65 * dyn, bar_start + spb)
                        _render_drum(master, "snare", 0, spb, 0.65 * dyn, bar_start + spb * 3)
                        _render_drum(master, "snare", 0, spb, 0.2 * dyn,
                                        bar_start + spb * 3 + sp_step * 3)
                        for k in 16:
                                _render_drum(master, "hat", 0, spb,
                                                (0.13 if k % 2 == 0 else 0.06) * dyn,
                                                bar_start + k * sp_step)
                "halftime":
                        # Boss half-time: kick 1, snare 3 + crash leggero.
                        _render_drum(master, "kick", 0, spb, 1.0 * dyn, bar_start)
                        _render_drum(master, "kick", 0, spb, 0.5 * dyn,
                                        bar_start + spb + sp_step * 2)
                        _render_drum(master, "snare", 0, spb, 0.75 * dyn, bar_start + spb * 2)
                        _render_drum(master, "snare", 0, spb, 0.3 * dyn,
                                        bar_start + spb * 2 + sp_step * 2)
                        _render_drum(master, "crash", 0, spb, 0.16 * dyn,
                                        bar_start + spb * 2)
                "full":
                        # Pieno: kick 4/4 + snare 2/4 + hat 8esimi + open.
                        for q in 4:
                                _render_drum(master, "kick", 0, spb, 0.9 * dyn,
                                                bar_start + q * spb)
                        _render_drum(master, "kick", 0, spb, 0.5 * dyn,
                                        bar_start + sp_step * 2)
                        _render_drum(master, "kick", 0, spb, 0.5 * dyn,
                                        bar_start + spb * 2 + sp_step * 2)
                        _render_drum(master, "snare", 0, spb, 0.62 * dyn, bar_start + spb)
                        _render_drum(master, "snare", 0, spb, 0.66 * dyn, bar_start + spb * 3)
                        for k in 8:
                                _render_drum(master, "hat", 0, spb,
                                                (0.16 if k % 2 == 0 else 0.10) * dyn,
                                                bar_start + k * spb / 8)
                        _render_drum(master, "ohat", 0, spb, 0.12 * dyn,
                                        bar_start + spb * 3 + sp_step * 2)
                "roll":
                        # Rullo di timpani (allarme/riser): 8esimi crescenti.
                        for k in 8:
                                var g: float = 0.35 + 0.06 * k
                                _render_drum(master, "timpani", 0, spb, g * dyn,
                                                bar_start + k * spb / 8)
                        _render_drum(master, "crash", 0, spb, 0.2 * dyn, bar_start)
                _:
                        pass


func _render_drum_fill(master: PackedFloat32Array, bar_start: int, spb: int,
                sp_step: int, dyn: float, _mode: String) -> void:
        # Fill classico: due quarti normali + discesa di tom a sedicesimi,
        # snare sull'ultimo sedicesimo, crash implicito all'inizio della sezione.
        _render_drum(master, "kick", 0, spb, 0.8 * dyn, bar_start)
        _render_drum(master, "snare", 0, spb, 0.5 * dyn, bar_start + spb)
        var toms: Array = ["tomH", "tomM", "tomM", "tomL"]
        for k in 16:
                if k >= 8:
                        var t: String = toms[(k - 8) / 2]
                        _render_drum(master, t, 0, spb, (0.5 - 0.02 * (k - 8)) * dyn,
                                        bar_start + k * sp_step)
        _render_drum(master, "snare", 0, spb, 0.4 * dyn,
                        bar_start + spb * 3 + sp_step * 3)


# ---------------------------------------------------------------------------
# Campane / arpeggi di contrappunto
# ---------------------------------------------------------------------------

func _render_bells(echo: PackedFloat32Array, mode: String, chord: Array,
                bar_start: int, spb: int, sp_step: int, dyn: float,
                root_hz: float) -> void:
        match mode:
                "sparse":
                        # Una campana per battuta: la 5a dell'accordo, un'ottava su.
                        _render_note(echo, "bell", _cf(root_hz, chord[2]) * 4.0,
                                        bar_start, spb * 2, 0.10 * dyn)
                "eighth":
                        # Arpeggio in ottavi: root - 3a - 5a - 8va (su due ottave).
                        var seq: Array = [chord[0], chord[1], chord[2], chord[0] + 12,
                                        chord[1] + 12, chord[2] + 12, chord[0] + 12, chord[2]]
                        for k in 8:
                                _render_note(echo, "bell", _cf(root_hz, seq[k]) * 2.0,
                                                bar_start + k * spb / 8, spb / 8, 0.11 * dyn)
                "sixteenth":
                        # Arpeggio veloce in sedicesimi (climax): su e giu'.
                        var seq: Array = [chord[0], chord[1], chord[2], chord[0] + 12,
                                        chord[2], chord[0] + 12, chord[1] + 12, chord[2] + 12,
                                        chord[0], chord[1], chord[2], chord[0] + 12,
                                        chord[2], chord[0] + 12, chord[1] + 12, chord[2] + 12]
                        for k in 16:
                                _render_note(echo, "bell", _cf(root_hz, seq[k]) * 2.0,
                                                bar_start + k * sp_step, sp_step, 0.09 * dyn)
                "harp":
                        # Arpa: pizzicato in ottavi, solo su metà battuta.
                        var seqh: Array = [chord[0], chord[2], chord[1] + 12, chord[2] + 12]
                        for k in 4:
                                _render_note(echo, "harp", _cf(root_hz, seqh[k]) * 2.0,
                                                bar_start + k * spb / 4, spb / 4, 0.13 * dyn)
                "tritone":
                        # Menaccia del boss: tritono root-b5 in sedicesimi alternati.
                        var f0: float = _cf(root_hz, chord[0]) * 2.0
                        var fb5: float = f0 * pow(2.0, 6.0 / 12.0)
                        for k in 16:
                                var f: float = f0 if k % 2 == 0 else fb5
                                _render_note(echo, "bell", f, bar_start + k * sp_step,
                                                sp_step, 0.07 * dyn)
                _:
                        pass


# ---------------------------------------------------------------------------
# Percussioni singole
# ---------------------------------------------------------------------------

func _render_drum(master: PackedFloat32Array, kind: String, _off: int,
                _len: int, vol: float, at: int) -> void:
        match kind:
                "kick":
                        _render_kick(master, at, vol)
                "snare":
                        _render_snare(master, at, vol)
                "hat":
                        _render_hat(master, at, vol, false)
                "ohat":
                        _render_hat(master, at, vol, true)
                "tomH":
                        _render_tom(master, at, vol, 220.0)
                "tomM":
                        _render_tom(master, at, vol, 160.0)
                "tomL":
                        _render_tom(master, at, vol, 110.0)
                "crash":
                        _render_crash(master, at, vol)
                "timpani":
                        _render_timpani(master, at, vol)
                _:
                        pass


## Kick: sine con pitch drop 150->40 Hz + click.
func _render_kick(master: PackedFloat32Array, at: int, vol: float) -> void:
        var n: int = int(sr * 0.16)
        var ph: float = 0.0
        for i in n:
                var at_abs: int = at + i
                if at_abs >= master.size():
                        break
                var t: float = float(i) / float(sr)
                var freq: float = 150.0 * exp(-t * 28.0) + 42.0
                ph += TAU * freq / float(sr)
                var env: float = exp(-t * 18.0)
                var click: float = 0.0
                if i < 60:
                        click = _rng.randf_range(-1.0, 1.0) * (1.0 - float(i) / 60.0)
                master[at_abs] += (sin(ph) * 0.9 + click * 0.25) * env * vol


## Snare: noise + tono 190 Hz, decay medio.
func _render_snare(master: PackedFloat32Array, at: int, vol: float) -> void:
        var n: int = int(sr * 0.14)
        var ph: float = 0.0
        for i in n:
                var at_abs: int = at + i
                if at_abs >= master.size():
                        break
                var t: float = float(i) / float(sr)
                var env: float = exp(-t * 24.0)
                ph += TAU * 190.0 / float(sr)
                var v: float = 0.55 * _rng.randf_range(-1.0, 1.0) \
                                + 0.45 * sin(ph) * exp(-t * 40.0)
                master[at_abs] += v * env * vol


## Hi-hat: noise filtrato passa-alto (differenza), corto o aperto.
func _render_hat(master: PackedFloat32Array, at: int, vol: float,
                open: bool) -> void:
        var n: int = int(sr * (0.09 if open else 0.035))
        var last: float = 0.0
        for i in n:
                var at_abs: int = at + i
                if at_abs >= master.size():
                        break
                var t: float = float(i) / float(sr)
                var w: float = _rng.randf_range(-1.0, 1.0)
                var hp: float = w - last
                last = w
                var env: float = exp(-t * (28.0 if open else 90.0))
                master[at_abs] += hp * env * vol * 0.8


## Tom: sine con sweep discendente.
func _render_tom(master: PackedFloat32Array, at: int, vol: float,
                f0: float) -> void:
        var n: int = int(sr * 0.22)
        var ph: float = 0.0
        for i in n:
                var at_abs: int = at + i
                if at_abs >= master.size():
                        break
                var t: float = float(i) / float(sr)
                var freq: float = f0 * exp(-t * 4.0) + f0 * 0.45
                ph += TAU * freq / float(sr)
                var env: float = exp(-t * 12.0)
                master[at_abs] += sin(ph) * env * vol


## Crash: rumore con coda lunga e decay doppio.
func _render_crash(master: PackedFloat32Array, at: int, vol: float) -> void:
        var n: int = int(sr * 0.9)
        var lp: float = 0.0
        for i in n:
                var at_abs: int = at + i
                if at_abs >= master.size():
                        break
                var t: float = float(i) / float(sr)
                var w: float = _rng.randf_range(-1.0, 1.0)
                lp += 0.6 * (w - lp)
                var env: float = exp(-t * 3.5) + 0.3 * exp(-t * 9.0)
                master[at_abs] += lp * env * vol


## Timpani: 82 Hz + noise thump, sustain medio.
func _render_timpani(master: PackedFloat32Array, at: int, vol: float) -> void:
        var n: int = int(sr * 0.35)
        var ph: float = 0.0
        for i in n:
                var at_abs: int = at + i
                if at_abs >= master.size():
                        break
                var t: float = float(i) / float(sr)
                ph += TAU * 82.0 / float(sr)
                var env: float = exp(-t * 7.0)
                var thump: float = 0.0
                if i < int(sr * 0.008):
                        thump = _rng.randf_range(-1.0, 1.0) * 0.4
                master[at_abs] += (sin(ph) + thump) * env * vol


## Riser: rumore passa-basso con cutoff che sale (build di sezione).
func _render_riser(master: PackedFloat32Array, at: int, len: int,
                vol: float) -> void:
        var lp: float = 0.0
        for i in len:
                var at_abs: int = at + i
                if at_abs >= master.size():
                        break
                var p: float = float(i) / float(len)
                var cutoff: float = 200.0 + 3800.0 * p * p
                var alpha: float = minf(1.0, TAU * cutoff / float(sr))
                var w: float = _rng.randf_range(-1.0, 1.0)
                lp += alpha * (w - lp)
                var env: float = p
                master[at_abs] += lp * env * vol
