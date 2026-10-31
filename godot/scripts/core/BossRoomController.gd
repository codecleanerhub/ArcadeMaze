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
const ContinuesOverlayClass = preload("res://scripts/ui/ContinuesOverlay.gd")
# TASK 106 (SALVA PARTITA): card di scelta slot da eliminare quando i 10
# slot sono pieni e la run deve salvare.
const SaveSlotsCardClass = preload("res://scripts/ui/SaveSlotsCard.gd")

# TASK 23: CONTINUE PER-PLAYER IN 2P anche in boss room (crediti separati
# P1/P2). Mirror di MainGameController: il player che perde l'ultima vita
# con l'altro ancora vivo congela il fight e sceglie dal SUO contatore.
var _continue_overlay: CanvasLayer = null
var _continue_pending_player: int = 0
const CONTINUE_RESPAWN_INVULN_MS: int = 2500
# FUOCO AMICO (Task 18): effetto corpo accasciato + anima che vola verso il
# vincitore ricaricandogli l'energia (mirror MainGameController).
const SoulTransferFx = preload("res://scripts/entities/SoulTransferEffect.gd")
# TASK 87 — animazione di morte del player (collasso a terra + gemito).
const PlayerCollapseFx = preload("res://scripts/entities/PlayerCollapseEffect.gd")
# FUOCO AMICO (Task 18): raggio di collisione proiettile player -> altro
# player (~25 px, mirror MainGameController).
const FF_HIT_RADIUS_SQ: float = 625.0
# RELIC (Task 21): schermata bonus post-boss (scelta reliquia). Pure-code
# CanvasLayer layer 30 (sopra HUD 10 e pausa 20), pattern PauseOverlay.
const BonusScreenClass = preload("res://scripts/ui/BonusScreen.gd")

# TASK 86 — animazione di morte del boss per-tipo (voragine di fiamme +
# vortice, sgretolamento in sassolini, pipistrello + lampo, ecc.) mostrata
# PRIMA delle card delle reliquie. Nodo self-drawing, guida la trasformazione
# del nodo Boss e disegna effetti ambientali + particelle.
const BossDeathSequenceClass = preload("res://scripts/entities/BossDeathSequences.gd")

# TASK 39 — L'ARENA DEL BOSS: meccaniche esclusive della stanza.
#   * BossArenaPillar: 4 pilastri-condotto a tema dell'elemento debole del
#     boss; si frantumano in 3 colpi, bloccano i proiettili del boss e al
#     crollo scagliano frammenti che danneggiano il boss
#   * ElementalBarrel: barili elementali raccoglibili e lanciabili col tasto
#     di fuoco; l'elemento debole del boss infligge il 250% del danno
#   * BossSiegeCannon: pickup del Cannone d'Assedio (arma SIEGE, 4 colpi)
const BossArenaPillarClass = preload("res://scripts/entities/BossArenaPillar.gd")
const BossArenaRuinClass = preload("res://scripts/entities/BossArenaRuin.gd")
const ElementalBarrelClass = preload("res://scripts/entities/ElementalBarrel.gd")
const BossSiegeCannonClass = preload("res://scripts/entities/BossSiegeCannon.gd")

# Props dell'arena (figli di boss_room_weapons_node: disegnati sopra il
# pavimento, sotto player/boss, e liberati con la scena).
var _arena_pillars: Array = []          # [BossArenaPillar] (LEGACY TASK 39)
var _arena_ruins: Array = []            # [BossArenaRuin] (TASK 50: muri-labirinto)
var _arena_ruin_seed: int = 0           # seed layout (per-boss, per-run)
var _arena_barrels: Array = []          # [ElementalBarrel]
var _arena_siege: Node2D = null         # BossSiegeCannon (pickup a terra)
var _arena_renewal_ms: float = 0.0      # timer rigenerazione arena

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

# RELIC (Task 21): fase SCHERMATA BONUS. Quando il boss muore (e c'e' un
# livello successivo) il fight si congela e il player sceglie la reliquia;
# alla chiusura la transizione di livello prosegue normalmente.
var _bonus_screen: CanvasLayer = null
var _bonus_active: bool = false

# TASK 99 (LEVEL UP): annuncio fulmine + "LEVEL UP!" anche in boss room
# (i punti del boss possono far scattare una soglia). Non parte durante
# la sequenza di morte/bonus: il pending sopravvive al carry verso il
# labirinto successivo.
var _levelup_announce: CanvasLayer = null
const LevelUpAnnounceClass = preload("res://scripts/ui/LevelUpAnnounce.gd")

# TASK 99 (LEVEL UP): modale delle abilità anche in boss room (stesso
# pattern del labirinto: pausa del tree + PROCESS_MODE_ALWAYS + freeze
# del fight tramite early-return in _physics_process).
var _levelup_card: CanvasLayer = null
const LevelUpOverlayClass = preload("res://scripts/ui/LevelUpOverlay.gd")

# TASK 86 — sequenza di animazione di morte del boss (null = non in corsa).
var _death_seq: Node2D = null
var _death_seq_started: bool = false

# FIX (pausa P): overlay PAUSE sopra tutto (CanvasLayer layer 20 > HUD 10).
var _pause_canvas: CanvasLayer = null
var _pause_overlay: Control = null

# --- Boss-room mine (port of C++ `mine` in STATE_BOSS branch, Game.cpp 2728-2843).
#     Spawns once at fight start; bounces between walls and, on impact with
#     the boss, deals 30% of boss.max_health. ---
var mine_item: Collectibles = null

# TASK 51 — FASE 2 DEL BOSS: stato lato controller.
#   * _phase2_flash_ms: flash bianco/rosa a pieno schermo all'ingresso in
#     fase 2 (si scarica in _draw);
#   * boss_pits: buche aperte dal boss (PIT_SPAWNER): telegrafo crepa ->
#     voragine aperta BOSS_PHASE2_PIT_OPEN_MS -> richiude. Danno ai player
#     GROUNDED dentro il raggio (una volta per buca per player).
var _phase2_flash_ms: float = 0.0
var boss_pits: Array[Dictionary] = []

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
        # RELIC (Task 21): in boss room i colpi delle reliquie sono INFINITI
        # (decisione utente, coerente con le munizioni potenziate delle armi
        # base). Il flag si azzera da solo in Player.reset() nelle altre scene.
        player.relic_infinite_shots = true
        player2.relic_infinite_shots = true
        # FIX (punteggio perso tra le scene): ripristina lo stato dei player
        # portato dal labirinto (score/vite/soglia vita-extra). SOLO se NON e'
        # un restore da CONTINUE (usa session_snapshot; le vite restano le 3
        # fresche della scena nuova, come il reset() del C++ su continue).
        if GameManager and not GameManager.session_restore_pending:
                GameManager.restore_player_carry(player, player2)
        # Setup boss fight
        start_boss_fight(died_in_boss)
        # TASK 79d: precarica lo sfondo per-tipo FUORI dalla draw callback
        # (prima veniva caricato al primo _draw: decode JPG + upload GPU
        # dentro il callback di disegno = hitch sul primo frame della stanza).
        _load_boss_bg()
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
                        # TASK 99 (LEVEL UP): conserva livello/punti/pending.
                        player.level = int(p1_snap_b.get("level", 1))
                        player.skill_points = int(p1_snap_b.get("skill_points", 0))
                        player.pending_levelup_fx = int(p1_snap_b.get("pending_levelup_fx", 0))
                        var skills1_b: Dictionary = p1_snap_b.get("skill_levels", {})
                        if not skills1_b.is_empty():
                                player.restore_skills(skills1_b)
                        var w1_b: Dictionary = p1_snap_b.get("weapon", {})
                        if not w1_b.is_empty():
                                player.current_weapon = w1_b.duplicate()
                                # Regola d'ingresso della boss room (già valida
                                # per il primo ingresso): arma utilizzabile.
                                # RELIC (Task 21): NON toccare un'arma reliquia
                                # (le reliquie hanno i loro colpi/potenza).
                                if not player.current_weapon.has("relic"):
                                        player.current_weapon["power"] = 2
                                        player.current_weapon["ammo"] = maxi(
                                                        int(player.current_weapon.get("ammo", 0)), C.BOSS_ROOM_AMMO_MIN)
                var p2_snap_b: Dictionary = snap.get("p2", {})
                if not p2_snap_b.is_empty() and GameManager.num_players == 2:
                        player2.visible = true
                        player2.score = int(p2_snap_b.get("score", 0))
                        # TASK 99 (LEVEL UP): idem P2.
                        player2.level = int(p2_snap_b.get("level", 1))
                        player2.skill_points = int(p2_snap_b.get("skill_points", 0))
                        player2.pending_levelup_fx = int(p2_snap_b.get("pending_levelup_fx", 0))
                        var skills2_b: Dictionary = p2_snap_b.get("skill_levels", {})
                        if not skills2_b.is_empty():
                                player2.restore_skills(skills2_b)
                        var w2_b: Dictionary = p2_snap_b.get("weapon", {})
                        if not w2_b.is_empty():
                                player2.current_weapon = w2_b.duplicate()
                                # RELIC (Task 21): NON toccare un'arma reliquia.
                                if not player2.current_weapon.has("relic"):
                                        player2.current_weapon["power"] = 2
                                        player2.current_weapon["ammo"] = maxi(
                                                        int(player2.current_weapon.get("ammo", 0)), C.BOSS_ROOM_AMMO_MIN)
                # TASK 43: le ARCHITETTURE non risorgono al continue — applica
                # lo stato salvato alla morte (le macerie restano macerie, i
                # pilastri sopravvissuti tengono i danni subiti).
                _restore_arena_pillars_from_snapshot(snap)
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
        # TASK 23: niente pausa/uscita mentre la schermata continue per-player
        # è aperta (l'unico input ammesso è quello dell'overlay).
        if _continue_pending_player != 0:
                return
        # RELIC (Task 21): niente pausa mentre la schermata bonus è aperta
        # (la fase è già un congelamento controllato del fight).
        if _bonus_active:
                return
        # TASK 99 (LEVEL UP): niente pausa mentre annuncio o modale sono
        # aperti (congelamenti controllati).
        if _levelup_card != null or _levelup_announce != null:
                return
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
        # TASK 23: continue per-player aperto — fight CONGELATO.
        if _continue_pending_player != 0:
                return
        # TASK 99 (LEVEL UP): modale abilità aperta — fight CONGELATO
        # (l'overlay gira in PROCESS_MODE_ALWAYS e si chiude con l'OK).
        if _levelup_card != null:
                return
        if is_paused:
                return
        var delta_ms: float = _delta * 1000.0
        delta_ms = min(delta_ms, 50.0)

        # TASK 86: sequenza di morte del boss in corsa → fight congelato
        # (nessun input/movimento): si anima solo la sequenza, che guida la
        # trasformazione del nodo Boss (sink/shrink/spin/hide). Al `finished`
        # il flusso riprende (effetti finali + reliquie / vittoria).
        if _death_seq != null:
                _death_seq.update(delta_ms)
                _update_hud()
                return

        _handle_input(delta_ms)
        _update_boss(delta_ms)
        _update_hud()
        # TASK 99 (LEVEL UP): celebra i level up maturati durante il fight
        # (fulmine + scritta, gioco NON fermo; stessa regola del labirinto).
        _check_levelup_celebrations()


# ============================================================================
# TASK 99 (LEVEL UP) — celebrazione del level up (mirror MainGameController)
# ============================================================================
func _check_levelup_celebrations() -> void:
        if _levelup_announce != null or _bonus_screen != null or _bonus_active:
                return
        var p: CharacterBody2D = null
        if player != null and is_instance_valid(player) \
                        and player.pending_levelup_fx > 0:
                p = player
        elif GameManager != null and GameManager.num_players == 2 \
                        and player2 != null and is_instance_valid(player2) \
                        and player2.visible and player2.pending_levelup_fx > 0:
                p = player2
        if p == null:
                return
        var gained: int = p.consume_pending_levelup_fx()
        if gained <= 0:
                return
        var ann: CanvasLayer = LevelUpAnnounceClass.new()
        ann.setup(int(p.player_num), int(p.level), gained, p.position, self)
        ann.announcement_done.connect(_on_levelup_announcement_done)
        _levelup_announce = ann
        add_child(ann)


func _on_levelup_announcement_done(player_num: int) -> void:
        if _levelup_announce != null:
                _levelup_announce.queue_free()
                _levelup_announce = null
        _maybe_open_levelup_modal(player_num)


## Apre la modale abilità del player `player_num` (pattern del labirinto:
## pausa del tree; il controller e' ALWAYS e si congela da solo con
## l'early-return in _physics_process).
func _maybe_open_levelup_modal(player_num: int) -> void:
        var p: CharacterBody2D = player if player_num != 2 else player2
        if p == null or not is_instance_valid(p):
                return
        if int(p.skill_points) <= 0:
                return  # nulla da spendere: i punti restano bancati
        if _levelup_card != null or _bonus_screen != null or _bonus_active:
                return
        var modal: CanvasLayer = LevelUpOverlayClass.new()
        modal.setup(p)
        modal.modal_closed.connect(_on_levelup_modal_closed)
        _levelup_card = modal
        add_child(modal)
        get_tree().paused = true


func _on_levelup_modal_closed(_player_num: int) -> void:
        if _levelup_card != null:
                _levelup_card.queue_free()
                _levelup_card = null
        if get_tree():
                get_tree().paused = false
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
                # TASK 39: se P1 porta un BARILE, il fuoco lo LANCIA invece
                # di sparare (pattern dinamite/martello del labirinto).
                if not _try_throw_carried_barrel(player):
                        player.shoot()
                        # RELIC (Task 21): cooldown dedicato per reliquia (Arco del
                        # Ranger = raffica 90ms; armi base restano a 150ms).
                        player.shoot_cooldown = C.relic_fire_cooldown(player.current_weapon)

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
                        # TASK 39: barile in spalla -> il fuoco lo lancia (P2).
                        if not _try_throw_carried_barrel(player2):
                                player2.shoot()
                                # RELIC (Task 21): cooldown dedicato per reliquia (P2).
                                player2.shoot_cooldown = C.relic_fire_cooldown(
                                                player2.current_weapon)
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

# ============================================================================
# TASK 51 — FASE 2 DEL BOSS: handler dei segnali del Boss.
# ============================================================================

# _on_boss_phase2_entered(boss): annuncio drammatico del potenziamento —
# flash a pieno schermo, rombo profondo + risata tenebrosa, UNA scossa
# singola (one-shot: non e' la vibrazione ricorrente dei muri rimossa su
# richiesta utente) e polvere attorno al boss.
func _on_boss_phase2_entered(b: Node2D) -> void:
        _phase2_flash_ms = 700.0
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.HAZARD_RUMBLE)
                AudioManager.play_sound(AudioManager.SoundType.DARK_LAUGH)
        if EffectsManager:
                EffectsManager.screen_shake(5.0, 0.5)
                if EffectsManager.has_method("spawn_blast_smoke"):
                        var dust := EffectsManager.spawn_blast_smoke(
                                        b.pos, Color(0.5, 0.1, 0.15), 12)
                        if dust != null:
                                _add_capped_fx(dust)
        queue_redraw()


# _on_boss_spawn_pit(world_pos, tint): il boss apre una buca — fase crepa
# telegrafica gestita in _update_boss_pits.
func _on_boss_spawn_pit(world_pos: Vector2, tint: Color) -> void:
        boss_pits.append({
                "pos": world_pos,
                "tint": tint,
                "state": 0,  # 0 = crepa (telegrafo), 1 = aperta
                "timer": float(C.BOSS_PHASE2_PIT_TELEGRAPH_MS),
                "hit_p1": false,
                "hit_p2": false,
        })
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.HAZARD_RUMBLE)


# _update_boss_pits(delta_ms): ciclo di vita delle buche + danni.
func _update_boss_pits(delta_ms: float) -> void:
        if boss_pits.is_empty():
                return
        for i in range(boss_pits.size() - 1, -1, -1):
                var pit: Dictionary = boss_pits[i]
                pit["timer"] = float(pit["timer"]) - delta_ms
                match int(pit["state"]):
                        0:
                                if float(pit["timer"]) <= 0.0:
                                        pit["state"] = 1
                                        pit["timer"] = float(C.BOSS_PHASE2_PIT_OPEN_MS)
                                        if AudioManager:
                                                AudioManager.play_sound(
                                                                AudioManager.SoundType.HAZARD_COLLAPSE)
                        1:
                                # danno: player GROUNDED dentro il raggio, una
                                # volta per buca per player (niente drain).
                                if not pit["hit_p1"] and player.visible \
                                                and not player.is_invulnerable() \
                                                and not player.is_jumping():
                                        if player.get_pixel_pos().distance_to(
                                                        pit["pos"]) <= C.BOSS_PHASE2_PIT_RADIUS:
                                                # TASK 105 (NG+): buca fase 2 del boss — danno scalato.
                                                player.take_enemy_damage()
                                                pit["hit_p1"] = true
                                if not pit["hit_p2"] and GameManager \
                                                and GameManager.num_players == 2 \
                                                and player2.visible \
                                                and not player2.is_invulnerable() \
                                                and not player2.is_jumping():
                                        if player2.get_pixel_pos().distance_to(
                                                        pit["pos"]) <= C.BOSS_PHASE2_PIT_RADIUS:
                                                # TASK 105 (NG+): buca fase 2 del boss — danno scalato.
                                                player2.take_enemy_damage()
                                                pit["hit_p2"] = true
                                if float(pit["timer"]) <= 0.0:
                                        boss_pits.remove_at(i)
                                        continue
                # disegno animato (crepa pulsante / voragine)
                queue_redraw()


# _on_boss_slam_landed(world_pos, radius): onda d'urto del salto — i player
# GROUNDED nel raggio subiscono un colpo (chi si e' spostato durante
# l'ombra si salva), polvere + scossa singola + tonfo.
func _on_boss_slam_landed(world_pos: Vector2, radius: float) -> void:
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.HAZARD_THUD)
        if EffectsManager:
                EffectsManager.screen_shake(6.0, 0.4)
                var dust := EffectsManager.spawn_explosion(
                                world_pos, Color(0.45, 0.40, 0.33), 22, 0.7)
                _add_capped_fx(dust)
        for p in [player, player2]:
                if p == null or not p.visible:
                        continue
                if p.is_invulnerable() or p.is_jumping() or p.is_ghost():
                        continue
                if p.get_pixel_pos().distance_to(world_pos) <= radius:
                        # TASK 105 (NG+): onda d'urto del salto del boss — danno scalato.
                        p.take_enemy_damage()


# ============================================================================
# TASK 39/50 — L'ARENA DEL BOSS (pilastri, muri in rovina, barili, cannone)
# ============================================================================

func _update_boss(delta_ms: float) -> void:
        # TASK 87: avvia le animazioni di morte del player richieste nel
        # frame precedente (collasso a terra + gemito di sofferenza).
        _start_pending_collapses()
        # RELIC (Task 21): durante la SCHERMATA BONUS il fight è congelato —
        # il boss è morto, i player stanno scegliendo. Si aggiorna solo la
        # HUD (vita bonus già applicata, scelte visibili a schermo).
        if _bonus_active:
                _update_hud()
                return

        # (1) Player update (free movement, FIX: passa delta_ms)
        player.update_player(null, true, delta_ms)
        if GameManager and GameManager.num_players == 2 and player2.visible:
                player2.update_player(null, true, delta_ms)

        # (1b) RELIC (Task 21): passate reliquie — fendenti in mischia vs
        # boss, sterzo dei proiettili a ricerca, esplosione delle bombe a
        # parabola, pulsazioni dell'aura della Corazza di Fuoco.
        _check_pending_relic_melee(player)
        _steer_relic_homing_projectiles(player)
        _consume_relic_bombs(player)
        _tick_fire_armor(player, delta_ms)
        if GameManager and GameManager.num_players == 2 and player2.visible:
                _check_pending_relic_melee(player2)
                _steer_relic_homing_projectiles(player2)
                _consume_relic_bombs(player2)
                _tick_fire_armor(player2, delta_ms)

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
                                # TASK 51 (fix latente): bounds REALI della
                                # stanza 1920x1080 — il default 1024 cullava i
                                # colpi nella meta' destra dello schermo.
                                proj.bounds = Rect2(0.0, C.UI_HEIGHT,
                                                float(C.WINDOW_WIDTH),
                                                float(C.WINDOW_HEIGHT) - C.UI_HEIGHT)
                                boss_projectiles_node.add_child(proj)

        # TASK 51 — FASE 2: update delle buche del boss (telegrafo/apertura/
        # scadenza + danno ai player grounded dentro il raggio).
        _update_boss_pits(delta_ms)
        # TASK 51: scarica il timer del flash d'ingresso fase 2.
        if _phase2_flash_ms > 0.0:
                _phase2_flash_ms = maxf(0.0, _phase2_flash_ms - delta_ms)
                queue_redraw()

        # (3) Advance boss projectiles
        _advance_boss_projectiles(delta_ms)

        # (4) Player projectiles vs pillars (TASK 39: i pilastri sono PHYSICAL:
        # frantumano i colpi PRIMA che possano raggiungere il boss dietro)
        # e vs boss (con danno potenziato del Cannone d'Assedio).
        if boss and not boss.is_dead():
                _check_player_projectiles_vs_pillars(player)
                if GameManager and GameManager.num_players == 2 and player2.visible:
                        _check_player_projectiles_vs_pillars(player2)
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

        # (8c) TASK 39 — L'arena del boss: pickup barili/cannone, frammenti
        # vs boss, rimbalzo del boss sui pilastri, rinnovo dell'arena.
        _update_boss_arena(delta_ms)

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


# TASK 23: eliminazione + CONTINUE per-player in 2P (mirror del
# MainGameController). Il player senza vite e senza crediti viene eliminato
# e l'altro continua da solo; con crediti → ContinuesOverlay col SUO
# contatore (separato). Se non resta nessuno → LOSE.
func _check_player2_elimination() -> void:
        if GameManager == null or GameManager.num_players != 2:
                return
        if _continue_pending_player != 0:
                return
        for p in [player, player2]:
                if p == null or not is_instance_valid(p) or not p.visible:
                        continue
                if p.soul_pending:
                        continue
                if p.lives > 0:
                        continue
                var pnum: int = 1 if p == player else 2
                var credits: int = GameManager.continues_for(pnum)
                if credits > 0:
                        _open_continue_overlay(pnum, credits)
                        return
                _eliminate_player(p)
        _check_all_players_out()


# TASK 23: apre l'overlay CONTINUE? per il player `pnum` (crediti SUOI).
func _open_continue_overlay(pnum: int, credits: int) -> void:
        _continue_pending_player = pnum
        if GameManager:
                GameManager.continue_player_num = pnum
        _continue_overlay = ContinuesOverlayClass.new()
        _continue_overlay.setup(pnum, credits)
        _continue_overlay.continue_chosen.connect(_on_continue_chosen)
        add_child(_continue_overlay)
        print("[Continue] boss room: schermata continue per PLAYER ", pnum,
                        " (crediti suoi: ", credits, ")")


# TASK 23: scelta continue del player `pnum` (YES = riparte con
# C.STARTING_LIVES vite e invulnerabilità breve, il boss CONSERVA gli HP;
# NO = eliminato).
func _on_continue_chosen(pnum: int, yes: bool) -> void:
        _continue_pending_player = 0
        if GameManager:
                GameManager.continue_player_num = 0
        if _continue_overlay != null and is_instance_valid(_continue_overlay):
                _continue_overlay.queue_free()
        _continue_overlay = null
        var p: CharacterBody2D = player if pnum == 1 else player2
        if yes and p != null and is_instance_valid(p):
                if GameManager:
                        GameManager.use_continue_for(pnum)
                p.lives = C.STARTING_LIVES
                p.energy = p.max_energy
                p.reset_position()
                p.damage_timer = CONTINUE_RESPAWN_INVULN_MS
                p.visible = true
                # RELIC (Task 21): il continue in boss room NON tocca le
                # reliquie (relic_infinite_shots resta valido).
                if EffectsManager:
                        EffectsManager.screen_shake(4.0, 0.2)
                        var burst := EffectsManager.spawn_pickup_burst(
                                        p.get_pixel_pos(), Color(0.4, 0.9, 1.0))
                        _add_capped_fx(burst)
                if AudioManager and GameManager and GameManager.music_enabled:
                        AudioManager.play_level_music(current_level, true)
                print("[Continue] boss room: PLAYER ", pnum, " riprende (boss HP ",
                                int(boss.health) if boss != null else 0, ")")
        else:
                _eliminate_player(p)
                _check_all_players_out()


# TASK 23: elimina `p` (mirror del MainGameController, effetti su
# boss_projectiles_node).
func _eliminate_player(p: CharacterBody2D) -> void:
        if p == null or not is_instance_valid(p) or not p.visible:
                return
        var pnum: int = 1 if p == player else 2
        p.visible = false
        p.set_direction(0, 0)
        print("[2P] Player ", pnum, " eliminato nella boss room (vite esaurite)")
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.LOSE_LIFE)
        if EffectsManager:
                var burst := EffectsManager.spawn_explosion(p.get_pixel_pos(),
                        Color(0.55, 0.65, 1.0), 18, 0.7)
                _add_capped_fx(burst)
        if hud:
                var snap_d: Dictionary = {
                        "score": p.score,
                        "lives": 0,
                        "energy": 0,
                        "max_energy": p.max_energy,
                        "weapon_name": C.get_weapon_name(
                                        int(p.current_weapon.get("type", 0))),
                        "weapon_color": C.get_weapon_color(
                                        int(p.current_weapon.get("type", 0))),
                        "weapon_ammo": p.current_weapon.get("ammo", 0),
                        "weapon_max": p.current_weapon.get("max_ammo", 15),
                }
                if pnum == 1:
                        hud.set_player_state(snap_d)
                else:
                        hud.set_player2_state(snap_d)


# TASK 23: game over 2P in boss room — punteggi finali + LOSE.
func _check_all_players_out() -> void:
        var any_alive: bool = false
        for p in [player, player2]:
                if p != null and is_instance_valid(p) and p.visible and p.lives > 0:
                        any_alive = true
        if any_alive or _continue_pending_player != 0:
                return
        # TASK 101: anche in 2P il flusso di fine partita aspetta le
        # animazioni di morte in corso (collasso in attesa/avviato o anima
        # in volo): la LOSE appare DOPO che l'ultimo corpo si è accasciato,
        # come la schermata continue in 1P.
        for p in [player, player2]:
                if p != null and is_instance_valid(p) and p.visible \
                                and (p.soul_pending or p.collapse_requested):
                        return
        if AudioManager:
                AudioManager.stop_epic_music()
                AudioManager.stop_ghost_music()
        if GameManager:
                var total_score_b: int = player.score
                if player2 != null and is_instance_valid(player2):
                        total_score_b += player2.score
                GameManager.final_score = total_score_b
                GameManager.final_score_p1 = player.score
                GameManager.final_score_p2 = player2.score if \
                                (player2 != null and is_instance_valid(player2)) else 0
                GameManager.final_level = current_level
                GameManager.give_up()


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
                # TASK 39 (bug FX): gli effetti particellari (scintille,
                # esplosioni, burst) aggiunti a questo nodo NON sono
                # proiettili: senza questo filtro venivano avanzati,
                # "bloccati" dai pilastri (colpendoli OGNI FRAME) e potevano
                # colpire il player come proiettili fantasma.
                if proj is GPUParticles2D or proj.is_in_group("fx_effect"):
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
                        # TASK 79d: ridisegna SOLO le munizioni con animazione
                        # interna (variante 5 fase-2 = aura pulsante + corona
                        # rotante; homing = scia in dissolvenza): prima il loro
                        # _draw restava CONGELATO allo stato di spawn (nobody
                        # chiamava queue_redraw). Costo trascurabile: sono ~3-6
                        # nodi per volta, e solo in fase 2.
                        if proj.variant == 5 or proj.homing_timer_ms > 0:
                                proj.queue_redraw()
                else:
                        vel = proj.get_meta("velocity", Vector2.ZERO)
                proj.position += vel
                # TASK 39/50: LE ARCHITETTURE in piedi BLOCCANO i proiettili
                # del boss (copertura fisica) e subiscono 1 danno ciascuna:
                # la copertura si consuma durante lo scontro. Dal TASK 50 le
                # architetture sono i MURO-LABIRINTO in rovina (AABB); il
                # ramo pilastri resta per il rollback (flag in GameConstants).
                var blocked_by_arena: bool = false
                if C.BOSS_ARENA_RUINS_ENABLED:
                        for ruin in _arena_ruins:
                                if ruin == null or not is_instance_valid(ruin):
                                        continue
                                if not ruin.is_standing():
                                        continue
                                if ruin.blocks_point(proj.position, 7.0):
                                        blocked_by_arena = true
                                        ruin.take_hit()  # la copertura si consuma
                                        if AudioManager:
                                                AudioManager.play_sound(
                                                                AudioManager.SoundType.PILLAR_CRACK)
                                        if EffectsManager:
                                                var block_fx: Node2D = EffectsManager.spawn_sparks(
                                                                proj.position, 8)
                                                _add_capped_fx(block_fx)
                                        break
                else:
                        for pillar in _arena_pillars:
                                if pillar == null or not is_instance_valid(pillar):
                                        continue
                                if not pillar.is_standing():
                                        continue
                                if proj.position.distance_squared_to(pillar.position) \
                                                < C.BOSS_ARENA_PILLAR_RADIUS * C.BOSS_ARENA_PILLAR_RADIUS:
                                        blocked_by_arena = true
                                        pillar.take_hit()  # la copertura si consuma
                                        if AudioManager:
                                                AudioManager.play_sound(
                                                                AudioManager.SoundType.PILLAR_CRACK)
                                        if EffectsManager:
                                                var block_fx2: Node2D = EffectsManager.spawn_sparks(
                                                                proj.position, 8)
                                                _add_capped_fx(block_fx2)
                                        break
                if blocked_by_arena:
                        proj.visible = false
                        to_remove.append(proj)
                        continue
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
                        # RELIC (Task 21): Corazza del Furore = +1 flat vs boss.
                        var dmg: int = int(proj.get("power", 1)) \
                                        + (1 if p.is_fury_active() else 0)
                        # TASK 39 — CANNONE D'ASSEDIO: la palla di cannone ha
                        # potenza flat E una componente %HP del boss (scala
                        # negli livelli tardivi) + impatto scenico dedicato.
                        if proj.get("siege", false):
                                dmg = maxi(dmg, int(round(float(boss.max_health)
                                                * C.BOSS_ARENA_SIEGE_PCT)))
                                if EffectsManager:
                                        EffectsManager.screen_shake(6.0, 0.25)
                                        var siege_fx := EffectsManager.spawn_blast_smoke(
                                                        proj_pos)
                                        _add_capped_fx(siege_fx)
                                        var smoke_fx := EffectsManager.spawn_explosion(
                                                        proj_pos + Vector2(0.0, -12.0),
                                                        Color(0.25, 0.23, 0.21), 12, 1.0)
                                        _add_capped_fx(smoke_fx)
                                if AudioManager:
                                        AudioManager.play_sound(
                                                        AudioManager.SoundType.ENEMY_EXPLODE)
                        boss.take_damage(dmg)
                        # RELIC (Task 21): la bomba esplode al contatto col boss.
                        if proj.has("lob_px"):
                                if EffectsManager:
                                        var boom := EffectsManager.spawn_blast_smoke(
                                                        proj_pos, Color(1.0, 0.55, 0.18), 12)
                                        _add_capped_fx(boom)
                                if AudioManager:
                                        AudioManager.play_sound(AudioManager.SoundType.ENEMY_EXPLODE)
                        proj["active"] = false
                        if AudioManager:
                                AudioManager.play_sound(AudioManager.SoundType.BOSS_HIT)
                        break


func _check_boss_projectiles_vs_player(p: CharacterBody2D) -> void:
        for proj in boss_projectiles_node.get_children():
                if not proj is Node2D or not proj.visible:
                        continue
                if proj.is_in_group("fx_effect"):
                        continue
                if proj.position.distance_squared_to(p.get_pixel_pos()) < 600.0:
                        # RELIC (Task 21) — SCAGLIE DEL DRAGO: il proiettile del
                        # boss RIMBALZA: viene assorbito dalle scaglie e rispara-
                        # to dal player VERSO IL BOSS col danno del suo MIGLIOR
                        # colpo (max potenza base 5, ROCKET). Una carica a
                        # rimbalzo; a 0 l'armatura si rompe.
                        if p.try_reflect_projectile():
                                proj.visible = false
                                _spawn_reflected_bolt(p, proj.position)
                                if AudioManager:
                                        AudioManager.play_sound(
                                                        AudioManager.SoundType.REFLECT_BOLT)
                                if EffectsManager:
                                        EffectsManager.screen_shake(3.0, 0.15)
                                break
                        p.take_enemy_damage()
                        proj.visible = false
                        if AudioManager:
                                AudioManager.play_sound(AudioManager.SoundType.LOSE_LIFE)
                        break


# RELIC (Task 21): spawna il proiettile riflesso dalle Scaglie del Drago —
# un proiettile DEL PLAYER (flag comportamento, pattern fuoco amico) diretto
# verso il boss con la potenza del miglior colpo del player.
func _spawn_reflected_bolt(p: CharacterBody2D, from_pos: Vector2) -> void:
        if boss == null or not is_instance_valid(boss):
                return
        var dir: Vector2 = (boss.pos - from_pos).normalized()
        if dir == Vector2.ZERO:
                dir = Vector2(0.0, -1.0)
        p.projectiles.append({
                "pos": from_pos + dir * 20.0,
                "dir": dir,
                "power": C.reflect_bolt_power(p.current_weapon),
                "active": true,
                "type": C.RelicType.REFLECT_BOLT,
                "relic": "reflect_bolt",
        })


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
                        _add_capped_fx(burst)
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


# ============================================================================
# TASK 87 — ANIMAZIONE DI MORTE DEL PLAYER (collasso a terra + gemito)
# ============================================================================
# Mirror del MainGameController: Player.begin_collapse() congela il player
# e pone collapse_requested; qui parte PlayerCollapseEffect con il gemito
# PLAYER_SUFFER. Al `finished`: respawn (vite residue) o sblocco per il
# flusso continue (morte definitiva).
var _collapses: Array = []


func _start_pending_collapses() -> void:
        var any_req: bool = player != null and is_instance_valid(player) \
                        and player.collapse_requested
        if not any_req and GameManager and GameManager.num_players == 2 \
                        and player2 != null and is_instance_valid(player2):
                any_req = player2.collapse_requested
        if not any_req:
                return
        for p in [player, player2]:
                if p == null or not is_instance_valid(p) or not p.collapse_requested:
                        continue
                p.collapse_requested = false
                var fx: Node2D = PlayerCollapseFx.new()
                fx.setup(p)
                add_child(fx)  # figlio del root: sopra player e boss
                fx.finished.connect(_on_collapse_finished.bind(p))
                _collapses.append(fx)
                if AudioManager:
                        AudioManager.play_sound(AudioManager.SoundType.PLAYER_SUFFER)


func _on_collapse_finished(p: CharacterBody2D) -> void:
        for i in _collapses.size():
                if _collapses[i] != null and is_instance_valid(_collapses[i]) \
                                and _collapses[i].victim == p:
                        _collapses.remove_at(i)
                        break
        if p == null or not is_instance_valid(p):
                return
        if p.lives > 0:
                p.respawn_after_soul()
        else:
                p.soul_pending = false


func _is_collapsing(p: CharacterBody2D) -> bool:
        for fx in _collapses:
                if fx != null and is_instance_valid(fx) and fx.victim == p:
                        return true
        return false


func _check_boss_death() -> void:
        # TASK 23: in 2P la morte/gestione continue è del flusso per-player
        # (_check_player2_elimination + ContinuesOverlay). Questo ramo
        # scene-based (snapshot + ContinuesScreen) vale SOLO in 1P.
        if not (GameManager and GameManager.num_players == 2):
                # TASK 87: il player si sta ancora accasciando — la
                # transizione verso CONTINUES/LOSE aspetta la fine
                # dell'animazione di morte (~1.2s).
                # TASK 101 (continue DOPO l'animazione di morte): il gate
                # copre anche il frame della morte STESSA (soul_pending /
                # collapse_requested): l'effetto di collasso parte infatti
                # al frame successivo (_start_pending_collapses è in testa a
                # _update_boss), quindi _is_collapsing() da solo lasciava
                # passare la transizione PRIMA che l'animazione iniziasse.
                if _is_collapsing(player) or player.soul_pending \
                                or player.collapse_requested:
                        return
                # Player death -> continues (1P, flusso scene-based storico)
                var p1_dead_1p: bool = player.lives <= 0
                if p1_dead_1p:
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
                                # TASK 43: salva anche lo stato delle ARCHITETTURE
                                # — un pilastro crollato NON risorge al continue.
                                var pillars_snap: Array = []
                                for pillar in _arena_pillars:
                                        if pillar == null or not is_instance_valid(pillar):
                                                continue
                                        pillars_snap.append({
                                                "idx": int(pillar.pillar_index),
                                                "state": int(pillar.state),
                                                "hp": int(pillar.hp),
                                        })
                                # TASK 50: snapshot dei muri-rovina (il SEED
                                # ricrea lo stesso labirinto al restore)
                                var ruins_snap: Array = []
                                for ruin in _arena_ruins:
                                        if ruin == null or not is_instance_valid(ruin):
                                                continue
                                        ruins_snap.append(ruin.snapshot())
                                GameManager.session_snapshot = {
                                        "kind": "boss",
                                        "level": current_level,
                                        "boss_health": int(boss.health) if (boss != null and is_instance_valid(boss)) else 0,
                                        "arena_pillars": pillars_snap,
                                        "arena_ruins": ruins_snap,
                                        "arena_ruin_seed": int(_arena_ruin_seed),
                                        "p1": {
                                                "score": player.score,
                                                "weapon": player.current_weapon.duplicate(),
                                                # TASK 99: la continue in boss
                                                # room conserva la progressione.
                                                "level": player.level,
                                                "skill_points": player.skill_points,
                                                "pending_levelup_fx": player.pending_levelup_fx,
                                                "skill_levels": player.skill_levels.duplicate(),
                                        },
                                        "p2": {
                                                "score": player2.score,
                                                "weapon": player2.current_weapon.duplicate(),
                                                "level": player2.level,
                                                "skill_points": player2.skill_points,
                                                "pending_levelup_fx": player2.pending_levelup_fx,
                                                "skill_levels": player2.skill_levels.duplicate(),
                                        } if (GameManager.num_players == 2 and player2.visible) else {},
                                }
                                if GameManager.continues_left > 0:
                                        GameManager.player_died(true)
                                else:
                                        GameManager.give_up()
                        return

        # Boss death -> next level
        if boss and boss.is_dead():
                # RELIC (Task 21): fase bonus già attiva/chiusa → mai ri-trigger.
                if _bonus_active or _bonus_screen != null:
                        return
                # TASK 86 — animazione di morte per-tipo del boss: PRIMA che
                # appaiano le card delle reliquie il boss viene 'inghiottito'
                # dal suolo (voragine di fiamme + vortice), sgretolato in
                # sassolini, trasformato in pipistrello ecc. (~2.4-2.8s). Il
                # fight resta congelato finché la sequenza emette `finished`.
                if not _death_seq_started:
                        _start_boss_death_sequence()
                        if _death_seq == null:
                                # Fallback (boss invalido): flusso originale
                                # senza animazione.
                                _finish_boss_death(false)
                return


# ============================================================================
# TASK 86 — ANIMAZIONE DI MORTE DEL BOSS (per-tipo)
# ============================================================================
func _start_boss_death_sequence() -> void:
        _death_seq_started = true
        if boss == null or not is_instance_valid(boss):
                return
        var seq: Node2D = BossDeathSequenceClass.new()
        seq.finished.connect(_on_boss_death_seq_finished)
        add_child(seq)  # sibling del Boss (z_index 50: sopra il boss)
        seq.begin(boss)
        _death_seq = seq


func _on_boss_death_seq_finished() -> void:
        if _death_seq != null and is_instance_valid(_death_seq):
                _death_seq.queue_free()
        _death_seq = null
        _finish_boss_death(true)


func _finish_boss_death(with_sequence: bool) -> void:
        # Corpo originale del ramo morte del boss: eseguito DOPO l'animazione
        # di morte (Task 86), o subito in fallback senza animazione.
        if AudioManager and not with_sequence:
                AudioManager.play_sound(AudioManager.SoundType.BOSS_DEATH)
        # Effetti Godot-native: screen shake forte + esplosione multipla
        # (solo fallback: la sequenza ha gia' shake/suoni per famiglia).
        if EffectsManager and not with_sequence:
                EffectsManager.screen_shake(15.0, 0.8)
                for i in 3:
                        var p := EffectsManager.spawn_blast_smoke(
                                        boss.pos + Vector2(randf() * 60 - 30, randf() * 60 - 30),
                                        Color(0.6, 0.45, 0.3), 12)
                        _add_capped_fx(p)
        player.add_life()
        # TASK 97: il boss e' il nemico PIU' REMUNERATIVO del gioco ( prima
        # dava 0 punti!): 2500 + 100 x indice boss (2500..4100). In 2P il
        # premio va a ENTRAMBI i player (hanno combattuto insieme).
        var boss_pts: int = C.BOSS_KILL_POINTS_BASE \
                        + GameManager.get_boss_index(current_level) \
                        * C.BOSS_KILL_POINTS_PER_INDEX
        player.add_score(boss_pts)
        if GameManager.num_players == 2 and player2 != null and player2.visible:
                player2.add_score(boss_pts)
        # TASK 39: il boss e' morto — libera l'arena (barili inclusi:
        # nessun proiettile vagante durante la schermata bonus).
        _clear_boss_arena()
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
                        # TASK 105 (NEW GAME PLUS): salva lo stato dei player
                        # PRIMA di uscire dalla scena: se dopo i credits il
                        # player accetta il NG+, begin_newgameplus() costruisce
                        # da QUESTO carry la progressione Level Up da conservare
                        # (livello/punti/abilità; score/reliquie si ignorano).
                        # offer_pending = i credits DOPO questa vittoria possono
                        # proporre la card NG+ (i credits aperti dal menu no).
                        GameManager.save_player_carry(player, player2)
                        GameManager.newgameplus_offer_pending = true
                        # Vittoria finale: NESSUNA schermata bonus (una
                        # reliquia non servirebbe più oltre la fine della
                        # campagna) — transizione diretta alla WinScreen.
                        GameManager.boss_defeated.emit(GameManager.get_boss_index(current_level))
                        GameManager.current_level = current_level + 1
                        GameManager.go_to_win()
                else:
                        # RELIC (Task 21): c'è un livello successivo →
                        # SCHERMATA BONUS. Il fight si congela e i player
                        # scelgono la reliquia; la transizione di livello
                        # avviene alla chiusura (_on_bonus_completed).
                        _start_bonus_phase()


# ============================================================================
# RELIC (Task 21) — SCHERMATA BONUS post-boss
# ============================================================================
func _start_bonus_phase() -> void:
        if _bonus_active or _bonus_screen != null:
                return
        _bonus_active = true
        # Chi sceglie: P1 sempre (se vivo); P2 solo se in 2P e non eliminato.
        var choosers: Array = [player]
        if GameManager and GameManager.num_players == 2 and player2.visible \
                        and player2.lives > 0:
                choosers.append(player2)
        _bonus_screen = BonusScreenClass.new()
        _bonus_screen.setup(current_level, choosers)
        _bonus_screen.bonus_completed.connect(_on_bonus_completed)
        add_child(_bonus_screen)
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.WIN)


# Tutti i choosers hanno scelto: prosegui col flusso originale del livello
# successivo (mirror del ramo "Back to maze" pre-Task-21, col carry esteso
# alle reliquie appena scelte).
func _on_bonus_completed() -> void:
        _bonus_active = false
        if _bonus_screen != null and is_instance_valid(_bonus_screen):
                _bonus_screen.queue_free()
        _bonus_screen = null
        if GameManager:
                GameManager.boss_defeated.emit(GameManager.get_boss_index(current_level))
                GameManager.current_level = current_level + 1
                # FIX (punteggio perso tra le scene): salva lo stato dei player
                # PRIMA del cambio scena — ora include anche reliquia e
                # armatura (Task 21) così attraversano il cambio di scena.
                GameManager.save_player_carry(player, player2)
                # TASK 106 (SALVA PARTITA): AUTO-SAVE su disco dopo ogni boss
                # vinto — la run corrente sovrascrive SEMPRE il proprio slot;
                # alla prima vittoria occupa uno slot libero (se sono tutti
                # occupati, la card chiede quale eliminare e il salvataggio
                # riprende a scelta fatta).
                if not _autosave_run():
                        return  # la card di overflow completa il flusso
                GameManager.go_to_maze()


## TASK 106: scrive lo slot della run corrente. Ritorna true se il
## salvataggio è COMPLETO (si può cambiare scena); false se ha aperto la
## card di scelta slot da eliminare (10/10 pieni) — i callback
## _on_slot_freed_for_save / _on_slot_delete_aborted chiudono il flusso.
func _autosave_run() -> bool:
        if GameManager == null or SaveSystem == null:
                return true  # ambiente minimo (test senza disco): flusso invariato
        # La modalità ENDLESS non ha una progressione salvabile (run infinita).
        if GameManager.game_mode != C.GameMode.STORY:
                return true
        var slot: int = GameManager.save_slot_current
        if slot < 0:
                slot = SaveSystem.first_free_slot()
                if slot < 0:
                        # 10 slot pieni: chiedi quale eliminare PRIMA di salvare
                        # (la card pausa il tree e lo ripristina alla chiusura).
                        var card := SaveSlotsCardClass.new()
                        card.setup(SaveSlotsCardClass.Mode.DELETE,
                                        SaveSystem.all_summaries())
                        card.slot_deleted.connect(_on_slot_freed_for_save)
                        card.delete_aborted.connect(_on_slot_delete_aborted)
                        add_child(card)
                        return false
                GameManager.save_slot_current = slot
        SaveSystem.save_run(slot, _build_save_data())
        # L'annuncio "Partita salvata..." appare al livello successivo.
        GameManager.save_announce_pending = true
        return true


## Dati completi dello slot: livello di gioco (già il SUCCESSIVO al boss),
## personaggi, modalità, tier NG+ e il carry appena salvato (punteggio,
## vite, level up, reliquie).
func _build_save_data() -> Dictionary:
        return {
                        "num_players": GameManager.num_players,
                        "game_mode": GameManager.game_mode,
                        "newgameplus_tier": GameManager.newgameplus_tier,
                        "current_level": GameManager.current_level,
                        "char1": GameManager.player1_character,
                        "char2": GameManager.player2_character,
                        "carry_p1": GameManager.carry_p1.duplicate(true),
                        "carry_p2": GameManager.carry_p2.duplicate(true),
        }


## TASK 106: slot liberato dalla card di overflow -> salva lì e prosegui.
func _on_slot_freed_for_save(slot: int) -> void:
        if SaveSystem == null:
                GameManager.go_to_maze()
                return
        GameManager.save_slot_current = slot
        SaveSystem.save_run(slot, _build_save_data())
        GameManager.save_announce_pending = true
        GameManager.go_to_maze()


## TASK 106: nessuno slot eliminato -> si prosegue SENZA salvataggio
## (richiesta utente: la scelta è esplicita, il gioco non si blocca).
func _on_slot_delete_aborted() -> void:
        GameManager.go_to_maze()


# ============================================================================
# RELIC (Task 21) — passate reliquie nella boss room
# ============================================================================
# Fendente in mischia: shoot() del player con arma mischia alza melee_pending;
# qui si consuma e si applica il danno al boss se è nella shape del colpo.
func _check_pending_relic_melee(p: CharacterBody2D) -> void:
        if not p.melee_pending:
                return
        var def: Dictionary = p.consume_melee_pending()
        if def.is_empty() or boss == null or not is_instance_valid(boss) \
                        or boss.is_dead():
                return
        var aim: Vector2 = Vector2(
                        float(p.dx if p.dx != 0 else p.last_dx),
                        float(p.dy if p.dy != 0 else p.last_dy))
        if aim == Vector2.ZERO:
                aim = Vector2(1.0, 0.0)
        if C.relic_melee_in_shape(def, aim, p.get_pixel_pos(), boss.pos):
                boss.take_damage(C.relic_melee_flat_damage(def, p.is_fury_active()))
                if AudioManager:
                        AudioManager.play_sound(AudioManager.SoundType.BOSS_HIT)
                if EffectsManager:
                        var hit_fx := EffectsManager.spawn_sparks(boss.pos, 14)
                        _add_capped_fx(hit_fx)
        # TASK 39: il fendente reliquia FRANTUMA anche le architetture
        # adiacenti (una spada spacca la pietra meglio di una pallottola).
        if C.BOSS_ARENA_RUINS_ENABLED:
                for ruin in _arena_ruins:
                        if ruin == null or not is_instance_valid(ruin) or not ruin.is_standing():
                                continue
                        if ruin.blocks_point(p.get_pixel_pos()
                                        + aim * 44.0, 26.0):
                                _damage_ruin(ruin, p.get_pixel_pos())
        for pillar in _arena_pillars:
                if pillar == null or not is_instance_valid(pillar) or not pillar.is_standing():
                        continue
                if C.relic_melee_in_shape(def, aim, p.get_pixel_pos(), pillar.position):
                        _damage_pillar(pillar, p.get_pixel_pos())


# Sterzo dei proiettili a RICERCA (Bastone dell'Arcimago): la sfera insegue
# il boss ruotando la direzione di un po' per frame (mirror homing boss).
func _steer_relic_homing_projectiles(p: CharacterBody2D) -> void:
        if boss == null or not is_instance_valid(boss) or boss.is_dead():
                return
        for proj in p.projectiles:
                if not proj.get("active", false) or not proj.get("homing", false):
                        continue
                var to_boss: Vector2 = (boss.pos - proj.get("pos", Vector2.ZERO))
                if to_boss.length_squared() < 1.0:
                        continue
                var desired: Vector2 = to_boss.normalized()
                proj["dir"] = proj.get("dir", Vector2(1, 0)).lerp(desired, 0.09).normalized()


# BOMBE dell'Alchimista: i proiettili "exploded" (parabola finita o muro)
# esplodono ad area — in boss room l'area raggiunge il boss se è nel raggio.
func _consume_relic_bombs(p: CharacterBody2D) -> void:
        var to_remove: Array = []
        for proj in p.projectiles:
                if not (proj.get("exploded", false) and not proj.get("consumed", false)):
                        continue
                proj["consumed"] = true
                to_remove.append(proj)
                var blast_pos: Vector2 = proj.get("pos", Vector2.ZERO)
                var radius: float = float(proj.get("radius_px", 96.0))
                if boss != null and is_instance_valid(boss) and not boss.is_dead():
                        if blast_pos.distance_squared_to(boss.pos) \
                                        < (radius + boss.size * 0.25) ** 2:
                                boss.take_damage(int(proj.get("power", 4)) \
                                                + (1 if p.is_fury_active() else 0))
                                if AudioManager:
                                        AudioManager.play_sound(AudioManager.SoundType.BOSS_HIT)
                if EffectsManager:
                        var boom := EffectsManager.spawn_explosion(blast_pos,
                                        Color(1.0, 0.6, 0.15), 30, 0.8)
                        _add_capped_fx(boom)
                        EffectsManager.screen_shake(8.0, 0.3)
                if AudioManager:
                        AudioManager.play_sound(AudioManager.SoundType.ENEMY_EXPLODE)
        for proj in to_remove:
                p.projectiles.erase(proj)


# CORAZZA DI FUOCO (aura): a ogni pulsazione tutti i nemici nel raggio
# prendono 1 danno — in boss room "nemici" = il boss se è a contatto.
func _tick_fire_armor(p: CharacterBody2D, delta_ms: float) -> void:
        if not p.has_relic_armor():
                return
        if not p.armor_aura_pulse(delta_ms):
                return
        var radius: float = float(p.armor_relic.get("aura_radius_px", 64.0))
        var aura_dmg: int = int(p.armor_relic.get("aura_damage", 1))
        if boss != null and is_instance_valid(boss) and not boss.is_dead():
                if p.get_pixel_pos().distance_squared_to(boss.pos) \
                                < (radius + boss.size * 0.25) ** 2:
                        boss.take_damage(aura_dmg)
        if EffectsManager:
                var ring := EffectsManager.spawn_explosion(p.get_pixel_pos(),
                                Color(1.0, 0.45, 0.2), 12, 0.4)
                _add_capped_fx(ring)
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.ENEMY_EXPLODE)


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
                # TASK 43: al continue si rinnovano SOLO i consumabili (barili,
                # cannone — come mina e armi a terra); le ARCHITETTURE rotte
                # NON risorgono: lo snapshot di sessione riapplica i danni.
                _respawn_boss_arena()
                return

        # New boss fight
        if boss:
                boss.queue_free()
        # Create boss via the Boss node's script
        # TASK 86: reset dello stato della sequenza di morte (run precedente).
        _death_seq = null
        _death_seq_started = false
        if boss_node:
                boss_node.setup(current_level, C.WINDOW_WIDTH, C.WINDOW_HEIGHT)
                boss = boss_node
                # TASK 86: reset delle trasformazioni dell'animazione di morte
                # (la sequenza lascia scale/rotation/modulate/visible sul nodo
                # Boss, che viene riusato tra i livelli).
                boss_node.scale = Vector2.ONE
                boss_node.rotation = 0.0
                boss_node.modulate = Color.WHITE
                boss_node.visible = true
        # TASK 51 — FASE 2: hook dei segnali del boss (annuncio, buche, salto).
        # Guard is_connected: start_boss_fight puo' essere richiamato sullo
        # stesso nodo (continue senza snapshot).
        if boss != null:
                if not boss.phase2_entered.is_connected(_on_boss_phase2_entered):
                        boss.phase2_entered.connect(_on_boss_phase2_entered)
                if not boss.spawn_pit.is_connected(_on_boss_spawn_pit):
                        boss.spawn_pit.connect(_on_boss_spawn_pit)
                if not boss.slam_landed.is_connected(_on_boss_slam_landed):
                        boss.slam_landed.connect(_on_boss_slam_landed)
        # TASK 91 (fix scatti alle distruzioni): pre-carica i contenuti
        # lazy di EffectsManager usati dai crolli (sheet esplosione,
        # materiali polvere/fumo) PRIMA che il fight parta: il primo
        # colpo fatale non paga piu' Image.load + upload GPU nel frame.
        if EffectsManager:
                EffectsManager.prewarm()
        # TASK 51: reset dello stato fase-2 del controller (buche/flash).
        boss_pits.clear()
        _phase2_flash_ms = 0.0
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
                player.current_weapon = {"type": 0, "power": 2, "ammo": C.BOSS_ROOM_AMMO_MIN}
        elif not player.current_weapon.has("relic"):
                # Arma base valida: potenzialala per il boss
                player.current_weapon["ammo"] = maxi(player.current_weapon.get("ammo", 0), C.BOSS_ROOM_AMMO_MIN)
                player.current_weapon["power"] = 2
        # RELIC (Task 21): un'arma RELIQUIA (restore dal carry del labirinto)
        # resta INTATTA: ha la sua potenza e in boss room spara a colpi
        # infiniti (relic_infinite_shots = true in _ready).

        # Spawn the boss-room mine (1 per fight). Mirrors C++ Game.cpp
        # 2728-2843: a single bouncing mine at a random position in the
        # boss room; when collected by either player it starts bouncing
        # and, on impact with the boss, deals 30% of boss.max_health.
        _spawn_boss_room_mine()

        # TASK 39 — L'arena del boss: pilastri, barili e cannone d'assedio.
        _spawn_boss_arena()


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
                # TASK 26: munizioni armi a terra +30% (5 -> 7).
                w.ammo = 7
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
                # TASK 50 (mina a ricerca, coerente col labirinto): nella boss
                # room la mina ora INSEGUE il boss invece di vagare a caso
                # rimbalzando finché non esplode: steering continuo verso il
                # boss, i rimbalzi sui bordi restano solo come rete di sicurezza.
                if boss != null and not boss.is_dead():
                        var to_boss: Vector2 = boss.pos - mine_item.pos
                        if to_boss.length() > 1.0:
                                var m_speed: float = clampf(mine_item.velocity.length(), 4.5, 6.0)
                                mine_item.velocity = to_boss.normalized() * m_speed
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
                                        # TASK 50: nube di fumo morbida, non pallini
                                        var p := EffectsManager.spawn_blast_smoke(mine_item.pos)
                                        _add_capped_fx(p)
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
                                        # TASK 50: nube di fumo morbida, non pallini
                                        var p := EffectsManager.spawn_blast_smoke(mine_item.pos)
                                        _add_capped_fx(p)
                                if AudioManager:
                                        AudioManager.play_sound(AudioManager.SoundType.ENEMY_EXPLODE)
                                mine_item.active = false
                                mine_item.bouncing = false
                                mine_item.queue_free()
                                mine_item = null


# ============================================================================
# TASK 39 — L'ARENA DEL BOSS: pilastri, barili elementali, cannone d'assedio
# ============================================================================
# 4 pilastri a tema dell'elemento debole del boss (posizioni simmetriche,
# lontane dagli spawn di player e boss), 3 barili elementali (almeno 1
# dell'elemento debole) e 1 cannone d'assedio a terra.
func _spawn_boss_arena() -> void:
        var weak_el: int = C.get_boss_weakness(boss.boss_type) if boss != null \
                        else C.ElementKind.FIRE
        # --- TASK 50: MURO-LABIRINTO IN ROVINA (sostituisce i 4 pilastri,
        # vedi richiesta utente: "elementi troppi e piccoli... pezzi di
        # muraglia di labirinto spezzato, procedurali, diversi ogni
        # partita e ogni boss"). Rollback: BOSS_ARENA_RUINS_ENABLED=false
        # riporta i pilastri simmetrici del TASK 39. ---
        if C.BOSS_ARENA_RUINS_ENABLED:
                _generate_arena_ruins()
        else:
                # --- LEGACY: 4 pilastri a posizioni fisse simmetriche ---
                var pillar_spots: Array = [
                        Vector2(430.0, 430.0), Vector2(1490.0, 430.0),
                        Vector2(430.0, 800.0), Vector2(1490.0, 800.0),
                ]
                for i in range(mini(C.BOSS_ARENA_PILLAR_COUNT, pillar_spots.size())):
                        var pillar: Node2D = BossArenaPillarClass.new()
                        boss_room_weapons_node.add_child(pillar)
                        if pillar.has_method("setup"):
                                pillar.setup(pillar_spots[i], weak_el, i,
                                                boss_room_weapons_node)
                        _arena_pillars.append(pillar)
        # --- Barili: 3 posizioni scelte da un pool (prima = elemento debole) ---
        var barrel_spots: Array = [
                Vector2(270.0, 320.0), Vector2(1650.0, 320.0),
                Vector2(270.0, 920.0), Vector2(1650.0, 920.0),
                Vector2(960.0, 580.0),
        ]
        barrel_spots.shuffle()
        var elements_pool: Array = [
                C.ElementKind.FIRE, C.ElementKind.FROST,
                C.ElementKind.LIGHTNING, C.ElementKind.POISON,
        ]
        for i in range(mini(C.BOSS_ARENA_BARREL_COUNT, barrel_spots.size())):
                var el: int = weak_el if i == 0 \
                                else elements_pool[randi() % elements_pool.size()]
                var barrel: Node2D = ElementalBarrelClass.new()
                boss_room_weapons_node.add_child(barrel)
                if barrel.has_method("setup"):
                        barrel.setup(barrel_spots[i], el)
                if barrel.has_signal("exploded"):
                        barrel.exploded.connect(_on_barrel_exploded)
                _arena_barrels.append(barrel)
        # --- Cannone d'assedio: uno a terra tra il centro e lo spawn player ---
        _spawn_arena_siege(Vector2(C.WINDOW_WIDTH * 0.5, 850.0))
        _arena_renewal_ms = 0.0


# ---------------------------------------------------------------------------
# TASK 50 — GENERAZIONE PROCEDURALE DEL LABIRINTO IN ROVINA
# ---------------------------------------------------------------------------
# Segmenti di muraglia (2-4 celle) piazzati su una griglia di ancore con
# vincoli: zone di rispetto (spawn boss/player, barili, cannone), corridoi
# minimi tra i muri (il player ci passa in mezzo), niente sovrapposizioni.
# Il seed dipende dal TEMPO + tipo di boss + livello: layout DIVERSO ad ogni
# partita e ad ogni boss, ma DETERMINISTICO per lo snapshot/restore.
func _generate_arena_ruins(forced_seed: int = -1) -> void:
        # seed: tempo corrente ^ boss ^ livello (per-partita, per-boss)
        if forced_seed >= 0:
                _arena_ruin_seed = forced_seed
        else:
                var boss_id: int = boss.boss_type if boss != null else 0
                var lvl: int = GameManager.current_level if GameManager \
                                and "current_level" in GameManager else 0
                _arena_ruin_seed = (Time.get_ticks_msec() & 0x7fffffff) \
                                ^ (boss_id * 2654435761) ^ (lvl * 40503)
        var rng := RandomNumberGenerator.new()
        rng.seed = _arena_ruin_seed
        # pulisci eventuali rovine precedenti
        for ruin in _arena_ruins:
                if ruin != null and is_instance_valid(ruin):
                        ruin.queue_free()
        _arena_ruins.clear()
        # --- zone di rispetto (keep-out) ---
        # NB: si usa la posizione di SPAWN canonica del boss (centro-alto),
        # NON boss.pos corrente: il layout deve dipendere SOLO dal seed per
        # essere identico al restore dallo snapshot (boss.pos nel frattempo
        # e' cambiato e romperebbe il determinismo).
        var keep_out: Array = []
        keep_out.append([Vector2(C.WINDOW_WIDTH * 0.5, 420.0), 230.0])   # spawn boss
        keep_out.append([Vector2(C.WINDOW_WIDTH * 0.5, 880.0), 170.0])   # spawn player
        for spot in [Vector2(270.0, 320.0), Vector2(1650.0, 320.0),
                        Vector2(270.0, 920.0), Vector2(1650.0, 920.0),
                        Vector2(960.0, 580.0)]:
                keep_out.append([spot, 90.0])                   # barili
        keep_out.append([Vector2(C.WINDOW_WIDTH * 0.5, 850.0), 120.0])  # cannone
        # --- piazzamento ---
        var placed: Array = []   # Rect2 (ingombro + corridoio) dei segmenti
        var target: int = rng.randi_range(C.BOSS_ARENA_RUIN_MIN, C.BOSS_ARENA_RUIN_MAX)
        var attempts: int = 0
        while _arena_ruins.size() < target and attempts < 220:
                attempts += 1
                var axis: String = "h" if rng.randf() < 0.62 else "v"
                var length_cells: int
                var roll: float = rng.randf()
                if roll < 0.30:
                        length_cells = 2
                elif roll < 0.72:
                        length_cells = 3
                else:
                        length_cells = 4
                length_cells = mini(length_cells, C.BOSS_ARENA_RUIN_MAX_LEN)
                var len_px: float = length_cells * C.TILE_SIZE
                # centro candidato su griglia di mezze celle
                var half_w: float = len_px * 0.5 if axis == "h" else C.TILE_SIZE * 0.5
                var half_h: float = C.TILE_SIZE * 0.5 if axis == "h" else len_px * 0.5
                var cx: float = 180.0 + rng.randf() * (C.WINDOW_WIDTH - 360.0)
                var cy: float = C.UI_HEIGHT + 150.0 \
                                + rng.randf() * (C.WINDOW_HEIGHT - C.UI_HEIGHT - 330.0)
                cx = roundf(cx / 32.0) * 32.0
                cy = roundf(cy / 32.0) * 32.0
                var rect := Rect2(cx - half_w, cy - half_h, half_w * 2.0, half_h * 2.0)
                # corridoio minimo attorno (il gap tra muri lascia passare il player)
                var corridor := rect.grow(C.BOSS_ARENA_RUIN_PASS_GAP * 0.5)
                var ok: bool = true
                # bounds arena
                if rect.position.x < 110.0 or rect.end.x > C.WINDOW_WIDTH - 110.0:
                        ok = false
                if rect.position.y < C.UI_HEIGHT + 110.0 \
                                or rect.end.y > C.WINDOW_HEIGHT - 90.0:
                        ok = false
                # keep-out (centro del segmento lontano dalle zone protette)
                if ok:
                        for ko in keep_out:
                                var kpos: Vector2 = ko[0]
                                var krad: float = ko[1]
                                var nearest := Rect2(rect.position - Vector2(krad, krad),
                                                rect.size + Vector2(krad * 2.0, krad * 2.0))
                                if nearest.has_point(kpos):
                                        ok = false
                                        break
                # sovrapposizione con altri segmenti (con corridoio)
                if ok:
                        for other in placed:
                                if other.intersects(corridor):
                                        ok = false
                                        break
                if not ok:
                        continue
                placed.append(rect)
                var ruin: Node2D = BossArenaRuinClass.new()
                boss_room_weapons_node.add_child(ruin)
                if ruin.has_method("setup"):
                        ruin.setup(Vector2(cx, cy), axis, length_cells,
                                        rng.randf() * 100.0, _arena_ruins.size(),
                                        boss_room_weapons_node)
                _arena_ruins.append(ruin)
        # distribuzione di cortesia: se una meta' arena e' rimasta vuota,
        # sposta un segmento lì (copertura bilanciata sinistra/destra)
        _balance_arena_ruins(placed)
        if _arena_ruins.is_empty():
                push_warning("[TASK50] nessun muro-rovina piazzato (seed="
                                + str(_arena_ruin_seed) + ")")


## Garantisce almeno 2 segmenti per meta' arena (sinistra/destra): se tutto
## e' finito da un lato, sposta i piu' esterni nell'altra meta'.
func _balance_arena_ruins(placed: Array) -> void:
        if _arena_ruins.size() < 2:
                return
        var mid_x: float = C.WINDOW_WIDTH * 0.5
        var left_count: int = 0
        for r in placed:
                if r.get_center().x < mid_x:
                        left_count += 1
        var min_side: int = 2
        if left_count >= min_side and _arena_ruins.size() - left_count >= min_side:
                return
        # sposta finche' entrambi i lati non hanno min_side segmenti
        var side_needed: int
        if left_count < min_side:
                side_needed = 0  # serve a sinistra
        else:
                side_needed = 1  # serve a destra
        var moved: int = 0
        for i in range(_arena_ruins.size()):
                if moved >= min_side:
                        break
                var ruin: Node2D = _arena_ruins[i]
                if ruin == null or not is_instance_valid(ruin):
                        continue
                var on_side: int = 1 if ruin.origin.x >= mid_x else 0
                if on_side == side_needed:
                        continue
                # sposta il segmento nella meta' opposta (specchiato)
                var new_x: float = C.WINDOW_WIDTH - ruin.origin.x
                # verifica che lo slot specchiato non collida con altri
                var r: Rect2 = ruin.get_rect()
                var mirrored := Rect2(new_x - r.size.x * 0.5, r.position.y,
                                r.size.x, r.size.y).grow(C.BOSS_ARENA_RUIN_PASS_GAP * 0.5)
                var blocked: bool = false
                for other in placed:
                        if other != r and other.intersects(mirrored):
                                blocked = true
                                break
                if blocked:
                        continue
                ruin.origin = Vector2(new_x, ruin.origin.y)
                ruin.position = ruin.origin
                moved += 1


# Spawna il pickup del cannone (usato anche dal rinnovo dell'arena).
func _spawn_arena_siege(at_pos: Vector2) -> void:
        if _arena_siege != null and is_instance_valid(_arena_siege):
                return
        var cannon: Node2D = BossSiegeCannonClass.new()
        boss_room_weapons_node.add_child(cannon)
        if cannon.has_method("setup"):
                cannon.setup(at_pos)
        _arena_siege = cannon


# Continue (2P in-scena): si rinnovano SOLO i consumabili — barili finiti e
# cannone esaurito (come mina e armi a terra). TASK 43: le ARCHITETTURE non
# si toccano MAI — i pilastri in piedi restano, le macerie restano macerie
# ("quando un'architettura si rompe non deve risorgere, neanche se il
# player muore"). Il boss conserva gli HP.
func _respawn_boss_arena() -> void:
        _clear_arena_consumables()
        if boss != null and not boss.is_dead():
                _renew_boss_arena()


# TASK 43: libera SOLO i consumabili dell'arena (barili + cannone), senza
# toccare i pilastri — in piedi o macerie che siano, restano per sempre.
func _clear_arena_consumables() -> void:
        for barrel in _arena_barrels:
                if barrel != null and is_instance_valid(barrel):
                        barrel.queue_free()
        _arena_barrels.clear()
        if _arena_siege != null and is_instance_valid(_arena_siege):
                _arena_siege.queue_free()
        _arena_siege = null


# TASK 43: applica lo snapshot delle ARCHITETTURE salvato alla morte del
# player (continue 1P con ricarica scena). L'arena e' stata appena ricreata
# fresca da start_boss_fight: qui si RIAPPLICANO i danni — i pilastri che
# erano gia' crollati tornano cumuli di macerie (senza animazione ne'
# frammenti: il crollo era gia' avvenuto), quelli in piedi recuperano le
# crepe deterministiche derivate dagli HP residui.
func _restore_arena_pillars_from_snapshot(snap: Dictionary) -> void:
        # TASK 50: prima i muri-rovina (rigenera lo STESSO labirinto dal seed
        # salvato, poi riapplica gli stati: in piedi con HP residui o macerie
        # senza animazione — il crollo era gia' avvenuto).
        var ruins_states: Array = snap.get("arena_ruins", [])
        if not ruins_states.is_empty():
                var saved_seed: int = int(snap.get("arena_ruin_seed", -1))
                if saved_seed >= 0:
                        _generate_arena_ruins(saved_seed)
                for entry in ruins_states:
                        var ridx: int = int(entry.get("idx", -1))
                        var rst: int = int(entry.get("state", 0))
                        var rhp: int = int(entry.get("hp", C.BOSS_ARENA_RUIN_HP))
                        for ruin in _arena_ruins:
                                if ruin == null or not is_instance_valid(ruin):
                                        continue
                                if ruin.ruin_index != ridx:
                                        continue
                                if rst != int(BossArenaRuinClass.RuinState.STANDING):
                                        ruin.restore_from_snapshot(true)
                                else:
                                        ruin.restore_from_snapshot(false, rhp)
                                break
                return
        var states: Array = snap.get("arena_pillars", [])
        if states.is_empty():
                return
        for entry in states:
                var idx: int = int(entry.get("idx", -1))
                var st: int = int(entry.get("state", 0))
                var hp_snap: int = int(entry.get("hp", C.BOSS_ARENA_PILLAR_HP))
                for pillar in _arena_pillars:
                        if pillar == null or not is_instance_valid(pillar):
                                continue
                        if pillar.pillar_index != idx:
                                continue
                        # COLLAPSING (1) al momento della morte -> il crollo si
                        # e' gia' completato durante la schermata continue;
                        # ogni stato != STANDING (0) torna CUMULO DI MACERIE.
                        if st != int(BossArenaPillarClass.PillarState.STANDING):
                                pillar.restore_from_snapshot(true)
                        else:
                                pillar.restore_from_snapshot(false, hp_snap)
                        break


# Libera tutti i props dell'arena (morte del boss, cambio scena, continue).
func _clear_boss_arena() -> void:
        for pillar in _arena_pillars:
                if pillar != null and is_instance_valid(pillar):
                        pillar.queue_free()
        _arena_pillars.clear()
        for ruin in _arena_ruins:
                if ruin != null and is_instance_valid(ruin):
                        ruin.queue_free()
        _arena_ruins.clear()
        for barrel in _arena_barrels:
                if barrel != null and is_instance_valid(barrel):
                        barrel.queue_free()
        _arena_barrels.clear()
        if _arena_siege != null and is_instance_valid(_arena_siege):
                _arena_siege.queue_free()
        _arena_siege = null
        # frammenti ancora in volo
        for node in get_tree().get_nodes_in_group("arena_debris"):
                if node is Node2D and is_instance_valid(node):
                        node.queue_free()


# Tick per-frame dell'arena: pickup barili/cannone, frammenti vs boss,
# rimbalzo del boss sui pilastri in piedi, rinnovo periodico.
func _update_boss_arena(delta_ms: float) -> void:
        # pulizia riferimenti morti (barili esplosi / pilastri liberati)
        _prune_arena_refs()
        # --- pickup barili a terra (P1 e P2) ---
        for barrel in _arena_barrels:
                if barrel == null or not is_instance_valid(barrel) \
                                or not barrel.is_idle():
                        continue
                for p in [player, player2]:
                        if p == null or not is_instance_valid(p) or not p.visible \
                                        or p.soul_pending or p.lives <= 0:
                                continue
                        if p.get_pixel_pos().distance_squared_to(barrel.position) \
                                        < 676.0:  # 26 px
                                barrel.pickup(p)
                                break
        # --- barili lanciati vs boss: detonazione al contatto ---
        if boss != null and is_instance_valid(boss) and not boss.is_dead():
                for barrel in _arena_barrels:
                        if barrel == null or not is_instance_valid(barrel):
                                continue
                        if barrel.state != 2:  # 2 = THROWN
                                continue
                        var barrel_r: float = boss.size * 0.5 + 14.0
                        if barrel.position.distance_squared_to(boss.pos) < barrel_r * barrel_r:
                                barrel.detonate()
        # --- pickup cannone d'assedio ---
        if _arena_siege != null and is_instance_valid(_arena_siege):
                for p in [player, player2]:
                        if p == null or not is_instance_valid(p) or not p.visible:
                                continue
                        if p.get_pixel_pos().distance_squared_to(
                                        _arena_siege.position) < 900.0:
                                p.collect_weapon(
                                                BossSiegeCannonClass.make_siege_weapon())
                                if AudioManager:
                                        AudioManager.play_sound(
                                                        AudioManager.SoundType.RELIC_PICKUP)
                                if EffectsManager:
                                        var burst: Node2D = EffectsManager.spawn_pickup_burst(
                                                        _arena_siege.position,
                                                        Color(1.0, 0.80, 0.30))
                                        _add_capped_fx(burst)
                                _arena_siege.queue_free()
                                _arena_siege = null
                                break
        # --- frammenti (arena_debris) vs boss ---
        if boss != null and is_instance_valid(boss) and not boss.is_dead():
                var boss_r: float = boss.size * 0.5 + 8.0
                for node in get_tree().get_nodes_in_group("arena_debris"):
                        if not node is Node2D or not is_instance_valid(node):
                                continue
                        if node.position.distance_squared_to(boss.pos) < boss_r * boss_r:
                                boss.take_damage(C.BOSS_ARENA_PILLAR_FRAGMENT_DMG)
                                if AudioManager:
                                        AudioManager.play_sound(
                                                        AudioManager.SoundType.BOSS_HIT)
                                if EffectsManager:
                                        var frag_fx: Node2D = EffectsManager.spawn_sparks(
                                                        node.position, 10)
                                        _add_capped_fx(frag_fx)
                                if node.has_method("consume_on_boss"):
                                        node.consume_on_boss()
        # --- il boss RIMBALZA sui pilastri in piedi (ostacoli fisici).
        # TASK 50: solo nel ramo LEGACY — i muri-rovina sono BASI e spezzati:
        # il boss (creatura gigante) li CALPESTA passando sopra, cosi' non
        # puo' mai incastellarsi nel labirinto in rovina. ---
        if not C.BOSS_ARENA_RUINS_ENABLED \
                        and boss != null and is_instance_valid(boss) and not boss.is_dead():
                for pillar in _arena_pillars:
                        if pillar == null or not is_instance_valid(pillar) \
                                        or not pillar.is_standing():
                                continue
                        var min_d: float = boss.size * 0.5 \
                                        + C.BOSS_ARENA_PILLAR_RADIUS * 0.7
                        if boss.pos.distance_squared_to(pillar.position) < min_d * min_d:
                                var away: Vector2 = (boss.pos - pillar.position)
                                if away.length() < 0.01:
                                        away = Vector2(0.0, 1.0)
                                away = away.normalized()
                                # spingi fuori dal pilastro + inversione marcia
                                boss.pos = pillar.position + away * (min_d + 2.0)
                                if absf(away.x) > absf(away.y):
                                        boss.dx = -boss.dx
                                else:
                                        boss.dy = -boss.dy
                                break
        # --- rinnovo periodico dell'arena (scontri lunghi) ---
        _arena_renewal_ms += float(delta_ms)
        if _arena_renewal_ms >= C.BOSS_ARENA_RENEWAL_MS:
                _arena_renewal_ms = 0.0
                _renew_boss_arena()


# Rinnova cio' che e' stato consumato: barili finiti e cannone esaurito.
# I frammenti in volo non bloccano il rinnovo.
# TASK 43: le ARCHITETTURE non si rinnovano MAI — un pilastro crollato
# resta un cumulo di macerie per tutta la durata dello scontro.
func _renew_boss_arena() -> void:
        if boss == null or not is_instance_valid(boss) or boss.is_dead():
                return
        var weak_el: int = C.get_boss_weakness(boss.boss_type)
        # TASK 43: i PILASTRI non si toccano (richiesta utente: "quando
        # un'architettura si rompe non deve risorgere"). Il vecchio blocco
        # ricreava i pilastri mancanti alle 4 posizioni fisse: rimosso.
        # barili: se non ne restano (raccolti/esplosi), ne spawna 2
        var usable_barrels: int = 0
        for barrel in _arena_barrels:
                if barrel != null and is_instance_valid(barrel) \
                                and barrel.state != ElementalBarrelClass.State.EXPLODING:
                        usable_barrels += 1
        if usable_barrels == 0:
                var barrel_spots: Array = [
                        Vector2(380.0, 560.0), Vector2(1540.0, 640.0),
                ]
                for i in range(barrel_spots.size()):
                        var el: int = weak_el if i == 0 else randi() % 4
                        var barrel: Node2D = ElementalBarrelClass.new()
                        boss_room_weapons_node.add_child(barrel)
                        if barrel.has_method("setup"):
                                barrel.setup(barrel_spots[i], el)
                        if barrel.has_signal("exploded"):
                                barrel.exploded.connect(_on_barrel_exploded)
                        _arena_barrels.append(barrel)
        # cannone: se non c'e' a terra e NESSUN player lo impugna ancora
        var siege_in_use: bool = _arena_siege != null and is_instance_valid(_arena_siege)
        if not siege_in_use:
                for p in [player, player2]:
                        if p != null and is_instance_valid(p) and p.visible \
                                        and int(p.current_weapon.get("type", -1)) \
                                                        == C.WeaponType.SIEGE \
                                        and int(p.current_weapon.get("ammo", 0)) > 0:
                                siege_in_use = true
                                break
        if not siege_in_use:
                _spawn_arena_siege(Vector2(C.WINDOW_WIDTH * 0.5, 850.0))


# Rimuove i riferimenti a nodi liberati (esplosi/crollati).
func _prune_arena_refs() -> void:
        var keep_pillars: Array = []
        for pillar in _arena_pillars:
                if pillar != null and is_instance_valid(pillar):
                        keep_pillars.append(pillar)
        _arena_pillars = keep_pillars
        var keep_ruins: Array = []
        for ruin in _arena_ruins:
                if ruin != null and is_instance_valid(ruin):
                        keep_ruins.append(ruin)
        _arena_ruins = keep_ruins
        var keep_barrels: Array = []
        for barrel in _arena_barrels:
                if barrel != null and is_instance_valid(barrel):
                        keep_barrels.append(barrel)
        _arena_barrels = keep_barrels


# Barile trasportato da `p` (o null).
func _carried_barrel_of(p: CharacterBody2D) -> Node2D:
        for barrel in _arena_barrels:
                if barrel != null and is_instance_valid(barrel) \
                                and barrel.is_carried_by(p):
                        return barrel
        return null


# Lancia il barile trasportato da `p` nella direzione di mira. Ritorna false
# se `p` non trasporta nulla (il controller prosegue con lo sparo normale).
func _try_throw_carried_barrel(p: CharacterBody2D) -> bool:
        var barrel: Node2D = _carried_barrel_of(p)
        if barrel == null:
                return false
        var aim: Vector2 = Vector2(
                        float(p.dx if p.dx != 0 else p.last_dx),
                        float(p.dy if p.dy != 0 else p.last_dy))
        barrel.throw_barrel(aim)
        p.shoot_cooldown = 300
        return true


# Proiettili del player vs pilastri in piedi: il colpo si FRANTUMA sul
# pilastro (consumato) e gli infligge 1 danno.
func _check_player_projectiles_vs_pillars(p: CharacterBody2D) -> void:
        # TASK 50: unifica il check sui due tipi di architettura (rovine
        # AABB / pilastri legacy a raggio): il colpo si FRANTUMA (consumato)
        # e infligge 1 danno alla copertura.
        if C.BOSS_ARENA_RUINS_ENABLED:
                if _arena_ruins.is_empty():
                        return
                for proj in p.projectiles:
                        if not proj.get("active", false):
                                continue
                        var proj_pos_r: Vector2 = proj.get("pos", Vector2.ZERO)
                        for ruin in _arena_ruins:
                                if ruin == null or not is_instance_valid(ruin) \
                                                or not ruin.is_standing():
                                        continue
                                if ruin.blocks_point(proj_pos_r, 5.0):
                                        proj["active"] = false
                                        _damage_ruin(ruin, proj_pos_r)
                                        break
                return
        if _arena_pillars.is_empty():
                return
        var r_sq: float = C.BOSS_ARENA_PILLAR_RADIUS * C.BOSS_ARENA_PILLAR_RADIUS
        for proj in p.projectiles:
                if not proj.get("active", false):
                        continue
                var proj_pos: Vector2 = proj.get("pos", Vector2.ZERO)
                for pillar in _arena_pillars:
                        if pillar == null or not is_instance_valid(pillar) \
                                        or not pillar.is_standing():
                                continue
                        if proj_pos.distance_squared_to(pillar.position) < r_sq:
                                proj["active"] = false
                                _damage_pillar(pillar, proj_pos)
                                break


## Danno a un muro-rovina + feedback comune (crack, scintille, micro-shake).
func _damage_ruin(ruin: Node2D, from_pos: Vector2) -> void:
        if ruin == null or not is_instance_valid(ruin) or not ruin.is_standing():
                return
        ruin.take_hit()
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.PILLAR_CRACK)
        if EffectsManager:
                EffectsManager.screen_shake(2.5, 0.12)
                var sparks: Node2D = EffectsManager.spawn_sparks(from_pos, 10)
                _add_capped_fx(sparks)


# Danno a un pilastro + feedback comune (crack, scintille, micro-shake).
func _damage_pillar(pillar: Node2D, from_pos: Vector2) -> void:
        if pillar == null or not is_instance_valid(pillar) or not pillar.is_standing():
                return
        pillar.take_hit()
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.PILLAR_CRACK)
        if EffectsManager:
                EffectsManager.screen_shake(2.5, 0.12)
                var sparks: Node2D = EffectsManager.spawn_sparks(from_pos, 10)
                _add_capped_fx(sparks)


# Detonazione di un barile elementale: danno %HP al boss (x2.5 se elemento
# debole), danno ai player nella deflagrazione, SFX elementale dedicato.
func _on_barrel_exploded(pos: Vector2, element: int) -> void:
        var pal: Dictionary = C.get_element_palette(element)
        var col: Color = pal.get("color", Color.WHITE)
        # --- SFX elementale dedicato (il fuoco riusa il botto del barile) ---
        if AudioManager:
                match element:
                        C.ElementKind.FIRE:
                                AudioManager.play_sound(
                                                AudioManager.SoundType.BARREL_EXPLODE)
                        C.ElementKind.FROST:
                                AudioManager.play_sound(
                                                AudioManager.SoundType.BURST_FROST)
                        C.ElementKind.LIGHTNING:
                                AudioManager.play_sound(
                                                AudioManager.SoundType.BURST_LIGHTNING)
                        C.ElementKind.POISON:
                                AudioManager.play_sound(
                                                AudioManager.SoundType.BURST_POISON)
        if EffectsManager:
                EffectsManager.screen_shake(8.0, 0.4)
                # TASK 50 (pallini arancioni — bug utente): RIMOSSA la nube di
                # particelle tonde spawn_explosion(col): il barile ha GIA' la
                # sua deflagrazione completa (_draw_explosion di ElementalBarrel:
                # core incandescente, doppia onda d'urto, 12 spine, fumo e
                # detriti disegnati). Le palline tonde sovrapposte risultavano
                # "puntini arancioni" fluttuanti sopra l'esplosione vera.
        # --- danno al boss (raggio blast + meta' raggio del boss) ---
        if boss != null and is_instance_valid(boss) and not boss.is_dead():
                var hit_r: float = C.BOSS_ARENA_BARREL_BLAST_RADIUS + boss.size * 0.5
                if pos.distance_squared_to(boss.pos) < hit_r * hit_r:
                        var weak: bool = element == C.get_boss_weakness(boss.boss_type)
                        var dmg: int = int(round(float(boss.max_health)
                                        * C.BOSS_ARENA_BARREL_BASE_PCT))
                        if weak:
                                dmg = int(round(float(dmg)
                                                * C.BOSS_ARENA_BARREL_WEAK_MULT))
                        boss.take_damage(dmg)
                        # trova il barile appena esploso per il testo DEBOLEZZA!
                        for barrel in _arena_barrels:
                                if barrel != null and is_instance_valid(barrel) \
                                                and barrel.state \
                                                == ElementalBarrelClass.State.EXPLODING \
                                                and barrel.position.distance_to(pos) < 2.0 \
                                                and barrel.has_method("confirm_weakness"):
                                        barrel.confirm_weakness()
                                        break
                        if weak:
                                if AudioManager:
                                        AudioManager.play_sound(
                                                        AudioManager.SoundType.WEAKNESS_HIT)
                                if EffectsManager:
                                        EffectsManager.screen_shake(11.0, 0.5)
                        else:
                                if AudioManager:
                                        AudioManager.play_sound(
                                                        AudioManager.SoundType.BOSS_HIT)
        # --- danno ai player nella deflagrazione (saltare/invulnerabilita' salva) ---
        for p in [player, player2]:
                if p == null or not is_instance_valid(p) or not p.visible:
                        continue
                if p.is_jumping() or p.is_invulnerable() or p.soul_pending:
                        continue
                if p.get_pixel_pos().distance_squared_to(pos) \
                                < C.BOSS_ARENA_BARREL_BLAST_RADIUS \
                                                * C.BOSS_ARENA_BARREL_BLAST_RADIUS:
                        p.take_hazard_damage(C.BOSS_ARENA_BARREL_PLAYER_DMG)


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
                # FIX (stamina salti): barra sotto quella della vita (rosa/arancione/rosso).
                "stamina": player.get_stamina_ratio(),
                "stamina_exhausted": player.is_stamina_exhausted(),
                # TASK 99 (LEVEL UP): livello e punti da spendere in HUD.
                "level": player.level,
                "skill_points": player.skill_points,
                # RELIC (Task 21): stato armatura reliquia in HUD.
                "armor_name": C.get_armor_short_name(player.armor_relic),
                "armor_color": player.armor_relic.get("color", Color.WHITE),
                "armor_charges": player.armor_charges(),
                "armor_max": int(player.armor_relic.get("max_charges", 0)),
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
                        # FIX (stamina salti): barra sotto quella della vita, P2 (rosa/arancione/rosso).
                        "stamina": player2.get_stamina_ratio(),
                        "stamina_exhausted": player2.is_stamina_exhausted(),
                        # TASK 99 (LEVEL UP): livello e punti da spendere (P2).
                        "level": player2.level,
                        "skill_points": player2.skill_points,
                        # RELIC (Task 21): stato armatura reliquia in HUD (P2).
                        "armor_name": C.get_armor_short_name(player2.armor_relic),
                        "armor_color": player2.armor_relic.get("color", Color.WHITE),
                        "armor_charges": player2.armor_charges(),
                        "armor_max": int(player2.armor_relic.get("max_charges", 0)),
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


# TASK 79d (performance, richiesta utente "troppi oggetti su schermo che si
# muovono"): CAP sugli FX COSMETICI simultanei nella boss room. In fase 2 le
# scintille spawano di continuo (ogni proiettile bloccato dalle rovine,
# fendenti, frammenti) e OGNI FX e' un contenitore Node2D + GPUParticles2D
# con buffer particellari propri: su GPU/driver deboli la creazione/distruzione
# continua provoca micro-stutter. Oltre il cap il nuovo FX cosmetico viene
# semplicemente scartato (i danni e il gameplay NON passano di qui: sono
# applicati prima, questi sono solo effetti visivi). Sotto il cap: identico
# a prima. I PROIETTILI veri non passano da qui.
const MAX_CONCURRENT_FX: int = 10


func _add_capped_fx(fx: Node) -> void:
        if fx == null:
                return
        var alive: int = 0
        for ch in boss_projectiles_node.get_children():
                if ch.is_in_group("fx_effect") or ch is GPUParticles2D:
                        alive += 1
                        if alive >= MAX_CONCURRENT_FX:
                                break
        if alive >= MAX_CONCURRENT_FX:
                fx.queue_free()
                return
        boss_projectiles_node.add_child(fx)

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
        # TASK 79d: il caricamento non avviene piu' QUI (era dentro _draw al
        # PRIMO frame della stanza: decode JPG + upload GPU dentro la draw
        # callback = hitch percepibile all'ingresso). Ora e' precaricato in
        # _ready via start_boss_fight -> _load_boss_bg().
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
        # TASK 50: ARCHITETTURE BLOODBORNE — riabilitato il render delle
        # decorazioni DOPO l'overlay scuro (i props PixelLab 256x256 a
        # dimensioni per-tipo fino a 170px incorniciano l'arena e risaltano
        # sull'ambiente; posizioni viewport-relative, zona di gioco libera).
        _render_boss_room_decorations()
        # TASK 51 — FASE 2: BUCHE DEL BOSS (sotto player/boss/proiettili).
        #   * crepa (stato 0): cerchio frastagliato pulsante nel colore d'aura
        #     del boss — telegrafo "sta per aprirsi una voragine qui";
        #   * aperta (stato 1): voragine scura con bordo luminoso e fondo
        #     screziato, leggero battito di scala.
        for pit in boss_pits:
                var pp: Vector2 = pit["pos"]
                var ptint: Color = pit["tint"]
                if int(pit["state"]) == 0:
                        var pulse: float = 0.55 + 0.45 * sin(_boss_bg_time * 16.0)
                        draw_circle(pp, C.BOSS_PHASE2_PIT_RADIUS * 0.55,
                                        Color(ptint.r, ptint.g, ptint.b, 0.30 * pulse))
                        for k in range(6):
                                var a := float(k) * (TAU / 6.0) + 0.35
                                var rr := C.BOSS_PHASE2_PIT_RADIUS * (0.55 + 0.35 * pulse)
                                draw_line(pp + Vector2(cos(a), sin(a)) * 6.0,
                                                pp + Vector2(cos(a), sin(a)) * rr,
                                                Color(ptint.r, ptint.g, ptint.b, 0.55 * pulse), 2.0)
                else:
                        var breathe: float = 1.0 + 0.04 * sin(_boss_bg_time * 6.0)
                        var pr := C.BOSS_PHASE2_PIT_RADIUS * breathe
                        draw_circle(pp, pr, Color(0.02, 0.01, 0.04, 0.92))
                        draw_circle(pp, pr * 0.72, Color(0.0, 0.0, 0.0, 0.95))
                        draw_arc(pp, pr, 0.0, TAU, 26,
                                        Color(ptint.r, ptint.g, ptint.b, 0.55), 3.0, true)
                        for k in range(8):
                                var a2 := float(k) * (TAU / 8.0)
                                draw_circle(pp + Vector2(cos(a2), sin(a2)) * pr * 0.8,
                                                2.5, Color(ptint.r, ptint.g, ptint.b, 0.30))
        # TASK 51 — FASE 2: flash d'ingresso (bianco -> rosa in dissolvenza,
        # 700ms): lettura immediata del potenziamento.
        if _phase2_flash_ms > 0.0:
                var k: float = _phase2_flash_ms / 700.0
                var flash_col := Color(1.0, 1.0, 1.0, 0.55 * k) \
                                if k > 0.5 else Color(1.0, 0.45, 0.55, 0.55 * k)
                draw_rect(Rect2(0, C.UI_HEIGHT, vp_size.x, vp_size.y - C.UI_HEIGHT),
                                flash_col, true)
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
                        # TASK 51 — FASE 2: la barra HP del boss pulsa di rosso
                        # acceso quando e' entrato in fase 2 (segnale immediato
                        # del cambio di regime, insieme ad aura e dimensione).
                        var hp_col := Color(0.8, 0.15, 0.1)
                        if int(boss.get("phase")) == 2:
                                var pk: float = 0.5 + 0.5 * sin(_boss_bg_time * 10.0)
                                hp_col = Color(0.95, 0.10 + 0.25 * pk, 0.15 + 0.35 * pk)
                        draw_rect(Rect2(bar_x, bar_y, bar_w * hp_ratio, bar_h),
                                hp_col, true)
                        # TASK 41 — hint DEBOLEZZA ELEMENTALE RIMOSSO su richiesta
                        # utente: la debolezza non deve essere riportata in HUD.
                        # Il player la scopre per tentativi lanciando i barili
                        # (il moltiplicatore x2.5 resta nel calcolo danno).
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
                                # TASK 50: texture normalizzate al 75% del canvas
                                # -> draw 56px = contenuto ~42px, coerente col maze
                                draw_texture_rect(w_tex,
                                        Rect2(pos.x - 28, pos.y - 28, 56, 56), false)
                                continue
                # Fallback: Simple weapon icon (colored circle)
                var col: Color = Color.WHITE
                if w_entry.has("weapon") and w_entry["weapon"].has_method("get_color"):
                        col = w_entry["weapon"].get_color()
                draw_circle(pos, 16.0, Color(0.2, 0.2, 0.2, 0.8))
                draw_circle(pos, 12.0, col)

        # TASK 79d (performance — doppio draw dei proiettili RIMOSSO):
        # questo loop disegnava a mano OGNI proiettile OGNI frame (3 cerchi
        # ciascuno) DENTRO il _draw del controller, ma ogni Projectile e' gia'
        # un Node2D figlio di boss_projectiles_node con un suo _draw TEMATICO
        # (forme per BossProjKind, aura fase-2, scia homing): i proiettili
        # venivano disegnati DUE VOLTE (strato tematico + 3 cerchi glow sopra).
        # Ora li disegna SOLO il loro nodo: -3 draw_circle per proiettile per
        # frame dal GDScript del controller e niente look "doppio".
        # Verifica A/B: screenshot shot_boss79d prima/dopo (VLM) — proiettili
        # tematici ben visibili. Rollback: git revert di questo hunk.


# Disegna decorazioni ambiente: ARCHITETTURE BLOODBORNE (TASK 50).
# 10 props PixelLab 256x256 ispirati a Yharnam (colonne ricche, archi
# rotti, statue, candelieri, altare, obelischi, doccioni, inferriate,
# candelabri, sarcofaghi) disegnati a dimensioni per-tipo (fino a 170px:
# il Task 48 li relegava a 64px e il vecchio codice procedurale usava
# coordinate 1024 su viewport 1920 — per questo apparivano "semplici
# pilastri" mal distribuiti e il render era stato commentato).
# Posizioni FRAZIONI del viewport: identiche su ogni risoluzione, simmetriche,
# zona centrale di gioco libera. Solo layer visivo: niente collisioni.
var _decorations_spawned: bool = false
var _boss_room_decorations: Array = []  # [{type, pos, size}]

# TASK 50 — dimensione di rendering per tipo (px su schermo 1920x1080).
const DECOR_SIZES := {
        "column_ornate": 170.0,
        "arch": 150.0,
        "statue": 140.0,
        "chandelier": 120.0,
        "altar": 130.0,
        "obelisk": 150.0,
        "gargoyle": 110.0,
        "gate": 120.0,
        "candelabra": 100.0,
        "sarcophagus": 120.0,
}

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
                        "column_ornate": tex = EnvironmentArt.get_column_ornate_texture()
                        "arch": tex = EnvironmentArt.get_arch_texture()
                        "statue": tex = EnvironmentArt.get_statue_texture()
                        "chandelier": tex = EnvironmentArt.get_chandelier_texture()
                        "altar": tex = EnvironmentArt.get_altar_texture()
                        "obelisk": tex = EnvironmentArt.get_obelisk_texture()
                        "gargoyle": tex = EnvironmentArt.get_gargoyle_texture()
                        "gate": tex = EnvironmentArt.get_gate_texture()
                        "candelabra": tex = EnvironmentArt.get_candelabra_texture()
                        "sarcophagus": tex = EnvironmentArt.get_sarcophagus_texture()
                if tex:
                        var s: float = dec.size
                        draw_texture_rect(tex,
                                Rect2(dec.pos.x - s / 2, dec.pos.y - s / 2, s, s), false)


func _spawn_boss_room_decorations() -> void:
        _boss_room_decorations.clear()
        var vp: Vector2 = get_viewport_rect().size
        # Frazioni (fx, fy) del viewport -> identiche su ogni risoluzione.
        # TASK 51 (P10, richiesta utente): RIMOSSI archi (finestre gotiche
        # in alto) e inferriate (in basso) — segnalati come elementi da
        # togliere. Gli elementi restanti sono stati RIDISTRIBUITI:
        #   * i doccioni prendono il posto degli archi in alto (piu'
        #     esterni, incorniciano il nome del boss senza finestre);
        #   * gli obelischi scendono negli angoli bassi (dove c'erano le
        #     inferriate) chiudendo la composizione;
        #   * due candelabri riempiono la fascia bassa dove stavano gli
        #     obelischi, mantenendo la simmetria a speccio.
        # Zona centrale di gioco libera (x 0.31-0.69, y 0.28-0.83).
        var layout := [
                # --- lati: colonne cattedrali DOMINANTI (le piu' grandi) ---
                ["column_ornate", 0.050, 0.520],
                ["column_ornate", 0.950, 0.520],
                # --- fascia alta: candelieri appesi + doccioni esterni
                # che fiancheggiano il nome del boss + altare centrale ---
                ["chandelier", 0.292, 0.140],
                ["chandelier", 0.708, 0.140],
                ["gargoyle", 0.175, 0.195],
                ["gargoyle", 0.825, 0.195],
                ["altar", 0.500, 0.225],
                # --- cintura mediana: candelabri + statue in preghiera ---
                ["candelabra", 0.156, 0.575],
                ["candelabra", 0.844, 0.575],
                ["statue", 0.110, 0.805],
                ["statue", 0.890, 0.805],
                # --- fascia bassa: candelabri + obelischi d'angolo +
                # sarcofaghi centrali (niente piu' inferriate) ---
                ["candelabra", 0.290, 0.900],
                ["candelabra", 0.710, 0.900],
                ["obelisk", 0.068, 0.905],
                ["obelisk", 0.932, 0.905],
                ["sarcophagus", 0.406, 0.925],
                ["sarcophagus", 0.594, 0.925],
        ]
        for entry in layout:
                _boss_room_decorations.append({
                        "type": entry[0],
                        "pos": Vector2(float(entry[1]) * vp.x,
                                        float(entry[2]) * vp.y),
                        "size": DECOR_SIZES.get(entry[0], 100.0),
                })
