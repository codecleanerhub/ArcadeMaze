# ============================================================================
# MainMenu.gd  (Control node)
#
# Godot port of:
#   - Game.cpp :: drawMenu()
#   - Game.cpp :: drawSelectPlayer()  (character wheel portion)
#
# Layout (mirror of the SFML build, expressed in 1024x1024 design space):
#   * Background:   bg_menu.jpg (cover-fit to the window)
#   * Title:        "ARCADE MAZE"  (gold + dark gold shadow)
#   * Ornament:     gold horizontal line + diamond (between title and items)
#   * Scroll panel: dark parchment-style rounded rectangle (items list)
#       7 menu items (selected one highlighted in yellow + animated flame):
#           0. NUMBER OF PLAYERS: 1 / 2
#           1. GAME MODE: STORY / INFINITE
#           2. MUSIC: ON / OFF
#           3. TEST MODE: ON / OFF
#           4. CONFIGURE JOYSTICK
#           5. START GAME
#           6. CREDITS
#   * Character wheel: 8 characters (HERO_M, HERO_F, MAGE, ORC, ELF, KNIGHT,
#                      GOLEM, DRAGON, VAMPIRE) shown side-view.
#   * Footer:        "By" (gold) + "Marled Software" (ivory)
#
# Navigation (matches the original):
#   * Up/Down (or joystick Y axis) = move selection
#   * Left/Right (or joystick X axis) = change the selected option's value
#   * Enter / Space (or joystick confirm) = activate item
#   * ESC                          = quit (handled by parent)
#
# Emitted signals:
#   * start_requested(num_players:int, mode:int, music:bool, p1_char:int, p2_char:int)
#   * credits_requested()
#   * configure_joystick_requested(player:int)  # 1 or 2
# ============================================================================
extends Control

# Game-mode mirror of GameMode enum (kept in sync with ConfigManager).
enum GameMode { STORY, INFINITE }

# --- Signals ---------------------------------------------------------------
signal start_requested(num_players: int, game_mode: int, music: bool,
                                           p1_char: int, p2_char: int)
signal credits_requested()
signal configure_joystick_requested(player: int)

# --- Exposed theme colors (match the SFML palette) -------------------------
@export var color_title_gold:    Color = Color(1.000, 0.843, 0.000)   # 255,215,0
@export var color_title_shadow:  Color = Color(0.706, 0.471, 0.157)   # 180,120,40
@export var color_item_normal:   Color = Color(0.706, 0.706, 0.706)   # 180,180,180
@export var color_item_selected: Color = Color(1.000, 1.000, 0.000)   # Yellow
@export var color_footer_by:     Color = Color(1.000, 0.843, 0.392)   # 255,215,100
@export var color_footer_name:   Color = Color(0.961, 0.922, 0.784)   # 245,235,200
@export var color_hint:          Color = Color(0.588, 0.588, 0.588)   # 150,150,150
@export var color_parchment_bg:  Color = Color(0.078, 0.047, 0.031, 0.784)
@export var color_parchment_border: Color = Color(0.549, 0.392, 0.196)

# --- Internal state (mirrors Game::xxx fields) ----------------------------
var _menu_item_index: int = 0
var _num_players: int = 1
var _game_mode: int = GameMode.STORY
var _music_enabled: bool = true  # default ON so music plays at startup
var _test_mode_enabled: bool = false
var _fullscreen_enabled: bool = true  # BootManager sets fullscreen at startup
# Character selection (8 characters, matches Player.h:CharacterType).
var _p1_character: int = 0
var _p2_character: int = 1
var _wheel_index: int = 0  # current wheel position (0..7)
var _wheel_step: int = 0   # 0 = P1 choosing, 1 = P2 choosing (only used in 2P)

# Animation timer (mirrors menuTime in drawMenu()).
var _menu_time: float = 0.0

# Child nodes (built in _ready).
var _bg: TextureRect
var _title_label: Label
var _footer_by: Label
var _footer_name: Label
var _hint_label: Label
var _item_labels: Array[Label] = []
var _panel: Panel
var _char_preview_container: HBoxContainer
# Preview sprites for the 8 characters.
var _char_sprites: Array[TextureRect] = []
# Index of the wheel sprite currently highlighted.
var _wheel_highlight: int = 0


# ============================================================================
# Lifecycle
# ============================================================================
func _ready() -> void:
        set_anchors_preset(Control.PRESET_FULL_RECT)
        mouse_filter = Control.MOUSE_FILTER_STOP
        focus_mode = Control.FOCUS_ALL
        _build_ui()
        _update_items_text()
        _update_character_wheel()
        # Sync music state from GameManager and start menu music if enabled.
        if GameManager:
                _music_enabled = GameManager.music_enabled
                _test_mode_enabled = GameManager.test_mode_enabled
        if AudioManager and _music_enabled:
                AudioManager.set_music_enabled(true)
                AudioManager.play_menu_music()
        # Self-wire signals to scene-transition handlers.
        start_requested.connect(_on_start_requested)
        credits_requested.connect(_on_credits_requested)
        configure_joystick_requested.connect(_on_configure_joystick_requested)


# ============================================================================
# Signal handlers (wire menu actions to GameManager scene transitions)
# ============================================================================
func _on_start_requested(num_players: int, game_mode: int, music: bool,
                p1_char: int, p2_char: int) -> void:
        if GameManager:
                GameManager.num_players = num_players
                GameManager.game_mode = game_mode
                GameManager.music_enabled = music
                GameManager.player1_character = p1_char
                GameManager.player2_character = p2_char
                GameManager.current_level = 1
                GameManager.config_joy_step = 0
                # Flow: START GAME -> joystick config (if not done) -> select player -> intro -> game
                # Check if joystick needs configuration (mirror C++ behavior)
                if ConfigManager and not ConfigManager.p1_joystick_ready():
                        # Joystick not configured yet: go to config first
                        GameManager.config_joy_player = 1
                        GameManager.go_to_config_joy()
                elif num_players == 2 and ConfigManager and not ConfigManager.p2_joystick_ready():
                        # P2 joystick not configured
                        GameManager.config_joy_player = 2
                        GameManager.go_to_config_joy()
                else:
                        # Joystick ready: go to character selection
                        GameManager.go_to_select_player()


func _on_credits_requested() -> void:
        if GameManager:
                GameManager.go_to_credits()


func _on_configure_joystick_requested(player: int) -> void:
        if GameManager:
                GameManager.config_joy_player = player
                GameManager.config_joy_step = 0
                GameManager.go_to_config_joy()


func _process(delta: float) -> void:
        _menu_time += delta
        # Animated flame flicker for the selected item (visual only).
        var flicker: float = sin(_menu_time * 15.0) * 1.5
        for i in _item_labels.size():
                var lbl: Label = _item_labels[i]
                if i == _menu_item_index:
                        lbl.add_theme_color_override("font_color", color_item_selected)
                        lbl.modulate = Color(1.0, 1.0, 1.0, 0.95 + 0.05 * sin(_menu_time * 8.0))
                else:
                        lbl.add_theme_color_override("font_color", color_item_normal)
                        lbl.modulate = Color(1.0, 1.0, 1.0, 1.0)
        # Pulse the title (very subtle gold shimmer).
        if _title_label:
                _title_label.modulate = Color(
                        1.0, 1.0, 1.0, 0.92 + 0.08 * sin(_menu_time * 2.0))
        # Hint text gentle fade.
        if _hint_label:
                _hint_label.modulate = Color(1, 1, 1, 0.7 + 0.3 * (0.5 + 0.5 * sin(_menu_time * 1.5)))
        # Hide unused warning
        pass # flicker variable used above
        queue_redraw()


func _draw() -> void:
        # Ornament line + central diamond (gold).
        var orn_y: float = 220.0
        var orn_gold: Color = Color(0.784, 0.627, 0.196)
        # Center diamond
        var cx: float = size.x / 2.0
        var pts := PackedVector2Array([
                Vector2(cx, orn_y - 6),
                Vector2(cx + 8, orn_y),
                Vector2(cx, orn_y + 6),
                Vector2(cx - 8, orn_y),
        ])
        draw_colored_polygon(pts, orn_gold)
        # Side lines
        draw_rect(Rect2(cx - 200, orn_y - 1, 180, 2), orn_gold)
        draw_rect(Rect2(cx + 20, orn_y - 1, 180, 2), orn_gold)
        # Small side diamonds
        for side in [-1, 1]:
                var dx: float = side * 200.0
                var dpts := PackedVector2Array([
                        Vector2(cx + dx, orn_y - 4),
                        Vector2(cx + dx + side * 4, orn_y),
                        Vector2(cx + dx, orn_y + 4),
                        Vector2(cx + dx - side * 4, orn_y),
                ])
                draw_colored_polygon(dpts, orn_gold)
        # Flame icon next to the selected item (animated)
        # Panel starts at y=300 (offset_top) + ~30px padding = ~330 for first item.
        # Each item is ~24px font + 22px separation = ~46px per row.
        _draw_flame(150.0, 350.0 + _menu_item_index * 46.0)


# Draws a small animated flame (aura + outer red + inner yellow) at (fx, fy).
func _draw_flame(fx: float, fy: float) -> void:
        var flicker: float = sin(_menu_time * 15.0) * 1.5
        # Aura
        draw_circle(Vector2(fx, fy), 8.0,
                Color(1.0, 0.706, 0.235, 0.314))
        # Outer red flame
        draw_circle(Vector2(fx - flicker, fy + flicker * 0.3), 4.0 + flicker,
                Color(0.863, 0.196, 0.078, 0.902))
        # Inner yellow flame
        draw_circle(Vector2(fx - 2.5, fy + flicker * 0.2), 2.5,
                Color(1.0, 0.863, 0.392, 0.941))


# ============================================================================
# UI construction
# ============================================================================
func _build_ui() -> void:
        # --- Background texture ---
        # Full-screen background. STRETCH_KEEP_ASPECT_COVERED ensures the entire
        # viewport is filled (no black bars) even when the screen aspect ratio
        # differs from the texture's 1:1 ratio. With aspect="keep" in
        # project.godot, the viewport is already 1024x1024, so the texture
        # fills the entire design area perfectly.
        _bg = TextureRect.new()
        _bg.name = "Background"
        _bg.set_anchors_preset(Control.PRESET_FULL_RECT)
        _bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        _bg.stretch_mode = TextureRect.STRETCH_SCALE
        var tex := load("res://assets/backgrounds/bg_menu.jpg")
        if tex is Texture:
                _bg.texture = tex
        add_child(_bg)

        # Dark overlay over the background, below the panel
        var dark := ColorRect.new()
        dark.set_anchors_preset(Control.PRESET_FULL_RECT)
        dark.color = Color(0, 0, 0, 0.20)
        add_child(dark)

        # --- Title ---
        # Centered horizontally at the top. We set anchors explicitly
        # (anchor_left=anchor_right=0.5, anchor_top=anchor_bottom=0) and use
        # symmetric offsets (-280/+280) so the label is exactly 560px wide and
        # always centered, regardless of how Godot interprets PRESET_FULL_RECT.
        _title_label = Label.new()
        _title_label.name = "Title"
        _title_label.text = "ARCADE MAZE"
        _title_label.anchor_left = 0.5
        _title_label.anchor_top = 0.0
        _title_label.anchor_right = 0.5
        _title_label.anchor_bottom = 0.0
        _title_label.offset_left = -300.0
        _title_label.offset_top = 60.0
        _title_label.offset_right = 300.0
        _title_label.offset_bottom = 130.0
        _title_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
        _title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        _title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        _title_label.add_theme_font_size_override("font_size", 48)
        _title_label.add_theme_color_override("font_color", color_title_gold)
        _title_label.add_theme_color_override("font_shadow_color", color_title_shadow)
        _title_label.add_theme_constant_override("shadow_offset_x", -3)
        _title_label.add_theme_constant_override("shadow_offset_y", -3)
        _title_label.add_theme_constant_override("shadow_outline_size", 3)
        add_child(_title_label)

        # --- Parchment panel ---
        # Anchored to fill the middle/lower portion of the screen.
        # anchor_left=0, anchor_right=1, offset_left=120, offset_right=-120
        # => panel spans from x=120 to x=(width-120), centered horizontally.
        # offset_top=300 leaves room for the title; offset_bottom=-100 leaves
        # room for the footer + hint text.
        _panel = Panel.new()
        _panel.name = "MenuPanel"
        _panel.anchor_left = 0.0
        _panel.anchor_top = 0.0
        _panel.anchor_right = 1.0
        _panel.anchor_bottom = 1.0
        _panel.offset_left = 120.0
        _panel.offset_top = 300.0
        _panel.offset_right = -120.0
        _panel.offset_bottom = -100.0
        _panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
        _panel.grow_vertical = Control.GROW_DIRECTION_BOTH
        var stylebox := StyleBoxFlat.new()
        stylebox.bg_color = color_parchment_bg
        stylebox.border_color = color_parchment_border
        stylebox.set_border_width_all(6)
        stylebox.set_corner_radius_all(8)
        stylebox.set_content_margin_all(12)
        _panel.add_theme_stylebox_override("panel", stylebox)
        add_child(_panel)

        # --- 7 menu items inside the panel ---
        # VBoxContainer filling the panel with 40px padding on each side.
        var items_container := VBoxContainer.new()
        items_container.name = "Items"
        items_container.anchor_left = 0.0
        items_container.anchor_top = 0.0
        items_container.anchor_right = 1.0
        items_container.anchor_bottom = 1.0
        items_container.offset_left = 40.0
        items_container.offset_top = 30.0
        items_container.offset_right = -40.0
        items_container.offset_bottom = -30.0
        items_container.grow_horizontal = Control.GROW_DIRECTION_BOTH
        items_container.grow_vertical = Control.GROW_DIRECTION_BOTH
        items_container.alignment = BoxContainer.ALIGNMENT_BEGIN
        items_container.add_theme_constant_override("separation", 22)
        _panel.add_child(items_container)

        var item_texts: Array = [
                "NUMBER OF PLAYERS:",
                "GAME MODE:",
                "MUSIC:",
                "TEST MODE:",
                "FULLSCREEN:",
                "CONFIGURE JOYSTICK",
                "START GAME",
                "CREDITS",
        ]
        for txt in item_texts:
                var lbl := Label.new()
                lbl.text = txt
                lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
                lbl.add_theme_font_size_override("font_size", 24)
                lbl.add_theme_color_override("font_color", color_item_normal)
                lbl.add_theme_color_override("font_shadow_color", Color.BLACK)
                lbl.add_theme_constant_override("shadow_offset_x", 1)
                lbl.add_theme_constant_override("shadow_offset_y", 1)
                _item_labels.append(lbl)
                items_container.add_child(lbl)

        # --- Character wheel (8 side-view previews) ---
        # Hidden by default, shown during character selection.
        # Anchored to center-bottom with symmetric offsets so it stays centered.
        _char_preview_container = HBoxContainer.new()
        _char_preview_container.name = "CharacterWheel"
        _char_preview_container.anchor_left = 0.5
        _char_preview_container.anchor_top = 1.0
        _char_preview_container.anchor_right = 0.5
        _char_preview_container.anchor_bottom = 1.0
        _char_preview_container.offset_left = -360.0
        _char_preview_container.offset_top = -160.0
        _char_preview_container.offset_right = 360.0
        _char_preview_container.offset_bottom = -20.0
        _char_preview_container.grow_horizontal = Control.GROW_DIRECTION_BOTH
        _char_preview_container.grow_vertical = Control.GROW_DIRECTION_BOTH
        _char_preview_container.alignment = BoxContainer.ALIGNMENT_CENTER
        _char_preview_container.add_theme_constant_override("separation", 12)
        _char_preview_container.visible = false
        add_child(_char_preview_container)

        # --- Footer ---
        # Two centered labels at the bottom of the screen.
        # "By" label (small gold text)
        _footer_by = Label.new()
        _footer_by.text = "By"
        _footer_by.anchor_left = 0.5
        _footer_by.anchor_top = 1.0
        _footer_by.anchor_right = 0.5
        _footer_by.anchor_bottom = 1.0
        _footer_by.offset_left = -200.0
        _footer_by.offset_top = -50.0
        _footer_by.offset_right = 200.0
        _footer_by.offset_bottom = -30.0
        _footer_by.grow_horizontal = Control.GROW_DIRECTION_BOTH
        _footer_by.grow_vertical = Control.GROW_DIRECTION_BOTH
        _footer_by.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        _footer_by.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        _footer_by.add_theme_font_size_override("font_size", 18)
        _footer_by.add_theme_color_override("font_color", color_footer_by)
        add_child(_footer_by)

        # "Marled Software" label (ivory text)
        _footer_name = Label.new()
        _footer_name.text = "Marled Software"
        _footer_name.anchor_left = 0.5
        _footer_name.anchor_top = 1.0
        _footer_name.anchor_right = 0.5
        _footer_name.anchor_bottom = 1.0
        _footer_name.offset_left = -200.0
        _footer_name.offset_top = -30.0
        _footer_name.offset_right = 200.0
        _footer_name.offset_bottom = -10.0
        _footer_name.grow_horizontal = Control.GROW_DIRECTION_BOTH
        _footer_name.grow_vertical = Control.GROW_DIRECTION_BOTH
        _footer_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        _footer_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        _footer_name.add_theme_font_size_override("font_size", 18)
        _footer_name.add_theme_color_override("font_color", color_footer_name)
        add_child(_footer_name)

        # --- Hint text (centered at the bottom, above the footer) ---
        _hint_label = Label.new()
        _hint_label.text = "UP/DOWN TO SELECT - LEFT/RIGHT TO CHANGE"
        _hint_label.anchor_left = 0.5
        _hint_label.anchor_top = 1.0
        _hint_label.anchor_right = 0.5
        _hint_label.anchor_bottom = 1.0
        _hint_label.offset_left = -300.0
        _hint_label.offset_top = -75.0
        _hint_label.offset_right = 300.0
        _hint_label.offset_bottom = -55.0
        _hint_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
        _hint_label.grow_vertical = Control.GROW_DIRECTION_BOTH
        _hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        _hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        _hint_label.add_theme_font_size_override("font_size", 16)
        _hint_label.add_theme_color_override("font_color", color_hint)
        add_child(_hint_label)


# Builds a gold-outlined stylebox for highlighting the selected character slot.
func _make_highlight_stylebox() -> StyleBoxFlat:
        var sb := StyleBoxFlat.new()
        sb.bg_color = Color(0, 0, 0, 0)
        sb.border_color = color_title_gold
        sb.set_border_width_all(2)
        sb.set_corner_radius_all(4)
        return sb


# Returns the resource path of the "side-view" sprite for the given character.
# Mirrors getCharacterSpriteBase() in Player.h.
func _character_sprite_path(char_idx: int) -> String:
        var base_names := [
                "player1_sheet",          # HERO_M
                "player2_sheet",           # HERO_F
                "char_mage_sheet",         # MAGE
                "char_orc_sheet",          # ORC
                "char_elf_sheet",          # ELF
                "char_knight_sheet",       # KNIGHT
                "char_golem_sheet",        # GOLEM
                "char_dragon_sheet",       # DRAGON
                "char_vampire_sheet",      # VAMPIRE (8th in our 8-slot wheel)
        ]
        if char_idx < 0 or char_idx >= base_names.size():
                return ""
        return "res://assets/sprites/%s.png" % base_names[char_idx]


# Returns a friendly display name for a character index.
func _character_name(char_idx: int) -> String:
        var names := [
                "HERO", "HEROINE", "MAGE", "ORC",
                "ELF", "KNIGHT", "GOLEM", "DRAGON", "VAMPIRE"
        ]
        if char_idx < 0 or char_idx >= names.size():
                return "???"
        return names[char_idx]


# ============================================================================
# State updates
# ============================================================================

# Refresh the text of every menu item to reflect the current selection values.
func _update_items_text() -> void:
        if _item_labels.is_empty():
                return
        _item_labels[0].text = "NUMBER OF PLAYERS: %d" % _num_players
        _item_labels[1].text = "GAME MODE: %s" % ("STORY" if _game_mode == GameMode.STORY else "INFINITE")
        _item_labels[2].text = "MUSIC: %s" % ("ON" if _music_enabled else "OFF")
        _item_labels[3].text = "TEST MODE: %s" % ("ON" if _test_mode_enabled else "OFF")
        _item_labels[4].text = "FULLSCREEN: %s" % ("ON" if _fullscreen_enabled else "OFF")
        _item_labels[5].text = "CONFIGURE JOYSTICK"
        _item_labels[6].text = "START GAME"
        _item_labels[7].text = "CREDITS"


# Updates the visual highlight of the character wheel.
# Mirrors drawSelectPlayer(): selected character appears brighter (alpha=1.0)
# and gets a gold outline; others are dimmed (alpha=0.55).
func _update_character_wheel() -> void:
        for i in _char_sprites.size():
                var sprite: TextureRect = _char_sprites[i]
                var hl: Panel = sprite.get_meta("highlight") as Panel
                if i == _wheel_highlight:
                        sprite.modulate = Color(1, 1, 1, 1.0)
                        sprite.scale = Vector2(1.15, 1.15)
                        if hl != null:
                                hl.visible = true
                else:
                        sprite.modulate = Color(1, 1, 1, 0.55)
                        sprite.scale = Vector2(1.0, 1.0)
                        if hl != null:
                                hl.visible = false


# ============================================================================
# Input handling
# ============================================================================

func _unhandled_input(event: InputEvent) -> void:
        # Keyboard navigation
        if event is InputEventKey and event.pressed and not event.echo:
                var key: int = event.keycode
                match key:
                        KEY_UP:
                                _move_selection(-1)
                        KEY_DOWN:
                                _move_selection(1)
                        KEY_LEFT:
                                _change_option(-1)
                        KEY_RIGHT:
                                _change_option(1)
                        KEY_ENTER, KEY_SPACE:
                                _activate_current()
                        KEY_ESCAPE:
                                # Quit the game from the main menu.
                                get_tree().quit()

        # Joystick / controller hat motion (d-pad)
        elif event is InputEventJoypadMotion:
                var ax: float = event.axis_value
                if event.axis == JOY_AXIS_LEFT_Y:
                        if ax < -0.5:
                                _move_selection(-1)
                        elif ax > 0.5:
                                _move_selection(1)
                elif event.axis == JOY_AXIS_LEFT_X:
                        if ax < -0.5:
                                _change_option(-1)
                        elif ax > 0.5:
                                _change_option(1)

        # Joystick button (confirm)
        elif event is InputEventJoypadButton and event.pressed:
                if event.button_index == JOY_BUTTON_A:
                        _activate_current()


# Move the selection cursor up/down by `delta` (-1 or +1), wrapping around.
func _move_selection(delta: int) -> void:
        _menu_item_index = posmod(_menu_item_index + delta, 8)
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.MENU_SELECT)


# Change the value of the currently-selected option (Left/Right).
func _change_option(delta: int) -> void:
        match _menu_item_index:
                0:  # Number of players
                        _num_players = 1 if _num_players == 2 else 2
                        _wheel_step = 0
                1:  # Game mode
                        _game_mode = GameMode.INFINITE if _game_mode == GameMode.STORY else GameMode.STORY
                2:  # Music on/off
                        _music_enabled = not _music_enabled
                        if AudioManager:
                                AudioManager.set_music_enabled(_music_enabled)
                                if _music_enabled:
                                        AudioManager.play_menu_music()
                3:  # Test mode on/off
                        _test_mode_enabled = not _test_mode_enabled
                4:  # Fullscreen on/off (toggles immediately)
                        _fullscreen_enabled = not _fullscreen_enabled
                        _apply_fullscreen()
                5, 6, 7:
                        # These items are not toggleable, just activate them.
                        pass
                _:
                        # Move the character wheel selection
                        _wheel_index = posmod(_wheel_index + delta, 8)
                        _wheel_highlight = _wheel_index
                        if _wheel_step == 0:
                                _p1_character = _wheel_index
                        else:
                                _p2_character = _wheel_index
        _update_items_text()
        _update_character_wheel()
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.MENU_SELECT)


# Apply the current fullscreen state via DisplayServer.
# Uses WINDOW_MODE_FULLSCREEN (exclusive fullscreen, mode 3) which is the
# most compatible mode across all Godot 4.x builds (WINDOW_MODE_WINDOWED_FULLSCREEN
# is missing in some 4.7 builds).
func _apply_fullscreen() -> void:
        var mode: int
        if _fullscreen_enabled:
                mode = DisplayServer.WINDOW_MODE_FULLSCREEN
        else:
                mode = DisplayServer.WINDOW_MODE_WINDOWED
        DisplayServer.window_set_mode(mode)


# Activate the currently-selected menu item (Enter/Space/A button).
func _activate_current() -> void:
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.MENU_CONFIRM)
        match _menu_item_index:
                5:
                        # CONFIGURE JOYSTICK - P1 first, then P2 (if 2 players)
                        configure_joystick_requested.emit(1)
                6:
                        # START GAME - in 2P mode the second player's joystick config
                        # is requested automatically (handled by parent via signal).
                        start_requested.emit(_num_players, _game_mode, _music_enabled,
                                         _p1_character, _p2_character)
                7:
                        credits_requested.emit()
                _:
                        # Toggleable items (0..4) confirm their current value.
                        _change_option(1 if _menu_item_index == 0 else 0)


# ============================================================================
# Public API for the parent scene
# ============================================================================

# Parent calls this after the CONFIGURE JOYSTICK screen returns, to advance to
# the next step (P2 in 2P mode, or simply refresh state in 1P mode).
func on_joystick_config_done(player: int) -> void:
        if player == 1 and _num_players == 2:
                # Need to configure P2 as well.
                configure_joystick_requested.emit(2)
        else:
                # Done configuring. Re-arm the cursor on START GAME (item 6).
                _menu_item_index = 6
                _update_items_text()


# Pre-select an item (used by external scenes to set focus).
func select_item(idx: int) -> void:
        _menu_item_index = clampi(idx, 0, 7)
        _update_items_text()
