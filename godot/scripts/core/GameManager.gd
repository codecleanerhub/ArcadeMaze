## GameManager.gd - Autoload singleton that owns the global game state.
##
## Migrated from the C++ `Game` class (Game.h / Game.cpp). The C++ class was
## a monolith owning every subsystem (window, maze, players, enemies, boss,
## UI, audio). In Godot the scene tree replaces "ownership" of nodes - each
## scene owns its children. GameManager therefore keeps ONLY the
## bookkeeping that needs to be globally accessible:
##
##   * the current GameState and GameMode
##   * the current level number and number of players
##   * the per-player character selection
##   * the menu cursor, continues counter and pause state
##
## It exposes the same level-structure helpers as the C++ inline functions
## in Boss.h (is_boss_level / get_boss_index) so other scripts can ask
## "is this level a boss level?" without importing the constants file.
##
## Communication is via signals (state_changed, level_changed, ...) so UI
## and gameplay scenes can react without polling.
extends Node

# Import the shared constants file. `const C = ...` gives every consumer a
# short alias (C.MAZE_COLS, C.GameState.PLAYING, ...).
const C = preload("res://scripts/core/GameConstants.gd")

# ============================================================================
# SIGNALS
# ============================================================================
## Emitted whenever current_state changes. Payload is the new GameState int.
signal state_changed(new_state: int)
## Emitted when current_level changes (e.g. startLevel, boss fight, etc.).
signal level_changed(new_level: int)
## Emitted when the player count changes (1P <-> 2P from the menu).
signal num_players_changed(num_players: int)
## Emitted when the player's selected character changes (select-player screen).
signal character_changed(player_num: int, character_type: int)
## Emitted when the game mode changes (STORY <-> INFINITE).
signal game_mode_changed(mode: int)
## Emitted when the player loses the last life and the run ends.
signal run_ended
## Emitted when the player transitions from a maze level to a boss fight.
signal boss_fight_started(boss_index: int)
## Emitted when the player defeats a boss.
signal boss_defeated(boss_index: int)

# ============================================================================
# PUBLIC STATE  (read directly, mutate via the setters below so signals fire)
# ============================================================================
## Current top-level state. See GameState enum.
@export var current_state: int = C.GameState.MENU:
        set(v):
                if v != current_state:
                        current_state = v
                        state_changed.emit(v)

## The level we're playing right now. 1..STORY_LEVELS_COUNT in story mode,
## unbounded (>= 1) in infinite mode.
@export var current_level: int = 1:
        set(v):
                if v != current_level:
                        current_level = v
                        level_changed.emit(v)

## 1 or 2 players (selected from the main menu).
@export_range(1, 2) var num_players: int = 1:
        set(v):
                if v != num_players:
                        num_players = v
                        num_players_changed.emit(v)

## STORY or INFINITE.
@export var game_mode: int = C.GameMode.STORY:
        set(v):
                if v != game_mode:
                        game_mode = v
                        game_mode_changed.emit(v)

## Character chosen by P1 (one of CharacterType).
@export var player1_character: int = C.CharacterType.HERO_M:
        set(v):
                if v != player1_character:
                        player1_character = v
                        character_changed.emit(1, v)

## Character chosen by P2 (one of CharacterType).
@export var player2_character: int = C.CharacterType.HERO_F:
        set(v):
                if v != player2_character:
                        player2_character = v
                        character_changed.emit(2, v)

## Cursor position in the main menu (0..5 in the C++ game).
@export var menu_item_index: int = 0

## Step index of the joystick configuration screen (0 or 1 in C++).
@export var config_joy_step: int = 0

## Which player we are configuring in the joystick config screen (1 or 2).
@export var config_joy_player: int = 1

## FIX (config joystick dal menu OPTIONS): true se la schermata ConfigJoy
## e' stata aperta dal sottomenu OPTIONS (non dal flusso START GAME).
## A fine configurazione ConfigJoy deve riportare al MENU PRINCIPALE
## (sottomenu OPTIONS aperto, cursore su CONFIGURE JOYSTICK) invece di
## mandare il giocatore in SelectPlayer -> partita avviata di colpo.
@export var config_joy_from_options: bool = false

## FIX (ritorno al menu dopo ConfigJoy): MainMenu lo legge in _ready() e,
## se true, riapre il sottomenu OPTIONS col cursore su CONFIGURE JOYSTICK
## (indice 1), poi lo azzera. Scritto da ConfigJoy._on_config_finished
## prima di go_to_menu().
@export var menu_reopen_options: bool = false

## State we were in before pausing (so we can restore it on resume).
@export var paused_from_state: int = C.GameState.PLAYING

## Continues remaining (max 3 in the C++ game). When the player runs out
## the LOSE screen is shown.
## TASK 23: in 2P i crediti continue sono SEPARATI per player: `continues_left`
## resta il contatore di P1 (usato dal flusso 1P scene-based e dalla
## ContinuesScreen), `continues_left_p2` è il contatore di P2 (usato dal
## ContinuesOverlay 2P). Se P1 consuma un credito, quello di P2 NON scende
## e viceversa (richiesta utente).
@export_range(0, 3) var continues_left: int = 3

## TASK 23: crediti continue del GIOCATORE 2 (separati da quelli di P1).
## TASK 106: il valore iniziale di default qui non conta più — reset_run(),
## IntroCutscene e begin_newgameplus lo settano tutti a
## C.CONTINUE_CREDITS_PER_RUN (1 credito: la schermata CONTINUE appare
## UNA volta sola per player).
@export_range(0, 3) var continues_left_p2: int = 3

## TASK 23: a quale player è rivolta la schermata continue APERTA
## (1 o 2; 0 = nessuna). Usato dal ContinuesOverlay per il titolo e dal
## flusso 2P per sapere chi deve riprendere.
var continue_player_num: int = 0

# ============================================================================
# TASK 105 — NEW GAME PLUS
# ============================================================================
## Tier di difficoltà della run corrente: 0 = partita normale,
## 1 = NEW GAME PLUS (nemici danno x1.20 / HP x1.33),
## 2 = NEW GAME PLUS PLUS (danno x1.40 / HP x1.50) — CAP.
## Il setter tiene allineato il mirror statico C.newgameplus_tier letto da
## Enemy/MiniBoss/Boss/Player e dai damage-helper (pattern ui_language).
var newgameplus_tier: int = 0:
        set(v):
                newgameplus_tier = clampi(v, 0, C.NEWGAMEPLUS_MAX_TIER)
                C.newgameplus_tier = newgameplus_tier

## True dalla conferma (SÌ) della card NG+ finché il MainGameController
## non ha applicato il carry della progressione: serve perché il NG+
## riparte dal livello 1, dove il restore del carry è normalmente saltato
## ("current_level > 1" — una partita nuova deve partire pulita).
var newgameplus_carry_pending: bool = false

## TASK 105: true dalla VITTORIA FINALE (BossRoomController salva il carry
## e va a WinScreen) finché i credits non mostrano la card NG+ (che lo
## consuma). I credits aperti dal MENU NON propongono il NG+ (niente run
## appena conclusa alle spalle): questo flag è l'unico discriminante.
var newgameplus_offer_pending: bool = false

## TASK 105: true se conclusa la run si può proporre ancora un tier superiore
## (la card NG+ appare dopo i credits solo se true; a tier 2 non riappare).
func newgameplus_available() -> bool:
        return newgameplus_tier < C.NEWGAMEPLUS_MAX_TIER

# ============================================================================
# TASK 106 — SALVA PARTITA (slot per run)
# ============================================================================
## Slot assegnato alla run corrente (-1 = run non ancora salvata: il primo
## boss vinto le assegna il primo slot libero, o ne chiede uno da liberare
## se sono tutti occupati). La voce CONTINUA del menu riparte da qui.
var save_slot_current: int = -1

## True dall'AUTO-SAVE dopo un boss finché il MainGameController del livello
## successivo non ha mostrato l'annuncio "Partita salvata..." (2s, sfuma
## fino a sparire). Consumato in _ready, MAI al resume dal menu (il
## salvataggio è vecchio: niente annuncio).
var save_announce_pending: bool = false

## TASK 106 (SALVA PARTITA): riprende la run salvata nello slot `slot`
## (voce CONTINUA del menu principale). La run eredita livello di gioco,
## carry (punteggio/vite/level up/reliquie), personaggi, numero player,
## modalità e tier NG+; i crediti continue sono quelli di una run fresca.
## Il restore del carry avviene nel _ready del MainGameController
## (current_level > 1, ramo già esistente).
func begin_continue_from_slot(slot: int) -> void:
        if SaveSystem == null:
                go_to_menu()
                return
        var data: Dictionary = SaveSystem.load_slot(slot)
        if data.is_empty():
                push_warning("[GameManager] slot di salvataggio vuoto: %d" % slot)
                go_to_menu()
                return
        _apply_saved_run(slot, data)
        start_level_at(current_level)


## TASK 106: applica allo stato globale la run salvata (senza toccare le
## scene — separato da begin_continue_from_slot per essere testabile
## headless senza cambio scena).
func _apply_saved_run(slot: int, data: Dictionary) -> void:
        save_slot_current = slot
        num_players = clampi(int(data.get("num_players", 1)), 1, 2)
        game_mode = int(data.get("game_mode", C.GameMode.STORY))
        newgameplus_tier = int(data.get("newgameplus_tier", 0))
        current_level = clampi(int(data.get("current_level", 1)), 1,
                        C.STORY_LEVELS_COUNT)
        player1_character = int(data.get("char1", C.CharacterType.HERO_M))
        player2_character = int(data.get("char2", C.CharacterType.HERO_F))
        carry_p1 = (data.get("carry_p1", {}) as Dictionary).duplicate(true)
        carry_p2 = (data.get("carry_p2", {}) as Dictionary).duplicate(true)
        # Sessione pulita (il resume NON è un continue) e crediti freschi
        # (un solo credito, come ogni nuova ripresa).
        continues_left = C.CONTINUE_CREDITS_PER_RUN
        continues_left_p2 = C.CONTINUE_CREDITS_PER_RUN
        continue_player_num = 0
        died_in_boss = false
        continues_timer = 10
        continues_choice = true
        bonus_cards_seen.clear()
        session_snapshot.clear()
        session_restore_pending = false
        save_announce_pending = false
        hof_from_win = false

## TASK 105: progressione Level Up da CONSERVARE nel NG+ (il resto è una
## run nuova: score/vite/reliquie/armi ripartono da zero — "Ricomincerai
## dal primo livello di gioco senza perdere i tuoi upgrade accumulati").
static func _ngp_kept_progression(snap: Dictionary) -> Dictionary:
        var skills: Dictionary = snap.get("skill_levels", {})
        return {
                        "score": 0,
                        "lives": 3,
                        "next_life_threshold": C.EXTRA_LIFE_EVERY_POINTS,
                        "level": int(snap.get("level", 1)),
                        "skill_points": int(snap.get("skill_points", 0)),
                        "pending_levelup_fx": int(snap.get("pending_levelup_fx", 0)),
                        "skill_levels": (skills as Dictionary).duplicate(),
        }

## TASK 105 — inizia la run NEW GAME PLUS (SÌ sulla card post-credits):
## tier +1 (cap 2), livello 1, crediti continue freschi, sessione/carry
## ripuliti e sostituiti con la SOLA progressione Level Up conservata
## (carry_p1/p2 erano stati salvati dal BossRoomController alla vittoria
## finale, PRIMA di WinScreen/HOF/credits). start_level(1) -> go_to_maze.
func begin_newgameplus() -> void:
        var kept_p1: Dictionary = _ngp_kept_progression(carry_p1)
        var kept_p2: Dictionary = _ngp_kept_progression(carry_p2)
        newgameplus_tier += 1
        newgameplus_carry_pending = true
        newgameplus_offer_pending = false
        current_level = 1
        # TASK 106: NG+ = RUN NUOVA (nuovo slot di salvataggio) e crediti
        # continue da costante (1 credito).
        save_slot_current = -1
        save_announce_pending = false
        continues_left = C.CONTINUE_CREDITS_PER_RUN
        continues_left_p2 = C.CONTINUE_CREDITS_PER_RUN
        continue_player_num = 0
        died_in_boss = false
        continues_timer = 10
        continues_choice = true
        # TASK 51 — CARD BONUS: nuova run = le card informative dei bonus
        # tornano a comparire alla prima raccolta (memoria per-run).
        bonus_cards_seen.clear()
        # FIX (continue = sessione ESATTA): nuova run = nessun restore.
        session_snapshot.clear()
        session_restore_pending = false
        # Il carry diventa la SOLA progressione conservata; il restore avviene
        # nel _ready del MainGameController DOPO start_level(1) (reset()).
        carry_p1 = kept_p1
        carry_p2 = kept_p2
        # I finali della run appena conclusa restano per la HOF già salvata.
        start_level(1)


## TASK 23: true quando la Hall of Fame è raggiunta dal flusso di VITTORIA
## (WinScreen -> tastiera -> HOF): a fine visualizzazione si prosegue verso
## i CREDITS e poi il menu (sequenza richiesta dall'utente: congratulazioni
## -> salvataggio score -> credits -> menu). Dal menu, invece, la HOF torna
## al menu come prima.
var hof_from_win: bool = false

## Countdown timer on the continues screen (10..0 seconds).
@export var continues_timer: int = 10

## Whether the player chose YES (true) or NO (false) on the continues screen.
@export var continues_choice: bool = true

## True if the player died during a boss fight (used by the C++ game to
## decide whether to keep the boss state on continue).
@export var died_in_boss: bool = false

# ============================================================================
# FIX (continue = sessione ESATTA): quando il player usa un credito continue,
# la partita deve riprendere ESATTAMENTE da dov'era morto — stesso livello,
# stesso layout del labirinto, stessi tesori residui, stessi nemici (numero,
# tipo, posizione e HP), stessi item a terra, stesso punteggio; uguale nella
# schermata del boss (HP del boss conservati). I controller di gioco
# (MainGameController / BossRoomController) scrivono qui lo snapshot allo
# momento della morte e lo consumano in _ready() se `session_restore_pending`
# è true. Lo snapshot viene SEMPRE sovrascritto alla morte successiva e
# ripulito quando si avanza di livello / si inizia una partita nuova.
var session_snapshot: Dictionary = {}
## True tra la conferma del continue e il _ready() della scena di gioco che
## deve ripristinare lo snapshot (il controller lo azzera dopo il restore).
var session_restore_pending: bool = false

## Music toggle (set from the main menu). Default OFF (user can enable in Options).
@export var music_enabled: bool = false

## True if the player picked up the test-mode shortcut (skip current level).
@export var test_mode_enabled: bool = false

# ============================================================================
# FIX (Hall of Fame): punteggio e livello raggiunti a fine partita. Vengono
# impostati dai controller di gioco subito prima della transizione verso
# LOSE/WIN e letti dalla schermata di inserimento nome (NameEntryKeyboard).
# ============================================================================
var final_score: int = 0
var final_level: int = 1
# FIX (Hall of Fame 2P): punteggi finali SINGOLI dei due player. In 2P ogni
# giocatore può salvare il PROPRIO punteggio in classifica (prima si salvava
# solo la somma con un solo nome); final_score resta la somma per la
# schermata di game over.
var final_score_p1: int = 0
var final_score_p2: int = 0
# FIX (Hall of Fame): indice della voce appena salvata da evidenziare nella
# schermata Hall of Fame (-1 = nessuna evidenziazione).
var hof_highlight_index: int = -1
# FIX (standby alternato): true quando la Hall of Fame è stata aperta dal
# timer di inattività del menu (in alternanza con la demo mode): in quel
# caso ritorna al menu dopo 20s senza input.
var hof_from_standby: bool = false
# FIX (alternanza standby demo/Hall of Fame): contatore delle attivazioni
# da inattività nel menu. Ogni 30s di standby il gioco mostra IN ALTERNANZA
# la demo mode (attivazioni dispari: 1ª, 3ª, ...) e la Hall of Fame
# (attivazioni pari: 2ª, 4ª, ...), come richiesto.
var standby_show_count: int = 0


# ============================================================================
# FIX (punteggio perso tra le scene — root cause del record HOF mancante):
# nel C++ originale ESISTE UN SOLO oggetto Player per tutta la partita, quindi
# punteggio/vite/soglia-vita-extra sopravvivono NATURALMENTE al passaggio
# labirinto -> boss room -> labirinto. Nel port Godot OGNI scena (MainGame /
# BossRoom) istanzia un nodo Player PROPRIO che riparte da reset() (score=0,
# 3 vite): a ogni cambio scena il punteggio accumulato si AZZERAVA. Saltando
# i livelli in test mode (maze -> boss -> maze ...) il punteggio finale alla
# morte era ~0 e non entrava mai in Hall of Fame, e la vita bonus (+1) del
# boss sconfitto andava persa al ritorno nel labirinto.
# I controller salvano qui lo stato dei player PRIMA di cambiare scena e lo
# ripristinano nel _ready() della scena di arrivo (SOLO se non e' un restore
# da CONTINUE — quello usa session_snapshot — e non una partita nuova).
# ============================================================================
var carry_p1: Dictionary = {}
var carry_p2: Dictionary = {}

# TASK 51 — CARD BONUS (richiesta utente): memoria per-RUN dei bonus di cui
# e' stata gia' mostrata la card informativa. La card appare SOLO la prima
# volta che il bonus viene raccolto nella partita; se al livello dopo il
# player riprende lo stesso bonus, la card NON riappare.
var bonus_cards_seen: Dictionary = {}


## true se la card di questo tipo di bonus e' gia' stata mostrata in run.
func has_seen_bonus_card(kind_key: String) -> bool:
        return bonus_cards_seen.has(kind_key)


## Segna la card del bonus come vista (prima mostra effettuata).
func mark_bonus_card_seen(kind_key: String) -> void:
        bonus_cards_seen[kind_key] = true


## TASK 51: segna TUTTE le card bonus come gia' viste. Usato dai TEST
## automatici (che simulano pickup) per non interrompersi sulla pausa
## della card — equivalente a un player che ha gia' visto tutte le card.
func mark_all_bonus_cards_seen() -> void:
        for k in range(21):  # Kind enum: 0..20 (MINE..FREEZE_SCROLL)
                bonus_cards_seen["kind_%d" % k] = true

## Snapshot dello stato di UN player da portare nella prossima scena.
## RELIC (Task 21): include ANCHE l'arma reliquia e l'armatura — nel C++
## originale l'oggetto Player era UNICO e sopravviveva a tutte le scene;
## qui le reliquie devono attraversare labirinto -> boss room -> labirinto
## esattamente come punteggio e vite (si perdono solo alla morte/rottura).
static func make_player_carry(p: Node) -> Dictionary:
        if p == null or not is_instance_valid(p):
                return {}
        var snap: Dictionary = {
                "score": int(p.score),
                "lives": int(p.lives),
                "next_life_threshold": int(p.next_life_threshold),
                "permanent_speed_boost": bool(p.permanent_speed_boost),
                # TASK 99 (LEVEL UP): la progressione attraversa le scene
                # come punteggio e vite (maze -> boss room -> maze).
                "level": int(p.get("level")),
                "skill_points": int(p.get("skill_points")),
                "pending_levelup_fx": int(p.get("pending_levelup_fx")),
                "skill_levels": (p.get("skill_levels") as Dictionary).duplicate(),
                # TASK 107 (CUORI): l'ENERGIA del cuore corrente attraversa le
                # scene (niente piu' refill gratuito a ogni cambio scena).
                # TASK 108 (VOODOO): mentre e' posseduto, l'energia del nodo e'
                # quella del NEMICO: si trasporta quella REALE salvata; la
                # bambola (pagata a punti) attraversa le scene come le armi.
                "energy": int(p.get_real_energy()) if p.has_method("get_real_energy") else int(p.get("energy")),
                "voodoo_equipped": bool(p.get("voodoo_equipped")),
        }
        # Arma reliquia (le armi base NON si portano: comportamento storico
        # invariato — la boss room dà già la sua arma potenziata d'ingresso).
        var w: Dictionary = p.current_weapon
        # NOTA GDScript: la chiave "relic" contiene una STRINGA (l'id) —
        # niente cast bool() (bool(String) non esiste come costruttore).
        if w is Dictionary and w.has("relic"):
                snap["relic_weapon"] = w.duplicate()
        # Armatura reliquia (con le cariche correnti).
        if p.has_method("has_relic_armor") and p.has_relic_armor():
                snap["relic_armor"] = p.armor_relic.duplicate()
        return snap

## Salva lo stato dei player di entrambe le scene di gioco (chiamato dai
## controller subito PRIMA di GameManager.start_boss_fight() /
## go_to_maze(), cioe' prima del cambio scena).
func save_player_carry(p1: Node, p2: Node = null) -> void:
        carry_p1 = make_player_carry(p1)
        var two_players: bool = num_players == 2 and p2 != null \
                        and is_instance_valid(p2) and p2.visible
        carry_p2 = make_player_carry(p2) if two_players else {}

## Ripristina lo stato portato sui player della scena APPENA caricata.
## Ritorna true se e' stato applicato un carry valido.
func restore_player_carry(p1: Node, p2: Node = null) -> bool:
        if carry_p1.is_empty() or p1 == null or not is_instance_valid(p1):
                return false
        _apply_carry(p1, carry_p1)
        if num_players == 2 and p2 != null and is_instance_valid(p2) \
                        and p2.visible and not carry_p2.is_empty():
                _apply_carry(p2, carry_p2)
        return true

func _apply_carry(p: Node, snap: Dictionary) -> void:
        p.score = int(snap.get("score", 0))
        p.lives = int(snap.get("lives", 3))
        p.next_life_threshold = int(snap.get("next_life_threshold", 100000))
        p.permanent_speed_boost = bool(snap.get("permanent_speed_boost", false))
        # TASK 99 (LEVEL UP): ripristina la progressione nella scena appena
        # caricata (il player e' gia' passato da reset() = livello 1 pulito;
        # anche un level up maturato ma NON ancora annunciato sopravvive:
        # la celebrazione parte appena il controller riparte).
        p.level = int(snap.get("level", 1))
        p.skill_points = int(snap.get("skill_points", 0))
        p.pending_levelup_fx = int(snap.get("pending_levelup_fx", 0))
        var skills_snap: Dictionary = snap.get("skill_levels", {})
        if not skills_snap.is_empty() and p.has_method("restore_skills"):
                p.restore_skills(skills_snap)
        # RELIC (Task 21): ripristina arma reliquia e armatura nella scena
        # appena caricata (il player e' gia' passato da reset() = pulito).
        var rw: Dictionary = snap.get("relic_weapon", {})
        if not rw.is_empty() and p.has_method("collect_weapon"):
                p.current_weapon = rw.duplicate()
        var ra: Dictionary = snap.get("relic_armor", {})
        if not ra.is_empty() and p.has_method("restore_relic_armor"):
                p.restore_relic_armor(ra)
        # TASK 107/108 (CUORI/VOODOO): per ULTIMO, dopo abilita'/armatura (che
        # ricalcolano max_energy): la bambola in tasca e l'ENERGIA trasportata,
        # clampata al massimo corrente. Chiave assente (salvataggi vecchi,
        # NG+, run nuova) = il player resta com'e' (energia piena dal reset).
        # NB: "prop in obj" (non obj.has()) perche' i Node non hanno .has().
        if "voodoo_equipped" in p:
                p.set("voodoo_equipped", bool(snap.get("voodoo_equipped", false)))
        if snap.has("energy") and "energy" in p:
                var carried_energy: int = int(snap.get("energy", 5))
                if "max_energy" in p:
                        carried_energy = clampi(carried_energy, 0, int(p.get("max_energy")))
                p.set("energy", carried_energy)


# ============================================================================
# LEVEL HELPERS  (mirror the inline functions in Boss.h)
# ============================================================================
## True if `level` (1-based) is a boss level (multiples of 4: 4, 8, ..., 68).
func is_boss_level(level: int = current_level) -> bool:
        return C.is_boss_level(level)


## Returns the boss index (0..16) for the given level.
func get_boss_index(level: int = current_level) -> int:
        return C.get_boss_index(level)


## Returns the mini-boss index (0..50) for the given level. Boss levels do
## not spawn mini-bosses but the index is still well-defined.
func get_miniboss_index(level: int = current_level) -> int:
        return C.get_miniboss_index(level)


## True if we have completed every story-mode level (current_level > 68).
func is_story_complete() -> bool:
        return current_level > C.STORY_LEVELS_COUNT


# ============================================================================
# STATE TRANSITIONS  (named after the C++ methods that performed them)
# ============================================================================
## Begin a new maze level. Mirrors Game::startLevel(lvl). Emits level_changed
## and switches the state to PLAYING.
func start_level(lvl: int) -> void:
        current_level = lvl
        current_state = C.GameState.PLAYING
        # Transition to the main game scene (maze level).
        go_to_maze()


## Begin the boss fight for the current level. Mirrors Game::startBossFight().
## `keep_boss_state` matches the C++ argument of the same name and is used
## when continuing after death in the boss room.
func start_boss_fight(keep_boss_state: bool = false) -> void:
        var boss_idx: int = get_boss_index()
        if not keep_boss_state:
                boss_fight_started.emit(boss_idx)
        current_state = C.GameState.BOSS
        # Transition to the boss room scene.
        go_to_boss()


## Advance to the next level after the current one is cleared. If we are in
## story mode and just finished level 68, switch to WIN_STORY.
## FIX (continue = sessione ESATTA): avanzare di livello invalida lo snapshot
## della sessione precedente (il restore vale SOLO per il continue).
func advance_level() -> void:
        session_snapshot.clear()
        session_restore_pending = false
        if game_mode == C.GameMode.STORY and current_level >= C.STORY_LEVELS_COUNT:
                current_state = C.GameState.WIN_STORY
                run_ended.emit()
                go_to_win()
                return
        if game_mode == C.GameMode.STORY and is_boss_level():
                # Defeated a boss - reward the player with an extra life (in C++
                # this is `player.addLife()` which is the Player node's job).
                boss_defeated.emit(get_boss_index())
        current_level += 1
        start_level(current_level)


## Toggle pause. Mirrors the C++ behavior: P toggles between PLAYING/BOSS
## and PAUSE, storing the previous state in paused_from_state.
func toggle_pause() -> void:
        if current_state == C.GameState.PAUSE:
                current_state = paused_from_state
        elif current_state == C.GameState.PLAYING or current_state == C.GameState.BOSS:
                paused_from_state = current_state
                current_state = C.GameState.PAUSE


## Lose a life. If we still have continues we go to CONTINUES, otherwise LOSE.
## `in_boss` is the C++ `diedInBoss` flag - true if the death happened during
## a boss fight (so we keep the boss state on continue).
func player_died(in_boss: bool = false) -> void:
        died_in_boss = in_boss
        if continues_left > 0:
                current_state = C.GameState.CONTINUES
                go_to_continues()
        else:
                current_state = C.GameState.LOSE
                run_ended.emit()
                go_to_lose()


## TASK 23: crediti continue del player `player_num` (1 o 2). In 1P è il
## contatore classico; in 2P i due contatori sono indipendenti.
func continues_for(player_num: int) -> int:
        return continues_left_p2 if player_num == 2 else continues_left

## TASK 23: consuma UN credito continue del player `player_num`
## (se P1 ne consuma uno, il contatore di P2 resta intatto e viceversa).
func use_continue_for(player_num: int) -> void:
        if player_num == 2:
                continues_left_p2 = max(0, continues_left_p2 - 1)
        else:
                continues_left = max(0, continues_left - 1)

## Called by the continues screen when the player picks YES: consume a
## continue credit and resume the game (boss fight if died there, else
## restart the current level).
## FIX (continue = sessione ESATTA): marca il restore pendente così il
## controller che ricrea la scena ripristina lo snapshot della sessione
## (maze/tesori/nemici/item/punteggi — o gli HP del boss) invece di
## rigenerare un livello nuovo di zecca.
func use_continue() -> void:
        continues_left = max(0, continues_left - 1)
        session_restore_pending = true
        if died_in_boss:
                start_boss_fight(true)
        else:
                start_level(current_level)


## Called by the continues screen when the player picks NO: go to LOSE.
func give_up() -> void:
        current_state = C.GameState.LOSE
        run_ended.emit()
        go_to_lose()


## Reset all transient state so a new run can start from a clean slate.
## Mirrors Game::cleanupGameEntities() for the state-only portion.
func reset_run() -> void:
        current_level = 1
        # TASK 106: crediti continue da costante (1 credito per player:
        # la schermata CONTINUE appare UNA volta sola).
        continues_left = C.CONTINUE_CREDITS_PER_RUN
        continues_left_p2 = C.CONTINUE_CREDITS_PER_RUN
        continue_player_num = 0
        hof_from_win = false
        continues_timer = 10
        continues_choice = true
        died_in_boss = false
        # TASK 106 — SALVA PARTITA: nuova sessione = run non ancora salvata.
        save_slot_current = -1
        save_announce_pending = false
        # TASK 105 — NEW GAME PLUS: nuova sessione = partita base.
        newgameplus_tier = 0
        newgameplus_carry_pending = false
        newgameplus_offer_pending = false
        # TASK 51 — CARD BONUS: nuova partita = le card informative dei bonus
        # tornano a comparire alla prima raccolta (memoria per-run).
        bonus_cards_seen.clear()
        # FIX (continue = sessione ESATTA): nuova partita = nessun restore.
        session_snapshot.clear()
        session_restore_pending = false
        # FIX (punteggio perso tra le scene): nuova partita = nessun carry.
        carry_p1.clear()
        carry_p2.clear()
        menu_item_index = 0
        config_joy_step = 0
        config_joy_player = 1
        config_joy_from_options = false
        menu_reopen_options = false
        test_mode_enabled = false
        final_score = 0
        final_score_p1 = 0
        final_score_p2 = 0
        final_level = 1
        standby_show_count = 0
        current_state = C.GameState.MENU


# ============================================================================
# LIFE-CYCLE
# ============================================================================
func _ready() -> void:
        # Enforce a deterministic initial state on autoload.
        reset_run()
        # When the game starts on a fresh load we want to be in MENU (already
        # set by reset_run), and the player count is whatever the C++ default was.
        player1_character = C.CharacterType.HERO_M
        player2_character = C.CharacterType.HERO_F


# FIX (tasto M per musica): toggle on/off globale, funziona in tutte le scene
# (menu, gameplay, pause, ecc.) perché GameManager è un autoload sempre attivo.
func _unhandled_input(event: InputEvent) -> void:
        if event is InputEventKey and event.pressed and not event.is_echo():
                if event.keycode == KEY_M:
                        if AudioManager:
                                var new_state: bool = not AudioManager.music_enabled
                                # FIX (flag desincronizzato): aggiorna ANCHE
                                # GameManager.music_enabled, così il menu e i
                                # controller leggono lo stesso stato reale
                                # dell'audio (prima il flag restava stale).
                                music_enabled = new_state
                                AudioManager.set_music_enabled(new_state)
                                if new_state:
                                        # Riavvia la musica appropriata in base allo stato
                                        match current_state:
                                                C.GameState.MENU:
                                                        AudioManager.play_menu_music()
                                                C.GameState.PLAYING:
                                                        AudioManager.play_level_music(current_level, _is_current_level_boss())
                                                _:
                                                        pass
                                        print("[GameManager] Musica RIATTIVATA (M)")
                                else:
                                        print("[GameManager] Musica DISATTIVATA (M)")
                        get_viewport().set_input_as_handled()


# Helper: verifica se il livello corrente è un boss level (per scegliere
# la musica corretta quando si riattiva con M).
func _is_current_level_boss() -> bool:
        return C.is_boss_level(current_level)


# ============================================================================
# DEBUG HELPERS
# ============================================================================
## Returns a readable name for a GameState. Handy for debug prints and UI.
func state_name(state: int = current_state) -> String:
        match state:
                C.GameState.MENU:
                        return "MENU"
                C.GameState.SELECT_PLAYER:
                        return "SELECT_PLAYER"
                C.GameState.CONFIG_JOY:
                        return "CONFIG_JOY"
                C.GameState.CONFIG_JOY_2:
                        return "CONFIG_JOY_2"
                C.GameState.INTRO:
                        return "INTRO"
                C.GameState.PLAYING:
                        return "PLAYING"
                C.GameState.BOSS:
                        return "BOSS"
                C.GameState.PAUSE:
                        return "PAUSE"
                C.GameState.CONTINUES:
                        return "CONTINUES"
                C.GameState.LOSE:
                        return "LOSE"
                C.GameState.WIN_STORY:
                        return "WIN_STORY"
                C.GameState.WIN_INFINITE:
                        return "WIN_INFINITE"
                C.GameState.CREDITS:
                        return "CREDITS"
                C.GameState.DEMO:
                        return "DEMO"
                _:
                        return "UNKNOWN(%d)" % state


# ============================================================================
# SCENE TRANSITIONS
# ============================================================================

func change_scene(scene_path: String) -> void:
        # TASK 44: overlay "Loading..." (sangue gocciolante, stile Hurry Up)
        # al posto dello schermo nero. L'autoload resta sopra la scena nuova
        # finché non sono passati 3 frame renderizzati: se il _ready della
        # scena è pesante (es. generazione labirinto) i frame non avanzano e
        # la scritta copre TUTTA l'elaborazione.
        if LoadingScreen:
                LoadingScreen.show_loading()
        var err := get_tree().change_scene_to_file(scene_path)
        if err != OK:
                push_error("Errore caricamento scena: " + scene_path)
                if LoadingScreen:
                        LoadingScreen.hide_loading()

func go_to_menu() -> void:
        # TASK 105 — NEW GAME PLUS: tornare al menu CHIUDE la run corrente:
        # il tier NG+ si azzera (la prossima run dal menu è una partita base;
        # l'unico accesso al NG+ è la SÌ sulla card post-credits, che non
        # passa mai dal menu). Evita anche che la demo mode erediti i
        # moltiplicatori di una run NG+ abbandonata.
        newgameplus_tier = 0
        newgameplus_carry_pending = false
        newgameplus_offer_pending = false
        current_state = C.GameState.MENU
        change_scene("res://scenes/MainMenu.tscn")

func go_to_select_player() -> void:
        current_state = C.GameState.SELECT_PLAYER
        change_scene("res://scenes/SelectPlayer.tscn")

func go_to_config_joy() -> void:
        current_state = C.GameState.CONFIG_JOY
        change_scene("res://scenes/ConfigJoy.tscn")

func go_to_intro() -> void:
        current_state = C.GameState.INTRO
        change_scene("res://scenes/IntroCutscene.tscn")

func go_to_maze() -> void:
        current_state = C.GameState.PLAYING
        change_scene("res://scenes/MainGame.tscn")

func go_to_boss() -> void:
        current_state = C.GameState.BOSS
        change_scene("res://scenes/BossRoom.tscn")

func go_to_credits() -> void:
        current_state = C.GameState.CREDITS
        change_scene("res://scenes/CreditsScreen.tscn")

func go_to_continues() -> void:
        current_state = C.GameState.CONTINUES
        change_scene("res://scenes/ContinuesScreen.tscn")

func go_to_win() -> void:
        current_state = C.GameState.WIN_STORY
        change_scene("res://scenes/WinScreen.tscn")

func go_to_lose() -> void:
        current_state = C.GameState.LOSE
        change_scene("res://scenes/LoseScreen.tscn")

# FIX (Hall of Fame): transizione alla schermata Hall of Fame (dal menu e
# dallo standby in alternanza con la demo mode).
func go_to_hall_of_fame() -> void:
        current_state = C.GameState.MENU
        change_scene("res://scenes/HallOfFame.tscn")

func start_level_at(level: int) -> void:
        current_level = level
        if is_boss_level(level):
                go_to_boss()
        else:
                go_to_maze()

func next_level() -> void:
        # FIX (continue = sessione ESATTA): avanzare di livello invalida lo
        # snapshot della sessione precedente.
        session_snapshot.clear()
        session_restore_pending = false
        current_level += 1
        if current_level > C.STORY_LEVELS_COUNT:
                # Vittoria: mostra credits
                go_to_credits()
        else:
                start_level_at(current_level)
