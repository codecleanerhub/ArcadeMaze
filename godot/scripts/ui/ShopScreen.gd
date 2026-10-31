## ShopScreen.gd — TASK 108 (SHOP): INTERNO DEL NEGOZIO DEL MAGO.
## ============================================================
## Il player entra nella casa strega del labirinto camminandoci sopra:
## il gioco si mette in pausa e si apre questa schermata.
##
##   * in alto il MAGO (shop_wizard.png, PixelLab: stile Gandalf/Merlino)
##     con il saluto;
##   * sotto, un box per ogni item IN VENDITA: ICONA (PNG PixelLab),
##     sotto l'icona una BREVE DESCRIZIONE, sotto ancora il COSTO in punti;
##   * ogni box ha il suo tasto ACQUISTA: DISATTIVATO (grigio, saltato
##     dalla navigazione) quando i punti non bastano — o quando l'acquisto
##     non avrebbe effetto (medikit a energia piena, bambola gia' in tasca);
##   * il tasto ESCI chiude: il player torna accanto alla porta e sullo
##     shop viene appeso il cartello "CHIUSO" (una sola visita per livello);
##   * il punteggio cala in diretta dopo ogni acquisto (spend_score: il
##     livello e' high watermark ma la Hall of Fame registra lo sconto).
##
## Pure-code CanvasLayer (pattern SaveSlotsCard: pausa il tree, input SU/
## GIU'/SX/DX + INVIO/FUOCO + ESC, edge-detection D-pad). In 2P lo shop
## serve il player che ci è entrato (punteggio e acquisti sono SUOI).
extends CanvasLayer

## Emitted quando il player ha finito (tasto ESCI): il controller chiude
## lo shop (cartello CHIUSO) e riposiziona il player accanto alla porta.
signal shop_exited

const C = preload("res://scripts/core/GameConstants.gd")

# --- Palette (legno caldo + oro, coerenza col resto delle UI di gioco) ------
const COL_VEIL: Color = Color(0.02, 0.01, 0.04, 0.86)
const COL_WOOD: Color = Color(0.15, 0.09, 0.06, 0.96)
const COL_WOOD_LIGHT: Color = Color(0.27, 0.17, 0.10, 0.96)
const COL_GOLD: Color = Color(1.0, 0.84, 0.25)
const COL_TEXT: Color = Color(0.96, 0.90, 0.74)
const COL_TEXT_DIM: Color = Color(0.72, 0.66, 0.52)
const COL_RED: Color = Color(0.98, 0.28, 0.34)
const COL_GREEN: Color = Color(0.35, 0.85, 0.45)
const COL_GREEN_DIM: Color = Color(0.35, 0.48, 0.38)
const COL_PURPLE: Color = Color(0.80, 0.55, 1.0)

## Il player che sta facendo acquisti (chi è entrato nella capanna).
var shopper: CharacterBody2D = null

## Indice selezionato: 0..2 = item, 3 = tasto ESCI.
var _sel: int = 0
var _t: float = 0.0
var _panel: Control = null
## Feedback dell'ultimo acquisto ("ACQUISTATO: CUORE (-4000 punti)").
var _bought_feedback: String = ""
var _bought_feedback_ms: float = 0.0
var _confirm_lock_ms: float = 250.0  # anti-doppio-acquisto sullo stesso frame
# Edge detection ESC e D-pad/joystick (pattern SaveSlotsCard/NewGamePlusCard).
var _prev_esc: bool = false
var _prev_joy_btns: Dictionary = {}

# Texture (PNG PixelLab Task 108 + icone riusate).
var _wizard_tex: Texture2D = null
var _bg_tex: Texture2D = null
var _heart_tex: Texture2D = null
var _medikit_tex: Texture2D = null
var _voodoo_tex: Texture2D = null


## `player`: chi è entrato (P1 o P2). Lo shop resta aperto finché non preme ESCI.
func setup(player: CharacterBody2D) -> void:
        shopper = player


func _ready() -> void:
        layer = 33  # sopra HUD/pausa/bonus, come la card degli slot
        process_mode = Node.PROCESS_MODE_ALWAYS
        # Lo shop blocca il gioco sotto (pattern SaveSlotsCard).
        get_tree().paused = true
        _panel = Control.new()
        _panel.name = "ShopPanel"
        _panel.set_anchors_preset(Control.PRESET_FULL_RECT)
        _panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _panel.draw.connect(_draw_panel.bind(_panel))
        add_child(_panel)
        _wizard_tex = _load_png("res://assets/sprites/shop_wizard.png")
        _bg_tex = _load_png("res://assets/backgrounds/bg_shop.png")
        _heart_tex = _load_png("res://assets/sprites/ui_heart.png")
        _medikit_tex = _load_png("res://assets/sprites/collectibles/item_medikit.png")
        _voodoo_tex = _load_png("res://assets/sprites/collectibles/item_voodoo.png")


static func _load_png(path: String) -> Texture2D:
        var abs_path: String = ProjectSettings.globalize_path(path)
        if not FileAccess.file_exists(abs_path):
                return null
        var img := Image.new()
        if img.load(abs_path) != OK:
                return null
        return ImageTexture.create_from_image(img)


func _physics_process(delta: float) -> void:
        _t += delta
        _panel.queue_redraw()
        if _bought_feedback_ms > 0.0:
                _bought_feedback_ms = maxf(0.0, _bought_feedback_ms - delta * 1000.0)
        if _confirm_lock_ms > 0.0:
                _confirm_lock_ms = maxf(0.0, _confirm_lock_ms - delta * 1000.0)
        _poll_input(delta * 1000.0)


# ============================================================================
# Catalogo items (richiesta utente: "il più caro è la bambola voodoo, poi
# il cuore e poi il medikit") + regole di acquistabilità.
# ============================================================================
func _item_defs() -> Array:
        return [
                {
                        "id": "voodoo", "cost": C.SHOP_COST_VOODOO,
                        "name_key": "shop.item.voodoo",
                        "desc_key": "shop.item.voodoo.desc",
                        "tex": _voodoo_tex, "color": COL_PURPLE,
                        "icon_scale": 1.0,
                },
                {
                        "id": "heart", "cost": C.SHOP_COST_HEART,
                        "name_key": "shop.item.heart",
                        "desc_key": "shop.item.heart.desc",
                        "tex": _heart_tex, "color": COL_RED,
                        "icon_scale": 1.25,
                },
                {
                        "id": "medikit", "cost": C.SHOP_COST_MEDICIT,
                        "name_key": "shop.item.medikit",
                        "desc_key": "shop.item.medikit.desc",
                        "tex": _medikit_tex, "color": Color(0.4, 0.9, 0.5),
                        "icon_scale": 1.0,
                },
        ]


## Perché questo item NON è acquistabile adesso? "" se lo è.
## Il tasto ACQUISTA appare disattivato con la ragione sotto il costo.
func _lock_reason(def: Dictionary) -> String:
        if shopper == null or not is_instance_valid(shopper):
                return "shop.buy_locked"
        if int(shopper.score) < int(def["cost"]):
                return "shop.buy_locked"
        if str(def["id"]) == "medikit" and int(shopper.energy) >= int(shopper.max_energy):
                return "shop.buy_full"
        if str(def["id"]) == "voodoo" and bool(shopper.get("voodoo_equipped")):
                return "shop.buy_owned"
        return ""


## Applica l'acquisto dell'item `def` al shopper. Ritorna true se comprato.
func _buy_item(def: Dictionary) -> bool:
        if shopper == null or not is_instance_valid(shopper):
                return false
        if _lock_reason(def) != "":
                return false
        var cost: int = int(def["cost"])
        shopper.spend_score(cost)
        match str(def["id"]):
                "heart":
                        shopper.add_life()
                "medikit":
                        shopper.energy = mini(int(shopper.max_energy),
                                        int(shopper.energy) + 1)
                "voodoo":
                        shopper.set("voodoo_equipped", true)
        _bought_feedback = I18n.t("shop.bought") % [I18n.t(str(def["name_key"])), cost]
        _bought_feedback_ms = 2400.0
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.RELIC_PICKUP)
                AudioManager.play_sound(AudioManager.SoundType.MENU_CONFIRM)
        print("[Shop] Player ", int(shopper.player_num), " acquista ",
                        str(def["id"]), " per ", cost, " punti")
        return true


# ============================================================================
# Input: frecce/D-pad per selezionare (item o ESCI), INVIO/FUOCO acquista,
# ESC chiude sempre. Gli item non acquistabili restano selezionabili (il
# tasto ACQUISTA è disattivato e mostra il motivo).
# ============================================================================
func _poll_input(_delta_ms: float) -> void:
        var moved: int = 0
        var is_p1: bool = shopper != null and int(shopper.player_num) == 1
        if is_p1 or shopper == null:
                if Input.is_action_just_pressed("move_left"):
                        moved = -1
                elif Input.is_action_just_pressed("move_right"):
                        moved = 1
                var joy: int = _first_joy()
                if joy >= 0:
                        if _joy_edge(joy, JOY_BUTTON_DPAD_LEFT):
                                moved = -1
                        elif _joy_edge(joy, JOY_BUTTON_DPAD_RIGHT):
                                moved = 1
        else:
                if Input.is_action_just_pressed("p2_left"):
                        moved = -1
                elif Input.is_action_just_pressed("p2_right"):
                        moved = 1
                var joy2: int = _second_joy()
                if joy2 >= 0:
                        if _joy_edge(joy2, JOY_BUTTON_DPAD_LEFT):
                                moved = -1
                        elif _joy_edge(joy2, JOY_BUTTON_DPAD_RIGHT):
                                moved = 1
        if moved != 0:
                _sel = int(fposmod(float(_sel + moved), 4.0))
                if AudioManager:
                        AudioManager.play_sound(AudioManager.SoundType.MENU_SELECT)
        # ESC chiude sempre.
        var esc: bool = Input.is_action_just_pressed("ui_cancel")
        _prev_esc = esc
        if esc:
                _exit_shop()
                return
        # INVIO / FUOCO: acquista l'item selezionato (o ESCI se selezionato).
        var confirm: bool = false
        if is_p1 or shopper == null:
                confirm = Input.is_action_just_pressed("confirm") \
                                or Input.is_action_just_pressed("shoot") \
                                or Input.is_action_just_pressed("jump")
        else:
                confirm = Input.is_action_just_pressed("p2_jump") \
                                or Input.is_action_just_pressed("p2_shoot")
        # Gate anti-ghost: 250ms dopo l'apertura (lo stesso tasto che ha
        # fatto entrare non deve comprare subito).
        if confirm and _confirm_lock_ms <= 0.0:
                if _sel == 3:
                        _exit_shop()
                else:
                        _buy_item(_item_defs()[_sel])


func _exit_shop() -> void:
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.MENU_CONFIRM)
        # Ripristina il tree PRIMA del segnale (pattern SaveSlotsCard).
        get_tree().paused = false
        shop_exited.emit()
        queue_free()


func _first_joy() -> int:
        var pads: Array = Input.get_connected_joypads()
        if ConfigManager and ConfigManager.joy_id() >= 0 and pads.has(ConfigManager.joy_id()):
                return ConfigManager.joy_id()
        if pads.size() > 0:
                return pads[0]
        return -1


func _second_joy() -> int:
        var pads: Array = Input.get_connected_joypads()
        var p1: int = _first_joy()
        if ConfigManager and ConfigManager.joy2_id() >= 0 \
                        and pads.has(ConfigManager.joy2_id()) \
                        and ConfigManager.joy2_id() != p1:
                return ConfigManager.joy2_id()
        for pad_id in pads:
                if pad_id != p1:
                        return pad_id
        return -1


func _joy_edge(joy_id: int, btn: int) -> bool:
        var key: String = str(joy_id) + ":" + str(btn)
        var now: bool = Input.is_joy_button_pressed(joy_id, btn)
        var prev: bool = bool(_prev_joy_btns.get(key, false))
        _prev_joy_btns[key] = now
        return now and not prev


# ============================================================================
# Rendering
# ============================================================================
func _draw_panel(p: Control) -> void:
        var vp: Vector2 = p.get_viewport_rect().size
        var font: Font = ThemeDB.fallback_font
        var gothic: Font = C.gothic_font()  # Task 78, static: null se manca
        var title_font: Font = gothic if gothic != null else font
        var cx: float = vp.x * 0.5

        # Sfondo: interno della capanna (bg_shop.png, PixelLab) + velo.
        if _bg_tex != null:
                var tex_size: Vector2 = _bg_tex.get_size()
                var scale_val: float = max(vp.x / tex_size.x, vp.y / tex_size.y)
                var draw_size: Vector2 = tex_size * scale_val
                p.draw_texture_rect(_bg_tex,
                        Rect2((vp - draw_size) * 0.5, draw_size), false)
                p.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.02, 0.01, 0.04, 0.55), true)
        else:
                p.draw_rect(Rect2(Vector2.ZERO, vp), COL_VEIL, true)

        # --- Titolo + saluto + punteggio del shopper ---
        var pnum: int = 1
        if shopper != null and is_instance_valid(shopper):
                pnum = int(shopper.player_num)
        _draw_centered(p, title_font, I18n.t("shop.title"),
                Vector2(cx, 78.0), 46, COL_GOLD)
        _draw_centered(p, font, I18n.t("shop.greeting"),
                Vector2(cx, 118.0), 19, Color(0.9, 0.8, 0.6))
        var score_col: Color = Color(0.39, 0.78, 1.0) if pnum == 1 else Color(1.0, 0.59, 0.39)
        var score_now: int = int(shopper.score) if shopper != null and is_instance_valid(shopper) else 0
        _draw_centered(p, font, (I18n.t("shop.player") % pnum) + "   ·   "
                        + (I18n.t("shop.score") % score_now),
                Vector2(cx, 152.0), 22, score_col)

        # --- Il MAGO (PixelLab) con lieve fluttuazione e alone ---
        var wizard_c: Vector2 = Vector2(cx, 330.0)
        var bob: float = 4.0 * sin(_t * 1.3)
        var pulse: float = 0.5 + 0.5 * sin(_t * 2.0)
        if _wizard_tex != null:
                var ws: Vector2 = Vector2(300.0, 300.0)
                p.draw_circle(wizard_c + Vector2(0.0, 40.0), 90.0,
                        Color(0.45, 0.65, 1.0, 0.05 + 0.04 * pulse))
                p.draw_texture_rect(_wizard_tex,
                        Rect2(wizard_c - ws * 0.5 + Vector2(0.0, bob), ws), false)
        else:
                # Fallback procedurale: sagoma del mago (cappello + barba)
                var hat_c: Color = Color(0.38, 0.45, 0.62)
                p.draw_colored_polygon(PackedVector2Array([
                        wizard_c + Vector2(-46, -50), wizard_c + Vector2(46, -50),
                        wizard_c + Vector2(0, -140)]), hat_c)
                p.draw_rect(Rect2(wizard_c + Vector2(-60, -56), Vector2(120, 14)), hat_c, true)
                p.draw_circle(wizard_c + Vector2(0, -30), 16.0, Color(0.92, 0.82, 0.68))
                p.draw_colored_polygon(PackedVector2Array([
                        wizard_c + Vector2(-18, -22), wizard_c + Vector2(18, -22),
                        wizard_c + Vector2(0, 60)]), Color(0.93, 0.93, 0.9))
                p.draw_rect(Rect2(wizard_c + Vector2(-52, 20), Vector2(104, 110)),
                        Color(0.42, 0.48, 0.65), true)

        # --- I box degli item (icona / descrizione / costo / ACQUISTA) ---
        var defs: Array = _item_defs()
        var box_w: float = 380.0
        var box_h: float = 330.0
        var gap: float = 56.0
        var total_w: float = box_w * 3.0 + gap * 2.0
        var x0: float = cx - total_w * 0.5
        var box_y: float = 528.0
        for i in defs.size():
                _draw_item_box(p, font, defs[i],
                        Rect2(x0 + float(i) * (box_w + gap), box_y, box_w, box_h),
                        i == _sel)
        # --- Tasto ESCI (selection 3) ---
        _draw_exit_button(p, font, cx, box_y + box_h + 46.0, _sel == 3)

        # --- Istruzioni comandi ---
        var hint: String = I18n.t("shop.hint_1p" if pnum == 1 else "shop.hint_2p")
        _draw_centered(p, font, hint,
                Vector2(cx, vp.y - 34.0), 17, Color(0.72, 0.72, 0.78))

        # --- Feedback dell'ultimo acquisto (sfuma) ---
        if _bought_feedback != "" and _bought_feedback_ms > 0.0:
                var alpha: float = clampf(_bought_feedback_ms / 2400.0, 0.0, 1.0)
                _draw_centered(p, font, _bought_feedback,
                        Vector2(cx, vp.y - 66.0), 20,
                        Color(0.5, 1.0, 0.6, alpha))


## Un box item: ICONA in alto, sotto la BREVE DESCRIZIONE, sotto il COSTO
## e il tasto ACQUISTA (verde se acquistabile, grigio col motivo se no).
func _draw_item_box(p: Control, font: Font, def: Dictionary,
                rect: Rect2, selected: bool) -> void:
        var col: Color = def.get("color", COL_GOLD)
        var lock_key: String = _lock_reason(def)
        var locked: bool = lock_key != ""
        var pulse: float = 0.5 + 0.5 * sin(_t * 4.0)
        # Pannello legno.
        p.draw_rect(rect, COL_WOOD, true)
        p.draw_rect(rect.grow(-6.0), COL_WOOD_LIGHT, false, 1.5)
        # Bordo: selezione = colore item pulsante + bagliore.
        if selected:
                p.draw_rect(rect, Color(col.r, col.g, col.b, 0.60 + 0.40 * pulse),
                                false, 4.0)
                p.draw_rect(Rect2(rect.position - Vector2(6, 6),
                                rect.size + Vector2(12, 12)),
                        Color(col.r, col.g, col.b, 0.10 + 0.06 * pulse), true)
        else:
                p.draw_rect(rect, Color(0.40, 0.32, 0.28, 0.9), false, 2.0)
        var cx: float = rect.position.x + rect.size.x * 0.5
        # ICONA (PNG PixelLab) con alone colorato; grande e centrata.
        var tex: Texture2D = def.get("tex")
        var icon_s: float = 112.0 * float(def.get("icon_scale", 1.0))
        p.draw_circle(Vector2(cx, rect.position.y + 88.0), 58.0,
                        Color(col.r, col.g, col.b, 0.09 + 0.06 * pulse))
        if tex != null:
                var ts: Vector2 = tex.get_size()
                var fit: float = min(icon_s / ts.x, icon_s / ts.y)
                var draw_size: Vector2 = ts * fit
                var bob: float = 3.0 * sin(_t * 1.6 + float(rect.position.x))
                p.draw_texture_rect(tex, Rect2(
                        Vector2(cx, rect.position.y + 88.0) - draw_size * 0.5
                                        + Vector2(0.0, bob), draw_size), false)
        # NOME item.
        _draw_centered_box(p, font, I18n.t(str(def["name_key"])),
                Vector2(cx, rect.position.y + 172.0), rect.size.x - 40.0, 22,
                col if not locked else Color(0.6, 0.55, 0.5))
        # DESCRIZIONE (a capo automatico, max 3 righe sotto l'icona).
        var desc_y: float = rect.position.y + 200.0
        for line in _wrap_text(I18n.t(str(def["desc_key"])), 44):
                _draw_centered_box(p, font, line,
                        Vector2(cx, desc_y), rect.size.x - 44.0, 14,
                        Color(0.80, 0.80, 0.86))
                desc_y += 19.0
        # COSTO in punti.
        var cost_col: Color = COL_GOLD if not locked else Color(0.55, 0.48, 0.42)
        _draw_centered_box(p, font, I18n.t("shop.cost_line") % int(def["cost"]),
                Vector2(cx, rect.position.y + 282.0), rect.size.x - 40.0, 19, cost_col)
        # Tasto ACQUISTA: verde attivo o grigio disattivato col motivo.
        var btn_rect: Rect2 = Rect2(cx - 120.0, rect.position.y + 296.0, 240.0, 26.0)
        if not locked:
                p.draw_rect(btn_rect, Color(0.10, 0.22, 0.13, 0.95), true)
                p.draw_rect(btn_rect, Color(col.r, col.g, col.b, 0.75 if selected else 0.45),
                                false, 2.0)
                _draw_centered_box(p, font, I18n.t("shop.buy"),
                        Vector2(cx, rect.position.y + 314.0), 240.0, 17, COL_GREEN)
        else:
                p.draw_rect(btn_rect, Color(0.13, 0.11, 0.10, 0.9), true)
                p.draw_rect(btn_rect, Color(0.30, 0.26, 0.24, 0.8), false, 2.0)
                var reason: String = I18n.t(lock_key)
                _draw_centered_box(p, font,
                                I18n.t("shop.buy") + "  —  " + reason,
                                Vector2(cx, rect.position.y + 314.0), 240.0, 14,
                                Color(0.48, 0.44, 0.40))


## Il tasto ESCI in basso: cornice oro quando selezionato.
func _draw_exit_button(p: Control, font: Font, cx: float, y: float,
                selected: bool) -> void:
        var pulse: float = 0.5 + 0.5 * sin(_t * 4.0)
        var rect: Rect2 = Rect2(cx - 110.0, y, 220.0, 34.0)
        p.draw_rect(rect, COL_WOOD, true)
        if selected:
                p.draw_rect(rect, Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b,
                                0.60 + 0.40 * pulse), false, 3.0)
                # Freccia lampeggiante ai lati.
                var blink: float = 0.55 + 0.45 * sin(_t * 6.0)
                for sx in [-132.0, 114.0]:
                        p.draw_colored_polygon(PackedVector2Array([
                                Vector2(cx + sx, y + 8.0),
                                Vector2(cx + sx, y + 26.0),
                                Vector2(cx + sx + (10.0 if sx > 0 else -10.0), y + 17.0)]),
                                Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b, blink))
        else:
                p.draw_rect(rect, Color(0.40, 0.32, 0.28, 0.9), false, 2.0)
        _draw_centered_box(p, font, I18n.t("shop.exit"),
                Vector2(cx, y + 23.0), 220.0, 20, COL_TEXT)


# ----------------------------------------------------------------------------
# Helper di disegno
# ----------------------------------------------------------------------------
func _draw_centered(p: Control, font: Font, text: String, at: Vector2,
                size: int, col: Color) -> void:
        if text == "":
                return
        # draw_string con align CENTER usa pos.x come BORDO SINISTRO del box
        # (pattern BonusScreen._draw_text_centered): centro il box su at.x.
        var pos_x: float = at.x - 900.0 * 0.5
        p.draw_string(font, Vector2(pos_x, at.y + 2.0), text,
                HORIZONTAL_ALIGNMENT_CENTER, 900.0, size, Color(0, 0, 0, 0.85))
        p.draw_string(font, Vector2(pos_x, at.y), text,
                HORIZONTAL_ALIGNMENT_CENTER, 900.0, size, col)


func _draw_centered_box(p: Control, font: Font, text: String, at: Vector2,
                width: float, size: int, col: Color) -> void:
        if text == "":
                return
        var pos_x: float = at.x - width * 0.5
        p.draw_string(font, Vector2(pos_x, at.y + 2.0), text,
                HORIZONTAL_ALIGNMENT_CENTER, width, size, Color(0, 0, 0, 0.85))
        p.draw_string(font, Vector2(pos_x, at.y), text,
                HORIZONTAL_ALIGNMENT_CENTER, width, size, col)


func _wrap_text(text: String, width_chars: int) -> Array[String]:
        var words: PackedStringArray = text.split(" ", false)
        var lines: Array[String] = []
        var cur: String = ""
        for w in words:
                if cur.length() + w.length() + 1 > width_chars and cur != "":
                        lines.append(cur)
                        cur = w
                else:
                        cur = cur + (" " if cur != "" else "") + w
        if cur != "":
                lines.append(cur)
        return lines
