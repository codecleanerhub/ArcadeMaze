extends Control

# SelectPlayer.gd - Selezione personaggio con RUOTA VISIVA in prospettiva.
# Porting fedele di Game.cpp drawSelectPlayer() (righe 4528-4750).
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

        # Input: keyboard arrows
        if Input.is_action_just_pressed("move_left"):
                wheel_target = (wheel_target + 1) % CHARACTER_COUNT
                if AudioManager:
                        AudioManager.play_sound(AudioManager.SoundType.MENU_SELECT)
        elif Input.is_action_just_pressed("move_right"):
                wheel_target = (wheel_target - 1 + CHARACTER_COUNT) % CHARACTER_COUNT
                if AudioManager:
                        AudioManager.play_sound(AudioManager.SoundType.MENU_SELECT)
        elif Input.is_action_just_pressed("confirm"):
                if AudioManager:
                        AudioManager.play_sound(AudioManager.SoundType.MENU_CONFIRM)
                player_selected.emit(wheel_index, player_num)

        # Input: joystick (debounced)
        var joy_pads: Array = Input.get_connected_joypads()
        if joy_pads.size() > 0:
                var jid: int = joy_pads[0]
                var axis_x: float = Input.get_joy_axis(jid, 0)
                if absf(axis_x) > 0.5 and _joy_nav_cooldown <= 0:
                        if axis_x > 0:
                                wheel_target = (wheel_target - 1 + CHARACTER_COUNT) % CHARACTER_COUNT
                        else:
                                wheel_target = (wheel_target + 1) % CHARACTER_COUNT
                        _joy_nav_cooldown = 0.3
                        if AudioManager:
                                AudioManager.play_sound(AudioManager.SoundType.MENU_SELECT)
                var btn_a: bool = Input.is_joy_button_pressed(jid, 0)
                if btn_a and _joy_confirm_cooldown <= 0:
                        _joy_confirm_cooldown = 0.5
                        if AudioManager:
                                AudioManager.play_sound(AudioManager.SoundType.MENU_CONFIRM)
                        player_selected.emit(wheel_index, player_num)

        # Decrement cooldowns
        if _joy_nav_cooldown > 0:
                _joy_nav_cooldown -= delta
        if _joy_confirm_cooldown > 0:
                _joy_confirm_cooldown -= delta

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

        # --- SFONDO FANTASY CRIPTA ---
        # 1. Gradiente notte profonda (dall'alto scuro al basso viola scuro)
        for i in 32:
                var t: float = float(i) / 31.0
                var r: float = 8.0 + (1.0 - t) * 12.0
                var g: float = 6.0 + (1.0 - t) * 8.0
                var b: float = 18.0 + (1.0 - t) * 22.0
                var band_h: float = vp_size.y / 32.0 + 1.0
                draw_rect(Rect2(0, i * band_h, vp_size.x, band_h),
                        Color(r / 255.0, g / 255.0, b / 255.0), true)

        # 2. Nebbia animata in basso (pulsazione lenta)
        var fog_alpha: float = 0.12 + 0.06 * sin(anim_time * 0.8)
        for i in 5:
                var fog_y: float = vp_size.y - 60.0 - float(i) * 30.0
                var fog_r: float = 200.0 + i * 60.0
                var fog_col: Color = Color(0.15, 0.12, 0.25, fog_alpha * (1.0 - float(i) * 0.15))
                draw_circle(Vector2(cx + sin(anim_time * 0.5 + i) * 80, fog_y), fog_r, fog_col)

        # 3. Colonne di pietra laterali (stile cripta D&D)
        _draw_crypt_column(vp_size.x * 0.08, vp_size.y * 0.15, 0.7)
        _draw_crypt_column(vp_size.x * 0.92, vp_size.y * 0.15, 0.7)

        # 4. Arco di pietra in alto (decorazione architettonica)
        var arch_y: float = vp_size.y * 0.08
        var arch_w: float = vp_size.x * 0.7
        for i in 24:
                var angle: float = PI + float(i) / 23.0 * PI
                var ax: float = cx + cos(angle) * (arch_w / 2.0)
                var ay: float = arch_y + sin(angle) * 40.0
                draw_circle(Vector2(ax, ay), 8.0, Color(0.15, 0.12, 0.10))

        # 5. Teschi decorativi sui lati
        if EnvironmentArt:
                var skull_tex: Texture2D = EnvironmentArt.get_skull_texture()
                if skull_tex:
                        draw_texture_rect(skull_tex,
                                Rect2(vp_size.x * 0.05, vp_size.y * 0.35, 64, 64), false)
                        draw_texture_rect(skull_tex,
                                Rect2(vp_size.x * 0.05, vp_size.y * 0.55, 48, 48), false)
                        draw_texture_rect(skull_tex,
                                Rect2(vp_size.x * 0.90, vp_size.y * 0.35, 64, 64), false)
                        draw_texture_rect(skull_tex,
                                Rect2(vp_size.x * 0.92, vp_size.y * 0.55, 48, 48), false)

        # 6. Torce animate sui lati
        _draw_torch_flame(vp_size.x * 0.12, vp_size.y * 0.25)
        _draw_torch_flame(vp_size.x * 0.88, vp_size.y * 0.25)

        # 7. Ruderi sul pavimento (pietre spezzate)
        for i in 6:
                var rubble_x: float = (0.1 + float(i) * 0.15) * vp_size.x
                var rubble_y: float = vp_size.y - 30.0 + sin(float(i) * 1.7) * 10.0
                var rubble_col: Color = Color(0.2, 0.18, 0.15)
                if i % 2 == 0:
                        rubble_col = Color(0.25, 0.22, 0.18)
                draw_circle(Vector2(rubble_x, rubble_y), 12.0 + float(i % 3) * 4.0, rubble_col)
                draw_circle(Vector2(rubble_x + 8, rubble_y - 4), 6.0, rubble_col.darkened(0.3))

        # 8. Vignette scuro ai bordi per profondita'
        for i in 10:
                var vign_alpha: float = 0.05 * (10 - i) / 10.0
                draw_rect(Rect2(0, 0, float(i) * 4.0, vp_size.y),
                        Color(0, 0, 0, vign_alpha), true)
                draw_rect(Rect2(vp_size.x - float(i) * 4.0, 0, 4.0, vp_size.y),
                        Color(0, 0, 0, vign_alpha), true)

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


# --- Decorazioni sfondo cripta ---

# Colonna di pietra con capitello, scanalature, crepe e muschio
func _draw_crypt_column(x: float, y: float, scale_val: float) -> void:
        var col_w: float = 50.0 * scale_val
        var col_h: float = 500.0 * scale_val
        var rock_dark: Color = Color(0.12, 0.10, 0.09)
        var rock_mid: Color = Color(0.20, 0.17, 0.14)
        var rock_light: Color = Color(0.28, 0.24, 0.20)
        # Base (piu' larga)
        draw_rect(Rect2(x - col_w / 2.0 - 5, y + col_h - 10, col_w + 10, 20), rock_dark)
        # Fusto
        draw_rect(Rect2(x - col_w / 2.0, y, col_w, col_h), rock_mid)
        # Scanalature
        for i in 3:
                var sx: float = x - col_w / 2.0 + float(i + 1) * col_w / 4.0
                draw_rect(Rect2(sx - 1, y, 2, col_h), rock_dark)
        # Highlight sinistro (luce da torce)
        draw_rect(Rect2(x - col_w / 2.0, y, 3, col_h), rock_light)
        # Capitello (parte superiore)
        draw_rect(Rect2(x - col_w / 2.0 - 5, y - 10, col_w + 10, 15), rock_dark)
        draw_rect(Rect2(x - col_w / 2.0 - 3, y - 15, col_w + 6, 8), rock_mid)
        # Crepe
        draw_line(Vector2(x + 5, y + 50), Vector2(x + 8, y + 200), Color(0.05, 0.04, 0.03), 1)
        draw_line(Vector2(x - 10, y + 100), Vector2(x - 7, y + 250), Color(0.05, 0.04, 0.03), 1)
        # Muschio alla base
        draw_rect(Rect2(x - col_w / 2.0, y + col_h - 8, col_w, 6), Color(0.12, 0.22, 0.08))
        for i in 4:
                draw_circle(Vector2(x - 15 + float(i) * 10, y + col_h - 5), 2.0, Color(0.15, 0.28, 0.10))


# Torcia con fiamma animata
func _draw_torch_flame(x: float, y: float) -> void:
        var flicker: float = sin(anim_time * 18.0) * 1.5
        var flicker2: float = cos(anim_time * 22.0) * 1.0
        # Supporto metallico
        draw_rect(Rect2(x - 2, y, 4, 15), Color(0.25, 0.22, 0.20))
        # Aura
        draw_circle(Vector2(x, y), 16.0, Color(1.0, 0.6, 0.2, 0.15))
        draw_circle(Vector2(x, y), 10.0, Color(1.0, 0.5, 0.1, 0.25))
        # Fiamma esterna (arancione)
        draw_circle(Vector2(x, y - 5), 6.0 + flicker, Color(1.0, 0.4, 0.0, 0.8))
        # Fiamma media (gialla)
        draw_circle(Vector2(x, y - 5), 4.0 + flicker * 0.6, Color(1.0, 0.8, 0.2, 0.9))
        # Nucleo (bianco)
        draw_circle(Vector2(x, y - 5), 2.0 + flicker2 * 0.5, Color(1.0, 1.0, 0.8, 1.0))
        # Scintille
        for i in 3:
                var spark_y: float = y - 10.0 - float(i) * 5.0 + sin(anim_time * 3.0 + i) * 2.0
                var spark_x: float = x + cos(anim_time * 4.0 + i * 2.0) * 3.0
                draw_circle(Vector2(spark_x, spark_y), 1.0, Color(1.0, 0.7, 0.2, 0.6))
