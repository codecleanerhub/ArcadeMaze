## Boss.gd - End-of-level boss (17 unique types).
## ============================================================
## Godot port of `src/Boss.{h,cpp}`.
##
## 17 boss types, each with its own sprite and shooting pattern. The boss
## spawns on every 4th level (level 4, 8, 12, ...). Type is selected via
## getBossIndex(level) which cycles through 0..16.
##
## Stats:
##   * size:   120..180 px (grows with level, capped at 180)
##   * speed:  1..2 px/frame (always ≤ player speed)
##   * health: 50 + level*20  (level 1=70, level 10=250, level 17=390)
##
## Behaviour:
##   * Diagonal movement, bouncing off the room walls
##   * Type-specific shooting patterns: 1 to 5 projectiles per shot
##   * Some patterns include homing projectiles (WRAITH_LORD, VAMPIRE,
##     SUPREME_WITCH) that pursue the player for a few seconds
##   * attackingTimer triggers a "pulse" animation on the DeformableSprite
##
## Rendering:
##   * Sprite: DeformableSprite (mesh-deformed single frame from
##     `assets/sprites/boss_XXX_sheet.png`, sub-rect 64x64, grid 8x8)
##   * HP bar: positioned above the head, color-coded by HP ratio
##   * If sprite PNG is missing: falls back to render_primitives() which
##     draws the boss with Polygon2D/CircleShape primitives
extends Node2D
class_name Boss

const C = preload("res://scripts/core/GameConstants.gd")

# ---- Boss types (mirrors C++ enum BossType) ----
enum Type {
        BOSS_GOLEM, BOSS_LICH, BOSS_DEMON, BOSS_SPIDER,
        BOSS_ABOMINATION, BOSS_KRAKEN, BOSS_DRAGON,
        BOSS_WRAITH_LORD, BOSS_VAMPIRE, BOSS_BEHOLDER,
        BOSS_GHOUL_LORD, BOSS_SPECTRAL_ALPHA, BOSS_CULT_HERALD,
        BOSS_COLOSSAL_MIMIC, BOSS_RAT_KING, BOSS_SUPREME_WITCH,
        BOSS_TWILIGHT_KNIGHT
}

const BOSS_TYPE_COUNT := 17
const MAZE_LEVELS_PER_BOSS := 3
const TOTAL_LEVELS_PER_BOSS := MAZE_LEVELS_PER_BOSS + 1  # 4

# TASK 49b — sync per-boss: frame di RILASCIO dell'attacco (riga 1 dello
# sheet, 6 frame @ 11 FPS) auditato su TUTTI i 17 boss (VLM + analisi pixel
# degli effetti: veleno/fiamma/raggio per frame). Default = frame 3
# (C.BOSS_ATTACK_WINDUP_MS = 280ms, 15/17 boss). Override per i boss che
# rilasciano su un altro frame (ms = frame * 90.9 + 8, stesso scarto del
# default 3 -> 280):
#   - DRAGO ANTICO (boss_035): la fiamma eruppe dalle fauci a F4
#     (getto 1892px in F4 vs 8px nei frame 0-3) -> 372ms = F4;
#   - BEHOLDER (boss_037): il raggio centrale spara a F2 (estensione
#     massima a F2, gia' in decadimento da F3) -> 190ms = F2.
const ATTACK_WINDUP_OVERRIDES := {
        Type.BOSS_DRAGON: 372,
        Type.BOSS_BEHOLDER: 190,
}

const WINDOW_WIDTH := 1920
const WINDOW_HEIGHT := 1080
const UI_HEIGHT := 80

@export var boss_level: int = 4   # 1-based level (4 = first boss level)
@export var boss_type: int = Type.BOSS_GOLEM

# Position (pixel coords, +Y down).
var pos: Vector2 = Vector2.ZERO:
        set(v):
                pos = v
                position = v

# Direction (sign only; magnitude is implicit in speed).
var dx: int = 2
var dy: int = 1

var size: float = 130.0
var speed: int = 1
var health: int = 70
var max_health: int = 70

# Timers (in ms, decremented each frame).
var shoot_timer_ms: int = 0
var attacking_timer_ms: int = 0
var anim_time: float = 0.0

# TASK 49 — sparo differito: >0 = attacco in "wind-up", il colpo parte
# quando il contatore raggiunge 0 (frame di rilascio dell'animazione).
var pending_shot_ms: int = 0

# DeformableSprite node (lazy-init on first render).
var deform_sprite: DeformableSprite = null
var deform_loaded: bool = false

# Sprite ID (e.g. "boss_031" for the GOLEM).
var sprite_id: String = ""

# TASK 22 — frame size della sorgente (64 SD legacy / 256 XHD).
var _frame_px: int = 64

# TASK 46 — animazione a FRAME REALI dello sheet: colonne (frame per riga)
# e righe (0 = camminata/idle, 1 = attacco quando presente) rilevate dalla
# dimensione della texture caricata. 1 colonna = sheet statico (boss senza
# ciclo): il cycling resta semplicemente inattivo.
var _frame_cols: int = 1
var _frame_rows: int = 1

# TASK 22 — mappa tipo boss -> profilo animazione arti (DeformableSprite).
# LP_* vedi DeformableSprite.LimbProfile. LP_NONE = solo respirazione/idle
# classico (comportamento pre-Task 22).
static func get_limb_profile(t: int) -> int:
        match t:
                Type.BOSS_GOLEM:           return DeformableSprite.LimbProfile.LP_ARMS
                Type.BOSS_LICH:            return DeformableSprite.LimbProfile.LP_HOVER
                Type.BOSS_DEMON:           return DeformableSprite.LimbProfile.LP_WINGS
                Type.BOSS_SPIDER:          return DeformableSprite.LimbProfile.LP_ARMS
                Type.BOSS_ABOMINATION:     return DeformableSprite.LimbProfile.LP_TENTACLES
                Type.BOSS_KRAKEN:          return DeformableSprite.LimbProfile.LP_TENTACLES
                Type.BOSS_DRAGON:          return DeformableSprite.LimbProfile.LP_WINGS
                Type.BOSS_WRAITH_LORD:     return DeformableSprite.LimbProfile.LP_HOVER
                Type.BOSS_VAMPIRE:         return DeformableSprite.LimbProfile.LP_HOVER
                Type.BOSS_BEHOLDER:        return DeformableSprite.LimbProfile.LP_STALKS
                Type.BOSS_GHOUL_LORD:      return DeformableSprite.LimbProfile.LP_ARMS
                Type.BOSS_SPECTRAL_ALPHA:  return DeformableSprite.LimbProfile.LP_HOVER
                Type.BOSS_CULT_HERALD:     return DeformableSprite.LimbProfile.LP_HOVER
                Type.BOSS_COLOSSAL_MIMIC:  return DeformableSprite.LimbProfile.LP_NONE
                Type.BOSS_RAT_KING:        return DeformableSprite.LimbProfile.LP_ARMS
                Type.BOSS_SUPREME_WITCH:   return DeformableSprite.LimbProfile.LP_HOVER
                Type.BOSS_TWILIGHT_KNIGHT: return DeformableSprite.LimbProfile.LP_ARMS
        return DeformableSprite.LimbProfile.LP_NONE

# Signals emitted to the Game.
signal shoot(projectile: Projectile)
signal died(boss: Boss)

# TASK 51 — FASE 2 DEL BOSS (richiesta utente): al 50% di energia il boss
# entra in fase 2 e POTENZIA lo scontro.
signal phase2_entered(boss: Boss)          # annuncio visivo/sonoro (flash+rombo)
signal spawn_pit(world_pos: Vector2, tint: Color)  # buca telegrafata a terra
signal slam_landed(world_pos: Vector2, radius: float)  # onda d'urto del salto

# --- TASK 51: attacco speciale di fase 2 per tipo ---
enum Phase2Special { NONE, HOMING_VOLLEY, SKY_STRIKE, PIT_SPAWNER, JUMP_SLAM }

# Assegnazione per tipo (scelte tematiche sull'aspetto del boss):
#  * JUMP_SLAM — bruti fisici: si scagliano sul player e lo schiacciano
#    (il player vede l'ombra crescere e deve spostarsi in tempo).
#  * SKY_STRIKE — incantatori/alati: magia o fulmini che PIOMBANO DALL'ALTO
#    sulla posizione del player (colonne verticali da scansare).
#  * PIT_SPAWNER — tessitori/rifugiati: APRONO BUCHE A CASO sul pavimento
#    (crepa telegrafica poi voragine che danneggia chi vi resta sopra).
#  * HOMING_VOLLEY — predatori eterei: raffica di proiettili POTENZIATI a
#    INSEGUIMENTO (variante 5: aura pulsante + corona rotante + scia).
static func get_phase2_special(t: int) -> int:
        match t:
                Type.BOSS_GOLEM:           return Phase2Special.JUMP_SLAM
                Type.BOSS_LICH:            return Phase2Special.SKY_STRIKE
                Type.BOSS_DEMON:           return Phase2Special.SKY_STRIKE
                Type.BOSS_SPIDER:          return Phase2Special.PIT_SPAWNER
                Type.BOSS_ABOMINATION:     return Phase2Special.JUMP_SLAM
                Type.BOSS_KRAKEN:          return Phase2Special.PIT_SPAWNER
                Type.BOSS_DRAGON:          return Phase2Special.SKY_STRIKE
                Type.BOSS_WRAITH_LORD:     return Phase2Special.SKY_STRIKE
                Type.BOSS_VAMPIRE:         return Phase2Special.HOMING_VOLLEY
                Type.BOSS_BEHOLDER:        return Phase2Special.SKY_STRIKE
                Type.BOSS_GHOUL_LORD:      return Phase2Special.JUMP_SLAM
                Type.BOSS_SPECTRAL_ALPHA:  return Phase2Special.HOMING_VOLLEY
                Type.BOSS_CULT_HERALD:     return Phase2Special.SKY_STRIKE
                Type.BOSS_COLOSSAL_MIMIC:  return Phase2Special.PIT_SPAWNER
                Type.BOSS_RAT_KING:        return Phase2Special.PIT_SPAWNER
                Type.BOSS_SUPREME_WITCH:   return Phase2Special.SKY_STRIKE
                Type.BOSS_TWILIGHT_KNIGHT: return Phase2Special.JUMP_SLAM
        return Phase2Special.NONE

# Colore dell'aura di fase 2 (famiglia visiva del boss).
static func get_phase2_aura_color(t: int) -> Color:
        match t:
                Type.BOSS_GOLEM:           return Color(1.00, 0.45, 0.15)
                Type.BOSS_LICH:            return Color(0.20, 1.00, 0.30)
                Type.BOSS_DEMON:           return Color(1.00, 0.25, 0.10)
                Type.BOSS_SPIDER:          return Color(0.65, 0.30, 0.95)
                Type.BOSS_ABOMINATION:     return Color(0.90, 0.25, 0.55)
                Type.BOSS_KRAKEN:          return Color(0.15, 0.55, 0.75)
                Type.BOSS_DRAGON:          return Color(1.00, 0.55, 0.10)
                Type.BOSS_WRAITH_LORD:     return Color(0.35, 0.95, 1.00)
                Type.BOSS_VAMPIRE:         return Color(0.95, 0.10, 0.20)
                Type.BOSS_BEHOLDER:        return Color(1.00, 0.85, 0.25)
                Type.BOSS_GHOUL_LORD:      return Color(0.85, 0.75, 0.30)
                Type.BOSS_SPECTRAL_ALPHA:  return Color(0.55, 1.00, 0.80)
                Type.BOSS_CULT_HERALD:     return Color(0.70, 0.25, 0.95)
                Type.BOSS_COLOSSAL_MIMIC:  return Color(0.85, 0.75, 0.15)
                Type.BOSS_RAT_KING:        return Color(0.55, 0.55, 0.25)
                Type.BOSS_SUPREME_WITCH:   return Color(0.95, 0.30, 0.95)
                Type.BOSS_TWILIGHT_KNIGHT: return Color(0.35, 0.35, 0.95)
        return Color(1.0, 0.3, 0.3)

# Fase corrente (1 = normale, 2 = potenziata al 50% di energia).
var phase: int = 1
# Timer (ms) dell'attacco speciale di fase 2.
var special_timer_ms: int = 0
# Stato del salto schiacciante (Phase2Special.JUMP_SLAM).
var _slam_state: int = 0   # 0=none 1=telegraph 2=leap 3=recover
var _slam_timer_ms: float = 0.0
var _slam_from: Vector2 = Vector2.ZERO
var _slam_to: Vector2 = Vector2.ZERO


# ============================================================
# Static helpers (mirror C++ inline functions in Boss.h)
# ============================================================

static func is_boss_level(level: int) -> bool:
        return (level % TOTAL_LEVELS_PER_BOSS) == 0


static func get_boss_index(level: int) -> int:
        return (level / TOTAL_LEVELS_PER_BOSS) % BOSS_TYPE_COUNT


# Map boss type to its spritesheet ID (assets/sprites/<id>_sheet.png).
# Matches the C++ Boss::getSpriteId() switch exactly.
static func get_sprite_id(t: int) -> String:
        match t:
                Type.BOSS_GOLEM:           return "boss_031"
                Type.BOSS_LICH:            return "boss_032"
                Type.BOSS_DEMON:           return "boss_033"
                Type.BOSS_ABOMINATION:     return "boss_034"
                Type.BOSS_DRAGON:          return "boss_035"
                Type.BOSS_WRAITH_LORD:     return "boss_036"
                Type.BOSS_BEHOLDER:        return "boss_037"
                Type.BOSS_SPIDER:          return "boss_022"
                Type.BOSS_KRAKEN:          return "boss_030"
                Type.BOSS_VAMPIRE:         return "boss_029"
                Type.BOSS_GHOUL_LORD:      return "boss_021"
                Type.BOSS_SPECTRAL_ALPHA:  return "boss_023"
                Type.BOSS_CULT_HERALD:     return "boss_024"
                Type.BOSS_COLOSSAL_MIMIC:  return "boss_025"
                Type.BOSS_RAT_KING:        return "boss_026"
                Type.BOSS_SUPREME_WITCH:   return "boss_027"
                Type.BOSS_TWILIGHT_KNIGHT: return "boss_028"
        return ""


# Descriptive boss name for the room banner.
# TASK 44: localizzato (EN default / IT) tramite il mirror statico
# C.ui_language — le funzioni static NON risolvono gli autoload.
static func get_boss_name(t: int) -> String:
        var it: bool = C.ui_is_italian()
        match t:
                Type.BOSS_GOLEM: return "Golem di Pietra" if it else "Stone Golem"
                Type.BOSS_LICH: return "Lich Necromante" if it else "Lich Necromancer"
                Type.BOSS_DEMON: return "Demone Abissale" if it else "Abyssal Demon"
                Type.BOSS_SPIDER: return "Ragno Gigante" if it else "Giant Spider"
                Type.BOSS_ABOMINATION: return "Abominio" if it else "Abomination"
                Type.BOSS_KRAKEN: return "Kraken" if it else "Kraken"
                Type.BOSS_DRAGON: return "Drago Antico" if it else "Ancient Dragon"
                Type.BOSS_WRAITH_LORD: return "Signore degli Spettri" if it else "Wraith Lord"
                Type.BOSS_VAMPIRE: return "Signore dei Vampiri" if it else "Vampire Lord"
                Type.BOSS_BEHOLDER: return "Beholder" if it else "Beholder"
                Type.BOSS_GHOUL_LORD: return "Signore dei Ghoul" if it else "Ghoul Lord"
                Type.BOSS_SPECTRAL_ALPHA:
                        return "Lupo Alfa Spettrale" if it else "Spectral Alpha Wolf"
                Type.BOSS_CULT_HERALD: return "Araldo del Culto" if it else "Cult Herald"
                Type.BOSS_COLOSSAL_MIMIC: return "Mimico Colossale" if it else "Colossal Mimic"
                Type.BOSS_RAT_KING: return "Re dei Ratti" if it else "Rat King"
                Type.BOSS_SUPREME_WITCH: return "Strega Suprema" if it else "Supreme Witch"
                Type.BOSS_TWILIGHT_KNIGHT:
                        return "Cavaliere del Crepuscolo" if it else "Twilight Knight"
        return "Unknown"


# ============================================================
# Setup
# ============================================================
func setup(level: int, screen_w: int, screen_h: int) -> void:
        boss_level = level
        boss_type = get_boss_index(level)

        # Size scaling (FIX: aumentato del 60% per schermo 1920x1080).
        # Era: 120 + level*4 (124..160), cap 180.
        # Ora: 192 + level*6 (198..256), cap 288.
        if level <= 10:
                size = float(192 + level * 6)        # 198..252
        else:
                size = float(252 + min(36, (level - 10) * 3))  # cap 288

        # Initial position: centered horizontally, below the UI bar.
        pos = Vector2(screen_w / 2.0, UI_HEIGHT + 120.0 + size)

        # Diagonal direction (alternates by level parity).
        dx = 2 if (level % 2 == 0) else -2
        dy = 1 if (level % 3 == 0) else -1

        # Speed cap (≤ player base speed of 2).
        speed = 1 + level / 8
        if speed > 2:
                speed = 2

        # Health (50 + level*20).
        # TASK 105 (NEW GAME PLUS): resistenza del boss scala col tier
        # (x1.33 NG+ / x1.50 NG++); le armi del player in boss room fanno
        # danno FLAT, quindi più HP = davvero più colpi per abbatterlo
        # (cannone d'assedio e mina sono % degli HP max e restano invariati
        # in termini relativi).
        health = int(round(float(50 + level * 20)
                        * C.newgameplus_resist_multiplier()))
        max_health = health

        sprite_id = get_sprite_id(boss_type)

        # Pre-create the DeformableSprite child (lazy loads texture on first render).
        _ensure_deform_sprite()

        # Apply CharacterArt enhancement shader (strong variant for bosses).
        # Boss renders via DeformableSprite (MeshInstance2D, spatial shader)
        # but also has a primitive fallback _draw_primitives() path on self.
        # We apply the canvas_item shader to the Boss node itself so the
        # primitive rendering gets enhanced (rim light, sharpening, depth).
        if CharacterArt:
                CharacterArt.apply_enhancement_to_canvas_item(self, true)


func _ensure_deform_sprite() -> void:
        if deform_sprite != null:
                return
        var ds := DeformableSprite.new()
        add_child(ds)
        deform_sprite = ds


# ============================================================
# Damage / state queries
# ============================================================
func take_damage(dmg: int) -> void:
        health -= dmg


func is_dead() -> bool:
        return health <= 0


# ============================================================
# Update
# ============================================================

# `player_x`/`player_y` are the player's pixel coordinates (for aiming).
# `delta_ms` is the simulated elapsed time (16ms @ 60fps).
# `projectiles_out` is an Array the boss appends new Projectile instances to.
func update_step(player_x: float, player_y: float, delta_ms: int,
                projectiles_out: Array) -> void:
        anim_time += float(delta_ms) * 0.001

        # TASK 51 — FASE 2 (richiesta utente): al 50% di energia il boss
        # POTENZIA lo scontro. Il check vive qui (non solo in take_damage)
        # cosi' copre anche il restore da continue e i setup di test.
        if C.BOSS_PHASE2_ENABLED and phase == 1 and health > 0 \
                        and float(health) <= float(max_health) * C.BOSS_PHASE2_TRIGGER_RATIO:
                _enter_phase2()

        # TASK 51 — salto schiacciante: telegrafo (ombra) -> arco di volo ->
        # atterraggio (onda d'urto via segnale) -> recupero. Mentre la
        # macchina a stati e' attiva il boss NON spara e NON rimbalza.
        if _update_slam(delta_ms):
                position = pos
                if phase == 2 or _slam_state != 0:
                        queue_redraw()
                return

        # Decrement attackingTimer (FIX: usa delta_ms reale, non fisso 16).
        if attacking_timer_ms > delta_ms:
                attacking_timer_ms -= delta_ms
        else:
                attacking_timer_ms = 0

        # TASK 49 — SYNC posa/proiettile/suono: lo sparo parte quando la posa
        # d'attacco raggiunge il frame di RILASCIO dell'animazione (per-boss:
        # vedi ATTACK_WINDUP_OVERRIDES; default frame 3 @ 11 FPS ~ 280ms
        # dall'inizio del timer), non al frame 0. La mira resta fresca (usa
        # la posizione del player al momento del lancio).
        if pending_shot_ms > 0:
                if pending_shot_ms > delta_ms:
                        pending_shot_ms -= delta_ms
                else:
                        pending_shot_ms = 0
                        _shoot_pattern(player_x, player_y, projectiles_out)

        # Diagonal movement.
        pos.x += float(dx) * float(speed)
        pos.y += float(dy) * float(speed)

        # Bounce on room walls.
        if pos.x < size * 0.5 or pos.x > float(WINDOW_WIDTH) - size * 0.5:
                dx = -dx
        if pos.y < UI_HEIGHT + size * 0.5 or pos.y > float(WINDOW_HEIGHT) - size * 0.5:
                dy = -dy

        # Shoot timer.
        shoot_timer_ms += delta_ms
        var base_cd := 2500 - boss_level * 100
        if base_cd < 1000:
                base_cd = 1000
        # TASK 51: in fase 2 il fuoco base e' piu' fitto (-18% cooldown).
        if phase == 2:
                base_cd = int(float(base_cd) * 0.82)
        if shoot_timer_ms > base_cd:
                shoot_timer_ms = 0
                attacking_timer_ms = 500
                if C.BOSS_ATTACK_SYNC_ENABLED:
                        # TASK 49: prima il wind-up (posa), poi il colpo.
                        # TASK 49b: wind-up per-boss (frame di rilascio auditato).
                        pending_shot_ms = _attack_windup_ms()
                else:
                        _shoot_pattern(player_x, player_y, projectiles_out)

        # TASK 51 — attacco SPECIALE di fase 2 (per tipo: pioggia dall'alto,
        # buche sul pavimento, salto schiacciante, raffica a inseguimento).
        if phase == 2:
                special_timer_ms += delta_ms
                if special_timer_ms >= C.BOSS_PHASE2_SPECIAL_CD_MS:
                        special_timer_ms = 0
                        _run_phase2_special(player_x, player_y, projectiles_out)
                # l'aura e l'ombra del salto vivono nel _draw del nodo:
                # ridisegna mentre e' attiva una delle due.
                queue_redraw()

        # Update the deformable sprite.
        if deform_loaded and deform_sprite != null:
                var mode := DeformableSprite.AnimMode.IDLE
                var prof: int = get_limb_profile(boss_type)
                if attacking_timer_ms > 0:
                        mode = DeformableSprite.AnimMode.ATTACK
                elif (dx != 0 or dy != 0) and (
                                prof == DeformableSprite.LimbProfile.LP_ARMS
                                or prof == DeformableSprite.LimbProfile.LP_TENTACLES
                                or prof == DeformableSprite.LimbProfile.LP_WINGS):
                        # TASK 25: il boss TERRESTRE che rimbalza per la stanza
                        # CAMMINA (bob + dondolio zampe) invece di restare in
                        # IDLE: prima l'unico movimento visibile era la lieve
                        # respirazione. I fluttuanti (Lich/Wraith/Vampiro/
                        # Beholder/Mimic) restano in IDLE: la loro animazione
                        # e' il profilo arti (LP_HOVER/LP_STALKS).
                        mode = DeformableSprite.AnimMode.WALK
                # TASK 22: profilo arti procedurale (tentacoli/braccia/ali/volo)
                # attivo solo col flag di rollback attivo.
                # TASK 25: limb_gain amplifica le ampiezze (subtle -> visibili).
                if C.BOSS_LIMB_ANIM_ENABLED:
                        deform_sprite.limb_profile = prof
                        deform_sprite.limb_gain = C.BOSS_LIMB_ANIM_GAIN
                else:
                        deform_sprite.limb_profile = DeformableSprite.LimbProfile.LP_NONE
                # TASK 22: scala relativa al frame sorgente (64 SD / 256 XHD):
                # a parità di `size` lo sprite a schermo è IDENTICO, cambia solo
                # la densità di texel (definizione).
                var scale_val := size / float(_frame_px)
                var half_frame := float(_frame_px) * 0.5
                var draw_x := pos.x - half_frame * scale_val
                var draw_y := (pos.y - size * 0.25) - half_frame * scale_val
                # TASK 28: i boss fluttuanti (LP_HOVER: Lich/Wraith/Vampiro/
                # SPECTRAL_ALPHA/CULT_HERALD/Supreme Witch) si animano ANCHE
                # via trasformo di NODO (bob verticale + deriva orizzontale in
                # controfase): movimento chiaramente visibile e PRIVO di
                # artefatti perche' non tocca la mesh (la veste continua a
                # ondeggiare via profilo LP_HOVER col gain calibrato + clamp).
                if C.BOSS_LIMB_ANIM_ENABLED \
                                and prof == DeformableSprite.LimbProfile.LP_HOVER:
                        draw_x += sin(anim_time * 0.8) * 4.0
                        draw_y += sin(anim_time * 1.6) * 7.0
                deform_sprite.position = Vector2(draw_x, draw_y) - pos  # local offset
                # TASK 46 — cycling dei frame reali dello sheet. I rate
                # replicano i frameDuration legacy dei meta (idle 180ms,
                # walk 120ms, attack 90ms -> 5.5 / 8.3 / 11 FPS): il nuovo
                # Golem PixelLab (6 frame) e i cicli legacy 4-frame degli
                # altri boss si animano con la stessa tempizzazione originale.
                if C.BOSS_FRAME_ANIM_ENABLED and _frame_cols > 1:
                        var frow := 0
                        var fidx := 0
                        if mode == DeformableSprite.AnimMode.ATTACK:
                                if _frame_rows > 1:
                                        frow = 1  # riga attacco dedicata
                                # riproduzione one-shot nel timer d'attacco
                                # (500 ms): 11 FPS -> ~5 frame e mezzo.
                                var elapsed_ms := 500 - attacking_timer_ms
                                fidx = int(float(elapsed_ms) * 0.011)
                                if fidx >= _frame_cols:
                                        fidx = _frame_cols - 1
                        elif mode == DeformableSprite.AnimMode.WALK:
                                # TASK 48 — riga walk dedicata (riga 2) per gli
                                # sheet PixelLab v2 a 3 righe (idle/attack/walk);
                                # sheet a 1-2 righe: walk sulla riga idle (0),
                                # comportamento legacy invariato.
                                if _frame_rows > 2:
                                        frow = 2
                                fidx = int(anim_time * 8.3) % _frame_cols
                        else:  # IDLE
                                fidx = int(anim_time * 5.5) % _frame_cols
                        deform_sprite.set_sheet_frame(fidx, frow)
                deform_sprite.update(anim_time, mode, scale_val, false)

        position = pos


# ============================================================
# TASK 51 — FASE 2 DEL BOSS (richiesta utente)
# ============================================================

# _enter_phase2(): potenziamento al 50% di energia. Oltre al nuovo attacco
# speciale per tipo, il boss cambia ASPETTO per segnalare l'aumento di
# potenza: dimensione +12%, aura pulsante del colore della famiglia (vedi
# _draw) e tinta dello sprite spostata verso lo stesso colore.
func _enter_phase2() -> void:
        phase = 2
        size *= C.BOSS_PHASE2_SIZE_BONUS
        # primo speciale quasi subito: il player capisce subito che il boss
        # e' cambiato (annuncio + nuova minaccia nella stessa finestra).
        special_timer_ms = maxi(0, C.BOSS_PHASE2_SPECIAL_CD_MS - 1300)
        # i boss che NON usano il salto si muovono un po' piu' veloci
        # (pressione di marcia); i saltatori hanno gia' il balzo.
        if get_phase2_special(boss_type) != Phase2Special.JUMP_SLAM and speed < 3:
                speed += 1
        # tinta dello sprite: scivola verso il colore d'aura (leggera).
        if deform_sprite != null:
                var ac := get_phase2_aura_color(boss_type)
                deform_sprite.modulate = Color(
                                1.0 + (ac.r - 0.5) * 0.20,
                                1.0 + (ac.g - 0.5) * 0.20,
                                1.0 + (ac.b - 0.5) * 0.20)
        phase2_entered.emit(self)
        queue_redraw()


# _update_slam(delta_ms): macchina a stati del salto schiacciante.
# Ritorna true mentre e' attivo (il chiamante salta movimento/spari normali).
func _update_slam(delta_ms: int) -> bool:
        if _slam_state == 0:
                return false
        _slam_timer_ms -= float(delta_ms)
        match _slam_state:
                1:  # TELEGRAPH: accovacciato, l'ombra sul bersaglio cresce.
                        if _slam_timer_ms <= 0.0:
                                _slam_state = 2
                                _slam_timer_ms = float(C.BOSS_PHASE2_SLAM_LEAP_MS)
                2:  # LEAP: arco parabolico verso il bersaglio (locked al
                    # telegrafo: il player che si sposta si salva).
                        var total := float(C.BOSS_PHASE2_SLAM_LEAP_MS)
                        var t := 1.0 - clampf(_slam_timer_ms / total, 0.0, 1.0)
                        pos = _slam_from.lerp(_slam_to, t)
                        pos.y -= sin(t * PI) * 170.0
                        if _slam_timer_ms <= 0.0:
                                pos = _slam_to
                                _slam_state = 3
                                _slam_timer_ms = float(C.BOSS_PHASE2_SLAM_RECOVER_MS)
                                # onda d'urto: il controller applica danni/VFX
                                slam_landed.emit(_slam_to, C.BOSS_PHASE2_SLAM_RADIUS)
                3:  # RECOVER: fermo sul punto d'atterraggio (finestra di
                    # contrattacco), poi torna al movimento diagonale.
                        if _slam_timer_ms <= 0.0:
                                _slam_state = 0
                                dy = 1 if pos.y < float(WINDOW_HEIGHT) * 0.5 else -1
        return true


# _run_phase2_special(player_x, player_y, out): attacco speciale per tipo.
func _run_phase2_special(player_x: float, player_y: float, out: Array) -> void:
        match get_phase2_special(boss_type):
                Phase2Special.JUMP_SLAM:
                        _slam_state = 1
                        _slam_timer_ms = float(C.BOSS_PHASE2_SLAM_TELEGRAPH_MS)
                        _slam_from = pos
                        # bersaglio LOCKED alla posizione attuale del player:
                        # l'ombra cresce e chi si sposta in tempo non subisce
                        # danno (richiesta utente).
                        _slam_to = Vector2(
                                        clampf(player_x, size * 0.5,
                                                        float(WINDOW_WIDTH) - size * 0.5),
                                        clampf(player_y, UI_HEIGHT + size * 0.5,
                                                        float(WINDOW_HEIGHT) - size * 0.5))
                        if AudioManager:
                                AudioManager.play_sound(
                                                AudioManager.SoundType.HAZARD_GRIND)
                Phase2Special.SKY_STRIKE:
                        # magia/fulmine che PIOMBA DALL'ALTO sulla posizione
                        # del player: colonne verticali potenziate (variante 5).
                        if C.BOSS_SHOOT_SFX_ENABLED and AudioManager != null:
                                AudioManager.play_boss_shoot(_primary_projectile_kind())
                        var n := 3 if boss_type == Type.BOSS_DRAGON else 2
                        for i in range(n):
                                var ox := (float(i) - float(n - 1) * 0.5) * 95.0
                                var drop := Vector2(
                                                clampf(player_x + ox, 40.0,
                                                                float(WINDOW_WIDTH) - 40.0),
                                                UI_HEIGHT + 6.0)
                                out.append(Projectile.make_boss(drop, PI / 2.0,
                                                8.5, 2, _primary_projectile_kind(), 5))
                Phase2Special.PIT_SPAWNER:
                        # BUCHE A CASO attorno al player: crepa telegrafica
                        # (900ms) poi voragine aperta 5s che danneggia chi vi
                        # resta sopra. Il controller gestisce il ciclo.
                        var tint := get_phase2_aura_color(boss_type)
                        var count := 3 if boss_type == Type.BOSS_SPIDER else 2
                        for _i in range(count):
                                var spread := Vector2(
                                                randf_range(-150.0, 150.0),
                                                randf_range(-100.0, 100.0))
                                var pp := Vector2(player_x, player_y) + spread
                                pp.x = clampf(pp.x, 60.0, float(WINDOW_WIDTH) - 60.0)
                                pp.y = clampf(pp.y, UI_HEIGHT + 60.0,
                                                float(WINDOW_HEIGHT) - 60.0)
                                spawn_pit.emit(pp, tint)
                Phase2Special.HOMING_VOLLEY:
                        # raffica di proiettili POTENZIATI a inseguimento:
                        # 3 lame/saette che curvano dietro il player.
                        if C.BOSS_SHOOT_SFX_ENABLED and AudioManager != null:
                                AudioManager.play_boss_shoot(_primary_projectile_kind())
                        var base := atan2(player_y - pos.y, player_x - pos.x)
                        for i in range(3):
                                out.append(Projectile.make_boss(pos,
                                                base + (float(i) - 1.0) * 0.5, 3.2, 2,
                                                _primary_projectile_kind(), 5, 3200))
                _:
                        pass


# ============================================================
# Shooting patterns (per type)
# ============================================================

## TASK 49b — wind-up (ms) di QUESTO boss: default 280ms (frame 3 @ 11 FPS,
## valido per 15/17 boss), override ATTACK_WINDUP_OVERRIDES per i boss il cui
## frame di rilascio auditato e' diverso (Drago=F4, Beholder=F2).
func _attack_windup_ms() -> int:
        if ATTACK_WINDUP_OVERRIDES.has(boss_type):
                return int(ATTACK_WINDUP_OVERRIDES[boss_type])
        return C.BOSS_ATTACK_WINDUP_MS


## TASK 26 — tipo di "munizione" primario del boss (BossProjKind): usato
## per lo SFX di sparo COERENTE col proiettile (masso=tonfo, ragnatela=
## fruscio, fiamma=soffio...). Mirror dei kind usati in _shoot_pattern.
func _primary_projectile_kind() -> int:
        match boss_type:
                Type.BOSS_GOLEM:           return Projectile.BossProjKind.BP_BOULDER
                Type.BOSS_LICH:            return Projectile.BossProjKind.BP_NECRO_BOLT
                Type.BOSS_DEMON:           return Projectile.BossProjKind.BP_FIREBALL
                Type.BOSS_SPIDER:          return Projectile.BossProjKind.BP_WEBSHOT
                Type.BOSS_ABOMINATION:     return Projectile.BossProjKind.BP_FLESH_CHUNK
                Type.BOSS_KRAKEN:          return Projectile.BossProjKind.BP_INK_SPRAY
                Type.BOSS_DRAGON:          return Projectile.BossProjKind.BP_DRAGON_BREATH
                Type.BOSS_WRAITH_LORD:     return Projectile.BossProjKind.BP_GHOST_BOLT
                Type.BOSS_VAMPIRE:         return Projectile.BossProjKind.BP_BLOOD_BOLT
                Type.BOSS_BEHOLDER:        return Projectile.BossProjKind.BP_EYE_RAY
                Type.BOSS_GHOUL_LORD:      return Projectile.BossProjKind.BP_GHOUL_CLAW
                Type.BOSS_SPECTRAL_ALPHA:  return Projectile.BossProjKind.BP_SPECTRAL_FANG
                Type.BOSS_CULT_HERALD:     return Projectile.BossProjKind.BP_CULT_ORB
                Type.BOSS_COLOSSAL_MIMIC:  return Projectile.BossProjKind.BP_MIMIC_GOO
                Type.BOSS_RAT_KING:        return Projectile.BossProjKind.BP_RAT_SWARM
                Type.BOSS_SUPREME_WITCH:   return Projectile.BossProjKind.BP_WITCH_HEX
                Type.BOSS_TWILIGHT_KNIGHT: return Projectile.BossProjKind.BP_TWILIGHT_BLADE
        return Projectile.BossProjKind.BP_NORMAL


func _shoot_pattern(player_x: float, player_y: float, out: Array) -> void:
        # TASK 26 (richiesta utente): SFX di sparo del boss COERENTE col tipo
        # di munizione che sta per lanciare (AudioManager sintetizza un timbro
        # per ogni BossProjKind; debounce dedicato 1000+kind).
        if C.BOSS_SHOOT_SFX_ENABLED and AudioManager != null:
                AudioManager.play_boss_shoot(_primary_projectile_kind())
        var dxp := player_x - pos.x
        var dyp := player_y - pos.y
        var dist := sqrt(dxp * dxp + dyp * dyp)
        if dist <= 0.0:
                return
        var base_angle := atan2(dyp, dxp)

        match boss_type:
                Type.BOSS_GOLEM:
                        # 1 heavy slow boulder + 2 small fast side boulders.
                        out.append(Projectile.make_boss(pos, base_angle, 2.5, 2,
                                Projectile.BossProjKind.BP_BOULDER))
                        out.append(Projectile.make_boss(pos, base_angle - 0.5, 3.5, 1,
                                Projectile.BossProjKind.BP_BOULDER))
                        out.append(Projectile.make_boss(pos, base_angle + 0.5, 3.5, 1,
                                Projectile.BossProjKind.BP_BOULDER))

                Type.BOSS_LICH:
                        # 3 green necro bolts in a tight fan.
                        for i in range(-1, 2):
                                out.append(Projectile.make_boss(pos, base_angle + float(i) * 0.25, 5.0, 1,
                                        Projectile.BossProjKind.BP_NECRO_BOLT))
                        # 1/3 chance: slow powerful necro bolt.
                        if randi() % 3 == 0:
                                out.append(Projectile.make_boss(pos, base_angle, 2.5, 2,
                                        Projectile.BossProjKind.BP_NECRO_BOLT, 1))

                Type.BOSS_DEMON:
                        # 3 fast fireballs + 50% chance of a slow big bomb.
                        for i in range(-1, 2):
                                out.append(Projectile.make_boss(pos, base_angle + float(i) * 0.35, 5.5, 1,
                                        Projectile.BossProjKind.BP_FIREBALL))
                        if randi() % 2 == 0:
                                out.append(Projectile.make_boss(pos, base_angle, 2.0, 3,
                                        Projectile.BossProjKind.BP_FIREBALL, 1))

                Type.BOSS_SPIDER:
                        # 2 slow webshots + 25% chance of 8-way web burst.
                        out.append(Projectile.make_boss(pos, base_angle - 0.2, 2.5, 1,
                                Projectile.BossProjKind.BP_WEBSHOT))
                        out.append(Projectile.make_boss(pos, base_angle + 0.2, 2.5, 1,
                                Projectile.BossProjKind.BP_WEBSHOT))
                        if randi() % 4 == 0:
                                for i in range(8):
                                        var a := float(i) * (PI / 4.0)
                                        out.append(Projectile.make_boss(pos, a, 3.0, 1,
                                                Projectile.BossProjKind.BP_WEBSHOT, 1))

                Type.BOSS_ABOMINATION:
                        # 3 flesh chunks with random spread.
                        for i in range(-1, 2):
                                var ang_var := float(randi_range(-20, 40) - 20) * PI / 180.0
                                out.append(Projectile.make_boss(pos, base_angle + float(i) * 0.4 + ang_var, 4.0, 1,
                                        Projectile.BossProjKind.BP_FLESH_CHUNK))

                Type.BOSS_KRAKEN:
                        # 2 ink sprays + 2 slow powerful tentacles.
                        out.append(Projectile.make_boss(pos, base_angle - 0.3, 3.0, 1,
                                Projectile.BossProjKind.BP_INK_SPRAY))
                        out.append(Projectile.make_boss(pos, base_angle + 0.3, 3.0, 1,
                                Projectile.BossProjKind.BP_INK_SPRAY))
                        out.append(Projectile.make_boss(pos, base_angle - 0.1, 1.8, 2,
                                Projectile.BossProjKind.BP_INK_SPRAY, 1))
                        out.append(Projectile.make_boss(pos, base_angle + 0.1, 1.8, 2,
                                Projectile.BossProjKind.BP_INK_SPRAY, 1))

                Type.BOSS_DRAGON:
                        # Wide 5-shot fire breath.
                        for i in range(-2, 3):
                                out.append(Projectile.make_boss(pos, base_angle + float(i) * 0.18, 6.0, 1,
                                        Projectile.BossProjKind.BP_DRAGON_BREATH))

                Type.BOSS_WRAITH_LORD:
                        # 2 ghost bolts + 1 short homing (1500ms).
                        out.append(Projectile.make_boss(pos, base_angle - 0.2, 4.5, 1,
                                Projectile.BossProjKind.BP_GHOST_BOLT))
                        out.append(Projectile.make_boss(pos, base_angle + 0.2, 4.5, 1,
                                Projectile.BossProjKind.BP_GHOST_BOLT))
                        out.append(Projectile.make_boss(pos, base_angle, 3.0, 2,
                                Projectile.BossProjKind.BP_GHOST_BOLT, 1, 1500))

                Type.BOSS_VAMPIRE:
                        # 3 blood bolts + 1 medium homing (2000ms).
                        for i in range(-1, 2):
                                out.append(Projectile.make_boss(pos, base_angle + float(i) * 0.25, 5.0, 1,
                                        Projectile.BossProjKind.BP_BLOOD_BOLT))
                        out.append(Projectile.make_boss(pos, base_angle, 3.0, 2,
                                Projectile.BossProjKind.BP_BLOOD_BOLT, 1, 2000))

                Type.BOSS_BEHOLDER:
                        # 4 eye rays (variants 0..3 in a row) + 33% chance of a powerful central ray.
                        for i in range(4):
                                var ang := base_angle + (float(i) - 1.5) * 0.3
                                out.append(Projectile.make_boss(pos, ang, 6.0, 1,
                                        Projectile.BossProjKind.BP_EYE_RAY, i))
                        if randi() % 3 == 0:
                                out.append(Projectile.make_boss(pos, base_angle, 4.0, 2,
                                        Projectile.BossProjKind.BP_EYE_RAY, 4))

                Type.BOSS_GHOUL_LORD:
                        # 3 bone claws.
                        for i in range(-1, 2):
                                out.append(Projectile.make_boss(pos, base_angle + float(i) * 0.3, 4.5, 1,
                                        Projectile.BossProjKind.BP_GHOUL_CLAW))

                Type.BOSS_SPECTRAL_ALPHA:
                        # 2 fast spectral fangs.
                        out.append(Projectile.make_boss(pos, base_angle - 0.15, 5.5, 1,
                                Projectile.BossProjKind.BP_SPECTRAL_FANG))
                        out.append(Projectile.make_boss(pos, base_angle + 0.15, 5.5, 1,
                                Projectile.BossProjKind.BP_SPECTRAL_FANG))

                Type.BOSS_CULT_HERALD:
                        # 1 powerful central cult orb + 2 small side orbs.
                        out.append(Projectile.make_boss(pos, base_angle, 3.5, 2,
                                Projectile.BossProjKind.BP_CULT_ORB))
                        out.append(Projectile.make_boss(pos, base_angle - 0.4, 5.0, 1,
                                Projectile.BossProjKind.BP_CULT_ORB, 1))
                        out.append(Projectile.make_boss(pos, base_angle + 0.4, 5.0, 1,
                                Projectile.BossProjKind.BP_CULT_ORB, 1))

                Type.BOSS_COLOSSAL_MIMIC:
                        # 3 sticky goo streams with random spread.
                        for i in range(-1, 2):
                                var ang_var := float(randi_range(-15, 30) - 15) * PI / 180.0
                                out.append(Projectile.make_boss(pos, base_angle + float(i) * 0.3 + ang_var, 3.5, 1,
                                        Projectile.BossProjKind.BP_MIMIC_GOO))

                Type.BOSS_RAT_KING:
                        # 3 small rats in slightly different directions.
                        for i in range(-1, 2):
                                out.append(Projectile.make_boss(pos, base_angle + float(i) * 0.5, 4.0, 1,
                                        Projectile.BossProjKind.BP_RAT_SWARM))

                Type.BOSS_SUPREME_WITCH:
                        # 2 decoy hexes + 1 long homing HEX (3000ms).
                        out.append(Projectile.make_boss(pos, base_angle - 0.3, 4.0, 1,
                                Projectile.BossProjKind.BP_WITCH_HEX, 1))
                        out.append(Projectile.make_boss(pos, base_angle + 0.3, 4.0, 1,
                                Projectile.BossProjKind.BP_WITCH_HEX, 1))
                        out.append(Projectile.make_boss(pos, base_angle, 3.0, 2,
                                Projectile.BossProjKind.BP_WITCH_HEX, 0, 3000))

                Type.BOSS_TWILIGHT_KNIGHT:
                        # 1 powerful shadow blade + 2 small fast ones.
                        out.append(Projectile.make_boss(pos, base_angle, 4.0, 2,
                                Projectile.BossProjKind.BP_TWILIGHT_BLADE))
                        out.append(Projectile.make_boss(pos, base_angle - 0.3, 6.0, 1,
                                Projectile.BossProjKind.BP_TWILIGHT_BLADE, 1))
                        out.append(Projectile.make_boss(pos, base_angle + 0.3, 6.0, 1,
                                Projectile.BossProjKind.BP_TWILIGHT_BLADE, 1))

        # TASK 51 — FASE 2: oltre allo schema nativo, OGNI boss aggiunge un
        # proiettile POTENZIATO a inseguimento (variante 5: aura pulsante +
        # corona rotante + scia) del suo tipo di munizione. Chi ha gia' il
        # fuoco a inseguimento (Wraith/Vampire/Strega) lo riceve piu' lungo.
        if phase == 2:
                var homing_ms := 2600
                match boss_type:
                        Type.BOSS_WRAITH_LORD, Type.BOSS_VAMPIRE, Type.BOSS_SUPREME_WITCH:
                                homing_ms = 3800
                out.append(Projectile.make_boss(pos, base_angle, 3.4, 2,
                                _primary_projectile_kind(), 5, homing_ms))


# ============================================================
# Rendering
# ============================================================
func _draw() -> void:
        # TASK 51 — AURA DI FASE 2: si disegna nel _draw del NODO Boss (il
        # figlio DeformableSprite disegna DOPO il parent, quindi l'aura finisce
        # DIETRO lo sprite). Doppio alone pulsante + arco rotante nel colore
        # della famiglia: cambiamento grafico che segnala l'aumento di potenza.
        if phase == 2:
                var ac := get_phase2_aura_color(boss_type)
                var t := anim_time
                var aura_r := size * (0.74 + 0.05 * sin(t * 5.0))
                draw_circle(Vector2.ZERO, aura_r, Color(ac.r, ac.g, ac.b, 0.10))
                draw_circle(Vector2.ZERO, aura_r * 0.84, Color(ac.r, ac.g, ac.b, 0.10))
                draw_arc(Vector2.ZERO, size * 0.66, t * 1.6, t * 1.6 + PI * 1.35,
                                30, Color(ac.r, ac.g, ac.b, 0.38), 5.0, true)
        # TASK 51 — OMBRA DEL SALTO SCHIACCIANTE: sul punto bersaglio (locale
        # = bersaglio - pos) cresce un'ellisse scura bordata di rosso durante
        # il telegrafo, e resta durante il volo: e' il segnale "spostati!".
        if _slam_state == 1 or _slam_state == 2:
                var local := _slam_to - pos
                var grow := 1.0
                if _slam_state == 1:
                        grow = 1.0 - clampf(_slam_timer_ms
                                        / float(C.BOSS_PHASE2_SLAM_TELEGRAPH_MS), 0.0, 1.0)
                var rr := C.BOSS_PHASE2_SLAM_RADIUS * (0.35 + 0.65 * grow)
                draw_circle(local, rr * 0.9, Color(0.0, 0.0, 0.0, 0.20 + 0.16 * grow))
                draw_arc(local, rr, 0.0, TAU, 26,
                                Color(1.0, 0.25, 0.10, 0.45 + 0.40 * sin(anim_time * 18.0)),
                                3.0, true)

        # Lazy-load the DeformableSprite's texture.
        if not deform_loaded and sprite_id != "" and deform_sprite != null:
                # TASK 22 — priorità XHD 4x (256px/frame, palette identica):
                # carica da assets/sprites/xhd/ SE il flag è attivo e il file
                # esiste. Grid 12x12 (invece di 8x8) per deformazioni arti più
                # fluide sui frame 256px. Fallback = sheet SD legacy identico
                # a prima (64px, grid 8x8, filtro NEAREST).
                var loaded := false
                if C.SPRITE_XHD_ENABLED:
                        var xhd_path := C.xhd_sheet_path(sprite_id)
                        var xhd_abs: String = ProjectSettings.globalize_path(xhd_path)
                        if FileAccess.file_exists(xhd_abs):
                                loaded = deform_sprite.load_subrect(xhd_path, 0, 0,
                                        C.SPRITE_XHD_FRAME_PX, C.SPRITE_XHD_FRAME_PX)
                                if loaded:
                                        _frame_px = C.SPRITE_XHD_FRAME_PX
                                        # TASK 28: grid 16x16 (era 12x12): celle
                                        # piu' piccole = gradienti di
                                        # deformazione piu' lisci, meno shear
                                        # visibile tra celle adiacenti.
                                        deform_sprite.set_grid_size(16, 16)
                if not loaded:
                        _frame_px = 64
                        var path := "res://assets/sprites/" + sprite_id + "_sheet.png"
                        loaded = deform_sprite.load_subrect(path, 0, 0, 64, 64)
                        if loaded:
                                deform_sprite.set_grid_size(8, 8)
                # TASK 46 — rilevamento frame reali dello sheet caricato:
                # colonne = larghezza/frame, righe = altezza/frame. Golem
                # PixelLab = 6x1 (XHD 1536x256 / SD 384x64); boss legacy =
                # 4x1; 1x1 = sprite statico (cycling inattivo).
                if loaded and deform_sprite != null and deform_sprite.texture != null:
                        var tw := float(deform_sprite.texture.get_width())
                        var th := float(deform_sprite.texture.get_height())
                        _frame_cols = max(1, int(tw / float(_frame_px)))
                        _frame_rows = max(1, int(th / float(_frame_px)))
                else:
                        _frame_cols = 1
                        _frame_rows = 1
                deform_loaded = loaded
                # TASK 22: applica subito il profilo arti (update_step lo
                # rinnova ogni frame; qui copre il primo frame di vita).
                # TASK 25: anche il gain, così il primo frame è già corretto.
                if deform_loaded and deform_sprite != null:
                        if C.BOSS_LIMB_ANIM_ENABLED:
                                deform_sprite.limb_profile = get_limb_profile(boss_type)
                                deform_sprite.limb_gain = C.BOSS_LIMB_ANIM_GAIN
                        else:
                                deform_sprite.limb_profile = DeformableSprite.LimbProfile.LP_NONE
                        # TASK 26 (fix "boss sbiaditi/sgranati"): enhancement
                        # canvas DIRETTAMENTE sul DeformableSprite (lo shader
                        # sul nodo Boss non si propaga ai figli). Params
                        # "strong" = CharacterArt._enhanced_strong.
                        if C.BOSS_CANVAS_SHADER_ENABLED:
                                deform_sprite.enable_canvas_enhancement()
                        else:
                                deform_sprite.disable_canvas_enhancement()

        # Draw the deformable sprite (it's a child node, draws itself).
        # If not loaded, fall back to procedural primitives drawn in this node's _draw.
        if not deform_loaded:
                _draw_primitives()

        # FIX: HP bar sopra il boss rimossa — c'è già la barra HP in alto
        # allo schermo disegnata da BossRoomController._draw().
        # _draw_hp_bar()


func _draw_hp_bar() -> void:
        # HP bar sits above the boss's head.
        var bar_y := -size * 1.125 - 18.0
        var bar_w := size
        var bar_h := 12.0
        # Background.
        draw_rect(Rect2(-bar_w * 0.5, bar_y, bar_w, bar_h), Color(0.12, 0.0, 0.0))
        draw_rect(Rect2(-bar_w * 0.5, bar_y, bar_w, bar_h), Color(0.39, 0.0, 0.0), false, 2.0)
        # Foreground (color-coded).
        var ratio := float(health) / float(max_health) if max_health > 0 else 0.0
        var col := Color(0.31, 0.86, 0.31) if ratio > 0.5 \
                          else Color(0.86, 0.71, 0.16) if ratio > 0.25 \
                          else Color(0.86, 0.16, 0.16)
        draw_rect(Rect2(-bar_w * 0.5, bar_y, bar_w * ratio, bar_h), col)


# ------------------------------------------------------------
# Procedural fallback (matches C++ Boss::renderPrimitives)
# Each boss type has its own distinctive primitive drawing.
# ------------------------------------------------------------
func _draw_primitives() -> void:
        var px := 0.0  # Local origin is (0,0); position is already applied.
        var py := 0.0
        var outline := Color(0.04, 0.04, 0.04)

        # Mouth animation (sinusoidal).
        var mouth_open := (sin(anim_time * 4.0) + 1.0) * 0.5
        var mouth_h := size / 6.0 + mouth_open * size / 6.0

        match boss_type:
                Type.BOSS_GOLEM:
                        _draw_golem(px, py, outline)
                Type.BOSS_LICH:
                        _draw_lich(px, py, outline, mouth_h)
                Type.BOSS_DEMON:
                        _draw_demon(px, py, outline)
                Type.BOSS_SPIDER:
                        _draw_spider(px, py, outline)
                Type.BOSS_ABOMINATION:
                        _draw_abomination(px, py, outline)
                Type.BOSS_KRAKEN:
                        _draw_kraken(px, py, outline)
                Type.BOSS_DRAGON:
                        _draw_dragon(px, py, outline)
                Type.BOSS_WRAITH_LORD:
                        _draw_wraith_lord(px, py, outline)
                Type.BOSS_VAMPIRE:
                        _draw_vampire(px, py, outline)
                Type.BOSS_BEHOLDER:
                        _draw_beholder(px, py, outline)
                Type.BOSS_GHOUL_LORD:
                        _draw_ghoul_lord(px, py, outline)
                Type.BOSS_SPECTRAL_ALPHA:
                        _draw_spectral_alpha(px, py, outline)
                Type.BOSS_CULT_HERALD:
                        _draw_cult_herald(px, py, outline)
                Type.BOSS_COLOSSAL_MIMIC:
                        _draw_colossal_mimic(px, py, outline)
                Type.BOSS_RAT_KING:
                        _draw_rat_king(px, py, outline)
                Type.BOSS_SUPREME_WITCH:
                        _draw_supreme_witch(px, py, outline)
                Type.BOSS_TWILIGHT_KNIGHT:
                        _draw_twilight_knight(px, py, outline)


# --- Individual primitive renderers (compact translations of C++ code) ---

func _draw_golem(px: float, py: float, outline: Color) -> void:
        var rock := Color(0.39, 0.39, 0.43)
        draw_rect(Rect2(px - size * 0.5, py - size * 0.4, size, size * 0.8), rock)
        var arm_off := sin(anim_time * 3.0) * 10.0
        draw_rect(Rect2(px - size * 0.8, py - size * 0.2 + arm_off,
                                        size * 0.3, size * 0.6), Color(0.24, 0.24, 0.27))
        draw_rect(Rect2(px + size * 0.5, py - size * 0.2 - arm_off,
                                        size * 0.3, size * 0.6), Color(0.24, 0.24, 0.27))
        draw_rect(Rect2(px - size * 0.25, py - size * 0.8, size * 0.5, size * 0.5), rock)
        # Eyes (pulsing green).
        var eb := 150.0 + sin(anim_time * 10.0) * 105.0
        var eye_c := Color(0.0, eb / 255.0, 50.0 / 255.0)
        draw_circle(Vector2(px - size * 0.25, py - size * 0.6), size / 12.0, eye_c)
        draw_circle(Vector2(px + size * 0.25, py - size * 0.6), size / 12.0, eye_c)


func _draw_lich(px: float, py: float, outline: Color, mouth_h: float) -> void:
        # Robe (purple, animated wave).
        var wave := sin(anim_time * 3.0) * 10.0
        var robe_pts := PackedVector2Array([
                Vector2(px, py - size * 0.5),
                Vector2(px + size * 0.5 + wave, py),
                Vector2(px + size * 0.33, py + size * 0.5),
                Vector2(px - size * 0.33, py + size * 0.5),
                Vector2(px - size * 0.5 - wave, py),
        ])
        draw_colored_polygon(robe_pts, Color(0.16, 0.08, 0.24))
        # Skull.
        draw_circle(Vector2(px, py - size * 0.33), size / 3.0, Color(0.86, 0.86, 0.78))
        # Eyes.
        draw_circle(Vector2(px - size * 0.13, py - size * 0.33), size / 14.0, Color(1.0, 0.0, 0.0))
        draw_circle(Vector2(px + size * 0.13, py - size * 0.33), size / 14.0, Color(1.0, 0.0, 0.0))
        # Mouth.
        draw_rect(Rect2(px - size * 0.2, py + size * 0.125, size * 0.4, mouth_h * 0.5), Color.BLACK)


func _draw_demon(px: float, py: float, outline: Color) -> void:
        # Wings (flapping).
        var flap := sin(anim_time * 8.0) * 0.4 + 0.8
        var wing_pts := PackedVector2Array([
                Vector2(px - size * 0.33, py - size * 0.25),
                Vector2(px - size * 1.2, py - size * 0.5 * flap),
                Vector2(px - size * 1.1, py + size * 0.25 * flap),
                Vector2(px - size * 0.33, py + size * 0.16),
        ])
        draw_colored_polygon(wing_pts, Color(0.31, 0.04, 0.04))
        var wing_pts_r := PackedVector2Array([
                Vector2(px + size * 0.33, py - size * 0.25),
                Vector2(px + size * 1.2, py - size * 0.5 * flap),
                Vector2(px + size * 1.1, py + size * 0.25 * flap),
                Vector2(px + size * 0.33, py + size * 0.16),
        ])
        draw_colored_polygon(wing_pts_r, Color(0.31, 0.04, 0.04))
        # Body.
        draw_circle(Vector2(px, py), size * 0.5, Color(0.59, 0.12, 0.12))
        # Horns.
        var horn_l := PackedVector2Array([
                Vector2(px - size * 0.33, py - size * 0.5),
                Vector2(px - size * 0.5, py - size * 0.8),
                Vector2(px - size * 0.25, py - size * 0.7),
        ])
        draw_colored_polygon(horn_l, outline)
        var horn_r := PackedVector2Array([
                Vector2(px + size * 0.33, py - size * 0.5),
                Vector2(px + size * 0.5, py - size * 0.8),
                Vector2(px + size * 0.25, py - size * 0.7),
        ])
        draw_colored_polygon(horn_r, outline)
        # Eyes.
        draw_circle(Vector2(px - size * 0.25 - size * 0.1, py - size * 0.16), size / 10.0, Color.YELLOW)
        draw_circle(Vector2(px + size * 0.25 - size * 0.1, py - size * 0.16), size / 10.0, Color.YELLOW)


func _draw_spider(px: float, py: float, outline: Color) -> void:
        var carapace := Color(0.16, 0.0, 0.20)
        # 8 legs.
        for i in range(4):
                var a1 := deg_to_rad(45.0 + i * 20.0)
                var a2 := deg_to_rad(-45.0 - i * 20.0)
                var leg_move := sin(anim_time * 6.0 + i) * 10.0
                _draw_leg(px - size * 0.25, py + leg_move, a1, size * 0.5, carapace)
                _draw_leg(px + size * 0.25, py - leg_move, a2, size * 0.5, carapace)
        # Abdomen.
        draw_circle(Vector2(px, py - size * 0.25), size * 0.5, carapace)
        # Head.
        draw_circle(Vector2(px, py - size * 0.66), size * 0.25, Color(0.24, 0.0, 0.27))
        # Eyes.
        var eb := 150.0 + sin(anim_time * 8.0) * 105.0
        var eye_c := Color(eb / 255.0, 0.0, 0.0)
        draw_circle(Vector2(px - size * 0.05, py - size * 0.625), size / 20.0, eye_c)
        draw_circle(Vector2(px + size * 0.13, py - size * 0.625), size / 20.0, eye_c)


func _draw_leg(x: float, y: float, angle: float, length: float, color: Color) -> void:
        var end := Vector2(x + cos(angle) * length, y + sin(angle) * length)
        draw_line(Vector2(x, y), end, color, size / 16.0)


func _draw_abomination(px: float, py: float, outline: Color) -> void:
        var flesh := Color(0.55, 0.63, 0.47)
        # Body.
        draw_rect(Rect2(px - size * 0.4, py - size * 0.5, size * 0.8, size), flesh)
        # Arms.
        var arm := sin(anim_time * 2.0) * 15.0
        draw_rect(Rect2(px - size * 0.7, py - size * 0.33 + arm, size * 0.3, size * 0.7), flesh)
        draw_rect(Rect2(px + size * 0.4, py - size * 0.33 - arm, size * 0.3, size * 0.7), flesh)
        # Head.
        draw_rect(Rect2(px - size * 0.2, py - size * 0.9, size * 0.4, size * 0.4), flesh)
        # Bolts.
        draw_rect(Rect2(px - size * 0.3, py - size * 0.8, size * 0.1, size * 0.1), Color(0.71, 0.71, 0.71))
        draw_rect(Rect2(px + size * 0.2, py - size * 0.8, size * 0.1, size * 0.1), Color(0.71, 0.71, 0.71))
        # Eyes.
        draw_circle(Vector2(px - size * 0.2, py - size * 0.75), size / 14.0, Color(0.20, 0.20, 0.20))
        draw_circle(Vector2(px + size * 0.1, py - size * 0.75), size / 14.0, Color(0.20, 0.20, 0.20))


func _draw_kraken(px: float, py: float, outline: Color) -> void:
        var skin := Color(0.0, 0.39, 0.39)
        # 8 tentacles.
        for i in range(8):
                var angle := float(i) * (PI / 4.0) + sin(anim_time * 2.0 + i) * 0.2
                var end := Vector2(px + cos(angle) * size * 0.5, py + sin(angle) * size * 0.5)
                draw_line(Vector2(px, py), end, skin, size * 0.1)
        # Body.
        draw_circle(Vector2(px, py), size * 0.5, skin)
        # Eyes.
        draw_circle(Vector2(px - size * 0.25, py - size * 0.25), size / 10.0, Color.YELLOW)
        draw_circle(Vector2(px + size * 0.25, py - size * 0.25), size / 10.0, Color.YELLOW)


func _draw_dragon(px: float, py: float, outline: Color) -> void:
        var bone := Color(0.78, 0.78, 0.71)
        var flap := sin(anim_time * 6.0) * 0.3 + 0.8
        # Wings.
        var wing_l := PackedVector2Array([
                Vector2(px - size * 0.25, py - size * 0.33),
                Vector2(px - size, py - size * 0.5 * flap),
                Vector2(px - size * 0.9, py + size * 0.16 * flap),
                Vector2(px - size * 0.25, py),
        ])
        draw_colored_polygon(wing_l, Color(0.20, 0.20, 0.20))
        var wing_r := PackedVector2Array([
                Vector2(px + size * 0.25, py - size * 0.33),
                Vector2(px + size, py - size * 0.5 * flap),
                Vector2(px + size * 0.9, py + size * 0.16 * flap),
                Vector2(px + size * 0.25, py),
        ])
        draw_colored_polygon(wing_r, Color(0.20, 0.20, 0.20))
        # Body.
        draw_rect(Rect2(px - size * 0.3, py - size * 0.2, size * 0.6, size * 0.6), bone)
        # Head.
        var head_pts := PackedVector2Array([
                Vector2(px - size * 0.5, py - size),
                Vector2(px - size * 0.25, py - size * 1.1),
                Vector2(px - size * 0.25, py - size * 0.9),
                Vector2(px - size * 0.5, py - size * 0.9),
        ])
        draw_colored_polygon(head_pts, bone)
        # Eye.
        draw_circle(Vector2(px - size * 0.45, py - size * 0.95), size / 20.0, Color.RED)


func _draw_wraith_lord(px: float, py: float, outline: Color) -> void:
        var armor := Color(0.39, 0.39, 0.59)
        # Cloak.
        var wave := sin(anim_time * 4.0) * 15.0
        var cloak_pts := PackedVector2Array([
                Vector2(px - size * 0.5, py - size * 0.33),
                Vector2(px + size * 0.5, py - size * 0.33),
                Vector2(px + size * 0.33 + wave, py + size * 0.5),
                Vector2(px + size * 0.16, py + size * 0.33 - wave * 0.5),
                Vector2(px - size * 0.16, py + size * 0.5),
                Vector2(px - size * 0.33 - wave, py + size * 0.33 + wave * 0.5),
        ])
        draw_colored_polygon(cloak_pts, Color(0.08, 0.08, 0.16, 0.86))
        # Helmet.
        draw_rect(Rect2(px - size * 0.2, py - size * 0.6, size * 0.4, size * 0.5), armor)
        # Horns.
        var horn_l := PackedVector2Array([
                Vector2(px - size * 0.2, py - size * 0.6),
                Vector2(px - size * 0.4, py - size * 0.8),
                Vector2(px - size * 0.2, py - size * 0.5),
        ])
        draw_colored_polygon(horn_l, armor)
        var horn_r := PackedVector2Array([
                Vector2(px + size * 0.2, py - size * 0.6),
                Vector2(px + size * 0.4, py - size * 0.8),
                Vector2(px + size * 0.2, py - size * 0.5),
        ])
        draw_colored_polygon(horn_r, armor)
        # Eyes.
        var eb := 150.0 + sin(anim_time * 5.0) * 105.0
        var eye_c := Color(0.0, eb / 255.0, eb / 255.0, 0.78)
        draw_circle(Vector2(px - size * 0.2, py - size * 0.45), size / 14.0, eye_c)
        draw_circle(Vector2(px + size * 0.1, py - size * 0.45), size / 14.0, eye_c)


func _draw_vampire(px: float, py: float, outline: Color) -> void:
        var skin := Color(0.90, 0.90, 0.98)
        # Cloak.
        var wave := sin(anim_time * 3.0) * 10.0
        var cloak_pts := PackedVector2Array([
                Vector2(px - size * 0.5, py - size * 0.25),
                Vector2(px + size * 0.5, py - size * 0.25),
                Vector2(px + size * 0.33 + wave, py + size * 0.5),
                Vector2(px - size * 0.33 - wave, py + size * 0.5),
        ])
        draw_colored_polygon(cloak_pts, Color(0.47, 0.0, 0.0))
        # Collar.
        draw_rect(Rect2(px - size * 0.15, py - size * 0.3, size * 0.3, size * 0.1), Color.WHITE)
        # Head.
        draw_circle(Vector2(px, py - size * 0.33), size * 0.33, skin)
        # Hair.
        draw_rect(Rect2(px - size * 0.3, py - size * 0.5, size * 0.6, size * 0.2), Color.BLACK)
        # Eyes.
        draw_circle(Vector2(px - size * 0.2, py - size * 0.33), size / 14.0, Color.RED)
        draw_circle(Vector2(px + size * 0.1, py - size * 0.33), size / 14.0, Color.RED)


func _draw_beholder(px: float, py: float, outline: Color) -> void:
        var body_col := Color(0.39, 0.20, 0.20)
        # Pulsating body.
        var pulse := 1.0 + sin(anim_time * 4.0) * 0.1
        draw_circle(Vector2(px, py), size * 0.5 * pulse, body_col)
        # Central eye.
        draw_circle(Vector2(px, py), size * 0.25, Color.WHITE)
        # Pupil that roams.
        var pupil := Vector2(px + cos(anim_time * 2.0) * size * 0.05,
                                                  py + sin(anim_time * 2.0) * size * 0.05)
        draw_circle(pupil, size * 0.0625, Color.BLACK)
        draw_circle(pupil, size * 0.03125, Color.RED)
        # 8 satellite eyes on stalks.
        for i in range(8):
                var a := float(i) * (PI / 4.0) + sin(anim_time * 3.0 + i) * 0.3
                var tx := px + cos(a) * size * 0.5
                var ty := py + sin(a) * size * 0.5
                draw_line(Vector2(px, py), Vector2(tx, ty), body_col, 2.0)
                draw_circle(Vector2(tx, ty), size / 12.0, Color.WHITE)
                draw_circle(Vector2(tx, ty), size / 24.0, Color.BLACK)


func _draw_ghoul_lord(px: float, py: float, outline: Color) -> void:
        var bone := Color(0.86, 0.86, 0.78)
        # Aura.
        draw_circle(Vector2(px, py), size * 0.5 + 10.0, Color(0.31, 1.0, 0.31, 0.16))
        # Body.
        draw_rect(Rect2(px - size * 0.4, py - size * 0.5, size * 0.8, size), bone)
        # Arms.
        var arm := sin(anim_time * 2.0) * 15.0
        draw_rect(Rect2(px - size * 0.6, py - size * 0.25 + arm, size * 0.2, size * 0.6), bone)
        draw_rect(Rect2(px + size * 0.4, py - size * 0.25 - arm, size * 0.2, size * 0.6), bone)
        # Head.
        draw_circle(Vector2(px, py - size * 0.66), size * 0.33, bone)
        # Crown spikes.
        for i in range(5):
                var sx := px - size * 0.33 + float(i) * (size * 0.66) / 4.0
                var spike := PackedVector2Array([
                        Vector2(sx, py - size * 0.8),
                        Vector2(sx + size * 0.083, py - size * 0.8),
                        Vector2(sx + size * 0.042, py - size * 0.8 - size * 0.125),
                ])
                draw_colored_polygon(spike, Color(0.94, 0.94, 0.86))
        # Eyes.
        draw_circle(Vector2(px - size * 0.2, py - size * 0.6), size / 14.0, Color(1.0, 0.20, 0.20))
        draw_circle(Vector2(px + size * 0.1, py - size * 0.6), size / 14.0, Color(1.0, 0.20, 0.20))


func _draw_spectral_alpha(px: float, py: float, outline: Color) -> void:
        var smoke := Color(0.47, 0.47, 0.55, 0.78)
        # 6 smoke puffs.
        for i in range(6):
                var a := float(i) * (PI / 3.0) + anim_time
                var puff_pos := Vector2(px - size * 0.5 + cos(a) * size * 0.33,
                                                                  py - size * 0.33 + sin(a) * size * 0.25)
                draw_circle(puff_pos, size * 0.25, smoke)
        # Body.
        var body_pts := PackedVector2Array([
                Vector2(px - size * 0.5, py + size * 0.25),
                Vector2(px - size * 0.33, py - size * 0.25),
                Vector2(px + size * 0.25, py - size * 0.25),
                Vector2(px + size * 0.5, py),
                Vector2(px + size * 0.33, py + size * 0.25),
        ])
        draw_colored_polygon(body_pts, Color(0.35, 0.35, 0.43, 0.90))
        # Head.
        draw_circle(Vector2(px + size * 0.25, py - size * 0.33), size * 0.25, Color(0.43, 0.43, 0.51, 0.90))
        # Ear.
        var ear := PackedVector2Array([
                Vector2(px + size * 0.25, py - size * 0.33),
                Vector2(px + size * 0.2, py - size * 0.5),
                Vector2(px + size * 0.33, py - size * 0.33),
        ])
        draw_colored_polygon(ear, Color(0.35, 0.35, 0.43, 0.90))
        # Eye.
        draw_circle(Vector2(px + size * 0.33, py - size * 0.25), size / 20.0, Color(0.59, 1.0, 0.59))


func _draw_cult_herald(px: float, py: float, outline: Color) -> void:
        # Robe.
        var wave := sin(anim_time * 3.0) * 15.0
        var robe_pts := PackedVector2Array([
                Vector2(px - size * 0.5, py - size * 0.33),
                Vector2(px + size * 0.5, py - size * 0.33),
                Vector2(px + size * 0.33 + wave, py + size * 0.5),
                Vector2(px + size * 0.16, py + size * 0.33),
                Vector2(px - size * 0.16, py + size * 0.5),
                Vector2(px - size * 0.33 - wave, py + size * 0.33),
        ])
        draw_colored_polygon(robe_pts, Color(0.24, 0.0, 0.31))
        # Hood.
        draw_circle(Vector2(px, py - size * 0.66), size * 0.33, Color(0.16, 0.0, 0.24))
        # Face (dark).
        draw_circle(Vector2(px, py - size * 0.55), size * 0.16, Color.BLACK)
        # Eyes (golden).
        draw_circle(Vector2(px - size * 0.05, py - size * 0.58), size / 24.0, Color(1.0, 0.84, 0.0))
        draw_circle(Vector2(px + size * 0.08, py - size * 0.58), size / 24.0, Color(1.0, 0.84, 0.0))
        # Staff.
        draw_rect(Rect2(px + size * 0.4, py - size * 0.33, size * 0.083, size * 0.8), Color(0.47, 0.31, 0.16))
        # Sigil.
        draw_circle(Vector2(px + size * 0.43, py - size * 0.4), size * 0.1, Color(0.71, 0.20, 0.86, 0.78))


func _draw_colossal_mimic(px: float, py: float, outline: Color) -> void:
        var wood := Color(0.43, 0.27, 0.12)
        # Body (chest).
        draw_rect(Rect2(px - size * 0.5, py - size * 0.33, size, size * 0.8), wood)
        # Lid.
        var lid_pts := PackedVector2Array([
                Vector2(px - size * 0.5, py - size * 0.33),
                Vector2(px + size * 0.5, py - size * 0.33),
                Vector2(px + size * 0.33, py - size * 0.8),
                Vector2(px - size * 0.33, py - size * 0.8),
        ])
        draw_colored_polygon(lid_pts, Color(0.31, 0.20, 0.08))
        # Maw (black).
        draw_rect(Rect2(px - size * 0.4, py - size * 0.125, size * 0.8, size * 0.25), Color.BLACK)
        # 8 teeth.
        for i in range(8):
                var tw := size * 0.8 / 8.0
                var tooth := PackedVector2Array([
                        Vector2(px - size * 0.4 + float(i) * tw, py - size * 0.125),
                        Vector2(px - size * 0.4 + float(i + 1) * tw, py - size * 0.125),
                        Vector2(px - size * 0.4 + float(i) * tw + tw * 0.5, py),
                ])
                draw_colored_polygon(tooth, Color(1.0, 1.0, 0.86))
        # Tongue.
        var tongue := PackedVector2Array([
                Vector2(px - size * 0.125, py),
                Vector2(px + size * 0.125, py),
                Vector2(px + size * 0.083, py + size * 0.16),
                Vector2(px - size * 0.083, py + size * 0.16),
        ])
        draw_colored_polygon(tongue, Color(0.86, 0.31, 0.47))
        # Bands.
        draw_rect(Rect2(px - size * 0.33, py - size * 0.33, size * 0.083, size * 0.8), Color(0.78, 0.78, 0.78))
        draw_rect(Rect2(px + size * 0.25, py - size * 0.33, size * 0.083, size * 0.8), Color(0.78, 0.78, 0.78))


func _draw_rat_king(px: float, py: float, outline: Color) -> void:
        var fur := Color(0.31, 0.27, 0.24)
        # 5 surrounding rats.
        for i in range(5):
                var a := float(i) * (TAU / 5.0) + anim_time * 0.5
                var rat_pos := Vector2(px + cos(a) * size * 0.33, py + sin(a) * size * 0.33)
                draw_circle(rat_pos, size * 0.2, fur)
                draw_circle(rat_pos + Vector2(size * 0.07, 0), size * 0.05, Color.RED)
        # Central body.
        draw_circle(Vector2(px, py), size * 0.33, Color(0.24, 0.20, 0.16))
        # Crown spikes.
        for i in range(5):
                var sx := px - size * 0.25 + float(i) * size * 0.125
                var spike := PackedVector2Array([
                        Vector2(sx, py - size * 0.33),
                        Vector2(sx + size * 0.083, py - size * 0.33),
                        Vector2(sx + size * 0.042, py - size * 0.5),
                ])
                draw_colored_polygon(spike, Color(0.94, 0.94, 0.86))
        # Eyes.
        draw_circle(Vector2(px - size * 0.125, py - size * 0.16), size / 16.0, Color(1.0, 0.12, 0.12))
        draw_circle(Vector2(px + size * 0.063, py - size * 0.16), size / 16.0, Color(1.0, 0.12, 0.12))


func _draw_supreme_witch(px: float, py: float, outline: Color) -> void:
        var robe := Color(0.16, 0.31, 0.16)
        # 6 vines rotating.
        for i in range(6):
                var a := float(i) * (PI / 3.0) + anim_time
                var end := Vector2(px + cos(a) * size * 0.33, py + sin(a) * size * 0.33)
                draw_line(Vector2(px, py), end, Color(0.24, 0.47, 0.24), size * 0.083)
        # Robe.
        var wave := sin(anim_time * 2.0) * 12.0
        var robe_pts := PackedVector2Array([
                Vector2(px, py - size * 0.33),
                Vector2(px + size * 0.5 + wave, py),
                Vector2(px + size * 0.33, py + size * 0.5),
                Vector2(px - size * 0.33, py + size * 0.5),
                Vector2(px - size * 0.5 - wave, py),
        ])
        draw_colored_polygon(robe_pts, robe)
        # Face.
        draw_circle(Vector2(px, py - size * 0.33), size * 0.25, Color(0.59, 0.78, 0.47))
        # Hat.
        var hat := PackedVector2Array([
                Vector2(px - size * 0.33, py - size * 0.5),
                Vector2(px + size * 0.33, py - size * 0.5),
                Vector2(px + size * 0.083, py - size),
        ])
        draw_colored_polygon(hat, Color(0.08, 0.08, 0.08))
        # Eyes.
        draw_circle(Vector2(px - size * 0.1, py - size * 0.42), size / 24.0, Color(1.0, 1.0, 0.39))
        draw_circle(Vector2(px + size * 0.03, py - size * 0.42), size / 24.0, Color(1.0, 1.0, 0.39))


func _draw_twilight_knight(px: float, py: float, outline: Color) -> void:
        var armor := Color(0.08, 0.08, 0.14)
        # Body.
        draw_rect(Rect2(px - size * 0.375, py - size * 0.375, size * 0.75, size * 0.75), armor)
        # Pulsing aura.
        var pulse := 1.0 + sin(anim_time * 3.0) * 0.1
        draw_circle(Vector2(px, py), size * 0.5 * pulse, Color(0.0, 0.0, 0.12, 0.39))
        # Chest.
        draw_rect(Rect2(px - size * 0.25, py - size * 0.16, size * 0.5, size * 0.33), Color(0.16, 0.16, 0.24))
        # Helmet.
        draw_rect(Rect2(px - size * 0.25, py - size * 0.8, size * 0.5, size * 0.4), armor)
        # Visor.
        draw_rect(Rect2(px - size * 0.16, py - size * 0.55, size * 0.33, size * 0.0625), Color(0.59, 0.20, 0.86))
        # Shield.
        draw_circle(Vector2(px - size * 0.5, py), size * 0.25, Color(0.12, 0.12, 0.20))
        # Lance.
        draw_rect(Rect2(px + size * 0.33, py - size * 0.5, size * 0.083, size), Color(0.71, 0.71, 0.78))
        # Lance tip.
        var tip := PackedVector2Array([
                Vector2(px + size * 0.33, py - size * 0.5),
                Vector2(px + size * 0.41, py - size * 0.5),
                Vector2(px + size * 0.375, py - size * 0.625),
        ])
        draw_colored_polygon(tip, Color(0.86, 0.86, 0.94))


# ============================================================
# Sprite loading (static, called once by Game::init)
# ============================================================

# In the C++ version, Boss::loadAllSprites caches SpriteSheets. In Godot this
# responsibility is delegated to the SpriteManager autoload, which loads all
# `*_sheet.png` files at startup. The Boss simply looks up its sprite by ID.
# For the DeformableSprite path we lazy-load the texture on first render.
