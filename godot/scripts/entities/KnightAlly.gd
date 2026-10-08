## KnightAlly.gd - Cavaliere alleato evocato dalla statua.
## ============================================================
## Meccanica: quando il player raccoglie la statua del cavaliere (icona
## di pietra), questa si ANIMA: l'oggetto statua viene sostituito dal
## cavaliere vivo che combatte al fianco del player.
##
## Fasi:
##   1. STONE       - appare come statua di pietra (1.0s, immobile)
##   2. TRANSFORMING - la statua prende colore e diventa viva (1.5s)
##   3. ACTIVE      - cavaliere vivo combatte
##   4. DISAPPEARING - animazione fumo (1.2s) quando scade/muore
##   5. DEAD        - rimosso
extends Node2D
class_name KnightAlly

const TILE_SIZE: int = 64
const UI_HEIGHT: int = 80
# FIX (costanti allineate a GameConstants, 31x15): in precedenza erano stale
# (40x22, poi 30x15 con COLS pari -> doppio muro destro, vedi GameConstants).
# FIX (doppio muro lato destro): allineato a GameConstants (31, dispari).
const MAZE_COLS: int = 31
const MAZE_ROWS: int = 15

# --- Stats ---
var health: int = 5
var max_health: int = 5
# FIX (cavaliere muore subito): cooldown invulnerabilità dopo essere stato colpito.
# I nemici attaccano ogni frame, quindi senza cooldown il cavaliere muore in
# 3 frame (0.05s). 1 secondo di invulnerabilità dopo ogni hit.
var invulnerable_timer_ms: int = 0
var speed: int = 3  # più veloce del player (player=2, con boost=3)
var shots_left: int = 3  # FIX: 3 colpi totali, uno alla volta
var disappear_timer_ms: int = 0
var smoke_timer_ms: int = 0
var spawning_ms: int = 800  # legacy, non usato ma mantenuto per compat
var transform_ms: int = 1500  # durata transform statua→vivo
var stone_ms: int = 1000  # durata fase statua di pietra (1s)

# --- Movement ---
var pos: Vector2 = Vector2.ZERO:
        set(v):
                pos = v
                position = v
var dx: int = 1
var dy: int = 0
var last_dx: int = 1
var last_dy: int = 0
var anim_time: int = 0
var shoot_cooldown: int = 0

# --- Targeting ---
var target_enemy: Node2D = null
var target_recalc_timer: int = 0

# --- Pathfinding (BFS) — FIX AI unicorno aggira muri ---
# Mirror di Enemy.gd: BFS.find_path ogni PATH_RECALC_INTERVAL_MS,
# snap al centro cella, anti-stuck tracking, anti-tunneling.
var path_update_timer: int = 0       # ms accumulator per BFS recalc
var stuck_timer: int = 0             # anti-stuck detection (<1px mov -> accumula)
var last_pos: Vector2 = Vector2.ZERO  # per stuck detection
var current_dir: Vector2i = Vector2i.ZERO  # direzione BFS cached tra recalc
const PATH_RECALC_INTERVAL_MS: int = 200  # mirror Enemy.gd
const STUCK_THRESHOLD_MS: int = 100       # mirror Enemy.gd

# --- Sprite ---
var _sprite_sheet: Texture2D = null
var _sprite_loaded: bool = false
var _statue_texture: Texture2D = null
var _statue_loaded: bool = false

# --- Projectiles ---
var projectiles: Array = []

# --- State ---
enum State { STONE, TRANSFORMING, ACTIVE, DISAPPEARING, DEAD }
var state: int = State.STONE


func _ready() -> void:
        _load_sprite()
        _load_statue_texture()
        health = max_health


func _load_sprite() -> void:
        var path := "res://assets/sprites/unicorn_ally_sheet.png"
        var abs_path := ProjectSettings.globalize_path(path)
        if not FileAccess.file_exists(abs_path):
                _sprite_loaded = false
                return
        var img := Image.new()
        if img.load(abs_path) == OK:
                _sprite_sheet = ImageTexture.create_from_image(img)
                _sprite_loaded = _sprite_sheet != null


# FIX (statua di pietra): carica la texture della statua (unicorno di pietra)
func _load_statue_texture() -> void:
        var path := "res://assets/sprites/collectibles/item_unicorn_statue.png"
        var abs_path := ProjectSettings.globalize_path(path)
        if not FileAccess.file_exists(abs_path):
                _statue_loaded = false
                return
        var img := Image.new()
        if img.load(abs_path) == OK:
                _statue_texture = ImageTexture.create_from_image(img)
                _statue_loaded = _statue_texture != null


# Reference al mini-boss (settabile da MainGameController)
var mini_boss: Node2D = null
# FIX (proiettili rimbalzo): reference al maze per wall check
var maze_ref: Node = null

func update_ally(maze: Node, player_pos: Vector2, enemies: Array, delta_ms: int) -> void:
        anim_time += delta_ms
        maze_ref = maze  # FIX: salva reference per wall check proiettili

        # Fase 1: statua di pietra (1s, immobile)
        if state == State.STONE:
                stone_ms -= delta_ms
                if stone_ms <= 0:
                        state = State.TRANSFORMING
                        transform_ms = 1500
                queue_redraw()
                return

        # Fase 2: transform (1.5s, statua prende colore e diventa viva)
        if state == State.TRANSFORMING:
                transform_ms -= delta_ms
                if transform_ms <= 0:
                        state = State.ACTIVE
                queue_redraw()
                return

        # Fase 4: disappearing (smoke animation)
        if state == State.DISAPPEARING:
                smoke_timer_ms -= delta_ms
                if smoke_timer_ms <= 0:
                        state = State.DEAD
                queue_redraw()
                return

        if state == State.DEAD:
                return

        # Disappear timer (5s after 3 shots fired)
        if disappear_timer_ms > 0:
                disappear_timer_ms -= delta_ms
                if disappear_timer_ms <= 0:
                        _start_disappearing()
                        return

        # Find target enemy
        target_recalc_timer += delta_ms
        if target_recalc_timer >= 500 or target_enemy == null:
                target_recalc_timer = 0
                target_enemy = _find_closest_enemy(enemies)
                if target_enemy != null:
                        print("[KnightAlly] Target found: ", target_enemy)

        # FIX (cavaliere segue player): il problema è che se target_enemy è null
        # (nessun nemico vivo trovato), il cavaliere segue il player.
        # Ora: se non ci sono nemici, il cavaliere STA FERMO e aspetta
        # (non segue il player). Se ci sono nemici, li insegue.
        var chase_pos: Vector2 = pos  # default: fermo
        var has_target: bool = false
        if target_enemy != null and is_instance_valid(target_enemy) and not target_enemy.is_dead():
                chase_pos = target_enemy.get_pixel_pos()
                has_target = true

        # FIX (unicorno bloccato senza nemici): se non ci sono nemici,
        # l'unicorno deve scomparire dopo 5 secondi, non rimanere bloccato.
        if not has_target:
                # Nessun nemico: avvia countdown scomparsa
                if disappear_timer_ms <= 0:
                        disappear_timer_ms = 5000
                        print("[KnightAlly] No enemies found, disappear in 5s")
        # FIX (compenetrazione muri + scatti): movimento GRID-LOCKED come
        # Enemy.gd / C++ originale (vedi Enemy.update_enemy). La direzione è
        # cambiata SOLO al centro cella (snap immediato di max step_size px),
        # wall check point-based sulla cella successiva, movimento cardinale
        # lungo la linea centrale dei corridoi. Rimossi: snap graduale non
        # gating, BFS ricalcolato a metà cella e safety clamp con teleport
        # (rompevano l'invariante della linea centrale -> compenetrazione
        # muri percepita e scatti, le stesse cause dei nemici).
        if has_target:
                var col := int(pos.x / TILE_SIZE)
                var row := int((pos.y - UI_HEIGHT) / TILE_SIZE)
                var center_x: float = col * TILE_SIZE + TILE_SIZE / 2.0
                var center_y: float = row * TILE_SIZE + TILE_SIZE / 2.0 + UI_HEIGHT

                # Anti-stuck tracking (mirror Enemy.gd)
                var dx_pos: float = pos.x - last_pos.x
                var dy_pos: float = pos.y - last_pos.y
                if dx_pos * dx_pos + dy_pos * dy_pos < 1.0:
                        stuck_timer += delta_ms
                else:
                        stuck_timer = 0
                last_pos = pos

                # Step size frame-rate independent (mirror Enemy.gd)
                var step_size: float = float(speed) * (float(delta_ms) / 16.6667)
                path_update_timer += delta_ms

                # Direzione decisa SOLO al centro cella (snap immediato).
                if absf(pos.x - center_x) < step_size \
                                and absf(pos.y - center_y) < step_size:
                        pos = Vector2(center_x, center_y)

                        # Force recalc on: timer expiry, idle, stuck.
                        var must_recompute: bool = (path_update_timer >= PATH_RECALC_INTERVAL_MS) \
                                        or (current_dir.x == 0 and current_dir.y == 0) \
                                        or (stuck_timer > STUCK_THRESHOLD_MS)
                        if must_recompute and maze != null:
                                path_update_timer = 0
                                var target_col: int = int(chase_pos.x / TILE_SIZE)
                                var target_row: int = int((chase_pos.y - UI_HEIGHT) / TILE_SIZE)
                                var start_cell: Vector2i = Vector2i(col, row)
                                var target_cell: Vector2i = Vector2i(target_col, target_row)
                                # FIX: se start == target, è già sulla cella del target
                                if start_cell == target_cell:
                                        current_dir = Vector2i.ZERO
                                else:
                                        var next_step: Vector2i = BFS.find_path(
                                                maze, start_cell, target_cell)
                                        # BFS ritorna (-1, -1) se nessun path
                                        if next_step.x >= 0 and next_step.y >= 0:
                                                current_dir = Vector2i(
                                                                next_step.x - col, next_step.y - row)
                                                stuck_timer = 0
                                        else:
                                                # Nessun path (nemico irraggiungibile) — idle
                                                current_dir = Vector2i.ZERO

                        # Wall check point-based al centro (mai a metà cella).
                        if current_dir.x != 0 or current_dir.y != 0:
                                if maze.is_wall(col + current_dir.x, row + current_dir.y):
                                        current_dir = Vector2i.ZERO
                elif current_dir.x == 0 and current_dir.y == 0:
                        # Fermo ma decentrato (stato anomalo): recovery al centro.
                        pos = pos.move_toward(Vector2(center_x, center_y), step_size)
                        last_pos = pos

                # Movimento cardinale lungo la linea centrale.
                pos.x += current_dir.x * step_size
                pos.y += current_dir.y * step_size

                # Correzione "rotaia" (no-op ESATTO se già in asse): riallinea
                # l'asse perpendicolare alla marcia -> invariante auto-riparante.
                if current_dir.x != 0 and current_dir.y == 0:
                        pos.y = move_toward(pos.y, center_y, step_size)
                elif current_dir.y != 0 and current_dir.x == 0:
                        pos.x = move_toward(pos.x, center_x, step_size)

                # Aggiorna la direzione visiva per lo sprite (flip).
                if current_dir.x != 0 or current_dir.y != 0:
                        dx = current_dir.x
                        dy = current_dir.y
                        if dx != 0:
                                last_dx = dx
                else:
                        dx = 0
                        dy = 0

                # Safety clamp (ultima difesa): se la cella corrente è WALL
                # (stato invalido), teleport al centro della cella aperta più
                # vicina. Con il movimento grid-locked non dovrebbe attivarsi.
                var final_col: int = clampi(int(pos.x / TILE_SIZE), 0, MAZE_COLS - 1)
                var final_row: int = clampi(int((pos.y - UI_HEIGHT) / TILE_SIZE), 0, MAZE_ROWS - 1)
                if maze.is_wall(final_col, final_row):
                        for snap_radius in range(1, 4):
                                var found_safe: bool = false
                                for sdc in range(-snap_radius, snap_radius + 1):
                                        for sdr in range(-snap_radius, snap_radius + 1):
                                                var nnc: int = final_col + sdc
                                                var nnr: int = final_row + sdr
                                                if nnc > 0 and nnc < MAZE_COLS - 1 \
                                                                and nnr > 0 and nnr < MAZE_ROWS - 1:
                                                        if not maze.is_wall(nnc, nnr):
                                                                pos = Vector2(
                                                                                nnc * TILE_SIZE + TILE_SIZE / 2.0,
                                                                                nnr * TILE_SIZE + TILE_SIZE / 2.0 + UI_HEIGHT)
                                                                current_dir = Vector2i.ZERO
                                                                path_update_timer = PATH_RECALC_INTERVAL_MS
                                                                found_safe = true
                                                                break
                                if found_safe:
                                        break
                        if found_safe:
                                break

        # Shoot at closest enemy in range — UN colpo alla volta, solo con linea di vista.
        # FIX (richiesta utente): l'unicorno ha 3 colpi totali.
        # - Sparare UN colpo alla volta (non tutti insieme)
        # - Se il primo colpo va a segno → si ferma (non spara più)
        # - Se il primo colpo manca → spara il secondo, ecc.
        # - I colpi NON devono attraversare i muri
        # - Sparare SOLO quando c'è linea di vista libera (no muri tra unicorno e target)
        if shoot_cooldown > 0:
                shoot_cooldown -= delta_ms
        elif shots_left > 0 and target_enemy != null and is_instance_valid(target_enemy):
                # FIX: non sparare se c'è già un proiettile in volo (un colpo alla volta)
                var has_active_projectile: bool = false
                for p in projectiles:
                        if p.get("active", false):
                                has_active_projectile = true
                                break
                if not has_active_projectile and target_enemy.has_method("get_pixel_pos"):
                        var e_pos2: Vector2 = target_enemy.get_pixel_pos()
                        var dist2: float = pos.distance_to(e_pos2)
                        # FIX: spara solo se il nemico è entro 250px
                        if dist2 < 250.0:
                                # FIX: spara solo se c'è linea di vista libera (no muri)
                                if _has_line_of_sight(pos, e_pos2):
                                        _shoot_at(e_pos2)
                                        shoot_cooldown = 800
                                        shots_left -= 1
                                        if shots_left == 0:
                                                disappear_timer_ms = 5000

        # FIX (cavaliere muore subito): decrementa invulnerability timer
        if invulnerable_timer_ms > 0:
                invulnerable_timer_ms -= delta_ms
                if invulnerable_timer_ms < 0:
                        invulnerable_timer_ms = 0

        _update_projectiles(enemies, delta_ms)
        queue_redraw()


func _find_closest_enemy(enemies: Array) -> Node2D:
        var closest: Node2D = null
        var closest_dist: float = 999999.0
        # Cerca tra i nemici normali
        for e in enemies:
                if e == null or not is_instance_valid(e):
                        continue
                if not e.has_method("is_dead"):
                        continue
                if e.is_dead():
                        continue
                if not e.has_method("get_pixel_pos"):
                        continue
                var d: float = pos.distance_squared_to(e.get_pixel_pos())
                if d < closest_dist:
                        closest_dist = d
                        closest = e
        # Cerca anche il mini-boss
        if mini_boss != null and is_instance_valid(mini_boss):
                if mini_boss.has_method("is_dead") and not mini_boss.is_dead():
                        if mini_boss.has_method("get_pixel_pos"):
                                var d_mb: float = pos.distance_squared_to(mini_boss.get_pixel_pos())
                                if d_mb < closest_dist:
                                        closest_dist = d_mb
                                        closest = mini_boss
        return closest


# FIX (linea di vista): verifica se ci sono muri tra from_pos e to_pos.
# Usa raycasting lungo la griglia: controlla ogni cella attraversata dalla
# linea retta tra i due punti. Se una cella è WALL, ritorna false.
# Implementazione: Bresenham-like, controlla le celle lungo l'asse
# dominante e perpendicolare.
func _has_line_of_sight(from_pos: Vector2, to_pos: Vector2) -> bool:
        if maze_ref == null:
                return true  # se non c'è maze, permetti (fallback)
        var from_col: int = int(from_pos.x / TILE_SIZE)
        var from_row: int = int((from_pos.y - UI_HEIGHT) / TILE_SIZE)
        var to_col: int = int(to_pos.x / TILE_SIZE)
        var to_row: int = int((to_pos.y - UI_HEIGHT) / TILE_SIZE)
        # Bresenham line algorithm per attraversare le celle
        var dx: int = abs(to_col - from_col)
        var dy: int = abs(to_row - from_row)
        var sx: int = 1 if from_col < to_col else -1
        var sy: int = 1 if from_row < to_row else -1
        var err: int = dx - dy
        var cx: int = from_col
        var cy: int = from_row
        while true:
                # Salta la cella di partenza (l'unicorno è lì)
                if cx != from_col or cy != from_row:
                        if maze_ref.is_wall(cx, cy):
                                return false  # muro blocca la linea di vista
                if cx == to_col and cy == to_row:
                        break
                var e2: int = 2 * err
                if e2 > -dy:
                        err -= dy
                        cx += sx
                if e2 < dx:
                        err += dx
                        cy += sy
        return true  # nessun muro attraversato


func _shoot_at(target_pos: Vector2) -> void:
        var d: Vector2 = target_pos - pos
        var dist: float = d.length()
        if dist < 0.001:
                return
        var dir: Vector2 = d / dist
        # FIX (danno 50% HP): il colpo dell'unicorno toglie il 50% dell'energia
        # a qualsiasi nemico. Se il nemico ha meno del 50% HP, viene ucciso.
        # power=-1 significa "50% di max_health" (gestito in _update_projectiles).
        projectiles.append({
                "pos": pos + dir * 20.0,
                "dir": dir * 5.0,
                "power": -1,  # FIX: -1 = danno 50% max_health (speciale)
                "active": true,
                "type": 0,
                "life_ms": 6000,  # FIX: 6 secondi di vita con rimbalzo
        })


func _update_projectiles(enemies: Array, delta_ms: int) -> void:
        var alive: Array = []
        for proj in projectiles:
                if not proj.get("active", false):
                        continue
                # FIX (proiettili non attraversano muri): se il proiettile sta
                # per entrare in una cella WALL, DISATTIVALO (no rimbalzo).
                # L'utente vuole che i colpi NON attraversino i muri.
                var p_pos: Vector2 = proj.get("pos", Vector2.ZERO)
                var p_vel: Vector2 = proj.get("dir", Vector2.ZERO)
                var new_pos: Vector2 = p_pos + p_vel
                var col: int = int(new_pos.x / TILE_SIZE)
                var row: int = int((new_pos.y - UI_HEIGHT) / TILE_SIZE)
                if maze_ref != null and maze_ref.is_wall(col, row):
                        # Proiettile ha colpito un muro: DISATTIVALO (no rimbalzo)
                        proj["active"] = false
                        continue
                proj["pos"] = new_pos
                proj["dir"] = p_vel
                # FIX (proiettili durata 6s): decrementa life_ms
                var life: int = proj.get("life_ms", 6000)
                life -= int(delta_ms)
                proj["life_ms"] = life
                if life <= 0:
                        proj["active"] = false
                        continue
                # Out of bounds
                if new_pos.x < 0 or new_pos.x > 1920 or new_pos.y < UI_HEIGHT or new_pos.y > 1080:
                        proj["active"] = false
                        continue
                var hit: bool = false
                # Check nemici normali
                for e in enemies:
                        if e == null or not is_instance_valid(e):
                                continue
                        if not e.has_method("is_dead") or e.is_dead():
                                continue
                        if not e.has_method("get_pixel_pos"):
                                continue
                        if new_pos.distance_squared_to(e.get_pixel_pos()) < 600.0:
                                # FIX (danno 50% HP): calcola danno come 50% di max_health.
                                # Se il nemico ha HP <= 50%, viene ucciso (take_damage 999).
                                # Altrimenti take_damage(50% max_health).
                                var dmg: int = 999  # default: kill
                                var raw_power: int = int(proj.get("power", 999))
                                if raw_power == -1:
                                        # power=-1 = danno speciale 50% max_health
                                        if e.has_method("get_max_health"):
                                                var max_hp: int = e.get_max_health()
                                                var fifty_pct: int = int(max_hp * 0.5)
                                                if e.health <= fifty_pct:
                                                        dmg = 999  # kill: HP <= 50%
                                                else:
                                                        dmg = fifty_pct  # sopravvive con 50% HP
                                        # else: nemico senza get_max_health, usa 999 default
                                else:
                                        dmg = raw_power
                                e.take_damage(dmg)
                                if e.has_method("start_burning"):
                                        e.start_burning(30)
                                hit = true
                                break
                # Check mini_boss
                if not hit and mini_boss != null and is_instance_valid(mini_boss):
                        if mini_boss.has_method("is_dead") and not mini_boss.is_dead():
                                if mini_boss.has_method("get_pixel_pos"):
                                        if new_pos.distance_squared_to(mini_boss.get_pixel_pos()) < 900.0:
                                                # FIX (danno 50% HP): stesso calcolo per mini_boss
                                                var dmg: int = 999
                                                var raw_power: int = int(proj.get("power", 999))
                                                if raw_power == -1:
                                                        if mini_boss.has_method("get_max_health"):
                                                                var max_hp: int = mini_boss.get_max_health()
                                                                var fifty_pct: int = int(max_hp * 0.5)
                                                                if mini_boss.health <= fifty_pct:
                                                                        dmg = 999
                                                                else:
                                                                        dmg = fifty_pct
                                                else:
                                                        dmg = raw_power
                                                mini_boss.take_damage(dmg)
                                                hit = true
                if hit:
                        proj["active"] = false
                        continue
                alive.append(proj)
        projectiles = alive


func take_damage(dmg: int) -> void:
        if state != State.ACTIVE:
                return
        # FIX (cavaliere muore subito): se invulnerabile, ignora il danno
        if invulnerable_timer_ms > 0:
                return
        health -= dmg
        # 1 secondo di invulnerabilità dopo ogni hit
        invulnerable_timer_ms = 1000
        if health <= 0:
                _start_disappearing()


func _start_disappearing() -> void:
        state = State.DISAPPEARING
        smoke_timer_ms = 1200  # 1.2s smoke animation (più lunga)


func is_dead() -> bool:
        return state == State.DEAD


func is_active() -> bool:
        return state == State.ACTIVE


func get_pixel_pos() -> Vector2:
        return pos


func _draw() -> void:
        # FIX (unicorno unificato): usa SEMPRE _statue_texture per tutte le
        # fasi, applicando effetti procedurali (tint dorata, bob, nube) per
        # differenziare visivamente. Questo evita il "cambio palese di PNG"
        # tra statua e forma attiva.
        var is_moving: bool = (dx != 0 or dy != 0)
        var move_bob: float = 0.0
        if is_moving and state == State.ACTIVE:
                move_bob = sin(float(anim_time) * 0.015) * 2.0

        # Fase 1: statua di pietra immobile
        if state == State.STONE:
                _draw_statue_unified(1.0, 1.0, 0.0, 0.0, false)
                # Aura mistica debole
                var pulse: float = (sin(float(anim_time) * 0.005) + 1.0) * 0.5
                draw_circle(Vector2.ZERO, 30.0,
                        Color(0.4, 0.6, 1.0, 0.15 + pulse * 0.1))
                return

        # Fase 2: transform statua→vivo (1.5s) — effetto NUDE
        # FIX (nube su transform): nube densa + statua che prende colore
        if state == State.TRANSFORMING:
                var t: float = 1.0 - (float(transform_ms) / 1500.0)
                # Statua con tint dorata crescente + bob leggero
                _draw_statue_unified(1.0 - t * 0.2, 1.0, t, move_bob, true)
                # NUDE densa attorno alla statua
                _draw_cloud_effect(t, 0.7)
                # Aura mistica che cresce
                draw_circle(Vector2.ZERO, 20.0 + t * 25.0,
                        Color(0.5, 0.8, 1.0, 0.3 + t * 0.3))
                return

        # Fase 4: disappearing (smoke) — effetto NUDE
        # FIX (nube su disappear): nube densa + statua che sfuma
        if state == State.DISAPPEARING:
                var t2: float = 1.0 - (float(smoke_timer_ms) / 1200.0)
                # Statua che sfuma
                _draw_statue_unified(1.0 - t2 * 0.3, 1.0 - t2, 1.0, 0.0, false)
                # NUDE densa che si espande
                _draw_cloud_effect(t2, 0.8)
                # Aura finale
                draw_circle(Vector2.ZERO, 25.0 + t2 * 20.0,
                        Color(0.4, 0.7, 1.0, 0.3 * (1.0 - t2)))
                return

        if state == State.DEAD:
                return

        # Fase 3: ACTIVE - statua con aura celeste chiara + bob movimento
        # FIX (effetto movimento): bob verticale quando si muove
        _draw_statue_unified(1.0, 1.0, 1.0, move_bob, true)
        # FIX (NO aura dorata): sostituita con aura celeste chiara appena visibile
        var aura_pulse: float = (sin(float(anim_time) * 0.008) + 1.0) * 0.5
        draw_circle(Vector2.ZERO, 32.0,
                Color(0.6, 0.8, 1.0, 0.06 + aura_pulse * 0.04))

        # FIX (pallino procedurale MOBILE accanto al miniboss, 3° tentativo):
        # i proiettili dorati del KnightAlly erano percepiti come "pallino
        # procedurale che SI MUOVE accanto al miniboss". Rendering disabilitato:
        # la logica di collisione (_update_projectiles) resta attiva — i
        # proiettili fanno ancora danno al miniboss, ma non sono più visibili.
        pass

        # HP bar
        if health < max_health:
                var bar_w: float = 24.0
                var bar_h: float = 3.0
                var bar_y: float = -36.0
                draw_rect(Rect2(-bar_w / 2, bar_y, bar_w, bar_h),
                        Color(0.2, 0.0, 0.0, 0.8), true)
                var hp_ratio: float = float(health) / float(max_health)
                draw_rect(Rect2(-bar_w / 2, bar_y, bar_w * hp_ratio, bar_h),
                        Color(1.0, 0.85, 0.2, 1.0), true)


# FIX (effetto nube): disegna nube densa attorno all'unicorno per transform
# e disappear. intensity 0..1 (0 = nube leggera, 1 = nube densa).
func _draw_cloud_effect(intensity: float, alpha_mul: float) -> void:
        # Nube principale: 14 particelle grigio-bianche che si espandono
        for i in 14:
                var a: float = (float(i) / 14.0) * TAU + float(anim_time) * 0.003
                var r: float = 12.0 + intensity * 30.0
                var sx: float = cos(a) * r
                var sy: float = sin(a) * r - intensity * 8.0  # sale verso l'alto
                var sz: float = 6.0 + intensity * 4.0
                # Nube bianco-grigia densa
                draw_circle(Vector2(sx, sy), sz,
                        Color(0.85, 0.85, 0.9, 0.6 * alpha_mul * (1.0 - intensity * 0.3)))
                draw_circle(Vector2(sx + 2, sy - 2), sz * 0.5,
                        Color(0.95, 0.95, 1.0, 0.4 * alpha_mul))
        # Nube interna più densa
        for i in 8:
                var a2: float = (float(i) / 8.0) * TAU + float(anim_time) * 0.005
                var r2: float = 8.0 + intensity * 15.0
                var sx2: float = cos(a2) * r2
                var sy2: float = sin(a2) * r2 - intensity * 4.0
                draw_circle(Vector2(sx2, sy2), 4.0 + intensity * 2.0,
                        Color(0.9, 0.9, 0.95, 0.7 * alpha_mul * (1.0 - intensity * 0.2)))


# FIX (unicorno unificato): disegna la statua texture con effetti procedurali.
# alpha_mul = moltiplicatore alpha (per fade in/out)
# alpha = alpha finale della texture
# color_t = 0.0 (pietra grigia) → 1.0 (vivo)
# bob_y = offset verticale per effetto movimento
# golden_glow = true per aggiungere aura celeste chiara (NON gialla)
func _draw_statue_unified(alpha_mul: float, alpha: float, color_t: float,
                bob_y: float, golden_glow: bool) -> void:
        if _statue_loaded and _statue_texture != null:
                var size: float = 60.0  # FIX: 60px (meno di TILE_SIZE=64) per non overflow muro
                var draw_pos: Vector2 = Vector2(-size / 2.0, -size / 2.0 + bob_y)
                # Texture con alpha
                draw_texture_rect(_statue_texture,
                        Rect2(draw_pos, Vector2(size, size)), false,
                        Color(1, 1, 1, alpha * alpha_mul))
                # FIX (NO quadrato giallo): rimosso il draw_rect dorato che
                # copriva tutto lo sprite con un rettangolo giallo opaco.
                # L'utente vedeva "tutto giallo dentro un quadrato giallo".
                # Ora usiamo solo un'aura celeste chiara appena visibile.
                # Aura celeste chiara trasparente (appena visibile)
                if golden_glow and color_t > 0.3:
                        var aura_pulse: float = (sin(float(anim_time) * 0.008) + 1.0) * 0.5
                        # Celeste chiaro (0.6, 0.8, 1.0) con alpha molto basso (0.08-0.15)
                        draw_circle(Vector2.ZERO, size * 0.55 + aura_pulse * 2.0,
                                Color(0.6, 0.8, 1.0, 0.08 + aura_pulse * 0.04))
                return
        # Fallback: statua procedurale grigia
        _draw_procedural_unified(alpha_mul, alpha, color_t, bob_y)


# FIX (fallback procedurale unificato)
func _draw_procedural_unified(alpha_mul: float, alpha: float, color_t: float,
                bob_y: float) -> void:
        var s: float = 20.0
        var stone_col: Color = Color(0.66, 0.62, 0.56, alpha * alpha_mul)
        var gold_col: Color = Color(0.85, 0.7, 0.3, alpha * alpha_mul)
        var body_col: Color = stone_col.lerp(gold_col, color_t)
        var y_off: float = bob_y
        # Ali
        draw_polygon(PackedVector2Array([
                Vector2(-s - 4, -4 + y_off), Vector2(-s - 12, -12 + y_off), Vector2(-s, -8 + y_off)
        ]), PackedColorArray([body_col]))
        draw_polygon(PackedVector2Array([
                Vector2(s + 4, -4 + y_off), Vector2(s + 12, -12 + y_off), Vector2(s, -8 + y_off)
        ]), PackedColorArray([body_col]))
        # Corpo
        draw_rect(Rect2(-s / 2.0, -s / 2.0 + y_off, s, s), body_col, true)
        # Elmo
        draw_circle(Vector2(0, -s / 2.0 - 4 + y_off), 6.0, body_col)

        # FIX (rimossi 3 pallini): i pallini indicator dei colpi si muovevano
        # rispetto allo sprite. Rimossi completamente.


# FIX (statua di pietra): disegna la statua con texture PNG o fallback.
# alpha = moltiplicatore alpha, color_t = 0.0 (pietra) → 1.0 (vivo)
func _draw_statue(alpha_mul: float, alpha: float, color_t: float) -> void:
        if _statue_loaded and _statue_texture != null:
                var size: float = 64.0
                var y_off: float = 0.0
                # Bob leggero per indicare "sta prendendo vita"
                if color_t > 0.3:
                        y_off = sin(float(anim_time) * 0.008) * 1.0 * color_t
                draw_texture_rect(_statue_texture,
                        Rect2(-size / 2.0, -size / 2.0 + y_off, size, size), false,
                        Color(1, 1, 1, alpha * alpha_mul))
                # Tint graduale verso il dorato (cavaliere vivo)
                if color_t > 0.0:
                        var tint_col: Color = Color(1.0, 0.85, 0.3, color_t * 0.4)
                        draw_rect(Rect2(-size / 2.0, -size / 2.0 + y_off, size, size),
                                tint_col, false, 2.0)
                return
        # Fallback: statua procedurale grigia
        var s: float = 20.0
        var stone_col: Color = Color(0.66, 0.62, 0.56, alpha * alpha_mul)
        # Ali di pietra
        draw_polygon(PackedVector2Array([
                Vector2(-s - 4, -4), Vector2(-s - 12, -12), Vector2(-s, -8)
        ]), PackedColorArray([stone_col]))
        draw_polygon(PackedVector2Array([
                Vector2(s + 4, -4), Vector2(s + 12, -12), Vector2(s, -8)
        ]), PackedColorArray([stone_col]))
        # Corpo
        draw_rect(Rect2(-s / 2.0, -s / 2.0, s, s), stone_col, true)
        # Elmo
        draw_circle(Vector2(0, -s / 2.0 - 4), 6.0, stone_col)
        # Tint dorato crescente
        if color_t > 0.0:
                var gold_tint: Color = Color(0.85, 0.7, 0.3, color_t * 0.5)
                draw_rect(Rect2(-s / 2.0, -s / 2.0, s, s), gold_tint, true)


func _draw_sprite(scale_val: float, alpha: float) -> void:
        if _sprite_loaded and _sprite_sheet != null:
                var is_moving: bool = (dx != 0 or dy != 0)
                var frame: int = 0
                if is_moving:
                        frame = (int(anim_time) / 100) % 4
                var frame_w: int = 64
                var frame_h: int = 64
                var src_rect: Rect2 = Rect2(frame * frame_w, 0, frame_w, frame_h)
                var target_size: float = 72.0 * scale_val
                var bob_y: float = 0.0
                if is_moving:
                        bob_y = sin(float(anim_time) * 0.01) * 2.0
                var draw_pos: Vector2 = Vector2(-target_size / 2.0, -target_size / 2.0 + bob_y)
                var flip: bool = last_dx < 0
                if flip:
                        draw_texture_rect_region(_sprite_sheet,
                                Rect2(draw_pos.x + target_size, draw_pos.y, -target_size, target_size),
                                src_rect, Color(1, 1, 1, alpha))
                else:
                        draw_texture_rect_region(_sprite_sheet,
                                Rect2(draw_pos, Vector2(target_size, target_size)),
                                src_rect, Color(1, 1, 1, alpha))
                return
        _draw_procedural(scale_val, alpha)


func _draw_procedural(scale_val: float, alpha: float) -> void:
        var s: float = 20.0 * scale_val
        var wing_col: Color = Color(0.85, 0.85, 0.95, alpha * 0.8)
        draw_polygon(PackedVector2Array([
                Vector2(-s - 4, -4), Vector2(-s - 12, -12), Vector2(-s, -8)
        ]), PackedColorArray([wing_col]))
        draw_polygon(PackedVector2Array([
                Vector2(s + 4, -4), Vector2(s + 12, -12), Vector2(s, -8)
        ]), PackedColorArray([wing_col]))
        draw_rect(Rect2(-s / 2.0, -s / 2.0, s, s),
                Color(0.85, 0.7, 0.3, alpha), true)
        draw_circle(Vector2(0, -s / 2.0 - 4), 6.0,
                Color(0.8, 0.65, 0.25, alpha))
        draw_rect(Rect2(-1.5, -s / 2.0 - 10, 3.0, 6.0),
                Color(0.8, 0.15, 0.15, alpha))
        draw_rect(Rect2(-1.5, -4, 3.0, 8.0), Color(1.0, 0.85, 0.2, alpha))
        draw_rect(Rect2(-4.0, -1.0, 8.0, 3.0), Color(1.0, 0.85, 0.2, alpha))
