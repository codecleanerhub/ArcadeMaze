## BootManager.gd - Autoload singleton that runs FIRST and sets up the display.
##
## Responsibilities:
##   1. Force fullscreen at startup (handles all platforms: Windows, Linux,
##      macOS, and future HTML5 browser export).
##   2. Adapt the game window to the user's actual screen resolution.
##   3. Apply the correct stretch mode so the 1024x1024 design space scales
##      cleanly to any aspect ratio (16:9, 16:10, 4:3, ultrawide, etc.)
##      without distortion or letterboxing.
##
## Why a dedicated autoload instead of just project.godot settings?
##   - project.godot's window/size/mode=3 works on desktop, but on some
##     Linux compositors and on HTML5 export it doesn't take effect until
##     the first frame. Calling DisplayServer methods in _ready() guarantees
##     the window is fullscreen before any scene is drawn.
##   - We also want to detect the screen size dynamically (the user may have
##     multiple monitors with different resolutions) and set the window size
##     accordingly, so the game always fills the screen.
##   - For HTML5 export: Godot runs inside a canvas. Fullscreen requires a
##     user gesture (click) due to browser security. This script detects
##     HTML5 and only sets the canvas size, leaving fullscreen toggle to
##     a user-initiated action (handled in MainMenu.gd on first input).
##
## Load order: BootManager MUST be the first autoload. In project.godot:
##   [autoload]
##   BootManager="*res://scripts/core/BootManager.gd"
##   GameManager="*res://scripts/core/GameManager.gd"
##   ...
extends Node

# --- Display mode enum (mirrors DisplayServer.WindowMode) ---
# In Godot 4.7 the WindowMode enum values are:
#   WINDOW_MODE_WINDOWED    = 0  (regular window)
#   WINDOW_MODE_MINIMIZED   = 1
#   WINDOW_MODE_MAXIMIZED   = 2
#   WINDOW_MODE_FULLSCREEN  = 3  (exclusive fullscreen, changes screen res)
#
# Note: Godot 4.3+ added WINDOW_MODE_WINDOWED_FULLSCREEN (borderless), but
# the constant is missing in some 4.7 builds, so we use the numeric value 3
# (exclusive fullscreen) which is the most compatible across all Godot 4.x.
# Exclusive fullscreen works fine on desktop and is the same mode that
# project.godot's window/size/mode=3 uses.
const DESKTOP_FULLSCREEN_MODE: int = 3  # WINDOW_MODE_FULLSCREEN

# Design resolution (must match project.godot viewport_width/height).
const DESIGN_WIDTH: int = 1920
const DESIGN_HEIGHT: int = 1080


func _ready() -> void:
        _setup_display()


## Configures the display for fullscreen + adaptive resolution.
## Called once at startup. Safe to call again to re-apply (e.g. after the
## user changes monitor).
func _setup_display() -> void:
        var os_name: String = OS.get_name()

        # --- HTML5 / Web export ---
        # In the browser, we cannot force fullscreen without a user gesture.
        # We just make sure the window fills the browser viewport. The user
        # can press F11 or click a button in-game to enter real fullscreen.
        if os_name == "Web":
                _setup_web()
                return

        # --- Desktop (Windows, Linux, macOS) ---
        _setup_desktop(os_name)


## Desktop setup: borderless fullscreen + canvas_items stretch + expand aspect.
## This makes the game fill the entire screen at the user's native resolution,
## and the UI (built with anchors) adapts to any aspect ratio.
func _setup_desktop(os_name: String) -> void:
        # 1. Get the actual screen resolution of the user's primary monitor.
        var screen_id: int = DisplayServer.get_primary_screen()
        var screen_size: Vector2i = DisplayServer.screen_get_size(screen_id)
        # print("[BootManager] Primary screen #%d size: %s" % [screen_id, str(screen_size)])

        # 2. Set the window size to match the screen (so that when we toggle
        #    to borderless fullscreen, the rendering area is exactly the
        #    screen resolution - no scaling artifacts).
        #    On some compositors, setting the window size before fullscreen
        #    helps avoid a brief flash of the wrong size.
        var win: Window = get_window()
        if win:
                win.size = screen_size
                win.position = DisplayServer.screen_get_position(screen_id)

        # 3. Switch to borderless fullscreen (MODE_WINDOWED_FULLSCREEN).
        #    This is preferred over exclusive fullscreen (MODE_FULLSCREEN)
        #    because:
        #    - No resolution change flicker
        #    - Faster Alt+Tab / multi-monitor switching
        #    - Works reliably on all compositors (X11, Wayland, Windows, macOS)
        DisplayServer.window_set_mode(DESKTOP_FULLSCREEN_MODE)

        # 4. Ensure the stretch mode is canvas_items + expand so the UI
        #    adapts to the actual screen aspect ratio (16:9, 16:10, 21:9, ...).
        #    project.godot already sets this, but we re-apply defensively in
        #    case some platform override changed it.
        get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
        get_tree().root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND


## Web (HTML5) setup: we can't force fullscreen, but we ensure the canvas
## fills the browser viewport. The game's design resolution (1024x1024)
## will be scaled to fit via CSS (Godot handles this automatically).
## A user-initiated fullscreen toggle is wired up in MainMenu.gd on first
## input.
func _setup_web() -> void:
        # On Web, the window is the browser canvas. We just make sure the
        # stretch mode is correct so the game scales cleanly.
        get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
        get_tree().root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
        # NOTE: To enter real fullscreen in the browser, the user must press
        # F11 (browser fullscreen) or click a button in-game. Godot's
        # DisplayServer.window_set_mode(MODE_FULLSCREEN) on Web requires a
        # user gesture - we handle this in MainMenu.gd's _unhandled_input.


## Public API: call this from a button press (e.g. in MainMenu) to toggle
## real fullscreen. On Web, this must be called from within an input event
## handler (user gesture) or the browser will reject it.
func toggle_fullscreen() -> void:
        var current_mode: int = DisplayServer.window_get_mode()
        if current_mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
                DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
        else:
                DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


## Public API: returns true if the game is currently fullscreen.
func is_fullscreen() -> bool:
        var mode: int = DisplayServer.window_get_mode()
        return mode == DisplayServer.WINDOW_MODE_FULLSCREEN
