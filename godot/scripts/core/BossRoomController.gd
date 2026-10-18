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
const CollectiblesClass = preload("res://scripts/items/Collectibles.gd")
const Boss = preload("res://scripts/bosses/Boss.gd")
const Projectile = preload("res://scripts/items/Projectile.gd")
# FIX (pausa P senza feedback visivo): overlay PAUSE (mirror MainGame).
const PauseOverlayClass = preload("res://scripts/ui/PauseOverlay.gd")
# FUOCO AMICO (Task 18): effetto corpo accasciato + anima che vola verso il
# vincitore ricaricandogli l'energia (mirror MainGameController).
const SoulTransferFx = preload("res://scripts/entities/SoulTransferEffect.gd")
# FUOCO AMICO (Task 18): raggio di collisione proiettile player -> altro
# player (~25 px, mirror MainGameController).
const FF_HIT_RADIUS_SQ: float = 625.0

# --- Node references ---
@onready var player: CharacterBody2D = $Player
@onready var player2: CharacterBody2D = $Player2
@onready var boss_node: Node2D = $Boss
@onready var boss_projectiles_node: Node2D = $BossProjectiles
@onready var boss_room_weapons_node: Node2D = $BossRoomWeapons
@onready var hud: Control = $HUDLayer/HUD

# --- Game state ---
var current_level: int = 4
var is_paused: bool = false
var test_skip_key_held: bool = false
var grace_period_ms: int = 1000  # 1s delay before Space can kill boss
var boss_room_weapons: Array = []  # [{weapon, pos}]
var boss: Node2D = null
var died_in_boss: bool = false

# FIX (pausa P): overlay PAUSE sopra tutto (CanvasLayer layer 20 > HUD 10).
var _pause_canvas: CanvasLayer = null
var _pause_overlay: Control = null

# --- Boss-room mine (port of C++ `mine` in STATE_BOSS branch, Game.cpp 2728-2843).
#     Spawns once at fight start; bounces between walls and, on impact with
#     the boss, deals 30% of boss.max_health. ---
var mine_item: Collectibles = null

const FRAME_MS: float = 1000.0 / 60.0


# ============================================================================
# Lifecycle
# ============================================================================
func _ready() -> void:
        # FIX (player non spara/salta in boss room): main game controller
        # imposta process_mode = PROCESS_MODE_ALWAYS (riga 153 di
        # MainGameController.gd) così _physics_process continua a girare
        # anche se get_tree().paused = true. BossRoomController NON lo faceva,
        # quindi se lo scene tree era paused (leftover da pause P o da
        # transizione MainGame->BossRoom con pause non ripristinata),
        # _physics_process non girava -> _handle_input non veniva chiamata
        # -> player non spara/salta. Mirror esatto di MainGameController.
        process_mode = Node.PROCESS_MODE_ALWAYS
        # Safety: reset di eventuali pause state left-over dal MainGame.
        get_tree().paused = false
        if GameManager:
                current_level = GameManager.current_level
                died_in_boss = GameManager.died_in_boss
        player.set_character(GameManager.player1_character, 1)
        if GameManager.num_players == 2:
                player2.set_character(GameManager.player2_character, 2)
                player2.visible = true
        else:
                player2.visible = false
        # FIX (punteggio perso tra le scene): ripristina lo stato dei player
        # portato dal labirinto (score/vite/soglia vita-extra). SOLO se NON e'
        # un restore da CONTINUE (usa session_snapshot; le vite restano le 3
        # fresche della scena nuova, come il reset() del C++ su continue).
        if GameManager and not GameManager.session_restore_pending:
                GameManager.restore_player_carry(player, player2)
        # Setup boss fight
        start_boss_fight(died_in_boss)
        # FIX (continue = sessione ESATTA nella boss room — richiesta utente):
        # se siamo qui da un CONTINUE, ripristina lo scontro COM'E'ERA alla
        # morte: HP del boss salvati nello snapshot (NON ricomincia da capo),
        # punteggi e armi/ammo dei player. Le armi a terra e la mina si
        # rigenerano fresche (il sistema anti-softlock le fa ricomparire
        # comunque quando servono: il set si rinnova finché il boss vive).
        if GameManager and GameManager.session_restore_pending \
                        and not GameManager.session_snapshot.is_empty() \
                        and str(GameManager.session_snapshot.get("kind", "")) == "boss" \
                        and int(GameManager.session_snapshot.get("level", -1)) == current_level:
                var snap: Dictionary = GameManager.session_snapshot
                GameManager.session_restore_pending = false
                if boss != null and is_instance_valid(boss) and not boss.is_dead():
                        var hp_snap: int = int(snap.get("boss_health", 0))
                        if hp_snap > 0:
                                boss.health = hp_snap
                var p1_snap_b: Dictionary = snap.get("p1", {})
                if not p1_snap_b.is_empty():
                        player.score = int(p1_snap_b.get("score", 0))
                        var w1_b: Dictionary = p1_snap_b.get("weapon", {})
                        if not w1_b.is_empty():
                                player.current_weapon = w1_b.duplicate()
                                # Regola d'ingresso della boss room (già valida
                                # per il primo ingresso): arma utilizzabile.
                                player.current_weapon["power"] = 2
                                player.current_weapon["ammo"] = maxi(
                                                int(player.current_weapon.get("ammo", 0)), 30)
                var p2_snap_b: Dictionary = snap.get("p2", {})
                if not p2_snap_b.is_empty() and GameManager.num_players == 2:
                        player2.visible = true
                        player2.score = int(p2_snap_b.get("score", 0))
                        var w2_b: Dictionary = p2_snap_b.get("weapon", {})
                        if not w2_b.is_empty():
                                player2.current_weapon = w2_b.duplicate()
                                player2.current_weapon["power"] = 2
                                player2.current_weapon["ammo"] = maxi(
                                                int(player2.current_weapon.get("ammo", 0)), 30)
                print("[Continue] Sessione boss room ripristinata: HP boss ",
                                boss.health if boss != null else "?", "/ ",
                                boss.max_health if boss != null else "?")
        # Boss music
        if AudioManager and GameManager and GameManager.music_enabled:
                AudioManager.play_level_music(current_level, true)
        # FIX (pausa P senza feedback visivo): overlay PAUSE sopra tutto.
        _pause_canvas = CanvasLayer.new()
        _pause_canvas.layer = 20
        _pause_overlay = PauseOverlayClass.new()
        _pause_canvas.add_child(_pause_overlay)
        add_child(_pause_canvas)


# FIX (pausa P non si toglie premendo di nuovo P — ROOT CAUSE): il toggle
# della pausa era dentro _handle_input, chiamato da _physics_process, che
# fa `return` subito quando is_paused == true. Con la pausa attiva il check
# di Input.is_action_just_pressed("pause") non veniva MAI eseguito → la
# partita restava in pausa per sempre. Mirror esatto di MainGameController:
# il toggle vive in _unhandled_input, che continua a girare con il tree in
# pausa grazie a process_mode = PROCESS_MODE_ALWAYS (riga 60).
func _unhandled_input(event: InputEvent) -> void:
        if event.is_action_pressed("pause") and not event.is_echo():
                _toggle_pause()
                var vp: Viewport = get_viewport()
                if vp != null:
                        vp.set_input_as_handled()
                return
        # FIX (ESC durante la pausa): prima il toggle era nel loop
        # _handle_input, irraggiungibile con is_paused == true. ESC ora
        # toglie la pausa e torna al menu anche da fermo (mirror MainGame).
        if event.is_action_pressed("ui_cancel") and not event.is_echo():
                if is_paused:
                        is_paused = false
                        get_tree().paused = false
                        if _pause_overlay != null:
                                _pause_overlay.hide_overlay()
                if AudioManager:
                        AudioManager.stop_music()
                if GameManager:
                        GameManager.go_to_menu()
                var vp2: Viewport = get_viewport()
                if vp2 != null:
                        vp2.set_input_as_handled()
                return


func _physics_process(_delta: float) -> void:
        if is_paused:
                return
        var delta_ms: float = _delta * 1000.0
        delta_ms = min(delta_ms, 50.0)

        _handle_input(delta_ms)
        _update_boss(delta_ms)
        _update_hud()


# ============================================================================
# Input
# ============================================================================
func _handle_input(delta_ms: float = 16.0) -> void:
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

        # FIX (joystick in boss room): il MainGameController gestisce il joystick
        # con Input.is_joy_button_pressed(p1_joy_id, joy_jump_btn/joy_shoot_btn)
        # leggendo i bottoni configurati da ConfigManager. Il BossRoomController
        # usava solo Input.is_action_pressed("shoot"/"jump") che sono mappati
        # su TASTIERA (Z e Space), NON sui bottoni joystick configurati.
        # Ora aggiungiamo il supporto joystick mirror del MainGameController.
        var p1_joy_id: int = -1
        var joy_pads: Array = Input.get_connected_joypads()
        # FIX (2P — pad del giocatore 1, mirror MainGameController): P1 usa
        # il DEVICE salvato in configurazione (JOY_ID), non il primo pad
        # collegato: il pad su cui P1 ha configurato i tasti guida P1 in
        # boss room come nel labirinto, qualunque sia l'ordine di collegamento.
        if ConfigManager and ConfigManager.joy_id() >= 0 \
                        and joy_pads.has(ConfigManager.joy_id()):
                p1_joy_id = ConfigManager.joy_id()
        elif joy_pads.size() > 0:
                p1_joy_id = joy_pads[0]
        var joy_jump_btn: int = ConfigManager.joy_jump() if ConfigManager else -1
        var joy_shoot_btn: int = ConfigManager.joy_shoot() if ConfigManager else -1
        if joy_jump_btn < 0:
                joy_jump_btn = JOY_BUTTON_A  # default: A button = jump
        if joy_shoot_btn < 0:
                joy_shoot_btn = JOY_BUTTON_B  # default: B button = shoot

        # P1 shoot (keyboard OR joystick)
        var shoot_pressed: bool = Input.is_action_pressed("shoot")
        if p1_joy_id >= 0 and Input.is_joy_button_pressed(p1_joy_id, joy_shoot_btn):
                shoot_pressed = true
        if shoot_pressed and player.shoot_cooldown == 0:
                player.shoot()
                player.shoot_cooldown = 150

        # P1 jump (keyboard OR joystick)
        var jump_pressed: bool = Input.is_action_pressed("jump")
        if p1_joy_id >= 0 and Input.is_joy_button_pressed(p1_joy_id, joy_jump_btn):
                jump_pressed = true
        if jump_pressed:
                player.activate_jump()

        # P2
        # FIX (2P — joystick P2 mancava nella boss room): nel labirinto P2 ha
        # il secondo joystick configurato (JOY2_*), ma qui c'era solo la
        # tastiera WASD/Q/E: il giocatore 2 restava senza comandi in boss
        # room se giocava col pad. Ora leggiamo il pad configurato
        # (joy2_id se connesso, altrimenti il 2° pad collegato) con assi,
        # D-pad e tasti jump/shoot configurati, come per P1.
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
                # Joystick P2: device configurato o secondo pad collegato.
                var p2_joy_id: int = -1
                if ConfigManager and ConfigManager.joy2_id() >= 0 \
                                and Input.get_connected_joypads().has(ConfigManager.joy2_id()):
                        p2_joy_id = ConfigManager.joy2_id()
                elif joy_pads.size() > 1:
                        p2_joy_id = joy_pads[1]
                # FIX (anti-conflitto, mirror MainGameController): se P1 e P2
                # risolvono lo STESSO device, P2 prende il primo pad diverso
                # da quello di P1 (se esiste), altrimenti resta in tastiera.
                if p2_joy_id == p1_joy_id and p1_joy_id >= 0:
                        p2_joy_id = -1
                        for pad_id in joy_pads:
                                if pad_id != p1_joy_id:
                                        p2_joy_id = pad_id
                                        break
                if p2_joy_id >= 0:
                        var ax2: int = ConfigManager.joy2_axis_x() if ConfigManager else 0
                        var ay2: int = ConfigManager.joy2_axis_y() if ConfigManager else 1
                        var axis_x2: float = Input.get_joy_axis(p2_joy_id, ax2)
                        var axis_y2: float = Input.get_joy_axis(p2_joy_id, ay2)
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
                player2.set_direction(p2_dx, p2_dy)
                # FIX (parità autofire P2): P1 spara tenendo premuto il tasto
                # (is_action_pressed + cooldown), P2 doveva RIPREMERE il tasto
                # per ogni colpo (just_pressed). Ora anche P2 ha l'autofire.
                var p2_shoot_pressed: bool = Input.is_action_pressed("p2_shoot")
                if p2_joy_id >= 0:
                        var j2_shoot: int = ConfigManager.joy2_shoot() if ConfigManager else -1
                        if j2_shoot < 0:
                                j2_shoot = JOY_BUTTON_B
                        if Input.is_joy_button_pressed(p2_joy_id, j2_shoot):
                                p2_shoot_pressed = true
                if p2_shoot_pressed and player2.shoot_cooldown == 0:
                        player2.shoot()
                        player2.shoot_cooldown = 150
                var p2_jump_pressed: bool = Input.is_action_pressed("p2_jump")
                if p2_joy_id >= 0:
                        var j2_jump: int = ConfigManager.joy2_jump() if ConfigManager else -1
                        if j2_jump < 0:
                                j2_jump = JOY_BUTTON_A
                        if Input.is_joy_button_pressed(p2_joy_id, j2_jump):
                                p2_jump_pressed = true
                if p2_jump_pressed:
                        player2.activate_jump()

        # (la pausa è gestita in _unhandled_input: vedi fix sopra)

        # Test mode: Space kills boss instantly (C++ behavior).
        # FIX (boss skippato subito): il debounce test_skip_key_held veniva
        # reinizializzato a false ad ogni nuova scena, quindi se l'utente
        # teneva premuto spazio dal livello precedente, il boss veniva
        # killato subito. Aggiungiamo un delay di 1s (grace_period_ms)
        # prima che lo spazio possa killare il boss.
        if GameManager and GameManager.test_mode_enabled:
                grace_period_ms = maxi(0, grace_period_ms - int(delta_ms))
                if grace_period_ms == 0:
                        var space_now: bool = Input.is_key_pressed(KEY_SPACE)
                        if space_now and not test_skip_key_held:
                                if boss:
                                        boss.take_damage(9999)
                        test_skip_key_held = space_now

        # (ESC è gestito in _unhandled_input, raggiungibile anche in pausa)


# ============================================================================
# Boss fight update loop (STATE_BOSS)
# ============================================================================
func _update_boss(delta_ms: float) -> void:
        # (1) Player update (free movement, FIX: passa delta_ms)
        player.update_player(null, true, delta_ms)
        if GameManager and GameManager.num_players == 2 and player2.visible:
                player2.update_player(null, true, delta_ms)

        # (2) Boss update
        # FIX CRASH: boss.update_step si aspetta un Array come arg 4
        # (projectiles_out), non un Node. Passiamo un array vuoto che
        # il boss riempirà con i nuovi proiettili, poi li spawniamo
        # come nodi figli di boss_projectiles_node.
        # FIX (2P): il boss mira il player VIVO più vicino (prima solo P1:
        # in 2P il giocatore 2 poteva ballare davanti al boss senza che
        # quest'ultimo reagisse).
        if boss and not boss.is_dead():
                var boss_target: CharacterBody2D = _nearest_alive_player(boss.pos)
                if boss_target == null:
                        boss_target = player
                var new_projectiles: Array = []
                boss.update_step(boss_target.get_pixel_pos().x,
                                boss_target.get_pixel_pos().y, int(delta_ms), new_projectiles)
                # Spawn boss projectiles
                # FIX: Boss._shoot_pattern append oggetti Projectile (Node2D).
                # Impostiamo position = pos e visible = true, poi aggiungiamo
                # come figli di boss_projectiles_node.
                for proj in new_projectiles:
                        if proj is Projectile:
                                proj.position = proj.pos
                                proj.visible = true
                                boss_projectiles_node.add_child(proj)

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

        # (5b) FUOCO AMICO (Task 18 — mirror MainGameController): i proiettili
        # di un player colpiscono l'altro anche in boss room. Il colpo fatale
        # (ultima energia) congela la vittima e lancia l'anima verso il
        # vincitore che ricarica COMPLETAMENTE l'energia.
        _check_friendly_fire_projectiles()

        # (6) Invincible player damages boss
        # FIX (doppio decremento calice): il timer è già decrementato da
        # Player.update_player (unico owner del tick). Qui si legge soltanto
        # per infliggere il danno a contatto (prima veniva scalato UNA
        # SECONDA volta per frame e l'effetto durava la metà).
        if boss and not boss.is_dead() and player.invincible_timer > 0:
                if player.get_pixel_pos().distance_squared_to(boss.pos) < (boss.size / 2.0) ** 2:
                        boss.take_damage(1)
                        if AudioManager:
                                AudioManager.play_sound(AudioManager.SoundType.BOSS_HIT)
        # P2 invincibility also damages boss
        if boss and not boss.is_dead() and player2.visible and player2.invincible_timer > 0:
                if player2.get_pixel_pos().distance_squared_to(boss.pos) < (boss.size / 2.0) ** 2:
                        boss.take_damage(1)
                        if AudioManager:
                                AudioManager.play_sound(AudioManager.SoundType.BOSS_HIT)

        # FIX (musica calice in boss room): quando l'effetto del calice
        # termina durante il fight (loop epic attivo), fermalo e riprendi la
        # musica del boss se la musica è attiva.
        if AudioManager and AudioManager._epic_playing:
                var p1_still: bool = player.visible and player.invincible_timer > 0
                var p2_still: bool = player2.visible and player2.invincible_timer > 0
                if not p1_still and not p2_still:
                        AudioManager.stop_epic_music()
                        if AudioManager.music_enabled and GameManager:
                                AudioManager.play_level_music(GameManager.current_level, true)

        # (7) Boss room weapons pickup
        _check_boss_room_weapon_pickup(player)
        if GameManager and GameManager.num_players == 2 and player2.visible:
                _check_boss_room_weapon_pickup(player2)

        # (8) Anti-softlock: respawn weapons if all empty
        _check_softlock()

        # (8b) Boss-room mine: bounce physics + collision with boss
        _update_boss_room_mine(delta_ms)

        # (9) Death / continue check
        _check_boss_death()
        # (9b) FIX (2P): eliminazione del player senza vite (mirror
        # MainGameController: niente più player "zombie" con vite negative).
        _check_player2_elimination()


# FIX (2P): il player VIVO più vicino a `from_pos` (P1 o P2), oppure null.
# Usato dal targeting del boss: in 2P il boss preme su chi è più vicino
# invece di ignorare completamente P2.
func _nearest_alive_player(from_pos: Vector2) -> CharacterBody2D:
        var best: CharacterBody2D = null
        var best_d: float = INF
        # FUOCO AMICO (Task 18): il player congelato in attesa dell'anima non
        # è un bersaglio valido per il boss.
        if player != null and is_instance_valid(player) and player.lives > 0 \
                        and not player.soul_pending:
                best = player
                best_d = from_pos.distance_squared_to(player.get_pixel_pos())
        if GameManager and GameManager.num_players == 2 and player2 != null \
                        and is_instance_valid(player2) and player2.visible and player2.lives > 0 \
                        and not player2.soul_pending:
                var d2: float = from_pos.distance_squared_to(player2.get_pixel_pos())
                if d2 < best_d:
                        best = player2
        return best


# FIX (2P — eliminazione player in boss room): quando P2 perde l'ultima
# vita ma P1 è ancora vivo, P2 viene eliminato (non più "zombie"), come
# nel labirinto. La scena si ricrea con 3 vite per entrambi usando un
# continue.
func _check_player2_elimination() -> void:
        if player2 == null or not is_instance_valid(player2) or not player2.visible:
                return
        # FUOCO AMICO (Task 18): se P2 è morto per colpo del compagno e la
        # sua anima sta ancora volando, l'eliminazione aspetta la fine del
        # trasferimento (respawn_after_soul + frame successivo).
        if player2.soul_pending:
                return
        if player2.lives > 0 or player.lives <= 0:
                return  # P2 vivo, oppure entrambi morti (game over via _check_boss_death)
        player2.visible = false
        player2.set_direction(0, 0)
        print("[2P] Player 2 eliminato nella boss room (vite esaurite)")
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.LOSE_LIFE)
        if EffectsManager:
                var p := EffectsManager.spawn_explosion(player2.get_pixel_pos(),
                        Color(0.55, 0.65, 1.0), 18, 0.7)
                boss_projectiles_node.add_child(p)
        if hud:
                hud.set_player2_state({
                        "score": player2.score,
                        "lives": 0,
                        "energy": 0,
                        "max_energy": player2.max_energy,
                        "weapon_name": C.get_weapon_name(
                                        int(player2.current_weapon.get("type", 0))),
                        "weapon_color": C.get_weapon_color(
                                        int(player2.current_weapon.get("type", 0))),
                        "weapon_ammo": player2.current_weapon.get("ammo", 0),
                        "weapon_max": player2.current_weapon.get("max_ammo", 15),
                })


func _advance_boss_projectiles(_delta_ms: float) -> void:
        # Move boss projectiles by their velocity, apply homing if enabled.
        # FIX: Projectile ha property `dir` (Vector2 velocity) e `homing_timer_ms`
        # non meta. Leggiamo direttamente le property.
        # FIX (2P): l'homing insegue il player VIVO più vicino AL PROIETTILE
        # (prima solo P1: i proiettili a ricerca ignoravano del tutto P2).
        var to_remove: Array = []
        for proj in boss_projectiles_node.get_children():
                if not proj is Node2D:
                        continue
                if not proj.visible:
                        to_remove.append(proj)
                        continue
                # Get velocity: Projectile ha `dir` come property velocity
                var vel: Vector2 = Vector2.ZERO
                if proj is Projectile:
                        vel = proj.dir
                        # Homing
                        if proj.homing_timer_ms > 0:
                                proj.homing_timer_ms -= int(_delta_ms)
                                var homing_target: CharacterBody2D = _nearest_alive_player(proj.position)
                                if homing_target == null:
                                        homing_target = player
                                var to_player: Vector2 = (homing_target.get_pixel_pos() - proj.position).normalized()
                                vel = vel.lerp(to_player * vel.length(), 0.08)
                                proj.dir = vel
                else:
                        vel = proj.get_meta("velocity", Vector2.ZERO)
                proj.position += vel
                # Remove if out of bounds
                if proj.position.x < -50 or proj.position.x > C.WINDOW_WIDTH + 50 or \
                   proj.position.y < C.UI_HEIGHT - 50 or proj.position.y > C.WINDOW_HEIGHT + 50:
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


# ============================================================================
# FUOCO AMICO (Task 18 — mirror MainGameController, adattato alla boss room):
# i PROIETTILI di un player colpiscono l'altro player anche durante lo
# scontro col boss. Colpo non fatale: -1 energia. Colpo FATALE (ultima
# energia): la vittima si accascia, la sua anima vola verso il vincitore e
# gli ricarica COMPLETAMENTE l'energia (SoulTransferEffect).
# ============================================================================


func _check_friendly_fire_projectiles() -> void:
        if not (GameManager and GameManager.num_players == 2 and player2.visible):
                return
        _ff_shooter_vs_target(player, player2)
        _ff_shooter_vs_target(player2, player)


# Proiettili di `shooter` contro `target` (l'altro player vivo).
func _ff_shooter_vs_target(shooter: CharacterBody2D, target: CharacterBody2D) -> void:
        if shooter.soul_pending or target.soul_pending:
                return
        if target.is_invulnerable() or target.is_jumping():
                return  # parita' proiettili boss: passa attraverso
        if shooter.projectiles.is_empty():
                return
        var target_pos: Vector2 = target.get_pixel_pos()
        for proj in shooter.projectiles:
                if not proj.get("active", false):
                        continue
                var proj_pos: Vector2 = proj.get("pos", Vector2.INF)
                if proj_pos.distance_squared_to(target_pos) > FF_HIT_RADIUS_SQ:
                        continue
                # Colpito! Il proiettile si ferma nel corpo del compagno.
                proj["active"] = false
                if target.energy > 1:
                        target.take_damage()
                else:
                        # Ultima energia: morte per fuoco amico -> anima.
                        _start_soul_transfer(shooter, target)
                break


# Morte per fuoco amico: congela la vittima (kill_by_friendly_fire) e lancia
# l'effetto anima verso il vincitore (homing sulla sua posizione live).
func _start_soul_transfer(winner: CharacterBody2D, victim: CharacterBody2D) -> void:
        victim.kill_by_friendly_fire()
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.LOSE_LIFE)
                AudioManager.play_sound(AudioManager.SoundType.SOUL_RELEASE)
        if EffectsManager:
                EffectsManager.screen_shake(4.0, 0.2)
        var fx: Node2D = SoulTransferFx.new()
        fx.setup(victim, winner)
        add_child(fx)  # figlio del root: disegnato sopra player e boss
        fx.soul_delivered.connect(_on_soul_delivered.bind(winner, victim))


# L'anima ha raggiunto il vincitore: ricarica COMPLETA dell'energia e
# respawn della vittima (se era l'ultima vita, il frame dopo
# _check_player2_elimination la elimina in modo pulito).
func _on_soul_delivered(winner: CharacterBody2D, victim: CharacterBody2D) -> void:
        if is_instance_valid(winner) and winner.lives > 0 and not winner.soul_pending:
                winner.energy = winner.max_energy
                if AudioManager:
                        AudioManager.play_sound(AudioManager.SoundType.SOUL_ABSORB)
                if EffectsManager:
                        EffectsManager.screen_shake(3.0, 0.15)
                        var burst := EffectsManager.spawn_pickup_burst(
                                        winner.get_pixel_pos(), Color(0.85, 0.95, 1.0))
                        boss_projectiles_node.add_child(burst)
        if is_instance_valid(victim):
                victim.respawn_after_soul()


func _check_boss_room_weapon_pickup(p: CharacterBody2D) -> void:
        var to_remove: Array = []
        for w_entry in boss_room_weapons:
                if p.get_pixel_pos().distance_squared_to(w_entry["pos"]) < 1000.0:
                        # FIX CRASH: w_entry["weapon"] è un oggetto Weapon (Node2D),
                        # non un Dictionary. collect_weapon si aspetta un Dictionary.
                        # Convertiamo l'oggetto Weapon in Dictionary.
                        var w_obj = w_entry["weapon"]
                        var w_dict: Dictionary = {}
                        if w_obj is Object and w_obj.has_method("get") and w_obj.get("type") != null:
                                w_dict = {
                                        "type": w_obj.type,
                                        "power": w_obj.power,
                                        "ammo": w_obj.ammo,
                                }
                        elif w_obj is Dictionary:
                                w_dict = w_obj
                        if not w_dict.is_empty():
                                p.collect_weapon(w_dict)
                                if AudioManager:
                                        AudioManager.play_sound(AudioManager.SoundType.WEAPON_PICKUP)
                        to_remove.append(w_entry)
        for w in to_remove:
                boss_room_weapons.erase(w)
                if w.get("node"):
                        w["node"].queue_free()


func _check_softlock() -> void:
        # FIX (armi boss room che non riapparivano MAI in 1P): p2_empty restava
        # FALSE quando non c'è un player 2, quindi la condizione AND
        # "p1_empty AND p2_empty" non scattava MAI in 1P → nessun respawn.
        # Ora: senza P2 (o P2 eliminato) il gate dipende solo da P1.
        # FIX (richiesta utente): quando le munizioni sono finite E le armi
        # a terra (quelle in alto) sono terminate, appare UN ALTRO SET DI ARMI
        # — e questo si ripete FINCHÉ IL BOSS NON VIENE TERMINATO (il check
        # gira a ogni frame dello scontro, quindi il set si rigenera ogni
        # volta che serve).
        var p1_empty: bool = int(player.current_weapon.get("ammo", 0)) == 0
        var p2_active: bool = GameManager and GameManager.num_players == 2 \
                        and player2 != null and is_instance_valid(player2) and player2.visible
        var p2_empty: bool = not p2_active \
                        or int(player2.current_weapon.get("ammo", 0)) == 0
        if p1_empty and p2_empty and boss_room_weapons.is_empty():
                _spawn_boss_room_weapons()


func _check_boss_death() -> void:
        # Player death -> continues
        var p1_dead: bool = player.lives <= 0
        var p2_dead: bool = true
        if GameManager and GameManager.num_players == 2 and player2.visible:
                p2_dead = player2.lives <= 0
        if p1_dead and p2_dead:
                # FIX (musica calice alla morte): ferma il loop epic del
                # calice prima di passare alle schermate CONTINUES/LOSE.
                if AudioManager:
                        AudioManager.stop_epic_music()
                if GameManager:
                        # FIX (Hall of Fame 2P): registra i punteggi finali SINGOLI
                        # dei due player (ognuno salva il proprio in classifica);
                        # final_score resta la somma per la schermata di game over.
                        var total_score_b: int = player.score
                        if GameManager.num_players == 2 and player2.visible:
                                total_score_b += player2.score
                        GameManager.final_score = total_score_b
                        GameManager.final_score_p1 = player.score
                        GameManager.final_score_p2 = player2.score if \
                                        (GameManager.num_players == 2 and player2.visible) else 0
                        GameManager.final_level = current_level
                        # FIX (continue = sessione ESATTA — ROOT CAUSE del bug
                        # segnalato dall'utente): qui si chiamava
                        # GameManager.player_died() SENZA argomento, e player_died()
                        # SOVRASCRIVEVA died_in_boss = in_boss = FALSE, Azzerando
                        # il flag "died_in_boss = true" impostato subito prima.
                        # Risultato: use_continue() vedeva died_in_boss = false e
                        # invece di tornare nella BOSS ROOM rimetteva il player
                        # nel LABIRINTO (livello maze). Ora si passa TRUE.
                        # FIX (snapshot boss): salva anche HP del boss e stato
                        # dei player, così il continue riprende LO STESSO
                        # scontro (stesso HP del boss, stessi punteggi/armi).
                        GameManager.session_snapshot = {
                                "kind": "boss",
                                "level": current_level,
                                "boss_health": int(boss.health) if (boss != null and is_instance_valid(boss)) else 0,
                                "p1": {
                                        "score": player.score,
                                        "weapon": player.current_weapon.duplicate(),
                                },
                                "p2": {
                                        "score": player2.score,
                                        "weapon": player2.current_weapon.duplicate(),
                                } if (GameManager.num_players == 2 and player2.visible) else {},
                        }
                        if GameManager.continues_left > 0:
                                GameManager.player_died(true)
                        else:
                                GameManager.give_up()
                return

        # Boss death -> next level
        if boss and boss.is_dead():
                if AudioManager:
                        AudioManager.play_sound(AudioManager.SoundType.BOSS_DEATH)
                # Effetti Godot-native: screen shake forte + esplosione multipla
                if EffectsManager:
                        EffectsManager.screen_shake(15.0, 0.8)
                        for i in 3:
                                var p := EffectsManager.spawn_explosion(
                                        boss.pos + Vector2(randf() * 60 - 30, randf() * 60 - 30),
                                        Color(1.0, 0.5, 0.1), 40, 1.2)
                                boss_projectiles_node.add_child(p)
                player.add_life()
                if GameManager:
                        # FIX (Hall of Fame): se questa è la vittoria finale
                        # (story completa), registra il punteggio prima di
                        # passare alla WinScreen.
                        if GameManager.game_mode == C.GameMode.STORY and \
                           current_level + 1 > C.STORY_LEVELS_COUNT:
                                # FIX (Hall of Fame 2P): vittoria finale con
                                # punteggi SINGOLI per player + somma.
                                var total_score_w: int = player.score
                                if GameManager.num_players == 2 and player2.visible:
                                        total_score_w += player2.score
                                GameManager.final_score = total_score_w
                                GameManager.final_score_p1 = player.score
                                GameManager.final_score_p2 = player2.score if \
                                                (GameManager.num_players == 2 and player2.visible) else 0
                                GameManager.final_level = current_level
                        GameManager.boss_defeated.emit(GameManager.get_boss_index(current_level))
                        GameManager.current_level = current_level + 1
                        if GameManager.game_mode == C.GameMode.STORY and \
                           current_level + 1 > C.STORY_LEVELS_COUNT:
                                # Win! -> go to WinScreen
                                GameManager.go_to_win()
                        else:
                                # Back to maze
                                # FIX (punteggio perso tra le scene): salva lo
                                # stato dei player PRIMA del cambio scena — il
                                # MainGame della prossima level istanzia nodi
                                # Player NUOVI. Include la vita bonus (+1) appena
                                # concessa da add_life() del boss sconfitto:
                                # prima si PERDEVA al ritorno nel labirinto.
                                GameManager.save_player_carry(player, player2)
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

        # FIX (player non spara in boss room): assicurati che il player abbia
        # un'arma valida con ammo prima della boss fight. Il player nel BossRoom
        # è un nuovo nodo (creato dalla scena), e il suo _ready() chiama reset()
        # che setta current_weapon = PISTOL con ammo=15. MA se per qualche
        # motivo current_weapon è null o ammo=0 (es. stato corrotto), lo
        # resetta qui. Inoltre dai al player un'arma potenziata per il boss.
        # FIX (rinforzo check): controlla anche ammo == 0 (non solo null/empty)
        if player.current_weapon == null or player.current_weapon.is_empty() \
                        or player.current_weapon.get("ammo", 0) <= 0:
                player.current_weapon = {"type": 0, "power": 2, "ammo": 30}
        else:
                # Arma valida: potenzialala per il boss
                player.current_weapon["ammo"] = maxi(player.current_weapon.get("ammo", 0), 30)
                player.current_weapon["power"] = 2

        # Spawn the boss-room mine (1 per fight). Mirrors C++ Game.cpp
        # 2728-2843: a single bouncing mine at a random position in the
        # boss room; when collected by either player it starts bouncing
        # and, on impact with the boss, deals 30% of boss.max_health.
        _spawn_boss_room_mine()


func _spawn_boss_room_weapons() -> void:
        # FIX (armi non centrate): posizionate al centro schermo in alto.
        # Prima erano a x=200,500,800 su uno schermo 1024 (vecchio design).
        # Ora su 1920 wide, le centriamo.
        var center_x: float = float(C.WINDOW_WIDTH) * 0.5
        var spacing: float = 200.0
        var y_pos: float = float(C.UI_HEIGHT) + 120.0
        for i in range(3):
                var w := WeaponClass.new()
                w.generate_random()
                w.ammo = 5
                var w_pos := Vector2(center_x + (float(i) - 1.0) * spacing, y_pos)
                boss_room_weapons.append({"weapon": w, "pos": w_pos, "node": null})


# FIX (test armi boss room): helper per i test headless — raccoglie TUTTE le
# armi a terra teletrasportandovi sopra il player (simula il pickup completo
# del set da parte di un player). Non usato dal gameplay reale.
func _pickup_all_floor_weapons_for_test() -> void:
        for w_entry in boss_room_weapons.duplicate():
                if w_entry.get("pos") != null:
                        player.position = w_entry["pos"]
                        _check_boss_room_weapon_pickup(player)


# Spawn the boss-room mine at a random position inside the room (away from
# the boss center). Mirrors C++ Game::startBossFight() mine init.
func _spawn_boss_room_mine() -> void:
        if mine_item != null and is_instance_valid(mine_item):
                mine_item.queue_free()
        mine_item = null
        # Random position inside the room, keeping margins from walls.
        var margin: float = 80.0
        var mine_pos := Vector2(
                randf_range(margin, float(C.WINDOW_WIDTH) - margin),
                randf_range(float(C.UI_HEIGHT) + margin, float(C.WINDOW_HEIGHT) - margin))
        var mine := CollectiblesClass.new()
        mine.kind = CollectiblesClass.Kind.MINE
        mine.pos = mine_pos
        mine.position = mine_pos
        mine.in_boss_room = true
        mine.active = true
        boss_room_weapons_node.add_child(mine)
        mine_item = mine


# Update the boss-room mine: pick up by either player, then bounce physics
# + collision with the boss (deals 30% of boss.max_health, destroys the
# mine, plays explosion sound + particles).
# Port of C++ Game.cpp lines 2728-2843.
func _update_boss_room_mine(delta_ms: float) -> void:
        if mine_item == null or not is_instance_valid(mine_item) or not mine_item.active:
                return
        # Pulse animation (mirrors C++ mine.pulse += 0.016f).
        mine_item.pulse += float(delta_ms) * 0.001
        if not mine_item.bouncing:
                # Pickup check against P1 and P2 (both players can collect
                # the boss-room mine; fixed 2P bug in C++ r2732-2744).
                var p1_pos: Vector2 = player.get_pixel_pos()
                var p1_hit: bool = p1_pos.distance_squared_to(mine_item.pos) < 400.0
                var p2_hit: bool = false
                if GameManager and GameManager.num_players == 2 and player2.visible:
                        var p2_pos: Vector2 = player2.get_pixel_pos()
                        p2_hit = p2_pos.distance_squared_to(mine_item.pos) < 400.0
                if p1_hit or p2_hit:
                        mine_item.bouncing = true
                        # FIX (mina 6 secondi): anche nella boss room la mina
                        # esplode automaticamente dopo 6 secondi (prima 30s).
                        mine_item.bounce_timer_ms = 6000
                        var angle: float = randf() * TAU
                        mine_item.velocity = Vector2(cos(angle), sin(angle)) * 6.0
                        if AudioManager:
                                AudioManager.play_sound(AudioManager.SoundType.MINE_BOUNCE)
        else:
                # Bounce physics: rotate + move + bounce off room walls
                # (mirrors C++ r2754-2760).
                mine_item.rotation_deg += 0.08 * float(delta_ms) * 0.06
                mine_item.pos += mine_item.velocity
                mine_item.position = mine_item.pos
                var margin: float = 30.0
                if mine_item.pos.x < margin:
                        mine_item.pos.x = margin
                        mine_item.velocity.x = -mine_item.velocity.x
                        if AudioManager:
                                AudioManager.play_sound(AudioManager.SoundType.MINE_BOUNCE)
                if mine_item.pos.x > float(C.WINDOW_WIDTH) - margin:
                        mine_item.pos.x = float(C.WINDOW_WIDTH) - margin
                        mine_item.velocity.x = -mine_item.velocity.x
                        if AudioManager:
                                AudioManager.play_sound(AudioManager.SoundType.MINE_BOUNCE)
                if mine_item.pos.y < float(C.UI_HEIGHT) + margin:
                        mine_item.pos.y = float(C.UI_HEIGHT) + margin
                        mine_item.velocity.y = -mine_item.velocity.y
                        if AudioManager:
                                AudioManager.play_sound(AudioManager.SoundType.MINE_BOUNCE)
                if mine_item.pos.y > float(C.WINDOW_HEIGHT) - margin:
                        mine_item.pos.y = float(C.WINDOW_HEIGHT) - margin
                        mine_item.velocity.y = -mine_item.velocity.y
                        if AudioManager:
                                AudioManager.play_sound(AudioManager.SoundType.MINE_BOUNCE)
                mine_item.position = mine_item.pos
                # Collision with the boss: 30% of boss.max_health damage.
                # Mirrors C++ r2761-2774.
                if boss != null and not boss.is_dead():
                        var boss_half: float = boss.size / 2.0
                        if mine_item.pos.distance_squared_to(boss.pos) < boss_half * boss_half:
                                var dmg: int = int(float(boss.max_health) * 0.3)
                                if dmg < 1:
                                        dmg = 1
                                boss.take_damage(dmg)
                                if AudioManager:
                                        AudioManager.play_sound(AudioManager.SoundType.BOSS_HIT)
                                        AudioManager.play_sound(AudioManager.SoundType.ENEMY_EXPLODE)
                                if EffectsManager:
                                        var p := EffectsManager.spawn_explosion(mine_item.pos,
                                                Color(1.0, 0.78, 0.2), 20, 0.5)
                                        boss_projectiles_node.add_child(p)
                                mine_item.active = false
                                mine_item.bouncing = false
                                mine_item.queue_free()
                                mine_item = null
                                return
                # Timer: FIX (mina esplode dopo 6 secondi) — anche se non ha
                # colpito il boss, allo scadere esplode e se il boss è entro il
                # raggio di scoppio (60px, "pochi pixel") subisce il danno.
                if mine_item != null and mine_item.bouncing:
                        if mine_item.bounce_timer_ms > int(delta_ms):
                                mine_item.bounce_timer_ms -= int(delta_ms)
                        else:
                                mine_item.bounce_timer_ms = 0
                        if mine_item.bounce_timer_ms == 0:
                                # Danno al boss se entro il raggio di scoppio
                                if boss != null and not boss.is_dead():
                                        if mine_item.pos.distance_squared_to(boss.pos) < 60.0 * 60.0:
                                                var expiry_dmg: int = int(float(boss.max_health) * 0.3)
                                                if expiry_dmg < 1:
                                                        expiry_dmg = 1
                                                boss.take_damage(expiry_dmg)
                                                if AudioManager:
                                                        AudioManager.play_sound(AudioManager.SoundType.BOSS_HIT)
                                if EffectsManager:
                                        var p := EffectsManager.spawn_explosion(mine_item.pos,
                                                Color(1.0, 0.78, 0.2), 20, 0.5)
                                        boss_projectiles_node.add_child(p)
                                if AudioManager:
                                        AudioManager.play_sound(AudioManager.SoundType.ENEMY_EXPLODE)
                                mine_item.active = false
                                mine_item.bouncing = false
                                mine_item.queue_free()
                                mine_item = null


# ============================================================================
# Pause
# ============================================================================
func _toggle_pause() -> void:
        is_paused = not is_paused
        if is_paused:
                get_tree().paused = true
                if _pause_overlay != null:
                        _pause_overlay.show_overlay(false)  # tree già paused sopra
                if AudioManager:
                        AudioManager.play_sound(AudioManager.SoundType.MENU_SELECT)
        else:
                get_tree().paused = false
                if _pause_overlay != null:
                        _pause_overlay.hide_overlay()
                if AudioManager:
                        AudioManager.play_sound(AudioManager.SoundType.MENU_CONFIRM)


# ============================================================================
# HUD
# ============================================================================
func _update_hud() -> void:
        if not hud:
                return
        # FIX (HUD 2P invisibile): mirror di MainGameController._update_hud —
        # set_num_players() non veniva mai chiamato → la sezione P2 non veniva
        # mai disegnata nemmeno in boss room. Sincronizzato ogni frame.
        if GameManager != null:
                hud.set_num_players(GameManager.num_players)
        var p1_snap: Dictionary = {
                "score": player.score,
                "lives": player.lives,
                "energy": player.energy,
                "max_energy": player.max_energy,
                "weapon_name": C.get_weapon_name(int(player.current_weapon.get("type", 0))),
                "weapon_color": C.get_weapon_color(int(player.current_weapon.get("type", 0))),
                "weapon_ammo": player.current_weapon.get("ammo", 0),
                "weapon_max": player.current_weapon.get("max_ammo", 15),
                # FIX (stamina salti): barra verde sotto quella della vita.
                "stamina": player.get_stamina_ratio(),
                "stamina_exhausted": player.is_stamina_exhausted(),
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
                        "weapon_name": C.get_weapon_name(int(player2.current_weapon.get("type", 0))),
                        "weapon_color": C.get_weapon_color(int(player2.current_weapon.get("type", 0))),
                        "weapon_ammo": player2.current_weapon.get("ammo", 0),
                        "weapon_max": player2.current_weapon.get("max_ammo", 15),
                        # FIX (stamina salti): barra verde sotto quella della vita (P2).
                        "stamina": player2.get_stamina_ratio(),
                        "stamina_exhausted": player2.is_stamina_exhausted(),
                }
                hud.set_player2_state(p2_snap)


# ============================================================================
# Drawing
# ============================================================================
var _boss_bg_time: float = 0.0
var _boss_bg_texture: Texture2D = null
var _boss_bg_loaded: bool = false

func _process(delta: float) -> void:
        _boss_bg_time += delta
        queue_redraw()

func _load_boss_bg() -> void:
        if _boss_bg_loaded:
                return
        _boss_bg_loaded = true
        # Mappa boss_type → path JPG background (17 boss, 17 sfondi diversi)
        var bg_path: String = ""
        if boss != null:
                var bt: int = boss.boss_type
                match bt:
                        0: bg_path = "res://assets/backgrounds/boss_rooms/bg_boss_golem.jpg"
                        1: bg_path = "res://assets/backgrounds/boss_rooms/bg_boss_lich.jpg"
                        2: bg_path = "res://assets/backgrounds/boss_rooms/bg_boss_demon.jpg"
                        3: bg_path = "res://assets/backgrounds/boss_rooms/bg_boss_spider.jpg"
                        4: bg_path = "res://assets/backgrounds/boss_rooms/bg_boss_abomination.jpg"
                        5: bg_path = "res://assets/backgrounds/boss_rooms/bg_boss_kraken.jpg"
                        6: bg_path = "res://assets/backgrounds/boss_rooms/bg_boss_dragon.jpg"
                        7: bg_path = "res://assets/backgrounds/boss_rooms/bg_boss_wraith_lord.jpg"
                        8: bg_path = "res://assets/backgrounds/boss_rooms/bg_boss_vampire.jpg"
                        9: bg_path = "res://assets/backgrounds/boss_rooms/bg_boss_beholder.jpg"
                        10: bg_path = "res://assets/backgrounds/boss_rooms/bg_boss_ghoul_lord.jpg"
                        11: bg_path = "res://assets/backgrounds/boss_rooms/bg_boss_spectral_alpha.jpg"
                        12: bg_path = "res://assets/backgrounds/boss_rooms/bg_boss_cult_herald.jpg"
                        13: bg_path = "res://assets/backgrounds/boss_rooms/bg_boss_colossal_mimic.jpg"
                        14: bg_path = "res://assets/backgrounds/boss_rooms/bg_boss_rat_king.jpg"
                        15: bg_path = "res://assets/backgrounds/boss_rooms/bg_boss_supreme_witch.jpg"
                        16: bg_path = "res://assets/backgrounds/boss_rooms/bg_boss_twilight_knight.jpg"
        if not bg_path.is_empty():
                var abs_path: String = ProjectSettings.globalize_path(bg_path)
                if FileAccess.file_exists(abs_path):
                        var img := Image.new()
                        if img.load(abs_path) == OK:
                                _boss_bg_texture = ImageTexture.create_from_image(img)

func _draw() -> void:
        # FIX (sfondo boss room per-tipo): carica un PNG AI dedicato per
        # ogni tipo di boss (golem=caverna, lich=necropoli, demon=inferno,
        # dragon=tana drago, vampire=castello gotico). Se non disponibile,
        # usa il background cripta procedurale.
        _load_boss_bg()
        var vp_size: Vector2 = get_viewport_rect().size
        if _boss_bg_texture != null:
                # Cover-fit della texture
                var tex_size: Vector2 = _boss_bg_texture.get_size()
                var scale_x: float = vp_size.x / tex_size.x
                var scale_y: float = vp_size.y / tex_size.y
                var bg_scale: float = maxf(scale_x, scale_y)
                var draw_size: Vector2 = tex_size * bg_scale
                var draw_pos: Vector2 = (vp_size - draw_size) * 0.5
                draw_texture_rect(_boss_bg_texture, Rect2(draw_pos, draw_size), false)
        elif EnvironmentArt:
                EnvironmentArt.draw_crypt_background(self, vp_size, _boss_bg_time)
        # Dark overlay per far risaltare il boss.
        # FIX (rettoangolo trasparente copre HUD in alto): l'overlay nero
        # 0.25 su TUTTA la viewport copriva la zona 0..UI_HEIGHT dove c'è
        # la HUD (info player + nome boss + barra HP boss). L'utente vedeva
        # un "rettoangolo trasparente" che oscurava le informazioni in alto.
        # Ora l'overlay parte da UI_HEIGHT (80px) verso il basso, lasciando
        # la zona HUD completamente libera e nitida.
        draw_rect(Rect2(0, C.UI_HEIGHT, vp_size.x, vp_size.y - C.UI_HEIGHT),
                Color(0, 0, 0, 0.25), true)
        # FIX (decorazioni procedurali fatte male): rimosse le decorazioni
        # (colonne, teschi, bare) disegnate proceduralmente che apparivano
        # male e mal distribuite. Lo sfondo PNG AI è sufficiente.
        # _render_boss_room_decorations()
        # FIX (nome boss in alto): disegna il nome del boss stilizzato
        # in alto al centro (mirror C++ Game.cpp drawBossBanner).
        if boss != null:
                var boss_name: String = Boss.get_boss_name(boss.boss_type)
                var cx: float = vp_size.x * 0.5
                # FIX (nome boss tagliato): by aumentato da 90 a 110 per evitare
                # che il font size 28 venga coperto dalla HUD (0-80). Con font 28
                # il testo occupa y=82 a y=110, tutto sotto la HUD.
                var by: float = 110.0
                var font: Font = ThemeDB.fallback_font
                # Shadow
                draw_string(font, Vector2(cx - 250, by + 2), boss_name,
                        HORIZONTAL_ALIGNMENT_CENTER, 500, 28,
                        Color(0, 0, 0, 0.9))
                # Gold text
                draw_string(font, Vector2(cx - 252, by), boss_name,
                        HORIZONTAL_ALIGNMENT_CENTER, 500, 28,
                        Color(1.0, 0.84, 0.0))
                # HP bar sotto il nome
                if not boss.is_dead():
                        var hp_ratio: float = float(boss.health) / float(boss.max_health)
                        var bar_w: float = 400.0
                        var bar_h: float = 8.0
                        var bar_x: float = cx - bar_w * 0.5
                        var bar_y: float = by + 40.0  # = 130, sotto la HUD
                        draw_rect(Rect2(bar_x - 2, bar_y - 2, bar_w + 4, bar_h + 4),
                                Color(0, 0, 0, 0.8), true)
                        draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h),
                                Color(0.3, 0.1, 0.1), true)
                        draw_rect(Rect2(bar_x, bar_y, bar_w * hp_ratio, bar_h),
                                Color(0.8, 0.15, 0.1), true)
        # Draw boss room weapons on the floor
        for w_entry in boss_room_weapons:
                var pos: Vector2 = w_entry["pos"]
                # Usa texture procedurale dettagliata per l'arma pickup
                if EnvironmentArt and w_entry.has("weapon"):
                        var w_type: int = int(w_entry["weapon"].type)
                        var w_tex: Texture2D = EnvironmentArt.get_weapon_pickup_texture(w_type)
                        if w_tex:
                                # Aura glow dietro
                                draw_circle(pos, 22.0, Color(1.0, 0.85, 0.2, 0.15))
                                draw_texture_rect(w_tex,
                                        Rect2(pos.x - 24, pos.y - 24, 48, 48), false)
                                continue
                # Fallback: Simple weapon icon (colored circle)
                var col: Color = Color.WHITE
                if w_entry.has("weapon") and w_entry["weapon"].has_method("get_color"):
                        col = w_entry["weapon"].get_color()
                draw_circle(pos, 16.0, Color(0.2, 0.2, 0.2, 0.8))
                draw_circle(pos, 12.0, col)

        # FIX (boss non sparano): i proiettili del boss venivano avanzati ma
        # mai disegnati. Aggiungiamo il disegno di tutti i proiettili figli
        # di boss_projectiles_node. Ogni proiettile ha un colore diverso
        # in base al BossProjKind (vedi Projectile.gd).
        for proj in boss_projectiles_node.get_children():
                if not proj is Node2D:
                        continue
                var ppos: Vector2 = proj.position
                # Colore in base al tipo di proiettile
                var bp_kind: int = 0
                if proj is Projectile:
                        bp_kind = proj.bp_kind
                elif proj.has_meta("bp_kind"):
                        bp_kind = int(proj.get_meta("bp_kind"))
                var proj_col: Color = Color(1.0, 0.4, 0.1)  # default rosso/arancio
                match bp_kind:
                        1: proj_col = Color(0.6, 0.4, 0.2)  # BOULDER (marrone)
                        2: proj_col = Color(0.2, 1.0, 0.3)   # NECRO_BOLT (verde)
                        3: proj_col = Color(1.0, 0.3, 0.1)   # FIREBALL (rosso fuoco)
                        4: proj_col = Color(0.8, 0.8, 0.8)   # WEBSHOT (bianco)
                        5: proj_col = Color(0.8, 0.3, 0.5)   # FLESH_CHUNK (rosa)
                        6: proj_col = Color(0.2, 0.6, 1.0)   # INK_SPRAY (blu)
                        7: proj_col = Color(1.0, 0.5, 0.1)   # DRAGON_BREATH (arancio)
                        8: proj_col = Color(0.5, 0.5, 1.0)   # GHOST_BOLT (azzurro)
                        9: proj_col = Color(0.9, 0.1, 0.2)  # BLOOD_BOLT (rosso sangue)
                        10: proj_col = Color(1.0, 1.0, 0.2) # EYE_RAY (giallo)
                        11: proj_col = Color(0.4, 0.2, 0.1) # GHOUL_CLAW (marrone scuro)
                        12: proj_col = Color(0.6, 0.6, 1.0) # SPECTRAL_FANG (blu pallido)
                        13: proj_col = Color(0.8, 0.2, 0.8)  # CULT_ORB (viola)
                        14: proj_col = Color(0.5, 0.8, 0.2)  # MIMIC_GOO (verde slime)
                        15: proj_col = Color(0.6, 0.5, 0.3)  # RAT_SWARM (marrone)
                        16: proj_col = Color(0.9, 0.3, 0.9) # WITCH_HEX (magenta)
                        17: proj_col = Color(0.7, 0.7, 0.9)  # TWILIGHT_BLADE (argento)
                # Glow esterno
                draw_circle(ppos, 8.0, Color(proj_col.r, proj_col.g, proj_col.b, 0.3))
                # Nucleo
                draw_circle(ppos, 4.0, proj_col)
                # Highlight
                draw_circle(ppos - Vector2(1, 1), 1.5,
                        Color(proj_col.r + 0.3, proj_col.g + 0.3, proj_col.b + 0.3))


# Disegna decorazioni ambiente: bare, colonne, ruderi, teschi sul pavimento.
# Posizionate in modo deterministico (non casuale ogni frame).
var _decorations_spawned: bool = false
var _boss_room_decorations: Array = []  # [{type, pos}]

func _render_boss_room_decorations() -> void:
        if not EnvironmentArt:
                return
        # Genera le decorazioni una sola volta
        if not _decorations_spawned:
                _spawn_boss_room_decorations()
                _decorations_spawned = true
        # Disegna le decorazioni (determinate, non casuali)
        for dec in _boss_room_decorations:
                var tex: Texture2D = null
                match dec.type:
                        "coffin": tex = EnvironmentArt.get_coffin_texture()
                        "column": tex = EnvironmentArt.get_column_texture()
                        "rubble": tex = EnvironmentArt.get_rubble_texture()
                        "skull": tex = EnvironmentArt.get_skull_texture()
                if tex:
                        var s: float = 64.0  # dimensione decorazione
                        draw_texture_rect(tex,
                                Rect2(dec.pos.x - s / 2, dec.pos.y - s / 2, s, s), false)


func _spawn_boss_room_decorations() -> void:
        _boss_room_decorations.clear()
        # Posiziona decorazioni in punti fissi (non sopra l'arena centrale)
        # Bare negli angoli
        _boss_room_decorations.append({"type": "coffin", "pos": Vector2(80, 150)})
        _boss_room_decorations.append({"type": "coffin", "pos": Vector2(944, 150)})
        _boss_room_decorations.append({"type": "coffin", "pos": Vector2(80, 850)})
        _boss_room_decorations.append({"type": "coffin", "pos": Vector2(944, 850)})
        # Colonne ai lati (4 per lato)
        for i in range(4):
                var y: float = 200.0 + float(i) * 180.0
                _boss_room_decorations.append({"type": "column", "pos": Vector2(50, y)})
                _boss_room_decorations.append({"type": "column", "pos": Vector2(974, y)})
        # Ruderi sparsi
        for pos in [Vector2(250, 300), Vector2(780, 280), Vector2(300, 800), Vector2(750, 820)]:
                _boss_room_decorations.append({"type": "rubble", "pos": pos})
        # Teschi sul pavimento (piccoli, decorativi)
        for pos in [Vector2(200, 500), Vector2(824, 500), Vector2(400, 250), Vector2(624, 750)]:
                _boss_room_decorations.append({"type": "skull", "pos": pos})
