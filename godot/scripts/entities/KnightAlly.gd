## KnightAlly.gd - Cavaliere alleato evocato dalla statua.
## ============================================================
## Meccanica: quando il player raccoglie la statua del cavaliere,
## questo NPC appare e combatte al suo fianco.
##
## Caratteristiche:
##   * Stessa energia del player al momento dell'evocazione
##   * 3 colpi che fanno danno massimo (instant kill)
##   * Si muove più velocemente del player (speed=3, come con scarpe)
##   * I nemici lo considerano un player e lo seguono
##   * Dopo 5 secondi dai 3 colpi (o se muore), scompare con animazione fumo
##   * Sprite sheet 4-frame walk cycle (knight_ally_sheet.png 256x64)
extends Node2D
class_name KnightAlly

const TILE_SIZE: int = 48
const UI_HEIGHT: int = 80

# --- Stats ---
var health: int = 3
var max_health: int = 3
var speed: int = 3  # più veloce del player (player=2, con boost=3)
var shots_left: int = 3
var disappear_timer_ms: int = 0  # >0 = scompare dopo questo tempo
var smoke_timer_ms: int = 0  # animazione scomparsa fumo
var spawning_ms: int = 800  # animazione apparizione (0.8s)

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

# --- Sprite ---
var _sprite_sheet: Texture2D = null
var _sprite_loaded: bool = false

# --- Projectiles (KnightAlly spara 3 colpi) ---
var projectiles: Array = []

# --- State ---
enum State { SPAWNING, ACTIVE, DISAPPEARING, DEAD }
var state: int = State.SPAWNING


func _ready() -> void:
        _load_sprite()
        health = max_health


func _load_sprite() -> void:
        var path := "res://assets/sprites/knight_ally_sheet.png"
        var abs_path := ProjectSettings.globalize_path(path)
        if not FileAccess.file_exists(abs_path):
                _sprite_loaded = false
                return
        var img := Image.new()
        if img.load(abs_path) == OK:
                _sprite_sheet = ImageTexture.create_from_image(img)
                _sprite_loaded = _sprite_sheet != null


func update_ally(maze: Node, player_pos: Vector2, enemies: Array, delta_ms: int) -> void:
        anim_time += delta_ms

        # Spawning animation
        if state == State.SPAWNING:
                spawning_ms -= delta_ms
                if spawning_ms <= 0:
                        state = State.ACTIVE
                queue_redraw()
                return

        # Disappearing (smoke) animation
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

        # Find target enemy (closest alive enemy)
        target_recalc_timer += delta_ms
        if target_recalc_timer >= 500 or target_enemy == null:
                target_recalc_timer = 0
                target_enemy = _find_closest_enemy(enemies)

        # Movement: chase the closest enemy
        if target_enemy != null and is_instance_valid(target_enemy) and not target_enemy.is_dead():
                var e_pos: Vector2 = target_enemy.get_pixel_pos()
                var d: Vector2 = e_pos - pos
                var dist: float = d.length()
                if dist > 4.0:
                        var dir: Vector2 = d / dist
                        var move_x: int = 0
                        var move_y: int = 0
                        if abs(dir.x) > abs(dir.y):
                                move_x = 1 if dir.x > 0 else -1
                        else:
                                move_y = 1 if dir.y > 0 else -1
                        var col := int(pos.x / TILE_SIZE)
                        var row := int((pos.y - UI_HEIGHT) / TILE_SIZE)
                        if not maze.is_wall(col + move_x, row + move_y):
                                dx = move_x
                                dy = move_y
                                last_dx = dx
                                last_dy = dy
                                pos.x += dx * speed
                                pos.y += dy * speed
                        else:
                                if move_x != 0 and not maze.is_wall(col, row + 1):
                                        dy = 1
                                        last_dy = 1
                                        pos.y += speed
                                elif move_x != 0 and not maze.is_wall(col, row - 1):
                                        dy = -1
                                        last_dy = -1
                                        pos.y -= speed
                                elif move_y != 0 and not maze.is_wall(col + 1, row):
                                        dx = 1
                                        last_dx = 1
                                        pos.x += speed
                                elif move_y != 0 and not maze.is_wall(col - 1, row):
                                        dx = -1
                                        last_dx = -1
                                        pos.x -= speed

        # Shoot at closest enemy in range
        if shoot_cooldown > 0:
                shoot_cooldown -= delta_ms
        elif shots_left > 0 and target_enemy != null and is_instance_valid(target_enemy):
                var e_pos2: Vector2 = target_enemy.get_pixel_pos()
                var dist2: float = pos.distance_to(e_pos2)
                if dist2 < 300.0:
                        _shoot_at(e_pos2)
                        shoot_cooldown = 800
                        shots_left -= 1
                        if shots_left == 0:
                                disappear_timer_ms = 5000

        _update_projectiles(enemies, delta_ms)
        queue_redraw()


func _find_closest_enemy(enemies: Array) -> Node2D:
        var closest: Node2D = null
        var closest_dist: float = 999999.0
        for e in enemies:
                if e == null or not is_instance_valid(e):
                        continue
                if e.is_dead():
                        continue
                var d: float = pos.distance_squared_to(e.get_pixel_pos())
                if d < closest_dist:
                        closest_dist = d
                        closest = e
        return closest


func _shoot_at(target_pos: Vector2) -> void:
        var d: Vector2 = target_pos - pos
        var dist: float = d.length()
        if dist < 0.001:
                return
        var dir: Vector2 = d / dist
        projectiles.append({
                "pos": pos + dir * 20.0,
                "dir": dir * 5.0,
                "power": 999,
                "active": true,
                "type": 0,
        })


func _update_projectiles(enemies: Array, delta_ms: int) -> void:
        var alive: Array = []
        for proj in projectiles:
                if not proj.get("active", false):
                        continue
                proj["pos"] = proj["pos"] + proj.get("dir", Vector2.ZERO)
                var p_pos: Vector2 = proj.get("pos", Vector2.ZERO)
                var hit: bool = false
                for e in enemies:
                        if e == null or not is_instance_valid(e):
                                continue
                        if e.is_dead():
                                continue
                        if p_pos.distance_squared_to(e.get_pixel_pos()) < 400.0:
                                e.take_damage(int(proj.get("power", 999)))
                                e.start_burning(30)
                                hit = true
                                break
                if hit:
                        proj["active"] = false
                        continue
                if p_pos.x < 0 or p_pos.x > 1920 or p_pos.y < UI_HEIGHT or p_pos.y > 1080:
                        proj["active"] = false
                        continue
                alive.append(proj)
        projectiles = alive


func take_damage(dmg: int) -> void:
        if state != State.ACTIVE:
                return
        health -= dmg
        if health <= 0:
                _start_disappearing()


func _start_disappearing() -> void:
        state = State.DISAPPEARING
        smoke_timer_ms = 800


func is_dead() -> bool:
        return state == State.DEAD


func is_active() -> bool:
        return state == State.ACTIVE or state == State.SPAWNING


func get_pixel_pos() -> Vector2:
        return pos


func _draw() -> void:
        if state == State.SPAWNING:
                var t: float = 1.0 - (float(spawning_ms) / 800.0)
                var scale_val: float = 0.3 + t * 0.7
                var alpha: float = t
                _draw_sprite(scale_val, alpha)
                draw_circle(Vector2.ZERO, 30.0 * (1.0 - t) + 10.0,
                        Color(0.6, 0.85, 1.0, 0.4 * (1.0 - t)))
                return

        if state == State.DISAPPEARING:
                var t2: float = 1.0 - (float(smoke_timer_ms) / 800.0)
                for i in 8:
                        var a: float = (float(i) / 8.0) * TAU + anim_time * 0.005
                        var r: float = 10.0 + t2 * 30.0
                        var sx: float = cos(a) * r
                        var sy: float = sin(a) * r
                        draw_circle(Vector2(sx, sy - 10), 6.0 * (1.0 - t2),
                                Color(0.6, 0.6, 0.65, 0.6 * (1.0 - t2)))
                _draw_sprite(1.0, 1.0 - t2)
                return

        if state == State.DEAD:
                return

        _draw_sprite(1.0, 1.0)

        for proj in projectiles:
                if not proj.get("active", false):
                        continue
                var p_pos: Vector2 = proj.get("pos", Vector2.ZERO)
                var local_pos: Vector2 = p_pos - position
                draw_circle(local_pos, 5.0, Color(1.0, 0.85, 0.2, 0.5))
                draw_circle(local_pos, 3.0, Color(1.0, 0.95, 0.4, 1.0))
                draw_circle(local_pos, 1.5, Color(1.0, 1.0, 0.8, 1.0))

        if health < max_health:
                var bar_w: float = 24.0
                var bar_h: float = 3.0
                var bar_y: float = -36.0
                draw_rect(Rect2(-bar_w / 2, bar_y, bar_w, bar_h),
                        Color(0.2, 0.0, 0.0, 0.8), true)
                var hp_ratio: float = float(health) / float(max_health)
                draw_rect(Rect2(-bar_w / 2, bar_y, bar_w * hp_ratio, bar_h),
                        Color(1.0, 0.85, 0.2, 1.0), true)

        for i in 3:
                var dot_x: float = -8.0 + float(i) * 8.0
                var dot_y: float = -42.0
                if i < shots_left:
                        draw_circle(Vector2(dot_x, dot_y), 2.0, Color(1.0, 0.9, 0.3, 1.0))
                else:
                        draw_circle(Vector2(dot_x, dot_y), 1.5, Color(0.3, 0.3, 0.3, 0.5))


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
        ]), wing_col)
        draw_polygon(PackedVector2Array([
                Vector2(s + 4, -4), Vector2(s + 12, -12), Vector2(s, -8)
        ]), wing_col)
        draw_rect(Rect2(-s / 2.0, -s / 2.0, s, s),
                Color(0.85, 0.7, 0.3, alpha), true)
        draw_circle(Vector2(0, -s / 2.0 - 4), 6.0,
                Color(0.8, 0.65, 0.25, alpha))
        draw_rect(Rect2(-1.5, -s / 2.0 - 10, 3.0, 6.0),
                Color(0.8, 0.15, 0.15, alpha))
        draw_rect(Rect2(-1.5, -4, 3.0, 8.0), Color(1.0, 0.85, 0.2, alpha))
        draw_rect(Rect2(-4.0, -1.0, 8.0, 3.0), Color(1.0, 0.85, 0.2, alpha))
