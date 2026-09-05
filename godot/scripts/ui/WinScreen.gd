## WinScreen.gd
## ============================================================
## Porting of Game.cpp STATE_WIN_STORY.
## Shows the victory screen with bg_win.jpg background and
## animated fireworks. "PRESS ENTER TO RETURN TO MENU".
## ============================================================
extends Control

signal back_to_menu_requested()

@export var color_title:    Color = Color(1.000, 0.843, 0.000)
@export var color_subtitle: Color = Color(0.961, 0.922, 0.784)
@export var color_hint:     Color = Color(0.745, 0.745, 0.745)

var _bg_texture: Texture2D = null
var _time: float = 0.0
var _fireworks: Array = []
var _finished: bool = false


func _ready() -> void:
        set_anchors_preset(Control.PRESET_FULL_RECT)
        mouse_filter = Control.MOUSE_FILTER_STOP
        focus_mode = Control.FOCUS_ALL
        _finished = false
        var tex := load("res://assets/backgrounds/bg_win.jpg")
        if tex is Texture2D:
                _bg_texture = tex
        if AudioManager:
                AudioManager.stop_music()
                if AudioManager.music_enabled:
                        AudioManager.play_epic_music(7)  # victory track


func _process(delta: float) -> void:
        _time += delta
        # Spawn fireworks periodically
        if randf() < delta * 2.0:  # ~2 per second
                _spawn_firework()
        # Update fireworks
        var alive: Array = []
        for fw in _fireworks:
                fw["pos"] += fw.get("vel", Vector2.ZERO)
                fw["vel"].y += 15.0 * delta  # gravity
                fw["life"] -= 1
                if int(fw.get("life", 0)) > 0:
                        alive.append(fw)
        _fireworks = alive
        queue_redraw()


func _spawn_firework() -> void:
        var cx: float = randf() * size.x
        var cy: float = randf() * size.y * 0.6 + size.y * 0.1
        var col: Color = Color.from_hsv(randf(), 0.8, 1.0)
        var count: int = 20 + randi() % 15
        for i in count:
                var angle: float = (float(i) / float(count)) * TAU
                var speed: float = 80.0 + randf() * 60.0
                _fireworks.append({
                        "pos": Vector2(cx, cy),
                        "vel": Vector2(cos(angle), sin(angle)) * speed,
                        "life": 40 + randi() % 20,
                        "color": col,
                        "size": 2.0 + randf() * 2.0,
                })


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
                draw_rect(Rect2(0, 0, size.x, size.y), Color(0.02, 0.04, 0.08, 1.0), true)

        # Fireworks
        for fw in _fireworks:
                var pos: Vector2 = fw.get("pos", Vector2.ZERO)
                var col: Color = fw.get("color", Color.WHITE)
                var sz: float = float(fw.get("size", 3))
                var life: int = int(fw.get("life", 0))
                var alpha: float = min(1.0, float(life) / 30.0)
                draw_circle(pos, sz, Color(col.r, col.g, col.b, alpha))

        # Title "VICTORY!" (pulsing)
        var font := get_theme_default_font()
        var cx: float = size.x / 2.0
        var pulse: float = 1.0 + 0.05 * sin(_time * 3.0)
        var title_size: int = int(72 * pulse)
        draw_string(font, Vector2(cx - 300, 100), "VICTORY!",
                HORIZONTAL_ALIGNMENT_CENTER, 600, title_size, color_title)

        # Subtitle
        draw_string(font, Vector2(cx - 350, 220),
                "YOU CONQUERED THE ARCADE MAZE",
                HORIZONTAL_ALIGNMENT_CENTER, 700, 32, color_subtitle)
        draw_string(font, Vector2(cx - 200, 280),
                "All 68 levels cleared. The treasure is yours.",
                HORIZONTAL_ALIGNMENT_CENTER, 400, 22, color_hint)

        # Final score (if available)
        if GameManager:
                draw_string(font, Vector2(cx - 150, 350),
                        "FINAL SCORE: %d" % 0,
                        HORIZONTAL_ALIGNMENT_CENTER, 300, 28, color_title)

        # Hint (blinking)
        var hint_alpha: float = 0.5 + 0.5 * sin(_time * 2.0)
        draw_string(font, Vector2(cx - 300, size.y - 80),
                "PRESS ENTER TO RETURN TO MENU",
                HORIZONTAL_ALIGNMENT_CENTER, 600, 24,
                Color(color_hint.r, color_hint.g, color_hint.b, hint_alpha))
