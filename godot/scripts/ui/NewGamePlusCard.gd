## NewGamePlusCard.gd — TASK 105 (richiesta utente): NEW GAME PLUS.
## ============================================================
## Card in STILE "ARMI BONUS" (pattern BonusCardOverlay: pure-code
## CanvasLayer, legno scuro + rifiniture oro + nastro + angoli runici)
## che appare DOPO i titoli dei credits, sullo schermo "THANK YOU FOR
## PLAYING!", quando la campagna e' finita e resta almeno un tier NG+.
##
## Domanda (testo utente, localizzato):
##   "Vuoi continuare a giocare (new game plus)? Ricomincerai dal primo
##    livello di gioco senza perdere i tuoi upgrade accumulati ad una
##    difficoltà maggiore."
## Opzioni:
##   * SÌ  -> GameManager.begin_newgameplus() (tier 1 = NG+ / 2 = NG++,
##            progressione Level Up conservata, nemici +danno/+resistenza)
##   * NO  -> Ritorna al Menù Principale (comportamento pre-Task-105).
##
## Input: SU/GIÙ (frecce, action move_*, D-pad) per scegliere,
## INVIO/SPAZIO (action confirm, tasto A del joystick) per confermare.
## ESC non fa nulla: la scelta e' esplicita (niente NG+ perso per sbaglio).
## Il gioco NON e' in pausa: la card vive nei credits (niente gameplay
## attivo sotto), quindi niente get_tree().paused.
extends CanvasLayer

## Scelta del player: true = SÌ (inizia il tier NG+), false = NO (menu).
## Il host (CreditsScreen) reagisce e libera la card.
signal choice_made(accepted: bool)

const C = preload("res://scripts/core/GameConstants.gd")

# Palette (mirror BonusCardOverlay: legno scuro + oro + nastro rosso).
const COL_VEIL: Color = Color(0.0, 0.0, 0.02, 0.78)
const COL_WOOD: Color = Color(0.16, 0.10, 0.06, 0.97)
const COL_WOOD_LIGHT: Color = Color(0.27, 0.17, 0.09, 0.97)
const COL_GOLD: Color = Color(0.84, 0.66, 0.18)
const COL_GOLD_DARK: Color = Color(0.55, 0.41, 0.10)
const COL_TEXT: Color = Color(0.94, 0.88, 0.72)
const COL_TEXT_DIM: Color = Color(0.72, 0.66, 0.52)
const COL_RIBBON: Color = Color(0.45, 0.05, 0.05, 0.95)
## Accento del tier: oro caldo per NG+, brace rossa per NG++.
const COL_ACCENT_BY_TIER: Dictionary = {
        1: Color(1.0, 0.84, 0.25),
        2: Color(1.0, 0.52, 0.30),
}

## Tier che si sta PROPONENDO (1 = NG+, 2 = NG++) e progressione che
## verrebbe conservata (per la riga "LIVELLO n CONSERVATO").
var _next_tier: int = 1
var _kept_level: int = 1

var _choice: int = 0          # 0 = SÌ, 1 = NO
var _confirm_armed: bool = false
var _t: float = 0.0
var _panel: Control = null

# Edge detection D-pad (pattern BonusScreen/LevelUpOverlay).
var _prev_joy_btns: Dictionary = {}


func setup(next_tier: int, kept_level: int) -> void:
        _next_tier = clampi(next_tier, 1, C.NEWGAMEPLUS_MAX_TIER)
        _kept_level = maxi(1, kept_level)


func _ready() -> void:
        layer = 30
        process_mode = Node.PROCESS_MODE_ALWAYS
        _panel = Control.new()
        _panel.name = "NewGamePlusCardPanel"
        _panel.set_anchors_preset(Control.PRESET_FULL_RECT)
        _panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _panel.draw.connect(_draw_panel.bind(_panel))
        add_child(_panel)
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.MENU_SELECT)


# ---------------------------------------------------------------------------
# Input (tastiera + action + joystick D-pad/A; la conferma richiede un
# rilascio preliminare — gate anti-ghost del codebase)
# ---------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
        _t += delta
        # --- navigazione SÌ / NO (action move_* = frecce + asse + D-pad) ---
        if Input.is_action_just_pressed("move_up"):
                _move_choice(-1)
        elif Input.is_action_just_pressed("move_down"):
                _move_choice(1)
        _poll_joystick()
        # --- conferma: INVIO (action confirm) / SPAZIO (action jump) /
        # tasto A del joystick. Gate anti-ghost: serve un RILASCIO preliminare
        # (pattern bonus card / LevelUpOverlay) perché il tasto che ha
        # scavalcato i credits potrebbe essere ancora tenuto.
        var confirm: bool = Input.is_action_just_pressed("confirm") \
                        or Input.is_action_just_pressed("jump") \
                        or _joy_confirm_edge()
        if not confirm:
                _confirm_armed = true
        elif _confirm_armed:
                _confirm_armed = false
                _confirm()
        _panel.queue_redraw()

func _move_choice(dir: int) -> void:
        _choice = clampi(_choice + dir, 0, 1)
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.MENU_SELECT)


## D-pad del primo pad collegato (nei credits non c'e' un ConfigJoy attivo:
## fallback dpad del pad 0; A = conferma, come i menu del gioco).
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
                        _move_choice(int(dpad[btn]))

func _joy_confirm_edge() -> bool:
        var pads: Array = Input.get_connected_joypads()
        if pads.is_empty():
                return false
        # A (bottom action) oppure START, come i menu; edge-detected col
        # latch (_prev_joy_btns), così tenere premuto conferma UNA volta.
        var joy: int = int(pads[0])
        for btn in [JOY_BUTTON_A, JOY_BUTTON_START]:
                var pressed: bool = Input.is_joy_button_pressed(joy, btn)
                var was: bool = bool(_prev_joy_btns.get(btn, false))
                _prev_joy_btns[btn] = pressed
                if pressed and not was:
                        return true
        return false


func _confirm() -> void:
        var accepted: bool = _choice == 0
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.MENU_CONFIRM)
        choice_made.emit(accepted)
        queue_free()


# ---------------------------------------------------------------------------
# Rendering (mirror BonusCardOverlay._draw_card)
# ---------------------------------------------------------------------------
func _draw_panel(ci: Control) -> void:
        var vp: Vector2 = ci.get_viewport_rect().size
        var font: Font = ThemeDB.fallback_font

        # velo scuro sui credits
        ci.draw_rect(Rect2(Vector2.ZERO, vp), COL_VEIL, true)

        # card centrata (min tra 780x640 e il 92% della viewport)
        var card_size := Vector2(minf(780.0, vp.x * 0.92), minf(640.0, vp.y * 0.94))
        var card_pos := (vp - card_size) * 0.5
        var accent: Color = COL_ACCENT_BY_TIER.get(_next_tier, COL_GOLD)

        # --- cornice: legno scuro + doppio bordo oro + angoli runici ---
        ci.draw_rect(Rect2(card_pos, card_size), COL_WOOD, true)
        ci.draw_rect(Rect2(card_pos + Vector2(6, 6),
                        card_size - Vector2(12, 12)), COL_WOOD_LIGHT, true)
        ci.draw_rect(Rect2(card_pos + Vector2(10, 10),
                        card_size - Vector2(20, 20)), COL_WOOD, true)
        ci.draw_rect(Rect2(card_pos + Vector2(10, 10),
                        card_size - Vector2(20, 20)), COL_GOLD, false, 3.0)
        ci.draw_rect(Rect2(card_pos + Vector2(18, 18),
                        card_size - Vector2(36, 36)), COL_GOLD_DARK, false, 1.5)
        var pulse := 0.5 + 0.5 * sin(_t * 3.0)
        var corners: Array[Vector2] = [
                card_pos + Vector2(26, 26),
                card_pos + Vector2(card_size.x - 26, 26),
                card_pos + Vector2(26, card_size.y - 26),
                card_pos + Vector2(card_size.x - 26, card_size.y - 26),
        ]
        for corner in corners:
                _draw_diamond(ci, corner, 9.0 + 2.0 * pulse, accent)

        # --- nastro col titolo del tier in alto ---
        var tier_name: String = I18n.t("ngp.title") if _next_tier == 1 \
                        else I18n.t("ngp.title2")
        var ribbon_w := 340.0
        var ribbon_rect := Rect2(card_pos.x + (card_size.x - ribbon_w) * 0.5,
                        card_pos.y + 34.0, ribbon_w, 36.0)
        ci.draw_rect(ribbon_rect, COL_RIBBON, true)
        ci.draw_rect(ribbon_rect, COL_GOLD, false, 2.0)
        _draw_outlined_string(ci, font, Vector2(ribbon_rect.position.x,
                        ribbon_rect.position.y + 8.0), tier_name,
                        22, accent, ribbon_w)

        # sottolineatura decorativa
        var ul_w := 320.0
        var ul_x := card_pos.x + (card_size.x - ul_w) * 0.5
        ci.draw_line(Vector2(ul_x, card_pos.y + 92.0),
                        Vector2(ul_x + ul_w, card_pos.y + 92.0), COL_GOLD, 2.0)
        ci.draw_circle(Vector2(ul_x - 8, card_pos.y + 92.0), 4.0, COL_GOLD)
        ci.draw_circle(Vector2(ul_x + ul_w + 8, card_pos.y + 92.0), 4.0, COL_GOLD)

        # --- emblema centrale: teschio d'oro su medaglione + spade incrociate ---
        var emblem_c := card_pos + Vector2(card_size.x * 0.5, 172.0)
        _draw_emblem(ci, emblem_c, accent)

        # --- domanda (testo utente, wrap su più righe, centrato) ---
        var question: String = I18n.t("ngp.question") if _next_tier == 1 \
                        else I18n.t("ngp.question2")
        var text_w := card_size.x - 120.0
        var lines := _wrap_text(font, question, text_w, 19)
        var ly := card_pos.y + 236.0
        for ln in lines:
                ci.draw_string(font, Vector2(card_pos.x + 60.0, ly), ln,
                                HORIZONTAL_ALIGNMENT_CENTER, text_w, 19, COL_TEXT)
                ly += 26.0

        # --- chip DANNO / RESISTENZA del tier proposto ---
        var dmg_pct: int = int(round((C.NEWGAMEPLUS_DAMAGE_MULTS[_next_tier] - 1.0) * 100.0))
        var res_pct: int = int(round((C.NEWGAMEPLUS_RESIST_MULTS[_next_tier] - 1.0) * 100.0))
        var chip_w := 330.0
        var chip_y := card_pos.y + 340.0
        _draw_chip(ci, Rect2(card_pos.x + 40.0, chip_y, chip_w, 32.0),
                        I18n.t("ngp.chip_damage") % dmg_pct)
        _draw_chip(ci, Rect2(card_pos.x + card_size.x - 40.0 - chip_w, chip_y,
                        chip_w, 32.0), I18n.t("ngp.chip_resist") % res_pct)

        # --- riga del livello conservato (l'upgrade che NON si perde) ---
        _draw_outlined_string(ci, font, Vector2(card_pos.x, card_pos.y + 402.0),
                        I18n.t("ngp.chip_kept") % _kept_level, 20, accent,
                        card_size.x)

        # --- opzioni SÌ / NO ---
        var opt_w := 560.0
        var opt_x := card_pos.x + (card_size.x - opt_w) * 0.5
        _draw_option(ci, Rect2(opt_x, card_pos.y + 436.0, opt_w, 54.0),
                        I18n.t("ngp.yes"), "", 0)
        _draw_option(ci, Rect2(opt_x, card_pos.y + 500.0, opt_w, 54.0),
                        I18n.t("ngp.no"), I18n.t("ngp.no_hint"), 1)

        # --- footer: hint comandi ---
        _draw_outlined_string(ci, font, Vector2(card_pos.x, card_pos.y + card_size.y - 34.0),
                        I18n.t("ngp.hint"), 16, COL_TEXT_DIM, card_size.x)


## Un'opzione del menu SÌ/NO: pannello scuro + bordo (oro se SELEZIONATA,
## legno scuro se no) + rombi-freccia ai lati di quella selezionata.
## `sub` è il suggerimento piccolo a destra del testo principale (usato dal NO).
func _draw_option(ci: Control, r: Rect2, text: String, sub: String, idx: int) -> void:
        var selected: bool = _choice == idx
        var font: Font = ThemeDB.fallback_font
        ci.draw_rect(r, Color(0.10, 0.07, 0.04, 0.95) if selected
                        else Color(0.08, 0.05, 0.03, 0.85), true)
        ci.draw_rect(r, COL_GOLD if selected else COL_GOLD_DARK, false,
                        2.0 if selected else 1.5)
        var label_col: Color = Color(1.0, 0.92, 0.55) if selected else COL_TEXT_DIM
        var base_y: float = r.position.y + r.size.y * 0.5 + 8.0
        if sub.is_empty():
                _draw_outlined_string(ci, font, Vector2(r.position.x, base_y - 12.0),
                                text, 26, label_col, r.size.x)
        else:
                # testo principale a sinistra + suggerimento a destra (NO)
                _draw_outlined_string(ci, font, Vector2(r.position.x + 60.0, base_y - 12.0),
                                text, 26, label_col, 140.0)
                _draw_outlined_string(ci, font, Vector2(r.position.x + 200.0, base_y - 8.0),
                                sub, 18, COL_TEXT_DIM, r.size.x - 240.0)
        if selected:
                # rombi-freccia pulsanti ai lati della riga selezionata
                var blink: float = 0.6 + 0.4 * sin(_t * 6.0)
                var accent: Color = COL_ACCENT_BY_TIER.get(_next_tier, COL_GOLD)
                var col: Color = Color(accent.r, accent.g, accent.b, blink)
                _draw_diamond(ci, r.position + Vector2(26.0, r.size.y * 0.5), 8.0, col)
                _draw_diamond(ci, r.position + Vector2(r.size.x - 26.0, r.size.y * 0.5), 8.0, col)


## Emblema della card: medaglione scuro con anelli oro, SPADE INCROCIATE
## dietro un TESCHIO dorato (fantasy/horror arcade, coerente col bestiario).
## Procedurale al 100% (niente asset da rigenerare).
func _draw_emblem(ci: Control, c: Vector2, accent: Color) -> void:
        # medaglione
        ci.draw_circle(c, 58.0, Color(0.08, 0.06, 0.04, 0.95))
        ci.draw_arc(c, 58.0, 0.0, TAU, 40, COL_GOLD_DARK, 2.0, true)
        ci.draw_arc(c, 52.0, _t * 1.2, _t * 1.2 + PI * 1.2, 24,
                        Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b, 0.5), 3.0, true)
        # spade incrociate (dietro il teschio): due lame diagonali con
        # guardia e pomo d'elsa
        for s in [-1, 1]:
                var dir := Vector2(s, -1.0).normalized()
                var tip := c + dir * 52.0
                var hilt := c - dir * 34.0
                ci.draw_line(hilt, tip, Color(0.72, 0.66, 0.50), 4.0)
                ci.draw_circle(tip, 2.6, Color(0.85, 0.80, 0.62))
                # guardia perpendicolare alla lama
                var perp := Vector2(-dir.y, dir.x)
                ci.draw_line(hilt - perp * 10.0, hilt + perp * 10.0, COL_GOLD_DARK, 3.0)
                ci.draw_circle(hilt, 3.4, COL_GOLD_DARK)
        # teschio: cranio (cerchio) + mandibola (rettangolo smussato)
        var bone: Color = Color(0.88, 0.84, 0.70)
        var bone_dim: Color = Color(0.70, 0.65, 0.52)
        var skull_c := c + Vector2(0.0, -4.0)
        ci.draw_circle(skull_c, 22.0, bone)
        ci.draw_rect(Rect2(skull_c + Vector2(-13.0, 12.0), Vector2(26.0, 12.0)), bone, true)
        # orbite
        var eye_off := Vector2(8.5, -2.0)
        ci.draw_circle(skull_c - eye_off, 5.2, Color(0.07, 0.05, 0.03))
        ci.draw_circle(skull_c + Vector2(eye_off.x, eye_off.y), 5.2, Color(0.07, 0.05, 0.03))
        # pupille accese del colore del tier (teschio "posseduto")
        var glow: float = 0.6 + 0.4 * sin(_t * 5.0)
        ci.draw_circle(skull_c - eye_off, 2.0, Color(accent.r, accent.g, accent.b, glow))
        ci.draw_circle(skull_c + Vector2(eye_off.x, eye_off.y), 2.0,
                        Color(accent.r, accent.g, accent.b, glow))
        # naso a triangolo
        ci.draw_colored_polygon(PackedVector2Array([
                        skull_c + Vector2(0.0, 6.0),
                        skull_c + Vector2(-3.0, 11.0),
                        skull_c + Vector2(3.0, 11.0)]), Color(0.07, 0.05, 0.03))
        # denti (linee verticali sulla mandibola)
        for i in 4:
                var tx: float = skull_c.x - 9.0 + float(i) * 6.0
                ci.draw_line(Vector2(tx, skull_c.y + 14.0),
                                Vector2(tx, skull_c.y + 22.0), bone_dim, 1.5)
        # crepa sul cranio (segno dei molti cycle di gioco)
        ci.draw_line(skull_c + Vector2(-14.0, -14.0), skull_c + Vector2(-6.0, -4.0),
                        bone_dim, 1.5)


# ---------------------------------------------------------------------------
# Helper (mirror BonusCardOverlay / CreditsScreen)
# ---------------------------------------------------------------------------
func _draw_chip(ci: Control, r: Rect2, text: String) -> void:
        ci.draw_rect(r, Color(0.1, 0.07, 0.04, 0.95), true)
        ci.draw_rect(r, COL_GOLD_DARK, false, 1.5)
        ci.draw_string(ThemeDB.fallback_font, r.position + Vector2(12, 22),
                        text, HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 24.0, 16, COL_TEXT)


func _wrap_text(font: Font, text: String, max_w: float, size: int) -> Array:
        var words := text.split(" ")
        var lines: Array = []
        var cur := ""
        for w in words:
                var trial := cur + (" " if cur != "" else "") + w
                if font.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT,
                                -1, size).x > max_w and cur != "":
                        lines.append(cur)
                        cur = w
                else:
                        cur = trial
        if cur != "":
                lines.append(cur)
        return lines


func _draw_diamond(ci: Control, c: Vector2, r: float, col: Color) -> void:
        ci.draw_colored_polygon(PackedVector2Array([
                        c + Vector2(0, -r), c + Vector2(r, 0),
                        c + Vector2(0, r), c + Vector2(-r, 0)]), col)


## Testo con contorno nero a 4 offset (pattern CreditsScreen) centrato
## dentro `width` a partire da x.
func _draw_outlined_string(ci: Control, font: Font, at: Vector2, text: String,
                font_size: int, color: Color, width: float) -> void:
        var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER,
                        -1, font_size).x
        var pos := Vector2(at.x + (width - w) * 0.5, at.y + font_size)
        for off in [Vector2(-2, 0), Vector2(2, 0), Vector2(0, -2), Vector2(0, 2)]:
                ci.draw_string(font, Vector2(pos.x + off.x, pos.y + off.y), text,
                                HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.BLACK)
        ci.draw_string(font, pos, text,
                        HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
