extends Control

# SelectPlayer.gd - Selezione personaggio con RUOTA VISIVA in prospettiva.
# Porting fedele di Game.cpp drawSelectPlayer() (righe 4528-4750).
#
# Background: AI-generated crypt/ruderi/fantasy image (bg_select_player.png).
# The procedural crypt originally drawn here has been extracted to
# EnvironmentArt.draw_crypt_background() (reusable by ConfigJoy and other menus).
#
# La ruota e' un'ellisse (cerchio compresso verticalmente) con:
#   * 8 personaggi disposti attorno al perimetro
#   * Raggi dal centro al bordo
#   * Perno centrale metallico
#   * Ombre e prospettiva (depth-based scale + alpha)
#   * Il personaggio selezionato e' al FRONT (in basso)
#
# Input: LEFT/RIGHT o joystick per ruotare, ENTER per confermare.

signal player_selected(character_index: int, player_num: int)

const C = preload("res://scripts/core/GameConstants.gd")

# 9 personaggi (8 nella ruota + il 9° extra)
const CHARACTERS: Array[String] = [
        "player1", "player2", "char_mage", "char_orc",
        "char_elf", "char_knight", "char_golem", "char_dragon", "char_vampire"
]
const CHARACTER_NAMES: Array[String] = [
        "HERO", "HEROINE", "MAGE", "ORC", "ELF", "KNIGHT", "GOLEM", "DRAGON", "VAMPIRE"
]
const CHARACTER_COUNT: int = 8  # solo 8 nella ruota

# Colori (mirror C++ palette)
const COL_ROCK_DARK := Color(0.188, 0.157, 0.141)
const COL_ROCK_MID := Color(0.376, 0.314, 0.282)
const COL_ROCK_LIGHT := Color(0.627, 0.502, 0.439)
const COL_METAL_DARK := Color(0.188, 0.157, 0.141)
const COL_GOLD := Color(0.863, 0.627, 0.157)
const COL_BLACK := Color(0.047, 0.047, 0.047)

# State
var current_index: int = 0
var player_num: int = 1
var wheel_rotation: float = 0.0
var wheel_target: int = 0
var wheel_index: int = 0
var anim_time: float = 0.0

# Cached character textures (loaded once)
var _char_textures: Array = []
# AI-generated background texture (loaded once)
var _bg_texture: Texture2D = null


func _ready() -> void:
        set_anchors_preset(Control.PRESET_FULL_RECT)
        mouse_filter = Control.MOUSE_FILTER_STOP
        focus_mode = Control.FOCUS_ALL
        # Initialize wheel index from GameManager
        if GameManager:
                wheel_index = GameManager.player1_character % CHARACTER_COUNT
                wheel_target = wheel_index
        wheel_rotation = 0.0
        # Preload all character textures
        _char_textures.clear()
        for i in CHARACTER_COUNT:
                var path := "res://assets/sprites/" + CHARACTERS[i] + "_sheet.png"
                var tex = null
                if ResourceLoader.exists(path):
                        tex = load(path)
                if tex == null:
                        # Fallback: try Image.load
                        var img := Image.new()
                        if img.load(path) == OK:
                                tex = ImageTexture.create_from_image(img)
                _char_textures.append(tex)
        # Preload the AI-generated crypt/ruderi background.
        var bg_path := "res://assets/backgrounds/bg_select_player.png"
        if ResourceLoader.exists(bg_path):
                _bg_texture = load(bg_path) as Texture2D
        # Self-wire
        player_selected.connect(_on_player_selected)


func _process(delta: float) -> void:
        anim_time += delta
        # Animate wheel rotation toward target
        if wheel_index != wheel_target:
                wheel_rotation += 0.15 * 60.0 * delta
                if wheel_rotation >= 1.0:
                        wheel_rotation = 0.0
                        var diff: int = wheel_target - wheel_index
                        if diff > CHARACTER_COUNT / 2:
                                diff -= CHARACTER_COUNT
                        elif diff < -CHARACTER_COUNT / 2:
                                diff += CHARACTER_COUNT
                        if diff > 0:
                                wheel_index = (wheel_index + 1) % CHARACTER_COUNT
                        elif diff < 0:
                                wheel_index = (wheel_index - 1 + CHARACTER_COUNT) % CHARACTER_COUNT

        # FIX (joystick skips 2 per move):
        # Previously, BOTH `is_action_just_pressed("move_left")` (which now
        # triggers for JoypadMotion too, thanks to the input map bindings we
        # added in project.godot) AND the raw `Input.get_joy_axis(jid, 0)` block
        # below were firing on the same joystick tilt → 2 increments per move.
        # The raw joystick block is now redundant: the input map already maps
        # left-stick X and D-pad left/right to move_left/move_right, and A/Start
        # to confirm. We just keep a short debounce so a single tilt doesn't
        # re-trigger the very next frame (the action-just-pressed edge already
        # handles this, but a defensive cooldown doesn't hurt).
        if _joy_nav_cooldown > 0:
                _joy_nav_cooldown -= delta
        if _joy_confirm_cooldown > 0:
                _joy_confirm_cooldown -= delta

        if Input.is_action_just_pressed("move_left"):
                wheel_target = (wheel_target + 1) % CHARACTER_COUNT
                _joy_nav_cooldown = 0.3
                if AudioManager:
                        AudioManager.play_sound(AudioManager.SoundType.MENU_SELECT)
        elif Input.is_action_just_pressed("move_right"):
                wheel_target = (wheel_target - 1 + CHARACTER_COUNT) % CHARACTER_COUNT
                _joy_nav_cooldown = 0.3
                if AudioManager:
                        AudioManager.play_sound(AudioManager.SoundType.MENU_SELECT)
        elif Input.is_action_just_pressed("confirm"):
                _joy_confirm_cooldown = 0.5
                if AudioManager:
                        AudioManager.play_sound(AudioManager.SoundType.MENU_CONFIRM)
                player_selected.emit(wheel_index, player_num)

        queue_redraw()


var _joy_nav_cooldown: float = 0.0
var _joy_confirm_cooldown: float = 0.0


func _on_player_selected(character_index: int, p_num: int) -> void:
        if GameManager:
                if p_num == 1:
                        GameManager.player1_character = character_index
                        if GameManager.num_players == 2:
                                player_num = 2
                                wheel_index = GameManager.player2_character % CHARACTER_COUNT
                                wheel_target = wheel_index
                                wheel_rotation = 0.0
                                return
                else:
                        GameManager.player2_character = character_index
                GameManager.go_to_intro()
        else:
                get_tree().change_scene_to_file("res://scenes/IntroCutscene.tscn")


func _draw() -> void:
        var vp_size: Vector2 = size
        var cx: float = vp_size.x / 2.0
        var cy: float = vp_size.y / 2.0 + 80.0  # piu' in basso per il titolo

        # --- BACKGROUND: AI-generated crypt/ruderi/fantasy image ---
        # Cover-fit math (same pattern as WinScreen/LoseScreen/ContinuesScreen):
        # scale = max(vp/tex) so the entire viewport is filled (no black bars),
        # and center the draw rect on the viewport.
        if _bg_texture != null:
                var tex_size: Vector2 = _bg_texture.get_size()
                var scale_x: float = vp_size.x / tex_size.x
                var scale_y: float = vp_size.y / tex_size.y
                var bg_scale: float = maxf(scale_x, scale_y)
                var draw_size: Vector2 = tex_size * bg_scale
                var draw_pos: Vector2 = (vp_size - draw_size) * 0.5
                draw_texture_rect(_bg_texture, Rect2(draw_pos, draw_size), false)
        else:
                # Fallback: procedural crypt background (if AI image missing)
                if EnvironmentArt:
                        EnvironmentArt.draw_crypt_background(self, vp_size, anim_time)

        # Dark overlay so the wheel and text stand out against the busy art
        draw_rect(Rect2(0, 0, vp_size.x, vp_size.y), Color(0, 0, 0, 0.35), true)

        # --- Titolo ---
        var title: String = "SELECT PLAYER " + str(player_num)
        _draw_text_centered(title, cx - 4, 96, 48, Color(0.706, 0.471, 0.157))  # shadow
        _draw_text_centered(title, cx, 100, 48, Color(1.0, 0.843, 0.0))  # gold

        # --- Hint ---
        var player_color: Color = Color(1.0, 0.843, 0.0) if player_num == 1 else Color(0.471, 0.706, 1.0)
        _draw_text_centered("LEFT/RIGHT TO ROTATE - ENTER TO CONFIRM", cx, 160, 20, Color(0.588, 0.588, 0.588))
        _draw_text_centered(CHARACTER_NAMES[wheel_index], cx, 185, 28, player_color)

        # --- Parametri ruota ---
        var wheel_radius_x: float = 300.0
        var perspective_ratio: float = 0.32
        var wheel_radius_y: float = wheel_radius_x * perspective_ratio

        # --- 1. Ombra sotto la ruota ---
        draw_circle(Vector2(cx, cy + wheel_radius_y * 0.85),
                wheel_radius_x * 1.15, Color(0, 0, 0, 0.43))

        # --- 2. Base ellisse ---
        _draw_ellipse(cx, cy, wheel_radius_x, wheel_radius_y, COL_ROCK_DARK)
        _draw_ellipse_outline(cx, cy, wheel_radius_x, wheel_radius_y, COL_ROCK_MID, 6.0)

        # --- 3. Anello interno ---
        var inner_radius: float = wheel_radius_x - 28.0
        _draw_ellipse(cx, cy, inner_radius, inner_radius * perspective_ratio, COL_ROCK_MID)

        # --- 4. Angolo ruota ---
        var angle_per_char: float = TAU / CHARACTER_COUNT
        var diff: int = wheel_target - wheel_index
        if diff > CHARACTER_COUNT / 2:
                diff -= CHARACTER_COUNT
        elif diff < -CHARACTER_COUNT / 2:
                diff += CHARACTER_COUNT
        var interp_step: float = 0.0
        if diff != 0:
                interp_step = wheel_rotation * (1.0 if diff > 0 else -1.0)
        var wheel_angle_base: float = PI / 2.0 - (float(wheel_index) + interp_step) * angle_per_char

        # --- 5. Raggi ---
        for s in CHARACTER_COUNT:
                var a: float = wheel_angle_base + s * angle_per_char
                var x2: float = cx + cos(a) * (inner_radius - 8.0)
                var y2: float = cy + sin(a) * (inner_radius - 8.0) * perspective_ratio
                draw_line(Vector2(cx, cy), Vector2(x2, y2),
                        Color(COL_ROCK_LIGHT.r, COL_ROCK_LIGHT.g, COL_ROCK_LIGHT.b, 0.55), 4.0)

        # --- 6. Perno centrale ---
        _draw_ellipse(cx, cy, 46.0, 46.0 * perspective_ratio, COL_METAL_DARK)
        _draw_ellipse_outline(cx, cy, 46.0, 46.0 * perspective_ratio, COL_GOLD, 4.0)
        _draw_ellipse(cx, cy, 14.0, 14.0 * perspective_ratio, COL_GOLD)

        # --- 7. Personaggi attorno al perimetro ---
        # Calcola posizioni e ordinale per depth (dietro -> davanti)
        var placements: Array = []
        for i in CHARACTER_COUNT:
                var a: float = wheel_angle_base + float(i) * angle_per_char
                var px: float = cx + cos(a) * wheel_radius_x
                var py: float = cy + sin(a) * wheel_radius_y
                var depth: float = sin(a)
                var scale_val: float = 0.8 + (depth + 1.0) * 0.5
                var alpha: float = 0.5 + (depth + 1.0) * 0.235
                placements.append({
                        "idx": i, "x": px, "y": py,
                        "scale": scale_val, "depth": depth, "alpha": alpha
                })
        # Sort by depth (back first)
        placements.sort_custom(func(a, b): return a.depth < b.depth)

        # Draw characters
        for p in placements:
                var i: int = p.idx
                if i < _char_textures.size() and _char_textures[i] != null:
                        var tex: Texture2D = _char_textures[i]
                        var char_size: float = 64.0 * p.scale
                        var draw_rect := Rect2(p.x - char_size / 2.0, p.y - char_size, char_size, char_size)
                        # AtlasTexture for first frame (64x64)
                        var at := AtlasTexture.new()
                        at.atlas = tex
                        at.region = Rect2(0, 0, 64, 64)
                        draw_texture_rect(at, draw_rect, false)
                else:
                        # Fallback: colored circle
                        var col: Color = Color(0.7, 0.5, 0.3, p.alpha)
                        draw_circle(Vector2(p.x, p.y - 20), 20 * p.scale, col)
                        # Name
                        _draw_text_centered(CHARACTER_NAMES[i], p.x, p.y - 50 * p.scale, 14 * p.scale,
                                Color(1, 1, 1, p.alpha))

                # Glow on selected character (front)
                if i == wheel_index:
                        var glow: float = 0.5 + 0.5 * sin(anim_time * 4.0)
                        draw_circle(Vector2(p.x, p.y - 20),
                                30.0 * p.scale, Color(1.0, 0.84, 0.0, 0.3 * glow))
                        draw_circle(Vector2(p.x, p.y - 20),
                                22.0 * p.scale, Color(1.0, 0.84, 0.0, 0.5 * glow))

        # --- 8. Nome personaggio selezionato (in basso) ---
        _draw_text_centered(CHARACTER_NAMES[wheel_index], cx, vp_size.y - 60, 32,
                Color(1.0, 0.843, 0.0))


# Draw text centered at (x, y) with given size and color.
func _draw_text_centered(text: String, x: float, y: float, font_size: int, col: Color) -> void:
        var font := get_theme_default_font()
        draw_string(font, Vector2(x - 200, y + font_size), text,
                HORIZONTAL_ALIGNMENT_CENTER, 400, font_size, col)


# Draw filled ellipse (circle scaled vertically).
func _draw_ellipse(cx: float, cy: float, rx: float, ry: float, col: Color) -> void:
        # Approximate with multiple horizontal lines
        var steps: int = 32
        for i in steps:
                var angle: float = float(i) / steps * TAU
                var angle2: float = float(i + 1) / steps * TAU
                var x1: float = cx + cos(angle) * rx
                var y1: float = cy + sin(angle) * ry
                var x2: float = cx + cos(angle2) * rx
                var y2: float = cy + sin(angle2) * ry
                draw_colored_polygon(PackedVector2Array([
                        Vector2(cx, cy), Vector2(x1, y1), Vector2(x2, y2)
                ]), col)


# Draw ellipse outline.
func _draw_ellipse_outline(cx: float, cy: float, rx: float, ry: float, col: Color, width: float) -> void:
        var steps: int = 48
        var prev: Vector2 = Vector2(cx + cos(0) * rx, cy + sin(0) * ry)
        for i in range(1, steps + 1):
                var angle: float = float(i) / steps * TAU
                var curr: Vector2 = Vector2(cx + cos(angle) * rx, cy + sin(angle) * ry)
                draw_line(prev, curr, col, width)
                prev = curr
