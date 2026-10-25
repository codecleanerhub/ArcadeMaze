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
# FUOCO AMICO (Task 18): effetto corpo accasciato + anima che vola verso il
# vincitore ricaricandogli l'energia.
const SoulTransferFx = preload("res://scripts/entities/SoulTransferEffect.gd")
# TASK 23: arco di fulmine visibile per la Verga della Tempesta (catena).
const LightningArcFx = preload("res://scripts/entities/LightningArcEffect.gd")

## TASK 36 — fulmine che si abbatte al suolo all'apparizione delle
## pergamene evento (effetto visivo pronunciato + flash + shake).
const LightningStrikeFx = preload("res://scripts/entities/LightningStrikeEffect.gd")

## TASK 38 — onda di luce che si diffonde per TUTTO il labirinto dopo il
## fulmine delle pergamene (esplosione di luce dal punto d'impatto).
const MazeLightWaveFx = preload("res://scripts/entities/MazeLightWaveEffect.gd")

## TASK 50 — raggio congelante della pergamena del ghiaccio (beam dal
## player fino al primo muro, con brina e anello di impatto).
const IceBeamFx = preload("res://scripts/entities/IceBeamEffect.gd")
# FUOCO AMICO (Task 18): raggio di collisione proiettile player -> altro
# player (~25 px, tra proiettile-nemico 24.5 e miniboss 35).
const FF_HIT_RADIUS_SQ: float = 625.0

# --- Node references (assigned in _ready) ---
@onready var maze: Node2D = $Maze
@onready var player: CharacterBody2D = $Player
@onready var player2: CharacterBody2D = $Player2
@onready var spawner: Node2D = $Enemies
@onready var projectiles_node: Node2D = $Projectiles
@onready var enemy_projectiles_node: Node2D = $EnemyProjectiles
@onready var collectibles_node: Node2D = $Collectibles

## TASK 30 (hazard ambientali): nodo che genera e aggiorna sabbie mobili,
## ganasce, voragini e muri di roccia. Inserito in MainGame.tscn tra Maze
## e Player (draw order: pavimento -> hazard -> entita').
@onready var hazards: Node2D = $Hazards
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

# FIX (pausa P senza feedback visivo): overlay "PAUSE / PRESS P TO RESUME"
# lampeggiante sopra tutto (CanvasLayer dedicato, layer 20 > HUD 10). Il
# toggle del tasto P resta in _unhandled_input (process_mode ALWAYS).
const PauseOverlayClass = preload("res://scripts/ui/PauseOverlay.gd")
var _pause_canvas: CanvasLayer = null
var _pause_overlay: Control = null

# ============================================================================
# TASK 23: CONTINUE PER-PLAYER IN 2P (crediti separati P1/P2).
# Quando un player (P1 o P2) perde l'ultima vita mentre l'altro è ancora
# vivo, il gioco si congela e appare il ContinuesOverlay con IL SUO
# contatore crediti. YES = consuma 1 credito del SUO contatore e riprende
# con 3 vite/energia piena/invulnerabilità breve. NO/timeout = eliminato
# (l'altro continua da solo). Se nessun player resta in gioco -> LOSE.
# In 1P il flusso resta la ContinuesScreen scene-based (snapshot restore).
# ============================================================================
const ContinuesOverlayClass = preload("res://scripts/ui/ContinuesOverlay.gd")
var _continue_overlay: CanvasLayer = null
## Player a cui è aperta la schermata continue (1 o 2; 0 = nessuna).
var _continue_pending_player: int = 0
## Invulnerabilità di grazia dopo un continue (ms) — non si muore appena
## ripresi mentre i nemici convergono sulla cella di respawn.
const CONTINUE_RESPAWN_INVULN_MS: int = 2500

# ============================================================================
# FIX (meccanica "Hurry Up!" — mini boss immortale): quando TUTTI i nemici
# del labirinto (compresi quelli respawnati dal portale) sono stati uccisi
# e sono passati 10 secondi dall'ultimo tesoro raccolto, appare in alto
# allo schermo la scritta lampeggiante "Hurry Up!" scritta col sangue
# gocciolante, e DAL PORTALE emerge un fantasma immortale unico (teschio
# con braccia scheletriche, stile Slimer): gli spari non lo uccidono (si
# sente solo una risata tenebrosa), si può solo scappare. Insegue il
# player a velocità dei nemici finché non passa la porta di fine livello;
# poi scompare e riappare al livello labirinto successivo allo stesso modo.
# ============================================================================
const GhostReaperClass = preload("res://scripts/entities/GhostReaper.gd")

## TASK 32 — nube di pipistrelli: evento casuale per livello.
const BatCloudClass = preload("res://scripts/entities/BatCloud.gd")
var bat_cloud: Node2D = null
var bat_events_left: int = 0
var bat_event_timer_ms: float = 0.0
var _bat_rng := RandomNumberGenerator.new()

# TASK 35 — PERGAMENE EVENTO (terremoto + voragini magiche). TASK 36: ogni
# TIPO puo' apparire al massimo DUE volte per livello ma con UN SOLO USO,
# e solo se i nemici vivi sono >= 30% (al di sotto non appaiono). Fasi per
# tipo: WAIT (timer all'apparizione) -> BEACON (bagliore/aura di telegrafo
# sulla cella) -> GROUND (FULMINE che si abbatte al suolo, pergamena a
# terra: 10s + 2s di lampeggio, poi svanisce) -> DONE (raccolta/USO o
# budget di 2 apparizioni esaurito: evento concluso per il livello; se
# invece scade non raccolta, torna WAIT per la seconda apparizione).
enum ScrollPhase { WAIT, BEACON, GROUND, DONE }
var scroll_quake_phase: int = ScrollPhase.DONE
var scroll_quake_timer_ms: float = 0.0
var scroll_quake_item: Node2D = null
var scroll_quake_beacon: Sprite2D = null
var scroll_chasm_phase: int = ScrollPhase.DONE
var scroll_chasm_timer_ms: float = 0.0
var scroll_chasm_item: Node2D = null
var scroll_chasm_beacon: Sprite2D = null
# TASK 50 — PERGAMENA DEL GHIACCIO: stessa macchina a stati delle altre
# due (WAIT -> BEACON -> GROUND -> DONE, stesse tempistiche), ma la
# raccolta EQUIPAGGIA il player: il fuoco spara il raggio congelante
# (2 colpi). Il beam congela i nemici per TUTTO il livello.
var scroll_freeze_phase: int = ScrollPhase.DONE
var scroll_freeze_timer_ms: float = 0.0
var scroll_freeze_item: Node2D = null
var scroll_freeze_beacon: Sprite2D = null
## TASK 36 — apparizioni gia' consumate in questo livello (per TIPO):
## il budget e' PARCHMENT_MAX_SPAWNS (2), ma l'USO e' uno solo.
var scroll_quake_spawns_used: int = 0
var scroll_chasm_spawns_used: int = 0
var scroll_freeze_spawns_used: int = 0
## TASK 50 — equip della pergamena del ghiaccio: 0 = nessuno, 1 = P1,
## 2 = P2; colpi rimasti del raggio congelante.
var freeze_scroll_player: int = 0
var freeze_charges_left: int = 0
var _scroll_rng := RandomNumberGenerator.new()
# FIX (2P): in modalità due giocatori il mini boss immortale NON è uno ma
# DUE, uno per player, e si differenziano SOLO nel colore: quello che
# insegue P1 è VERDE, quello che insegue P2 è ROSSO. In 1P resta il
# singolo fantasma verde.
var ghost_reapers: Array = []
var hurry_up_active: bool = false
var _hurry_up_time: float = 0.0          # animazione testo (blink + drips)
var _since_last_treasure_ms: float = 0.0 # tempo dall'ultimo tesoro raccolto
const HURRY_UP_DELAY_MS: float = 10000.0 # 10s richiesti dall'utente
var _ghost_laugh_cooldown_ms: int = 0    # anti-spam risata tenebrosa
const GHOST_LAUGH_COOLDOWN_MS: int = 1100

# Lightning bolts from scepter (full-screen, hit all enemies/boss on path)
var lightning_bolts: Array = []  # [{pos, life, max_life, zigzag_points}]
var scepter_active: bool = false
var scepter_strikes_left: int = 0
var scepter_timer_ms: int = 0
var initial_enemy_count: int = 0

# TASK 23 (respawn progressivo): conteggio dei nemici vivi al frame
# precedente — quando scende, è stata registrata una KILL e il portale
# progressivo (post-5° boss) riapre per far uscire altri 2 nemici.
var _last_alive_enemies: int = -1

# Items spawned per level
var chalice_item: Node2D = null
var scepter_item: Node2D = null
var mine_item: Collectibles = null
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
# FIX (dinamite del giocatore 2 — bug utente 2P): P2 può raccogliere la
# dinamite ma non poteva lanciarla (il ramo fuoco di P2 non esisteva), la
# miccia esplodeva colpendo P1 e il candelotto veniva disegnato in mano a
# P1 anche se l'aveva raccolto P2. Traccia il PROPRIETARIO (1 = P1, 2 = P2).
var dynamite_player: int = 1
var dynamite_fuse_timer_ms: int = 0  # timer miccia (7000ms = 7s)
var dynamite_alert_played: bool = false
var dynamite_explode_timer_ms: int = 0  # timer esplosione dopo alert (2000ms)
var dynamite_thrown: Node2D = null  # candelotto lanciato in volo

# FIX (pozione magica): pozione (1 per livello) + traccia se l'effetto
# fantasma era attivo nel frame precedente (per fermare la musica e
# ripristinare quella di livello quando termina).
var potion_item: Node2D = null
var _ghost_was_active: bool = false

# ============================================================================
# FIX (martello di Thor — nuova meccanica richiesta dall'utente):
#   * nuovo item HAMMER nel labirinto (1 per livello): 2 lanci;
#   * quando il player che lo possiede SPARA, viene lanciato IL MARTELLO
#     (non un proiettile): vola roteando come Mjolnir;
#   * nemico colpito: 50% dei suoi HP massimi;
#   * muro INTERNO colpito: si ROMPE con effetto sgretolamento e crea un
#     passaggio-scorciatoia usabile da player E nemici (i muri di BORDO non
#     si rompono: non si crea un ulteriore effetto Pac-Man);
#   * dopo l'impatto il martello RITORNA in mano al player; dopo il SECONDO
#     lancio scompare dal player.
# ============================================================================
const HammerClass = preload("res://scripts/items/Hammer.gd")
var hammer_item: Node2D = null          # item a terra (Collectibles.Kind.HAMMER)
var hammer_player: int = 0              # 0 = nessuno, 1 = P1, 2 = P2
var hammer_uses_left: int = 0           # lanci rimasti (max HAMMER_MAX_USES)
var hammer_thrown: Node2D = null        # Hammer in volo (scripts/items/Hammer.gd)
# TASK 50 (martello autofire): stato precedente del pulsante FUOCO dei pad,
# per rilevare il FRONTE di pressione (premuto adesso e NON premuto al frame
# precedente). Il martello e la dinamite si lanciano SOLO sul fronte: tenendo
# il pulsante premuto non si rilancia quando il martello torna in mano
# (sprecava il secondo colpo). Le armi normali mantengono l'autofire held.
var _p1_joy_fire_prev: bool = false
var _p2_joy_fire_prev: bool = false
const HAMMER_MAX_USES: int = 2

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
# FIX (portone di pietra): il portone è ora disegnato proceduralmente (vedi
# _draw_exit_door_stone) — non serve più la texture PNG che sembrava un
# cancello medievale.

# Hash deterministico per la variazione di tono dei blocchi di pietra
# (stabile frame per frame: niente sfarfallio).
static func _stone_hash(i: int) -> float:
        var h: int = (i * 2654435761) % 100000
        return float(h) / 100000.0


# Ritorna una variante leggermente più chiara/scura del colore pietra per il
# blocco `idx` (ogni blocco ha un tono proprio, come la muratura vera).
static func _stone_tint(base: Color, idx: int, amount: float) -> Color:
        var v: float = (_stone_hash(idx) - 0.5) * 2.0 * amount
        return Color(
                clampf(base.r + v, 0.0, 1.0),
                clampf(base.g + v, 0.0, 1.0),
                clampf(base.b + v * 0.9, 0.0, 1.0),
                base.a)


# ============================================================================
# PORTONE DI PIETRA (nuova grafica, disegno accurato)
# ============================================================================
# Struttura del disegno (centrata in door_pos, totale ~100x130 px):
#   1. Aurea dorata pulsante attorno al portale
#   2. Scalinata esterna in blocchi di pietra (3 gradini larghi che salgono
#      alla soglia del portale)
#   3. Arcata interna buia con SCALA CHE SCENDE al piano di sotto: gradini
#      in prospettiva che si restringono verso il fondo scuro, con bagliore
#      caldo che sale dal basso
#   4. Porta: LASTRA DI PIETRA massiccia che scorre VERSO L'ALTO quando si
#      apre (open_ratio 0→1), rivelando la scala sottostante
#   5. Arco esterno a CONCI di pietra (voussoirs) con CHIAVE DI VOLTA
#      decorata da un simbolo dorato, stipiti in blocchi squadrati
#   6. Due torce alle pareti con fiamma tremolante calda
# La pietra usa tinte grigio-neutre con variazione per-blocco deterministica.
func _draw_exit_door_stone(ci: CanvasItem, door_pos: Vector2,
                open_ratio: float, glow: float) -> void:
        # --- Dimensioni totali ---
        var w: float = 100.0            # larghezza arcata esterna
        var arch_h: float = 108.0       # altezza totale arcata
        var door_w: float = 62.0        # larghezza apertura (lastra)
        var door_h: float = 74.0        # altezza apertura (lastra)
        var cx: float = door_pos.x
        # Soglia del portone: il centro verticale dell'apertura
        var cy: float = door_pos.y + 6.0

        # --- Palette pietra (grigio caverna + venature calde) ---
        var stone_base := Color(0.36, 0.34, 0.32)
        var stone_dark := Color(0.24, 0.23, 0.21)
        var stone_light := Color(0.50, 0.48, 0.44)
        var stone_edge := Color(0.16, 0.15, 0.14)

        # ============ (1) AUREA DORATA ============
        ci.draw_circle(door_pos, w * 0.85, Color(1.0, 0.84, 0.35, 0.06 + 0.06 * glow))
        ci.draw_circle(door_pos, w * 0.55, Color(1.0, 0.86, 0.4, 0.08 + 0.08 * glow))

        # ============ (2) SCALINATA ESTERNA (3 gradini che salgono alla soglia) ============
        # I gradini sono più larghi dell'arcata e scendono verso il player.
        var step_h: float = 7.0
        for i in 3:
                var sw: float = door_w + 16.0 + float(i) * 14.0
                var sy: float = cy + door_h * 0.5 + float(i) * step_h
                var st := _stone_tint(stone_base, 40 + i, 0.05)
                # Alzata (faccia verticale del gradino, più scura)
                ci.draw_rect(Rect2(cx - sw * 0.5, sy - step_h, sw, step_h),
                        st.darkened(0.22), true)
                ci.draw_rect(Rect2(cx - sw * 0.5, sy - step_h, sw, step_h),
                        stone_edge, false, 1.0)
                # Pianerottolo (piano superiore del gradino, più chiaro)
                ci.draw_rect(Rect2(cx - sw * 0.5, sy - step_h - 3.0, sw, 3.0),
                        st.lightened(0.12), true)

        # ============ (3) ARCATA INTERNA + SCALA CHE SCENDE ============
        # Il vano interno: buio profondo. La scala scende dal livello della
        # soglia verso il basso lontano (prospettiva: gradini sempre più
        # stretti e scuri), con bagliore caldo che sale dal fondo.
        ci.draw_rect(Rect2(cx - door_w * 0.5, cy - door_h * 0.5, door_w, door_h),
                Color(0.03, 0.025, 0.03), true)
        # Scala in discesa (dal bordo alto verso il fondo, restringendosi)
        var n_steps: int = 7
        for i in n_steps:
                var t: float = float(i) / float(n_steps - 1)
                var stw: float = door_w * (0.94 - t * 0.62)
                var syy: float = cy + door_h * 0.5 - 4.0 - t * (door_h - 14.0)
                var lum: float = 0.55 - t * 0.42
                var step_col := Color(0.30 * lum + 0.05, 0.28 * lum + 0.04, 0.26 * lum + 0.04)
                # Pianerottolo del gradino (riflette la luce dal basso)
                ci.draw_rect(Rect2(cx - stw * 0.5, syy, stw, 3.2), step_col, true)
                # Alzata scura sopra il pianerottolo
                if i < n_steps - 1:
                        ci.draw_rect(Rect2(cx - stw * 0.5, syy - 4.2, stw, 4.2),
                                step_col.darkened(0.45), true)
                # Bordo pietra del gradino
                ci.draw_rect(Rect2(cx - stw * 0.5, syy, stw, 3.2),
                        Color(0.12, 0.11, 0.10), false, 0.5)
        # Bagliore caldo che sale dal fondo della scala (torcia del piano sotto)
        ci.draw_circle(Vector2(cx, cy + door_h * 0.30), 16.0 + glow * 4.0,
                Color(1.0, 0.62, 0.22, 0.16 + 0.08 * glow))
        ci.draw_circle(Vector2(cx, cy + door_h * 0.36), 7.0 + glow * 2.0,
                Color(1.0, 0.78, 0.35, 0.22 + 0.10 * glow))

        # ============ (4) LASTRA DI PIETRA (si solleva) ============
        # La lastra copre il vano e sale con open_ratio, rivelando la scala.
        # Il bordo inferiore è visibile durante il movimento.
        var slab_h: float = door_h
        var lift: float = open_ratio * (door_h * 0.92)
        var slab_top: float = cy - door_h * 0.5 - lift
        # Le due metà visibili della lastra (cornice + pannello)
        var slab_rect := Rect2(cx - door_w * 0.5, slab_top, door_w, slab_h)
        if open_ratio < 0.995:
                # Corpo lastra: blocchi di pietra squadrati
                var slab_col := _stone_tint(stone_base, 77, 0.04)
                ci.draw_rect(slab_rect, slab_col, true)
                # Bordo inferiore levigato (bordo della porta che sale)
                ci.draw_rect(Rect2(slab_rect.position.x, slab_top + slab_h - 5.0,
                        door_w, 5.0), stone_light.lightened(0.06), true)
                ci.draw_rect(Rect2(slab_rect.position.x, slab_top + slab_h - 5.0,
                        door_w, 5.0), stone_edge, false, 1.0)
                # Conci della lastra: 3 file di blocchi con fughe scure
                var rows := 4
                var cols := 3
                for r_i in rows:
                        for c_i in cols:
                                var bx: float = slab_rect.position.x + 3.0 + float(c_i) * (door_w - 6.0) / float(cols)
                                var by: float = slab_top + 3.0 + float(r_i) * (slab_h - 12.0) / float(rows)
                                var bw: float = (door_w - 6.0) / float(cols) - 2.0
                                var bh: float = (slab_h - 12.0) / float(rows) - 2.0
                                if by + bh > slab_top + slab_h - 8.0:
                                        continue
                                ci.draw_rect(Rect2(bx, by, bw, bh),
                                        _stone_tint(stone_base, 100 + r_i * 3 + c_i, 0.06), true)
                # Maniglia ad anello in ferro al centro della lastra
                var ring_c: Vector2 = Vector2(cx, slab_top + slab_h * 0.62)
                ci.draw_arc(ring_c, 4.5, 0.0, TAU, 20,
                        Color(0.16, 0.15, 0.14), 1.8)
                ci.draw_circle(ring_c + Vector2(0, -5.0), 1.6,
                        Color(0.35, 0.33, 0.30))
                # Ombra della lastra sul vano (profondità)
                ci.draw_rect(Rect2(cx - door_w * 0.5, slab_top, door_w, 3.0),
                        Color(0.0, 0.0, 0.0, 0.45), true)

        # ============ (5) ARCO ESTERNO A CONCI + STIPITI + CHIAVE DI VOLTA ============
        # Stipiti laterali: 5 blocchi ciascuno
        var jamb_w: float = 12.0
        for i in 5:
                var by2: float = cy - door_h * 0.5 + float(i) * (door_h / 5.0)
                var bh2: float = door_h / 5.0 - 1.5
                # Sinistro
                ci.draw_rect(Rect2(cx - door_w * 0.5 - jamb_w, by2, jamb_w, bh2),
                        _stone_tint(stone_base, 200 + i, 0.05), true)
                ci.draw_rect(Rect2(cx - door_w * 0.5 - jamb_w, by2, jamb_w, bh2),
                        stone_edge, false, 0.8)
                # Destro
                ci.draw_rect(Rect2(cx + door_w * 0.5, by2, jamb_w, bh2),
                        _stone_tint(stone_base, 210 + i, 0.05), true)
                ci.draw_rect(Rect2(cx + door_w * 0.5, by2, jamb_w, bh2),
                        stone_edge, false, 0.8)
        # Arco a conci: semicerchio di trapezi disposti a raggiera
        var arch_r: float = door_w * 0.5 + jamb_w * 0.5
        var arch_cy: float = cy - door_h * 0.5
        var n_vous: int = 9
        for i in n_vous:
                # Angolo di ogni concio (dal semicerchio sinistro al destro)
                var a: float = PI + (float(i) + 0.5) * PI / float(n_vous)
                var a0: float = PI + float(i) * PI / float(n_vous)
                var a1: float = PI + (float(i) + 1.0) * PI / float(n_vous)
                var r_in: float = arch_r - 2.0
                var r_out: float = arch_r + jamb_w
                # Trapezio del concio (4 vertici tra raggio interno/esterno)
                var p_in0: Vector2 = Vector2(cx + cos(a0) * r_in, arch_cy + sin(a0) * r_in)
                var p_in1: Vector2 = Vector2(cx + cos(a1) * r_in, arch_cy + sin(a1) * r_in)
                var p_out1: Vector2 = Vector2(cx + cos(a1) * r_out, arch_cy + sin(a1) * r_out)
                var p_out0: Vector2 = Vector2(cx + cos(a0) * r_out, arch_cy + sin(a0) * r_out)
                var vous_col := _stone_tint(stone_base, 300 + i, 0.06)
                ci.draw_colored_polygon(PackedVector2Array([p_in0, p_in1, p_out1, p_out0]),
                        vous_col)
                ci.draw_polyline(PackedVector2Array([p_in0, p_in1, p_out1, p_out0, p_in0]),
                        stone_edge, 0.8)
        # Chiave di volta: blocco centrale più grande con simbolo dorato
        var key_w: float = 14.0
        var key_h: float = 16.0
        var key_rect := Rect2(cx - key_w * 0.5, arch_cy - arch_r - key_h * 0.72, key_w, key_h)
        ci.draw_rect(key_rect, _stone_tint(stone_light, 400, 0.03), true)
        ci.draw_rect(key_rect, stone_edge, false, 1.0)
        # Simbolo dorato sulla chiave (rombo runico)
        var rune_c: Vector2 = key_rect.get_center()
        var rune_pts := PackedVector2Array([
                Vector2(rune_c.x, rune_c.y - 4.5),
                Vector2(rune_c.x + 3.5, rune_c.y),
                Vector2(rune_c.x, rune_c.y + 4.5),
                Vector2(rune_c.x - 3.5, rune_c.y),
        ])
        ci.draw_colored_polygon(rune_pts, Color(0.85, 0.68, 0.25, 0.85 + 0.15 * glow))
        ci.draw_circle(Vector2(rune_c.x, rune_c.y), 1.2, Color(1.0, 0.9, 0.55))

        # ============ (6) TORCE ALLE PARETI ============
        # Due piccole torce ai lati dell'arcata, con fiamma tremolante.
        for side in [-1, 1]:
                var tx: float = cx + side * (door_w * 0.5 + jamb_w + 10.0)
                var ty: float = cy - door_h * 0.18
                # Sostegno in ferro
                ci.draw_rect(Rect2(tx - 1.5, ty - 2.0, 3.0, 8.0),
                        Color(0.20, 0.18, 0.16), true)
                ci.draw_rect(Rect2(tx - 3.0, ty - 4.5, 6.0, 3.0),
                        Color(0.25, 0.22, 0.19), true)
                # Fiamma tremolante (due strati + nucleo)
                var flick: float = sin(float(exit_door.get("glow_pulse", 0.0)) * 13.0 + side * 2.1) * 1.2
                ci.draw_circle(Vector2(tx, ty - 7.0 + flick * 0.3), 4.5 + flick * 0.4,
                        Color(1.0, 0.55, 0.15, 0.85))
                ci.draw_circle(Vector2(tx, ty - 8.0 + flick * 0.2), 2.8,
                        Color(1.0, 0.78, 0.30, 0.95))
                ci.draw_circle(Vector2(tx, ty - 8.0), 1.3,
                        Color(1.0, 0.95, 0.70, 1.0))
                # Luce proiettata sulla pietra
                ci.draw_circle(Vector2(tx, ty - 6.0), 10.0,
                        Color(1.0, 0.6, 0.2, 0.12 + 0.05 * glow))

# Frame delta in ms (for timer decrements matching C++ @ 60 FPS)
const FRAME_MS: float = 1000.0 / 60.0


# ============================================================================
# Lifecycle
# ============================================================================
func _ready() -> void:
        print("[MainGameController] VERSION: engine/godot-engine-fixes-v9 - game controller ready")
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
        # FIX (punteggio perso tra le scene): ripristina lo stato dei player
        # portato dalla scena precedente (boss sconfitto -> maze, ecc.). SOLO
        # se NON e' un restore da CONTINUE (quello usa session_snapshot, e le
        # vite devono restare le 3 fresche della scena nuova) e non una
        # partita nuova (livello 1: start_level chiamera' reset()).
        if GameManager and GameManager.current_level > 1 \
                        and not GameManager.session_restore_pending:
                GameManager.restore_player_carry(player, player2)
        # Start the first level
        start_level(current_level)
        # Start level music if enabled
        if AudioManager and GameManager.music_enabled:
                AudioManager.play_level_music(current_level, false)
        # Vignette post-processing — riabilitato (1 full-screen shader, costo minimo).
        if EffectsManager:
                var vignette := EffectsManager.create_vignette_rect()
                add_child(vignette)
        # FIX (pausa P senza feedback visivo): overlay PAUSE sopra tutto.
        _pause_canvas = CanvasLayer.new()
        _pause_canvas.layer = 20
        _pause_overlay = PauseOverlayClass.new()
        _pause_canvas.add_child(_pause_overlay)
        add_child(_pause_canvas)


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
        # Exit door rendering — PORTONE DI PIETRA procedurale (FIX grafica:
        # prima era un PNG che sembrava un cancello medievale). Ora è un
        # portale monumentale in blocchi di pietra: arco a conci con
        # chiave di volta, stipiti in blocchi, lastra di pietra che si
        # SOLLEVA (animazione di apertura 1.4s) rivelando la scalinata
        # interna che scende al piano di sotto, con bagliore caldo dal basso.
        if exit_door.get("active", false) and not is_boss_state:
                var door_pos: Vector2 = exit_door["pos"]
                var anim_ms: int = int(exit_door.get("anim_timer_ms", 0))
                var glow: float = 0.5 + 0.5 * sin(float(exit_door["glow_pulse"]))
                # Animazione di apertura: la lastra di pietra sale (1400ms)
                var open_ratio: float = 1.0
                if anim_ms > 0:
                        open_ratio = 1.0 - (float(anim_ms) / 1400.0)
                        open_ratio = clampf(open_ratio, 0.0, 1.0)
                _draw_exit_door_stone(ci, door_pos, open_ratio, glow)
        # FIX (meccanica "Hurry Up!"): scritta horror lampeggiante in alto,
        # scritta col sangue gocciolante — appare quando tutti i nemici sono
        # stati uccisi e il fantasma immortale emerge dal portale.
        if hurry_up_active:
                _draw_hurry_up_text(ci)
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
                if proj.is_in_group("fx_effect"):
                        continue
                if not is_instance_valid(proj) or not proj.visible:
                        continue
                var ppos: Vector2 = proj.position
                ci.draw_circle(ppos, 6.0, Color(1.0, 0.4, 0.1, 0.4))
                ci.draw_circle(ppos, 3.0, Color(1.0, 0.2, 0.05, 1.0))
        # Dynamite thrown
        if dynamite_thrown != null and is_instance_valid(dynamite_thrown):
                var dt_pos: Vector2 = dynamite_thrown.position
                # FIX (traiettoria parabolica): leggi vel e vy per calcolare
                # l'angolo totale della velocità e ruotare il candelotto
                # secondo la traiettoria (effetto visivo realistico).
                var dt_vel: Vector2 = dynamite_thrown.get_meta("dir", Vector2.ZERO)
                var dt_vy: float = dynamite_thrown.get_meta("vy", 0.0)
                var dt_total_vel: Vector2 = dt_vel + Vector2(0, dt_vy)
                var dt_angle: float = dt_total_vel.angle()
                # Glow circle (NON ruota — aura radiale simmetrica)
                ci.draw_circle(dt_pos, 14.0, Color(1.0, 0.4, 0.1, 0.4))
                # Candelotto ruotato: draw_set_transform sposta l'origine a
                # dt_pos e ruota di dt_angle. I Rect2 diventano relativi a (0,0).
                ci.draw_set_transform(dt_pos, dt_angle, Vector2.ONE)
                ci.draw_rect(Rect2(-5, -10, 10, 20),
                        Color(0.7, 0.12, 0.1, 1.0), true)
                ci.draw_rect(Rect2(-3, -4, 6, 4),
                        Color(0.94, 0.86, 0.7, 1.0), true)
                # Reset del transform per non influenzare i draw successivi
                # (magic portal, etc.)
                ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
        # Magic portal
        if spawner != null and spawner.magic_portal.active:
                var ppos2: Vector2 = spawner.magic_portal.pos
                var prot2: float = spawner.magic_portal.rotation
                var pglow2: float = spawner.magic_portal.glow_pulse
                var aura_r: float = 40.0 + sin(pglow2 * 2.0) * 6.0
                # Aura viola morbida attorno al portale (sia sprite sia proc)
                ci.draw_circle(ppos2, aura_r, Color(0.5, 0.2, 0.8, 0.2))
                # --- TASK 54: portale come sprite animato PixelLab ---
                # (env/portal_sheet.png, 4 frame vortice). Rollback:
                # GameConstants.PORTAL_SPRITE_ENABLED = false -> cerchi.
                if C.PORTAL_SPRITE_ENABLED and _get_portal_sheet() != null:
                        var sheet: Texture2D = _get_portal_sheet()
                        var frame_idx: int = int(prot2 * 2.2 + pglow2 * 3.0) % 4
                        if frame_idx < 0:
                                frame_idx += 4
                        var pulse: float = 1.0 + sin(pglow2 * 2.0) * 0.06
                        var w: float = 84.0 * pulse
                        var src := Rect2(float(frame_idx) * 64.0, 0.0, 64.0, 64.0)
                        var dst := Rect2(ppos2.x - w * 0.5, ppos2.y - w * 0.5, w, w)
                        ci.draw_texture_rect_region(sheet, dst, src, Color.WHITE, false)
                else:
                        for i in 12:
                                var a2: float = prot2 + (float(i) / 12.0) * TAU
                                var p1: Vector2 = ppos2 + Vector2(cos(a2), sin(a2)) * 32.0
                                ci.draw_circle(p1, 3.0, Color(0.7, 0.3, 1.0, 0.7))
                        for i in 8:
                                var a2b: float = -prot2 * 1.5 + (float(i) / 8.0) * TAU
                                var p2: Vector2 = ppos2 + Vector2(cos(a2b), sin(a2b)) * 22.0
                                ci.draw_circle(p2, 2.5, Color(0.3, 0.8, 1.0, 0.8))
                        var core_r: float = 10.0 + sin(pglow2 * 4.0) * 2.0
                        # FIX (pallino procedurale accanto al miniboss, 2° tentativo):
                        # il fix precedente aveva ridotto solo l'alpha del cerchietto
                        # bianco più piccolo (riga 328, alpha 1.0 -> 0.5), MA il
                        # PALLINO VERO era il disco LAVANDA qui sotto (alpha 0.9,
                        # raggio 10px, quasi solido). Ridotto alpha da 0.9 a 0.25:
                        # rimane un nucleo viola tenue che pulsa con glow_pulse,
                        # ma non è più un cerchio solido che appare come "pallino
                        # alieno" accanto al miniboss spawnato 1-4 celle più in là.
                        ci.draw_circle(ppos2, core_r + 4.0, Color(1.0, 1.0, 1.0, 0.1))
                        ci.draw_circle(ppos2, core_r, Color(0.9, 0.7, 1.0, 0.25))
                        # FIX: pallino centrale bianco alpha 0.5 (era 1.0 nel commit
                        # 424b038, confermato invariato).
                        ci.draw_circle(ppos2, core_r * 0.5, Color(1.0, 1.0, 1.0, 0.5))


# ============================================================================
# FIX (meccanica "Hurry Up!"): scritta in alto allo schermo, lampeggiante,
# di colore rosso in stile orrore, come scritta col sangue GOCCIOLANTE.
# Sotto le lettere pendono gocce che crescono, si staccano e cadono, con
# ciclo deterministico (nessun random per frame: stabile e curato).
# ============================================================================
const HURRY_UP_TEXT: String = "Hurry Up!"
const HURRY_UP_FONT_SIZE: int = 84
const HURRY_UP_BASELINE_Y: float = 170.0
# Posizioni delle gocce in frazione della larghezza del testo + fase iniziale.
const HURRY_UP_DRIP_T: Array[float] = [0.07, 0.18, 0.31, 0.44, 0.57, 0.69, 0.82, 0.94]
const HURRY_UP_DRIP_PHASE: Array[float] = [0.0, 1.35, 0.6, 1.8, 0.35, 1.1, 1.6, 0.85]
const HURRY_UP_DRIP_CYCLE: float = 2.6  # durata del ciclo di ogni goccia (s)

func _draw_hurry_up_text(ci: CanvasItem) -> void:
        var font: Font = ThemeDB.fallback_font
        if font == null:
                return
        var t: float = _hurry_up_time
        # --- Lampeggio intermittente (on 0.66s / off 0.34s, con micro-fade) ---
        var blink_phase: float = fmod(t, 1.0)
        var alpha: float
        if blink_phase < 0.66:
                # accensione rapida (0..0.06 fade-in), poi pieno
                alpha = clampf(blink_phase / 0.06, 0.0, 1.0)
        else:
                # spegnimento con dissolvenza del sangue (0.66..1.0)
                alpha = clampf(1.0 - (blink_phase - 0.66) / 0.20, 0.0, 1.0)
        if alpha <= 0.01:
                return
        # Leggero tremolio orror (offset orizzontale/verticale ±1px).
        var shiver_x: float = sin(t * 37.0) * 1.2 * alpha
        var shiver_y: float = cos(t * 29.0) * 0.8 * alpha

        var text_size: Vector2 = font.get_string_size(HURRY_UP_TEXT,
                        HORIZONTAL_ALIGNMENT_LEFT, -1, HURRY_UP_FONT_SIZE)
        var cx: float = C.WINDOW_WIDTH * 0.5 + shiver_x
        var x0: float = cx - text_size.x * 0.5
        var baseline: float = HURRY_UP_BASELINE_Y + shiver_y

        # --- Alalone scuro dietro il testo (sangue che trasuda) ---
        ci.draw_rect(Rect2(x0 - 34.0, baseline - HURRY_UP_FONT_SIZE - 18.0,
                        text_size.x + 68.0, HURRY_UP_FONT_SIZE + 40.0),
                Color(0.28, 0.0, 0.0, 0.16 * alpha), true)
        ci.draw_rect(Rect2(x0 - 24.0, baseline - HURRY_UP_FONT_SIZE - 10.0,
                        text_size.x + 48.0, HURRY_UP_FONT_SIZE + 24.0),
                Color(0.34, 0.0, 0.0, 0.14 * alpha), true)

        # --- Gocce di sangue (sotto la baseline, deterministico) ---
        for i in HURRY_UP_DRIP_T.size():
                var drip_x: float = x0 + text_size.x * HURRY_UP_DRIP_T[i]
                var ct: float = fmod(t + HURRY_UP_DRIP_PHASE[i], HURRY_UP_DRIP_CYCLE)
                # lunghezza massima variabile per goccia (deterministica)
                var max_len: float = 22.0 + 16.0 * (0.5 + 0.5 * sin(float(i) * 2.7))
                var blood: Color = Color(0.62, 0.02, 0.02, alpha)
                var blood_dark: Color = Color(0.38, 0.0, 0.0, alpha)
                if ct < 1.7:
                        # fase 1: la goccia cresce pendendo dalla lettera
                        var len: float = max_len * (ct / 1.7)
                        ci.draw_rect(Rect2(drip_x - 2.5, baseline + 2.0, 5.0, len),
                                blood, true)
                        ci.draw_circle(Vector2(drip_x, baseline + 2.0 + len), 3.4, blood)
                else:
                        # fase 2: la goccia si stacca e cade, il residuo si accorcia
                        var ft: float = (ct - 1.7) / (HURRY_UP_DRIP_CYCLE - 1.7)
                        var resid: float = max_len * (1.0 - ft * 0.55)
                        ci.draw_rect(Rect2(drip_x - 2.5, baseline + 2.0, 5.0, resid),
                                blood_dark, true)
                        var drop_y: float = baseline + 2.0 + resid \
                                        + ft * ft * 74.0
                        var drop_alpha: float = (1.0 - ft) * alpha
                        ci.draw_circle(Vector2(drip_x, drop_y), 3.8,
                                Color(0.62, 0.02, 0.02, drop_alpha))
                        # scia della goccia che cade
                        if ft > 0.15:
                                ci.draw_rect(Rect2(drip_x - 1.5, drop_y - 10.0, 3.0, 8.0),
                                        Color(0.55, 0.02, 0.02, drop_alpha * 0.55), true)

        # --- Testo: ombra scura sotto + passata sangue ---
        ci.draw_string(font, Vector2(x0 + 3.0, baseline + 3.0), HURRY_UP_TEXT,
                        HORIZONTAL_ALIGNMENT_LEFT, -1, HURRY_UP_FONT_SIZE,
                        Color(0.18, 0.0, 0.0, 0.85 * alpha))
        ci.draw_string(font, Vector2(x0, baseline), HURRY_UP_TEXT,
                        HORIZONTAL_ALIGNMENT_LEFT, -1, HURRY_UP_FONT_SIZE,
                        Color(0.72, 0.03, 0.03, alpha))
        # riflesso bagnato in alto (leggero, tipo vernice fresca)
        ci.draw_string(font, Vector2(x0, baseline - 1.5), HURRY_UP_TEXT,
                        HORIZONTAL_ALIGNMENT_LEFT, -1, HURRY_UP_FONT_SIZE,
                        Color(0.85, 0.10, 0.08, 0.35 * alpha))


# FIX (sprite uno sopra l'altro): true se la cella (c, r) NON contiene un
# collectible attivo. Passato a EnemySpawner.trigger_portal_if_needed così
# portale, mini-boss e nemici respawnati non spuntano mai sopra un oggetto.
func _collectible_cell_free(c: int, r: int) -> bool:
        for item in collectibles_node.get_children():
                if item is Node2D and is_instance_valid(item):
                        var active_val: Variant = item.get("active")
                        if active_val != null and not bool(active_val):
                                continue  # già raccolto/inattivo: cella libera
                        var ip: Vector2 = item.position
                        if int(ip.x / C.TILE_SIZE) == c \
                                        and int((ip.y - C.UI_HEIGHT) / C.TILE_SIZE) == r:
                                return false
        return true


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
        # TASK 23: niente pausa/uscita mentre la schermata continue per-player
        # è aperta (l'unico input ammesso è quello dell'overlay).
        if _continue_pending_player != 0:
                return
        # TASK 51 — CARD BONUS: niente pausa/uscita mentre la card informativa
        # e' aperta (l'unico input ammesso e' l'hold del fuoco).
        if _bonus_card != null:
                return
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
        # TASK 51 — CARD BONUS: libera l'overlay e sblocca il tree se si
        # esce dalla scena mentre la card e' aperta (cambio livello/ESC).
        if _bonus_card != null:
                _bonus_card.queue_free()
                _bonus_card = null
                if get_tree():
                        get_tree().paused = false
        # FIX (pausa attiva al cambio scena): se si esce dal MainGame mentre
        # è in pausa (ESC dal menu gestito sotto, transizioni), il tree va
        # ripristinato sennò la scena successiva parte congelata.
        if is_paused:
                is_paused = false
                if get_tree():
                        get_tree().paused = false
        if _game_camera != null and is_instance_valid(_game_camera):
                _game_camera.queue_free()
                _game_camera = null
        if _bg_canvas != null and is_instance_valid(_bg_canvas):
                _bg_canvas.queue_free()
                _bg_canvas = null
        # FIX (porta di fine livello visibile nella schermata boss): il
        # CanvasLayer di foreground (layer = 1, aggiunto al Window root) non
        # veniva MAI liberato. Un CanvasItem non più ridisegnato conserva
        # l'ultimo frame renderizzato: il portale/la porta disegnati
        # dall'OverlayDrawer restavano "congelati" SOPRA la scena successiva
        # (la boss room), come da screenshot utente. Ora viene liberato
        # insieme a camera e background, così nulla sopravvive al cambio scena.
        if _fg_canvas != null and is_instance_valid(_fg_canvas):
                _fg_canvas.queue_free()
                _fg_canvas = null
                _fg_drawer = null


# FIX (pausa P senza feedback visivo): overlay PAUSE (mirror MainGame).
# TASK 51 — CARD BONUS: pure-code CanvasLayer che mostra la card informativa
# alla PRIMA raccolta di un bonus particolare (gioco in pausa, si chiude
# tenendo premuto il fuoco per 1 secondo).
var _bonus_card: CanvasLayer = null
const BonusCardOverlayClass = preload("res://scripts/ui/BonusCardOverlay.gd")

func _physics_process(_delta: float) -> void:
        # TASK 23: continue per-player aperto — gioco CONGELATO (mirror della
        # pausa: nessun update, nessun input di gameplay; l'overlay gira in
        # PROCESS_MODE_ALWAYS e smette da solo alla scelta).
        if _continue_pending_player != 0:
                return
        # TASK 51 — CARD BONUS aperta: gioco in pausa (l'overlay gira in
        # PROCESS_MODE_ALWAYS e si chiude da solo con l'hold del fuoco).
        if _bonus_card != null:
                return
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
        # FIX (2P — pad del giocatore 1 — bug utente): P1 era hardcoded a
        # joy_pads[0] (primo pad collegato). Ora usa il DEVICE salvato in
        # configurazione durante ConfigJoy (JOY_ID): il pad su cui P1 ha
        # premuto i tasti è quello che guida P1, qualunque sia l'ordine di
        # collegamento. Fallback: primo pad collegato (config assente).
        if ConfigManager and ConfigManager.joy_id() >= 0 \
                        and joy_pads.has(ConfigManager.joy_id()):
                p1_joy_id = ConfigManager.joy_id()
        elif joy_pads.size() > 0:
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
                # TASK 50 (martello autofire — bug utente): il ramo martello/
                # dinamite NON controllava lo shoot_cooldown e scattava a
                # OGNI frame di pressione (is_joy_button_pressed = "tenuto
                # premuto"): quando il martello tornava in mano col pulsante
                # ancora premuto, il secondo colpo partiva da solo. Ora
                # martello e dinamite si lanciano SOLO sul FRONTE di pressione
                # (fire_edge, aggiornato SEMPRE anche a pulsante rilasciato);
                # il fuoco delle armi normali resta automatico tenendo premuto
                # (comportamento arcade).
                var fire_now: bool = Input.is_joy_button_pressed(p1_joy_id, joy_shoot_btn)
                var fire_edge: bool = fire_now and not _p1_joy_fire_prev
                _p1_joy_fire_prev = fire_now
                if fire_now:
                        # FIX (dinamite): se il player ha la dinamite equipaggiata,
                        # il fuoco lancia il candelotto invece di sparare.
                        # FIX (dinamite del proprietario — 2P): solo se la dinamite
                        # appartiene a P1 (se l'ha raccolta P2, il fuoco di P1
                        # spara normalmente).
                        # FIX (dinamite non lanciata): niente check shoot_cooldown==0
                        # perché dopo il pickup, shoot_cooldown potrebbe essere > 0
                        # e bloccare il lancio. La dinamite ha il suo cooldown separato.
                        if dynamite_equipped and dynamite_player == 1:
                                if fire_edge:
                                        print("[Dynamite] Joy fire pressed, throwing!")
                                        _throw_dynamite()
                                        player.shoot_cooldown = 300
                        elif freeze_scroll_player == 1 and freeze_charges_left > 0 \
                                        and not is_boss_state and player.shoot_cooldown == 0:
                                # TASK 50: il fuoco spara il RAGGIO
                                # CONGELANTE (2 colpi, solo nel labirinto).
                                # Anche il raggio e' sul FRONTE di pressione
                                # (come dinamite/martello: niente autofire).
                                if fire_edge:
                                        _fire_freeze_ray(player)
                        elif hammer_player == 1 and hammer_thrown == null:
                                # FIX (martello di Thor): il fuoco lancia IL
                                # MARTELLO (fino a 2 volte, poi scompare).
                                # SOLO fronte di pressione: vedi TASK 50 sopra.
                                if fire_edge:
                                        _throw_hammer(player)
                                        player.shoot_cooldown = 300
                        elif player.shoot_cooldown == 0:
                                var ammo_before: int = player.current_weapon.get("ammo", 0)
                                player.shoot()
                                var ammo_after: int = player.current_weapon.get("ammo", 0)
                                if ammo_after < ammo_before and AudioManager \
                                                and not bool(player.current_weapon.get("melee", false)):
                                        AudioManager.play_sound(AudioManager.SoundType.PISTOL)
                                player.shoot_cooldown = C.relic_fire_cooldown(
                                                player.current_weapon)
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
        if Input.is_action_just_pressed("shoot"):
                # FIX (dinamite del proprietario — 2P): anche da tastiera il
                # lancio avviene solo se la dinamite appartiene a P1.
                if dynamite_equipped and dynamite_player == 1:
                        _throw_dynamite()
                        player.shoot_cooldown = 300
                elif freeze_scroll_player == 1 and freeze_charges_left > 0 \
                                and not is_boss_state and player.shoot_cooldown == 0:
                        # TASK 50: raggio congelante da tastiera (P1).
                        _fire_freeze_ray(player)
                elif hammer_player == 1 and hammer_thrown == null:
                        # FIX (martello di Thor): lancio da tastiera (P1).
                        _throw_hammer(player)
                        player.shoot_cooldown = 300
                elif player.shoot_cooldown == 0:
                        var ammo_before: int = player.current_weapon.get("ammo", 0)
                        player.shoot()
                        var ammo_after: int = player.current_weapon.get("ammo", 0)
                        if ammo_after < ammo_before and AudioManager \
                                        and not bool(player.current_weapon.get("melee", false)):
                                AudioManager.play_sound(AudioManager.SoundType.PISTOL)
                        # RELIC (Task 21): cooldown dedicato per reliquia
                        # (Arco del Ranger = raffica 90ms).
                        player.shoot_cooldown = C.relic_fire_cooldown(
                                        player.current_weapon)

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
                # P2 joystick input: il DEVICE configurato per P2 (JOY2_ID,
                # salvato durante ConfigJoy), non il "secondo pad collegato".
                # FIX (2P — bug utente "il pad guida il giocatore 1"): prima
                # era hardcoded a joy_pads[1] e JOY2_ID veniva IGNORATO: con
                # un solo pad (o due pad collegati in ordine diverso) il pad
                # configurato per P2 finiva a guidare P1 e P2 restava senza
                # comandi joystick. Questa è la stessa logica già usata nella
                # boss room (BossRoomController), ora allineata al labirinto.
                var p2_joy_id: int = -1
                if ConfigManager and ConfigManager.joy2_id() >= 0 \
                                and joy_pads.has(ConfigManager.joy2_id()):
                        p2_joy_id = ConfigManager.joy2_id()
                elif joy_pads.size() > 1:
                        p2_joy_id = joy_pads[1]
                # FIX (anti-conflitto): se P1 e P2 risolvono lo STESSO device
                # (entrambi configurati accidentalmente sullo stesso pad), P2
                # prende il primo pad DIVERSO da quello di P1, se esiste;
                # altrimenti resta in tastiera (WASD). Evita che un solo pad
                # guidi entrambi i player simultaneamente.
                if p2_joy_id == p1_joy_id and p1_joy_id >= 0:
                        p2_joy_id = -1
                        for pad_id in joy_pads:
                                if pad_id != p1_joy_id:
                                        p2_joy_id = pad_id
                                        break
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
                                # FIX (parità con P1): suono di salto anche per
                                # P2 (P1 lo aveva, P2 no — "deve funzionare
                                # analogamente al giocatore 1").
                                var was_jumping_2: bool = player2.is_jumping()
                                player2.activate_jump()
                                if not was_jumping_2 and player2.is_jumping() \
                                                and AudioManager:
                                        AudioManager.play_sound(AudioManager.SoundType.JUMP)
                        # TASK 50 (martello autofire): fronte di pressione anche per P2
                        # (stesso fix di P1 — il martello non si rilancia da solo se il
                        # pulsante resta premuto quando torna in mano). L'edge si basa
                        # SOLO sullo stato fisico del pulsante: il cooldown non deve
                        # creare falsi fronti quando scade col pulsante gia' premuto.
                        var fire2_now: bool = Input.is_joy_button_pressed(p2_joy_id, j2_shoot)
                        var fire2_edge: bool = fire2_now and not _p2_joy_fire_prev
                        _p2_joy_fire_prev = fire2_now
                        if fire2_now and player2.shoot_cooldown == 0:
                                # FIX (dinamite del giocatore 2 — bug utente 2P):
                                # prima il ramo dinamite NON esisteva nel fuoco
                                # di P2: poteva raccoglierla ma non lanciarla.
                                # Ora il fuoco di P2 lancia la dinamite se è SUA.
                                if dynamite_equipped and dynamite_player == 2:
                                        if fire2_edge:
                                                _throw_dynamite()
                                                player2.shoot_cooldown = 300
                                elif freeze_scroll_player == 2 and freeze_charges_left > 0 \
                                                and not is_boss_state:
                                        # TASK 50: raggio congelante P2 joystick
                                        # (l'outer check richiede gia' cooldown 0).
                                        # Fronte di pressione come P1.
                                        if fire2_edge:
                                                _fire_freeze_ray(player2)
                                elif hammer_player == 2 and hammer_thrown == null:
                                        # FIX (martello di Thor): lancio P2 joystick.
                                        if fire2_edge:
                                                _throw_hammer(player2)
                                                player2.shoot_cooldown = 300
                                else:
                                        player2.shoot()
                                        player2.shoot_cooldown = C.relic_fire_cooldown(
                                                        player2.current_weapon)
                player2.set_direction(p2_dx, p2_dy)
                if Input.is_action_just_pressed("p2_shoot") and player2.shoot_cooldown == 0:
                        # FIX (dinamite del giocatore 2 — bug utente 2P): ramo
                        # dinamite anche da tastiera (tasto E), come per P1.
                        if dynamite_equipped and dynamite_player == 2:
                                _throw_dynamite()
                                player2.shoot_cooldown = 300
                        elif freeze_scroll_player == 2 and freeze_charges_left > 0 \
                                        and not is_boss_state:
                                # TASK 50: raggio congelante P2 tastiera
                                # (l'outer check richiede gia' cooldown 0).
                                _fire_freeze_ray(player2)
                        elif hammer_player == 2 and hammer_thrown == null:
                                # FIX (martello di Thor): lancio P2 tastiera.
                                _throw_hammer(player2)
                                player2.shoot_cooldown = 300
                        else:
                                player2.shoot()
                                # RELIC (Task 21): cooldown dedicato P2.
                                player2.shoot_cooldown = C.relic_fire_cooldown(
                                                player2.current_weapon)
                if Input.is_action_just_pressed("p2_jump"):
                        # FIX (parità con P1): suono di salto anche da tastiera.
                        var was_jumping_2k: bool = player2.is_jumping()
                        player2.activate_jump()
                        if not was_jumping_2k and player2.is_jumping() and AudioManager:
                                AudioManager.play_sound(AudioManager.SoundType.JUMP)

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
                # FIX (pozione magica): ferma anche il tema fantasma (il
                # canale vive sull'autoload e sopravvivrebbe al cambio scena).
                AudioManager.stop_ghost_music()
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
                # FIX (Hurry Up!): il pickup di un tesoro resetta il conteggio
                # dei 10s — il fantasma appare solo se il player SMETTE di
                # raccogliere tesori con tutti i nemici già morti.
                _since_last_treasure_ms = 0.0
                if AudioManager:
                        AudioManager.play_sound(AudioManager.SoundType.TREASURE)

        # (1b) RELIC (Task 21): passate reliquie — fendenti in mischia (danno
        # ad area ai nemici nella shape), sterzo dei proiettili a ricerca
        # (Bastone dell'Arcimago), esplosione delle bombe a parabola
        # (Alchimista) e pulsazioni dell'aura della Corazza di Fuoco.
        _check_pending_relic_melee(player)
        _steer_relic_homing_projectiles(player)
        _consume_relic_bombs(player)
        _tick_fire_armor(player, delta_ms)
        if GameManager and GameManager.num_players == 2 and player2.visible:
                _check_pending_relic_melee(player2)
                _steer_relic_homing_projectiles(player2)
                _consume_relic_bombs(player2)
                _tick_fire_armor(player2, delta_ms)

        # (1c) TASK 30 — HAZARD AMBIENTALI: update DOPO i player (le celle
        # occupate sono fresche) e PRIMA dei nemici (i flag held_by_wall e
        # hazard_slow sono gia' validi per il movimento nemico del frame).
        # Internamente: telegrafo/apertura voragini, ciclo dei muri di
        # roccia, cattura/mash delle ganasce, rallentamento sabbie.
        hazards.update_hazards(delta_ms, maze)

        # (1d) TASK 32 — NUBE DI PIPISTRELLI: spawn programmato, caccia,
        # morsi e abbattimento (lo sciame vola sopra i muri: niente
        # interazione col maze, solo con player e proiettili).
        _update_bat_cloud(delta_ms)

        # (1e) TASK 35 — PERGAMENE EVENTO: scheduling (momento casuale,
        # solo con >= 50% di nemici vivi), telegrafo luminoso, vita a
        # terra 10s + 2s di lampeggio, raccolta = effetto immediato.
        _update_parchments(delta_ms)

        # (2) Enemies update
        # FIX (2P — nemici ignoravano P2): ogni nemico insegue il player VIVO
        # più VICINO a sé (P1 o P2). Prima passavamo solo la posizione di P1:
        # in 2P il giocatore 2 vagava indisturbato senza mai essere inseguito.
        # Il flee mode (calice) è per-nemico: fuggono solo i nemici il cui
        # bersaglio è invincibile (se P1 ha il calice ma il nemico sta
        # pressando P2, quel nemico NON scappa).
        var p_pos: Vector2 = player.get_pixel_pos()
        var p_grid: Vector2i = player.get_grid_pos()
        var player_invuln: bool = player.is_invulnerable()
        # Collect enemy projectiles in a real array (enemies that shoot add to it)
        var enemy_projectiles: Array = []
        for enemy in spawner.enemies:
                if not enemy.is_death_anim_done():
                        var target_p: CharacterBody2D = _nearest_alive_player(enemy.get_pixel_pos())
                        if target_p != null:
                                enemy.set_flee_mode(target_p.is_invulnerable())
                                enemy.update_enemy(maze, target_p.get_grid_pos(),
                                        target_p.get_pixel_pos(), enemy_projectiles, delta_ms)
                        else:
                                enemy.set_flee_mode(player_invuln)
                                enemy.update_enemy(maze, p_grid, p_pos, enemy_projectiles, delta_ms)

        # FIX (deriva fuori asse -> compenetrazione muri): RIMOSSA la
        # separazione nemici-nemici (push di 1px/frame entro 32px). Il push
        # spostava i nemici FUORI dalla linea centrale dei corridoi, rompendo
        # l'invariante del movimento grid-locked (vedi Enemy.update_enemy):
        # lo sprite usciva dal corridoio e compenetrava i muri, e i "fix" a
        # cascata (clamp di rendering, snap, teleport) generavano gli scatti.
        # Nel C++ originale i nemici si sovrappongono liberamente (come i
        # fantasmi di Pac-Man): due nemici sulla stessa cella divergono
        # naturalmente al centro cella successivo se il BFS dà direzioni
        # diverse, quindi la separazione non serve e fa solo danno.

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
                if proj.is_in_group("fx_effect"):
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
        _check_melee_collisions(player, delta_ms)
        if GameManager and GameManager.num_players == 2 and player2.visible:
                _check_melee_collisions(player2, delta_ms)

        # (7) Invincibility burn (chalice effect)
        _update_invincible_burn(player, delta_ms)
        if GameManager and GameManager.num_players == 2 and player2.visible:
                _update_invincible_burn(player2, delta_ms)

        # (7b) 2P friendly fire: if both players are within contact range
        # (~28 px, dist^2 < 800) and neither is invulnerable or jumping,
        # both take 1 damage. Mirrors C++ Game.cpp 1846-1862.
        _check_2p_friendly_fire()

        # (7b-2) FUOCO AMICO (Task 18 — richiesta utente): i PROIETTILI di un
        # player colpiscono l'altro player (il danno da contatto resta OFF,
        # vedi (7b)). Colpo non fatale: -1 energia con invulnerabilita' di 1s
        # (identico a un colpo nemico). Colpo FATALE (ultima energia): il
        # corpo della vittima si accascia al suolo, la sua anima si separa e
        # vola veloce verso il vincitore ricaricandogli COMPLETAMENTE
        # l'energia (SoulTransferEffect -> _start_soul_transfer).
        _check_friendly_fire_projectiles()

        # (7c) FIX (2P): eliminazione del player senza vite (non più "zombie").
        _check_player_elimination()

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
        # FIX (martello di Thor): volo del martello lanciato (andata, impatto,
        # ritorno in mano al player).
        _update_thrown_hammer(delta_ms)

        # (9e) Last hit enemy timer (FIX: HUD nemico colpito)
        if last_hit_enemy_timer_ms > 0:
                last_hit_enemy_timer_ms -= int(delta_ms)
                if last_hit_enemy_timer_ms <= 0:
                        last_hit_enemy = null
        # Se il nemico è morto o non più valido, cleanup
        if last_hit_enemy != null and (not is_instance_valid(last_hit_enemy) or last_hit_enemy.is_dead()):
                last_hit_enemy = null
                last_hit_enemy_timer_ms = 0

        # (9f) FIX (pozione magica): fine dell'effetto fantasma — ferma il tema
        # fantasmagorico e ripristina la musica di livello. Il timer/scadenza
        # dell'effetto è gestito da Player.update_player (unico owner).
        var ghost_now: bool = player.is_ghost() or (GameManager and GameManager.num_players == 2 \
                        and player2.visible and player2.is_ghost())
        if ghost_now:
                _ghost_was_active = true
        elif _ghost_was_active:
                _ghost_was_active = false
                if AudioManager:
                        AudioManager.stop_ghost_music()
                        # Ripristina la musica di livello se attiva (e se non
                        # c'è un calice in corso sul canale epic: quella va
                        # fermata dal suo gestore, non qui).
                        if AudioManager.music_enabled and not AudioManager._epic_playing:
                                AudioManager.play_level_music(current_level, false)

        # (10) Exit door logic (treasures collected)
        _update_exit_door(delta_ms)

        # (11) Magic portal (50% enemies killed) - spawn mini-boss too
        # FIX (sprite uno sopra l'altro): passa anche il check delle celle
        # occupate da collectible: portale, mini-boss e respawn non devono
        # MAI spuntare sopra mine/calice/scetturo/statua/pozione.
        # TASK 23 (respawn progressivo): prima del trigger, rileva le KILL
        # del frame (alive_count sceso) — nel post-5° boss ogni kill riapre
        # il portale con 2 nemici finché il budget del livello non è esaurito.
        if _last_alive_enemies >= 0:
                var alive_now: int = spawner.alive_count()
                if alive_now < _last_alive_enemies:
                        spawner.notify_enemy_killed(maze)
                _last_alive_enemies = spawner.alive_count()
        else:
                _last_alive_enemies = spawner.alive_count()
        spawner.trigger_portal_if_needed(maze, p_pos, _spawn_mini_boss,
                _collectible_cell_free)
        spawner.update_portal(maze, int(delta_ms))

        # (11h) FIX (meccanica "Hurry Up!"): timer tesori + trigger del
        # fantasma immortale quando tutti i nemici (respawn compresi) sono
        # morti da 10s dall'ultimo tesoro raccolto; il fantasma insegue
        # finché il player non passa la porta.
        _update_hurry_up(delta_ms, p_grid, p_pos)

        # (11b) MiniBoss update + melee collision (mirror C++ riga 1581-1633)
        # FIX CRASH: MiniBoss espone update_step(maze, p_grid, p_pos, delta_ms)
        # non update_enemy(). Il crash "Nonexistent function 'update_enemy'"
        # bloccava il gioco dopo qualche minuto quando il portal spawnava un
        # mini-boss.
        # FIX (2P): anche il miniboss insegue il player vivo più vicino e
        # colpisce in melee CHUNQUE è a portata (P1 o P2), non solo P1.
        if mini_boss != null and not mini_boss.is_dead():
                var mb_target: CharacterBody2D = _nearest_alive_player(mini_boss.get_pixel_pos())
                if mb_target == null:
                        mb_target = player
                mini_boss.set_flee_mode(mb_target.is_invulnerable())
                mini_boss.update_step(maze, mb_target.get_grid_pos(),
                                mb_target.get_pixel_pos(), int(delta_ms))
                # MiniBoss melee attack: if attacking and target in range, damage
                # FIX CRASH: MiniBoss non ha get_pixel_pos(); usa la property
                # `pos` (Vector2) direttamente con .get().
                if mini_boss.has_method("is_attacking") and mini_boss.is_attacking():
                        var mb_pos: Vector2 = mini_boss.get("pos") if mini_boss.get("pos") != null else Vector2.ZERO
                        var mb_range: float = 36.0  # default attack range
                        if mini_boss.has_method("get_attack_range"):
                                mb_range = mini_boss.get_attack_range()
                        # FIX (2P): il colpo melee arriva a qualunque player a
                        # portata (prima solo P1: P2 poteva stare accanto al
                        # miniboss senza conseguenze).
                        for melee_p in _alive_players():
                                if melee_p.get_pixel_pos().distance_squared_to(mb_pos) < (mb_range + 10) ** 2:
                                        if not melee_p.is_invulnerable() and not melee_p.is_jumping():
                                                var mb_dmg: int = 5  # default
                                                if mini_boss.has_method("get_attack_damage"):
                                                        mb_dmg = mini_boss.get_attack_damage()
                                                var num_hits: int = max(1, mb_dmg / 5)
                                                for _i in num_hits:
                                                        melee_p.take_damage()
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


## TASK 61 — archetipi dei player attivi (selettore del pool armi del
## labirinto: umani -> armi da fuoco, non-umani -> elementali).
func _collect_char_types() -> Array:
        var out: Array = []
        if player != null and is_instance_valid(player):
                out.append(player.character_type)
        if GameManager and GameManager.num_players == 2 \
                        and player2 != null and is_instance_valid(player2):
                out.append(player2.character_type)
        return out


func _check_player_projectiles_vs_enemies(p: CharacterBody2D) -> void:
        # Player.gd stores projectiles as Array[Dictionary] with keys:
        # pos, dir, power, active, type
        # RELIC (Task 21): i proiettili reliquia passano dallo stesso flusso
        # con le loro flag di comportamento:
        #   * pierce_left/hit_ids (Balestra d'Argento): il dardo ATTRAVERSA
        #     fino a 3 nemici (non si ferma sul primo, non rivolve lo stesso);
        #   * chain (Verga della Tempesta): sul primo colpo il fulmine SALTA
        #     fino a 2 nemici entro chain_radius_px dal bersaglio;
        #   * Corazza del Furore: take_weapon_hit con fury=true (-1
        #     hit-to-kill, floor 2) e +1 flat sul mini-boss.
        var fury: bool = p.is_fury_active()
        for proj in p.projectiles:
                if not proj.get("active", false):
                        continue
                var proj_pos: Vector2 = proj.get("pos", Vector2.ZERO)
                var hit_something: bool = false
                var hit_ids: Array = proj.get("hit_ids", [])
                for enemy in spawner.enemies:
                        if enemy.is_dead():
                                continue
                        if hit_ids.has(enemy):
                                continue  # gia' colpito da QUESTO dardo perforante
                        var e_pos: Vector2 = enemy.get_pixel_pos()
                        if proj_pos.distance_squared_to(e_pos) < 600.0:
                                # FIX (nessuna arma one-shot — richiesta utente):
                                # il danno delle armi da fuoco e' calcolato in %
                                # degli HP massimi del nemico in base all'arma
                                # (pistola 4 colpi, laser 3, shotgun 2, razzo
                                # 2). NESSUNA arma uccide con un colpo solo:
                                # solo mina, dinamite e item magici
                                # (calice/scettro) restano kill istantanei.
                                # TASK 61 — COLPO DI GRAZIA ELEMENTALE + penalita'
                                # affinita'. Il colpo che ucciderebbe il
                                # nemico innesca lo stato della def:
                                # burn_ms -> si infuoca e muore (start_burning,
                                # macchinario aura/dinamite esistente);
                                # freeze -> statua di ghiaccio (freeze_kill,
                                # macchinario raggio congelante Task 50).
                                # Il danno normale passa comunque da
                                # take_weapon_hit con il char_type del tiratore
                                # per la penalita' -50% fuori affinita'.
                                var w_type61: int = int(proj.get("type", 0))
                                var edef61: Dictionary = C.get_relic_def(w_type61)
                                var dmg61: int = C.weapon_damage_for(w_type61,
                                                enemy.max_health, fury,
                                                p.character_type)
                                if enemy.health - dmg61 <= 0 \
                                                and not edef61.is_empty() \
                                                and not enemy.is_dead():
                                        if int(edef61.get("burn_ms", 0)) > 0:
                                                enemy.start_burning(
                                                                int(edef61.get("burn_ms", 30)))
                                        elif bool(edef61.get("freeze", false)):
                                                enemy.freeze_kill()
                                        else:
                                                enemy.take_weapon_hit(w_type61, fury,
                                                                p.character_type)
                                else:
                                        enemy.take_weapon_hit(w_type61, fury,
                                                        p.character_type)
                                hit_ids.append(enemy)
                                # TASK 51 (P3) — KNOCKBACK da armi reliquia a
                                # DISTANZA: spinta visiva ~24px in direzione
                                # opposta al player + stun 400ms (cap 1.5s).
                                # Le mischia non sparano proiettili: se il
                                # proiettile ha una def reliquia di famiglia
                                # "distanza" e' un arco/balestra/bomba/ecc.
                                var kdef: Dictionary = C.get_relic_def(
                                                int(proj.get("type", 0)))
                                if not kdef.is_empty() \
                                                and kdef.get("family", "") == "distanza":
                                        var kdir: Vector2 = (e_pos - p.get_pixel_pos()).normalized()
                                        enemy.apply_knockback(kdir, 24.0)
                                        if not enemy.is_dead():
                                                enemy.apply_stun(400)
                                # RELIC (Task 21) — Verga della Tempesta: il
                                # fulmine salta ai nemici vicini al bersaglio.
                                if proj.has("chain"):
                                        _apply_storm_chain(p, proj, enemy, e_pos, fury)
                                # RELIC (Task 21) — Balestra d'Argento: il
                                # dardo perfora fino a pierce_max nemici IN
                                # TUTTO e PROSEGUE (pierce_left>1 = altri hit).
                                var pierce_left: int = int(proj.get("pierce_left", 0))
                                if pierce_left > 1:
                                        proj["pierce_left"] = pierce_left - 1
                                        continue
                                proj["active"] = false
                                # FIX (HUD last hit enemy): traccia il nemico colpito
                                # SOLO nel labirinto (non boss room). Nella boss room
                                # la barra HP è gestita dal BossRoomController.
                                if not is_boss_state:
                                        last_hit_enemy = enemy
                                        last_hit_enemy_timer_ms = 3000  # 3s di visibilità
                                if enemy.is_dead():
                                        _on_relic_enemy_killed(p, e_pos)
                                hit_something = true
                                break
                # FIX (mid-boss immune): controlla anche il mini-boss.
                # Prima i proiettili passavano attraverso il mini-boss senza
                # fare danno perché non era incluso nel loop degli enemies.
                if not hit_something and mini_boss != null and is_instance_valid(mini_boss):
                        if not mini_boss.is_dead():
                                var mb_pos: Vector2 = mini_boss.get_pixel_pos()
                                var mb_dist_sq: float = proj_pos.distance_squared_to(mb_pos)
                                if mb_dist_sq < 1200.0:  # radius ~35px
                                        # RELIC (Task 21): +1 flat col Furore.
                                        var dmg: int = int(proj.get("power", 1)) \
                                                        + (1 if fury else 0)
                                        mini_boss.take_damage(dmg)
                                        proj["active"] = false
                                        # FIX (HUD last hit enemy): traccia MiniBoss
                                        if not is_boss_state:
                                                last_hit_enemy = mini_boss
                                                last_hit_enemy_timer_ms = 3000
                                        if AudioManager:
                                                AudioManager.play_sound(AudioManager.SoundType.BOSS_HIT)
                                        if mini_boss.is_dead():
                                                p.add_score(10000)
                                                if AudioManager:
                                                        AudioManager.play_sound(AudioManager.SoundType.BOSS_DEATH)
                # FIX (Hurry Up! — fantasma immortale): i proiettili NON lo
                # uccidono: colpirlo fa sentire la risata tenebrosa (via
                # segnale laughed) e il proiettile viene assorbito
                # dall'ectoplasma. In 2P ci sono DUE fantasmi (verde P1,
                # rosso P2): entrambi assorbono i proiettili.
                if not hit_something:
                        for ghost in ghost_reapers:
                                if ghost == null or not is_instance_valid(ghost):
                                        continue
                                var g_pos: Vector2 = ghost.get_pixel_pos()
                                if proj_pos.distance_squared_to(g_pos) < 1500.0:  # raggio ~39px
                                        ghost.take_damage(int(proj.get("power", 1)))
                                        proj["active"] = false
                                        hit_something = true
                                        break


func _check_enemy_projectiles_vs_player(p: CharacterBody2D) -> void:
        for proj in enemy_projectiles_node.get_children():
                if not proj is Node2D or not proj.visible:
                        continue
                if proj.is_in_group("fx_effect"):
                        continue
                var proj_pos: Vector2 = proj.position
                if proj_pos.distance_squared_to(p.get_pixel_pos()) < 600.0:
                        # RELIC (Task 21) — SCAGLIE DEL DRAGO: il proiettile
                        # nemico RIMBALZA (assorbito e ri-sparato dal player
                        # in direzione opposta col danno del suo miglior colpo).
                        if _reflect_enemy_projectile_if_armored(p, proj, proj_pos):
                                break
                        p.take_damage()
                        proj.visible = false
                        if AudioManager:
                                AudioManager.play_sound(AudioManager.SoundType.LOSE_LIFE)
                        break


# RELIC (Task 21) — SCAGLIE DEL DRAGO (riflessione, mirror boss room): il
# proiettile nemico che sta per colpire il player rimbalza — assorbito dalle
# scaglie e ri-sparato dal player in direzione OPPOSTA (nel labirinto non
# c'e' un boss da prendere di mira) col danno del suo MIGLIOR colpo (max 5).
# Una carica a rimbalzo, 4 in tutto, poi l'armatura si rompe.
func _reflect_enemy_projectile_if_armored(p: CharacterBody2D, proj: Node2D,
                proj_pos: Vector2) -> bool:
        if not p.try_reflect_projectile():
                return false
        proj.queue_free()
        var back: Vector2 = -Vector2(proj.get_meta("velocity", Vector2(1.0, 0.0)))
        if back.length_squared() < 0.001:
                back = Vector2(1.0, 0.0)
        back = back.normalized()
        p.projectiles.append({
                "pos": proj_pos + back * 20.0,
                "dir": back,
                "power": C.reflect_bolt_power(p.current_weapon),
                "active": true,
                "type": C.RelicType.REFLECT_BOLT,
                "relic": "reflect_bolt",
        })
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.REFLECT_BOLT)
        if EffectsManager:
                EffectsManager.screen_shake(3.0, 0.15)
        return true


# ============================================================================
# RELIC (Task 21) — passate reliquie nel labirinto
# ============================================================================

# Kill-effects condivisi da tutte le fonti reliquia (mischia, bombe, catena,
# aura, spine, dardi perforanti): punteggio + suoni + macchie + scoppio.
func _on_relic_enemy_killed(p: CharacterBody2D, pos: Vector2) -> void:
        p.add_score(5000)
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.ENEMY_DEATH)
                AudioManager.play_sound(AudioManager.SoundType.BLOOD_SPLAT)
                AudioManager.play_sound(AudioManager.SoundType.ENEMY_EXPLODE)
        _spawn_blood_stain(pos)
        _spawn_fire_burst(pos, 1.0)


# Fendente in mischia: shoot() con arma mischia alza melee_pending; qui si
# consuma e si applica il danno a TUTTI i nemici (e al mini-boss) nella shape:
#   * Spadone: settore 120 gradi raggio 2 celle;  * Ascia: settore + splash
#     attorno al bersaglio;  * Mazza: cerchio + STORDIMENTO 1s;  * Alabarda:
#     linea perforante 3 celle;  * Lama del Vampiro: cura 1 energia per colpo;
#   * Martello del Golem: cerchio stretto + stun breve + scossa.
func _check_pending_relic_melee(p: CharacterBody2D) -> void:
        if not p.melee_pending:
                return
        var def: Dictionary = p.consume_melee_pending()
        if def.is_empty():
                return
        var fury: bool = p.is_fury_active()
        var aim: Vector2 = Vector2(
                        float(p.dx if p.dx != 0 else p.last_dx),
                        float(p.dy if p.dy != 0 else p.last_dy))
        if aim == Vector2.ZERO:
                aim = Vector2(1.0, 0.0)
        var p_pos: Vector2 = p.get_pixel_pos()
        var hits: int = 0
        var primary_hits: Array = []
        # TASK 51 (P4) — Spadone "max_targets": cap esplicito di nemici per
        # fendente (4 per lo Spadone buffato). Se il def NON ha max_targets
        # il comportamento resta quello storico (tutti i nemici nella shape).
        # Selettore NEAREST-FIRST: con piu' nemici nell'arco di quanti ne
        # possa colpire, vincono i piu' vicini (colpo "fisico" che parte
        # dal player, non dall'angolo piu' comodo).
        var max_targets: int = int(def.get("max_targets", 0))
        var in_shape: Array = []
        for enemy in spawner.enemies:
                if enemy.is_dead():
                        continue
                var e_pos: Vector2 = enemy.get_pixel_pos()
                if not C.relic_melee_in_shape(def, aim, p_pos, e_pos):
                        continue
                in_shape.append([p_pos.distance_squared_to(e_pos), enemy])
        in_shape.sort_custom(func(a, b): return a[0] < b[0])
        for pair in in_shape:
                if max_targets > 0 and hits >= max_targets:
                        break
                var enemy = pair[1]
                var e_pos: Vector2 = enemy.get_pixel_pos()
                enemy.take_damage(C.relic_melee_damage(def, enemy.max_health, fury))
                primary_hits.append(enemy)
                hits += 1
                if def.get("stun_ms", 0) > 0 and not enemy.is_dead():
                        enemy.apply_stun(int(def["stun_ms"]))
                if not is_boss_state:
                        last_hit_enemy = enemy
                        last_hit_enemy_timer_ms = 3000
                if enemy.is_dead():
                        _on_relic_enemy_killed(p, e_pos)
                # Lama del Vampiro: cura 1 energia per nemico colpito.
                if bool(def.get("vampiric", false)) and not p.soul_pending:
                        p.energy = mini(p.max_energy, p.energy + 1)
        # Ascia del Berserker: scheggia ad area attorno a OGNI bersaglio primario.
        if def.has("splash_px"):
                var splash_px: float = float(def["splash_px"])
                var splash_hits: int = int(def.get("splash_hits", 4))
                for prim in primary_hits:
                        if prim.is_dead():
                                continue
                        var prim_pos: Vector2 = prim.get_pixel_pos()
                        for enemy2 in spawner.enemies:
                                if enemy2.is_dead() or primary_hits.has(enemy2):
                                        continue
                                if prim_pos.distance_squared_to(enemy2.get_pixel_pos()) \
                                                < splash_px * splash_px:
                                        var splash_dmg: int = maxi(1, int(ceil(
                                                        float(enemy2.max_health) / float(splash_hits))))
                                        enemy2.take_damage(splash_dmg)
                                        if enemy2.is_dead():
                                                _on_relic_enemy_killed(p, enemy2.get_pixel_pos())
        # Mini-boss nella shape: danno flat (+1 col Furore).
        if mini_boss != null and is_instance_valid(mini_boss) and not mini_boss.is_dead():
                if C.relic_melee_in_shape(def, aim, p_pos, mini_boss.get_pixel_pos()):
                        mini_boss.take_damage(C.relic_melee_flat_damage(def, fury))
                        hits += 1
                        if AudioManager:
                                AudioManager.play_sound(AudioManager.SoundType.BOSS_HIT)
                        if mini_boss.is_dead():
                                p.add_score(10000)
                                if AudioManager:
                                        AudioManager.play_sound(AudioManager.SoundType.BOSS_DEATH)
        # TASK 34 (richiesta utente — "i pipistrelli devono poter essere
        # eliminati sia con lo sparo che con le spade..."): la nube di
        # pipistrelli dentro la shape del fendente prende UN colpo per
        # fendente (due fendenti la disperdono, come per i proiettili).
        # Conta come colpo andato a segno anche per la scossa del Golem.
        if bat_cloud != null and is_instance_valid(bat_cloud):
                if C.relic_melee_in_shape(def, aim, p_pos, bat_cloud.position):
                        bat_cloud.take_projectile_hit(p)
                        hits += 1
        # Scossa visiva del Martello del Golem (cerchio): il colpo pesante
        # si FA sentire anche quando non prende nessuno.
        if hits == 0 and str(def.get("shape", "")) == "circle" and EffectsManager:
                EffectsManager.screen_shake(3.0, 0.12)


# Sterzo dei proiettili a RICERCA (Bastone dell'Arcimago): la sfera insegue
# il nemico (o mini-boss) VIVO piu' vicino alla sua posizione corrente.
func _steer_relic_homing_projectiles(p: CharacterBody2D) -> void:
        for proj in p.projectiles:
                if not proj.get("active", false) or not proj.get("homing", false):
                        continue
                var proj_pos: Vector2 = proj.get("pos", Vector2.ZERO)
                var target_pos: Vector2 = Vector2.INF
                var best_d: float = INF
                for enemy in spawner.enemies:
                        if enemy.is_dead():
                                continue
                        var d: float = proj_pos.distance_squared_to(enemy.get_pixel_pos())
                        if d < best_d:
                                best_d = d
                                target_pos = enemy.get_pixel_pos()
                if mini_boss != null and is_instance_valid(mini_boss) \
                                and not mini_boss.is_dead():
                        var dmb: float = proj_pos.distance_squared_to(mini_boss.get_pixel_pos())
                        if dmb < best_d:
                                best_d = dmb
                                target_pos = mini_boss.get_pixel_pos()
                if target_pos == Vector2.INF:
                        continue
                var desired: Vector2 = (target_pos - proj_pos).normalized()
                proj["dir"] = proj.get("dir", Vector2(1, 0)).lerp(desired, 0.09).normalized()


# VERGA DELLA TEMPESTA: catena di fulmini — dal primo bersaglio colpito il
# danno salta fino a `chain` nemici entro chain_radius_px (nessun re-hit).
# TASK 23 (fix utente): la catena è VISIBILE — LightningArcEffect disegna il
# fulmine che attraversa player → nemico1 → nemico2 → ... per ~340ms.
func _apply_storm_chain(p: CharacterBody2D, proj: Dictionary,
                first_enemy: Node2D, first_pos: Vector2, fury: bool) -> void:
        var jumps_left: int = int(proj.get("chain", 0))
        if jumps_left <= 0 or first_enemy == null:
                return
        var radius: float = float(proj.get("chain_radius_px", 128.0))
        var chained: Array = [first_enemy]
        var type: int = int(proj.get("type", 0))
        var arc_path: Array = [p.get_pixel_pos(), first_pos]
        for enemy in spawner.enemies:
                if jumps_left <= 0:
                        break
                if enemy.is_dead() or chained.has(enemy):
                        continue
                if first_pos.distance_squared_to(enemy.get_pixel_pos()) \
                                < radius * radius:
                        enemy.take_weapon_hit(type, fury, p.character_type)
                        chained.append(enemy)
                        arc_path.append(enemy.get_pixel_pos())
                        jumps_left -= 1
                        if EffectsManager:
                                var spark := EffectsManager.spawn_sparks(
                                                enemy.get_pixel_pos(), 10)
                                collectibles_node.add_child(spark)
                        if not is_boss_state:
                                last_hit_enemy = enemy
                                last_hit_enemy_timer_ms = 3000
                        if enemy.is_dead():
                                _on_relic_enemy_killed(p, enemy.get_pixel_pos())
        # TASK 23: il fulmine SI VEDE attraversare i nemici (traiettoria).
        if arc_path.size() >= 2:
                var arc: Node2D = LightningArcFx.new()
                arc.setup(arc_path)
                add_child(arc)
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.LIGHTNING)


# BOMBE dell'Alchimista: i proiettili "exploded" (parabola finita o muro o
# bordo) esplodono AD AREA: tutti i nemici entro radius_px prendono il danno
# (frazione HP come le armi), il mini-boss quello flat.
func _consume_relic_bombs(p: CharacterBody2D) -> void:
        var to_remove: Array = []
        var fury: bool = p.is_fury_active()
        for proj in p.projectiles:
                if not (proj.get("exploded", false) and not proj.get("consumed", false)):
                        continue
                proj["consumed"] = true
                to_remove.append(proj)
                var blast_pos: Vector2 = proj.get("pos", Vector2.ZERO)
                var radius: float = float(proj.get("radius_px", 96.0))
                var type: int = int(proj.get("type", 0))
                for enemy in spawner.enemies:
                        if enemy.is_dead():
                                continue
                        if blast_pos.distance_squared_to(enemy.get_pixel_pos()) \
                                        < radius * radius:
                                enemy.take_weapon_hit(type, fury, p.character_type)
                                if enemy.is_dead():
                                        _on_relic_enemy_killed(p, enemy.get_pixel_pos())
                if mini_boss != null and is_instance_valid(mini_boss) \
                                and not mini_boss.is_dead():
                        if blast_pos.distance_squared_to(mini_boss.get_pixel_pos()) \
                                        < radius * radius:
                                mini_boss.take_damage(int(proj.get("power", 4)) \
                                                + (1 if fury else 0))
                                if mini_boss.is_dead():
                                        p.add_score(10000)
                                        if AudioManager:
                                                AudioManager.play_sound(AudioManager.SoundType.BOSS_DEATH)
                # TASK 34 (pipistrelli): le Bombe dell'Alchimista sono un'arma
                # bonus — lo scoppio nel raggio disperde SUBITO lo sciame.
                if bat_cloud != null and is_instance_valid(bat_cloud):
                        if blast_pos.distance_squared_to(bat_cloud.position) \
                                        < radius * radius:
                                bat_cloud.take_explosion_hit(p)
                if EffectsManager:
                        var boom := EffectsManager.spawn_explosion(blast_pos,
                                        Color(1.0, 0.6, 0.15), 30, 0.8)
                        collectibles_node.add_child(boom)
                        EffectsManager.screen_shake(8.0, 0.3)
                if AudioManager:
                        AudioManager.play_sound(AudioManager.SoundType.ENEMY_EXPLODE)
        for proj in to_remove:
                p.projectiles.erase(proj)


# CORAZZA DI FUOCO (aura): a ogni pulsazione (aura_ms) TUTTI i nemici entro
# aura_radius_px prendono aura_damage flat; carica a pulsazione (20 in tutto).
func _tick_fire_armor(p: CharacterBody2D, delta_ms: float) -> void:
        if not p.has_relic_armor():
                return
        if not p.armor_aura_pulse(delta_ms):
                return
        var radius: float = float(p.armor_relic.get("aura_radius_px", 64.0))
        var aura_dmg: int = int(p.armor_relic.get("aura_damage", 1))
        var p_pos: Vector2 = p.get_pixel_pos()
        for enemy in spawner.enemies:
                if enemy.is_dead():
                        continue
                if p_pos.distance_squared_to(enemy.get_pixel_pos()) < radius * radius:
                        enemy.take_damage(aura_dmg)
                        if enemy.is_dead():
                                _on_relic_enemy_killed(p, enemy.get_pixel_pos())
        if mini_boss != null and is_instance_valid(mini_boss) \
                        and not mini_boss.is_dead():
                if p_pos.distance_squared_to(mini_boss.get_pixel_pos()) \
                                < radius * radius:
                        mini_boss.take_damage(aura_dmg)
        # TASK 34 (pipistrelli): la Corazza di Fuoco e' un'arma bonus — lo
        # sciame che si avvicina per mordere brucia a ogni pulsazione
        # dell'aura (due pulsazioni lo disperdono).
        if bat_cloud != null and is_instance_valid(bat_cloud):
                if p_pos.distance_squared_to(bat_cloud.position) < radius * radius:
                        bat_cloud.take_projectile_hit(p)
        if EffectsManager:
                var ring := EffectsManager.spawn_explosion(p_pos,
                                Color(1.0, 0.45, 0.2), 12, 0.4)
                collectibles_node.add_child(ring)
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.ENEMY_EXPLODE)


# FIX (bomba non esplode all'impatto): controlla collisione tra la mine
# (quando sta bouncing) e i nemici. Se la mine tocca un nemico, esplode:
# danno ad area (radius 60px), particelle esplosione, screen shake,
# sparisce immediatamente invece di rimanere per terra immobile.
# FIX (bomba supera muri): controlla collisione tra la mine (quando bouncing)
# e i muri del maze. Se la mine sta per entrare in una cella WALL, inverte
# la velocità (rimbalzo elastico arcade, NON damped).
# FIX (bomba homing): ogni 250ms ricalcola la direzione verso il nemico più
# vicino (incluso mini-boss) usando BFS. La bomba "segue il labirinto".
# FIX (bomba gira per sempre): la mina ora ESPLODE automaticamente dopo 6
# secondi dal lancio anche se non colpisce nessun nemico. I nemici entro il
# raggio di scoppio (60px, "pochi pixel") vengono uccisi dall'esplosione;
# il mini-boss perde il 50% dell'energia. L'esplosione è la stessa dell'impatto
# diretto (usa _explode_mine).
func _check_mine_vs_enemies() -> void:
        if mine_item == null or not is_instance_valid(mine_item):
                return
        if not mine_item.bouncing:
                # FIX (bomba esplode quando finisce): se la mine non è più bouncing
                # ma è ancora nel tree, esplodi con danno AoE e rimuovi.
                if not mine_item.active:
                        _explode_mine(mine_item.position)
                        mine_item.queue_free()
                        mine_item = null
                return
        var mine_pos2: Vector2 = mine_item.position
        var mine_vel: Vector2 = mine_item.velocity
        # =========================================================================
        # TASK 50 (mina si blocca al primo muro e torna indietro in loop):
        # riscritto l'homing. VECCHIO modello: ogni 250ms il BFS dava una
        # direzione axis-aligned; tra un ricalcolo e l'altro la mina andava
        # dritto e RIMBALZAVA elasticamente sui muri, finendo in oscillazione
        # destra-sinistra finché non esplodeva. NUOVO modello: path-FOLLOWING
        # continuo — BFS completo (BFS.find_path_cells), la mina insegue il
        # centro del waypoint corrente, avanza appena entra nella cella e
        # ricalcola appena il nemico si sposta di cella (o ogni 200ms).
        # Nessun rimbalzo: se un passo finisse in un muro, scivola sull'asse
        # libero (mai inversione di direzione).
        # =========================================================================
        var mine_cell := Vector2i(int(mine_pos2.x / C.TILE_SIZE),
                        int((mine_pos2.y - C.UI_HEIGHT) / C.TILE_SIZE))
        var best_enemy: Node2D = null
        var best_dist: float = INF
        for enemy in spawner.enemies:
                if enemy.is_dead():
                        continue
                var e_pos: Vector2 = enemy.get_pixel_pos()
                var d: float = mine_pos2.distance_squared_to(e_pos)
                if d < best_dist:
                        best_dist = d
                        best_enemy = enemy
        if mini_boss != null and not mini_boss.is_dead():
                var mb_pos: Vector2 = mini_boss.get_pixel_pos()
                var d_mb: float = mine_pos2.distance_squared_to(mb_pos)
                if d_mb < best_dist:
                        best_dist = d_mb
                        best_enemy = mini_boss
        var homing_timer: int = mine_item.homing_ms
        homing_timer -= 16
        if best_enemy != null and homing_timer <= 0:
                var bpos: Vector2 = best_enemy.get_pixel_pos()
                var target_cell := Vector2i(int(bpos.x / C.TILE_SIZE),
                                int((bpos.y - C.UI_HEIGHT) / C.TILE_SIZE))
                var new_path: Array[Vector2i] = BFS.find_path_cells(maze, mine_cell, target_cell)
                if new_path.size() > 0:
                        mine_item.path_cells = new_path
                        mine_item.path_idx = 0
                homing_timer = 200
        # --- Segui il waypoint corrente (steering continuo) ---
        var speed: float = clampf(mine_vel.length(), 6.0, 7.5)
        if mine_item.path_cells.size() > 0 and best_enemy != null:
                # avanza i waypoint gia' raggiunti (cella corrente o sorpassati)
                while mine_item.path_idx < mine_item.path_cells.size():
                        var wp: Vector2i = mine_item.path_cells[mine_item.path_idx]
                        if wp == mine_cell:
                                mine_item.path_idx += 1
                                continue
                        break
                if mine_item.path_idx < mine_item.path_cells.size():
                        var wp2: Vector2i = mine_item.path_cells[mine_item.path_idx]
                        var step_d: Vector2i = wp2 - mine_cell
                        var tgt: Vector2
                        if absi(step_d.x) > 1 or absi(step_d.y) > 1:
                                # Tunnel Pac-Man: il waypoint e' l'imbocco partner
                                # opposto. Vola VERSO L'ESTERNO dal proprio imbocco:
                                # il tunnel_wrap teletrasporta e il waypoint dopo
                                # l'attraversamento e' adiacente di nuovo.
                                # direzione d'uscita = verso il bordo piu' vicino
                                # dell'imbocco (la cella corrente e' di bordo)
                                var outward: Vector2 = Vector2(
                                        signf(float(mine_cell.x) - float(C.MAZE_COLS - 1) * 0.5),
                                        signf(float(mine_cell.y) - float(C.MAZE_ROWS - 1) * 0.5))
                                if absf(outward.x) > absf(outward.y):
                                        outward = Vector2(signf(outward.x), 0)
                                else:
                                        outward = Vector2(0, signf(outward.y))
                                tgt = mine_pos2 + outward * 80.0
                        else:
                                tgt = Vector2((wp2.x + 0.5) * C.TILE_SIZE,
                                                C.UI_HEIGHT + (wp2.y + 0.5) * C.TILE_SIZE)
                        var to_t: Vector2 = tgt - mine_pos2
                        if to_t.length() > 1.0:
                                mine_vel = to_t.normalized() * speed
                else:
                        # percorso esaurito: puntala direttamente al nemico
                        var direct: Vector2 = best_enemy.get_pixel_pos() - mine_pos2
                        if direct.length() > 1.0:
                                mine_vel = direct.normalized() * speed
        elif best_enemy != null:
                # nessun percorso BFS (nemico irraggiungibile / stessa cella):
                # puntala direttamente al nemico
                var direct2: Vector2 = best_enemy.get_pixel_pos() - mine_pos2
                if direct2.length() > 1.0:
                        mine_vel = direct2.normalized() * speed
        # --- Movimento con SLIDE sui muri (mai rimbalzo) + wrap tunnel ---
        var new_pos: Vector2 = mine_pos2 + mine_vel
        var cur_col: int = int(mine_pos2.x / C.TILE_SIZE)
        var cur_row: int = int((mine_pos2.y - C.UI_HEIGHT) / C.TILE_SIZE)
        if new_pos.x < 0.0 or new_pos.x >= C.WINDOW_WIDTH \
                        or new_pos.y < C.UI_HEIGHT or new_pos.y >= C.WINDOW_HEIGHT:
                var wrapped_mine: Vector2 = GameConstants.tunnel_wrap(new_pos)
                if wrapped_mine != new_pos:
                        new_pos = wrapped_mine
        var next_col: int = int(new_pos.x / C.TILE_SIZE)
        var next_row: int = int((new_pos.y - C.UI_HEIGHT) / C.TILE_SIZE)
        if next_col >= 0 and next_col < C.MAZE_COLS and next_row >= 0 and next_row < C.MAZE_ROWS:
                var blocked_x: bool = next_col != cur_col and maze.is_wall(next_col, cur_row)
                var blocked_y: bool = next_row != cur_row and maze.is_wall(cur_col, next_row)
                var blocked_diag: bool = (next_col != cur_col or next_row != cur_row) \
                                and maze.is_wall(next_col, next_row)
                if blocked_x and blocked_y:
                        # angolo: resta dov'e' e forza ricalcolo percorso
                        new_pos = mine_pos2
                        homing_timer = 0
                elif blocked_diag and not blocked_x and not blocked_y:
                        # taglio dell'angolo: muovi solo sull'asse che resta libero
                        if not maze.is_wall(cur_col, next_row):
                                new_pos = Vector2(mine_pos2.x, new_pos.y)
                        else:
                                new_pos = Vector2(new_pos.x, mine_pos2.y)
                elif blocked_x:
                        new_pos = Vector2(mine_pos2.x, new_pos.y)
                elif blocked_y:
                        new_pos = Vector2(new_pos.x, mine_pos2.y)
        mine_item.homing_ms = homing_timer
        mine_pos2 = new_pos
        # Aggiorna posizione e velocità della mine
        mine_item.position = mine_pos2
        mine_item.velocity = mine_vel
        mine_item.pos = mine_pos2
        # Damage check: se un nemico è entro il raggio, esplode (uso AoE)
        var blast_radius: float = 60.0
        var blast_radius_sq: float = blast_radius * blast_radius
        var hit_any: bool = false
        for enemy in spawner.enemies:
                if enemy.is_dead():
                        continue
                var e_pos: Vector2 = enemy.get_pixel_pos()
                if mine_pos2.distance_squared_to(e_pos) < blast_radius_sq:
                        hit_any = true
                        break
        if not hit_any and mini_boss != null and not mini_boss.is_dead():
                var mb_pos2: Vector2 = mini_boss.get_pixel_pos()
                if mine_pos2.distance_squared_to(mb_pos2) < blast_radius_sq:
                        hit_any = true
        if hit_any:
                _explode_mine(mine_pos2)
                mine_item.queue_free()
                mine_item = null


# FIX (bomba esplode dopo 6s): esplosione unificata della mina — usata sia
# quando colpisce un nemico direttamente, sia allo scadere dei 6 secondi.
# Uccide tutti i nemici entro il raggio di scoppio (60px) e toglie il 50%
# dell'energia massima al mini-boss se è nel raggio. Effetti: esplosione,
# screen shake, flash e suono.
func _explode_mine(explode_pos: Vector2) -> void:
        var blast_radius: float = 60.0
        var blast_radius_sq: float = blast_radius * blast_radius
        # Danno Ai nemici normali: uccisione istantanea + burning + punteggio
        for enemy in spawner.enemies:
                if enemy.is_dead():
                        continue
                var e_pos: Vector2 = enemy.get_pixel_pos()
                if explode_pos.distance_squared_to(e_pos) < blast_radius_sq:
                        enemy.take_damage(999)
                        enemy.start_burning(30)
                        player.add_score(2000)
        # Danno al mini-boss: 50% degli HP massimi
        if mini_boss != null and not mini_boss.is_dead():
                var mb_pos: Vector2 = mini_boss.get_pixel_pos()
                if explode_pos.distance_squared_to(mb_pos) < blast_radius_sq:
                        var mb_max_hp: int = mini_boss.get_max_health()
                        mini_boss.take_damage(int(mb_max_hp * 0.5))
        # TASK 34 (pipistrelli): la mina e' un'arma bonus — l'esplosione nel
        # raggio disperde SUBITO lo sciame (punti al player).
        if bat_cloud != null and is_instance_valid(bat_cloud):
                if explode_pos.distance_squared_to(bat_cloud.position) < blast_radius_sq:
                        bat_cloud.take_explosion_hit(player)
        # Effetti visivi + audio
        if EffectsManager:
                var burst := EffectsManager.spawn_explosion(explode_pos,
                        Color(1.0, 0.4, 0.1), 40, 1.0)
                collectibles_node.add_child(burst)
                EffectsManager.screen_shake(12.0, 0.4)
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.ENEMY_EXPLODE)
        screen_flash_timer_ms = 80


func _check_melee_collisions(p: CharacterBody2D, delta_ms: float = 16.0) -> void:
        var p_pos: Vector2 = p.get_pixel_pos()
        if p.is_invulnerable() or p.is_jumping():
                # Jump-over-enemy: grant speed boost
                if p.is_jumping():
                        for enemy in spawner.enemies:
                                if enemy.is_dead():
                                        continue
                                if p_pos.distance_squared_to(enemy.get_pixel_pos()) < 800.0:
                                        p.set_jump_speed_boost(2000)  # FIX: 2s acceleration
                                        break
                return
        for enemy in spawner.enemies:
                if enemy.is_dead():
                        continue
                if p_pos.distance_squared_to(enemy.get_pixel_pos()) < 800.0:
                        # TASK 23 (fix bug utente) — CORAZZA DI FUOCO: il
                        # contatto con un nemico mentre l'aura è attiva
                        # USTISCE IL NEMICO (danno frazione HP max, vedi
                        # GameConstants.relic_aura_contact_damage), consuma
                        # UNA carica dell'armatura e il player NON subisce il
                        # colpo. Prima: il player prendeva danno, l'armatura
                        # non calava e il nemico non subiva nulla.
                        if p.armor_aura_contact_proc(delta_ms):
                                var burn_dmg: int = C.relic_aura_contact_damage(
                                                p.armor_relic, enemy.get_max_health())
                                enemy.take_damage(burn_dmg)
                                if enemy.is_dead():
                                        _on_relic_enemy_killed(p, enemy.get_pixel_pos())
                                if AudioManager:
                                        AudioManager.play_sound(AudioManager.SoundType.BOSS_HIT)
                                if EffectsManager:
                                        var fb := EffectsManager.spawn_sparks(
                                                        enemy.get_pixel_pos(), 8)
                                        collectibles_node.add_child(fb)
                                continue
                        # RELIC (Task 21) — OSSIDIANA DEL CREPUSCOLO: chi
                        # tocca il player in mischia prende 2 danni da
                        # spine (una carica per colpo inflitto, 5 in tutto).
                        var thorn_dmg: int = p.consume_thorn_charge()
                        if thorn_dmg > 0:
                                enemy.take_damage(thorn_dmg)
                                if enemy.is_dead():
                                        _on_relic_enemy_killed(p, enemy.get_pixel_pos())
                        p.take_damage()
                        if AudioManager:
                                AudioManager.play_sound(AudioManager.SoundType.LOSE_LIFE)
                        break
        # FIX (Hurry Up! — fantasmi immortali): il contatto con UN QUALSIASI
        # fantasma fa danno come i nemici (si può solo scappare!). In 2P ci
        # sono due fantasmi (verde per P1, rosso per P2) e ognuno insegue il
        # SUO player, ma il contatto danneggia qualunque player tocchi.
        for ghost in ghost_reapers:
                if ghost == null or not is_instance_valid(ghost):
                        continue
                if p_pos.distance_squared_to(ghost.get_pixel_pos()) < 800.0:
                        p.take_damage()
                        if AudioManager:
                                AudioManager.play_sound(AudioManager.SoundType.LOSE_LIFE)
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


func _update_invincible_burn(p: CharacterBody2D, _delta_ms: float) -> void:
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
        # FIX (doppio decremento timer calice): il timer è già decrementato da
        # Player.update_player (unico owner del tick). Qui si legge soltanto:
        # prima veniva scalato UNA SECONDA volta per frame e l'effetto durava
        # la metà del valore impostato.
        if p.invincible_timer <= 0:
                # FIX (musica calice): quando l'effetto del calice termina,
                # ferma la musica epic (era in loop per tutta la durata) e
                # ripristina la musica di livello se la musica è attiva.
                if AudioManager and AudioManager._epic_playing:
                        AudioManager.stop_epic_music()
                        if AudioManager.music_enabled:
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
                        # FIX (calice non sottrae energia al miniboss): la
                        # funzione start_burning() in MiniBoss.gd imposta SOLO
                        # burning_timer_ms e burned_flag per l'animazione, MA
                        # NON riduce gli HP. Per i nemici normali il danno
                        # finale viene dato in _update_invincible_burn riga
                        # 1111-1127 (enemy.take_damage(999) quando
                        # burning_timer scade). Per il miniboss quel loop NON
                        # viene eseguito (itera solo spawner.enemies), quindi
                        # il miniboss si brucia visualmente ma non perde mai
                        # energia. Ora infliggiamo il danno qui direttamente:
                        # 35% degli HP massimi del miniboss (mirror del
                        # scepter lightning che fa 35% dei max HP).
                        var mb_dmg: int = int(mini_boss.get_max_health() * 0.35)
                        if mb_dmg < 1:
                                mb_dmg = 1
                        mini_boss.take_damage(mb_dmg)
                        p.add_score(2000)


# FIX (2P — P2 spawnava dentro il muro): il posizionamento fisso a
# P1.x + TILE_SIZE metteva P2 nella cella (2,1), che nel labirinto DFS è
# un muro in circa il 50% dei livelli (colonna pari: scavata solo se il
# corridoio (1,1)->(3,1) esiste). Cerchiamo invece la cella APERTA più
# vicina a P1 seguendo un ordine di preferenza fisso (destra, giù, su,
# sinistra, poi gli anelli successivi) e piazziamo P2 al suo centro:
# mai dentro un muro, mai sopra P1. Nota: la cella (1,2) è odd-odd, quindi
# SEMPRE aperta nel maze DFS -> la ricerca riesce sempre entro il 2° tentativo.
const _P2_SPAWN_PREF: Array[Vector2i] = [
        Vector2i(1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(-1, 0),
        Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
        Vector2i(2, 0), Vector2i(0, 2), Vector2i(2, 1), Vector2i(1, 2),
        Vector2i(-1, 2), Vector2i(-2, 0), Vector2i(0, -2), Vector2i(2, -1),
        Vector2i(-2, 1), Vector2i(1, -2), Vector2i(-1, -2), Vector2i(-2, -1),
        Vector2i(2, 2), Vector2i(-2, 2), Vector2i(2, -2), Vector2i(-2, -2),
        Vector2i(3, 0), Vector2i(0, 3), Vector2i(3, 1), Vector2i(1, 3),
]


func _place_player2_near_p1() -> void:
        var p1_col: int = int(player.position.x / C.TILE_SIZE)
        var p1_row: int = int((player.position.y - C.UI_HEIGHT) / C.TILE_SIZE)
        for off in _P2_SPAWN_PREF:
                var c: int = p1_col + off.x
                var r: int = p1_row + off.y
                if c < 1 or c >= C.MAZE_COLS - 1 or r < 1 or r >= C.MAZE_ROWS - 1:
                        continue
                if maze.is_wall(c, r):
                        continue
                player2.position = Vector2(
                                c * C.TILE_SIZE + C.TILE_SIZE / 2.0,
                                r * C.TILE_SIZE + C.TILE_SIZE / 2.0 + C.UI_HEIGHT)
                return
        # Retroguardia (maze degenere): vecchio posizionamento a fianco di P1.
        player2.position = Vector2(player.position.x + C.TILE_SIZE,
                        player.position.y)


# FIX (2P): helper — true se il player 2 esiste, è attivo e visibile in
# questa partita (usato dal rendering della dinamite del proprietario).
func _is_p2_active() -> bool:
        return GameManager != null and GameManager.num_players == 2 \
                        and player2 != null and is_instance_valid(player2) \
                        and player2.visible


# FIX (2P): lista dei player vivi (vite > 0) in gioco. In 1P contiene
# solo P1; in 2P contiene P1 e/o P2 finché hanno vite (il player eliminato
# scompare dalla lista: niente più danni/targeting su un morto).
# FUOCO AMICO (Task 18): il player in attesa dell'anima (soul_pending) è
# escluso: è già caduto, non è né un bersaglio né un "vivo" per l'IA.
func _alive_players() -> Array:
        var out: Array = []
        if player != null and is_instance_valid(player) and player.lives > 0 \
                        and not player.soul_pending:
                out.append(player)
        if GameManager and GameManager.num_players == 2 and player2 != null \
                        and is_instance_valid(player2) and player2.visible and player2.lives > 0 \
                        and not player2.soul_pending:
                out.append(player2)
        return out


# ============================================================================
# TASK 32 — NUBE DI PIPISTRELLI (evento casuale per livello)
# ============================================================================

## Scheduling + update dello sciame: spawn alla scadenza del timer, caccia
## fino a morte/dispersione, poi (se restano eventi) riarmo del timer.
func _update_bat_cloud(delta_ms: float) -> void:
        if not C.BATS_ENABLED:
                return
        if bat_cloud != null and is_instance_valid(bat_cloud):
                var players: Array = _alive_players()
                bat_cloud.set_players_ref(players)
                bat_cloud.update_cloud(delta_ms, players)
                if bat_cloud.is_gone():
                        bat_cloud.queue_free()
                        bat_cloud = null
                        if bat_events_left > 0:
                                bat_event_timer_ms = float(_bat_rng.randi_range(
                                        C.BAT_CLOUD_SECOND_MIN_MS,
                                        C.BAT_CLOUD_SECOND_MAX_MS))
                return
        if bat_events_left <= 0:
                return
        bat_event_timer_ms -= delta_ms
        if bat_event_timer_ms <= 0.0:
                bat_events_left -= 1
                _spawn_bat_cloud()


## Spawna lo sciame in un punto casuale dell'area di gioco, lontano da
## OGNI player vivo (min ~6 celle): nessun morso a tradimento.
func _spawn_bat_cloud() -> void:
        var players: Array = _alive_players()
        if players.is_empty():
                # nessun player vivo: evento rimandato (non consumato)
                bat_events_left += 1
                bat_event_timer_ms = 5000.0
                return
        var pos: Vector2 = Vector2.ZERO
        for _attempt in 60:
                pos = Vector2(
                        float(_bat_rng.randi_range(80, int(C.WINDOW_WIDTH) - 80)),
                        float(_bat_rng.randi_range(int(C.UI_HEIGHT) + 90,
                                        int(C.WINDOW_HEIGHT) - 70)))
                var far_enough: bool = true
                for p in players:
                        if p.position.distance_to(pos) < C.BAT_CLOUD_MIN_SPAWN_DIST:
                                far_enough = false
                                break
                if far_enough:
                        break
        bat_cloud = BatCloudClass.new()
        bat_cloud.position = pos
        bat_cloud.set_players_ref(players)
        add_child(bat_cloud)


# ============================================================================
# TASK 35 — PERGAMENE EVENTO: terremoto + voragini magiche
# ============================================================================

## Reset a inizio livello: pulizia difensiva di item/beacon rimasti e
## programmazione dei due timer (seed RNG per livello: al continue gli
## orari di apparizione si ripetono, come gli hazard).
func _reset_parchments(level: int) -> void:
        _free_scroll_visuals()
        scroll_quake_phase = ScrollPhase.DONE
        scroll_chasm_phase = ScrollPhase.DONE
        scroll_freeze_phase = ScrollPhase.DONE
        scroll_quake_spawns_used = 0
        scroll_chasm_spawns_used = 0
        scroll_freeze_spawns_used = 0
        # TASK 50: l'equip della pergamena del ghiaccio NON sopravvive al
        # cambio livello (i colpi non usati sono persi, come il martello).
        _unequip_freeze_scroll()
        if not C.PARCHMENTS_ENABLED or level < C.PARCHMENT_GRACE_LEVEL:
                return
        _scroll_rng.seed = hash("scrolls_v1_%d" % level)
        scroll_quake_phase = ScrollPhase.WAIT
        scroll_quake_timer_ms = float(_scroll_rng.randi_range(
                C.PARCHMENT_FIRST_MIN_MS, C.PARCHMENT_FIRST_MAX_MS))
        scroll_chasm_phase = ScrollPhase.WAIT
        scroll_chasm_timer_ms = float(_scroll_rng.randi_range(
                C.PARCHMENT_FIRST_MIN_MS, C.PARCHMENT_FIRST_MAX_MS))
        # TASK 50: la pergamena del ghiaccio usa le STESSE finestre
        # temporali delle altre due (stesse tempistiche di apparizione).
        # Il suo draw RNG avviene DOPO quake e chasm: le sequenze dei due
        # eventi esistenti restano IDENTICHE ai livelli precedenti.
        if C.SCROLL_FREEZE_ENABLED:
                scroll_freeze_phase = ScrollPhase.WAIT
                scroll_freeze_timer_ms = float(_scroll_rng.randi_range(
                        C.PARCHMENT_FIRST_MIN_MS, C.PARCHMENT_FIRST_MAX_MS))


## Libera item a terra e beacon di entrambe le pergamene (fine livello /
## reset difensivo). Le voragini magiche vivono in MazeHazards e vengono
## ripulite da hazards.generate() -> clear().
func _free_scroll_visuals() -> void:
        if scroll_quake_item != null:
                if is_instance_valid(scroll_quake_item):
                        scroll_quake_item.queue_free()
                scroll_quake_item = null
        if scroll_quake_beacon != null:
                if is_instance_valid(scroll_quake_beacon):
                        scroll_quake_beacon.queue_free()
                scroll_quake_beacon = null
        if scroll_chasm_item != null:
                if is_instance_valid(scroll_chasm_item):
                        scroll_chasm_item.queue_free()
                scroll_chasm_item = null
        if scroll_chasm_beacon != null:
                if is_instance_valid(scroll_chasm_beacon):
                        scroll_chasm_beacon.queue_free()
                scroll_chasm_beacon = null
        # TASK 50: pulizia difensiva anche della pergamena del ghiaccio.
        if scroll_freeze_item != null:
                if is_instance_valid(scroll_freeze_item):
                        scroll_freeze_item.queue_free()
                scroll_freeze_item = null
        if scroll_freeze_beacon != null:
                if is_instance_valid(scroll_freeze_beacon):
                        scroll_freeze_beacon.queue_free()
                scroll_freeze_beacon = null


## Macchina a stati delle due pergamene (WAIT -> BEACON -> GROUND -> DONE).
## TASK 36: la condizione "almeno il 30% dei nemici ancora vivi" viene
## verificata ALLA SCADENZA del timer: se non e' soddisfatta si riprova
## dopo PARCHMENT_RETRY_MS; se il budget di PARCHMENT_MAX_SPAWNS
## apparizioni e' esaurito, l'evento si chiude (DONE).
func _update_parchments(delta_ms: float) -> void:
        _update_one_scroll(delta_ms, true)   # terremoto
        _update_one_scroll(delta_ms, false)  # voragini
        _update_freeze_scroll(delta_ms)      # TASK 50: ghiaccio


func _update_one_scroll(delta_ms: float, is_quake: bool) -> void:
        var phase: int = scroll_quake_phase if is_quake else scroll_chasm_phase
        match phase:
                ScrollPhase.WAIT:
                        var timer: float = scroll_quake_timer_ms if is_quake \
                                        else scroll_chasm_timer_ms
                        timer -= delta_ms
                        if timer <= 0.0:
                                # TASK 36: budget apparizioni esaurito?
                                var spawns_used: int = scroll_quake_spawns_used \
                                                if is_quake else scroll_chasm_spawns_used
                                if spawns_used >= C.PARCHMENT_MAX_SPAWNS:
                                        if is_quake:
                                                scroll_quake_phase = ScrollPhase.DONE
                                        else:
                                                scroll_chasm_phase = ScrollPhase.DONE
                                        return
                                # condizione: almeno il 30% dei nemici vivi
                                var alive: int = spawner.alive_count()
                                var total: int = maxi(1, spawner.initial_count)
                                if float(alive) >= float(total) * C.PARCHMENT_MIN_ALIVE_PCT:
                                        _start_scroll_beacon(is_quake)
                                        return
                                # troppi morti: riprova piu' tardi
                                timer = float(C.PARCHMENT_RETRY_MS)
                        if is_quake:
                                scroll_quake_timer_ms = timer
                        else:
                                scroll_chasm_timer_ms = timer
                ScrollPhase.BEACON:
                        var tb: float = scroll_quake_timer_ms if is_quake \
                                        else scroll_chasm_timer_ms
                        tb -= delta_ms
                        # pulsazione del bagliore (cresce verso l'apparizione)
                        var beacon: Sprite2D = scroll_quake_beacon if is_quake \
                                        else scroll_chasm_beacon
                        if beacon != null and is_instance_valid(beacon):
                                var k: float = 1.0 - tb / float(C.PARCHMENT_TELEGRAPH_MS)
                                var pulse_k: float = 0.75 + 0.25 * sin(
                                                _time_now() * 16.0)
                                beacon.scale = Vector2.ONE * (0.55 + k * 0.75) * pulse_k
                                beacon.rotation += delta_ms / 900.0
                        if tb <= 0.0:
                                _spawn_scroll_item(is_quake)
                                return
                        if is_quake:
                                scroll_quake_timer_ms = tb
                        else:
                                scroll_chasm_timer_ms = tb
                ScrollPhase.GROUND:
                        # il lifetime (10s + 2s blink) vive nel Collectibles;
                        # qui si vigilano scomparsa (active=false) e validita'.
                        var item: Node2D = scroll_quake_item if is_quake \
                                        else scroll_chasm_item
                        if item == null or not is_instance_valid(item) \
                                        or not item.active:
                                _consume_scroll_ground(is_quake, false)
                ScrollPhase.DONE:
                        pass


## Orologio di scena per le pulsazioni (secondi).
func _time_now() -> float:
        return Time.get_ticks_msec() / 1000.0


## Fase BEACON: accende il bagliore/aura sulla cella scelta (PRIMA ancora
## dell'apparizione, come richiesto: "emette una luce, un bagliore, un'aura
## nei pressi prima di apparire").
func _start_scroll_beacon(is_quake: bool) -> void:
        var cell := _random_empty_cell()
        if cell == Vector2i(-1, -1):
                # nessuna cella libera (labirinto degenere): riprova piu' tardi
                if is_quake:
                        scroll_quake_timer_ms = float(C.PARCHMENT_RETRY_MS)
                else:
                        scroll_chasm_timer_ms = float(C.PARCHMENT_RETRY_MS)
                return
        var pos: Vector2 = _cell_to_pixel(cell)
        var beacon := Sprite2D.new()
        var tex: Texture2D = load("res://assets/sprites/parchment/beacon_glow.png")
        if tex != null:
                beacon.texture = tex
        beacon.position = pos
        beacon.scale = Vector2.ONE * 0.55
        # arancio fuoco per il terremoto, viola psichico per le voragini
        beacon.modulate = Color(1.0, 0.55, 0.2, 0.85) if is_quake \
                        else Color(0.7, 0.45, 1.0, 0.85)
        beacon.z_index = 5  # sopra pavimento e hazard, sotto le entita'
        collectibles_node.add_child(beacon)
        if is_quake:
                scroll_quake_beacon = beacon
                scroll_quake_phase = ScrollPhase.BEACON
                scroll_quake_timer_ms = float(C.PARCHMENT_TELEGRAPH_MS)
                scroll_quake_item = null
                # memorizza la cella per lo spawn dell'item
                set_meta("scroll_quake_cell", cell)
        else:
                scroll_chasm_beacon = beacon
                scroll_chasm_phase = ScrollPhase.BEACON
                scroll_chasm_timer_ms = float(C.PARCHMENT_TELEGRAPH_MS)
                scroll_chasm_item = null
                set_meta("scroll_chasm_cell", cell)
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.HAZARD_RUMBLE)
        if EffectsManager:
                EffectsManager.screen_shake(2.0, 0.2)


## Fase GROUND: il bagliore si spegne, un FULMINE SI ABBATE AL SUOLO
## sulla cella (TASK 36: apparizione eclatante) e la pergamena appare.
func _spawn_scroll_item(is_quake: bool) -> void:
        var meta_key: String = "scroll_quake_cell" if is_quake else "scroll_chasm_cell"
        var cell: Vector2i = get_meta(meta_key, Vector2i(-1, -1))
        var beacon: Sprite2D = scroll_quake_beacon if is_quake else scroll_chasm_beacon
        if beacon != null and is_instance_valid(beacon):
                beacon.queue_free()
        if cell == Vector2i(-1, -1):
                cell = _random_empty_cell()
        if cell == Vector2i(-1, -1):
                _consume_scroll_ground(is_quake, false)
                return
        var kind: int = CollectiblesClass.Kind.QUAKE_SCROLL if is_quake \
                        else CollectiblesClass.Kind.CHASM_SCROLL
        var item: Collectibles = _create_collectible(kind, _cell_to_pixel(cell))
        item.scroll_lifetime_ms = float(C.PARCHMENT_VISIBLE_MS + C.PARCHMENT_BLINK_MS)
        collectibles_node.add_child(item)
        # TASK 36: consuma UNO dei due slot di apparizione del livello
        if is_quake:
                scroll_quake_item = item
                scroll_quake_beacon = null
                scroll_quake_phase = ScrollPhase.GROUND
                scroll_quake_spawns_used += 1
        else:
                scroll_chasm_item = item
                scroll_chasm_beacon = null
                scroll_chasm_phase = ScrollPhase.GROUND
                scroll_chasm_spawns_used += 1
        # TASK 36 — FULMINE CHE SI ABBATE AL SUOLO: saetta verticale con
        # zigzag flicker, onda d'urto, bagliore d'impatto e braci (alone
        # tinto col colore della pergamena) + flash dello schermo + shake.
        var tint := Color(1.0, 0.62, 0.22) if is_quake else Color(0.72, 0.50, 1.0)
        var strike: Node2D = LightningStrikeFx.new()
        strike.setup(item.position, tint)
        collectibles_node.add_child(strike)
        # TASK 38 — ONDA DI LUCE: dopo il lampo, un bagliore che si diffonde
        # per TUTTO il labirinto come un'esplosione di luce. L'ondata nasce
        # dal punto in cui il fulmine colpisce il pavimento e si estende
        # fino all'angolo piu' lontano del labirinto (materiale additivo:
        # illumina davvero pavimento e muri al suo passaggio).
        var wave: Node2D = MazeLightWaveFx.new()
        var maze_origin: Vector2 = Vector2(0.0, float(C.UI_HEIGHT))
        var maze_far: float = 0.0
        for corner in [
                        maze_origin,
                        maze_origin + Vector2(
                                        float(C.MAZE_COLS * C.TILE_SIZE), 0.0),
                        maze_origin + Vector2(
                                        0.0, float(C.MAZE_ROWS * C.TILE_SIZE)),
                        maze_origin + Vector2(
                                        float(C.MAZE_COLS * C.TILE_SIZE),
                                        float(C.MAZE_ROWS * C.TILE_SIZE)),
                ]:
                maze_far = maxf(maze_far, item.position.distance_to(corner))
        wave.setup(item.position, tint, maze_far + 60.0)
        collectibles_node.add_child(wave)
        screen_flash_timer_ms = 110
        if EffectsManager:
                EffectsManager.screen_shake(7.0, 0.55)
                # piccola esplosione luminosa: la pergamena MATERIALIZZA
                var burst := EffectsManager.spawn_explosion(item.position, tint, 14, 0.45)
                collectibles_node.add_child(burst)
        # TASK 36 — effetto audio LUNGO dedicato (~1.9s: carica + crack +
        # sweep + boom + tuono rotolante), al posto del corto PORTAL_OPEN.
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.SCROLL_LIGHTNING)


## Conclude la fase GROUND: raccolta (collected=true, l'USO chiude
## l'evento per il resto del livello: nessuna seconda apparizione) o
## scaduta (collected=false). TASK 36: se scade NON raccolta e il budget
## di PARCHMENT_MAX_SPAWNS apparizioni non e' esaurito, il tipo torna
## WAIT per una SECONDA apparizione in un momento casuale successivo.
func _consume_scroll_ground(is_quake: bool, collected: bool) -> void:
        var item: Node2D = scroll_quake_item if is_quake else scroll_chasm_item
        if item != null and is_instance_valid(item):
                if not collected:
                        # svanita nel nulla: piccolo puff di polvere
                        if EffectsManager:
                                var puff := EffectsManager.spawn_explosion(
                                                item.position,
                                                Color(0.5, 0.45, 0.4), 8, 0.4)
                                collectibles_node.add_child(puff)
                item.queue_free()
        if is_quake:
                scroll_quake_item = null
                scroll_quake_beacon = null
        else:
                scroll_chasm_item = null
                scroll_chasm_beacon = null
        # TASK 36 — se NON e' stata usata puo' riapparire (max 2 per livello);
        # se e' stata RACCOLTA (usata) l'evento e' chiuso per sempre.
        if not collected:
                var spawns_used: int = scroll_quake_spawns_used if is_quake \
                                else scroll_chasm_spawns_used
                if spawns_used < C.PARCHMENT_MAX_SPAWNS:
                        var next_ms: float = float(_scroll_rng.randi_range(
                                C.PARCHMENT_NEXT_MIN_MS, C.PARCHMENT_NEXT_MAX_MS))
                        if is_quake:
                                scroll_quake_phase = ScrollPhase.WAIT
                                scroll_quake_timer_ms = next_ms
                        else:
                                scroll_chasm_phase = ScrollPhase.WAIT
                                scroll_chasm_timer_ms = next_ms
                        return
        if is_quake:
                scroll_quake_phase = ScrollPhase.DONE
        else:
                scroll_chasm_phase = ScrollPhase.DONE


# ============================================================================
# TASK 50 — PERGAMENA DEL GHIACCIO. Copia DIRETTA della macchina a stati
# delle altre due pergamene (WAIT -> BEACON -> GROUND -> DONE) con le
# STESSE costanti (PARCHMENT_*): tempistiche di apparizione identiche.
# Differenze: colore celeste-ghiaccio, kind FREEZE_SCROLL e raccolta che
# EQUIPAGGIA il player invece di attivare un evento immediato.
# ============================================================================

func _update_freeze_scroll(delta_ms: float) -> void:
        match scroll_freeze_phase:
                ScrollPhase.WAIT:
                        scroll_freeze_timer_ms -= delta_ms
                        if scroll_freeze_timer_ms <= 0.0:
                                # budget apparizioni esaurito?
                                if scroll_freeze_spawns_used >= C.PARCHMENT_MAX_SPAWNS:
                                        scroll_freeze_phase = ScrollPhase.DONE
                                        return
                                # condizione: almeno il 30% dei nemici vivi
                                var alive: int = spawner.alive_count()
                                var total: int = maxi(1, spawner.initial_count)
                                if float(alive) >= float(total) * C.PARCHMENT_MIN_ALIVE_PCT:
                                        _start_freeze_beacon()
                                        return
                                # troppi morti: riprova piu' tardi
                                scroll_freeze_timer_ms = float(C.PARCHMENT_RETRY_MS)
                ScrollPhase.BEACON:
                        scroll_freeze_timer_ms -= delta_ms
                        if scroll_freeze_beacon != null \
                                        and is_instance_valid(scroll_freeze_beacon):
                                var k: float = 1.0 - scroll_freeze_timer_ms \
                                                / float(C.PARCHMENT_TELEGRAPH_MS)
                                var pulse_k: float = 0.75 + 0.25 * sin(
                                                _time_now() * 16.0)
                                scroll_freeze_beacon.scale = Vector2.ONE \
                                                * (0.55 + k * 0.75) * pulse_k
                                scroll_freeze_beacon.rotation += delta_ms / 900.0
                        if scroll_freeze_timer_ms <= 0.0:
                                _spawn_freeze_item()
                                return
                ScrollPhase.GROUND:
                        # il lifetime (16s + 2s blink) vive nel Collectibles;
                        # qui si vigilano scomparsa (active=false) e validita'.
                        if scroll_freeze_item == null \
                                        or not is_instance_valid(scroll_freeze_item) \
                                        or not scroll_freeze_item.active:
                                _consume_freeze_ground(false)
                ScrollPhase.DONE:
                        pass


## Fase BEACON: bagliore/aura CELESTE GHIACCIO sulla cella scelta.
func _start_freeze_beacon() -> void:
        var cell := _random_empty_cell()
        if cell == Vector2i(-1, -1):
                scroll_freeze_timer_ms = float(C.PARCHMENT_RETRY_MS)
                return
        var pos: Vector2 = _cell_to_pixel(cell)
        var beacon := Sprite2D.new()
        var tex: Texture2D = load("res://assets/sprites/parchment/beacon_glow.png")
        if tex != null:
                beacon.texture = tex
        beacon.position = pos
        beacon.scale = Vector2.ONE * 0.55
        # celeste ghiaccio per la pergamena del congelamento
        beacon.modulate = Color(0.35, 0.8, 1.0, 0.85)
        beacon.z_index = 5
        collectibles_node.add_child(beacon)
        scroll_freeze_beacon = beacon
        scroll_freeze_phase = ScrollPhase.BEACON
        scroll_freeze_timer_ms = float(C.PARCHMENT_TELEGRAPH_MS)
        scroll_freeze_item = null
        set_meta("scroll_freeze_cell", cell)
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.HAZARD_RUMBLE)
        if EffectsManager:
                EffectsManager.screen_shake(2.0, 0.2)


## Fase GROUND: il bagliore si spegne, il FULMINE SI ABBATE AL SUOLO
## (tinta ghiaccio) e la pergamena celeste appare.
func _spawn_freeze_item() -> void:
        var cell: Vector2i = get_meta("scroll_freeze_cell", Vector2i(-1, -1))
        if scroll_freeze_beacon != null and is_instance_valid(scroll_freeze_beacon):
                scroll_freeze_beacon.queue_free()
        if cell == Vector2i(-1, -1):
                cell = _random_empty_cell()
        if cell == Vector2i(-1, -1):
                _consume_freeze_ground(false)
                return
        var item: Collectibles = _create_collectible(
                        CollectiblesClass.Kind.FREEZE_SCROLL, _cell_to_pixel(cell))
        item.scroll_lifetime_ms = float(C.PARCHMENT_VISIBLE_MS + C.PARCHMENT_BLINK_MS)
        collectibles_node.add_child(item)
        scroll_freeze_item = item
        scroll_freeze_beacon = null
        scroll_freeze_phase = ScrollPhase.GROUND
        scroll_freeze_spawns_used += 1
        # FULMINE che si abbatte al suolo, tinto CELESTE GHIACCIO
        var tint := Color(0.35, 0.8, 1.0)
        var strike: Node2D = LightningStrikeFx.new()
        strike.setup(item.position, tint)
        collectibles_node.add_child(strike)
        # ONDA DI LUCE che si diffonde dal punto d'impatto (pattern Task 38)
        var wave: Node2D = MazeLightWaveFx.new()
        wave.setup(item.position, tint, 900.0)
        collectibles_node.add_child(wave)
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.SCROLL_LIGHTNING)
        if EffectsManager:
                EffectsManager.screen_shake(3.0, 0.3)


## Fine della fase GROUND (raccolta o scadenza a terra). Se NON raccolta
## puo' riapparire (max PARCHMENT_MAX_SPAWNS per livello); se RACCOLTA
## (equipaggiata) l'evento e' chiuso per il resto del livello.
func _consume_freeze_ground(collected: bool) -> void:
        if scroll_freeze_item != null and is_instance_valid(scroll_freeze_item):
                if not collected:
                        if EffectsManager:
                                var puff := EffectsManager.spawn_explosion(
                                                scroll_freeze_item.position,
                                                Color(0.55, 0.75, 0.9), 8, 0.4)
                                collectibles_node.add_child(puff)
                scroll_freeze_item.queue_free()
        scroll_freeze_item = null
        scroll_freeze_beacon = null
        if not collected:
                if scroll_freeze_spawns_used < C.PARCHMENT_MAX_SPAWNS:
                        scroll_freeze_phase = ScrollPhase.WAIT
                        scroll_freeze_timer_ms = float(_scroll_rng.randi_range(
                                C.PARCHMENT_NEXT_MIN_MS, C.PARCHMENT_NEXT_MAX_MS))
                        return
        scroll_freeze_phase = ScrollPhase.DONE


## Rimuove l'equip della pergamena del ghiaccio dal player che la tiene
## (fine colpi, cambio livello, reset difensivo).
func _unequip_freeze_scroll() -> void:
        if freeze_scroll_player != 0:
                var p: CharacterBody2D = player if freeze_scroll_player == 1 else player2
                if p != null and is_instance_valid(p) \
                                and p.has_method("set_freeze_scroll_equipped"):
                        p.set_freeze_scroll_equipped(false)
        freeze_scroll_player = 0
        freeze_charges_left = 0


## TASK 50 — SPARO DEL RAGGIO CONGELANTE. Hitscan dalla posizione del
## player lungo la direzione di fuoco: congela TUTTI i nemici la cui
## distanza dalla traiettoria e' entro SCROLL_FREEZE_HIT_RADIUS_PX (il
## beam attraversa i nemici e si ferma al primo muro). Ogni nemico
## congelato = uccisione one-shot (sprite CONGELATO sul posto per tutto
## il livello). Il mid-boss subisce il 50% degli HP max + stordimento.
## Consuma UNO dei 2 colpi; a zero colpi la pergamena scompare.
func _fire_freeze_ray(p: CharacterBody2D) -> void:
        var shoot_dx: int = p.dx if p.dx != 0 else p.last_dx
        var shoot_dy: int = p.dy if p.dy != 0 else p.last_dy
        if shoot_dx == 0 and shoot_dy == 0:
                shoot_dx = 1  # fallback: spara a destra (come shoot())
        var dir := Vector2(float(shoot_dx), float(shoot_dy)).normalized()
        var muzzle: Vector2 = p.get_pixel_pos() + Vector2(0.0, -12.0) \
                        + dir * 20.0

        # --- Hitscan: cammina lungo il raggio fino al primo muro -----------
        var max_len: float = float(C.SCROLL_FREEZE_RANGE_CELLS * C.TILE_SIZE)
        var beam_end: Vector2 = muzzle + dir * max_len
        var step: float = C.SCROLL_FREEZE_STEP_PX
        var travelled: float = 0.0
        while travelled < max_len:
                travelled += step
                var probe: Vector2 = muzzle + dir * travelled
                var col: int = int(probe.x) / C.TILE_SIZE
                var row: int = int(probe.y - C.UI_HEIGHT) / C.TILE_SIZE
                if col < 0 or col >= C.MAZE_COLS or row < 0 or row >= C.MAZE_ROWS:
                        beam_end = probe
                        break
                if maze.get_cell_type(col, row) != C.CellType.EMPTY:
                        beam_end = probe - dir * (step * 0.5)
                        break

        # --- Congela i nemici colpiti dalla traiettoria ---------------------
        var hit_r_sq: float = C.SCROLL_FREEZE_HIT_RADIUS_PX * C.SCROLL_FREEZE_HIT_RADIUS_PX
        var frozen_count: int = 0
        for enemy in spawner.enemies:
                if enemy == null or not is_instance_valid(enemy):
                        continue
                if enemy.is_dead():
                        continue
                # distanza punto-segmento (muzzle -> beam_end)
                var e_pos: Vector2 = enemy.get_pixel_pos()
                var ap: Vector2 = e_pos - muzzle
                var ab: Vector2 = beam_end - muzzle
                var ab_len_sq: float = ab.length_squared()
                var tproj: float = ap.dot(ab) / ab_len_sq if ab_len_sq > 0.0 else 0.0
                tproj = clampf(tproj, 0.0, 1.0)
                var closest: Vector2 = muzzle + ab * tproj
                if e_pos.distance_squared_to(closest) > hit_r_sq:
                        continue
                enemy.freeze_kill()
                frozen_count += 1
                p.add_score(C.SCROLL_FREEZE_POINTS)
                # esplosione di brina + frantumazione ghiaccio sul nemico
                if EffectsManager:
                        var burst := EffectsManager.spawn_explosion(
                                        e_pos, Color(0.55, 0.85, 1.0), 18, 0.5)
                        collectibles_node.add_child(burst)
                if AudioManager:
                        # TASK 50b: suono dedicato della cristallizzazione
                        # (schiocco vetroso + crescita cristalli + tonfo)
                        AudioManager.play_sound(AudioManager.SoundType.FREEZE_HIT)

        # --- Mid-boss nella traiettoria: troppo potente per congelare,
        # subisce il 50% degli HP max + stordimento (come il martello). ---
        if mini_boss != null and is_instance_valid(mini_boss) \
                        and not mini_boss.is_dead():
                var mb_pos: Vector2 = mini_boss.get_pixel_pos()
                var ap_mb: Vector2 = mb_pos - muzzle
                var ab_mb: Vector2 = beam_end - muzzle
                var tmb: float = ap_mb.dot(ab_mb) / ab_mb.length_squared()
                tmb = clampf(tmb, 0.0, 1.0)
                var closest_mb: Vector2 = muzzle + ab_mb * tmb
                if mb_pos.distance_squared_to(closest_mb) <= hit_r_sq:
                        var mb_max: int = mini_boss.get_max_health()
                        var mb_dmg: int = maxi(1, int(round(
                                        float(mb_max) * C.SCROLL_FREEZE_MINIBOSS_DMG_PCT)))
                        mini_boss.take_damage(mb_dmg)
                        if mini_boss.has_method("apply_stun"):
                                mini_boss.apply_stun(C.SCROLL_FREEZE_MINIBOSS_STUN_MS)
                        if EffectsManager:
                                var burst_mb := EffectsManager.spawn_explosion(
                                                mb_pos, Color(0.55, 0.85, 1.0), 14, 0.45)
                                collectibles_node.add_child(burst_mb)
                        if AudioManager:
                                # TASK 50b: cristallizzazione anche sul mid-boss
                                AudioManager.play_sound(AudioManager.SoundType.FREEZE_HIT)

        # --- Visual: raggio congelante + screen flash leggero ---------------
        var beam: Node2D = IceBeamFx.new()
        beam.setup(muzzle, beam_end)
        collectibles_node.add_child(beam)
        if EffectsManager:
                EffectsManager.screen_shake(2.5, 0.2)

        # --- Consumo del colpo ----------------------------------------------
        freeze_charges_left -= 1
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.FREEZE_RAY)
        p.shoot_cooldown = 300
        p.shoot_anim_timer = 300
        var shooter_id: int = freeze_scroll_player
        if freeze_charges_left <= 0:
                _unequip_freeze_scroll()
                print("[Parchment] Player ", shooter_id,
                                " ha esaurito i colpi del raggio congelante")
        print("[Parchment] Raggio congelante: ", frozen_count,
                        " nemici congelati (colpi rimasti: ", freeze_charges_left, ")")


## Cella EMPTY casuale non-tunnel e libera da collectible a terra.
func _random_empty_cell() -> Vector2i:
        var candidates: Array[Vector2i] = []
        for r in range(1, C.MAZE_ROWS - 1):
                for c in range(1, C.MAZE_COLS - 1):
                        if maze.get_cell_type(c, r) != C.CellType.EMPTY:
                                continue
                        if C.is_tunnel_cell(c, r):
                                continue
                        if not _collectible_cell_free(c, r):
                                continue
                        candidates.append(Vector2i(c, r))
        if candidates.is_empty():
                return Vector2i(-1, -1)
        return candidates[randi() % candidates.size()]


## EFFETTO — PERGAMENA DEL TERREMOTO: -50% HP max a TUTTI i nemici; chi
## dopo il colpo si ritrova SOTTO il 50% dell'energia massima viene
## ELIMINATO (+5000 punti al raccoglitore). Il player NON subisce danni.
func _activate_scroll_quake(p: CharacterBody2D) -> void:
        if EffectsManager:
                EffectsManager.screen_shake(10.0, 0.9)
                EffectsManager.screen_shake(4.0, 0.5)
        screen_flash_timer_ms = 90
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.HAZARD_RUMBLE)
                AudioManager.play_sound(AudioManager.SoundType.HAZARD_THUD)
        var killed: int = 0
        for enemy in spawner.enemies:
                if enemy == null or not is_instance_valid(enemy) or enemy.is_dead():
                        continue
                var max_hp: int = enemy.get_max_health()
                var dmg: int = maxi(1, int(round(float(max_hp) * C.SCROLL_QUAKE_DAMAGE_PCT)))
                var kill_threshold: int = int(ceil(float(max_hp) * C.SCROLL_QUAKE_KILL_PCT))
                if enemy.health - dmg < kill_threshold:
                        # sotto il 50% dopo il colpo: eliminato
                        enemy.take_damage(99999)
                        killed += 1
                        if p != null:
                                p.add_score(C.SCROLL_QUAKE_KILL_POINTS)
                        if EffectsManager:
                                var blood := EffectsManager.spawn_blood(
                                                enemy.get_pixel_pos(), 14)
                                collectibles_node.add_child(blood)
                else:
                        enemy.take_damage(dmg)
                        if EffectsManager:
                                var dust := EffectsManager.spawn_explosion(
                                                enemy.get_pixel_pos(),
                                                Color(0.45, 0.4, 0.35), 10, 0.5)
                                collectibles_node.add_child(dust)
        # mini-boss: stessa regola (50% + kill sotto soglia, +10000 punti)
        if mini_boss != null and is_instance_valid(mini_boss) and not mini_boss.is_dead():
                var mb_max: int = mini_boss.get_max_health()
                var mb_dmg: int = maxi(1, int(round(float(mb_max) * C.SCROLL_QUAKE_DAMAGE_PCT)))
                var mb_threshold: int = int(ceil(float(mb_max) * C.SCROLL_QUAKE_KILL_PCT))
                if mini_boss.health - mb_dmg < mb_threshold:
                        mini_boss.take_damage(99999)
                        if mini_boss.is_dead() and p != null:
                                p.add_score(C.HAZARD_WALL_KILL_POINTS)
                else:
                        mini_boss.take_damage(mb_dmg)
        if AudioManager and killed > 0:
                AudioManager.play_sound(AudioManager.SoundType.ENEMY_DEATH)


## EFFETTO — PERGAMENA DELLE VORAGINI: 3 ondate da 4 voragini magiche in
## celle casuali ben distanziate (le uccisioni sono gestite da MazeHazards).
func _activate_scroll_chasms(p: CharacterBody2D) -> void:
        hazards.start_scroll_chasms(p)


# FIX (2P): il player VIVO più vicino a `from_pos` (P1 o P2), oppure null se
# non ce ne sono. Usato dal targeting di nemici, miniboss e boss room: in 2P
# l'IA preme su chi è più vicino invece di ignorare completamente P2.
func _nearest_alive_player(from_pos: Vector2) -> CharacterBody2D:
        var best: CharacterBody2D = null
        var best_d: float = INF
        # FUOCO AMICO (Task 18): il player congelato in attesa dell'anima non
        # è un bersaglio valido (né per i nemici né per i miniboss).
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


# TASK 23: eliminazione + CONTINUE per-player in 2P. Quando un player
# (P1 o P2) perde l'ultima vita mentre l'altro è ancora vivo:
#   * con crediti > 0 nel SUO contatore → si congela il gioco e appare il
#     ContinuesOverlay (PLAYER N CONTINUE? + crediti SUOI, separati);
#   * senza crediti → eliminato subito (comportamento pre-esistente).
# Chi viene eliminato NON è più uno "zombie" giocabile: non riceve input,
# non collide, non viene più preso di mira. L'HUD conserva il suo punteggio
# finale. Se nessun player resta in gioco → game over (LOSE).
# In 1P il flusso continua a essere quello scene-based di _check_death().
func _check_player_elimination() -> void:
        if GameManager == null or GameManager.num_players != 2:
                return
        # Una schermata continue alla volta: se è già aperta, la morte
        # dell'altro player verrà gestita al frame dopo la risoluzione.
        if _continue_pending_player != 0:
                return
        for p in [player, player2]:
                if p == null or not is_instance_valid(p) or not p.visible:
                        continue
                # FUOCO AMICO (Task 18): se il player è morto per colpo del
                # compagno e la sua anima sta ancora volando, l'eliminazione
                # aspetta la fine del trasferimento (respawn_after_soul la
                # gestisce al frame dopo).
                if p.soul_pending:
                        continue
                if p.lives > 0:
                        continue  # vivo
                var pnum: int = 1 if p == player else 2
                var credits: int = GameManager.continues_for(pnum)
                if credits > 0:
                        _open_continue_overlay(pnum, credits)
                        return  # il gioco si congela al frame successivo
                _eliminate_player(p)
        _check_all_players_out()


# TASK 23: apre l'overlay CONTINUE? per il player `pnum` con i SUOI crediti.
func _open_continue_overlay(pnum: int, credits: int) -> void:
        _continue_pending_player = pnum
        if GameManager:
                GameManager.continue_player_num = pnum
        _continue_overlay = ContinuesOverlayClass.new()
        _continue_overlay.setup(pnum, credits)
        _continue_overlay.continue_chosen.connect(_on_continue_chosen)
        add_child(_continue_overlay)
        print("[Continue] schermata continue per PLAYER ", pnum,
                        " (crediti suoi: ", credits, ")")


# TASK 23: scelta sulla schermata continue del player `pnum`.
# YES: consuma 1 credito del SUO contatore e riprende (3 vite, energia
# piena, respawn, invulnerabilità breve). NO/timeout: eliminato; se non
# resta nessun player → LOSE (game over).
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
                p.lives = 3
                p.energy = p.max_energy
                p.reset_position()
                p.damage_timer = CONTINUE_RESPAWN_INVULN_MS
                p.visible = true
                if EffectsManager:
                        EffectsManager.screen_shake(4.0, 0.2)
                        var burst := EffectsManager.spawn_pickup_burst(
                                        p.get_pixel_pos(), Color(0.4, 0.9, 1.0))
                        collectibles_node.add_child(burst)
                # Musica di livello: era stata fermata dall'overlay.
                if AudioManager and AudioManager.music_enabled \
                                and not AudioManager._epic_playing:
                        AudioManager.play_level_music(current_level, false)
                print("[Continue] PLAYER ", pnum, " riprende con 3 vite (crediti suoi residui: ",
                                GameManager.continues_for(pnum) if GameManager else 0, ")")
        else:
                _eliminate_player(p)
                _check_all_players_out()


# TASK 23: elimina `p` (vite esaurite e niente crediti / scelta NO).
func _eliminate_player(p: CharacterBody2D) -> void:
        if p == null or not is_instance_valid(p) or not p.visible:
                return
        var pnum: int = 1 if p == player else 2
        p.visible = false
        p.set_direction(0, 0)
        print("[2P] Player ", pnum, " eliminato (vite esaurite)")
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.LOSE_LIFE)
        # Effetto visivo sull'ultimo punto noto del player eliminato.
        if EffectsManager:
                var burst := EffectsManager.spawn_explosion(p.get_pixel_pos(),
                        Color(0.55, 0.65, 1.0), 18, 0.7)
                collectibles_node.add_child(burst)
        # Snapshot finale sull'HUD (il player eliminato resta mostrato con
        # l'ultimo punteggio e 0 vite).
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


# TASK 23: game over 2P — nessun player vivo né in attesa di continue.
# Registra i punteggi finali (per la Hall of Fame) e va alla LOSE screen.
func _check_all_players_out() -> void:
        if not _alive_players().is_empty():
                return
        if _continue_pending_player != 0:
                return  # c'è ancora una scelta continue in sospeso
        if AudioManager:
                AudioManager.stop_epic_music()
                AudioManager.stop_ghost_music()
        if GameManager:
                # FIX (Hall of Fame): registra il punteggio finale prima della
                # transizione. In 2P ogni player ha il PROPRIO punteggio.
                var total_score_d: int = player.score
                if player2 != null and is_instance_valid(player2):
                        total_score_d += player2.score
                GameManager.final_score = total_score_d
                GameManager.final_score_p1 = player.score
                GameManager.final_score_p2 = player2.score if \
                                (player2 != null and is_instance_valid(player2)) else 0
                GameManager.final_level = current_level
                GameManager.give_up()


func _check_death() -> void:
        # TASK 23: in 2P la morte/gestione continue è del flusso per-player
        # (_check_player_elimination + ContinuesOverlay): questo ramo
        # scene-based (snapshot + ContinuesScreen) vale SOLO in 1P.
        if GameManager and GameManager.num_players == 2:
                return
        var p1_dead: bool = player.lives <= 0
        var p2_dead: bool = true
        if GameManager and GameManager.num_players == 2 and player2.visible:
                p2_dead = player2.lives <= 0
        if p1_dead and p2_dead:
                # FIX (musica calice alla morte): il canale epic è un canale
                # SEPARATO che sopravvive al cambio stato (autoplay su nodo
                # AudioManager). Con il loop del calice attivo alla morte
                # sarebbe continuato all'infinito sulle schermate
                # CONTINUES/LOSE: lo fermiamo qui.
                if AudioManager:
                        AudioManager.stop_epic_music()
                        # FIX (pozione magica): ferma anche il tema fantasma
                        AudioManager.stop_ghost_music()
                if GameManager:
                        # FIX (Hall of Fame): registra il punteggio finale prima
                        # della transizione. In 2P ogni player ha il PROPRIO
                        # punteggio (salvabile singolarmente in classifica:
                        # tastiera di inserimento prima per P1 poi per P2);
                        # final_score resta la somma dei due per compatibilità
                        # con la schermata di game over.
                        var total_score_d: int = player.score
                        if GameManager.num_players == 2 and player2.visible:
                                total_score_d += player2.score
                        GameManager.final_score = total_score_d
                        GameManager.final_score_p1 = player.score
                        GameManager.final_score_p2 = player2.score if \
                                        (GameManager.num_players == 2 and player2.visible) else 0
                        GameManager.final_level = current_level
                        # FIX (continue = sessione ESATTA — richiesta utente):
                        # salva lo snapshot COMPLETO della sessione PRIMA di
                        # uscire verso la schermata dei crediti. Se il player
                        # usa un continue, start_level ripristina ESATTAMENTE
                        # questa sessione (stesso labirinto, tesori residui,
                        # nemici con numero/tipo/posizione/HP, item, punteggi).
                        GameManager.session_snapshot = _build_session_snapshot()
                        if GameManager.continues_left > 0:
                                GameManager.player_died()
                        else:
                                GameManager.give_up()


# 2P friendly fire: quando i due player si sovrappongono (distanza^2 < 800,
# cioe' ~28 px) il C++ originale infliggeva 1 danno energia a entrambi
# (Game.cpp 1846-1862).
# FIX (bug utente 2P — "P2 subiva colpi senza che nessuno gli sparasse"):
# il danno da sovrapposizione è STATO DISABILITATO su segnalazione
# dell'utente: in cooperativa i due player camminano costantemente vicini
# nei corridoi (larghi una cella) e P2 subiva un colpo al secondo senza
# alcun nemico visibile — percepito come un bug, non come una meccanica.
# I due player ora si attraversano liberamente: P2 "funziona analogamente
# a P1", come richiesto dall'utente. La funzione resta come hook.
func _check_2p_friendly_fire() -> void:
        return


# ============================================================================
# FUOCO AMICO (Task 18 — richiesta utente): "se un giocatore uccide l'altro
# player il player vincitore recupera completamente l'energia con effetto
# grafico di un'anima che si separa dal corpo del player ucciso che si
# accascia al pavimento e [l'anima] vola velocemente verso l'altro player
# ricaricandogli l'energia".
# I PROIETTILI di un player colpiscono l'altro player:
#   * colpo NON fatale: target.take_damage() (flusso identico ai colpi
#     nemici: -1 energia, invulnerabilita' 1s, sparks/shake);
#   * colpo FATALE (target.energy == 1): _start_soul_transfer — la vittima
#     perde una vita ma resta congelata sul posto (soul_pending) mentre il
#     corpo si accascia e l'anima vola verso il vincitore.
# I colpi a bersaglio invulnerabile/in salto passano attraverso (parita'
# con (5) proiettili nemici vs player).
# ============================================================================


func _check_friendly_fire_projectiles() -> void:
        if not _is_p2_active():
                return
        _ff_shooter_vs_target(player, player2)
        _ff_shooter_vs_target(player2, player)


# Proiettili di `shooter` contro `target` (l'altro player vivo).
func _ff_shooter_vs_target(shooter: CharacterBody2D, target: CharacterBody2D) -> void:
        if shooter.soul_pending or target.soul_pending:
                return
        if target.is_invulnerable() or target.is_jumping():
                return  # parita' proiettili nemici: passa attraverso
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
# l'effetto anima verso il vincitore. Il segnale soul_delivered chiamera'
# _on_soul_delivered quando l'anima arriva.
func _start_soul_transfer(winner: CharacterBody2D, victim: CharacterBody2D) -> void:
        victim.kill_by_friendly_fire()
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.LOSE_LIFE)
                AudioManager.play_sound(AudioManager.SoundType.SOUL_RELEASE)
        if EffectsManager:
                EffectsManager.screen_shake(4.0, 0.2)
        var fx: Node2D = SoulTransferFx.new()
        fx.setup(victim, winner)
        add_child(fx)  # figlio del root: disegnato sopra player e nemici
        fx.soul_delivered.connect(_on_soul_delivered.bind(winner, victim))


# L'anima ha raggiunto il vincitore: ricarica COMPLETA dell'energia del
# vincitore (se ancora in gioco) e respawn della vittima. Se era l'ultima
# vita della vittima, al frame dopo _check_player_elimination la elimina
# in modo pulito (soul_pending e' stato riportato a false).
func _on_soul_delivered(winner: CharacterBody2D, victim: CharacterBody2D) -> void:
        if is_instance_valid(winner) and winner.lives > 0 and not winner.soul_pending:
                winner.energy = winner.max_energy
                if AudioManager:
                        AudioManager.play_sound(AudioManager.SoundType.SOUL_ABSORB)
                if EffectsManager:
                        EffectsManager.screen_shake(3.0, 0.15)
                        var burst := EffectsManager.spawn_pickup_burst(
                                        winner.get_pixel_pos(), Color(0.85, 0.95, 1.0))
                        collectibles_node.add_child(burst)
        if is_instance_valid(victim):
                victim.respawn_after_soul()


# ============================================================================
# Collectibles update + collision with player
# ============================================================================

# TASK 51 — CARD BONUS (richiesta utente): mostra la card informativa alla
# PRIMA raccolta di un bonus particolare. Il gioco si mette in PAUSA; la
# card presenta nome/effetto/usi/danno, icona stilizzata e una demo animata
# in loop; si chiude TENENDO PREMUTO il fuoco per 1 secondo. Se lo stesso
# bonus viene ripreso piu' avanti nella partita la card NON riappare
# (memoria per-run: GameManager.bonus_cards_seen, azzerata a nuova run).
func _maybe_show_bonus_card(kind: int, player_num: int) -> void:
        if not C.BONUS_CARD_ENABLED:
                return
        var key := "kind_%d" % kind
        if GameManager == null or GameManager.has_seen_bonus_card(key):
                return
        # una card alla volta (pickup simultanei in 2P): il secondo bonus
        # NON viene segnato come visto — la sua card comparira' alla
        # prossima raccolta, non viene saltata in silenzio.
        if _bonus_card != null:
                return
        GameManager.mark_bonus_card_seen(key)
        var card: CanvasLayer = BonusCardOverlayClass.new()
        # TASK 58b: la demo mostra la sprite PixelLab del personaggio che
        # ha raccolto il bonus (player2 e' un nodo della scena anche in 1P,
        # con character_type di default HERO_M se mai selezionato).
        var char_owner: CharacterBody2D = player2 if player_num == 2 else player
        var ct := 0
        if char_owner != null and "character_type" in char_owner:
                ct = int(char_owner.character_type)
        card.setup(kind, player_num, ct)
        card.card_closed.connect(_on_bonus_card_closed)
        _bonus_card = card
        add_child(card)
        get_tree().paused = true


# TASK 51 — chiusura della card: riavvia il gioco e libera l'overlay.
func _on_bonus_card_closed() -> void:
        if _bonus_card != null:
                _bonus_card.queue_free()
                _bonus_card = null
        if get_tree():
                get_tree().paused = false


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
                # FIX (mina gira per sempre): la mina in movimento (bouncing) NON
                # può essere raccolta di nuovo dal player — ogni tocco resetta
                # il timer dei 6 secondi rendendola di fatto infinita.
                if child.get("bouncing"):
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
                        _maybe_show_bonus_card(CollectiblesClass.Kind.MINE, player_id)
                        # FIX (bomba scompare subito): velocità iniziale troppo alta
                        # (randf()*4-2)*50 = fino a 100px/frame → la bomba usciva
                        # dallo schermo in 1-2 frame. Ridotta a *5 (max 10px/frame).
                        # FIX (durata bomba 6 secondi): come richiesto, la mina
                        # esplode automaticamente dopo 6 secondi se non colpisce
                        # nessun nemico (prima 10s e il timer si resettava ogni
                        # volta che il player toccava di nuovo la mina vagante,
                        # per cui girava per sempre).
                        item.start_bounce(Vector2(randf() * 4 - 2, randf() * 4 - 2) * 5, 6000)
                        if AudioManager:
                                AudioManager.play_sound(AudioManager.SoundType.TRAP)
                CollectiblesClass.Kind.CHALICE:
                        _maybe_show_bonus_card(CollectiblesClass.Kind.CHALICE, player_id)
                        # FIX (durata calice -3s + bug doppio decremento): il timer
                        # veniva decrementato DUE volte per frame (in
                        # Player.update_player E in _update_invincible_burn),
                        # quindi i 25s nominali duravano in realtà ~12.5s.
                        # Corretto il doppio decremento (ora un solo tick in
                        # Player.update_player) e impostata la durata richiesta:
                        # 12.5s percepite - 3s = 9.5s reali.
                        p.set_invincible_timer(9500)
                        p.add_score(15000)
                        item.active = false
                        item.queue_free()
                        if AudioManager:
                                AudioManager.play_sound(AudioManager.SoundType.TREASURE)
                                # FIX (musica calice non partiva + deve durare
                                # tutto l'effetto): come nel C++ originale
                                # (Game.cpp:2209, AudioManager.cpp:98) il
                                # jingle epico suona sul canale SEPARATO epic
                                # SENZA il gate musicEnabled (il gate impediva
                                # di sentirlo con la musica disattivata) e ora
                                # va in LOOP per tutta la durata dell'effetto:
                                # lo ferma _update_invincible_burn quando
                                # l'invincibilità scade.
                                AudioManager.play_epic_music(
                                                AudioManager.TRACK_EPIC_CHALICE, true)
                        # Particelle pickup oro (Godot-native)
                        if EffectsManager:
                                var burst := EffectsManager.spawn_pickup_burst(p.get_pixel_pos(),
                                        Color(1.0, 0.84, 0.0))
                                collectibles_node.add_child(burst)
                CollectiblesClass.Kind.SCEPTER:
                        _maybe_show_bonus_card(CollectiblesClass.Kind.SCEPTER, player_id)
                        item.trigger_scepter()
                        item.active = false
                        item.queue_free()
                        if AudioManager:
                                AudioManager.play_sound(AudioManager.SoundType.SCEPTER_PICKUP)
                                # FIX (jingle scettro): niente gate musicEnabled,
                                # come nel C++ originale. One-shot (no loop).
                                AudioManager.play_epic_music(7, false)  # TRACK_EPIC_SCEPTER
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
                        _maybe_show_bonus_card(CollectiblesClass.Kind.SPEED_BOOTS, player_id)
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
                        # collectible TREASURE, rimuovi la cella TREASURE del maze
                        # più vicina. Usa remove_nearest_treasure che cerca in
                        # TUTTO il maze, non solo in raggio 5.
                        var p_pos_t: Vector2 = p.get_pixel_pos()
                        var p_col_t: int = int(p_pos_t.x / C.TILE_SIZE)
                        var p_row_t: int = int((p_pos_t.y - C.UI_HEIGHT) / C.TILE_SIZE)
                        maze.remove_nearest_treasure(p_col_t, p_row_t)
                CollectiblesClass.Kind.MEDIKIT:
                        # FIX (medikit): aumenta l'ENERGIA del player, non le vite.
                        # L'energia è la barra che si vede in alto (energy/max_energy).
                        # +1 energia, capped a max_energy.
                        if p.energy < p.max_energy:
                                p.energy = p.energy + 1
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
                        _maybe_show_bonus_card(CollectiblesClass.Kind.KNIGHT_STATUE, player_id)
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
                        _maybe_show_bonus_card(CollectiblesClass.Kind.DYNAMITE, player_id)
                        # FIX (nuova meccanica): candelotto di dinamite.
                        # Animazione accensione miccia (0.8s), poi player equipaggia.
                        # La miccia brucia per 7s, poi alert + 2s esplosione.
                        item.active = false
                        item.queue_free()
                        dynamite_item = null
                        # FIX (2P): passa l'id del player che raccoglie, così la
                        # dinamite appartiene a CHI la raccoglie (lancio, miccia,
                        # esplosione e rendering sul player giusto).
                        _start_dynamite_pickup(p, player_id)
                CollectiblesClass.Kind.POTION:
                        _maybe_show_bonus_card(CollectiblesClass.Kind.POTION, player_id)
                        # FIX (pozione magica): il player BEVE la pozione.
                        # Suono di deglutizione + effetto fantasma per 5s:
                        # evanescente, attraversa i muri, uscita automatica dal
                        # muro a fine effetto, musica fantasmagorica per tutto
                        # il periodo dell'effetto.
                        item.active = false
                        item.queue_free()
                        potion_item = null
                        # Suono di deglutizione (glu-glu)
                        if AudioManager:
                                AudioManager.play_sound(AudioManager.SoundType.POTION_GULP)
                        # Attiva la modalità fantasma sul player che ha bevuto
                        p.start_ghost_mode()
                        # Musica fantasmagorica in loop per tutta la durata
                        # (canale dedicato, non soggetto a musicEnabled come il
                        # jingle del calice). Abbassiamo la musica di livello
                        # per dare spazio al tema.
                        if AudioManager:
                                AudioManager.stop_music()
                                AudioManager.play_ghost_music()
                        # Particelle verdi di trasformazione
                        if EffectsManager:
                                var burst_p := EffectsManager.spawn_pickup_burst(p.get_pixel_pos(),
                                        Color(0.45, 1.0, 0.55))
                                collectibles_node.add_child(burst_p)
                CollectiblesClass.Kind.HAMMER:
                        _maybe_show_bonus_card(CollectiblesClass.Kind.HAMMER, player_id)
                        # FIX (martello di Thor — nuova meccanica): il player
                        # raccoglie Mjolnir. Da questo momento il tasto di
                        # fuoco LANCIA il martello (max 2 volte); poi
                        # scompare. In mano finché non lo lancia.
                        item.active = false
                        item.queue_free()
                        hammer_item = null
                        hammer_player = player_id
                        hammer_uses_left = HAMMER_MAX_USES
                        p.set_hammer_equipped(true)
                        if AudioManager:
                                AudioManager.play_sound(AudioManager.SoundType.WEAPON_PICKUP)
                                AudioManager.play_sound(AudioManager.SoundType.HAMMER_CLANK)
                        # Particelle elettriche blu
                        if EffectsManager:
                                var burst_h := EffectsManager.spawn_pickup_burst(p.get_pixel_pos(),
                                        Color(0.5, 0.8, 1.0))
                                collectibles_node.add_child(burst_h)
                        print("[Hammer] Player ", player_id, " ha raccolto Mjolnir (2 lanci)")
                CollectiblesClass.Kind.QUAKE_SCROLL:
                        _maybe_show_bonus_card(CollectiblesClass.Kind.QUAKE_SCROLL, player_id)
                        # TASK 35 (pergamene evento): si attiva IMMEDIATAMENTE
                        # alla raccolta — terremoto: -50% HP a tutti i nemici,
                        # eliminati quelli che restano sotto il 50%. Il player
                        # non subisce NESSUN danno. (_consume_scroll_ground
                        # libera l'item e chiude la fase GROUND.)
                        item.active = false
                        _consume_scroll_ground(true, true)
                        _activate_scroll_quake(p)
                        if AudioManager:
                                AudioManager.play_sound(AudioManager.SoundType.RELIC_PICKUP)
                        if EffectsManager:
                                var burst_q := EffectsManager.spawn_pickup_burst(
                                        p.get_pixel_pos(), Color(1.0, 0.55, 0.2))
                                collectibles_node.add_child(burst_q)
                        print("[Parchment] Player ", player_id,
                                        " ha letto la pergamena del terremoto")
                CollectiblesClass.Kind.CHASM_SCROLL:
                        _maybe_show_bonus_card(CollectiblesClass.Kind.CHASM_SCROLL, player_id)
                        # TASK 35: pergamena delle voragini — 3 ondate da 4
                        # voragini magiche: uccidono i nemici, il player e'
                        # immune e non puo' caderci.
                        item.active = false
                        _consume_scroll_ground(false, true)
                        _activate_scroll_chasms(p)
                        if AudioManager:
                                AudioManager.play_sound(AudioManager.SoundType.RELIC_PICKUP)
                        if EffectsManager:
                                var burst_c := EffectsManager.spawn_pickup_burst(
                                        p.get_pixel_pos(), Color(0.7, 0.45, 1.0))
                                collectibles_node.add_child(burst_c)
                        print("[Parchment] Player ", player_id,
                                        " ha letto la pergamena delle voragini")
                CollectiblesClass.Kind.FREEZE_SCROLL:
                        _maybe_show_bonus_card(CollectiblesClass.Kind.FREEZE_SCROLL, player_id)
                        # TASK 50 (pergamena del GHIACCIO): il player la
                        # EQUIPAGGIA — il tasto di fuoco spara il raggio
                        # congelante (2 colpi, poi la pergamena scompare).
                        # Congela i nemici per TUTTO il livello: conta come
                        # uccisione one-shot ma lo sprite resta sul
                        # labirinto, congelato nel ghiaccio trasparente.
                        item.active = false
                        _consume_freeze_ground(true)
                        freeze_scroll_player = player_id
                        freeze_charges_left = C.SCROLL_FREEZE_CHARGES
                        p.set_freeze_scroll_equipped(true)
                        if AudioManager:
                                AudioManager.play_sound(AudioManager.SoundType.RELIC_PICKUP)
                                AudioManager.play_sound(AudioManager.SoundType.BURST_FROST)
                        if EffectsManager:
                                var burst_f := EffectsManager.spawn_pickup_burst(
                                        p.get_pixel_pos(), Color(0.35, 0.8, 1.0))
                                collectibles_node.add_child(burst_f)
                        print("[Parchment] Player ", player_id,
                                        " ha equipaggiato la pergamena del ghiaccio (",
                                        C.SCROLL_FREEZE_CHARGES, " colpi)")


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
                                "anim_timer_ms": 1400,
                                "glow_pulse": 0.0,
                        }
                        # TASK 30 (hazard): la porta deve essere pulita — via
                        # eventuali sabbie/ganasce/voragini sulla cella scelta.
                        hazards.clear_at(door_cell, maze)
                        # FIX (portone di pietra): suono DOOR_OPEN quando appare
                        # il portone (prima usava il suono TREASURE, già sentito
                        # a ogni tesoro raccolto).
                        if AudioManager:
                                AudioManager.play_sound(AudioManager.SoundType.DOOR_OPEN)

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
                        # FIX (punteggio perso tra le scene): salva lo stato
                        # dei player PRIMA del cambio scena — la boss room
                        # istanzia nodi Player NUOVI che altrimenti ripartirebbero
                        # da score=0 (nel C++ il player e' UNICO e sopravvive).
                        GameManager.save_player_carry(player, player2)
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
                        # FIX (punteggio perso tra le scene): mirror _advance_level.
                        GameManager.save_player_carry(player, player2)
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
        # FIX (continue = sessione ESATTA — richiesta utente): se start_level e'
        # stato raggiunto da un CONTINUE (GameManager.session_restore_pending)
        # e lo snapshot corrisponde a QUESTO livello maze, ripristiniamo la
        # sessione com'era al momento della morte (stesso labirinto, stessi
        # tesori residui, stessi nemici in numero/tipo/posizione/HP, stessi
        # item a terra, punteggi, porta, portale, fantasmi, martello)
        # invece di rigenerare tutto random.
        var restore: Dictionary = {}
        if GameManager and GameManager.session_restore_pending \
                        and not GameManager.session_snapshot.is_empty() \
                        and str(GameManager.session_snapshot.get("kind", "")) == "maze" \
                        and int(GameManager.session_snapshot.get("level", -1)) == lvl:
                restore = GameManager.session_snapshot
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
        # Generate maze (o RIPRISTINO dallo snapshot del continue)
        if restore.is_empty():
                # TASK 61 — le armi nel labirinto seguono l'affinita' degli
                # archetipi dei player (umani -> armi da fuoco, non-umani ->
                # elementali del pool del personaggio).
                maze.affinity_char_types = _collect_char_types()
                maze.generate(current_level)
        else:
                maze.restore_state(restore.get("maze", {}))
                GameManager.session_restore_pending = false
        # Reset player position
        if current_level == 1:
                player.reset()
                if GameManager and GameManager.num_players == 2:
                        player2.reset()
                        _place_player2_near_p1()
        else:
                player.reset_position()
                if GameManager and GameManager.num_players == 2:
                        player2.reset_position()
                        _place_player2_near_p1()
        # Spawn enemies
        # FIX (6 nemici al livello 1 + 1 dopo ogni boss): passa il livello allo
        # spawner: ondata = 6 + numero di boss già sconfitti.
        # FIX (continue = sessione ESATTA): al restore ricrea ESATTAMENTE i
        # nemici vivi al momento della morte (tipo, posizione, HP residui).
        if restore.is_empty():
                spawner.spawn_enemies(maze, current_level)
                initial_enemy_count = spawner.enemies.size()
                portal_used = false
        else:
                _restore_enemies_from_snapshot(restore)
        # Clear mini-boss + scepter state
        if mini_boss != null:
                mini_boss.queue_free()
                mini_boss = null
        mini_boss_spawned = false
        # FIX (Hurry Up!): rimuove il fantasma immortale e la scritta a ogni
        # cambio livello — riapparirà al prossimo livello labirinto quando
        # verranno uccisi tutti i nemici (10s dall'ultimo tesoro).
        _clear_hurry_up()
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
        if restore.is_empty():
                _spawn_collectibles()
        else:
                # FIX (continue = sessione ESATTA): item a terra, giocatori,
                # portale, mini-boss, porta, fantasmi e martello come alla
                # morte (i tesori raccolti NON riappaiono: la griglia e' gia'
                # stata ripristinata da maze.restore_state).
                _restore_session_from_snapshot(restore)
        # TASK 30 — HAZARD AMBIENTALI: generati DOPO i collectible (le celle
        # occupate da item sono escluse dal placement). RNG seedato sul
        # livello: al continue gli hazard tornano negli stessi punti con
        # stati freschi (le voragini ri-partono dal telegrafo). generate()
        # ripulisce prima tutto (sprite + registro dynamic_walls del Maze).
        hazards.generate(current_level, maze, self)
        # TASK 32 — NUBE DI PIPISTRELLI: programma gli eventi del livello
        # (1 dal livello 5, 2 dal 31) e rimuove l'eventuale sciame del
        # livello precedente.
        if bat_cloud != null and is_instance_valid(bat_cloud):
                bat_cloud.queue_free()
                bat_cloud = null
        _bat_rng.seed = hash("bats_v1_%d" % current_level)
        bat_events_left = C.bat_events_for_level(current_level)
        bat_event_timer_ms = float(_bat_rng.randi_range(
                C.BAT_CLOUD_FIRST_MIN_MS, C.BAT_CLOUD_FIRST_MAX_MS))
        # TASK 35: programma le due pergamene evento (momento casuale,
        # seedato per livello: al continue gli orari si ripetono).
        _reset_parchments(current_level)
        # Play level music
        # FIX (musica calice tra livelli): se l'effetto del calice è ancora
        # attivo (player uscito dal livello mentre era invincibile) la
        # musica epic resta in loop e NON viene sovrapposta dalla musica di
        # livello: la fermerà _update_invincible_burn alla scadenza.
        # Se invece non c'è nessun calice attivo, stop difensivo del canale
        # epic (evita jingle residui) e musica di livello normale.
        var chalice_still_active: bool = player.invincible_timer > 0 \
                        or (GameManager and GameManager.num_players == 2 \
                                and player2.visible and player2.invincible_timer > 0)
        if AudioManager:
                if not chalice_still_active:
                        AudioManager.stop_epic_music()
                if GameManager and GameManager.music_enabled:
                        AudioManager.play_level_music(current_level, false)


# ============================================================================
# FIX (continue = sessione ESATTA): snapshot / restore della sessione maze
# ============================================================================

## Costruisce lo snapshot COMPLETO della sessione al momento della morte:
## labirinto (celle per celle), nemici vivi (tipo/posizione/HP), spawner,
## item a terra, porta/portale/mini-boss/fantasmi, stato martello e
## punteggi/armi/stivali dei player. Salvato in GameManager.session_snapshot
## e consumato da start_level quando il player usa un CONTINUE.
func _build_session_snapshot() -> Dictionary:
        var snap: Dictionary = {"kind": "maze", "level": current_level}
        # --- Labirinto cella per cella ---
        snap["maze"] = maze.serialize_state()
        # --- Nemici VIVI (non morti/non morenti) ---
        var enemies_snap: Array = []
        for e in spawner.enemies:
                if e == null or not is_instance_valid(e):
                        continue
                if e.is_dead() or e.is_dying():
                        continue
                enemies_snap.append({
                        "type": int(e.type),
                        "col": int(e.position.x / C.TILE_SIZE),
                        "row": int((e.position.y - C.UI_HEIGHT) / C.TILE_SIZE),
                        "pos": e.position,
                        "health": int(e.health),
                })
        snap["enemies"] = enemies_snap
        snap["initial_count"] = spawner.initial_count
        # --- Portale magico ---
        # FIX (Task 40 - crash 'phase_timer_ms'): le chiavi REALI del dict
        # magic_portal di EnemySpawner sono "phase_timer" e "spawn_timer"
        # (senza suffisso _ms). Gli accessi vecchi leggevano chiavi
        # inesistenti -> SCRIPT ERROR alla morte con portale attivo (HurryUp)
        # e session_snapshot persa (continue senza sessione esatta).
        var portal_snap: Dictionary = {}
        if spawner.magic_portal.active:
                portal_snap = {
                        "pos": spawner.magic_portal.pos,
                        "active": true,
                        "phase": int(spawner.magic_portal.phase),
                        "phase_timer_ms": int(spawner.magic_portal.phase_timer),
                        "enemies_to_spawn": int(spawner.magic_portal.enemies_to_spawn),
                        "spawn_timer_ms": int(spawner.magic_portal.spawn_timer),
                }
        snap["portal"] = portal_snap
        snap["portal_used"] = spawner.portal_used
        snap["portal_used_local"] = portal_used
        # TASK 23 (respawn progressivo): anche il budget residuo del portale.
        snap["respawn_budget"] = int(spawner.respawn_budget)
        snap["progressive_respawn"] = bool(spawner.progressive_respawn)
        # --- Mini-boss (se vivo) ---
        var mb_snap: Dictionary = {}
        if mini_boss != null and is_instance_valid(mini_boss) and not mini_boss.is_dead():
                mb_snap = {
                        "health": int(mini_boss.health),
                        "pos": mini_boss.position,
                        "col": int(mini_boss.position.x / C.TILE_SIZE),
                        "row": int((mini_boss.position.y - C.UI_HEIGHT) / C.TILE_SIZE),
                }
        snap["mini_boss"] = mb_snap
        # --- Item a terra (solo quelli ancora raccoglibili) ---
        var items: Dictionary = {}
        if mine_item != null and is_instance_valid(mine_item) and mine_item.active:
                items["mine"] = {"pos": mine_item.pos}
        if chalice_item != null and is_instance_valid(chalice_item) and chalice_item.active:
                items["chalice"] = {"pos": chalice_item.pos}
        if scepter_item != null and is_instance_valid(scepter_item) and scepter_item.active:
                items["scepter"] = {"pos": scepter_item.pos}
        if speed_boots_item != null and is_instance_valid(speed_boots_item) and speed_boots_item.active:
                items["boots1"] = {"pos": speed_boots_item.pos}
        if speed_boots2_item != null and is_instance_valid(speed_boots2_item) and speed_boots2_item.active:
                items["boots2"] = {"pos": speed_boots2_item.pos}
        if medikit_item != null and is_instance_valid(medikit_item) and medikit_item.active:
                items["medikit"] = {"pos": medikit_item.pos}
        if knight_statue_item != null and is_instance_valid(knight_statue_item) and knight_statue_item.active:
                items["statue"] = {"pos": knight_statue_item.pos}
        if dynamite_item != null and is_instance_valid(dynamite_item) and dynamite_item.active:
                items["dynamite"] = {"pos": dynamite_item.pos}
        if potion_item != null and is_instance_valid(potion_item) and potion_item.active:
                items["potion"] = {"pos": potion_item.pos}
        if hammer_item != null and is_instance_valid(hammer_item) and hammer_item.active:
                items["hammer"] = {"pos": hammer_item.pos}
        snap["items"] = items
        # --- Porta di uscita ---
        snap["exit_door"] = {
                "active": bool(exit_door.get("active", false)),
                "pos": exit_door.get("pos", Vector2.ZERO),
        }
        # --- Hurry Up + fantasmi immortali ---
        snap["hurry_up_active"] = hurry_up_active
        var ghosts_snap: Array = []
        for g in ghost_reapers:
                if g == null or not is_instance_valid(g):
                        continue
                ghosts_snap.append({
                        "pos": g.position,
                        "target_player_num": int(g.get("target_player_num")),
                        "red": bool(g.get("is_red_variant")),
                })
        snap["ghosts"] = ghosts_snap
        # --- Martello ---
        if hammer_player != 0:
                snap["hammer"] = {"player": hammer_player, "uses_left": hammer_uses_left}
        # --- TASK 50: pergamena del ghiaccio equipaggiata ---
        if freeze_scroll_player != 0:
                snap["freeze_scroll"] = {"player": freeze_scroll_player,
                                "charges_left": freeze_charges_left}
        # --- Dinamite (se in mano senza essere scoppiata) ---
        snap["dynamite_equipped"] = dynamite_equipped
        snap["dynamite_player"] = dynamite_player
        snap["dynamite_fuse_ms"] = dynamite_fuse_timer_ms
        # --- Player: punteggio, arma, stivali, prossima vita extra ---
        var p1_snap: Dictionary = {
                "score": player.score,
                "next_life_threshold": player.next_life_threshold,
                "weapon": player.current_weapon.duplicate(),
                "boots": player.permanent_speed_boost,
        }
        snap["p1"] = p1_snap
        if GameManager and GameManager.num_players == 2 and player2.visible:
                snap["p2"] = {
                        "score": player2.score,
                        "next_life_threshold": player2.next_life_threshold,
                        "weapon": player2.current_weapon.duplicate(),
                        "boots": player2.permanent_speed_boost,
                }
        return snap


## Ripristina i nemici vivi dallo snapshot del continue (tipo, posizione
## esatta e HP residui al momento della morte).
func _restore_enemies_from_snapshot(restore: Dictionary) -> void:
        for e in restore.get("enemies", []):
                var enemy: Enemy = spawner._spawn_enemy_instance(
                                int(e.get("type", 0)),
                                int(e.get("col", 1)), int(e.get("row", 1)))
                if enemy == null:
                        continue
                var pos: Vector2 = e.get("pos", enemy.position)
                enemy.position = pos
                enemy.last_pos = pos
                enemy.health = int(e.get("health", enemy.max_health))
        initial_enemy_count = int(restore.get("initial_count", spawner.enemies.size()))
        portal_used = bool(restore.get("portal_used_local", false))


## Ripristina la sessione dallo snapshot: item a terra, spawner/portale,
## mini-boss, porta, fantasmi, martello, dinamite e stato dei player.
func _restore_session_from_snapshot(snap: Dictionary) -> void:
        # --- Item a terra: SOLO quelli non raccolti alla morte, alle stesse
        # posizioni (i tesori raccolti non riappaiono: la griglia e' stata
        # gia' ripristinata cella per cella). ---
        for child in collectibles_node.get_children():
                child.queue_free()
        CollectiblesClass.clear_texture_cache()
        mine_item = null
        chalice_item = null
        scepter_item = null
        speed_boots_item = null
        speed_boots2_item = null
        medikit_item = null
        knight_statue_item = null
        dynamite_item = null
        potion_item = null
        hammer_item = null
        if knight_ally != null and is_instance_valid(knight_ally):
                knight_ally.queue_free()
                knight_ally = null
        var items: Dictionary = snap.get("items", {})
        var kind_map: Dictionary = {
                "mine": CollectiblesClass.Kind.MINE,
                "chalice": CollectiblesClass.Kind.CHALICE,
                "scepter": CollectiblesClass.Kind.SCEPTER,
                "boots1": CollectiblesClass.Kind.SPEED_BOOTS,
                "boots2": CollectiblesClass.Kind.SPEED_BOOTS,
                "medikit": CollectiblesClass.Kind.MEDIKIT,
                "statue": CollectiblesClass.Kind.KNIGHT_STATUE,
                "dynamite": CollectiblesClass.Kind.DYNAMITE,
                "potion": CollectiblesClass.Kind.POTION,
                "hammer": CollectiblesClass.Kind.HAMMER,
        }
        for key in items.keys():
                var it: Dictionary = items.get(key, {})
                if it.is_empty() or not kind_map.has(key):
                        continue
                var node: Collectibles = _create_collectible(int(kind_map[key]),
                                it.get("pos", Vector2.ZERO))
                if key == "boots1":
                        node.owner_id = 1
                elif key == "boots2":
                        node.owner_id = 2
                if key == "statue":
                        node.active = true
                collectibles_node.add_child(node)
                match key:
                        "mine": mine_item = node
                        "chalice": chalice_item = node
                        "scepter": scepter_item = node
                        "boots1": speed_boots_item = node
                        "boots2": speed_boots2_item = node
                        "medikit": medikit_item = node
                        "statue": knight_statue_item = node
                        "dynamite": dynamite_item = node
                        "potion": potion_item = node
                        "hammer": hammer_item = node
        medikit_used = not items.has("medikit")
        # --- Spawner: portale e soglia del 50% ---
        spawner.initial_count = int(snap.get("initial_count", spawner.enemies.size()))
        spawner.portal_used = bool(snap.get("portal_used", false))
        # TASK 23 (respawn progressivo): budget residuo del portale.
        spawner.respawn_budget = int(snap.get("respawn_budget", 0))
        spawner.progressive_respawn = bool(snap.get("progressive_respawn", false))
        _last_alive_enemies = spawner.alive_count()
        var portal_snap: Dictionary = snap.get("portal", {})
        if not portal_snap.is_empty() and bool(portal_snap.get("active", false)):
                spawner.magic_portal.pos = portal_snap.get("pos", Vector2.ZERO)
                spawner.magic_portal.active = true
                spawner.magic_portal.phase = int(portal_snap.get("phase", 1))
                # FIX (Task 40): scrive le chiavi REALI della state machine del
                # portale (phase_timer / spawn_timer): prima creava chiavi
                # fantasma "*_ms" mai lette da update_portal.
                spawner.magic_portal.phase_timer = int(portal_snap.get("phase_timer_ms", 4000))
                spawner.magic_portal.enemies_to_spawn = int(portal_snap.get("enemies_to_spawn", 0))
                spawner.magic_portal.spawn_timer = int(portal_snap.get("spawn_timer_ms", 4000))
        # --- Mini-boss: ricreato con gli HP che aveva alla morte ---
        var mb_snap: Dictionary = snap.get("mini_boss", {})
        if not mb_snap.is_empty():
                var mb_col: int = int(mb_snap.get("col", 15))
                var mb_row: int = int(mb_snap.get("row", 7))
                _spawn_mini_boss(mb_col, mb_row)
                if mini_boss != null and is_instance_valid(mini_boss):
                        mini_boss.position = mb_snap.get("pos", mini_boss.position)
                        mini_boss.health = int(mb_snap.get("health", mini_boss.health))
        # --- Porta di uscita (se era gia' aperta) ---
        var door_snap: Dictionary = snap.get("exit_door", {})
        if bool(door_snap.get("active", false)):
                exit_door = {
                        "pos": door_snap.get("pos", Vector2.ZERO),
                        "active": true,
                        "anim_timer_ms": 0,
                        "glow_pulse": 0.0,
                }
        # --- Hurry Up + fantasmi immortali ---
        hurry_up_active = bool(snap.get("hurry_up_active", false))
        ghost_reapers.clear()
        if hurry_up_active:
                _hurry_up_time = 0.0
                for g in snap.get("ghosts", []):
                        var ghost := GhostReaperClass.new()
                        ghost.set("target_player_num", int(g.get("target_player_num", 1)))
                        if bool(g.get("red", false)):
                                ghost.set("is_red_variant", true)
                        var g_col: int = int(g.get("pos", Vector2.ZERO).x / C.TILE_SIZE)
                        var g_row: int = int((g.get("pos", Vector2.ZERO).y - C.UI_HEIGHT) / C.TILE_SIZE)
                        ghost.setup(g_col, g_row)
                        ghost.position = g.get("pos", Vector2.ZERO)
                        ghost.laughed.connect(_on_ghost_laughed)
                        add_child(ghost)
                        ghost_reapers.append(ghost)
        # --- Martello: in mano al player giusto con i lanci rimasti ---
        var hammer_snap: Dictionary = snap.get("hammer", {})
        hammer_player = 0
        hammer_uses_left = 0
        if not hammer_snap.is_empty():
                hammer_player = int(hammer_snap.get("player", 1))
                hammer_uses_left = int(hammer_snap.get("uses_left", 0))
        player.set_hammer_equipped(hammer_player == 1 and hammer_uses_left > 0)
        player2.set_hammer_equipped(hammer_player == 2 and hammer_uses_left > 0)
        # --- TASK 50: pergamena del ghiaccio in spalla al player giusto ---
        var freeze_snap: Dictionary = snap.get("freeze_scroll", {})
        freeze_scroll_player = 0
        freeze_charges_left = 0
        if not freeze_snap.is_empty():
                freeze_scroll_player = int(freeze_snap.get("player", 1))
                freeze_charges_left = int(freeze_snap.get("charges_left", 0))
        player.set_freeze_scroll_equipped(
                        freeze_scroll_player == 1 and freeze_charges_left > 0)
        player2.set_freeze_scroll_equipped(
                        freeze_scroll_player == 2 and freeze_charges_left > 0)
        # --- Dinamite equipaggiata (senza miccia evoluta: riparte da 7s) ---
        dynamite_equipped = bool(snap.get("dynamite_equipped", false))
        dynamite_fuse_timer_ms = int(snap.get("dynamite_fuse_ms", 7000)) \
                        if dynamite_equipped else 0
        # FIX (2P): ripristina il proprietario della dinamite (chi la tira,
        # chi subisce l'esplosione della miccia, su chi viene disegnata).
        dynamite_player = int(snap.get("dynamite_player", 1))
        dynamite_alert_played = false
        dynamite_explode_timer_ms = 0
        # --- Player: punteggio, arma, stivali (le vite sono quelle nuove
        # del continue: e' la regola arcade del credito). ---
        var p1_snap: Dictionary = snap.get("p1", {})
        if not p1_snap.is_empty():
                player.score = int(p1_snap.get("score", 0))
                player.next_life_threshold = int(p1_snap.get("next_life_threshold", 100000))
                var w1: Dictionary = p1_snap.get("weapon", {})
                if not w1.is_empty():
                        player.current_weapon = w1.duplicate()
                player.permanent_speed_boost = bool(p1_snap.get("boots", false))
        var p2_snap: Dictionary = snap.get("p2", {})
        if not p2_snap.is_empty() and GameManager and GameManager.num_players == 2:
                player2.visible = true
                player2.score = int(p2_snap.get("score", 0))
                player2.next_life_threshold = int(p2_snap.get("next_life_threshold", 100000))
                var w2: Dictionary = p2_snap.get("weapon", {})
                if not w2.is_empty():
                        player2.current_weapon = w2.duplicate()
                player2.permanent_speed_boost = bool(p2_snap.get("boots", false))
        # --- HUD: aggiorna subito con lo stato ripristinato ---
        _update_hud_snapshot()
        print("[Continue] Sessione maze ripristinata: livello ", current_level,
                        ", nemici ", spawner.enemies.size(),
                        ", tesori residui ", maze.get_remaining_treasures())


# Aggiorna l'HUD con lo stato corrente (usato al termine del restore).
func _update_hud_snapshot() -> void:
        if hud == null:
                return
        hud.set_player_state({
                "score": player.score,
                "lives": player.lives,
                "energy": player.energy,
                "max_energy": player.max_energy,
                "weapon_name": C.get_weapon_name(int(player.current_weapon.get("type", 0))),
                "weapon_color": C.get_weapon_color(int(player.current_weapon.get("type", 0))),
                "weapon_ammo": player.current_weapon.get("ammo", 0),
                "weapon_max": player.current_weapon.get("max_ammo", 15),
                "stamina": player.get_stamina_ratio(),
                "stamina_exhausted": player.is_stamina_exhausted(),
                # RELIC (Task 21): stato armatura reliquia in HUD.
                "armor_name": C.get_armor_short_name(player.armor_relic),
                "armor_color": player.armor_relic.get("color", Color.WHITE),
                "armor_charges": player.armor_charges(),
                "armor_max": int(player.armor_relic.get("max_charges", 0)),
        })
        if GameManager and GameManager.num_players == 2 and player2.visible:
                hud.set_player2_state({
                        "score": player2.score,
                        "lives": player2.lives,
                        "energy": player2.energy,
                        "max_energy": player2.max_energy,
                        "weapon_name": C.get_weapon_name(int(player2.current_weapon.get("type", 0))),
                        "weapon_color": C.get_weapon_color(int(player2.current_weapon.get("type", 0))),
                        "weapon_ammo": player2.current_weapon.get("ammo", 0),
                        "weapon_max": player2.current_weapon.get("max_ammo", 15),
                        "stamina": player2.get_stamina_ratio(),
                        "stamina_exhausted": player2.is_stamina_exhausted(),
                        # RELIC (Task 21): stato armatura reliquia in HUD (P2).
                        "armor_name": C.get_armor_short_name(player2.armor_relic),
                        "armor_color": player2.armor_relic.get("color", Color.WHITE),
                        "armor_charges": player2.armor_charges(),
                        "armor_max": int(player2.armor_relic.get("max_charges", 0)),
                })


# ============================================================================
# FIX (martello di Thor — nuova meccanica): lancio, volo e ritorno
# ============================================================================

## Lancia il martello di Thor nella direzione in cui e' rivolto il player.
## Consuma uno dei 2 usi: quando uses_left arriva a 0, al ritorno il
## martello SCOMPARE dal player (il lancio in corso si conclude comunque).
func _throw_hammer(p: CharacterBody2D) -> void:
        if hammer_thrown != null and is_instance_valid(hammer_thrown):
                return  # martello gia' in volo
        if hammer_uses_left <= 0:
                hammer_player = 0
                p.set_hammer_equipped(false)
                return
        var dir_vec: Vector2 = Vector2(float(p.last_dx), float(p.last_dy))
        if dir_vec == Vector2.ZERO:
                dir_vec = Vector2(1.0, 0.0)
        dir_vec = dir_vec.normalized()
        var hammer := HammerClass.new()
        hammer.dir = dir_vec
        hammer.speed = 13.0
        hammer.position = p.get_pixel_pos() + dir_vec * 24.0
        # FIX (2P): il martello torna SEMPRE a chi lo ha lanciato, anche
        # all'ultimo lancio (dopo il quale scompare).
        hammer.set_meta("thrower_num", 1 if p == player else 2)
        hammer_thrown = hammer
        # Consuma l'uso e toglie subito il martello dalla mano (e' in volo).
        hammer_uses_left -= 1
        p.set_hammer_equipped(false)
        if hammer_uses_left <= 0:
                hammer_player = 0
        # Contenitore sicuro (come la dinamite lanciata).
        collectibles_node.add_child(hammer)
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.HAMMER_THROW)
        print("[Hammer] Lanciato da P", 1 if p == player else 2,
                        " (usi rimasti: ", hammer_uses_left, ")")


## Update del martello in volo: andata (fino a nemico/muro/max corsa) e
## ritorno in mano al player. Chiamato da _update_playing a ogni frame.
func _update_thrown_hammer(delta_ms: float) -> void:
        if hammer_thrown == null or not is_instance_valid(hammer_thrown):
                hammer_thrown = null
                return
        var hammer = hammer_thrown  # dynamic: Hammer.gd (Node2D + proprieta' di volo)
        var steps_scale: float = delta_ms / 16.6667
        # Il martello torna a chi lo ha lanciato (meta sul nodo, valida anche
        # per l'ultimo lancio dopo il quale hammer_player viene azzerato).
        var thrower_num: int = int(hammer.get_meta("thrower_num", 1))
        var owner_p: CharacterBody2D = player2 if thrower_num == 2 else player
        # Rotazione costante (piu' veloce al ritorno, come Mjolnir).
        hammer.spin_deg = fmod(hammer.spin_deg
                        + (26.0 if hammer.phase == 0 else 40.0) * steps_scale, 360.0)
        if hammer.phase == 0:
                # ================= ANDATA =================
                var new_pos: Vector2 = hammer.position + hammer.dir * hammer.speed * steps_scale
                hammer.travelled_px += hammer.speed * steps_scale
                # Tunnel Pac-Man: il martello attraversa le gallerie.
                var wrapped: Vector2 = GameConstants.tunnel_wrap(new_pos)
                if wrapped != new_pos:
                        new_pos = wrapped
                var hit_cell: Vector2i = Vector2i(
                                int(new_pos.x / C.TILE_SIZE),
                                int((new_pos.y - C.UI_HEIGHT) / C.TILE_SIZE))
                # --- Impatto con MURO ---
                if hit_cell.x >= 0 and hit_cell.x < C.MAZE_COLS \
                                and hit_cell.y >= 0 and hit_cell.y < C.MAZE_ROWS \
                                and maze.is_wall(hit_cell.x, hit_cell.y):
                        var is_border: bool = hit_cell.x == 0 or hit_cell.x == C.MAZE_COLS - 1 \
                                        or hit_cell.y == 0 or hit_cell.y == C.MAZE_ROWS - 1
                        if not is_border:
                                # MURO INTERNO: si rompe (effetto sgretolamento)
                                _break_internal_wall(hit_cell, new_pos)
                        else:
                                # Muro di BORDO: indistruttibile (nessun altro
                                # effetto Pac-Man oltre alle gallerie).
                                if AudioManager:
                                        AudioManager.play_sound(AudioManager.SoundType.HAMMER_CLANK)
                                if EffectsManager:
                                        var spark_burst := EffectsManager.spawn_sparks(new_pos, 14)
                                        collectibles_node.add_child(spark_burst)
                                        EffectsManager.screen_shake(5.0, 0.2)
                        hammer.position = new_pos - hammer.dir * 10.0
                        hammer.start_return()
                        return
                hammer.position = new_pos
                hammer.push_trail_point(new_pos)
                # --- Impatto con NEMICO (50% HP max) ---
                for enemy in spawner.enemies:
                        if enemy.is_dead():
                                continue
                        if new_pos.distance_squared_to(enemy.get_pixel_pos()) < 700.0:
                                var dmg: int = enemy.take_hammer_hit()
                                last_hit_enemy = enemy
                                last_hit_enemy_timer_ms = 3000
                                if AudioManager:
                                        AudioManager.play_sound(AudioManager.SoundType.HAMMER_CLANK)
                                        AudioManager.play_sound(AudioManager.SoundType.BLOOD_SPLAT)
                                if EffectsManager:
                                        var hit_burst := EffectsManager.spawn_explosion(new_pos,
                                                Color(0.65, 0.8, 1.0), 16, 0.5)
                                        collectibles_node.add_child(hit_burst)
                                        EffectsManager.screen_shake(6.0, 0.25)
                                if enemy.is_dead():
                                        owner_p.add_score(5000)
                                        if AudioManager:
                                                AudioManager.play_sound(AudioManager.SoundType.ENEMY_DEATH)
                                        _spawn_blood_stain(enemy.get_pixel_pos())
                                        _spawn_fire_burst(enemy.get_pixel_pos(), 1.0)
                                print("[Hammer] Nemico colpito: -", dmg, " HP")
                                hammer.start_return()
                                return
                # --- Impatto con MINI-BOSS (35% HP max, come lo scettro) ---
                if mini_boss != null and is_instance_valid(mini_boss) and not mini_boss.is_dead():
                        if new_pos.distance_squared_to(mini_boss.get_pixel_pos()) < 1100.0:
                                var mb_max: int = mini_boss.get_max_health()
                                var mb_dmg: int = maxi(1, int(float(mb_max) * 0.35))
                                mini_boss.take_damage(mb_dmg)
                                last_hit_enemy = mini_boss
                                last_hit_enemy_timer_ms = 3000
                                if AudioManager:
                                        AudioManager.play_sound(AudioManager.SoundType.HAMMER_CLANK)
                                        AudioManager.play_sound(AudioManager.SoundType.BOSS_HIT)
                                if EffectsManager:
                                        var mb_burst := EffectsManager.spawn_explosion(new_pos,
                                                Color(0.65, 0.8, 1.0), 20, 0.6)
                                        collectibles_node.add_child(mb_burst)
                                        EffectsManager.screen_shake(7.0, 0.3)
                                hammer.start_return()
                                return
                # --- Fantasmi immortali: assorbono il martello (risata) ---
                for ghost in ghost_reapers:
                        if ghost == null or not is_instance_valid(ghost):
                                continue
                        if new_pos.distance_squared_to(ghost.get_pixel_pos()) < 1500.0:
                                ghost.take_damage(1)  # immortale: risata
                                hammer.start_return()
                                return
                # --- TASK 34 (pipistrelli): il martello e' un'arma bonus —
                # attraverso lo sciame abbatte un pipistrello per passaggio
                # (due passaggi lo disperdono), poi torna indietro ---
                if bat_cloud != null and is_instance_valid(bat_cloud):
                        if new_pos.distance_squared_to(bat_cloud.position) < 1600.0:
                                bat_cloud.take_projectile_hit(owner_p)
                                if AudioManager:
                                        AudioManager.play_sound(AudioManager.SoundType.HAMMER_CLANK)
                                if EffectsManager:
                                        var bat_burst := EffectsManager.spawn_explosion(new_pos,
                                                Color(0.65, 0.8, 1.0), 12, 0.4)
                                        collectibles_node.add_child(bat_burst)
                                hammer.start_return()
                                return
                # --- Corsa massima: ritorno automatico ---
                if hammer.travelled_px >= HammerClass.MAX_TRAVEL_PX:
                        hammer.start_return()
                return
        # ================= RITORNO =================
        var target_pos: Vector2 = owner_p.get_pixel_pos()
        var to_target: Vector2 = target_pos - hammer.position
        var dist: float = to_target.length()
        var step: float = hammer.speed * steps_scale
        if dist <= maxf(step, 22.0):
                # Il martello raggiunge chi lo ha lanciato.
                hammer.queue_free()
                hammer_thrown = null
                if hammer_player != 0 and hammer_uses_left > 0:
                        # Ulteriori lanci disponibili: il martello torna in mano.
                        owner_p.set_hammer_equipped(true)
                        if AudioManager:
                                AudioManager.play_sound(AudioManager.SoundType.HAMMER_CLANK)
                        print("[Hammer] Tornato in mano (lanci rimasti: ", hammer_uses_left, ")")
                else:
                        # Ultimo lancio usato: il martello SPARISCE dal player.
                        hammer_player = 0
                        hammer_uses_left = 0
                        if EffectsManager:
                                var vanish := EffectsManager.spawn_pickup_burst(target_pos,
                                        Color(0.6, 0.85, 1.0))
                                collectibles_node.add_child(vanish)
                        print("[Hammer] Usi esauriti: il martello scompare dal player")
                return
        var dir_back: Vector2 = to_target / maxf(dist, 0.001)
        hammer.position += dir_back * step
        hammer.push_trail_point(hammer.position)


## Rompe il muro INTERNO colpito dal martello: la cella diventa pavimento
## (scorciatoia usabile da player E nemici: BFS la vede subito), con effetto
## di sgretolamento (frammenti di pietra, polvere, screen shake e suono).
func _break_internal_wall(cell: Vector2i, impact_pos: Vector2) -> void:
        var broken: bool = maze.break_wall(cell.x, cell.y)
        if not broken:
                if AudioManager:
                        AudioManager.play_sound(AudioManager.SoundType.HAMMER_CLANK)
                return
        var cell_center: Vector2 = Vector2(
                        cell.x * C.TILE_SIZE + C.TILE_SIZE / 2.0,
                        cell.y * C.TILE_SIZE + C.TILE_SIZE / 2.0 + C.UI_HEIGHT)
        # Sgretolamento: 3 ondate di frammenti di pietra con colori del muro.
        if EffectsManager:
                var stone_a: Color = maze.wall_color.lightened(0.15)
                var stone_b: Color = maze.wall_color.darkened(0.2)
                var stone_c: Color = Color(0.55, 0.5, 0.42)
                for i in 3:
                        var burst := EffectsManager.spawn_explosion(
                                        cell_center + Vector2(randf() * 30.0 - 15.0,
                                                        randf() * 30.0 - 15.0),
                                        [stone_a, stone_b, stone_c][i], 26, 0.7 + 0.25 * float(i))
                        collectibles_node.add_child(burst)
                var dust := EffectsManager.spawn_sparks(cell_center, 20)
                collectibles_node.add_child(dust)
                EffectsManager.screen_shake(10.0, 0.45)
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.WALL_CRUMBLE)
                AudioManager.play_sound(AudioManager.SoundType.HAMMER_CLANK)
        screen_flash_timer_ms = 60
        print("[Hammer] Muro interno spezzato alla cella (", cell.x, ",", cell.y,
                        "): nuova scorciatoia aperta")


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
        # FIX (2P): reset del proprietario della dinamite a ogni livello.
        dynamite_player = 1
        dynamite_fuse_timer_ms = 0
        dynamite_alert_played = false
        dynamite_explode_timer_ms = 0
        if dynamite_thrown != null and is_instance_valid(dynamite_thrown):
                dynamite_thrown.queue_free()
                dynamite_thrown = null
        # FIX (pozione magica): reset pozione + stato fantasma (la musica
        # fantasma vive sull'autoload AudioManager e sopravvive al cambio
        # livello: va fermata qui).
        potion_item = null
        _ghost_was_active = false
        if AudioManager:
                AudioManager.stop_ghost_music()
        # FIX (martello di Thor): reset stato martello a inizio livello.
        hammer_item = null
        hammer_player = 0
        hammer_uses_left = 0
        if hammer_thrown != null and is_instance_valid(hammer_thrown):
                hammer_thrown.queue_free()
        hammer_thrown = null
        if player != null:
                player.set_hammer_equipped(false)
        if player2 != null:
                player2.set_hammer_equipped(false)
        # FIX (HUD last hit enemy): reset al cambio livello
        last_hit_enemy = null
        last_hit_enemy_timer_ms = 0

        # Find empty cells far from player start (Manhattan distance >= 5)
        # FIX (sprite uno sopra l'altro): la vecchia condizione `not
        # maze.is_wall(c, r)` includeva anche le celle TREASURE e WEAPON del
        # maze -> mine/calice/scettro/statua/pozione potevano spuntare SOPRA
        # un tesoro o un'arma (screenshot utente: unicorno sopra le monete
        # d'oro). Ora si usa SOLO il tipo EMPTY: ogni collectible nasce su
        # pavimento pulito, ben distanziato da tesori e armi del maze.
        var empty_cells: Array = []
        for r in range(1, C.MAZE_ROWS - 1):
                for c in range(1, C.MAZE_COLS - 1):
                        if maze.get_cell_type(c, r) == C.CellType.EMPTY \
                                        and not (c < 5 and r < 5):
                                empty_cells.append(Vector2i(c, r))
        if empty_cells.is_empty():
                return

        # Shuffle and pick cells for each collectible
        empty_cells.shuffle()

        # FIX (oggetti troppo vicini): traccia le celle già usate e prendi solo
        # celle a distanza minima (Manhattan >= 3) da quelle già usate. Questo
        # previene sovrapposizioni come "bomba sopra l'oro".
        var used_cells: Array = []
        const MIN_DIST_BETWEEN_ITEMS: int = 3

        # Mine (item index 0)
        var cell: Vector2i = _pop_cell_far_enough(empty_cells, used_cells, MIN_DIST_BETWEEN_ITEMS)
        if cell.x >= 0:
                var mine_pos := _cell_to_pixel(cell)
                mine_item = _create_collectible(CollectiblesClass.Kind.MINE, mine_pos)
                collectibles_node.add_child(mine_item)

        # Chalice (invincibility)
        cell = _pop_cell_far_enough(empty_cells, used_cells, MIN_DIST_BETWEEN_ITEMS)
        if cell.x >= 0:
                var chalice_pos := _cell_to_pixel(cell)
                chalice_item = _create_collectible(CollectiblesClass.Kind.CHALICE, chalice_pos)
                collectibles_node.add_child(chalice_item)

        # Scepter (lightning)
        cell = _pop_cell_far_enough(empty_cells, used_cells, MIN_DIST_BETWEEN_ITEMS)
        if cell.x >= 0:
                var scepter_pos := _cell_to_pixel(cell)
                scepter_item = _create_collectible(CollectiblesClass.Kind.SCEPTER, scepter_pos)
                collectibles_node.add_child(scepter_item)

        # Speed boots (P1)
        cell = _pop_cell_far_enough(empty_cells, used_cells, MIN_DIST_BETWEEN_ITEMS)
        if cell.x >= 0:
                var boots_pos := _cell_to_pixel(cell)
                speed_boots_item = _create_collectible(CollectiblesClass.Kind.SPEED_BOOTS, boots_pos)
                speed_boots_item.owner_id = 1
                collectibles_node.add_child(speed_boots_item)

        # Speed boots (P2, if 2 players)
        if GameManager and GameManager.num_players == 2:
                cell = _pop_cell_far_enough(empty_cells, used_cells, MIN_DIST_BETWEEN_ITEMS)
                if cell.x >= 0:
                        var boots_pos := _cell_to_pixel(cell)
                        speed_boots2_item = _create_collectible(CollectiblesClass.Kind.SPEED_BOOTS, boots_pos)
                        speed_boots2_item.owner_id = 2
                        collectibles_node.add_child(speed_boots2_item)

        # FIX (nuova meccanica): Medikit (1 per livello, posizione casuale)
        cell = _pop_cell_far_enough(empty_cells, used_cells, MIN_DIST_BETWEEN_ITEMS)
        if cell.x >= 0:
                var medikit_pos := _cell_to_pixel(cell)
                medikit_item = _create_collectible(CollectiblesClass.Kind.MEDIKIT, medikit_pos)
                collectibles_node.add_child(medikit_item)

        # FIX (nuova meccanica): Statua cavaliere (1 per livello, posizione casuale)
        # FIX (statua appare subito): prima active=false con delay 5-15s, ora
        # active=true da subito come le altre armi (medikit, chalice, ecc.)
        cell = _pop_cell_far_enough(empty_cells, used_cells, MIN_DIST_BETWEEN_ITEMS)
        if cell.x >= 0:
                var statue_pos := _cell_to_pixel(cell)
                knight_statue_item = _create_collectible(CollectiblesClass.Kind.KNIGHT_STATUE, statue_pos)
                knight_statue_item.active = true
                collectibles_node.add_child(knight_statue_item)

        # FIX (nuova meccanica): Dinamite (1 per livello, posizione casuale)
        cell = _pop_cell_far_enough(empty_cells, used_cells, MIN_DIST_BETWEEN_ITEMS)
        if cell.x >= 0:
                var dyn_pos := _cell_to_pixel(cell)
                dynamite_item = _create_collectible(CollectiblesClass.Kind.DYNAMITE, dyn_pos)
                collectibles_node.add_child(dynamite_item)

        # FIX (pozione magica): Pozione (1 per livello, posizione casuale).
        # Ampolla di vetro con liquido verde: chi la beve diventa un fantasma
        # evanescente per 5 secondi e attraversa i muri del labirinto.
        cell = _pop_cell_far_enough(empty_cells, used_cells, MIN_DIST_BETWEEN_ITEMS)
        if cell.x >= 0:
                var potion_pos := _cell_to_pixel(cell)
                potion_item = _create_collectible(CollectiblesClass.Kind.POTION, potion_pos)
                collectibles_node.add_child(potion_item)

        # FIX (martello di Thor — nuova meccanica): Mjolnir (1 per livello,
        # posizione casuale). Chi lo raccoglie puo' lanciarlo 2 volte: 50%
        # dei danni ai nemici e spezza i muri INTERNI del labirinto.
        cell = _pop_cell_far_enough(empty_cells, used_cells, MIN_DIST_BETWEEN_ITEMS)
        if cell.x >= 0:
                var hammer_pos := _cell_to_pixel(cell)
                hammer_item = _create_collectible(CollectiblesClass.Kind.HAMMER, hammer_pos)
                collectibles_node.add_child(hammer_item)


# FIX (oggetti troppo vicini): estrae una cella dalla lista `cells` che sia
# a distanza Manhattan >= min_dist da tutte le celle in `used`. Rimuove la
# cella estratta da `cells` e la aggiunge a `used`. Ritorna Vector2i(-1, -1)
# se nessuna cella rispetta il vincolo (caso raro: labirinto piccolo).
func _pop_cell_far_enough(cells: Array, used: Array, min_dist: int) -> Vector2i:
        var i: int = 0
        while i < cells.size():
                var candidate: Vector2i = cells[i]
                var ok: bool = true
                for u in used:
                        if abs(u.x - candidate.x) + abs(u.y - candidate.y) < min_dist:
                                ok = false
                                break
                if ok:
                        cells.remove_at(i)
                        used.append(candidate)
                        return candidate
                i += 1
        # Fallback: se nessuna cella rispetta il vincolo, prendi la prima disponibile
        if cells.size() > 0:
                var fallback: Vector2i = cells.pop_back()
                used.append(fallback)
                return fallback
        return Vector2i(-1, -1)


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
                print("[MiniBoss] Already spawned, skipping!")
                return
        var mb_type: int = (current_level - 1) % 51  # cycle through 51 types
        var mb := MiniBossClass.new()
        mb.setup(mb_type, current_level, col, row)
        add_child(mb)
        mini_boss = mb
        mini_boss_spawned = true
        print("[MiniBoss] Spawned type=", mb_type, " sprite_id=", mb.sprite_id, " sprite_loaded=", mb.sprite_loaded, " at cell (", col, ",", row, ")")
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.PORTAL_OPEN)


# ============================================================================
# FIX (meccanica "Hurry Up!" — fantasma immortale dal portale)
# ============================================================================
# Timer + trigger: quando TUTTI i nemici del labirinto (compresi quelli
# respawnati: il portale ha finito la sua coda) sono morti E sono passati
# 10 secondi dall'ultimo tesoro raccolto, appare la scritta e dal portale
# emerge il fantasma. Se il player raccoglie un tesoro, i 10s ripartono
# (un player ATTIVO non viene punito: "Hurry Up!" significa muoversi!).
func _update_hurry_up(delta_ms: float, p_grid: Vector2i, p_pos: Vector2) -> void:
        _since_last_treasure_ms += float(delta_ms)
        if hurry_up_active:
                _hurry_up_time += float(delta_ms) * 0.001
        if _ghost_laugh_cooldown_ms > 0:
                _ghost_laugh_cooldown_ms = maxi(0, _ghost_laugh_cooldown_ms - int(delta_ms))

        # FIX (2P): i fantasmi già attivi inseguono il LORO player per tutto
        # il tempo (verde -> P1, rosso -> P2); se il loro player è eliminato,
        # ripiegano sull'altro (non smettono mai di dare la caccia).
        if ghost_reapers.size() > 0:
                for ghost in ghost_reapers:
                        if ghost == null or not is_instance_valid(ghost):
                                continue
                        var target_p: CharacterBody2D = _ghost_target_player(ghost)
                        ghost.update_step(maze, target_p.get_grid_pos(), int(delta_ms))
                return

        # Trigger una sola volta per livello.
        if hurry_up_active:
                return
        # "Tutti i nemici uccisi, respawn compresi": zero nemici vivi E il
        # portale non ha respawn in sospeso (se la coda è ancora aperta,
        # altri nemici stanno per uscire → la condizione non è ancora vera).
        # TASK 23: anche il budget del respawn progressivo conta come coda
        # aperta (post-5° boss il portale ha sempre nemici da sfornare finché
        # il budget non è esaurito).
        var portal_spawning: bool = (spawner.magic_portal.active \
                        and spawner.magic_portal.enemies_to_spawn > 0) \
                        or spawner.respawn_pending()
        var all_dead: bool = initial_enemy_count > 0 \
                        and spawner.alive_count() == 0 \
                        and not portal_spawning
        if all_dead and _since_last_treasure_ms >= HURRY_UP_DELAY_MS:
                _trigger_hurry_up(p_pos)


# Attiva la scritta "Hurry Up!" e fa emergere i fantasmi dal portale.
# FIX (2P): in due giocatori NON è uno ma DUE mini boss immortali, uno per
# player, diversi solo nel colore (verde per P1, rosso per P2): entrambi
# emergono dal portale (il secondo da una cella adiacente libera).
# TASK 23 (fix utente): un fantasma per OGNI PLAYER VIVO — se in 2P un
# player è già morto/eliminato e ne resta uno solo, dal portale esce UN
# SOLO fantasma (prima ne uscivano due anche con un solo giocatore in vita).
func _trigger_hurry_up(_p_pos: Vector2) -> void:
        hurry_up_active = true
        _hurry_up_time = 0.0
        # Posizione del portale (l'ultima usata: resta valida anche dopo la
        # chiusura perché pos non viene azzerata). Fallback: centro maze.
        var spawn_pos: Vector2 = spawner.magic_portal.pos
        var spawn_col: int = int(spawn_pos.x / C.TILE_SIZE)
        var spawn_row: int = int((spawn_pos.y - C.UI_HEIGHT) / C.TILE_SIZE)
        if spawn_col <= 0 or spawn_row <= 0 or spawn_col >= C.MAZE_COLS - 1 \
                        or spawn_row >= C.MAZE_ROWS - 1:
                var center_cell: Vector2i = _find_empty_cell_near_center()
                spawn_col = center_cell.x
                spawn_row = center_cell.y
        if spawn_col < 0:
                return  # maze degenere: niente fantasmi
        # Il portale si RIAPRE visivamente e i fantasmi emergono da lì.
        spawner.reopen_portal_for_ghost()
        # TASK 23: un fantasma per player VIVO (verde -> P1, rosso -> P2).
        var p1_alive: bool = player != null and is_instance_valid(player) \
                        and player.lives > 0 and not player.soul_pending
        var p2_alive: bool = GameManager and GameManager.num_players == 2 \
                        and player2 != null and is_instance_valid(player2) \
                        and player2.visible and player2.lives > 0 \
                        and not player2.soul_pending
        var next_cell: Vector2i = Vector2i(spawn_col, spawn_row)
        if p1_alive:
                next_cell = _spawn_ghost_at(1, false, next_cell)
        if p2_alive:
                next_cell = _spawn_ghost_at(2, true, next_cell)
        print("[HurryUp] Fantasmi immortali spawnati dal portale a cell (",
                        spawn_col, ",", spawn_row, ") x", ghost_reapers.size())
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.PORTAL_OPEN)
                AudioManager.play_sound(AudioManager.SoundType.DARK_LAUGH)


# TASK 23: spawna UN fantasma (target_player_num, eventuale variante rossa)
# su `cell` o su una cella adiacente libera; ritorna la cella usata così il
# secondo fantasma nasce accanto e non sopra il primo.
func _spawn_ghost_at(target_num: int, red_variant: bool,
                cell: Vector2i) -> Vector2i:
        var col: int = cell.x
        var row: int = cell.y
        if ghost_reapers.size() > 0:
                # Secondo fantasma: cella adiacente libera (non sopra il primo).
                var g2_cell: Vector2i = _find_free_cell_near(col, row, 0, 2)
                if g2_cell.x >= 0:
                        col = g2_cell.x
                        row = g2_cell.y
        var ghost := GhostReaperClass.new()
        ghost.set("target_player_num", target_num)
        if red_variant:
                ghost.set("is_red_variant", true)
        ghost.setup(col, row)
        ghost.laughed.connect(_on_ghost_laughed)
        add_child(ghost)
        ghost_reapers.append(ghost)
        return Vector2i(col, row)


# FIX (2P): il bersaglio del fantasma. Ogni fantasma ha il SUO player
# (target_player_num 1 o 2, assegnato allo spawn): se il suo player è vivo
# lo insegue, altrimenti ripiega sull'altro così la minaccia non svanisce.
func _ghost_target_player(ghost: Node2D) -> CharacterBody2D:
        var g_num: int = 1
        if ghost.get("target_player_num") != null:
                g_num = int(ghost.get("target_player_num"))
        if g_num == 2:
                if player2 != null and is_instance_valid(player2) and player2.visible \
                                and player2.lives > 0:
                        return player2
                return player
        if player != null and is_instance_valid(player) and player.lives > 0:
                return player
        if player2 != null and is_instance_valid(player2) and player2.visible:
                return player2
        return player


# Il player ha sparato al fantasma: risata tenebrosa (con anti-spam).
func _on_ghost_laughed(_pos: Vector2) -> void:
        if _ghost_laugh_cooldown_ms > 0:
                return
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.DARK_LAUGH)
        _ghost_laugh_cooldown_ms = GHOST_LAUGH_COOLDOWN_MS


# FIX (fantasmi immortali): rimuove TUTTI i fantasmi e la scritta (chiamato
# da start_level a ogni cambio livello: "poi scompaiono e riappariranno al
# livello del labirinto successivo sempre alla stessa maniera").
func _clear_hurry_up() -> void:
        for ghost in ghost_reapers:
                if ghost != null and is_instance_valid(ghost):
                        ghost.queue_free()
        ghost_reapers.clear()
        hurry_up_active = false
        _since_last_treasure_ms = 0.0
        _ghost_laugh_cooldown_ms = 0
        _hurry_up_time = 0.0


# FIX (nuova meccanica): spawn cavaliere alleato evocato dalla statua.
# Il cavaliere appare accanto al player con animazione di "materializzazione".
const KnightAllyClass = preload("res://scripts/entities/KnightAlly.gd")

# FIX (sprite uno sopra l'altro): cerca la cella LIBERA più vicina a
# (from_col, from_row). "Libera" significa: pavimento EMPTY (non tesoro,
# non arma), senza collectible, senza nemici, senza mini-boss, senza portale
# o portone, e non occupata dall'altro player. La ricerca procede ad anelli
# (radius 1..max_radius) partendo dalla direzione suggerita `prefer_dir`
# (0=destra,1=giù,2=sinistra,3=alto) così l'alleato tende a spuntare davanti
# al player, mantenendo però una distanza minima di 1 cella da ogni entità.
func _find_free_cell_near(from_col: int, from_row: int, prefer_dir: int,
                max_radius: int = 3) -> Vector2i:
        # Celle occupate da collectible (pos -> cell).
        var occupied: Dictionary = {}
        for item in collectibles_node.get_children():
                if item is Node2D and is_instance_valid(item):
                        var ip: Vector2 = item.position
                        occupied[Vector2i(int(ip.x / C.TILE_SIZE),
                                int((ip.y - C.UI_HEIGHT) / C.TILE_SIZE))] = true
        # Nemici vivi.
        if spawner != null:
                for e in spawner.enemies:
                        if e is Node2D and is_instance_valid(e) and not e.is_dead():
                                var ep: Vector2 = e.position
                                occupied[Vector2i(int(ep.x / C.TILE_SIZE),
                                        int((ep.y - C.UI_HEIGHT) / C.TILE_SIZE))] = true
        # Mini-boss.
        if mini_boss != null and is_instance_valid(mini_boss) and not mini_boss.is_dead():
                var mp: Vector2 = mini_boss.get_pixel_pos()
                occupied[Vector2i(int(mp.x / C.TILE_SIZE),
                        int((mp.y - C.UI_HEIGHT) / C.TILE_SIZE))] = true
        # Players (l'alleato non deve spuntare sopra di loro).
        var p1_cell: Vector2i = Vector2i(int(player.position.x / C.TILE_SIZE),
                int((player.position.y - C.UI_HEIGHT) / C.TILE_SIZE))
        occupied[p1_cell] = true
        if GameManager and GameManager.num_players == 2 and player2.visible:
                occupied[Vector2i(int(player2.position.x / C.TILE_SIZE),
                        int((player2.position.y - C.UI_HEIGHT) / C.TILE_SIZE))] = true
        # Portale e portone (quando attivi).
        if spawner != null and spawner.magic_portal.active:
                var pp: Vector2 = spawner.magic_portal.pos
                occupied[Vector2i(int(pp.x / C.TILE_SIZE),
                        int((pp.y - C.UI_HEIGHT) / C.TILE_SIZE))] = true
        if exit_door != null and exit_door.get("active", false):
                var dp: Vector2 = exit_door.get("pos", Vector2.ZERO)
                occupied[Vector2i(int(dp.x / C.TILE_SIZE),
                        int((dp.y - C.UI_HEIGHT) / C.TILE_SIZE))] = true

        # Ricerca ad anelli (Chebyshev radius 1..max_radius), celle ordinate
        # per distanza Manhattan reale dal player: lo spawn è sempre la
        # cella libera più vicina possibile.
        for radius in range(1, max_radius + 1):
                # Celle dell'anello in ordine di distanza reale dal player
                # (così lo spawn è sempre il più vicino possibile).
                var ring: Array = []
                for dc in range(-radius, radius + 1):
                        for dr in range(-radius, radius + 1):
                                if absi(dc) + absi(dr) != radius \
                                                and max(absi(dc), absi(dr)) != radius:
                                        continue  # solo il bordo dell'anello
                                ring.append(Vector2i(from_col + dc, from_row + dr))
                ring.sort_custom(func(a, b):
                        return (absi(a.x - from_col) + absi(a.y - from_row)) \
                                        < (absi(b.x - from_col) + absi(b.y - from_row)))
                for cell in ring:
                        var nc: int = cell.x
                        var nr: int = cell.y
                        if nc <= 0 or nc >= C.MAZE_COLS - 1:
                                continue
                        if nr <= 0 or nr >= C.MAZE_ROWS - 1:
                                continue
                        if maze.get_cell_type(nc, nr) != C.CellType.EMPTY:
                                continue
                        if occupied.has(cell):
                                continue
                        return cell
        return Vector2i(-1, -1)


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
        # FIX (unicorno sopra un tesoro): il vecchio spawn era
        # player_pos + Vector2(48, 0), cioè 16px DENTRO la cella adiacente
        # (non al centro!) e SENZA alcun controllo sul contenuto della cella:
        # se lì c'era un tesuro/arma/collectible, l'unicorno animato spuntava
        # SOPRA l'oggetto (screenshot utente). Ora: cerca la cella libera più
        # vicina (che NON contiene tesori, armi, collectible, nemici o altri
        # player) nella direzione in cui il player è girato, e spawn ESATTO
        # al centro cella (griglia, on-grid per il movimento grid-locked).
        var pc: int = int(player_pos.x / C.TILE_SIZE)
        var pr: int = int((player_pos.y - C.UI_HEIGHT) / C.TILE_SIZE)
        var prefer_dir: int = 0
        if player != null and player.get("last_dx") != null:
                prefer_dir = 0 if player.last_dx > 0 else 2
        var spawn_cell: Vector2i = _find_free_cell_near(pc, pr, prefer_dir, 3)
        if spawn_cell.x < 0:
                # Fallback estremo: qualunque cella libera nel raggio 6.
                spawn_cell = _find_free_cell_near(pc, pr, prefer_dir, 6)
        var spawn_pos: Vector2
        if spawn_cell.x >= 0:
                spawn_pos = Vector2(
                        spawn_cell.x * C.TILE_SIZE + C.TILE_SIZE / 2.0,
                        spawn_cell.y * C.TILE_SIZE + C.TILE_SIZE / 2.0 + C.UI_HEIGHT)
        else:
                # Maze degenere: spawn al centro della cella del player.
                spawn_pos = Vector2(
                        pc * C.TILE_SIZE + C.TILE_SIZE / 2.0,
                        pr * C.TILE_SIZE + C.TILE_SIZE / 2.0 + C.UI_HEIGHT)
        ka.pos = spawn_pos
        add_child(ka)
        knight_ally = ka
        ka.update_ally(maze, player_pos, spawner.enemies, 0)
        print("[KnightAlly] Spawned at cell (", spawn_cell.x, ",", spawn_cell.y,
                ") health=", ka.health, " state=", ka.state)


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
# FIX (2P): `owner_id` (1 = P1, 2 = P2) registra CHI ha raccolto la dinamite:
# il fuoco del proprietario la lancia, la miccia scaduta colpisce il
# proprietario e il candelotto viene disegnato in mano al proprietario.
func _start_dynamite_pickup(p: CharacterBody2D, owner_id: int = 1) -> void:
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
        dynamite_player = owner_id
        dynamite_fuse_timer_ms = 7000  # 7 secondi
        dynamite_alert_played = false
        dynamite_explode_timer_ms = 0
        print("[Dynamite] Player ", owner_id, " equipped dynamite, fuse 7s")


# Update della dinamite equipaggiata (chiamato da _update_playing)
func _update_dynamite(delta_ms: int) -> void:
        # FIX (2P): il rendering del candelotto va sul PROPRIETARIO
        # (dynamite_player), non sempre su P1. L'altro player non disegna nulla.
        var dyn_owner: CharacterBody2D = player if dynamite_player == 1 else player2
        var dyn_owner_valid: bool = dyn_owner != null \
                        and is_instance_valid(dyn_owner) \
                        and (dynamite_player == 1 or _is_p2_active())
        # Aggiorna candelotto lanciato se in volo
        if dynamite_thrown != null and is_instance_valid(dynamite_thrown):
                _update_thrown_dynamite(delta_ms)
                # Sync player rendering state
                player.set_dynamite_equipped(false, 0, false)
                if GameManager and GameManager.num_players == 2 and player2.visible:
                        player2.set_dynamite_equipped(false, 0, false)
                return
        if not dynamite_equipped:
                # Assicurati che il player non disegni la dinamite
                player.set_dynamite_equipped(false, 0, false)
                if GameManager and GameManager.num_players == 2 and player2.visible:
                        player2.set_dynamite_equipped(false, 0, false)
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
                        _explode_dynamite(false)  # false = non lanciata, uccide il proprietario
        # Sync rendering state del PROPRIETARIO (per disegnare candelotto +
        # scintille/fumo); l'altro player non disegna niente.
        if dyn_owner_valid:
                var dyn_fuse: int = dynamite_fuse_timer_ms
                var dyn_alert: bool = dynamite_alert_played
                dyn_owner.set_dynamite_equipped(dynamite_equipped, dyn_fuse, dyn_alert)
                if dynamite_player == 1:
                        if GameManager and GameManager.num_players == 2 and player2.visible:
                                player2.set_dynamite_equipped(false, 0, false)
                else:
                        player.set_dynamite_equipped(false, 0, false)


# Lancia il candelotto di dinamite
func _throw_dynamite() -> void:
        if not dynamite_equipped:
                print("[Dynamite] _throw_dynamite called but dynamite_equipped=false!")
                return
        # FIX (2P): lancia dalla posizione e nella direzione del PROPRIETARIO
        # della dinamite (prima era sempre P1: se P2 l'aveva raccolta, il
        # candelotto spuntava dal player sbagliato).
        var thrower: CharacterBody2D = player if dynamite_player == 1 else player2
        if thrower == null or not is_instance_valid(thrower):
                thrower = player
        print("[Dynamite] Throwing! player ", dynamite_player, " pos=", thrower.get_pixel_pos())
        var dir: Vector2 = Vector2(thrower.last_dx, thrower.last_dy)
        if dir == Vector2.ZERO:
                dir = Vector2(1, 0)
        dir = dir.normalized()
        # FIX (dinamite esplode subito): offset aumentato da 24 a 40px per
        # evitare che il candelotto spawni dentro un muro o troppo vicino
        # al player. Aggiunto grace_period_ms per non checkare collisioni
        # nei primi 200ms (lascia che il candelotto si allontani).
        var spawn_pos: Vector2 = thrower.get_pixel_pos() + dir * 40.0
        # FIX (dinamite spawn dentro muro): se spawn_pos è in una cella WALL,
        # retrocedi verso il player finché non trova una cella vuota.
        var sp_col: int = int(spawn_pos.x / C.TILE_SIZE)
        var sp_row: int = int((spawn_pos.y - C.UI_HEIGHT) / C.TILE_SIZE)
        if sp_col >= 0 and sp_col < C.MAZE_COLS and sp_row >= 0 and sp_row < C.MAZE_ROWS:
                if maze.is_wall(sp_col, sp_row):
                        for i in range(32, 7, -8):
                                var tp: Vector2 = thrower.get_pixel_pos() + dir * float(i)
                                var tc: int = int(tp.x / C.TILE_SIZE)
                                var tr: int = int((tp.y - C.UI_HEIGHT) / C.TILE_SIZE)
                                if tc >= 0 and tc < C.MAZE_COLS and tr >= 0 and tr < C.MAZE_ROWS:
                                        if not maze.is_wall(tc, tr):
                                                spawn_pos = tp
                                                break
        # Crea nodo candelotto lanciato
        var proj := Node2D.new()
        proj.position = spawn_pos
        # FIX (root cause + comportamento dinamite corretto):
        #  - speed 18 px/frame ≈ 1080 px/s
        #  - life_ms 10000 = 10 secondi (richiesta utente)
        #  - grace_ms 200ms: il candelotto non esplode al contatto col player
        #    per i primi 200ms (lascia che si allontani)
        # Il candelotto NON rimbalza e NON fa homing: si muove dritto e
        # esplode al PRIMO contatto (muro, nemico, mini-boss, player) oppure
        # dopo 10s. Il bouncing + BFS homing appartengono alla MINE (bomb),
        # NON alla dinamite.
        proj.set_meta("dir", dir * 18.0)
        # FIX (traiettoria parabolica): aggiunge componente verticale
        # separata (vy) che accumula gravità. Inizia a -5 px/frame (kick
        # verso l'alto) per creare l'arco classico da proiettile: il
        # candelotto sale poi ricade.
        proj.set_meta("vy", -5.0)
        # Gravità 0.4 px/frame² — bilanciata per dare tempo al
        # candelotto di raggiungere nemici lontani prima di cadere a terra.
        proj.set_meta("gravity", 0.4)
        proj.set_meta("life_ms", 10000)
        proj.set_meta("grace_ms", 200)
        proj.set_meta("active", true)
        proj.visible = true
        # FIX (root cause): il candelotto era aggiunto a enemy_projectiles_node,
        # ma il loop (3b) a riga ~696 fa queue_free() su ogni figlio con meta
        # "velocity" == Vector2.ZERO. Il candelotto usa meta "dir" (non
        # "velocity"), quindi velocity default = ZERO → distrutto al primo
        # frame, PRIMA che _update_thrown_dynamite possa muoverlo.
        # Soluzione: aggiungerlo a collectibles_node, che è un contenitore
        # sicuro (in _update_collectibles i nodi senza metodo update_step
        # vengono semplicemente saltati con `continue`).
        collectibles_node.add_child(proj)
        dynamite_thrown = proj
        dynamite_equipped = false
        dynamite_fuse_timer_ms = 0
        dynamite_alert_played = false
        print("[Dynamite] Thrown! pos=", spawn_pos, " dir=", dir, " vel=", dir * 18.0)


# Update del candelotto lanciato in volo.
# Comportamento richiesto dall'utente (CHIARIMENTO: dinamite != bomba):
#   1. si muove dritto nella direzione di lancio (NESSUN rimbalzo)
#   2. NESSUN BFS homing (l'homing appartiene alla bomba/MINE, non alla dinamite)
#   3. esplode al PRIMO contatto con qualsiasi cosa: muro, nemico, mini-boss
#      o player (richiesta utente esplicita: "Qualsiasi")
#   4. se non colpisce nulla, esplode dopo 10 secondi
func _update_thrown_dynamite(delta_ms: int) -> void:
        if dynamite_thrown == null or not is_instance_valid(dynamite_thrown):
                dynamite_thrown = null
                return
        var dt: Node2D = dynamite_thrown
        var vel: Vector2 = dt.get_meta("dir", Vector2.ZERO)
        # FIX (traiettoria parabolica): leggi vy (componente verticale
        # accumulata) e gravity. vel resta costante (movimento di lancio),
        # vy evolve nel tempo per creare l'arco.
        var vy: float = dt.get_meta("vy", 0.0)
        var gravity: float = dt.get_meta("gravity", 0.4)
        var life: int = dt.get_meta("life_ms", 10000)
        life -= int(delta_ms)
        dt.set_meta("life_ms", life)
        # Timeout: 10 secondi scaduti → esplode
        if life <= 0:
                _explode_dynamite(true, dt.position)
                dt.queue_free()
                dynamite_thrown = null
                return
        # Grace period: nei primi 200ms NON checkare collisioni col player
        # (lascia che il candelotto si allontani). Le altre collisioni
        # (muro, nemico, mini-boss) restano attive subito.
        var grace: int = dt.get_meta("grace_ms", 0)
        if grace > 0:
                grace -= int(delta_ms)
                dt.set_meta("grace_ms", grace)
        # FIX (traiettoria parabolica): mantieni vel costante (componente
        # orizzontale/di lancio), aggiungi gravità alla componente
        # verticale SEPARATA (vy). total_vel compone le due: vel (costante)
        # + Vector2(0, vy) (gravità accumulata). Risultato: parabola.
        vy += gravity
        dt.set_meta("vy", vy)
        var total_vel: Vector2 = vel + Vector2(0, vy)
        var new_pos: Vector2 = dt.position + total_vel
        # Collisione con MURO: esplode al primo impatto
        var new_col: int = int(new_pos.x / C.TILE_SIZE)
        var new_row: int = int((new_pos.y - C.UI_HEIGHT) / C.TILE_SIZE)
        if new_col >= 0 and new_col < C.MAZE_COLS and new_row >= 0 and new_row < C.MAZE_ROWS:
                if maze.is_wall(new_col, new_row):
                        _explode_dynamite(true, new_pos)
                        dt.queue_free()
                        dynamite_thrown = null
                        return
        # Out of bounds: esplode
        if new_pos.x < 0 or new_pos.x > C.WINDOW_WIDTH \
                        or new_pos.y < C.UI_HEIGHT or new_pos.y > C.WINDOW_HEIGHT:
                _explode_dynamite(true, new_pos)
                dt.queue_free()
                dynamite_thrown = null
                return
        dt.position = new_pos
        # FIX (rotazione realistica): il candelotto ruota secondo l'angolo
        # della velocità totale, seguendo la traiettoria parabolica.
        # L'effetto visivo viene applicato in _draw_overlay con
        # draw_set_transform (vedi riga ~296).
        dt.rotation = total_vel.angle()
        # Collisione con NEMICO: esplode (instant kill per ogni nemico nel raggio)
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
        # Collisione con il PLAYER: esplode (richiesta utente "Qualsiasi").
        # Skip durante grace period (lascia che il candelotto si allontani
        # dal player che lo ha lanciato, altrimenti esploderebbe subito).
        if grace <= 0:
                if not player.is_invulnerable() and not player.is_jumping():
                        if dt.position.distance_squared_to(player.get_pixel_pos()) < 500.0:
                                _explode_dynamite(true, dt.position)
                                dt.queue_free()
                                dynamite_thrown = null
                                return
                if GameManager and GameManager.num_players == 2 and player2.visible:
                        if not player2.is_invulnerable() and not player2.is_jumping():
                                if dt.position.distance_squared_to(player2.get_pixel_pos()) < 500.0:
                                        _explode_dynamite(true, dt.position)
                                        dt.queue_free()
                                        dynamite_thrown = null
                                        return


# Esplosione dinamite
# thrown=true: candelotto lanciato, uccide nemici in raggio
# thrown=false: dinamite in mano al player, uccide il player PROPRIETARIO
func _explode_dynamite(thrown: bool, at_pos: Vector2 = Vector2.ZERO) -> void:
        # FIX (2P): la miccia scaduta colpisce CHI ha raccolto la dinamite
        # (prima era sempre P1, anche se l'aveva presa P2).
        var dyn_victim: CharacterBody2D = player if dynamite_player == 1 else player2
        if dyn_victim == null or not is_instance_valid(dyn_victim):
                dyn_victim = player
        var pos: Vector2 = at_pos if thrown else dyn_victim.get_pixel_pos()
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
                # Dinamite in mano: uccide il player proprietario
                dyn_victim.take_damage()
                print("[Dynamite] BOOM! Player ", dynamite_player, " hit by own dynamite")
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
                # TASK 34 (richiesta utente — "...dinamite e barili"): la
                # dinamite lanciata che esplode sullo sciame lo disperde
                # SUBITO (punti al proprietario della dinamite).
                if bat_cloud != null and is_instance_valid(bat_cloud):
                        if pos.distance_squared_to(bat_cloud.position) < blast_sq:
                                bat_cloud.take_explosion_hit(dyn_victim)
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
        screen_flash_timer_ms = 60
        # FIX (fulmini non colpiscono): il check usava e_pos.distance_to(pt) < 50
        # ma i fulmini vanno da UI_HEIGHT a WINDOW_HEIGHT, e i nemici potrebbero
        # non essere vicini a nessun punto del percorso. Aumentiamo il raggio
        # di danno a 80px e controlliamo anche la distanza dal SEGMENTO
        # (non solo dai punti).
        for enemy in spawner.enemies:
                if enemy.is_dead():
                        continue
                var e_pos: Vector2 = enemy.get_pixel_pos()
                # Check distanza dai punti del fulmine
                for pt in points:
                        if e_pos.distance_to(pt) < 80:  # FIX: 50→80
                                enemy.take_damage(999)
                                if enemy.has_method("start_electrified"):
                                        enemy.start_electrified(30)
                                player.add_score(3000)
                                break
        # Damage mini-boss if present (35% max HP)
        if mini_boss != null and is_instance_valid(mini_boss):
                if mini_boss.has_method("is_dead") and not mini_boss.is_dead():
                        var mb_pos: Vector2 = mini_boss.get_pixel_pos()
                        for pt in points:
                                if mb_pos.distance_to(pt) < 80:  # FIX: 50→80
                                        var mb_max_hp: int = 100
                                        if mini_boss.has_method("get_max_health"):
                                                mb_max_hp = mini_boss.get_max_health()
                                        mini_boss.take_damage(int(mb_max_hp * 0.35))
                                        break
        # TASK 34 (pipistrelli): lo scettro e' un'arma bonus — il fulmine che
        # passa vicino allo sciame lo disperde SUBITO (80px dal percorso,
        # come i nemici).
        if bat_cloud != null and is_instance_valid(bat_cloud):
                for pt in points:
                        if bat_cloud.position.distance_to(pt) < 80.0:
                                bat_cloud.take_explosion_hit(player)
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
        # FIX (HUD 2P invisibile): hud.set_num_players() non veniva MAI
        # chiamato da nessuno in tutto il codebase → _num_players restava 1
        # → _draw() usava sempre il layout 1P e la sezione P2 (energia,
        # stamina, vite, arma, punteggio) non veniva mai DISEGNATA, pur
        # ricevendo regolarmente i dati via set_player2_state(). Sincronizzato
        # qui ogni frame: il layout si auto-corregge in ogni flusso (nuova
        # partita, continue, restore sessione, ritorno dalla boss room).
        if GameManager != null:
                hud.set_num_players(GameManager.num_players)
        # NOTE (HUD weapon name): il Dictionary dell'arma non ha la chiave
        # "name" (ha type/power/ammo) → il nome è derivato dal type con la
        # mappa ufficiale (C.get_weapon_name), mai hardcoded "PISTOL".
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
                # RELIC (Task 21): stato armatura reliquia in HUD.
                "armor_name": C.get_armor_short_name(player.armor_relic),
                "armor_color": player.armor_relic.get("color", Color.WHITE),
                "armor_charges": player.armor_charges(),
                "armor_max": int(player.armor_relic.get("max_charges", 0)),
        }
        hud.set_player_state(p1_snap)
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
                        # RELIC (Task 21): stato armatura reliquia in HUD (P2).
                        "armor_name": C.get_armor_short_name(player2.armor_relic),
                        "armor_color": player2.armor_relic.get("color", Color.WHITE),
                        "armor_charges": player2.armor_charges(),
                        "armor_max": int(player2.armor_relic.get("max_charges", 0)),
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


# ============================================================================
# TASK 54: cache statica dello sheet portale PixelLab (env/portal_sheet.png,
# 4 frame vortice). Null se il PNG non esiste -> fallback cerchi procedurali.
# ============================================================================
static var _portal_sheet_cache: Texture2D = null
static var _portal_sheet_tried: bool = false

static func _get_portal_sheet() -> Texture2D:
        if _portal_sheet_tried:
                return _portal_sheet_cache
        _portal_sheet_tried = true
        var path := "res://assets/sprites/env/portal_sheet.png"
        var abs_path: String = ProjectSettings.globalize_path(path)
        if FileAccess.file_exists(abs_path):
                var img := Image.new()
                if img.load(abs_path) == OK:
                        _portal_sheet_cache = ImageTexture.create_from_image(img)
        return _portal_sheet_cache
