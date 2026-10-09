## NameEntryKeyboard.gd - Tastiera alfanumerica virtuale per l'inserimento
## del nome a fine partita (Hall of Fame).
## ============================================================
## FIX (Hall of Fame): appare quando la partita termina con un punteggio
## da classifica. Il player inserisce il proprio nome con i MOVIMENTI
## (frecce direzionali / joystick) per spostare il cursore sulla griglia di
## caratteri e col TASTO FUOCO (Enter/Space/joy A/tasto fuoco configurato)
## seleziona il carattere da inserire. Tasti speciali in fondo alla griglia:
##   * CANC  - cancella l'ultimo carattere del nome
##   * FINE  - termina l'inserimento (tasto dedicato accanto a CANC)
##   * OK    - conferma e salva nome + punteggio nella Hall of Fame
##
## Griglia: 4 righe x 10 colonne
##   Riga 0: A B C D E F G H I J
##   Riga 1: K L M N O P Q R S T
##   Riga 2: U V W X Y Z 0 1 2 3
##   Riga 3: 4 5 6 7 8 9 . - ! ?   (poi CANC / FINE / OK come celle speciali
##                                  della riga, attivabili come caratteri)
## Layout scelto: CANC, FINE e OK sono le ultime 3 celle della riga 3.
extends Control

signal entry_confirmed(player_name: String)
signal entry_cancelled

const C = preload("res://scripts/core/GameConstants.gd")

# Griglia caratteri: 4 righe x 10 colonne (le ultime 3 celle della riga 3
# sono i comandi speciali CANC / FINE / OK).
const GRID_ROWS: int = 4
const GRID_COLS: int = 10
const CELL_W: float = 96.0
const CELL_H: float = 72.0
const SPECIAL_CANC: int = 37   # indice piatto riga 3, col 7
const SPECIAL_END: int = 38    # col 8
const SPECIAL_OK: int = 39     # col 9

const CHARACTERS: Array = [
        "A", "B", "C", "D", "E", "F", "G", "H", "I", "J",
        "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T",
        "U", "V", "W", "X", "Y", "Z", "0", "1", "2", "3",
        "4", "5", "6", "7", "8", "9", ".", "-", "!", "?",
]

@export var color_title: Color = Color(0.863, 0.627, 0.196)   # oro
@export var color_cell: Color = Color(0.784, 0.784, 0.784)    # argento
@export var color_cell_sel: Color = Color(1.0, 0.84, 0.0)    # giallo oro
@export var color_special: Color = Color(0.55, 0.75, 1.0)   # azzurro
@export var color_name: Color = Color(1.0, 0.9, 0.6)

var _sel_row: int = 0
var _sel_col: int = 0
var _name: String = ""
var _finished: bool = false
var _time: float = 0.0
var _joy_nav_cooldown: float = 0.0
# Score mostrato nella barra del nome (set dal chiamante)
var display_score: int = 0
var display_level: int = 1
# Se true, il tasto FINE/OK salva già la voce (usato dalla LoseScreen)
var save_on_confirm: bool = true


func _ready() -> void:
        set_anchors_preset(Control.PRESET_FULL_RECT)
        mouse_filter = Control.MOUSE_FILTER_STOP
        focus_mode = Control.FOCUS_ALL


func _process(delta: float) -> void:
        _time += delta
        if _joy_nav_cooldown > 0:
                _joy_nav_cooldown -= delta
        queue_redraw()


# ---------------------------------------------------------------------------
# Input: frecce = movimento, fuoco = selezione carattere.
# L'input joy configurato (ConfigManager.joy_shoot) è gestito da chi ha la
# scena attiva; qui gestiamo tastiera + joypad standard.
# ---------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
        if _finished:
                return
        if event is InputEventKey and event.pressed and not event.echo:
                match event.keycode:
                        KEY_UP:
                                _move(-1, 0)
                        KEY_DOWN:
                                _move(1, 0)
                        KEY_LEFT:
                                _move(0, -1)
                        KEY_RIGHT:
                                _move(0, 1)
                        KEY_ENTER, KEY_SPACE, KEY_Z:
                                _select_current()
                        KEY_BACKSPACE:
                                _delete_char()
                        KEY_ESCAPE:
                                _confirm_entry()
                return
        if event is InputEventJoypadMotion:
                var ax: float = event.axis_value
                if _joy_nav_cooldown <= 0:
                        if event.axis == JOY_AXIS_LEFT_Y:
                                if ax < -0.5:
                                        _move(-1, 0)
                                        _joy_nav_cooldown = 0.22
                                elif ax > 0.5:
                                        _move(1, 0)
                                        _joy_nav_cooldown = 0.22
                        elif event.axis == JOY_AXIS_LEFT_X:
                                if ax < -0.5:
                                        _move(0, -1)
                                        _joy_nav_cooldown = 0.22
                                elif ax > 0.5:
                                        _move(0, 1)
                                        _joy_nav_cooldown = 0.22
                        # D-pad come hat (axis 6/7 su molti pad)
                        elif event.axis == 6:
                                if ax < -0.5:
                                        _move(0, -1)
                                        _joy_nav_cooldown = 0.22
                                elif ax > 0.5:
                                        _move(0, 1)
                                        _joy_nav_cooldown = 0.22
                        elif event.axis == 7:
                                if ax < -0.5:
                                        _move(-1, 0)
                                        _joy_nav_cooldown = 0.22
                                elif ax > 0.5:
                                        _move(1, 0)
                                        _joy_nav_cooldown = 0.22
                return
        if event is InputEventJoypadButton and event.pressed:
                # Tasto fuoco configurato (se disponibile) oppure A/START
                var configured_shoot: int = -1
                if ConfigManager and ConfigManager.p1_joystick_ready():
                        configured_shoot = ConfigManager.joy_shoot()
                if configured_shoot >= 0 and event.button_index == configured_shoot:
                        _select_current()
                        return
                match event.button_index:
                        JOY_BUTTON_A, JOY_BUTTON_START:
                                _select_current()
                        JOY_BUTTON_DPAD_UP:
                                if _joy_nav_cooldown <= 0:
                                        _move(-1, 0)
                                        _joy_nav_cooldown = 0.22
                        JOY_BUTTON_DPAD_DOWN:
                                if _joy_nav_cooldown <= 0:
                                        _move(1, 0)
                                        _joy_nav_cooldown = 0.22
                        JOY_BUTTON_DPAD_LEFT:
                                if _joy_nav_cooldown <= 0:
                                        _move(0, -1)
                                        _joy_nav_cooldown = 0.22
                        JOY_BUTTON_DPAD_RIGHT:
                                if _joy_nav_cooldown <= 0:
                                        _move(0, 1)
                                        _joy_nav_cooldown = 0.22
                        JOY_BUTTON_B:
                                _delete_char()
                        JOY_BUTTON_BACK:
                                _confirm_entry()


func _move(d_row: int, d_col: int) -> void:
        _sel_row = clampi(_sel_row + d_row, 0, GRID_ROWS - 1)
        _sel_col = clampi(_sel_col + d_col, 0, GRID_COLS - 1)
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.MENU_SELECT)


func _flat_index() -> int:
        return _sel_row * GRID_COLS + _sel_col


func _select_current() -> void:
        var idx: int = _flat_index()
        if idx == SPECIAL_CANC:
                _delete_char()
        elif idx == SPECIAL_END or idx == SPECIAL_OK:
                _confirm_entry()
        elif idx < CHARACTERS.size() and _name.length() < HallOfFameData.MAX_NAME_LENGTH:
                # Carattere normale (le celle speciali sostituiscono "-", "!",
                # "?" quindi tutti gli indici 0..36 sono caratteri validi)
                _name += CHARACTERS[idx]
                if AudioManager:
                        AudioManager.play_sound(AudioManager.SoundType.MENU_CONFIRM)


func _delete_char() -> void:
        if _name.length() > 0:
                _name = _name.substr(0, _name.length() - 1)
                if AudioManager:
                        AudioManager.play_sound(AudioManager.SoundType.MENU_SELECT)


func _confirm_entry() -> void:
        if _finished:
                return
        _finished = true
        var final_name: String = _name if _name.length() > 0 else "HERO"
        if save_on_confirm:
                HallOfFameData.add_entry(final_name, display_score, display_level)
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.WIN)
        entry_confirmed.emit(final_name)


func get_entered_name() -> String:
        return _name if _name.length() > 0 else "HERO"


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------
func _draw() -> void:
        var font := get_theme_default_font()
        var vp: Vector2 = size
        var cx: float = vp.x * 0.5

        # Sfondo scuro semitrasparente (sopra la schermata di game over)
        draw_rect(Rect2(0, 0, vp.x, vp.y), Color(0.02, 0.0, 0.0, 0.82), true)
        # Cornice dorata
        var frame_margin: float = 60.0
        draw_rect(Rect2(frame_margin, 40.0, vp.x - frame_margin * 2.0, vp.y - 80.0),
                Color(0.78, 0.62, 0.20, 0.9), false, 4.0)
        draw_rect(Rect2(frame_margin + 8.0, 48.0, vp.x - (frame_margin + 8.0) * 2.0,
                vp.y - 96.0), Color(0.78, 0.62, 0.20, 0.4), false, 1.5)

        # Titolo
        var title_pulse: float = 1.0 + 0.04 * sin(_time * 2.0)
        draw_string(font, Vector2(cx - 400, 110), "NEW HIGH SCORE!",
                HORIZONTAL_ALIGNMENT_CENTER, 800, int(46 * title_pulse), color_title)

        # Punteggio e livello raggiunto
        draw_string(font, Vector2(cx - 400, 152),
                "SCORE: %d   -   LEVEL: %d" % [display_score, display_level],
                HORIZONTAL_ALIGNMENT_CENTER, 800, 24, Color(0.9, 0.9, 0.9))

        # Nome in costruzione (con cursore lampeggiante)
        var shown_name: String = _name
        if _name.length() < HallOfFameData.MAX_NAME_LENGTH:
                shown_name += "_" if fmod(_time, 0.8) < 0.4 else " "
        while shown_name.length() < HallOfFameData.MAX_NAME_LENGTH:
                shown_name += " "
        draw_string(font, Vector2(cx - 300, 200), "NAME:  %s" % shown_name,
                HORIZONTAL_ALIGNMENT_LEFT, 600, 34, color_name)
        # Riga di underline sotto il nome
        var name_x: float = cx - 300 + 90
        draw_rect(Rect2(name_x, 212, HallOfFameData.MAX_NAME_LENGTH * 20.0, 3.0),
                Color(0.78, 0.62, 0.20, 0.8), true)

        # --- Griglia caratteri ---
        var grid_w: float = GRID_COLS * CELL_W
        var grid_x0: float = cx - grid_w * 0.5
        var grid_y0: float = 250.0
        for row in GRID_ROWS:
                for col in GRID_COLS:
                        var idx: int = row * GRID_COLS + col
                        var cell_cx: float = grid_x0 + float(col) * CELL_W + CELL_W * 0.5
                        var cell_cy: float = grid_y0 + float(row) * CELL_H + CELL_H * 0.5
                        var is_sel: bool = (row == _sel_row and col == _sel_col)
                        # Cella speciale?
                        var is_special: bool = (idx >= SPECIAL_CANC)
                        # Riquadro cella
                        var cell_rect := Rect2(cell_cx - CELL_W * 0.44, cell_cy - CELL_H * 0.42,
                                CELL_W * 0.88, CELL_H * 0.84)
                        if is_sel:
                                # Evidenziata: riquadro pieno + bordo pulsante
                                var pulse: float = 0.5 + 0.5 * sin(_time * 6.0)
                                draw_rect(cell_rect, Color(0.35, 0.28, 0.05, 0.85), true)
                                draw_rect(cell_rect,
                                        Color(1.0, 0.84, 0.2, 0.7 + 0.3 * pulse), false, 3.0)
                        else:
                                draw_rect(cell_rect, Color(0.12, 0.10, 0.08, 0.6), true)
                                draw_rect(cell_rect, Color(0.45, 0.38, 0.25, 0.5), false, 1.0)
                        # Etichetta
                        var label: String
                        if idx == SPECIAL_CANC:
                                label = "CANC"
                        elif idx == SPECIAL_END:
                                label = "FINE"
                        elif idx == SPECIAL_OK:
                                label = "OK"
                        else:
                                label = CHARACTERS[idx]
                        var lbl_col: Color = color_special if is_special else (
                                color_cell_sel if is_sel else color_cell)
                        var lbl_size: int = 20 if is_special else 30
                        draw_string(font, Vector2(cell_cx - CELL_W * 0.44, cell_cy + 10),
                                label, HORIZONTAL_ALIGNMENT_CENTER,
                                CELL_W * 0.88, lbl_size, lbl_col)

        # Hint comandi (pulsante)
        var hint_alpha: float = 0.5 + 0.5 * sin(_time * 2.0)
        draw_string(font, Vector2(cx - 500, vp.y - 90),
                "FRECCE / JOYSTICK = MOVIMENTO    FUOCO = SELEZIONA",
                HORIZONTAL_ALIGNMENT_CENTER, 1000, 20,
                Color(0.59, 0.59, 0.59, hint_alpha))
        draw_string(font, Vector2(cx - 500, vp.y - 62),
                "OK O FINE = CONFERMA E SALVA IN HALL OF FAME",
                HORIZONTAL_ALIGNMENT_CENTER, 1000, 20,
                Color(0.59, 0.59, 0.59, hint_alpha))
