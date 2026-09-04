# ============================================================================
# PauseOverlay.gd  (Control node)
#
# Godot port of the PAUSE overlay in Game.cpp (the `if (state == STATE_PAUSE)`
# block at the end of Game::render()).
#
# Behavior:
#   * Full-screen semi-transparent overlay (so the frozen game frame behind is
#     still visible).
#   * Centered big "PAUSE" label in RED, INTERMITTENT (alpha oscillates
#     between 100 and 255 via sinf, mirror of the C++ implementation).
#   * Subtitle "PRESS P TO RESUME" below, same color/alpha modulation.
#   * When this overlay is visible, the game behind is "frozen": the parent
#     should not call _process / _physics_process on the gameplay tree while
#     the overlay is shown (process_mode = PROCESS_MODE_ALWAYS lets the
#     overlay keep updating, regardless of the parent's paused state).
#
# Emitted signals:
#   * resume_requested()       -- the user pressed the pause/resume key.
# ============================================================================
extends Control

signal resume_requested()

# --- Theme colors (mirror the SFML palette in Game::render PAUSE block) ---
@export var color_pause_text:  Color = Color(1.000, 0.157, 0.157)   # 255,40,40
@export var color_resume_hint: Color = Color(1.000, 0.784, 0.784)   # 255,200,200
@export var color_overlay_bg: Color = Color(0.0, 0.0, 0.0, 0.55)    # dark veil

# Pause-text animation timer (mirrors `static float pauseTime` in the C++ code).
# The original advances it by 0.05 each frame; here we use delta in _process.
var _pause_time: float = 0.0

# The actual child nodes.
var _bg: ColorRect
var _pause_label: Label
var _resume_label: Label
# The pause key (default 'P'). Can be overridden by the parent.
@export var pause_action: String = "pause"


# ============================================================================
# Lifecycle
# ============================================================================
func _ready() -> void:
        set_anchors_preset(Control.PRESET_FULL_RECT)
        mouse_filter = Control.MOUSE_FILTER_STOP
        # Keep processing even when the tree is paused, so the pulse animation
        # keeps running.
        process_mode = Node.PROCESS_MODE_ALWAYS
        focus_mode = Control.FOCUS_ALL
        _build_ui()
        visible = false


func _process(delta: float) -> void:
        # Advance the animation timer (mirror: pauseTime += 0.05f each frame).
        _pause_time += delta * 5.0  # 0.05 at 60fps is ~3.0/s; we use a 5x multiplier
                # to match the original feel.
        # Compute alpha (sin maps to [0..1], we shift to [100..255] / 255).
        var pulse: float = (sin(_pause_time) + 1.0) * 0.5
        var alpha: float = (100.0 + pulse * 155.0) / 255.0
        _pause_label.modulate = Color(color_pause_text.r, color_pause_text.g,
                color_pause_text.b, alpha)
        _resume_label.modulate = Color(color_resume_hint.r, color_resume_hint.g,
                color_resume_hint.b, alpha)


# ============================================================================
# UI construction
# ============================================================================
func _build_ui() -> void:
        # --- Semi-transparent full-screen veil ---
        _bg = ColorRect.new()
        _bg.set_anchors_preset(Control.PRESET_FULL_RECT)
        _bg.color = color_overlay_bg
        _bg.mouse_filter = Control.MOUSE_FILTER_STOP
        add_child(_bg)

        # --- "PAUSE" label (big, centered, red) ---
        # Use explicit anchors so the label spans the full width and centers
        # its text. This avoids relying on `size.x` (which is 0 at _ready()).
        _pause_label = Label.new()
        _pause_label.text = "PAUSE"
        _pause_label.anchor_left = 0.0
        _pause_label.anchor_top = 0.0
        _pause_label.anchor_right = 1.0
        _pause_label.anchor_bottom = 1.0
        _pause_label.offset_top = -60.0
        _pause_label.offset_bottom = 20.0
        _pause_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
        _pause_label.grow_vertical = Control.GROW_DIRECTION_BOTH
        _pause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        _pause_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        _pause_label.add_theme_font_size_override("font_size", 80)
        _pause_label.add_theme_color_override("font_color", color_pause_text)
        _pause_label.add_theme_color_override("font_shadow_color", Color.BLACK)
        _pause_label.add_theme_constant_override("shadow_offset_x", 2)
        _pause_label.add_theme_constant_override("shadow_offset_y", 2)
        add_child(_pause_label)

        # --- "PRESS P TO RESUME" label (smaller, below) ---
        _resume_label = Label.new()
        _resume_label.text = "PRESS P TO RESUME"
        _resume_label.anchor_left = 0.0
        _resume_label.anchor_top = 0.0
        _resume_label.anchor_right = 1.0
        _resume_label.anchor_bottom = 1.0
        _resume_label.offset_top = 60.0
        _resume_label.offset_bottom = 100.0
        _resume_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
        _resume_label.grow_vertical = Control.GROW_DIRECTION_BOTH
        _resume_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        _resume_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        _resume_label.add_theme_font_size_override("font_size", 24)
        _resume_label.add_theme_color_override("font_color", color_resume_hint)
        add_child(_resume_label)


# ============================================================================
# Input
# ============================================================================
func _unhandled_input(event: InputEvent) -> void:
        if not visible:
                return
        # Toggle off when the pause key (default 'P') is pressed.
        if event.is_action_pressed(pause_action):
                resume_requested.emit()
        elif event is InputEventKey and event.pressed and not event.echo:
                if event.keycode == KEY_ESCAPE:
                        resume_requested.emit()


# ============================================================================
# Public API
# ============================================================================
# Show the overlay (and pause the underlying tree, if requested).
func show_overlay(pause_tree: bool = true) -> void:
        visible = true
        _pause_time = 0.0
        if pause_tree and get_tree():
                get_tree().paused = true


# Hide the overlay and unpause the underlying tree.
func hide_overlay() -> void:
        visible = false
        if get_tree():
                get_tree().paused = false
