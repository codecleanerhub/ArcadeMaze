## SaveSlotsCard.gd — TASK 106 (SALVA PARTITA): card scelta della RUN.
## ============================================================
## Card in stile "armi bonus" (pattern NewGamePlusCard: CanvasLayer
## pure-code, legno scuro + rifiniture oro) che elenca gli slot di
## salvataggio. Due modalità:
##
##   MODE_LOAD  (voce CONTINUA del menu principale): ogni riga mostra
##              DATA/ORA del save, LIVELLO DI GIOCO, LIVELLO DEL PLAYER e
##              TIPO DEL PLAYER (elfo, drago...; in 2P entrambi).
##              INVIO -> signal slot_chosen(slot); ESC -> closed.
##
##   MODE_DELETE (overflow: 10 slot pieni e la run deve salvare):
##              "prima di salvare, verrà chiesto quale slot di salvataggio
##              eliminare per liberare lo slot e salvare". INVIO su una
##              riga -> conferma inline ("Eliminare?"), secondo INVIO
##              elimina lo slot dal disco -> signal slot_deleted(slot);
##              ESC alla lista -> delete_aborted (si prosegue SENZA save).
##
## Input: SU/GIÙ (frecce, action move_*, D-pad) + INVIO/SPAZIO (confirm /
## jump / tasto A) + ESC. Gate anti-ghost sul confirm (pattern card).
## La card mette in PAUSA il tree (PROCESS_MODE_ALWAYS) e la toglie
## SEMPRE alla chiusura, prima di emettere il segnale.
extends CanvasLayer

## Scelta confermata in MODE_LOAD: slot da riprendere.
signal slot_chosen(slot: int)
## Slot eliminato in MODE_DELETE (il salvataggio può procedere lì).
signal slot_deleted(slot: int)
## Chiusura senza scelta (MODE_LOAD) / senza eliminare (MODE_DELETE).
signal closed
signal delete_aborted

enum Mode { LOAD, DELETE }

const C = preload("res://scripts/core/GameConstants.gd")

# Palette (mirror NewGamePlusCard: legno scuro + oro + nastro rosso).
const COL_VEIL: Color = Color(0.0, 0.0, 0.02, 0.78)
const COL_WOOD: Color = Color(0.16, 0.10, 0.06, 0.97)
const COL_WOOD_LIGHT: Color = Color(0.27, 0.17, 0.09, 0.97)
const COL_GOLD: Color = Color(0.84, 0.66, 0.18)
const COL_GOLD_DARK: Color = Color(0.55, 0.41, 0.10)
const COL_TEXT: Color = Color(0.94, 0.88, 0.72)
const COL_TEXT_DIM: Color = Color(0.72, 0.66, 0.52)
const COL_RIBBON: Color = Color(0.45, 0.05, 0.05, 0.95)
const COL_DELETE: Color = Color(1.0, 0.42, 0.30)

## Altezza di una riga slot e margine interno della lista.
const ROW_H: float = 46.0
const ROW_W: float = 640.0

var _mode: int = Mode.LOAD
var _rows: Array = []            # sommari (dict di SaveSystem.slot_summary)
var _sel: int = 0
var _confirm_armed: bool = false
var _delete_confirm: bool = false  # true = secondo INVIO su riga DELETE
var _prev_esc: bool = false
var _t: float = 0.0
var _panel: Control = null

# Edge detection D-pad/joystick (pattern NewGamePlusCard).
var _prev_joy_btns: Dictionary = {}


## `slots`: sommari già pronti (SaveSystem.all_summaries()).
func setup(mode: int, rows: Array) -> void:
        _mode = mode
        _rows = rows


func _ready() -> void:
        layer = 33
        process_mode = Node.PROCESS_MODE_ALWAYS
        # La card blocca il gioco sotto (nel MENU ferma anche il timer demo).
        get_tree().paused = true
        _panel = Control.new()
        _panel.name = "SaveSlotsCardPanel"
        _panel.set_anchors_preset(Control.PRESET_FULL_RECT)
        _panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _panel.draw.connect(_draw_panel.bind(_panel))
        add_child(_panel)
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.MENU_SELECT)


func _exit_tree() -> void:
        # Belt & braces: la pausa va SEMPRE via, anche su free esterno.
        if get_tree() != null:
                get_tree().paused = false


func _physics_process(delta: float) -> void:
        _t += delta
        if Input.is_action_just_pressed("move_up"):
                _move_sel(-1)
        elif Input.is_action_just_pressed("move_down"):
                _move_sel(1)
        _poll_joystick()
        var confirm: bool = Input.is_action_just_pressed("confirm") \
                        or Input.is_action_just_pressed("jump") \
                        or _joy_confirm_edge()
        if not confirm:
                _confirm_armed = true
        elif _confirm_armed:
                _confirm_armed = false
                _confirm()
        # ESC edge-detected (annulla: conferma elimina in DELETE, chiusura).
        var esc: bool = Input.is_action_just_pressed("ui_cancel")
        if esc and not _prev_esc:
                _cancel()
        _prev_esc = esc
        _panel.queue_redraw()


func _move_sel(dir: int) -> void:
        if _rows.is_empty():
                return
        _delete_confirm = false
        _sel = posmod(_sel + dir, _rows.size())
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.MENU_SELECT)


func _poll_joystick() -> void:
        var pads: Array = Input.get_connected_joypads()
        if pads.is_empty():
                return
        var joy: int = int(pads[0])
        var dpad := {
                        JOY_BUTTON_DPAD_UP: -1,
                        JOY_BUTTON_DPAD_DOWN: 1,
        }
        for btn in dpad.keys():
                var pressed: bool = Input.is_joy_button_pressed(joy, btn)
                var was: bool = bool(_prev_joy_btns.get(btn, false))
                _prev_joy_btns[btn] = pressed
                if pressed and not was:
                        _move_sel(int(dpad[btn]))
        # B = annulla (come i menu del gioco).
        var pressed_b: bool = Input.is_joy_button_pressed(joy, JOY_BUTTON_B)
        var was_b: bool = bool(_prev_joy_btns.get(JOY_BUTTON_B, false))
        _prev_joy_btns[JOY_BUTTON_B] = pressed_b
        if pressed_b and not was_b:
                _cancel()


func _joy_confirm_edge() -> bool:
        var pads: Array = Input.get_connected_joypads()
        if pads.is_empty():
                return false
        var joy: int = int(pads[0])
        for btn in [JOY_BUTTON_A, JOY_BUTTON_START]:
                var pressed: bool = Input.is_joy_button_pressed(joy, btn)
                var was: bool = bool(_prev_joy_btns.get(btn, false))
                _prev_joy_btns[btn] = pressed
                if pressed and not was:
                        return true
        return false


func _confirm() -> void:
        if _rows.is_empty():
                _cancel()
                return
        var slot: int = int(_rows[_sel].get("slot", -1))
        if _mode == Mode.LOAD:
                if AudioManager:
                        AudioManager.play_sound(AudioManager.SoundType.MENU_CONFIRM)
                _close()
                slot_chosen.emit(slot)
                return
        # MODE_DELETE: primo INVIO = chiedi conferma, secondo = elimina.
        if not _delete_confirm:
                _delete_confirm = true
                if AudioManager:
                        AudioManager.play_sound(AudioManager.SoundType.MENU_SELECT)
                return
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.MENU_CONFIRM)
        if SaveSystem != null:
                SaveSystem.delete_slot(slot)
        _close()
        slot_deleted.emit(slot)


func _cancel() -> void:
        if _mode == Mode.DELETE and _delete_confirm:
                _delete_confirm = false   # annulla la conferma, torna alla lista
                return
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.MENU_SELECT)
        _close()
        if _mode == Mode.DELETE:
                delete_aborted.emit()
        else:
                closed.emit()


func _close() -> void:
        # La pausa va tolta PRIMA che l'host reagisca al segnale (il cambio
        # scena deve trovare il tree non in pausa).
        get_tree().paused = false
        queue_free()


# ---------------------------------------------------------------------------
# Rendering (mirror NewGamePlusCard)
# ---------------------------------------------------------------------------
func _draw_panel(ci: Control) -> void:
        var vp: Vector2 = ci.get_viewport_rect().size
        var font: Font = ThemeDB.fallback_font
        var gold_font: Font = C.gothic_font()
        if gold_font == null:
                gold_font = font

        ci.draw_rect(Rect2(Vector2.ZERO, vp), COL_VEIL, true)

        # card centrata: altezza in funzione del numero di righe.
        var title: String = I18n.t("save.card_title") if _mode == Mode.LOAD \
                        else I18n.t("save.delete_title")
        var rows_n: int = maxi(1, _rows.size())
        var list_h: float = rows_n * ROW_H
        var card_h: float = minf(196.0 + list_h + 96.0, vp.y * 0.94)
        var card_size := Vector2(minf(780.0, vp.x * 0.92), card_h)
        var card_pos := (vp - card_size) * 0.5

        # cornice legno + doppio bordo oro + angoli runici pulsanti
        ci.draw_rect(Rect2(card_pos, card_size), COL_WOOD, true)
        ci.draw_rect(Rect2(card_pos + Vector2(6, 6),
                        card_size - Vector2(12, 12)), COL_WOOD_LIGHT, true)
        ci.draw_rect(Rect2(card_pos + Vector2(10, 10),
                        card_size - Vector2(20, 20)), COL_WOOD, true)
        ci.draw_rect(Rect2(card_pos + Vector2(10, 10),
                        card_size - Vector2(20, 20)), COL_GOLD, false, 3.0)
        ci.draw_rect(Rect2(card_pos + Vector2(18, 18),
                        card_size - Vector2(36, 36)), COL_GOLD_DARK, false, 1.5)
        var pulse: float = 0.5 + 0.5 * sin(_t * 3.0)
        var accent: Color = COL_DELETE if _mode == Mode.DELETE else COL_GOLD
        for corner in [
                        card_pos + Vector2(26, 26),
                        card_pos + Vector2(card_size.x - 26, 26),
                        card_pos + Vector2(26, card_size.y - 26),
                        card_pos + Vector2(card_size.x - 26, card_size.y - 26)]:
                _draw_diamond(ci, corner, 8.0 + 2.0 * pulse, accent)

        # nastro col titolo
        var ribbon_w: float = 400.0
        var ribbon_rect := Rect2(card_pos.x + (card_size.x - ribbon_w) * 0.5,
                        card_pos.y + 30.0, ribbon_w, 38.0)
        ci.draw_rect(ribbon_rect, COL_RIBBON, true)
        ci.draw_rect(ribbon_rect, COL_GOLD, false, 2.0)
        _draw_outlined_string(ci, gold_font, Vector2(ribbon_rect.position.x,
                        ribbon_rect.position.y + 8.0), title, 22, accent,
                        ribbon_w)

        # sottotitolo (solo DELETE: istruzione)
        var sub_y: float = card_pos.y + 94.0
        if _mode == Mode.DELETE:
                _draw_outlined_string(ci, font, Vector2(card_pos.x, sub_y),
                                I18n.t("save.delete_sub"), 17, COL_TEXT_DIM,
                                card_size.x)
                sub_y += 30.0
        else:
                sub_y += 12.0

        # righe degli slot
        var list_x: float = card_pos.x + (card_size.x - ROW_W) * 0.5
        for i in rows_n:
                _draw_row(ci, font, Rect2(list_x, sub_y + i * ROW_H,
                                ROW_W, ROW_H - 8.0), i)

        # footer: hint comandi / conferma elimina
        var footer: String
        if _mode == Mode.DELETE and _delete_confirm:
                footer = I18n.t("save.delete_confirm")
        else:
                footer = I18n.t("save.hint")
        var footer_col: Color = COL_DELETE if (_delete_confirm) else COL_TEXT_DIM
        _draw_outlined_string(ci, font, Vector2(card_pos.x,
                        card_pos.y + card_size.y - 40.0), footer, 16,
                        footer_col, card_size.x)


func _draw_row(ci: Control, font: Font, r: Rect2, idx: int) -> void:
        var s: Dictionary = _rows[idx] if idx < _rows.size() else {}
        var selected: bool = idx == _sel
        var is_delete_conf: bool = _delete_confirm and selected \
                        and _mode == Mode.DELETE
        # riga: pannello scuro + bordo oro/rosso
        ci.draw_rect(r, Color(0.10, 0.07, 0.04, 0.95) if selected
                        else Color(0.08, 0.05, 0.03, 0.85), true)
        var border_col: Color = COL_DELETE if is_delete_conf \
                        else (COL_GOLD if selected else COL_GOLD_DARK)
        ci.draw_rect(r, border_col, false, 2.0 if selected else 1.5)

        # testo: data/ora + livelli + personaggi (una riga, come richiesto)
        var chars: String = ""
        var names: Array = s.get("char_names", ["?"])
        if names.size() >= 2:
                chars = I18n.t("save.row_2p") % [str(s.get("saved_at", "")),
                                int(s.get("game_level", 1)),
                                int(s.get("player_level", 1)),
                                str(names[0]), str(names[1])]
        else:
                chars = I18n.t("save.row") % [str(s.get("saved_at", "")),
                                int(s.get("game_level", 1)),
                                int(s.get("player_level", 1)),
                                str(names[0] if names.size() > 0 else "?")]
        var label_col: Color = COL_TEXT_DIM
        if is_delete_conf:
                label_col = COL_DELETE
        elif selected:
                label_col = Color(1.0, 0.92, 0.55)
        _draw_outlined_string(ci, font, Vector2(r.position.x + 16.0,
                        r.position.y + 10.0), chars, 19, label_col,
                        r.size.x - 32.0)

        # rombi-freccia ai lati della riga selezionata
        if selected:
                var blink: float = 0.6 + 0.4 * sin(_t * 6.0)
                var col: Color = Color(border_col.r, border_col.g,
                                border_col.b, blink)
                _draw_diamond(ci, r.position + Vector2(14.0, r.size.y * 0.5),
                                7.0, col)
                _draw_diamond(ci, r.position + Vector2(r.size.x - 14.0,
                                r.size.y * 0.5), 7.0, col)


# ---------------------------------------------------------------------------
# Helper (mirror NewGamePlusCard)
# ---------------------------------------------------------------------------
func _draw_diamond(ci: Control, c: Vector2, r: float, col: Color) -> void:
        ci.draw_colored_polygon(PackedVector2Array([
                        c + Vector2(0, -r), c + Vector2(r, 0),
                        c + Vector2(0, r), c + Vector2(-r, 0)]), col)


## Testo con contorno nero a 4 offset, centrato dentro `width` da x.
func _draw_outlined_string(ci: Control, font: Font, at: Vector2,
                text: String, font_size: int, color: Color, width: float) -> void:
        var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER,
                        -1, font_size).x
        var pos := Vector2(at.x + (width - w) * 0.5, at.y + font_size)
        for off in [Vector2(-2, 0), Vector2(2, 0), Vector2(0, -2), Vector2(0, 2)]:
                ci.draw_string(font, Vector2(pos.x + off.x, pos.y + off.y), text,
                                HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.BLACK)
        ci.draw_string(font, pos, text,
                        HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
