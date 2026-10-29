# ===========================================================================
# Player.gd - Player character for Arcade Maze Fantasy (Godot port).
#
# Port of src/Player.h and src/Player.cpp (SFML/C++ -> GDScript).
#
# Movement: "grid-aligned" in the maze (snap-to-cell-centre before turning),
# but free pixel movement in the boss room (freeMovement=true).
#
# Lifecycle: lives (3) -> each life has maxEnergy (5) energy points.
# When energy reaches 0 a life is lost and the player respawns. The player is
# invulnerable for ~1 s after taking damage (damageTimer), or fully invincible
# while the chalice effect is active (invincibleTimer).
# TASK 38: alla NASCITA e alla RINASCITA dopo una morte il player LAMPEGGIA
# per 3 secondi (spawn_guard_ms) e in quel periodo e' IMMORTALE, per dare il
# tempo di allontanarsi dai nemici.
#
# Timers are stored in "simulated ms" (decremented by 16 per frame @ 60 FPS),
# exactly mirroring the C++ implementation so balance stays identical.
#
# Weapon system: pistol/shotgun/rocket/laser. Each shot consumes 1 ammo;
# with 0 ammo the player cannot shoot until they pick up a new weapon.
# ===========================================================================
class_name Player
extends CharacterBody2D

const C = preload("res://scripts/core/GameConstants.gd")

# --- Engine config ----------------------------------------------------------
# Run in physics step so timers/snap-to-grid stay deterministic at 60 FPS.
# Game node is expected to call `update_player()` from its own _physics_process;
# we don't tick ourselves here so the Game can pause us, slow-mo, etc.

# --- Grid constants (mirror Utils.h) ---------------------------------------
const WINDOW_WIDTH: int = 1920
const WINDOW_HEIGHT: int = 1080
const TILE_SIZE: int = 64
const MAZE_COLS: int = 30  # FIX (muro destro invisibile): 31 -> 30, allineato a GameConstants
const MAZE_ROWS: int = 15  # FIX (costanti stale): era 19 (layout vecchio), allineato a GameConstants
const UI_HEIGHT: int = 80

# Cell-type values matching GameConstants.CellType enum (so this script works
# whether the caller passes our own Maze or the central GameConstants one):
#   EMPTY = 0, WALL = 1, TREASURE = 2, WEAPON = 3.
const CELL_EMPTY: int = 0
const CELL_WALL: int = 1
const CELL_TREASURE: int = 2
const CELL_WEAPON: int = 3

# --- Weapon types (mirror Weapon.h) -----------------------------------------
enum WeaponType { PISTOL, SHOTGUN, ROCKET, LASER, SIEGE }

# --- Playable characters (mirror Player.h CharacterType) --------------------
# 9 entries in C++ enum (HERO_M..VAMPIRE), though the C++ comment says 8 -
# the comment is a stale bug; we keep all 9.
enum CharacterType { HERO_M, HERO_F, MAGE, ORC, ELF, KNIGHT, GOLEM, DRAGON, VAMPIRE }

# Sprite base path per character (assets/sprites/<base>_sheet.png —
# l'unico sheet caricato: main 4-frame per idle/walk/jump/attack,
# come il C++ originale).
const CHARACTER_SPRITE_BASE := {
        CharacterType.HERO_M:   "res://assets/sprites/player1",
        CharacterType.HERO_F:   "res://assets/sprites/player2",
        CharacterType.MAGE:     "res://assets/sprites/char_mage",
        CharacterType.ORC:      "res://assets/sprites/char_orc",
        CharacterType.ELF:      "res://assets/sprites/char_elf",
        CharacterType.KNIGHT:   "res://assets/sprites/char_knight",
        CharacterType.GOLEM:    "res://assets/sprites/char_golem",
        CharacterType.DRAGON:   "res://assets/sprites/char_dragon",
        CharacterType.VAMPIRE:  "res://assets/sprites/char_vampire",
}

# Descriptive name shown in UI menus.
const CHARACTER_NAME := {
        CharacterType.HERO_M:   "HERO",
        CharacterType.HERO_F:   "HEROINE",
        CharacterType.MAGE:     "MAGE",
        CharacterType.ORC:      "ORC",
        CharacterType.ELF:      "ELF",
        CharacterType.KNIGHT:   "KNIGHT",
        CharacterType.GOLEM:    "GOLEM",
        CharacterType.DRAGON:   "DRAGON",
        CharacterType.VAMPIRE:   "VAMPIRE",
}

# Whether the sprite PNG default-facing is RIGHT (true) or LEFT (false).
# Drives flip logic: default-RIGHT -> flipped when lastDx < 0.
# Verified per-character via VLM/user-feedback in the original game.
# TASK 67 (feedback utente "heroine/knight/elf/golem si girano dal lato
# opposto al movimento"): gli sheet PixelLab v2 di QUESTI 4 personaggi
# guardano nativamente a SINISTRA (come orc/dragon/vampire: la generazione
# v2 non normalizza il facing, 7/9 sheet escono rivolti a sinistra).
# Con flag=true il verso era invertito in ENTRAMBE le direzioni; flag=false
# = arte nativa a sinistra. Verificato: walk0-3/jump sono estrazioni IDENTICHE
# dei frame del main sheet e XHD = upscale 4x esatto del SD -> un solo flag
# per personaggio copre tutte le pose.
const SPRITE_DEFAULT_FACES_RIGHT := {
        # TASK 82 (eroe si girava al contrario): verificato con VLM sul PNG
        # attuale player1_sheet.png (v2, 256x64): il personaggio guarda
        # NATIVAMENTE a SINISTRA come gli altri 7/9 sheet v2. Il vecchio flag
        # true (retaggio dello sheet v1) invertiva il facing in entrambe le
        # direzioni. Con false: muove a destra -> flip_h=true -> guarda bene.
        CharacterType.HERO_M:   false,  # TASK 82: sheet v2 guarda a sinistra (VLM)
        CharacterType.HERO_F:   false,  # FIX task67: sheet v2 guarda a sinistra -> era true
        CharacterType.MAGE:     true,
        CharacterType.ORC:      false,
        CharacterType.ELF:      false,  # FIX task67: sheet v2 guarda a sinistra -> era true
        CharacterType.KNIGHT:   false,  # FIX task67: sheet v2 guarda a sinistra -> era true
        CharacterType.GOLEM:    false,  # FIX task67: sheet v2 guarda a sinistra -> era true
        CharacterType.DRAGON:   false,  # FIX: dragon si girava al contrario
        CharacterType.VAMPIRE: false,  # FIX: sprite faces left
}

# --- Tunable stats ----------------------------------------------------------
@export var lives: int = 3
@export var max_energy: int = 5
@export var energy: int = 5
@export var score: int = 0
@export var speed: int = 2  # base speed (px/frame @ 60 FPS)

# --- Public state -----------------------------------------------------------
# Direction:
#   dx,dy          = current movement direction (applied this frame)
#   nextDx,nextDy  = direction requested by input (applied at next cell centre)
#   lastDx,lastDy  = last non-zero direction (orients sprite/weapon when idle)
var dx: int = 0
var dy: int = 0
var next_dx: int = 0
var next_dy: int = 0
var last_dx: int = 1
var last_dy: int = 0

# Weapon / projectiles
# TASK 26: munizioni iniziali +30% (15 -> 20, vedi GameConstants.make_weapon).
var current_weapon: Dictionary = {
        "type": WeaponType.PISTOL,
        "power": 1,
        "ammo": 20,
}
# Each projectile is a Dictionary {pos: Vector2, dir: Vector2, power: int,
# active: bool, type: WeaponType}. Erase-remove is done in update_player().
var projectiles: Array[Dictionary] = []

# Flag: true if the player picked up a weapon THIS frame.
# Game::update consumes it via consume_picked_weapon() to play the load SFX.
var picked_weapon_this_frame: bool = false

# ===========================================================================
# TASK 30 (hazard ambientali): stato del player verso i pericoli del
# labirinto. I flag di TENUTA (ganasce/muri di roccia) bloccano il
# movimento ma lasciano tickare i timer; hazard_slow e' il fattore di
# velocita' impostato dal MazeHazards ogni frame (sabbie mobili = 0.5,
# annullato dagli stivali); input_mash_count conta le pressioni di
# salto/sparo (anche a vuoto) mentre e' trattenuto: il MazeHazards lo
# consuma per accorciare la tenuta delle ganasce.
# ===========================================================================
var held_by_trap: bool = false
var held_by_wall: bool = false
var hazard_slow: float = 1.0
var input_mash_count: int = 0

# --- Timers (simulated ms; -16 per frame @ 60 FPS, floored at 0) -----------
var jump_timer: int = 0       # >0 = airborne (immune to damage)
var max_jump_time: int = 40   # frames the jump lasts (Player.h:138)
var jump_offset: float = 0.0 # visual arc offset, computed via sin(progress*pi)*25
var damage_timer: int = 0    # post-hit invulnerability (~1 s)
var invincible_timer: int = 0  # chalice-of-immortality total invuln (ms)
var spawn_guard_ms: int = 0   # TASK 38: immortalita'+lampeggio alla nascita/rinascita (3 s)
var speed_boost_timer: int = 0 # temporary post-jump-over-enemy speed boost (ms)
var permanent_speed_boost: bool = false  # winged boots: persists until death

# ===========================================================================
# FIX (pozione magica): modalità FANTASMA. Il player che beve la pozione
# diventa evanescente per GHOST_MODE_DURATION_MS e attraversa i muri.
# A fine effetto, se si trova DENTRO un muro, scivola automaticamente verso
# il centro della cella percorribile più vicina (mai intrappolato nel muro).
# ===========================================================================
const GHOST_MODE_DURATION_MS: int = 9000  # FIX: 5s + 4s richiesti dall'utente
var ghost_mode: bool = false
var ghost_timer_ms: int = 0
# Uscita di sicurezza: quando il timer scade dentro un muro, il player
# scivola (ancora fantasma, senza collisioni) verso questo centro cella.
var _ghost_exit_target: Vector2 = Vector2.INF
var _ghost_exiting: bool = false
var shoot_cooldown: int = 0
var shoot_anim_timer: int = 0  # >0 = attack animation playing
var anim_time: int = 0  # accumulated for idle/walk anim (NEVER reset)
var next_life_threshold: int = 50000  # TASK 97: extra life ogni 50k (era 100k)

# ===========================================================================
# TASK 99 (LEVEL UP): il punteggio È esperienza. Ogni soglia della curva
# 1.000 x n^1,75 superata fa salire di livello e accredita 1 PUNTO
# ABILITÀ bancabile (spendibile nella modale che si apre in pausa).
#   * level                = livello corrente (1..20)
#   * skill_points         = punti abilità NON ancora spesi (bancabili:
#                            se alla modale si preme OK senza scegliere,
#                            restano e si sommano al prossimo level up)
#   * pending_levelup_fx   = level up maturati ma NON ancora annunciati:
#                            il controller li consuma uno alla volta per
#                            fare partire fulmine + scritta "LEVEL UP!"
#                            (così un singolo botto di punti che salta più
#                            soglie produce UNA celebrazione, non una raffica)
# Semantica di reset (uguale a punteggio/reliquie): azzerato da reset()
# (nuova partita), conservato da reset_position() (respawn/cambio livello),
# trasportato tra scene dal carry e salvato/ripristinato dalle continue.
# ===========================================================================
var level: int = 1
var skill_points: int = 0
var pending_levelup_fx: int = 0

# TASK 99 FASE 2 — livelli acquistati delle otto abilità (id -> int, vedi
# GameConstants.SKILL_DEFS). Aggiornati SOLO alla conferma della modale
# (confirm_skills): le +/− nella finestra sono assegnazioni temporanee.
# Segue la stessa semantica di level (reset() a nuova partita, carry e
# session snapshot la conservano tra scene e continue).
var skill_levels: Dictionary = {}
# Rigenerazione (accumulatori): +0.2 energia ogni 5s per livello di Rigenerazione.
var _skill_regen_timer_ms: float = 0.0
var _skill_regen_acc: float = 0.0
# Quota di salti aggiuntivi in aria ancora disponibili (si resetta al
# salto da terra, si consuma a ogni salto a mezz'aria).
var _air_jumps_left: int = 0

# ===========================================================================
# TASK 82 — LAMPO DI VOLATA (muzzle flash): feedback visivo dello sparo.
# Quando un'arma spara, per ~160 ms all'estremita' dell'arma appare un
# piccolo effetto GRAFICO DEDICATO per arma/elemento (fuoco per pistol/
# shotgun/rocket, energia per laser, polvere+brace per il cannone d'assedio,
# fiamma/brina/arcano colorato per le armi elementali) + un piccolo
# PointLight2D riusato (solo se le luci sono attive) che illumina il muro
# accanto nel dungeon buio. La POSIZIONE e' la volata (punta dell'arma
# disegnata in mano: PNG PixelLab se presente, fallback procedurale).
# ===========================================================================
const MUZZLE_FLASH_MS: int = 160          # durata del lampo (ms simulati)
const MUZZLE_LIGHT_ENABLED: bool = true   # piccolo PointLight2D durante il lampo
const MUZZLE_LIGHT_RADIUS: float = 104.0  # raggio della luce di sparo (px)

var _muzzle_timer_ms: int = 0             # countdown del lampo
var _muzzle_pos: Vector2 = Vector2.ZERO   # posizione LOCALE della volata
var _muzzle_dir: Vector2 = Vector2(1.0, 0.0)  # direzione del colpo allo sparo
var _muzzle_color: Color = Color(1.0, 0.55, 0.15)
var _muzzle_style: String = "fire"        # fire|wide|blast|energy|cannon|flame|frost|arcane
var _muzzle_light: PointLight2D = null    # luce riusata (mai ricreata a colpo)

# ===========================================================================
# FIX (stamina dei salti): il player può eseguire al massimo 2 SALTI
# CONSECUTIVI (TASK 23: richiesto dall'utente — prima erano 3), poi "si
# stanca" e non può più saltare.
#   * Ogni salto consuma 1/2 della barra (visibile in HUD, verde, sotto la
#     barra della vita).
#   * Dopo ogni salto la barra tende a ricaricarsi se il player non salta
#     nuovamente (la ricarica parte poco dopo l'ultimo salto).
#   * Al secondo salto consecutivo la barra si svuota: il player non può
#     saltare finché non si è caricata COMPLETAMENTE.
#   * Se prova a saltare senza stamina, non salta e si sente un rumore
#     secco di pulsante premuto "a vuoto" (click, vedi STAMINA_CLICK).
# ===========================================================================
const STAMINA_JUMP_COST: float = 1.0 / 2.0
const STAMINA_RECHARGE_FULL_MS: float = 2400.0   # barra vuota → piena in 2.4s
const STAMINA_RECHARGE_DELAY_MS: float = 720.0   # la ricarica parte ~0.72s dopo l'ATTERRAGGIO dell'ultimo salto (così 2 salti in catena restano tali a qualunque framerate)

## TASK 38 — nascita/rinascita: dopo lo spawn (nuovo livello, continue o
## respawn post-morte) il player e' IMMORTALE e LAMPEGGIA per 3 secondi,
## per dare il tempo di allontanarsi dai nemici.
const SPAWN_GUARD_MS: int = 3000
## Periodo del lampeggio della guardia (~4 Hz, acceso per il 60% del ciclo:
## mai invisibile del tutto, per non perdere il player di vista).
const SPAWN_GUARD_BLINK_MS: float = 250.0
const STAMINA_CLICK_COOLDOWN_MS: float = 280.0   # anti-spam del click a vuoto
var stamina: float = 1.0                 # 1.0 = piena, 0.0 = vuota
var stamina_exhausted: bool = false      # true dopo il 2° salto consecutivo → blocco fino a ricarica completa
var _stamina_since_jump_ms: float = 99999.0  # ms trascorsi dall'ultimo salto (per il delay di ricarica)
var _stamina_click_cd_ms: float = 0.0        # cooldown residuo del suono di click a vuoto

# ===========================================================================
# FUOCO AMICO (Task 18 — trasferimento anima): se un player uccide il
# compagno (ultimo punto di energia portato a 0 da un suo proiettile), il
# corpo della vittima si accascia al suolo, la sua anima si separa e vola
# veloce verso il vincitore ricaricandogli COMPLETAMENTE l'energia.
# Durante il volo la vittima è congelata (soul_pending = true): niente
# input, niente danni, niente rendering — la scena la disegna
# SoulTransferEffect (corpo + anima). Il respawn avviene quando l'anima
# viene assorbita (respawn_after_soul).
# ===========================================================================
var soul_pending: bool = false
# TASK 87 — morte normale: il corpo si sta accasciando (PlayerCollapseEffect
# disegna la caduta). `collapse_requested` dice al controller di avviare
# l'effetto (sempre false per il fuoco amico, che ha SoulTransferEffect).
var collapse_requested: bool = false
# Visibilità degli sprite prima della morte (ripristinata al respawn).
var _pre_soul_sprite_visible: bool = true
var _pre_soul_weapon_visible: bool = true

# ============================================================================
# RELIC (Task 21) — LE RELIQUIE DELLE SCHERMATE BONUS POST-BOSS
# ============================================================================
# Arma reliquia: vive in current_weapon (Dictionary esteso con le chiavi
# "relic"/"melee"/"max_ammo", vedi GameConstants.make_relic_weapon).
# "ammo" = COLPI rimanenti: a 0 l'arma SI ROMPE e si torna alla PISTOL.
# ALLA MORTE (perdita di una vita) arma reliquia E armatura si PERDONO.
# Le armi a terra NON sovrascrivono una reliquia (guard in collect_weapon).
# In boss room BossRoomController imposta relic_infinite_shots = true
# (i colpi NON si consumano, coerente con le munizioni potenziate base).

# True solo nella boss room: i colpi della reliquia non si consumano.
var relic_infinite_shots: bool = false

# MISCHIA: shoot() NON spawna proiettili — alza questo flag one-shot; il
# controller (MainGame/BossRoom) lo consuma nello stesso frame applicando
# il danno ad area ai nemici nella shape (pattern picked_weapon_this_frame).
var melee_pending: bool = false
var melee_pending_def: Dictionary = {}

# Visual dell'attacco in mischia (arco/cerchio/linea) disegnato in _draw()
# per ~250ms dopo il fendente.
var melee_fx_timer_ms: int = 0
var melee_fx_def: Dictionary = {}
var melee_fx_dir: Vector2 = Vector2(1.0, 0.0)
const MELEE_FX_DURATION_MS: int = 250

# ARMATURA RELIQUIA (slot DEDICATO, non occupa l'arma). Dictionary = def
# duplicata + "charges"/"max_charges" correnti. Vuota = nessuna armatura.
# Tutte: +2 energia max (5 -> 7) e cura piena all'equip; durabilita' per
# kind; si perde alla morte; outfit overlay procedurale in _draw().
var armor_relic: Dictionary = {}
const ARMOR_ENERGY_BONUS: int = 2
# Timer interni: rigenerazione (Veste) e pulsazione aura (Fuoco).
var _armor_regen_timer_ms: float = 0.0
var _armor_aura_timer_ms: float = 0.0
# TASK 25 — outfit armatura: materiale shader attivo e hue del VESTIARIO
# del personaggio (calcolata una volta per carattere dal frame 0 dello sheet;
# -1.0 = nessun hue dominante -> solo tinta metallo).
var _armor_outfit_on: bool = false
# TASK 51 (P8): true quando sta usando lo sheet XHD CORAZZATO
var _armored_sheet_on: bool = false
var _cloth_hue: float = -1.0
var _cloth_hue_valid: bool = false
const _CLOTH_HUE_WINDOW: float = 0.09


# ----------------------------------------------------------------
# RELIC: API armature
# ----------------------------------------------------------------
## Equipaggia un'armatura reliquia (dalla schermata bonus): +2 energia max,
## CURA PIENA, durabilita' piena. Sostituisce l'eventuale armatura corrente.
func equip_relic_armor(def: Dictionary) -> void:
        armor_relic = def.duplicate()
        armor_relic["charges"] = int(def.get("charges", 5))
        armor_relic["max_charges"] = int(def.get("charges", 5))
        max_energy = 5 + _perk_energy_bonus_units() + ARMOR_ENERGY_BONUS
        energy = max_energy  # cura piena all'equipaggiamento
        _armor_regen_timer_ms = 0.0
        _armor_aura_timer_ms = 0.0
        # TASK 51 (P8): ARMATURA INTEGRATA — swap allo sprite corazzato
        # (se non gia' attivo); il ricolor vestito resta solo come fallback
        # per i personaggi senza sheet corazzato.
        if not _armored_sheet_on:
                load_character_sprite()
        _apply_armor_outfit_visual()
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.RELIC_PICKUP)


## Ripristina un'armatura dal carry tra scene (maze <-> boss room):
## stesse cariche salvate, +2 energia max, energia piena (comportamento
## standard dei player a inizio scena).
func restore_relic_armor(saved: Dictionary) -> void:
        if saved.is_empty():
                return
        armor_relic = saved.duplicate()
        max_energy = 5 + _perk_energy_bonus_units() + ARMOR_ENERGY_BONUS
        energy = max_energy
        _armor_regen_timer_ms = 0.0
        _armor_aura_timer_ms = 0.0
        # TASK 51 (P8): il carry tra scene ricarica lo sprite corazzato.
        if not _armored_sheet_on:
                load_character_sprite()
        # TASK 25: ri-applica l'outfit dopo il carry tra scene.
        _apply_armor_outfit_visual()


func has_relic_armor() -> bool:
        return not armor_relic.is_empty()


func armor_kind() -> String:
        return str(armor_relic.get("kind", ""))


func armor_charges() -> int:
        return int(armor_relic.get("charges", 0))


## CORAZZA D'ORO (assorbimento): true se il colpo viene assorbito dalla
## riserva (10 cariche = doppio della vita base). Chiamato DENTRO
## take_damage() prima di scalare l'energia.
func _try_absorb_with_golden_armor() -> bool:
        if armor_kind() != "absorb":
                return false
        if armor_charges() <= 0:
                return false
        armor_relic["charges"] = armor_charges() - 1
        if armor_charges() <= 0:
                _break_relic_armor()
        return true


## SCAGLIE DEL DRAGO (riflessione): consuma una carica; true se il colpo
## va riflesso. Il controller rimuove il proiettile nemico e spawna il
## proiettile-rimbalzo del player verso il boss (danno = miglior colpo).
func try_reflect_projectile() -> bool:
        if armor_kind() != "reflect":
                return false
        if armor_charges() <= 0:
                return false
        armor_relic["charges"] = armor_charges() - 1
        var broke: bool = armor_charges() <= 0
        if broke:
                _break_relic_armor()
        return true


## OSSIDIANA DEL CREPUSCOLO (spine): ritorna il danno delle spine (2) se
## la carica scatta, 0 altrimenti. Il controller lo applica al nemico che
## ha toccato il player (SOLO tocco in mischia, NON proiettili).
func consume_thorn_charge() -> int:
        if armor_kind() != "thorns":
                return 0
        if armor_charges() <= 0:
                return 0
        armor_relic["charges"] = armor_charges() - 1
        var dmg: int = int(armor_relic.get("thorn_damage", 2))
        if armor_charges() <= 0:
                _break_relic_armor()
        return dmg


## CORAZZA DI FUOCO (aura): true quando scatta la pulsazione (ogni aura_ms);
## il controller applica il danno a tutti i nemici nel raggio. La carica si
## consuma a PULSAZIONE (non per nemico colpito).
func armor_aura_pulse(delta_ms: float) -> bool:
        if armor_kind() != "aura":
                return false
        _armor_aura_timer_ms += delta_ms
        if _armor_aura_timer_ms < float(armor_relic.get("aura_ms", 2000)):
                return false
        _armor_aura_timer_ms = 0.0
        armor_relic["charges"] = armor_charges() - 1
        if armor_charges() <= 0:
                _break_relic_armor()
        return true


## TASK 23 (fix bug utente — corazza di fuoco): true se il contatto con un
## nemico attiva l'ustione (il controller applica il danno al nemico e il
## player NON subisce il colpo). Consuma UNA carica per proc con cooldown
## AURA_CONTACT_CD_MS (così restare appoggiati a un nemico non fonde tutte
## le 20 cariche in un secondo). Ritorna false se l'armatura non c'è, non ha
## cariche o il cooldown non è ancora scaduto.
const AURA_CONTACT_CD_MS: float = 450.0
var _aura_contact_cd_ms: float = 0.0


func armor_aura_contact_proc(delta_ms: float) -> bool:
        if _aura_contact_cd_ms > 0.0:
                _aura_contact_cd_ms = maxf(0.0, _aura_contact_cd_ms - delta_ms)
        if armor_kind() != "aura" or armor_charges() <= 0:
                return false
        if _aura_contact_cd_ms > 0.0:
                return false
        _aura_contact_cd_ms = AURA_CONTACT_CD_MS
        armor_relic["charges"] = armor_charges() - 1
        if armor_charges() <= 0:
                _break_relic_armor()
        return true


## CORAZZA DEL FURORE: true mentre attiva — i colpi colpiscono come se
## avessero 1 hit-to-kill in meno (floor 2) e +1 power flat vs boss.
func is_fury_active() -> bool:
        return armor_kind() == "fury" and armor_charges() > 0


## Consuma una carica del Furore per colpo sparato (30 colpi totali).
func _tick_fury_shot() -> void:
        if armor_kind() != "fury":
                return
        armor_relic["charges"] = armor_charges() - 1
        if armor_charges() <= 0:
                _break_relic_armor()


## L'armatura si rompe (durabilita' esaurita): slot liberato, energia max
## torna alla base + il perk Energia Vitale (TASK 99: il perk NON si perde
## quando l'armatura si rompe; l'energia eccedente viene troncata).
func _break_relic_armor() -> void:
        armor_relic = {}
        max_energy = 5 + _perk_energy_bonus_units()
        energy = mini(energy, max_energy)
        _armor_regen_timer_ms = 0.0
        _armor_aura_timer_ms = 0.0
        # TASK 25: il vestito torna al colore originale.
        _revert_armor_outfit_visual()
        # TASK 51 (P8): l'armatura fisica SPARISCE di dosso — torna allo
        # sprite normale.
        if _armored_sheet_on:
                _armored_sheet_on = false
                load_character_sprite()
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.RELIC_BREAK)


# ----------------------------------------------------------------
# TASK 25 — OUTFIT ARMATURA: ricolor vestito (shader armor_outfit)
# ----------------------------------------------------------------
## Hue dominante del VESTIARIO del personaggio corrente, dal frame 0 dello
## sheet (XHD o SD): istogramma a 24 bucket sui pixel opachi SATURI e NON
## pelle. -1.0 se non c'e' un hue dominante (Golem di pietra ecc.): lo shader
## applichera' solo la tinta metallo. Deterministico: stesso sheet, stesso hue.
func _compute_cloth_hue() -> float:
        if _character_sheet_texture == null:
                return -1.0
        var img: Image = null
        if _character_sheet_texture is ImageTexture:
                img = (_character_sheet_texture as ImageTexture).get_image()
        else:
                img = _character_sheet_texture.get_image()
        if img == null:
                return -1.0
        # get_pixel vuole RGBA8: converti difensivamente (le texture caricate
        # via load() possono essere compressed).
        if img.get_format() != Image.FORMAT_RGBA8:
                img = img.duplicate()
                img.convert(Image.FORMAT_RGBA8)
        var fw: int = mini(_frame_px, img.get_width())
        var fh: int = mini(_frame_px, img.get_height())
        var buckets: Array[int] = []
        buckets.resize(24)
        for i in 24:
                buckets[i] = 0
        var total_saturated: int = 0
        # campionamento denso (~128x128 campioni): con step 5 il conteggio
        # saturi cadeva sotto la soglia e l'eroe (cuoio rosso scuro) risultava
        # senza vestito. Deterministico: stesso sheet, stesso istogramma.
        var step_x: int = maxi(1, fw / 128)
        var step_y: int = maxi(1, fh / 128)
        for y in range(0, fh, step_y):
                for x in range(0, fw, step_x):
                        var c: Color = img.get_pixel(x, y)
                        if c.a < 0.5:
                                continue
                        # Godot 4: h/s/v sono proprietà di Color
                        var h: float = c.h
                        var s: float = c.s
                        var v: float = c.v
                        if s < 0.28:
                                continue
                        # guardia PELLE: hue arancio-rossiccio + chiara (il
                        # cuoio scuro v<0.4 resta ricolorabile come vestito)
                        var hd: float = absf(h - 0.08)
                        if hd > 0.5:
                                hd = 1.0 - hd
                        if hd < 0.06 and v > 0.4:
                                continue
                        var b: int = clampi(int(h * 24.0), 0, 23)
                        buckets[b] += 1
                        total_saturated += 1
        if total_saturated < 60:
                return -1.0
        var best: int = 0
        for i in 24:
                if buckets[i] > buckets[best]:
                        best = i
        # il bucket dominante deve pesare almeno il 15% dei pixel saturi
        if buckets[best] < total_saturated * 0.15:
                return -1.0
        return (float(best) + 0.5) / 24.0


## Applica il materiale outfit: enhancement identico + vestito ricolorato
## col colore dell'armatura + tinta metallo + rim colorato. No-op se il flag
## di rollback e' spento o lo sprite non e' pronto (verra' ri-applicato dal
## reload dello sprite).
func _apply_armor_outfit_visual() -> void:
        if not GameConstants.ARMOR_OUTFIT_ENABLED:
                return
        if armor_relic.is_empty() or sprite == null:
                return
        if CharacterArt == null:
                return
        if not _cloth_hue_valid:
                _cloth_hue = _compute_cloth_hue()
                _cloth_hue_valid = true
        var col: Color = armor_relic.get("color", Color.WHITE)
        CharacterArt.apply_armor_outfit(sprite, col, _cloth_hue, _CLOTH_HUE_WINDOW)
        _armor_outfit_on = true


## Ripristina l'enhancement standard quando l'armatura si rompe/viene persa.
func _revert_armor_outfit_visual() -> void:
        if not _armor_outfit_on:
                return
        if CharacterArt != null and sprite != null:
                CharacterArt.remove_armor_outfit(sprite)
        _armor_outfit_on = false


## REGOLE DELLA MORTE (decisione utente Task 21): alla perdita di una vita
## il player perde l'ARMA RELIQUIA (torna PISTOL) e l'ARMATURA. Vale per
## la morte da nemico/boss (take_damage) e da fuoco amico (anima).
func lose_relics_on_death() -> void:
        if current_weapon.has("relic"):
                current_weapon = _make_weapon(WeaponType.PISTOL)
                projectiles.clear()
                if AudioManager:
                        AudioManager.play_sound(AudioManager.SoundType.RELIC_BREAK)
        if not armor_relic.is_empty():
                armor_relic = {}
                max_energy = 5 + _perk_energy_bonus_units()
                energy = mini(energy, max_energy)
                _armor_regen_timer_ms = 0.0
                _armor_aura_timer_ms = 0.0
                # TASK 25: vestito torna originale anche alla morte.
                _revert_armor_outfit_visual()
        melee_pending = false
        melee_fx_timer_ms = 0


# ----------------------------------------------------------------
# RELIC: API mischia (flag one-shot consumato dal controller)
# ----------------------------------------------------------------
func consume_melee_pending() -> Dictionary:
        var def: Dictionary = melee_pending_def
        melee_pending = false
        melee_pending_def = {}
        return def


## Direzione di sparo/attacco corrente (dx se in movimento, altrimenti
## l'ultima direzione non-zero; fallback destra). Usata da shoot() e dalla
## mischia per orientare arco e linea.
func _aim_dir() -> Vector2:
        var adx: int = dx if dx != 0 else last_dx
        var ady: int = dy if dy != 0 else last_dy
        if adx == 0 and ady == 0:
                adx = 1
        return Vector2(float(adx), float(ady))

# --- Character selection ----------------------------------------------------
var character_type: int = CharacterType.HERO_M
var player_num: int = 1
# tint modulates the sprite (white = no tint for P1, light blue for P2)
var tint: Color = Color.WHITE

# Sprite nodes (assigned by load_character_sprite or set in editor).
# Player sprite is 64x64 side-view; feet anchor at (32, 56) in C++,
# here we use the Sprite2D centered horizontally + offset down by 24.
@onready var sprite: Sprite2D = $Sprite2D if has_node("Sprite2D") else null
@onready var weapon_sprite: Sprite2D = $WeaponSprite if has_node("WeaponSprite") else null
# Visual jump offset is applied to the sprite, not the Node2D position.
# We track the last applied flip so it persists when last_dx == 0.
var _last_flipped: bool = false


# ===========================================================================
# Lifecycle
# ===========================================================================
func _ready() -> void:
        # Starting stats: position (1,1) cell, 3 lives, full energy, pistol.
        reset()
        # Load fire-aura spritesheet via SpriteManager (mirror C++ static
        # SpriteSheet load in Game::drawFireAura 3789-3794).
        if SpriteManager:
                _fire_aura_sheet = SpriteManager.get_sheet("effect_fireaura")
        # FIX (pallina gialla intermittente sotto il player): il PointLight2D
        # AuraLight creato qui era una luce gialla che pulsava sotto il player
        # e copriva quasi tutto lo sprite. L'utente lo ha segnalato come bug.
        # Rimuoviamo il PointLight2D — l'aura del player viene disegnata
        # proceduralmente solo quando è invincibile (chalice effect, vedi
        # _draw_fire_aura) e non come luce ambientale permanente.
        # FIX: la Camera2D viene ora creata da MainGameController._setup_camera
        # e aggiunta al Window root (NON come figlia del MainGame scalato né
        # del player). Questo evita che la camera erediti trasformazioni di
        # scale/position dai genitori. Player.gd non crea più la sua camera;
        # si limita a registrare la posizione del player per eventuali
        # screen-shake futuri (gestiti da EffectsManager.set_camera).
        # Non facciamo nulla qui — MainGameController._setup_camera() crea
        # una camera globale con zoom 1080/1024 = 1.0547 centrata su (512,512).


# ===========================================================================
# reset(): full reset (new game / continue credit).
# Mirrors Player::reset() in src/Player.cpp line 99-108.
# ===========================================================================
func reset() -> void:
        reset_position()
        lives = 3
        max_energy = 5
        energy = max_energy
        score = 0
        next_life_threshold = C.EXTRA_LIFE_EVERY_POINTS
        # TASK 99 (LEVEL UP): nuova partita = progressione azzerata (le
        # continue invece conservano livello/punti: vengono ripristinati
        # dal session snapshot dopo questo reset).
        level = 1
        skill_points = 0
        pending_levelup_fx = 0
        skill_levels.clear()
        _skill_regen_timer_ms = 0.0
        _skill_regen_acc = 0.0
        _air_jumps_left = 0
        current_weapon = _make_weapon(WeaponType.PISTOL)
        projectiles.clear()
        picked_weapon_this_frame = false
        # Permanent boost is LOST on full reset (death). See Player.cpp:106.
        permanent_speed_boost = false
        invincible_timer = 0
        # FIX (pozione magica): azzera lo stato fantasma
        _end_ghost_mode_now()
        # RELIC (Task 21): nuova partita / continue = NESSUNA reliquia
        # (arma e armatura si perdono alla morte, molto prima di qui).
        lose_relics_on_death()
        relic_infinite_shots = false
        # FUOCO AMICO (Task 18): safety net — un full reset (nuovo livello /
        # continue) NON deve mai ereditare un player congelato in attesa
        # dell'anima (l'effetto viene comunque liberato con la scena).
        soul_pending = false
        if sprite != null:
                sprite.visible = true
        if weapon_sprite != null:
                weapon_sprite.visible = _pre_soul_weapon_visible


# ===========================================================================
# reset_position(): respawn after losing 1 life / start of new level.
# Mirrors Player::resetPosition() in src/Player.cpp line 117-129.
#
# NOTE: this also clears `permanent_speed_boost` per user requirement -
# "no speed boost after death". The C++ source comment at line 126 is
# explicit: the winged-boots bonus does NOT survive death.
# ===========================================================================
func reset_position() -> void:
        # Start at centre of cell (1, 1) inside the maze area (below UI bar).
        position = Vector2(
                1 * TILE_SIZE + TILE_SIZE / 2.0,
                1 * TILE_SIZE + TILE_SIZE / 2.0 + UI_HEIGHT
        )
        dx = 0
        dy = 0
        next_dx = 0
        next_dy = 0
        last_dx = 1
        last_dy = 0
        speed = 2
        jump_timer = 0
        max_jump_time = 0
        damage_timer = 0
        shoot_cooldown = 0
        shoot_anim_timer = 0
        anim_time = 0
        speed_boost_timer = 0
        permanent_speed_boost = false  # fix: no speed boost after death
        invincible_timer = 0
        jump_offset = 0.0
        # TASK 38 (nascita/rinascita): 3 secondi di immortalita' con
        # lampeggio, per dare il tempo di allontanarsi dai nemici.
        spawn_guard_ms = SPAWN_GUARD_MS
        # FIX (stamina): al respawn le "gambe" sono riposate (barra piena
        # alla CAPACITÀ CORRENTE: con Resistenza > 0 la barra massima è
        # oltre 1.0, TASK 99).
        stamina = get_stamina_max()
        stamina_exhausted = false
        _stamina_since_jump_ms = 99999.0
        _stamina_click_cd_ms = 0.0
        # FIX (pozione magica): il respawn azzera lo stato fantasma (il player
        # torna solido nella cella di partenza, che è sempre percorribile).
        _end_ghost_mode_now()
        # TASK 30 (hazard): nessuna trattenuta oltre la morte/respawn e
        # nessun rallentamento residuo (le sabbie sono lontane dallo spawn).
        held_by_trap = false
        held_by_wall = false
        hazard_slow = 1.0
        input_mash_count = 0
        # FUOCO AMICO (Task 18): il respawn classico (perdita vita da nemico,
        # cambio livello) scongela sempre il player dall'attesa anima.
        if soul_pending:
                soul_pending = false
                if sprite != null:
                        sprite.visible = _pre_soul_sprite_visible
                if weapon_sprite != null:
                        weapon_sprite.visible = _pre_soul_weapon_visible


# ===========================================================================
# set_position(new_x, new_y): absolute pixel position (used in boss mode to
# place the player at the bottom of the boss room). Stops movement.
# Mirrors Player::setPosition() line 161-163.
# ===========================================================================
func set_position_abs(new_x: float, new_y: float) -> void:
        position = Vector2(new_x, new_y)
        dx = 0
        dy = 0
        next_dx = 0
        next_dy = 0


# ===========================================================================
# Character selection
# ===========================================================================

# set_character(ct, pNum): set character type + player number, then load
# the matching sprite. If player_num == 2, applies a light blue tint to
# distinguish P1 from P2 when they share the same character.
func set_character(ct: int, p_num: int) -> void:
        character_type = ct
        player_num = p_num
        tint = _get_player_tint(p_num)
        load_character_sprite()


# Load the sprite for the current character_type from
# assets/sprites/<base>_sheet.png. The main sheet is 256x64 (4 frames of 64x64),
# oppure 1024x256 XHD (4 frame da 256px, Task 22).
# TASK 69 (pulizia codice/asset morti): i PNG walk/jump dedicati
# (<base>_walk0..3_sheet.png, <base>_jump_sheet.png) e il loro preload
# (_walk_sheet_textures / _jump_sheet_texture, write-only) sono stati
# rimossi: il C++ (Player.cpp:432-443) NON swappava sheet per walk/jump
# e lo swap AI rigenerato cambiava stile a metà ciclo (vedi _update_sprite).
func load_character_sprite() -> void:
        var base: String = CHARACTER_SPRITE_BASE.get(character_type, CHARACTER_SPRITE_BASE[CharacterType.HERO_M])
        var path := base + "_sheet.png"
        # TASK 25: l'hue del vestito dipende dal personaggio -> da ricalcolare.
        _cloth_hue_valid = false
        _cloth_hue = -1.0
        if ResourceLoader.exists(path) and sprite:
                # TASK 22 — priorità sheet XHD 4x (256px/frame): stessa palette,
                # stessa silhouette, stessi frame — solo bordi più lisci e
                # definizione maggiore. Flag di rollback: GameConstants.SPRITE_XHD_ENABLED.
                # Con XHD attivo la texture 256px viene disegnata con scala
                # 1/4 => dimensione A SCHERMO identica (64*1.3=83px).
                # TASK 51 (P8) — ARMATURA INTEGRATA NELLO SPRITE: se il
                # player ha un'armatura reliquia equipaggiata e esiste lo
                # sheet XHD corazzato ({char}_armored_xhd_sheet.png), quello
                # SOSTITUISCE lo sheet normale (armatura disegnata addosso,
                # non piu' solo il ricolor vestito del Task 25). Con lo
                # sprite corazzato i walk/jump dedicati NON si caricano
                # (il ciclo 4f del main sheet copre il passo; salto =
                # frame 0 + offset Y) e la tinta vira verso il colore
                # dell'armatura per mantenere l'identita' del tipo.
                var xhd_tex: Texture2D = _try_load_xhd_texture(base.get_file())
                var armored_mode: bool = false
                if has_relic_armor():
                        var arm_tex: Texture2D = _try_load_xhd_texture(
                                        base.get_file() + "_armored")
                        if arm_tex != null:
                                xhd_tex = arm_tex
                                armored_mode = true
                if xhd_tex != null:
                        _character_sheet_texture = xhd_tex
                        _character_sheet_path = base
                        _frame_px = GameConstants.SPRITE_XHD_FRAME_PX
                        sprite.modulate = tint
                        if armored_mode:
                                var acol: Color = armor_relic.get("color", Color.WHITE)
                                sprite.modulate = tint.lerp(acol, 0.28)
                        sprite.flip_h = false
                        _armored_sheet_on = armored_mode
                        _apply_character_frame(0)
                        sprite_loaded = true
                        var px_scale: float = 1.3 * (64.0 / float(_frame_px))
                        sprite.scale = Vector2(px_scale, px_scale)
                        sprite.centered = true
                        # Enhancement shader invariato (funziona su qualunque
                        # risoluzione: sharpening + rim light a runtime).
                        if CharacterArt and sprite:
                                CharacterArt.apply_enhancement(sprite, false)
                        # TASK 25: apply_enhancement ha appena sostituito il
                        # materiale: ri-applica l'outfit se c'e' un'armatura.
                        # TASK 51 (P8): con lo sprite CORAZZATO il ricolor
                        # vestito e' ridondante (l'armatura e' gia' disegnata).
                        _armor_outfit_on = false
                        if has_relic_armor() and not armored_mode:
                                _apply_armor_outfit_visual()
                        return
                _frame_px = 64
                var tex := load(path)
                if tex is Texture2D:
                        # Store the full sheet; _update_sprite() will set the
                        # AtlasTexture for the current frame each frame.
                        _character_sheet_texture = tex
                        _character_sheet_path = base
                        sprite.modulate = tint
                        sprite.flip_h = false
                        # Initial frame (idle = main sheet frame 0)
                        _apply_character_frame(0)
                        sprite_loaded = true
                        # FIX (sprite troppo piccoli): scale aumentata da 1.0 a 1.3
                        # per rendere il player più visibile nel tile 48px.
                        # 64*1.3=83px, leggermente più del tile ma visibile.
                        if sprite:
                                sprite.scale = Vector2(1.3, 1.3)
                                sprite.centered = true
                        # Apply CharacterArt enhancement shader — SOLO per il Player.
                        # Costo: 1 sprite × 64x64 = ~4K pixel shader ops/frame
                        # (era 29 sprite × 750K ops con tutti i nemici).
                        if CharacterArt and sprite:
                                CharacterArt.apply_enhancement(sprite, false)
                        # TASK 25: ri-applica l'outfit dopo il reload (SD path).
                        _armor_outfit_on = false
                        if has_relic_armor():
                                _apply_armor_outfit_visual()
                else:
                        sprite_loaded = false
        else:
                sprite_loaded = false


# TASK 22 — Carica uno sheet XHD (assets/sprites/xhd/<id>_xhd_sheet.png)
# via Image.load() runtime (bypassa l'import, pattern già usato da
# SpriteManager per gli hd/). Ritorna null se il flag è spento o il file
# manca => il chiamante ricade sul percorso SD legacy intatto.
func _try_load_xhd_texture(id: String) -> Texture2D:
        if not GameConstants.SPRITE_XHD_ENABLED:
                return null
        var xhd_path: String = GameConstants.xhd_sheet_path(id)
        var abs_path: String = ProjectSettings.globalize_path(xhd_path)
        if not FileAccess.file_exists(abs_path):
                return null
        var img := Image.new()
        if img.load(abs_path) != OK:
                return null
        return ImageTexture.create_from_image(img)


# Apply a specific frame index from the character sheet to the Sprite2D.
# The main sheet is 256x64 = 4 frames of 64x64 (SD) oppure 1024x256 = 4 frame
# di 256x256 (XHD Task 22): la larghezza frame è _frame_px.
# FIX: re-apply tint after every texture change (P2 bluish tint was lost
# when _apply_character_frame set sprite.texture = at).
func _apply_character_frame(frame_idx: int) -> void:
        if _character_sheet_texture == null or sprite == null:
                return
        var fw: int = _frame_px
        var fh: int = _frame_px
        var cols: int = 4
        var idx: int = clampi(frame_idx, 0, cols - 1)
        var at := AtlasTexture.new()
        at.atlas = _character_sheet_texture
        at.region = Rect2(idx * fw, 0, fw, fh)
        sprite.texture = at
        sprite.modulate = tint  # FIX: re-apply tint (P2 bluish)


var _character_sheet_texture: Texture2D = null
var _character_sheet_path: String = ""
var sprite_loaded: bool = false
# TASK 22 — dimensione frame della sheet corrente (64 SD / 256 XHD).
var _frame_px: int = 64

# Fire-aura spritesheet (effect_fireaura, 6x4 frames of 64x64, anchor 32,32).
# Loaded via SpriteManager in _ready() and used in _draw() while the chalice
# invincibility is active. Mirrors C++ Game::drawFireAura (3770-3879) which
# loads the same spritesheet as a static SpriteSheet instance.
var _fire_aura_sheet: Variant = null
var _fire_aura_anim_time: float = 0.0  # accumulates for the fire flicker


# ===========================================================================
# Movement
# ===========================================================================

# set_direction(t_dx, t_dy): request a new direction (applied when aligned
# to cell centre, or immediately in free-movement mode).
func set_direction(t_dx: int, t_dy: int) -> void:
        next_dx = t_dx
        next_dy = t_dy


# try_move(t_dx, t_dy, maze): attempt to set movement toward (t_dx, t_dy).
# Returns true if the adjacent cell is open. Also updates last_dx/last_dy
# (so sprite/weapon orient correctly when the player stops).
# Mirrors Player::tryMove() line 170-185.
# FIX (pozione magica): in modalità fantasma il muro NON blocca la corsa —
# il player attraversa i muri liberamente (uso principale della pozione:
# sfuggire ai nemici o fare scorciatoia verso un oggetto).
## TASK 50: collisione del player coi MURO-LABIRINTO in rovina della boss
## room (gruppo "arena_ruins"). Risolve l'overlap AABB-cerchio spingendo
## fuori sull'asse con penetrazione minore (scivolamento), cosi' il player
## "gira l'angolo" dei frammenti invece di incollarcisi. In modalita'
## fantasma (pozione) i muri NON bloccano, come nel labirinto.
func _collide_arena_ruins() -> void:
        if ghost_mode:
                return
        var radius: float = 13.0
        for node in get_tree().get_nodes_in_group("arena_ruins"):
                if node == null or not is_instance_valid(node):
                        continue
                if not node.has_method("is_standing") or not node.is_standing():
                        continue
                if not node.has_method("get_rect"):
                        continue
                var r: Rect2 = node.get_rect()
                # overlap AABB-cerchio (clamp del centro sul rettangolo)
                var closest := Vector2(
                                clampf(position.x, r.position.x, r.end.x),
                                clampf(position.y, r.position.y, r.end.y))
                var delta_v: Vector2 = position - closest
                if delta_v.length_squared() >= radius * radius:
                        continue
                if delta_v.length_squared() < 0.0001:
                        # centro DENTRO il rettangolo: spingi fuori dal lato piu' vicino
                        var to_l: float = position.x - r.position.x
                        var to_r: float = r.end.x - position.x
                        var to_t: float = position.y - r.position.y
                        var to_b: float = r.end.y - position.y
                        var m: float = minf(minf(to_l, to_r), minf(to_t, to_b))
                        if m == to_l:
                                position.x = r.position.x - radius
                        elif m == to_r:
                                position.x = r.end.x + radius
                        elif m == to_t:
                                position.y = r.position.y - radius
                        else:
                                position.y = r.end.y + radius
                        continue
                var dist: float = delta_v.length()
                var push: float = radius - dist
                position += delta_v / dist * push


func try_move(t_dx: int, t_dy: int, maze: Object) -> bool:
        var col := int(position.x / TILE_SIZE)
        var row := int((position.y - UI_HEIGHT) / TILE_SIZE)
        if ghost_mode or not maze.is_wall(col + t_dx, row + t_dy):
                dx = t_dx
                dy = t_dy
                last_dx = t_dx
                last_dy = t_dy
                return true
        # Direction blocked: still orient the sprite/weapon, then stop.
        # (Without this, the player could be permanently stuck against a wall
        # because dx/dy would carry over from the previous frame.)
        last_dx = t_dx
        last_dy = t_dy
        dx = 0
        dy = 0
        return false


# ===========================================================================
# update_player(maze, free_movement): per-frame update.
# Mirrors Player::update() in src/Player.cpp line 202-315.
#
#  1. Jump arc visual offset (sin curve, max 25 px).
#  2. Decrement all timers by 16 ms (60 FPS cadence).
#  3. Movement:
#     - free_movement=true  : pixel-free movement bounded to the screen.
#     - free_movement=false : snap-to-grid; aligns to cell centre before
#       turning, applies requested direction at centre, stops if wall ahead.
#       Player stops IMMEDIATELY when direction released (next_dx == next_dy
#       == 0).
#  4. Cell pickups (treasure / weapon).
#  5. Projectile advance (8 px/frame) + erase-remove inactive.
# ===========================================================================
func update_player(maze: Object, free_movement: bool, delta_ms: float = 16.0) -> void:
        # FUOCO AMICO (Task 18): player congelato in attesa che la sua anima
        # raggiunga il vincitore. Nessun input/movimento/proiettile/timer:
        # il corpo accasciato e l'anima in volo sono disegnati da
        # SoulTransferEffect; il respawn scatta all'assorbimento.
        if soul_pending:
                return
        # 1) Jump visual offset: half sin curve (0 -> peak -> 0 over max_jump_time).
        if jump_timer > 0:
                jump_timer -= 1
                var progress: float = 1.0 - float(jump_timer) / float(max_jump_time)
                jump_offset = sin(progress * PI) * 25.0
                # FIX (stamina): il delay di ricarica parte dall'ATTERRAGGIO
                # (fine del salto), non dall'inizio: così una catena di 3
                # salti ravvicinati è identica a qualunque framerate (il
                # timer in ms dell'animazione dipende dagli FPS, il consumo
                # della barra no).
                if jump_timer == 0:
                        _stamina_since_jump_ms = 0.0
        else:
                jump_offset = 0.0

        # 2) Tick all simulated-ms timers using REAL delta_ms (not fixed 16).
        # FIX (calice durava meno di 15s): _tick_timer usava 16ms fissi per
        # frame, ma se il gioco gira a FPS diverso da 60, la durata reale
        # cambia (120fps → 7.8s, 30fps → 31s). Ora usiamo delta_ms reale
        # passato dal MainGameController per garantire durate corrette.
        damage_timer = _tick_timer_ms(damage_timer, delta_ms)
        shoot_cooldown = _tick_timer_ms(shoot_cooldown, delta_ms)
        shoot_anim_timer = _tick_timer_ms(shoot_anim_timer, delta_ms)
        # TASK 82: decadimento del lampo di volata + sync della luce di sparo.
        if _muzzle_timer_ms > 0:
                _muzzle_timer_ms = maxi(0, _muzzle_timer_ms - int(delta_ms))
        _update_muzzle_light()
        anim_time += int(delta_ms)
        speed_boost_timer = _tick_timer_ms(speed_boost_timer, delta_ms)
        invincible_timer = _tick_timer_ms(invincible_timer, delta_ms)
        spawn_guard_ms = _tick_timer_ms(spawn_guard_ms, delta_ms)

        # FIX (stamina): ricarica della barra quando il player non salta.
        # La ricarica parte un attimo dopo l'ultimo salto (delay): 3 salti
        # in rapida successione svuotano la barra, un ritmo più disteso
        # permette di recuperare. Se il player è "stanco" (barra svuotata
        # dal 3° salto) può saltare di nuovo SOLO a ricarica completa.
        _stamina_since_jump_ms += delta_ms
        if _stamina_click_cd_ms > 0.0:
                _stamina_click_cd_ms = maxf(0.0, _stamina_click_cd_ms - delta_ms)
        if not is_jumping() and _stamina_since_jump_ms >= STAMINA_RECHARGE_DELAY_MS:
                # TASK 99 (Resistenza): barra massima maggiore (+7%/liv) e
                # ricarica più rapida (-5% tempo per liv).
                stamina = minf(get_stamina_max(), stamina + delta_ms
                                / STAMINA_RECHARGE_FULL_MS
                                * get_stamina_recharge_mult())
        if stamina_exhausted and stamina >= get_stamina_max() - 0.0001:
                stamina_exhausted = false

        # TASK 99 (Rigenerazione): +0.2 energia ogni 5s per livello, solo se
        # manca energia (pattern della Veste dell'Arcimago, senza cariche:
        # l'accumulo frazionario converte le mezze unità in cuori interi).
        var regen_rate: float = get_regen_rate()
        if regen_rate > 0.0 and energy < max_energy:
                _skill_regen_timer_ms += delta_ms
                if _skill_regen_timer_ms >= C.SKILL_REGEN_STEP_MS:
                        _skill_regen_timer_ms -= C.SKILL_REGEN_STEP_MS
                        _skill_regen_acc += regen_rate
                        while _skill_regen_acc >= 1.0:
                                _skill_regen_acc -= 1.0
                                energy = mini(max_energy, energy + 1)

        # RELIC (Task 21) — VESTE DELL'ARCIMAGO (rigenerazione): 1 energia
        # ogni regen_ms FINCHE' l'energia manca; ogni rigenerazione consuma
        # una carica (12 in tutto), poi l'armatura si rompe. A energia
        # piena il timer resta fermo (nessuno spreco).
        if armor_kind() == "regen" and energy < max_energy:
                _armor_regen_timer_ms += delta_ms
                if _armor_regen_timer_ms >= float(armor_relic.get("regen_ms", 5000)):
                        _armor_regen_timer_ms = 0.0
                        energy = mini(max_energy, energy + 1)
                        armor_relic["charges"] = armor_charges() - 1
                        if armor_charges() <= 0:
                                _break_relic_armor()
        # RELIC (Task 21): decadimento del visual del fendente in mischia.
        if melee_fx_timer_ms > 0:
                melee_fx_timer_ms = maxi(0, melee_fx_timer_ms - int(delta_ms))

        # FIX (pozione magica): gestione della modalità fantasma.
        if _ghost_exiting:
                # Uscita di sicurezza dal muro: scivola verso il centro della
                # cella libera più vicina (input ignorato, nessuna collisione).
                var exit_speed: float = 6.0 * (float(delta_ms) / 16.6667)
                position = position.move_toward(_ghost_exit_target, exit_speed)
                dx = 0
                dy = 0
                if position.distance_to(_ghost_exit_target) < 0.5:
                        position = _ghost_exit_target
                        _ghost_exiting = false
                        _ghost_exit_target = Vector2.INF
                        ghost_mode = false
                _update_sprite()
                # FIX (martello di Thor): sync dello sprite in mano.
                _update_hammer_sprite()
                _update_freeze_scroll_sprite()
                queue_redraw()
                return
        ghost_timer_ms = _tick_timer_ms(ghost_timer_ms, delta_ms)
        if ghost_mode and ghost_timer_ms <= 0:
                _end_ghost_mode(maze)

        # TASK 30 (hazard): trattenuto da ganasce o muro di roccia chiuso —
        # niente movimento per tutto il frame (i timer continuano a scorrere:
        # la tenuta scade anche stando fermi, il mash di salto/sparo la
        # accorcia). Sparare resta possibile (disarma altre ganasce).
        if held_by_trap or held_by_wall:
                dx = 0
                dy = 0

        # Effective speed: base 2, +1 if any boost active (permanent or temp).
        var boosted: bool = permanent_speed_boost or speed_boost_timer > 0
        var effective_speed: int = speed + 1 if boosted else speed
        # TASK 30 (sabbie mobili): il fattore hazard_slow (0.5 sulle sabbie,
        # imposto dal MazeHazards) scala la velocita' di marcia. Solo gli
        # STIVALI ALATI (boost permanente) lo annullano: anche il MazeHazards
        # lo azzera per chi li calza, quindi qui e' doppia sicurezza. Il
        # boost TEMPORANEO post-salto NON protegge: si corre comunque nella
        # sabbia (spec: solo gli stivali). Salto e ghost sono gestiti dal
        # MazeHazards (slow=1 mentre si e' a mezz'aria/evanescenti).
        var move_speed: float = float(effective_speed) * get_speed_mult()
        if not permanent_speed_boost:
                move_speed *= hazard_slow

        if free_movement:
                # --- Boss-room mode: free pixel movement ---
                if next_dx != 0 or next_dy != 0:
                        dx = next_dx
                        dy = next_dy
                        last_dx = dx
                        last_dy = dy
                        next_dx = 0
                        next_dy = 0
                else:
                        # No input pressed -> stop immediately (fix: prevent drift).
                        dx = 0
                        dy = 0
                position.x += dx * move_speed
                position.y += dy * move_speed
                # Clamp to screen bounds (16 px margin so half the sprite stays visible).
                position.x = clamp(position.x, 16, WINDOW_WIDTH - 16)
                position.y = clamp(position.y, UI_HEIGHT + 16, WINDOW_HEIGHT - 16)
                # TASK 50 (muri-labirinto in boss room): il player si muove
                # TRA i frammenti di muraglia — i muri in piedi BLOCCANO il
                # movimento, con scivolamento sull'asse libero (mai incastro).
                _collide_arena_ruins()
        else:
                # --- Maze mode: snap-to-grid ---
                # FIX (line 245-247): if no direction pressed, stop IMMEDIATELY.
                if next_dx == 0 and next_dy == 0:
                        dx = 0
                        dy = 0

                var col := int(position.x / TILE_SIZE)
                var row := int((position.y - UI_HEIGHT) / TILE_SIZE)
                var center_x: float = col * TILE_SIZE + TILE_SIZE / 2.0
                var center_y: float = row * TILE_SIZE + TILE_SIZE / 2.0 + UI_HEIGHT

                # FIX (line 261-268): if idle and a new direction is pressed, align
                # to the current cell centre BEFORE try_move so the wall check uses
                # the correct cell (otherwise the player could clip through walls).
                if dx == 0 and dy == 0 and (next_dx != 0 or next_dy != 0):
                        position.x = center_x
                        position.y = center_y
                        try_move(next_dx, next_dy, maze)
                        next_dx = 0
                        next_dy = 0

                # When close enough to the cell centre, snap and try to turn.
                if absf(position.x - center_x) < effective_speed \
                                and absf(position.y - center_y) < effective_speed:
                        position.x = center_x
                        position.y = center_y
                        if next_dx != 0 or next_dy != 0:
                                try_move(next_dx, next_dy, maze)
                                next_dx = 0
                                next_dy = 0
                        # FIX (line 278-281): if a wall is now ahead, stop.
                        # FIX (pozione magica): in modalità fantasma il muro
                        # non ferma il player (attraversa).
                        if dx != 0 or dy != 0:
                                if not ghost_mode and maze.is_wall(col + dx, row + dy):
                                        dx = 0
                                        dy = 0
                # FIX (pozione magica): limite dello schermo sempre attivo
                # anche da fantasma (mai uscire dall'area di gioco). Durante
                # il fantasma i muri NON bloccano, i bordi sì.
                position.x += dx * move_speed
                position.y += dy * move_speed
                if ghost_mode:
                        var ghost_margin: float = 8.0
                        # FIX (tunnel Pac-Man): dentro le gallerie il clamp NON
                        # si applica — altrimenti il player-fantasma resterebbe
                        # bloccato all'imbocco senza raggiungere mai la soglia
                        # di wrap (il clamp gli impediva di superare il bordo).
                        # Fuori dalle gallerie il comportamento e' invariato.
                        if not GameConstants.is_tunnel_cell(
                                        int(position.x / TILE_SIZE),
                                        int((position.y - UI_HEIGHT) / TILE_SIZE)):
                                position.x = clamp(position.x, ghost_margin,
                                        float(WINDOW_WIDTH) - ghost_margin)
                                position.y = clamp(position.y, UI_HEIGHT + ghost_margin,
                                        float(WINDOW_HEIGHT) - ghost_margin)
                # FIX (meccanica tunnel "Pac-Man"): chi supera il bordo del
                # labirinto DENTRO una galleria riemerge dal lato opposto
                # mantenendo direzione e coordinata trasversale (es. entra
                # nella galleria in alto e riappare in basso, già in marcia
                # verso l'interno). I muri di bordo bloccano ovunque altrove,
                # quindi il wrap puo' scattare SOLO attraverso le 4 gallerie.
                var wrapped_pos: Vector2 = GameConstants.tunnel_wrap(position)
                if wrapped_pos != position:
                        position = wrapped_pos

                # Cell pickups: treasure (10000 pts + sparkle particles) or weapon.
                var cell_type: int = maze.get_cell_type(col, row)
                if cell_type == CELL_TREASURE:
                        maze.collect_treasure(col, row)
                        # TASK 97: 10000 -> C.TREASURE_CELL_POINTS (150)
                        add_score(C.TREASURE_CELL_POINTS)
                        # Particle emission is left to the Game node (it owns particles).
                elif cell_type == CELL_WEAPON:
                        # FIX (salto sopra armi): non raccogliere armi durante il salto
                        if not is_jumping():
                                var w: Dictionary = maze.collect_weapon(col, row)
                                collect_weapon(w)
                                picked_weapon_this_frame = true

        # 5) Projectile advance: 8 px/frame, killed by walls (maze mode) or
        # out-of-bounds (always).
        # RELIC (Task 21): le BOMBE dell'Alchimista sono proiettili "lob":
        # dopo lob_px percorsi (o contro un muro) esplodono — restano nell'
        # array con active=false + exploded=true finche' il CONTROLLER non
        # consuma l'esplosione (danno ad area) e le rimuove.
        var alive: Array[Dictionary] = []
        for p in projectiles:
                if not p.active and not p.get("exploded", false):
                        continue
                if not free_movement:
                        var p_col := int(p.pos.x / TILE_SIZE)
                        var p_row := int((p.pos.y - UI_HEIGHT) / TILE_SIZE)
                        if maze.is_wall(p_col, p_row):
                                p.active = false
                                if p.has("lob_px"):
                                        p["exploded"] = true  # bomba: esplode sul muro
                                continue
                # TASK 39 (Cannone d'Assedio): velocita' per-proiettile — la
                # palla di cannone viaggia piu' lenta (pesante) delle pallottole.
                var step_px: float = float(p.get("speed_px", 8.0))
                p.pos.x += p.dir.x * step_px
                p.pos.y += p.dir.y * step_px
                if p.has("lob_px"):
                        p["traveled"] = float(p.get("traveled", 0.0)) + 8.0
                        if float(p["traveled"]) >= float(p["lob_px"]):
                                p.active = false
                                p["exploded"] = true
                                alive.append(p)
                                continue
                if p.pos.x < 0 or p.pos.x > WINDOW_WIDTH \
                                or p.pos.y < UI_HEIGHT or p.pos.y > WINDOW_HEIGHT:
                        p.active = false
                        if p.has("lob_px") and not p.get("exploded", false):
                                p["exploded"] = true  # esplode anche al bordo
                                alive.append(p)
                        continue
                alive.append(p)
        projectiles = alive

        # Apply sprite flip + jump offset for rendering.
        _update_sprite()
        # FIX (martello di Thor): sync dello sprite in mano (posizione/lato
        # rispetto al facing del player + bagliore elettrico).
        _update_hammer_sprite()
        _update_freeze_scroll_sprite()
        # Trigger redraw so projectiles/aura/muzzle flash update visually.
        queue_redraw()


# ===========================================================================
# Shooting
# ===========================================================================

# shoot(): fire one projectile in the current direction. If idle, uses the
# last non-zero direction; if even that is zero (corner case), fires right.
# Consumes 1 ammo and triggers a short attack animation.
# Mirrors Player::shoot() line 323-354.
func shoot() -> void:
        # FUOCO AMICO (Task 18): il player morto-in-attesa-anima non spara.
        if soul_pending:
                return
        # TASK 30 (hazard): sparare mentre si e' trattenuti conta come mash
        # (il proiettile parte comunque e puo' disarmare altre ganasce).
        input_mash_count += 1
        if current_weapon.ammo <= 0:
                return

        var shoot_dx: int = dx if dx != 0 else last_dx
        var shoot_dy: int = dy if dy != 0 else last_dy
        if shoot_dx == 0 and shoot_dy == 0:
                shoot_dx = 1  # fallback: fire right

        # RELIC (Task 21): le reliquie hanno il loro ramo di fuoco.
        var rdef: Dictionary = GameConstants.get_relic_def(int(current_weapon.get("type", 0)))
        if not rdef.is_empty() and int(current_weapon.get("type", 0)) != GameConstants.RelicType.REFLECT_BOLT:
                _fire_relic(rdef, shoot_dx, shoot_dy)
                return

        # TASK 39 (Cannone d'Assedio): palla di cannone PESANTE — piu' lenta
        # (6 px/frame contro 8), potenza potente e flag "siege" che il
        # BossRoomController usa per danno %HP + esplosione d'impatto.
        if int(current_weapon.get("type", 0)) == WeaponType.SIEGE \
                        and not current_weapon.has("relic"):
                var siege_pos: Vector2
                if shoot_dx != 0:
                        siege_pos = Vector2(position.x + float(shoot_dx) * 26.0,
                                                    position.y - 10.0)
                else:
                        siege_pos = Vector2(position.x + 4.0,
                                                    position.y - 10.0 + float(shoot_dy) * 20.0)
                projectiles.append({
                        "pos": siege_pos,
                        "dir": Vector2(float(shoot_dx), float(shoot_dy)),
                        "power": current_weapon.power,
                        "active": true,
                        "type": WeaponType.SIEGE,
                        "speed_px": 6.0,
                        "siege": true,
                })
                current_weapon.ammo -= 1
                _after_player_shot_fired()
                shoot_anim_timer = 300
                # TASK 82: vampa del cannone (bianco-oro + fumo) alla volata.
                _begin_muzzle_flash(shoot_dx, shoot_dy, "cannon",
                                Color(1.0, 0.80, 0.30))
                if AudioManager:
                        AudioManager.play_sound(AudioManager.SoundType.SIEGE_FIRE)
                return

        # Spawn position: muzzle end of the weapon (gun barrel).
        # Horizontal shots fire from +20 px on the axis; vertical shots from
        # a slightly offset position (weapon held to the right of the body).
        var shoot_pos: Vector2
        if shoot_dx != 0:
                shoot_pos = Vector2(position.x + float(shoot_dx) * 20.0,
                                            position.y - 12.0)
        else:
                shoot_pos = Vector2(position.x + 4.0,
                                            position.y - 12.0 + float(shoot_dy) * 16.0)

        # FIX (crash 'power' missing — visto nel test fire_rearm): alcune
        # armi (elementali Task 61 / reliquie) non hanno la chiave "power"
        # nel dict; accesso difensivo con default invece di .power diretto.
        projectiles.append({
                "pos": shoot_pos,
                "dir": Vector2(float(shoot_dx), float(shoot_dy)),
                "power": int(current_weapon.get("power", 1)),
                "active": true,
                "type": int(current_weapon.get("type", 0)),
        })
        current_weapon.ammo -= 1
        _after_player_shot_fired()
        # Trigger attack animation for ~300 ms (6 frames at 50 ms).
        shoot_anim_timer = 300
        # TASK 82 — LAMPO DI VOLATA per arma da fuoco: stile+colore dedicati
        # (pistol scintilla, shotgun cono ampio, rocket vampata, laser energia;
        # REFLECT_BOLT e le armi senza ramo dedicato usano l'arcano colorato).
        var w_type: int = int(current_weapon.get("type", 0))
        match w_type:
                WeaponType.SHOTGUN:
                        _begin_muzzle_flash(shoot_dx, shoot_dy, "wide",
                                        Color(1.0, 0.50, 0.20))
                WeaponType.ROCKET:
                        _begin_muzzle_flash(shoot_dx, shoot_dy, "blast",
                                        Color(1.0, 0.45, 0.12))
                WeaponType.LASER:
                        _begin_muzzle_flash(shoot_dx, shoot_dy, "energy",
                                        Color(0.45, 1.00, 0.62))
                _:
                        # PISTOL e reliquie a percorso proiettile (es. riflesso):
                        # se c'e' una def reliquia col colore, la usiamo (arcano).
                        var rd: Dictionary = GameConstants.get_relic_def(w_type)
                        if not rd.is_empty() and rd.has("color"):
                                _begin_muzzle_flash(shoot_dx, shoot_dy, "arcane",
                                                rd["color"])
                        else:
                                _begin_muzzle_flash(shoot_dx, shoot_dy, "fire",
                                                Color(1.0, 0.62, 0.18))


# ----------------------------------------------------------------------------
# TASK 82 — LAMPO DI VOLATA (muzzle flash).
# ----------------------------------------------------------------------------
## Registra lo sparo appena avvenuto: salva posizione della volata (punta
## dell'arma in mano), direzione del colpo, stile e colore. Il disegno vero
## e proprio avviene in _draw_muzzle_flash() finche' _muzzle_timer_ms > 0.
func _begin_muzzle_flash(shoot_dx: int, shoot_dy: int, style: String,
                col: Color) -> void:
        var dir: Vector2 = Vector2(float(shoot_dx), float(shoot_dy))
        if dir == Vector2.ZERO:
                dir = Vector2(1.0, 0.0)
        var aim: Vector2 = dir.normalized()
        var w_type: int = int(current_weapon.get("type", 0))
        # Le reliquia a distanza ruotano col mira (_draw_relic_png_in_hand):
        # la volata sta lungo la mira, poco oltre la punta (~46 px dalla mano).
        var is_ranged_relic: bool = GameConstants.is_relic_weapon(w_type) \
                        and w_type != GameConstants.RelicType.REFLECT_BOLT
        var tip: Vector2
        if is_ranged_relic:
                var hand: Vector2 = Vector2(10.0, -6.0 - jump_offset)
                tip = hand + aim * 46.0
        elif dir.x != 0.0:
                # Arma da fuoco orizzontale: volata = punta dell'arma in mano.
                tip = Vector2(_weapon_tip_dist_px() * (1.0 if dir.x > 0.0 else -1.0),
                                -5.0 - jump_offset)
        else:
                # Sparo verticale con arma da fuoco: il lampo accompagna
                # l'uscita del proiettile (l'arma resta impugnata di fianco).
                tip = Vector2(6.0, -8.0 - jump_offset + aim.y * 20.0)
        _muzzle_pos = tip
        _muzzle_dir = aim
        _muzzle_style = style
        _muzzle_color = col
        _muzzle_timer_ms = MUZZLE_FLASH_MS


## Distanza della volata dal centro del player lungo il facing, allineata al
## render dell'arma in mano: PNG PixelLab (grip a +22, punta a +0.8*disp_len)
## oppure fallback procedurale (muzzle/emettitore a 15-24 px).
func _weapon_tip_dist_px() -> float:
        var png: bool = EnvironmentArt != null \
                        and EnvironmentArt.get_weapon_pickup_texture(
                                        int(current_weapon.get("type", 0))) != null
        match int(current_weapon.get("type", 0)):
                WeaponType.PISTOL:
                        return 56.0 if png else 24.0
                WeaponType.SHOTGUN:
                        return 75.0 if png else 20.0
                WeaponType.ROCKET:
                        return 68.0 if png else 17.0
                WeaponType.LASER:
                        return 67.0 if png else 15.0
                WeaponType.SIEGE:
                        return 30.0
                _:
                        return 24.0


## Luce di sparo (TASK 82): UN solo PointLight2D riusato per player — si
## accende per la durata del lampo e si spegne (mai create/destroy a colpo,
## zero churn di nodi). Segue il flag master delle luci (LANTERN_LIGHT_ENABLED)
## cosi' i test perf e le configurazioni senza luci restano invariate.
func _update_muzzle_light() -> void:
        if not MUZZLE_LIGHT_ENABLED:
                return
        if _muzzle_timer_ms <= 0:
                if _muzzle_light != null and _muzzle_light.visible:
                        _muzzle_light.visible = false
                return
        if not GameConstants.LANTERN_LIGHT_ENABLED:
                return
        if _muzzle_light == null:
                if EffectsManager == null:
                        return
                _muzzle_light = EffectsManager.create_light(
                                _muzzle_pos, _muzzle_color,
                                1.0, MUZZLE_LIGHT_RADIUS)
                add_child(_muzzle_light)
        var t: float = float(_muzzle_timer_ms) / float(MUZZLE_FLASH_MS)
        _muzzle_light.position = _muzzle_pos
        _muzzle_light.color = Color(
                        clampf(_muzzle_color.r + 0.25, 0.0, 1.0),
                        clampf(_muzzle_color.g + 0.25, 0.0, 1.0),
                        clampf(_muzzle_color.b + 0.25, 0.0, 1.0), 1.0)
        _muzzle_light.energy = 0.35 + 1.15 * t  # picco al colpo, poi cala
        _muzzle_light.visible = true


# ----------------------------------------------------------------------------
# RELIC (Task 21): fuoco delle armi reliquia.
# MISCHIA: niente proiettile — alza melee_pending (il controller applica il
# danno ad area) + visual del fendente. DISTANZA: proiettili con flag di
# comportamento (pierce/homing/fan/chain/lob). I colpi NON si consumano in
# boss room (relic_infinite_shots); a 0 l'arma SI ROMPE -> PISTOL.
# ----------------------------------------------------------------------------
func _fire_relic(rdef: Dictionary, shoot_dx: int, shoot_dy: int) -> void:
        var base_dir: Vector2 = Vector2(float(shoot_dx), float(shoot_dy))
        var is_melee: bool = str(rdef.get("family", "")) == "mischia"

        if is_melee:
                # Fendente: flag one-shot per il controller + visual arco.
                melee_pending = true
                melee_pending_def = rdef
                melee_fx_timer_ms = MELEE_FX_DURATION_MS
                melee_fx_def = rdef
                melee_fx_dir = base_dir
                if AudioManager:
                        AudioManager.play_sound(AudioManager.SoundType.MELEE_SWING)
        else:
                var shoot_pos: Vector2
                if shoot_dx != 0:
                        shoot_pos = Vector2(position.x + float(shoot_dx) * 20.0,
                                                    position.y - 12.0)
                else:
                        shoot_pos = Vector2(position.x + 4.0,
                                                    position.y - 12.0 + float(shoot_dy) * 16.0)
                var proj_type: int = int(rdef.get("type", 0))
                var fan_n: int = int(rdef.get("fan", 1))
                if fan_n > 1:
                        # Pugnali Gemelli: ventaglio di 3 lame (± spread).
                        var spread: float = deg_to_rad(float(rdef.get("fan_spread_deg", 18.0)))
                        for i in fan_n:
                                var t: float = float(i) / float(fan_n - 1) - 0.5  # -0.5..0.5
                                var d: Vector2 = base_dir.rotated(t * 2.0 * spread)
                                projectiles.append(_make_relic_projectile(
                                                shoot_pos, d, rdef, proj_type))
                else:
                        projectiles.append(_make_relic_projectile(
                                        shoot_pos, base_dir, rdef, proj_type))

        # Consumo colpi (in boss room: infiniti, come le munizioni potenziate).
        if not relic_infinite_shots:
                current_weapon.ammo -= 1
        _after_player_shot_fired()
        shoot_anim_timer = 300
        # TASK 82 — LAMPO DI VOLATA ELEMENTALE: alla punta dell'arma (che
        # ruota con la mira) appare un lampo colorato col TEMA dell'arma:
        # lingua di fiamma per le armi che incendiano (burn_ms), scintillio
        # di brina per quelle che congelano (freeze), impulso arcano per le
        # altre (lame/rozzi/dardi). Le reliquia da MISCHIA non sparano: il
        # fendente ha gia' il suo visual dedicato.
        if not is_melee:
                var m_style: String = "arcane"
                if rdef.has("burn_ms"):
                        m_style = "flame"
                elif bool(rdef.get("freeze", false)):
                        m_style = "frost"
                _begin_muzzle_flash(shoot_dx, shoot_dy, m_style,
                                rdef.get("color", Color(1.0, 0.62, 0.18)))
        # COLPI ESAURITI: la reliquia SI ROMPE e si torna alla PISTOL
        # (richiesta utente: "le armi quando finiscono i colpi spariscono").
        if int(current_weapon.get("ammo", 0)) <= 0 and not relic_infinite_shots:
                current_weapon = _make_weapon(WeaponType.PISTOL)
                melee_pending = false
                if AudioManager:
                        AudioManager.play_sound(AudioManager.SoundType.RELIC_BREAK)


## Costruisce il Dictionary-proiettile di una reliquia a distanza, con le
## flag di comportamento che il controller legge (pattern fuoco amico).
func _make_relic_projectile(from: Vector2, dir: Vector2, rdef: Dictionary,
                proj_type: int) -> Dictionary:
        var p: Dictionary = {
                "pos": from,
                "dir": dir,
                "power": int(rdef.get("power", 1)),
                "active": true,
                "type": proj_type,
                "relic": str(rdef.get("id", "")),
        }
        if rdef.has("pierce_max"):
                p["pierce_left"] = int(rdef["pierce_max"])
                p["hit_ids"] = []  # nemici gia' colpiti da QUESTO dardo
        if bool(rdef.get("homing", false)):
                p["homing"] = true
        if rdef.has("chain"):
                p["chain"] = int(rdef["chain"])
                p["chain_radius_px"] = float(rdef.get("chain_radius_px", 128.0))
        if rdef.has("lob_px"):
                p["lob_px"] = float(rdef["lob_px"])
                p["traveled"] = 0.0
                p["radius_px"] = float(rdef.get("radius_px", 96.0))
        return p


## Contabilita' post-colpo: Corazza del Furore (30 colpi poi si spegne).
func _after_player_shot_fired() -> void:
        if armor_kind() == "fury":
                _tick_fury_shot()


# ===========================================================================
# Damage / lives
# ===========================================================================

# take_damage(): applies 1 point of energy damage if NOT invulnerable and
# NOT jumping. On 0 energy, lose a life, restore energy, and respawn.
# Mirrors Player::takeDamage() line 364-374.
func take_damage() -> void:
        # FUOCO AMICO (Task 18): il corpo accasciato in attesa dell'anima è
        # già morto ai fini del gameplay: invulnerabile a ogni fonte di danno.
        if soul_pending:
                return
        if is_jumping() or is_invulnerable():
                return
        # RELIC (Task 21) — CORAZZA D'ORO: il colpo viene assorbito dalla
        # riserva (una carica per tocco/proiettile); l'energia NON cala.
        if _try_absorb_with_golden_armor():
                return
        energy -= 1
        damage_timer = 1000  # ~1 s of invulnerability after hit
        # Effetti Godot-native: screen shake + particelle danno
        if EffectsManager:
                EffectsManager.screen_shake(6.0, 0.25)
                var p := EffectsManager.spawn_sparks(get_pixel_pos(), 10)
                if get_parent():
                        get_parent().add_child(p)
        if energy <= 0:
                lives -= 1
                # RELIC (Task 21): alla morte si perdono arma reliquia e
                # armatura (decisione utente) PRIMA del respawn.
                lose_relics_on_death()
                energy = max_energy
                # TASK 87: animazione di morte — il corpo si accascia al
                # pavimento con un gemito di sofferenza; il respawn avviene
                # alla fine dell'effetto (controller -> respawn_after_soul).
                begin_collapse()


# take_hazard_damage(dmg): TASK 30 — danno AMBIENTALE del labirinto
# (ganasce, muro di roccia che si chiude). Differenze da take_damage():
#   * scala PIU' punti energia in un colpo solo (33%/66% del massimo,
#     calcolati dal MazeHazards);
#   * BYPASSA la Corazza d'Oro (decisione utente: le cariche armatura
#     valgono per il combattimento, il dungeon colpisce a prescindere);
#   * calice invincibile, salto in corso e invulnerabilita' post-colpo
#     (damage_timer) proteggono come per qualunque altro danno.
# A energia esaurita: vita persa, reliquie perse, respawn (pattern della
# morte standard).
# TASK 81 (correzione utente — braccia zombie): `unblockable = true` ignora
# ANCHE il salto (spec: "Il player non può schivare le braccia ma solo
# attendere le vengano ritratte"). Le invulnerabilita' (post-colpo/calice/
# spawn guard) restano valide in ogni caso: "20% ad ogni tocco" = cadenza
# del damage_timer ~1s.
func take_hazard_damage(dmg: int, unblockable: bool = false) -> void:
        if soul_pending:
                return
        # GHOST (pozione): il fantasma fluttua sopra ogni pericolo (spec
        # Task 30) — niente danni ambientali.
        if ghost_mode:
                return
        if is_invulnerable():
                return
        if not unblockable and is_jumping():
                return
        energy -= dmg
        damage_timer = 1000
        if EffectsManager:
                EffectsManager.screen_shake(6.0, 0.25)
                var p := EffectsManager.spawn_sparks(get_pixel_pos(), 10)
                if get_parent():
                        get_parent().add_child(p)
        if energy <= 0:
                lives -= 1
                lose_relics_on_death()
                energy = max_energy
                # TASK 87: collasso a terra con gemito (v. take_damage).
                begin_collapse()


# fall_into_chasm(): TASK 30 — il player e' caduto nella voragine aperta:
# perde una vita (reliquie incluse, e' una morte) e respawna alla cella
# di partenza. Il salto e la ghost mode rendono immuni (il MazeHazards
# chiama questa funzione solo per player grounded sulla cella aperta).
func fall_into_chasm() -> void:
        if soul_pending:
                return
        lives -= 1
        lose_relics_on_death()
        energy = max_energy
        damage_timer = 0
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.LOSE_LIFE)
        # TASK 87: gemito di sofferenza anche nella caduta: il corpo si
        # accascia sul bordo della voragine e sfuma dentro il buco.
        begin_collapse()


# ===========================================================================
# FUOCO AMICO (Task 18) — morte per colpo del compagno + rinascita
# ===========================================================================

# begin_collapse(): TASK 87 — morte normale (energia finita): congela il
# player come il fuoco amico (kill_by_friendly_fire) MA senza anima: il
# controller avvia PlayerCollapseEffect (il corpo si accascia al pavimento
# con gemito di sofferenza) e al `finished` chiama respawn_after_soul()
# (vite residue) o sblocca il player per il flusso continue (morte finale).
# Riusa volutamente i gate di soul_pending: niente input, niente danni,
# niente rendering del player, non e' un bersaglio (boss/lanterne/FF).
func begin_collapse() -> void:
        soul_pending = true
        collapse_requested = true
        set_direction(0, 0)
        dx = 0
        dy = 0
        projectiles.clear()
        if sprite != null:
                _pre_soul_sprite_visible = sprite.visible
                sprite.visible = false
        if weapon_sprite != null:
                _pre_soul_weapon_visible = weapon_sprite.visible
                weapon_sprite.visible = false
        _end_ghost_mode_now()


# kill_by_friendly_fire(): il colpo fatale arriva dal PROIETTILE del
# compagno (MainGameController._check_friendly_fire_projectiles quando
# energy == 1). Replica il ramo morte di take_damage (vita persa, energia
# ripristinata) MA differisce il respawn: il player resta congelato e
# invisibile finché la sua anima non raggiunge il vincitore
# (SoulTransferEffect -> soul_delivered -> respawn_after_soul).
func kill_by_friendly_fire() -> void:
        lives -= 1
        energy = max_energy
        damage_timer = 0
        # RELIC (Task 21): la vittima perde reliquia e armatura (morte).
        lose_relics_on_death()
        # Congela: nessun input, nessun danno, nessun rendering del player.
        soul_pending = true
        set_direction(0, 0)
        dx = 0
        dy = 0
        # I proiettili in volo si dissolvono con la morte.
        projectiles.clear()
        # Il corpo accasciato lo disegna l'effetto: nascondiamo gli sprite
        # del player (salvando lo stato per il ripristino al respawn).
        if sprite != null:
                _pre_soul_sprite_visible = sprite.visible
                sprite.visible = false
        if weapon_sprite != null:
                _pre_soul_weapon_visible = weapon_sprite.visible
                weapon_sprite.visible = false
        # FIX (pozione magica): se la vittima era in modalità fantasma, la
        # chiudiamo subito (l'anima è già tutto ciò che resta di evanescente).
        _end_ghost_mode_now()


# respawn_after_soul(): l'anima è stata assorbita dal vincitore — la
# vittima rinviene e respawna con la posizione/timer standard
# (reset_position: cella di partenza, stamina piena, boost azzerati).
func respawn_after_soul() -> void:
        soul_pending = false
        if sprite != null:
                sprite.visible = _pre_soul_sprite_visible
        if weapon_sprite != null:
                weapon_sprite.visible = _pre_soul_weapon_visible
        reset_position()


# collect_weapon(w): replace the current weapon (old one discarded).
# `w` is expected to be a Dictionary {type: WeaponType, power: int, ammo: int}.
# RELIC (Task 21): le armi a terra NON sovrascrivono una reliquia
# equipaggiata (decisione utente: la reliquia si cambia SOLO nella
# schermata bonus o quando si rompe).
func collect_weapon(w: Dictionary) -> void:
        # NOTA: la chiave "relic" contiene una STRINGA — cast bool() vietato
        # (bool(String) non esiste come costruttore in GDScript).
        if current_weapon.has("relic") and not w.has("relic"):
                return  # arma base a terra ignorata: reliquia in mano
        # TASK 61 — un'arma ELEMENTALE a terra NON sovrascrive una reliquia
        # scelta nello schermo bonus (la scelta del player e' sacra): le
        # elementali del labirinto si scambiano solo tra loro (flag "ground"
        # impostata dallo spawn di make_random_weapon) o con le armi base.
        if current_weapon.has("relic") and w.has("relic") \
                        and not bool(current_weapon.get("ground", false)):
                return
        current_weapon = w.duplicate()
        # TASK 99 (Caricatore Esteso): ogni arma appena raccolta parte col
        # bonus colpi del perk (le reliquie restano intatte: la loro "ammo"
        # e' durabilita').
        _apply_magazine_bonus_to_weapon()


# add_score(points): add points and grant an extra life every 50k
# (TASK 97: EXTRA_LIFE_EVERY_POINTS, era 100k — la ricalibrazione ha
# ridotto il massimo cumulabile a ~200k per run completa).
func add_score(points: int) -> void:
        score += points
        if score >= next_life_threshold:
                lives += 1
                next_life_threshold += C.EXTRA_LIFE_EVERY_POINTS
        # TASK 99 (LEVEL UP): XP = punteggio. Ogni soglia superata = +1
        # punto abilità. Il while copre il salto di più soglie in un solo
        # colpo (es. premio del boss): il livello arriva subito a quello
        # definitivo ma la CELEBRAZIONE è una sola (pending_levelup_fx
        # accumula e il controller ne consuma una per volta).
        while level < C.LEVELUP_MAX_LEVEL \
                        and score >= C.levelup_threshold(level + 1):
                level += 1
                skill_points += 1
                pending_levelup_fx += 1


# add_life(): bonus life (reward after defeating a boss).
func add_life() -> void:
        lives += 1


# ===========================================================================
# TASK 99 (LEVEL UP): accessor del motore XP.
# ===========================================================================
func get_level() -> int:
        return level


func get_skill_points() -> int:
        return skill_points


## Ritorna (e azzera) il numero di level up maturati e NON ancora annunciati:
# il controller lo chiama quando fa partire la celebrazione.
func consume_pending_levelup_fx() -> int:
        var gained: int = pending_levelup_fx
        pending_levelup_fx = 0
        return gained


# ===========================================================================
# TASK 99 FASE 2 — LE OTTO ABILITÀ: effetti e conferma
# ===========================================================================
func get_skill_level(skill_id: String) -> int:
        return int(skill_levels.get(skill_id, 0))


# --- Energia Vitale: +5%/livello su base 5 (unità discrete) ---------------
## Unità di energia extra dal perk: ceil(0.05 x livello x 5) — il PRIMO
## acquisto vale subito +1 unità (~+20% reale sul primo), a cap 10 sono +3
## (5 -> 8, +60%: leggermente sopra il +50% del report per l'arrotondamento
## per eccesso delle unità discrete).
func _perk_energy_bonus_units() -> int:
        var lvl: int = get_skill_level("energy")
        if lvl <= 0:
                return 0
        return int(ceil(0.05 * float(lvl) * 5.0))


# --- Resistenza: +7% max, -5% attesa per livello --------------------------
func get_stamina_max() -> float:
        return 1.0 + 0.07 * float(get_skill_level("stamina"))


func get_stamina_recharge_mult() -> float:
        return 1.0 + 0.05 * float(get_skill_level("stamina"))


# --- Rapidità: +4%/livello ------------------------------------------------
func get_speed_mult() -> float:
        return 1.0 + 0.04 * float(get_skill_level("swiftness"))


# --- Potenza di Fuoco: +5%/livello ----------------------------------------
func get_damage_mult() -> float:
        return 1.0 + 0.05 * float(get_skill_level("firepower"))


# --- Caricatore Esteso: +1 colpo/livello ----------------------------------
func get_magazine_bonus() -> int:
        return get_skill_level("magazine")


# --- Fortuna del Cacciatore: +3%/livello di drop --------------------------
func get_luck_drop_chance() -> float:
        return 0.03 * float(get_skill_level("luck"))


# --- Rigenerazione: +0.2 energia ogni 5s per livello ---------------------
func get_regen_rate() -> float:
        return 0.2 * float(get_skill_level("regen"))


# --- Salto Aggiuntivo: +1 salto in aria per livello (richiede Stam 4) -----
func get_extra_air_jumps() -> int:
        return get_skill_level("jump")


## Applica il bonus caricatore all'arma CORRENTE (le reliquie usano ammo
## come durabilità: mai toccarle). La chiave "mag_bonus_applied" nel dict
## dell'arma traccia quanto bonus è già dentro, così le +/− multiple in
## sessione modale e i cambi arma restano coerenti.
func _apply_magazine_bonus_to_weapon() -> void:
        var w: Dictionary = current_weapon
        if w.is_empty() or w.has("relic"):
                return
        var bonus: int = get_magazine_bonus()
        var applied: int = int(w.get("mag_bonus_applied", 0))
        if bonus == applied:
                return
        w["ammo"] = maxi(0, int(w.get("ammo", 0)) + bonus - applied)
        w["mag_bonus_applied"] = bonus


## Conferma della modale abilità: `final_levels` è il dict COMPLETO
## id->livello dopo le assegnazioni (confermate = definitive). Ricalcola
## tutti gli effetti derivati con gain immediato (es. nuova energia massima
## si riempie subito delle unità appena guadagnate).
func confirm_skills(final_levels: Dictionary) -> void:
        skill_levels = {}
        for k in final_levels.keys():
                skill_levels[k] = int(final_levels[k])
        _recalc_skill_effects()


## Ripristino della progressione da snapshot (carry tra scene / sessione
## continue): identico a confirm_skills, esplicito per chi legge il call-site.
func restore_skills(skills: Dictionary) -> void:
        confirm_skills(skills)


## Ricalcola gli effetti derivati delle abilità (chiamato anche dopo
## carry/restore e quando l'armatura reliquia cambia il max energia base).
func _recalc_skill_effects() -> void:
        var new_max: int = 5 + _perk_energy_bonus_units()
        if has_relic_armor():
                new_max += ARMOR_ENERGY_BONUS
        if new_max != max_energy:
                var delta: int = new_max - max_energy
                max_energy = new_max
                if delta > 0:
                        energy = mini(max_energy, energy + delta)
                else:
                        energy = mini(energy, max_energy)
        _apply_magazine_bonus_to_weapon()


# ===========================================================================
# Jump
# ===========================================================================

# activate_jump(): start a jump if not already jumping.
# Mirrors Player::activateJump() line 138.
# FIX (salto + velocità): dopo il salto, il player ottiene speed_boost_timer
# di 1000ms (1 secondo) per potersi allontanare dai nemici. Questo mirrora
# il comportamento C++ del "jump over enemy" boost, ma applicato a ogni
# salto, non solo quando si salta sopra un nemico.
# FIX (stamina): il salto è consentito solo con stamina sufficiente (>= 1/2
# di barra) e se il player non è "stanco". Al 2° salto consecutivo la barra
# si svuota e scatta il blocco fino a ricarica completa. Il tentativo a
# vuoto produce un click secco (pulsante senza molla).
# Ritorna true se il salto è partito, false altrimenti (già in salto oppure
# senza stamina).
func activate_jump() -> bool:
        # FUOCO AMICO (Task 18): il player morto-in-attesa-anima non salta.
        if soul_pending:
                return false
        # TASK 30 (hazard): trattenuto da ganasce o muro di roccia chiuso —
        # il salto non parte, ma la PRESSIONE conta come mash per accorciare
        # la tenuta delle ganasce (input_mash_count e' consumato dal
        # MazeHazards a ogni frame).
        if held_by_trap or held_by_wall:
                input_mash_count += 1
                return false
        if jump_timer > 0:
                # TASK 99 (Salto Aggiuntivo): con l'abilità sbloccata si può
                # saltare ANCHE a mezz'aria, consumando uno dei salti extra;
                # il costo di stamina resta il gate fisico (per questo il
                # perk richiede Resistenza 4: serve barra oltre il secondo
                # salto per pagarselo).
                if _air_jumps_left > 0 and not stamina_exhausted \
                                and stamina >= STAMINA_JUMP_COST - 0.0001:
                        _air_jumps_left -= 1
                else:
                        return false  # già in salto, nessun salto extra
        else:
                # Salto da terra: ricarica la quota di salti a mezz'aria.
                _air_jumps_left = get_extra_air_jumps()
        # Gate di stamina: ci vuole almeno 1/2 barra per un salto.
        if stamina_exhausted or stamina < STAMINA_JUMP_COST - 0.0001:
                # Click "a vuoto": tenendo premuto il tasto di salto il
                # suono non si mitraglia (cooldown interno + debounce SFX).
                if _stamina_click_cd_ms <= 0.0:
                        _stamina_click_cd_ms = STAMINA_CLICK_COOLDOWN_MS
                        if AudioManager:
                                AudioManager.play_sound(AudioManager.SoundType.STAMINA_CLICK)
                return false
        stamina = maxf(0.0, stamina - STAMINA_JUMP_COST)
        _stamina_since_jump_ms = 0.0
        if stamina <= 0.0001:
                # barra vuota → player "stanco" (fino a ricarica completa).
                stamina_exhausted = true
        max_jump_time = 40
        jump_timer = max_jump_time
        # FIX: speed boost post-jump per sfuggire ai nemici.
        # 1000ms = 60 frame @ 60fps. effective_speed = speed+1 = 3.
        speed_boost_timer = 2000  # FIX: 2s di accelerazione dopo il salto
        return true


# is_jumping() -> bool — true mentre il player è in salto (invulnerabile).
func is_jumping() -> bool:
        return jump_timer > 0


# ===========================================================================
# FIX (stamina): accessor per la barra verde in HUD (1.0 = piena).
# TASK 99 (Resistenza): con barra massima > 1.0 il ratio è relativo alla
# CAPACITÀ CORRENTE (la HUD mostra "quanto è piena la barra che ho").
# ===========================================================================
func get_stamina_ratio() -> float:
        var cap: float = maxf(0.0001, get_stamina_max())
        return clampf(stamina / cap, 0.0, 1.0)


# FIX (stamina): true dopo il 2° salto consecutivo, finché la barra non si
# è ricaricata completamente (in HUD la barra lampeggia).
func is_stamina_exhausted() -> bool:
        return stamina_exhausted


# ===========================================================================
# Invulnerability / Chalice
# ===========================================================================

# is_invulnerable(): true if either post-hit invuln OR chalice invincibility
# is active. Mirrors Player::isInvulnerable() line 133.
# TASK 38: compresa la guardia di nascita/rinascita (3s di immortalita'
# con lampeggio dopo lo spawn).
func is_invulnerable() -> bool:
        return damage_timer > 0 or invincible_timer > 0 or spawn_guard_ms > 0


# set_invincible_timer(ms): total invulnerability duration from the
# Golden Chalice. While > 0 the player takes no damage from anything and
# enemies they touch start burning.
func set_invincible_timer(ms: int) -> void:
        invincible_timer = ms


# tick_invincible_timer(): called every frame from update_player().
# Decrements by ~16 ms (matching 60 FPS frame step).
func tick_invincible_timer() -> void:
        invincible_timer = _tick_timer(invincible_timer)


# ===========================================================================
# Speed boosts
# ===========================================================================

# set_jump_speed_boost(ms): temporary speed boost after jumping over an
# enemy (sliding-forward effect). Lasts ~1000 ms by default.
func set_jump_speed_boost(ms: int) -> void:
        speed_boost_timer = ms


# activate_speed_boost(): permanent speed boost from winged boots.
# Survives reset_position() but is cleared by reset() (full death).
# Mirrors Player::activateSpeedBoost() line 198.
func activate_speed_boost() -> void:
        permanent_speed_boost = true


# has_speed_boost(): true if EITHER the permanent or temporary boost is on.
func has_speed_boost() -> bool:
        return permanent_speed_boost or speed_boost_timer > 0


# ===========================================================================
# get_grid_pos / get_pixel_pos
# ===========================================================================

# Grid position (col, row) computed from current pixel position.
# Used by Enemy AI to target the player.
func get_grid_pos() -> Vector2i:
        return Vector2i(
                int(position.x / TILE_SIZE),
                int((position.y - UI_HEIGHT) / TILE_SIZE)
        )

func get_pixel_pos() -> Vector2:
        return position


# ===========================================================================
# Helpers
# ===========================================================================

# _tick_timer(): decrement a simulated-ms timer by 16, floored at 0.
# Matches the `if (t > 16) t -= 16; else t = 0;` idiom in Player.cpp.
static func _tick_timer(t: int) -> int:
        return t - 16 if t > 16 else 0


# FIX (calice durava meno di 15s): tick basato su delta_ms reale invece di
# 16ms fissi. Garantisce che i timer (invincible_timer, shoot_cooldown, etc.)
# durino il tempo reale specificato indipendentemente dal frame rate.
static func _tick_timer_ms(t: int, delta_ms: float) -> int:
        var new_t: int = t - int(delta_ms)
        return new_t if new_t > 0 else 0


# _make_weapon(t): factory mirroring Weapon::generate() in src/Weapon.cpp.
# Returns a Dictionary {type, power, ammo} matching the C++ struct Weapon.
static func _make_weapon(t: int) -> Dictionary:
        var power: int = 1
        var ammo: int = 15
        match t:
                WeaponType.PISTOL:
                        power = 1
                        ammo = 15
                WeaponType.SHOTGUN:
                        power = 3
                        ammo = 8
                WeaponType.LASER:
                        power = 2
                        ammo = 20
                WeaponType.ROCKET:
                        power = 5
                        ammo = 4
        return {"type": t, "power": power, "ammo": ammo}


# _get_player_tint(p_num): P1 = no tint (white), P2 = light blue.
# Mirrors getPlayerTint() line 59-66.
static func _get_player_tint(p_num: int) -> Color:
        if p_num == 2:
                return Color(0.784, 0.784, 1.0)  # (200, 200, 255)
        return Color.WHITE


# consume_picked_weapon(): one-shot flag for the Game to detect "weapon
# picked up this frame" and play the load SFX. Resets after consumption.
func consume_picked_weapon() -> bool:
        var v := picked_weapon_this_frame
        picked_weapon_this_frame = false
        return v


# ===========================================================================
# Sprite / flip handling
# ===========================================================================

# ===========================================================================
# FIX (pozione magica): modalità FANTASMA — API e uscita di sicurezza.
# ===========================================================================

# start_ghost_mode(duration_ms): attiva l'effetto pozione. Chiamato dal
# MainGameController quando il player raccoglie la pozione (dopo il suono
# di deglutizione). Durata default 5 secondi.
func start_ghost_mode(duration_ms: int = GHOST_MODE_DURATION_MS) -> void:
        ghost_mode = true
        ghost_timer_ms = duration_ms
        _ghost_exiting = false
        _ghost_exit_target = Vector2.INF


# is_ghost(): true mentre l'effetto pozione è attivo (il player è evanescente
# e attraversa i muri).
func is_ghost() -> bool:
        return ghost_mode


# _end_ghost_mode(maze): fine naturale dell'effetto. Se il player è in una
# cella percorribile, torna semplicemente solido. Se è DENTRO un muro, non
# resta intrappolato: scivola (ancora fantasma, senza collisioni) verso il
# centro della cella percorribile più vicina al punto in cui si trova —
# attraversando la pietra, esattamente come richiesto.
func _end_ghost_mode(maze: Object) -> void:
        # FIX (boss room): in boss room il controller passa maze=null (movimento
        # libero): nessun muro, il player torna solido subito.
        if maze == null:
                ghost_mode = false
                _ghost_exiting = false
                _ghost_exit_target = Vector2.INF
                return
        var col := int(position.x / TILE_SIZE)
        var row := int((position.y - UI_HEIGHT) / TILE_SIZE)
        var col_c := clampi(col, 0, MAZE_COLS - 1)
        var row_c := clampi(row, 0, MAZE_ROWS - 1)
        if not maze.is_wall(col_c, row_c):
                # Cellata libera: torna solido subito.
                ghost_mode = false
                return
        # Dentro un muro: trova la cella percorribile più vicina (anelli
        # crescenti attorno alla posizione corrente) e scivola verso il
        # suo centro restando fantasma finché non la raggiunge.
        var target := _find_nearest_open_cell(maze, col_c, row_c)
        _ghost_exit_target = Vector2(
                target.x * TILE_SIZE + TILE_SIZE / 2.0,
                target.y * TILE_SIZE + TILE_SIZE / 2.0 + UI_HEIGHT)
        _ghost_exiting = true


# _end_ghost_mode_now(): azzeramento immediato e totale dello stato fantasma
# (usato su reset/respawn/cambio livello — la posizione viene comunque
# reimpostata su una cella percorribile dal chiamante).
func _end_ghost_mode_now() -> void:
        ghost_mode = false
        ghost_timer_ms = 0
        _ghost_exiting = false
        _ghost_exit_target = Vector2.INF


# _find_nearest_open_cell(maze, col, row): ricerca ad anelli crescenti
# (raggio 1..8) della cella non-muro più vicina. Ritorna Vector2i; se non
# trova nulla (maze degenere), ritorna la cella di partenza.
func _find_nearest_open_cell(maze: Object, col: int, row: int) -> Vector2i:
        for radius in range(1, 9):
                for dc in range(-radius, radius + 1):
                        for dr in range(-radius, radius + 1):
                                # solo il bordo dell'anello
                                if absi(dc) != radius and absi(dr) != radius:
                                        continue
                                var nc: int = col + dc
                                var nr: int = row + dr
                                if nc < 0 or nc >= MAZE_COLS or nr < 0 or nr >= MAZE_ROWS:
                                        continue
                                if not maze.is_wall(nc, nr):
                                        return Vector2i(nc, nr)
        return Vector2i(col, row)


# _update_sprite(): applies the side-view flip + jump offset each frame.
# TASK 82: solo MAGE guarda nativamente a destra; gli altri 8 sheet v2
# (hero, heroine, orc, elf, knight, golem, dragon, vampire) guardano a
# SINISTRA e il flag SPRITE_DEFAULT_FACES_RIGHT lo registra.
#
# Behaviour (mirrors Player::render() line 432-443):
#   * last_dx > 0 -> no flip
#   * last_dx < 0 -> flip horizontally
#   * last_dx == 0 (idle / vertical movement) -> keep previous orientation
# The flip state persists across frames so a player who stops after moving
# left keeps facing left.
func _update_sprite() -> void:
        if sprite == null:
                return

        var default_right: bool = SPRITE_DEFAULT_FACES_RIGHT.get(
                character_type, true)

        # FIX (player donna si gira dal lato opposto): la logica precedente
        # era confusa con l'inversione per default_left. Logica corretta:
        #   * Lo sprite PNG ha un facing di default (right o left).
        #   * flip_h = true specchia orizzontalmente lo sprite.
        #   * Vogliamo che il player guardi verso last_dx:
        #     - se last_dx > 0 (muove a destra), l'output deve guardare a destra
        #     - se last_dx < 0 (muove a sinistra), l'output deve guardare a sinistra
        #   * Se default_right: l'output "guarda destra" quando flip_h=false,
        #     "guarda sinistra" quando flip_h=true. Quindi:
        #       flip_h = (last_dx < 0)
        #   * Se default_left (NOT default_right): l'output "guarda sinistra"
        #     quando flip_h=false, "guarda destra" quando flip_h=true. Quindi:
        #       flip_h = (last_dx > 0)
        # In entrambi i casi, quando last_dx == 0 mantieni l'ultima orientazione.
        if last_dx > 0:
                # Moving right
                _last_flipped = false if default_right else true
        elif last_dx < 0:
                # Moving left
                _last_flipped = true if default_right else false
        # else: keep _last_flipped from previous frame.

        sprite.flip_h = _last_flipped

        # --- Animation frame selection ---
        # FIX (player cambia aspetto quando cammina/salta): lo swap con le
        # walk/jump_sheet dedicate (AI calls separate, stile diverso dal main
        # sheet) cambiava aspetto/colore a metà ciclo. Il C++ (Player.cpp:
        # 432-443) NON swappava sheet per walk/jump: usava il main 4-frame
        # sheet per tutto, e applicava un arc Y sinusoidale per il salto
        # (lo stesso sprite che si alzava in aria). Modello attuale: main
        # sheet 4-frame per idle/walk/attack, jump = stessa sprite con
        # offset Y sin(progress*PI)*25 (TASK 69: asset dedicati rimossi).
        if is_jumping():
                # Jump: NON swappare texture. Usa frame 0 (idle) dello stesso
                # main sheet. L'offset Y (jump_offset) viene applicato sotto
                # per dare l'effetto "salto in aria" con il solito sprite.
                _apply_character_frame(0)
        elif shoot_anim_timer > 0:
                # Attack: use frame 3 (arm-up pose on main sheet) which reads
                # as an attack recoil. Same texture as walk/idle → no swap.
                _apply_character_frame(3)
        elif dx != 0 or dy != 0:
                # Walking: cycle frames 0-3 of the MAIN sheet at ~12 FPS
                # (FIX: era 130ms/frame = ~7.5fps, troppo lento → sembrava
                # statico. Ridotto a 80ms/frame = ~12.5fps, più visibile).
                var walk_frame: int = int(anim_time / 80.0) % 4
                _apply_character_frame(walk_frame)
        else:
                # Idle: frame 0 of the main sheet.
                _apply_character_frame(0)

        # Apply jump arc as a vertical offset (sprite only, not the Node2D).
        # In C++ the sprite is drawn at pos.y + 24 - jumpOffset; here we shift
        # the sprite by -jumpOffset relative to its anchor.
        # TASK 22: sprite.offset è in unità LOCALI (pre-scala): con la texture
        # XHD (scala 1/4) va compensato perché l'arco di salto resti identico
        # a schermo (jump_offset px reali).
        var off_scale: float = float(_frame_px) / 64.0
        sprite.offset = Vector2(0, -jump_offset * off_scale)

        # FIX (pozione magica): il player fantasma è EVANESCENTE — sprite
        # semitrasparente con tinta eterea ciano e pulsazione lenta. Quando
        # l'effetto finisce, il modulate torna al tint normale (P2 blu).
        if ghost_mode:
                var ghost_pulse: float = 0.46 + 0.14 * sin(float(anim_time) * 0.006)
                # Lampeggio d'avviso negli ultimi 1.2s (sta per finire)
                if ghost_timer_ms < 1200:
                        ghost_pulse = 0.35 + 0.35 * absf(sin(float(anim_time) * 0.012))
                sprite.modulate = Color(
                        tint.r * 0.7 + 0.3,
                        tint.g * 0.85 + 0.15,
                        tint.b * 0.9 + 0.1,
                        ghost_pulse)
        else:
                sprite.modulate = tint

        # TASK 38 (nascita/rinascita): durante la guardia di 3s il player
        # LAMPEGGIA. Si usa il modulate del NODO (propagato a TUTTI i figli
        # e al disegno proprio: carattere, arma in mano, martello, aurole e
        # proiettili pulsano insieme — il corpo intero lampeggia, non solo
        # lo sprite). La tinta P2 e lo stato fantasma restano intatti: si
        # agisce solo sul canale alpha del nodo.
        if spawn_guard_ms > 0:
                var blink_phase: float = fmod(float(spawn_guard_ms),
                                SPAWN_GUARD_BLINK_MS)
                if blink_phase < SPAWN_GUARD_BLINK_MS * 0.6:
                        modulate = Color(1.0, 1.0, 1.0, 1.0)
                else:
                        modulate = Color(1.0, 1.0, 1.0, 0.15)
        else:
                modulate = Color(1.0, 1.0, 1.0, 1.0)


# ===========================================================================
# _draw(): render projectiles fired by this player.
# Projectiles are stored in the `projectiles` Array[Dictionary].
# Each projectile dict has: pos, dir, power, active, type.
# ===========================================================================
func _draw() -> void:
        # FUOCO AMICO (Task 18): il player congelato in attesa dell'anima non
        # disegna nulla (il corpo accasciato lo disegna SoulTransferEffect).
        if soul_pending:
                return
        # FIX (pozione magica): aura fantasmagorica attorno al player mentre
        # l'effetto pozione è attivo (scia eterea + particelle che salgono).
        if ghost_mode:
                _draw_ghost_aura()
        # Draw projectiles (relative to player node origin = player position)
        # 4 distinct shapes per weapon type (mirror C++ drawProjectiles)
        for proj in projectiles:
                if not proj.get("active", false):
                        continue
                var p_pos: Vector2 = proj.get("pos", Vector2.ZERO)
                # Convert world position to local (relative to player node)
                var local_pos: Vector2 = p_pos - position
                var w_type: int = proj.get("type", WeaponType.PISTOL)
                # RELIC (Task 21): proiettili reliquia con forma dedicata.
                if GameConstants.is_relic_weapon(w_type):
                        _draw_relic_projectile(local_pos,
                                        proj.get("dir", Vector2(1, 0)), w_type)
                        continue
                var col: Color = _projectile_color(w_type)
                match w_type:
                        WeaponType.LASER:
                                # Laser: thin elongated beam (14x3) rotated by direction
                                var dir: Vector2 = proj.get("dir", Vector2(1, 0))
                                # Draw as elongated beam with circles along direction
                                for i in 7:
                                        var offset: Vector2 = dir * (i - 3) * 2
                                        draw_circle(local_pos + offset, 1.0, col)
                        WeaponType.SHOTGUN:
                                # Shotgun: 3 small pellets perpendicular to direction
                                var dir: Vector2 = proj.get("dir", Vector2(1, 0))
                                var perp: Vector2 = Vector2(-dir.y, dir.x)
                                draw_circle(local_pos + perp * 2, 1.5, col)
                                draw_circle(local_pos, 2.0, col)
                                draw_circle(local_pos - perp * 2, 1.5, col)
                        WeaponType.ROCKET:
                                # Rocket: body + tip + trail
                                var dir: Vector2 = proj.get("dir", Vector2(1, 0))
                                # Trail
                                draw_circle(local_pos - dir * 6, 2.0, Color(1, 0.4, 0.1, 0.5))
                                draw_circle(local_pos - dir * 9, 1.5, Color(1, 0.3, 0.1, 0.3))
                                # Body
                                draw_circle(local_pos, 3.5, col)
                                draw_circle(local_pos, 2.5, Color(0.6, 0.3, 0.1))
                                # Tip
                                draw_circle(local_pos + dir * 3, 2.0, Color(1, 0.9, 0.4))
                        WeaponType.SIEGE:
                                # TASK 39 — palla di cannone in ghisa: sfera
                                # scura con riflessi, anello runico dorato che
                                # ruota e scia di fumo/braci.
                                var dir: Vector2 = proj.get("dir", Vector2(1, 0))
                                # Scia di fumo (3 sbuffi sfumati)
                                draw_circle(local_pos - dir * 8, 3.2,
                                                Color(0.22, 0.20, 0.19, 0.45))
                                draw_circle(local_pos - dir * 13, 2.4,
                                                Color(0.25, 0.23, 0.21, 0.30))
                                draw_circle(local_pos - dir * 17, 1.7,
                                                Color(0.28, 0.26, 0.24, 0.20))
                                # Braci nella scia
                                draw_circle(local_pos - dir * 10 + Vector2(0, -2), 1.0,
                                                Color(1.0, 0.55, 0.15, 0.65))
                                # Alone incandescente
                                draw_circle(local_pos, 7.0, Color(1.0, 0.60, 0.18, 0.22))
                                # Corpo in ghisa (3 strati: scuro/chiaro/specular)
                                draw_circle(local_pos, 5.0, Color(0.16, 0.15, 0.17))
                                draw_circle(local_pos - Vector2(1, 1), 3.6,
                                                Color(0.38, 0.36, 0.38))
                                draw_circle(local_pos - Vector2(2, 2), 1.4,
                                                Color(0.85, 0.83, 0.86))
                                # Anello runico dorato che ruota (2 archi)
                                var spin: float = fmod(float(Time.get_ticks_msec()) * 0.004, TAU)
                                draw_arc(local_pos, 5.8, spin, spin + 2.1, 12,
                                                Color(1.0, 0.80, 0.30, 0.85), 1.4)
                                draw_arc(local_pos, 5.8, spin + PI, spin + PI + 2.1, 12,
                                                Color(1.0, 0.80, 0.30, 0.85), 1.4)
                        _:
                                # Pistol: small red fire bullet (was: huge yellow ball).
                                # FIX (pallino giallo troppo grande e giallo):
                                # era draw_circle(local_pos, 5.0, yellow) → ora 2px rosso.
                                draw_circle(local_pos, 2.0, col)
                                draw_circle(local_pos, 1.0, Color(1.0, 1.0, 0.8, 1.0))

        # TASK 82 — LAMPO DI VOLATA: feedback visivo dello sparo con forma,
        # colore e comportamento DEDICATI per arma/elemento (sostituisce il
        # vecchio lampo generico rosso/arancio sempre uguale a 18 px dal
        # centro). Ora il lampo sta ALLA PUNTA dell'arma e dura ~160 ms.
        if _muzzle_timer_ms > 0:
                _draw_muzzle_flash()

        # RELIC (Task 21): visual del fendente in mischia (arco/cerchio/linea
        # che sfuma in ~250ms) + outfit overlay dell'armatura equipaggiata.
        if melee_fx_timer_ms > 0:
                _draw_melee_fx()
        if not armor_relic.is_empty():
                _draw_armor_overlay()

        # Draw invincibility aura (chalice effect) - detailed fire aura:
        # spritesheet + 3 glow circles + 12 procedural flames + 8 sparks +
        # central nucleus. Mirrors C++ Game::drawFireAura (3770-3879).
        if invincible_timer > 0:
                _draw_fire_aura()

        # Draw shadow (always visible, like C++)
        var shadow_y: float = 20.0 - jump_offset * 0.3
        draw_circle(Vector2(0, shadow_y), 12.0, Color(0, 0, 0, 0.3))

        # Fallback procedural character if no sprite loaded
        _draw_character_fallback()

        # Equipped weapon (drawn on top of body so it's visible when held).
        # Mirrors C++ Weapon::renderEquipped() in src/Weapon.cpp line 523-817.
        _draw_equipped_weapon()

        # FIX (dinamite): se il player ha la dinamite equipaggiata, disegna
        # il candelotto con miccia accesa accanto al player.
        # Lo stato dynamite_equipped è in MainGameController, ma il player
        # non vi accede direttamente. Il MainGameController chiama una
        # funzione del player per abilitare/disabilitare il rendering.
        if _dynamite_equipped:
                _draw_dynamite_equipped()
        # FIX (martello di Thor): il Mjolnir in mano NON viene disegnato qui:
        # i figli Sprite2D (personaggio) disegnano SOPRA il _draw del parent,
        # quindi qui resterebbe NASCOSTO dietro il corpo. Usa il child
        # Sprite2D dedicato _hammer_sprite (vedi _update_hammer_sprite).


# ===========================================================================
# TASK 82 — _draw_muzzle_flash(): lampo di volata per arma/elemento.
#
# Disegnato in locale alla PUNTA dell'arma (_muzzle_pos, registrata allo
# sparo) mentre _muzzle_timer_ms scende da MUZZLE_FLASH_MS a 0 (~160 ms):
# `t` va da 1 (appena sparato) a 0 (spegnimento) e guida dimensioni/alpha.
# Stili (scelti in shoot()/_fire_relic in base all'arma/elemento):
#   fire    — pistola: scintilla bianca + bagliore ambra + fumo
#   wide    — shotgun: cono ampio a 3 lobi + 5 scintille in ventaglio
#   blast   — rocket: vampata + anello di braci + fumo di rinculo
#   energy  — laser: nucleo + anello carico + streak di emissione
#   cannon  — cannone d'assedio: vampa oro + 2 sbuffi di polvere + braci
#   flame   — armi elementali che INCENDIANO: lingua di fiamma colorata
#   frost   — armi elementali che CONGELANO: glint cristallino a stella
#   arcane  — lame/dardi lanciati: anello + impulso + streak di velocita'
# Tutto volutamente PICCOLO (max ~7 px di raggio): deve leggere come
# feedback del colpo, non coprire il corridoio.
# ===========================================================================
func _draw_muzzle_flash() -> void:
        var t: float = float(_muzzle_timer_ms) / float(MUZZLE_FLASH_MS)
        var pos: Vector2 = _muzzle_pos
        var dir: Vector2 = _muzzle_dir
        var col: Color = _muzzle_color
        var perp: Vector2 = Vector2(-dir.y, dir.x)
        # Leggero flicker: il lampo "vive" invece di restare statico.
        var flick: float = 0.85 + 0.15 * sin(float(Time.get_ticks_msec()) * 0.09)
        var bright: Color = Color(minf(col.r + 0.40, 1.0),
                        minf(col.g + 0.40, 1.0), minf(col.b + 0.40, 1.0))
        var hot: Color = Color(1.0, 0.96, 0.82)
        var smoke: Color = Color(0.55, 0.53, 0.50)

        match _muzzle_style:
                "fire":
                        # Pistola: scintilla compatta.
                        draw_circle(pos, 5.0 * t * flick, Color(col.r, col.g, col.b, 0.30))
                        draw_circle(pos, 2.8 * t + 0.8, col)
                        draw_circle(pos, 1.3, hot)
                        for i in 3:
                                var sp: Vector2 = pos + dir * (3.5 + 3.0 * float(i)) \
                                                * (1.0 - 0.6 * t)
                                draw_circle(sp, 0.9 * t + 0.3, bright)
                        draw_circle(pos + Vector2(0.0, -2.0 - 2.5 * (1.0 - t)),
                                        1.5 + 1.5 * (1.0 - t),
                                        Color(smoke.r, smoke.g, smoke.b, 0.22 * t))
                "wide":
                        # Shotgun: cono ampio a 3 lobi + scintille in ventaglio.
                        for k in 3:
                                var k_off: float = float(k - 1) * 5.2
                                var lobe: Vector2 = pos + perp * k_off
                                draw_circle(lobe, 4.0 * t * flick,
                                                Color(col.r, col.g, col.b, 0.30))
                                draw_circle(lobe, 1.9 * t + 0.6, col)
                        draw_circle(pos, 2.2, hot)
                        for k in 5:
                                var spread_a: float = (float(k) - 2.0) * 0.45
                                var s_dir: Vector2 = dir.rotated(spread_a)
                                draw_circle(pos + s_dir * (5.5 + 3.5 * (1.0 - t)),
                                                1.1 * t + 0.3, bright)
                        draw_circle(pos + Vector2(0.0, -3.0 - 3.0 * (1.0 - t)),
                                        2.0 + 2.0 * (1.0 - t),
                                        Color(smoke.r, smoke.g, smoke.b, 0.20 * t))
                "blast":
                        # Rocket: vampata + braci + fumo di rinculo.
                        draw_circle(pos, 6.5 * t * flick, Color(col.r, col.g, col.b, 0.35))
                        draw_circle(pos, 3.6 * t + 1.2, col)
                        draw_circle(pos, 1.8, hot)
                        for k in 4:
                                var e_a: float = float(k) * (PI * 0.5) + 0.7 * t
                                draw_circle(pos + dir.rotated(e_a) * 4.5 * t,
                                                1.0 * t + 0.3, bright)
                        draw_circle(pos - dir * (5.0 + 3.0 * (1.0 - t)),
                                        2.5 + 2.5 * (1.0 - t),
                                        Color(smoke.r, smoke.g, smoke.b, 0.28 * t))
                "energy":
                        # Laser: nucleo + anello carico + streak di emissione.
                        draw_circle(pos, 5.5 * t * flick, Color(col.r, col.g, col.b, 0.40))
                        draw_arc(pos, 4.2 * t + 1.2, 0.0, TAU, 20,
                                        Color(col.r, col.g, col.b, 0.70 * t + 0.20), 1.0)
                        draw_circle(pos, 1.6, Color(1.0, 1.0, 1.0))
                        for i in 3:
                                var st: Vector2 = pos + dir * (2.5 + 2.5 * float(i)) \
                                                * (1.2 - 0.4 * t)
                                draw_circle(st, 1.3 - 0.3 * float(i),
                                                Color(col.r, col.g, col.b, 0.85 - 0.25 * float(i)))
                "cannon":
                        # Cannone d'assedio: vampa oro + polvere + braci.
                        draw_circle(pos, 7.0 * t * flick, Color(col.r, col.g, col.b, 0.40))
                        draw_circle(pos, 3.0 * t + 1.4, col)
                        draw_circle(pos, 2.0, hot)
                        for k in 2:
                                var p_off: Vector2 = perp * (3.0 * float(k) - 1.5)
                                draw_circle(pos + p_off + Vector2(0.0, -2.0 * (1.0 - t)),
                                                3.0 + 2.5 * (1.0 - t),
                                                Color(smoke.r, smoke.g, smoke.b, 0.30 * t))
                        for k in 3:
                                draw_circle(pos + dir.rotated(0.6 * float(k) - 0.6) \
                                                * (5.0 * t + 1.0), 1.0 * t + 0.3, bright)
                "flame":
                        # Elementale di fuoco: lingua di fiamma colorata.
                        for j in 3:
                                var f_d: Vector2 = dir * (2.0 + 3.5 * float(j)) \
                                                * (0.4 + 0.6 * t)
                                var f_r: float = (2.6 - 0.7 * float(j)) * t + 0.6
                                draw_circle(pos + f_d, f_r,
                                                Color(col.r, col.g, col.b, 0.85))
                                draw_circle(pos + f_d, f_r * 0.55, bright)
                        draw_circle(pos, 1.4, hot)
                        for k in 2:
                                draw_circle(pos + Vector2(float(k) * 3.0 - 1.5,
                                                -2.0 - 3.0 * (1.0 - t)),
                                                0.8 * t + 0.3, bright)
                "frost":
                        # Elementale di ghiaccio: glint cristallino a stella.
                        draw_circle(pos, 4.6 * t, Color(col.r, col.g, col.b, 0.35))
                        draw_circle(pos, 1.5, Color(1.0, 1.0, 1.0))
                        for k in 3:
                                var ray_a: float = float(k) * (PI / 3.0) + 0.3
                                var ray_dir: Vector2 = Vector2(cos(ray_a), sin(ray_a))
                                var ray_len: float = 4.5 * t + 1.5
                                draw_line(pos - ray_dir * ray_len, pos + ray_dir * ray_len,
                                                Color(col.r, col.g, col.b, 0.80), 0.8)
                        draw_circle(pos + perp * 2.8 * t, 0.9, col)
                        draw_circle(pos - perp * 2.8 * t, 0.9, col)
                _:
                        # Arcano (lame/dardi lanciati): anello + impulso.
                        draw_circle(pos, 4.0 * t * flick, Color(col.r, col.g, col.b, 0.35))
                        draw_arc(pos, 5.0 * t + 1.5, 0.0, TAU, 20,
                                        Color(col.r, col.g, col.b, 0.65 * t + 0.15), 1.2)
                        draw_circle(pos, 1.6, bright)
                        draw_circle(pos + dir * 3.5, 1.2,
                                        Color(col.r, col.g, col.b, 0.80))
                        draw_circle(pos + dir * 6.5, 0.8,
                                        Color(col.r, col.g, col.b, 0.50))


# FIX (dinamite): variabile di stato per il rendering della dinamite.
# Settata dal MainGameController quando il player raccoglie la dinamite.
var _dynamite_equipped: bool = false
var _dynamite_fuse_timer_ms: int = 0  # per animazione scintille
var _dynamite_alert_played: bool = false  # per cambio colore miccia

# FIX (martello di Thor): stato del martello impugnato. Settato dal
# MainGameController al pickup e azzerato quando finiscono i 2 lanci.
var _hammer_equipped: bool = false
# Texture PNG del martello (cache statica condivisa tra i player).
static var _hammer_tex: Texture2D = null
# FIX (visibilita' in mano): Sprite2D figlio DEDICATO al martello — aggiunto
# DOPO lo sprite del personaggio, quindi disegnato SOPRA di lui (nel _draw
# del parent resterebbe coperto dal corpo: i child Node2D renderizzano dopo
# il canvas del parent).
var _hammer_sprite: Sprite2D = null

# TASK 50 (pergamena del GHIACCIO): pergamena equipaggiata — fluttua sopra
# la spalla del player con bagliore ghiacciato finché ha colpi disponibili.
var _freeze_scroll_equipped: bool = false
static var _freeze_scroll_tex: Texture2D = null
var _freeze_scroll_sprite: Sprite2D = null


func set_freeze_scroll_equipped(equipped: bool) -> void:
        _freeze_scroll_equipped = equipped
        _ensure_freeze_scroll_sprite()
        if _freeze_scroll_sprite != null and is_instance_valid(_freeze_scroll_sprite):
                _freeze_scroll_sprite.visible = equipped


func is_freeze_scroll_equipped() -> bool:
        return _freeze_scroll_equipped


# Crea (una volta sola) lo Sprite2D della pergamena del ghiaccio.
func _ensure_freeze_scroll_sprite() -> void:
        if _freeze_scroll_sprite != null and is_instance_valid(_freeze_scroll_sprite):
                return
        if _freeze_scroll_tex == null:
                var abs_path: String = ProjectSettings.globalize_path(
                                "res://assets/sprites/parchment/freeze_scroll.png")
                if FileAccess.file_exists(abs_path):
                        var img := Image.new()
                        if img.load(abs_path) == OK:
                                _freeze_scroll_tex = ImageTexture.create_from_image(img)
        if _freeze_scroll_tex == null:
                return  # senza PNG niente pergamena in spalla
        _freeze_scroll_sprite = Sprite2D.new()
        _freeze_scroll_sprite.name = "FreezeScrollSprite"
        _freeze_scroll_sprite.texture = _freeze_scroll_tex
        _freeze_scroll_sprite.scale = Vector2(0.28, 0.28)  # ~36px
        _freeze_scroll_sprite.centered = true
        _freeze_scroll_sprite.visible = false
        add_child(_freeze_scroll_sprite)


# Aggiorna posizione/rotazione/aura della pergamena del ghiaccio: fluttua
# sopra la spalla con bob sinusoide e pulsazione ciano-ghiaccio.
func _update_freeze_scroll_sprite() -> void:
        if _freeze_scroll_sprite == null or not is_instance_valid(_freeze_scroll_sprite):
                return
        if not _freeze_scroll_equipped:
                _freeze_scroll_sprite.visible = false
                return
        var x_sign: float = 1.0 if last_dx >= 0 else -1.0
        _freeze_scroll_sprite.visible = true
        var bob: float = sin(float(anim_time) * 0.005) * 3.0
        _freeze_scroll_sprite.position = Vector2(
                        16.0 * x_sign, -26.0 + bob - jump_offset)
        _freeze_scroll_sprite.rotation = x_sign * deg_to_rad(12.0) \
                        + 0.06 * sin(float(anim_time) * 0.003)
        var glow: float = 0.5 + 0.5 * sin(float(anim_time) * 0.007)
        _freeze_scroll_sprite.modulate = Color(1.0, 1.0, 1.0).lerp(
                        Color(0.45, 0.85, 1.0), 0.18 + 0.30 * glow)


func set_hammer_equipped(equipped: bool) -> void:
        _hammer_equipped = equipped
        _ensure_hammer_sprite()
        if _hammer_sprite != null and is_instance_valid(_hammer_sprite):
                _hammer_sprite.visible = equipped


func is_hammer_equipped() -> bool:
        return _hammer_equipped


# Crea (una volta sola) lo Sprite2D del martello in mano.
func _ensure_hammer_sprite() -> void:
        if _hammer_sprite != null and is_instance_valid(_hammer_sprite):
                return
        if _hammer_tex == null:
                var abs_path: String = ProjectSettings.globalize_path(
                                "res://assets/sprites/collectibles/item_hammer.png")
                if FileAccess.file_exists(abs_path):
                        var img := Image.new()
                        if img.load(abs_path) == OK:
                                _hammer_tex = ImageTexture.create_from_image(img)
        if _hammer_tex == null:
                return  # senza PNG niente martello in mano (il volo ha il fallback)
        _hammer_sprite = Sprite2D.new()
        _hammer_sprite.name = "HammerSprite"
        _hammer_sprite.texture = _hammer_tex
        _hammer_sprite.scale = Vector2(0.34, 0.34)  # ~43px
        _hammer_sprite.centered = true
        _hammer_sprite.visible = false
        add_child(_hammer_sprite)


# Aggiorna posizione/rotazione/aura del martello in mano (ogni frame da
# _update_sprite): pendere al fianco del player, inclinato in avanti, con
# bagliore elettrico che pulsa.
func _update_hammer_sprite() -> void:
        if _hammer_sprite == null or not is_instance_valid(_hammer_sprite):
                return
        if not _hammer_equipped:
                _hammer_sprite.visible = false
                return
        var x_sign: float = 1.0 if last_dx >= 0 else -1.0
        _hammer_sprite.visible = true
        # FIX (martello scollegato durante il salto): anche il Mjolnir segue
        # l'arco del salto del corpo sprite (-jump_offset), come arma e
        # dinamite, così resta in mano al player mentre è in aria.
        _hammer_sprite.position = Vector2(19.0 * x_sign, -7.0 - jump_offset)
        _hammer_sprite.rotation = x_sign * deg_to_rad(38.0)
        var glow: float = 0.5 + 0.5 * sin(float(anim_time) * 0.006)
        _hammer_sprite.modulate = Color(1.0, 1.0, 1.0).lerp(
                        Color(0.72, 0.88, 1.0), 0.14 + 0.22 * glow)


func set_dynamite_equipped(equipped: bool, fuse_ms: int = 0, alert: bool = false) -> void:
        _dynamite_equipped = equipped
        _dynamite_fuse_timer_ms = fuse_ms
        _dynamite_alert_played = alert


# Disegna il candelotto di dinamite equipaggiato con miccia accesa.
# Scintille animate, miccia che brucia.
func _draw_dynamite_equipped() -> void:
        var facing_right: bool = last_dx >= 0
        var x_sign: float = 1.0 if facing_right else -1.0
        # Posizione: accanto al player, sporgente
        var dyn_x: float = 20.0 * x_sign
        # FIX (dinamite scollegata durante il salto): il candelotto segue
        # l'arco del salto del corpo sprite (-jump_offset), come l'arma.
        var dyn_y: float = -2.0 - jump_offset
        # === CANDELOTTO (cilindro rosso) ===
        # Corpo
        draw_rect(Rect2(dyn_x - 5, dyn_y - 10, 10, 20),
                Color(0.7, 0.12, 0.1, 1.0), true)
        draw_rect(Rect2(dyn_x - 5, dyn_y - 10, 10, 20),
                Color(0.45, 0.06, 0.05, 1.0), false, 1.0)
        # Highlight
        draw_rect(Rect2(dyn_x - 4, dyn_y - 8, 2, 16),
                Color(0.86, 0.24, 0.2, 1.0), true)
        # Etichetta TNT
        draw_rect(Rect2(dyn_x - 3, dyn_y - 4, 6, 4),
                Color(0.94, 0.86, 0.7, 1.0), true)
        # Cappucciio superiore
        draw_rect(Rect2(dyn_x - 5, dyn_y - 12, 10, 3),
                Color(0.55, 0.1, 0.08, 1.0), true)
        # === MICCIA (esce dal cappuccio superiore) ===
        var fuse_top_x: float = dyn_x - 1
        var fuse_top_y: float = dyn_y - 14
        draw_line(Vector2(dyn_x, dyn_y - 12),
                Vector2(fuse_top_x, fuse_top_y),
                Color(0.16, 0.14, 0.12, 1.0), 2)
        # === SCINTILLE (se miccia accesa, non in alert) ===
        if not _dynamite_alert_played:
                # Animazione scintille con anim_time
                var phase: int = (int(anim_time) / 80) % 4
                for i in 3:
                        var a: float = (float(i) / 3.0) * TAU + phase * 1.5
                        var sx: float = fuse_top_x + cos(a) * 3.0
                        var sy: float = fuse_top_y + sin(a) * 3.0
                        # Glow arancione
                        draw_circle(Vector2(sx, sy), 2.5,
                                Color(1.0, 0.6, 0.2, 0.6))
                        # Nucleo giallo
                        draw_circle(Vector2(sx, sy), 1.5,
                                Color(1.0, 0.95, 0.4, 1.0))
                # Scintilla centrale bianca
                draw_circle(Vector2(fuse_top_x, fuse_top_y), 1.0,
                        Color(1.0, 1.0, 0.9, 1.0))
        else:
                # In fase alert: miccia fumante (grigio, no scintille)
                draw_circle(Vector2(fuse_top_x, fuse_top_y), 2.0,
                        Color(0.4, 0.4, 0.4, 0.6))
                # Fumo che sale
                for i in 3:
                        var sy2: float = fuse_top_y - 4 - i * 3
                        var sx2: float = fuse_top_x + sin(float(anim_time) * 0.005 + i) * 2
                        draw_circle(Vector2(sx2, sy2), 2.0 - i * 0.3,
                                Color(0.5, 0.5, 0.5, 0.4 - i * 0.1))


# FIX (pozione magica): aura fantasmagorica del player — 3 aure eteree
# pulsanti + 6 particelle che salgono a spirale + scia ondulata sotto i piedi.
# Tinta verde-acqua (il colore della pozione) che sfuma nel ciano spettrale.
func _draw_ghost_aura() -> void:
        var t: float = float(anim_time)
        var breath: float = (sin(t * 0.004) + 1.0) * 0.5
        # FIX (aura scollegata durante il salto): l'aura eterea segue l'arco
        # del salto del corpo sprite (-jump_offset), come arma e martello.
        draw_set_transform(Vector2(0.0, -jump_offset))
        # Aure concentriche eteree
        draw_circle(Vector2.ZERO, 30.0 + breath * 3.0, Color(0.45, 0.95, 0.75, 0.06))
        draw_circle(Vector2.ZERO, 22.0 + breath * 2.5, Color(0.55, 1.0, 0.85, 0.08))
        draw_circle(Vector2.ZERO, 15.0 + breath * 2.0, Color(0.65, 1.0, 0.9, 0.10))
        # Anello spettrale che pulsa
        draw_arc(Vector2.ZERO, 26.0 + breath * 4.0, 0.0, TAU, 32,
                Color(0.7, 1.0, 0.9, 0.16 + 0.08 * breath), 1.5)
        # Particelle che salgono a spirale
        for i in 6:
                var phase: float = t * 0.002 + float(i) * TAU / 6.0
                var py: float = 18.0 - fmod(t * 0.045 + float(i) * 7.0, 44.0)
                var px: float = cos(phase) * (10.0 - py * 0.15)
                draw_circle(Vector2(px, py), 1.8,
                        Color(0.75, 1.0, 0.9, 0.55 - absf(py) * 0.008))
        # Scia ondulata ai piedi (bassa, sotto lo sprite)
        for i in 4:
                var st: float = t * 0.008 + float(i) * 1.6
                draw_circle(Vector2(sin(st) * 4.0, 20.0 + float(i) * 1.2),
                        2.2 - float(i) * 0.3, Color(0.6, 0.95, 0.8, 0.30 - float(i) * 0.06))
        # Reset del transform: il resto del _draw() torna a quota terra.
        draw_set_transform(Vector2.ZERO)


# ===========================================================================
# RELIC (Task 21) — rendering: proiettili, fendente mischia, outfit armatura
# ===========================================================================

## Proiettile reliquia: una forma per reliquia (colore dalla definizione).
# TASK 61 — cache statica dei sheet PNG dei proiettili elementali
# (fiamme del Drago: riuso dei sheet Task 60b + ricolorazione blu).
static var _elem_sheet_cache: Dictionary = {}


func _get_elemental_sheet(res_path: String) -> Texture2D:
        if _elem_sheet_cache.has(res_path):
                return _elem_sheet_cache[res_path]
        var tex: Texture2D = null
        var abs_p: String = ProjectSettings.globalize_path(res_path)
        if FileAccess.file_exists(abs_p):
                var img := Image.new()
                if img.load(abs_p) == OK:
                        tex = ImageTexture.create_from_image(img)
        _elem_sheet_cache[res_path] = tex
        return tex


## TASK 61 — proiettile fiamma del Drago dal sheet PNG (4 frame, flicker
## 10 fps). False se il PNG manca (il chiamante ricade sul procedurale).
func _draw_elemental_flame_png(local_pos: Vector2, res_path: String,
                size_px: float, col: Color) -> bool:
        var tex: Texture2D = _get_elemental_sheet(res_path)
        if tex == null:
                return false
        var frames: int = 4
        var fw: float = float(tex.get_width()) / float(frames)
        var fh: float = float(tex.get_height())
        var f: int = int(float(anim_time) * 0.01) % frames
        draw_circle(local_pos, size_px * 0.62,
                        Color(col.r, col.g, col.b, 0.20))
        draw_texture_rect_region(tex,
                        Rect2(local_pos.x - size_px * 0.5,
                                        local_pos.y - size_px * 0.5,
                                        size_px, size_px),
                        Rect2(float(f) * fw, 0.0, fw, fh))
        return true


## TASK 61 — arma da lancio che ROTEA in volo (spade/asce/alabarda/martello
## del set elementale): silhouette procedurale in stile Task 23, ruotata
## a tempo attorno al proprio centro (i pickup/in-mano usano i PNG reliquia
## esistenti; il volo ruotando e' leggibile anche stilizzato).
func _draw_spin_throw(local_pos: Vector2, dir: Vector2, kind: String) -> void:
        var spin: float = fmod(float(anim_time) * 0.025, TAU)
        # scia di volo PRIMA del transform locale (coordinate non ruotate)
        draw_circle(local_pos - dir * 7.0, 2.0, Color(1.0, 1.0, 1.0, 0.16))
        draw_circle(local_pos - dir * 11.0, 1.3, Color(1.0, 1.0, 1.0, 0.10))
        draw_set_transform(local_pos, spin)
        if kind == "sword":
                # lama d'acciaio doppio filo + guardia + elsa
                draw_colored_polygon(PackedVector2Array([
                        Vector2(9.5, 0.0), Vector2(2.0, 1.6),
                        Vector2(2.0, -1.6)]), Color(0.82, 0.88, 0.98))
                draw_colored_polygon(PackedVector2Array([
                        Vector2(9.5, 0.0), Vector2(2.0, 1.6),
                        Vector2(4.5, 0.0)]), Color(0.95, 0.97, 1.0))
                draw_line(Vector2(-2.0, -2.6), Vector2(-2.0, 2.6),
                                Color(0.55, 0.45, 0.30), 1.6)
                draw_line(Vector2(-2.0, 0.0), Vector2(-5.5, 0.0),
                                Color(0.30, 0.22, 0.14), 2.0)
                draw_circle(Vector2(-6.4, 0.0), 1.1, Color(0.72, 0.58, 0.34))
        elif kind == "axe":
                # manico + testa d'ascia bipenne
                draw_line(Vector2(-5.5, 0.0), Vector2(3.5, 0.0),
                                Color(0.45, 0.32, 0.18), 1.8)
                draw_colored_polygon(PackedVector2Array([
                        Vector2(2.0, -0.4), Vector2(4.5, -3.8),
                        Vector2(6.2, -2.2), Vector2(3.6, 0.6)]),
                                Color(0.78, 0.78, 0.82))
                draw_colored_polygon(PackedVector2Array([
                        Vector2(2.0, 0.4), Vector2(4.5, 3.8),
                        Vector2(6.2, 2.2), Vector2(3.6, -0.6)]),
                                Color(0.66, 0.66, 0.72))
                draw_line(Vector2(4.5, -3.8), Vector2(6.2, -2.2),
                                Color(0.95, 0.95, 1.0), 0.8)
        elif kind == "halberd":
                # asta lunga + lama d'alabarda + puntale
                draw_line(Vector2(-8.0, 0.0), Vector2(6.0, 0.0),
                                Color(0.40, 0.30, 0.18), 1.6)
                draw_colored_polygon(PackedVector2Array([
                        Vector2(5.0, -1.0), Vector2(8.5, -3.6),
                        Vector2(9.0, -1.4), Vector2(6.0, 0.8)]),
                                Color(0.80, 0.86, 0.94))
                draw_colored_polygon(PackedVector2Array([
                        Vector2(6.0, 0.0), Vector2(9.5, 0.0),
                        Vector2(7.5, 2.6)]), Color(0.60, 0.68, 0.80))
                draw_circle(Vector2(-8.6, 0.0), 1.2, Color(0.55, 0.50, 0.40))
        elif kind == "hammer":
                # manico + testa quadrata di pietra
                draw_line(Vector2(-5.0, 0.0), Vector2(3.0, 0.0),
                                Color(0.42, 0.32, 0.20), 2.0)
                draw_rect(Rect2(2.0, -3.6, 5.6, 7.2), Color(0.58, 0.58, 0.62))
                draw_rect(Rect2(2.8, -2.8, 4.0, 5.6), Color(0.72, 0.72, 0.76))
                draw_line(Vector2(3.0, -2.0), Vector2(6.4, 1.6),
                                Color(0.42, 0.42, 0.46), 0.8)
        draw_set_transform(Vector2.ZERO, 0.0)


func _draw_relic_projectile(local_pos: Vector2, dir: Vector2, w_type: int) -> void:
        var rdef: Dictionary = GameConstants.get_relic_def(w_type)
        if rdef.is_empty():
                draw_circle(local_pos, 2.5, Color.WHITE)
                return
        var col: Color = rdef.get("color", Color.WHITE)
        var ang: float = dir.angle()
        var perp: Vector2 = Vector2(-dir.y, dir.x)
        match w_type:
                GameConstants.RelicType.CROSSBOW:
                        # TASK 23: dardo d'argento DETTAGLIATO — asta in legno
                        # chiaro con impennaggio + punta d'acciaio affilata.
                        var shaft_tail: Vector2 = local_pos - dir * 9.0
                        var shaft_tip: Vector2 = local_pos + dir * 6.0
                        draw_line(shaft_tail, shaft_tip, Color(0.72, 0.62, 0.44), 2.6)
                        draw_line(shaft_tail, shaft_tip, Color(0.88, 0.80, 0.62), 1.2)
                        # punta triangolare d'acciaio
                        var tip_a: Vector2 = local_pos + dir * 10.0
                        draw_colored_polygon(PackedVector2Array([
                                tip_a, local_pos + dir * 5.0 + perp * 2.0,
                                local_pos + dir * 5.0 - perp * 2.0]),
                                Color(0.92, 0.94, 1.0))
                        # impennaggio posteriore (2 penne)
                        for fs in [-1.0, 1.0]:
                                draw_colored_polygon(PackedVector2Array([
                                        local_pos - dir * 4.0,
                                        local_pos - dir * 9.0 + perp * 3.0 * fs,
                                        local_pos - dir * 8.5]),
                                        Color(0.85, 0.88, 0.95, 0.9))
                GameConstants.RelicType.ARCANE_ORB:
                        # TASK 23: sfera arcana con anello runico orbitante.
                        var pulse: float = 1.0 + 0.25 * sin(float(anim_time) * 0.02)
                        draw_circle(local_pos, 7.5 * pulse,
                                Color(col.r, col.g, col.b, 0.28))
                        draw_circle(local_pos, 4.2, col)
                        draw_circle(local_pos, 2.2, Color(0.92, 0.88, 1.0))
                        # anello runico inclinato che orbita
                        var ring_t: float = float(anim_time) * 0.004
                        draw_arc(local_pos + Vector2(sin(ring_t) * 3.0, cos(ring_t) * 2.0),
                                6.5, ring_t, ring_t + PI * 1.4, 12,
                                Color(0.85, 0.75, 1.0, 0.75), 1.2)
                        # scia
                        draw_line(local_pos - dir * 8.0, local_pos - dir * 2.0,
                                Color(col.r, col.g, col.b, 0.35), 2.5)
                GameConstants.RelicType.TWIN_DAGGERS:
                        # TASK 23 (fix utente: "non sono pugnali"): PUGNALE
                        # COMPLETO ruotato al volo — lama triangolare con
                        # luccichio, guardia ad arco, impugnatura avvolta e
                        # pomo rotondo. Distinguibile da qualunque spada.
                        var blade_tip: Vector2 = local_pos + dir * 7.5
                        var guard_c: Vector2 = local_pos + dir * 1.5
                        # lama a doppio filo (2 triangoli specchiati)
                        draw_colored_polygon(PackedVector2Array([
                                blade_tip, guard_c + perp * 1.8, guard_c]),
                                Color(0.72, 0.95, 0.90))
                        draw_colored_polygon(PackedVector2Array([
                                blade_tip, guard_c - perp * 1.8, guard_c]),
                                Color(0.55, 0.85, 0.80))
                        # riflesso della lama
                        draw_line(guard_c + dir * 0.5, blade_tip - dir * 1.0,
                                Color(0.95, 1.0, 0.98, 0.9), 0.8)
                        # guardia ad arco (bronzo scuro)
                        draw_arc(guard_c, 3.2, ang + PI * 0.35, ang - PI * 0.35 + TAU,
                                8, Color(0.62, 0.48, 0.28), 1.6)
                        # impugnatura avolta (2 fasce)
                        var grip_a: Vector2 = local_pos - dir * 1.5
                        var grip_b: Vector2 = local_pos - dir * 4.5
                        draw_line(grip_a, grip_b, Color(0.30, 0.22, 0.14), 2.2)
                        draw_line(grip_a - perp * 0.8, grip_b - perp * 0.8,
                                Color(0.45, 0.33, 0.20), 0.9)
                        # pomo rotondo
                        draw_circle(grip_b - dir * 1.2, 1.4, Color(0.72, 0.58, 0.34))
                        # scia di volo
                        draw_line(local_pos - dir * 9.0, local_pos - dir * 4.0,
                                Color(col.r, col.g, col.b, 0.30), 2.0)
                GameConstants.RelicType.RANGER_BOW:
                        # TASK 23: FRECCIA dettagliata — asta in frassino,
                        # punta selce scura, impennaggio 3 penne verdi.
                        var shaft_a: Vector2 = local_pos - dir * 7.0
                        var shaft_b: Vector2 = local_pos + dir * 5.0
                        draw_line(shaft_a, shaft_b, Color(0.78, 0.65, 0.40), 1.9)
                        draw_line(shaft_a + perp * 0.4, shaft_b + perp * 0.4,
                                Color(0.90, 0.80, 0.55), 0.7)
                        # punta in selce
                        draw_colored_polygon(PackedVector2Array([
                                local_pos + dir * 8.5, local_pos + dir * 4.0 + perp * 1.7,
                                local_pos + dir * 4.0 - perp * 1.7]),
                                Color(0.42, 0.40, 0.36))
                        # impennaggio: 3 penne (2 visibili + 1 centrale)
                        for fs in [-1.0, 1.0]:
                                draw_colored_polygon(PackedVector2Array([
                                        local_pos - dir * 3.0,
                                        local_pos - dir * 7.0 + perp * 2.6 * fs,
                                        local_pos - dir * 6.5]),
                                        Color(0.35, 0.68, 0.30, 0.95))
                        draw_line(local_pos - dir * 7.0, local_pos - dir * 3.0,
                                Color(0.45, 0.75, 0.38, 0.9), 1.0)
                GameConstants.RelicType.STORM_ROD:
                        # TASK 23: segmento di fulmine più lungo e vivido:
                        # zigzag a 3 gomiti + doppio tratto (alone + core
                        # bianco) + scintille alle estremità.
                        var zig1: float = sin(float(anim_time) * 0.05) * 3.0
                        var p0: Vector2 = local_pos - dir * 11.0
                        var p1: Vector2 = local_pos - dir * 4.0 + perp * zig1
                        var p2: Vector2 = local_pos + dir * 4.0 - perp * zig1
                        var p3: Vector2 = local_pos + dir * 11.0
                        draw_polyline(PackedVector2Array([p0, p1, p2, p3]),
                                Color(0.55, 0.78, 1.0, 0.45), 4.5)
                        draw_polyline(PackedVector2Array([p0, p1, p2, p3]),
                                Color(0.75, 0.92, 1.0), 2.0)
                        draw_polyline(PackedVector2Array([p0, p1, p2, p3]),
                                Color(1.0, 1.0, 1.0, 0.95), 0.9)
                        draw_circle(p3, 1.8, Color(1.0, 1.0, 1.0, 0.9))
                        draw_circle(p0, 1.4, Color(0.8, 0.95, 1.0, 0.8))
                GameConstants.RelicType.ALCHEMIST_BOMBS:
                        # TASK 23: bomba in ghisa con riflessi, fascia metallica,
                        # miccia con scintilla + piccola scia di fumo.
                        draw_circle(local_pos, 4.8, Color(0.14, 0.14, 0.16))
                        draw_circle(local_pos - Vector2(1.3, 1.3), 1.6,
                                Color(0.40, 0.40, 0.46))
                        # fascia metallica orizzontale
                        draw_line(local_pos - Vector2(3.6, -1.0), local_pos + Vector2(3.6, -1.0),
                                Color(0.52, 0.50, 0.55), 1.1)
                        # miccia
                        draw_line(local_pos + Vector2(2.2, -3.8),
                                local_pos + Vector2(4.2, -5.6), Color(0.55, 0.42, 0.25), 1.2)
                        var spark_t: float = fmod(float(anim_time) * 0.02, TAU)
                        draw_circle(local_pos + Vector2(4.2, -5.6)
                                + Vector2(cos(spark_t), sin(spark_t)) * 1.6, 1.8,
                                Color(1.0, 0.85, 0.3))
                        draw_circle(local_pos + Vector2(4.2, -5.6)
                                + Vector2(cos(spark_t), sin(spark_t)) * 1.6, 0.9,
                                Color(1.0, 1.0, 0.7))
                        # scia di fumo
                        draw_circle(local_pos - dir * 6.0, 1.2, Color(0.35, 0.35, 0.38, 0.5))
                        draw_circle(local_pos - dir * 9.0, 0.9, Color(0.35, 0.35, 0.38, 0.3))
                GameConstants.RelicType.REFLECT_BOLT:
                        # Colpo riflesso delle Scaglie: dardo smeraldo con scia.
                        draw_line(local_pos - dir * 10.0, local_pos + dir * 5.0,
                                Color(col.r, col.g, col.b, 0.5), 3.0)
                        draw_circle(local_pos, 3.0, col)
                        draw_circle(local_pos + dir * 4.0, 2.0,
                                Color(0.85, 1.0, 0.9))
                # ================= TASK 61 — ARMi ELEMENTALI =================
                GameConstants.RelicType.THROWING_SWORD:
                        _draw_spin_throw(local_pos, dir, "sword")
                GameConstants.RelicType.THROWING_AXE:
                        _draw_spin_throw(local_pos, dir, "axe")
                GameConstants.RelicType.HALBERD_THROW:
                        _draw_spin_throw(local_pos, dir, "halberd")
                GameConstants.RelicType.GOLEM_HAMMER_THROW:
                        _draw_spin_throw(local_pos, dir, "hammer")
                GameConstants.RelicType.FIRE_STAFF:
                        # Dardo di fiamma: goccia incandescente + scia ustoria
                        # (fallback se il sheet PNG del drago non esiste).
                        draw_circle(local_pos - dir * 8.0, 2.0,
                                        Color(1.0, 0.45, 0.10, 0.30))
                        draw_circle(local_pos, 4.0, Color(1.0, 0.45, 0.10))
                        draw_circle(local_pos + dir * 2.5, 2.6,
                                        Color(1.0, 0.85, 0.35))
                        draw_circle(local_pos + dir * 3.5, 1.2,
                                        Color(1.0, 0.98, 0.75))
                GameConstants.RelicType.ICE_LANCE:
                        # Lancia di ghiaccio: cristallo appuntito + brina
                        draw_line(local_pos - dir * 10.0, local_pos + dir * 8.0,
                                Color(0.60, 0.85, 1.0, 0.55), 3.2)
                        draw_colored_polygon(PackedVector2Array([
                                local_pos + dir * 12.0,
                                local_pos + dir * 6.0 + perp * 2.4,
                                local_pos + dir * 6.0 - perp * 2.4]),
                                Color(0.75, 0.94, 1.0))
                        draw_colored_polygon(PackedVector2Array([
                                local_pos + dir * 10.0,
                                local_pos + dir * 5.0 + perp * 1.5,
                                local_pos + dir * 5.0 - perp * 1.5]),
                                Color(0.95, 1.0, 1.0))
                        draw_circle(local_pos - dir * 11.0, 1.2,
                                        Color(0.85, 0.97, 1.0, 0.5))
                GameConstants.RelicType.ICE_ARROW:
                        # Freccia di ghiaccio: asta di brina + punta
                        # cristallina + impennaggio azzurro
                        draw_line(local_pos - dir * 7.0, local_pos + dir * 5.0,
                                Color(0.72, 0.92, 1.0), 1.8)
                        draw_colored_polygon(PackedVector2Array([
                                local_pos + dir * 8.5, local_pos + dir * 4.0 + perp * 1.8,
                                local_pos + dir * 4.0 - perp * 1.8]),
                                Color(0.90, 0.98, 1.0))
                        for fs in [-1.0, 1.0]:
                                draw_colored_polygon(PackedVector2Array([
                                        local_pos - dir * 3.0,
                                        local_pos - dir * 7.0 + perp * 2.4 * fs,
                                        local_pos - dir * 6.5]),
                                        Color(0.55, 0.80, 1.0, 0.9))
                GameConstants.RelicType.THROWN_BOULDER:
                        # Masso irregolare con crepe (mini-boulder)
                        draw_circle(local_pos, 6.0, Color(0.35, 0.29, 0.20))
                        draw_circle(local_pos - Vector2(1.5, 1.5), 4.0,
                                        Color(0.55, 0.46, 0.30))
                        draw_circle(local_pos + Vector2(2.5, 1.0), 1.2,
                                        Color(0.75, 0.70, 0.58))
                        draw_line(local_pos + Vector2(-3.0, -2.0),
                                        local_pos + Vector2(2.0, 1.5),
                                        Color(0.22, 0.18, 0.12), 1.1)
                        draw_circle(local_pos - dir * 8.0, 1.6,
                                        Color(0.35, 0.29, 0.20, 0.35))
                GameConstants.RelicType.BLOOD_DART:
                        # Dardo sanguigno con gocce in scia (homing)
                        draw_line(local_pos - dir * 8.0, local_pos + dir * 6.0,
                                Color(0.55, 0.02, 0.08, 0.8), 2.4)
                        draw_circle(local_pos + dir * 4.5, 2.2, col)
                        draw_circle(local_pos + dir * 7.0, 1.2,
                                        Color(1.0, 0.25, 0.3))
                        var drip_t: float = fmod(float(anim_time) * 0.03, TAU)
                        draw_circle(local_pos - dir * 10.0
                                        + Vector2(cos(drip_t), sin(drip_t)) * 1.5,
                                        1.1, Color(0.70, 0.05, 0.10, 0.8))
                GameConstants.RelicType.FLAME_EMBER:
                        # Fiammella piccola e rapida (sheet drago, fallback
                        # procedural a fiammetta)
                        if not _draw_elemental_flame_png(local_pos,
                                        "res://assets/sprites/projectiles/proj_fireball_sheet.png",
                                        15.0, col):
                                draw_circle(local_pos, 3.0, Color(1.0, 0.6, 0.15))
                                draw_circle(local_pos + dir * 1.5, 1.6,
                                                Color(1.0, 0.9, 0.4))
                GameConstants.RelicType.FIREBALL_RED:
                        # Palla di fuoco rossa (sheet Task 60b del DEMONE)
                        if not _draw_elemental_flame_png(local_pos,
                                        "res://assets/sprites/projectiles/proj_fireball_sheet.png",
                                        24.0, col):
                                draw_circle(local_pos, 5.5, Color(1.0, 0.4, 0.1))
                                draw_circle(local_pos, 3.0, Color(1.0, 0.8, 0.3))
                GameConstants.RelicType.FLAME_BLUE:
                        # Fiamma blu gelida (ricolorazione PIL del sheet rosso)
                        if not _draw_elemental_flame_png(local_pos,
                                        "res://assets/sprites/projectiles/proj_fireball_blue_sheet.png",
                                        24.0, col):
                                draw_circle(local_pos, 5.5, Color(0.3, 0.6, 1.0))
                                draw_circle(local_pos, 3.0, Color(0.8, 0.95, 1.0))
                GameConstants.RelicType.FIRE_MAELSTROM:
                        # Cataclisma: palla di fuoco gigante (sheet DRAGON
                        # BREATH del Task 60b) + vortice di scintille
                        var mael_t: float = float(anim_time) * 0.008
                        for ms in 3:
                                var ma: float = mael_t + float(ms) * (TAU / 3.0)
                                draw_circle(local_pos + Vector2(cos(ma), sin(ma)) * 10.0,
                                                1.6, Color(1.0, 0.55, 0.15, 0.7))
                        if not _draw_elemental_flame_png(local_pos,
                                        "res://assets/sprites/projectiles/proj_dragon_breath_sheet.png",
                                        34.0, col):
                                draw_circle(local_pos, 8.5, Color(1.0, 0.35, 0.05))
                                draw_circle(local_pos, 5.0, Color(1.0, 0.7, 0.2))
                                draw_circle(local_pos, 2.5, Color(1.0, 0.95, 0.6))
                _:
                        draw_circle(local_pos, 2.5, col)


## Visual del fendente in mischia — TASK 23 (fix utente: "i colpi di spada
## non fanno vedere la spada che fa un arco ma si vede soltanto un'ellisse"):
## ora SI VEDE L'ARMA VERA (PNG ruotata) che percorre l'arco del fendente,
## con scia multi-banda che ne marca la traiettoria.
##   * "sector" (Spadone/Ascia/Lama): il PNG ruota da un bordo all'altro
##     dell'arco (ease-out) attorno al player;
##   * "circle" (Mazza/Martello): il PNG compie un giro completo attorno al
##     player (rotazione 360°);
##   * "line" (Alabarda): il PNG scatta in avanti lungo la direzione (thrust).
## Se il PNG manca: fallback alla sola scia procedurale potenziata.
func _draw_melee_fx() -> void:
        var rdef: Dictionary = melee_fx_def
        if rdef.is_empty():
                return
        var col: Color = rdef.get("color", Color.WHITE)
        var life: float = clampf(float(melee_fx_timer_ms) / float(MELEE_FX_DURATION_MS), 0.0, 1.0)
        # progress = 0 -> 1 nel corso del fendente (ease-out per lo scatto
        # iniziale tipico dei colpi in mischia).
        var prog: float = 1.0 - life
        var eased: float = 1.0 - pow(1.0 - prog, 2.2)
        var fade: float = 0.14 + 0.40 * life  # più tenue a fine fendente
        var radius: float = float(rdef.get("radius_px", 96.0)) * (1.15 - 0.15 * life)
        # Il pivot del fendente sporge leggermente verso il facing (la mano).
        var pivot_off: Vector2 = melee_fx_dir * 6.0
        draw_set_transform(Vector2(0.0, -jump_offset))
        var shape: String = str(rdef.get("shape", "sector"))

        # --- 1) L'ARMA (PNG) che percorre il fendente ---
        var weapon_tex: Texture2D = RelicArt.get_icon_for_def(rdef)
        if weapon_tex != null:
                var tex_size: Vector2 = weapon_tex.get_size()
                var shape_kind: String = shape
                # TASK 24: orientamento dal MANICO (png_grip_deg): la parte
                # utile (lama/testa) sta dall'altra parte e punta IN FUORI
                # lungo la direzione corrente del fendente. Il manico resta
                # ancorato al player (centro immagine a ~0.42*side lungo la
                # direzione: il manico, a meta' lunghezza, ricade sul pivot).
                # FIX utente: prima la rotazione era +90 gradi fissa e le armi
                # con elsa in alto (spadone/pugnali) colpivano col MANICO.
                var business_rad: float = deg_to_rad(
                                float(rdef.get("png_grip_deg", 90.0)) + 180.0)
                if shape_kind == "circle":
                        # Mazza / Martello: giro completo attorno al player,
                        # testa in fuori lungo il raggio corrente. Dimensione
                        # TASK 24: testa entro ~1 cella dal centro (64px) per
                        # non compenetrare i muri adiacenti.
                        var spin: float = eased * TAU
                        var spin_dir: Vector2 = Vector2(cos(spin), sin(spin))
                        var side_len: float = clampf(radius * 0.45, 26.0, 48.0)
                        var wsc: float = side_len / maxf(tex_size.x, tex_size.y)
                        # La mano orbita leggermente attorno al player.
                        var pivot: Vector2 = spin_dir * (radius * 0.12) + pivot_off
                        var wcenter: Vector2 = pivot + spin_dir * (side_len * 0.42)
                        # NOTA: draw_set_transform NON componga coi transform
                        # precedenti → il jump offset va sommato a mano.
                        draw_set_transform(wcenter + Vector2(0.0, -jump_offset),
                                        spin - business_rad, Vector2(wsc, wsc))
                        draw_texture_rect(weapon_tex,
                                Rect2(-tex_size * 0.5, tex_size), false)
                        draw_set_transform(Vector2(0.0, -jump_offset))
                elif shape_kind == "line":
                        # Alabarda: thrust lineare avanti e indietro (la punta
                        # resta entro il raggio d'effetto dichiarato). TASK 24:
                        # lunge ridotto — prima scattava di ~160px e la shaft
                        # compenetrava vistosamente i muri.
                        var thrust: float = 8.0 + eased * radius * 0.22
                        var side_len2: float = clampf(radius * 0.42, 36.0, 72.0)
                        var wsc2: float = side_len2 / maxf(tex_size.x, tex_size.y)
                        var aim_ang: float = melee_fx_dir.angle()
                        var wpos: Vector2 = melee_fx_dir \
                                        * (thrust + side_len2 * 0.42) + pivot_off
                        draw_set_transform(wpos + Vector2(0.0, -jump_offset),
                                        aim_ang - business_rad, Vector2(wsc2, wsc2))
                        draw_texture_rect(weapon_tex,
                                Rect2(-tex_size * 0.5, tex_size), false)
                        draw_set_transform(Vector2(0.0, -jump_offset))
                else:
                        # Spadone / Ascia / Lama: ARCO — l'arma ruota da un
                        # bordo all'altro del settore orientato al facing.
                        var center_a: float = melee_fx_dir.angle()
                        var half_arc: float = deg_to_rad(float(rdef.get("arc_deg", 90.0))) * 0.5
                        # leggera anticipazione oltre i bordi (follow-through)
                        var start_a: float = center_a - half_arc - 0.18
                        var end_a: float = center_a + half_arc + 0.18
                        # Senso dello sweep: dall'alto verso il basso se si
                        # mira in orizzontale, dal basso verso l'alto se si
                        # mira in verticale (legge del colpo "naturale").
                        var swing_a: float
                        if melee_fx_dir.y <= 0.0:
                                swing_a = start_a + (end_a - start_a) * eased
                        else:
                                swing_a = end_a - (end_a - start_a) * eased
                        # TASK 24: dimensione corporea (prima fino a 110px =
                        # piu' alta del player -> "spada enorme" che entrava
                        # nei muri). La SCIA marca comunque tutto il raggio
                        # d'effetto; l'arma fisica resta ~1 cella.
                        var side_len3: float = clampf(radius * 0.58, 36.0, 72.0)
                        var wsc3: float = side_len3 / maxf(tex_size.x, tex_size.y)
                        var swing_dir: Vector2 = Vector2(cos(swing_a), sin(swing_a))
                        var wcenter: Vector2 = swing_dir * (side_len3 * 0.42) + pivot_off
                        draw_set_transform(wcenter + Vector2(0.0, -jump_offset),
                                        swing_a - business_rad, Vector2(wsc3, wsc3))
                        draw_texture_rect(weapon_tex,
                                Rect2(-tex_size * 0.5, tex_size), false)
                        draw_set_transform(Vector2(0.0, -jump_offset))

        # --- 2) Scia del fendente (multi-banda, con "fantasmi" del percorso) ---
        if shape == "circle":
                # Mazza / Martello: anello a 360° + bagliore centrale.
                draw_circle(Vector2.ZERO, radius * 0.55,
                        Color(col.r, col.g, col.b, fade * 0.35))
                draw_arc(Vector2.ZERO, radius * 0.8, 0.0, TAU, 40,
                        Color(col.r, col.g, col.b, fade + 0.25), 4.0)
                draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40,
                        Color(1.0, 1.0, 1.0, fade * 0.5), 2.0)
        elif shape == "line":
                # Alabarda: linea taglio lunga davanti al player.
                var end: Vector2 = melee_fx_dir * radius
                draw_line(melee_fx_dir * 14.0, end,
                        Color(col.r, col.g, col.b, fade + 0.3), 5.0)
                draw_line(melee_fx_dir * 18.0, end * 0.92,
                        Color(1.0, 1.0, 1.0, fade * 0.6), 2.0)
        else:
                # Spadone / Ascia / Lama: settore ad arco orientato al facing.
                var center_a2: float = melee_fx_dir.angle()
                var half_arc2: float = deg_to_rad(float(rdef.get("arc_deg", 90.0))) * 0.5
                # banda larga tenue (spazzata completa)
                draw_arc(Vector2.ZERO, radius * 0.82, center_a2 - half_arc2,
                        center_a2 + half_arc2, 26,
                        Color(col.r, col.g, col.b, fade * 0.55), 9.0)
                # banda stretta intensa (filo della lama)
                draw_arc(Vector2.ZERO, radius * 0.86, center_a2 - half_arc2 * 0.9,
                        center_a2 + half_arc2 * 0.9, 26,
                        Color(col.r, col.g, col.b, fade + 0.25), 4.0)
                # filo bianco interno
                draw_arc(Vector2.ZERO, radius, center_a2 - half_arc2 * 0.75,
                        center_a2 + half_arc2 * 0.75, 26,
                        Color(1.0, 1.0, 1.0, fade * 0.6), 2.0)
                # "fantasmi" del percorso della lama (3 echì della posizione)
                for g in 3:
                        var gp: float = clampf(eased - 0.12 * float(g + 1), 0.0, 1.0)
                        var ga: float = center_a2 - half_arc2 + (2.0 * half_arc2) * gp
                        var ghost_pos: Vector2 = Vector2(cos(ga), sin(ga)) * radius * 0.84
                        draw_circle(ghost_pos, 4.0 - float(g),
                                Color(col.r, col.g, col.b, fade * (0.5 - 0.15 * float(g))))
                draw_circle(melee_fx_dir * radius * 0.4, 6.0,
                        Color(col.r, col.g, col.b, fade * 0.5))
        draw_set_transform(Vector2.ZERO)


## Outfit overlay procedurale dell'armatura (adattato ai 9 personaggi:
## anello-scutidato attorno al corpo + spallacci + tacche di durabilita').
## Disegnato nel canvas del player (DIETRO lo sprite figlio): l'anello a
## raggio 44+ sporge dal corpo 64x64 scalato 1.3 (~83px, semicorsa ~42).
func _draw_armor_overlay() -> void:
        var col: Color = armor_relic.get("color", Color.WHITE)
        var kind: String = armor_kind()
        var charges: int = armor_charges()
        var max_charges: int = int(armor_relic.get("max_charges", charges))
        var t: float = float(anim_time)
        var breath: float = (sin(t * 0.004) + 1.0) * 0.5
        draw_set_transform(Vector2(0.0, -jump_offset))
        # Glow esterno tenue (tinta dell'armatura).
        draw_circle(Vector2.ZERO, 46.0 + breath * 3.0,
                Color(col.r, col.g, col.b, 0.05 + 0.03 * breath))
        # Anello-scutidato: tacche = cariche residue (funzionale + elegante).
        if max_charges > 0 and charges > 0:
                var seg: int = mini(charges, 16)
                var gap: float = deg_to_rad(7.0)
                var span: float = TAU / float(mini(max_charges, 16))
                for i in seg:
                        var a0: float = float(i) * span + gap
                        draw_arc(Vector2.ZERO, 44.0, a0, a0 + span - gap * 2.0, 8,
                                Color(col.r, col.g, col.b, 0.85), 3.0)
        else:
                draw_arc(Vector2.ZERO, 44.0, 0.0, TAU, 40,
                        Color(col.r, col.g, col.b, 0.5), 2.0)
        # Spallacci (sporgono dai lati del corpo: "indossa" l'armatura).
        draw_circle(Vector2(-26.0, -12.0), 7.0, Color(col.r, col.g, col.b, 0.9))
        draw_circle(Vector2(26.0, -12.0), 7.0, Color(col.r, col.g, col.b, 0.9))
        draw_circle(Vector2(-26.0, -12.0), 4.0,
                Color(col.r * 0.6, col.g * 0.6, col.b * 0.6, 0.9))
        draw_circle(Vector2(26.0, -12.0), 4.0,
                Color(col.r * 0.6, col.g * 0.6, col.b * 0.6, 0.9))
        # Sigillo per kind (piccola marca sopra la testa).
        var sigil_col: Color = Color(1.0, 1.0, 1.0, 0.75)
        match kind:
                "absorb":
                        draw_circle(Vector2(0.0, -34.0), 3.0, sigil_col)  # oro pieno
                "reflect":
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(-4.0, -34.0), Vector2(4.0, -34.0), Vector2(0.0, -28.0)]), sigil_col)
                "thorns":
                        for s in 3:
                                draw_line(Vector2(-4.0 + float(s) * 4.0, -30.0),
                                        Vector2(-4.0 + float(s) * 4.0, -36.0), sigil_col, 1.5)
                "regen":
                        draw_circle(Vector2(0.0, -34.0), 4.0, Color(0.4, 0.95, 0.6, 0.8))
                        draw_circle(Vector2(0.0, -34.0), 2.0, sigil_col)
                "aura":
                        # Aura di fuoco: 6 fiammelle attorno.
                        for i in 6:
                                var fa: float = float(i) / 6.0 * TAU + t * 0.001
                                var fx: float = cos(fa) * 36.0
                                var fy: float = sin(fa) * 36.0
                                draw_colored_polygon(PackedVector2Array([
                                        Vector2(fx - 2.5, fy), Vector2(fx + 2.5, fy),
                                        Vector2(fx, fy - 8.0 - sin(t * 0.01 + i) * 2.0)]),
                                        Color(1.0, 0.5, 0.15, 0.55))
                "fury":
                        draw_circle(Vector2(0.0, -34.0), 3.0, Color(1.0, 0.3, 0.25, 0.9))
                        draw_circle(Vector2(0.0, -38.0), 2.0, Color(1.0, 0.5, 0.3, 0.9))
        draw_set_transform(Vector2.ZERO)


func _projectile_color(w_type: int) -> Color:
        match w_type:
                WeaponType.PISTOL:
                        return Color(1.0, 0.25, 0.1)  # red fire (was yellow)
                WeaponType.SHOTGUN:
                        return Color(1.0, 0.5, 0.2)  # orange
                WeaponType.ROCKET:
                        return Color(1.0, 0.3, 0.1)  # red
                WeaponType.SIEGE:
                        return Color(1.0, 0.80, 0.30)  # oro cannone (TASK 39)
                WeaponType.LASER:
                        return Color(0.3, 1.0, 0.3)  # green
                _:
                        return Color(1.0, 1.0, 1.0)


# ===========================================================================
# _draw_fire_aura(): detailed chalice invincibility aura.
#
# Renders (in local space, centered on the player):
#   0. effect_fireaura spritesheet frame (idle, animated by anim_time)
#   1. Outer gold glow circle (32px pulsing)
#   2. Inner dark-red glow circle (22px pulsing)
#   3. Mid gold glow circle (14px pulsing)
#   4. 12 procedural flames (gold base + red tip) arranged around the player
#   5. 8 white sparks ascending upward (animated by anim_time)
#   6. Central white nucleus (8px pulsing)
#
# Mirrors Game::drawFireAura in src/Game.cpp lines 3770-3879.
# All drawing happens at Vector2.ZERO since this is the player's local origin.
# ===========================================================================
func _draw_fire_aura() -> void:
        var COL_GOLD: Color = Color(220.0 / 255.0, 160.0 / 255.0, 40.0 / 255.0)
        var COL_RED_L: Color = Color(200.0 / 255.0, 80.0 / 255.0, 80.0 / 255.0)
        var COL_RED_D: Color = Color(160.0 / 255.0, 40.0 / 255.0, 40.0 / 255.0)
        var COL_WHITE: Color = Color(240.0 / 255.0, 240.0 / 255.0, 240.0 / 255.0)
        var inv_pulse: float = sin(float(invincible_timer) * 0.01) * 0.2 + 1.0
        # Persist anim time across frames (mirror C++ static fireAnimTime)
        _fire_aura_anim_time += 0.08
        var fire_anim: float = _fire_aura_anim_time
        # FIX (aura scollegata durante il salto): le fiamme del calice seguono
        # l'arco del salto del corpo sprite (-jump_offset) così restano
        # attorno al player anche quando è in aria.
        draw_set_transform(Vector2(0.0, -jump_offset))

        # --- 0. Spritesheet PNG aura di fuoco (effect_fireaura) ---
        # 6x4 frames of 64x64 with anchor (32, 32). Blend is alpha (normale)
        # but procedural glows below give extra luminosity.
        if _fire_aura_sheet != null and _fire_aura_sheet.is_loaded():
                var frame_count: int = _fire_aura_sheet.get_frame_count("idle")
                if frame_count <= 0:
                        frame_count = 6
                var frame_idx: int = int(fire_anim * 1000.0 / 80.0) % frame_count
                if frame_idx < 0:
                        frame_idx = 0
                var tex: AtlasTexture = _fire_aura_sheet.get_frame_texture("idle", frame_idx)
                if tex != null:
                        var sprite_scale: float = 1.4 * inv_pulse
                        var fw: float = float(tex.get_width()) * sprite_scale
                        var fh: float = float(tex.get_height()) * sprite_scale
                        # Anchor (32, 32) of 64x64 frame = centered on player
                        draw_texture_rect(tex,
                                Rect2(-fw / 2.0, -fh / 2.0, fw, fh), false)

        # --- 1. Bagliore arancione pulsante (gold 32px) ---
        var glow_r: float = 32.0 * inv_pulse
        draw_circle(Vector2.ZERO, glow_r,
                Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b, 70.0 / 255.0))
        # --- 2. Bagliore interno rosso (22px) ---
        var inner_r: float = 22.0 * inv_pulse
        draw_circle(Vector2.ZERO, inner_r,
                Color(COL_RED_D.r, COL_RED_D.g, COL_RED_D.b, 100.0 / 255.0))
        # --- 3. Glow centrale oro (14px) ---
        var mid_r: float = 14.0 * inv_pulse
        draw_circle(Vector2.ZERO, mid_r,
                Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b, 90.0 / 255.0))

        # --- 4. 12 fiamme procedurali (gold base + red tip) ---
        # Alternate gold base / red tip - matches Game.cpp 3832-3858.
        for i in 12:
                var angle: float = (float(i) / 12.0) * TAU
                var fx: float = cos(angle) * 20.0
                var fy: float = sin(angle) * 20.0
                var flame_h: float = 10.0 + sin(fire_anim + float(i) * 0.7) * 5.0 + 5.0
                var flame_w: float = 3.5
                # Tip is offset horizontally by a sin wave for flicker
                var tip_x: float = fx + sin(fire_anim * 2.0 + float(i)) * 3.0
                var tip_y: float = fy - flame_h
                # Base oro (triangolo)
                draw_colored_polygon(PackedVector2Array([
                        Vector2(fx - flame_w, fy),
                        Vector2(fx + flame_w, fy),
                        Vector2(tip_x, tip_y),
                ]), Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b, 220.0 / 255.0))
                # Apice rosso (triangolo piu' piccolo sovrapposto)
                var tip_h: float = flame_h * 0.6
                draw_colored_polygon(PackedVector2Array([
                        Vector2(fx - flame_w * 0.6, fy - flame_h * 0.4),
                        Vector2(fx + flame_w * 0.6, fy - flame_h * 0.4),
                        Vector2(tip_x, fy - flame_h - tip_h * 0.3),
                ]), Color(COL_RED_L.r, COL_RED_L.g, COL_RED_L.b, 230.0 / 255.0))

        # --- 5. 8 scintille bianche ascending ---
        # Sparks rise upward and fade as they go higher.
        for i in 8:
                var spark_x: float = sin(fire_anim * 1.5 + float(i) * 1.2) * 14.0
                var spark_y: float = -10.0 - float(int(fire_anim * 20.0 + float(i) * 8.0) % 35)
                var spark_r: float = 1.2 + sin(fire_anim + float(i)) * 0.5
                var fade: int = int(fire_anim * 20.0 + float(i) * 8.0) % 35
                draw_circle(Vector2(spark_x, spark_y), spark_r,
                        Color(COL_WHITE.r, COL_WHITE.g, COL_WHITE.b,
                                (220.0 - float(fade) * 6.0) / 255.0))

        # --- 6. Nucleo centrale bianco pulsante (8px) ---
        var core_r: float = 8.0 * inv_pulse
        draw_circle(Vector2.ZERO, core_r,
                Color(COL_WHITE.r, COL_WHITE.g, COL_WHITE.b, 180.0 / 255.0))
        # Reset del transform: il resto del _draw() torna a quota terra.
        draw_set_transform(Vector2.ZERO)


# ===========================================================================
# renderCharacterFallback(): procedural rendering when no sprite PNG is loaded.
# Mirrors C++ Player::renderCharacterFallback() - draws a unique shape per
# character type using draw_circle, draw_rect, draw_colored_polygon.
# Each character has distinct features: HERO_M (hat), HERO_F (hair), MAGE
# (cone+robe), ORC (tusks+green), ELF (hood+ears), KNIGHT (helm+plume),
# GOLEM (cracks+glow), DRAGON (crest+wings+tail), VAMPIRE (cape+fangs).
# ===========================================================================
func _draw_character_fallback() -> void:
        if sprite_loaded and sprite != null and sprite.texture != null:
                return  # sprite exists, no fallback needed
        # FIX (fallback scollegato durante il salto): anche il corpo
        # procedurale (quando manca lo sprite PNG) segue l'arco del salto.
        draw_set_transform(Vector2(0.0, -jump_offset))
        var body_col: Color = Color(0.7, 0.6, 0.5)
        var accent_col: Color = Color(0.9, 0.8, 0.7)
        match character_type:
                CharacterType.HERO_M:
                        body_col = Color(0.5, 0.4, 0.3)
                        accent_col = Color(0.3, 0.3, 0.4)  # blue tunic
                CharacterType.HERO_F:
                        body_col = Color(0.6, 0.45, 0.4)
                        accent_col = Color(0.8, 0.2, 0.2)  # red hair
                CharacterType.MAGE:
                        body_col = Color(0.3, 0.2, 0.5)
                        accent_col = Color(0.5, 0.4, 0.8)  # purple robe
                CharacterType.ORC:
                        body_col = Color(0.3, 0.5, 0.2)
                        accent_col = Color(0.2, 0.3, 0.1)  # dark green
                CharacterType.ELF:
                        body_col = Color(0.8, 0.7, 0.5)
                        accent_col = Color(0.5, 0.4, 0.2)  # brown hood
                CharacterType.KNIGHT:
                        body_col = Color(0.6, 0.6, 0.65)
                        accent_col = Color(0.4, 0.4, 0.45)  # steel
                CharacterType.GOLEM:
                        body_col = Color(0.5, 0.48, 0.45)
                        accent_col = Color(1.0, 0.6, 0.1)  # glow eyes
                CharacterType.DRAGON:
                        body_col = Color(0.7, 0.2, 0.1)
                        accent_col = Color(0.9, 0.4, 0.1)  # red scales
                CharacterType.VAMPIRE:
                        body_col = Color(0.15, 0.1, 0.15)
                        accent_col = Color(0.8, 0.8, 0.9)  # pale skin
        # Body (circle)
        draw_circle(Vector2(0, 4), 12, body_col)
        # Head (circle)
        draw_circle(Vector2(0, -8), 8, accent_col)
        # Character-specific details
        match character_type:
                CharacterType.HERO_M:
                        # Hat (brown triangle)
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(-8, -14), Vector2(8, -14), Vector2(0, -22)
                        ]), Color(0.4, 0.3, 0.15))
                        # Eyes
                        draw_circle(Vector2(-3, -8), 1.5, Color.WHITE)
                        draw_circle(Vector2(3, -8), 1.5, Color.WHITE)
                CharacterType.HERO_F:
                        # Hair (red flowing)
                        draw_rect(Rect2(-8, -14, 16, 4), Color(0.8, 0.2, 0.2))
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(-8, -12), Vector2(-12, -4), Vector2(-8, 0)
                        ]), Color(0.7, 0.15, 0.15))
                CharacterType.MAGE:
                        # Pointed hat
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(-8, -14), Vector2(8, -14), Vector2(2, -26)
                        ]), Color(0.2, 0.15, 0.4))
                        # Robe bottom (wider)
                        draw_rect(Rect2(-14, 8, 28, 8), accent_col)
                        # Staff
                        draw_rect(Rect2(10, -8, 2, 20), Color(0.4, 0.3, 0.1))
                        draw_circle(Vector2(11, -10), 3, Color(0.3, 0.8, 1.0))
                CharacterType.ORC:
                        # Tusks
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(-2, -4), Vector2(-4, 0), Vector2(-1, 0)
                        ]), Color(0.9, 0.9, 0.8))
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(2, -4), Vector2(4, 0), Vector2(1, 0)
                        ]), Color(0.9, 0.9, 0.8))
                        # Ears
                        draw_circle(Vector2(-9, -8), 2, body_col)
                        draw_circle(Vector2(9, -8), 2, body_col)
                CharacterType.ELF:
                        # Pointed ears
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(-8, -10), Vector2(-12, -6), Vector2(-8, -4)
                        ]), accent_col)
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(8, -10), Vector2(12, -6), Vector2(8, -4)
                        ]), accent_col)
                        # Hood
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(-8, -14), Vector2(8, -14), Vector2(6, -8), Vector2(-6, -8)
                        ]), Color(0.4, 0.3, 0.15))
                CharacterType.KNIGHT:
                        # Helm
                        draw_rect(Rect2(-7, -16, 14, 8), accent_col)
                        # Plume
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(-2, -16), Vector2(2, -16), Vector2(0, -22)
                        ]), Color(0.8, 0.2, 0.2))
                        # Visor slit
                        draw_rect(Rect2(-4, -12, 8, 1), Color(0, 0, 0))
                CharacterType.GOLEM:
                        # Cracks (lines)
                        draw_line(Vector2(-6, -4), Vector2(-2, 4), Color(0.2, 0.18, 0.15), 1)
                        draw_line(Vector2(4, -6), Vector2(6, 2), Color(0.2, 0.18, 0.15), 1)
                        # Glowing eyes
                        draw_circle(Vector2(-3, -8), 2, accent_col)
                        draw_circle(Vector2(3, -8), 2, accent_col)
                CharacterType.DRAGON:
                        # Wings
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(-8, -4), Vector2(-16, -10), Vector2(-14, 0), Vector2(-8, 4)
                        ]), accent_col)
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(8, -4), Vector2(16, -10), Vector2(14, 0), Vector2(8, 4)
                        ]), accent_col)
                        # Horns
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(-4, -14), Vector2(-6, -20), Vector2(-2, -16)
                        ]), Color(0.5, 0.2, 0.05))
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(4, -14), Vector2(6, -20), Vector2(2, -16)
                        ]), Color(0.5, 0.2, 0.05))
                CharacterType.VAMPIRE:
                        # Cape (behind body)
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(-10, -6), Vector2(-14, 12), Vector2(14, 12), Vector2(10, -6)
                        ]), Color(0.05, 0.0, 0.05))
                        # Fangs
                        draw_rect(Rect2(-3, -4, 1, 3), Color.WHITE)
                        draw_rect(Rect2(2, -4, 1, 3), Color.WHITE)
        # Flip indicator (small arrow if facing left)
        if last_dx < 0:
                draw_colored_polygon(PackedVector2Array([
                        Vector2(-14, 0), Vector2(-18, -2), Vector2(-18, 2)
                ]), accent_col)
        # Reset del transform: il resto del _draw() torna a quota terra.
        draw_set_transform(Vector2.ZERO)


# ===========================================================================
# _draw_equipped_weapon(): draws the equipped weapon beside the player when
# ammo > 0, oriented by `last_dx` (right when >= 0, left when < 0).
# Mirrors C++ Weapon::renderEquipped() in src/Weapon.cpp line 523-817.
# Each of the 4 weapon types has unique multi-layer rendering:
#   * PISTOL:  2-layer grip + body + slide + gold insert + barrel + muzzle
#   * SHOTGUN: 2-layer stock + double barrel + reflection + pump + groove
#   * ROCKET:  2-layer tube + metal band + rocket body + conical tip + fin + scope
#   * LASER:   glow + body + body top + 3-layer core (out/mid/inner) + emitter + ring
# ===========================================================================
func _draw_equipped_weapon() -> void:
        if current_weapon.ammo <= 0:
                return
        # RELIC (Task 21): arma reliquia in mano — forma dedicata per
        # mischia (lama/manico) e distanza (spara-lanci). In boss room, con
        # colpi infiniti, ammo resta > 0 per costruzione.
        var relic_type: int = int(current_weapon.get("type", 0))
        if GameConstants.is_relic_weapon(relic_type) \
                        and relic_type != GameConstants.RelicType.REFLECT_BOLT:
                _draw_relic_weapon_in_hand(relic_type)
                return
        # FIX (arma non visibile): prima y=-8 (sotto la testa, coperta dallo
        # sprite 64x64). Ora y=-4 e l'arma è più a destra (offset +14px)
        # così sporge dal corpo del player ed è sempre visibile.
        # FIX (arma piccola): scale_factor aumentato da 1.4 a 2.0 per renderla
        # più visibile. Offset passato da 14 a 22 per proporzioni.
        var scale_factor: float = 2.0
        # FIX (arma scollegata durante il salto): il corpo dello sprite viene
        # alzato in aria di jump_offset px durante il salto (sprite.offset =
        # (0, -jump_offset)), ma l'arma era disegnata a quota FISSA y=-4 e
        # restava a terra mentre il player volava -> sembrava scollegata.
        # Ora l'arma segue lo stesso arco sinusoidale del corpo: resta
        # "attaccata" alla mano del player in ogni frame del salto.
        var y: float = -4.0 - jump_offset  # weapon height + jump arc sync
        var facing_right: bool = last_dx >= 0
        # Offset aggiuntivo per sporgere dal corpo
        var x_off: float = 22.0

        # TASK 51 (P7): RIDISEGNO ARMI — sprite PixelLab in mano (stessi
        # PNG dei pickup, cache condivisa in EnvironmentArt). Il pivot e'
        # il GRIP dell'arma (~22% dalla coda); specchiata col facing.
        # Fallback procedurale sotto se il PNG manca.
        var wtex: Texture2D = null
        if EnvironmentArt:
                wtex = EnvironmentArt.get_weapon_pickup_texture(
                                int(current_weapon.type))
        if wtex != null and int(current_weapon.type) <= 3:
                var src_w: float = wtex.get_width()
                var src_h: float = wtex.get_height()
                var disp_len: float = 58.0
                match current_weapon.type:
                        WeaponType.PISTOL: disp_len = 42.0
                        WeaponType.SHOTGUN: disp_len = 66.0
                        WeaponType.ROCKET: disp_len = 58.0
                        WeaponType.LASER: disp_len = 56.0
                var disp_h: float = disp_len * src_h / maxf(src_w, 1.0)
                if facing_right:
                        draw_set_transform(Vector2(x_off, y), 0.0, Vector2.ONE)
                        draw_texture_rect(wtex,
                                        Rect2(-disp_len * 0.20, -disp_h * 0.5,
                                                        disp_len, disp_h), false)
                else:
                        draw_set_transform(Vector2(-x_off, y), 0.0,
                                        Vector2(-1.0, 1.0))
                        draw_texture_rect(wtex,
                                        Rect2(-disp_len * 0.20, -disp_h * 0.5,
                                                        disp_len, disp_h), false)
                draw_set_transform(Vector2.ZERO)
                return

        match current_weapon.type:
                WeaponType.PISTOL:
                        # FIX (pistol troppo piccolo): ingrandito del 50% per
                        # uniformarlo a shotgun/rocket/laser. Prima era 6/11/13/8,
                        # ora 9/17/20/12.
                        # Grip (2 layers: dark base + lighter mid)
                        draw_rect(Rect2(_wxr(-4.5, 9.0, facing_right), y + 1, 9, 17),
                                Color(0.20, 0.10, 0.05))
                        draw_rect(Rect2(_wxr(-3.75, 7.5, facing_right), y + 1, 7.5, 17),
                                Color(0.33, 0.20, 0.10))
                        # Metal body + slide + gold insert
                        draw_rect(Rect2(_wxr(-6.0, 20.0, facing_right), y - 10, 20, 14),
                                Color(0.27, 0.27, 0.31))
                        draw_rect(Rect2(_wxr(-6.0, 20.0, facing_right), y - 10, 20, 5),
                                Color(0.47, 0.47, 0.51))
                        draw_rect(Rect2(_wxr(-4.5, 3.0, facing_right), y - 9, 3, 5),
                                Color(0.71, 0.55, 0.24))
                        # Barrel + muzzle
                        draw_rect(Rect2(_wxr(12.0, 12.0, facing_right), y - 8, 12, 8),
                                Color(0.33, 0.33, 0.37))
                        draw_circle(Vector2(_wxc(22.0, facing_right), y - 5), 2.5,
                                Color(0.06, 0.06, 0.06))
                WeaponType.SHOTGUN:
                        # Wooden stock (2 layers: dark base + lighter top)
                        draw_rect(Rect2(_wxr(-7.0, 14.0, facing_right), y + 3, 14, 10),
                                Color(0.27, 0.16, 0.07))
                        draw_rect(Rect2(_wxr(-7.0, 14.0, facing_right), y + 3, 14, 5),
                                Color(0.51, 0.31, 0.14))
                        # Double barrel + reflection
                        draw_rect(Rect2(_wxr(-6.0, 20.0, facing_right), y - 6, 20, 4),
                                Color(0.22, 0.22, 0.24))
                        draw_rect(Rect2(_wxr(-6.0, 20.0, facing_right), y - 1, 20, 4),
                                Color(0.20, 0.20, 0.22))
                        draw_rect(Rect2(_wxr(-5.0, 18.0, facing_right), y - 5.5, 18, 1),
                                Color(0.71, 0.71, 0.75))
                        # Pump + groove
                        draw_rect(Rect2(_wxr(1.0, 8.0, facing_right), y + 4, 8, 5),
                                Color(0.55, 0.35, 0.18))
                        draw_rect(Rect2(_wxr(4.0, 0.8, facing_right), y + 4.5, 0.8, 4),
                                Color(0.24, 0.14, 0.06))
                WeaponType.ROCKET:
                        # Tube (2 layers) + metal band
                        draw_rect(Rect2(_wxr(-9.0, 18.0, facing_right), y - 4, 18, 9),
                                Color(0.24, 0.35, 0.20))
                        draw_rect(Rect2(_wxr(-9.0, 18.0, facing_right), y - 4, 18, 3),
                                Color(0.39, 0.55, 0.31))
                        draw_rect(Rect2(_wxr(-2.0, 1.5, facing_right), y - 4, 1.5, 9),
                                Color(0.71, 0.71, 0.71))
                        # Rocket body + conical tip + fin
                        draw_rect(Rect2(_wxr(5.0, 8.0, facing_right), y - 2.5, 8, 5),
                                Color(0.71, 0.20, 0.20))
                        _draw_wpoly(PackedVector2Array([
                                Vector2(13.0, y - 2.5),
                                Vector2(13.0, y + 2.5),
                                Vector2(17.0, y),
                        ]), Color(0.86, 0.31, 0.31), facing_right)
                        _draw_wpoly(PackedVector2Array([
                                Vector2(5.0, y - 2.5),
                                Vector2(8.0, y - 2.5),
                                Vector2(6.5, y - 5.0),
                        ]), Color(0.55, 0.12, 0.12), facing_right)
                        # Scope
                        draw_rect(Rect2(_wxr(-3.0, 6.0, facing_right), y - 7, 6, 2),
                                Color(0.12, 0.12, 0.16))
                WeaponType.LASER:
                        # Glow
                        draw_circle(Vector2(_wxc(-8.0, facing_right), y - 6), 8,
                                Color(0.31, 0.86, 1.0, 0.24))
                        # Body (2 layers: base + top)
                        draw_rect(Rect2(_wxr(-5.0, 16.0, facing_right), y - 4, 16, 9),
                                Color(0.20, 0.22, 0.31))
                        draw_rect(Rect2(_wxr(-5.0, 16.0, facing_right), y - 4, 16, 3),
                                Color(0.39, 0.43, 0.59))
                        # Luminous core (3 layers: outer / mid / inner)
                        draw_circle(Vector2(_wxc(-4.0, facing_right), y - 4), 4,
                                Color(0.39, 0.78, 1.0, 0.86))
                        draw_circle(Vector2(_wxc(-2.5, facing_right), y - 2.5), 2.5,
                                Color(0.71, 0.94, 1.0, 0.94))
                        draw_circle(Vector2(_wxc(-1.2, facing_right), y - 1.2), 1.2,
                                Color(1.0, 1.0, 1.0, 0.98))
                        # Emitter + luminous ring
                        draw_rect(Rect2(_wxr(8.0, 7.0, facing_right), y - 3, 7, 5),
                                Color(0.27, 0.31, 0.43))
                        draw_circle(Vector2(_wxc(13.0, facing_right), y - 2), 2,
                                Color(0.59, 1.0, 1.0, 0.86))


# _wxr(offset, width, facing_right): returns the X coordinate of a weapon
# rect's left edge, mirrored around the player centre when facing left.
# `offset` is the right-facing left-edge offset from x=0.
# FIX (arma non visibile): aggiunto x_off (offset dal corpo del player) per
# far sporgere l'arma fuori dallo sprite 64x64 ed essere sempre visibile.
static func _wxr(offset: float, w: float, facing_right: bool) -> float:
        if facing_right:
                return offset + 14.0  # sporge a destra del corpo
        return -offset - w - 14.0  # sporge a sinistra del corpo


# _wxc(offset, facing_right): returns the X coordinate of a weapon circle
# centre, mirrored around the player centre when facing left.
# FIX (arma non visibile): aggiunto offset 14px per far sporgere dal corpo.
static func _wxc(offset: float, facing_right: bool) -> float:
        return (offset + 14.0) if facing_right else (-offset - 14.0)


# _draw_wpoly(points, color, facing_right): draws a polygon for the equipped
# weapon, mirroring all X coordinates around the player centre when facing
# left.
# FIX (arma non visibile): aggiunto offset 14px come in _wxr/_wxc.
func _draw_wpoly(points: PackedVector2Array, col: Color, facing_right: bool) -> void:
        var offset_x: float = 14.0 if facing_right else -14.0
        var shifted := PackedVector2Array()
        shifted.resize(points.size())
        if facing_right:
                for i in points.size():
                        shifted[i] = Vector2(points[i].x + offset_x, points[i].y)
                draw_colored_polygon(shifted, col)
                return
        for i in points.size():
                shifted[i] = Vector2(-points[i].x + offset_x, points[i].y)
        draw_colored_polygon(shifted, col)


# ===========================================================================
# RELIC (Task 21): arma reliquia in mano — TASK 23: PNG AD ALTA QUALITÀ
# (RelicArt) ruotata verso la direzione di mira, con fallback alla grafica
# procedurale storica se l'asset PNG manca. Il PNG rappresenta ESATTAMENTE
# l'oggetto (spadone vero, martello vero, arco vero...) invece di forme
# geometriche approssimative (fix utente: "spadone = tubo bianco",
# "arco = bastone con palla", "martello non è un martello").
# ===========================================================================
func _draw_relic_weapon_in_hand(relic_type: int) -> void:
        var rdef: Dictionary = GameConstants.get_relic_def(relic_type)
        if rdef.is_empty():
                return
        var col: Color = rdef.get("color", Color.WHITE)
        # TASK 23: PNG dell'arma in mano (preferito: qualità molto superiore).
        # TASK 24: durante il fendente (250ms) l'arma è GIÀ disegnata dal
        # _draw_melee_fx che la fa roteare: evita il doppio disegno (arma
        # statica in mano + arma che fende = "spada gigante doppia").
        var relic_tex: Texture2D = RelicArt.get_icon_for_def(rdef)
        if relic_tex != null:
                if melee_fx_timer_ms <= 0:
                        _draw_relic_png_in_hand(relic_tex, col, rdef)
                return
        # ---- Fallback procedurale (PNG non generato / rollback) ----
        var y: float = -4.0 - jump_offset  # quota arma + sync arco salto
        var facing_right: bool = last_dx >= 0
        var x_sign: float = 1.0 if facing_right else -1.0
        var glow: float = 0.5 + 0.5 * sin(float(anim_time) * 0.005)
        if str(rdef.get("family", "")) == "mischia":
                # Lama lunga con elsa e guardia (il colore distingue la reliquia).
                # Bagliore etereo dietro la lama.
                draw_circle(Vector2(_wxc(10.0, facing_right), y - 4), 10.0,
                        Color(col.r, col.g, col.b, 0.10 + 0.08 * glow))
                # Elsa (impugnatura scura 2 layer).
                draw_rect(Rect2(_wxr(-6.0, 8.0, facing_right), y - 1, 8, 9),
                        Color(0.22, 0.15, 0.08))
                draw_rect(Rect2(_wxr(-5.0, 6.0, facing_right), y - 1, 6, 9),
                        Color(0.38, 0.26, 0.14))
                # Guardia trasversale.
                draw_rect(Rect2(_wxr(-1.5, 12.0, facing_right), y - 8, 12, 4),
                        Color(0.55, 0.45, 0.30))
                # Lama (2 layer: base colorita + filo chiaro), lunghezza dalla
                # definizione (Spadone lunga, Daggers corta...).
                var blade_len: float = clampf(float(rdef.get("radius_px", 96.0)) * 0.16, 14.0, 26.0)
                draw_rect(Rect2(_wxr(6.0, blade_len, facing_right), y - 7, blade_len, 5), col)
                draw_rect(Rect2(_wxr(6.0, blade_len, facing_right), y - 7, blade_len, 2),
                        Color(minf(col.r + 0.35, 1.0), minf(col.g + 0.35, 1.0), minf(col.b + 0.35, 1.0)))
                # Punta triangolare.
                _draw_wpoly(PackedVector2Array([
                        Vector2(6.0 + blade_len, y - 7.0),
                        Vector2(6.0 + blade_len, y - 2.0),
                        Vector2(10.0 + blade_len, y - 4.5),
                ]), col, facing_right)
        else:
                # Ista/lancia arcana: asta + anelli + nucleo luminoso in punta.
                draw_rect(Rect2(_wxr(-8.0, 22.0, facing_right), y - 4, 22, 5),
                        Color(0.28, 0.24, 0.34))
                draw_rect(Rect2(_wxr(-8.0, 22.0, facing_right), y - 4, 22, 2),
                        Color(0.45, 0.40, 0.55))
                # Anelli decorativi lungo l'asta.
                draw_rect(Rect2(_wxr(0.0, 2.0, facing_right), y - 6, 2, 9), col)
                draw_rect(Rect2(_wxr(6.0, 2.0, facing_right), y - 6, 2, 9), col)
                # Nucleo luminoso in punta (pulsante).
                var tip_pos: Vector2 = Vector2(_wxc(16.0, facing_right), y - 1.5)
                draw_circle(tip_pos, 5.0 + glow * 2.0,
                        Color(col.r, col.g, col.b, 0.30))
                draw_circle(tip_pos, 3.0, col)
                draw_circle(tip_pos, 1.4, Color(1.0, 1.0, 1.0, 0.9))


## TASK 23: disegna il PNG dell'arma reliquia IN MANO al player.
## TASK 24 (fix utente: "spada impugnata dalla parte della lama e colpisce
## col manico"): l'orientamento NON e' piu' hardcoded su "PNG verticale
## con punta in alto" — ogni reliquia dichiara in GameConstants dove sta
## l'impugnatura nell'icona:
##   * png_grip_deg (armi "impugnate"): la parte OPPOSTA (lama/testa)
##     viene allineata alla mira e il MANICO resta sulla mano (il centro
##     immagine avanza di ~0.42*side lungo la mira: il manico, a meta'
##     lunghezza dal centro, ricade sulla mano stessa);
##   * png_point_deg (arco/balestra, impugnatura centrale): l'asse di
##     tiro dell'icona (freccia/saetta) viene allineato alla mira;
##   * nessun metadato (bombe, simmetriche): verticale, centrato sulla mano.
## FIX aggiuntivo TASK 24: l'offset del centro era in UNITA' TEXTURE (~512px)
## e non in px a schermo -> l'arma restava centrata sulla mano (mano in
## mezzo alla lama). Ora il centro e' posizionato in coordinate MONDO.
func _draw_relic_png_in_hand(tex: Texture2D, col: Color, rdef: Dictionary) -> void:
        var aim: Vector2 = Vector2(float(last_dx), float(last_dy))
        if aim == Vector2.ZERO:
                aim = Vector2(1.0, 0.0)
        aim = aim.normalized()
        var hand: Vector2 = Vector2(10.0, -6.0 - jump_offset)
        var side: float = 48.0  # lato del render (px a schermo)
        var tex_size: Vector2 = tex.get_size()
        var sc: float = side / maxf(tex_size.x, tex_size.y)
        var rot: float
        var center_world: Vector2
        if rdef.has("png_grip_deg"):
                # La direzione "utile" (dal manico verso lama/testa) e' l'OPPOSTO
                # del grip: allineiamola alla mira. rot = mira - business.
                var business_rad: float = deg_to_rad(
                                float(rdef.get("png_grip_deg", 90.0)) + 180.0)
                rot = aim.angle() - business_rad
                # Centro immagine avanti lungo la mira: il manico ricade
                # sulla mano (a ~meta' lunghezza dal centro, lato player).
                center_world = hand + aim * (side * 0.42)
        elif rdef.has("png_point_deg"):
                # Arco/balestra: la mano tiene il CENTRO; l'asse di fuoco
                # dell'icona viene allineato alla mira (la freccia/saetta
                # punta dove spara il player).
                rot = aim.angle() - deg_to_rad(float(rdef.get("png_point_deg", 0.0)))
                center_world = hand + aim * 6.0
        else:
                # Oggetto simmetrico (bombe): verticale, appena avanti.
                rot = aim.angle() + PI * 0.5
                center_world = hand + aim * (side * 0.20)
        draw_set_transform(center_world, rot, Vector2(sc, sc))
        draw_texture_rect(tex, Rect2(-tex_size * 0.5, tex_size), false,
                        Color(1.0, 1.0, 1.0, 1.0))
        draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
        # Lieve bagliore color reliquia attorno alla mano (coerenza col tema).
        var glow: float = 0.5 + 0.5 * sin(float(anim_time) * 0.005)
        draw_circle(hand, 7.0 + glow * 2.0,
                Color(col.r, col.g, col.b, 0.10 + 0.06 * glow))
