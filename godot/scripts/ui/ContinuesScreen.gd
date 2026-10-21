## ContinuesScreen.gd
## ============================================================
## Porting of Game.cpp STATE_CONTINUES.
## Shows "CONTINUE?" with a 10-second countdown and Yes/No selector.
## Background uses bg_continues.jpg.
##
## On Yes: GameManager.use_continue() (resumes at boss or current level)
## On No / timeout: GameManager.give_up() (goes to LOSE -> menu)
## ============================================================
extends Control

signal continue_used()
signal give_up_requested()

# FIX (continue consumato involontariamente — mirror LoseScreen): la
# pressione residua del tasto di salto livelli (SPACE in test mode) o del
# tasto fuoco del joystick, riflessa sulla schermata CONTINUE? appena comparsa,
# confermava subito YES e consumava un credito senza che il player lo
# volesse. GRAZIA INPUT: per i primi INPUT_GRACE_SECONDS la schermata non
# accetta conferme (la navigazione LEFT/RIGHT resta subito disponibile).
const INPUT_GRACE_SECONDS: float = 1.0

@export var color_title:    Color = Color(1.000, 0.843, 0.000)
@export var color_yes:      Color = Color(0.392, 0.941, 0.392)
@export var color_no:       Color = Color(0.941, 0.235, 0.235)
@export var color_hint:     Color = Color(0.745, 0.745, 0.745)
@export var color_bg_overlay: Color = Color(0, 0, 0, 0.55)

var _countdown: int = 10
var _countdown_timer: float = 0.0
var _choice: bool = true  # true = YES, false = NO
var _blink_time: float = 0.0
var _bg_texture: Texture2D = null
var _finished: bool = false
var _grace_timer: float = 0.0


func _ready() -> void:
        set_anchors_preset(Control.PRESET_FULL_RECT)
        mouse_filter = Control.MOUSE_FILTER_STOP
        focus_mode = Control.FOCUS_ALL
        _countdown = 10
        _countdown_timer = 0.0
        _choice = true
        _finished = false
        # Load continues background.
        var _abs := ProjectSettings.globalize_path("res://assets/backgrounds/bg_continues.jpg")
        if FileAccess.file_exists(_abs):
                var _img := Image.new()
                if _img.load(_abs) == OK:
                        _bg_texture = ImageTexture.create_from_image(_img)
        if AudioManager:
                AudioManager.stop_music()


func _process(delta: float) -> void:
        if _finished:
                return
        _blink_time += delta
        _grace_timer += delta
        _countdown_timer += delta
        if _countdown_timer >= 1.0:
                _countdown_timer = 0.0
                _countdown -= 1
                if _countdown <= 0:
                        _on_timeout()
                        return
        queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
        if _finished:
                return
        if event is InputEventKey and event.pressed and not event.echo:
                match event.keycode:
                        KEY_LEFT, KEY_A:
                                _choice = false
                                if AudioManager:
                                        AudioManager.play_sound(AudioManager.SoundType.MENU_SELECT)
                        KEY_RIGHT, KEY_D:
                                _choice = true
                                if AudioManager:
                                        AudioManager.play_sound(AudioManager.SoundType.MENU_SELECT)
                        KEY_ENTER, KEY_SPACE:
                                # FIX (grazia input): durante il primo secondo una
                                # pressione residua (SPACE del salto livelli in test
                                # mode) NON consuma il credito.
                                if _grace_timer < INPUT_GRACE_SECONDS:
                                        return
                                _confirm()
                        KEY_ESCAPE:
                                if _grace_timer < INPUT_GRACE_SECONDS:
                                        return
                                _choice = false
                                _confirm()
        elif event is InputEventJoypadMotion:
                if event.axis == JOY_AXIS_LEFT_X:
                        # FIX (inversione si/no): prima LEFT=NO, RIGHT=YES.
                        # Invertito: LEFT=YES, RIGHT=NO come richiesto dall'utente.
                        if event.axis_value < -0.5:
                                _choice = true  # LEFT = YES
                        elif event.axis_value > 0.5:
                                _choice = false  # RIGHT = NO
        elif event is InputEventJoypadButton and event.pressed:
                # FIX (grazia input): vale anche per il tasto fuoco del joystick.
                if _grace_timer < INPUT_GRACE_SECONDS:
                        return
                if event.button_index == JOY_BUTTON_A:
                        _confirm()
                else:
                        # FIX (tasto fuoco configurato): se il tasto premuto corrisponde
                        # al JOY_SHOOT configurato in ConfigManager, conferma.
                        if ConfigManager and ConfigManager.p1_joystick_ready():
                                var configured_shoot: int = ConfigManager.joy_shoot()
                                if configured_shoot >= 0 and event.button_index == configured_shoot:
                                        _confirm()


func _confirm() -> void:
        if _finished:
                return
        _finished = true
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.MENU_CONFIRM)
        if _choice:
                continue_used.emit()
                if GameManager:
                        GameManager.use_continue()
        else:
                give_up_requested.emit()
                if GameManager:
                        GameManager.give_up()


func _on_timeout() -> void:
        _finished = true
        give_up_requested.emit()
        if GameManager:
                GameManager.give_up()


func _draw() -> void:
        # Background image (cover-fit)
        if _bg_texture:
                var vp_size: Vector2 = size
                var tex_size: Vector2 = _bg_texture.get_size()
                var scale_val: float = max(vp_size.x / tex_size.x, vp_size.y / tex_size.y)
                var draw_size: Vector2 = tex_size * scale_val
                var draw_pos: Vector2 = (vp_size - draw_size) / 2.0
                draw_texture_rect(_bg_texture, Rect2(draw_pos, draw_size), false)
        else:
                draw_rect(Rect2(0, 0, size.x, size.y), Color(0.02, 0.02, 0.04, 1.0), true)
        # Dark overlay
        draw_rect(Rect2(0, 0, size.x, size.y), color_bg_overlay, true)

        # Title "CONTINUE?" — TASK 44: resta in inglese in entrambe le lingue
        # (termine arcade usato anche in Italia, richiesta utente).
        var font := get_theme_default_font()
        var cx: float = size.x / 2.0
        draw_string(font, Vector2(cx - 200, 120), I18n.t("cont.title"),
                HORIZONTAL_ALIGNMENT_CENTER, 400, 64, color_title)

        # Countdown number (big, blinking when < 5)
        var count_color: Color = color_title if _countdown > 5 else Color(1, 0.3, 0.2)
        if _countdown <= 3:
                count_color.a = 0.5 + 0.5 * sin(_blink_time * 15.0)
        draw_string(font, Vector2(cx - 50, 250), str(_countdown),
                HORIZONTAL_ALIGNMENT_CENTER, 100, 72, count_color)

        # YES / NO selector
        var yes_color: Color = color_yes if _choice else color_yes.darkened(0.5)
        var no_color: Color = color_no if not _choice else color_no.darkened(0.5)
        if _choice:
                # Arrow next to YES
                draw_string(font, Vector2(cx - 220, 400), ">",
                        HORIZONTAL_ALIGNMENT_CENTER, 30, 36, color_title)
        else:
                draw_string(font, Vector2(cx + 80, 400), ">",
                        HORIZONTAL_ALIGNMENT_CENTER, 30, 36, color_title)
        draw_string(font, Vector2(cx - 180, 400), I18n.t("cont.yes"),
                HORIZONTAL_ALIGNMENT_CENTER, 150, 40, yes_color)
        draw_string(font, Vector2(cx + 30, 400), I18n.t("cont.no"),
                HORIZONTAL_ALIGNMENT_CENTER, 150, 40, no_color)

        # Continues left
        var continues: int = GameManager.continues_left if GameManager else 3
        draw_string(font, Vector2(cx - 200, 500),
                I18n.t("cont.left") % continues,
                HORIZONTAL_ALIGNMENT_CENTER, 400, 24, color_hint)

        # Hint
        draw_string(font, Vector2(cx - 300, 560),
                I18n.t("cont.hint"),
                HORIZONTAL_ALIGNMENT_CENTER, 600, 18, color_hint)
