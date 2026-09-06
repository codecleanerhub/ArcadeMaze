# ============================================================================
# ConfigManager.gd  (Autoload singleton -> name: ConfigManager)
#
# Godot port of:
#   - Utils.h  (struct Config)
#   - Utils.cpp (loadConfig / saveConfig)
#
# Persists keyboard + joystick configuration to <user_dir>/config.ini using
# the SAME INI schema as the original C++ game, so a config saved by the
# original SFML build is fully readable here (and vice-versa).
#
# INI format (one KEY=VALUE per line, comments start with '#' or '['):
#     KEY_UP=...
#     JOY_JUMP=...
#     JOY2_ID=...
#
# Notes:
#   * Godot Key codes differ from SFML Key codes. We keep using Godot's
#     KEY_* constants directly (the file just stores integers). A future
#     compatibility shim could remap legacy SFML values when loading.
#   * `joy_*_id` corresponds to Godot JoyDevice indexes (0-based, same as
#     SFML Joystick:: identification).
#   * joy_jump / joy_shoot == -1 means "not configured yet" (must be set
#     in the CONFIGURE JOYSTICK screen before playing with a pad).
# ============================================================================
extends Node

signal config_changed()

# --- Window / maze constants (mirrors Utils.h) -----------------------------
const WINDOW_WIDTH: int = 1024
const WINDOW_HEIGHT: int = 1024
const TILE_SIZE: int = 48
const MAZE_COLS: int = 21
const MAZE_ROWS: int = 19
const UI_HEIGHT: int = 80

# --- Game modes ------------------------------------------------------------
enum GameMode { STORY, INFINITE }

# --- Character types (mirrors CharacterType in Player.h) -------------------
enum CharacterType {
        HERO_M, HERO_F, MAGE, ORC, ELF, KNIGHT, GOLEM, DRAGON, VAMPIRE
}

# --- Weapon types (mirrors WeaponType in Weapon.h) ------------------------
enum WeaponType { PISTOL, SHOTGUN, ROCKET, LASER }

# Max ammo per weapon (used by HUD for normalisation, mirrors Weapon.cpp).
const MAX_AMMO_PER_TYPE: Dictionary = {
        WeaponType.PISTOL: 15,
        WeaponType.SHOTGUN: 8,
        WeaponType.LASER: 20,
        WeaponType.ROCKET: 4,
}
const AMMO_NORMALISER: int = 15  # Pistol's max, matches UI.cpp

# ----------------------------------------------------------------------------
# The Config struct (mirrors Utils.h `Config`).
# All public so callers can read/write freely; call save() to persist.
# ----------------------------------------------------------------------------
var config: Dictionary = {
        # --- Player 1 (keyboard) ---
        "KEY_UP":     KEY_UP,
        "KEY_DOWN":   KEY_DOWN,
        "KEY_LEFT":   KEY_LEFT,
        "KEY_RIGHT":  KEY_RIGHT,
        "KEY_JUMP":   KEY_SPACE,
        "KEY_SHOOT":  KEY_ALT,
        # --- Player 1 (joystick 0) ---
        "JOY_AXIS_X": 0,
        "JOY_AXIS_Y": 1,
        "JOY_JUMP":   -1,   # -1 = not configured
        "JOY_SHOOT":  -1,
        # --- Player 2 (secondary keyboard, fixed WASD + Q/E) ---
        "KEY2_UP":     KEY_W,
        "KEY2_DOWN":   KEY_S,
        "KEY2_LEFT":   KEY_A,
        "KEY2_RIGHT":  KEY_D,
        "KEY2_JUMP":   KEY_Q,
        "KEY2_SHOOT":  KEY_E,
        # --- Player 2 (joystick 1) ---
        "JOY2_ID":     1,
        "JOY2_AXIS_X": 0,
        "JOY2_AXIS_Y": 1,
        "JOY2_JUMP":   -1,
        "JOY2_SHOOT":  -1,
}

# Path to the config file (user://config.ini = OS-specific writable folder).
const CONFIG_PATH: String = "user://config.ini"

# Cached read-only view of the valid INI keys (used by save()).
const _INI_KEYS: Array = [
        "KEY_UP", "KEY_DOWN", "KEY_LEFT", "KEY_RIGHT", "KEY_JUMP", "KEY_SHOOT",
        "JOY_AXIS_X", "JOY_AXIS_Y", "JOY_JUMP", "JOY_SHOOT",
        "KEY2_UP", "KEY2_DOWN", "KEY2_LEFT", "KEY2_RIGHT", "KEY2_JUMP", "KEY2_SHOOT",
        "JOY2_ID", "JOY2_AXIS_X", "JOY2_AXIS_Y", "JOY2_JUMP", "JOY2_SHOOT",
]


# ============================================================================
# Lifecycle
# ============================================================================
func _ready() -> void:
        load_config()


# ============================================================================
# load_config: parse <user_dir>/config.ini into `config`.
#
# Rules (mirror loadConfig() in Utils.cpp):
#   * Empty lines, '#' comments and '[section]' lines are skipped.
#   * Format: KEY=VALUE (integer).
#   * Unknown keys are silently ignored.
#   * Missing/unparseable values fall back to the default already in `config`.
#   * If the file does not exist, defaults remain (no error).
# ============================================================================
func load_config() -> void:
        if not FileAccess.file_exists(CONFIG_PATH):
                return

        var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
        if f == null:
                push_warning("ConfigManager: cannot open %s for reading." % CONFIG_PATH)
                return

        while not f.eof_reached():
                var line: String = f.get_line().strip_edges()
                if line.is_empty() or line.begins_with("#") or line.begins_with("["):
                        continue
                var eq_pos: int = line.find("=")
                if eq_pos < 0:
                        continue
                var key: String = line.substr(0, eq_pos).strip_edges()
                var value_str: String = line.substr(eq_pos + 1).strip_edges()
                if not value_str.is_valid_int():
                        continue
                var value: int = int(value_str)
                if config.has(key):
                        config[key] = value
        f.close()
        config_changed.emit()


# ----------------------------------------------------------------------------
# save_config: write the current `config` to <user_dir>/config.ini.
# Called after the joystick configuration screens.
# ----------------------------------------------------------------------------
func save_config() -> void:
        var f := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
        if f == null:
                push_warning("ConfigManager: cannot open %s for writing." % CONFIG_PATH)
                return

        f.store_line("# ArcadeMazeFantasy - configurazione comandi")
        f.store_line("# Generato automaticamente dopo la configurazione joystick.")
        f.store_line("# Non modificare a mano: usa il menu CONFIGURE JOYSTICK del gioco.")
        f.store_line("")

        # Player 1 - keyboard
        f.store_line("KEY_UP=%d"     % config["KEY_UP"])
        f.store_line("KEY_DOWN=%d"   % config["KEY_DOWN"])
        f.store_line("KEY_LEFT=%d"   % config["KEY_LEFT"])
        f.store_line("KEY_RIGHT=%d"  % config["KEY_RIGHT"])
        f.store_line("KEY_JUMP=%d"   % config["KEY_JUMP"])
        f.store_line("KEY_SHOOT=%d"  % config["KEY_SHOOT"])
        # Player 1 - joystick
        f.store_line("JOY_AXIS_X=%d" % config["JOY_AXIS_X"])
        f.store_line("JOY_AXIS_Y=%d" % config["JOY_AXIS_Y"])
        f.store_line("JOY_JUMP=%d"   % config["JOY_JUMP"])
        f.store_line("JOY_SHOOT=%d"  % config["JOY_SHOOT"])
        # Player 2 - joystick
        f.store_line("JOY2_ID=%d"     % config["JOY2_ID"])
        f.store_line("JOY2_AXIS_X=%d" % config["JOY2_AXIS_X"])
        f.store_line("JOY2_AXIS_Y=%d" % config["JOY2_AXIS_Y"])
        f.store_line("JOY2_JUMP=%d"   % config["JOY2_JUMP"])
        f.store_line("JOY2_SHOOT=%d"  % config["JOY2_SHOOT"])
        f.close()
        config_changed.emit()


# ============================================================================
# Convenience getters (mirror Player.cpp accessors)
# ============================================================================

# Player 1 keyboard
func key_up()    -> int: return config["KEY_UP"]
func key_down()  -> int: return config["KEY_DOWN"]
func key_left()  -> int: return config["KEY_LEFT"]
func key_right() -> int: return config["KEY_RIGHT"]
func key_jump()  -> int: return config["KEY_JUMP"]
func key_shoot() -> int: return config["KEY_SHOOT"]

# Player 1 joystick
func joy_axis_x() -> int: return config["JOY_AXIS_X"]
func joy_axis_y() -> int: return config["JOY_AXIS_Y"]
func joy_jump()   -> int: return config["JOY_JUMP"]
func joy_shoot()  -> int: return config["JOY_SHOOT"]

# Player 2 keyboard (fixed WASD + Q/E)
func key2_up()    -> int: return config["KEY2_UP"]
func key2_down()  -> int: return config["KEY2_DOWN"]
func key2_left()  -> int: return config["KEY2_LEFT"]
func key2_right() -> int: return config["KEY2_RIGHT"]
func key2_jump()  -> int: return config["KEY2_JUMP"]
func key2_shoot() -> int: return config["KEY2_SHOOT"]

# Player 2 joystick
func joy2_id()     -> int: return config["JOY2_ID"]
func joy2_axis_x() -> int: return config["JOY2_AXIS_X"]
func joy2_axis_y() -> int: return config["JOY2_AXIS_Y"]
func joy2_jump()   -> int: return config["JOY2_JUMP"]
func joy2_shoot()  -> int: return config["JOY2_SHOOT"]


# ============================================================================
# Queries used by Game/UI
# ============================================================================

# Returns true iff player 1 has configured the two required joystick buttons.
func p1_joystick_ready() -> bool:
        return config["JOY_JUMP"] >= 0 and config["JOY_SHOOT"] >= 0

# Returns true iff player 2 has configured the two required joystick buttons.
func p2_joystick_ready() -> bool:
        return config["JOY2_JUMP"] >= 0 and config["JOY2_SHOOT"] >= 0


# ----------------------------------------------------------------------------
# Reset to factory defaults (used by an eventual "RESET CONFIG" menu item).
# ----------------------------------------------------------------------------
func reset_to_defaults() -> void:
        config.KEY_UP    = KEY_UP
        config.KEY_DOWN  = KEY_DOWN
        config.KEY_LEFT  = KEY_LEFT
        config.KEY_RIGHT = KEY_RIGHT
        config.KEY_JUMP  = KEY_SPACE
        config.KEY_SHOOT = KEY_ALT
        config.JOY_AXIS_X = 0
        config.JOY_AXIS_Y = 1
        config.JOY_JUMP   = -1
        config.JOY_SHOOT  = -1
        config.KEY2_UP    = KEY_W
        config.KEY2_DOWN  = KEY_S
        config.KEY2_LEFT  = KEY_A
        config.KEY2_RIGHT = KEY_D
        config.KEY2_JUMP  = KEY_Q
        config.KEY2_SHOOT = KEY_E
        config.JOY2_ID     = 1
        config.JOY2_AXIS_X = 0
        config.JOY2_AXIS_Y = 1
        config.JOY2_JUMP   = -1
        config.JOY2_SHOOT  = -1
        config_changed.emit()
