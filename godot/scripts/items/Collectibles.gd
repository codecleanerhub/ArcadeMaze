## Collectibles.gd - Maze items: mines, chalice, scepter, speed boots,
##                  treasures, exit door and magic portal.
## ============================================================
## Godot port of the items defined in `src/Game.h` (struct Mine,
## GoldenChalice, MagicScepter, SpeedBootsBonus, ExitDoor, MagicPortal)
## and the corresponding Cell.treasure / TreasureType from `src/Maze.h`.
##
## Each kind of item is a small Node2D with its own update/render logic.
## The Game scene instantiates them as needed and calls `update_step()`
## each frame; the player's collision logic queries `active` and `pos`.
extends Node2D
class_name Collectibles

# Treasure kinds (mirror C++ enum TreasureType).
enum TreasureType { TRES_CROWN, TRES_GOLD, TRES_CHEST, TRES_GEM, TRES_CUP }

# All treasure kinds (5) give the same score on collection.
const TREASURE_COUNT := 5
const TREASURE_POINTS := 10000

# Power-up types (sub-enum for the collectibles kinds themselves).
enum Kind {
        MINE,            # Explosive bouncing ball (1 per level, also in boss room).
        CHALICE,         # Golden chalice - 15s of player invincibility.
        SCEPTER,         # Lightning scepter - 5 strikes at 3s intervals.
        SPEED_BOOTS,     # Permanent speed boost (P1 or P2 owner).
        TREASURE,        # One of the 5 treasures (crown/gold/chest/gem/cup).
        EXIT_DOOR,       # Appears once all treasures are collected.
        MAGIC_PORTAL,    # Spawns at 50% enemies killed; respawns enemies.
}

@export var kind: int = Kind.TREASURE:
        set(v):
                kind = v
                _apply_kind_defaults()

@export var treasure_type: int = TreasureType.TRES_CROWN

@export var active: bool = true

# Position in pixels (top-left origin, +Y down).
var pos: Vector2 = Vector2.ZERO:
        set(v):
                pos = v
                position = v

# Per-item animation state.
var anim_time: float = 0.0
var pulse: float = 0.0
var bob_offset: float = 0.0
var rotation_deg: float = 0.0

# --- MINE-specific ---
var bouncing: bool = false
var velocity: Vector2 = Vector2.ZERO
var bounce_timer_ms: int = 0
var in_boss_room: bool = false

# --- SCEPTER-specific ---
var triggered: bool = false
var lightnings_left: int = 0
var lightning_timer_ms: int = 0  # ms to next strike

# --- SPEED_BOOTS-specific ---
var owner_id: int = 0  # 0 = free (1P), 1 = P1, 2 = P2

# --- EXIT_DOOR-specific ---
var door_anim_timer_ms: int = 0
var door_glow_pulse: float = 0.0

# --- MAGIC_PORTAL-specific ---
var portal_phase: int = 0       # 0=open, 1=spawn, 2=close, 3=idle
var portal_phase_timer_ms: int = 0
var portal_enemies_to_spawn: int = 0
var portal_spawn_timer_ms: int = 0

# ----- Signals -----
# Emitted when an item is collected by the player. `player_id` is 1 or 2.
signal collected(item: Collectibles, player_id: int)
# Emitted when a scepter's lightning strike should fire.
signal lightning_strike(target_pos: Vector2)


func _ready() -> void:
        _apply_kind_defaults()


func _apply_kind_defaults() -> void:
        match kind:
                Kind.MINE:
                        rotation_deg = 0.0
                        pulse = 0.0
                        bouncing = false
                        bounce_timer_ms = 0
                Kind.CHALICE:
                        pulse = 0.0
                        bob_offset = 0.0
                Kind.SCEPTER:
                        pulse = 0.0
                        bob_offset = 0.0
                        lightnings_left = 5
                        lightning_timer_ms = 3000
                Kind.SPEED_BOOTS:
                        bob_offset = 0.0
                        owner_id = 0
                Kind.EXIT_DOOR:
                        door_anim_timer_ms = 0
                        door_glow_pulse = 0.0
                Kind.MAGIC_PORTAL:
                        portal_phase = 0
                        portal_phase_timer_ms = 0


# =========================================================
# Update step (delta_ms ≈ 16ms per frame at 60fps)
# =========================================================
# `player_pos` is the pixel position of the active player (P1) for collision
# detection. Set by the Game. For 2P, call twice (once per player).
func update_step(delta_ms: int, player_pos: Vector2, player_id: int = 1) -> void:
        if not active:
                return
        anim_time += float(delta_ms) * 0.001
        bob_offset = sin(anim_time * 3.0) * 2.0
        pulse = (sin(anim_time * 4.0) + 1.0) * 0.5
        rotation_deg += float(delta_ms) * 0.1
        match kind:
                Kind.MINE:
                        _update_mine(delta_ms)
                Kind.CHALICE:
                        pass  # only anim
                Kind.SCEPTER:
                        _update_scepter(delta_ms)
                Kind.SPEED_BOOTS:
                        pass
                Kind.TREASURE:
                        pass
                Kind.EXIT_DOOR:
                        _update_door(delta_ms)
                Kind.MAGIC_PORTAL:
                        _update_portal(delta_ms)

        # Collision: 16px radius for small items, 24px for the door/portal.
        var coll_radius := 16.0
        if kind == Kind.EXIT_DOOR or kind == Kind.MAGIC_PORTAL:
                coll_radius = 24.0
        elif kind == Kind.MINE:
                coll_radius = 12.0
        if active and pos.distance_to(player_pos) <= coll_radius:
                _on_collected(player_id)


# =========================================================
# Per-kind update helpers
# =========================================================

func _update_mine(delta_ms: int) -> void:
        if bouncing:
                # Bounce physics: gravity + floor bounce.
                velocity.y += 0.2  # gravity (px/frame²)
                pos += velocity
                rotation_deg += 6.0
                # Simple horizontal bounce off the room bounds.
                if pos.x < 64.0 or pos.x > 1024.0 - 64.0:
                        velocity.x = -velocity.x
                if bounce_timer_ms > delta_ms:
                        bounce_timer_ms -= delta_ms
                else:
                        bouncing = false
                        bounce_timer_ms = 0
                        active = false
                        collected.emit(self, 0)  # mine expired (no player)


func _update_scepter(delta_ms: int) -> void:
        if triggered:
                if lightning_timer_ms > delta_ms:
                        lightning_timer_ms -= delta_ms
                else:
                        if lightnings_left > 0:
                                # Fire a strike at a random target near the player position.
                                # The Game can override this target via the lightning_strike
                                # signal (e.g. to pick the closest enemy/boss).
                                lightnings_left -= 1
                                lightning_timer_ms = 3000
                                lightning_strike.emit(pos + Vector2(randf_range(-200, 200), randf_range(-200, 200)))
                        else:
                                active = false


func _update_door(delta_ms: int) -> void:
        if door_anim_timer_ms > 0:
                door_anim_timer_ms = maxi(0, door_anim_timer_ms - delta_ms)
        door_glow_pulse = (sin(anim_time * 3.0) + 1.0) * 0.5


func _update_portal(delta_ms: int) -> void:
        if portal_phase_timer_ms > delta_ms:
                portal_phase_timer_ms -= delta_ms
        else:
                match portal_phase:
                        0:  # opening
                                portal_phase = 1
                                portal_phase_timer_ms = 4000
                        1:  # spawning
                                if portal_enemies_to_spawn > 0:
                                        portal_enemies_to_spawn -= 1
                                        portal_spawn_timer_ms = 4000
                                        portal_phase_timer_ms = 4000
                                else:
                                        portal_phase = 2
                                        portal_phase_timer_ms = 1000
                        2:  # closing
                                portal_phase = 3
                                portal_phase_timer_ms = 0
                                active = false
                        3:
                                active = false
        if portal_phase == 1 and portal_enemies_to_spawn > 0:
                if portal_spawn_timer_ms > delta_ms:
                        portal_spawn_timer_ms -= delta_ms
                else:
                        portal_enemies_to_spawn -= 1
                        portal_spawn_timer_ms = 4000


# =========================================================
# Public API for the Game to configure items
# =========================================================

# --- MINE ---
func start_bounce(initial_vel: Vector2, duration_ms: int = 1500) -> void:
        bouncing = true
        velocity = initial_vel
        bounce_timer_ms = duration_ms

# --- CHALICE ---
func consume_chalice() -> int:
        # Returns the invincibility duration in ms (15 seconds).
        if kind == Kind.CHALICE and active:
                active = false
                return 15000
        return 0

# --- SCEPTER ---
func trigger_scepter() -> void:
        if kind == Kind.SCEPTER and active and not triggered:
                triggered = true
                lightnings_left = 5
                lightning_timer_ms = 0  # fire immediately on first frame

# --- SPEED BOOTS ---
func consume_boots(player_id: int) -> void:
        if kind == Kind.SPEED_BOOTS and active:
                active = false
                owner_id = player_id

# --- EXIT DOOR ---
# Attiva la porta di uscita e fa partire l'animazione di apertura (800ms).
# Chiamato dal Game quando tutti i tesori sono stati raccolti. L'anta si
# restringe verso destra rivelando la scala sottostante (1:1 con C++).
func start_open_animation() -> void:
        if kind == Kind.EXIT_DOOR:
                active = true
                door_anim_timer_ms = 800


# =========================================================
# Collision callback
# =========================================================
func _on_collected(player_id: int) -> void:
        match kind:
                Kind.MINE:
                        # Mine activates on touch: starts bouncing in a random direction
                        # at moderate speed. The Game's collision logic detects enemy
                        # hits during the bounce; after bounce_timer expires the mine
                        # deactivates.
                        if not bouncing:
                                var ang := randf() * TAU
                                start_bounce(Vector2(cos(ang), sin(ang)) * 4.0, 1500)
                Kind.CHALICE:
                        active = false
                        collected.emit(self, player_id)
                Kind.SCEPTER:
                        # Don't deactivate yet — scepter has 5 strikes to fire.
                        trigger_scepter()
                        collected.emit(self, player_id)
                Kind.SPEED_BOOTS:
                        consume_boots(player_id)
                        collected.emit(self, player_id)
                Kind.TREASURE:
                        active = false
                        collected.emit(self, player_id)
                Kind.EXIT_DOOR:
                        # Door activation is handled by Game (level transition).
                        collected.emit(self, player_id)
                Kind.MAGIC_PORTAL:
                        # Portal is not collectible.
                        pass


# =========================================================
# Rendering
# =========================================================
func _draw() -> void:
        if not active:
                if kind == Kind.EXIT_DOOR:
                        # Door stays visible briefly during its open animation.
                        if door_anim_timer_ms > 0:
                                _draw_exit_door()
                return
        match kind:
                Kind.MINE:         _draw_mine()
                Kind.CHALICE:      _draw_chalice()
                Kind.SCEPTER:      _draw_scepter()
                Kind.SPEED_BOOTS:  _draw_speed_boots()
                Kind.TREASURE:     _draw_treasure()
                Kind.EXIT_DOOR:    _draw_exit_door()
                Kind.MAGIC_PORTAL: _draw_magic_portal()


func _draw_mine() -> void:
        # Spiky ball with pulsing red aura + trail when bouncing.
        # Mirrors C++ Game.cpp 5294-5350 (mine rendering):
        #   * Aura rossa pulsante 18px (Color 200,50,20,50)
        #   * Body (cerchio metallico scuro 7px pulsante)
        #   * 4 spunzoni triangolari (Godot: 8 spikes, kept for retrocompat)
        #   * LED rosso pulsante al centro
        #   * Scia quando bouncing (3px arancio a pos-vel)
        var r := 10.0 + pulse * 1.5
        var col := Color(0.7, 0.6, 0.3)
        var dark := Color(0.2, 0.2, 0.2)
        # --- Aura rossa pulsante (18px) ---
        # In C++: pulse = sinf(mine.pulse * 5.f) * 0.2 + 1.f (range 0.8-1.2)
        var aura_pulse: float = sin(anim_time * 5.0) * 0.2 + 1.0
        var aura_r: float = 18.0 * aura_pulse
        draw_circle(Vector2.ZERO, aura_r,
                Color(200.0 / 255.0, 50.0 / 255.0, 20.0 / 255.0, 50.0 / 255.0))
        # --- Scia quando rimbalza (3px at pos-velocity) ---
        # Drawn in local space, so -velocity (since pos == local origin).
        if bouncing:
                var trail_pos: Vector2 = -velocity
                draw_circle(trail_pos, 3.0,
                        Color(255.0 / 255.0, 150.0 / 255.0, 50.0 / 255.0, 100.0 / 255.0))
        # --- Corpo della mina (cerchio scuro) ---
        draw_circle(Vector2.ZERO, r, col)
        # --- Spikes (8 triangulari attorno al corpo) ---
        for i in range(8):
                var a := (float(i) / 8.0) * TAU + deg_to_rad(rotation_deg)
                var tip := Vector2(cos(a), sin(a)) * (r + 4.0)
                var base_l := Vector2(cos(a + 0.3), sin(a + 0.3)) * r
                var base_r := Vector2(cos(a - 0.3), sin(a - 0.3)) * r
                draw_colored_polygon(PackedVector2Array([tip, base_l, base_r]), dark)
        # --- LED rosso pulsante (blinking, kept as original) ---
        if fmod(anim_time, 1.0) > 0.5:
                draw_circle(Vector2.ZERO, 2.0, Color(1.0, 0.2, 0.2))


func _draw_chalice() -> void:
        # Golden chalice with a pulsing aura.
        var aura_r := 18.0 + pulse * 3.0
        draw_circle(Vector2.ZERO - Vector2(0, bob_offset), aura_r,
                                Color(1.0, 0.85, 0.2, 0.20))
        # Cup body
        var gold := Color(1.0, 0.85, 0.2)
        var y_off := -bob_offset
        var top := Rect2(-8.0, -10.0 + y_off, 16.0, 4.0)
        var body := Rect2(-6.0, -6.0 + y_off, 12.0, 10.0)
        var base := Rect2(-3.0, 4.0 + y_off, 6.0, 4.0)
        draw_rect(top, gold)
        draw_rect(body, gold)
        draw_rect(base, gold)
        # Stem
        draw_rect(Rect2(-1.5, -2.0 + y_off, 3.0, 6.0), gold)
        # Highlight
        draw_rect(Rect2(-5.0, -5.0 + y_off, 2.0, 4.0), Color(1.0, 1.0, 0.7))


func _draw_scepter() -> void:
        # Port 1:1 di Game::drawMagicScepter (C++ righe 3308-3478).
        # Bastone di Gandalf con gemma azzurra incastonata in gabbia dorata.
        # Strati (dal basso verso l'alto):
        #   1. Aura magica pulsante (2 cerchi: gem + bianco)
        #   2. Bastone lungo (3 strati: medio + venatura chiara + ombra scura)
        #   3. 3 nodi del legno (con highlight 3D)
        #   4. 4 prongs dorati che tengono la gemma (raggi inclinati a 45/135/225/315)
        #   5. Cornice metallica dorata (gemBase, anello alla base della gemma)
        #   6. Gemma cristallina (azzurra) + nucleo bianco + specchio
        #   7. 4 raggi di luce rotanti (bianco semi-trasparente)
        #   8. Impugnatura: anello oro + 3 strisce cuoio + anello oro
        #   9. Ombra sul pavimento (ellisse scura)
        # (sx, sy) e' il centro del bastone (gemma ~sy-18, impugnatura ~sy+18).
        var y_off := -bob_offset
        var sx := 0.0
        var sy := y_off
        var s_pulse := 1.0 + pulse * 0.2  # fattore di pulsazione (>1 = piu' grande)
        # Palette 16 colori OBBLIGATORIA (1:1 con C++ drawMagicScepter).
        var col_black := Color(12.0 / 255.0, 12.0 / 255.0, 12.0 / 255.0)
        var col_dark_wood := Color(48.0 / 255.0, 40.0 / 255.0, 36.0 / 255.0)
        var col_mid_wood := Color(96.0 / 255.0, 80.0 / 255.0, 72.0 / 255.0)
        var col_lit_wood := Color(160.0 / 255.0, 128.0 / 255.0, 112.0 / 255.0)
        var col_pale := Color(200.0 / 255.0, 180.0 / 255.0, 160.0 / 255.0)
        var col_gold := Color(220.0 / 255.0, 160.0 / 255.0, 40.0 / 255.0)
        var col_gem := Color(80.0 / 255.0, 160.0 / 255.0, 220.0 / 255.0)
        var col_white := Color(240.0 / 255.0, 240.0 / 255.0, 240.0 / 255.0)
        # --- Aura magica pulsante attorno alla gemma (2 strati) ---
        var aura_r := 22.0 * s_pulse
        draw_circle(Vector2(sx, sy - 18.0), aura_r,
                Color(col_gem.r, col_gem.g, col_gem.b, 55.0 / 255.0))
        var aura_r2 := 12.0 * s_pulse
        draw_circle(Vector2(sx, sy - 18.0), aura_r2,
                Color(col_white.r, col_white.g, col_white.b, 80.0 / 255.0))
        # --- Bastone lungo (legno grezzo, 3 strati di texture) ---
        # Strato base: legno medio 4x32.
        draw_rect(Rect2(sx - 2.0, sy - 4.0, 4.0, 32.0), col_mid_wood, true)
        draw_rect(Rect2(sx - 2.0, sy - 4.0, 4.0, 32.0), col_black, false, 0.5)
        # Strato chiaro (venatura del legno) - 1.2x32.
        draw_rect(Rect2(sx - 1.5, sy - 4.0, 1.2, 32.0), col_lit_wood, true)
        # Strato scuro (ombra venatura) - 0.8x32.
        draw_rect(Rect2(sx + 0.8, sy - 4.0, 0.8, 32.0), col_dark_wood, true)
        # --- 3 nodi del legno (effetto texture ruvida) ---
        # Nodi scuri con highlight per dare carattere di legno grezzo.
        for n in range(3):
                var ny: float = sy - 2.0 + float(n) * 11.0
                draw_circle(Vector2(sx - 1.2, ny), 1.2, col_dark_wood)
                draw_circle(Vector2(sx - 0.8, ny - 0.3), 0.5, col_pale)
        # --- 4 prongs dorati che tengono la gemma (gabbia metallica) ---
        # Simula le rifle metalliche che tengono il cristallo (bastone Gandalf).
        # 4 raggi inclinati a 45, 135, 225, 315 gradi dalla cima del bastone
        # (sx, sy-4) verso i lati della gemma (sx +/- 5, sy-18 +/- 5).
        for i in range(4):
                var angle: float = float(i) * (PI / 2.0) + (PI / 4.0)
                var ex: float = sx + cos(angle) * 5.0
                var ey: float = (sy - 18.0) + sin(angle) * 5.0
                draw_line(Vector2(sx, sy - 4.0), Vector2(ex, ey), col_gold, 1.2)
        # --- Cornice metallica dorata (gemBase) ---
        # Anello dorato alla base della gemma (dove il cristallo si inserisce).
        draw_circle(Vector2(sx, sy - 18.0), 5.5, col_gold)
        draw_circle(Vector2(sx, sy - 18.0), 5.5, col_dark_wood, false, 1.0)
        # --- Gemma cristallina luminosa (azzurra, r=6*sPulse) ---
        # Outline dorato spesso 1.2 (disegnato come cerchio piu' grande sotto).
        var gem_r := 6.0 * s_pulse
        draw_circle(Vector2(sx, sy - 18.0), gem_r + 1.2, col_gold)
        draw_circle(Vector2(sx, sy - 18.0), gem_r, col_gem)
        # --- Nucleo bianco luminoso + specchio ---
        var core_r := 2.5 * s_pulse
        draw_circle(Vector2(sx, sy - 18.0), core_r, col_white)
        # Riflesso specchiato (piccolo puntino bianco in alto a sinistra).
        draw_circle(Vector2(sx - 2.0, sy - 18.0 - 3.0), 0.8,
                Color(col_white.r, col_white.g, col_white.b, 220.0 / 255.0))
        # --- 4 raggi di luce rotanti dalla gemma ---
        # Simula la luce magica che emana dal cristallo (rotazione lenta).
        for i in range(4):
                var angle: float = float(i) * (PI / 2.0) + s_pulse * 0.3
                # Direzione del raggio (in coordinate schermo y-down):
                # il raggio punta in direzione (-cos(angle), -sin(angle)).
                var dir := Vector2(-cos(angle), -sin(angle))
                var ray_len: float = 10.0 * s_pulse
                var p_start := Vector2(sx, sy - 18.0)
                var p_end: Vector2 = p_start + dir * ray_len
                draw_line(p_start, p_end,
                        Color(col_white.r, col_white.g, col_white.b, 120.0 / 255.0), 1.0)
        # --- Impugnatura (grip) ---
        # 1. Anello metallico superiore (oro) 6x1.5.
        draw_rect(Rect2(sx - 3.0, sy + 16.0, 6.0, 1.5), col_gold, true)
        draw_rect(Rect2(sx - 3.0, sy + 16.0, 6.0, 1.5), col_dark_wood, false, 0.4)
        # 2. Cuoio avvolto (3 strisce di legno scuro).
        for i in range(3):
                var ly: float = sy + 18.0 + float(i) * 1.8
                draw_rect(Rect2(sx - 2.75, ly, 5.5, 1.5), col_dark_wood, true)
                draw_rect(Rect2(sx - 2.75, ly, 5.5, 1.5), col_black, false, 0.2)
        # 3. Anello metallico inferiore (oro) 6x1.5.
        draw_rect(Rect2(sx - 3.0, sy + 24.0, 6.0, 1.5), col_gold, true)
        draw_rect(Rect2(sx - 3.0, sy + 24.0, 6.0, 1.5), col_dark_wood, false, 0.4)
        # --- Ombra del bastone sul pavimento ---
        # Ellisise piatta scura per ancoraggio visivo (in C++ scale 1.5x0.5).
        draw_circle(Vector2(sx, sy + 28.0), 4.0,
                Color(col_black.r, col_black.g, col_black.b, 80.0 / 255.0))


func _draw_speed_boots() -> void:
        # Usa sprite AI bonus_speedboots se caricato da SpriteManager,
        # altrimenti fallback procedurale.
        var y_off := -bob_offset
        if SpriteManager:
                var sheet = SpriteManager.get_sheet("bonus_speedboots")
                if sheet != null and sheet.is_loaded():
                        var at: AtlasTexture = sheet.get_frame_texture("idle", 0)
                        if at != null:
                                var tw: float = at.get_width()
                                var th: float = at.get_height()
                                draw_texture_rect(at, Rect2(-tw / 2.0, -th / 2.0 + y_off, tw, th), false)
                                return
        # Fallback: Winged boot icon
        draw_rect(Rect2(-6.0, 0.0 + y_off, 10.0, 6.0), Color(0.4, 0.3, 0.2))
        draw_rect(Rect2(-6.0, -6.0 + y_off, 6.0, 8.0), Color(0.4, 0.3, 0.2))
        draw_colored_polygon(PackedVector2Array([
                Vector2(2.0, -4.0 + y_off),
                Vector2(10.0, -8.0 + y_off),
                Vector2(2.0, 0.0 + y_off)
        ]), Color(1.0, 1.0, 1.0, 0.9))


func _draw_treasure() -> void:
        # Usa texture procedurali ad alta risoluzione da EnvironmentArt
        # (miglioramento grafico Godot-native vs PNG AI 64x64 del C++)
        var y_off := -bob_offset
        # Soft glow
        draw_circle(Vector2.ZERO, 18.0, Color(1.0, 0.85, 0.3, 0.2))
        if EnvironmentArt:
                var tex: Texture2D = EnvironmentArt.get_treasure_texture(treasure_type)
                if tex:
                        # Disegna la texture 128x128 scalata a 32x32 centrata
                        var size: float = 32.0
                        var draw_rect := Rect2(-size / 2.0, -size / 2.0 + y_off, size, size)
                        draw_texture_rect(tex, draw_rect, false)
                        return
        # Fallback: rendering semplice se EnvironmentArt non disponibile
        match treasure_type:
                TreasureType.TRES_CROWN:
                        draw_rect(Rect2(-8.0, 0.0 + y_off, 16.0, 4.0), Color(1.0, 0.85, 0.2))
                        for i in range(3):
                                var x := -6.0 + float(i) * 6.0
                                draw_colored_polygon(PackedVector2Array([
                                        Vector2(x, 0.0 + y_off),
                                        Vector2(x + 4.0, 0.0 + y_off),
                                        Vector2(x + 2.0, -6.0 + y_off)
                                ]), Color(1.0, 0.85, 0.2))
                TreasureType.TRES_GOLD:
                        for i in range(3):
                                draw_circle(Vector2(0, float(i) * 2.0 + y_off - 4.0), 5.0,
                                                        Color(1.0, 0.85, 0.2))
                TreasureType.TRES_CHEST:
                        draw_rect(Rect2(-8.0, -4.0 + y_off, 16.0, 10.0), Color(0.6, 0.4, 0.2))
                        draw_rect(Rect2(-8.0, -6.0 + y_off, 16.0, 4.0), Color(0.45, 0.3, 0.15))
                        draw_rect(Rect2(-1.0, 0.0 + y_off, 2.0, 4.0), Color(1.0, 0.85, 0.2))
                TreasureType.TRES_GEM:
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(0, -8.0 + y_off),
                                Vector2(7.0, 0.0 + y_off),
                                Vector2(0, 8.0 + y_off),
                                Vector2(-7.0, 0.0 + y_off)
                        ]), Color(0.3, 0.8, 1.0))
                TreasureType.TRES_CUP:
                        draw_rect(Rect2(-6.0, -6.0 + y_off, 12.0, 4.0), Color(1.0, 0.85, 0.2))
                        draw_rect(Rect2(-4.0, -2.0 + y_off, 8.0, 4.0), Color(1.0, 0.85, 0.2))
                        draw_rect(Rect2(-1.5, 2.0 + y_off, 3.0, 6.0), Color(1.0, 0.85, 0.2))
                        draw_rect(Rect2(-4.0, 8.0 + y_off, 8.0, 2.0), Color(1.0, 0.85, 0.2))


func _draw_exit_door() -> void:
        # Port 1:1 di Game::drawExitDoor (C++ righe 5440-5597).
        # Porta di uscita che appare dopo aver raccolto tutti i tesori.
        # Strati (dal basso verso l'alto):
        #   1. Aura luminosa pulsante dorata (2 cerchi)
        #   2. Architrave (40x6) + simbolo dorato (cerchio r=3)
        #   3. 2 stipiti laterali (4x40 ciascuno)
        #   4. 12 bande verticali gradiente (profondita' buio, da scuro a chiaro)
        #   5. 6 gradini scala con prospettiva (largo+chiaro -> stretto+scuro)
        #   6. Bagliore profondo + scintilla (in fondo alla scala)
        #   7. Anta animata che si apre (si restringe verso destra)
        #      - Venature del legno (3 strisce verticali)
        #      - Maniglia (visibile quando anta quasi chiusa)
        # (dx, dy) e' il centro della porta. La porta e' verticale, alta ~46px.
        var dx := 0.0
        var dy := 0.0
        # --- Aura luminosa pulsante dorata (2 cerchi) ---
        var pulse_factor: float = 1.0 + door_glow_pulse * 0.15
        var aura_r: float = 32.0 * pulse_factor
        draw_circle(Vector2(dx, dy), aura_r, Color(1.0, 0.78, 0.31, 50.0 / 255.0))
        draw_circle(Vector2(dx, dy), aura_r * 0.6, Color(1.0, 0.86, 0.39, 80.0 / 255.0))
        # --- Architrave (rettangolo orizzontale 40x6 sopra la porta) ---
        draw_rect(Rect2(dx - 20.0, dy - 22.0, 40.0, 6.0), Color(0.471, 0.392, 0.314), true)
        draw_rect(Rect2(dx - 20.0, dy - 22.0, 40.0, 6.0), Color(0.196, 0.157, 0.118), false, 1.0)
        # Decorazione architrave (simbolo dorato, cerchio r=3)
        draw_circle(Vector2(dx, dy - 20.0), 3.0, Color(0.784, 0.627, 0.235))
        draw_circle(Vector2(dx, dy - 20.0), 3.0, Color(0.392, 0.314, 0.118), false, 0.8)
        # --- 2 stipiti laterali (4x40 ciascuno) ---
        # Stipite sinistro.
        draw_rect(Rect2(dx - 20.0, dy - 16.0, 4.0, 40.0), Color(0.392, 0.333, 0.255), true)
        draw_rect(Rect2(dx - 20.0, dy - 16.0, 4.0, 40.0), Color(0.157, 0.137, 0.098), false, 0.8)
        # Stipite destro.
        draw_rect(Rect2(dx + 16.0, dy - 16.0, 4.0, 40.0), Color(0.392, 0.333, 0.255), true)
        draw_rect(Rect2(dx + 16.0, dy - 16.0, 4.0, 40.0), Color(0.157, 0.137, 0.098), false, 0.8)
        # --- Interna della porta (12 bande verticali gradiente) ---
        # Buio piu' intenso in alto (dove la scala sparisce), piu' chiaro in basso.
        var door_h: float = 36.0
        for i in range(12):
                var t: float = float(i) / 11.0
                var y0: float = dy - 14.0 + t * door_h
                var band_h: float = door_h / 12.0 + 1.0
                var dark_r: float = 2.0 + t * 18.0  # 2 -> 20
                var dark_g: float = 2.0 + t * 12.0  # 2 -> 14
                var dark_b: float = 1.0 + t * 7.0    # 1 -> 8
                draw_rect(Rect2(dx - 16.0, y0, 32.0, band_h),
                        Color(dark_r / 255.0, dark_g / 255.0, dark_b / 255.0), true)
        # --- 6 gradini della scala con prospettiva ---
        # Primo gradino in basso (largo + chiaro), ultimo in alto (stretto + scuro).
        var num_steps: int = 6
        var bot_step_y: float = dy + 16.0
        var step_spacing: float = 5.0
        var bot_step_w: float = 30.0
        var top_step_w: float = 14.0
        for i in range(num_steps):
                var t: float = float(i) / float(num_steps - 1)
                var step_y: float = bot_step_y - float(i) * step_spacing
                var step_w: float = bot_step_w - (bot_step_w - top_step_w) * t
                # Colore: piu' scuro andando verso l'alto (profondita').
                var sr: float = 100.0 - t * 70.0   # 100 -> 30
                var sg: float = 82.0 - t * 58.0    # 82 -> 24
                var sb: float = 64.0 - t * 46.0    # 64 -> 18
                # Gradino: rettangolo orizzontale (pianerottolo).
                draw_rect(Rect2(dx - step_w / 2.0, step_y, step_w, 3.0),
                        Color(sr / 255.0, sg / 255.0, sb / 255.0), true)
                draw_rect(Rect2(dx - step_w / 2.0, step_y, step_w, 3.0),
                        Color(sr / 510.0, sg / 510.0, sb / 510.0), false, 0.6)
                # Alzata del gradino (parte verticale scura SOPRA il pianerottolo).
                if i < num_steps - 1:
                        var riser_h: float = step_spacing - 3.0
                        draw_rect(Rect2(dx - step_w / 2.0, step_y - riser_h, step_w, riser_h),
                                Color(sr * 0.4 / 255.0, sg * 0.4 / 255.0, sb * 0.4 / 255.0), true)
                # Highlight sul bordo superiore del gradino (riflesso luce).
                draw_rect(Rect2(dx - (step_w - 2.0) / 2.0, step_y, step_w - 2.0, 0.8),
                        Color(minf(sr + 40.0, 255.0) / 255.0,
                                minf(sg + 35.0, 255.0) / 255.0,
                                minf(sb + 30.0, 255.0) / 255.0, 200.0 / 255.0), true)
        # --- Bagliore profondo in fondo alla scala + scintilla ---
        var glow_y: float = bot_step_y - float(num_steps - 1) * step_spacing - 2.0
        var glow_pulse2: float = sin(anim_time * 2.0) * 0.3 + 0.7
        draw_circle(Vector2(dx, glow_y), 4.0 * glow_pulse2,
                Color(0.784, 0.627, 0.235, 120.0 / 255.0))
        draw_circle(Vector2(dx, glow_y), 1.5 * glow_pulse2,
                Color(1.0, 0.902, 0.471, 200.0 / 255.0))
        # --- Anta della porta (animazione di apertura verso destra) ---
        # openProgress = 1 - animTimer/800 (0 all'inizio, 1 quando aperta).
        # doorWidth = 32 * (1 - openProgress) = 32 * (animTimer/800).
        var open_progress: float = 1.0 - float(door_anim_timer_ms) / 800.0
        open_progress = clampf(open_progress, 0.0, 1.0)
        var door_width: float = 32.0 * (1.0 - open_progress)
        if door_width > 0.5:
                # Pannello della porta (legno scuro).
                draw_rect(Rect2(dx - 16.0, dy - 14.0, door_width, 36.0),
                        Color(0.353, 0.235, 0.098), true)
                draw_rect(Rect2(dx - 16.0, dy - 14.0, door_width, 36.0),
                        Color(0.157, 0.098, 0.039), false, 1.0)
                # Venature del legno (3 strisce verticali).
                for i in range(3):
                        if door_width > 4.0 + float(i) * 6.0:
                                draw_rect(Rect2(dx - 14.0 + float(i) * 6.0, dy - 12.0, 1.0, 30.0),
                                        Color(0.235, 0.137, 0.059), true)
                # Maniglia (appare quando la porta e' quasi chiusa).
                if open_progress < 0.3:
                        draw_circle(Vector2(dx + 8.0, dy + 1.0), 1.5, Color(0.863, 0.706, 0.235))
                        draw_circle(Vector2(dx + 8.0, dy + 1.0), 1.5,
                                Color(0.392, 0.275, 0.078), false, 0.4)


func _draw_magic_portal() -> void:
        # Port 1:1 di Game::drawMagicPortal (C++ righe 5353-5432).
        # Portale magico che respawna i nemici. Strati:
        #   1. 3 aure pulsanti (viola-blu, grande -> piccola, da 55 a 22 px)
        #   2. 4 anelli concentrici rotanti (16, 24, 32, 40 px di raggio;
        #      colori 240, 200, 160, 120 alpha da interno a esterno)
        #   3. 12 particelle spirale rotanti (raggio variabile con sin)
        #   4. Centro nero profondo (viola scuro, r=12)
        #   5. Bagliore centrale phase-dependent (3 fasi: open/spawn/close)
        # (px, py) e' il centro del portale. Usa rotation_deg per la rotazione.
        var px := 0.0
        var py := 0.0
        var rot: float = deg_to_rad(rotation_deg)
        var portal_pulse: float = 1.0 + sin(anim_time * 4.0) * 0.2
        # --- 3 aure pulsanti (viola-blu, grande -> piccola) ---
        var aura_r: float = 55.0 * portal_pulse
        draw_circle(Vector2(px, py), aura_r, Color(120.0 / 255.0, 60.0 / 255.0, 220.0 / 255.0, 40.0 / 255.0))
        draw_circle(Vector2(px, py), aura_r * 0.65,
                Color(160.0 / 255.0, 80.0 / 255.0, 240.0 / 255.0, 60.0 / 255.0))
        draw_circle(Vector2(px, py), aura_r * 0.4,
                Color(200.0 / 255.0, 100.0 / 255.0, 255.0 / 255.0, 80.0 / 255.0))
        # --- 4 anelli concentrici rotanti (16, 24, 32, 40 px di raggio) ---
        # Colori 240->120 alpha da interno a esterno; spessore 3->1.5.
        var ring_colors: Array[Color] = [
                Color(220.0 / 255.0, 120.0 / 255.0, 255.0 / 255.0, 240.0 / 255.0),
                Color(180.0 / 255.0, 90.0 / 255.0, 240.0 / 255.0, 200.0 / 255.0),
                Color(140.0 / 255.0, 70.0 / 255.0, 210.0 / 255.0, 160.0 / 255.0),
                Color(100.0 / 255.0, 50.0 / 255.0, 180.0 / 255.0, 120.0 / 255.0),
        ]
        var ring_widths: Array[float] = [3.0, 2.5, 2.0, 1.5]
        for ring in range(4):
                var ring_r: float = (16.0 + float(ring) * 8.0) * portal_pulse
                # Godot draw_circle non ha outline; uso draw_arc per gli anelli.
                draw_arc(Vector2(px, py), ring_r, 0.0, TAU, 48,
                        ring_colors[ring], ring_widths[ring])
        # --- 12 particelle spirale rotanti ---
        for i in range(12):
                var a: float = rot * 2.0 + float(i) * PI / 6.0
                var r: float = 14.0 + sin(rot + float(i)) * 8.0
                var sx_p: float = px + cos(a) * r
                var sy_p: float = py + sin(a) * r
                var spark_size: float = 2.5 + sin(rot * 3.0 + float(i)) * 1.0
                draw_circle(Vector2(sx_p, sy_p), spark_size,
                        Color(230.0 / 255.0, 160.0 / 255.0, 255.0 / 255.0, 220.0 / 255.0))
        # --- Centro del portale (nero/viola profondo, r=12) ---
        draw_circle(Vector2(px, py), 12.0, Color(15.0 / 255.0, 5.0 / 255.0, 25.0 / 255.0, 220.0 / 255.0))
        # --- Bagliore centrale phase-dependent (3 fasi) ---
        if portal_phase == 0:
                # Apertura: bagliore crescente.
                var open_t: float = 1.0 - float(portal_phase_timer_ms) / 1000.0
                var glow_r: float = 6.0 + open_t * 12.0
                draw_circle(Vector2(px, py), glow_r,
                        Color(200.0 / 255.0, 100.0 / 255.0, 255.0 / 255.0, 180.0 * open_t / 255.0))
        elif portal_phase == 1:
                # Spawn: bagliore intenso costante.
                draw_circle(Vector2(px, py), 10.0,
                        Color(255.0 / 255.0, 150.0 / 255.0, 255.0 / 255.0, 180.0 / 255.0))
        elif portal_phase == 2:
                # Chiusura: bagliore decrescente.
                var close_t: float = float(portal_phase_timer_ms) / 800.0
                var glow_r: float = 4.0 + close_t * 6.0
                draw_circle(Vector2(px, py), glow_r,
                        Color(150.0 / 255.0, 80.0 / 255.0, 200.0 / 255.0, 120.0 * close_t / 255.0))


# =========================================================
# Static helpers
# =========================================================

## Factory: create a treasure of given kind at pos.
static func make_treasure(t: int, at: Vector2) -> Collectibles:
        var c := Collectibles.new()
        c.kind = Kind.TREASURE
        c.treasure_type = t
        c.pos = at
        return c


## Factory: create a mine at pos.
static func make_mine(at: Vector2, in_boss: bool = false) -> Collectibles:
        var c := Collectibles.new()
        c.kind = Kind.MINE
        c.pos = at
        c.in_boss_room = in_boss
        return c


## Factory: create a chalice at pos.
static func make_chalice(at: Vector2) -> Collectibles:
        var c := Collectibles.new()
        c.kind = Kind.CHALICE
        c.pos = at
        return c


## Factory: create a scepter at pos.
static func make_scepter(at: Vector2) -> Collectibles:
        var c := Collectibles.new()
        c.kind = Kind.SCEPTER
        c.pos = at
        c.lightnings_left = 5
        c.lightning_timer_ms = 3000
        return c


## Factory: create a speed-boots pickup at pos.
static func make_speed_boots(at: Vector2) -> Collectibles:
        var c := Collectibles.new()
        c.kind = Kind.SPEED_BOOTS
        c.pos = at
        return c


## Factory: create an exit door at pos.
static func make_exit_door(at: Vector2) -> Collectibles:
        var c := Collectibles.new()
        c.kind = Kind.EXIT_DOOR
        c.pos = at
        c.active = false  # activates when all treasures are collected
        return c


## Factory: create a magic portal at pos.
static func make_magic_portal(at: Vector2, enemies_count: int) -> Collectibles:
        var c := Collectibles.new()
        c.kind = Kind.MAGIC_PORTAL
        c.pos = at
        c.portal_enemies_to_spawn = enemies_count
        c.portal_phase = 0
        c.portal_phase_timer_ms = 1000  # 1s open animation
        c.portal_spawn_timer_ms = 0
        return c
