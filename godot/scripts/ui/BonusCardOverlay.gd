## BonusCardOverlay.gd — TASK 51 (richiesta utente): CARD DEL BONUS alla
## PRIMA raccolta/equipaggiamento.
## ============================================================
## Quando un player raccoglie un bonus particolare (martello, dinamite,
## bastone del fulmine, pergamene, stivali, pozione, mina, calice,
## statua del cavaliere...) per la PRIMA volta in una partita, il gioco
## si METTE IN PAUSA e mostra al centro dello schermo una card in stile
## "arma bonus post-boss" con:
##   * nome del bonus, effetto, numero di usi, danno;
##   * icona rappresentativa stilizzata (fantasy);
##   * un piccolo "video" animato IN LOOP che mostra l'utilizzo e
##     l'effetto del bonus (es. martello che sfonda il muro e uccide il
##     nemico, fulmine che folgora, dinamite lanciata che esplode...).
## La card si chiude TENENDO PREMUTO il tasto di fuoco per 1 secondo
## (barra di riempimento; il tap singolo non chiude). Se lo stesso bonus
## viene ripreso piu' avanti nella partita, la card NON riappare
## (memoria per-run in GameManager.bonus_cards_seen).
##
## Pure-code CanvasLayer (pattern BonusScreen/PauseOverlay): nessun .tscn,
## il controller lo crea con BonusCardOverlay.new() + setup() e ascolta
## card_closed. Layer 26 (sopra HUD 10 e pausa 20, sotto bonus screen 30).
extends CanvasLayer

## Emitted quando il player ha tenuto premuto il fuoco abbastanza a lungo:
## il controller riavvia il gioco (pause off) e libera la card.
signal card_closed

const C = preload("res://scripts/core/GameConstants.gd")
const Collectibles = preload("res://scripts/items/Collectibles.gd")

## Durata della pressione di fuoco richiesta per chiudere (richiesta
## utente: "tiene premuto per 1 secondo il fire e la schermata sparisce").
const HOLD_CLOSE_MS: float = 1000.0

# --- Stato ---
var bonus_kind: int = Collectibles.Kind.HAMMER
var player_num: int = 1          # chi ha raccolto (per il tasto di fuoco)
var _t: float = 0.0              # tempo animazioni (demo in loop)
var _hold_ms: float = 0.0
var _hold_frac: float = 0.0
var _closing: bool = false

# Testi risolti via I18n alla setup (EN/IT).
var _title: String = ""
var _fx_text: String = ""
var _uses_text: String = ""
var _dmg_text: String = ""
var _hold_text: String = ""
var _demo_text: String = ""
var _new_text: String = ""

# Pannello di disegno (Control full-rect figlio del layer).
var _panel: Control = null

# Colori card (stile reliquia post-boss: legno scuro + oro + rosso sangue).
const COL_WOOD := Color(0.16, 0.10, 0.06, 0.97)
const COL_WOOD_LIGHT := Color(0.27, 0.17, 0.09, 0.97)
const COL_GOLD := Color(0.84, 0.66, 0.18)
const COL_GOLD_DARK := Color(0.55, 0.41, 0.10)
const COL_TEXT := Color(0.94, 0.88, 0.72)
const COL_TEXT_DIM := Color(0.72, 0.66, 0.52)


# ============================================================================
# Setup + lifecycle
# ============================================================================
func setup(kind: int, pnum: int) -> void:
        bonus_kind = kind
        player_num = 1 if pnum != 2 else 2
        _title = I18n.t(_name_key())
        _fx_text = I18n.t(_fx_key())
        _uses_text = I18n.t(_uses_key())
        _dmg_text = I18n.t(_dmg_key())
        _hold_text = I18n.t("bonuscard.hold")
        _demo_text = I18n.t("bonuscard.demo")
        _new_text = I18n.t("bonuscard.new")


func _ready() -> void:
        layer = 26
        process_mode = Node.PROCESS_MODE_ALWAYS
        _panel = Control.new()
        _panel.name = "BonusCardPanel"
        _panel.set_anchors_preset(Control.PRESET_FULL_RECT)
        _panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _panel.draw.connect(_draw_card)
        add_child(_panel)
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.RELIC_PICKUP)


func _physics_process(delta: float) -> void:
        if _closing:
                return
        _t += delta
        _panel.queue_redraw()
        # --- chiusura: TENENDO PREMUTO il fuoco del player raccoglitore ---
        var fire_held := _owner_fire_held()
        if fire_held:
                _hold_ms += delta * 1000.0
        else:
                _hold_ms = 0.0
        _hold_frac = clampf(_hold_ms / HOLD_CLOSE_MS, 0.0, 1.0)
        if _hold_ms >= HOLD_CLOSE_MS:
                _closing = true
                if AudioManager:
                        AudioManager.play_sound(
                                        AudioManager.SoundType.MENU_CONFIRM)
                card_closed.emit()


## Fuoco del player che ha raccolto il bonus (tastiera + joystick,
## mirror BonusScreen._poll_current_chooser).
func _owner_fire_held() -> bool:
        var held := false
        if player_num == 1:
                held = Input.is_action_pressed("shoot") \
                                or Input.is_action_pressed("confirm")
                var joy := _resolve_p1_joy()
                if not held and joy >= 0:
                        var btn: int = ConfigManager.joy_shoot() if ConfigManager else -1
                        if btn < 0:
                                btn = JOY_BUTTON_B
                        held = Input.is_joy_button_pressed(joy, btn)
        else:
                held = Input.is_action_pressed("p2_shoot")
                var joy2 := _resolve_p2_joy()
                if not held and joy2 >= 0:
                        var btn2: int = ConfigManager.joy2_shoot() if ConfigManager else -1
                        if btn2 < 0:
                                btn2 = JOY_BUTTON_B
                        held = Input.is_joy_button_pressed(joy2, btn2)
        return held


func _resolve_p1_joy() -> int:
        var pads: Array = Input.get_connected_joypads()
        if ConfigManager and ConfigManager.joy_id() >= 0 \
                        and pads.has(ConfigManager.joy_id()):
                return ConfigManager.joy_id()
        if pads.size() > 0:
                return pads[0]
        return -1


func _resolve_p2_joy() -> int:
        var pads: Array = Input.get_connected_joypads()
        var p1: int = _resolve_p1_joy()
        if ConfigManager and ConfigManager.joy2_id() >= 0 \
                        and pads.has(ConfigManager.joy2_id()) \
                        and ConfigManager.joy2_id() != p1:
                return ConfigManager.joy2_id()
        for pad_id in pads:
                if pad_id != p1:
                        return pad_id
        return -1


# ============================================================================
# Chiavi i18n per tipo di bonus
# ============================================================================
func _name_key() -> String:
        match bonus_kind:
                Collectibles.Kind.HAMMER: return "bonuscard.name.hammer"
                Collectibles.Kind.DYNAMITE: return "bonuscard.name.dynamite"
                Collectibles.Kind.SCEPTER: return "bonuscard.name.scepter"
                Collectibles.Kind.SPEED_BOOTS: return "bonuscard.name.boots"
                Collectibles.Kind.POTION: return "bonuscard.name.potion"
                Collectibles.Kind.FREEZE_SCROLL: return "bonuscard.name.freeze"
                Collectibles.Kind.QUAKE_SCROLL: return "bonuscard.name.quake"
                Collectibles.Kind.CHASM_SCROLL: return "bonuscard.name.chasm"
                Collectibles.Kind.MINE: return "bonuscard.name.mine"
                Collectibles.Kind.CHALICE: return "bonuscard.name.chalice"
                Collectibles.Kind.KNIGHT_STATUE: return "bonuscard.name.knight"
        return "bonuscard.name.hammer"


func _fx_key() -> String:
        var k := _name_key()
        return k.replace("bonuscard.name.", "bonuscard.fx.")


func _uses_key() -> String:
        match bonus_kind:
                Collectibles.Kind.HAMMER: return "bonuscard.uses.two"
                Collectibles.Kind.DYNAMITE: return "bonuscard.uses.one"
                Collectibles.Kind.SCEPTER: return "bonuscard.uses.5strikes"
                Collectibles.Kind.SPEED_BOOTS: return "bonuscard.uses.perm"
                Collectibles.Kind.POTION: return "bonuscard.uses.one"
                Collectibles.Kind.FREEZE_SCROLL: return "bonuscard.uses.2shots"
                Collectibles.Kind.QUAKE_SCROLL: return "bonuscard.uses.instant"
                Collectibles.Kind.CHASM_SCROLL: return "bonuscard.uses.3waves"
                Collectibles.Kind.MINE: return "bonuscard.uses.one"
                Collectibles.Kind.CHALICE: return "bonuscard.uses.one"
                Collectibles.Kind.KNIGHT_STATUE: return "bonuscard.uses.one"
        return "bonuscard.uses.one"


func _dmg_key() -> String:
        match bonus_kind:
                Collectibles.Kind.HAMMER: return "bonuscard.dmg.high"
                Collectibles.Kind.DYNAMITE: return "bonuscard.dmg.blast"
                Collectibles.Kind.SCEPTER: return "bonuscard.dmg.fry"
                Collectibles.Kind.SPEED_BOOTS: return "bonuscard.dmg.none"
                Collectibles.Kind.POTION: return "bonuscard.dmg.none"
                Collectibles.Kind.FREEZE_SCROLL: return "bonuscard.dmg.kill"
                Collectibles.Kind.QUAKE_SCROLL: return "bonuscard.dmg.half"
                Collectibles.Kind.CHASM_SCROLL: return "bonuscard.dmg.kill"
                Collectibles.Kind.MINE: return "bonuscard.dmg.boss"
                Collectibles.Kind.CHALICE: return "bonuscard.dmg.burn"
                Collectibles.Kind.KNIGHT_STATUE: return "bonuscard.dmg.kill"
        return "bonuscard.dmg.none"


# ============================================================================
# Rendering della card
# ============================================================================
func _draw_card() -> void:
        var vp: Vector2 = _panel.get_viewport_rect().size
        var font: Font = ThemeDB.fallback_font

        # velo scuro sul gioco in pausa
        _panel.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.0, 0.0, 0.02, 0.72), true)

        # card centrata (min tra 780x680 e il 92% della viewport)
        var card_size := Vector2(minf(780.0, vp.x * 0.92), minf(690.0, vp.y * 0.94))
        var card_pos := (vp - card_size) * 0.5

        # --- cornice: legno scuro + doppio bordo oro + angoli runici ---
        _panel.draw_rect(Rect2(card_pos, card_size), COL_WOOD, true)
        _panel.draw_rect(Rect2(card_pos + Vector2(6, 6),
                        card_size - Vector2(12, 12)), COL_WOOD_LIGHT, true)
        _panel.draw_rect(Rect2(card_pos + Vector2(10, 10),
                        card_size - Vector2(20, 20)), COL_WOOD, true)
        _panel.draw_rect(Rect2(card_pos + Vector2(10, 10),
                        card_size - Vector2(20, 20)), COL_GOLD, false, 3.0)
        _panel.draw_rect(Rect2(card_pos + Vector2(18, 18),
                        card_size - Vector2(36, 36)), COL_GOLD_DARK, false, 1.5)
        # angoli: rombi dorati pulsanti
        var pulse := 0.5 + 0.5 * sin(_t * 3.0)
        var corners: Array[Vector2] = [
                card_pos + Vector2(26, 26),
                card_pos + Vector2(card_size.x - 26, 26),
                card_pos + Vector2(26, card_size.y - 26),
                card_pos + Vector2(card_size.x - 26, card_size.y - 26),
        ]
        for corner in corners:
                _draw_diamond(_panel, corner, 9.0 + 2.0 * pulse, COL_GOLD)

        # --- nastro "NUOVO BONUS!" in alto ---
        var ribbon_w := 240.0
        var ribbon_rect := Rect2(card_pos.x + (card_size.x - ribbon_w) * 0.5,
                        card_pos.y + 34.0, ribbon_w, 34.0)
        _panel.draw_rect(ribbon_rect, Color(0.45, 0.05, 0.05, 0.95), true)
        _panel.draw_rect(ribbon_rect, COL_GOLD, false, 2.0)
        _panel.draw_string(font, ribbon_rect.position
                        + Vector2(14, 24.0), _new_text,
                        HORIZONTAL_ALIGNMENT_CENTER, ribbon_w - 28.0, 19,
                        Color(1.0, 0.85, 0.55))

        # --- titolo (nome del bonus) ---
        _panel.draw_string(font, Vector2(card_pos.x, card_pos.y + 116.0),
                        _title, HORIZONTAL_ALIGNMENT_CENTER, card_size.x, 34,
                        Color(1.0, 0.9, 0.45))
        # sottolineatura decorativa
        var ul_w := 320.0
        var ul_x := card_pos.x + (card_size.x - ul_w) * 0.5
        _panel.draw_line(Vector2(ul_x, card_pos.y + 132.0),
                        Vector2(ul_x + ul_w, card_pos.y + 132.0), COL_GOLD, 2.0)
        _panel.draw_circle(Vector2(ul_x - 8, card_pos.y + 132.0), 4.0, COL_GOLD)
        _panel.draw_circle(Vector2(ul_x + ul_w + 8, card_pos.y + 132.0), 4.0, COL_GOLD)

        # --- icona (a sinistra, box 110x110) ---
        var icon_c := card_pos + Vector2(78.0, 196.0)
        _panel.draw_circle(icon_c, 56.0, Color(0.08, 0.06, 0.04, 0.9))
        _panel.draw_arc(icon_c, 56.0, 0.0, TAU, 40, COL_GOLD_DARK, 2.0, true)
        _panel.draw_arc(icon_c, 50.0, _t * 1.2, _t * 1.2 + PI * 1.2, 24,
                        Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b, 0.5), 3.0, true)
        _draw_icon(_panel, icon_c)

        # --- testo effetto (destra dell'icona, wrap su 3 righe) ---
        var text_x := card_pos.x + 160.0
        var text_w := card_size.x - 160.0 - 34.0
        var lines := _wrap_text(font, _fx_text, text_w, 19)
        var ly := card_pos.y + 172.0
        for ln in lines:
                _panel.draw_string(font, Vector2(text_x, ly), ln,
                                HORIZONTAL_ALIGNMENT_LEFT, text_w, 19, COL_TEXT)
                ly += 25.0

        # --- chip USI / DANNO ---
        var chip_y := card_pos.y + 286.0
        _draw_chip(_panel, Rect2(text_x, chip_y, 250.0, 30.0),
                        "%s: %s" % [I18n.t("bonuscard.uses"), _uses_text])
        _draw_chip(_panel, Rect2(text_x + 262.0, chip_y, 250.0, 30.0),
                        "%s: %s" % [I18n.t("bonuscard.damage"), _dmg_text])

        # --- pannello DEMO ("COME FUNZIONA") ---
        var demo_lab_y := card_pos.y + 336.0
        _panel.draw_string(font, Vector2(card_pos.x, demo_lab_y), _demo_text,
                        HORIZONTAL_ALIGNMENT_CENTER, card_size.x, 17, COL_TEXT_DIM)
        var demo_rect := Rect2(card_pos.x + 30.0, demo_lab_y + 12.0,
                        card_size.x - 60.0, card_size.y - demo_lab_y - 106.0)
        # cornice schermo demo
        _panel.draw_rect(demo_rect, Color(0.04, 0.03, 0.05, 0.98), true)
        _panel.draw_rect(demo_rect, COL_GOLD_DARK, false, 2.0)
        _draw_demo(_panel, demo_rect, _t)

        # --- footer: testo hold + barra di riempimento 1s ---
        var foot_y := card_pos.y + card_size.y - 52.0
        _panel.draw_string(font, Vector2(card_pos.x, foot_y), _hold_text,
                        HORIZONTAL_ALIGNMENT_CENTER, card_size.x, 18,
                        Color(1.0, 0.85, 0.6) if _hold_frac <= 0.0
                                        else Color(0.6, 1.0, 0.6))
        var bar_w := 340.0
        var bar_x := card_pos.x + (card_size.x - bar_w) * 0.5
        var bar_y := foot_y + 10.0
        _panel.draw_rect(Rect2(bar_x, bar_y, bar_w, 12.0),
                        Color(0.1, 0.08, 0.05), true)
        _panel.draw_rect(Rect2(bar_x, bar_y, bar_w, 12.0), COL_GOLD_DARK, false, 1.5)
        if _hold_frac > 0.0:
                _panel.draw_rect(Rect2(bar_x, bar_y, bar_w * _hold_frac, 12.0),
                                Color(0.45, 0.95, 0.35), true)


func _draw_chip(ci: Control, r: Rect2, text: String) -> void:
        ci.draw_rect(r, Color(0.1, 0.07, 0.04, 0.95), true)
        ci.draw_rect(r, COL_GOLD_DARK, false, 1.5)
        ci.draw_string(ThemeDB.fallback_font, r.position + Vector2(10, 21),
                        text, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 16.0, 16,
                        COL_TEXT)


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


# ============================================================================
# ICONE — TASK 55: PNG PixelLab-first (item rigenerati Task 53 + pergamene
# Task 55), con pulse "respirato". Fallback: disegno procedurale Task 51d.
# ============================================================================
## Mapping kind -> PNG dell'item PixelLab (coerenza col pickup a terra).
const ICON_PNG_BY_KIND: Dictionary = {
        Collectibles.Kind.HAMMER: "res://assets/sprites/collectibles/item_hammer.png",
        Collectibles.Kind.DYNAMITE: "res://assets/sprites/collectibles/item_dynamite.png",
        Collectibles.Kind.SCEPTER: "res://assets/sprites/collectibles/item_scepter.png",
        Collectibles.Kind.SPEED_BOOTS: "res://assets/sprites/collectibles/item_speedboots.png",
        Collectibles.Kind.POTION: "res://assets/sprites/collectibles/item_potion.png",
        Collectibles.Kind.MINE: "res://assets/sprites/collectibles/item_mine.png",
        Collectibles.Kind.CHALICE: "res://assets/sprites/collectibles/item_chalice.png",
        Collectibles.Kind.KNIGHT_STATUE: "res://assets/sprites/collectibles/item_knight_statue.png",
        Collectibles.Kind.QUAKE_SCROLL: "res://assets/sprites/parchment/quake_scroll.png",
        Collectibles.Kind.CHASM_SCROLL: "res://assets/sprites/parchment/chasm_scroll.png",
        Collectibles.Kind.FREEZE_SCROLL: "res://assets/sprites/parchment/freeze_scroll.png",
}

static var _icon_tex_cache: Dictionary = {}

static func _icon_texture(kind: int) -> Texture2D:
        if _icon_tex_cache.has(kind):
                return _icon_tex_cache[kind]
        var tex: Texture2D = null
        var path: String = ICON_PNG_BY_KIND.get(kind, "")
        if not path.is_empty():
                var abs_path: String = ProjectSettings.globalize_path(path)
                if FileAccess.file_exists(abs_path):
                        var img := Image.new()
                        if img.load(abs_path) == OK:
                                tex = ImageTexture.create_from_image(img)
        _icon_tex_cache[kind] = tex
        return tex


func _draw_icon(ci: Control, c: Vector2) -> void:
        var t := _t
        # --- TASK 55: PNG PixelLab con pulse respirato (fallback proc sotto) ---
        var png_tex: Texture2D = _icon_texture(bonus_kind)
        if png_tex != null:
                var breathe: float = 1.0 + sin(t * 2.2) * 0.05
                var w: float = 104.0 * breathe
                ci.draw_texture_rect(png_tex,
                        Rect2(c - Vector2(w * 0.5, w * 0.5), Vector2(w, w)), false)
                return
        match bonus_kind:
                Collectibles.Kind.HAMMER:
                        # Mjolnir: manico + testa squadrata + scintille
                        var sway := sin(t * 2.0) * 0.12
                        ci.draw_line(c + Vector2(-14, 26), c + Vector2(14, -18),
                                        Color(0.35, 0.22, 0.1), 7.0)
                        var head_c := c + Vector2(16, -22)
                        ci.draw_rect(Rect2(head_c - Vector2(18, 12), Vector2(36, 24)),
                                        Color(0.62, 0.65, 0.72))
                        ci.draw_rect(Rect2(head_c - Vector2(18, 12), Vector2(36, 24)),
                                        Color(0.25, 0.28, 0.35), false, 2.0)
                        for k in range(3):
                                var a := t * 4.0 + k * TAU / 3.0
                                ci.draw_circle(head_c + Vector2(cos(a), sin(a)) * 34.0,
                                                2.5, Color(0.6, 0.85, 1.0))
                Collectibles.Kind.DYNAMITE:
                        # tre candelotti rossi + miccia con scintilla
                        for k in range(3):
                                var off := Vector2((k - 1) * 13.0, (k - 1) * 3.0)
                                ci.draw_rect(Rect2(c + off - Vector2(6, 22), Vector2(12, 44)),
                                                Color(0.72, 0.16, 0.1))
                                ci.draw_rect(Rect2(c + off - Vector2(6, 2), Vector2(12, 6)),
                                                Color(0.9, 0.75, 0.4))
                        var spark := c + Vector2(10, -30) + Vector2(sin(t * 20.0) * 3, 0)
                        ci.draw_circle(spark, 4.0 + 2.0 * sin(t * 25.0), Color(1.0, 0.85, 0.3))
                Collectibles.Kind.SCEPTER:
                        # bastone con gemma elettrica
                        ci.draw_line(c + Vector2(0, 30), c + Vector2(0, -14),
                                        Color(0.3, 0.2, 0.12), 6.0)
                        var gem := c + Vector2(0, -24)
                        ci.draw_circle(gem, 13.0, Color(0.35, 0.55, 1.0))
                        ci.draw_circle(gem, 8.0 + 2.0 * sin(t * 8.0), Color(0.7, 0.9, 1.0))
                        for k in range(4):
                                var a2 := t * 6.0 + k * TAU / 4.0
                                ci.draw_line(gem, gem + Vector2(cos(a2), sin(a2)) * 22.0,
                                                Color(0.6, 0.85, 1.0), 2.0)
                Collectibles.Kind.SPEED_BOOTS:
                        # stivale alato
                        ci.draw_rect(Rect2(c + Vector2(-10, -18), Vector2(18, 30)),
                                        Color(0.4, 0.25, 0.12))
                        ci.draw_rect(Rect2(c + Vector2(-10, 12), Vector2(34, 12)),
                                        Color(0.4, 0.25, 0.12))
                        for k in range(3):
                                var fl := sin(t * 9.0 + k) * 4.0
                                ci.draw_line(c + Vector2(8, -12 + k * 9),
                                                c + Vector2(34 + fl, -20 + k * 9),
                                                Color(0.95, 0.92, 0.8), 3.0)
                Collectibles.Kind.POTION:
                        # ampolla con liquido verde effervescente
                        ci.draw_rect(Rect2(c + Vector2(-6, -30), Vector2(12, 12)),
                                        Color(0.5, 0.6, 0.55, 0.6))
                        ci.draw_circle(c + Vector2(0, 6), 22.0, Color(0.25, 0.5, 0.35, 0.55))
                        ci.draw_circle(c + Vector2(0, 6), 17.0, Color(0.3, 0.95, 0.45, 0.8))
                        for k in range(4):
                                var bub := c + Vector2(sin(t * 3.0 + k * 2.0) * 8.0,
                                                12.0 - fmod(t * 14.0 + k * 7.0, 26.0))
                                ci.draw_circle(bub, 2.5, Color(0.75, 1.0, 0.8, 0.8))
                Collectibles.Kind.FREEZE_SCROLL:
                        _draw_scroll_icon(ci, c, Color(0.4, 0.75, 1.0), t)
                Collectibles.Kind.QUAKE_SCROLL:
                        _draw_scroll_icon(ci, c, Color(1.0, 0.55, 0.2), t)
                Collectibles.Kind.CHASM_SCROLL:
                        _draw_scroll_icon(ci, c, Color(0.7, 0.4, 1.0), t)
                Collectibles.Kind.MINE:
                        # sfera nera con aculei + luce lampeggiante
                        ci.draw_circle(c, 20.0, Color(0.12, 0.12, 0.14))
                        for k in range(8):
                                var a3 := k * TAU / 8.0
                                ci.draw_line(c + Vector2(cos(a3), sin(a3)) * 18.0,
                                                c + Vector2(cos(a3), sin(a3)) * 28.0,
                                                Color(0.2, 0.2, 0.24), 3.0)
                        var blink := 0.5 + 0.5 * sin(t * 10.0)
                        ci.draw_circle(c + Vector2(0, -6), 4.0,
                                        Color(1.0, 0.2, 0.15 + 0.6 * blink))
                Collectibles.Kind.CHALICE:
                        # calice d'oro con luccichio
                        ci.draw_rect(Rect2(c + Vector2(-18, -26), Vector2(36, 10)),
                                        COL_GOLD)
                        ci.draw_colored_polygon(PackedVector2Array([
                                c + Vector2(-18, -18), c + Vector2(18, -18),
                                c + Vector2(5, 8), c + Vector2(-5, 8)]), COL_GOLD)
                        ci.draw_rect(Rect2(c + Vector2(-4, 8), Vector2(8, 16)), COL_GOLD)
                        ci.draw_rect(Rect2(c + Vector2(-12, 24), Vector2(24, 7)), COL_GOLD)
                        var glint := c + Vector2(-8.0, -22.0 + sin(t * 4.0) * 2.0)
                        ci.draw_circle(glint, 3.0, Color(1.0, 1.0, 0.85))
                Collectibles.Kind.KNIGHT_STATUE:
                        # statua: elmo + spallali pietra
                        ci.draw_rect(Rect2(c + Vector2(-16, 4), Vector2(32, 22)),
                                        Color(0.42, 0.42, 0.46))
                        ci.draw_rect(Rect2(c + Vector2(-11, -20), Vector2(22, 22)),
                                        Color(0.52, 0.52, 0.56))
                        ci.draw_rect(Rect2(c + Vector2(-7, -12), Vector2(14, 5)),
                                        Color(0.1, 0.1, 0.12))
                        ci.draw_line(c + Vector2(0, -20), c + Vector2(0, -34),
                                        Color(0.3, 0.25, 0.1), 3.0)
                        ci.draw_circle(c + Vector2(0, -36), 3.5, COL_GOLD)


func _draw_scroll_icon(ci: Control, c: Vector2, tint: Color, t: float) -> void:
        # pergamena arrotolata con sigillo colorato
        ci.draw_rect(Rect2(c + Vector2(-20, -22), Vector2(40, 44)),
                        Color(0.85, 0.76, 0.55))
        ci.draw_rect(Rect2(c + Vector2(-20, -22), Vector2(40, 44)),
                        Color(0.55, 0.45, 0.25), false, 2.0)
        ci.draw_rect(Rect2(c + Vector2(-24, -24), Vector2(8, 48)), Color(0.7, 0.6, 0.4))
        ci.draw_rect(Rect2(c + Vector2(16, -24), Vector2(8, 48)), Color(0.7, 0.6, 0.4))
        # rune che scorrono
        for k in range(3):
                var ry := -14.0 + k * 12.0 + sin(t * 2.0 + k) * 2.0
                ci.draw_line(c + Vector2(-12, ry), c + Vector2(12, ry),
                                Color(0.5, 0.35, 0.15), 2.0)
        # sigillo pulsante
        ci.draw_circle(c + Vector2(0, 0), 9.0 + 1.5 * sin(t * 5.0), tint)
        ci.draw_circle(c + Vector2(0, 0), 5.0, Color(1, 1, 1, 0.55))


# ============================================================================
# DEMO ANIMATA ("piccolo video" in loop nel pannello)
# ============================================================================
# Ogni demo e' una timeline parametrica (0..LOOP_S, in loop) disegnata con
# figure stilizzate: player cavaliere, nemici blob, muri, effetti.
# Nomenclatura helper: _dp = demo player, _de = demo enemy, ecc.

const DEMO_LOOP_S := 4.6


func _draw_demo(ci: Control, r: Rect2, t: float) -> void:
        var lt := fmod(t, DEMO_LOOP_S)  # tempo locale del loop
        # sfondo: pavimento pietra scuro con vignetta
        ci.draw_rect(r, Color(0.07, 0.06, 0.08), true)
        for gx in range(int(r.size.x / 46.0) + 1):
                for gy in range(int(r.size.y / 46.0) + 1):
                        var cell := Vector2(r.position.x + gx * 46.0 + 23.0,
                                        r.position.y + gy * 46.0 + 23.0)
                        ci.draw_rect(Rect2(cell - Vector2(21, 21), Vector2(42, 42)),
                                        Color(0.09, 0.08, 0.1), false, 1.0)
        # linea pavimento
        var floor_y := r.position.y + r.size.y * 0.78
        ci.draw_line(Vector2(r.position.x + 10.0, floor_y),
                        Vector2(r.end.x - 10.0, floor_y), Color(0.2, 0.17, 0.14), 3.0)

        match bonus_kind:
                Collectibles.Kind.HAMMER:
                        _demo_hammer(ci, r, floor_y, lt)
                Collectibles.Kind.DYNAMITE:
                        _demo_dynamite(ci, r, floor_y, lt)
                Collectibles.Kind.SCEPTER:
                        _demo_scepter(ci, r, floor_y, lt)
                Collectibles.Kind.SPEED_BOOTS:
                        _demo_boots(ci, r, floor_y, lt)
                Collectibles.Kind.POTION:
                        _demo_potion(ci, r, floor_y, lt)
                Collectibles.Kind.FREEZE_SCROLL:
                        _demo_freeze(ci, r, floor_y, lt)
                Collectibles.Kind.QUAKE_SCROLL:
                        _demo_quake(ci, r, floor_y, lt)
                Collectibles.Kind.CHASM_SCROLL:
                        _demo_chasm(ci, r, floor_y, lt)
                Collectibles.Kind.MINE:
                        _demo_mine(ci, r, floor_y, lt)
                Collectibles.Kind.CHALICE:
                        _demo_chalice(ci, r, floor_y, lt)
                Collectibles.Kind.KNIGHT_STATUE:
                        _demo_knight(ci, r, floor_y, lt)


# --- figure comuni ----------------------------------------------------------

# player stilizzato (cavaliere 34px) che cammina; walk fase da t
func _dp(ci: Control, c: Vector2, t: float, alpha: float = 1.0,
                scale: float = 1.0) -> void:
        var col_body := Color(0.35, 0.45, 0.75, alpha)
        var col_skin := Color(0.95, 0.78, 0.6, alpha)
        var bob := sin(t * 9.0) * 2.0 * scale
        var p := c + Vector2(0, bob)
        # gambe che camminano
        var step := sin(t * 9.0) * 6.0 * scale
        ci.draw_line(p + Vector2(-4 * scale, 10 * scale), p + Vector2(-4 * scale + step, 20 * scale), col_body, 4.0)
        ci.draw_line(p + Vector2(4 * scale, 10 * scale), p + Vector2(4 * scale - step, 20 * scale), col_body, 4.0)
        # corpo
        ci.draw_rect(Rect2(p - Vector2(9 * scale, 6 * scale),
                        Vector2(18 * scale, 18 * scale)), col_body)
        # testa + elmo
        ci.draw_circle(p + Vector2(0, -14 * scale), 8.0 * scale, col_skin)
        ci.draw_rect(Rect2(p + Vector2(-9 * scale, -22 * scale),
                        Vector2(18 * scale, 8 * scale)), Color(0.6, 0.62, 0.7, alpha))
        # scudo
        ci.draw_rect(Rect2(p + Vector2(8 * scale, -4 * scale),
                        Vector2(7 * scale, 14 * scale)), Color(0.55, 0.3, 0.15, alpha))


# nemico blob stilizzato; state: 0=vivo, 1=morto(poof via k), 2=congelato,
# 3=folgorato, 4=brucia, 5=nel pozzo (k = progressione effetto)
func _de(ci: Control, c: Vector2, t: float, state: int = 0,
                k: float = 0.0, tint: Color = Color(0.6, 0.3, 0.35)) -> void:
        var wob := sin(t * 7.0) * 1.5
        var p := c + Vector2(0, wob)
        var alpha := 1.0
        var sc := 1.0
        match state:
                1:
                        alpha = 1.0 - k  # poof: dissolvenza
                        sc = 1.0 + k * 0.6
                5:
                        sc = maxf(0.05, 1.0 - k)  # cade nel pozzo
        if alpha <= 0.02:
                return
        var col := Color(tint.r, tint.g, tint.b, alpha)
        if state == 2:
                col = Color(0.55, 0.8, 1.0, alpha)
        elif state == 3:
                col = Color(0.95, 0.95, 0.6, alpha)
        elif state == 4:
                col = Color(1.0, 0.4 + 0.4 * sin(t * 20.0), 0.1, alpha)
        # corpo blob
        ci.draw_circle(p + Vector2(0, -10 * sc), 12.0 * sc, col)
        ci.draw_rect(Rect2(p + Vector2(-9 * sc, -4 * sc), Vector2(18 * sc, 12 * sc)), col)
        # occhi
        if state == 1 or state == 3:
                # X eyes
                for ex in [-5.0, 5.0]:
                        ci.draw_line(p + Vector2(ex - 2, -14 * sc), p + Vector2(ex + 2, -10 * sc), Color(0.1, 0.05, 0.05, alpha), 2.0)
                        ci.draw_line(p + Vector2(ex - 2, -10 * sc), p + Vector2(ex + 2, -14 * sc), Color(0.1, 0.05, 0.05, alpha), 2.0)
        else:
                ci.draw_circle(p + Vector2(-5, -13 * sc), 2.2, Color(1, 1, 0.8, alpha))
                ci.draw_circle(p + Vector2(5, -13 * sc), 2.2, Color(1, 1, 0.8, alpha))
        # blocco di ghiaccio
        if state == 2:
                ci.draw_rect(Rect2(p + Vector2(-16, -26), Vector2(32, 36)),
                                Color(0.5, 0.8, 1.0, 0.45))
                ci.draw_rect(Rect2(p + Vector2(-16, -26), Vector2(32, 36)),
                                Color(0.75, 0.95, 1.0, 0.8), false, 2.0)
                for ic in range(3):
                        ci.draw_line(p + Vector2(-10 + ic * 10, -26),
                                        p + Vector2(-10 + ic * 10, -33), Color(0.75, 0.95, 1.0, 0.85), 2.0)
        # fiamme che bruciano
        if state == 4:
                for f in range(3):
                        var fh := 8.0 + 6.0 * sin(t * 15.0 + f * 2.0)
                        ci.draw_circle(p + Vector2(-6 + f * 6, -22 - fh * 0.4), 3.5,
                                        Color(1.0, 0.55 + 0.3 * f * 0.2, 0.15, alpha))


# muro di mattoni (per martello/pozione)
func _dw(ci: Control, r: Rect2, broken: float = 0.0) -> void:
        if broken >= 1.0:
                return
        ci.draw_rect(r, Color(0.38, 0.26, 0.18), true)
        ci.draw_rect(r, Color(0.22, 0.15, 0.09), false, 2.0)
        # mattoni
        for row in range(4):
                for colm in range(2):
                        var br := Rect2(r.position + Vector2(colm * 14.0 + (1 if row % 2 == 0 else 7), row * 12.0),
                                        Vector2(13, 11))
                        if br.position.x + br.size.x <= r.end.x:
                                ci.draw_rect(br, Color(0.32, 0.21, 0.14), false, 1.0)
        # frattura crescente
        if broken > 0.0:
                ci.draw_line(r.position + Vector2(r.size.x * 0.5, 0),
                                r.position + Vector2(r.size.x * 0.5, r.size.y * broken),
                                Color(0.05, 0.03, 0.02), 3.0)


# esplosione stilizzata (k 0..1)
func _boom(ci: Control, c: Vector2, k: float, max_r: float = 46.0) -> void:
        if k <= 0.0 or k >= 1.0:
                return
        var r := max_r * (0.3 + 0.7 * k)
        var a := 1.0 - k
        ci.draw_circle(c, r, Color(1.0, 0.55, 0.1, a * 0.5))
        ci.draw_circle(c, r * 0.6, Color(1.0, 0.85, 0.3, a * 0.8))
        for f in range(6):
                var fa := f * TAU / 6.0 + k * 2.0
                ci.draw_circle(c + Vector2(cos(fa), sin(fa)) * r * 1.1,
                                3.5 * (1.0 - k), Color(1.0, 0.7, 0.2, a))


# fulmine zigzag dall'alto (k 0..1 visibilita')
func _bolt(ci: Control, from_top: Vector2, to: Vector2, seed: float,
                alpha: float = 1.0) -> void:
        var pts := PackedVector2Array()
        var steps := 7
        for i in range(steps + 1):
                var k := float(i) / float(steps)
                var p := from_top.lerp(to, k)
                if i > 0 and i < steps:
                        p.x += sin(seed + i * 2.7) * 12.0
                pts.append(p)
        ci.draw_polyline(pts, Color(1.0, 1.0, 0.75, alpha), 4.0)
        ci.draw_polyline(pts, Color(0.6, 0.85, 1.0, alpha), 1.5)


# scia di velocita'
func _speedlines(ci: Control, c: Vector2, t: float) -> void:
        for k in range(4):
                var off := 18.0 + k * 9.0 + sin(t * 20.0 + k * 3.0) * 6.0
                ci.draw_line(c + Vector2(-off, -18.0 + k * 7.0),
                                c + Vector2(-off - 16.0, -18.0 + k * 7.0),
                                Color(0.8, 0.85, 1.0, 0.5), 2.0)


# --- demo per bonus ---------------------------------------------------------

func _demo_hammer(ci: Control, r: Rect2, floor_y: float, lt: float) -> void:
        var p_c := Vector2(r.position.x + r.size.x * 0.16, floor_y - 20.0)
        var wall_r := Rect2(Vector2(r.position.x + r.size.x * 0.42, floor_y - 64.0), Vector2(28.0, 64.0))
        var e_c := Vector2(r.position.x + r.size.x * 0.8, floor_y - 18.0)
        # timeline: 0-0.9 carica, 0.9-1.8 volo (muro a meta'), 1.8-2.4 muro rotto,
        # 2.4-3.0 nemico colpito, 3.0-4.6 pausa e restart
        var thrown := lt > 0.9
        var wall_k := clampf((lt - 1.55) / 0.5, 0.0, 1.0)
        var enemy_dead := lt > 2.45
        _dp(ci, p_c, lt, 1.0, 0.0 if not thrown else 1.0)
        _dw(ci, wall_r, wall_k)
        if not enemy_dead:
                _de(ci, e_c, lt, 0)
        else:
                _de(ci, e_c, lt, 1, clampf((lt - 2.45) / 0.7, 0.0, 1.0))
        if thrown and not enemy_dead:
                var fly_k := clampf((lt - 0.9) / 1.55, 0.0, 1.0)
                var hm_pos := p_c.lerp(e_c, fly_k)
                # il martello ruota in volo
                var ang := (lt - 0.9) * 14.0
                ci.draw_line(hm_pos, hm_pos + Vector2(cos(ang), sin(ang)) * 12.0,
                                Color(0.4, 0.28, 0.12), 4.0)
                var head := hm_pos + Vector2(cos(ang), sin(ang)) * 15.0
                ci.draw_rect(Rect2(head - Vector2(8, 8), Vector2(16, 16)),
                                Color(0.62, 0.65, 0.72))
        if wall_k > 0.0 and wall_k < 1.0:
                _boom(ci, wall_r.position + wall_r.size * 0.5, wall_k, 34.0)
        if enemy_dead and lt < 3.3:
                _boom(ci, e_c + Vector2(0, -10), clampf((lt - 2.45) / 0.6, 0.0, 1.0))


func _demo_dynamite(ci: Control, r: Rect2, floor_y: float, lt: float) -> void:
        var p_c := Vector2(r.position.x + r.size.x * 0.14, floor_y - 20.0)
        var e_c := Vector2(r.position.x + r.size.x * 0.78, floor_y - 18.0)
        var boom_at := 3.1
        _dp(ci, p_c, lt, 1.0, 1.0 if lt < 1.0 else 0.0)
        if lt < boom_at:
                _de(ci, e_c, lt, 0)
        else:
                _de(ci, e_c, lt, 1, clampf((lt - boom_at) / 0.7, 0.0, 1.0))
        # candelotto: in mano (0-1s, miccia scintilla) poi in volo parabolico
        if lt < 1.0:
                var dy_pos := p_c + Vector2(14, -26)
                ci.draw_rect(Rect2(dy_pos - Vector2(4, 9), Vector2(8, 18)), Color(0.72, 0.16, 0.1))
                ci.draw_circle(dy_pos + Vector2(0, -13), 3.0 + sin(lt * 25.0) * 1.5,
                                Color(1.0, 0.85, 0.3))
        elif lt < boom_at:
                var k := (lt - 1.0) / (boom_at - 1.0)
                var fly := p_c.lerp(e_c, k)
                fly.y -= sin(k * PI) * 60.0
                ci.draw_rect(Rect2(fly - Vector2(4, 9), Vector2(8, 18)), Color(0.72, 0.16, 0.1))
                ci.draw_circle(fly + Vector2(0, -13), 3.0 + sin(lt * 30.0) * 1.5,
                                Color(1.0, 0.85, 0.3))
        if lt >= boom_at:
                _boom(ci, e_c + Vector2(0, -10), clampf((lt - boom_at) / 0.8, 0.0, 1.0), 60.0)


func _demo_scepter(ci: Control, r: Rect2, floor_y: float, lt: float) -> void:
        # 3 nemici; 5 fulmini in sequenza (uno ogni 0.55s dal 0.6s)
        var n := 3
        for k in range(n):
                var ex := r.position.x + r.size.x * (0.3 + 0.25 * float(k))
                var e_c := Vector2(ex, floor_y - 18.0)
                # il nemico k e' fulgorato quando uno dei 5 fulmini assegnati
                # a lui (s % n == k) e' gia' scoccato
                var fried := false
                for s in range(5):
                        var at := 0.6 + float(s) * 0.55
                        if lt > at and s % n == k:
                                fried = true
                if fried:
                        _de(ci, e_c, lt, 3)
                else:
                        _de(ci, e_c, lt, 0)
        # il fulmine CORRENTE (fase flash)
        var s_idx := int((lt - 0.6) / 0.55) if lt > 0.6 else -1
        if s_idx >= 0 and s_idx < 5 and fmod(lt - 0.6, 0.55) < 0.22:
                var ex2 := r.position.x + r.size.x * (0.3 + 0.25 * float(s_idx % n))
                _bolt(ci, Vector2(ex2, r.position.y + 8.0), Vector2(ex2, floor_y - 26.0), float(s_idx) * 3.1)
                ci.draw_circle(Vector2(ex2, floor_y - 26.0), 10.0 + sin(lt * 40.0) * 4.0,
                                Color(1.0, 1.0, 0.7, 0.5))


func _demo_boots(ci: Control, r: Rect2, floor_y: float, lt: float) -> void:
        # 0-1.4: cammina lento; 1.4: raccoglie gli stivali (lampi);
        # 1.8-4.0: scatta a destra con scia; 4.0-4.6: esce e restart
        var slow_k := clampf(lt / 1.4, 0.0, 1.0)
        var fast_k := clampf((lt - 1.8) / 2.2, 0.0, 1.0)
        var px: float
        if lt < 1.4:
                px = r.position.x + r.size.x * (0.12 + 0.18 * slow_k)
        else:
                px = r.position.x + r.size.x * (0.3 + 0.62 * fast_k)
        var p_c := Vector2(px, floor_y - 20.0)
        _dp(ci, p_c, lt * (1.0 if lt < 1.4 else 3.0), 1.0)
        # stivali a terra prima della raccolta
        if lt < 1.4:
                var b_c := Vector2(r.position.x + r.size.x * 0.32, floor_y - 10.0)
                ci.draw_rect(Rect2(b_c - Vector2(6, 6), Vector2(12, 10)), Color(0.4, 0.25, 0.12))
                for k in range(2):
                        ci.draw_line(b_c + Vector2(6, -4 + k * 6), b_c + Vector2(16, -10 + k * 6),
                                        Color(0.95, 0.92, 0.8), 2.0)
        elif lt < 1.8:
                _speedlines(ci, p_c, lt)
        else:
                _speedlines(ci, p_c, lt)
                # doppie scie
                ci.draw_line(p_c + Vector2(-26, -14), p_c + Vector2(-58, -14), Color(0.9, 0.95, 1.0, 0.35), 3.0)


func _demo_potion(ci: Control, r: Rect2, floor_y: float, lt: float) -> void:
        # muro in mezzo; 0-1: beve; 1-2.2: diventa fantasma; 2.2-3.4: attraversa
        var wall_r := Rect2(Vector2(r.position.x + r.size.x * 0.5 - 14.0, floor_y - 64.0), Vector2(28.0, 64.0))
        _dw(ci, wall_r)
        var ghost := lt > 1.0
        var crossing_k := clampf((lt - 2.2) / 1.2, 0.0, 1.0)
        var px: float
        if lt < 2.2:
                px = r.position.x + r.size.x * (0.18 + 0.14 * clampf(lt / 2.2, 0.0, 1.0))
        else:
                px = r.position.x + r.size.x * (0.32 + 0.5 * crossing_k)
        var alpha := 0.45 if ghost else 1.0
        _dp(ci, Vector2(px, floor_y - 20.0), lt, alpha)
        # onda evanescenza
        if ghost and lt < 3.4:
                var p_c := Vector2(px, floor_y - 20.0)
                ci.draw_circle(p_c + Vector2(0, -12), 22.0 + sin(lt * 6.0) * 3.0,
                                Color(0.5, 1.0, 0.6, 0.18))
        # ampolla prima della bevuta
        if lt < 1.0:
                var fl_c := Vector2(r.position.x + r.size.x * 0.18, floor_y - 44.0)
                ci.draw_circle(fl_c, 9.0, Color(0.3, 0.95, 0.45, 0.85))
                ci.draw_rect(Rect2(fl_c - Vector2(3, -8), Vector2(6, 8)), Color(0.5, 0.6, 0.55, 0.6))


func _demo_freeze(ci: Control, r: Rect2, floor_y: float, lt: float) -> void:
        var p_c := Vector2(r.position.x + r.size.x * 0.14, floor_y - 20.0)
        _dp(ci, p_c, lt)
        # raggio congelante 0.8-1.8
        if lt > 0.8 and lt < 1.8:
                var k := (lt - 0.8) / 1.0
                var beam_end := p_c.lerp(Vector2(r.position.x + r.size.x * 0.84, floor_y - 22.0), k)
                ci.draw_line(p_c + Vector2(12, -10), beam_end, Color(0.5, 0.85, 1.0, 0.8), 6.0)
                ci.draw_line(p_c + Vector2(12, -10), beam_end, Color(0.85, 0.97, 1.0, 0.9), 2.0)
        # nemici: congelano quando il raggio li raggiunge (1.0+)
        for k in range(2):
                var e_c := Vector2(r.position.x + r.size.x * (0.6 + 0.22 * float(k)), floor_y - 18.0)
                var frozen := lt > 1.0 + 0.4 * float(k)
                if frozen:
                        _de(ci, e_c, lt, 2)
                else:
                        _de(ci, e_c, lt, 0, 0.0, Color(0.55, 0.35, 0.6))


func _demo_quake(ci: Control, r: Rect2, floor_y: float, lt: float) -> void:
        # shake decrescente 0.3-2.6 + crepe a terra; nemici barcollano e muoiono
        var shake := 0.0
        if lt > 0.3 and lt < 2.6:
                shake = (1.0 - (lt - 0.3) / 2.3) * 6.0 * sin(lt * 46.0)
        ci.draw_line(Vector2(r.position.x + 10.0, floor_y + shake),
                        Vector2(r.end.x - 10.0, floor_y + shake), Color(0.2, 0.17, 0.14), 3.0)
        if lt > 0.3:
                # crepe a terra
                for k in range(4):
                        var cx2 := r.position.x + r.size.x * (0.25 + 0.16 * float(k))
                        var ck := clampf((lt - 0.3 - 0.2 * float(k)) / 0.4, 0.0, 1.0)
                        if ck > 0.0:
                                ci.draw_line(Vector2(cx2, floor_y + shake),
                                                Vector2(cx2 - 18.0 * ck, floor_y + 10.0 + shake),
                                                Color(0.05, 0.03, 0.02), 3.0)
        for k in range(3):
                var e_c := Vector2(r.position.x + r.size.x * (0.3 + 0.2 * float(k)),
                                floor_y - 18.0 + (2.0 * sin(lt * 30.0 + k * 2.0) if lt > 0.3 else 0.0))
                var die_at := 1.5 + 0.35 * float(k)
                if lt > die_at:
                        _de(ci, e_c, lt, 1, clampf((lt - die_at) / 0.8, 0.0, 1.0))
                else:
                        _de(ci, e_c, lt, 0, 0.0, Color(0.5, 0.4, 0.3))


func _demo_chasm(ci: Control, r: Rect2, floor_y: float, lt: float) -> void:
        # ondata: voragine viola sotto un nemico (0.8s crepa), nemico cade,
        # si chiude, seconda ondata altrove (mostra "3 ondate")
        var wave_len := 2.2
        var wave := int(lt / wave_len)  # 0,1,2
        var wl := fmod(lt, wave_len)
        var ex := r.position.x + r.size.x * (0.35 + 0.18 * float(wave))
        var e_c := Vector2(ex, floor_y - 18.0)
        var crack_k := clampf(wl / 0.8, 0.0, 1.0)
        var falling_k := clampf((wl - 0.8) / 0.8, 0.0, 1.0)
        # voragine
        if wl < 0.8:
                # crepa telegrafo
                var pulse2 := 0.5 + 0.5 * sin(lt * 16.0)
                ci.draw_circle(Vector2(ex, floor_y + 4), 20.0 * crack_k,
                                Color(0.7, 0.4, 1.0, 0.25 * pulse2))
                for k in range(5):
                        var a := k * TAU / 5.0 + 0.4
                        ci.draw_line(Vector2(ex, floor_y + 4) + Vector2(cos(a), sin(a)) * 5.0,
                                        Vector2(ex, floor_y + 4) + Vector2(cos(a), sin(a)) * 22.0 * crack_k,
                                        Color(0.7, 0.4, 1.0, 0.6), 2.0)
        else:
                ci.draw_circle(Vector2(ex, floor_y + 4), 24.0, Color(0.04, 0.02, 0.06, 0.95))
                ci.draw_arc(Vector2(ex, floor_y + 4), 24.0, 0.0, TAU, 22,
                                Color(0.7, 0.4, 1.0, 0.7), 3.0, true)
                # spirale interna
                ci.draw_arc(Vector2(ex, floor_y + 4), 13.0 + sin(lt * 9.0) * 3.0,
                                lt * 4.0, lt * 4.0 + PI * 1.4, 14,
                                Color(0.85, 0.6, 1.0, 0.5), 2.0, true)
        if falling_k < 1.0:
                _de(ci, e_c + Vector2(0, 14.0 * falling_k), lt,
                                5 if wl > 0.8 else 0, falling_k)
        # gli ALTRI nemici (non bersaglio) restano vivi e camminano
        for k in range(2):
                var oe := Vector2(r.position.x + r.size.x * (0.68 - 0.2 * float(wave) + 0.12 * float(k)),
                                floor_y - 18.0)
                if absf(oe.x - ex) > 50.0:
                        _de(ci, oe, lt, 0, 0.0, Color(0.5, 0.45, 0.3))


func _demo_mine(ci: Control, r: Rect2, floor_y: float, lt: float) -> void:
        # mina che rimbalza (rimbalzi a muri demo) e colpisce il nemico
        var e_c := Vector2(r.position.x + r.size.x * 0.75, floor_y - 18.0)
        var boom_at := 2.9
        _de(ci, e_c, lt, 0 if lt < boom_at else 1,
                        0.0 if lt < boom_at else clampf((lt - boom_at) / 0.7, 0.0, 1.0))
        # traiettoria: sinusoide con rimbalzi sul pavimento
        var travel := r.position.x + r.size.x * (0.1 + 0.6 * clampf(lt / 2.7, 0.0, 1.0))
        var bounce := absf(sin(lt * 6.0)) * 44.0
        var m_c := Vector2(travel, floor_y - 12.0 - (bounce if lt < boom_at else 0.0))
        if lt < boom_at:
                ci.draw_circle(m_c, 9.0, Color(0.12, 0.12, 0.14))
                for k in range(6):
                        var a := k * TAU / 6.0
                        ci.draw_line(m_c + Vector2(cos(a), sin(a)) * 8.0,
                                        m_c + Vector2(cos(a), sin(a)) * 13.0,
                                        Color(0.2, 0.2, 0.24), 2.5)
                ci.draw_circle(m_c + Vector2(0, -3), 2.5,
                                Color(1.0, 0.25, 0.2, 0.5 + 0.5 * sin(lt * 14.0)))
        else:
                _boom(ci, e_c + Vector2(0, -10), clampf((lt - boom_at) / 0.8, 0.0, 1.0), 52.0)
        # linee rimbalzo
        if lt < boom_at:
                ci.draw_line(m_c, m_c + Vector2(-14.0, -10.0), Color(1.0, 1.0, 1.0, 0.18), 2.0)


func _demo_chalice(ci: Control, r: Rect2, floor_y: float, lt: float) -> void:
        var p_c := Vector2(r.position.x + r.size.x * 0.4, floor_y - 20.0)
        _dp(ci, p_c, lt)
        # aura dorata + anello timer che si scarica (9.5s ~ loop 4.6 dimezzato)
        var remain := clampf(1.0 - lt / DEMO_LOOP_S, 0.0, 1.0)
        ci.draw_circle(p_c + Vector2(0, -12), 34.0, Color(1.0, 0.85, 0.3, 0.14 + 0.05 * sin(lt * 6.0)))
        ci.draw_arc(p_c + Vector2(0, -12), 34.0, -PI / 2.0, -PI / 2.0 + TAU * remain,
                        30, Color(1.0, 0.9, 0.5, 0.8), 3.0, true)
        # due nemici si avvicinano e BRUCIANO al tocco
        for k in range(2):
                var approach := clampf(lt / (2.0 + 0.5 * float(k)), 0.0, 1.0)
                var side := 1.0 if k == 0 else -1.0
                var ex := p_c.x + side * (140.0 - 90.0 * approach)
                var e_c := Vector2(ex, floor_y - 18.0)
                var burning := approach >= 1.0
                if burning:
                        _de(ci, e_c, lt, 4, 0.0)
                else:
                        _de(ci, e_c, lt, 0, 0.0, Color(0.55, 0.3, 0.3))


func _demo_knight(ci: Control, r: Rect2, floor_y: float, lt: float) -> void:
        # statua a sinistra che si illumina (0-0.9), evoca il cavaliere
        # alleato (0.9-1.4), che carica e colpisce il nemico (2.6)
        var st_c := Vector2(r.position.x + r.size.x * 0.18, floor_y - 22.0)
        var glow := clampf(lt / 0.9, 0.0, 1.0)
        # statua
        ci.draw_rect(Rect2(st_c - Vector2(11, 16), Vector2(22, 16)),
                        Color(0.42, 0.42, 0.46))
        ci.draw_rect(Rect2(st_c - Vector2(8, -30 + 16), Vector2(16, 16)),
                        Color(0.52, 0.52, 0.56))
        if glow > 0.0:
                ci.draw_circle(st_c + Vector2(0, -8), 26.0 * glow,
                                Color(0.45, 0.75, 1.0, 0.22 * glow))
        var e_c := Vector2(r.position.x + r.size.x * 0.78, floor_y - 18.0)
        _de(ci, e_c, lt, 0 if lt < 2.6 else 1,
                        0.0 if lt < 2.6 else clampf((lt - 2.6) / 0.7, 0.0, 1.0))
        # cavaliere alleato: emerge dalla statua e carica
        if lt > 0.9:
                var charge_k := clampf((lt - 1.4) / 1.2, 0.0, 1.0)
                var kx: float
                if lt < 1.4:
                        kx = st_c.x + 18.0
                else:
                        kx = st_c.x + 18.0 + (e_c.x - st_c.x - 60.0) * charge_k
                var ally := Vector2(kx, floor_y - 20.0)
                # corpo del cavaliere alleato (armatura chiara)
                var bob := sin(lt * 12.0) * 2.0
                var p := ally + Vector2(0, bob)
                ci.draw_rect(Rect2(p - Vector2(8, 4), Vector2(16, 16)),
                                Color(0.72, 0.75, 0.8))
                ci.draw_circle(p + Vector2(0, -12), 7.0, Color(0.9, 0.92, 0.95))
                ci.draw_rect(Rect2(p + Vector2(-8, -18), Vector2(16, 7)),
                                Color(0.55, 0.6, 0.7))
                # spada: abbassata in corsa, alzata allo scatto
                var swing := clampf((lt - 2.4) / 0.3, 0.0, 1.0)
                var sword_tip := p + Vector2(20.0, -18.0 + swing * 26.0)
                ci.draw_line(p + Vector2(6, -8), sword_tip, Color(0.85, 0.88, 0.95), 4.0)
                if swing > 0.0 and swing < 1.0:
                        ci.draw_arc(p + Vector2(10, -10), 26.0, -1.2, 0.4, 10,
                                        Color(1.0, 1.0, 1.0, 0.5), 3.0, true)
