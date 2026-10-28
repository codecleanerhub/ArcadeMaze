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
#
# Background dedicato (bg_credits.png): teschio pirata stile Monkey Island con
# occhiali da sole (emoji style) e braccia scheletriche con la mano nel gesto
# OK (pugno chiuso e pollice in su), su sala gotica con torce — stesso stile
# e palette degli altri sfondi (es. bg_halloffame.png). Copertina cover-fit
# + overlay scuro per la leggibilità del testo scorrevole, come HallOfFame.
# ============================================================================
extends Control

signal back_to_menu_requested()

# --- Colors (mirror the SFML palette in drawCredits) ----------------------
# TASK 78 — palette ORO MEDIEVALE: le sezioni dei credits in oro caldo
# (coerente col nuovo logo del titolo in font Goth And Gothic).
@export var color_section:  Color = Color(0.941, 0.780, 0.373)   # oro caldo
@export var color_role:     Color = Color(0.706, 0.706, 0.706)   # 180,180,180
@export var color_name:     Color = Color(0.961, 0.922, 0.784)    # 245,235,200
@export var color_thank:    Color = Color(0.941, 0.780, 0.373)   # oro caldo
@export var color_publisher: Color = Color(0.784, 0.784, 0.784)
@export var color_hint:     Color = Color(0.588, 0.588, 0.588)
@export var color_bg:       Color = Color(0.020, 0.020, 0.039)    # 5,5,10

# --- Background (stile delle altre schermate: cover-fit + overlay) ---------
var _bg_texture: Texture2D = null

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
        # Self-wire: when the user requests to go back, return to menu.
        back_to_menu_requested.connect(_on_back_to_menu_requested)
        # Background dedicato (pattern HallOfFameScreen): caricamento diretto
        # dal filesystem perche' l'import di Godot potrebbe non essere ancora
        # disponibile al primo avvio dopo l'aggiunta del file.
        var _abs := ProjectSettings.globalize_path("res://assets/backgrounds/bg_credits.png")
        if FileAccess.file_exists(_abs):
                var _img := Image.new()
                if _img.load(_abs) == OK:
                        _bg_texture = ImageTexture.create_from_image(_img)


func _on_back_to_menu_requested() -> void:
        if GameManager:
                GameManager.go_to_menu()


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
        _entries.append({ "role": I18n.t("cr.design"), "name": "" })
        _entries.append({ "role": "", "name": "" })
        _add_role(I18n.t("cr.lead_game_designer"))
        _add_role(I18n.t("cr.senior_level_designer"))
        _add_role(I18n.t("cr.gameplay_engineer"))
        _add_role(I18n.t("cr.balance_tuning"))
        _entries.append({ "role": "", "name": "" })

        # --- PROGRAMMING ---
        _entries.append({ "role": I18n.t("cr.programming"), "name": "" })
        _entries.append({ "role": "", "name": "" })
        _add_role(I18n.t("cr.lead_programmer"))
        _add_role(I18n.t("cr.engine_architecture"))
        _add_role(I18n.t("cr.ai_pathfinding"))
        _add_role(I18n.t("cr.physics_collision"))
        _add_role(I18n.t("cr.audio_engine"))
        _add_role(I18n.t("cr.procedural_generation"))
        _add_role(I18n.t("cr.bug_fixing"))
        _add_role(I18n.t("cr.coffee_compiler"))
        _entries.append({ "role": "", "name": "" })

        # --- ART & GRAPHICS ---
        _entries.append({ "role": I18n.t("cr.art"), "name": "" })
        _entries.append({ "role": "", "name": "" })
        _add_role(I18n.t("cr.lead_artist"))
        _add_role(I18n.t("cr.character_design"))
        _add_role(I18n.t("cr.monster_design"))
        _add_role(I18n.t("cr.boss_design"))
        _add_role(I18n.t("cr.environment_art"))
        _add_role(I18n.t("cr.pixel_art_director"))
        _add_role(I18n.t("cr.sprite_animation"))
        _add_role(I18n.t("cr.uiux_design"))
        _add_role(I18n.t("cr.special_effects"))
        _entries.append({ "role": "", "name": "" })

        # --- AUDIO ---
        _entries.append({ "role": I18n.t("cr.audio"), "name": "" })
        _entries.append({ "role": "", "name": "" })
        _add_role(I18n.t("cr.music_composer"))
        _add_role(I18n.t("cr.sound_designer"))
        _add_role(I18n.t("cr.voice_acting"))
        _add_role(I18n.t("cr.foley_artist"))
        _add_role(I18n.t("cr.boom_operator"))
        _entries.append({ "role": "", "name": "" })

        # --- STORY & WRITING ---
        _entries.append({ "role": I18n.t("cr.story"), "name": "" })
        _entries.append({ "role": "", "name": "" })
        _add_role(I18n.t("cr.story_writer"))
        _add_role(I18n.t("cr.dialogue"))
        _add_role(I18n.t("cr.lore_master"))
        _add_role(I18n.t("cr.cutscene_director"))
        _entries.append({ "role": "", "name": "" })

        # --- QUALITY ASSURANCE ---
        _entries.append({ "role": I18n.t("cr.qa"), "name": "" })
        _entries.append({ "role": "", "name": "" })
        _add_role(I18n.t("cr.lead_qa_tester"))
        _add_role(I18n.t("cr.senior_tester"))
        _add_role(I18n.t("cr.bug_hunter"))
        _add_role(I18n.t("cr.crash_reproducer"))
        _add_role(I18n.t("cr.edge_case_finder"))
        _entries.append({ "role": "", "name": "" })

        # --- PRODUCTION ---
        _entries.append({ "role": I18n.t("cr.production"), "name": "" })
        _entries.append({ "role": "", "name": "" })
        _add_role(I18n.t("cr.executive_producer"))
        _add_role(I18n.t("cr.project_manager"))
        _add_role(I18n.t("cr.scrum_master"))
        _add_role(I18n.t("cr.schedule_optimizer"))
        _add_role(I18n.t("cr.morale_officer"))
        _entries.append({ "role": "", "name": "" })

        # --- SPECIAL THANKS ---
        _entries.append({ "role": I18n.t("cr.thanks"), "name": "" })
        _entries.append({ "role": "", "name": "" })
        _add_role(I18n.t("cr.thanks_1"))
        _add_role(I18n.t("cr.thanks_2"))
        _add_role(I18n.t("cr.thanks_3"))
        _add_role(I18n.t("cr.thanks_4"))
        _add_role(I18n.t("cr.thanks_5"))
        _add_role(I18n.t("cr.thanks_6"))
        _entries.append({ "role": "", "name": "" })

        # --- TOOLS & TECHNOLOGIES ---
        _entries.append({ "role": I18n.t("cr.tools"), "name": "" })
        _entries.append({ "role": "", "name": "" })
        _entries.append({ "role": "SFML",       "name": "Simple and Fast Multimedia Library" })
        _entries.append({ "role": "CMake",      "name": I18n.t("cr.tool_build") })
        _entries.append({ "role": "Z-AI SDK",   "name": I18n.t("cr.tool_ai") })
        _entries.append({ "role": "Git",        "name": I18n.t("cr.tool_vcs") })
        _entries.append({ "role": "Pillow",     "name": I18n.t("cr.tool_python") })
        _entries.append({ "role": "", "name": "" })

        # --- PUBLISHER ---
        _entries.append({ "role": I18n.t("cr.published_by"), "name": "" })
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
        # --- Background (cover-fit come HallOfFameScreen/MainMenu) ---
        if _bg_texture:
                var tex_size: Vector2 = _bg_texture.get_size()
                var scale_val: float = max(size.x / tex_size.x, size.y / tex_size.y)
                var draw_size: Vector2 = tex_size * scale_val
                var draw_pos: Vector2 = (size - draw_size) / 2.0
                draw_texture_rect(_bg_texture, Rect2(draw_pos, draw_size), false)
                # Overlay scuro per la leggibilità del testo che scorre
                # (stesso trattamento della Hall of Fame: 0.45).
                draw_rect(Rect2(0, 0, size.x, size.y), Color(0.0, 0.0, 0.0, 0.45), true)
        else:
                # Fallback: solid background
                draw_rect(Rect2(0, 0, size.x, size.y), color_bg)
        # FIX (schermata nera dai credits): se il tema non fornisce un font di
        # default (get_theme_default_font() puo' tornare null), usa il font di
        # fallback del ThemeDB: senza font ogni draw_string e' un no-op e la
        # schermata resta NERA anche se il resto funziona.
        var font := get_theme_default_font()
        if font == null:
                font = ThemeDB.fallback_font
        # TASK 78: font medievale Goth And Gothic per i TITOLI DI SEZIONE
        # (e "Thank you"); ruoli e nomi restano col font leggibile di default.
        var gf: FontFile = GameConstants.gothic_font()
        var section_font: Font = gf if gf != null else font
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
                                        # Section header (e.g. "PROGRAMMING") — TASK 78:
                                        # font medievale Goth And Gothic in oro.
                                        _draw_outlined_string(section_font, Vector2(cx, y), role,
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
                _draw_outlined_string(section_font, Vector2(cx, size.y / 2.0 - 20.0),
                        I18n.t("cr.thank_you"), 40, thank_col, true)
                _draw_plain_string(font, Vector2(cx, size.y / 2.0 + 60.0),
                        "Marled Software", 24, color_publisher, true)
                _draw_plain_string(font, Vector2(cx, size.y - 40.0),
                        I18n.t("cr.press_esc"), 16, color_hint, true)


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
