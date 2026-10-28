## ContinuesOverlay.gd — TASK 23: schermata CONTINUE? come OVERLAY.
## ============================================================
## Richiesta utente: "anche quando il giocatore 2 muore deve apparire la
## schermata dei continues per il giocatore 2 (giocatore 1 e 2 hanno crediti
## separati)".
##
## In 2P, quando un player perde l'ultima vita mentre l'altro è ancora vivo,
## il gioco SI CONGELA e appare QUESTO overlay (NON un cambio scena: il
## labirinto/i nemici/il boss restano esattamente com'erano — la ripresa è
## perfetta senza snapshot/restore). Il player morto sceglie:
##   * YES (o ENTER/A): consuma UN credito del SUO contatore (P1 e P2 hanno
##     crediti separati: il credito consumato da P1 NON tocca quello di P2
##     e viceversa) e riprende con 3 vite, energia piena e breve
##     invulnerabilità;
##   * NO / ESC / timeout 10s: il player viene ELIMINATO e l'altro continua
##     da solo (comportamento pre-esistente).
##
## In 1P il flusso resta la ContinuesScreen scene-based (snapshot restore).
##
## Pure-code CanvasLayer (pattern PauseOverlay/BonusScreen): il controller
## lo crea con ContinuesOverlay.new(), chiama setup() e ascolta
## continue_chosen. Layer 35 (sopra HUD 10, pausa 20 e bonus 30).
## Styling mirror di ContinuesScreen (bg_continues.jpg cover-fit + overlay).
extends CanvasLayer

## Emitted una sola volta alla scelta: `player_num` (1|2), `yes` (true =
## consuma credito e riprendi; false = eliminato).
signal continue_chosen(player_num: int, yes: bool)

const INPUT_GRACE_SECONDS: float = 1.0   # mirror ContinuesScreen
const COUNTDOWN_SECONDS: int = 10

var player_num: int = 1
var credits_left: int = 3

var _countdown: int = COUNTDOWN_SECONDS
var _countdown_timer: float = 0.0
var _choice: bool = true  # true = YES, false = NO
var _blink_time: float = 0.0
var _grace_timer: float = 0.0
var _finished: bool = false
var _bg_texture: Texture2D = null

var _panel: Control = null

# Colori mirror di ContinuesScreen.
const COLOR_TITLE: Color = Color(1.000, 0.843, 0.000)
const COLOR_YES: Color = Color(0.392, 0.941, 0.392)
const COLOR_NO: Color = Color(0.941, 0.235, 0.235)
const COLOR_HINT: Color = Color(0.745, 0.745, 0.745)
const COLOR_BG_OVERLAY: Color = Color(0, 0, 0, 0.62)


## `pnum`: player a cui è rivolta la schermata. `credits`: crediti RESIDUI
## di QUEL player (GameManager.continues_for(pnum)).
func setup(pnum: int, credits: int) -> void:
        player_num = pnum
        credits_left = credits


func _ready() -> void:
        layer = 35
        process_mode = Node.PROCESS_MODE_ALWAYS
        _countdown = COUNTDOWN_SECONDS
        _countdown_timer = 0.0
        _choice = true
        _finished = false
        _panel = Control.new()
        _panel.name = "ContinuesPanel"
        _panel.set_anchors_preset(Control.PRESET_FULL_RECT)
        _panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _panel.draw.connect(_draw_screen.bind(_panel))
        add_child(_panel)
        # Sfondo: stesso asset della ContinuesScreen.
        var abs_path := ProjectSettings.globalize_path(
                        "res://assets/backgrounds/bg_continues.jpg")
        if FileAccess.file_exists(abs_path):
                var img := Image.new()
                if img.load(abs_path) == OK:
                        _bg_texture = ImageTexture.create_from_image(img)
        if AudioManager:
                AudioManager.stop_music()


func _physics_process(delta: float) -> void:
        if _finished:
                return
        _blink_time += delta
        _grace_timer += delta
        _countdown_timer += delta
        if _countdown_timer >= 1.0:
                _countdown_timer = 0.0
                _countdown -= 1
                if _countdown <= 0:
                        _confirm(false)  # timeout = NO (mirror ContinuesScreen)
                        return
        _poll_input()
        _panel.queue_redraw()


# ============================================================================
# Input: tastiera GENERALE + pad del player morente (P2 usa il pad P2).
# LEFT = YES, RIGHT = NO (mirror del fix inversione di ContinuesScreen).
# ============================================================================
func _poll_input() -> void:
        # --- Navigazione tastiera ---
        if Input.is_action_just_pressed("move_left") \
                        or Input.is_action_just_pressed("p2_left"):
                _choice = true
                _play_select()
        elif Input.is_action_just_pressed("move_right") \
                        or Input.is_action_just_pressed("p2_right"):
                _choice = false
                _play_select()

        # --- Joystick del player morente: D-pad + asse X ---
        var joy_id: int = _resolve_joy()
        if joy_id >= 0:
                if _joy_edge(joy_id, JOY_BUTTON_DPAD_LEFT):
                        _choice = true
                        _play_select()
                elif _joy_edge(joy_id, JOY_BUTTON_DPAD_RIGHT):
                        _choice = false
                        _play_select()
                var axis_x: float = Input.get_joy_axis(joy_id, JOY_AXIS_LEFT_X)
                if axis_x < -0.5:
                        _choice = true
                elif axis_x > 0.5:
                        _choice = false

        # --- Conferma (dopo la grazia input) ---
        if _grace_timer < INPUT_GRACE_SECONDS:
                return
        var confirmed: bool = false
        if Input.is_action_just_pressed("shoot") \
                        or Input.is_action_just_pressed("confirm") \
                        or Input.is_action_just_pressed("p2_shoot"):
                confirmed = true
        if not confirmed and joy_id >= 0:
                var btn: int = _configured_shoot_button()
                if btn >= 0:
                        confirmed = _joy_edge(joy_id, btn)
                if not confirmed:
                        confirmed = _joy_edge(joy_id, JOY_BUTTON_A)
        if confirmed:
                _confirm(_choice)


## Il pad del player a cui è rivolta la schermata (P2 → pad configurato P2).
func _resolve_joy() -> int:
        var pads: Array = Input.get_connected_joypads()
        if player_num == 2 and ConfigManager:
                if ConfigManager.joy2_id() >= 0 and pads.has(ConfigManager.joy2_id()):
                        return ConfigManager.joy2_id()
                var p1_joy: int = ConfigManager.joy_id() if ConfigManager else -1
                for pad_id in pads:
                        if pad_id != p1_joy:
                                return pad_id
                return -1
        if ConfigManager and ConfigManager.joy_id() >= 0 \
                        and pads.has(ConfigManager.joy_id()):
                return ConfigManager.joy_id()
        if pads.size() > 0:
                return pads[0]
        return -1


func _configured_shoot_button() -> int:
        if player_num == 2 and ConfigManager:
                return ConfigManager.joy2_shoot() if ConfigManager else -1
        return ConfigManager.joy_shoot() if ConfigManager else -1


func _joy_edge(joy_id: int, btn: int) -> bool:
        var key: String = str(joy_id) + ":" + str(btn)
        var now: bool = Input.is_joy_button_pressed(joy_id, btn)
        var prev: bool = bool(_prev_joy_btns.get(key, false))
        _prev_joy_btns[key] = now
        return now and not prev


var _prev_joy_btns: Dictionary = {}


func _play_select() -> void:
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.MENU_SELECT)


func _confirm(yes: bool) -> void:
        if _finished:
                return
        _finished = true
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.MENU_CONFIRM)
        continue_chosen.emit(player_num, yes)


# ============================================================================
# Rendering (mirror ContinuesScreen, con titolo PLAYER N e crediti propri)
# ============================================================================
func _draw_screen(p: Control) -> void:
        var vp: Vector2 = p.get_viewport_rect().size
        var font: Font = ThemeDB.fallback_font
        if font == null:
                return
        # Sfondo cover-fit + overlay scuro.
        if _bg_texture:
                var tex_size: Vector2 = _bg_texture.get_size()
                var scale_val: float = max(vp.x / tex_size.x, vp.y / tex_size.y)
                var draw_size: Vector2 = tex_size * scale_val
                var draw_pos: Vector2 = (vp - draw_size) / 2.0
                p.draw_texture_rect(_bg_texture, Rect2(draw_pos, draw_size), false)
        else:
                p.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.02, 0.02, 0.04, 1.0), true)
        p.draw_rect(Rect2(Vector2.ZERO, vp), COLOR_BG_OVERLAY, true)

        var cx: float = vp.x * 0.5
        # Titolo: PLAYER N + CONTINUE?
        # TASK 79b: "PLAYER N" localizzato (hud.player); "CONTINUE?" resta
        # in inglese in entrambe le lingue (termine arcade, richiesta Task 44).
        var p_col: Color = Color(0.39, 0.78, 1.0) if player_num == 1 \
                        else Color(1.0, 0.59, 0.39)
        var p_title: String = "PLAYER %d" % player_num
        if I18n:
                p_title = I18n.t("hud.player") % player_num
        _text_centered(p, font, p_title,
                Vector2(cx, 92.0), 40, p_col)
        _text_centered(p, font, "CONTINUE?",
                Vector2(cx, 158.0), 64, COLOR_TITLE)

        # Countdown (lampeggia negli ultimi secondi).
        var count_color: Color = COLOR_TITLE if _countdown > 5 \
                        else Color(1, 0.3, 0.2)
        if _countdown <= 3:
                count_color.a = 0.5 + 0.5 * sin(_blink_time * 15.0)
        _text_centered(p, font, str(_countdown),
                Vector2(cx, 290.0), 72, count_color)

        # YES / NO (LEFT = YES, RIGHT = NO). TASK 79b: localizzati (SÌ/NO).
        var yes_color: Color = COLOR_YES if _choice else COLOR_YES.darkened(0.5)
        var no_color: Color = COLOR_NO if not _choice else COLOR_NO.darkened(0.5)
        var yes_txt: String = "YES"
        var no_txt: String = "NO"
        if I18n:
                yes_txt = I18n.t("cont.yes")
                no_txt = I18n.t("cont.no")
        if _choice:
                _text_centered(p, font, ">", Vector2(cx - 150.0, 430.0), 36, COLOR_TITLE, 60.0)
        else:
                _text_centered(p, font, ">", Vector2(cx + 110.0, 430.0), 36, COLOR_TITLE, 60.0)
        _text_centered(p, font, yes_txt, Vector2(cx - 120.0, 430.0), 40, yes_color, 150.0)
        _text_centered(p, font, no_txt, Vector2(cx + 60.0, 430.0), 40, no_color, 150.0)

        # Crediti RESIDUI di QUESTO player (contatore separato).
        # TASK 79b: riga localizzata (cont.p_left) + hint (cont.hint).
        var left_txt: String = "PLAYER %d CONTINUES LEFT: %d" % [player_num, credits_left]
        if I18n:
                left_txt = I18n.t("cont.p_left") % [player_num, credits_left]
        _text_centered(p, font, left_txt,
                Vector2(cx, 520.0), 24, COLOR_HINT)
        var hint_txt: String = "LEFT/RIGHT TO SELECT - ENTER TO CONFIRM"
        if I18n:
                hint_txt = I18n.t("cont.hint")
        _text_centered(p, font, hint_txt,
                Vector2(cx, 570.0), 18, COLOR_HINT)


func _text_centered(p: Control, font: Font, text: String, at: Vector2,
                size_px: int, col: Color, box_w: float = 700.0) -> void:
        if text == "":
                return
        var pos_x: float = at.x - box_w * 0.5
        p.draw_string(font, Vector2(pos_x, at.y + 2.0), text,
                HORIZONTAL_ALIGNMENT_CENTER, box_w, size_px, Color(0, 0, 0, 0.85))
        p.draw_string(font, Vector2(pos_x, at.y), text,
                HORIZONTAL_ALIGNMENT_CENTER, box_w, size_px, col)
