## DemoController.gd
## ============================================================
## Modalita' demo: AI controlla il player per 30 secondi.
## Mirror di Game.cpp startDemoMode/updateDemoMode/drawDemoOverlay.
##
## - Parte dopo 30s di inattivita' nel menu principale
## - AI cerca nemico/boss/tesoro piu' vicino e gli spara
## - Cambia direzione ogni 400ms per evitare di bloccarsi ai muri
## - Salta occasionalmente (2% per frame)
## - Spara quando allineato al target o 20% casuale
## - 30s durata, poi torna al menu
## - Interrupt su qualsiasi input utente
## ============================================================
extends Node2D

const C = preload("res://scripts/core/GameConstants.gd")
const WeaponClass = preload("res://scripts/items/Weapon.gd")
const CollectiblesClass = preload("res://scripts/items/Collectibles.gd")

@onready var maze: Node2D = $Maze
@onready var player: CharacterBody2D = $Player
@onready var spawner: Node2D = $Enemies
@onready var projectiles_node: Node2D = $Projectiles
@onready var enemy_projectiles_node: Node2D = $EnemyProjectiles
@onready var collectibles_node: Node2D = $Collectibles
@onready var hud: Control = $HUD

# Demo state
var demo_duration_timer_ms: int = 30000
var demo_is_boss: bool = false
var demo_ai_timer_p1: int = 0
var demo_ai_dir_p1: int = 0
var demo_ai_shoot_timer_p1: int = 0
var demo_overlay_time: float = 0.0
var current_level: int = 1

# Boss reference (se demo boss)
var boss: Node2D = null


func _ready() -> void:
        print("[DemoController] Starting demo mode")
        # Random character
        var char_type: int = randi() % 8
        player.set_character(char_type, 1)
        player.reset()
        # Random level
        current_level = (randi() % C.STORY_LEVELS_COUNT) + 1
        demo_is_boss = (randi() % 2 == 0)
        demo_duration_timer_ms = 30000
        demo_ai_timer_p1 = 0
        demo_ai_dir_p1 = 0
        demo_ai_shoot_timer_p1 = 0
        # Generate maze
        maze.generate(current_level)
        # Spawn enemies
        spawner.spawn_enemies(maze)
        # Spawn collectibles
        _spawn_collectibles()
        # Set player position
        player.reset_position()
        # Music
        if AudioManager and GameManager.music_enabled:
                AudioManager.play_level_music(current_level, demo_is_boss)
        print("[DemoController] Demo started: level=%d boss=%s char=%d" % [current_level, demo_is_boss, char_type])


func _physics_process(_delta: float) -> void:
        var delta_ms: float = _delta * 1000.0
        delta_ms = min(delta_ms, 50.0)

        # Decrement duration timer
        demo_duration_timer_ms -= int(delta_ms)
        if demo_duration_timer_ms <= 0:
                print("[DemoController] Demo duration ended, returning to menu")
                _stop_demo()
                return

        # Check for user input (interrupt demo)
        if _check_user_input():
                print("[DemoController] User input detected, stopping demo")
                _stop_demo()
                return

        # AI control
        _update_ai(delta_ms)

        # Update player
        player.update_player(maze, demo_is_boss)
        player.shoot_cooldown = max(0, player.shoot_cooldown - 1)

        # Update enemies
        var p_pos: Vector2 = player.get_pixel_pos()
        var p_grid: Vector2i = player.get_grid_pos()
        for enemy in spawner.enemies:
                if not enemy.is_death_anim_done():
                        enemy.update_enemy(maze, p_grid, p_pos, [])
        spawner.remove_dead()

        # Player projectiles vs enemies
        for proj in player.projectiles:
                if not proj.get("active", false):
                        continue
                var proj_pos: Vector2 = proj.get("pos", Vector2.ZERO)
                for enemy in spawner.enemies:
                        if enemy.is_dead():
                                continue
                        if proj_pos.distance_squared_to(enemy.get_pixel_pos()) < 600.0:
                                enemy.take_damage(int(proj.get("power", 1)))
                                proj["active"] = false
                                break

        # Exit door logic (if treasures collected)
        if maze.get_remaining_treasures() == 0:
                # Demo: just keep playing, don't advance level
                pass

        # Update HUD
        if hud:
                hud.set_player_state({
                        "score": player.score,
                        "lives": player.lives,
                        "energy": player.energy,
                        "max_energy": player.max_energy,
                        "weapon_name": "PISTOL",
                        "weapon_color": Color.WHITE,
                        "weapon_ammo": player.current_weapon.get("ammo", 0),
                        "weapon_max": 15,
                })
                hud.set_remaining_treasures(maze.get_remaining_treasures())

        queue_redraw()


func _update_ai(delta_ms: float) -> void:
        # Find target: nearest enemy or boss
        var target_pos: Vector2 = player.get_pixel_pos()
        var has_target: bool = false

        # Look for nearest enemy
        var min_dist: float = 1e9
        for enemy in spawner.enemies:
                if enemy.is_dead() or enemy.is_death_anim_done():
                        continue
                var e_pos: Vector2 = enemy.get_pixel_pos()
                var d: float = player.get_pixel_pos().distance_squared_to(e_pos)
                if d < min_dist:
                        min_dist = d
                        target_pos = e_pos
                        has_target = true

        # If no enemies, look for nearest treasure
        if not has_target:
                var p_col: int = int(player.get_pixel_pos().x / C.TILE_SIZE)
                var p_row: int = int((player.get_pixel_pos().y - C.UI_HEIGHT) / C.TILE_SIZE)
                var min_t_dist: float = 1e9
                for r in range(C.MAZE_ROWS):
                        for c in range(C.MAZE_COLS):
                                if maze.get_cell_type(c, r) == C.CellType.TREASURE:
                                        var d: float = float((c - p_col) * (c - p_col) + (r - p_row) * (r - p_row))
                                        if d < min_t_dist:
                                                min_t_dist = d
                                                target_pos = Vector2(
                                                        c * C.TILE_SIZE + C.TILE_SIZE / 2.0,
                                                        r * C.TILE_SIZE + C.TILE_SIZE / 2.0 + C.UI_HEIGHT
                                                )
                                                has_target = true

        # Change direction every 400ms
        demo_ai_timer_p1 -= int(delta_ms)
        if demo_ai_timer_p1 <= 0 or not has_target:
                demo_ai_timer_p1 = 400
                if has_target:
                        var dx: float = target_pos.x - player.get_pixel_pos().x
                        var dy: float = target_pos.y - player.get_pixel_pos().y
                        if absf(dx) > absf(dy):
                                demo_ai_dir_p1 = 4 if dx > 0 else 3  # right/left
                        else:
                                demo_ai_dir_p1 = 2 if dy > 0 else 1  # down/up
                        # 20% random direction
                        if randi() % 100 < 20:
                                demo_ai_dir_p1 = 1 + randi() % 4
                else:
                        demo_ai_dir_p1 = 1 + randi() % 4

        # Apply direction
        match demo_ai_dir_p1:
                1: player.set_direction(0, -1)  # up
                2: player.set_direction(0, 1)   # down
                3: player.set_direction(-1, 0)  # left
                4: player.set_direction(1, 0)   # right
                _: player.set_direction(0, 0)

        # Shoot logic
        demo_ai_shoot_timer_p1 -= int(delta_ms)
        if demo_ai_shoot_timer_p1 <= 0:
                demo_ai_shoot_timer_p1 = 500
                var should_shoot: bool = false
                if has_target:
                        var dx: float = absf(target_pos.x - player.get_pixel_pos().x)
                        var dy: float = absf(target_pos.y - player.get_pixel_pos().y)
                        if dx < C.TILE_SIZE / 2.0 or dy < C.TILE_SIZE / 2.0:
                                should_shoot = true
                if not should_shoot and randi() % 100 < 20:
                        should_shoot = true
                if should_shoot and player.shoot_cooldown == 0:
                        player.shoot()
                        player.shoot_cooldown = 150

        # Random jump (2% per frame)
        if randi() % 100 < 2:
                player.activate_jump()


func _check_user_input() -> bool:
        # Keyboard: any key interrupts demo
        if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_DOWN) or \
           Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_RIGHT) or \
           Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_ENTER) or \
           Input.is_key_pressed(KEY_ESCAPE) or Input.is_key_pressed(KEY_W) or \
           Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_S) or \
           Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_Q) or \
           Input.is_key_pressed(KEY_E):
                return true
        # Joystick: any axis or button
        var joy_pads: Array = Input.get_connected_joypads()
        for jid in joy_pads:
                var x: float = Input.get_joy_axis(jid, 0)
                var y: float = Input.get_joy_axis(jid, 1)
                if absf(x) > 0.3 or absf(y) > 0.3:
                        return true
                if Input.is_joy_button_pressed(jid, 0):
                        return true
        return false


func _stop_demo() -> void:
        if AudioManager:
                AudioManager.stop_music()
        if GameManager:
                GameManager.go_to_menu()


func _spawn_collectibles() -> void:
        for child in collectibles_node.get_children():
                child.queue_free()
        var empty_cells: Array = []
        for r in range(1, C.MAZE_ROWS - 1):
                for c in range(1, C.MAZE_COLS - 1):
                        if not maze.is_wall(c, r) and not (c < 5 and r < 5):
                                empty_cells.append(Vector2i(c, r))
        if empty_cells.is_empty():
                return
        empty_cells.shuffle()
        # Chalice
        if empty_cells.size() > 0:
                var cell: Vector2i = empty_cells.pop_back()
                var chalice := CollectiblesClass.new()
                chalice.kind = CollectiblesClass.Kind.CHALICE
                chalice.pos = Vector2(cell.x * C.TILE_SIZE + C.TILE_SIZE / 2.0,
                        cell.y * C.TILE_SIZE + C.TILE_SIZE / 2.0 + C.UI_HEIGHT)
                chalice.position = chalice.pos
                collectibles_node.add_child(chalice)
        # Scepter
        if empty_cells.size() > 0:
                var cell: Vector2i = empty_cells.pop_back()
                var scepter := CollectiblesClass.new()
                scepter.kind = CollectiblesClass.Kind.SCEPTER
                scepter.pos = Vector2(cell.x * C.TILE_SIZE + C.TILE_SIZE / 2.0,
                        cell.y * C.TILE_SIZE + C.TILE_SIZE / 2.0 + C.UI_HEIGHT)
                scepter.position = scepter.pos
                collectibles_node.add_child(scepter)
        # Speed boots
        if empty_cells.size() > 0:
                var cell: Vector2i = empty_cells.pop_back()
                var boots := CollectiblesClass.new()
                boots.kind = CollectiblesClass.Kind.SPEED_BOOTS
                boots.pos = Vector2(cell.x * C.TILE_SIZE + C.TILE_SIZE / 2.0,
                        cell.y * C.TILE_SIZE + C.TILE_SIZE / 2.0 + C.UI_HEIGHT)
                boots.position = boots.pos
                collectibles_node.add_child(boots)


func _draw() -> void:
        # Demo overlay: "DEMO MODE" pulsing red at bottom center
        demo_overlay_time += 0.05
        var pulse: float = (sin(demo_overlay_time * 5.0) + 1.0) * 0.5
        var alpha: float = (100.0 + pulse * 155.0) / 255.0
        var demo_col: Color = Color(1.0, 0.157, 0.157, alpha)
        # Draw text using draw_string
        var font := get_theme_default_font()
        var cx: float = C.WINDOW_WIDTH / 2.0
        draw_string(font, Vector2(cx - 150, C.WINDOW_HEIGHT - 60), "DEMO MODE",
                HORIZONTAL_ALIGNMENT_CENTER, 300, 48, demo_col)
        draw_string(font, Vector2(cx - 200, C.WINDOW_HEIGHT - 24), "PRESS ANY KEY TO EXIT",
                HORIZONTAL_ALIGNMENT_CENTER, 400, 18, Color(1.0, 0.784, 0.784, alpha))
