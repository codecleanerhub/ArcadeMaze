## MainGameController.gd
## ============================================================
## The central gameplay orchestrator for maze levels.
##
## This is the Godot equivalent of the C++ Game::update() STATE_PLAYING
## branch (Game.cpp lines 1556-2718). It:
##   - Reads P1/P2 input
##   - Calls player.update_player() / enemy.update_enemy()
##   - Handles collisions (projectile-enemy, enemy-player, etc.)
##   - Manages projectiles, exit door, magic portal
##   - Transitions to boss fight / next level
##   - Updates HUD
##   - Handles pause / test mode
##
## Attach this script to the root node of MainGame.tscn.
## ============================================================
extends Node2D

const C = preload("res://scripts/core/GameConstants.gd")
const WeaponClass = preload("res://scripts/items/Weapon.gd")
const CollectiblesClass = preload("res://scripts/items/Collectibles.gd")

# --- Node references (assigned in _ready) ---
@onready var maze: Node2D = $Maze
@onready var player: CharacterBody2D = $Player
@onready var player2: CharacterBody2D = $Player2
@onready var spawner: Node2D = $Enemies
@onready var projectiles_node: Node2D = $Projectiles
@onready var enemy_projectiles_node: Node2D = $EnemyProjectiles
@onready var collectibles_node: Node2D = $Collectibles
@onready var hud: Control = $HUD

# --- Game state ---
var current_level: int = 1
var is_boss_state: bool = false  # false in MainGame (maze), true in BossRoom
var is_paused: bool = false
var test_skip_key_held: bool = false

# --- Collectibles (port of C++ Game members) ---
var exit_door: Dictionary = {
        "pos": Vector2.ZERO,
        "active": false,
        "anim_timer_ms": 0,
        "glow_pulse": 0.0,
}

var magic_portal: Dictionary = {
        "pos": Vector2.ZERO,
        "active": false,
        "phase": 3,  # 0=open, 1=spawn, 2=close, 3=idle
        "phase_timer_ms": 0,
        "rotation": 0.0,
        "glow_pulse": 0.0,
        "enemies_to_spawn": 0,
        "spawn_timer_ms": 0,
}

var portal_used: bool = false
var initial_enemy_count: int = 0

# Items spawned per level
var chalice_item: Node2D = null
var scepter_item: Node2D = null
var mine_item: Node2D = null
var speed_boots_item: Node2D = null
var speed_boots2_item: Node2D = null  # P2 only

# Timers
var player_invincible_timer_ms: int = 0
var player2_invincible_timer_ms: int = 0
var screen_flash_timer_ms: int = 0

# Particles (simple visual feedback)
var particles: Array = []

# Frame delta in ms (for timer decrements matching C++ @ 60 FPS)
const FRAME_MS: float = 1000.0 / 60.0


# ============================================================================
# Lifecycle
# ============================================================================
func _ready() -> void:
        # Configure player characters from GameManager
        if GameManager:
                current_level = GameManager.current_level
                if current_level <= 0:
                        current_level = 1
        player.set_character(GameManager.player1_character, 1)
        if GameManager.num_players == 2:
                player2.set_character(GameManager.player2_character, 2)
                player2.visible = true
        else:
                player2.visible = false
        # Start the first level
        start_level(current_level)
        # Start level music if enabled
        if AudioManager and GameManager.music_enabled:
                AudioManager.play_level_music(current_level, false)
        # Aggiungi post-processing vignette (vantaggio Godot)
        if EffectsManager:
                var vignette := EffectsManager.create_vignette_rect()
                add_child(vignette)


func _physics_process(_delta: float) -> void:
        if is_paused:
                return
        var delta_ms: float = _delta * 1000.0
        # Clamp delta to avoid huge jumps on lag spikes (mirrors 60 FPS assumption)
        delta_ms = min(delta_ms, 50.0)

        _handle_input()
        _update_playing(delta_ms)
        _update_hud()


# ============================================================================
# Input handling
# ============================================================================
func _handle_input() -> void:
        # P1 keyboard arrows (mutually exclusive, dominant axis wins)
        var p1_dx: int = 0
        var p1_dy: int = 0
        if Input.is_action_pressed("move_up"):
                p1_dy = -1
        elif Input.is_action_pressed("move_down"):
                p1_dy = 1
        elif Input.is_action_pressed("move_left"):
                p1_dx = -1
        elif Input.is_action_pressed("move_right"):
                p1_dx = 1
        player.set_direction(p1_dx, p1_dy)

        # P1 shoot
        if Input.is_action_just_pressed("shoot") and player.shoot_cooldown == 0:
                var ammo_before: int = player.current_weapon.get("ammo", 0)
                player.shoot()
                var ammo_after: int = player.current_weapon.get("ammo", 0)
                if ammo_after < ammo_before and AudioManager:
                        AudioManager.play_sound(AudioManager.SoundType.SHOOT)
                player.shoot_cooldown = 150

        # P1 jump
        if Input.is_action_just_pressed("jump"):
                var was_jumping: bool = player.is_jumping()
                player.activate_jump()
                if not was_jumping and player.is_jumping() and AudioManager:
                        AudioManager.play_sound(AudioManager.SoundType.JUMP)

        # P2 input (if 2 players)
        if GameManager and GameManager.num_players == 2 and player2.visible:
                var p2_dx: int = 0
                var p2_dy: int = 0
                # P2 uses WASD via secondary input actions (fallback to arrows
                # if no separate mapping exists - Godot Input map)
                if Input.is_action_pressed("p2_up"):
                        p2_dy = -1
                elif Input.is_action_pressed("p2_down"):
                        p2_dy = 1
                elif Input.is_action_pressed("p2_left"):
                        p2_dx = -1
                elif Input.is_action_pressed("p2_right"):
                        p2_dx = 1
                player2.set_direction(p2_dx, p2_dy)
                if Input.is_action_just_pressed("p2_shoot") and player2.shoot_cooldown == 0:
                        player2.shoot()
                        player2.shoot_cooldown = 150
                if Input.is_action_just_pressed("p2_jump"):
                        player2.activate_jump()

        # Pause toggle (P key)
        if Input.is_action_just_pressed("pause"):
                _toggle_pause()

        # Test mode skip (Space)
        if GameManager and GameManager.test_mode_enabled:
                var space_now: bool = Input.is_key_pressed(KEY_SPACE)
                if space_now and not test_skip_key_held:
                        _test_mode_skip()
                test_skip_key_held = space_now


# ============================================================================
# Main update loop (STATE_PLAYING)
# ============================================================================
func _update_playing(delta_ms: float) -> void:
        # (1) Player update + treasure pickup detection
        var treasures_before: int = maze.get_remaining_treasures()
        player.update_player(maze, false)
        if player.consume_picked_weapon():
                if AudioManager:
                        AudioManager.play_sound(AudioManager.SoundType.WEAPON_PICKUP)
        if GameManager and GameManager.num_players == 2 and player2.visible:
                player2.update_player(maze, false)
                if player2.consume_picked_weapon() and AudioManager:
                        AudioManager.play_sound(AudioManager.SoundType.WEAPON_PICKUP)
        if maze.get_remaining_treasures() < treasures_before:
                if AudioManager:
                        AudioManager.play_sound(AudioManager.SoundType.TREASURE)

        # (2) Enemies update
        var p_pos: Vector2 = player.get_pixel_pos()
        var p_grid: Vector2i = player.get_grid_pos()
        var player_invuln: bool = player.is_invulnerable()
        for enemy in spawner.enemies:
                if not enemy.is_death_anim_done():
                        enemy.set_flee_mode(player_invuln)
                        enemy.update_enemy(maze, p_grid, p_pos, enemy_projectiles_node)

        # (3) Advance enemy projectiles
        _advance_projectiles(enemy_projectiles_node, delta_ms)

        # (4) Player projectiles vs enemies
        _check_player_projectiles_vs_enemies(player)
        if GameManager and GameManager.num_players == 2 and player2.visible:
                _check_player_projectiles_vs_enemies(player2)

        # (5) Enemy projectiles vs player
        if not player.is_invulnerable() and not player.is_jumping():
                _check_enemy_projectiles_vs_player(player)
        if GameManager and GameManager.num_players == 2 and player2.visible:
                if not player2.is_invulnerable() and not player2.is_jumping():
                        _check_enemy_projectiles_vs_player(player2)

        # (6) Melee enemy-player collisions
        _check_melee_collisions(player)
        if GameManager and GameManager.num_players == 2 and player2.visible:
                _check_melee_collisions(player2)

        # (7) Invincibility burn (chalice effect)
        _update_invincible_burn(player, delta_ms)
        if GameManager and GameManager.num_players == 2 and player2.visible:
                _update_invincible_burn(player2, delta_ms)

        # (8) Death check
        _check_death()

        # (9) Collectibles update + collision with player
        _update_collectibles(delta_ms)

        # (10) Exit door logic (treasures collected)
        _update_exit_door(delta_ms)

        # (11) Magic portal (50% enemies killed)
        spawner.trigger_portal_if_needed(maze, p_pos, player_invuln)
        spawner.update_portal(maze, int(delta_ms))

        # (12) Remove dead enemies
        spawner.remove_dead()

        # (13) Update particles
        _update_particles(delta_ms)

        # (14) Screen flash decay
        if screen_flash_timer_ms > 0:
                screen_flash_timer_ms = max(0, screen_flash_timer_ms - int(delta_ms))


# ============================================================================
# Collision helpers
# ============================================================================
func _advance_projectiles(container: Node2D, _delta_ms: float) -> void:
        # Projectiles are children of the container; each updates itself in
        # its own _physics_process. We just remove inactive ones.
        var to_remove: Array = []
        for proj in container.get_children():
                if proj is Node2D and not proj.visible:
                        to_remove.append(proj)
        for p in to_remove:
                container.remove_child(p)
                p.queue_free()


func _check_player_projectiles_vs_enemies(p: CharacterBody2D) -> void:
        # Player.gd stores projectiles as Array[Dictionary] with keys:
        # pos, dir, power, active, type
        for proj in p.projectiles:
                if not proj.get("active", false):
                        continue
                var proj_pos: Vector2 = proj.get("pos", Vector2.ZERO)
                for enemy in spawner.enemies:
                        if enemy.is_dead():
                                continue
                        var e_pos: Vector2 = enemy.get_pixel_pos()
                        if proj_pos.distance_squared_to(e_pos) < 600.0:
                                enemy.take_damage(int(proj.get("power", 1)))
                                proj["active"] = false
                                if enemy.is_dead():
                                        p.add_score(5000)
                                        if AudioManager:
                                                AudioManager.play_sound(AudioManager.SoundType.ENEMY_EXPLODE)
                                break


func _check_enemy_projectiles_vs_player(p: CharacterBody2D) -> void:
        for proj in enemy_projectiles_node.get_children():
                if not proj is Node2D or not proj.visible:
                        continue
                var proj_pos: Vector2 = proj.position
                if proj_pos.distance_squared_to(p.get_pixel_pos()) < 600.0:
                        p.take_damage()
                        proj.visible = false
                        if AudioManager:
                                AudioManager.play_sound(AudioManager.SoundType.LOSE_LIFE)
                        break


func _check_melee_collisions(p: CharacterBody2D) -> void:
        var p_pos: Vector2 = p.get_pixel_pos()
        if p.is_invulnerable() or p.is_jumping():
                # Jump-over-enemy: grant speed boost
                if p.is_jumping():
                        for enemy in spawner.enemies:
                                if enemy.is_dead():
                                        continue
                                if p_pos.distance_squared_to(enemy.get_pixel_pos()) < 800.0:
                                        p.set_jump_speed_boost(1000)
                                        break
                return
        for enemy in spawner.enemies:
                if enemy.is_dead():
                        continue
                if p_pos.distance_squared_to(enemy.get_pixel_pos()) < 800.0:
                        p.take_damage()
                        if AudioManager:
                                AudioManager.play_sound(AudioManager.SoundType.LOSE_LIFE)
                        break


func _update_invincible_burn(p: CharacterBody2D, delta_ms: float) -> void:
        # Chalice effect: while invincible_timer > 0, enemies in contact burn
        if p.invincible_timer <= 0:
                return
        p.invincible_timer = max(0, p.invincible_timer - int(delta_ms))
        if p.invincible_timer <= 0:
                return
        var p_pos: Vector2 = p.get_pixel_pos()
        for enemy in spawner.enemies:
                if enemy.is_dead() or enemy.is_dying() or enemy.is_burning():
                        continue
                if p_pos.distance_squared_to(enemy.get_pixel_pos()) < 600.0:
                        enemy.start_burning(50)
                        p.add_score(5000)
                        if AudioManager:
                                AudioManager.play_sound(AudioManager.SoundType.ENEMY_EXPLODE)


func _check_death() -> void:
        var p1_dead: bool = player.lives <= 0
        var p2_dead: bool = true
        if GameManager and GameManager.num_players == 2 and player2.visible:
                p2_dead = player2.lives <= 0
        if p1_dead and p2_dead:
                if GameManager:
                        if GameManager.continues_left > 0:
                                GameManager.player_died()
                        else:
                                GameManager.give_up()


# ============================================================================
# Collectibles update + collision with player
# ============================================================================
func _update_collectibles(delta_ms: float) -> void:
        var p1_pos: Vector2 = player.get_pixel_pos()
        var p2_pos: Vector2 = Vector2.ZERO
        if GameManager and GameManager.num_players == 2 and player2.visible:
                p2_pos = player2.get_pixel_pos()
        for child in collectibles_node.get_children():
                if not child is Node2D:
                        continue
                # Update item animation/behavior
                child.update_step(delta_ms, p1_pos, 1)
                if not child.active:
                        continue
                var item_pos: Vector2 = child.pos
                # Check P1 collision
                if p1_pos.distance_squared_to(item_pos) < 400.0:
                        _on_collectible_picked_up(child, player, 1)
                        continue
                # Check P2 collision
                if GameManager and GameManager.num_players == 2 and player2.visible:
                        if p2_pos.distance_squared_to(item_pos) < 400.0:
                                _on_collectible_picked_up(child, player2, 2)


func _on_collectible_picked_up(item: Node2D, p: CharacterBody2D, player_id: int) -> void:
        var kind_int: int = item.kind
        match kind_int:
                CollectiblesClass.Kind.MINE:
                        item.start_bounce(Vector2(randf() * 4 - 2, randf() * 4 - 2) * 50, 30000)
                        if AudioManager:
                                AudioManager.play_sound(AudioManager.SoundType.TRAP)
                CollectiblesClass.Kind.CHALICE:
                        p.set_invincible_timer(15000)
                        p.add_score(15000)
                        item.active = false
                        item.queue_free()
                        if AudioManager:
                                AudioManager.play_sound(AudioManager.SoundType.TREASURE)
                        if AudioManager and AudioManager.music_enabled:
                                AudioManager.play_epic_music(8)
                        # Particelle pickup oro (Godot-native)
                        if EffectsManager:
                                var burst := EffectsManager.spawn_pickup_burst(p.get_pixel_pos(),
                                        Color(1.0, 0.84, 0.0))
                                collectibles_node.add_child(burst)
                CollectiblesClass.Kind.SCEPTER:
                        item.trigger_scepter()
                        item.active = false
                        item.queue_free()
                        if AudioManager:
                                AudioManager.play_sound(AudioManager.SoundType.TREASURE)
                        # Particelle lightning (Godot-native)
                        if EffectsManager:
                                var burst := EffectsManager.spawn_pickup_burst(p.get_pixel_pos(),
                                        Color(0.5, 0.8, 1.0))
                                collectibles_node.add_child(burst)
                CollectiblesClass.Kind.SPEED_BOOTS:
                        if item.owner_id == 0 or item.owner_id == player_id:
                                p.activate_speed_boost()
                                item.active = false
                                item.queue_free()
                                if AudioManager:
                                        AudioManager.play_sound(AudioManager.SoundType.WEAPON_PICKUP)
                                # Particelle boots (Godot-native)
                                if EffectsManager:
                                        var burst := EffectsManager.spawn_pickup_burst(p.get_pixel_pos(),
                                                Color(0.3, 1.0, 0.3))
                                        collectibles_node.add_child(burst)
                CollectiblesClass.Kind.TREASURE:
                        p.add_score(CollectiblesClass.TREASURE_POINTS)
                        item.active = false
                        item.queue_free()
                        if AudioManager:
                                AudioManager.play_sound(AudioManager.SoundType.TREASURE)
                        # Particelle treasure (Godot-native)
                        if EffectsManager:
                                var burst := EffectsManager.spawn_pickup_burst(p.get_pixel_pos(),
                                        Color(1.0, 0.84, 0.0))
                                collectibles_node.add_child(burst)


# ============================================================================
# Exit door + level transitions
# ============================================================================
func _update_exit_door(delta_ms: float) -> void:
        # Spawn exit door when all treasures collected
        if maze.get_remaining_treasures() == 0 and not exit_door.get("active", false):
                var door_cell: Vector2i = _find_empty_cell_near_center()
                if door_cell.x >= 0:
                        var door_px: Vector2 = Vector2(
                                door_cell.x * C.TILE_SIZE + C.TILE_SIZE / 2.0,
                                door_cell.y * C.TILE_SIZE + C.TILE_SIZE / 2.0 + C.UI_HEIGHT
                        )
                        exit_door = {
                                "pos": door_px,
                                "active": true,
                                "anim_timer_ms": 800,
                                "glow_pulse": 0.0,
                        }
                        if AudioManager:
                                AudioManager.play_sound(AudioManager.SoundType.TREASURE)

        if exit_door.get("active", false):
                exit_door["anim_timer_ms"] = max(0, int(exit_door["anim_timer_ms"]) - int(delta_ms))
                exit_door["glow_pulse"] += delta_ms * 0.001
                if int(exit_door["anim_timer_ms"]) == 0:
                        # Check player contact
                        var p1_dist: float = player.get_pixel_pos().distance_squared_to(exit_door["pos"])
                        var p1_in: bool = p1_dist < 600.0
                        var p2_in: bool = false
                        if GameManager and GameManager.num_players == 2 and player2.visible:
                                p2_in = player2.get_pixel_pos().distance_squared_to(exit_door["pos"]) < 600.0
                        if p1_in or p2_in:
                                exit_door["active"] = false
                                _advance_level()


func _advance_level() -> void:
        if C.is_boss_level(current_level):
                # Go to boss fight
                if GameManager:
                        GameManager.start_boss_fight()
        else:
                current_level += 1
                if GameManager:
                        GameManager.current_level = current_level
                start_level(current_level)


func _test_mode_skip() -> void:
        player.current_weapon["ammo"] = 15
        if C.is_boss_level(current_level):
                if GameManager:
                        GameManager.start_boss_fight()
        else:
                current_level += 1
                if GameManager:
                        GameManager.current_level = current_level
                start_level(current_level)


# ============================================================================
# Level setup
# ============================================================================
func start_level(lvl: int) -> void:
        current_level = lvl
        if GameManager:
                GameManager.current_level = lvl
        # Generate maze
        maze.generate(current_level)
        # Reset player position
        if current_level == 1:
                player.reset()
                if GameManager and GameManager.num_players == 2:
                        player2.reset()
        else:
                player.reset_position()
                if GameManager and GameManager.num_players == 2:
                        player2.reset_position()
                        player2.position = Vector2(
                                player.position.x + C.TILE_SIZE,
                                player.position.y
                        )
        # Spawn enemies
        spawner.spawn_enemies(maze)
        initial_enemy_count = spawner.enemies.size()
        portal_used = false
        # Clear projectiles
        for child in enemy_projectiles_node.get_children():
                child.queue_free()
        # Reset exit door
        exit_door = {"pos": Vector2.ZERO, "active": false, "anim_timer_ms": 0, "glow_pulse": 0.0}
        # Reset magic portal
        magic_portal = {
                "pos": Vector2.ZERO, "active": false, "phase": 3,
                "phase_timer_ms": 0, "rotation": 0.0, "glow_pulse": 0.0,
                "enemies_to_spawn": 0, "spawn_timer_ms": 0,
        }
        # Reset timers
        player_invincible_timer_ms = 0
        player2_invincible_timer_ms = 0
        particles.clear()
        # Spawn collectibles (mine, chalice, scepter, speed boots)
        _spawn_collectibles()
        # Play level music
        if AudioManager and GameManager and GameManager.music_enabled:
                AudioManager.play_level_music(current_level, false)


# Spawn the level collectibles: mine, chalice, scepter, speed boots.
# Mirrors Game::startLevel() lines 280-360.
func _spawn_collectibles() -> void:
        # Clear previous collectibles
        for child in collectibles_node.get_children():
                child.queue_free()
        chalice_item = null
        scepter_item = null
        mine_item = null
        speed_boots_item = null
        speed_boots2_item = null

        # Find empty cells far from player start (Manhattan distance >= 5)
        var empty_cells: Array = []
        for r in range(1, C.MAZE_ROWS - 1):
                for c in range(1, C.MAZE_COLS - 1):
                        if not maze.is_wall(c, r) and not (c < 5 and r < 5):
                                empty_cells.append(Vector2i(c, r))
        if empty_cells.is_empty():
                return

        # Shuffle and pick cells for each collectible
        empty_cells.shuffle()

        # Mine (item index 0)
        if empty_cells.size() > 0:
                var cell: Vector2i = empty_cells.pop_back()
                var mine_pos := _cell_to_pixel(cell)
                mine_item = _create_collectible(CollectiblesClass.Kind.MINE, mine_pos)
                collectibles_node.add_child(mine_item)

        # Chalice (invincibility)
        if empty_cells.size() > 0:
                var cell: Vector2i = empty_cells.pop_back()
                var chalice_pos := _cell_to_pixel(cell)
                chalice_item = _create_collectible(CollectiblesClass.Kind.CHALICE, chalice_pos)
                collectibles_node.add_child(chalice_item)

        # Scepter (lightning)
        if empty_cells.size() > 0:
                var cell: Vector2i = empty_cells.pop_back()
                var scepter_pos := _cell_to_pixel(cell)
                scepter_item = _create_collectible(CollectiblesClass.Kind.SCEPTER, scepter_pos)
                collectibles_node.add_child(scepter_item)

        # Speed boots (P1)
        if empty_cells.size() > 0:
                var cell: Vector2i = empty_cells.pop_back()
                var boots_pos := _cell_to_pixel(cell)
                speed_boots_item = _create_collectible(CollectiblesClass.Kind.SPEED_BOOTS, boots_pos)
                speed_boots_item.owner_id = 1
                collectibles_node.add_child(speed_boots_item)

        # Speed boots (P2, if 2 players)
        if GameManager and GameManager.num_players == 2 and empty_cells.size() > 0:
                var cell: Vector2i = empty_cells.pop_back()
                var boots_pos := _cell_to_pixel(cell)
                speed_boots2_item = _create_collectible(CollectiblesClass.Kind.SPEED_BOOTS, boots_pos)
                speed_boots2_item.owner_id = 2
                collectibles_node.add_child(speed_boots2_item)


func _cell_to_pixel(cell: Vector2i) -> Vector2:
        return Vector2(
                cell.x * C.TILE_SIZE + C.TILE_SIZE / 2.0,
                cell.y * C.TILE_SIZE + C.TILE_SIZE / 2.0 + C.UI_HEIGHT
        )


# Create a Collectibles node instance with the given kind.
func _create_collectible(kind_int: int, pos: Vector2) -> Node2D:
        var item: Collectibles = CollectiblesClass.new()
        item.kind = kind_int
        item.pos = pos
        item.position = pos
        return item


# ============================================================================
# Pause
# ============================================================================
func _toggle_pause() -> void:
        is_paused = not is_paused
        if is_paused:
                get_tree().paused = true
                if AudioManager:
                        AudioManager.play_sound(AudioManager.SoundType.MENU_SELECT)
        else:
                get_tree().paused = false
                if AudioManager:
                        AudioManager.play_sound(AudioManager.SoundType.MENU_CONFIRM)


# ============================================================================
# Helpers
# ============================================================================
func _find_empty_cell_near_center() -> Vector2i:
        var center_c: int = C.MAZE_COLS / 2
        var center_r: int = C.MAZE_ROWS / 2
        # Search outward from center for an empty cell
        for radius in range(0, max(C.MAZE_COLS, C.MAZE_ROWS)):
                for dr in range(-radius, radius + 1):
                        for dc in range(-radius, radius + 1):
                                var c: int = center_c + dc
                                var r: int = center_r + dr
                                if c < 1 or c >= C.MAZE_COLS - 1:
                                        continue
                                if r < 1 or r >= C.MAZE_ROWS - 1:
                                        continue
                                if not maze.is_wall(c, r):
                                        return Vector2i(c, r)
        return Vector2i(-1, -1)


func _update_particles(delta_ms: float) -> void:
        var alive: Array = []
        for p in particles:
                p["pos"] = p["pos"] + p.get("vel", Vector2.ZERO)
                p["life"] = int(p.get("life", 0)) - 1
                if int(p.get("life", 0)) > 0:
                        alive.append(p)
        particles = alive


func _update_hud() -> void:
        if not hud:
                return
        var p1_snap: Dictionary = {
                "score": player.score,
                "lives": player.lives,
                "energy": player.energy,
                "max_energy": player.max_energy,
                "weapon_name": player.current_weapon.get("name", "PISTOL"),
                "weapon_color": Color.WHITE,
                "weapon_ammo": player.current_weapon.get("ammo", 0),
                "weapon_max": player.current_weapon.get("max_ammo", 15),
        }
        hud.set_player_state(p1_snap)
        if GameManager and GameManager.num_players == 2 and player2.visible:
                var p2_snap: Dictionary = {
                        "score": player2.score,
                        "lives": player2.lives,
                        "energy": player2.energy,
                        "max_energy": player2.max_energy,
                        "weapon_name": player2.current_weapon.get("name", "PISTOL"),
                        "weapon_color": Color.WHITE,
                        "weapon_ammo": player2.current_weapon.get("ammo", 0),
                        "weapon_max": player2.current_weapon.get("max_ammo", 15),
                }
                hud.set_player2_state(p2_snap)
        hud.set_remaining_treasures(maze.get_remaining_treasures())


# ============================================================================
# Public API (called by external systems)
# ============================================================================
func on_continue_used() -> void:
        # Player used a continue credit: reset positions, keep score
        player.reset_position()
        player.lives = 3
        player.energy = player.max_energy
        if GameManager and GameManager.num_players == 2:
                player2.reset_position()
                player2.lives = 3
                player2.energy = player2.max_energy


func _draw() -> void:
        # Exit door rendering
        if exit_door.get("active", false):
                var door_pos: Vector2 = exit_door["pos"]
                var glow: float = 0.5 + 0.5 * sin(float(exit_door["glow_pulse"]))
                draw_circle(door_pos, 30.0, Color(1.0, 0.84, 0.0, 0.3 + 0.3 * glow))
                draw_circle(door_pos, 20.0, Color(1.0, 0.84, 0.0, 0.5 + 0.3 * glow))
                draw_rect(Rect2(door_pos.x - 16, door_pos.y - 24, 32, 48),
                        Color(0.5, 0.35, 0.15, 0.9), true)
                draw_rect(Rect2(door_pos.x - 16, door_pos.y - 24, 32, 48),
                        Color(1.0, 0.84, 0.0, 0.8), false, 2)

        # Particles
        for p in particles:
                var pos: Vector2 = p.get("pos", Vector2.ZERO)
                var col: Color = p.get("color", Color.WHITE)
                var size: float = float(p.get("size", 3))
                draw_circle(pos, size, col)

        # Screen flash
        if screen_flash_timer_ms > 0:
                var alpha: float = float(screen_flash_timer_ms) / 200.0
                draw_rect(Rect2(0, 0, C.WINDOW_WIDTH, C.WINDOW_HEIGHT),
                        Color(1, 1, 1, alpha), false)
