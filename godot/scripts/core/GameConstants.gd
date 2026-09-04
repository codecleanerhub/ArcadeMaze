## GameConstants.gd - Centralized constants, enums and helpers for Arcade Maze Fantasy.
##
## This is a plain GDScript file (registered with `class_name GameConstants`)
## that acts as a static lookup table for everything shared between the
## GameManager, Maze, Player, Enemy, Boss and UI scripts.
##
## It is the Godot equivalent of the C++ headers Utils.h, Player.h (enums),
## Boss.h (enums + level math), Enemy.h (enums), MiniBoss.h (enums) and
## Weapon.h (enums), all collapsed into a single, importable file.
##
## Usage:
##   extends Node2D
##   const C = preload("res://scripts/core/GameConstants.gd")
##   func _ready():
##       print(C.MAZE_COLS)                      # -> 21
##       var t = C.WeaponType.WPN_PISTOL          # enum access
##       var is_boss = C.is_boss_level(4)         # -> true
class_name GameConstants

# ============================================================================
# 1. WINDOW / GRID DIMENSIONS  (from Utils.h)
# ============================================================================
# The logical window is square 1024x1024. The maze occupies a 21x19 grid of
# 48px tiles. 21*48 = 1008 (<=1024) and 19*48 = 912 (<= 1024-80). The 80px UI
# bar sits at the top.
const WINDOW_WIDTH: int = 1024
const WINDOW_HEIGHT: int = 1024
const TILE_SIZE: int = 48
const MAZE_COLS: int = 21
const MAZE_ROWS: int = 19
const UI_HEIGHT: int = 80

# ============================================================================
# 2. LEVEL STRUCTURE  (from Boss.h)
# ============================================================================
# Story mode is structured as: 3 maze levels + 1 boss level = 4 levels per
# boss. With 17 unique bosses, STORY_LEVELS_COUNT = 17 * 4 = 68. Bosses
# appear at levels 4, 8, 12, ..., 68. In infinite mode the level counter
# keeps growing past 68 and boss types cycle.
const BOSS_TYPE_COUNT: int = 17
const MAZE_LEVELS_PER_BOSS: int = 3
const TOTAL_LEVELS_PER_BOSS: int = MAZE_LEVELS_PER_BOSS + 1  # 4
const STORY_LEVELS_COUNT: int = BOSS_TYPE_COUNT * TOTAL_LEVELS_PER_BOSS  # 68

# Mini-boss types: 51 unique (one per maze level of the story mode).
const MINIBOSS_TYPE_COUNT: int = 51

# Player characters selectable from the menu.
const CHARACTER_TYPE_COUNT: int = 8

# Enemy types (15 original + 13 from the fantasy-horror bestiary).
const ENEMY_TYPE_COUNT: int = 28

# ============================================================================
# 3. ENUMS  (mirrors the C++ enums exactly)
# ============================================================================

## Game states (from Game.h). Order matters because the values are used as
## symbolic constants; do not reorder without auditing all consumers.
enum GameState {
	MENU,  ## Main menu (also chooses 1/2 players)
	SELECT_PLAYER,  ## Character selection (cycles 8 characters)
	CONFIG_JOY,  ## Joystick configuration - player 1 (2 steps)
	CONFIG_JOY_2,  ## Joystick configuration - player 2 (2 steps)
	INTRO,  ## Comic intro cutscene (4 images, 8s each)
	PLAYING,  ## Maze exploration (collect treasures + enemies)
	BOSS,  ## Boss fight
	PAUSE,  ## Pause (P key): blinking "PAUSE" overlay
	CONTINUES,  ## Continues screen (countdown 10-0)
	LOSE,  ## Game over screen
	WIN_STORY,  ## Story mode victory (fireworks)
	WIN_INFINITE,  ## Infinite mode victory (placeholder)
	CREDITS,  ## Scrolling credits screen
	DEMO,  ## Automatic demo mode (AI controls P1 and P2)
}

## Game modes (from Game.h).
enum GameMode {
	STORY,  ## 68 hand-crafted levels ending with WIN_STORY.
	INFINITE,  ## Endless mode: levels keep counting past 68.
}

## Cell types inside the maze grid (from Maze.h).
enum CellType {
	EMPTY,  ## Walkable floor
	WALL,  ## Blocks movement and projectiles
	TREASURE,  ## Collectible that activates the boss door
	WEAPON,  ## Random weapon pickup
}

## Treasure sub-types (from Maze.h) - purely cosmetic, all worth 10000 points.
enum TreasureType {
	CROWN,
	GOLD,
	CHEST,
	GEM,
	CUP,
}

## Playable characters (from Player.h). Order must match the C++ enum.
enum CharacterType {
	HERO_M,  ## Male hero (original player1)
	HERO_F,  ## Female heroine (original player2)
	MAGE,  ## Wizard (cloak, pointy hat, staff)
	ORC,  ## Green orc (fangs, muscular)
	ELF,  ## Blond elf (pointed ears, bow)
	KNIGHT,  ## Armored knight (helmet, sword)
	GOLEM,  ## Grey rock golem (glowing eyes)
	DRAGON,  ## Dragon-man (red scales, wings, tail)
	VAMPIRE,  ## Vampire (black cloak, pale skin, fangs)
}

## Boss types (from Boss.h). 17 total, one per boss level.
enum BossType {
	# --- 10 original types (boss_001..boss_010) ---
	GOLEM,
	LICH,
	DEMON,
	SPIDER,
	ABOMINATION,
	KRAKEN,
	DRAGON,
	WRAITH_LORD,
	VAMPIRE,
	BEHOLDER,
	# --- 7 new types from the bestiary (boss_021, 023..028) ---
	GHOUL_LORD,  # boss_021
	SPECTRAL_ALPHA,  # boss_023
	CULT_HERALD,  # boss_024
	COLOSSAL_MIMIC,  # boss_025
	RAT_KING,  # boss_026
	SUPREME_WITCH,  # boss_027
	TWILIGHT_KNIGHT,  # boss_028
}

## Mini-boss types (from MiniBoss.h). 51 total, one per maze level of story.
enum MiniBossType {
	# --- LOTR + D&D (17 original, maze levels 1-17) ---
	GOBLIN_CHIEFTAIN,
	CAVE_TROLL,
	ORC_BERSERKER,
	WARG_RIDER,
	URUK_HAI,
	NAZGUL,
	OGRE_BRUTE,
	GNOLL_PACKLORD,
	BUGBEAR_CHIEF,
	MINOTAUR,
	WIGHT_LORD,
	CAVE_GIANT,
	DEATH_KNIGHT,
	ILLITHID,
	ETTIN,
	FOMORIAN,
	BALROG_CULTIST,
	# --- Narnia (7, maze levels 18-24) ---
	FENRIS_WOLF,
	WHITE_WITCH_GUARD,
	NARNIA_MINOTAUR,
	DWARF_BERSERKER,
	WITCH_KNIGHT,
	TALKING_BEAST,
	ICE_GIANT_NARNIA,
	# --- The Witcher (10, maze levels 25-34) ---
	LESHEN,
	BRUXA,
	KATAKAN,
	FIEND,
	WITCHER_GOLEM,
	NOONWRAITH,
	FOGLET,
	GRAVE_HAG,
	MANTICORE_WITCHER,
	CYCLOPS_WITCHER,
	# --- Doom (10, maze levels 35-44) ---
	DOOM_IMP,
	PINKY_DEMON,
	REVENANT,
	CACODEMON,
	HELL_KNIGHT,
	MANCUBUS,
	ARCHVILE,
	BARON_OF_HELL,
	PAIN_ELEMENTAL,
	DOOM_CYBERDEMON,
	# --- Hybrid / extra fantasy (7, maze levels 45-51) ---
	SHADOW_ASSASSIN,
	CRYSTAL_GOLEM,
	VOID_WALKER,
	BLOOD_ELEMENTAL,
	STORM_TITAN,
	PLAGUE_LORD,
	VOID_SERPENT,
}

## Mini-boss melee weapon (from MiniBoss.h). Determines animation + damage.
enum MiniBossWeapon {
	AXE,  # slashing, medium damage
	MACE,  # blunt, high damage
	SWORD,  # slashing, medium-high damage
	DAGGER,  # slashing, low damage but fast
	CHAIN,  # blunt, high damage, long reach
	CLUB,  # blunt, very high damage
	WHIP,  # slashing, very long reach
	TENTACLES,  # medium damage, mind effect
}

## Enemy types (from Enemy.h). 28 total. Order matches the C++ enum.
enum EnemyType {
	# --- 15 original ---
	ZOMBIE,
	SKELETON,
	GHOST,
	BAT,
	SPIDER,
	SLIME,
	DEMON,
	ROBOT,
	GOBLIN,
	ORC,
	WRAITH,
	GHOUL,
	IMP,
	RAT,
	CULTIST,
	# --- 13 from the bestiary ---
	MIMIC,  # monster_005 - living chest
	WOLF,  # monster_003 - spectral wolf
	WITCH,  # monster_007 - swamp witch
	BONE_GOLEM,  # monster_010 - bone golem
	ASH_SERPENT,  # monster_011 - ash serpent
	DAMNED_KNIGHT,  # monster_012 - damned knight
	MAD_WIZARD,  # monster_013 - mad wizard
	DEMONIC_CROW,  # monster_015 - demonic crow
	TENTACLE,  # monster_016 - underground tentacle
	GARGOYLE,  # monster_017 - vigilant gargoyle
	WELL_SPIRIT,  # monster_018 - well spirit
	CURSED_BOAR,  # monster_019 - cursed boar
	PREDATOR_FUNGUS,  # monster_020 - predator fungus
}

## Player weapon types (from Weapon.h). Order is meaningful: used as index
## in rendering/audio switch statements.
enum WeaponType {
	PISTOL,
	SHOTGUN,
	ROCKET,
	LASER,
}

## Boss projectile kinds (from Weapon.h). Visual + behavior variant for
## boss projectiles.
enum BossProjKind {
	NORMAL,
	BOULDER,
	NECRO_BOLT,
	FIREBALL,
	WEBSHOT,
	FLESH_CHUNK,
	INK_SPRAY,
	DRAGON_BREATH,
	GHOST_BOLT,
	BLOOD_BOLT,
	EYE_RAY,
	GHOUL_CLAW,
	SPECTRAL_FANG,
	CULT_ORB,
	MIMIC_GOO,
	RAT_SWARM,
	WITCH_HEX,
	TWILIGHT_BLADE,
}

## Particle shape type (from Utils.h). 0=circle, 1=triangle flame, 2=square.
enum ParticleType {
	CIRCLE,
	FLAME,
	SQUARE,
}

# ============================================================================
# 4. 16-COLOR PALETTE
# ============================================================================
# A small, fixed palette of 16 colors used throughout the game for UI,
# particle effects, treasure colors, mini-boss overlays, etc. Each entry is
# a Godot Color (linear RGB, 0-1 range). The values mirror the spirit of
# the colors referenced in the C++ source (gold 220/160/40, red 200/80/80,
# ash white 240/240/240, etc.).
const PALETTE: Array[Color] = [
	Color(0.0, 0.0, 0.0, 1.0),  # 0  BLACK
	Color(1.0, 1.0, 1.0, 1.0),  # 1  WHITE
	Color(0.86, 0.63, 0.16, 1.0),  # 2  GOLD      (220,160,40)
	Color(0.78, 0.31, 0.31, 1.0),  # 3  RED       (200,80,80)
	Color(0.94, 0.94, 0.94, 1.0),  # 4  ASH WHITE (240,240,240)
	Color(0.30, 0.30, 0.36, 1.0),  # 5  DARK GREY
	Color(0.55, 0.55, 0.55, 1.0),  # 6  MID GREY
	Color(0.80, 0.80, 0.80, 1.0),  # 7  LIGHT GREY
	Color(0.31, 0.78, 1.0, 1.0),  # 8  CYAN (LASER)
	Color(0.20, 0.78, 0.30, 1.0),  # 9  GREEN (swamp)
	Color(0.55, 0.30, 0.78, 1.0),  # 10 PURPLE (necrotic)
	Color(0.78, 0.31, 0.16, 1.0),  # 11 ORANGE (fire)
	Color(0.16, 0.31, 0.55, 1.0),  # 12 NAVY BLUE (dungeon)
	Color(0.55, 0.16, 0.31, 1.0),  # 13 CRIMSON (blood)
	Color(0.94, 0.86, 0.31, 1.0),  # 14 SAND / BONE
	Color(0.18, 0.55, 0.55, 1.0),  # 15 TEAL (abyss)
]

# Convenience names for the palette indices above (mirrors a typical 16-color
# EGA / fantasy palette). Useful when the caller wants a readable alias.
const PAL_BLACK := 0
const PAL_WHITE := 1
const PAL_GOLD := 2
const PAL_RED := 3
const PAL_ASH := 4
const PAL_DARK_GREY := 5
const PAL_MID_GREY := 6
const PAL_LIGHT_GREY := 7
const PAL_CYAN := 8
const PAL_GREEN := 9
const PAL_PURPLE := 10
const PAL_ORANGE := 11
const PAL_NAVY := 12
const PAL_CRIMSON := 13
const PAL_SAND := 14
const PAL_TEAL := 15

# ============================================================================
# 5. LEVEL-STRUCTURE HELPERS  (mirrors the inline functions in Boss.h)
# ============================================================================


## Returns true if `level` (1-based) is a boss level (multiple of 4).
static func is_boss_level(level: int) -> bool:
	return (level % TOTAL_LEVELS_PER_BOSS) == 0


## Returns the boss index (0..16) for a given level. In infinite mode the
## boss type cycles every 17 bosses.
static func get_boss_index(level: int) -> int:
	return (level / TOTAL_LEVELS_PER_BOSS) % BOSS_TYPE_COUNT


## Returns the mini-boss index (0..50) for a given level. Boss levels do
## NOT spawn a mini-boss (only the 3 maze levels per boss do); in that case
## the function still returns a valid index for completeness.
static func get_miniboss_index(level: int) -> int:
	return (level - 1) % MINIBOSS_TYPE_COUNT


## Returns the maze sub-index within the current boss group (0..2).
## On boss levels this is meaningless and returns 0.
static func get_maze_sublevel(level: int) -> int:
	return (level - 1) % TOTAL_LEVELS_PER_BOSS


## Returns the palette index (0..7) for the given level. The 8 thematic
## palettes cycle: grey cavern -> blue dungeon -> purple crypt -> red rock
## -> bone ossuary -> green swamp -> red hell -> teal abyss.
static func get_palette_index(level: int) -> int:
	return (level - 1) % 8


# ============================================================================
# 6. CHARACTER HELPERS  (from Player.cpp getCharacterSpriteBase / getName)
# ============================================================================


## Maps a CharacterType to the base name used in the sprite files
## (e.g. CHAR_MAGE -> "char_mage"). Returns "" for HERO_M / HERO_F which
## use the legacy player1_sheet.png / player2_sheet.png files.
static func get_character_sprite_base(ct: int) -> String:
	match ct:
		CharacterType.HERO_M:
			return "player1"
		CharacterType.HERO_F:
			return "player2"
		CharacterType.MAGE:
			return "char_mage"
		CharacterType.ORC:
			return "char_orc"
		CharacterType.ELF:
			return "char_elf"
		CharacterType.KNIGHT:
			return "char_knight"
		CharacterType.GOLEM:
			return "char_golem"
		CharacterType.DRAGON:
			return "char_dragon"
		CharacterType.VAMPIRE:
			return "char_vampire"
		_:
			return ""


## Returns a human-readable name for the character (used by the UI).
static func get_character_name(ct: int) -> String:
	match ct:
		CharacterType.HERO_M:
			return "Hero"
		CharacterType.HERO_F:
			return "Heroine"
		CharacterType.MAGE:
			return "Mage"
		CharacterType.ORC:
			return "Orc"
		CharacterType.ELF:
			return "Elf"
		CharacterType.KNIGHT:
			return "Knight"
		CharacterType.GOLEM:
			return "Golem"
		CharacterType.DRAGON:
			return "Dragon Man"
		CharacterType.VAMPIRE:
			return "Vampire"
		_:
			return "Unknown"


## Returns the tint applied to P1 (white = no tint) or P2 (bluish) when
## they pick the same character.
static func get_player_tint(player_num: int) -> Color:
	if player_num == 2:
		# Bluish tint to distinguish P2 from P1 when same character.
		return Color(0.70, 0.80, 1.00, 1.0)
	return Color.WHITE


# ============================================================================
# 7. WEAPON FACTORY  (from Weapon.cpp)
# ============================================================================


## Inner dictionary representation of a weapon. We expose a static factory
## rather than a full class because the C++ Weapon struct is a pure value
## type with no behavior beyond the factory/render methods. Callers that
## need to mutate a weapon just modify the returned Dictionary.
##
## Returned Dictionary shape:
##   { "type": WeaponType.X, "power": int, "ammo": int }
static func make_weapon(type: int) -> Dictionary:
	match type:
		WeaponType.PISTOL:
			return {"type": type, "power": 1, "ammo": 15}
		WeaponType.SHOTGUN:
			return {"type": type, "power": 3, "ammo": 8}
		WeaponType.LASER:
			return {"type": type, "power": 2, "ammo": 20}
		WeaponType.ROCKET:
			return {"type": type, "power": 5, "ammo": 4}
		_:
			return {"type": WeaponType.PISTOL, "power": 1, "ammo": 15}


## Returns a random weapon Dictionary.
static func make_random_weapon() -> Dictionary:
	var t: int = randi() % 4
	return make_weapon(t)


## Returns the human-readable name of a weapon type.
static func get_weapon_name(type: int) -> String:
	match type:
		WeaponType.PISTOL:
			return "PISTOL"
		WeaponType.SHOTGUN:
			return "SHOTGUN"
		WeaponType.LASER:
			return "LASER"
		WeaponType.ROCKET:
			return "ROCKET"
		_:
			return "?"


## Returns the UI color associated with a weapon type.
static func get_weapon_color(type: int) -> Color:
	match type:
		WeaponType.PISTOL:
			return Color(0.78, 0.78, 0.20, 1.0)  # (200,200,50)
		WeaponType.SHOTGUN:
			return Color(0.78, 0.39, 0.20, 1.0)  # (200,100,50)
		WeaponType.LASER:
			return Color(0.31, 0.78, 1.00, 1.0)  # (80,200,255)
		WeaponType.ROCKET:
			return Color(0.78, 0.20, 0.20, 1.0)  # (200,50,50)
		_:
			return Color.WHITE
