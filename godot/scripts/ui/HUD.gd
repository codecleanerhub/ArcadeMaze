# ============================================================================
# HUD.gd  (Control node - game HUD)
#
# Godot port of:
#   - UI.h
#   - UI.cpp
#
# The HUD is an 80 px tall bar at the top of the screen (UI_HEIGHT = 80) that
# shows: SCORE, LIVES (hearts), ENERGY bar, WEAPON name, AMMO bar, TREASURES
# remaining. Supports both 1P and 2P layouts (in 2P the bar is split between
# the left = P1, center = treasures, right = P2).
#
# Heart sprite:
#   * Loaded via loadHeartSprite() from res://assets/sprites/ui_heart.png.
#   * Used by drawHeart() for each life; if the PNG is missing, falls back
#     to a procedural heart drawn in _draw_detailed_heart() (same fallback
#     logic as the original UI.cpp).
#
# Layout (1P mode) - mirrors UI.cpp::render(target, player, remainingTreasures):
#       x=  10  SCORE       + score
#       x= 150  LIVES       + hearts
#       x= 280  ENERGY      + energy bar (100x18, magenta on gray)
#       x= 420  WPN         + weapon name (colored)
#       x= 570  AMMO        + ammo bar (100x18, yellow on gray, norm. on 15)
#       x= 700  TRES        + remaining treasures
#
# Layout (2P mode) - mirrors UI.cpp::render(target, p1, p2, remainingTreasures):
#   P1 (left):   P1 score, LIFE hearts (16px), EN bar (60x14), WPN name, ammo#
#   Center:      TRES + remainingTreasures
#   P2 (right):  P2 score, LIFE hearts (16px), EN bar (60x14), WPN name, ammo#
# ============================================================================
extends Control

# --- Layout constants (mirrors Utils.h) -----------------------------------
const WINDOW_WIDTH: int = 1024
const WINDOW_HEIGHT: int = 1024
const UI_HEIGHT: int = 80

# --- Public API ------------------------------------------------------------
# Player snapshot for 1P rendering. Set externally before each render.
# Expected fields (mirror Player accessors used in UI.cpp):
#     score:int, lives:int, energy:float, max_energy:float,
#     weapon_name:String, weapon_color:Color, weapon_ammo:int, weapon_max:int
# Actually we expose a single `set_player_state` API instead of breaking it
# down, so the caller doesn't have to know about the exact field names.

# The "PlayerState" struct is a simple Dictionary with the fields above.
# We keep two slots for 1P/2P and a separate remaining-treasures counter.

# --- Signals ---------------------------------------------------------------
signal heart_clicked()  # currently unused but exposed for future editor hooks

# --- Exported theme colors (mirror SFML palette) --------------------------
@export var color_bg:        Color = Color(0.078, 0.078, 0.078)      # 20,20,20
@export var color_score:     Color = Color(1.000, 1.000, 0.000)      # Yellow
@export var color_label:     Color = Color.WHITE
@export var color_energy:     Color = Color(1.000, 0.000, 1.000)     # Magenta
@export var color_energy_bg:  Color = Color(0.392, 0.392, 0.392)
@export var color_energy_border: Color = Color(0.235, 0.235, 0.235)
@export var color_ammo:       Color = Color(1.000, 1.000, 0.000)
@export var color_p1_label:    Color = Color(0.392, 0.784, 1.000)     # 100,200,255
@export var color_p2_label:    Color = Color(1.000, 0.588, 0.392)     # 255,150,100
@export var color_heart_fill:  Color = Color(0.863, 0.078, 0.078)    # 220,20,20
@export var color_heart_outline: Color = Color(0.392, 0.000, 0.000)  # 100,0,0

# --- Heart sprite (mirror of UI::heartTexture + heartSprite) ---------------
var _heart_texture: Texture2D = null
var _heart_loaded: bool = false

# --- HUD state (set externally before _draw) ------------------------------
# 1P snapshot
var _p1: Dictionary = {
        "score": 0, "lives": 3, "energy": 100.0, "max_energy": 100.0,
        "weapon_name": "PISTOL", "weapon_color": Color(0.784, 0.784, 0.196),
        "weapon_ammo": 15, "weapon_max": 15,
}
# 2P snapshot (only used when _num_players == 2)
var _p2: Dictionary = {
        "score": 0, "lives": 3, "energy": 100.0, "max_energy": 100.0,
        "weapon_name": "PISTOL", "weapon_color": Color(0.784, 0.784, 0.196),
        "weapon_ammo": 15, "weapon_max": 15,
}
var _num_players: int = 1
var _remaining_treasures: int = 0

# Normalisation constant (mirror UI.cpp): ammo bar uses 15 as the max.
const _AMMO_NORMALISER: int = 15

# Built-in font for labels; we use the default Theme font (kept simple).


# ============================================================================
# Lifecycle
# ============================================================================
func _ready() -> void:
        # The HUD spans the full width and is UI_HEIGHT tall at the top.
        set_anchors_preset(Control.PRESET_TOP_WIDE)
        custom_minimum_size = Vector2(WINDOW_WIDTH, UI_HEIGHT)
        size = Vector2(WINDOW_WIDTH, UI_HEIGHT)
        mouse_filter = Control.MOUSE_FILTER_IGNORE
        load_heart_sprite("res://assets/sprites/ui_heart.png")


# ----------------------------------------------------------------------------
# loadHeartSprite: load the heart PNG. Returns true on success.
# Mirrors UI::loadHeartSprite(path). If the file is missing, `heartLoaded`
# stays false and drawHeart() will use the procedural fallback.
# ----------------------------------------------------------------------------
func load_heart_sprite(path: String) -> bool:
        if not ResourceLoader.exists(path):
                _heart_loaded = false
                _heart_texture = null
                return false
        var res := load(path)
        if res is Texture2D:
                _heart_texture = res
                _heart_loaded = true
                return true
        _heart_loaded = false
        _heart_texture = null
        return false


# ============================================================================
# Public API  (set state before redrawing)
# ============================================================================
# Set the 1P snapshot. The Dictionary may contain any subset of:
# score, lives, energy, max_energy, weapon_name, weapon_color, weapon_ammo,
# weapon_max.
func set_player_state(snap: Dictionary) -> void:
        for k in snap.keys():
                _p1[k] = snap[k]
        queue_redraw()


# Set the 2P snapshot (used only when num_players == 2).
func set_player2_state(snap: Dictionary) -> void:
        for k in snap.keys():
                _p2[k] = snap[k]
        queue_redraw()


# Set the number of players (1 or 2) - selects the layout.
func set_num_players(n: int) -> void:
        _num_players = clampi(n, 1, 2)
        queue_redraw()


# Set the remaining treasures count (drives the "boss is coming" trigger).
func set_remaining_treasures(n: int) -> void:
        _remaining_treasures = n
        queue_redraw()


# Set the boss HP bar (shown during boss fights).
var _boss_hp: int = 0
var _boss_max_hp: int = 0
var _boss_type: int = 0
var _show_boss_bar: bool = false

func set_boss_hp(hp: int, max_hp: int, boss_type: int) -> void:
        _boss_hp = hp
        _boss_max_hp = max_hp
        _boss_type = boss_type
        _show_boss_bar = true
        queue_redraw()

func hide_boss_bar() -> void:
        _show_boss_bar = false
        queue_redraw()


# ============================================================================
# Drawing
# ============================================================================
func _draw() -> void:
        # Background bar
        draw_rect(Rect2(0, 0, WINDOW_WIDTH, UI_HEIGHT), color_bg)
        if _num_players == 1:
                _draw_1p()
        else:
                _draw_2p()
        # Boss HP bar (shown during boss fights)
        if _show_boss_bar and _boss_max_hp > 0:
                _draw_boss_bar()


func _draw_boss_bar() -> void:
        var bar_x: float = 300.0
        var bar_y: float = 10.0
        var bar_w: float = 424.0
        var bar_h: float = 16.0
        # Background
        draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(0.1, 0.0, 0.0, 0.8), true)
        # HP fill
        var hp_ratio: float = float(_boss_hp) / float(_boss_max_hp)
        var hp_color: Color = Color(0.8, 0.2, 0.1) if hp_ratio < 0.3 else Color(0.9, 0.5, 0.1)
        draw_rect(Rect2(bar_x + 2, bar_y + 2, (bar_w - 4) * hp_ratio, bar_h - 4), hp_color, true)
        # Border
        draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(0.8, 0.6, 0.2), false, 2)
        # Label
        _draw_label_colored("BOSS", bar_x + 4, bar_y - 14, Color(0.9, 0.7, 0.3))


# --- 1-player layout (mirror UI::render single-player) ---------------------
func _draw_1p() -> void:
        # SCORE
        _draw_label("SCORE", 10, 10)
        _draw_label_int(_p1.score, 10, 30, color_score)
        # LIVES (hearts)
        _draw_label("LIVES", 150, 10)
        for i in _p1.lives:
                _draw_heart(160 + i * 24, 35, 8.0)
        # ENERGY
        _draw_label("ENERGY", 280, 10)
        _draw_bar(280, 30, 100, 18,
                float(_p1.energy) / float(_p1.max_energy), color_energy)
        # WPN
        _draw_label("WPN", 420, 10)
        _draw_label_colored(_p1.weapon_name, 420, 30, _p1.weapon_color)
        # AMMO
        _draw_label("AMMO", 570, 10)
        var ammo_ratio: float = float(_p1.weapon_ammo) / float(_AMMO_NORMALISER)
        _draw_bar(570, 30, 100, 18, ammo_ratio, color_ammo)
        # TRES
        _draw_label("TRES", 700, 10)
        _draw_label_int(_remaining_treasures, 700, 30, color_score)


# --- 2-player layout (mirror UI::render two-player) ------------------------
func _draw_2p() -> void:
        # === PLAYER 1 (left) ===
        _draw_label_colored("P1", 10, 10, color_p1_label)
        _draw_label_int(_p1.score, 10, 30, color_score)
        _draw_label("LIFE", 80, 10)
        for i in _p1.lives:
                _draw_heart(90 + i * 16, 35, 6.0)
        _draw_label("EN", 180, 10)
        _draw_bar(180, 32, 60, 14,
                float(_p1.energy) / float(_p1.max_energy), color_energy)
        _draw_label_colored(_p1.weapon_name, 250, 10, _p1.weapon_color)
        _draw_label_int(_p1.weapon_ammo, 250, 30, color_score)

        # === TREASURES (center) ===
        _draw_label("TRES", 470, 10)
        _draw_label_int(_remaining_treasures, 470, 30, color_score)

        # === PLAYER 2 (right) ===
        _draw_label_colored("P2", 560, 10, color_p2_label)
        _draw_label_int(_p2.score, 560, 30, color_score)
        _draw_label("LIFE", 640, 10)
        for i in _p2.lives:
                _draw_heart(650 + i * 16, 35, 6.0)
        _draw_label("EN", 740, 10)
        _draw_bar(740, 32, 60, 14,
                float(_p2.energy) / float(_p2.max_energy), color_energy)
        _draw_label_colored(_p2.weapon_name, 820, 10, _p2.weapon_color)
        _draw_label_int(_p2.weapon_ammo, 820, 30, color_score)


# ----------------------------------------------------------------------------
# drawHeart(x, y, size): draws a heart at (x, y) with radius `size`.
# Mirrors UI::drawHeart(target, x, y, size).
#   * If the PNG heart sprite is loaded, uses it (much higher quality, AI-gen).
#   * Otherwise falls back to drawDetailedHeart (procedural): two semicircles
#     + triangle + a small white highlight.
# The PNG is 32x32; the anchor is at its center (16, 16).
# ----------------------------------------------------------------------------
func _draw_heart(x: float, y: float, size: float) -> void:
        if _heart_loaded and _heart_texture != null:
                # Scale so the sprite is ~size*2 px wide (mirror UI.cpp:scale = size/16).
                var scale: float = size / 16.0
                var w: float = _heart_texture.get_width() * scale
                var h: float = _heart_texture.get_height() * scale
                var rect := Rect2(x - w / 2.0, y - h / 2.0, w, h)
                draw_texture_rect(_heart_texture, rect, false)
        else:
                _draw_detailed_heart(x, y, size, color_heart_fill, color_heart_outline)


# ----------------------------------------------------------------------------
# drawDetailedHeart (procedural fallback): mirror of the standalone function
# in UI.cpp. Two semicircles + triangle + white highlight.
# ----------------------------------------------------------------------------
func _draw_detailed_heart(x: float, y: float, size: float,
                                                  fill: Color, outline: Color) -> void:
        # Left lobe
        draw_circle(Vector2(x - size / 2.0, y - size / 4.0), size / 2.0, fill)
        # Right lobe
        draw_circle(Vector2(x, y - size / 4.0), size / 2.0, fill)
        # Bottom triangle (pointed tip)
        var tip := PackedVector2Array([
                Vector2(x - size, y),
                Vector2(x + size, y),
                Vector2(x, y + size),
        ])
        draw_colored_polygon(tip, fill)
        # Outline (drawn as line segments)
        _draw_circle_outline(Vector2(x - size / 2.0, y - size / 4.0), size / 2.0, outline, 1.5)
        _draw_circle_outline(Vector2(x, y - size / 4.0), size / 2.0, outline, 1.5)
        draw_polyline(tip + PackedVector2Array([tip[0]]), outline, 1.5, true)
        # White highlight (small dot in upper-left)
        draw_circle(Vector2(x - size / 3.0, y - size / 4.0), 1.5,
                Color(1, 1, 1, 200.0 / 255.0))


# Draw a circle outline as a polyline (Godot has no direct outline API for
# CircleShape2D in _draw; we approximate with a thin line loop).
func _draw_circle_outline(center: Vector2, radius: float,
                                                  color: Color, width: float) -> void:
        var pts := PackedVector2Array()
        var segs: int = 24
        for i in segs:
                var a: float = TAU * i / segs
                pts.append(center + Vector2(cos(a), sin(a)) * radius)
        draw_polyline(pts + PackedVector2Array([pts[0]]), color, width, true)


# Draw a label with a black outline (mirror of drawTextOutlined()).
func _draw_label(text: String, x: float, y: float) -> void:
        _draw_label_colored(text, x, y, color_label)


func _draw_label_colored(text: String, x: float, y: float, color: Color) -> void:
        # Approximate the bitmap-font outlined look by drawing 4 black shadows + the
        # foreground text. (Mirror of drawTextOutlined.)
        var font := get_theme_default_font()
        var font_size: int = 16
        # 4 shadow copies (offset by ±2 px)
        for off in [Vector2(-2, 0), Vector2(2, 0), Vector2(0, -2), Vector2(0, 2)]:
                draw_string(font, Vector2(x + off.x, y + off.y + font_size), text,
                        HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.BLACK)
        draw_string(font, Vector2(x, y + font_size), text,
                HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


# Draw an integer as outlined text (used for SCORE/TREASURES/AMMO count).
func _draw_label_int(value: int, x: float, y: float, color: Color) -> void:
        _draw_label_colored(str(value), x, y, color)


# Draw a horizontal bar (mirror of the energy/ammo bar in UI.cpp).
# Background = gray rounded rectangle + colored foreground proportional to ratio.
func _draw_bar(x: float, y: float, w: float, h: float,
                           ratio: float, fg_color: Color) -> void:
        # Background (gray with darker outline)
        draw_rect(Rect2(x, y, w, h), color_energy_bg, true)
        draw_rect(Rect2(x, y, w, h), color_energy_border, false, 2.0)
        # Foreground (clamped ratio)
        var r: float = clampf(ratio, 0.0, 1.0)
        if r > 0.0:
                draw_rect(Rect2(x, y, w * r, h), fg_color, true)
