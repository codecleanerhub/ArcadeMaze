# ============================================================================
# CreditsScreen.gd  (Control node)
#
# Godot port of:
#   - Game.cpp :: startCredits()
#   - Game.cpp :: updateCredits()
#   - Game.cpp :: drawCredits()
#
# Vertical scrolling credits that move from bottom to top at ~30 px/sec.
# Sections (all roles are "Luca A. Greco" - scherzoso, as in the original):
#   * ARCADE MAZE FANTASY  (title card)
#   * GAME DESIGN
#   * PROGRAMMING
#   * ART & GRAPHICS
#   * AUDIO
#   * STORY & WRITING
#   * QUALITY ASSURANCE
#   * PRODUCTION
#   * SPECIAL THANKS
#   * TOOLS & TECHNOLOGIES
#   * PUBLISHED BY (Marled Software)
#
# When the scrolling finishes, "THANK YOU FOR PLAYING!" + "Marled Software"
# is displayed centered, pulsing; ESC returns to the menu (and after a 5s
# timeout the screen auto-returns to the menu).
#
# Emitted signals:
#   * back_to_menu_requested()  -- when ESC is pressed or the timeout fires.
# ============================================================================
extends Control

signal back_to_menu_requested()

# --- Colors (mirror the SFML palette in drawCredits) ----------------------
@export var color_section:  Color = Color(1.000, 0.843, 0.392)   # 255,215,100
@export var color_role:     Color = Color(0.706, 0.706, 0.706)   # 180,180,180
@export var color_name:     Color = Color(0.961, 0.922, 0.784)    # 245,235,200
@export var color_thank:    Color = Color(1.000, 0.843, 0.392)
@export var color_publisher: Color = Color(0.784, 0.784, 0.784)
@export var color_hint:     Color = Color(0.588, 0.588, 0.588)
@export var color_bg:       Color = Color(0.020, 0.020, 0.039)    # 5,5,10

# --- Scrolling constants --------------------------------------------------
# Mirror: "Scroll speed: 30px/sec", "0.5px per frame at 60fps".
const SCROLL_SPEED_PX_PER_SEC: float = 30.0
# Mirror: each entry occupies ~40px vertically.
const ENTRY_HEIGHT_PX: float = 40.0
# Mirror: after scrolling we display "Thank you!" for 5 seconds.
const END_HOLD_MS: float = 5000.0

# --- Internal state (mirrors Game::creditsData / creditsScrollY / etc.) ---
var _entries: Array = []   # each entry is { "role": String, "name": String }
var _scroll_y: float = 0.0
var _finished: bool = false
var _end_timer_ms: float = 0.0


# ============================================================================
# Lifecycle
# ============================================================================
func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	# Build the credits data set (mirror of Game::startCredits).
	_build_entries()
	# Reset scroll state.
	_scroll_y = 0.0
	_finished = false
	_end_timer_ms = 0.0
	# If the AudioManager is available, switch to menu music.
	if AudioManager:
		AudioManager.stop_music()
		if AudioManager.music_enabled:
			AudioManager.play_menu_music()


func _process(delta: float) -> void:
	_update_credits(delta)
	queue_redraw()


# ============================================================================
# Building the credits data (mirror of startCredits())
# ============================================================================
func _build_entries() -> void:
	_entries.clear()
	# --- Title card ---
	_entries.append({ "role": "", "name": "" })
	_entries.append({ "role": "", "name": "" })
	_entries.append({ "role": "", "name": "" })
	_entries.append({ "role": "ARCADE MAZE FANTASY", "name": "" })
	_entries.append({ "role": "", "name": "" })
	_entries.append({ "role": "", "name": "" })

	# --- GAME DESIGN ---
	_entries.append({ "role": "GAME DESIGN", "name": "" })
	_entries.append({ "role": "", "name": "" })
	_add_role("Lead Game Designer")
	_add_role("Senior Level Designer")
	_add_role("Gameplay Engineer")
	_add_role("Balance & Tuning")
	_entries.append({ "role": "", "name": "" })

	# --- PROGRAMMING ---
	_entries.append({ "role": "PROGRAMMING", "name": "" })
	_entries.append({ "role": "", "name": "" })
	_add_role("Lead Programmer")
	_add_role("Engine Architecture")
	_add_role("AI & Pathfinding")
	_add_role("Physics & Collision")
	_add_role("Audio Engine")
	_add_role("Procedural Generation")
	_add_role("Bug Fixing Specialist")
	_add_role("Coffee to Code Compiler")
	_entries.append({ "role": "", "name": "" })

	# --- ART & GRAPHICS ---
	_entries.append({ "role": "ART & GRAPHICS", "name": "" })
	_entries.append({ "role": "", "name": "" })
	_add_role("Lead Artist")
	_add_role("Character Design")
	_add_role("Monster Design")
	_add_role("Boss Design")
	_add_role("Environment Art")
	_add_role("Pixel Art Director")
	_add_role("Sprite Animation")
	_add_role("UI/UX Design")
	_add_role("Special Effects")
	_entries.append({ "role": "", "name": "" })

	# --- AUDIO ---
	_entries.append({ "role": "AUDIO", "name": "" })
	_entries.append({ "role": "", "name": "" })
	_add_role("Music Composer")
	_add_role("Sound Designer")
	_add_role("Voice Acting")
	_add_role("Foley Artist")
	_add_role("Boom Operator")
	_entries.append({ "role": "", "name": "" })

	# --- STORY & WRITING ---
	_entries.append({ "role": "STORY & WRITING", "name": "" })
	_entries.append({ "role": "", "name": "" })
	_add_role("Story Writer")
	_add_role("Dialogue")
	_add_role("Lore Master")
	_add_role("Cutscene Director")
	_entries.append({ "role": "", "name": "" })

	# --- QUALITY ASSURANCE ---
	_entries.append({ "role": "QUALITY ASSURANCE", "name": "" })
	_entries.append({ "role": "", "name": "" })
	_add_role("Lead QA Tester")
	_add_role("Senior Tester")
	_add_role("Bug Hunter General")
	_add_role("Crash Reproducer")
	_add_role("Edge Case Finder")
	_entries.append({ "role": "", "name": "" })

	# --- PRODUCTION ---
	_entries.append({ "role": "PRODUCTION", "name": "" })
	_entries.append({ "role": "", "name": "" })
	_add_role("Executive Producer")
	_add_role("Project Manager")
	_add_role("Scrum Master")
	_add_role("Schedule Optimizer")
	_add_role("Morale Officer")
	_entries.append({ "role": "", "name": "" })

	# --- SPECIAL THANKS ---
	_entries.append({ "role": "SPECIAL THANKS", "name": "" })
	_entries.append({ "role": "", "name": "" })
	_add_role("To the universe for existing")
	_add_role("For the coffee that kept us going")
	_add_role("For the bugs that taught us patience")
	_add_role("To all the players")
	_add_role("For believing in the dream")
	_add_role("For never giving up")
	_entries.append({ "role": "", "name": "" })

	# --- TOOLS & TECHNOLOGIES ---
	_entries.append({ "role": "TOOLS & TECHNOLOGIES", "name": "" })
	_entries.append({ "role": "", "name": "" })
	_entries.append({ "role": "SFML",       "name": "Simple and Fast Multimedia Library" })
	_entries.append({ "role": "CMake",      "name": "Build System" })
	_entries.append({ "role": "Z-AI SDK",   "name": "AI Image Generation" })
	_entries.append({ "role": "Git",        "name": "Version Control" })
	_entries.append({ "role": "Pillow",     "name": "Python Image Processing" })
	_entries.append({ "role": "", "name": "" })

	# --- PUBLISHER ---
	_entries.append({ "role": "PUBLISHED BY", "name": "" })
	_entries.append({ "role": "", "name": "" })
	_entries.append({ "role": "Marled Software", "name": "" })
	_entries.append({ "role": "", "name": "" })
	_entries.append({ "role": "", "name": "" })
	_entries.append({ "role": "", "name": "" })


# Helper: every role is credited to "Luca A. Greco" (scherzoso).
func _add_role(role: String) -> void:
	_entries.append({ "role": role, "name": "Luca A. Greco" })


# ============================================================================
# updateCredits()  (mirror of Game::updateCredits)
# ============================================================================
func _update_credits(delta: float) -> void:
	if not _finished:
		# Scroll at 30 px/sec (the C++ uses 0.5 px/frame at 60 fps).
		_scroll_y += SCROLL_SPEED_PX_PER_SEC * delta
		var total_height: float = float(_entries.size()) * ENTRY_HEIGHT_PX
		if _scroll_y > total_height + 200.0:
			_finished = true
			_end_timer_ms = 0.0
	else:
		_end_timer_ms += delta * 1000.0
		# After 5 seconds of "Thank you!", return to the menu.
		if _end_timer_ms > END_HOLD_MS:
			back_to_menu_requested.emit()
			set_process(false)  # avoid emitting repeatedly


# ============================================================================
# Input
# ============================================================================
func _unhandled_input(event: InputEvent) -> void:
	# ESC: return to menu (matches the C++ behavior - the original uses
	# ESC because Enter is the key that opened the credits screen).
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			back_to_menu_requested.emit()
			set_process(false)


# ============================================================================
# drawCredits()  (mirror of Game::drawCredits)
# ============================================================================
func _draw() -> void:
	# Solid background
	draw_rect(Rect2(0, 0, size.x, size.y), color_bg)
	var font := get_theme_default_font()
	var cx: float = size.x / 2.0

	if not _finished:
		# Scroll entries from bottom to top.
		var start_y: float = size.y - _scroll_y
		var y: float = start_y
		for entry in _entries:
			if y > -60.0 and y < size.y + 60.0:
				var role: String = entry.role
				var name: String = entry.name
				if role.is_empty() and name.is_empty():
					pass  # blank line
				elif name.is_empty():
					# Section header (e.g. "PROGRAMMING")
					_draw_outlined_string(font, Vector2(cx, y), role,
					28, color_section, true)
				else:
					# Role + name pair
					_draw_plain_string(font, Vector2(cx, y), role,
					18, color_role, true)
					_draw_outlined_string(font, Vector2(cx, y + 18), name,
					18, color_name, true)
			y += ENTRY_HEIGHT_PX
	else:
		# Pulsing "THANK YOU FOR PLAYING!" centered.
		var pulse: float = (sin(_end_timer_ms * 0.003) + 1.0) * 0.5
		var alpha: float = 100.0 + pulse * 155.0
		var thank_col: Color = Color(color_thank.r, color_thank.g, color_thank.b, alpha / 255.0)
		_draw_outlined_string(font, Vector2(cx, size.y / 2.0 - 20.0),
			"THANK YOU FOR PLAYING!", 40, thank_col, true)
		_draw_plain_string(font, Vector2(cx, size.y / 2.0 + 60.0),
			"Marled Software", 24, color_publisher, true)
		_draw_plain_string(font, Vector2(cx, size.y - 40.0),
			"PRESS ESC TO RETURN", 16, color_hint, true)


# ----------------------------------------------------------------------------
# Helper: draw an outlined string (mirrors drawTextCenteredOutlined()).
# ----------------------------------------------------------------------------
func _draw_outlined_string(font: Font, at: Vector2, text: String,
	   font_size: int, color: Color,
	   centered: bool = false) -> void:
	var pos: Vector2 = at
	if centered:
		var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER,
			-1, font_size).x
		pos.x = at.x - w / 2.0
	# Outline: 4 shadow copies (mirrors drawTextOutlined)
	for off in [Vector2(-2, 0), Vector2(2, 0), Vector2(0, -2), Vector2(0, 2)]:
		draw_string(font, Vector2(pos.x + off.x, pos.y + off.y + font_size), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.BLACK)
	draw_string(font, Vector2(pos.x, pos.y + font_size), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


# Helper: plain centered/left string (mirrors drawTextCentered()).
func _draw_plain_string(font: Font, at: Vector2, text: String,
	font_size: int, color: Color,
	centered: bool = false) -> void:
	var pos: Vector2 = at
	if centered:
		var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER,
			-1, font_size).x
		pos.x = at.x - w / 2.0
	draw_string(font, Vector2(pos.x, pos.y + font_size), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


# ============================================================================
# Public API
# ============================================================================
# Reset the scroll to the beginning (used when re-entering the screen).
func restart() -> void:
	_scroll_y = 0.0
	_finished = false
	_end_timer_ms = 0.0
	set_process(true)


# Skip directly to the "Thank you!" screen.
func skip_to_end() -> void:
	_finished = true
	_end_timer_ms = 0.0
