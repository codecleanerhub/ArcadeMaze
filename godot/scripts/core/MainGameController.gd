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
@onready var hud: Control = $HUDLayer/HUD

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

# MiniBoss (spawned by magic portal, 1 per level)
var mini_boss: Node2D = null
var mini_boss_spawned: bool = false

# Lightning bolts from scepter (full-screen, hit all enemies/boss on path)
var lightning_bolts: Array = []  # [{pos, life, max_life, zigzag_points}]
var scepter_active: bool = false
var scepter_strikes_left: int = 0
var scepter_timer_ms: int = 0
var initial_enemy_count: int = 0

# Items spawned per level
var chalice_item: Node2D = null
var scepter_item: Node2D = null
var mine_item: Node2D = null
var speed_boots_item: Node2D = null
var speed_boots2_item: Node2D = null  # P2 only
# FIX (nuova meccanica): medikit e statua cavaliere
var medikit_item: Node2D = null
var knight_statue_item: Node2D = null
var knight_ally: Node2D = null  # cavaliere alleato evocato
var medikit_used: bool = false  # 1 medikit per livello
var knight_statue_spawned: bool = false  # 1 statua per livello
# FIX (nuova meccanica): candelotto di dinamite
var dynamite_item: Node2D = null
var dynamite_spawned: bool = false  # 1 dinamite per livello
# Stato dinamite equipaggiata
var dynamite_equipped: bool = false
var dynamite_fuse_timer_ms: int = 0  # timer miccia (7000ms = 7s)
var dynamite_alert_played: bool = false
var dynamite_explode_timer_ms: int = 0  # timer esplosione dopo alert (2000ms)
var dynamite_thrown: Node2D = null  # candelotto lanciato in volo

# FIX (HUD last hit enemy): traccia l'ultimo nemico colpito dal player.
# L'HUD mostra il nome + barra energia di questo nemico in alto al centro.
# Quando il nemico muore o dopo 3s senza hit, la barra scompare.
var last_hit_enemy: Node2D = null
var last_hit_enemy_timer_ms: int = 0  # timer per nascondere dopo 3s senza hit

# Timers
var player_invincible_timer_ms: int = 0
var player2_invincible_timer_ms: int = 0
var screen_flash_timer_ms: int = 0

# Particles (simple visual feedback)
var particles: Array = []

# Decals on the floor (port of C++ Game::bloodStains / ashPiles / fireBursts).
# - blood_stains: temporary dark-red splatter where an enemy died by projectile
#   or scepter. life counted in frames @ 60 FPS (300 = 5s).
# - ash_piles: long-lasting grey pile where an enemy was burned by the
#   invincible (chalice) player. life 600 = 10s.
# - fire_bursts: short orange/yellow expanding burst at burn/kill position.
#   life 40 = ~0.66s. Radius grows with age.
# Mirrors Game.h lines 117-151 and Game.cpp update logic 2146-2171 / 2314-2342.
var blood_stains: Array = []  # [{pos, life, max_life, radius, color}]
var ash_piles: Array = []     # [{pos, life, max_life, radius, anim_time}]
var fire_bursts: Array = []   # [{pos, life, max_life, scale, anim_time}]

# Spritesheets for advanced decals (loaded in _ready via SpriteManager).
# Mirror Game.cpp drawAshPiles/drawFireBursts (3998-4132 / 3892-3990):
#   - effect_ashpile: 6x4 frame 64x64 (anchor 32,56)
#   - effect_fireburst: 6x4 frame 64x64 (anchor 32,40)
var _ashpile_sheet: Variant = null
var _fireburst_sheet: Variant = null

# Frame delta in ms (for timer decrements matching C++ @ 60 FPS)
const FRAME_MS: float = 1000.0 / 60.0


# ============================================================================
# Lifecycle
# ============================================================================
func _ready() -> void:
        print("[MainGameController] VERSION: engine/godot-engine-fixes-v3 - game controller ready")
        # FIX (pause P non toggle): quando get_tree().paused = true, _physics_process
        # non gira più → is_action_just_pressed("pause") non viene rilevato per
        # togliere la pausa. Impostando process_mode = PROCESS_MODE_ALWAYS il nodo
        # continua a processare input anche con il game tree in pausa.
        process_mode = Node.PROCESS_MODE_ALWAYS
        # FIX (no sfondo esterno necessario): il design space è ora 1920x1080
        # (= viewport), il maze riempie tutto lo schermo. Niente più background
        # cripta esterno. La camera è zoom 1:1 centrata sul design space.
        # FIX (maze decentrato in basso a destra):
        # L'approccio precedente scalava il MainGame root Node2D, ma il Camera2D
        # creato in Player.gd veniva aggiunto come figlio di scene_root (che È
        # il MainGame scalato) → la camera ereditava la trasformazione di scale
        # e position → vista sballata con maze in basso a destra.
        # Ora usiamo un approccio corretto:
        #   1. MainGame root resta a scale (1,1) e position (0,0) — nessuna
        #      trasformazione ereditata dai figli.
        #   2. Una Camera2D indipendente (aggiunta al Window root, NON al
        #      MainGame) con zoom = 1:1 e position = (960, 540) (centro del
        #      design space 1920x1080) → il maze riempie tutto lo schermo.
        # Il MainGame root NON viene scalato; è la camera che "zooma" sul
        # design space.
        _setup_camera()
        # FIX (fulmini invisibili): crea overlay layer per disegnare SOPRA il maze
        _create_foreground_layer()
        # Load advanced-decal spritesheets via SpriteManager (mirror C++ static
        # SpriteSheet load in drawAshPiles 4012-4017 / drawFireBursts 3903-3908).
        if SpriteManager:
                _ashpile_sheet = SpriteManager.get_sheet("effect_ashpile")
                _fireburst_sheet = SpriteManager.get_sheet("effect_fireburst")
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
        # Vignette post-processing — riabilitato (1 full-screen shader, costo minimo).
        if EffectsManager:
                var vignette := EffectsManager.create_vignette_rect()
                add_child(vignette)


# Background layer node (CanvasLayer, independent of camera and MainGame scale).
# Drawn behind everything to fill the lateral black bars with thematic fantasy.
var _bg_canvas: CanvasLayer = null
var _bg_layer: Control = null
# FIX (fulmini invisibili): overlay CanvasLayer per disegnare fulmini, particelle,
# proiettili nemici SOPRA il maze. Prima venivano disegnati in _draw() del
# MainGameController che viene chiamato PRIMA dei figli (Maze, ecc.) →
# il maze copriva i fulmini.
var _fg_canvas: CanvasLayer = null
var _fg_drawer: Node2D = null  # OverlayDrawer Node2D che disegna sopra il maze
# Background animation timer (for crypt torches / fog drift).
var _bg_anim_time: float = 0.0


func _create_background_layer() -> void:
        # CanvasLayer renders independently of the 2D transform hierarchy.
        # layer = -100 puts it behind everything else.
        _bg_canvas = CanvasLayer.new()
        _bg_canvas.layer = -100
        _bg_layer = Control.new()
        _bg_layer.name = "BackgroundLayer"
        _bg_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
        _bg_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _bg_layer.draw.connect(_on_bg_layer_draw)
        _bg_canvas.add_child(_bg_layer)
        # Add the CanvasLayer to the Window root (NOT to self, which would
        # make it a child of the MainGame node and potentially affected by
        # any future transforms).
        get_tree().root.add_child(_bg_canvas)


# FIX (fulmini invisibili): crea un CanvasLayer con layer = 1 (sopra il
# gameplay layer 0) per disegnare fulmini, particelle, proiettili nemici,
# dinamite lanciata, ecc. SOPRA il maze. Prima erano in _draw() del
# MainGameController che viene chiamato PRIMA dei figli → il maze copriva tutto.
const OverlayDrawerClass = preload("res://scripts/core/OverlayDrawer.gd")

func _create_foreground_layer() -> void:
        _fg_canvas = CanvasLayer.new()
        _fg_canvas.layer = 1
        _fg_drawer = OverlayDrawerClass.new()
        _fg_drawer.name = "ForegroundDrawer"
        _fg_drawer.z_index = 100
        _fg_drawer.controller = self
        _fg_canvas.add_child(_fg_drawer)
        get_tree().root.add_child(_fg_canvas)


# Disegna gli overlay SOPRA il maze. Chiamato da OverlayDrawer._draw().
# Tutte le chiamate draw_* usano 'ci' (il CanvasItem passato) come contesto.
func _draw_overlay(ci: CanvasItem) -> void:
        # Exit door rendering
        if exit_door.get("active", false):
                var door_pos: Vector2 = exit_door["pos"]
                var glow: float = 0.5 + 0.5 * sin(float(exit_door["glow_pulse"]))
                ci.draw_circle(door_pos, 30.0, Color(1.0, 0.84, 0.0, 0.3 + 0.3 * glow))
                ci.draw_circle(door_pos, 20.0, Color(1.0, 0.84, 0.0, 0.5 + 0.3 * glow))
                ci.draw_rect(Rect2(door_pos.x - 16, door_pos.y - 24, 32, 48),
                        Color(0.5, 0.35, 0.15, 0.9), true)
                ci.draw_rect(Rect2(door_pos.x - 16, door_pos.y - 24, 32, 48),
                        Color(1.0, 0.84, 0.0, 0.8), false, 2)
        # Particles
        for p in particles:
                var pos: Vector2 = p.get("pos", Vector2.ZERO)
                var col: Color = p.get("color", Color.WHITE)
                var size: float = float(p.get("size", 3))
                ci.draw_circle(pos, size, col)
        # Screen flash
        if screen_flash_timer_ms > 0:
                var alpha: float = (float(screen_flash_timer_ms) / 60.0) * 0.3
                ci.draw_rect(Rect2(0, 0, C.WINDOW_WIDTH, C.WINDOW_HEIGHT),
                        Color(1, 1, 1, alpha), true)
        # Lightning bolts — ORA SOPRA il maze!
        _draw_lightning_bolts_overlay(ci)
        # Enemy projectiles
        for proj in enemy_projectiles_node.get_children():
                if not proj is Node2D:
                        continue
                if not is_instance_valid(proj) or not proj.visible:
                        continue
                var ppos: Vector2 = proj.position
                ci.draw_circle(ppos, 6.0, Color(1.0, 0.4, 0.1, 0.4))
                ci.draw_circle(ppos, 3.0, Color(1.0, 0.2, 0.05, 1.0))
        # Dynamite thrown
        if dynamite_thrown != null and is_instance_valid(dynamite_thrown):
                var dt_pos: Vector2 = dynamite_thrown.position
                ci.draw_circle(dt_pos, 14.0, Color(1.0, 0.4, 0.1, 0.4))
                ci.draw_rect(Rect2(dt_pos.x - 5, dt_pos.y - 10, 10, 20),
                        Color(0.7, 0.12, 0.1, 1.0), true)
                ci.draw_rect(Rect2(dt_pos.x - 3, dt_pos.y - 4, 6, 4),
                        Color(0.94, 0.86, 0.7, 1.0), true)
        # Magic portal
        if spawner != null and spawner.magic_portal.active:
                var ppos2: Vector2 = spawner.magic_portal.pos
                var prot2: float = spawner.magic_portal.rotation
                var pglow2: float = spawner.magic_portal.glow_pulse
                var aura_r: float = 40.0 + sin(pglow2 * 2.0) * 6.0
                ci.draw_circle(ppos2, aura_r, Color(0.5, 0.2, 0.8, 0.2))
                for i in 12:
                        var a2: float = prot2 + (float(i) / 12.0) * TAU
                        var p1: Vector2 = ppos2 + Vector2(cos(a2), sin(a2)) * 32.0
                        ci.draw_circle(p1, 3.0, Color(0.7, 0.3, 1.0, 0.7))
                for i in 8:
                        var a2b: float = -prot2 * 1.5 + (float(i) / 8.0) * TAU
                        var p2: Vector2 = ppos2 + Vector2(cos(a2b), sin(a2b)) * 22.0
                        ci.draw_circle(p2, 2.5, Color(0.3, 0.8, 1.0, 0.8))
                var core_r: float = 10.0 + sin(pglow2 * 4.0) * 2.0
                ci.draw_circle(ppos2, core_r + 4.0, Color(1.0, 1.0, 1.0, 0.3))
                ci.draw_circle(ppos2, core_r, Color(0.9, 0.7, 1.0, 0.9))
                ci.draw_circle(ppos2, core_r * 0.5, Color(1.0, 1.0, 1.0, 1.0))


# Setup a Camera2D for the play area. With the design space now at 1920x1080
# (matching the viewport), the camera uses zoom = 1:1 and is positioned at
# (960, 540) = center of the design space. The camera is added to the Window
# root (NOT to the MainGame node) so it doesn't inherit any transform.
var _game_camera: Camera2D = null
func _setup_camera() -> void:
        if _game_camera != null:
                return
        _game_camera = Camera2D.new()
        _game_camera.name = "GameCamera"
        _game_camera.enabled = true
        # Center of the design space (1920x1080 → center = 960, 540).
        _game_camera.position = Vector2(float(C.WINDOW_WIDTH) * 0.5, float(C.WINDOW_HEIGHT) * 0.5)
        _game_camera.position_smoothing_enabled = false
        # Zoom = 1:1 since design space now matches the viewport size.
        _game_camera.zoom = Vector2(1.0, 1.0)
        # Add to the Window root so it's NOT a child of the scaled MainGame.
        get_tree().root.add_child(_game_camera)
        # Register with EffectsManager for screen-shake.
        if EffectsManager:
                EffectsManager.set_camera(_game_camera)


# Called when the background layer needs to redraw. Draws the procedural
# crypt background at native viewport resolution (not affected by camera zoom).
func _on_bg_layer_draw() -> void:
        if _bg_layer == null:
                return
        var vp_size: Vector2 = _bg_layer.size
        if vp_size.x < 1.0 or vp_size.y < 1.0:
                vp_size = get_viewport_rect().size
        if EnvironmentArt:
                EnvironmentArt.draw_crypt_background(_bg_layer, vp_size, _bg_anim_time)
        # Subtle dark overlay so the maze + HUD stand out.
        _bg_layer.draw_rect(Rect2(0, 0, vp_size.x, vp_size.y),
                Color(0, 0, 0, 0.30), true)


func _process(delta: float) -> void:
        _bg_anim_time += delta
        # Redraw the background layer every frame so the torches flicker and
        # the fog drifts (EnvironmentArt.draw_crypt_background is animated).
        if _bg_layer != null:
                _bg_layer.queue_redraw()
        # FIX (fulmini invisibili): ridisegna anche il foreground layer
        if _fg_drawer != null:
                _fg_drawer.queue_redraw()
        queue_redraw()


# Handle pause + ESC via _unhandled_input so they work even when the game
# tree is paused (process_mode = PROCESS_MODE_ALWAYS on this node).
func _unhandled_input(event: InputEvent) -> void:
        # FIX CRASH: get_viewport() può ritornare null quando il nodo è in
        # fase di uscita dalla scena. Usiamo una variabile locale con null check.
        if event.is_action_pressed("pause") and not event.is_echo():
                _toggle_pause()
                var vp: Viewport = get_viewport()
                if vp != null:
                        vp.set_input_as_handled()
                return
        if event.is_action_pressed("ui_cancel") and not event.is_echo():
                _return_to_menu()
                var vp2: Viewport = get_viewport()
                if vp2 != null:
                        vp2.set_input_as_handled()
                return


# Cleanup: when leaving the MainGame scene, remove the camera and background
# CanvasLayer from the Window root (they were added there to avoid inheriting
# the MainGame transform). Without this cleanup, they would persist into the
# next scene (e.g. MainMenu) and cause rendering issues.
func _exit_tree() -> void:
        if _game_camera != null and is_instance_valid(_game_camera):
                _game_camera.queue_free()
                _game_camera = null
        if _bg_canvas != null and is_instance_valid(_bg_canvas):
                _bg_canvas.queue_free()
                _bg_canvas = null


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
        # P1 input — keyboard OR joystick (joystick is read first if a pad is
        # connected, then keyboard is layered on top so the user can mix).
        # The C++ engine (Game.cpp:1417-1431) read both at once and picked the
        # dominant axis (whichever had |value| > 30%). We mirror that here.
        var p1_dx: int = 0
        var p1_dy: int = 0

        # FIX #5 (joystick doesn't move player):
        # The previous code gated the joystick block behind
        # `ConfigManager.p1_joystick_ready()` (which requires JOY_JUMP >= 0 AND
        # JOY_SHOOT >= 0). The user could move the joystick but the player
        # wouldn't move until they had ALSO gone through ConfigJoy to bind
        # jump+shoot buttons. The C++ engine never gated MOVEMENT on button
        # config — only jump/shoot buttons need to be configured. We now:
        #   * Always read joystick axes when a pad is connected (movement works
        #     out-of-the-box even without ConfigJoy).
        #   * For jump/shoot, fall back to JOY_BUTTON_A / JOY_BUTTON_B if the
        #     user hasn't configured custom bindings yet (so the game is
        #     playable immediately).
        var p1_joy_id: int = -1
        var joy_pads: Array = Input.get_connected_joypads()
        if joy_pads.size() > 0:
                p1_joy_id = joy_pads[0]
        # FIX: rimosso print debug joystick (config case-sensitive fixato in f79748f)
        if p1_joy_id >= 0:
                # Read the configured axes (default 0=X, 1=Y) — same as C++.
                var axis_x: float = Input.get_joy_axis(p1_joy_id, ConfigManager.joy_axis_x()) if ConfigManager else Input.get_joy_axis(p1_joy_id, 0)
                var axis_y: float = Input.get_joy_axis(p1_joy_id, ConfigManager.joy_axis_y()) if ConfigManager else Input.get_joy_axis(p1_joy_id, 1)
                # Deadzone 0.3 — mirrors C++ threshold fabs > 30/100.
                if absf(axis_x) > 0.3 or absf(axis_y) > 0.3:
                        # Dominant axis only — no diagonal movement (matches C++).
                        if absf(axis_x) > absf(axis_y):
                                p1_dx = 1 if axis_x > 0 else -1
                                p1_dy = 0
                        else:
                                p1_dx = 0
                                p1_dy = 1 if axis_y > 0 else -1
                else:
                        # D-pad as buttons fallback (some controllers expose the
                        # D-pad as JOY_BUTTON_DPAD_* instead of axes 6/7).
                        if Input.is_joy_button_pressed(p1_joy_id, JOY_BUTTON_DPAD_UP):
                                p1_dy = -1
                        elif Input.is_joy_button_pressed(p1_joy_id, JOY_BUTTON_DPAD_DOWN):
                                p1_dy = 1
                        elif Input.is_joy_button_pressed(p1_joy_id, JOY_BUTTON_DPAD_LEFT):
                                p1_dx = -1
                        elif Input.is_joy_button_pressed(p1_joy_id, JOY_BUTTON_DPAD_RIGHT):
                                p1_dx = 1
                        else:
                                # Hat axes fallback (axes 6/7 on many PC controllers)
                                var hat_x: float = Input.get_joy_axis(p1_joy_id, 6)
                                var hat_y: float = Input.get_joy_axis(p1_joy_id, 7)
                                if absf(hat_x) > 0.3 or absf(hat_y) > 0.3:
                                        if absf(hat_x) > absf(hat_y):
                                                p1_dx = 1 if hat_x > 0 else -1
                                        else:
                                                p1_dy = 1 if hat_y > 0 else -1

                # Joystick buttons for shoot/jump. If ConfigJoy has been run,
                # use the configured buttons. Otherwise fall back to the
                # common Xbox/PlayStation layout: A=jump, B=shoot (matches the
                # C++ fallback of "joy_jump if >=0 else 0" in some code paths).
                var joy_jump_btn: int = ConfigManager.joy_jump() if ConfigManager else -1
                var joy_shoot_btn: int = ConfigManager.joy_shoot() if ConfigManager else -1
                if joy_jump_btn < 0:
                        joy_jump_btn = JOY_BUTTON_A  # default: A button = jump
                if joy_shoot_btn < 0:
                        joy_shoot_btn = JOY_BUTTON_B  # default: B button = shoot
                if Input.is_joy_button_pressed(p1_joy_id, joy_jump_btn):
                        var was_jumping: bool = player.is_jumping()
                        player.activate_jump()
                        if not was_jumping and player.is_jumping() and AudioManager:
                                AudioManager.play_sound(AudioManager.SoundType.JUMP)
                if Input.is_joy_button_pressed(p1_joy_id, joy_shoot_btn) and player.shoot_cooldown == 0:
                        # FIX (dinamite): se il player ha la dinamite equipaggiata,
                        # il fuoco lancia il candelotto invece di sparare.
                        if dynamite_equipped:
                                _throw_dynamite()
                                player.shoot_cooldown = 300
                        else:
                                var ammo_before: int = player.current_weapon.get("ammo", 0)
                                player.shoot()
                                var ammo_after: int = player.current_weapon.get("ammo", 0)
                                if ammo_after < ammo_before and AudioManager:
                                        AudioManager.play_sound(AudioManager.SoundType.PISTOL)
                                player.shoot_cooldown = 150
        # FIX: rimossi i debug print ogni 60 frame ora che la config joystick
        # funziona correttamente (joy_jump/joy_shoot vengono caricati dal disco).

        # Keyboard arrows (always work, even without joystick).
        # Note: in C++ keyboard + joystick both contribute; whichever is
        # pressed wins. We let keyboard OVERRIDE the joystick if the user is
        # also pressing keys (common pattern when testing).
        if Input.is_action_pressed("move_up"):
                p1_dy = -1
        elif Input.is_action_pressed("move_down"):
                p1_dy = 1
        elif Input.is_action_pressed("move_left"):
                p1_dx = -1
        elif Input.is_action_pressed("move_right"):
                p1_dx = 1

        player.set_direction(p1_dx, p1_dy)

        # P1 keyboard shoot (also works without joystick — matches C++ fallback)
        if Input.is_action_just_pressed("shoot") and player.shoot_cooldown == 0:
                # FIX (dinamite): se il player ha la dinamite equipaggiata,
                # il fuoco lancia il candelotto invece di sparare.
                if dynamite_equipped:
                        _throw_dynamite()
                        player.shoot_cooldown = 300
                else:
                        var ammo_before: int = player.current_weapon.get("ammo", 0)
                        player.shoot()
                        var ammo_after: int = player.current_weapon.get("ammo", 0)
                        if ammo_after < ammo_before and AudioManager:
                                AudioManager.play_sound(AudioManager.SoundType.PISTOL)
                        player.shoot_cooldown = 150

        # P1 keyboard jump (also works without joystick)
        # FIX (spazio fa jump invece di saltare livello in test mode):
        # In test mode, Space serve per saltare il livello (o killare il boss),
        # NON per far saltare il player. Disabilitiamo il jump da tastiera
        # quando test mode è attivo. Il test_mode_skip viene gestito più sotto
        # nella stessa funzione.
        var test_mode_active: bool = GameManager and GameManager.test_mode_enabled
        if not test_mode_active:
                if Input.is_action_just_pressed("jump"):
                        var was_jumping: bool = player.is_jumping()
                        player.activate_jump()
                        if not was_jumping and player.is_jumping() and AudioManager:
                                AudioManager.play_sound(AudioManager.SoundType.JUMP)

        # P2 input (if 2 players)
        if GameManager and GameManager.num_players == 2 and player2.visible:
                var p2_dx: int = 0
                var p2_dy: int = 0
                # P2 keyboard: WASD (mirrors C++ defaults W/S/A/D)
                if Input.is_action_pressed("p2_up"):
                        p2_dy = -1
                elif Input.is_action_pressed("p2_down"):
                        p2_dy = 1
                elif Input.is_action_pressed("p2_left"):
                        p2_dx = -1
                elif Input.is_action_pressed("p2_right"):
                        p2_dx = 1
                # P2 joystick input (always read when a 2nd pad is connected —
                # same gating-fix logic as P1 above).
                var p2_joy_id: int = -1
                if joy_pads.size() > 1:
                        p2_joy_id = joy_pads[1]
                if p2_joy_id >= 0:
                        var ax2_cfg: int = ConfigManager.joy2_axis_x() if ConfigManager else 0
                        var ay2_cfg: int = ConfigManager.joy2_axis_y() if ConfigManager else 1
                        var axis_x2: float = Input.get_joy_axis(p2_joy_id, ax2_cfg)
                        var axis_y2: float = Input.get_joy_axis(p2_joy_id, ay2_cfg)
                        if absf(axis_x2) > 0.3 or absf(axis_y2) > 0.3:
                                if absf(axis_x2) > absf(axis_y2):
                                        p2_dx = 1 if axis_x2 > 0 else -1
                                        p2_dy = 0
                                else:
                                        p2_dx = 0
                                        p2_dy = 1 if axis_y2 > 0 else -1
                        else:
                                if Input.is_joy_button_pressed(p2_joy_id, JOY_BUTTON_DPAD_UP):
                                        p2_dy = -1
                                elif Input.is_joy_button_pressed(p2_joy_id, JOY_BUTTON_DPAD_DOWN):
                                        p2_dy = 1
                                elif Input.is_joy_button_pressed(p2_joy_id, JOY_BUTTON_DPAD_LEFT):
                                        p2_dx = -1
                                elif Input.is_joy_button_pressed(p2_joy_id, JOY_BUTTON_DPAD_RIGHT):
                                        p2_dx = 1
                        # P2 jump/shoot buttons (configured or fallback to A/B)
                        var j2_jump: int = ConfigManager.joy2_jump() if ConfigManager else -1
                        var j2_shoot: int = ConfigManager.joy2_shoot() if ConfigManager else -1
                        if j2_jump < 0:
                                j2_jump = JOY_BUTTON_A
                        if j2_shoot < 0:
                                j2_shoot = JOY_BUTTON_B
                        if Input.is_joy_button_pressed(p2_joy_id, j2_jump):
                                player2.activate_jump()
                        if Input.is_joy_button_pressed(p2_joy_id, j2_shoot) and player2.shoot_cooldown == 0:
                                player2.shoot()
                                player2.shoot_cooldown = 150
                player2.set_direction(p2_dx, p2_dy)
                if Input.is_action_just_pressed("p2_shoot") and player2.shoot_cooldown == 0:
                        player2.shoot()
                        player2.shoot_cooldown = 150
                if Input.is_action_just_pressed("p2_jump"):
                        player2.activate_jump()

        # Pause + ESC sono ora gestiti da _unhandled_input (funzionano anche
        # quando il game tree è in pausa grazie a process_mode=ALWAYS).

        # Test mode skip (Space) — mirrors C++ Game.cpp:2692-2714.
        # In boss levels, instant-kills the boss. Otherwise advances 1 level.
        if GameManager and GameManager.test_mode_enabled:
                var space_now: bool = Input.is_key_pressed(KEY_SPACE)
                if space_now and not test_skip_key_held:
                        _test_mode_skip()
                test_skip_key_held = space_now


func _return_to_menu() -> void:
        if AudioManager:
                AudioManager.stop_music()
        if GameManager:
                GameManager.go_to_menu()


# ============================================================================
# Main update loop (STATE_PLAYING)
# ============================================================================
func _update_playing(delta_ms: float) -> void:
        # (1) Player update + treasure pickup detection
        var treasures_before: int = maze.get_remaining_treasures()
        player.update_player(maze, false, delta_ms)
        if player.consume_picked_weapon():
                if AudioManager:
                        AudioManager.play_sound(AudioManager.SoundType.WEAPON_PICKUP)
        if GameManager and GameManager.num_players == 2 and player2.visible:
                player2.update_player(maze, false, delta_ms)
                if player2.consume_picked_weapon() and AudioManager:
                        AudioManager.play_sound(AudioManager.SoundType.WEAPON_PICKUP)
        if maze.get_remaining_treasures() < treasures_before:
                if AudioManager:
                        AudioManager.play_sound(AudioManager.SoundType.TREASURE)

        # (2) Enemies update
        var p_pos: Vector2 = player.get_pixel_pos()
        var p_grid: Vector2i = player.get_grid_pos()
        var player_invuln: bool = player.is_invulnerable()
        # Collect enemy projectiles in a real array (enemies that shoot add to it)
        var enemy_projectiles: Array = []
        for enemy in spawner.enemies:
                if not enemy.is_death_anim_done():
                        enemy.set_flee_mode(player_invuln)
                        enemy.update_enemy(maze, p_grid, p_pos, enemy_projectiles, delta_ms)

        # (3) Spawn enemy projectiles as Projectile nodes so they get rendered + collide
        for proj_data in enemy_projectiles:
                if not proj_data.get("active", false):
                        continue
                var proj_pos: Vector2 = proj_data.get("pos", Vector2.ZERO)
                var proj_dir: Vector2 = proj_data.get("dir", Vector2.ZERO)
                var proj_power: int = int(proj_data.get("power", 1))
                # FIX: verifica che la posizione di spawn non sia dentro un muro.
                # Se lo è, sposta il proiettile indietro verso il nemico finché
                # non trova una cella vuota.
                var spawn_col: int = int(proj_pos.x / C.TILE_SIZE)
                var spawn_row: int = int((proj_pos.y - C.UI_HEIGHT) / C.TILE_SIZE)
                if spawn_col >= 0 and spawn_col < C.MAZE_COLS and spawn_row >= 0 and spawn_row < C.MAZE_ROWS:
                        if maze.is_wall(spawn_col, spawn_row):
                                continue  # skip: proiettile spawnato dentro muro
                var p_node := Node2D.new()
                p_node.position = proj_pos
                p_node.set_meta("pos", proj_pos)
                p_node.set_meta("dir", proj_dir)
                p_node.set_meta("power", proj_power)
                p_node.set_meta("velocity", proj_dir * 6.0)
                p_node.visible = true
                enemy_projectiles_node.add_child(p_node)

        # (3b) Advance enemy projectiles (move them by their velocity)
        # FIX (proiettili nemici attraversano i muri): aggiunto wall collision
        # check. Se il proiettile entra in una cella WALL, viene distrutto.
        for proj in enemy_projectiles_node.get_children():
                if not proj is Node2D:
                        continue
                if not is_instance_valid(proj):
                        continue
                var vel: Vector2 = proj.get_meta("velocity", Vector2.ZERO)
                if vel == Vector2.ZERO:
                        proj.queue_free()
                        continue
                proj.position += vel
                # Wall collision: se il proiettile è in una cella WALL, distruggilo
                var pcol: int = int(proj.position.x / C.TILE_SIZE)
                var prow: int = int((proj.position.y - C.UI_HEIGHT) / C.TILE_SIZE)
                if pcol >= 0 and pcol < C.MAZE_COLS and prow >= 0 and prow < C.MAZE_ROWS:
                        if maze.is_wall(pcol, prow):
                                proj.queue_free()
                                continue
                # Remove if out of bounds
                if proj.position.x < 0 or proj.position.x > C.WINDOW_WIDTH or \
                   proj.position.y < C.UI_HEIGHT or proj.position.y > C.WINDOW_HEIGHT:
                        proj.queue_free()

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

        # (7b) 2P friendly fire: if both players are within contact range
        # (~28 px, dist^2 < 800) and neither is invulnerable or jumping,
        # both take 1 damage. Mirrors C++ Game.cpp 1846-1862.
        _check_2p_friendly_fire()

        # (8) Death check
        _check_death()

        # (9) Collectibles update + collision with player
        _update_collectibles(delta_ms)

        # (9b) Mine vs enemies collision (FIX: la bomba deve esplodere all'impatto)
        _check_mine_vs_enemies()

        # (9c) KnightAlly update (FIX: nuova meccanica cavaliere alleato)
        _update_knight_ally(delta_ms)

        # (9d) Dynamite update (FIX: nuova meccanica dinamite)
        _update_dynamite(delta_ms)

        # (9e) Last hit enemy timer (FIX: HUD nemico colpito)
        if last_hit_enemy_timer_ms > 0:
                last_hit_enemy_timer_ms -= int(delta_ms)
                if last_hit_enemy_timer_ms <= 0:
                        last_hit_enemy = null
        # Se il nemico è morto o non più valido, cleanup
        if last_hit_enemy != null and (not is_instance_valid(last_hit_enemy) or last_hit_enemy.is_dead()):
                last_hit_enemy = null
                last_hit_enemy_timer_ms = 0

        # (10) Exit door logic (treasures collected)
        _update_exit_door(delta_ms)

        # (11) Magic portal (50% enemies killed) - spawn mini-boss too
        spawner.trigger_portal_if_needed(maze, p_pos, _spawn_mini_boss)
        spawner.update_portal(maze, int(delta_ms))

        # (11b) MiniBoss update + melee collision (mirror C++ riga 1581-1633)
        # FIX CRASH: MiniBoss espone update_step(maze, p_grid, p_pos, delta_ms)
        # non update_enemy(). Il crash "Nonexistent function 'update_enemy'"
        # bloccava il gioco dopo qualche minuto quando il portal spawnava un
        # mini-boss.
        if mini_boss != null and not mini_boss.is_dead():
                mini_boss.set_flee_mode(player_invuln)
                mini_boss.update_step(maze, p_grid, p_pos, int(delta_ms))
                # MiniBoss melee attack: if attacking and player in range, damage
                # FIX CRASH: MiniBoss non ha get_pixel_pos(); usa la property
                # `pos` (Vector2) direttamente con .get().
                if mini_boss.has_method("is_attacking") and mini_boss.is_attacking():
                        var mb_pos: Vector2 = mini_boss.get("pos") if mini_boss.get("pos") != null else Vector2.ZERO
                        var mb_range: float = 36.0  # default attack range
                        if mini_boss.has_method("get_attack_range"):
                                mb_range = mini_boss.get_attack_range()
                        if p_pos.distance_squared_to(mb_pos) < (mb_range + 10) ** 2:
                                if not player.is_invulnerable() and not player.is_jumping():
                                        var mb_dmg: int = 5  # default
                                        if mini_boss.has_method("get_attack_damage"):
                                                mb_dmg = mini_boss.get_attack_damage()
                                        var num_hits: int = max(1, mb_dmg / 5)
                                        for _i in num_hits:
                                                player.take_damage()
                                        if AudioManager:
                                                AudioManager.play_sound(AudioManager.SoundType.LOSE_LIFE)
        # MiniBoss death cleanup
        if mini_boss != null and mini_boss.is_dead():
                var score_reward: int = 5000
                if mini_boss.has_method("get_score_reward"):
                        score_reward = mini_boss.get_score_reward()
                player.add_score(score_reward)
                if EffectsManager:
                        var p := EffectsManager.spawn_explosion(mini_boss.position,
                                Color(0.8, 0.2, 0.1), 30, 0.8)
                        collectibles_node.add_child(p)
                mini_boss.queue_free()
                mini_boss = null

        # (11c) Scepter lightning strikes (5 strikes at 3s intervals)
        if scepter_active:
                scepter_timer_ms -= int(delta_ms)
                if scepter_timer_ms <= 0 and scepter_strikes_left > 0:
                        _fire_lightning_strike()
                        scepter_strikes_left -= 1
                        scepter_timer_ms = 3000  # 3s between strikes
                        if scepter_strikes_left == 0:
                                scepter_active = false

        # (12) Remove dead enemies
        spawner.remove_dead()

        # (13) Update particles
        _update_particles(delta_ms)

        # (13b) Update decals (blood stains, ash piles, fire bursts)
        _update_decals(delta_ms)

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
                var hit_something: bool = false
                for enemy in spawner.enemies:
                        if enemy.is_dead():
                                continue
                        var e_pos: Vector2 = enemy.get_pixel_pos()
                        if proj_pos.distance_squared_to(e_pos) < 600.0:
                                enemy.take_damage(int(proj.get("power", 1)))
                                proj["active"] = false
                                # FIX (HUD last hit enemy): traccia il nemico colpito
                                # SOLO nel labirinto (non boss room). Nella boss room
                                # la barra HP è gestita dal BossRoomController.
                                if not is_boss_state:
                                        last_hit_enemy = enemy
                                        last_hit_enemy_timer_ms = 3000  # 3s di visibilità
                                if enemy.is_dead():
                                        p.add_score(5000)
                                        if AudioManager:
                                                AudioManager.play_sound(AudioManager.SoundType.ENEMY_DEATH)
                                                AudioManager.play_sound(AudioManager.SoundType.BLOOD_SPLAT)
                                                AudioManager.play_sound(AudioManager.SoundType.ENEMY_EXPLODE)
                                        _spawn_blood_stain(e_pos)
                                        _spawn_fire_burst(e_pos, 1.0)
                                hit_something = true
                                break
                # FIX (mid-boss immune): controlla anche il mini-boss.
                # Prima i proiettili passavano attraverso il mini-boss senza
                # fare danno perché non era incluso nel loop degli enemies.
                if not hit_something and mini_boss != null and is_instance_valid(mini_boss):
                        if not mini_boss.is_dead():
                                var mb_pos: Vector2 = mini_boss.get_pixel_pos()
                                var mb_dist_sq: float = proj_pos.distance_squared_to(mb_pos)
                                if mb_dist_sq < 1200.0:  # FIX: 900→1200 (radius ~35px)
                                        var dmg: int = int(proj.get("power", 1))
                                        print("[MiniBoss] Hit! dist_sq=", mb_dist_sq, " dmg=", dmg, " hp_before=", mini_boss.health)
                                        mini_boss.take_damage(dmg)
                                        print("[MiniBoss] hp_after=", mini_boss.health)
                                        proj["active"] = false
                                        if AudioManager:
                                                AudioManager.play_sound(AudioManager.SoundType.BOSS_HIT)
                                        if mini_boss.is_dead():
                                                p.add_score(10000)
                                                if AudioManager:
                                                        AudioManager.play_sound(AudioManager.SoundType.BOSS_DEATH)


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


# FIX (bomba non esplode all'impatto): controlla collisione tra la mine
# (quando sta bouncing) e i nemici. Se la mine tocca un nemico, esplode:
# danno ad area (radius 60px), particelle esplosione, screen shake,
# sparisce immediatamente invece di rimanere per terra immobile.
# FIX (bomba supera muri): controlla collisione tra la mine (quando bouncing)
# e i muri del maze. Se la mine sta per entrare in una cella WALL, la ferma
# e inverte la velocità (rimbalzo elastico).
func _check_mine_vs_enemies() -> void:
        if mine_item == null or not is_instance_valid(mine_item):
                return
        if not mine_item.get("bouncing"):
                return
        # FIX (bomba supera muri): wall collision check
        var mine_pos2: Vector2 = mine_item.position
        var mine_vel: Vector2 = mine_item.get("velocity") if mine_item.get("velocity") != null else Vector2.ZERO
        # Calcola la cella attuale e la cella destinazione
        var cur_col: int = int(mine_pos2.x / C.TILE_SIZE)
        var cur_row: int = int((mine_pos2.y - C.UI_HEIGHT) / C.TILE_SIZE)
        var next_col: int = int((mine_pos2.x + mine_vel.x) / C.TILE_SIZE)
        var next_row: int = int((mine_pos2.y + mine_vel.y - C.UI_HEIGHT) / C.TILE_SIZE)
        # Se la cella destinazione è un muro, inverti la velocità
        if next_col != cur_col and maze.is_wall(next_col, cur_row):
                mine_vel.x = -mine_vel.x * 0.7  # damped bounce
                mine_pos2.x = cur_col * C.TILE_SIZE + C.TILE_SIZE / 2.0
        if next_row != cur_row and maze.is_wall(cur_col, next_row):
                mine_vel.y = -mine_vel.y * 0.7
                mine_pos2.y = cur_row * C.TILE_SIZE + C.TILE_SIZE / 2.0 + C.UI_HEIGHT
        # Aggiorna posizione e velocità della mine
        mine_item.position = mine_pos2
        mine_item.set("velocity", mine_vel)
        mine_item.set("pos", mine_pos2)
        # Damage check
        var blast_radius: float = 60.0
        var blast_radius_sq: float = blast_radius * blast_radius
        var hit_any: bool = false
        for enemy in spawner.enemies:
                if enemy.is_dead():
                        continue
                var e_pos: Vector2 = enemy.get_pixel_pos()
                if mine_pos2.distance_squared_to(e_pos) < blast_radius_sq:
                        enemy.take_damage(999)
                        enemy.start_burning(30)
                        player.add_score(2000)
                        hit_any = true
        if mini_boss != null and not mini_boss.is_dead():
                var mb_pos: Vector2 = mini_boss.get_pixel_pos()
                if mine_pos2.distance_squared_to(mb_pos) < blast_radius_sq:
                        var mb_max_hp: int = mini_boss.get_max_health()
                        mini_boss.take_damage(int(mb_max_hp * 0.5))
                        hit_any = true
        if hit_any:
                if EffectsManager:
                        var burst := EffectsManager.spawn_explosion(mine_pos2,
                                Color(1.0, 0.4, 0.1), 40, 1.0)
                        collectibles_node.add_child(burst)
                        EffectsManager.screen_shake(12.0, 0.4)
                if AudioManager:
                        AudioManager.play_sound(AudioManager.SoundType.ENEMY_EXPLODE)
                mine_item.set("bouncing", false)
                mine_item.set("active", false)
                mine_item.queue_free()
                mine_item = null
                screen_flash_timer_ms = 80


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
        # FIX (nuova meccanica): i nemici attaccano anche il cavaliere alleato
        # se è attivo e vicino al nemico. Il cavaliere è un "player" bersaglio.
        if knight_ally != null and is_instance_valid(knight_ally):
                var ka_pos: Vector2 = knight_ally.get_pixel_pos() if knight_ally.has_method("get_pixel_pos") else Vector2.ZERO
                for enemy in spawner.enemies:
                        if enemy.is_dead():
                                continue
                        if ka_pos.distance_squared_to(enemy.get_pixel_pos()) < 800.0:
                                if knight_ally.has_method("take_damage"):
                                        knight_ally.take_damage(1)
                                break


func _update_invincible_burn(p: CharacterBody2D, delta_ms: float) -> void:
        # Finalise burning enemies: when burning_timer reaches 0 but the
        # burned_flag is still set, kill the enemy and spawn AshPile +
        # final FireBurst. Mirrors Game.cpp lines 2314-2342 (the separate
        # "burning -> death transition" pass that runs every frame, even
        # after the player's invincibility expired, to ensure every ignited
        # enemy is finalised).
        for enemy in spawner.enemies:
                if enemy.is_burning() or not enemy.was_burned():
                        continue
                if enemy.is_dead():
                        # Already dead (e.g. another system killed it): just
                        # clear the flag so we don't re-trigger next frame.
                        enemy.clear_burned_flag()
                        continue
                # Burning finished but enemy still alive: finalise the kill.
                enemy.clear_burned_flag()
                var dead_pos: Vector2 = enemy.get_pixel_pos()
                enemy.take_damage(999)
                p.add_score(5000)
                _spawn_ash_pile(dead_pos)
                _spawn_fire_burst(dead_pos, 0.9)
                if AudioManager:
                        AudioManager.play_sound(AudioManager.SoundType.ENEMY_EXPLODE)

        # Chalice effect: while invincible_timer > 0, enemies in contact burn
        if p.invincible_timer <= 0:
                return
        p.invincible_timer = max(0, p.invincible_timer - int(delta_ms))
        if p.invincible_timer <= 0:
                # FIX (musica calice): ferma la musica epic quando l'effetto
                # del calice termina (15 secondi)
                if AudioManager:
                        AudioManager.stop_epic_music()
                        if GameManager and GameManager.music_enabled:
                                AudioManager.play_level_music(current_level, false)
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
        # Also burn mini-boss if present
        if mini_boss != null and not mini_boss.is_dead() and not mini_boss.is_burning():
                var mb_pos: Vector2 = mini_boss.get_pixel_pos()
                if p_pos.distance_squared_to(mb_pos) < 1200.0:
                        mini_boss.start_burning(50)
                        p.add_score(2000)


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


# 2P friendly fire: when both players touch each other (distance^2 < 800,
# i.e. ~28 px), and neither is invulnerable (post-hit or chalice) or
# mid-jump, both take 1 energy damage. Mirrors C++ Game.cpp 1846-1862.
func _check_2p_friendly_fire() -> void:
        if GameManager == null or GameManager.num_players != 2:
                return
        if not player2.visible:
                return
        # Skip if either player is invulnerable or jumping.
        if player.is_invulnerable() or player2.is_invulnerable():
                return
        if player.is_jumping() or player2.is_jumping():
                return
        var p1_pos: Vector2 = player.get_pixel_pos()
        var p2_pos: Vector2 = player2.get_pixel_pos()
        if p1_pos.distance_squared_to(p2_pos) >= 800.0:
                return
        # Both players take 1 damage. Player.take_damage() returns early
        # if is_jumping() or is_invulnerable(), so the guard above is
        # sufficient. Track lives/energy before to detect a real hit and
        # only then play LOSE_LIFE (mirrors C++ r1855-1860).
        var lives_before1: int = player.lives
        var energy_before1: int = player.energy
        var lives_before2: int = player2.lives
        var energy_before2: int = player2.energy
        player.take_damage()
        player2.take_damage()
        if player.lives < lives_before1 or player.energy < energy_before1 \
                or player2.lives < lives_before2 or player2.energy < energy_before2:
                if AudioManager:
                        AudioManager.play_sound(AudioManager.SoundType.LOSE_LIFE)


# ============================================================================
# Collectibles update + collision with player
# ============================================================================
func _update_collectibles(delta_ms: float) -> void:
        var p1_pos: Vector2 = player.get_pixel_pos()
        var p2_pos: Vector2 = Vector2.ZERO
        if GameManager and GameManager.num_players == 2 and player2.visible:
                p2_pos = player2.get_pixel_pos()
        # FIX (statua appare subito): rimosso il delay timer 5-15s.
        # La statua ora è active=true da subito, come le altre armi.
        for child in collectibles_node.get_children():
                if not child is Node2D:
                        continue
                # Skip GPUParticles2D (spawned by EffectsManager for visual effects)
                if child is GPUParticles2D:
                        continue
                # Skip nodes that don't have update_step (defensive)
                if not child.has_method("update_step"):
                        continue
                # Update item animation/behavior
                child.update_step(delta_ms, p1_pos, 1)
                if not child.has_method("get") or not child.get("active"):
                        continue
                var item_pos: Vector2 = child.pos
                # Check P1 collision
                # FIX (salto sopra oggetti): se il player sta saltando, non
                # raccoglie armi/bombe per evitare di perderle. MA raccoglie
                # comunque calice, scettro, medikit, statua, dinamite, tesori
                # perché sono oggetti importanti che non vanno persi.
                var can_pickup: bool = true
                if player.is_jumping():
                        var kind_val: int = child.get("kind")
                        # Solo armi/bombe non si raccolgono durante salto
                        if kind_val == CollectiblesClass.Kind.MINE:
                                can_pickup = false
                if can_pickup and p1_pos.distance_squared_to(item_pos) < 400.0:
                        _on_collectible_picked_up(child, player, 1)
                        continue
                # Check P2 collision
                if GameManager and GameManager.num_players == 2 and player2.visible:
                        var can_pickup2: bool = true
                        if player2.is_jumping():
                                var kind_val2: int = child.get("kind")
                                if kind_val2 == CollectiblesClass.Kind.MINE:
                                        can_pickup2 = false
                        if can_pickup2 and p2_pos.distance_squared_to(item_pos) < 400.0:
                                _on_collectible_picked_up(child, player2, 2)


func _on_collectible_picked_up(item: Node2D, p: CharacterBody2D, player_id: int) -> void:
        var kind_int: int = item.kind
        match kind_int:
                CollectiblesClass.Kind.MINE:
                        # FIX (bomba scompare subito): velocità iniziale troppo alta
                        # (randf()*4-2)*50 = fino a 100px/frame → la bomba usciva
                        # dallo schermo in 1-2 frame. Ridotta a *5 (max 10px/frame).
                        # FIX (durata bomba): 5000ms → 10000ms (10 secondi) per
                        # dare tempo alla bomba di rimbalzare e colpire i nemici.
                        item.start_bounce(Vector2(randf() * 4 - 2, randf() * 4 - 2) * 5, 10000)
                        if AudioManager:
                                AudioManager.play_sound(AudioManager.SoundType.TRAP)
                CollectiblesClass.Kind.CHALICE:
                        p.set_invincible_timer(15000)  # 15s chalice invincibility
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
                                AudioManager.play_sound(AudioManager.SoundType.SCEPTER_PICKUP)
                        if AudioManager and AudioManager.music_enabled:
                                AudioManager.play_epic_music(7)  # TRACK_EPIC_SCEPTER
                        # Activate 5 lightning strikes at 3s intervals
                        scepter_active = true
                        scepter_strikes_left = 5
                        scepter_timer_ms = 500  # first strike after 0.5s
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
                        # FIX (tesori counter): quando il player raccoglie un
                        # collectible TREASURE, trova la cella TREASURE del maze
                        # più vicina e la rimuove (collect_treasure). Questo
                        # decrementa maze.get_remaining_treasures() e attiva
                        # l'exit door quando tutti i tesori sono raccolti.
                        var p_pos_t: Vector2 = p.get_pixel_pos()
                        var p_col_t: int = int(p_pos_t.x / C.TILE_SIZE)
                        var p_row_t: int = int((p_pos_t.y - C.UI_HEIGHT) / C.TILE_SIZE)
                        # Cerca la cella TREASURE più vicina in raggio 3
                        var found_treasure: bool = false
                        for r in range(p_row_t - 3, p_row_t + 4):
                                for c in range(p_col_t - 3, p_col_t + 4):
                                        if maze.get_cell_type(c, r) == C.CellType.TREASURE:
                                                maze.collect_treasure(c, r)
                                                found_treasure = true
                                                break
                                if found_treasure:
                                        break
                CollectiblesClass.Kind.MEDIKIT:
                        # FIX (nuova meccanica): rigenera 1 punto vita del player.
                        # L'effetto è come se fosse stato toccato dal nemico una
                        # volta in meno (quindi +1 HP, capped a max HP del player).
                        # Suono: POTION_DRINK (effetto ingoia/declutisce pillola).
                        if p.lives < 99:  # safety cap
                                # Player ha lives (3 default), rigenera 1 = +1 vita
                                p.lives = p.lives + 1
                        item.active = false
                        item.queue_free()
                        medikit_item = null
                        if AudioManager:
                                AudioManager.play_sound(AudioManager.SoundType.POTION_DRINK)
                        # Particelle heal (verde/croce)
                        if EffectsManager:
                                var burst := EffectsManager.spawn_pickup_burst(p.get_pixel_pos(),
                                        Color(0.3, 1.0, 0.3))
                                collectibles_node.add_child(burst)
                CollectiblesClass.Kind.KNIGHT_STATUE:
                        # FIX (nuova meccanica): evoca cavaliere alleato.
                        # Il cavaliere appare accanto al player e combatte.
                        item.active = false
                        item.queue_free()
                        knight_statue_item = null
                        _spawn_knight_ally(p.get_pixel_pos())
                        if AudioManager:
                                AudioManager.play_sound(AudioManager.SoundType.WEAPON_PICKUP)
                        # Particelle evocazione (blu mistico)
                        if EffectsManager:
                                var burst := EffectsManager.spawn_pickup_burst(p.get_pixel_pos(),
                                        Color(0.4, 0.7, 1.0))
                                collectibles_node.add_child(burst)
                CollectiblesClass.Kind.DYNAMITE:
                        # FIX (nuova meccanica): candelotto di dinamite.
                        # Animazione accensione miccia (0.8s), poi player equipaggia.
                        # La miccia brucia per 7s, poi alert + 2s esplosione.
                        item.active = false
                        item.queue_free()
                        dynamite_item = null
                        _start_dynamite_pickup(p)


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
        # FIX (nemici precedenti rimangono): clear tutti i nemici, proiettili,
        # collectibles e decals del livello precedente prima di generare il nuovo.
        spawner.clear()
        for proj in projectiles_node.get_children():
                proj.queue_free()
        for proj in enemy_projectiles_node.get_children():
                proj.queue_free()
        for item in collectibles_node.get_children():
                item.queue_free()
        blood_stains.clear()
        ash_piles.clear()
        fire_bursts.clear()
        particles.clear()
        lightning_bolts.clear()
        scepter_active = false
        scepter_strikes_left = 0
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
        # Clear mini-boss + scepter state
        if mini_boss != null:
                mini_boss.queue_free()
                mini_boss = null
        mini_boss_spawned = false
        scepter_active = false
        scepter_strikes_left = 0
        scepter_timer_ms = 0
        lightning_bolts.clear()
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
        # Clear decals (port of C++ Game::startLevel lines 169-171)
        blood_stains.clear()
        ash_piles.clear()
        fire_bursts.clear()
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
        # FIX (cache stale): pulisce la cache delle texture collectible
        # all'inizio di ogni livello per forzare il ricaricamento dei PNG.
        CollectiblesClass.clear_texture_cache()
        chalice_item = null
        scepter_item = null
        mine_item = null
        speed_boots_item = null
        speed_boots2_item = null
        # FIX (nuova meccanica): reset medikit + knight_statue
        medikit_item = null
        knight_statue_item = null
        if knight_ally != null and is_instance_valid(knight_ally):
                knight_ally.queue_free()
                knight_ally = null
        medikit_used = false
        knight_statue_spawned = false
        # FIX (nuova meccanica): reset dinamite
        dynamite_item = null
        dynamite_spawned = false
        dynamite_equipped = false
        dynamite_fuse_timer_ms = 0
        dynamite_alert_played = false
        dynamite_explode_timer_ms = 0
        if dynamite_thrown != null and is_instance_valid(dynamite_thrown):
                dynamite_thrown.queue_free()
                dynamite_thrown = null
        # FIX (HUD last hit enemy): reset al cambio livello
        last_hit_enemy = null
        last_hit_enemy_timer_ms = 0

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

        # FIX (nuova meccanica): Medikit (1 per livello, posizione casuale)
        if empty_cells.size() > 0:
                var cell: Vector2i = empty_cells.pop_back()
                var medikit_pos := _cell_to_pixel(cell)
                medikit_item = _create_collectible(CollectiblesClass.Kind.MEDIKIT, medikit_pos)
                collectibles_node.add_child(medikit_item)

        # FIX (nuova meccanica): Statua cavaliere (1 per livello, posizione casuale)
        # FIX (statua appare subito): prima active=false con delay 5-15s, ora
        # active=true da subito come le altre armi (medikit, chalice, ecc.)
        if empty_cells.size() > 0:
                var cell: Vector2i = empty_cells.pop_back()
                var statue_pos := _cell_to_pixel(cell)
                knight_statue_item = _create_collectible(CollectiblesClass.Kind.KNIGHT_STATUE, statue_pos)
                knight_statue_item.active = true
                collectibles_node.add_child(knight_statue_item)

        # FIX (nuova meccanica): Dinamite (1 per livello, posizione casuale)
        if empty_cells.size() > 0:
                var cell: Vector2i = empty_cells.pop_back()
                var dyn_pos := _cell_to_pixel(cell)
                dynamite_item = _create_collectible(CollectiblesClass.Kind.DYNAMITE, dyn_pos)
                collectibles_node.add_child(dynamite_item)


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


# ============================================================================
# MiniBoss spawn (called by EnemySpawner.trigger_portal_if_needed)
# ============================================================================
const MiniBossClass = preload("res://scripts/bosses/MiniBoss.gd")

func _spawn_mini_boss(col: int, row: int) -> void:
        if mini_boss_spawned:
                return
        var mb_type: int = (current_level - 1) % 51  # cycle through 51 types
        var mb := MiniBossClass.new()
        mb.setup(mb_type, current_level, col, row)
        add_child(mb)
        mini_boss = mb
        mini_boss_spawned = true
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.PORTAL_OPEN)


# FIX (nuova meccanica): spawn cavaliere alleato evocato dalla statua.
# Il cavaliere appare accanto al player con animazione di "materializzazione".
const KnightAllyClass = preload("res://scripts/entities/KnightAlly.gd")

func _spawn_knight_ally(player_pos: Vector2) -> void:
        if knight_ally != null and is_instance_valid(knight_ally):
                return  # già evocato
        var ka := KnightAllyClass.new()
        # Stessa energia del player (lives = 3 default)
        # FIX (cavaliere energia 1.5x): energia = lives del player * 1.5
        # Player ha 3 lives → cavaliere ha 4.5 → arrotondato a 5
        var base_health: int = player.lives if player != null else 3
        ka.max_health = int(float(base_health) * 1.5) + 1
        ka.health = ka.max_health
        # Posizione: accanto al player (offset 48px a destra)
        var spawn_pos: Vector2 = player_pos + Vector2(48, 0)
        ka.pos = spawn_pos
        add_child(ka)
        knight_ally = ka
        ka.update_ally(maze, player_pos, spawner.enemies, 0)
        print("[KnightAlly] Spawned at ", spawn_pos, " health=", ka.health, " state=", ka.state)


# FIX (nuova meccanica): update del cavaliere alleato.
# Chiamato da _update_playing per movimento AI + shooting + check morte.
func _update_knight_ally(delta_ms: int) -> void:
        if knight_ally == null or not is_instance_valid(knight_ally):
                knight_ally = null
                return
        var ka2: Node2D = knight_ally
        if ka2.has_method("update_ally"):
                ka2.mini_boss = mini_boss
                ka2.update_ally(maze, player.get_pixel_pos(), spawner.enemies, int(delta_ms))
        # Se il cavaliere è morto (scomparso), cleanup
        if ka2.has_method("is_dead") and ka2.is_dead():
                ka2.queue_free()
                knight_ally = null


# ============================================================================
# Dynamite (nuova meccanica): candelotto di dinamite con miccia.
# Flow:
#   1. Player raccoglie DYNAMITE → _start_dynamite_pickup
#      - Animazione accensione miccia (0.8s, scintille)
#      - Suono accensione (TRAP o MINE_BOUNCE)
#      - Equip dinamite (dynamite_equipped = true)
#   2. Player preme fuoco → _throw_dynamite
#      - Candelotto lanciato nella direzione del player
#      - Se colpisce nemico/mid-boss → instant kill + esplosione
#      - Se non colpisce → continua fino a muro/schermo
#   3. Se player NON preme fuoco entro 7s:
#      - dynamite_alert_played = true, suono alert (BOSS_HIT o LOSE_LIFE)
#      - Dopo 2s → _explode_dynamite (esplosione che uccide il player)
# ============================================================================

# Avvia l'animazione di accensione miccia + equip
func _start_dynamite_pickup(p: CharacterBody2D) -> void:
        # Animazione accensione: 0.8s di scintille
        if EffectsManager:
                # Particelle scintille alla posizione del player
                var burst := EffectsManager.spawn_sparks(p.get_pixel_pos(), 12)
                collectibles_node.add_child(burst)
                EffectsManager.screen_shake(2.0, 0.2)
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.TRAP)
        # Equip immediato (l'animazione è gestita nel _draw del player)
        dynamite_equipped = true
        dynamite_fuse_timer_ms = 7000  # 7 secondi
        dynamite_alert_played = false
        dynamite_explode_timer_ms = 0
        print("[Dynamite] Player equipped dynamite, fuse 7s")


# Update della dinamite equipaggiata (chiamato da _update_playing)
func _update_dynamite(delta_ms: int) -> void:
        # Aggiorna candelotto lanciato se in volo
        if dynamite_thrown != null and is_instance_valid(dynamite_thrown):
                _update_thrown_dynamite(delta_ms)
                # Sync player rendering state
                player.set_dynamite_equipped(false, 0, false)
                return
        if not dynamite_equipped:
                # Assicurati che il player non disegni la dinamite
                player.set_dynamite_equipped(false, 0, false)
                return
        # Timer miccia
        if dynamite_fuse_timer_ms > 0:
                dynamite_fuse_timer_ms -= int(delta_ms)
                if dynamite_fuse_timer_ms <= 0 and not dynamite_alert_played:
                        # Miccia smette di fare scintille, suono alert
                        dynamite_alert_played = true
                        dynamite_explode_timer_ms = 2000  # 2s prima dell'esplosione
                        if AudioManager:
                                AudioManager.play_sound(AudioManager.SoundType.LOSE_LIFE)
                        print("[Dynamite] ALERT! Fuse done, explode in 2s")
        elif dynamite_alert_played:
                # Countdown esplosione
                dynamite_explode_timer_ms -= int(delta_ms)
                if dynamite_explode_timer_ms <= 0:
                        _explode_dynamite(false)  # false = non lanciata, uccide player
        # Sync player rendering state (per disegnare candelotto + scintille/fumo)
        player.set_dynamite_equipped(dynamite_equipped, dynamite_fuse_timer_ms, dynamite_alert_played)


# Lancia il candelotto di dinamite
func _throw_dynamite() -> void:
        if not dynamite_equipped:
                print("[Dynamite] _throw_dynamite called but dynamite_equipped=false!")
                return
        print("[Dynamite] Throwing! player pos=", player.get_pixel_pos())
        var dir: Vector2 = Vector2(player.last_dx, player.last_dy)
        if dir == Vector2.ZERO:
                dir = Vector2(1, 0)
        dir = dir.normalized()
        # FIX (dinamite esplode subito): offset aumentato da 24 a 40px per
        # evitare che il candelotto spawni dentro un muro o troppo vicino
        # al player. Aggiunto grace_period_ms per non checkare collisioni
        # nei primi 200ms (lascia che il candelotto si allontani).
        var spawn_pos: Vector2 = player.get_pixel_pos() + dir * 40.0
        # Crea nodo candelotto lanciato
        var proj := Node2D.new()
        proj.position = spawn_pos
        proj.set_meta("dir", dir * 8.0)  # velocità aumentata da 6 a 8
        proj.set_meta("life_ms", 2000)  # max 2s di volo
        proj.set_meta("grace_ms", 200)  # FIX: 200ms senza collision check
        proj.set_meta("active", true)
        enemy_projectiles_node.add_child(proj)
        dynamite_thrown = proj
        dynamite_equipped = false
        dynamite_fuse_timer_ms = 0
        dynamite_alert_played = false
        print("[Dynamite] Thrown! pos=", spawn_pos)


# Update del candelotto lanciato in volo
func _update_thrown_dynamite(delta_ms: int) -> void:
        if dynamite_thrown == null or not is_instance_valid(dynamite_thrown):
                dynamite_thrown = null
                return
        var dt: Node2D = dynamite_thrown
        var vel: Vector2 = dt.get_meta("dir", Vector2.ZERO)
        var life: int = dt.get_meta("life_ms", 2000)
        life -= int(delta_ms)
        dt.set_meta("life_ms", life)
        if life <= 0:
                _explode_dynamite(true, dt.position)
                dt.queue_free()
                dynamite_thrown = null
                return
        # FIX (grace period): riduci il grace_ms, non checkare collisioni
        # finché grace_ms > 0 (lascia che il candelotto si allontani dal player)
        var grace: int = dt.get_meta("grace_ms", 0)
        if grace > 0:
                grace -= int(delta_ms)
                dt.set_meta("grace_ms", grace)
                # Muovi ma non checkare collisioni
                dt.position += vel
                return
        # Muovi
        dt.position += vel
        # Wall collision: se colpisce muro, esplode
        var col: int = int(dt.position.x / C.TILE_SIZE)
        var row: int = int((dt.position.y - C.UI_HEIGHT) / C.TILE_SIZE)
        if maze.is_wall(col, row):
                _explode_dynamite(true, dt.position)
                dt.queue_free()
                dynamite_thrown = null
                return
        # Enemy collision: instant kill
        for enemy in spawner.enemies:
                if enemy.is_dead():
                        continue
                if dt.position.distance_squared_to(enemy.get_pixel_pos()) < 600.0:
                        enemy.take_damage(999)
                        enemy.start_burning(30)
                        player.add_score(2000)
                        _explode_dynamite(true, dt.position)
                        dt.queue_free()
                        dynamite_thrown = null
                        return
        # Mini-boss collision: instant kill
        if mini_boss != null and not mini_boss.is_dead():
                if dt.position.distance_squared_to(mini_boss.get_pixel_pos()) < 900.0:
                        var mb_max_hp: int = mini_boss.get_max_health()
                        mini_boss.take_damage(mb_max_hp)  # instant kill
                        _explode_dynamite(true, dt.position)
                        dt.queue_free()
                        dynamite_thrown = null
                        return


# Esplosione dinamite
# thrown=true: candelotto lanciato, uccide nemici in raggio
# thrown=false: dinamite in mano al player, uccide il player
func _explode_dynamite(thrown: bool, at_pos: Vector2 = Vector2.ZERO) -> void:
        var pos: Vector2 = at_pos if thrown else player.get_pixel_pos()
        # Particelle esplosione
        if EffectsManager:
                var burst := EffectsManager.spawn_explosion(pos,
                        Color(1.0, 0.4, 0.1), 50, 1.2)
                collectibles_node.add_child(burst)
                EffectsManager.screen_shake(15.0, 0.5)
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.ENEMY_EXPLODE)
        screen_flash_timer_ms = 120
        if not thrown:
                # Dinamite in mano: uccide il player
                player.take_damage()
                print("[Dynamite] BOOM! Player killed by dynamite")
        else:
                # Candelotto lanciato: danno ad area in raggio 80px
                var blast_sq: float = 80.0 * 80.0
                for enemy in spawner.enemies:
                        if enemy.is_dead():
                                continue
                        if pos.distance_squared_to(enemy.get_pixel_pos()) < blast_sq:
                                enemy.take_damage(999)
                                enemy.start_burning(30)
                                player.add_score(2000)
        # Cleanup stato
        dynamite_equipped = false
        dynamite_fuse_timer_ms = 0
        dynamite_alert_played = false
        dynamite_explode_timer_ms = 0


# ============================================================================
# Scepter lightning strike (full-screen, hits all enemies on path)
# ============================================================================
func _fire_lightning_strike() -> void:
        # Generate a full-screen zigzag lightning with 1 of 3 start angles.
        # Mirrors Game.cpp createFullScreenLightning (3540-3564):
        #   mode 0 = vertical: start at (end_x, UI_HEIGHT) above the impact point
        #   mode 1 = diagonal sx: start at top-left corner (20, UI_HEIGHT)
        #   mode 2 = diagonal dx: start at top-right corner (W-20, UI_HEIGHT)
        # The path uses 18 segments + 35px jitter perpendicular to direction
        # (generateLightningPath 3492-3523) so the zigzag is visible but
        # anchored at start and end.
        var end_x: float = randf() * float(C.WINDOW_WIDTH)
        var end_pos: Vector2 = Vector2(end_x, float(C.WINDOW_HEIGHT))
        var mode: int = randi() % 3
        var start_pos: Vector2
        match mode:
                0:
                        start_pos = Vector2(end_x, float(C.UI_HEIGHT))
                1:
                        start_pos = Vector2(20.0, float(C.UI_HEIGHT))
                _:
                        start_pos = Vector2(float(C.WINDOW_WIDTH) - 20.0, float(C.UI_HEIGHT))
        var points: Array = _generate_lightning_path(start_pos, end_pos, 18, 35.0)
        # Pre-compute 4 lateral branches (5 segments each, 6 points). The
        # branches are anchored at random points along the main path and
        # descend with horizontal jitter, matching Game.cpp 3683-3714.
        var branches: Array = []
        if points.size() >= 4:
                var br_rng := RandomNumberGenerator.new()
                br_rng.seed = randi()
                for _b in 4:
                        var seg_idx: int = 1 + br_rng.randi_range(0, points.size() - 3)
                        var b_cur: Vector2 = points[seg_idx]
                        var b_pts: Array = [b_cur]
                        for _s in 5:
                                var bx: float = b_cur.x + float(br_rng.randi_range(-8, 8))
                                var by: float = b_cur.y + 4.0 + float(br_rng.randi_range(0, 5))
                                b_cur = Vector2(bx, by)
                                b_pts.append(b_cur)
                        branches.append(b_pts)
        # Pre-compute 10 radial sparks (2-layer each: glow + core). Stable
        # across frames so the sparks don't jitter - matches Game.cpp 3718-3735.
        var sparks: Array = []
        var sp_rng := RandomNumberGenerator.new()
        sp_rng.seed = randi()
        for i in 10:
                var a: float = (float(i) / 10.0) * TAU
                var r: float = 10.0 + float(sp_rng.randi_range(0, 11))
                sparks.append({"angle": a, "radius": r})
        lightning_bolts.append({
                "pos": end_pos,
                "points": points,
                "branches": branches,
                "sparks": sparks,
                "life": 25,  # FIX: 0.4s @ 60fps (era 60 = 1s, troppo visibile)
                "max_life": 25,
        })
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.LIGHTNING)
        if EffectsManager:
                EffectsManager.screen_shake(8.0, 0.3)
        # FIX (graphics gap #8 — missing screen flash on lightning strike):
        # C++ Game.cpp:8238-8247 had `screenFlashTimer = 200` (200ms white
        # overlay, alpha 80→0) on every scepter lightning strike. The Godot
        # port had the draw code (MainGameController.gd:1508) but never set
        # screen_flash_timer_ms > 0. We now set it here so the full-screen
        # white flash plays on every strike, matching the C++ feel.
        # FIX (fulmini invisibili): aumentato a 400ms + alpha iniziale 1.0
        # invece di 0.4. Il flash bianco full-screen è l'effetto più visibile
        # del fulmine, deve dominare la scena per almeno 0.4s.
        screen_flash_timer_ms = 60  # FIX: era 120 → flash ancora troppo lungo, copriva il fulmine
        # Damage all enemies near any lightning segment
        for enemy in spawner.enemies:
                if enemy.is_dead():
                        continue
                var e_pos: Vector2 = enemy.get_pixel_pos()
                for pt in points:
                        if e_pos.distance_to(pt) < 50:
                                enemy.take_damage(999)  # instant kill
                                enemy.start_electrified(30)
                                player.add_score(3000)
                                break
        # Damage mini-boss if present (35% max HP)
        if mini_boss != null and not mini_boss.is_dead():
                var mb_pos: Vector2 = mini_boss.get_pixel_pos()
                for pt in points:
                        if mb_pos.distance_to(pt) < 50:
                                var mb_max_hp: int = 100
                                if mini_boss.has_method("get_max_health"):
                                        mb_max_hp = mini_boss.get_max_health()
                                mini_boss.take_damage(int(mb_max_hp * 0.35))
                                break


# Generate a zigzag lightning path from start_pos to end_pos with `num_segs`
# segments and perpendicular jitter (faded to 0 at the endpoints so the bolt
# stays anchored). Mirrors Game.cpp generateLightningPath 3492-3523.
func _generate_lightning_path(start_pos: Vector2, end_pos: Vector2,
                num_segs: int, jitter: float) -> Array:
        var pts: Array = [start_pos]
        var d: Vector2 = end_pos - start_pos
        var dir_len: float = d.length()
        var perp: Vector2 = Vector2.ZERO
        if dir_len > 0.001:
                perp = Vector2(-d.y, d.x) / dir_len
        for i in range(1, num_segs):
                var t: float = float(i) / float(num_segs)
                var p: Vector2 = start_pos + d * t
                # sin(t*PI): 0 at endpoints, 1 in the middle - keeps the
                # bolt anchored to start/end while allowing big mid jitter.
                var edge_fade: float = sin(t * PI)
                var jit: float = (randf() * 2.0 - 1.0) * jitter * edge_fade
                p += perp * jit
                pts.append(p)
        pts.append(end_pos)
        return pts


# ============================================================================
# Draw lightning bolts (called from _draw_overlay, SOPRA il maze)
# ============================================================================
func _draw_lightning_bolts_overlay(ci: CanvasItem) -> void:
        var COL_GEM_BLUE: Color = Color(80.0 / 255.0, 160.0 / 255.0, 220.0 / 255.0)
        var COL_CYAN: Color = Color(120.0 / 255.0, 200.0 / 255.0, 200.0 / 255.0)
        var COL_WHITE: Color = Color(240.0 / 255.0, 240.0 / 255.0, 240.0 / 255.0)
        var COL_YELLOW: Color = Color(1.0, 0.95, 0.4)
        for bolt in lightning_bolts:
                var pts: Array = bolt.get("points", [])
                if pts.size() < 2:
                        continue
                var life: int = int(bolt.get("life", 0))
                var max_life: int = int(bolt.get("max_life", 60))
                var alpha_raw: float = float(life) / float(max_life)
                var alpha: float = 1.0 if alpha_raw > 0.83 else alpha_raw
                var impact: Vector2 = bolt.get("pos", pts[pts.size() - 1])
                # Halo esterno
                ci.draw_circle(impact, 80.0,
                        Color(COL_GEM_BLUE.r, COL_GEM_BLUE.g, COL_GEM_BLUE.b, alpha * 0.25))
                ci.draw_circle(impact, 40.0,
                        Color(COL_CYAN.r, COL_CYAN.g, COL_CYAN.b, alpha * 0.45))
                # Saetta zigzag (4 strati)
                for i in pts.size() - 1:
                        ci.draw_line(pts[i], pts[i + 1],
                                Color(COL_GEM_BLUE.r, COL_GEM_BLUE.g, COL_GEM_BLUE.b, alpha * 0.4), 14.0)
                for i in pts.size() - 1:
                        ci.draw_line(pts[i], pts[i + 1],
                                Color(COL_YELLOW.r, COL_YELLOW.g, COL_YELLOW.b, alpha * 0.5), 8.0)
                for i in pts.size() - 1:
                        ci.draw_line(pts[i], pts[i + 1],
                                Color(COL_CYAN.r, COL_CYAN.g, COL_CYAN.b, alpha * 0.7), 4.0)
                for i in pts.size() - 1:
                        ci.draw_line(pts[i], pts[i + 1],
                                Color(COL_WHITE.r, COL_WHITE.g, COL_WHITE.b, alpha), 2.0)
                # Flash centrale
                ci.draw_circle(impact, 25.0, Color(COL_WHITE.r, COL_WHITE.g, COL_WHITE.b, alpha))
                ci.draw_circle(impact, 12.0, Color(COL_YELLOW.r, COL_YELLOW.g, COL_YELLOW.b, alpha))
                # Ramificazioni
                var branches: Array = bolt.get("branches", [])
                for br in branches:
                        if br.size() < 2:
                                continue
                        for i in br.size() - 1:
                                ci.draw_line(br[i], br[i + 1],
                                        Color(COL_CYAN.r, COL_CYAN.g, COL_CYAN.b, alpha * 0.5), 4.0)
                        for i in br.size() - 1:
                                ci.draw_line(br[i], br[i + 1],
                                        Color(COL_WHITE.r, COL_WHITE.g, COL_WHITE.b, alpha * 0.9), 2.0)
                # Shockwave
                var shock_r: float = (1.0 - alpha_raw) * 100.0
                if shock_r > 0.5:
                        ci.draw_arc(impact, shock_r, 0.0, TAU, 32,
                                Color(COL_WHITE.r, COL_WHITE.g, COL_WHITE.b, alpha * 0.4), 2.0)
        # Decay lightning life
        var alive_bolts: Array = []
        for bolt in lightning_bolts:
                bolt["life"] = int(bolt.get("life", 0)) - 1
                if int(bolt.get("life", 0)) > 0:
                        alive_bolts.append(bolt)
        lightning_bolts = alive_bolts


# OLD: _draw_lightning_bolts uses self.draw_* which fails when called from
# overlay context. Kept for reference but not called.
func _draw_lightning_bolts() -> void:
        pass
        # Detailed 3-strata lightning renderer with halo, flash, 4 lateral
        # branches, 10 radial sparks (2-layer) and an expanding shockwave.
        # Mirrors Game.cpp drawLightning (3582-3747).
        # FIX (fulmini invisibili): spessori raddoppiati e alpha aumentato.
        # Prima i line erano 6/3/1.5px con alpha 0.2/0.5/1.0 → quasi invisibili
        # sul maze scuro. Ora 14/7/3px con alpha 0.4/0.7/1.0 → ben visibili.
        var COL_GEM_BLUE: Color = Color(80.0 / 255.0, 160.0 / 255.0, 220.0 / 255.0)
        var COL_CYAN: Color = Color(120.0 / 255.0, 200.0 / 255.0, 200.0 / 255.0)
        var COL_WHITE: Color = Color(240.0 / 255.0, 240.0 / 255.0, 240.0 / 255.0)
        # FIX (fulmini invisibili): aggiunto giallo elettrico per contrasto
        # sul maze scuro. Il giallo è il colore più visibile per saette.
        var COL_YELLOW: Color = Color(1.0, 0.95, 0.4)
        for bolt in lightning_bolts:
                var pts: Array = bolt.get("points", [])
                if pts.size() < 2:
                        continue
                var life: int = int(bolt.get("life", 0))
                var max_life: int = int(bolt.get("max_life", 30))
                # Alpha curve: flash al frame 0 (alpha=1), poi decay lento.
                # Nei primi 10 frame (166ms) alpha=1.0 per massima visibilità.
                var alpha_raw: float = float(life) / float(max_life)
                var alpha: float = 1.0 if alpha_raw > 0.83 else alpha_raw
                var impact: Vector2 = bolt.get("pos", pts[pts.size() - 1])
                var lx: float = impact.x
                var ly: float = impact.y
                # --- 1. Halo esterno (bagliore grande attorno al punto di impatto) ---
                # FIX: raddoppiato il raggio (55→120) per visibilità
                draw_circle(impact, 120.0,
                        Color(COL_GEM_BLUE.r, COL_GEM_BLUE.g, COL_GEM_BLUE.b, alpha * 0.25))
                # --- 2. Glow medio ---
                draw_circle(impact, 60.0,
                        Color(COL_CYAN.r, COL_CYAN.g, COL_CYAN.b, alpha * 0.45))
                # --- 3. Glow interno ---
                draw_circle(impact, 30.0,
                        Color(COL_WHITE.r, COL_WHITE.g, COL_WHITE.b, alpha * 0.65))
                # --- 4. Saetta zigzag (4 strati per segmento) ---
                # Strato 1: glow esterno azzurro (14px) — FIX: 6→14
                for i in pts.size() - 1:
                        draw_line(pts[i], pts[i + 1],
                                Color(COL_GEM_BLUE.r, COL_GEM_BLUE.g, COL_GEM_BLUE.b,
                                        alpha * 0.4), 14.0)
                # Strato 2: glow medio giallo (8px) — FIX: aggiunto giallo
                for i in pts.size() - 1:
                        draw_line(pts[i], pts[i + 1],
                                Color(COL_YELLOW.r, COL_YELLOW.g, COL_YELLOW.b,
                                        alpha * 0.5), 8.0)
                # Strato 3: glow medio ciano (4px) — FIX: 3→4
                for i in pts.size() - 1:
                        draw_line(pts[i], pts[i + 1],
                                Color(COL_CYAN.r, COL_CYAN.g, COL_CYAN.b,
                                        alpha * 0.7), 4.0)
                # Strato 4: nucleo centrale bianco (2px) — FIX: 1.5→2
                for i in pts.size() - 1:
                        draw_line(pts[i], pts[i + 1],
                                Color(COL_WHITE.r, COL_WHITE.g, COL_WHITE.b, alpha), 2.0)
                # --- 5. Flash centrale al punto di impatto (25px) ---
                # FIX: 10→25 per renderlo più visibile
                draw_circle(impact, 25.0,
                        Color(COL_WHITE.r, COL_WHITE.g, COL_WHITE.b, alpha))
                draw_circle(impact, 12.0,
                        Color(COL_YELLOW.r, COL_YELLOW.g, COL_YELLOW.b, alpha))
                # --- 6. Ramificazioni laterali (4 rami, 5 segmenti ciascuno) ---
                # Ogni ramo: glow ciano 4px + nucleo bianco 2px (Game.cpp 3683-3714)
                # FIX: spessori raddoppiati (2→4, 1→2) per visibilità
                var branches: Array = bolt.get("branches", [])
                for br in branches:
                        if br.size() < 2:
                                continue
                        for i in br.size() - 1:
                                draw_line(br[i], br[i + 1],
                                        Color(COL_CYAN.r, COL_CYAN.g, COL_CYAN.b,
                                                alpha * 0.5), 4.0)
                        for i in br.size() - 1:
                                draw_line(br[i], br[i + 1],
                                        Color(COL_WHITE.r, COL_WHITE.g, COL_WHITE.b,
                                                alpha * 0.9), 2.0)
                # --- 7. Scintille radiali (10, 2 strati: glow + nucleo) ---
                # FIX: raddoppiati i raggi (2.5→5, 1.2→2.5)
                var sparks: Array = bolt.get("sparks", [])
                for sp in sparks:
                        var a: float = float(sp.get("angle", 0.0))
                        var r: float = float(sp.get("radius", 10.0))
                        var sx: float = lx + cos(a) * r
                        var sy: float = ly + sin(a) * r
                        draw_circle(Vector2(sx, sy), 5.0,
                                Color(COL_CYAN.r, COL_CYAN.g, COL_CYAN.b, alpha * 0.6))
                        draw_circle(Vector2(sx, sy), 2.5,
                                Color(COL_WHITE.r, COL_WHITE.g, COL_WHITE.b, alpha))
                # --- 8. Onda d'urto circolare (shockwave che si espande) ---
                # FIX: raggio massimo 50→150 per visibilità
                var shock_r: float = (1.0 - alpha_raw) * 150.0
                if shock_r > 0.5:
                        draw_arc(impact, shock_r, 0.0, TAU, 48,
                                Color(COL_WHITE.r, COL_WHITE.g, COL_WHITE.b, alpha * 0.5), 3.0)
                        draw_arc(impact, shock_r * 0.7, 0.0, TAU, 32,
                                Color(COL_YELLOW.r, COL_YELLOW.g, COL_YELLOW.b, alpha * 0.4), 2.0)
        # Decay lightning life
        var alive_bolts: Array = []
        for bolt in lightning_bolts:
                bolt["life"] = int(bolt.get("life", 0)) - 1
                if int(bolt.get("life", 0)) > 0:
                        alive_bolts.append(bolt)
        lightning_bolts = alive_bolts


func _update_particles(delta_ms: float) -> void:
        var alive: Array = []
        for p in particles:
                p["pos"] = p["pos"] + p.get("vel", Vector2.ZERO)
                p["life"] = int(p.get("life", 0)) - 1
                if int(p.get("life", 0)) > 0:
                        alive.append(p)
        particles = alive


# ============================================================================
# Decals: spawn helpers + update/draw for blood_stains / ash_piles / fire_bursts
# (port of C++ Game::bloodStains / ashPiles / fireBursts).
# ============================================================================

# Spawn a dark-red blood stain at the given pixel position. Life is 300
# frames (5s @ 60 FPS). Mirrors Game.cpp lines 1667 / 1782 / 2499 / 2637 / 2793.
func _spawn_blood_stain(pos: Vector2) -> void:
        blood_stains.append({
                "pos": pos,
                "life": 300,
                "max_life": 300,
                "radius": 8.0 + randf() * 6.0,  # 8-14 px
                "color": Color(120.0 / 255.0, 0.0, 0.0, 200.0 / 255.0),
        })


# Spawn a long-lasting grey ash pile at the given pixel position. Life is
# 600 frames (10s @ 60 FPS) - the task requirement (C++ uses 500/8.3s).
# Mirrors Game.cpp lines 2334-2335.
func _spawn_ash_pile(pos: Vector2) -> void:
        ash_piles.append({
                "pos": pos,
                "life": 600,
                "max_life": 600,
                "radius": 10.0 + randf() * 6.0,  # 10-16 px
                "anim_time": 0.0,
        })


# Spawn a fire burst (orange/yellow expanding flare) at the given pixel
# position. Life is 40 frames (~0.66s). `scale` controls base size
# (1.0 for kill explosions, 0.9 for burning-finalisation bursts).
# Mirrors Game.cpp lines 2339-2340 (life=30, scale=0.9) and the
# drawFireBursts() renderer at 3892-3990.
func _spawn_fire_burst(pos: Vector2, scale: float = 1.0) -> void:
        fire_bursts.append({
                "pos": pos,
                "life": 40,
                "max_life": 40,
                "scale": scale,
                "anim_time": 0.0,
        })


# Decrement life for all three decal arrays and remove expired entries.
# Also advances anim_time for ash piles and fire bursts (used by the
# renderer for pulsing / particle drift). Mirrors Game.cpp lines 2146-2171.
func _update_decals(_delta_ms: float) -> void:
        var alive_bs: Array = []
        for bs in blood_stains:
                bs["life"] = int(bs.get("life", 0)) - 1
                if int(bs["life"]) > 0:
                        alive_bs.append(bs)
        blood_stains = alive_bs

        var alive_ap: Array = []
        for ap in ash_piles:
                ap["life"] = int(ap.get("life", 0)) - 1
                ap["anim_time"] = float(ap.get("anim_time", 0.0)) + 0.04
                if int(ap["life"]) > 0:
                        alive_ap.append(ap)
        ash_piles = alive_ap

        var alive_fb: Array = []
        for fb in fire_bursts:
                fb["life"] = int(fb.get("life", 0)) - 1
                fb["anim_time"] = float(fb.get("anim_time", 0.0)) + 0.1
                if int(fb["life"]) > 0:
                        alive_fb.append(fb)
        fire_bursts = alive_fb


# Render all decals to the canvas. Called from _draw().
# - BloodStains: dark red main circle + 4 smaller splash circles around it,
#   alpha fades with life.
# - AshPiles: flattened grey/brown pile + lighter top + small smoke puffs
#   rising above; alpha fades with life.
# - FireBursts: expanding orange/yellow multi-layer glow (outer orange,
#   mid red, inner gold, white core) + 6 sparks; radius grows with age.
func _draw_decals() -> void:
        # --- Blood stains ---
        for bs in blood_stains:
                var pos: Vector2 = bs.get("pos", Vector2.ZERO)
                var radius: float = float(bs.get("radius", 8.0))
                var life_ratio: float = float(bs.get("life", 0)) / float(bs.get("max_life", 300))
                if life_ratio < 0.0:
                        life_ratio = 0.0
                var base_col: Color = bs.get("color", Color(0.47, 0.0, 0.0, 0.78))
                var alpha: float = base_col.a * life_ratio
                # Main splatter
                draw_circle(pos, radius, Color(base_col.r, base_col.g, base_col.b, alpha))
                # 4 smaller splashes around it (mirror C++ Game.cpp 5091-5102)
                for i in 4:
                        var angle: float = float(i) * (PI / 2.0) + 0.5
                        var dist: float = radius * 1.5
                        var sx: float = pos.x + cos(angle) * dist
                        var sy: float = pos.y + sin(angle) * dist
                        var sr: float = radius * 0.4
                        draw_circle(Vector2(sx, sy), sr,
                                Color(base_col.r, base_col.g, base_col.b, alpha * 0.7))

        # --- Ash piles ---
        # Detailed rendering: shadow + spritesheet (effect_ashpile) with
        # life-based anim selection (idle/walk/attack/death) + 4 braci
        # incandescenti pulsanti + 5 fumo + 5 detriti di carbone ruotati.
        # Mirrors Game.cpp drawAshPiles (3998-4132).
        for ap in ash_piles:
                var pos: Vector2 = ap.get("pos", Vector2.ZERO)
                var radius: float = float(ap.get("radius", 12.0))
                var anim_time: float = float(ap.get("anim_time", 0.0))
                var life_ratio: float = float(ap.get("life", 0)) / float(ap.get("max_life", 600))
                if life_ratio < 0.0:
                        life_ratio = 0.0
                var alpha: float = 1.0 * life_ratio
                # 1. Shadow (squashed dark ellipse)
                var shadow_r: float = radius * 0.7
                draw_circle(pos, shadow_r,
                        Color(0.05, 0.05, 0.05, 0.4 * life_ratio))
                # 2. Spritesheet PNG (effect_ashpile) - life-based anim phase
                var drew_sprite: bool = false
                if _ashpile_sheet != null and _ashpile_sheet.is_loaded():
                        var anim_name: String = "idle"
                        if life_ratio > 0.75:
                                anim_name = "idle"       # fresco
                        elif life_ratio > 0.5:
                                anim_name = "walk"        # smoldering
                        elif life_ratio > 0.25:
                                anim_name = "attack"      # cooling
                        else:
                                anim_name = "death"        # old
                        var frame_count: int = _ashpile_sheet.get_frame_count(anim_name)
                        if frame_count <= 0:
                                anim_name = "idle"
                                frame_count = _ashpile_sheet.get_frame_count(anim_name)
                        if frame_count > 0:
                                var frame_idx: int = int(anim_time * 1000.0 / 200.0) % frame_count
                                var tex: AtlasTexture = _ashpile_sheet.get_frame_texture(anim_name, frame_idx)
                                if tex != null:
                                        var sprite_scale: float = radius / 24.0
                                        if sprite_scale < 0.8:
                                                sprite_scale = 0.8
                                        var fw: float = float(tex.get_width()) * sprite_scale
                                        var fh: float = float(tex.get_height()) * sprite_scale
                                        # Anchor (32, 56) of 64x64 frame -> ground at y+radius*0.5
                                        var anchor_y: float = 56.0 * sprite_scale
                                        draw_texture_rect(tex,
                                                Rect2(pos.x - fw / 2.0, pos.y - anchor_y, fw, fh),
                                                false, Color(1, 1, 1, alpha))
                                        drew_sprite = true
                if not drew_sprite:
                        # Fallback: 3 layered circles (vecchio comportamento)
                        draw_circle(pos, radius * 0.6,
                                Color(0.47, 0.39, 0.35, alpha))
                        draw_circle(Vector2(pos.x, pos.y - radius * 0.2), radius * 0.4,
                                Color(0.63, 0.50, 0.44, alpha))
                        draw_circle(Vector2(pos.x, pos.y - radius * 0.4), radius * 0.25,
                                Color(0.78, 0.71, 0.63, alpha))
                # 3. Braci incandescenti (4 puntini rosso/oro che brillano)
                # Solo nei primi 75% della vita (poi si spengono)
                if life_ratio > 0.25:
                        var ember_pulse: float = 0.7 + 0.3 * sin(anim_time * 5.0)
                        var ember_alpha: float = (life_ratio - 0.25) / 0.75
                        for i in 4:
                                var e_angle: float = (float(i) / 4.0) * TAU + anim_time * 0.3
                                var ex: float = pos.x + cos(e_angle) * radius * 0.4
                                var ey: float = pos.y - 4.0 + sin(e_angle) * radius * 0.2 - float(i) * 2.0
                                # Glow attorno alla brace (3px rosso)
                                var e_glow_r: float = 3.0 * ember_pulse
                                draw_circle(Vector2(ex, ey), e_glow_r,
                                        Color(200.0 / 255.0, 80.0 / 255.0, 80.0 / 255.0,
                                                0.31 * ember_alpha))
                                # Centro brace (1px gold)
                                draw_circle(Vector2(ex, ey), 1.0,
                                        Color(220.0 / 255.0, 160.0 / 255.0, 40.0 / 255.0,
                                                1.0 * ember_alpha))
                # 4. Fumo che sale (5 particelle grigie)
                # Solo nei primi 60% della vita
                if life_ratio > 0.4:
                        var smoke_alpha: float = (life_ratio - 0.4) / 0.6
                        for i in 5:
                                var sx: float = pos.x + sin(anim_time + float(i) * 2.0) * radius * 0.5
                                var sy: float = pos.y - 8.0 - float(int(anim_time * 30.0 + float(i) * 20.0) % 40)
                                var sr2: float = 2.0 + float(i) * 0.5
                                draw_circle(Vector2(sx, sy), sr2,
                                        Color(0.7, 0.67, 0.63,
                                                0.4 * smoke_alpha * (1.0 - float(i) * 0.15)))
                # 5. Detriti di carbone (5 pezzi scuri attorno al mucchio, ruotati)
                # Rectangle 3x2 centered at the debris position, rotated by the
                # position angle around the pile (Game.cpp 4117-4130).
                for i in 5:
                        var d_angle: float = (float(i) / 5.0) * TAU + 0.5
                        var d_dist: float = radius * 1.1
                        var dx: float = pos.x + cos(d_angle) * d_dist
                        var dy: float = pos.y + sin(d_angle) * d_dist * 0.4
                        var c: float = cos(d_angle)
                        var s: float = sin(d_angle)
                        var hw: float = 1.5
                        var hh: float = 1.0
                        # 4 corners of the rotated rect
                        var p1: Vector2 = Vector2(dx + (-hw * c + hh * s), dy + (-hw * s - hh * c))
                        var p2: Vector2 = Vector2(dx + (hw * c + hh * s), dy + (hw * s - hh * c))
                        var p3: Vector2 = Vector2(dx + (hw * c - hh * s), dy + (hw * s + hh * c))
                        var p4: Vector2 = Vector2(dx + (-hw * c - hh * s), dy + (-hw * s + hh * c))
                        draw_colored_polygon(PackedVector2Array([p1, p2, p3, p4]),
                                Color(48.0 / 255.0, 40.0 / 255.0, 36.0 / 255.0,
                                        0.78 * life_ratio))

        # --- Fire bursts ---
        # Detailed rendering: 4 glow layers (outer orange, mid red, inner gold,
        # white core) + effect_fireburst spritesheet (life-based anim phase)
        # + 6 radial sparks. Mirrors Game.cpp drawFireBursts (3892-3990).
        for fb in fire_bursts:
                var pos: Vector2 = fb.get("pos", Vector2.ZERO)
                var life_ratio: float = float(fb.get("life", 0)) / float(fb.get("max_life", 40))
                if life_ratio < 0.0:
                        life_ratio = 0.0
                var scale: float = float(fb.get("scale", 1.0))
                var anim_time: float = float(fb.get("anim_time", 0.0))
                # Pulse (subtle breathing)
                var pulse: float = 1.0 + sin(anim_time * 0.3) * 0.1
                # Age factor: grows from 0 to 1 as the burst ages (life shrinks).
                var age: float = 1.0 - life_ratio
                # Expanding radius (grows with age, base 28 px scaled)
                var expand: float = 1.0 + age * 1.5
                # 1. Outer orange glow
                var outer_r: float = 28.0 * scale * pulse * expand
                draw_circle(pos, outer_r,
                        Color(1.0, 0.39, 0.0, 0.27 * life_ratio))
                # 2. Mid red glow
                var mid_r: float = 20.0 * scale * pulse * expand
                draw_circle(pos, mid_r,
                        Color(0.78, 0.31, 0.31, 0.39 * life_ratio))
                # 3. Inner gold glow
                var inner_r: float = 12.0 * scale * pulse * expand
                draw_circle(pos, inner_r,
                        Color(0.86, 0.63, 0.16, 0.55 * life_ratio))
                # 4. White-hot core
                var core_r: float = 6.0 * scale * pulse * expand
                draw_circle(pos, core_r,
                        Color(0.94, 0.94, 0.94, 0.7 * life_ratio))
                # 5. Spritesheet PNG (effect_fireburst) - life-based anim phase
                if _fireburst_sheet != null and _fireburst_sheet.is_loaded():
                        var anim_name: String = "idle"
                        if life_ratio > 0.75:
                                anim_name = "idle"        # inizio espansione
                        elif life_ratio > 0.5:
                                anim_name = "walk"        # espansione massima
                        elif life_ratio > 0.25:
                                anim_name = "attack"      # picco
                        else:
                                anim_name = "death"        # dissipazione
                        var frame_count: int = _fireburst_sheet.get_frame_count(anim_name)
                        if frame_count <= 0:
                                anim_name = "idle"
                                frame_count = _fireburst_sheet.get_frame_count(anim_name)
                        if frame_count > 0:
                                # Elapsed ms (simulated): (maxLife - life) * 50
                                var elapsed_ms: int = int((float(int(fb.get("max_life", 40))) - float(fb.get("life", 0))) * 50.0)
                                var frame_idx: int = (elapsed_ms / 50) % frame_count
                                var tex: AtlasTexture = _fireburst_sheet.get_frame_texture(anim_name, frame_idx)
                                if tex != null:
                                        # Scale grows during expansion, decays in dissipation
                                        var sprite_scale: float = scale * (1.2 + (1.0 - life_ratio) * 0.5)
                                        var fw: float = float(tex.get_width()) * sprite_scale
                                        var fh: float = float(tex.get_height()) * sprite_scale
                                        # Anchor (32, 40) of 64x64 frame
                                        var anchor_y: float = 40.0 * sprite_scale
                                        draw_texture_rect(tex,
                                                Rect2(pos.x - fw / 2.0, pos.y - anchor_y, fw, fh),
                                                false, Color(1, 1, 1, life_ratio))
                # 6. 6 sparks flying outward (procedural, mirrors Game.cpp 3977-3988)
                for i in 6:
                        var angle: float = (float(i) / 6.0) * 2.0 * PI + anim_time * 0.5
                        var sdist: float = age * 30.0 * scale
                        var sx: float = pos.x + cos(angle) * sdist
                        var sy: float = pos.y + sin(angle) * sdist - age * 10.0
                        draw_circle(Vector2(sx, sy), 1.5,
                                Color(0.94, 0.94, 0.94, 0.86 * life_ratio))


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
        # FIX (HUD last hit enemy): aggiorna l'HUD con le info del nemico colpito.
        # Solo nel labirinto (non boss room), e solo se il nemico è vivo.
        if last_hit_enemy != null and is_instance_valid(last_hit_enemy) and not last_hit_enemy.is_dead():
                var enemy_name: String = last_hit_enemy.get_enemy_name() if last_hit_enemy.has_method("get_enemy_name") else "Enemy"
                var enemy_hp: int = last_hit_enemy.health
                var enemy_max_hp: int = last_hit_enemy.max_health
                hud.set_last_hit_enemy(enemy_name, enemy_hp, enemy_max_hp)
        else:
                hud.set_last_hit_enemy("", 0, 0)


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
        # FIX (fulmini invisibili): tutti gli overlay (fulmini, particelle,
        # proiettili nemici, dinamite, portale, ecc.) sono stati spostati
        # in _on_fg_layer_draw() che viene disegnato SOPRA il maze tramite
        # un CanvasLayer (layer=1). Prima erano qui in _draw() che viene
        # chiamato PRIMA dei figli → il maze copriva tutto.
        pass
