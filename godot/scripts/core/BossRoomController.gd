## BossRoomController.gd
## ============================================================
## The central gameplay orchestrator for boss fights.
##
## This is the Godot equivalent of the C++ Game::update() STATE_BOSS
## branch (Game.cpp lines 2720-3228). It:
##   - Reads P1/P2 input (free movement, no grid snap)
##   - Calls player.update_player(free=true) / boss.update_step()
##   - Handles boss projectiles, boss room weapons
##   - Manages boss death -> next level / win
##   - Handles continue / lose
##
## Attach this script to the root node of BossRoom.tscn.
## ============================================================
extends Node2D

const C = preload("res://scripts/core/GameConstants.gd")
const WeaponClass = preload("res://scripts/items/Weapon.gd")

# --- Node references ---
@onready var player: CharacterBody2D = $Player
@onready var player2: CharacterBody2D = $Player2
@onready var boss_node: Node2D = $Boss
@onready var boss_projectiles_node: Node2D = $BossProjectiles
@onready var boss_room_weapons_node: Node2D = $BossRoomWeapons
@onready var hud: Control = $HUD

# --- Game state ---
var current_level: int = 4
var is_paused: bool = false
var test_skip_key_held: bool = false
var boss_room_weapons: Array = []  # [{weapon, pos}]
var boss: Node2D = null
var died_in_boss: bool = false

const FRAME_MS: float = 1000.0 / 60.0


# ============================================================================
# Lifecycle
# ============================================================================
func _ready() -> void:
        if GameManager:
                current_level = GameManager.current_level
                died_in_boss = GameManager.died_in_boss
        player.set_character(GameManager.player1_character, 1)
        if GameManager.num_players == 2:
                player2.set_character(GameManager.player2_character, 2)
                player2.visible = true
        else:
                player2.visible = false
        # Setup boss fight
        start_boss_fight(died_in_boss)
        # Boss music
        if AudioManager and GameManager and GameManager.music_enabled:
                AudioManager.play_level_music(current_level, true)


func _physics_process(_delta: float) -> void:
        if is_paused:
                return
        var delta_ms: float = _delta * 1000.0
        delta_ms = min(delta_ms, 50.0)

        _handle_input()
        _update_boss(delta_ms)
        _update_hud()


# ============================================================================
# Input
# ============================================================================
func _handle_input() -> void:
        # P1 movement (free, no grid snap)
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
                player.shoot()
                player.shoot_cooldown = 150

        # P1 jump
        if Input.is_action_just_pressed("jump"):
                player.activate_jump()

        # P2
        if GameManager and GameManager.num_players == 2 and player2.visible:
                var p2_dx: int = 0
                var p2_dy: int = 0
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

        # Pause
        if Input.is_action_just_pressed("pause"):
                _toggle_pause()

        # Test mode: Space kills boss instantly
        if GameManager and GameManager.test_mode_enabled:
                var space_now: bool = Input.is_key_pressed(KEY_SPACE)
                if space_now and not test_skip_key_held:
                        if boss:
                                boss.take_damage(9999)
                test_skip_key_held = space_now


# ============================================================================
# Boss fight update loop (STATE_BOSS)
# ============================================================================
func _update_boss(delta_ms: float) -> void:
        # (1) Player update (free movement)
        player.update_player(null, true)
        if GameManager and GameManager.num_players == 2 and player2.visible:
                player2.update_player(null, true)

        # (2) Boss update
        if boss and not boss.is_dead():
                var p_pos: Vector2 = player.get_pixel_pos()
                boss.update_step(p_pos.x, p_pos.y, int(delta_ms), boss_projectiles_node)

        # (3) Advance boss projectiles
        _advance_boss_projectiles(delta_ms)

        # (4) Player projectiles vs boss
        if boss and not boss.is_dead():
                _check_player_projectiles_vs_boss(player)
                if GameManager and GameManager.num_players == 2 and player2.visible:
                        _check_player_projectiles_vs_boss(player2)

        # (5) Boss projectiles vs player
        if not player.is_invulnerable() and not player.is_jumping():
                _check_boss_projectiles_vs_player(player)
        if GameManager and GameManager.num_players == 2 and player2.visible:
                if not player2.is_invulnerable() and not player2.is_jumping():
                        _check_boss_projectiles_vs_player(player2)

        # (6) Invincible player damages boss
        if boss and not boss.is_dead() and player.invincible_timer > 0:
                player.invincible_timer = max(0, player.invincible_timer - int(delta_ms))
                if player.get_pixel_pos().distance_squared_to(boss.pos) < (boss.size / 2.0) ** 2:
                        boss.take_damage(1)
                        if AudioManager:
                                AudioManager.play_sound(AudioManager.SoundType.BOSS_HIT)

        # (7) Boss room weapons pickup
        _check_boss_room_weapon_pickup(player)
        if GameManager and GameManager.num_players == 2 and player2.visible:
                _check_boss_room_weapon_pickup(player2)

        # (8) Anti-softlock: respawn weapons if all empty
        _check_softlock()

        # (9) Death / continue check
        _check_boss_death()


func _advance_boss_projectiles(_delta_ms: float) -> void:
        var to_remove: Array = []
        for proj in boss_projectiles_node.get_children():
                if not proj is Node2D:
                        continue
                if not proj.visible:
                        to_remove.append(proj)
        for p in to_remove:
                boss_projectiles_node.remove_child(p)
                p.queue_free()


func _check_player_projectiles_vs_boss(p: CharacterBody2D) -> void:
        for proj in p.projectiles:
                if not proj.get("active", false):
                        continue
                var proj_pos: Vector2 = proj.get("pos", Vector2.ZERO)
                if proj_pos.distance_squared_to(boss.pos) < (boss.size / 2.0) ** 2:
                        boss.take_damage(int(proj.get("power", 1)))
                        proj["active"] = false
                        if AudioManager:
                                AudioManager.play_sound(AudioManager.SoundType.BOSS_HIT)
                        break


func _check_boss_projectiles_vs_player(p: CharacterBody2D) -> void:
        for proj in boss_projectiles_node.get_children():
                if not proj is Node2D or not proj.visible:
                        continue
                if proj.position.distance_squared_to(p.get_pixel_pos()) < 600.0:
                        p.take_damage()
                        proj.visible = false
                        if AudioManager:
                                AudioManager.play_sound(AudioManager.SoundType.LOSE_LIFE)
                        break


func _check_boss_room_weapon_pickup(p: CharacterBody2D) -> void:
        var to_remove: Array = []
        for w_entry in boss_room_weapons:
                if p.get_pixel_pos().distance_squared_to(w_entry["pos"]) < 1000.0:
                        p.collect_weapon(w_entry["weapon"])
                        if AudioManager:
                                AudioManager.play_sound(AudioManager.SoundType.WEAPON_PICKUP)
                        to_remove.append(w_entry)
        for w in to_remove:
                boss_room_weapons.erase(w)
                if w.get("node"):
                        w["node"].queue_free()


func _check_softlock() -> void:
        # If both players have 0 ammo and no weapons on floor, respawn weapons
        var p1_empty: bool = int(player.current_weapon.get("ammo", 0)) == 0
        var p2_empty: bool = true
        if GameManager and GameManager.num_players == 2 and player2.visible:
                p2_empty = int(player2.current_weapon.get("ammo", 0)) == 0
        else:
                p2_empty = false
        if (p1_empty or p2_empty) and boss_room_weapons.is_empty():
                _spawn_boss_room_weapons()


func _check_boss_death() -> void:
        # Player death -> continues
        var p1_dead: bool = player.lives <= 0
        var p2_dead: bool = true
        if GameManager and GameManager.num_players == 2 and player2.visible:
                p2_dead = player2.lives <= 0
        if p1_dead and p2_dead:
                if GameManager:
                        GameManager.died_in_boss = true
                        if GameManager.continues_left > 0:
                                GameManager.player_died()
                        else:
                                GameManager.give_up()
                return

        # Boss death -> next level
        if boss and boss.is_dead():
                if AudioManager:
                        AudioManager.play_sound(AudioManager.SoundType.BOSS_DEATH)
                player.add_life()
                if GameManager:
                        GameManager.boss_defeated.emit(GameManager.get_boss_index(current_level))
                        GameManager.current_level = current_level + 1
                        if GameManager.game_mode == C.GameMode.STORY and \
                           current_level + 1 > C.STORY_LEVELS_COUNT:
                                # Win! -> go to WinScreen
                                GameManager.go_to_win()
                        else:
                                # Back to maze
                                GameManager.go_to_maze()


# ============================================================================
# Boss fight setup
# ============================================================================
func start_boss_fight(keep_boss_state: bool = false) -> void:
        if keep_boss_state and boss and not boss.is_dead():
                # Continue: keep boss HP, just reset player positions
                player.reset_position()
                player.position = Vector2(C.WINDOW_WIDTH / 2.0, C.WINDOW_HEIGHT - 100.0)
                if GameManager and GameManager.num_players == 2:
                        player2.reset_position()
                        player2.position = Vector2(C.WINDOW_WIDTH / 2.0 + 120, C.WINDOW_HEIGHT - 100.0)
                for child in boss_projectiles_node.get_children():
                        child.queue_free()
                return

        # New boss fight
        if boss:
                boss.queue_free()
        # Create boss via the Boss node's script
        if boss_node:
                boss_node.setup(current_level, C.WINDOW_WIDTH, C.WINDOW_HEIGHT)
                boss = boss_node
        # Reset player positions
        player.reset_position()
        player.position = Vector2(C.WINDOW_WIDTH / 2.0, C.WINDOW_HEIGHT - 100.0)
        if GameManager and GameManager.num_players == 2:
                player2.reset_position()
                player2.position = Vector2(C.WINDOW_WIDTH / 2.0 + 120, C.WINDOW_HEIGHT - 100.0)
        # Clear projectiles
        for child in boss_projectiles_node.get_children():
                child.queue_free()
        # Spawn boss room weapons
        boss_room_weapons.clear()
        for child in boss_room_weapons_node.get_children():
                child.queue_free()
        _spawn_boss_room_weapons()


func _spawn_boss_room_weapons() -> void:
        for i in range(3):
                var w := WeaponClass.new()
                w.generate_random()
                w.ammo = 5
                var w_pos := Vector2(200.0 + i * 300.0, 200.0)
                boss_room_weapons.append({"weapon": w, "pos": w_pos, "node": null})


# ============================================================================
# Pause
# ============================================================================
func _toggle_pause() -> void:
        is_paused = not is_paused
        if is_paused:
                get_tree().paused = true
        else:
                get_tree().paused = false


# ============================================================================
# HUD
# ============================================================================
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
        if boss:
                hud.set_boss_hp(boss.health, boss.max_health, boss.boss_type)
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


# ============================================================================
# Drawing
# ============================================================================
func _draw() -> void:
        # Draw boss room weapons on the floor
        for w_entry in boss_room_weapons:
                var pos: Vector2 = w_entry["pos"]
                # Simple weapon icon (colored circle + letter)
                var w: Resource = w_entry["weapon"]
                var col: Color = w.get_color() if w.has_method("get_color") else Color.WHITE
                draw_circle(pos, 16.0, Color(0.2, 0.2, 0.2, 0.8))
                draw_circle(pos, 12.0, col)
