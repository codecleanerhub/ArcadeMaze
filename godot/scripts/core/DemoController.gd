## DemoController.gd
## ============================================================
## Modalita' demo: AI controlla il player per 30 secondi.
## Mirror di Game.cpp startDemoMode/updateDemoMode/drawDemoOverlay.
##
## - Parte dopo 30s di inattivita' nel menu principale
## - TASK 76: AI con navigazione BFS (pathfinding vero del labirinto),
##   target con isteresi (insegue SEMPRE la stessa preda) e fuga decisa
##   quando un nemico e' a contatto; spara quando allineata al target
## - Salta occasionalmente (2% per frame, flavor)
## - 30s durata, poi torna al menu
## - Interrupt su qualsiasi input utente
## ============================================================
extends Node2D

const C = preload("res://scripts/core/GameConstants.gd")
const WeaponClass = preload("res://scripts/items/Weapon.gd")
const CollectiblesClass = preload("res://scripts/items/Collectibles.gd")
const PlayerCollapseFx = preload("res://scripts/entities/PlayerCollapseEffect.gd")

@onready var maze: Node2D = $Maze
@onready var player: CharacterBody2D = $Player
@onready var spawner: Node2D = $Enemies
@onready var projectiles_node: Node2D = $Projectiles
@onready var enemy_projectiles_node: Node2D = $EnemyProjectiles
@onready var collectibles_node: Node2D = $Collectibles
@onready var hud: Control = $HUDLayer/HUD

# Demo state
var demo_duration_timer_ms: int = 30000
var demo_is_boss: bool = false
var demo_ai_shoot_timer_p1: int = 0
var demo_overlay_time: float = 0.0
var current_level: int = 1

# TASK 76 — stato AI demo: BFS + isteresi del target + fuga.
const DEMO_TARGET_HOLD_MS: float = 1200.0  # minimo tra due ripescate target
const DEMO_FLEE_MS: float = 900.0          # durata della fuga da minaccia

# TASK 106 (demo più brava): il player demo SPARA più spesso (cooldown
# 260ms invece di 500), salta per SFUGGIRE i nemici (invulnerabilità
# aerea), raccoglie calice/scettro/stivali/medikit e insegue MEDIKIT o
# ARMA quando serve (energia bassa / arma scarica).
const DEMO_SHOOT_COOLDOWN_MS: int = 260
const DEMO_SHOOT_RANDOM_PCT: int = 30
const DEMO_JUMP_FLEE_PCT: int = 12
const DEMO_LOW_ENERGY: int = 2
const DEMO_LOW_AMMO: int = 3
const DEMO_FLEE_RADIUS_CELLS: float = 2.1  # nemico entro N celle -> fuga (anticipata)
const DEMO_HUNT_MAX_CELLS: float = 9.0     # oltre: conviene il tesoro piu' vicino
# anti-pendolo: la direzione di fuga resta COMMITTATA 600ms e l'U-turn e'
# vietato per 1.2s (salvo vicolo cieco) — senza questo il player "dondola"
# tra due celle quando il nemico insegue a contatto (segnalazione utente).
const DEMO_FLEE_DIR_HOLD_MS: float = 600.0
const DEMO_FLEE_NO_REVERSE_MS: float = 1200.0
const _DIRS4: Array[Vector2i] = [
        Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
]
var demo_target_enemy: Node = null         # nemico inseguito (isteresi)
var demo_target_treasure: Vector2i = Vector2i(-1, -1)  # tesoro inseguito
var demo_target_hold_ms: float = 0.0
var demo_flee_ms: float = 0.0
var _flee_dir: Vector2i = Vector2i(0, 0)   # direzione di fuga committata
var _flee_dir_age_ms: float = 0.0
var _flee_reverse_block_ms: float = 0.0
var _last_lives: int = 3                   # rileva morte/respawn del demo

# Boss reference (se demo boss)
var boss: Node2D = null

# TASK 87 (fix demo freeze): collassi in corso nel demo (mirror di
# MainGameController._collapses).
var _collapses: Array = []


func _ready() -> void:
        print("[DemoController] Starting demo mode")
        # FIX (demo mode): setup camera come MainGameController
        _setup_camera()
        # Random character
        var char_type: int = randi() % 8
        player.set_character(char_type, 1)
        player.reset()
        # Random level
        current_level = (randi() % C.STORY_LEVELS_COUNT) + 1
        demo_is_boss = false  # FIX: sempre maze mode (con wall collision) nel demo
        demo_duration_timer_ms = 30000
        demo_ai_shoot_timer_p1 = 0
        demo_target_enemy = null
        demo_target_treasure = Vector2i(-1, -1)
        demo_target_hold_ms = 0.0
        demo_flee_ms = 0.0
        _flee_dir = Vector2i(0, 0)
        _flee_dir_age_ms = 0.0
        _flee_reverse_block_ms = 0.0
        _last_lives = player.lives
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


# FIX (demo mode): setup Camera2D per visualizzare correttamente il maze
var _game_camera: Camera2D = null
func _setup_camera() -> void:
        _game_camera = Camera2D.new()
        _game_camera.name = "DemoCamera"
        _game_camera.enabled = true
        _game_camera.position = Vector2(float(C.WINDOW_WIDTH) * 0.5, float(C.WINDOW_HEIGHT) * 0.5)
        _game_camera.position_smoothing_enabled = false
        _game_camera.zoom = Vector2(1.0, 1.0)
        get_tree().root.add_child(_game_camera)


# FIX (demo mode — camera leak): la DemoCamera veniva aggiunta al Window
# root e MAI liberata: sopravviveva al ritorno al menu e alle scene
# successive (più camere attive nella tree). Mirror di
# MainGameController._exit_tree: libera la camera quando la demo termina.
func _exit_tree() -> void:
        if _game_camera != null and is_instance_valid(_game_camera):
                _game_camera.queue_free()
                _game_camera = null


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

        # TASK 87 (fix demo freeze): alla morte il player passa da
        # begin_collapse() -> animazione + respawn differito. Nel gioco vero
        # li avvia MainGameController, ma il DEMO non ha un controller:
        # senza questo driver il player morto restava INVISIBILE e congelato
        # fino alla scadenza dei 30s (regressione del respawn differito,
        # rilevata dagli stalli di test_task26 fase E).
        _start_pending_collapses()

        # AI control
        _update_ai(delta_ms)

        # Update player
        player.update_player(maze, demo_is_boss)
        player.shoot_cooldown = max(0, player.shoot_cooldown - 1)

        # Update enemies
        var p_pos: Vector2 = player.get_pixel_pos()
        var p_grid: Vector2i = player.get_grid_pos()
        for enemy in spawner.enemies:
                # TASK 76 (crash get_tree() null): salta nemici non validi o
                # fuori dal tree (finestra di teardown/respawn).
                if not is_instance_valid(enemy) or not enemy.is_inside_tree():
                        continue
                if not enemy.is_death_anim_done():
                        enemy.update_enemy(maze, p_grid, p_pos, [], delta_ms)
        spawner.remove_dead()

        # TASK 26 (fix segnalazione utente "il player non perdeva energia e
        # nessuno si muoveva piu'"): danno da contatto nemico->player, come
        # _check_melee_collisions del gioco vero. Nel demo mancava del tutto:
        # i nemici raggiunta la cella del player si fermavano lì per sempre
        # (caso A di update_enemy: stessa cella -> attesa del melee che non
        # arrivava mai) e il player si incagliava a spingere contro il muro
        # nella direzione del bersaglio sopra di lui. take_damage() è
        # self-contained: -1 energia, 1s di invulnerabilità, a 0 energia perde
        # una vita e RESPAWNA lontano dal mucchio (che così si scioglie).
        if player.lives > 0 and not player.is_invulnerable() and not player.is_jumping():
                for enemy in spawner.enemies:
                        if enemy.is_dead():
                                continue
                        if p_pos.distance_squared_to(enemy.get_pixel_pos()) < 800.0:
                                player.take_damage()
                                if AudioManager:
                                        AudioManager.play_sound(AudioManager.SoundType.LOSE_LIFE)
                                break

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

        # TASK 106 (demo più brava): raccolta dei COLLECTIBLES a terra
        # (pattern _check_collectible_collisions del gioco vero: calice,
        # scettro, stivali, medikit — le ARMI sono già raccolte da
        # Player.update_player quando passa sulle celle WEAPON).
        for child in collectibles_node.get_children():
                if child == null or not is_instance_valid(child):
                        continue
                if not child.get("active"):
                        continue
                if p_pos.distance_squared_to(child.pos) < 400.0:
                        _on_demo_collectible_picked(child)

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
                        # TASK 79b: nome arma localizzato (PISTOL/PISTOLA),
                        # mai hardcoded "PISTOL".
                        "weapon_name": C.get_weapon_name(C.WeaponType.PISTOL),
                        "weapon_color": Color.WHITE,
                        "weapon_ammo": player.current_weapon.get("ammo", 0),
                        "weapon_max": 20,
                })
                hud.set_remaining_treasures(maze.get_remaining_treasures())

        queue_redraw()


# TASK 87 (fix demo freeze): mirror di MainGameController._start_pending_
# collapses — avvia l'animazione di collasso richiesta da begin_collapse().
func _start_pending_collapses() -> void:
        if player == null or not is_instance_valid(player):
                return
        if not player.collapse_requested:
                return
        player.collapse_requested = false
        var fx: Node2D = PlayerCollapseFx.new()
        fx.setup(player)
        add_child(fx)
        fx.finished.connect(_on_collapse_finished.bind(player))
        _collapses.append(fx)
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.PLAYER_SUFFER)


# TASK 87 (fix demo freeze): a fine animazione il player demo RESPAWNA
# SEMPRE (anche a 0 vite): e' il comportamento pre-Task-87 del demo (il
# vecchio take_damage faceva reset_position incondizionato e il flusso
# continue non esiste nel demo). Il guard `lives > 0` del contatto nemico
# (riga sopra) evita che scenda sotto zero.
func _on_collapse_finished(p: CharacterBody2D) -> void:
        for i in _collapses.size():
                if _collapses[i] != null and is_instance_valid(_collapses[i]) \
                                and _collapses[i].victim == p:
                        _collapses.remove_at(i)
                        break
        if p == null or not is_instance_valid(p):
                return
        p.respawn_after_soul()
        # il respawn rimette il player alla cella (1,1): i nemici che
        # convergevano sul punto di morte restano lì a girare a vuoto finché
        # l'isteresi non ripesca il target — riparto pulito come fa il
        # controller vero alla morte.
        demo_target_enemy = null
        demo_target_treasure = Vector2i(-1, -1)
        demo_target_hold_ms = 0.0


func _update_ai(delta_ms: float) -> void:
        # TASK 76 — AI demo RISCRITTA (segnalazione utente: "il movimento del
        # player e' molto stupido, tende ad andare avanti e indietro
        # impacciandosi tra i nemici che gli stanno addosso"). L'AI vecchia
        # sceglieva una direzione greedy ogni 400ms con 20% di random: con 2+
        # nemici vicini il target cambiava di continuo e il player oscillava.
        # Nuova AI:
        #   * navigazione BFS cella-per-cella (stesso pathfinding dei nemici)
        #   * TARGET con ISTERESI: insegue SEMPRE lo stesso nemico finche'
        #     non muore o non ne compare uno molto piu' vicino (<60% distanza)
        #   * FUGA decisa quando un nemico e' a contatto (<=1.6 celle):
        #     direzione aperta che massimizza la distanza, sparando
        #   * niente nemici a tiro? tesoro piu' vicino (il demo percorre
        #     DAVVERO il labirinto invece di vagare)
        var pos: Vector2 = player.get_pixel_pos()
        var cell := Vector2i(int(pos.x / C.TILE_SIZE),
                        int((pos.y - C.UI_HEIGHT) / C.TILE_SIZE))

        # --- (0) Morte/respawn del player demo: via di fuga COMMITTATA per
        # allontanarsi dal punto di respawn (i nemici convergono lì) e
        # ripartenza pulita della caccia. ---
        if player.lives < _last_lives:
                _last_lives = player.lives
                demo_flee_ms = 1400.0
                demo_target_enemy = null
                demo_target_treasure = Vector2i(-1, -1)
                demo_target_hold_ms = 0.0
                _flee_dir = Vector2i(0, 0)
                _flee_dir_age_ms = 0.0
        elif player.lives > _last_lives:
                _last_lives = player.lives  # reset (nuova demo)

        # --- (1) Scansione nemici: minaccia piu' vicina + preda piu' vicina ---
        var threat: Node = null
        var threat_d2: float = 1e9
        var hunt: Node = null
        var hunt_d2: float = 1e9
        for enemy in spawner.enemies:
                if not is_instance_valid(enemy) or not enemy.is_inside_tree():
                        continue
                if enemy.is_dead() or enemy.is_death_anim_done():
                        continue
                var d2: float = pos.distance_squared_to(enemy.get_pixel_pos())
                if d2 < threat_d2:
                        threat_d2 = d2
                        threat = enemy
                        hunt = enemy
                        hunt_d2 = d2
                elif d2 < hunt_d2:
                        hunt_d2 = d2
                        hunt = enemy

        # --- (2) FUGA: nemico a contatto -> allontanarsi con decisione ---
        if threat != null and sqrt(threat_d2) <= DEMO_FLEE_RADIUS_CELLS * C.TILE_SIZE:
                demo_flee_ms = DEMO_FLEE_MS
        if demo_flee_ms > 0.0:
                demo_flee_ms -= delta_ms
                _flee_from(threat, cell, delta_ms)
                # TASK 106 (demo più brava): SALTO EVASIVO — durante la fuga,
                # se la minaccia è vicina, salta per sfruttare l'esenzione
                # danno del salto (il contatto nemico non ferisce un player
                # a mezz'aria) e attraversare il perimetro.
                if threat != null and is_instance_valid(threat) \
                                and not player.is_jumping() \
                                and sqrt(threat_d2) <= 2.6 * C.TILE_SIZE \
                                and randi() % 100 < DEMO_JUMP_FLEE_PCT:
                        player.activate_jump()
                # durante la fuga continua a sparare al nemico che la incalza
                demo_ai_shoot_timer_p1 -= int(delta_ms)
                if demo_ai_shoot_timer_p1 <= 0:
                        demo_ai_shoot_timer_p1 = DEMO_SHOOT_COOLDOWN_MS
                        _shoot_at_target(pos, threat)
                return

        # --- (3) TARGET con isteresi (niente flip-flop del bersaglio) ---
        if demo_target_enemy != null \
                        and (not is_instance_valid(demo_target_enemy) or demo_target_enemy.is_dead()):
                demo_target_enemy = null
                demo_target_hold_ms = 0.0
        demo_target_hold_ms -= delta_ms
        if demo_target_enemy == null and demo_target_treasure.x >= 0 \
                        and maze.get_cell_type(demo_target_treasure.x, demo_target_treasure.y) != C.CellType.TREASURE:
                # tesoro raccolto (o sparito): ripesca subito
                demo_target_treasure = Vector2i(-1, -1)
                demo_target_hold_ms = 0.0
        var want_repick: bool = demo_target_hold_ms <= 0.0 \
                        and demo_target_enemy == null and demo_target_treasure.x < 0
        if not want_repick and demo_target_enemy != null and hunt != null \
                        and hunt != demo_target_enemy \
                        and hunt_d2 < pos.distance_squared_to(demo_target_enemy.get_pixel_pos()) * 0.36:
                # e' comparso un nemico MOLTO piu' vicino: cambia preda
                want_repick = true
        if want_repick:
                demo_target_hold_ms = DEMO_TARGET_HOLD_MS
                demo_target_treasure = Vector2i(-1, -1)
                if hunt != null and sqrt(hunt_d2) <= DEMO_HUNT_MAX_CELLS * C.TILE_SIZE:
                        demo_target_enemy = hunt
                else:
                        # nemici tutti lontani (o nessuno): tesoro piu' vicino
                        demo_target_enemy = null
                        demo_target_treasure = _nearest_treasure_cell(cell)

        # --- (4) Direzione: BFS verso il target (ricalcolo continuo) ---
        var target_cell: Vector2i = cell
        if demo_target_enemy != null:
                var ep: Vector2 = demo_target_enemy.get_pixel_pos()
                target_cell = Vector2i(int(ep.x / C.TILE_SIZE),
                                int((ep.y - C.UI_HEIGHT) / C.TILE_SIZE))
        elif demo_target_treasure.x >= 0:
                target_cell = demo_target_treasure
        # TASK 106 (demo più brava): priorità di SOPRAVVIVENZA — con
        # energia bassa punta al MEDIKIT a terra; con l'arma scarica punta
        # alla cella ARMA più vicina (la raccolta avviene passandoci sopra,
        # in Player.update_player).
        var prio_cell: Vector2i = _demo_priority_item_cell(cell)
        if prio_cell.x >= 0:
                target_cell = prio_cell
        var next_step: Vector2i = Vector2i(0, 0)
        if target_cell != cell:
                next_step = BFS.find_path(maze, cell, target_cell)
        if next_step != Vector2i(-1, -1) and next_step != Vector2i(0, 0):
                var ndx: int = next_step.x - cell.x
                var ndy: int = next_step.y - cell.y
                if (ndx != 0 or ndy != 0) and not maze.is_wall(cell.x + ndx, cell.y + ndy):
                        player.set_direction(ndx, ndy)
                        # --- (5) Fuoco: allineato al bersaglio o colpo casuale ---
                        _demo_shoot(pos, threat if threat != null else demo_target_enemy, delta_ms)
                        return
        # Fallback (BFS senza percorso / target raggiunto): rotazione oraria
        # su direzione aperta (mai spingere contro un muro) + fuoco.
        var preferred: int = 1 + (randi() % 4)
        var open_dir: int = _open_dir_around(preferred)
        match open_dir:
                1: player.set_direction(0, -1)
                2: player.set_direction(0, 1)
                3: player.set_direction(-1, 0)
                4: player.set_direction(1, 0)
                _: player.set_direction(0, 0)
        _demo_shoot(pos, threat if threat != null else demo_target_enemy, delta_ms)


        # Salto casuale (flavor del demo originale). GATE is_jumping: da quando
        # il DOPPIO SALTO è base del player (TASK salti aggiuntivi), senza gate
        # questo salto scattava anche a mezz'aria allungando l'invulnerabilità
        # della demo e sfasando test_demo_collapse (contatto schivato).
        if randi() % 100 < 2 and not player.is_jumping():
                player.activate_jump()


## Fuga dal nemico piu' vicino (mirror di _flee_greedy dei nemici) con
## ISTERESI DI DIREZIONE: la direzione scelta resta committata per
## DEMO_FLEE_DIR_HOLD_MS e l'U-turn e' bloccato per DEMO_FLEE_NO_REVERSE_MS
## (salvo vicolo cieco). Senza questo, quando il nemico insegue a contatto
## la direzione "migliore" flippa a ogni frame e il player PENDOLA tra due
## celle — esattamente il comportamento segnalato dall'utente.
func _flee_from(threat: Node, cell: Vector2i, delta_ms: float) -> void:
        _flee_dir_age_ms = maxf(0.0, _flee_dir_age_ms - delta_ms)
        _flee_reverse_block_ms = maxf(0.0, _flee_reverse_block_ms - delta_ms)
        # direzione committata ancora valida (non muro, non scaduta)?
        if _flee_dir != Vector2i(0, 0) and _flee_dir_age_ms > 0.0:
                if not maze.is_wall(cell.x + _flee_dir.x, cell.y + _flee_dir.y):
                        player.set_direction(_flee_dir.x, _flee_dir.y)
                        return
        var best: Vector2i = _pick_flee_dir(threat, cell, true)
        if best == Vector2i(0, 0) and _flee_reverse_block_ms > 0.0:
                # vicolo cieco con U-turn bloccato: riprova consentendolo
                best = _pick_flee_dir(threat, cell, false)
        if best != Vector2i(0, 0):
                var reversed: bool = best == -_flee_dir
                _flee_dir = best
                _flee_dir_age_ms = DEMO_FLEE_DIR_HOLD_MS
                if not reversed:
                        _flee_reverse_block_ms = DEMO_FLEE_NO_REVERSE_MS
                player.set_direction(best.x, best.y)
        else:
                player.set_direction(0, 0)


## Direzione aperta che MASSIMIZZA la distanza dalla minaccia; se
## block_reverse, scarta l'U-turn rispetto all'ultima direzione di fuga.
func _pick_flee_dir(threat: Node, cell: Vector2i, block_reverse: bool) -> Vector2i:
        var best: Vector2i = Vector2i(0, 0)
        var best_d: float = -1.0
        for dir in _DIRS4:
                if maze.is_wall(cell.x + dir.x, cell.y + dir.y):
                        continue
                if block_reverse and _flee_reverse_block_ms > 0.0                                 and dir == -_flee_dir:
                        continue
                var cand: Vector2 = Vector2(
                                (cell.x + dir.x) * C.TILE_SIZE + C.TILE_SIZE * 0.5,
                                (cell.y + dir.y) * C.TILE_SIZE + C.TILE_SIZE * 0.5 + C.UI_HEIGHT)
                var d: float = randf()  # senza minaccia: direzione random
                if threat != null and is_instance_valid(threat):
                        d = cand.distance_squared_to(threat.get_pixel_pos())
                if d > best_d:
                        best_d = d
                        best = dir
        return best


## Fuoco del demo: spara se allineato al bersaglio (stesso asse entro mezza
## cella) o casualmente (TASK 106: 30% — era 20%; cooldown 260ms — era 500).
func _demo_shoot(pos: Vector2, target: Node, delta_ms: float) -> void:
        demo_ai_shoot_timer_p1 -= int(delta_ms)
        if demo_ai_shoot_timer_p1 > 0:
                return
        demo_ai_shoot_timer_p1 = DEMO_SHOOT_COOLDOWN_MS
        _shoot_at_target(pos, target)


func _shoot_at_target(pos: Vector2, target: Node) -> void:
        var should_shoot: bool = false
        if target != null and is_instance_valid(target):
                var dx: float = absf(target.get_pixel_pos().x - pos.x)
                var dy: float = absf(target.get_pixel_pos().y - pos.y)
                if dx < C.TILE_SIZE * 0.5 or dy < C.TILE_SIZE * 0.5:
                        should_shoot = true
        if not should_shoot and randi() % 100 < DEMO_SHOOT_RANDOM_PCT:
                should_shoot = true
        if should_shoot and player.shoot_cooldown == 0:
                player.shoot()
                player.shoot_cooldown = 150


## TASK 106 (demo più brava): cella del COLLECTIBLE o dell'ARMA più vicina
## quando la sopravvivenza lo chiede. Ritorna (-1,-1) se non serve nulla:
##   * energia <= DEMO_LOW_ENERGY e c'è un MEDIKIT a terra -> la sua cella
##   * arma corrente scarica e c'è una cella WEAPON nel maze -> la più vicina
func _demo_priority_item_cell(from_cell: Vector2i) -> Vector2i:
        if player.energy <= DEMO_LOW_ENERGY:
                var med := _nearest_collectible_cell(CollectiblesClass.Kind.MEDIKIT)
                if med.x >= 0:
                        return med
        if int(player.current_weapon.get("ammo", 0)) <= DEMO_LOW_AMMO:
                var wpn := _nearest_weapon_cell(from_cell)
                if wpn.x >= 0:
                        return wpn
        return Vector2i(-1, -1)


## TASK 106: cella del collectibile ATTIVO di kind `kind` più vicino
## (Manhattan; -1,-1 se non ce ne sono). Raccoglierlo darà l'effetto nel
## loop di pickup del controller.
func _nearest_collectible_cell(kind: int) -> Vector2i:
        var best: Vector2i = Vector2i(-1, -1)
        var best_d: int = -1
        var pc: Vector2i = player.get_grid_pos()
        for child in collectibles_node.get_children():
                if child == null or not is_instance_valid(child):
                        continue
                if not child.get("active") or int(child.get("kind")) != kind:
                        continue
                var cc: Vector2i = Vector2i(
                                int(child.pos.x / C.TILE_SIZE),
                                int((child.pos.y - C.UI_HEIGHT) / C.TILE_SIZE))
                var d: int = absi(cc.x - pc.x) + absi(cc.y - pc.y)
                if best_d < 0 or d < best_d:
                        best_d = d
                        best = cc
        return best


## TASK 106: cella WEAPON più vicina nel maze (-1,-1 se non ce ne sono).
func _nearest_weapon_cell(from_cell: Vector2i) -> Vector2i:
        var best: Vector2i = Vector2i(-1, -1)
        var best_d: int = -1
        for r in range(C.MAZE_ROWS):
                for c in range(C.MAZE_COLS):
                        if maze.get_cell_type(c, r) == C.CellType.WEAPON:
                                var d: int = absi(c - from_cell.x) + absi(r - from_cell.y)
                                if best_d < 0 or d < best_d:
                                        best_d = d
                                        best = Vector2i(c, r)
        return best


## TASK 106 (demo più brava): pickup di un collectibile da parte del player
## demo (effetti basilari del gioco vero, senza card informative/epiche:
## calice = invincibilità + punti, scettro = punti, stivali = velocità,
## medikit = +1 energia).
func _on_demo_collectible_picked(item: Node2D) -> void:
        var kind: int = int(item.get("kind"))
        match kind:
                CollectiblesClass.Kind.CHALICE:
                        player.set_invincible_timer(9500)
                        player.add_score(C.CHALICE_PICKUP_POINTS)
                        if AudioManager:
                                AudioManager.play_sound(AudioManager.SoundType.TREASURE)
                CollectiblesClass.Kind.SCEPTER:
                        item.trigger_scepter()
                        player.add_score(C.CHALICE_PICKUP_POINTS)
                        if AudioManager:
                                AudioManager.play_sound(AudioManager.SoundType.SCEPTER_PICKUP)
                CollectiblesClass.Kind.SPEED_BOOTS:
                        player.activate_speed_boost()
                        if AudioManager:
                                AudioManager.play_sound(AudioManager.SoundType.WEAPON_PICKUP)
                CollectiblesClass.Kind.MEDIKIT:
                        player.energy = mini(player.energy + 1, player.max_energy)
                        if AudioManager:
                                AudioManager.play_sound(AudioManager.SoundType.POTION_DRINK)
                _:
                        return  # mine/statue: fuori dal demo, lasciale a terra
        item.set("active", false)
        item.queue_free()


## Tesoro piu' vicino (distanza Manhattan sulla griglia).
func _nearest_treasure_cell(from_cell: Vector2i) -> Vector2i:
        var best: Vector2i = Vector2i(-1, -1)
        var best_d: int = -1
        for r in range(C.MAZE_ROWS):
                for c in range(C.MAZE_COLS):
                        if maze.get_cell_type(c, r) == C.CellType.TREASURE:
                                var d: int = absi(c - from_cell.x) + absi(r - from_cell.y)
                                if best_d < 0 or d < best_d:
                                        best_d = d
                                        best = Vector2i(c, r)
        return best


# TASK 26 — direzione preferita se bloccata da un muro -> prima direzione
# libera in rotazione oraria (1 su -> 2 giù -> 3 sinistra -> 4 destra).
# Usa la STESSA cella e lo stesso check (maze.is_wall) di Player.try_move,
# così la decisione dell'AI è sempre compatibile col movimento reale.
func _open_dir_around(preferred: int) -> int:
        var col := int(player.get_pixel_pos().x / C.TILE_SIZE)
        var row := int((player.get_pixel_pos().y - C.UI_HEIGHT) / C.TILE_SIZE)
        var d: int = preferred
        for k in 4:
                var ndx: int = 0
                var ndy: int = 0
                match d:
                        1: ndy = -1
                        2: ndy = 1
                        3: ndx = -1
                        4: ndx = 1
                        _: return preferred
                if not maze.is_wall(col + ndx, row + ndy):
                        return d
                d = 1 + (d % 4)
        return preferred


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
        # TASK 106 (demo più brava): anche un MEDIKIT a terra — l'AI lo
        # insegue quando l'energia è bassa e sopravvive più a lungo.
        if empty_cells.size() > 0:
                var cell: Vector2i = empty_cells.pop_back()
                var medikit := CollectiblesClass.new()
                medikit.kind = CollectiblesClass.Kind.MEDIKIT
                medikit.pos = Vector2(cell.x * C.TILE_SIZE + C.TILE_SIZE / 2.0,
                        cell.y * C.TILE_SIZE + C.TILE_SIZE / 2.0 + C.UI_HEIGHT)
                medikit.position = medikit.pos
                collectibles_node.add_child(medikit)


func _draw() -> void:
        # Demo overlay: "DEMO MODE" pulsing red at bottom center
        demo_overlay_time += 0.05
        var pulse: float = (sin(demo_overlay_time * 5.0) + 1.0) * 0.5
        var alpha: float = (100.0 + pulse * 155.0) / 255.0
        var demo_col: Color = Color(1.0, 0.157, 0.157, alpha)
        # Draw "DEMO MODE" as procedural shapes (Node2D has no get_theme_default_font)
        var cx: float = C.WINDOW_WIDTH / 2.0
        # Red glowing background for text
        draw_circle(Vector2(cx, C.WINDOW_HEIGHT - 55), 120.0, Color(0.8, 0.1, 0.1, alpha * 0.2))
        # Letters drawn as rectangles forming "DEMO MODE" - simplified to colored bars
        # Use draw_string with ThemeDB fallback
        var font: Font = ThemeDB.fallback_font
        draw_string(font, Vector2(cx - 150, C.WINDOW_HEIGHT - 60), I18n.t("demo.mode"),
                HORIZONTAL_ALIGNMENT_CENTER, 300, 48, demo_col)
        draw_string(font, Vector2(cx - 200, C.WINDOW_HEIGHT - 24), I18n.t("demo.exit"),
                HORIZONTAL_ALIGNMENT_CENTER, 400, 18, Color(1.0, 0.784, 0.784, alpha))
