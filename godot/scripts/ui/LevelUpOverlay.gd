## LevelUpOverlay.gd — TASK 99 (Level Up), FASE 2.
##
## MODALE DELLE ABILITÀ che si apre in pausa alla fine dell'annuncio del
## level up (pattern BonusCardOverlay / BonusScreen: pure-code CanvasLayer,
## layer 28, PROCESS_MODE_ALWAYS, gioco fermo con get_tree().paused).
##
## Struttura (report Task 98 §4.4): finestra scura in stile card bonus con
## la tabella delle otto abilità. Ogni riga: icona, nome IT + EN, descrizione
## breve, livello attuale ("3/10") e pulsanti +/− per alzare o togliere
## L'ASSEGNAZIONE CORRENTE (niente è definitivo finché non si preme OK).
## In alto il contatore dei punti non ancora spesi; in fondo il tasto OK
## (TENUTO PREMUTO ~450ms, come le card reliquia): conferma e rende
## definitive le scelte; se non si è scelto nulla il punto resta accumulato
## per il level up successivo (BANCABILE).
##
## Input: SU/GIÙ navigazione, DESTRA/SINISTRA +/− della riga selezionata,
## fuoco tenuto = OK. In 2P ogni giocatore usa i SUOI tasti (p2_*) e le
## modali si aprono in sequenza (prima P1 poi P2, guidate dal controller).
## Il Salto Aggiuntivo è l'unica riga con requisito PER LIVELLO: il 1° si
## sblocca a Resistenza 10, il 2° a Resistenza 40 (cap), il 3° NON è
## sbloccabile e la sua opzione resta VISIBILE ma DISATTIVATA (richiesta
## utente: "si vedrà disattivata l'opzione"). Il requisito valuta anche
## le assegnazioni di QUESTA sessione (si può comprare Resistenza fino
## alla soglia e poi il salto).
extends CanvasLayer

## Emitted when the player confirms (OK held). The host controller frees
## the layer, re-arms the fire gates and unpauses the tree.
signal modal_closed(player_num: int)

const C = preload("res://scripts/core/GameConstants.gd")

## Tenuta del fuoco per confermare (stessa soglia delle card reliquia).
const HOLD_CONFIRM_MS: float = 450.0
## Righe della tabella (una per abilità, ordine SKILL_IDS).
const ROW_H: float = 84.0
## Dimensione card.
const CARD_W: float = 1080.0
const CARD_H: float = 880.0

# Palette (stile card bonus: legno scuro + rifiniture oro).
const COL_VEIL: Color = Color(0.0, 0.0, 0.02, 0.80)
const COL_WOOD: Color = Color(0.16, 0.10, 0.07)
const COL_WOOD_DARK: Color = Color(0.10, 0.06, 0.04)
const COL_GOLD: Color = Color(1.0, 0.84, 0.25)
const COL_GOLD_SOFT: Color = Color(0.85, 0.68, 0.20)
const COL_TEXT: Color = Color(0.92, 0.88, 0.78)
const COL_TEXT_DIM: Color = Color(0.62, 0.58, 0.50)
const COL_LOCKED: Color = Color(0.45, 0.42, 0.38)

var _player: CharacterBody2D = null
var _player_num: int = 1
var _base_levels: Dictionary = {}   # livelli confermati (id -> int)
var _alloc: Dictionary = {}         # assegnazioni di QUESTA sessione (id -> int)
var _bank: int = 0                  # punti NON ancora assegnati (bancabili)
var _row: int = 0                   # riga selezionata (0..7)
var _hold_ms: float = 0.0           # tenuta del fuoco per l'OK
var _fire_armed: bool = false       # gate anti-ghost: serve un RILASCIO
var _t: float = 0.0
var _panel: Control = null
var _icons: Dictionary = {}         # id -> ImageTexture (o null: fallback)
## FASE 3: tile pietra scura + angolo ottone (4 flip) per il frame della
## card (null se gli asset mancano -> fallback piatto legno scuro).
var _stone_texture: ImageTexture = null
var _corner_tl: ImageTexture = null
var _corner_tr: ImageTexture = null
var _corner_bl: ImageTexture = null
var _corner_br: ImageTexture = null

# Edge detection joystick D-pad (pattern BonusScreen).
var _prev_joy_btns: Dictionary = {}


func setup(p: CharacterBody2D) -> void:
        _player = p
        _player_num = int(p.player_num)
        _base_levels = p.skill_levels.duplicate()
        _bank = int(p.skill_points)


func _ready() -> void:
        layer = 28
        process_mode = Node.PROCESS_MODE_ALWAYS
        _panel = Control.new()
        _panel.name = "LevelUpSkillsPanel"
        _panel.set_anchors_preset(Control.PRESET_FULL_RECT)
        _panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _panel.draw.connect(_draw_panel.bind(_panel))
        add_child(_panel)
        for id in C.SKILL_IDS:
                _icons[id] = _icon_texture(id)
        _load_frame_assets()
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.MENU_SELECT)


## FASE 3: tile pietra + angolo ottone (4 flip) per il frame della card.
## PNG-first (Image.load, pattern SpriteManager).
func _load_frame_assets() -> void:
        var stone_img := Image.new()
        var stone_abs: String = ProjectSettings.globalize_path(
                        "res://assets/sprites/skills/levelup_stone_tile.png")
        if FileAccess.file_exists(stone_abs) \
                        and stone_img.load(stone_abs) == OK:
                _stone_texture = ImageTexture.create_from_image(stone_img)
        var corner_img := Image.new()
        var corner_abs: String = ProjectSettings.globalize_path(
                        "res://assets/sprites/skills/levelup_corner.png")
        if FileAccess.file_exists(corner_abs) \
                        and corner_img.load(corner_abs) == OK:
                _corner_tl = ImageTexture.create_from_image(corner_img)
                var flip_x: Image = corner_img.duplicate()
                flip_x.flip_x()
                _corner_tr = ImageTexture.create_from_image(flip_x)
                var flip_y: Image = corner_img.duplicate()
                flip_y.flip_y()
                _corner_bl = ImageTexture.create_from_image(flip_y)
                var flip_xy: Image = corner_img.duplicate()
                flip_xy.flip_x()
                flip_xy.flip_y()
                _corner_br = ImageTexture.create_from_image(flip_xy)


# ---------------------------------------------------------------------------
# Input (tastiera + joystick, P1 o P2 a seconda di chi è salito di livello)
# ---------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
        _t += delta
        var is_p2: bool = _player_num == 2
        # --- navigazione su/giù ---
        if _edge_kb("move_up" if not is_p2 else "p2_up", "move_down" if not is_p2 else "p2_down"):
                pass  # gestita dentro _edge_kb
        # --- +/− della riga selezionata ---
        if not is_p2:
                if Input.is_action_just_pressed("move_right"):
                        _try_alloc(1)
                elif Input.is_action_just_pressed("move_left"):
                        _try_alloc(-1)
        else:
                if Input.is_action_just_pressed("p2_right"):
                        _try_alloc(1)
                elif Input.is_action_just_pressed("p2_left"):
                        _try_alloc(-1)
        _poll_joystick(is_p2)
        # --- OK: fuoco TENUTO (dopo un rilascio preliminare) ---
        var fire: bool = _fire_held(is_p2)
        if not fire:
                _fire_armed = true
                _hold_ms = 0.0
        elif _fire_armed:
                _hold_ms += delta * 1000.0
                if _hold_ms >= HOLD_CONFIRM_MS:
                        _confirm()
                        return
        else:
                _hold_ms = 0.0
        _panel.queue_redraw()


## Navigazione verticale con debounce (le action move_* sono "pressed"
## ripetute: si usa just_pressed).
func _edge_kb(up_action: String, down_action: String) -> bool:
        if Input.is_action_just_pressed(up_action):
                _row = (_row - 1 + C.SKILL_IDS.size()) % C.SKILL_IDS.size()
                if AudioManager:
                        AudioManager.play_sound(AudioManager.SoundType.MENU_SELECT)
                return true
        if Input.is_action_just_pressed(down_action):
                _row = (_row + 1) % C.SKILL_IDS.size()
                if AudioManager:
                        AudioManager.play_sound(AudioManager.SoundType.MENU_SELECT)
                return true
        return false


## D-pad del joystick configurato (P1: ConfigManager.joy_id, P2: secondo
## pad o pad configurato; fallback dpad del primo pad libero).
func _poll_joystick(is_p2: bool) -> void:
        var joy: int = _resolve_joy(is_p2)
        if joy < 0:
                return
        var dpad := {
                JOY_BUTTON_DPAD_UP: -1, JOY_BUTTON_DPAD_DOWN: 1,
                JOY_BUTTON_DPAD_LEFT: -1, JOY_BUTTON_DPAD_RIGHT: 1,
        }
        for btn in dpad.keys():
                var pressed: bool = Input.is_joy_button_pressed(joy, btn)
                var was: bool = bool(_prev_joy_btns.get(btn, false))
                _prev_joy_btns[btn] = pressed
                if pressed and not was:
                        if btn == JOY_BUTTON_DPAD_UP:
                                _row = (_row - 1 + C.SKILL_IDS.size()) % C.SKILL_IDS.size()
                                if AudioManager:
                                        AudioManager.play_sound(AudioManager.SoundType.MENU_SELECT)
                        elif btn == JOY_BUTTON_DPAD_DOWN:
                                _row = (_row + 1) % C.SKILL_IDS.size()
                                if AudioManager:
                                        AudioManager.play_sound(AudioManager.SoundType.MENU_SELECT)
                        elif btn == JOY_BUTTON_DPAD_RIGHT:
                                _try_alloc(1)
                        elif btn == JOY_BUTTON_DPAD_LEFT:
                                _try_alloc(-1)


func _resolve_joy(is_p2: bool) -> int:
        var pads: Array = Input.get_connected_joypads()
        if pads.is_empty():
                return -1
        if not is_p2 and ConfigManager and ConfigManager.joy_id() >= 0 \
                        and pads.has(ConfigManager.joy_id()):
                return ConfigManager.joy_id()
        if is_p2:
                # P2: il pad che NON e' di P1 (o il primo se P1 non ha pad).
                var p1_joy: int = ConfigManager.joy_id() if ConfigManager else -1
                for pad in pads:
                        if int(pad) != p1_joy:
                                return int(pad)
        return int(pads[0])


func _fire_held(is_p2: bool) -> bool:
        var held: bool = false
        if not is_p2:
                held = Input.is_action_pressed("shoot") \
                                or Input.is_action_pressed("confirm")
        else:
                held = Input.is_action_pressed("p2_shoot")
        var joy: int = _resolve_joy(is_p2)
        if joy >= 0:
                var btn: int = -1
                if not is_p2 and ConfigManager:
                        btn = ConfigManager.joy_shoot()
                elif is_p2 and ConfigManager:
                        btn = ConfigManager.joy2_shoot()
                if btn < 0:
                        btn = JOY_BUTTON_B
                held = held or Input.is_joy_button_pressed(joy, btn)
        return held


# ---------------------------------------------------------------------------
# Logica assegnazione
# ---------------------------------------------------------------------------
## Livelli VISUAL correnti (confermati + assegnati in sessione).
func _visual_levels() -> Dictionary:
        var out: Dictionary = {}
        for id in C.SKILL_IDS:
                out[id] = int(_base_levels.get(id, 0)) + int(_alloc.get(id, 0))
        return out


## +1 / -1 sulla riga selezionata. Il + rispetta cap e requisiti e prende
## un punto dal banco; il − restituisce il punto al banco.
func _try_alloc(dir: int) -> void:
        var id: String = C.SKILL_IDS[_row]
        if dir > 0:
                if _bank <= 0:
                        if AudioManager:
                                AudioManager.play_sound(AudioManager.SoundType.STAMINA_CLICK)
                        return
                if not C.skill_upgrade_allowed(id, _visual_levels()):
                        if AudioManager:
                                AudioManager.play_sound(AudioManager.SoundType.STAMINA_CLICK)
                        return
                _alloc[id] = int(_alloc.get(id, 0)) + 1
                _bank -= 1
                if AudioManager:
                        AudioManager.play_sound(AudioManager.SoundType.MENU_SELECT)
        else:
                var cur: int = int(_alloc.get(id, 0))
                if cur <= 0:
                        return
                _alloc[id] = cur - 1
                _bank += 1
                # Se tolgo Resistenza sotto la soglia, il Salto assegnato
                # oltre il requisito torna indisponibile: le assegnazioni in
                # eccesso vengono rimesse nel banco (mai stato illegale).
                _clamp_jump_alloc()
                if AudioManager:
                        AudioManager.play_sound(AudioManager.SoundType.MENU_SELECT)


## Coerenza requisito Salto: con la Resistenza (visual) corrente si può
## comprare il salto solo fino al livello la cui soglia è soddisfatta
## (1° >= 10, 2° >= 40, 3° mai): le assegnazioni della sessione oltre il
## livello permesso tornano al banco.
func _clamp_jump_alloc() -> void:
        var vis: Dictionary = _visual_levels()
        var stamina_lvl: int = int(vis.get("stamina", 0))
        # Livello di salto raggiungibile con questa Resistenza (sequenziale:
        # per comprare il 2° serve la soglia del 2°; il 3° non è mai in vendita).
        var allowed_total: int = int(_base_levels.get("jump", 0))
        var jump_cap: int = int(C.get_skill_def("jump").get("cap", 3))
        while allowed_total < jump_cap:
                var req: int = C.skill_jump_required_stamina(allowed_total + 1)
                if req >= 0 and stamina_lvl >= req:
                        allowed_total += 1
                else:
                        break
        var jump_visual: int = int(vis.get("jump", 0))
        if jump_visual <= allowed_total:
                return
        # Le assegnazioni di SESSIONE in eccesso tornano nel banco (le
        # confermate restano: sono state comprate con la soglia soddisfatta).
        var jump_base: int = int(_base_levels.get("jump", 0))
        var excess: int = mini(int(_alloc.get("jump", 0)),
                        jump_visual - maxi(allowed_total, jump_base))
        if excess > 0:
                _bank += excess
                _alloc["jump"] = int(_alloc.get("jump", 0)) - excess


## OK: rende definitive le scelte e chiude. I punti non assegnati restano
## bancati sul player (si sommano al prossimo level up).
func _confirm() -> void:
        var merged: Dictionary = _visual_levels()
        if _player != null and is_instance_valid(_player):
                _player.skill_points = _bank
                _player.confirm_skills(merged)
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.MENU_CONFIRM)
        modal_closed.emit(_player_num)


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------
func _icon_texture(id: String) -> ImageTexture:
        # FASE 3: icone PixelLab 64x64 (skill_<id>.png). PNG-first con
        # Image.load (pattern SpriteManager: bypassa l'import system).
        var path := "res://assets/sprites/skills/skill_%s.png" % id
        var abs_path: String = ProjectSettings.globalize_path(path)
        if not FileAccess.file_exists(abs_path):
                return null
        var img := Image.new()
        if img.load(abs_path) == OK:
                return ImageTexture.create_from_image(img)
        return null


func _draw_panel(p: Control) -> void:
        var font := ThemeDB.fallback_font
        var vp: Vector2 = p.size
        if vp.x <= 1.0:
                vp = Vector2(1920.0, 1080.0)
        var card_w: float = minf(CARD_W, vp.x * 0.94)
        var card_h: float = minf(CARD_H, vp.y * 0.95)
        var cx: float = vp.x * 0.5
        var cy: float = vp.y * 0.5
        var card_x: float = cx - card_w * 0.5
        var card_y: float = cy - card_h * 0.5

        # --- velo + card con doppio bordo legno/oro ---------------------
        p.draw_rect(Rect2(Vector2.ZERO, vp), COL_VEIL, true)
        p.draw_rect(Rect2(card_x, card_y, card_w, card_h), COL_WOOD, true)
        # FASE 3: riempimento in TILE DI PIETRA PixelLab (tinta scura per
        # tenere il contrasto del testo chiaro; fallback legno piatto).
        if _stone_texture != null:
                var inner: Rect2 = Rect2(card_x + 6.0, card_y + 6.0,
                                card_w - 12.0, card_h - 12.0)
                var tile: float = 256.0
                var tint: Color = Color(0.62, 0.58, 0.55)
                var nx: int = int(ceil(inner.size.x / tile))
                var ny: int = int(ceil(inner.size.y / tile))
                for gx in nx:
                        for gy in ny:
                                var r: Rect2 = Rect2(
                                                inner.position.x + float(gx) * tile,
                                                inner.position.y + float(gy) * tile,
                                                minf(tile, inner.end.x - (inner.position.x + float(gx) * tile)),
                                                minf(tile, inner.end.y - (inner.position.y + float(gy) * tile)))
                                p.draw_texture_rect(_stone_texture, r, false, tint)
        else:
                p.draw_rect(Rect2(card_x + 6.0, card_y + 6.0,
                                card_w - 12.0, card_h - 12.0), COL_WOOD_DARK, true)
        p.draw_rect(Rect2(card_x, card_y, card_w, card_h), COL_GOLD_SOFT, false, 3.0)
        p.draw_rect(Rect2(card_x + 6.0, card_y + 6.0,
                        card_w - 12.0, card_h - 12.0), COL_GOLD, false, 1.5)
        # FASE 3: angoli decorati in ottone (4 flip).
        if _corner_tl != null:
                var cs: float = 56.0
                p.draw_texture_rect(_corner_tl,
                                Rect2(card_x + 10.0, card_y + 10.0, cs, cs), false)
                p.draw_texture_rect(_corner_tr,
                                Rect2(card_x + card_w - 10.0 - cs, card_y + 10.0, cs, cs), false)
                p.draw_texture_rect(_corner_bl,
                                Rect2(card_x + 10.0, card_y + card_h - 10.0 - cs, cs, cs), false)
                p.draw_texture_rect(_corner_br,
                                Rect2(card_x + card_w - 10.0 - cs, card_y + card_h - 10.0 - cs, cs, cs), false)

        # --- header: LEVEL UP! + giocatore + PUNTI banco ---------------
        var title: String = I18n.t("levelup.title")
        var ty: float = card_y + 66.0
        _draw_text_centered(p, font, title, Vector2(card_x + card_w * 0.35, ty),
                        46, COL_GOLD, card_w * 0.6)
        if GameManager != null and GameManager.num_players == 2:
                _draw_text_centered(p, font, I18n.t("hud.player") % _player_num,
                                Vector2(card_x + card_w * 0.35, ty + 30.0),
                                18, Color(0.75, 0.80, 0.92), card_w * 0.5)
        # contatore punti (a destra, lampeggia se > 0)
        var bank_label: String = I18n.t("levelup.points") % _bank
        var bank_col: Color = COL_GOLD if _bank > 0 else COL_TEXT_DIM
        if _bank > 0:
                var blink: float = 0.70 + 0.30 * sin(_t * 6.0)
                bank_col = Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b, blink)
        p.draw_string(font, Vector2(card_x + card_w - 300.0, ty),
                        bank_label, HORIZONTAL_ALIGNMENT_LEFT, 280.0, 30, bank_col)

        # --- tabella: una riga per abilità ------------------------------
        var table_x: float = card_x + 26.0
        var table_w: float = card_w - 52.0
        var table_y: float = card_y + 128.0
        var row_h: float = ROW_H
        var vis: Dictionary = _visual_levels()
        for i in C.SKILL_IDS.size():
                _draw_skill_row(p, font, C.SKILL_IDS[i], i, vis,
                                Rect2(table_x, table_y + row_h * float(i),
                                                table_w, row_h - 6.0))

        # --- footer: hint + barra OK + nota banking --------------------
        var fy: float = card_y + card_h - 118.0
        var hint: String = I18n.t("levelup.hint")
        _draw_text_centered(p, font, hint, Vector2(cx, fy), 16,
                        COL_TEXT_DIM, card_w - 80.0)
        # barra OK (hold del fuoco)
        var bar_w: float = 420.0
        var bar_x: float = cx - bar_w * 0.5
        var bar_y: float = fy + 22.0
        p.draw_rect(Rect2(bar_x, bar_y, bar_w, 18.0), Color(0, 0, 0, 0.65), true)
        var frac: float = clampf(_hold_ms / HOLD_CONFIRM_MS, 0.0, 1.0)
        if frac > 0.0:
                p.draw_rect(Rect2(bar_x + 2.0, bar_y + 2.0,
                                (bar_w - 4.0) * frac, 14.0),
                                Color(0.45, 0.95, 0.35), true)
        p.draw_rect(Rect2(bar_x, bar_y, bar_w, 18.0), COL_GOLD_SOFT, false, 1.5)
        _draw_text_centered(p, font, I18n.t("levelup.ok_hold"),
                        Vector2(cx, bar_y + 40.0), 20, COL_TEXT, card_w)
        # nota bancabilità
        _draw_text_centered(p, font, I18n.t("levelup.banked"),
                        Vector2(cx, bar_y + 64.0), 14,
                        Color(0.55, 0.52, 0.45), card_w)


func _draw_skill_row(p: Control, font: Font, id: String, row_idx: int,
                vis: Dictionary, rect: Rect2) -> void:
        var def: Dictionary = C.get_skill_def(id)
        if def.is_empty():
                return
        var selected: bool = row_idx == _row
        var col: Color = def.get("color", Color.WHITE)
        var lvl: int = int(vis.get(id, 0))
        var cap: int = int(def.get("cap", 10))
        var allowed: bool = C.skill_upgrade_allowed(id, vis)
        var allocated: int = int(_alloc.get(id, 0))

        # sfondo riga + selezione
        if selected:
                var pulse: float = 0.5 + 0.5 * sin(_t * 5.0)
                p.draw_rect(rect, Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b,
                                0.10 + 0.06 * pulse), true)
                p.draw_rect(rect, Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b,
                                0.55 + 0.35 * pulse), false, 2.0)
        else:
                p.draw_rect(rect, Color(0, 0, 0, 0.28), true)

        # icona (PNG PixelLab in FASE 3, fallback glifo procedurale)
        var icon_rect: Rect2 = Rect2(rect.position.x + 12.0,
                        rect.position.y + (rect.size.y - 56.0) * 0.5, 56.0, 56.0)
        var tex: ImageTexture = _icons.get(id)
        if tex != null:
                p.draw_texture_rect(tex, icon_rect, false)
        else:
                _draw_icon_fallback(p, id, icon_rect, col)

        # nome IT + EN
        var name_it: String = str(def.get("name_it", id))
        var name_en: String = str(def.get("name_en", id))
        var nx: float = rect.position.x + 84.0
        p.draw_string(font, Vector2(nx + 1.5, rect.position.y + 27.0), name_it,
                        HORIZONTAL_ALIGNMENT_LEFT, 420.0, 22,
                        Color(0, 0, 0, 0.8))
        p.draw_string(font, Vector2(nx, rect.position.y + 25.0), name_it,
                        HORIZONTAL_ALIGNMENT_LEFT, 420.0, 22, COL_TEXT)
        p.draw_string(font, Vector2(nx, rect.position.y + 45.0), name_en,
                        HORIZONTAL_ALIGNMENT_LEFT, 420.0, 15, COL_TEXT_DIM)
        # descrizione + per-livello
        var desc: String = str(def.get("desc_it", ""))
        p.draw_string(font, Vector2(nx, rect.position.y + 64.0), desc,
                        HORIZONTAL_ALIGNMENT_LEFT, 520.0, 13, COL_TEXT_DIM)
        p.draw_string(font, Vector2(nx + 430.0, rect.position.y + 64.0),
                        str(def.get("per", "")),
                        HORIZONTAL_ALIGNMENT_LEFT, 160.0, 13,
                        Color(col.r, col.g, col.b, 0.9))

        # livello attuale "3/10" (le assegnazioni di sessione contano)
        var lvl_str: String = "%d/%d" % [lvl, cap]
        var lvl_col: Color = col if lvl > 0 else COL_TEXT_DIM
        p.draw_string(font, Vector2(rect.position.x + rect.size.x - 240.0,
                        rect.position.y + 34.0), lvl_str,
                        HORIZONTAL_ALIGNMENT_LEFT, 90.0, 24, lvl_col)

        # pulsanti − / + (disegnati; abilitati secondo regole)
        var minus_x: float = rect.position.x + rect.size.x - 140.0
        var plus_x: float = rect.position.x + rect.size.x - 76.0
        var by: float = rect.position.y + 14.0
        _draw_button(p, font, "−", Rect2(minus_x, by, 52.0, 36.0),
                        allocated > 0, selected)
        var plus_on: bool = allowed and _bank > 0
        _draw_button(p, font, "+", Rect2(plus_x, by, 52.0, 36.0),
                        plus_on, selected)

        # badge requisito / cap / mai-sbloccabile
        if id == "jump":
                # Salto Aggiuntivo: badge DEDICATO per livello. Il 3° salto ha
                # requisito -1 (MAI acquistabile) e la sua opzione appare
                # DISATTIVATA in grigio scuro (richiesta utente: "si vedrà
                # disattivata l'opzione"); il 1°/2° mostrano la Resistenza
                # richiesta (10 / 40).
                var next_req: int = C.skill_jump_required_stamina(lvl + 1)
                if next_req < 0 and lvl < cap:
                        p.draw_string(font, Vector2(rect.position.x + rect.size.x - 240.0,
                                        rect.position.y + 60.0),
                                        I18n.t("levelup.never"),
                                        HORIZONTAL_ALIGNMENT_LEFT, 220.0, 13,
                                        Color(0.38, 0.36, 0.33))
                elif not allowed and lvl < cap:
                        p.draw_string(font, Vector2(rect.position.x + rect.size.x - 240.0,
                                        rect.position.y + 60.0),
                                        I18n.t("levelup.locked") % next_req,
                                        HORIZONTAL_ALIGNMENT_LEFT, 220.0, 13, COL_LOCKED)
        elif not allowed and lvl < cap:
                p.draw_string(font, Vector2(rect.position.x + rect.size.x - 240.0,
                                rect.position.y + 60.0),
                                I18n.t("levelup.locked") % 0,
                                HORIZONTAL_ALIGNMENT_LEFT, 220.0, 13, COL_LOCKED)
        if lvl >= cap:
                        p.draw_string(font, Vector2(rect.position.x + rect.size.x - 240.0,
                            rect.position.y + 60.0), I18n.t("levelup.max"),
                            HORIZONTAL_ALIGNMENT_LEFT, 220.0, 13, COL_LOCKED)


func _draw_button(p: Control, font: Font, label: String, r: Rect2,
                enabled: bool, selected: bool) -> void:
        var bg: Color = Color(0.22, 0.15, 0.08) if enabled else Color(0.12, 0.10, 0.08, 0.6)
        p.draw_rect(r, bg, true)
        var border: Color = COL_GOLD_SOFT if enabled else Color(0.35, 0.30, 0.22, 0.5)
        if selected and enabled:
                border = COL_GOLD
        p.draw_rect(r, border, false, 2.0)
        var txt_col: Color = COL_GOLD if enabled else Color(0.45, 0.42, 0.38)
        p.draw_string(font, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + 10.0),
                        label, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 26, txt_col)


## Glifi procedurali di ripiego (FASE 3: icone PixelLab 64px sostituiranno
## questi disegni — il caricamento PNG-first e' gia' attivo).
func _draw_icon_fallback(p: Control, id: String, r: Rect2, col: Color) -> void:
        p.draw_rect(r, Color(col.r * 0.18, col.g * 0.18, col.b * 0.18, 0.9), true)
        p.draw_rect(r, Color(col.r, col.g, col.b, 0.6), false, 2.0)
        var c: Vector2 = r.position + r.size * 0.5
        var s: float = r.size.x * 0.5
        match id:
                "energy":  # cuore
                        p.draw_colored_polygon(PackedVector2Array([
                                Vector2(c.x - s * 0.45, c.y - s * 0.2),
                                Vector2(c.x - s * 0.15, c.y - s * 0.45),
                                Vector2(c.x + s * 0.15, c.y - s * 0.45),
                                Vector2(c.x + s * 0.45, c.y - s * 0.2),
                                Vector2(c.x, c.y + s * 0.5)]), col)
                "stamina":  # saetta
                        p.draw_colored_polygon(PackedVector2Array([
                                Vector2(c.x + s * 0.1, c.y - s * 0.5),
                                Vector2(c.x - s * 0.3, c.y + s * 0.05),
                                Vector2(c.x - s * 0.05, c.y + s * 0.05),
                                Vector2(c.x - s * 0.1, c.y + s * 0.5),
                                Vector2(c.x + s * 0.3, c.y - s * 0.05),
                                Vector2(c.x + s * 0.05, c.y - s * 0.05)]), col)
                "jump":  # doppia freccia su
                        for k in 2:
                                var yy: float = c.y + s * 0.35 - float(k) * s * 0.5
                                p.draw_colored_polygon(PackedVector2Array([
                                        Vector2(c.x, yy - s * 0.22),
                                        Vector2(c.x - s * 0.3, yy + s * 0.12),
                                        Vector2(c.x - s * 0.12, yy + s * 0.12),
                                        Vector2(c.x - s * 0.12, yy + s * 0.38),
                                        Vector2(c.x + s * 0.12, yy + s * 0.38),
                                        Vector2(c.x + s * 0.12, yy + s * 0.12),
                                        Vector2(c.x + s * 0.3, yy + s * 0.12)]), col)
                "firepower":  # spada
                        p.draw_rect(Rect2(c.x - s * 0.06, c.y - s * 0.5,
                                        s * 0.12, s * 0.7), col)
                        p.draw_rect(Rect2(c.x - s * 0.25, c.y + s * 0.2,
                                        s * 0.5, s * 0.08), col)
                        p.draw_rect(Rect2(c.x - s * 0.06, c.y + s * 0.28,
                                        s * 0.12, s * 0.22), col)
                "magazine":  # caricatore
                        p.draw_rect(Rect2(c.x - s * 0.18, c.y - s * 0.45,
                                        s * 0.36, s * 0.9), col)
                        for k in 4:
                                p.draw_rect(Rect2(c.x - s * 0.28,
                                                c.y - s * 0.35 + float(k) * s * 0.22,
                                                s * 0.56, s * 0.08),
                                                Color(0.1, 0.08, 0.06))
                "swiftness":  # stivale alato stilizzato
                        p.draw_rect(Rect2(c.x - s * 0.1, c.y - s * 0.45,
                                        s * 0.2, s * 0.55), col)
                        p.draw_rect(Rect2(c.x - s * 0.1, c.y + s * 0.1,
                                        s * 0.45, s * 0.16), col)
                        p.draw_rect(Rect2(c.x - s * 0.42, c.y - s * 0.3,
                                        s * 0.26, s * 0.09),
                                        Color(col.r, col.g, col.b, 0.7))
                "luck":  # quadrifoglio (4 cerchi)
                        for k in 4:
                                var ang: float = TAU * float(k) / 4.0 + PI / 4.0
                                p.draw_circle(c + Vector2(cos(ang), sin(ang)) * s * 0.2,
                                                s * 0.2, col)
                "regen":  # croce medicinale
                        p.draw_rect(Rect2(c.x - s * 0.1, c.y - s * 0.45,
                                        s * 0.2, s * 0.9), col)
                        p.draw_rect(Rect2(c.x - s * 0.45, c.y - s * 0.1,
                                        s * 0.9, s * 0.2), col)


func _draw_text_centered(p: Control, font: Font, text: String, at: Vector2,
                size: int, col: Color, box_w: float = 900.0) -> void:
        var pos_x: float = at.x - box_w * 0.5
        p.draw_string(font, Vector2(pos_x, at.y + 2.0), text,
                        HORIZONTAL_ALIGNMENT_CENTER, box_w, size,
                        Color(0, 0, 0, 0.85))
        p.draw_string(font, Vector2(pos_x, at.y), text,
                        HORIZONTAL_ALIGNMENT_CENTER, box_w, size, col)
