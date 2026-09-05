## LoseScreen.gd
## ============================================================
## Porting of Game.cpp STATE_LOSE.
## Shows the game over screen with bg_gameover.jpg background.
## "PRESS ENTER TO RETURN TO MENU".
## ============================================================
extends Control

signal back_to_menu_requested()

@export var color_title:    Color = Color(0.863, 0.157, 0.157)
@export var color_subtitle: Color = Color(0.784, 0.784, 0.784)
@export var color_hint:     Color = Color(0.588, 0.588, 0.588)

var _bg_texture: Texture2D = null
var _time: float = 0.0
var _finished: bool = false


func _ready() -> void:
        set_anchors_preset(Control.PRESET_FULL_RECT)
        mouse_filter = Control.MOUSE_FILTER_STOP
        focus_mode = Control.FOCUS_ALL
        _finished = false
        var tex := load("res://assets/backgrounds/bg_gameover.jpg")
        if tex is Texture2D:
                _bg_texture = tex
        if AudioManager:
                AudioManager.stop_music()


func _process(delta: float) -> void:
        _time += delta
        queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
        if _finished:
                return
        if event is InputEventKey and event.pressed and not event.echo:
                if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE or event.keycode == KEY_ESCAPE:
                        _finish()
        elif event is InputEventJoypadButton and event.pressed:
                if event.button_index == JOY_BUTTON_A:
                        _finish()


func _finish() -> void:
        _finished = true
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.MENU_CONFIRM)
        back_to_menu_requested.emit()
        if GameManager:
                GameManager.go_to_menu()


func _draw() -> void:
        # Background
        if _bg_texture:
                var vp_size: Vector2 = size
                var tex_size: Vector2 = _bg_texture.get_size()
                var scale_val: float = max(vp_size.x / tex_size.x, vp_size.y / tex_size.y)
                var draw_size: Vector2 = tex_size * scale_val
                var draw_pos: Vector2 = (vp_size - draw_size) / 2.0
                draw_texture_rect(_bg_texture, Rect2(draw_pos, draw_size), false)
        else:
                draw_rect(Rect2(0, 0, size.x, size.y), Color(0.02, 0.0, 0.0, 1.0), true)

        # Dark overlay for readability
        draw_rect(Rect2(0, 0, size.x, size.y), Color(0, 0, 0, 0.4), true)

        var font := get_theme_default_font()
        var cx: float = size.x / 2.0

        # Title "GAME OVER" (subtle pulse)
        var pulse: float = 1.0 + 0.03 * sin(_time * 2.0)
        var title_size: int = int(80 * pulse)
        draw_string(font, Vector2(cx - 350, 120), "GAME OVER",
                HORIZONTAL_ALIGNMENT_CENTER, 700, title_size, color_title)

        # Subtitle
        draw_string(font, Vector2(cx - 300, 240),
                "The maze has claimed another soul...",
                HORIZONTAL_ALIGNMENT_CENTER, 600, 28, color_subtitle)

        # Hint (blinking)
        var hint_alpha: float = 0.5 + 0.5 * sin(_time * 2.0)
        draw_string(font, Vector2(cx - 300, size.y - 80),
                "PRESS ENTER TO RETURN TO MENU",
                HORIZONTAL_ALIGNMENT_CENTER, 600, 24,
                Color(color_hint.r, color_hint.g, color_hint.b, hint_alpha))
