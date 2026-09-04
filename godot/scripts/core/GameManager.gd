## GameManager.gd - Autoload singleton that owns the global game state.
##
## Migrated from the C++ `Game` class (Game.h / Game.cpp). The C++ class was
## a monolith owning every subsystem (window, maze, players, enemies, boss,
## UI, audio). In Godot the scene tree replaces "ownership" of nodes - each
## scene owns its children. GameManager therefore keeps ONLY the
## bookkeeping that needs to be globally accessible:
##
##   * the current GameState and GameMode
##   * the current level number and number of players
##   * the per-player character selection
##   * the menu cursor, continues counter and pause state
##
## It exposes the same level-structure helpers as the C++ inline functions
## in Boss.h (is_boss_level / get_boss_index) so other scripts can ask
## "is this level a boss level?" without importing the constants file.
##
## Communication is via signals (state_changed, level_changed, ...) so UI
## and gameplay scenes can react without polling.
extends Node

# Import the shared constants file. `const C = ...` gives every consumer a
# short alias (C.MAZE_COLS, C.GameState.PLAYING, ...).
const C = preload("res://scripts/core/GameConstants.gd")

# ============================================================================
# SIGNALS
# ============================================================================
## Emitted whenever current_state changes. Payload is the new GameState int.
signal state_changed(new_state: int)
## Emitted when current_level changes (e.g. startLevel, boss fight, etc.).
signal level_changed(new_level: int)
## Emitted when the player count changes (1P <-> 2P from the menu).
signal num_players_changed(num_players: int)
## Emitted when the player's selected character changes (select-player screen).
signal character_changed(player_num: int, character_type: int)
## Emitted when the game mode changes (STORY <-> INFINITE).
signal game_mode_changed(mode: int)
## Emitted when the player loses the last life and the run ends.
signal run_ended
## Emitted when the player transitions from a maze level to a boss fight.
signal boss_fight_started(boss_index: int)
## Emitted when the player defeats a boss.
signal boss_defeated(boss_index: int)

# ============================================================================
# PUBLIC STATE  (read directly, mutate via the setters below so signals fire)
# ============================================================================
## Current top-level state. See GameState enum.
@export var current_state: int = C.GameState.MENU:
        set(v):
                if v != current_state:
                        current_state = v
                        state_changed.emit(v)

## The level we're playing right now. 1..STORY_LEVELS_COUNT in story mode,
## unbounded (>= 1) in infinite mode.
@export var current_level: int = 1:
        set(v):
                if v != current_level:
                        current_level = v
                        level_changed.emit(v)

## 1 or 2 players (selected from the main menu).
@export_range(1, 2) var num_players: int = 1:
        set(v):
                if v != num_players:
                        num_players = v
                        num_players_changed.emit(v)

## STORY or INFINITE.
@export var game_mode: int = C.GameMode.STORY:
        set(v):
                if v != game_mode:
                        game_mode = v
                        game_mode_changed.emit(v)

## Character chosen by P1 (one of CharacterType).
@export var player1_character: int = C.CharacterType.HERO_M:
        set(v):
                if v != player1_character:
                        player1_character = v
                        character_changed.emit(1, v)

## Character chosen by P2 (one of CharacterType).
@export var player2_character: int = C.CharacterType.HERO_F:
        set(v):
                if v != player2_character:
                        player2_character = v
                        character_changed.emit(2, v)

## Cursor position in the main menu (0..5 in the C++ game).
@export var menu_item_index: int = 0

## Step index of the joystick configuration screen (0 or 1 in C++).
@export var config_joy_step: int = 0

## Which player we are configuring in the joystick config screen (1 or 2).
@export var config_joy_player: int = 1

## State we were in before pausing (so we can restore it on resume).
@export var paused_from_state: int = C.GameState.PLAYING

## Continues remaining (max 3 in the C++ game). When the player runs out
## the LOSE screen is shown.
@export_range(0, 3) var continues_left: int = 3

## Countdown timer on the continues screen (10..0 seconds).
@export var continues_timer: int = 10

## Whether the player chose YES (true) or NO (false) on the continues screen.
@export var continues_choice: bool = true

## True if the player died during a boss fight (used by the C++ game to
## decide whether to keep the boss state on continue).
@export var died_in_boss: bool = false

## Music toggle (set from the main menu).
@export var music_enabled: bool = true

## True if the player picked up the test-mode shortcut (skip current level).
@export var test_mode_enabled: bool = false


# ============================================================================
# LEVEL HELPERS  (mirror the inline functions in Boss.h)
# ============================================================================
## True if `level` (1-based) is a boss level (multiples of 4: 4, 8, ..., 68).
func is_boss_level(level: int = current_level) -> bool:
        return C.is_boss_level(level)


## Returns the boss index (0..16) for the given level.
func get_boss_index(level: int = current_level) -> int:
        return C.get_boss_index(level)


## Returns the mini-boss index (0..50) for the given level. Boss levels do
## not spawn mini-bosses but the index is still well-defined.
func get_miniboss_index(level: int = current_level) -> int:
        return C.get_miniboss_index(level)


## True if we have completed every story-mode level (current_level > 68).
func is_story_complete() -> bool:
        return current_level > C.STORY_LEVELS_COUNT


# ============================================================================
# STATE TRANSITIONS  (named after the C++ methods that performed them)
# ============================================================================
## Begin a new maze level. Mirrors Game::startLevel(lvl). Emits level_changed
## and switches the state to PLAYING.
func start_level(lvl: int) -> void:
        current_level = lvl
        current_state = C.GameState.PLAYING
        # Transition to the main game scene (maze level).
        go_to_maze()


## Begin the boss fight for the current level. Mirrors Game::startBossFight().
## `keep_boss_state` matches the C++ argument of the same name and is used
## when continuing after death in the boss room.
func start_boss_fight(keep_boss_state: bool = false) -> void:
        var boss_idx: int = get_boss_index()
        if not keep_boss_state:
                boss_fight_started.emit(boss_idx)
        current_state = C.GameState.BOSS
        # Transition to the boss room scene.
        go_to_boss()


## Advance to the next level after the current one is cleared. If we are in
## story mode and just finished level 68, switch to WIN_STORY.
func advance_level() -> void:
        if game_mode == C.GameMode.STORY and current_level >= C.STORY_LEVELS_COUNT:
                current_state = C.GameState.WIN_STORY
                run_ended.emit()
                go_to_win()
                return
        if game_mode == C.GameMode.STORY and is_boss_level():
                # Defeated a boss - reward the player with an extra life (in C++
                # this is `player.addLife()` which is the Player node's job).
                boss_defeated.emit(get_boss_index())
        current_level += 1
        start_level(current_level)


## Toggle pause. Mirrors the C++ behavior: P toggles between PLAYING/BOSS
## and PAUSE, storing the previous state in paused_from_state.
func toggle_pause() -> void:
        if current_state == C.GameState.PAUSE:
                current_state = paused_from_state
        elif current_state == C.GameState.PLAYING or current_state == C.GameState.BOSS:
                paused_from_state = current_state
                current_state = C.GameState.PAUSE


## Lose a life. If we still have continues we go to CONTINUES, otherwise LOSE.
## `in_boss` is the C++ `diedInBoss` flag - true if the death happened during
## a boss fight (so we keep the boss state on continue).
func player_died(in_boss: bool = false) -> void:
        died_in_boss = in_boss
        if continues_left > 0:
                current_state = C.GameState.CONTINUES
                go_to_continues()
        else:
                current_state = C.GameState.LOSE
                run_ended.emit()
                go_to_lose()


## Called by the continues screen when the player picks YES: consume a
## continue credit and resume the game (boss fight if died there, else
## restart the current level).
func use_continue() -> void:
        continues_left = max(0, continues_left - 1)
        if died_in_boss:
                start_boss_fight(true)
        else:
                start_level(current_level)


## Called by the continues screen when the player picks NO: go to LOSE.
func give_up() -> void:
        current_state = C.GameState.LOSE
        run_ended.emit()
        go_to_lose()


## Reset all transient state so a new run can start from a clean slate.
## Mirrors Game::cleanupGameEntities() for the state-only portion.
func reset_run() -> void:
        current_level = 1
        continues_left = 3
        continues_timer = 10
        continues_choice = true
        died_in_boss = false
        menu_item_index = 0
        config_joy_step = 0
        config_joy_player = 1
        test_mode_enabled = false
        current_state = C.GameState.MENU


# ============================================================================
# LIFE-CYCLE
# ============================================================================
func _ready() -> void:
        # Enforce a deterministic initial state on autoload.
        reset_run()
        # When the game starts on a fresh load we want to be in MENU (already
        # set by reset_run), and the player count is whatever the C++ default was.
        player1_character = C.CharacterType.HERO_M
        player2_character = C.CharacterType.HERO_F


# ============================================================================
# DEBUG HELPERS
# ============================================================================
## Returns a readable name for a GameState. Handy for debug prints and UI.
func state_name(state: int = current_state) -> String:
        match state:
                C.GameState.MENU:
                        return "MENU"
                C.GameState.SELECT_PLAYER:
                        return "SELECT_PLAYER"
                C.GameState.CONFIG_JOY:
                        return "CONFIG_JOY"
                C.GameState.CONFIG_JOY_2:
                        return "CONFIG_JOY_2"
                C.GameState.INTRO:
                        return "INTRO"
                C.GameState.PLAYING:
                        return "PLAYING"
                C.GameState.BOSS:
                        return "BOSS"
                C.GameState.PAUSE:
                        return "PAUSE"
                C.GameState.CONTINUES:
                        return "CONTINUES"
                C.GameState.LOSE:
                        return "LOSE"
                C.GameState.WIN_STORY:
                        return "WIN_STORY"
                C.GameState.WIN_INFINITE:
                        return "WIN_INFINITE"
                C.GameState.CREDITS:
                        return "CREDITS"
                C.GameState.DEMO:
                        return "DEMO"
                _:
                        return "UNKNOWN(%d)" % state


# ============================================================================
# SCENE TRANSITIONS
# ============================================================================

func change_scene(scene_path: String) -> void:
        var err := get_tree().change_scene_to_file(scene_path)
        if err != OK:
                push_error("Errore caricamento scena: " + scene_path)

func go_to_menu() -> void:
        current_state = C.GameState.MENU
        change_scene("res://scenes/MainMenu.tscn")

func go_to_select_player() -> void:
        current_state = C.GameState.SELECT_PLAYER
        change_scene("res://scenes/SelectPlayer.tscn")

func go_to_config_joy() -> void:
        current_state = C.GameState.CONFIG_JOY
        change_scene("res://scenes/ConfigJoy.tscn")

func go_to_intro() -> void:
        current_state = C.GameState.INTRO
        change_scene("res://scenes/IntroCutscene.tscn")

func go_to_maze() -> void:
        current_state = C.GameState.PLAYING
        change_scene("res://scenes/MainGame.tscn")

func go_to_boss() -> void:
        current_state = C.GameState.BOSS
        change_scene("res://scenes/BossRoom.tscn")

func go_to_credits() -> void:
        current_state = C.GameState.CREDITS
        change_scene("res://scenes/CreditsScreen.tscn")

func go_to_continues() -> void:
        current_state = C.GameState.CONTINUES
        change_scene("res://scenes/ContinuesScreen.tscn")

func go_to_win() -> void:
        current_state = C.GameState.WIN_STORY
        change_scene("res://scenes/WinScreen.tscn")

func go_to_lose() -> void:
        current_state = C.GameState.LOSE
        change_scene("res://scenes/LoseScreen.tscn")

func start_level_at(level: int) -> void:
        current_level = level
        if is_boss_level(level):
                go_to_boss()
        else:
                go_to_maze()

func next_level() -> void:
        current_level += 1
        if current_level > C.STORY_LEVELS_COUNT:
                # Vittoria: mostra credits
                go_to_credits()
        else:
                start_level_at(current_level)
