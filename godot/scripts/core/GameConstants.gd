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
# 0. TASK 22 — POTENZIAMENTO GRAFICO XHD (facilmente reversibile)
# ============================================================================
# Tre interruttori indipendenti. Per tornare AL 100% alla grafica precedente
# basta mettere uno (o tutti) a `false`: i file originali non sono mai stati
# toccati, gli sheet XHD vivono in `assets/sprites/xhd/` e ogni loader ha
# il fallback identico al codice legacy. (In alternativa: git revert del
# singolo commit del Task 22.)
#   SPRITE_XHD_ENABLED     -> player + ruota selezione + boss usano gli sheet
#                             4x (256px/frame) generati deterministicamente
#                             dagli originali (stessa palette, stessa silhouette).
#   BOSS_LIMB_ANIM_ENABLED -> animazioni procedurali del mesh del boss
#                             (tentacoli/braccia/ali/volo, vedi DeformableSprite).
#   BOSS_PROJ_THEMED_ENABLED -> proiettili boss con FORME tematiche distinte
#                             (roccia/skull/ragnatela/globo di cristallo...).
static var SPRITE_XHD_ENABLED: bool = true
static var BOSS_LIMB_ANIM_ENABLED: bool = true
static var BOSS_PROJ_THEMED_ENABLED: bool = true

# ============================================================================
# 0b. TASK 25 — VISIBILITÀ ANIMAZIONI BOSS + OUTFIT ARMATURE
# ============================================================================
#   BOSS_LIMB_ANIM_GAIN -> moltiplicatore delle ampiezze degli arti procedurali
#                          (tentacoli/braccia/ali/vesto'). Il Task 22 le aveva
#                          calibrate SUBTLE (~2-4% del lato dello sprite) e a
#                          schermo risultavano impercettibili (segnalazione
#                          utente: "non vedo animazioni nei boss"). 2.6 (Task 25)
#                          portava lo spostamento al 6-13% del lato: VISO a
#                          schermo ma STRAPPAVA la mesh (smearing/doppie
#                          immagini: "grafica glitchata/confusa", Task 28).
#                          TASK 28: 1.15 = movimento chiaramente visibile (~4%
#                          del lato) SENZA lacerazioni; DeformableSprite
#                          clampa comunque ogni offset a MAX_LIMB_OFFSET_UNITS
#                          (rete di sicurezza anti-glitch per qualunque gain).
#                          1.0 = identico al Task 22 (rollback immediato).
#                          I boss fluttuanti (LP_HOVER) ricevono ANCHE il bob
#                          di nodo (Boss.update_step): animazione pulita.
#   ARMOR_OUTFIT_ENABLED -> le armature reliquia RICOLORANO il vestiario del
#                          player (shader armor_outfit: hue del vestito ->
#                          colore dell'armatura + tinta metallo + rim) oltre
#                          all'aura procedurale esistente.
static var BOSS_LIMB_ANIM_GAIN: float = 1.15
static var ARMOR_OUTFIT_ENABLED: bool = true

# ============================================================================
# 0c. TASK 26 — ENHANCEMENT CANVAS DEI BOSS
# ============================================================================
#   BOSS_CANVAS_SHADER_ENABLED -> i boss ricevono lo shader enhancement
#                          (boss_deform.gdshader) DIRETTAMENTE sul loro
#                          DeformableSprite: sharpening + contrasto 1.2 +
#                          saturazione 1.3 + fake-normal + rim, cioè la STESSA
#                          pipeline dei player (CharacterArt._enhanced_strong).
#                          Prima lo shader era applicato al nodo Boss ma i
#                          materiali CanvasItem NON si propagano ai figli: il
#                          mesh renderizzava col solo StandardMaterial3D ->
#                          boss visivamente spenti/sbiaditi rispetto a player
#                          e nemici (segnalazione utente). false = rendering
#                          identico al pre-Task-26.
static var BOSS_CANVAS_SHADER_ENABLED: bool = true

# ============================================================================
# 0d. TASK 44 — LINGUA UI (INGLESE / ITALIANO)
# ============================================================================
# Mirror STATICO della lingua selezionata nel menu OPTIONS -> LANGUAGE.
# L'autoload I18nManager ne è l'unico SCRITTORE (lo sincronizza al boot da
# ConfigManager e a ogni cambio); GameConstants è accessibile anche da
# funzioni static (Boss.get_boss_name, get_weapon_name...) dove gli
# autoload NON sono risolvibili (verificato: "Identifier not found").
#   0 = ENGLISH (default), 1 = ITALIANO.
static var ui_language: int = 0

## Scorciatoia statica: true se la UI è in italiano.
static func ui_is_italian() -> bool:
        return ui_language == 1

#   BOSS_SHOOT_SFX_ENABLED -> SFX procedurali di sparo dei boss, UNO per tipo
#                          di "munizione" (masso=tonfo di pietra, ragnatela=
#                          fruscio di seta, fiamma=soffio, raggio=zap...):
#                          AudioManager.play_boss_shoot(kind) chiamato da
#                          Boss._shoot_pattern. false = nessun suono di sparo
#                          (comportamento pre-Task-26).
static var BOSS_SHOOT_SFX_ENABLED: bool = true

## TASK 46 — ANIMAZIONE A FRAME REALI DEI BOSS
#   BOSS_FRAME_ANIM_ENABLED -> i boss ciclando i frame reali dello sheet
#                          (XHD/SD) in base allo stato: IDLE 5.5 FPS, WALK
#                          8.3 FPS, ATTACK one-shot 11 FPS sincronizzato col
#                          timer d'attacco (rate = frameDuration legacy dei
#                          meta). Prima il percorso DeformableSprite mostrava
#                          SOLO il frame 0: i boss erano statue che si
#                          muovevano solo via deformazione procedurale
#                          della mesh. Il GOLEM (boss_031) ora usa il ciclo
#                          walk a 6 frame rigenerato con PixelLab (256px);
#                          gli altri 16 boss tornano ad animare i propri cicli
#                          legacy a 4 frame. false = frame 0 statico (rollback
#                          al comportamento pre-Task-46).
static var BOSS_FRAME_ANIM_ENABLED: bool = true

## TASK 49 — SINCRONIZZAZIONE ATTACCO (wind-up -> lancio)
#   BOSS_ATTACK_SYNC_ENABLED -> il proiettile e il SFX di sparo partono al
#                          frame di RILASCIO dell'animazione d'attacco invece
#                          che al primo frame: prima il colpo usciva mentre il
#                          boss era ancora in posa di carica (per il Mimico
#                          Colossale la bocca era ancora chiusa!), con posa e
#                          proiettile/suono distanziati di ~270ms. Ora la posa
#                          di lancio, il proiettile e il suono appaiono nello
#                          STESSO frame. Il delay di 280ms = frame 3 @ 11 FPS
#                          (11 FPS = rate ATTACK del cycling frame): e' il
#                          frame di rilascio verificato via VLM per Mimico
#                          (bocca spalancata) e Golem (impatto dello smash).
#                          false = sparo immediato al frame 0 (rollback al
#                          comportamento pre-Task-49).
static var BOSS_ATTACK_SYNC_ENABLED: bool = true

## Delay (ms) tra l'inizio della posa d'attacco e lo sparo effettivo.
const BOSS_ATTACK_WINDUP_MS: int = 280

## Frame size (px) degli sheet XHD (4x del 64 originale).
const SPRITE_XHD_FRAME_PX: int = 256

## Percorso dello sheet XHD per id sprite (es. "player1", "boss_031",
## "char_knight_walk2"). Ritorna null se l'id non ha senso.
static func xhd_sheet_path(id: String) -> String:
        return "res://assets/sprites/xhd/" + id + "_xhd_sheet.png"

# ============================================================================
# 1. WINDOW / GRID DIMENSIONS  (from Utils.h)
# ============================================================================
# FIX (labirinto esteso a tutto schermo): design space portato a 1920x1080
# (16:9) per corrispondere al viewport di project.godot. Maze esteso a
# 40 colonne x 20 righe (= 1920x960 px) con UI bar di 80px sopra.
# TILE_SIZE resta 48px (compatibile con tutti gli sprite 64x64 scalati a 40
# per i nemici, e con il rendering procedurale del maze).
# FIX (doppio muro in basso): MAZE_ROWS aumentato da 20 a 22 per riempire
# meglio l'altezza del viewport 1080px. 22*48=1056 + 80 UI = 1136 (56px
# overflow coperti dal floor gradient). Il "doppio muro" che l'utente vedeva
# era causato dal bordo inferiore del maze (riga 20 = WALL) + 40px di sfondo
# scuro tra il maze e il bordo dello schermo.
const WINDOW_WIDTH: int = 1920
const WINDOW_HEIGHT: int = 1080
const TILE_SIZE: int = 64
# FIX (muro destro invisibile + doppio muro): 30 colonne. Con 31 (dispari)
# il muro di bordo (col 30, x 1920..1984) finiva FUORI SCHERMO: i corridoi
# della col 29 arrivavano al bordo video senza alcun muro visibile.
# Con 30 colonne (30*64=1920 esatto) il bordo destro (col 29) è l'ultima
# colonna VISIBILE su schermo. La DFS con passo 2 non scava mai la colonna
# 28 (pari, senza stanze a col 29): Maze.generate la apre selettivamente
# dove la colonna 27 è aperta, così il lato destro ha un muro di bordo
# SINGOLO visibile senza il doppio muro 128px di prima (comportamento del
# C++ originale 21x19, entrambi dispari).
const MAZE_COLS: int = 30
const MAZE_ROWS: int = 15
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

# Enemy types (15 original + 13 from the fantasy-horror bestiary + 16 new
# types unlocked one per defeated boss, see Enemy.gd).
# FIX (nemico +1 dopo ogni boss): 28 -> 44 (gli ultimi 16 sono OWLBEAR..
# POSSESSED_SOLDIER, sbloccati progressivamente dopo ogni boss).
const ENEMY_TYPE_COUNT: int = 44

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
        SIEGE,  # TASK 39 — Cannone d'Assedio: arma ESCLUSIVA della boss room
                # (non spawna mai nel labirinto, non e' nelle armi a terra
                # casuali: la genera solo BossRoomController dal pickup
                # dedicato). Potenza 5 flat + %HP del boss, 4 colpi.
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
## TASK 44: localizzato (EN default / IT) tramite il mirror statico
## ui_language (i nomi brevi della ruota sono in I18nManager: char.hero...).
static func get_character_name(ct: int) -> String:
        var it: bool = ui_is_italian()
        match ct:
                CharacterType.HERO_M:
                        return "Eroe" if it else "Hero"
                CharacterType.HERO_F:
                        return "Eroina" if it else "Heroine"
                CharacterType.MAGE:
                        return "Mago" if it else "Mage"
                CharacterType.ORC:
                        return "Orco" if it else "Orc"
                CharacterType.ELF:
                        return "Elfo" if it else "Elf"
                CharacterType.KNIGHT:
                        return "Cavaliere" if it else "Knight"
                CharacterType.GOLEM:
                        return "Golem" if it else "Golem"
                CharacterType.DRAGON:
                        return "Uomo Drago" if it else "Dragon Man"
                CharacterType.VAMPIRE:
                        return "Vampiro" if it else "Vampire"
                _:
                        return "Sconosciuto" if it else "Unknown"


## Returns the tint applied to P1 (white = no tint) or P2 (bluish) when
## they pick the same character.
static func get_player_tint(player_num: int) -> Color:
        if player_num == 2:
                # Bluish tint to distinguish P2 from P1 when same character.
                return Color(0.70, 0.80, 1.00, 1.0)
        return Color.WHITE


# ============================================================================
# 6b. TUNNEL "PAC-MAN" (effetto wrap-around ai 4 lati del labirinto)
# ============================================================================
# Il labirinto ha 4 gallerie scavate nel muro di bordo: alto al centro
# (colonna 15, riga 0), basso al centro (colonna 15, riga 14), sinistra
# al centro (colonna 0, riga 7) e destra al centro (colonna 29, riga 7).
# Player e nemici che entrano in una galleria riemergono dal lato
# OPPOSTO dello schermo, raggiungendo cosi' prima il lato opposto.
#
# FIX (fori verticali piu' grandi dei laterali): i tunnel alto/basso erano
# larghi 2 colonne (14-15 = 128px) mentre quelli laterali sono alti 1 riga
# (64px). Ora TUTTE le gallerie sono larghe 1 cella (64px), cosi' i 4 fori
# hanno la STESSA dimensione. Colonna 15 (dispari): le celle di accesso
# (15,1) e (15,13) sono odd-odd, che la DFS scava SEMPRE -> connessione
# garantita senza scavi extra.
const TUNNEL_COLS_TOP_BOTTOM: Array[int] = [15]
const TUNNEL_ROW_SIDES: int = 7


## Celle VIRTUALI fuori griglia che continuano le gallerie (l'unica parte
## "fuori labirinto" calpestabile: chi le attraversa riemerge dal lato
## opposto). Tutto il resto fuori griglia resta muro (is_wall = true).
static func is_tunnel_virtual_cell(c: int, r: int) -> bool:
        # Sopra il tunnel alto / sotto il tunnel basso (colonna singola).
        if TUNNEL_COLS_TOP_BOTTOM.has(c) and (r == -1 or r == MAZE_ROWS):
                return true
        # A sinistra del tunnel sinistro / a destra del tunnel destro (riga 7).
        if r == TUNNEL_ROW_SIDES and (c == -1 or c == MAZE_COLS):
                return true
        return false


## Se (c, r) è una cella di BORDO scavata come imbocco di galleria, ritorna
## la cella di bordo OPPOSTA in cui si riemerge dopo il wrap; altrimenti
## (-1, -1). Mappa completa: (15, 0) <-> (15, 14) e (0, 7) <-> (29, 7).
static func tunnel_partner(c: int, r: int) -> Vector2i:
        if r == 0 and TUNNEL_COLS_TOP_BOTTOM.has(c):
                return Vector2i(c, MAZE_ROWS - 1)
        if r == MAZE_ROWS - 1 and TUNNEL_COLS_TOP_BOTTOM.has(c):
                return Vector2i(c, 0)
        if c == 0 and r == TUNNEL_ROW_SIDES:
                return Vector2i(MAZE_COLS - 1, TUNNEL_ROW_SIDES)
        if c == MAZE_COLS - 1 and r == TUNNEL_ROW_SIDES:
                return Vector2i(0, TUNNEL_ROW_SIDES)
        return Vector2i(-1, -1)


## Celle (col, row) che compongono le 4 gallerie, compresi i corridoi di
## accesso (serve alla grafica e al clamp della modalità fantasma).
## Ritorna true se la cella è un imbocco di galleria o il suo corridoio.
static func is_tunnel_cell(c: int, r: int) -> bool:
        # Imbocchi + corridoi alto / basso (colonna singola, righe 0-1 e 13-14).
        if TUNNEL_COLS_TOP_BOTTOM.has(c) and (r <= 1 or r >= MAZE_ROWS - 2):
                return true
        # Imbocchi + corridoi sinistra / destra (riga 7, colonne 0-1 e 28-29).
        if r == TUNNEL_ROW_SIDES and (c <= 1 or c >= MAZE_COLS - 2):
                return true
        return false


## Teletrasporto "Pac-Man": chi supera il bordo del labirinto DENTRO una
## galleria riemerge dal lato opposto mantenendo direzione e coordinata
## trasversale. Ritorna la NUOVA posizione (identica se nessun wrap).
## Il chiamante rileva il wrap confrontando prima/dopo (new != old) e in
## quel caso specchia anche l'eventuale waypoint grid-locked
## (vedi mirror_waypoint_after_wrap).
static func tunnel_wrap(pos: Vector2) -> Vector2:
        var maze_top: float = float(UI_HEIGHT)
        var maze_bottom: float = float(UI_HEIGHT + MAZE_ROWS * TILE_SIZE)
        var maze_right: float = float(MAZE_COLS * TILE_SIZE)
        if pos.y < maze_top:
                pos.y += float(MAZE_ROWS * TILE_SIZE)
        elif pos.y > maze_bottom:
                pos.y -= float(MAZE_ROWS * TILE_SIZE)
        if pos.x < 0.0:
                pos.x += float(MAZE_COLS * TILE_SIZE)
        elif pos.x > maze_right:
                pos.x -= float(MAZE_COLS * TILE_SIZE)
        return pos


## Specchia il waypoint grid-locked dopo un wrap (il waypoint "verso l'esterno"
## diventa il centro della cella di sbocco opposta: es. (928, 48) -> (928, 1008)).
static func mirror_waypoint_after_wrap(wp: Vector2) -> Vector2:
        var maze_top: float = float(UI_HEIGHT)
        var maze_bottom: float = float(UI_HEIGHT + MAZE_ROWS * TILE_SIZE)
        var maze_right: float = float(MAZE_COLS * TILE_SIZE)
        if wp.y < maze_top:
                wp.y += float(MAZE_ROWS * TILE_SIZE)
        elif wp.y > maze_bottom:
                wp.y -= float(MAZE_ROWS * TILE_SIZE)
        if wp.x < 0.0:
                wp.x += float(MAZE_COLS * TILE_SIZE)
        elif wp.x > maze_right:
                wp.x -= float(MAZE_COLS * TILE_SIZE)
        return wp


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
        # TASK 26 (richiesta utente): munizioni +30% su TUTTE le armi
        # (ceil, mai meno del 30%: 15->20, 8->11, 20->26, 4->6).
        match type:
                WeaponType.PISTOL:
                        return {"type": type, "power": 1, "ammo": 20}
                WeaponType.SHOTGUN:
                        return {"type": type, "power": 3, "ammo": 11}
                WeaponType.LASER:
                        return {"type": type, "power": 2, "ammo": 26}
                WeaponType.ROCKET:
                        return {"type": type, "power": 5, "ammo": 6}
                _:
                        return {"type": WeaponType.PISTOL, "power": 1, "ammo": 20}


## Returns a random weapon Dictionary.
static func make_random_weapon() -> Dictionary:
        var t: int = randi() % 4
        return make_weapon(t)


## TASK 26 — munizioni minime garantite dalla boss room (regola d'ingresso
## "arma utilizzabile"): era 30, +30% -> 39 (ceil). Usata da
## BossRoomController all'ingresso, sul potenziamento e nel restore-continue.
const BOSS_ROOM_AMMO_MIN: int = 39


# ============================================================================
# TASK 39 — L'ARENA DEL BOSS: meccaniche esclusive della stanza del boss
# ============================================================================
# Il combattimento col boss e' lungo (HP alti) e puo' diventare monotono:
# ripetere la stessa azione per decine di secondi. L'arena si trasforma in un
# ALLEATO TATTICO con quattro meccaniche interagenti:
#   1. PILASTRI ELEMENTALI (BossArenaPillar): 4 colonne a tema (elemento
#      debole del boss). Si rompono in 3 colpi del player (o dei proiettili
#      del boss che BLOCCANO, subendo 1 danno: la copertura si consuma).
#      Al crollo scagliano 5 frammenti (ArenaDebris): chi colpisce il boss
#      gli toglie energia -> il player INCLINA lo scontro a proprio favore
#      posizionandosi tra pilastro e boss.
#   2. BARILI ELEMENTALI (ElementalBarrel): raccoglibili e LANCIABILI col
#      tasto di fuoco. Rotolano, rimbalzano sui muri e esplodono con una
#      detonazione elementale dedicata (fuoco/ghiaccio/fulmine/veleno).
#   3. DEBOLEZZA ELEMENTALE per TIPO DI BOSS: ogni boss teme UN elemento
#      (il Golem di pietra teme il GHIACCIO che lo fessura, il Kraken il
#      FULMINO che si propaga nell'acqua, la Strega il FUOCO...). Il barile
#      dell'elemento debole infligge il 250% del danno base. TASK 41: la
#      debolezza NON compare piu' in HUD — si scopre per tentativi.
#   4. CANNONE D'ASSEDIO (BossSiegeCannon): arma ESCLUSIVA della boss room.
#      4 colpi devastanti con palla di cannone pesante (lenta, potente,
#      grafica e audio dedicati). Non esiste nel labirinto.
# RINNOVO DELL'ARENA: ogni BOSS_ARENA_RENEWAL_MS i barili finiti e il
# cannone esaurito riappaiono — gli scontri lunghi non restano mai senza
# strumenti. TASK 43: le ARCHITETTURE (pilastri) NON si rinnovano MAI —
# un pilastro crollato resta un cumulo di macerie fino alla fine dello
# scontro, NEANCHE la morte del player lo fa risorgere (lo snapshot di
# sessione riapplica i danni al continue).
enum ElementKind { FIRE, FROST, LIGHTNING, POISON }

const BOSS_ARENA_PILLAR_COUNT: int = 4        # pilastri per set
const BOSS_ARENA_PILLAR_HP: int = 3           # colpi per abbattere un pilastro
const BOSS_ARENA_PILLAR_FRAGMENTS: int = 5    # frammenti lanciati al crollo
const BOSS_ARENA_PILLAR_FRAGMENT_DMG: int = 3 # danno di un frammento al boss
# raggio fisico (rimbalzo boss / colpi) — TASK 43: architettura PIU'
# GRANDE (pilastro 68x184, era 30 con pilastro 54x130)
const BOSS_ARENA_PILLAR_RADIUS: float = 34.0
const BOSS_ARENA_BARREL_COUNT: int = 3        # barili per set (>= 1 dell'elemento debole)
const BOSS_ARENA_BARREL_BASE_PCT: float = 0.10    # danno base: 10% HP max del boss
const BOSS_ARENA_BARREL_WEAK_MULT: float = 2.5    # elemento debole: 25% HP max
const BOSS_ARENA_BARREL_PLAYER_DMG: int = 1   # danno al player nella deflagrazione
const BOSS_ARENA_BARREL_BLAST_RADIUS: float = 95.0
const BOSS_ARENA_SIEGE_AMMO: int = 4          # colpi del cannone d'assedio
const BOSS_ARENA_SIEGE_POWER: int = 5         # potenza flat minima per colpo
const BOSS_ARENA_SIEGE_PCT: float = 0.025     # + 2.5% HP max del boss per colpo
const BOSS_ARENA_RENEWAL_MS: float = 45000.0  # rigenerazione arena se saccheggiata

## Palette per elemento: nome ITA + colori (corpo/glow) per barili, pilastri,
## esplosioni e testo HUD. Usata da ElementalBarrel / BossArenaPillar /
## BossRoomController (esplosioni e frammenti).
## TASK 41 — l'hint "Debolezza: X" in HUD e' stato RIMOSSO: la debolezza
## non viene piu' riportata, si scopre lanciando i barili sul boss.
static func get_element_palette(el: int) -> Dictionary:
        match el:
                ElementKind.FIRE:
                        return {
                                "id": "fire", "name": "FUOCO", "name_en": "FIRE",
                                "color": Color(1.00, 0.42, 0.14),
                                "glow": Color(1.00, 0.62, 0.22),
                                "wood": Color(0.36, 0.20, 0.10),
                        }
                ElementKind.FROST:
                        return {
                                "id": "frost", "name": "GHIACCIO", "name_en": "FROST",
                                "color": Color(0.42, 0.78, 1.00),
                                "glow": Color(0.62, 0.90, 1.00),
                                "wood": Color(0.26, 0.34, 0.46),
                        }
                ElementKind.LIGHTNING:
                        return {
                                "id": "lightning", "name": "FULMINE", "name_en": "LIGHTNING",
                                "color": Color(1.00, 0.88, 0.26),
                                "glow": Color(1.00, 0.96, 0.55),
                                "wood": Color(0.34, 0.30, 0.12),
                        }
                ElementKind.POISON:
                        return {
                                "id": "poison", "name": "VELENO", "name_en": "POISON",
                                "color": Color(0.55, 0.95, 0.28),
                                "glow": Color(0.72, 1.00, 0.45),
                                "wood": Color(0.24, 0.32, 0.14),
                        }
        return {
                "id": "neutral", "name": "?", "name_en": "?",
                "color": Color.WHITE, "glow": Color.WHITE,
                "wood": Color(0.3, 0.3, 0.3),
        }


## TASK 44: nome ELEMENTALE localizzato (IT "FUOCO" / EN "FIRE") letto
## dalla palette secondo il mirror statico ui_language.
static func get_element_name(el: int) -> String:
        var pal: Dictionary = get_element_palette(el)
        if ui_is_italian():
                return str(pal.get("name", "?"))
        return str(pal.get("name_en", pal.get("name", "?")))


## TASK 39 — elemento DEBOLE di ogni boss (logica fantasy coerente):
##   FUOCO    : brucia non-morti e streghe (Lich, Ragno, Abominio, Vampiro,
##              Signore dei Ghoul, Strega Suprema)
##   GHIACCIO : fessura la pietra col shock termico e spegne le fiamme
##              (Golem, Demone, Drago)
##   FULMINE  : si propaga in acqua e nell'etere (Kraken, Signore degli
##              Spettri, Alfa Spettrale, Araldo del Culto, Cavaliere del
##              Crepuscolo)
##   VELENO   : corroe occhio aberrante, colla del mimico e ratti (Beholder,
##              Mimico Colossale, Re dei Ratti)
static func get_boss_weakness(boss_type: int) -> int:
        match boss_type:
                0:   return ElementKind.FROST      # GOLEM
                1:   return ElementKind.FIRE       # LICH
                2:   return ElementKind.FROST      # DEMON
                3:   return ElementKind.FIRE       # SPIDER
                4:   return ElementKind.FIRE       # ABOMINATION
                5:   return ElementKind.LIGHTNING  # KRAKEN
                6:   return ElementKind.FROST      # DRAGON
                7:   return ElementKind.LIGHTNING  # WRAITH_LORD
                8:   return ElementKind.FIRE       # VAMPIRE
                9:   return ElementKind.POISON     # BEHOLDER
                10:  return ElementKind.FIRE       # GHOUL_LORD
                11:  return ElementKind.LIGHTNING  # SPECTRAL_ALPHA
                12:  return ElementKind.LIGHTNING  # CULT_HERALD
                13:  return ElementKind.POISON     # COLOSSAL_MIMIC
                14:  return ElementKind.POISON     # RAT_KING
                15:  return ElementKind.FIRE       # SUPREME_WITCH
                16:  return ElementKind.LIGHTNING  # TWILIGHT_KNIGHT
        return ElementKind.FIRE


## Nome ITA della debolezza (per l'hint HUD sotto la barra HP del boss).
static func get_boss_weakness_name(boss_type: int) -> String:
        return str(get_element_palette(get_boss_weakness(boss_type)).get("name", "?"))


# ============================================================================
# FIX (richiesta utente — nessuna arma one-shot): NESSUNA arma del player,
# tranne la MINA e la DINAMITE, puo' uccidere un nemico con un colpo solo.
# Le armi hanno un numero di colpi DIVERSO in base all'arma: piu' colpi serve
# un'arma, meno danno fa per colpo. Il danno e' calcolato come FRAZIONE degli
# HP massimi del nemico colpito, cosi' il numero di colpi e' identico per
# qualunque nemico (indipendente dai suoi HP):
#   PISTOL  = 4 colpi per uccidere (25% HP max a colpo)  — piu' munizioni
#   LASER   = 3 colpi (~34% HP max a colpo)
#   SHOTGUN = 2 colpi (50% HP max a colpo)
#   ROCKET  = 2 colpi (50% HP max a colpo)                — poche munizioni
# La mina, la dinamite, il calice (fuoco) e lo scettro (fulmine) restano
# kill istantanei: sono item magici, non armi da fuoco equipaggiabili.
# Il martello (nuovo item) infligge il 50% degli HP max (2 colpi), come da
# specifica utente.
# ============================================================================

# ============================================================================
# TASK 30 — HAZARD AMBIENTALI DEL LABIRINTO
# ============================================================================
# Quattro pericoli ambientali che appaiono nel labirinto a partire dal
# livello HAZARD_GRACE_LEVEL, in quantita' crescente ogni 3 livelli e con
# un MASSIMO di HAZARD_MAX_PER_TYPE per tipo in ogni livello:
#   * SABBIE MOBILI  — rallentano il player del 50% (i nemici passano
#                      indenni); si superano con un salto.
#   * GANASCE        — trappola dentata: intrappola il player e toglie il
#                      33% dell'energia max (morte se l'energia residua non
#                      basta). Mashare i tasti accorcia la tenuta. TASK 34
#                      (richiesta utente): una volta SCATTE resta
#                      DISATTIVATA per tutto il livello — puo' colpire il
#                      player UNA SOLA volta (un proiettile la fa scattare
#                      a vuoto: disattivata anche quello).
#   * VORAGINI       — crepa telegrafica (1.2s) poi si aprono in modo
#                      permanente: chi vi cade dentro perde una vita; si
#                      saltano con un salto.
#   * MURI DI ROCCIA — celle muro che si aprono/chiudono (3s + 0.5s di
#                      vibrazione pre-chiusura): scorciatoia per player e
#                      nemici quando APERTI; CHIUSI bloccano entrambi (i
#                      nemici non entrano mai in una cella muro chiusa,
#                      nemmeno a meta' transito); chi resta imprigionato
#                      prende il 66% dell'energia max (player) o il 33%
#                      (nemico, che resta bloccato fino alla riapertura). Un
#                      nemico ucciso dal muro vale il Doppio dei punti.
# I danni ambientali BYPASSANO le armature-reliquia (vanno dritti
# all'energia): le cariche armatura restano per il combattimento.
# Rollback globale: GameConstants.HAZARDS_ENABLED = false.
# ============================================================================

## Flag di rollback: false = nessun hazard generato e tutti i check no-op.
static var HAZARDS_ENABLED: bool = true

## Primo livello con hazard (i precedenti sono "grace period" tutorial).
const HAZARD_GRACE_LEVEL: int = 4

## Massimo elementi dello STESSO tipo per livello (specifica utente Task 34:
## prima era 5, ora 4 — ganasce, voragini, muri, sabbie non superano MAI il
## numero 4 dello stesso tipo per livello).
const HAZARD_MAX_PER_TYPE: int = 4

## Ogni 3 livelli (dal grace level) gli hazard per tipo aumentano di 1.
const HAZARD_GROWTH_EVERY: int = 3

## Quicksand: fattore di rallentamento del player sulla cella.
const HAZARD_QUICKSAND_SLOW: float = 0.5

## Ganasce (TASK 34): danno in frazione dell'energia max, durata della
## tenuta, riduzione per mash, minimo irriducibile. Lo scatto (cattura o
## proiettile) DISATTIVA la ganascia per il resto del livello: nessun
## riarmo, il player puo' essere colpito UNA SOLA volta.
const HAZARD_TRAP_DAMAGE_PCT: float = 0.33
const HAZARD_TRAP_HOLD_MS: int = 1500
const HAZARD_TRAP_MASH_REDUCE_MS: int = 250
const HAZARD_TRAP_HOLD_MIN_MS: int = 600

## Voragine: durata del telegrafo (crepa + rumble) prima dell'apertura.
const HAZARD_CHASM_TELEGRAPH_MS: int = 1200

## Muro di roccia: durata dei tre stadi del ciclo.
const HAZARD_WALL_OPEN_MS: int = 3000
const HAZARD_WALL_WARN_MS: int = 500
const HAZARD_WALL_CLOSED_MS: int = 3000

## Danni del muro in frazione: player (energia max player) e nemico
## (HP max del nemico).
const HAZARD_WALL_PLAYER_DAMAGE_PCT: float = 0.66
const HAZARD_WALL_ENEMY_DAMAGE_PCT: float = 0.33

## Punti per un nemico ucciso dal muro di roccia (2x il valore standard).
const HAZARD_WALL_KILL_POINTS: int = 10000

## Distanza minima (Chebyshev, in celle) dallo spawn del player (1,1).
const HAZARD_MIN_SPAWN_DIST: int = 3

## Distanza minima (Manhattan, in celle) tra due hazard qualsiasi.
const HAZARD_MIN_GAP: int = 2

## Numero di hazard per tipo al livello dato (0 sotto il grace level,
## poi 1 + un elemento ogni 3 livelli, cap HAZARD_MAX_PER_TYPE).
static func hazard_count_for_level(level: int) -> int:
        if not HAZARDS_ENABLED or level < HAZARD_GRACE_LEVEL:
                return 0
        var n: int = 1 + int((level - HAZARD_GRACE_LEVEL) / HAZARD_GROWTH_EVERY)
        return mini(n, HAZARD_MAX_PER_TYPE)


# ============================================================================
# TASK 31 — BARILI ESPLOSIVI + TERREMOTO CON ROCCE DAL SOFFITTO
# ============================================================================
# Due eventi ambientali supplementari (approvati dall'utente insieme agli
# hazard del Task 30; respinte invece casse-mimico, piastrelle crollanti
# e leve co-op):
#   * BARILI ESPLOSIVI — barili di legno piazzati a caso nei corridoi: un
#     colpo di proiettile li fa esplodere. L'esplosione (raggio 1.5 celle)
#     UCCIDE all'istante i nemici coinvolti (come la mina) e ferisce il
#     player che sta troppo vicino (-33% energia max, salto/ghost/calice
#     salvano). Gli altri barili nel raggio esplodono a catena (breve
#     ritardo). Kill da barile = punti standard (5000) al player vivo
#     piu' vicino.
#   * TERREMOTO — evento periodico casuale: 1.5s di rombo + scrollamento
#     (telegrafo), poi N massi cadono dal soffitto su celle casuali
#     (avvisate da una crepa pulsante ~0.9s prima). L'impatto ferisce
#     chi si trova sulla cella: player -33% energia, nemici -60% HP max.
#     Un masso che colpisce un barile lo innesca. Restano macerie
#     decorative per 3s. Max 1 evento per livello (2 dal livello 20).
# Rollback: GameConstants.BARRELS_ENABLED / QUAKE_ENABLED = false.
# ============================================================================

## Flag di rollback: false = nessun barile generato e le esplosioni no-op.
static var BARRELS_ENABLED: bool = true

## Flag di rollback: false = nessun terremoto programmato.
static var QUAKE_ENABLED: bool = true

## Primo livello con i barili (stesso grace period degli hazard).
const BARREL_GRACE_LEVEL: int = 4

## Massimo barili per livello.
const BARREL_MAX_PER_LEVEL: int = 6

## Raggio dell'esplosione in pixel (1.5 celle circa).
const BARREL_EXPLOSION_RADIUS: float = 100.0

## Danno al player caught nell'esplosione (frazione dell'energia max).
const BARREL_PLAYER_DAMAGE_PCT: float = 0.33

## Ritardo della reazione a catena tra barili.
const BARREL_CHAIN_DELAY_MS: int = 220

## Punti per un nemico ucciso dall'esplosione di un barile (valore standard).
const BARREL_KILL_POINTS: int = 5000

## Barili per livello: 2 al grace level, +1 ogni 6 livelli, cap 6.
static func barrel_count_for_level(level: int) -> int:
        if not BARRELS_ENABLED or level < BARREL_GRACE_LEVEL:
                return 0
        var n: int = 2 + int((level - BARREL_GRACE_LEVEL) / 6)
        return mini(n, BARREL_MAX_PER_LEVEL)


## Primo livello col terremoto (un po' dopo gli hazard: prima si imparano
## le trappole, poi il dungeon stesso si scatena).
const QUAKE_GRACE_LEVEL: int = 6

## Quando parte il primo terremoto del livello (finestra casuale, ms).
const QUAKE_FIRST_MIN_MS: int = 18000
const QUAKE_FIRST_MAX_MS: int = 30000

## Durata del telegrafo del terremoto (rombo + scrollamento).
const QUAKE_TELEGRAPH_MS: int = 1500

## Eventi terremoto per livello: 1, oppure 2 dal livello 20.
static func quake_events_for_level(level: int) -> int:
        if not QUAKE_ENABLED or level < QUAKE_GRACE_LEVEL:
                return 0
        return 2 if level >= 20 else 1

## Massi per evento: 4 base, +1 ogni 6 livelli, cap 10.
static func quake_boulder_count(level: int) -> int:
        return mini(4 + int(level / 6), 10)

## Quanto a lungo la cella bersaglio resta SEGNAALATA prima che il masso
## colpisca (crepa pulsante: tempo di scansarsi).
const QUAKE_MARK_MS: int = 900

## Durata della caduta del masso (dall'alto verso il centro cella).
const QUAKE_FALL_MS: int = 260

## Danni da impatto del masso (frazioni: player su energia max, nemico su
## HP max — il sasso che ti becca fa MALE).
const QUAKE_PLAYER_DAMAGE_PCT: float = 0.33
const QUAKE_ENEMY_DAMAGE_PCT: float = 0.6

## Le macerie restano a terra per questo tempo prima di svanire.
const QUAKE_RUBBLE_MS: int = 3000

## Punti per un nemico ucciso da un masso (valore standard).
const QUAKE_KILL_POINTS: int = 5000


# ============================================================================
# TASK 32 — NUBI DI PIPISTRELLI (evento casuale)
# ============================================================================
# Uno sciame di pipistrelli spawna in un punto casuale del labirinto (lontano
# dal player) e VOLA LIBERO sopra i muri inseguendo il player piu' vicino.
#   * MORSO: -20% dell'energia max (danno ambientale: bypassa le armature;
#     salto/ghost/calice proteggono). Dopo un morso lo sciame rimbalza via
#     per ~0.9s prima di riprendere la caccia (niente drain istantaneo).
#   * DIFESA: DUE colpi di proiettile disperdono lo sciame (+5000 punti);
#     al primo colpo perde un pipistrello (feedback visivo + squittio).
#   * FREQUENZA: 1 evento per livello (dal livello 5), DUE eventi dal
#     livello 31 in poi, a momenti casuali. Se non viene ucciso, lo sciame
#     svolazza via da solo dopo 20s.
#   * AUDIO: battito d'ali periodico mentre caccia + stridio al morso,
#     al colpo subito e alla dispersione.
# Rollback: GameConstants.BATS_ENABLED = false.
# ============================================================================

## Flag di rollback: false = nessun evento pipistrelli programmato.
static var BATS_ENABLED: bool = true

## Primo livello con le nubi di pipistrelli.
const BAT_CLOUD_GRACE_LEVEL: int = 5

## Finestra casuale di primo spawn (ms dall'inizio livello).
const BAT_CLOUD_FIRST_MIN_MS: int = 10000
const BAT_CLOUD_FIRST_MAX_MS: int = 26000

## Finestra del SECONDO evento (livelli 31+), dopo il primo concluso.
const BAT_CLOUD_SECOND_MIN_MS: int = 22000
const BAT_CLOUD_SECOND_MAX_MS: int = 40000

## Eventi per livello: 0 sotto il grace, 1 fino al livello 30, 2 dal 31.
static func bat_events_for_level(level: int) -> int:
        if not BATS_ENABLED or level < BAT_CLOUD_GRACE_LEVEL:
                return 0
        return 2 if level >= 31 else 1

## Velocita' di volo (px/frame a 60fps): il player corre a 2 — seminare
## lo sciame in linea retra e' possibile, ma gli angoli costano cari.
const BAT_CLOUD_SPEED: float = 1.7

## Cooldown tra i morsi (ms) e durata del rimbalzo post-morso.
const BAT_CLOUD_BITE_CD_MS: int = 900
const BAT_CLOUD_FLEE_MS: int = 900

## Danno del morso (frazione dell'energia max).
const BAT_CLOUD_PLAYER_DAMAGE_PCT: float = 0.2

## Colpi di proiettile per disperdere lo sciame e punti bonus.
const BAT_CLOUD_HITS_TO_DIE: int = 2
const BAT_CLOUD_KILL_POINTS: int = 5000

## Vita massima dello sciame se nessuno lo abbatte (poi vola via).
const BAT_CLOUD_LIFETIME_MS: int = 20000

## Distanza minima di spawn da OGNI player vivo (px, ~6 celle).
const BAT_CLOUD_MIN_SPAWN_DIST: float = 384.0


# ============================================================================
# TASK 35 — PERGAMENE EVENTO (terremoto + voragini magiche)
# ============================================================================
# Due pergamene raccoglibili con le STESSE meccaniche di apparizione:
# momento casuale del livello, SOLO se i nemici vivi sono almeno il 30%
# del totale iniziale (TASK 36: soglia abbassata dal 50% al 30%; al di
# sotto del 30% non appaiono piu'), telegrafo luminoso (bagliore/aura
# ~1.2s) sulla cella PRIMA dell'apparizione, poi un FULMINE SI ABBATE AL
# SUOLO sulla cella (TASK 36: effetto visivo pronunciato + effetto audio
# lungo dedicato SCROLL_LIGHTNING) e la pergamena resta a terra per 10s
# e lampeggia per gli ultimi 2s (poi scompare: evento perso).
# TASK 36 — apparizioni multiple: ogni TIPO puo' apparire al massimo DUE
# volte per livello in momenti casuali, ma puo' essere UTILIZZATA una
# sola volta: se la pergamena viene raccolta e usata, quel tipo non
# appare piu' nello stesso livello; se invece scade senza essere raccolta,
# puo' riapparire una seconda volta.
# Si attivano IMMEDIATAMENTE alla raccolta, un solo uso:
#   * PERGAMENA DEL TERREMOTO (arancio, simbolo sismico in alto a dx):
#     scatena un terremoto che infligge il 50% degli HP max a TUTTI i
#     nemici (mini-boss compreso); chi dopo il colpo si ritrova SOTTO il
#     50% dell'energia massima viene ELIMINATO. Il player non subisce
#     NESSUN danno. Kill ambientale: +5000 punti al raccoglitore.
#   * PERGAMENA DELLE VORAGINI (viola, simbolo spirale in alto a dx):
#     fa apparire 4 voragini MAGICHE in celle casuali BEN DISTANZIATE
#     tra loro (gap Manhattan >= 5). I nemici che vi entrano/ci cadono
#     sopra vengono UCCISI (+5000 punti al raccoglitore); il player NON
#     puo' caderci (immune del tutto). Ogni ondata dura 4s, poi le
#     voragini svaniscono e riappaiono in ALTRRE 4 celle casuali, per
#     3 ondate totali (12s di effetto). NON bloccano il pathing: i
#     nemici non le vedono e ci camminano dentro.
# Le due pergamene hanno lo stesso stile ma COLORI DIVERSI e dimensioni
# dei tesori (48px). 2 apparizioni per TIPO per livello, 1 solo uso.
# Rollback: GameConstants.PARCHMENTS_ENABLED = false.
# ============================================================================

## Flag di rollback: false = nessuna pergamena programmata.
static var PARCHMENTS_ENABLED: bool = true

## Primo livello con le pergamene evento.
const PARCHMENT_GRACE_LEVEL: int = 5

## Finestra casuale di apparizione (ms dall'inizio livello), per tipo.
const PARCHMENT_FIRST_MIN_MS: int = 25000
const PARCHMENT_FIRST_MAX_MS: int = 70000

## Se alla scadenza del timer i vivi sono sotto il 30%, riprova tra N ms.
const PARCHMENT_RETRY_MS: int = 5000

## Durata del bagliore/aura di telegrafo prima dell'apparizione.
const PARCHMENT_TELEGRAPH_MS: int = 1200

## Tempo raccoglibile a terra + lampeggio finale prima di svanire.
## TASK 41 — periodo raccoglibile +50%: 10s -> 16s visibili (totale
## 12s -> 18s con il lampeggio finale invariato a 2s).
const PARCHMENT_VISIBLE_MS: int = 16000
const PARCHMENT_BLINK_MS: int = 2000

## Soglia di nemici vivi per far apparire la pergamena (frazione del
## totale iniziale del livello). TASK 36: 0.5 -> 0.3 — le pergamene
## possono apparire anche con i nemici al 30%; AL DI SOTTO non appaiono.
const PARCHMENT_MIN_ALIVE_PCT: float = 0.3

## TASK 36 — apparizioni massime per TIPO per livello: DUE momenti casuali,
## ma UN SOLO USO (la raccolta chiude l'evento per il resto del livello).
const PARCHMENT_MAX_SPAWNS: int = 2

## TASK 36 — finestra casuale della SECONDA apparizione (ms dalla
## scomparsa della prima pergamena non raccolta: era scaduta a terra).
const PARCHMENT_NEXT_MIN_MS: int = 15000
const PARCHMENT_NEXT_MAX_MS: int = 45000

## Pergamena del terremoto: danno a tutti i nemici (frazione HP max) e
## soglia di eliminazione (chi resta sotto quella frazione viene ucciso).
const SCROLL_QUAKE_DAMAGE_PCT: float = 0.5
const SCROLL_QUAKE_KILL_PCT: float = 0.5
const SCROLL_QUAKE_KILL_POINTS: int = 5000

## Pergamena delle voragini: numero di voragini per ondata, durata di
## ogni ondata, ondate totali, distanza minima tra voragini (Manhattan,
## in celle) e durata della dissolvenza tra le ondate.
## TASK 51 (P2, richiesta utente): durata effetto +40% -> ogni ondata
## dura 5600ms invece di 4000ms (3 ondate = 16.8s totali vs 12s).
const SCROLL_CHASM_COUNT: int = 4
const SCROLL_CHASM_WAVE_MS: int = 5600
const SCROLL_CHASM_WAVES: int = 3
const SCROLL_CHASM_MIN_GAP: int = 5
const SCROLL_CHASM_FADE_MS: int = 350
const SCROLL_CHASM_KILL_POINTS: int = 5000


# ============================================================================
# RELIC (Task 21): i TYPE delle 12 armi reliquia (6 mischia + 6 distanza)
# + il proiettile riflesso dalle Scaglie del Drago. Dichiarati QUI (prima
# di WEAPON_HITS_TO_KILL) perche' i const si valutano IN ORDINE nel file.
# ============================================================================
enum RelicType {
        # --- MISCHIA ---
        SWORD = 101,           ## Spadone del Cavaliere
        AXE = 102,             ## Ascia del Berserker
        MACE = 103,            ## Mazza Ferrata
        HALBERD = 104,          ## Alabarda della Guardia Reale
        VAMPIRE_BLADE = 105,   ## Lama del Vampiro
        GOLEM_HAMMER = 106,    ## Martello del Golem
        # --- DISTANZA ---
        CROSSBOW = 107,        ## Balestra d'Argento
        ARCANE_ORB = 108,      ## Bastone dell'Arcimago
        TWIN_DAGGERS = 109,    ## Pugnali Gemelli
        RANGER_BOW = 110,      ## Arco del Ranger
        STORM_ROD = 111,       ## Verga della Tempesta
        ALCHEMIST_BOMBS = 112, ## Bombe dell'Alchimista
        # --- SPECIALE ---
        REFLECT_BOLT = 113,    ## Proiettile riflesso dalle Scaglie del Drago
}

## Colpi necessari a uccidere un nemico, per tipo di arma equipaggiata.
## RELIC (Task 21): incluse anche le 12 armi reliquia (tipi 101..112):
## stessa filosofia "nessuna arma one-shot" (mai meno di 2 colpi).
const WEAPON_HITS_TO_KILL: Dictionary = {
        WeaponType.PISTOL: 4,
        WeaponType.LASER: 3,
        WeaponType.SHOTGUN: 2,
        WeaponType.ROCKET: 2,
        # --- Reliquie MISCHIA (101..106) ---
        RelicType.SWORD: 2,
        RelicType.AXE: 2,
        RelicType.MACE: 3,
        RelicType.HALBERD: 3,
        RelicType.VAMPIRE_BLADE: 3,
        RelicType.GOLEM_HAMMER: 2,
        # --- Reliquie DISTANZA (107..112) ---
        RelicType.CROSSBOW: 2,
        RelicType.ARCANE_ORB: 3,
        RelicType.TWIN_DAGGERS: 4,
        RelicType.RANGER_BOW: 4,
        RelicType.STORM_ROD: 3,
        RelicType.ALCHEMIST_BOMBS: 2,
        # --- Proiettile riflesso dalle Scaglie del Drago (113) ---
        RelicType.REFLECT_BOLT: 2,
}


## Danno per colpo di un'arma su un bersaglio con `target_max_health` HP.
## Ritorna sempre ALMENO 1, e per costruzione NON uccide mai in un colpo solo
## un nemico con HP >= 2 (gli HP base dei nemici sono scalati x4, vedi
## Enemy.gd ENEMY_HEALTH_SCALE: il piu' debole ha 4 HP -> 4 colpi di pistola).
## RELIC (Task 21): `fury` = true con la Corazza del Furore equipaggiata →
## l'arma colpisce come se avesse 1 hit-to-kill in MENO (floor 2: la regola
## "nessuna arma one-shot" resta sacra anche potenziata).
static func weapon_damage_for(weapon_type: int, target_max_health: int,
                fury: bool = false) -> int:
        var hits: int = int(WEAPON_HITS_TO_KILL.get(weapon_type, 4))
        if fury:
                hits = maxi(2, hits - 1)
        if hits < 2:
                hits = 2  # sicurezza: mai one-shot per costruzione
        var dmg: int = int(ceil(float(target_max_health) / float(hits)))
        return maxi(1, dmg)


## Danno del MARTELLO (50% degli HP massimi del nemico colpito: 2 colpi per
## uccidere qualunque nemico, come richiesto dall'utente).
static func hammer_damage_for(target_max_health: int) -> int:
        return maxi(1, int(round(float(target_max_health) * 0.5)))


## Returns the human-readable name of a weapon type. TASK 26 (richiesta
## utente): le ARMI SPECIALI (reliquie) restituiscono "" -> la HUD non
## mostra il nome (resta il contatore AMMO); i nomi lunghi delle reliquie
## si sovrapponevano ai cuori delle vite. I nomi completi restano nelle
## schermate bonus (BonusScreen usa name/short delle definizioni).
## TASK 44: localizzato (EN default / IT) tramite il mirror statico
## ui_language (le reliquie usano invece i campi name/name_en).
static func get_weapon_name(type: int) -> String:
        if is_relic_weapon(type):
                return ""
        var it: bool = ui_is_italian()
        match type:
                WeaponType.PISTOL:
                        return "PISTOLA" if it else "PISTOL"
                WeaponType.SHOTGUN:
                        return "FUCILE" if it else "SHOTGUN"
                WeaponType.LASER:
                        return "LASER"
                WeaponType.ROCKET:
                        return "RAZZI" if it else "ROCKET"
                WeaponType.SIEGE:
                        return "ASSEDIO" if it else "SIEGE"
                _:
                        return "?"


## Returns the UI color associated with a weapon type (incluse le reliquie).
static func get_weapon_color(type: int) -> Color:
        var relic: Dictionary = get_relic_def(type)
        if not relic.is_empty():
                return relic.get("color", Color.WHITE)
        match type:
                WeaponType.PISTOL:
                        return Color(0.78, 0.78, 0.20, 1.0)  # (200,200,50)
                WeaponType.SHOTGUN:
                        return Color(0.78, 0.39, 0.20, 1.0)  # (200,100,50)
                WeaponType.LASER:
                        return Color(0.31, 0.78, 1.00, 1.0)  # (80,200,255)
                WeaponType.ROCKET:
                        return Color(0.78, 0.20, 0.20, 1.0)  # (200,50,50)
                WeaponType.SIEGE:
                        return Color(1.00, 0.80, 0.30, 1.0)  # (255,204,77) oro
                _:
                        return Color.WHITE


# ============================================================================
# 8. RELIC (Task 21) — LE 18 RELIQUIE DELLE SCHERMATE BONUS POST-BOSS
# ============================================================================
# 6 MISCHIA + 6 DISTANZA + 6 ARMATURE. Il player le SCELGE nella schermata
# bonus dopo ogni boss (rotazione A->B->C->A; TUTTE le famiglie disponibili
# in OGNI schermata; in 2P una reliquia per player).
#
# REGOLE COMUNI (decisioni utente):
#   * Armi reliquia a COLPI FINITI: esauriti i colpi l'arma SI ROMPE e si
#     torna alla PISTOL. ALLA MORTE (perdita vita) reliquia arma E armatura
#     si PERDONO (si torna a PISTOL / nessuna armatura).
#   * Le armi a terra NON sovrascrivono una reliquia equipaggiata.
#   * In BOSS ROOM i colpi della reliquia sono INFINITI (come le munizioni
#     potenziate delle armi base).
#   * Armature: tutte danno +2 energia max (5 -> 7) con CURA PIENA
#     all'equipaggiamento + outfit overlay procedurale; si rompono per
#     DURABILITA' (ognuna a modo suo) e si perdono alla morte.
#   * Danno: labirinto = frazione degli HP max del nemico (WEAPON_HITS_TO_KILL,
#     "hits"); boss room / mini-boss = danno FLAT ("power").
#   * RIFLESSIONE Scaglie del Drago: il proiettile nemico rimbalza verso il
#     boss come proiettile DEL PLAYER con il danno del MIGLIORE colpo del
#     player (max potenza base = 5, ROCKET; sale se una reliquia piu' forte
#     e' equipaggiata).
# ============================================================================

## MISCHIA — danno ad area istantaneo attorno al player (il controller
## calcola i nemici nella shape e applica il danno; visual = arco/spinta
## disegnato dal player per ~250ms).
##   shape: "sector" (arco orientato al facing) | "circle" (360 gradi)
##           "line" (linea perforante davanti al player)
##   hits: colpi-per-uccidere nel labirinto (frazione HP max)
##   power: danno FLAT vs boss / mini-boss
##   shots: colpi totali (rotura a 0)
##   splash_px / splash_hits: solo ASCIA — danno ad area attorno al bersaglio
##   stun_ms: nemici STUNNATI (congelati) per N ms
##   vampiric: cura 1 energia per nemico colpito
##   png_grip_deg: TASK 24 — dove sta l'IMPUGNATURA nell'icona PNG (gradi
##           nello spazio immagine, y verso il basso, 0=destra, 90=basso,
##           -90=alto): il rendering in mano/al fendente allinea la parte
##           OPPOSTA (lama/testa) alla mira e tiene il manico sulla mano.
##           Es. spadone: elsa in alto -> -90.
const RELIC_MELEE: Array[Dictionary] = [
        # TASK 26 (richiesta utente): "shots" = munizioni +30% rispetto ai
        # valori originali (arrotondati PER ECCESSO, mai meno del +30%):
        # 25->33, 15->20, 12->16, 18->24, 20->26, 10->13 (mischia) e
        # 30->39, 24->32, 20->26, 40->52, 15->20, 12->16 (distanza).
        {
                "id": "sword", "type": RelicType.SWORD, "family": "mischia",
                "name": "Spadone del Cavaliere", "short": "SPADONE",
                "name_en": "Knight's Greatsword", "short_en": "GREATSWORD",
                "color": Color(0.82, 0.86, 0.94), "power": 3, "hits": 2,
                "shots": 33, "shape": "sector", "radius_px": 150.0,
                "arc_deg": 150.0, "fire_cd": 260, "max_targets": 4,
                "png_grip_deg": -90.0,
                "desc": "Arco amplissimo: fende fino a 4 nemici davanti a te.",
                "desc_en": "Huge arc: cleaves up to 4 enemies in front of you.",
        },
        {
                "id": "axe", "type": RelicType.AXE, "family": "mischia",
                "name": "Ascia del Berserker", "short": "ASCIA",
                "name_en": "Berserker Axe", "short_en": "AXE",
                "color": Color(0.90, 0.35, 0.20), "power": 5, "hits": 2,
                "shots": 20, "shape": "sector", "radius_px": 96.0,
                "arc_deg": 90.0, "fire_cd": 380, "splash_px": 64.0,
                "splash_hits": 4, "png_grip_deg": 45.0,
                "desc": "Colpo devastante + scheggia ad area attorno al bersaglio.",
                "desc_en": "Devastating strike + area shrapnel around the target.",
        },
        {
                "id": "mace", "type": RelicType.MACE, "family": "mischia",
                "name": "Mazza Ferrata", "short": "MAZZA",
                "name_en": "Flanged Mace", "short_en": "MACE",
                "color": Color(0.72, 0.72, 0.78), "power": 2, "hits": 3,
                "shots": 16, "shape": "circle", "radius_px": 96.0,
                "arc_deg": 360.0, "fire_cd": 340, "stun_ms": 1000,
                "png_grip_deg": 90.0,
                "desc": "Rotazione 360°: colpisce attorno e STORDISCE i nemici.",
                "desc_en": "360° spin: strikes all around and STUNS enemies.",
        },
        {
                "id": "halberd", "type": RelicType.HALBERD, "family": "mischia",
                "name": "Alabarda della Guardia Reale", "short": "ALABARDA",
                "name_en": "Royal Guard Halberd", "short_en": "HALBERD",
                "color": Color(0.86, 0.78, 0.40), "power": 3, "hits": 3,
                "shots": 24, "shape": "line", "radius_px": 192.0,
                "arc_deg": 0.0, "fire_cd": 340, "png_grip_deg": 90.0,
                "desc": "Lunga (3 celle): infilza tutti i nemici in linea davanti.",
                "desc_en": "Long reach (3 tiles): skewers every enemy in a line.",
        },
        {
                "id": "vampire_blade", "type": RelicType.VAMPIRE_BLADE, "family": "mischia",
                "name": "Lama del Vampiro", "short": "LAMA",
                "name_en": "Vampire Blade", "short_en": "VAMP BLADE",
                "color": Color(0.85, 0.20, 0.35), "power": 2, "hits": 3,
                "shots": 26, "shape": "sector", "radius_px": 96.0,
                "arc_deg": 90.0, "fire_cd": 300, "vampiric": true,
                "png_grip_deg": 225.0,
                "desc": "Ogni nemico colpito ti CURA 1 energia.",
                "desc_en": "Every enemy hit HEALS you 1 energy.",
        },
        {
                "id": "golem_hammer", "type": RelicType.GOLEM_HAMMER, "family": "mischia",
                "name": "Martello del Golem", "short": "MARTELLO",
                "name_en": "Golem Hammer", "short_en": "HAMMER",
                "color": Color(0.65, 0.55, 0.45), "power": 4, "hits": 2,
                "shots": 13, "shape": "circle", "radius_px": 64.0,
                "arc_deg": 360.0, "fire_cd": 400, "stun_ms": 500,
                "png_grip_deg": 90.0,
                "desc": "Slam pesante attorno ai piedi: scossa + stordimento breve.",
                "desc_en": "Heavy ground slam: shockwave + brief stun.",
        },
]

## DISTANZA — proiettili con flag di comportamento (pattern Task 18):
##   pierce_max: il dardo attraversa fino a N nemici (Balestra)
##   homing: il proiettile insegue il nemico piu' vicino (Bastone)
##   fan: N proiettili a ventaglio per colpo (Pugnali)
##   fire_cd: cooldown di fuoco dedicato (Arco = rapido)
##   chain: catena di fulmini che salta ai nemici vicini (Verga)
##   lob_px: parabola che esplode dopo N px (Bombe, AoE radius_px)
##   png_grip_deg: TASK 24 — come per la mischia (bastone/verga: manico in
##           basso, parte utile in alto; pugnali: elsa in alto).
##   png_point_deg: TASK 24 — SOLO armi a impugnatura CENTRALE (arco,
##           balestra): direzione in cui l'icona PUNTA/SCOCCA (gradi nello
##           spazio immagine, y in giu'). Il rendering allinea quest'asse
##           alla mira e tiene il centro sulla mano.
const RELIC_RANGED: Array[Dictionary] = [
        {
                "id": "crossbow", "type": RelicType.CROSSBOW, "family": "distanza",
                "name": "Balestra d'Argento", "short": "BALESTRA",
                "name_en": "Silver Crossbow", "short_en": "CROSSBOW",
                "color": Color(0.90, 0.92, 0.98), "power": 3, "hits": 2,
                "shots": 39, "fire_cd": 160, "pierce_max": 3,
                "png_point_deg": 135.0,
                "desc": "Dardo perforante: attraversa fino a 3 nemici.",
                "desc_en": "Piercing bolt: punches through up to 3 enemies.",
        },
        {
                "id": "arcane_orb", "type": RelicType.ARCANE_ORB, "family": "distanza",
                "name": "Bastone dell'Arcimago", "short": "BASTONE",
                "name_en": "Archmage Staff", "short_en": "STAFF",
                "color": Color(0.55, 0.40, 0.95), "power": 2, "hits": 3,
                "shots": 32, "fire_cd": 200, "homing": true,
                "png_grip_deg": 90.0,
                "desc": "Sfera arcana a ricerca: insegue il nemico piu' vicino.",
                "desc_en": "Homing arcane orb: seeks out the nearest enemy.",
        },
        {
                "id": "twin_daggers", "type": RelicType.TWIN_DAGGERS, "family": "distanza",
                "name": "Pugnali Gemelli", "short": "PUGNALI",
                "name_en": "Twin Daggers", "short_en": "DAGGERS",
                "color": Color(0.45, 0.90, 0.85), "power": 2, "hits": 4,
                "shots": 26, "fire_cd": 220, "fan": 3, "fan_spread_deg": 18.0,
                "png_grip_deg": -90.0,
                "desc": "Ventaglio di 3 lame per salve: copre un ampio fronte.",
                "desc_en": "Fan of 3 blades per volley: covers a wide front.",
        },
        {
                "id": "ranger_bow", "type": RelicType.RANGER_BOW, "family": "distanza",
                "name": "Arco del Ranger", "short": "ARCO",
                "name_en": "Ranger Bow", "short_en": "BOW",
                "color": Color(0.55, 0.85, 0.35), "power": 1, "hits": 4,
                "shots": 52, "fire_cd": 90,
                "png_point_deg": 0.0,
                "desc": "Tiro rapido: frecce leggere ma frecce a raffica.",
                "desc_en": "Rapid fire: light arrows in quick volleys.",
        },
        {
                "id": "storm_rod", "type": RelicType.STORM_ROD, "family": "distanza",
                "name": "Verga della Tempesta", "short": "VERGA",
                "name_en": "Storm Rod", "short_en": "STORM ROD",
                "color": Color(0.55, 0.80, 1.00), "power": 2, "hits": 3,
                "shots": 20, "fire_cd": 200, "chain": 2, "chain_radius_px": 128.0,
                "png_grip_deg": 90.0,
                "desc": "Fulmine a catena: salta fino a 2 nemici vicini.",
                "desc_en": "Chain lightning: arcs to up to 2 nearby enemies.",
        },
        {
                "id": "alchemist_bombs", "type": RelicType.ALCHEMIST_BOMBS, "family": "distanza",
                "name": "Bombe dell'Alchimista", "short": "BOMBE",
                "name_en": "Alchemist Bombs", "short_en": "BOMBS",
                "color": Color(1.00, 0.60, 0.15), "power": 4, "hits": 2,
                "shots": 16, "fire_cd": 250, "lob_px": 160.0,
                "radius_px": 96.0,
                "desc": "Bomba a parabola: esplode ad area dopo 2 celle e mezza.",
                "desc_en": "Lobbed bomb: explodes in an area after 2.5 tiles.",
        },
]

## ARMATURE — equipaggiabili (slot dedicato, NON occupano l'arma):
##   kind: absorb | reflect | thorns | regen | aura | fury
##   charges: durabilita' iniziale (si consuma secondo il kind)
##   Tutte: +2 energia max (5 -> 7) + CURA PIENA all'equip + overlay outfit.
const RELIC_ARMORS: Array[Dictionary] = [
        {
                "id": "golden", "kind": "absorb", "family": "armatura",
                "name": "Corazza d'Oro", "short": "CORAZZA",
                "name_en": "Golden Cuirass", "short_en": "GOLD ARMOR",
                "color": Color(1.00, 0.80, 0.25), "charges": 10,
                "desc": "Assorbe i colpi con una riserva doppia della vita (10 cariche).",
                "desc_en": "Absorbs hits with a reserve twice your life (10 charges).",
        },
        {
                "id": "dragon", "kind": "reflect", "family": "armatura",
                "name": "Scaglie del Drago", "short": "SCAGLIE",
                "name_en": "Dragon Scales", "short_en": "SCALES",
                "color": Color(0.25, 0.85, 0.55), "charges": 4,
                "desc": "Riflette 4 proiettili: il colpo rimbalza e colpisce il boss col tuo danno migliore.",
                "desc_en": "Reflects 4 projectiles: the shot bounces back at the boss with your best damage.",
        },
        {
                "id": "obsidian", "kind": "thorns", "family": "armatura",
                "name": "Ossidiana del Crepuscolo", "short": "OSSIDIANA",
                "name_en": "Twilight Obsidian", "short_en": "OBSIDIAN",
                "color": Color(0.70, 0.35, 0.95), "charges": 5,
                "thorn_damage": 2,
                "desc": "Spine: chi ti tocca in mischia prende 2 danni (5 cariche).",
                "desc_en": "Thorns: melee attackers take 2 damage (5 charges).",
        },
        {
                "id": "archmage", "kind": "regen", "family": "armatura",
                "name": "Veste dell'Arcimago", "short": "VESTE",
                "name_en": "Archmage Robe", "short_en": "ROBE",
                "color": Color(0.45, 0.55, 0.95), "charges": 12,
                "regen_ms": 5000,
                "desc": "Rigenera 1 energia ogni 5 secondi (12 volte).",
                "desc_en": "Regenerates 1 energy every 5 seconds (12 times).",
        },
        {
                "id": "fire", "kind": "aura", "family": "armatura",
                "name": "Corazza di Fuoco", "short": "FUOCO",
                "name_en": "Fire Armor", "short_en": "FIRE",
                "color": Color(1.00, 0.45, 0.20), "charges": 20,
                "aura_ms": 2000, "aura_radius_px": 64.0, "aura_damage": 1,
                "contact_hits": 2,
                "desc": "Aura ustionante: i nemici vicini bruciano (20 pulsazioni).",
                "desc_en": "Scorching aura: nearby enemies burn (20 pulses). Touching an enemy burns it instead of you.",
        },
        {
                "id": "fury", "kind": "fury", "family": "armatura",
                "name": "Corazza del Furore", "short": "FURORE",
                "name_en": "Fury Cuirass", "short_en": "FURY ARMOR",
                "color": Color(0.90, 0.20, 0.25), "charges": 30,
                "desc": "I tuoi colpi colpiscono piu' a fondo (+1 grado): 30 colpi poi si spegne.",
                "desc_en": "Your hits strike one grade deeper: 30 shots, then it fades.",
        },
]

## Definizione reliquia per type ({} se non e' una reliquia). Ricerca
## lineare nelle 12 armi + il proiettile riflesso: chiamata raramente e su
## liste minuscole (niente dict costanti mutabili, vietate in GDScript).
static func get_relic_def(type: int) -> Dictionary:
        for def in RELIC_MELEE:
                if int(def.get("type", 0)) == type:
                        return def
        for def in RELIC_RANGED:
                if int(def.get("type", 0)) == type:
                        return def
        if type == RelicType.REFLECT_BOLT:
                return REFLECT_BOLT_DEF
        return {}


## True se `type` e' un'arma reliquia (101..113).
static func is_relic_weapon(type: int) -> bool:
        return not get_relic_def(type).is_empty()


## Lookup type -> definizione (armi reliquia + proiettile riflesso).
## Il proiettile riflesso dalle Scaglie del Drago: danno del MIGLIORE colpo
## del player. Base = ROCKET (5); sale se il player impugna una reliquia
## con potenza flat maggiore (es. Ascia 5).
const REFLECT_BOLT_DEF: Dictionary = {
        "id": "reflect_bolt", "type": RelicType.REFLECT_BOLT, "family": "riflesso",
        "name": "Colpo Riflesso", "short": "RIFLESSO",
        "color": Color(0.30, 0.95, 0.70), "power": 5, "hits": 2,
}


## Costruisce il Dictionary-arma (compatibile con current_weapon:
## {type, power, ammo}) esteso con le chiavi reliquia.
static func make_relic_weapon(def: Dictionary) -> Dictionary:
        return {
                "type": int(def.get("type", 0)),
                "power": int(def.get("power", 1)),
                "ammo": int(def.get("shots", 10)),
                "max_ammo": int(def.get("shots", 10)),
                "relic": str(def.get("id", "")),
                "melee": bool(def.get("family", "") == "mischia"),
        }


## Cooldown di fuoco per l'arma corrente: le reliquie hanno il loro
## fire_cd (es. Arco del Ranger 90ms = raffica), le armi base 150ms.
static func relic_fire_cooldown(weapon: Dictionary) -> int:
        var def: Dictionary = get_relic_def(int(weapon.get("type", 0)))
        if def.is_empty():
                return 150
        return int(def.get("fire_cd", 150))


# ----------------------------------------------------------------------------
# SCHERMATE BONUS — rotazione e offerta
# ----------------------------------------------------------------------------
## Indice dell'incontro bonus (0-based): dopo il boss del livello 4 -> 0,
## dopo l'8 -> 1, ... dopo il 68 -> 16. In infinito continua a crescere.
static func get_bonus_encounter(level: int) -> int:
        return int(level / TOTAL_LEVELS_PER_BOSS) - 1


## Quale schermata bonus tocca (0=A, 1=B, 2=C), rotazione fissa A->B->C->A
## decisa dall'utente: dopo il boss 1 la A, boss 2 la B, boss 3 la C,
## boss 4 di nuovo A... (A: boss 1,4,7,10,13,16 = 6 volte; B: 2,5,8,11,14,17
## = 6; C: 3,6,9,12,15 = 5).
static func get_bonus_screen_id(level: int) -> int:
        return get_bonus_encounter(level) % 3


## TASK 33 — ORDINE DI POTENZA CRESCENTE (richiesta utente: "le armi che
## fanno piu' danno vengono date piu' avanti nei livelli rispetto a quelle
## che fanno meno danni — ordinamento per potenza crescente, prima le piu'
## scarse"). Indici nelle liste RELIC_MELEE / RELIC_RANGED / RELIC_ARMORS,
## dal piu' debole al piu' forte. La scelta tiene conto di POTENZA (power),
## colpi-per-uccidere (hits: meno colpi = piu' danno) ed effetti speciali:
##   MISCHIA:  Mazza (p2, 3 colpi, solo stun) < Lama del Vampiro (p2, 3
##     colpi, risucchio) < Alabarda (p3, 3 colpi, linea perforante) <
##     Spadone (p3, 2 colpi, settore largo) < Martello del Golem (p4, 2
##     colpi, 360 gradi + stun) < Ascia (p5, 2 colpi, settore + splash).
##   DISTANZA: Arco (p1, 4 colpi) < Pugnali (p2, ventaglio) < Bastone (p2,
##     a ricerca) < Verga (p2, fulmine a catena) < Balestra (p3,
##     perforante x3) < Bombe (p4, esplosione ad area).
##   ARMATURE: Ossidiana (spine, situazionale) < Scaglie (riflesso, solo
##     contro chi spara) < Veste (rigenerazione lenta) < Corazza d'Oro
##     (assorbimento diretto) < Fuoco (aura + immunita' al contatto) <
##     Furore (+1 grado a OGNI colpo).
const RELIC_POWER_ORDER_MELEE: Array[int] = [2, 4, 3, 0, 5, 1]
const RELIC_POWER_ORDER_RANGED: Array[int] = [3, 2, 1, 4, 0, 5]
const RELIC_POWER_ORDER_ARMOR: Array[int] = [2, 1, 3, 0, 4, 5]


## Le 3 reliquie offerte nella schermata bonus dopo il boss del `level`:
## UNA per famiglia (mischia/distanza/armatura — tutte le famiglie sempre
## disponibili). TASK 33: le famiglie camminano in PARALLELO sull'ordine
## di POTENZA CRESCENTE (stesso "tier" per tutte e tre): i primi boss
## offrono le reliquie piu' scarse, i boss piu' avanti quelle piu' forti.
## Con 17 incontri e 6 pezzi per famiglia il ciclo 6+6+5 fa comparire
## tutte le 18 reliquie, e nessun pezzo si ripete due volte di fila.
static func get_bonus_offering(level: int) -> Array[Dictionary]:
        var e: int = get_bonus_encounter(level)
        if e < 0:
                e = 0
        var tier: int = e % RELIC_POWER_ORDER_MELEE.size()
        return [
                RELIC_MELEE[RELIC_POWER_ORDER_MELEE[tier]],
                RELIC_RANGED[RELIC_POWER_ORDER_RANGED[tier]],
                RELIC_ARMORS[RELIC_POWER_ORDER_ARMOR[tier]],
        ]


# ----------------------------------------------------------------------------
# RELIC: geometria degli attacchi in MISCHIA (usata da entrambi i controller)
# ----------------------------------------------------------------------------
## True se `target_pos` cade nella shape del fendente `def` partito da
## `from_pos` orientato come `aim_dir` (unitario):
##   * "circle": chiunque entro radius_px (Mazza / Martello, 360 gradi)
##   * "line":   entro radius_px davanti, con scarto perpendicolare <= 26 px
##               (Alabarda: linea perforante)
##   * "sector": entro radius_px e dentro il cono di arc_deg/2 attorno alla
##               direzione del fendente (Spadone / Ascia / Lama)
static func relic_melee_in_shape(def: Dictionary, aim_dir: Vector2,
                from_pos: Vector2, target_pos: Vector2) -> bool:
        var radius: float = float(def.get("radius_px", 96.0))
        var d: Vector2 = target_pos - from_pos
        var dist: float = d.length()
        if dist > radius:
                return false
        if dist < 1.0:
                return true  # addosso: colpito da qualunque shape
        var shape: String = str(def.get("shape", "sector"))
        if shape == "circle":
                return true
        if shape == "line":
                var n: Vector2 = aim_dir.normalized()
                var proj: float = d.dot(n)
                if proj < -16.0:
                        return false  # dietro il player
                var perp: float = absf(d.x * -n.y + d.y * n.x)
                return perp <= 26.0
        # sector
        var half_arc: float = deg_to_rad(float(def.get("arc_deg", 90.0))) * 0.5
        var diff: float = absf(angle_difference(aim_dir.angle(), d.angle()))
        return diff <= half_arc


## Danno di un colpo di MISCHIA su un nemico del labirinto (frazione HP max,
## come le armi da fuoco) con eventuale potenziamento Corazza del Furore.
static func relic_melee_damage(def: Dictionary, target_max_health: int,
                fury: bool = false) -> int:
        return weapon_damage_for(int(def.get("type", 0)), target_max_health, fury)


## Danno FLAT di mischia vs boss / mini-boss (+1 con la Corazza del Furore).
static func relic_melee_flat_damage(def: Dictionary, fury: bool = false) -> int:
        return maxi(1, int(def.get("power", 1)) + (1 if fury else 0))


## Danno flat del proiettile RIFLESSO dalle Scaglie del Drago: il MIGLIORE
## colpo del player = max(potenza base ROCKET 5, potenza dell'arma corrente).
static func reflect_bolt_power(current_weapon: Dictionary) -> int:
        return maxi(5, int(current_weapon.get("power", 1)))


## TASK 23 (fix bug corazza di fuoco): danno da CONTATTO di un nemico con la
## Corazza di Fuoco equipaggiata. Frazione degli HP max del nemico definita
## da "contact_hits" (default 2: due tocchi per uccidere, coerente con la
## regola "nessuna arma one-shot").
static func relic_aura_contact_damage(armor: Dictionary,
                target_max_health: int) -> int:
        var hits: int = maxi(2, int(armor.get("contact_hits", 2)))
        return maxi(1, int(ceil(float(target_max_health) / float(hits))))


## Nome corto dell'armatura per la HUD ("" se nessuna armatura equipaggiata).
## TASK 44: localizzato — IT usa "short", EN usa "short_en" (mirror statico
## ui_language, stessa convenzione name/name_en delle reliquie).
static func get_armor_short_name(armor: Dictionary) -> String:
        if armor.is_empty():
                return ""
        if ui_is_italian():
                return str(armor.get("short", "ARMATURA"))
        return str(armor.get("short_en", armor.get("short", "ARMOR")))
