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


func _ready() -> void:
        set_anchors_preset(Control.PRESET_FULL_RECT)
        mouse_filter = Control.MOUSE_FILTER_STOP
        focus_mode = Control.FOCUS_ALL
        _countdown = 10
        _countdown_timer = 0.0
        _choice = true
        _finished = false
        # Load continues background.
        var tex := load("res://assets/backgrounds/bg_continues.jpg")
        if tex is Texture2D:
                _bg_texture = tex
        if AudioManager:
                AudioManager.stop_music()


func _process(delta: float) -> void:
        if _finished:
                return
        _blink_time += delta
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
                                _confirm()
                        KEY_ESCAPE:
                                _choice = false
                                _confirm()
        elif event is InputEventJoypadMotion:
                if event.axis == JOY_AXIS_LEFT_X:
                        if event.axis_value < -0.5:
                                _choice = false
                        elif event.axis_value > 0.5:
                                _choice = true
        elif event is InputEventJoypadButton and event.pressed:
                if event.button_index == JOY_BUTTON_A:
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
                var vp_size := size
                var tex_size := _bg_texture.get_size()
                var scale := max(vp_size.x / tex_size.x, vp_size.y / tex_size.y)
                var draw_size := tex_size * scale
                var draw_pos := (vp_size - draw_size) / 2.0
                draw_texture_rect(_bg_texture, Rect2(draw_pos, draw_size), false)
        else:
                draw_rect(Rect2(0, 0, size.x, size.y), Color(0.02, 0.02, 0.04, 1.0), true)
        # Dark overlay
        draw_rect(Rect2(0, 0, size.x, size.y), color_bg_overlay, true)

        # Title "CONTINUE?"
        var font := get_theme_default_font()
        var cx: float = size.x / 2.0
        draw_string(font, Vector2(cx - 200, 120), "CONTINUE?",
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
        draw_string(font, Vector2(cx - 180, 400), "YES",
                HORIZONTAL_ALIGNMENT_CENTER, 150, 40, yes_color)
        draw_string(font, Vector2(cx + 30, 400), "NO",
                HORIZONTAL_ALIGNMENT_CENTER, 150, 40, no_color)

        # Continues left
        var continues: int = GameManager.continues_left if GameManager else 3
        draw_string(font, Vector2(cx - 200, 500),
                "CONTINUES LEFT: %d" % continues,
                HORIZONTAL_ALIGNMENT_CENTER, 400, 24, color_hint)

        # Hint
        draw_string(font, Vector2(cx - 300, 560),
                "LEFT/RIGHT TO SELECT - ENTER TO CONFIRM",
                HORIZONTAL_ALIGNMENT_CENTER, 600, 18, color_hint)
