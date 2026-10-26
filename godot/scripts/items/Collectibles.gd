## Collectibles.gd - Maze items: mines, chalice, scepter, speed boots,
##                  treasures, exit door and magic portal.
## ============================================================
## Godot port of the items defined in `src/Game.h` (struct Mine,
## GoldenChalice, MagicScepter, SpeedBootsBonus, ExitDoor, MagicPortal)
## and the corresponding Cell.treasure / TreasureType from `src/Maze.h`.
##
## Each kind of item is a small Node2D with its own update/render logic.
## The Game scene instantiates them as needed and calls `update_step()`
## each frame. **Pickup collision is owned ENTIRELY by MainGameController**
## (`_update_collectibles`, radius dist^2 < 400), mirroring the single
## centralized check in the original C++ Game::update — the item itself
## must NOT self-collect (FIX: the old 16px self-check silently deactivated
## items with zero effects when the player jumped inside its radius in one
## frame, e.g. the stop-and-resume snap-to-cell-center teleport).
extends Node2D
class_name Collectibles

# Treasure kinds (mirror C++ enum TreasureType).
enum TreasureType { TRES_CROWN, TRES_GOLD, TRES_CHEST, TRES_GEM, TRES_RUBY }

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
        MEDIKIT,         # FIX (nuova meccanica): rigenera 1 punto vita del player (1 per livello).
        KNIGHT_STATUE,   # FIX (nuova meccanica): evoca cavaliere alleato che combatte per il player.
        DYNAMITE,        # FIX (nuova meccanica): candelotto di dinamite con miccia (1 per livello).
        POTION,          # FIX (pozione magica): ampolla di vetro con liquido verde — il player
                         # la beve e diventa evanescente come un fantasma per 5 secondi,
                         # attraversando i muri del labirinto.
        HAMMER,          # FIX (martello di Thor — nuova meccanica): Mjolnir da raccogliere
                         # nel labirinto. 2 lanci: infligge il 50% degli HP max ai nemici
                         # e spezza i muri INTERNI creando scorciatoie usabili da player e
                         # nemici. Dopo il secondo lancio scompare dal player.
        QUAKE_SCROLL,     # TASK 35 (pergamene evento): pergamena del TERREMOTO.
                         # Si attiva subito alla raccolta: -50% HP a TUTTI i nemici,
                         # chi resta sotto il 50% dell'energia max viene eliminato.
                         # Il player non subisce danni. Appare in un momento casuale
                         # (solo se i vivi sono >= 50%), telegrafo luminoso, 10s a
                         # terra + 2s di lampeggio poi scompare. Un solo uso.
        CHASM_SCROLL,     # TASK 35: pergamena delle VORAGINI MAGICHE. Alla raccolta
                         # fa apparire 4 voragini in celle casuali ben distanziate:
                         # i nemici che vi cadono sopra vengono uccisi, il player e'
                         # immune. 3 ontate da 4s con riposizionamento (12s totali).
                         # Stesse meccaniche di apparizione della pergamena terremoto.
        FREEZE_SCROLL,    # TASK 50 (pergamena del GHIACCIO): alla raccolta il
                         # player la EQUIPAGGIA — il tasto di fuoco spara un
                         # RAGGIO CONGELANTE (2 colpi). I nemici colpiti dal
                         # beam vengono congelati per tutto il livello: conta
                         # come uccisione one-shot ma lo sprite resta sul
                         # labirinto, fermo, dentro un blocco di ghiaccio
                         # trasparente che lascia vedere il mostro. Stesse
                         # meccaniche di apparizione delle altre pergamene.
}

@export var kind: int = Kind.TREASURE:
        set(v):
                kind = v
                _apply_kind_defaults()

@export var treasure_type: int = TreasureType.TRES_CROWN

# --- SCROLL (TASK 35) ---
# Tempo di vita residuo a terra (ms): 16s raccoglibile + 2s di
# lampeggio finale (TASK 41: totale 12s -> 18s, +50%). Gli ultimi
# SCROLL_BLINK_THRESHOLD_MS modulano l'alpha (lampeggio d'avviso).
# A zero: active = false (l'evento e' perso — il controller libera
# il nodo).
var scroll_lifetime_ms: float = 0.0
const SCROLL_BLINK_THRESHOLD_MS: float = 2000.0

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

# --- TASK 64 (alleato alternato per livello) ---
# Variante estetica della statuetta KNIGHT_STATUE: "unicorn" (livelli
# dispari, comportamento storico) o "knight" (livelli pari). Decisa da
# MainGameController alla creazione/restore in base alla parita' del
# livello, cosi' l'icona a terra e' sempre coerente con l'alleato che
# verra' evocato (item_unicorn_statue.png / item_knight_statue.png,
# entrambi PixelLab v2).
var statue_variant: String = "unicorn"

func _knight_statue_png() -> String:
        return "res://assets/sprites/collectibles/item_knight_statue.png" \
                        if statue_variant == "knight" \
                        else "res://assets/sprites/collectibles/item_unicorn_statue.png"

# --- MINE-specific ---
var bouncing: bool = false
var velocity: Vector2 = Vector2.ZERO
var bounce_timer_ms: int = 0
var homing_ms: int = 0  # FIX (bomba homing): timer per BFS homing verso nemico più vicino
# TASK 50 (mina si incastra nei muri): path-following continuo — percorso
# BFS completo (waypoint in celle) + indice del waypoint inseguito.
var path_cells: Array = []
var path_idx: int = 0
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

# NOTE (TASK 69, pulizia codice morto): rimosso il port C++ del portale
# magico (Kind.MAGIC_PORTAL + make_magic_portal + _update_portal +
# _draw_magic_portal + vars portal_*): mai istanziato in gioco — il portale
# REALE è gestito interamente da MainGameController (magic_portal: Dictionary
# + _draw_portal_into via Maze.portal_draw_callback, Task 68).

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
                Kind.MEDIKIT:
                        pulse = 0.0
                        bob_offset = 0.0
                Kind.KNIGHT_STATUE:
                        pulse = 0.0
                        bob_offset = 0.0
                Kind.DYNAMITE:
                        pulse = 0.0
                        bob_offset = 0.0
                Kind.POTION:
                        pulse = 0.0
                        bob_offset = 0.0
                Kind.HAMMER:
                        pulse = 0.0
                        bob_offset = 0.0
                Kind.QUAKE_SCROLL:
                        pulse = 0.0
                        bob_offset = 0.0
                        # NB: scroll_lifetime_ms NON si tocca qui: e' stato
                        # runtime impostato dal controller PRIMA dell'add_child,
                        # e _ready() chiama _apply_kind_defaults() DOPO
                        # (azzerarlo qui cancellava il countdown di vita.
                        # Parte comunque a 0.0 per default di istanza.)
                Kind.CHASM_SCROLL:
                        pulse = 0.0
                        bob_offset = 0.0
                Kind.FREEZE_SCROLL:
                        pulse = 0.0
                        bob_offset = 0.0
                        # NB: come le altre pergamene, scroll_lifetime_ms e'
                        # impostato dal controller PRIMA dell'add_child.


# =========================================================
# Update step (delta_ms ≈ 16ms per frame at 60fps)
# =========================================================
# `player_pos` is kept for API compatibility (unused: no self-collision —
# the controller owns pickup detection). Set by the Game. For 2P, call
# twice (once per player).
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
                Kind.MEDIKIT:
                        pass  # only anim
                Kind.KNIGHT_STATUE:
                        pass  # only anim
                Kind.DYNAMITE:
                        pass  # only anim
                Kind.HAMMER:
                        pass  # only anim (bob + aura elettrica nel _draw)
                Kind.QUAKE_SCROLL:
                        _update_scroll_lifetime(delta_ms)
                Kind.CHASM_SCROLL:
                        _update_scroll_lifetime(delta_ms)
                Kind.FREEZE_SCROLL:
                        _update_scroll_lifetime(delta_ms)

        # FIX (calice non raccoglibile): RIMOSSA la self-collision a 16px.
        # Era un duplicato più piccolo del check del controller (20px) che
        # girava PRIMA di esso: se il player entrava nel raggio 16px in un
        # solo frame (es. snap al centro cella da fermo, riga 477 di
        # Player.gd, o qualunque teletrasporto), l'item si disattivava qui
        # con ZERO effetti (il segnale `collected` non è connesso a nulla!)
        # e il controller saltava il pickup per via del `if not active:
        # continue`. Il calice spariva senza invincibilità, punteggio o
        # suono. Il controller è l'unica autorità di pickup, come nel C++
        # originale (Game.cpp: dist^2 < 500 in un unico punto).


# =========================================================
# Per-kind update helpers
# =========================================================

func _update_mine(delta_ms: int) -> void:
        if bouncing:
                # FIX (bomba arcade): rimossa la gravità e la friction sul
                # pavimento. Movimento arcade puro tipo Bomberman: velocità
                # costante, rimbalza sui muri del maze (wall check gestito in
                # MainGameController._check_mine_vs_enemies).
                rotation_deg += 8.0  # rotazione più veloce (era 6.0)
                if bounce_timer_ms > delta_ms:
                        bounce_timer_ms -= delta_ms
                else:
                        # FIX (bomba esplode quando finisce): quando finisce di
                        # rimbalzare senza colpire nessuno, esplode e sparisce
                        # dal labirinto.
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


# =========================================================
# Public API for the Game to configure items
# =========================================================

# --- MINE ---
# FIX (bomba a ricerca): durata 10000ms -> 7000ms (7s come richiesto da utente)
func start_bounce(initial_vel: Vector2, duration_ms: int = 7000) -> void:
        bouncing = true
        velocity = initial_vel
        bounce_timer_ms = duration_ms
        homing_ms = 0  # ricalcola subito il path BFS al primo frame

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
# Rendering
# =========================================================
func _draw() -> void:
        if not active:
                if kind == Kind.EXIT_DOOR:
                        # Door stays visible briefly during its open animation.
                        if door_anim_timer_ms > 0:
                                _draw_exit_door()
                # FIX (statua invisibile): la statua del cavaliere deve essere
                # visibile anche durante il delay di spawn (5-15s), altrimenti
                # il player la raccoglie senza vederla. Disegna un "ghost"
                # semitrasparente della statua.
                elif kind == Kind.KNIGHT_STATUE:
                        _draw_knight_statue_ghost()
                return
        match kind:
                Kind.MINE:         _draw_mine()
                Kind.CHALICE:      _draw_chalice()
                Kind.SCEPTER:      _draw_scepter()
                Kind.SPEED_BOOTS:  _draw_speed_boots()
                Kind.TREASURE:     _draw_treasure()
                Kind.EXIT_DOOR:    _draw_exit_door()
                Kind.MEDIKIT:      _draw_medikit()
                Kind.KNIGHT_STATUE: _draw_knight_statue()
                Kind.DYNAMITE:     _draw_dynamite()
                Kind.POTION:       _draw_potion()
                Kind.HAMMER:       _draw_hammer()
                Kind.QUAKE_SCROLL: _draw_parchment(
                                "res://assets/sprites/parchment/quake_scroll.png",
                                Color(1.0, 0.55, 0.2))
                Kind.CHASM_SCROLL: _draw_parchment(
                                "res://assets/sprites/parchment/chasm_scroll.png",
                                Color(0.7, 0.45, 1.0))
                Kind.FREEZE_SCROLL: _draw_parchment(
                                "res://assets/sprites/parchment/freeze_scroll.png",
                                Color(0.35, 0.8, 1.0))


func _draw_mine() -> void:
        var y_off := -bob_offset
        # FIX: usa PNG AI dedicato invece di disegno procedurale
        var tex := _load_png_cached("res://assets/sprites/collectibles/item_mine.png")
        if tex != null:
                draw_circle(Vector2.ZERO, 10.0, Color(0.8, 0.2, 0.1, 0.10))
                var size: float = 64.0
                draw_texture_rect(tex, Rect2(-size / 2.0, -size / 2.0 + y_off, size, size), false)
                return
        # Fallback procedurale (solo se PNG non disponibile)
        var scale_factor: float = 1.5
        var r := (10.0 + pulse * 1.5) * scale_factor
        var col := Color(0.7, 0.6, 0.3)
        var dark := Color(0.2, 0.2, 0.2)
        var aura_pulse: float = sin(anim_time * 5.0) * 0.2 + 1.0
        var aura_r: float = 14.0 * aura_pulse
        draw_circle(Vector2.ZERO, aura_r,
                Color(200.0 / 255.0, 50.0 / 255.0, 20.0 / 255.0, 50.0 / 255.0))
        draw_circle(Vector2.ZERO, r, col)
        draw_circle(Vector2.ZERO, r, dark, false, 1.5)
        for i in range(8):
                var a := (float(i) / 8.0) * TAU + deg_to_rad(rotation_deg)
                var tip := Vector2(cos(a), sin(a)) * (r + 4.0 * scale_factor)
                var base_l := Vector2(cos(a + 0.3), sin(a + 0.3)) * r
                var base_r := Vector2(cos(a - 0.3), sin(a - 0.3)) * r
                draw_colored_polygon(PackedVector2Array([tip, base_l, base_r]), dark)
        if fmod(anim_time, 1.0) > 0.5:
                draw_circle(Vector2.ZERO, 2.0 * scale_factor, Color(1.0, 0.2, 0.2))


func _draw_chalice() -> void:
        var y_off := -bob_offset
        # FIX: usa PNG AI dedicato invece di disegno procedurale
        var tex := _load_png_cached("res://assets/sprites/collectibles/item_chalice.png")
        if tex != null:
                draw_circle(Vector2.ZERO, 10.0, Color(1.0, 0.85, 0.2, 0.10))
                var size: float = 64.0
                draw_texture_rect(tex, Rect2(-size / 2.0, -size / 2.0 + y_off, size, size), false)
                return
        # Fallback procedurale
        var scale_factor: float = 1.5
        var aura_r := (14.0 + pulse * 2.0)
        draw_circle(Vector2.ZERO - Vector2(0, bob_offset), aura_r,
                                Color(1.0, 0.85, 0.2, 0.10))
        var gold := Color(1.0, 0.85, 0.2)
        var gold_dark := Color(0.7, 0.55, 0.1)
        var y_off2 := -bob_offset
        var top := Rect2(-8.0 * scale_factor, -10.0 * scale_factor + y_off2,
                         16.0 * scale_factor, 4.0 * scale_factor)
        var body := Rect2(-6.0 * scale_factor, -6.0 * scale_factor + y_off2,
                          12.0 * scale_factor, 10.0 * scale_factor)
        var base := Rect2(-3.0 * scale_factor, 4.0 * scale_factor + y_off2,
                          6.0 * scale_factor, 4.0 * scale_factor)
        draw_rect(top, gold)
        draw_rect(body, gold)
        draw_rect(base, gold_dark)
        draw_rect(Rect2(-1.5 * scale_factor, -2.0 * scale_factor + y_off2,
                        3.0 * scale_factor, 6.0 * scale_factor), gold)
        draw_rect(Rect2(-5.0 * scale_factor, -5.0 * scale_factor + y_off2,
                        2.0 * scale_factor, 4.0 * scale_factor),
                  Color(1.0, 1.0, 0.7))
        draw_rect(top, gold_dark, false, 1.5)
        draw_rect(body, gold_dark, false, 1.5)


func _draw_scepter() -> void:
        var y_off := -bob_offset
        # FIX: usa PNG AI dedicato invece di disegno procedurale
        var tex := _load_png_cached("res://assets/sprites/collectibles/item_scepter.png")
        if tex != null:
                draw_circle(Vector2.ZERO, 10.0, Color(0.3, 0.6, 1.0, 0.10))
                var size: float = 64.0
                draw_texture_rect(tex, Rect2(-size / 2.0, -size / 2.0 + y_off, size, size), false)
                return
        # Fallback procedurale (codice originale sotto)
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
        # FIX: y_off già dichiarato all'inizio della funzione, non ridichiarare
        var sx := 0.0
        var sy := y_off
        var s_pulse := 1.0 + pulse * 0.2  # fattore di pulsazione (>1 = piu' grande)
        # FIX (scepter troppo piccolo): applica uno scale 2.0 a tutto il
        # drawing del scepter usando draw_set_transform. Così tutti i calcoli
        # esistenti (sx, sy, posizioni, dimensioni) vengono ingranditi.
        draw_set_transform(Vector2.ZERO, 0.0, Vector2(2.0, 2.0))
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
        # Reset transform (riporta a 1:1 per i disegni successivi)
        draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 1.0))


func _draw_speed_boots() -> void:
        var y_off := -bob_offset
        # FIX: usa PNG AI dedicato invece di sprite bonus_speedboots
        var tex := _load_png_cached("res://assets/sprites/collectibles/item_speedboots.png")
        if tex != null:
                draw_circle(Vector2.ZERO, 8.0, Color(1.0, 0.85, 0.2, 0.10))
                var size: float = 64.0
                draw_texture_rect(tex, Rect2(-size / 2.0, -size / 2.0 + y_off, size, size), false)
                return
        # Fallback: usa sprite AI bonus_speedboots da SpriteManager
        draw_circle(Vector2.ZERO, 8.0, Color(1.0, 0.85, 0.2, 0.10))
        if SpriteManager:
                var sheet = SpriteManager.get_sheet("bonus_speedboots")
                if sheet != null and sheet.is_loaded():
                        var at: AtlasTexture = sheet.get_frame_texture("idle", 0)
                        if at != null:
                                var size: float = 64.0
                                draw_texture_rect(at, Rect2(-size / 2.0, -size / 2.0 + y_off, size, size), false)
                                return
        # Fallback 2: procedurale
        draw_rect(Rect2(-6.0, 0.0 + y_off, 10.0, 6.0), Color(0.4, 0.3, 0.2))
        draw_rect(Rect2(-6.0, -6.0 + y_off, 6.0, 8.0), Color(0.4, 0.3, 0.2))
        draw_colored_polygon(PackedVector2Array([
                Vector2(2.0, -4.0 + y_off),
                Vector2(10.0, -8.0 + y_off),
                Vector2(2.0, 0.0 + y_off)
        ]), Color(1.0, 1.0, 1.0, 0.9))


# Cache delle texture PNG dei collectibles (evita load() ogni frame → lag).
# Usa Image.load() per bypassare il sistema di import di Godot.
static var _collectible_tex_cache: Dictionary = {}

# FIX (cache stale): pulisce la cache delle texture collectible. Chiamare
# all'inizio di ogni livello per forzare il ricaricamento dei PNG.
static func clear_texture_cache() -> void:
        _collectible_tex_cache.clear()

# Carica una texture PNG dal disco usando Image.load() (bypassa import).
# Ritorna null se il file non esiste o non può essere caricato.
static func _load_png_cached(path: String) -> Texture2D:
        if _collectible_tex_cache.has(path):
                return _collectible_tex_cache[path]
        var abs_path: String = ProjectSettings.globalize_path(path)
        if not FileAccess.file_exists(abs_path):
                return null
        var img := Image.new()
        if img.load(abs_path) == OK:
                var tex := ImageTexture.create_from_image(img)
                if tex != null:
                        _collectible_tex_cache[path] = tex
                        return tex
        return null

func _draw_treasure() -> void:
        var y_off := -bob_offset
        # Glow dorato ridotto
        draw_circle(Vector2.ZERO, 10.0, Color(1.0, 0.85, 0.3, 0.10))
        # Carica la texture PNG dedicata per questo tipo di tesoro (cached)
        var tex_path: String = ""
        match treasure_type:
                TreasureType.TRES_CROWN: tex_path = "res://assets/sprites/treasures/treasure_crown.png"
                TreasureType.TRES_GOLD: tex_path = "res://assets/sprites/treasures/treasure_gold.png"
                TreasureType.TRES_CHEST: tex_path = "res://assets/sprites/treasures/treasure_chest.png"
                TreasureType.TRES_GEM: tex_path = "res://assets/sprites/treasures/treasure_gem.png"
                TreasureType.TRES_RUBY: tex_path = "res://assets/sprites/treasures/treasure_ruby.png"
        if not tex_path.is_empty():
                var tex: Texture2D = _load_png_cached(tex_path)
                if tex != null:
                        # FIX (dimensione tesori, richiesta utente "poco più
                        # piccole"): 64 -> 52 -> 48px. Allineato ai tesori del
                        # maze (73.6px netti su cella 64): il collectible è la
                        # versione da raccogliere a schermo, il maze disegna il
                        # tesoro "padre". Contenuto visivo ~43px su cella 64.
                        var size: float = 48.0
                        var draw_rect := Rect2(-size / 2.0, -size / 2.0 + y_off, size, size)
                        draw_texture_rect(tex, draw_rect, false)
                        return
        # Fallback: rendering procedurale MIGLIORATO (più riconoscibile)
        # FIX (pallino giallo non riconoscibile): il fallback precedente
        # era solo un piccolo rettangolo giallo. Ora usa forme distinte per
        # ogni tipo di tesoro, con colori vivaci e contorni.
        var y_off2 := -bob_offset
        match treasure_type:
                TreasureType.TRES_CROWN:
                        # Corona d'oro con 3 punte + gemme rosse
                        var gold := Color(1.0, 0.85, 0.2)
                        var red := Color(0.9, 0.1, 0.1)
                        draw_rect(Rect2(-10.0, 2.0 + y_off2, 20.0, 6.0), gold)
                        for i in range(3):
                                var x := -8.0 + float(i) * 8.0
                                draw_colored_polygon(PackedVector2Array([
                                        Vector2(x, 2.0 + y_off2),
                                        Vector2(x + 5.0, 2.0 + y_off2),
                                        Vector2(x + 2.5, -6.0 + y_off2)
                                ]), gold)
                        # Gemme rosse sulle punte
                        for i in range(3):
                                var x := -6.0 + float(i) * 8.0
                                draw_circle(Vector2(x, -4.0 + y_off2), 2.0, red)
                TreasureType.TRES_GOLD:
                        # Pila di monete d'oro (3 cerchi)
                        var gold := Color(1.0, 0.85, 0.2)
                        var gold_dark := Color(0.8, 0.65, 0.1)
                        draw_circle(Vector2(0, 4.0 + y_off2), 6.0, gold_dark)
                        draw_circle(Vector2(-2, 0.0 + y_off2), 6.0, gold)
                        draw_circle(Vector2(2, -4.0 + y_off2), 5.0, gold)
                        # Simbolo $ sulle monete
                        draw_circle(Vector2(0, 0.0 + y_off2), 2.0, gold_dark)
                TreasureType.TRES_CHEST:
                        # Forziere di legno con cerniere d'oro
                        var wood := Color(0.55, 0.35, 0.15)
                        var wood_dark := Color(0.4, 0.25, 0.1)
                        var gold := Color(1.0, 0.85, 0.2)
                        draw_rect(Rect2(-10.0, -2.0 + y_off2, 20.0, 12.0), wood)
                        draw_rect(Rect2(-10.0, -6.0 + y_off2, 20.0, 5.0), wood_dark)
                        # Cerniere d'oro
                        draw_rect(Rect2(-10.0, -2.0 + y_off2, 3.0, 12.0), gold)
                        draw_rect(Rect2(7.0, -2.0 + y_off2, 3.0, 12.0), gold)
                        # Lucchetto
                        draw_rect(Rect2(-2.0, 1.0 + y_off2, 4.0, 5.0), gold)
                TreasureType.TRES_GEM:
                        # Gemma blu sfaccettata (diamante)
                        var gem := Color(0.3, 0.8, 1.0)
                        var gem_dark := Color(0.15, 0.5, 0.8)
                        var gem_light := Color(0.6, 0.95, 1.0)
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(0, -10.0 + y_off2),
                                Vector2(8.0, 0.0 + y_off2),
                                Vector2(0, 10.0 + y_off2),
                                Vector2(-8.0, 0.0 + y_off2)
                        ]), gem)
                        # Facette interne
                        draw_line(Vector2(0, -10.0 + y_off2), Vector2(0, 10.0 + y_off2), gem_dark, 1.0)
                        draw_line(Vector2(-8.0, 0.0 + y_off2), Vector2(8.0, 0.0 + y_off2), gem_dark, 1.0)
                        # Highlight
                        draw_circle(Vector2(-3.0, -3.0 + y_off2), 2.0, gem_light)
                TreasureType.TRES_RUBY:
                        # TASK 65c: rubino (prima calice d'oro) — silhouette
                        # a punta con facet, coerente col PNG PixelLab
                        var ruby := Color(0.85, 0.1, 0.2)
                        var ruby_dark := Color(0.5, 0.03, 0.1)
                        var ruby_light := Color(1.0, 0.5, 0.55)
                        # Corpo gemma: corona larga + padiglione a punta
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(-9.0, -6.0 + y_off2),
                                Vector2(9.0, -6.0 + y_off2),
                                Vector2(0.0, 10.0 + y_off2)
                        ]), ruby)
                        # Tavola superiore (corona)
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(-5.0, -9.0 + y_off2),
                                Vector2(5.0, -9.0 + y_off2),
                                Vector2(9.0, -6.0 + y_off2),
                                Vector2(-9.0, -6.0 + y_off2)
                        ]), ruby_dark)
                        # Facette interne
                        draw_line(Vector2(-9.0, -6.0 + y_off2), Vector2(0.0, 10.0 + y_off2), ruby_dark, 1.0)
                        draw_line(Vector2(9.0, -6.0 + y_off2), Vector2(0.0, 10.0 + y_off2), ruby_dark, 1.0)
                        # Highlight
                        draw_circle(Vector2(-3.0, -5.0 + y_off2), 2.0, ruby_light)


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


## Factory: create a medikit at pos.
static func make_medikit(at: Vector2) -> Collectibles:
        var c := Collectibles.new()
        c.kind = Kind.MEDIKIT
        c.pos = at
        c.active = true
        return c


## Factory: create a knight statue at pos.
static func make_knight_statue(at: Vector2) -> Collectibles:
        var c := Collectibles.new()
        c.kind = Kind.KNIGHT_STATUE
        c.pos = at
        c.active = true
        return c


## Factory: create a dynamite at pos.
static func make_dynamite(at: Vector2) -> Collectibles:
        var c := Collectibles.new()
        c.kind = Kind.DYNAMITE
        c.pos = at
        c.active = true
        return c


## FIX (pozione magica): Factory — crea una pozione magica (ampolla di vetro
## con liquido verde) alla posizione indicata.
static func make_potion(at: Vector2) -> Collectibles:
        var c := Collectibles.new()
        c.kind = Kind.POTION
        c.pos = at
        c.active = true
        return c


# FIX (nuova meccanica): disegna il medikit (scatola bianca con croce rossa).
# Carica il PNG AI dedicato; fallback procedurale se non disponibile.
# FIX (medikit "sopra un muro" — segnalazione utente, Task 62): il
# PIAZZAMENTO e' corretto (test test_medikit_reach: 48 seed x livello, il
# medikit nasce sempre su cella CellType.EMPTY e BFS-reraggiungibile dallo
# spawn), ma lo sprite PNG grigio-scuro disegnato a 64px (cella PIENA) si
# fondeva con la roccia dei muri nelle palette scure: a colpo d'occhio
# sembrava incastonato IN un muro. Tre misure di leggibilita':
#   1) size 64 -> 48px (come tesori/pergamene): margine di pavimento visibile
#      attorno alla scatola -> l'oggetto si legge "appoggiato", non "incassato";
#   2) ombra ellittica a terra sotto la scatola: ancora l'item alla cella;
#   3) doppio alone: bianco caldo ampio (schiarisce il pavimento attorno e
#      stacca dal buio dei muri) + rosso pulsante interno (identita' medikit).
func _draw_medikit() -> void:
        var y_off := -bob_offset
        var tex := _load_png_cached("res://assets/sprites/collectibles/item_medikit.png")
        if tex != null:
                var size: float = 48.0
                # (2) ombra ellittica a terra (pattern del martello)
                draw_set_transform(Vector2(1.5, 14.0), 0.0, Vector2(1.0, 0.42))
                draw_circle(Vector2.ZERO, 15.0, Color(0.0, 0.0, 0.0, 0.32))
                draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
                # (3a) alone bianco caldo che rischiara il pavimento attorno
                var glow_w: float = 0.26 + pulse * 0.10
                draw_circle(Vector2.ZERO, 25.0, Color(1.0, 0.95, 0.88, glow_w))
                draw_circle(Vector2.ZERO, 18.0, Color(1.0, 0.92, 0.86, glow_w * 0.85))
                # (3b) alone rosso pulsante interno
                var glow_alpha: float = 0.18 + pulse * 0.12
                draw_circle(Vector2.ZERO, 14.0, Color(1.0, 0.25, 0.25, glow_alpha))
                draw_texture_rect(tex, Rect2(-size / 2.0, -size / 2.0 + y_off, size, size), false)
                return
        # Fallback procedurale: scatola bianca + croce rossa
        var s: float = 24.0
        draw_rect(Rect2(-s / 2.0, -s / 2.0 + y_off, s, s),
                Color(0.95, 0.95, 0.95, 1.0), true)
        draw_rect(Rect2(-s / 2.0, -s / 2.0 + y_off, s, s),
                Color(0.7, 0.7, 0.7, 1.0), false, 1.0)
        # Croce rossa
        draw_rect(Rect2(-3.0, -s / 2.0 + 4.0 + y_off, 6.0, s - 8.0),
                Color(0.85, 0.15, 0.15, 1.0), true)
        draw_rect(Rect2(-s / 2.0 + 4.0, -3.0 + y_off, s - 8.0, 6.0),
                Color(0.85, 0.15, 0.15, 1.0), true)


# FIX (nuova meccanica): disegna la statua del cavaliere alleato.
# Carica il PNG AI dedicato; fallback procedurale se non disponibile.
func _draw_knight_statue() -> void:
        var y_off := -bob_offset
        # TASK 64: icona coerente con la variante dell'alleato del livello
        var tex := _load_png_cached(_knight_statue_png())
        if tex != null:
                # Aura mistica blu/ciano pulsante
                var glow_alpha: float = 0.20 + pulse * 0.15
                draw_circle(Vector2.ZERO, 20.0, Color(0.4, 0.7, 1.0, glow_alpha))
                draw_circle(Vector2.ZERO, 14.0, Color(0.6, 0.85, 1.0, glow_alpha * 0.7))
                var size: float = 64.0
                draw_texture_rect(tex, Rect2(-size / 2.0, -size / 2.0 + y_off, size, size), false)
                return
        # Fallback procedurale: statua grigia con ali
        var s2: float = 20.0
        # Aura
        draw_circle(Vector2.ZERO, 22.0, Color(0.4, 0.7, 1.0, 0.2 + pulse * 0.15))
        # Ali
        draw_polygon(PackedVector2Array([
                Vector2(-s2 - 4, y_off - 4), Vector2(-s2 - 12, y_off - 12),
                Vector2(-s2, y_off - 8)
        ]), PackedColorArray([Color(0.85, 0.85, 0.95, 0.8)]))
        draw_polygon(PackedVector2Array([
                Vector2(s2 + 4, y_off - 4), Vector2(s2 + 12, y_off - 12),
                Vector2(s2, y_off - 8)
        ]), PackedColorArray([Color(0.85, 0.85, 0.95, 0.8)]))
        # Corpo (armatura)
        draw_rect(Rect2(-s2 / 2.0, y_off - s2 / 2.0, s2, s2),
                Color(0.7, 0.7, 0.8, 1.0), true)
        # Elmo
        draw_circle(Vector2(0, y_off - s2 / 2.0 - 4), 6.0,
                Color(0.8, 0.8, 0.9, 1.0))
        # Croce dorata sul petto
        draw_rect(Rect2(-1.5, y_off - 4, 3.0, 8.0), Color(1.0, 0.85, 0.2, 1.0))
        draw_rect(Rect2(-4.0, y_off - 1.0, 8.0, 3.0), Color(1.0, 0.85, 0.2, 1.0))


# FIX (statua invisibile): disegna un "ghost" semitrasparente della statua
# del cavaliere quando è in fase di delay (active=false ma spawn_delay_ms > 0).
# Il player può così vedere dove apparirà la statua.
func _draw_knight_statue_ghost() -> void:
        var y_off := -bob_offset
        # TASK 64: il ghost della statua segue la stessa variante del livello
        var tex := _load_png_cached(_knight_statue_png())
        if tex != null:
                # Aura mistica pulsante
                var glow_alpha: float = 0.15 + pulse * 0.15
                draw_circle(Vector2.ZERO, 22.0, Color(0.4, 0.7, 1.0, glow_alpha))
                # Statua semitrasparente (ghost)
                var size: float = 64.0
                draw_texture_rect(tex, Rect2(-size / 2.0, -size / 2.0 + y_off, size, size), false,
                        Color(1, 1, 1, 0.4))
                return
        # Fallback: statua procedurale semitrasparente
        var s2: float = 20.0
        var ghost_col: Color = Color(0.6, 0.55, 0.5, 0.4)
        draw_circle(Vector2.ZERO, 22.0, Color(0.4, 0.7, 1.0, 0.2 + pulse * 0.15))
        draw_polygon(PackedVector2Array([
                Vector2(-s2 - 4, y_off - 4), Vector2(-s2 - 12, y_off - 12),
                Vector2(-s2, y_off - 8)
        ]), PackedColorArray([ghost_col]))
        draw_polygon(PackedVector2Array([
                Vector2(s2 + 4, y_off - 4), Vector2(s2 + 12, y_off - 12),
                Vector2(s2, y_off - 8)
        ]), PackedColorArray([ghost_col]))
        draw_rect(Rect2(-s2 / 2.0, y_off - s2 / 2.0, s2, s2), ghost_col, true)
        draw_circle(Vector2(0, y_off - s2 / 2.0 - 4), 6.0, ghost_col)


# FIX (nuova meccanica): disegna il candelotto di dinamite (pavimento).
# Carica il PNG AI dedicato; fallback procedurale se non disponibile.
func _draw_dynamite() -> void:
        var y_off := -bob_offset
        var tex := _load_png_cached("res://assets/sprites/collectibles/item_dynamite.png")
        if tex != null:
                # Glow rosso pulsante
                var glow_alpha: float = 0.15 + pulse * 0.10
                draw_circle(Vector2.ZERO, 18.0, Color(1.0, 0.3, 0.1, glow_alpha))
                var size: float = 64.0
                draw_texture_rect(tex, Rect2(-size / 2.0, -size / 2.0 + y_off, size, size), false)
                return
        # FIX (debug): se arriva qui, il PNG non è stato caricato
        print("[Dynamite] WARNING: PNG not loaded, using procedural fallback")
        # Fallback procedurale: CILINDRO ORIZZONTALE rosso (non verticale!)
        # FIX (estintore): prima era s×s*1.5 (verticale). Ora orizzontale.
        var cyl_w: float = 44.0  # larghezza (orizzontale)
        var cyl_h: float = 16.0  # altezza
        # Corpo cilindro rosso
        draw_rect(Rect2(-cyl_w / 2.0, -cyl_h / 2.0 + y_off, cyl_w, cyl_h),
                Color(0.78, 0.12, 0.1, 1.0), true)
        draw_rect(Rect2(-cyl_w / 2.0, -cyl_h / 2.0 + y_off, cyl_w, cyl_h),
                Color(0.45, 0.06, 0.05, 1.0), false, 1.0)
        # Highlight superiore
        draw_rect(Rect2(-cyl_w / 2.0 + 2, -cyl_h / 2.0 + y_off + 1, cyl_w - 4, 3),
                Color(0.95, 0.4, 0.3, 1.0), true)
        # Etichetta TNT (centro)
        draw_rect(Rect2(-6, -3 + y_off, 12, 6),
                Color(0.94, 0.86, 0.7, 1.0), true)
        # Miccia (esce da sinistra, curva in alto)
        draw_line(Vector2(-cyl_w / 2.0, -2 + y_off),
                Vector2(-cyl_w / 2.0 - 4, -8 + y_off),
                Color(0.16, 0.14, 0.12, 1.0), 2)
        draw_line(Vector2(-cyl_w / 2.0 - 4, -8 + y_off),
                Vector2(-cyl_w / 2.0 - 6, -14 + y_off),
                Color(0.16, 0.14, 0.12, 1.0), 2)


# FIX (pozione magica): disegna la pozione magica — ampolla di vetro con
# liquido verde brillante (quella tipica da laboratorio / pozione magica).
# Carica il PNG AI dedicato (128x128, stile pixel art dark fantasy); fallback
# procedurale se il PNG non è disponibile: ampolla rotonda con collo, tappo di
# sughero, liquido verde con bollle e riflesso del vetro.
func _draw_potion() -> void:
        var y_off := -bob_offset
        var tex := _load_png_cached("res://assets/sprites/collectibles/item_potion.png")
        if tex != null:
                # Aura magica verde pulsante
                var glow_alpha: float = 0.15 + pulse * 0.12
                draw_circle(Vector2.ZERO, 20.0, Color(0.3, 1.0, 0.35, glow_alpha))
                draw_circle(Vector2.ZERO, 12.0, Color(0.5, 1.0, 0.55, glow_alpha * 0.8))
                var size: float = 64.0
                draw_texture_rect(tex, Rect2(-size / 2.0, -size / 2.0 + y_off, size, size), false)
                # Scintilla luminosa sopra il liquido (luccichio magico)
                var spark_t: float = fmod(anim_time, 1.6)
                if spark_t < 0.35:
                        var spark_a: float = 1.0 - spark_t / 0.35
                        draw_circle(Vector2(6.0, -6.0 + y_off), 2.0 + (1.0 - spark_a) * 2.0,
                                Color(0.8, 1.0, 0.8, spark_a))
                return
        # Fallback procedurale: ampolla da laboratorio
        var body_c := Vector2(0, 6.0 + y_off)
        # Liquido verde nell'ampolla (cerchio pieno per 2/3)
        draw_circle(body_c, 11.0, Color(0.15, 0.5, 0.2, 1.0))
        draw_circle(body_c + Vector2(-3, -3), 7.0, Color(0.3, 0.85, 0.35, 1.0))
        draw_circle(body_c + Vector2(-4, -4), 3.0, Color(0.6, 1.0, 0.6, 1.0))
        # Vetro (contorno)
        draw_arc(body_c, 12.0, 0.0, TAU, 28, Color(0.75, 0.9, 0.85, 0.8), 1.6)
        # Collo dell'ampolla
        draw_rect(Rect2(-3.0, -12.0 + y_off, 6.0, 8.0), Color(0.55, 0.75, 0.7, 0.55), true)
        draw_rect(Rect2(-3.0, -12.0 + y_off, 6.0, 8.0), Color(0.75, 0.9, 0.85, 0.9), false, 1.0)
        # Tappo di sughero
        draw_rect(Rect2(-4.5, -16.0 + y_off, 9.0, 5.0), Color(0.55, 0.4, 0.25), true)
        draw_rect(Rect2(-4.5, -16.0 + y_off, 9.0, 5.0), Color(0.35, 0.25, 0.15), false, 1.0)
        # Riflesso del vetro
        draw_line(body_c + Vector2(-8.0, -6.0), body_c + Vector2(-5.0, -9.0),
                Color(0.9, 1.0, 0.95, 0.7), 1.5)


# ============================================================================
# FIX (martello di Thor — nuova meccanica): Mjolnir da raccogliere nel
# labirinto. PNG AI dedicato (128x128, testa d'acciaio squadrata con rune
# incise e crepe elettriche, manico avvolto in cuoio); fallback procedurale
# dettagliato con teste perni e legatura del manico se il PNG manca.
# Il martello a terra ruota LENTAMENTE su se stesso (come esposto su un
# piedistallo magico) con aura elettrica blu che pulsa.
func _draw_hammer() -> void:
        var y_off := -bob_offset
        var tex := _load_png_cached("res://assets/sprites/collectibles/item_hammer.png")
        # Aura elettrica blu pulsante (il "potere del fulmine" di Mjolnir)
        var glow_alpha: float = 0.12 + pulse * 0.10
        draw_circle(Vector2.ZERO, 24.0, Color(0.45, 0.75, 1.0, glow_alpha))
        draw_circle(Vector2.ZERO, 15.0, Color(0.55, 0.85, 1.0, glow_alpha * 0.8))
        if tex != null:
                # Rotazione lenta (9 gradi/s): il martello gira su un perno
                # invisibile mentre e' esposto a terra.
                draw_set_transform(Vector2(0.0, y_off),
                                deg_to_rad(fmod(anim_time * 9.0, 360.0)), Vector2.ONE)
                var size: float = 64.0
                draw_texture_rect(tex, Rect2(-size / 2.0, -size / 2.0, size, size), false)
                draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
                # Scintilla elettrica che corre sulla testa del martello
                var spark_t: float = fmod(anim_time, 2.2)
                if spark_t < 0.4:
                        var sa: float = sin((spark_t / 0.4) * PI)
                        draw_circle(Vector2(-10.0, -12.0 + y_off), 1.5 + sa * 1.5,
                                Color(0.75, 0.9, 1.0, sa))
                return
        # Fallback procedurale: Mjolnir stilizzato in pixel art
        # Testa squadrata in acciaio con smusso e perni + manico in cuoio.
        draw_set_transform(Vector2(0.0, y_off), deg_to_rad(-35.0), Vector2.ONE)
        # Ombra a terra
        draw_circle(Vector2(0.0, 16.0), 14.0, Color(0, 0, 0, 0.25))
        # Testa del martello (acciaio a 3 tonalita')
        draw_rect(Rect2(-17, -22, 34, 15), Color(0.58, 0.62, 0.70), true)
        draw_rect(Rect2(-17, -22, 34, 4), Color(0.76, 0.80, 0.88), true)
        draw_rect(Rect2(-17, -11, 34, 4), Color(0.44, 0.47, 0.54), true)
        # Perni laterali
        draw_rect(Rect2(-20, -19, 3, 9), Color(0.5, 0.54, 0.62), true)
        draw_rect(Rect2(17, -19, 3, 9), Color(0.5, 0.54, 0.62), true)
        # Rune incise (bagliore blu)
        draw_rect(Rect2(-8, -20, 3, 10), Color(0.45, 0.8, 1.0), true)
        draw_rect(Rect2(-2, -20, 3, 6), Color(0.55, 0.85, 1.0), true)
        draw_rect(Rect2(4, -20, 3, 8), Color(0.45, 0.8, 1.0), true)
        # Manico avvolto nel cuoio
        draw_rect(Rect2(-3.5, -8, 7, 22), Color(0.42, 0.28, 0.16), true)
        for strap in range(5):
                draw_rect(Rect2(-3.5, -6 + strap * 4.5, 7, 1.6),
                                Color(0.3, 0.19, 0.1), true)
        # Pomo metallico
        draw_rect(Rect2(-4.5, 13, 9, 5), Color(0.62, 0.58, 0.44), true)
        draw_rect(Rect2(-4.5, 13, 9, 2), Color(0.8, 0.76, 0.6), true)
        draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# =========================================================
# TASK 35 — PERGAMENE EVENTO (terremoto + voragini magiche)
# =========================================================

## Countdown di vita a terra: 10s raccoglibile, poi 2s di LAMPEGGIO
## (alpha oscillante: avviso "sta per sparire"), poi active = false.
## Il MainGameController libera il nodo quando vede active = false.
func _update_scroll_lifetime(delta_ms: int) -> void:
        if scroll_lifetime_ms <= 0.0:
                return
        scroll_lifetime_ms -= float(delta_ms)
        if scroll_lifetime_ms <= 0.0:
                scroll_lifetime_ms = 0.0
                active = false
                modulate.a = 1.0
                return
        if scroll_lifetime_ms <= SCROLL_BLINK_THRESHOLD_MS:
                # lampeggio: acceso/spento ~7 volte nei 2s finali
                var k: float = fmod(scroll_lifetime_ms, 280.0) / 280.0
                modulate.a = 0.25 + 0.75 * (1.0 if k < 0.5 else 0.0)
        else:
                modulate.a = 1.0


## Pergamena a terra: 48px (le dimensioni dei tesori) con aura colorata
## pulsante del colore della scuola magica (arancio terremoto / viola
## voragini). Fallback procedurale: rotolo di pergamena stilizzato.
func _draw_parchment(tex_path: String, glow_color: Color) -> void:
        var y_off := -bob_offset
        var glow_alpha: float = 0.14 + pulse * 0.12
        draw_circle(Vector2.ZERO, 26.0, Color(glow_color.r, glow_color.g,
                        glow_color.b, glow_alpha))
        draw_circle(Vector2.ZERO, 16.0, Color(glow_color.r, glow_color.g,
                        glow_color.b, glow_alpha * 0.8))
        var tex: Texture2D = _load_png_cached(tex_path)
        if tex != null:
                var size: float = 48.0  # come i tesori da raccogliere
                draw_texture_rect(tex, Rect2(-size / 2.0, -size / 2.0 + y_off,
                                size, size), false)
                return
        # Fallback procedurale: rotolo verticale con estremita' arrotolate
        # e nastro col sigillo. Palette derivata dal colore della scuola.
        var dark := Color(glow_color.r * 0.45, glow_color.g * 0.45,
                        glow_color.b * 0.45)
        var paper := Color(0.87, 0.78, 0.62)
        var edge := Color(0.62, 0.5, 0.34)
        # corpo
        draw_rect(Rect2(-10.0, -16.0 + y_off, 20.0, 32.0), paper)
        draw_rect(Rect2(-10.0, -16.0 + y_off, 20.0, 32.0), edge, false, 1.5)
        # estremita' arrotolate
        draw_rect(Rect2(-12.0, -20.0 + y_off, 24.0, 5.0), edge)
        draw_rect(Rect2(-12.0, 15.0 + y_off, 24.0, 5.0), edge)
        # rune centrali
        draw_rect(Rect2(-6.0, -9.0 + y_off, 12.0, 2.0), dark)
        draw_rect(Rect2(-6.0, -4.0 + y_off, 8.0, 2.0), dark)
        draw_rect(Rect2(-6.0, 1.0 + y_off, 11.0, 2.0), dark)
        draw_rect(Rect2(-6.0, 6.0 + y_off, 7.0, 2.0), dark)
        # nastro + sigillo
        draw_rect(Rect2(-11.0, -2.0 + y_off, 22.0, 4.0), dark)
        draw_circle(Vector2(0.0, 0.0 + y_off), 4.5, glow_color)
        draw_circle(Vector2(0.0, 0.0 + y_off), 4.5, dark, false, 1.2)
