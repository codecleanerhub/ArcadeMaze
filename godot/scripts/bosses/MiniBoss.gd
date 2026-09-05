## MiniBoss.gd - Maze mini-boss (1 per level, spawns at the magic portal).
## ============================================================
## Godot port of `src/MiniBoss.{h,cpp}`.
##
## 51 unique types inspired by LOTR + D&D (17), Narnia (7), The Witcher (10),
## Doom (10) and Fantasy hybrids (7). Each type has its own sprite, stats and
## weapon (axe, mace, sword, dagger, chain, club, whip, tentacles).
##
## Stats:
##   * HP:   18..38 + (level - 1) * 3
##   * Size: 32..40 px (must fit in TILE_SIZE=48 corridors)
##   * Speed: 1..2 px/frame (always slower than the player)
##   * Score reward: 5000 + type*300 (so type 0 = 5000, type 50 = 20000)
##
## AI:
##   * BFS pathfinding toward the player (recomputed every 300ms)
##   * Persistent targetPos between BFS calls (smooth movement every frame)
##   * Meele attack: range/weapon-specific, 1.2s cooldown, 400ms swing anim
##   * FLEE mode: when the player is invincible (chalice), the mini-boss
##     runs AWAY (greedy maximum-distance heuristic).
##
## Burning state (player invincibility contact):
##   * startBurning() sets burningTimer = 50 frames (~0.8s)
##   * While burning: the mini-boss is frozen, has a fire-aura overlay
##   * At end of burning: burnedFlag becomes true; Game finalizes death
##   * Because mini-boss HP is 18..38, a single burn deals ~40% HP
##     (2-3 contacts needed to fully kill)
extends Node2D
class_name MiniBoss

# Mirrors C++ enum MiniBossType (51 types).
enum Type {
        MB_GOBLIN_CHIEFTAIN, MB_CAVE_TROLL, MB_ORC_BERSERKER, MB_WARG_RIDER,
        MB_URUK_HAI, MB_NAZGUL, MB_OGRE_BRUTE, MB_GNOLL_PACKLORD,
        MB_BUGBEAR_CHIEF, MB_MINOTAUR, MB_WIGHT_LORD, MB_CAVE_GIANT,
        MB_DEATH_KNIGHT, MB_ILLITHID, MB_ETTIN, MB_FOMORIAN, MB_BALROG_CULTIST,
        MB_FENRIS_WOLF, MB_WHITE_WITCH_GUARD, MB_NARNIA_MINOTAUR,
        MB_DWARF_BERSERKER, MB_WITCH_KNIGHT, MB_TALKING_BEAST, MB_ICE_GIANT_NARNIA,
        MB_LESHEN, MB_BRUXA, MB_KATAKAN, MB_FIEND, MB_WITCHER_GOLEM,
        MB_NOONWRAITH, MB_FOGLET, MB_GRAVE_HAG, MB_MANTICORE_WITCHER,
        MB_CYCLOPS_WITCHER,
        MB_DOOM_IMP, MB_PINKY_DEMON, MB_REVENANT, MB_CACODEMON, MB_HELL_KNIGHT,
        MB_MANCUBUS, MB_ARCHVILE, MB_BARON_OF_HELL, MB_PAIN_ELEMENTAL,
        MB_DOOM_CYBERDEMON,
        MB_SHADOW_ASSASSIN, MB_CRYSTAL_GOLEM, MB_VOID_WALKER, MB_BLOOD_ELEMENTAL,
        MB_STORM_TITAN, MB_PLAGUE_LORD, MB_VOID_SERPENT
}

const MINIBOSS_TYPE_COUNT := 51

enum Weapon {
        MBW_AXE,       # ascia (tagliente, danno medio)
        MBW_MACE,      # mazza (contundente, danno alto)
        MBW_SWORD,     # spada (tagliente, danno medio-alto)
        MBW_DAGGER,    # pugnale (tagliente, danno basso ma veloce)
        MBW_CHAIN,     # catena (contundente, danno alto, raggio lungo)
        MBW_CLUB,      # mazzafrusto (contundente, danno molto alto)
        MBW_WHIP,      # frusta (tagliente, raggio lunghissimo)
        MBW_TENTACLES  # tentacoli (danno medio, effetto mente)
}

# Constants (must match C++ Utils.h)
const TILE_SIZE := 48
const MAZE_COLS := 21
const MAZE_ROWS := 19
const UI_HEIGHT := 80
const WINDOW_WIDTH := 1024
const WINDOW_HEIGHT := 1024

@export var mb_type: int = Type.MB_GOBLIN_CHIEFTAIN
@export var level: int = 1

# Position in pixels (top-left origin, +Y down).
var pos: Vector2 = Vector2.ZERO:
        set(v):
                pos = v
                position = v

var size: int = 32
var speed: int = 2
var health: int = 18
var max_health: int = 18
var weapon: int = Weapon.MBW_AXE
var dx: int = 1
var dy: int = 1

# Timers (in ms, decremented each frame; matches C++).
var path_update_timer_ms: int = 0
var attack_cooldown_ms: int = 0
var attacking_timer_ms: int = 0
var dying_timer_ms: int = 0
var burning_timer_ms: int = 0
var burn_anim_time_ms: int = 0
var anim_time: float = 0.0

# Burning flag (finalization of death).
var burned_flag: bool = false
# Flee mode (player invincible via chalice).
var flee_mode: bool = false

# Persistent movement target (cell center).
var target_pos: Vector2 = Vector2.ZERO
var has_target: bool = false

# Sprite (loaded lazily on first render via SpriteManager).
var sprite_id: String = ""
var sprite_loaded: bool = false
var sprite_sheet = null  # SpriteManager.Sheet

# Maze reference (set by Game). Must expose `is_wall(col, row) -> bool`.
var maze: Node = null


# ----- Signals -----
signal died(miniboss: MiniBoss)
signal burned_out(miniboss: MiniBoss)


# ============================================================
# Factory / Setup
# ============================================================
func setup(t: int, lvl: int, start_col: int, start_row: int) -> void:
        mb_type = t
        level = lvl
        pos = Vector2(start_col * TILE_SIZE + TILE_SIZE / 2.0,
                                  start_row * TILE_SIZE + UI_HEIGHT + TILE_SIZE / 2.0)
        max_health = get_base_health(t) + (level - 1) * 3
        health = max_health
        speed = get_base_speed(t)
        size = get_base_size(t)
        weapon = get_weapon_for_type(t)
        dx = 1 if (randi() % 2 == 0) else -1
        dy = 1 if (randi() % 2 == 0) else -1
        sprite_id = get_sprite_id(t)
        _load_sprite()


func _load_sprite() -> void:
        if SpriteManager == null:
                sprite_loaded = false
                return
        sprite_sheet = SpriteManager.get_sheet(sprite_id)
        sprite_loaded = sprite_sheet != null and sprite_sheet.is_loaded()
        # Apply CharacterArt enhancement shader (strong variant for minibosses)
        # MiniBoss renders via draw_texture_rect on self (CanvasItem), so we
        # apply the material to the node itself rather than a child Sprite2D.
        if CharacterArt:
                CharacterArt.apply_enhancement_to_canvas_item(self, true)


# ============================================================
# Stats tables (mirror C++ MiniBoss::getXxxForType)
# ============================================================

static func get_sprite_id(t: int) -> String:
        # miniboss_01..miniboss_51 (1-based).
        var n := t + 1
        return "miniboss_%02d" % n


static func get_weapon_for_type(t: int) -> int:
        # Compact lookup table indexed by type.
        const TABLE := [
                Weapon.MBW_AXE,       Weapon.MBW_CLUB,      Weapon.MBW_AXE,       Weapon.MBW_SWORD,
                Weapon.MBW_SWORD,     Weapon.MBW_DAGGER,    Weapon.MBW_MACE,      Weapon.MBW_AXE,
                Weapon.MBW_CHAIN,     Weapon.MBW_AXE,       Weapon.MBW_SWORD,     Weapon.MBW_CLUB,
                Weapon.MBW_SWORD,     Weapon.MBW_TENTACLES,  Weapon.MBW_MACE,      Weapon.MBW_CLUB,
                Weapon.MBW_WHIP,
                # Narnia (7)
                Weapon.MBW_CLUB,      Weapon.MBW_SWORD,     Weapon.MBW_AXE,       Weapon.MBW_AXE,
                Weapon.MBW_SWORD,     Weapon.MBW_CLUB,      Weapon.MBW_MACE,
                # Witcher (10)
                Weapon.MBW_TENTACLES, Weapon.MBW_DAGGER,    Weapon.MBW_DAGGER,    Weapon.MBW_MACE,
                Weapon.MBW_MACE,      Weapon.MBW_SWORD,     Weapon.MBW_DAGGER,    Weapon.MBW_DAGGER,
                Weapon.MBW_SWORD,     Weapon.MBW_CLUB,
                # Doom (10)
                Weapon.MBW_DAGGER,    Weapon.MBW_CHAIN,      Weapon.MBW_AXE,       Weapon.MBW_CHAIN,
                Weapon.MBW_MACE,      Weapon.MBW_MACE,       Weapon.MBW_WHIP,      Weapon.MBW_AXE,
                Weapon.MBW_TENTACLES, Weapon.MBW_CHAIN,
                # Hybrids (7)
                Weapon.MBW_DAGGER,    Weapon.MBW_MACE,       Weapon.MBW_DAGGER,    Weapon.MBW_WHIP,
                Weapon.MBW_MACE,      Weapon.MBW_CHAIN,      Weapon.MBW_TENTACLES,
        ]
        if t < 0 or t >= TABLE.size():
                return Weapon.MBW_AXE
        return TABLE[t]


static func get_base_health(t: int) -> int:
        const TABLE := [
                18, 35, 22, 20, 25, 24, 32, 22, 26, 30, 28, 35, 30, 26, 34, 33, 28,  # LOTR/D&D
                28, 26, 30, 24, 28, 26, 35,                                          # Narnia
                30, 24, 28, 35, 34, 26, 24, 22, 32, 36,                              # Witcher
                22, 30, 26, 28, 34, 36, 30, 32, 26, 38,                              # Doom
                24, 34, 28, 30, 36, 32, 30,                                          # Hybrids
        ]
        if t < 0 or t >= TABLE.size():
                return 22
        return TABLE[t]


static func get_base_speed(t: int) -> int:
        const TABLE := [
                2, 1, 2, 2, 2, 2, 1, 2, 2, 2, 2, 1, 2, 2, 1, 1, 2,                  # LOTR/D&D
                2, 2, 2, 2, 2, 2, 1,                                                 # Narnia
                1, 2, 2, 1, 1, 2, 2, 2, 2, 1,                                        # Witcher
                2, 2, 2, 1, 2, 1, 2, 2, 1, 1,                                        # Doom
                2, 1, 2, 2, 1, 1, 2,                                                 # Hybrids
        ]
        if t < 0 or t >= TABLE.size():
                return 2
        return TABLE[t]


static func get_base_size(t: int) -> int:
        # All non-LOTR/D&D types default to 34 (matches C++ default branch).
        const TABLE := [
                32, 40, 34, 36, 34, 36, 38, 32, 36, 38, 36, 40, 36, 34, 40, 40, 36,  # LOTR/D&D
        ]
        if t < 0 or t >= TABLE.size():
                return 34
        return TABLE[t]


func get_attack_damage() -> int:
        match weapon:
                Weapon.MBW_AXE:       return 18
                Weapon.MBW_MACE:      return 22
                Weapon.MBW_SWORD:     return 16
                Weapon.MBW_DAGGER:    return 12
                Weapon.MBW_CHAIN:     return 20
                Weapon.MBW_CLUB:      return 25
                Weapon.MBW_WHIP:      return 15
                Weapon.MBW_TENTACLES: return 14
        return 15


func get_attack_range() -> float:
        match weapon:
                Weapon.MBW_AXE:       return 36.0
                Weapon.MBW_MACE:      return 34.0
                Weapon.MBW_SWORD:     return 38.0
                Weapon.MBW_DAGGER:    return 30.0
                Weapon.MBW_CHAIN:     return 48.0
                Weapon.MBW_CLUB:      return 36.0
                Weapon.MBW_WHIP:      return 56.0
                Weapon.MBW_TENTACLES: return 42.0
        return 34.0


func get_score_reward() -> int:
        return 5000 + mb_type * 300


func is_dead() -> bool:
        return health <= 0


func is_attacking() -> bool:
        return attacking_timer_ms > 0


func is_burning() -> bool:
        return burning_timer_ms > 0


func is_dying() -> bool:
        return dying_timer_ms > 0


func is_fleeing() -> bool:
        return flee_mode


func was_burned() -> bool:
        return burned_flag


func clear_burned_flag() -> void:
        burned_flag = false


func set_flee_mode(flee: bool) -> void:
        flee_mode = flee


func take_damage(dmg: int) -> void:
        health -= dmg
        if health < 0:
                health = 0


# Start burning state (player invincibility contact). 50 frames = ~0.8s.
func start_burning(frames: int = 50) -> void:
        if dying_timer_ms > 0 or burning_timer_ms > 0:
                return
        burning_timer_ms = frames
        burn_anim_time_ms = 0
        burned_flag = true


# ============================================================
# Update
# ============================================================

# `maze_ref` exposes `is_wall(col, row) -> bool`.
# `player_grid_pos` is the player position in maze coordinates.
# `player_pixel_pos` is the player's screen position (for meele range).
func update_step(maze_ref: Node, player_grid_pos: Vector2i,
                player_pixel_pos: Vector2, delta_ms: int) -> void:
        maze = maze_ref
        anim_time += float(delta_ms) * 0.001

        if is_dead():
                if dying_timer_ms > 0:
                        dying_timer_ms = maxi(0, dying_timer_ms - delta_ms)
                return

        # Burning state: frozen, just decrement timer + play fire overlay.
        if burning_timer_ms > 0:
                burning_timer_ms = maxi(0, burning_timer_ms - 1)
                burn_anim_time_ms += delta_ms
                if burning_timer_ms == 0:
                        burned_out.emit(self)
                return

        # Decrement timers.
        if path_update_timer_ms > 0:
                path_update_timer_ms = maxi(0, path_update_timer_ms - delta_ms)
        if attack_cooldown_ms > 0:
                attack_cooldown_ms = maxi(0, attack_cooldown_ms - delta_ms)
        if attacking_timer_ms > 0:
                attacking_timer_ms = maxi(0, attacking_timer_ms - delta_ms)

        # Pathfinding / movement.
        var need_repath := path_update_timer_ms == 0
        if has_target:
                var d := target_pos - pos
                if d.length_squared() < 4.0:
                        need_repath = true

        if need_repath:
                path_update_timer_ms = 300
                var my_grid := Vector2i(int(pos.x) / TILE_SIZE,
                                                           int((pos.y - UI_HEIGHT)) / TILE_SIZE)
                if flee_mode:
                        _flee_greedy(player_grid_pos)
                else:
                        var next := _bfs_path(my_grid, player_grid_pos)
                        if next != Vector2i(-1, -1):
                                target_pos = Vector2(next.x * TILE_SIZE + TILE_SIZE / 2.0,
                                                                         next.y * TILE_SIZE + UI_HEIGHT + TILE_SIZE / 2.0)
                                has_target = true
                                var mv := target_pos - pos
                                if mv.x > 0.1:  dx = 1
                                elif mv.x < -0.1: dx = -1
                                if mv.y > 0.1:  dy = 1
                                elif mv.y < -0.1: dy = -1
                        else:
                                _move_greedy(player_grid_pos)
                                has_target = false

        # Apply movement every frame (smooth).
        if has_target and speed > 0:
                var mv := target_pos - pos
                var dist := mv.length()
                if dist > 0.5:
                        pos += (mv / dist) * float(speed)

        # Meele attack.
        var atk_d := player_pixel_pos - pos
        var atk_dist := atk_d.length()
        if atk_dist < get_attack_range() and attack_cooldown_ms == 0:
                attacking_timer_ms = 400
                attack_cooldown_ms = 1200
                if atk_d.x > 0: dx = 1
                elif atk_d.x < 0: dx = -1
                # Spawn particles? (delegated to Game for performance.)

        position = pos


# ============================================================
# Pathfinding
# ============================================================

# BFS pathfinding toward `target_grid`. Returns the next cell to step into,
# or Vector2i(-1, -1) if no path is found.
func _bfs_path(start: Vector2i, target: Vector2i) -> Vector2i:
        if start == target:
                return Vector2i(-1, -1)
        if maze == null:
                return Vector2i(-1, -1)

        var queue: Array = [[start, Vector2i(-1, -1)]]  # [cell, first_step]
        var visited := {start: true}
        var dirs := [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]
        var iter := 0
        while queue.size() > 0 and iter < 200:
                iter += 1
                var entry: Array = queue.pop_front()
                var cur: Vector2i = entry[0]
                var first: Vector2i = entry[1]
                if cur == target:
                        return first if first != Vector2i(-1, -1) else Vector2i(-1, -1)
                for d in dirs:
                        var next: Vector2i = cur + d
                        if next.x < 0 or next.x >= MAZE_COLS or next.y < 0 or next.y >= MAZE_ROWS:
                                continue
                        if maze.is_wall(next.x, next.y):
                                continue
                        if visited.has(next):
                                continue
                        visited[next] = true
                        var nf: Vector2i = first if first != Vector2i(-1, -1) else next
                        queue.append([next, nf])
        return Vector2i(-1, -1)


func _move_greedy(target_grid: Vector2i) -> void:
        var dirs: Array[Vector2i] = [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]
        var my_col := int(pos.x) / TILE_SIZE
        var my_row := int((pos.y - UI_HEIGHT)) / TILE_SIZE
        var best_dist := absi(target_grid.x - my_col) + absi(target_grid.y - my_row)
        var best_dx := 0
        var best_dy := 0
        for d in dirs:
                var nc: int = my_col + d.x
                var nr: int = my_row + d.y
                if nc < 0 or nc >= MAZE_COLS or nr < 0 or nr >= MAZE_ROWS:
                        continue
                if maze != null and maze.is_wall(nc, nr):
                        continue
                var dist := absi(target_grid.x - nc) + absi(target_grid.y - nr)
                if dist < best_dist:
                        best_dist = dist
                        best_dx = d.x
                        best_dy = d.y
        pos.x += float(best_dx) * float(speed)
        pos.y += float(best_dy) * float(speed)
        if best_dx > 0:  dx = 1
        elif best_dx < 0: dx = -1
        if best_dy > 0:  dy = 1
        elif best_dy < 0: dy = -1


func _flee_greedy(target_grid: Vector2i) -> void:
        var dirs: Array[Vector2i] = [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]
        var my_col := int(pos.x) / TILE_SIZE
        var my_row := int((pos.y - UI_HEIGHT)) / TILE_SIZE
        var cur_dist := absi(target_grid.x - my_col) + absi(target_grid.y - my_row)
        var best_dist := cur_dist
        var best_dx := 0
        var best_dy := 0
        for d in dirs:
                var nc: int = my_col + d.x
                var nr: int = my_row + d.y
                if nc < 0 or nc >= MAZE_COLS or nr < 0 or nr >= MAZE_ROWS:
                        continue
                if maze != null and maze.is_wall(nc, nr):
                        continue
                var dist := absi(target_grid.x - nc) + absi(target_grid.y - nr)
                if dist > best_dist:
                        best_dist = dist
                        best_dx = d.x
                        best_dy = d.y
        if best_dx != 0 or best_dy != 0:
                target_pos = Vector2((my_col + best_dx) * TILE_SIZE + TILE_SIZE / 2.0,
                                                         (my_row + best_dy) * TILE_SIZE + UI_HEIGHT + TILE_SIZE / 2.0)
                has_target = true
                if best_dx > 0:  dx = 1
                elif best_dx < 0: dx = -1
                if best_dy > 0:  dy = 1
                elif best_dy < 0: dy = -1


# ============================================================
# Rendering
# ============================================================

func _draw() -> void:
        if sprite_loaded and sprite_sheet != null:
                _draw_with_sprite()
        else:
                _draw_primitives()
        # Weapon swing overlay (when attacking) - drawn on top of the body so
        # the weapon appears in front of the mini-boss during the swing arc.
        # Mirrors the C++ weapon branch in src/MiniBoss.cpp line 199-308.
        if attacking_timer_ms > 0:
                _draw_weapon_swing(weapon, _get_facing_angle())
        # Burning overlay always on top.
        if burning_timer_ms > 0:
                _draw_burning_overlay()


# Facing angle (radians): 0.0 = right, PI = left. Used by _draw_weapon_swing
# to flip the weapon to the side the mini-boss is facing.
func _get_facing_angle() -> float:
        if dx < 0:
                return PI
        return 0.0


func _draw_with_sprite() -> void:
        var scale_val := float(size) / 64.0
        if scale_val < 1.0:
                scale_val = 1.0
        var bob_y := sin(anim_time * 3.0) * 1.0
        var flipped := dx < 0

        # Animation: death > attack > walk > idle
        var anim_name := "idle"
        var frame := 0
        var frame_duration := 200
        if dying_timer_ms > 0 and sprite_sheet.get_frame_count("death") > 0:
                anim_name = "death"
                frame_duration = 120
                var elapsed := 600 - dying_timer_ms
                var fc: int = sprite_sheet.get_frame_count("death")
                frame = elapsed / frame_duration
                frame = clampi(frame, 0, fc - 1)
        elif attacking_timer_ms > 0 and sprite_sheet.get_frame_count("attack") > 0:
                anim_name = "attack"
                frame_duration = 50
                var elapsed := 400 - attacking_timer_ms
                var fc: int = sprite_sheet.get_frame_count("attack")
                frame = elapsed / frame_duration
                frame = clampi(frame, 0, fc - 1)
        elif (dx != 0 or dy != 0) and sprite_sheet.get_frame_count("walk") > 0:
                anim_name = "walk"
                frame_duration = 100
                var fc: int = sprite_sheet.get_frame_count("walk")
                frame = (int(anim_time * 1000.0) / frame_duration) % fc
        elif sprite_sheet.get_frame_count("idle") > 0:
                anim_name = "idle"
                frame = 0

        var at: AtlasTexture = null
        if sprite_sheet != null:
                at = sprite_sheet.get_frame_texture(anim_name, frame)
        if at != null:
                # Centered draw with vertical bob. Flip horizontally via src_rect.
                var tw: int = 64  # mini-boss visual size (HD sheet scaled down)
                var th: int = 64
                var draw_pos := Vector2(-tw / 2, -th / 2 + 8 + bob_y)
                var dest_rect := Rect2(draw_pos, Vector2(tw, th))
                if flipped:
                        # Flip using transpose (Godot 4.7 max 5 args on draw_texture_rect)
                        draw_texture_rect(at, dest_rect, false, Color.WHITE, true)
                else:
                        draw_texture_rect(at, dest_rect, false)

        # Aura (accent color per type).
        var accent := _get_accent_color()
        var aura_r := float(size) * 0.7 * scale_val + sin(anim_time * 2.0) * 2.0
        draw_circle(Vector2(0, 0), aura_r, Color(accent.r, accent.g, accent.b, 0.15))

        # HP bar (always visible, always red).
        _draw_hp_bar(scale_val)

        # Shadow.
        var sh_r := float(size) * 0.4 * scale_val
        draw_circle(Vector2(0, float(size) * scale_val * 0.5), sh_r,
                                Color(0.05, 0.05, 0.05, 0.4))


func _get_accent_color() -> Color:
        match mb_type:
                Type.MB_GOBLIN_CHIEFTAIN: return Color(0.86, 0.63, 0.16)
                Type.MB_CAVE_TROLL:       return Color(0.78, 0.71, 0.63)
                Type.MB_ORC_BERSERKER:    return Color(0.63, 0.16, 0.16)
                Type.MB_WARG_RIDER:       return Color(0.78, 0.71, 0.63)
                Type.MB_URUK_HAI:         return Color(0.78, 0.31, 0.31)
                Type.MB_NAZGUL:           return Color(0.63, 0.16, 0.16)
                Type.MB_OGRE_BRUTE:       return Color(0.63, 0.50, 0.44)
                Type.MB_GNOLL_PACKLORD:   return Color(0.86, 0.63, 0.16)
                Type.MB_BUGBEAR_CHIEF:    return Color(0.19, 0.16, 0.14)
                Type.MB_MINOTAUR:         return Color(0.86, 0.63, 0.16)
                Type.MB_WIGHT_LORD:       return Color(0.47, 0.78, 0.78)
                Type.MB_CAVE_GIANT:       return Color(0.78, 0.71, 0.63)
                Type.MB_DEATH_KNIGHT:     return Color(0.47, 0.78, 0.78)
                Type.MB_ILLITHID:         return Color(0.63, 0.47, 0.78)
                Type.MB_ETTIN:            return Color(0.63, 0.16, 0.16)
                Type.MB_FOMORIAN:         return Color(0.19, 0.16, 0.14)
                Type.MB_BALROG_CULTIST:   return Color(0.86, 0.63, 0.16)
                # Narnia + Witcher + Doom + Hybrids default to gold.
                _: return Color(0.86, 0.63, 0.16)


func _draw_hp_bar(scale_val: float) -> void:
        var bar_w := float(size) * 0.9 * scale_val
        var bar_h := 4.0
        var bar_y := -float(size) * scale_val * 0.5 - 35.0
        draw_rect(Rect2(-bar_w * 0.5, bar_y, bar_w, bar_h), Color(0.05, 0.05, 0.05))
        var ratio := float(health) / float(max_health)
        if ratio < 0.0: ratio = 0.0
        var hp_col := Color(0.86, 0.24, 0.24) if ratio > 0.5 else Color(0.63, 0.16, 0.16)
        draw_rect(Rect2(-bar_w * 0.5, bar_y, bar_w * ratio, bar_h), hp_col)


# Procedural fallback (mirrors C++ renderPrimitives at src/MiniBoss.cpp:582-776).
# Draws aura, body, head, eyes, then type-specific details for the 17 main
# LOTR/D&D mini-boss types via `match mb_type:`. Each branch adds 1-4
# distinctive features (ears, horns, crown, cloak, tentacles, second head,
# fire aura, etc.) so the procedural fallback is still distinguishable per
# type even when the AI-generated sprite sheet is missing.
func _draw_primitives() -> void:
        var body_col := _get_body_color()
        var accent := _get_accent_color()
        var breath := sin(anim_time * 3.0) * 1.0

        # Aura
        var aura_r := float(size) * 0.7 + sin(anim_time * 2.0) * 2.0
        draw_circle(Vector2.ZERO, aura_r, Color(accent.r, accent.g, accent.b, 0.15))

        # Body
        var body_w := float(size) * 0.7
        var body_h := float(size) * 0.9
        draw_rect(Rect2(-body_w * 0.5, -body_h * 0.5 + 2, body_w, body_h + breath), body_col)

        # Head
        var head_r := float(size) * 0.25
        var head_y := -body_h * 0.5 - head_r * 0.3
        draw_circle(Vector2(0, head_y), head_r, body_col)

        # Eyes
        var eye_r := 1.5
        draw_circle(Vector2(-head_r * 0.5, head_y), eye_r, accent)
        draw_circle(Vector2(head_r * 0.5, head_y), eye_r, accent)

        # --- Type-specific details (17 LOTR/D&D mini-boss types) ---
        match mb_type:
                Type.MB_GOBLIN_CHIEFTAIN:
                        # Orecchie appuntite + corona d'oro
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(-head_r, head_y - 2),
                                Vector2(-head_r - 6, head_y - 4),
                                Vector2(-head_r + 2, head_y + 4),
                        ]), body_col)
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(head_r, head_y - 2),
                                Vector2(head_r + 6, head_y - 4),
                                Vector2(head_r - 2, head_y + 4),
                        ]), body_col)
                        draw_rect(Rect2(-head_r, head_y - head_r - 4,
                                        head_r * 2.0, 3.0), Color(0.86, 0.63, 0.16))
                        for i in 3:
                                draw_colored_polygon(PackedVector2Array([
                                        Vector2(-head_r + i * head_r - 1.0, head_y - head_r - 4),
                                        Vector2(-head_r + i * head_r + 1.0, head_y - head_r - 4),
                                        Vector2(-head_r + i * head_r, head_y - head_r - 8),
                                ]), Color(1.0, 0.86, 0.16))
                Type.MB_CAVE_TROLL:
                        # Grosso + grigio: extra bulk + zanne
                        draw_rect(Rect2(-body_w * 0.5 - 3, -body_h * 0.4, 3, body_h * 0.8), body_col)
                        draw_rect(Rect2(body_w * 0.5, -body_h * 0.4, 3, body_h * 0.8), body_col)
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(-head_r * 0.5, head_y + head_r * 0.5),
                                Vector2(-head_r * 0.7, head_y + head_r * 1.2),
                                Vector2(-head_r * 0.2, head_y + head_r * 0.5),
                        ]), Color(0.78, 0.78, 0.71))
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(head_r * 0.5, head_y + head_r * 0.5),
                                Vector2(head_r * 0.7, head_y + head_r * 1.2),
                                Vector2(head_r * 0.2, head_y + head_r * 0.5),
                        ]), Color(0.78, 0.78, 0.71))
                Type.MB_ORC_BERSERKER:
                        # Orecchie + cicatrici + frothing
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(-head_r, head_y - 2),
                                Vector2(-head_r - 6, head_y - 4),
                                Vector2(-head_r + 2, head_y + 4),
                        ]), body_col)
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(head_r, head_y - 2),
                                Vector2(head_r + 6, head_y - 4),
                                Vector2(head_r - 2, head_y + 4),
                        ]), body_col)
                        draw_line(Vector2(-head_r * 0.5, head_y - head_r * 0.5),
                                Vector2(head_r * 0.5, head_y + head_r * 0.5),
                                Color(0.86, 0.31, 0.31), 1)
                        draw_circle(Vector2(0, head_y + head_r * 0.7), 2,
                                Color(1.0, 1.0, 1.0, 0.78))
                        draw_circle(Vector2(-2, head_y + head_r * 0.8), 1.5,
                                Color(1.0, 1.0, 1.0, 0.78))
                        draw_circle(Vector2(2, head_y + head_r * 0.8), 1.5,
                                Color(1.0, 1.0, 1.0, 0.78))
                Type.MB_WARG_RIDER:
                        # Cavaliere su lupo: corpo lupo sotto + orecchie + occhio rosso
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(-body_w * 0.7, body_h * 0.4),
                                Vector2(-body_w * 0.3, body_h * 0.5),
                                Vector2(body_w * 0.3, body_h * 0.5),
                                Vector2(body_w * 0.7, body_h * 0.4),
                                Vector2(body_w * 0.8, body_h * 0.6),
                                Vector2(-body_w * 0.8, body_h * 0.6),
                        ]), Color(0.16, 0.16, 0.16))
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(-body_w * 0.6, body_h * 0.4),
                                Vector2(-body_w * 0.7, body_h * 0.3),
                                Vector2(-body_w * 0.5, body_h * 0.45),
                        ]), Color(0.16, 0.16, 0.16))
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(body_w * 0.6, body_h * 0.4),
                                Vector2(body_w * 0.7, body_h * 0.3),
                                Vector2(body_w * 0.5, body_h * 0.45),
                        ]), Color(0.16, 0.16, 0.16))
                        draw_circle(Vector2(body_w * 0.55, body_h * 0.45), 1.5,
                                Color(1.0, 0.2, 0.0))
                Type.MB_URUK_HAI:
                        # Marchio bianco sulla fronte (linea verticale)
                        draw_rect(Rect2(-1, head_y - head_r * 0.8, 2, head_r),
                                Color(0.94, 0.94, 0.94))
                Type.MB_NAZGUL:
                        # Mantello nero incappucciato
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(0, head_y - head_r),
                                Vector2(body_w * 0.9, body_h * 0.5),
                                Vector2(-body_w * 0.9, body_h * 0.5),
                        ]), Color(0.05, 0.05, 0.05, 0.86))
                        draw_circle(Vector2(0, head_y), head_r, Color(0.02, 0.02, 0.02))
                Type.MB_OGRE_BRUTE:
                        # Grosso ventre
                        draw_circle(Vector2(0, body_h * 0.2), body_w * 0.55, body_col)
                        draw_circle(Vector2(0, body_h * 0.2), 1.5,
                                Color(0.16, 0.12, 0.08))
                Type.MB_GNOLL_PACKLORD:
                        # Testa iena: muso elongato + orecchie + criniera
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(head_r, head_y - 1),
                                Vector2(head_r + 8, head_y),
                                Vector2(head_r, head_y + 3),
                        ]), body_col)
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(-head_r, head_y - 2),
                                Vector2(-head_r - 5, head_y - 6),
                                Vector2(-head_r, head_y + 2),
                        ]), body_col)
                        for i in 3:
                                var mx: float = -head_r * 0.5 + i * head_r * 0.4
                                draw_colored_polygon(PackedVector2Array([
                                        Vector2(mx, head_y - head_r),
                                        Vector2(mx + 2, head_y - head_r),
                                        Vector2(mx + 1, head_y - head_r - 4),
                                ]), accent)
                Type.MB_BUGBEAR_CHIEF:
                        # Pelliccia (zigzag outline laterale)
                        for i in 6:
                                var fy: float = -body_h * 0.4 + i * body_h * 0.16
                                draw_colored_polygon(PackedVector2Array([
                                        Vector2(-body_w * 0.5, fy),
                                        Vector2(-body_w * 0.5 - 4, fy + 2),
                                        Vector2(-body_w * 0.5 - 2, fy + 4),
                                        Vector2(-body_w * 0.5, fy + 6),
                                ]), Color(0.27, 0.20, 0.16))
                                draw_colored_polygon(PackedVector2Array([
                                        Vector2(body_w * 0.5, fy),
                                        Vector2(body_w * 0.5 + 4, fy + 2),
                                        Vector2(body_w * 0.5 + 2, fy + 4),
                                        Vector2(body_w * 0.5, fy + 6),
                                ]), Color(0.27, 0.20, 0.16))
                Type.MB_MINOTAUR:
                        # Testa toro: corna + muso
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(-head_r * 0.7, head_y - head_r * 0.5),
                                Vector2(-head_r * 1.6, head_y - head_r * 1.4),
                                Vector2(-head_r * 0.4, head_y - head_r * 0.5),
                        ]), Color(0.78, 0.78, 0.71))
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(head_r * 0.7, head_y - head_r * 0.5),
                                Vector2(head_r * 1.6, head_y - head_r * 1.4),
                                Vector2(head_r * 0.4, head_y - head_r * 0.5),
                        ]), Color(0.78, 0.78, 0.71))
                        draw_rect(Rect2(-3, head_y + head_r * 0.5, 6, 4), body_col)
                Type.MB_WIGHT_LORD:
                        # Armatura spettrale (semi-trasparente + runa glowing)
                        draw_rect(Rect2(-body_w * 0.4, -body_h * 0.3,
                                        body_w * 0.8, body_h * 0.6),
                                Color(accent.r, accent.g, accent.b, 0.3))
                        draw_circle(Vector2(0, 0), 2,
                                Color(0.47, 0.86, 0.86, 0.9))
                Type.MB_CAVE_GIANT:
                        # Grosso + primitivo: extra bulk + mazza
                        draw_rect(Rect2(-body_w * 0.6, -body_h * 0.4,
                                        body_w * 1.2, body_h * 0.8),
                                Color(body_col.r, body_col.g, body_col.b, 0.5))
                        draw_rect(Rect2(body_w * 0.5, -body_h * 0.3, 6, body_h * 0.7),
                                Color(0.39, 0.27, 0.13))
                Type.MB_DEATH_KNIGHT:
                        # Elmo teschio
                        draw_rect(Rect2(-head_r, head_y - head_r,
                                        head_r * 2.0, head_r * 2.0),
                                Color(0.94, 0.94, 0.86))
                        draw_circle(Vector2(-head_r * 0.4, head_y), 2, Color(0.02, 0.02, 0.02))
                        draw_circle(Vector2(head_r * 0.4, head_y), 2, Color(0.02, 0.02, 0.02))
                        draw_rect(Rect2(-head_r * 0.6, head_y + head_r * 0.5,
                                        head_r * 1.2, 2), Color(0.05, 0.05, 0.05))
                Type.MB_ILLITHID:
                        # Tentacoli facciali (4 piccoli attorno alla bocca)
                        for i in 4:
                                var ang: float = (i - 1.5) * 0.4
                                var bx: float = cos(ang) * head_r * 0.7
                                var by: float = head_y + head_r * 0.3 + sin(ang) * head_r * 0.3
                                draw_line(Vector2(bx, by),
                                        Vector2(bx + cos(ang) * 6, by + 6),
                                        body_col, 1.5)
                Type.MB_ETTIN:
                        # Due teste: seconda testa piu' piccola a destra
                        var head2_r := head_r * 0.8
                        var head2_x := head_r + head2_r
                        draw_circle(Vector2(head2_x, head_y - head2_r * 0.3),
                                head2_r, body_col)
                        draw_circle(Vector2(head2_x - head2_r * 0.5,
                                        head_y - head2_r * 0.3), eye_r, accent)
                Type.MB_FOMORIAN:
                        # Deforme + un occhio
                        draw_circle(Vector2(0, head_y), head_r * 0.6, Color(1.0, 1.0, 1.0))
                        draw_circle(Vector2(0, head_y), head_r * 0.4,
                                Color(0.08, 0.08, 0.16))
                        draw_circle(Vector2(0, head_y), head_r * 0.2, Color(0.0, 0.0, 0.0))
                Type.MB_BALROG_CULTIST:
                        # Aura di fuoco (6 fiamme pulsanti attorno)
                        for i in 6:
                                var fang: float = (i / 6.0) * TAU + anim_time * 2.0
                                var fr: float = float(size) * 0.55 + sin(anim_time * 4.0 + i) * 3.0
                                draw_circle(Vector2(cos(fang) * fr, sin(fang) * fr),
                                        2.5, Color(1.0, 0.63, 0.16, 0.86))
                _:
                        pass

        # HP bar
        _draw_hp_bar(1.0)


# ===========================================================================
# _draw_weapon_swing(weapon_type, angle): draws the equipped weapon in the
# mini-boss's hand during the attack animation (attacking_timer_ms > 0).
# The `angle` parameter (radians) orients the weapon: 0.0 = facing right,
# PI = facing left (mirrored). Mirrors the C++ weapon branch in
# src/MiniBoss.cpp line 199-308 (8 weapon types).
# ===========================================================================
func _draw_weapon_swing(weapon_type: int, angle: float) -> void:
        # Weapon anchor: to the right of the body when angle ~ 0, mirrored when
        # angle ~ PI. A small wobble simulates the swing motion.
        var body_w := float(size) * 0.7
        var facing_left := absf(angle - PI) < 0.5
        var dir_x := -1.0 if facing_left else 1.0
        var swing_off := sin((400.0 - float(attacking_timer_ms)) * 0.02) * 2.0
        var wx: float = dir_x * (body_w * 0.6 + swing_off)
        var wy: float = 0.0
        var col_dark := Color(0.19, 0.16, 0.14)
        var col_pale := Color(0.78, 0.71, 0.63)
        var col_mid := Color(0.38, 0.31, 0.28)
        var col_gold := Color(0.86, 0.63, 0.16)
        match weapon_type:
                Weapon.MBW_AXE:
                        # Manico + lama triangolare
                        draw_rect(Rect2(wx, wy - 6, 1.5, 12), col_dark)
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(wx, wy - 6),
                                Vector2(wx + dir_x * 8, wy - 4),
                                Vector2(wx + dir_x * 1, wy + 2),
                        ]), col_pale)
                Weapon.MBW_MACE, Weapon.MBW_CLUB:
                        # Manico + testa sferica con spuntoni
                        draw_rect(Rect2(wx, wy - 7, 1.5, 14), col_dark)
                        draw_circle(Vector2(wx, wy - 9), 4, col_mid)
                        for i in 6:
                                var sa: float = i * PI / 3.0
                                draw_colored_polygon(PackedVector2Array([
                                        Vector2(wx + cos(sa) * 4, wy - 9 + sin(sa) * 4),
                                        Vector2(wx + cos(sa) * 6, wy - 9 + sin(sa) * 6),
                                        Vector2(wx + cos(sa) * 4.5, wy - 9 + sin(sa) * 4.5),
                                ]), col_pale)
                Weapon.MBW_SWORD:
                        # Lama dritta + elsa
                        draw_rect(Rect2(wx, wy - 12, 1.5, 14), col_pale)
                        draw_rect(Rect2(wx - 1.5, wy + 1, 5, 1.5), col_gold)
                Weapon.MBW_DAGGER:
                        # Pugnale corto + guardia
                        draw_rect(Rect2(wx, wy - 6, 1.2, 8), col_pale)
                        draw_rect(Rect2(wx - 0.9, wy + 1, 3, 1), col_gold)
                Weapon.MBW_CHAIN:
                        # Catena (3 anelli) + palla
                        for i in 3:
                                draw_circle(Vector2(wx + dir_x * i * 4, wy - 6), 1.5, col_dark)
                        draw_circle(Vector2(wx + dir_x * 12, wy - 9.5), 3.5, col_mid)
                Weapon.MBW_WHIP:
                        # Frusta (4 segmenti curvi)
                        for i in 4:
                                var seg_y: float = wy - 8 + i * 4
                                draw_rect(Rect2(wx + dir_x * i * 2, seg_y, 1, 4), col_dark)
                Weapon.MBW_TENTACLES:
                        # Tentacoli gia' disegnati come dettaglio del tipo (ILLITHID).
                        pass
                _:
                        pass


func _get_body_color() -> Color:
        match mb_type:
                Type.MB_GOBLIN_CHIEFTAIN: return Color(0.16, 0.31, 0.24)
                Type.MB_CAVE_TROLL:       return Color(0.38, 0.31, 0.28)
                Type.MB_ORC_BERSERKER:    return Color(0.16, 0.31, 0.24)
                Type.MB_WARG_RIDER:       return Color(0.19, 0.16, 0.14)
                Type.MB_URUK_HAI:         return Color(0.19, 0.16, 0.14)
                Type.MB_NAZGUL:           return Color(0.05, 0.05, 0.05)
                Type.MB_OGRE_BRUTE:       return Color(0.38, 0.31, 0.28)
                Type.MB_GNOLL_PACKLORD:   return Color(0.63, 0.50, 0.44)
                Type.MB_BUGBEAR_CHIEF:    return Color(0.38, 0.31, 0.28)
                Type.MB_MINOTAUR:         return Color(0.19, 0.16, 0.14)
                Type.MB_WIGHT_LORD:       return Color(0.16, 0.31, 0.24)
                Type.MB_CAVE_GIANT:       return Color(0.38, 0.31, 0.28)
                Type.MB_DEATH_KNIGHT:     return Color(0.05, 0.05, 0.05)
                Type.MB_ILLITHID:         return Color(0.63, 0.47, 0.78)
                Type.MB_ETTIN:            return Color(0.38, 0.31, 0.28)
                Type.MB_FOMORIAN:         return Color(0.38, 0.31, 0.28)
                Type.MB_BALROG_CULTIST:   return Color(0.63, 0.16, 0.16)
                _: return Color(0.38, 0.31, 0.28)


func _draw_burning_overlay() -> void:
        # Fire aura: 3 radial glow layers + flames + sparks.
        var burn_progress := 1.0 - float(burning_timer_ms) / 50.0
        var intensity := 1.0
        if burn_progress < 0.2:
                intensity = 0.5 + burn_progress * 2.5
        elif burn_progress > 0.8:
                intensity = 1.0 - (burn_progress - 0.8) * 1.5
        intensity = max(0.3, intensity)

        var pulse := 1.0 + sin(burn_anim_time_ms * 0.02) * 0.1
        var cy := -8.0  # center of the mini-boss body

        # Outer / mid / inner glow
        draw_circle(Vector2(0, cy), 28.0 * pulse,
                                Color(1.0, 0.39, 0.0, 0.35 * intensity))
        draw_circle(Vector2(0, cy), 20.0 * pulse,
                                Color(0.78, 0.31, 0.31, 0.47 * intensity))
        draw_circle(Vector2(0, cy), 12.0 * pulse,
                                Color(0.86, 0.63, 0.16, 0.63 * intensity))

        # 8 procedural flames around the body.
        for i in range(8):
                var a := (float(i) / 8.0) * TAU + burn_anim_time_ms * 0.005
                var ring_r := 18.0
                var fx := cos(a) * ring_r
                var fy := cy + sin(a) * ring_r
                var flame_h := (10.0 + sin(burn_anim_time_ms * 0.02 + i * 0.7) * 5.0 + 5.0) * intensity
                var flame_w := 4.0
                draw_colored_polygon(PackedVector2Array([
                        Vector2(fx - flame_w, fy),
                        Vector2(fx + flame_w, fy),
                        Vector2(fx + sin(burn_anim_time_ms * 0.02 + i) * 3.0, fy - flame_h),
                ]), Color(0.86, 0.63, 0.16, 0.86 * intensity))

        # 4 white sparks.
        for i in range(4):
                var sx := sin(burn_anim_time_ms * 0.015 + i * 1.2) * 12.0
                var sy := cy - 10.0 - float((int(burn_anim_time_ms * 0.2 + i * 8)) % 30)
                draw_circle(Vector2(sx, sy), 1.2, Color(1.0, 1.0, 1.0, 0.86 * intensity))

        # 3 smoke particles.
        for i in range(3):
                var sx := sin(burn_anim_time_ms * 0.01 + i * 2.0) * 8.0
                var sy := cy - 15.0 - float((int(burn_anim_time_ms * 0.15 + i * 15)) % 40)
                draw_circle(Vector2(sx, sy), 2.5 + i * 0.5,
                                        Color(0.71, 0.67, 0.63, 0.43 * intensity))
