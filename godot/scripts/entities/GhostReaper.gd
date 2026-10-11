## GhostReaper.gd - Mini boss IMMORTALE "unico" della meccanica "Hurry Up!"
## ============================================================
## Appare dal portale magico quando TUTTI i nemici del labirinto
## (compresi quelli respawnati) sono stati uccisi e sono passati 10
## secondi dall'ultimo tesoro raccolto. È diverso da tutti gli altri
## nemici/mini-boss: un FANTASMA (stile Slimer dei Ghostbusters) con
## testa Teschio e braccia scheletriche.
##
## Caratteristiche (richiesta utente):
##   * IMMORTALE: i proiettili non gli fanno nulla — quando gli si spara
##     emette il segnale `laughed` (il controller suona la risata
##     tenebrosa: "non puoi ucciderlo, si può solo scappare").
##   * Velocità di movimento = nemici del labirinto (speed 2, come
##     Enemy.STATS: tutti i nemici maze usano speed 2).
##   * Insegue il player per TUTTO il tempo finché non supera il livello
##     passando dalla porta; poi scompare e riappare al livello labirinto
##     successivo alla stessa maniera.
##
## Movimento: GRID-LOCKED identico a MiniBoss/Enemy (commit 13feb64):
##   1) viaggio SEMPRE sulla linea centrale dei corridoi;
##   2) cambio direzione SOLO al centro cella (coincidenza ESATTA);
##   3) wall check point-based is_wall(col+dx, row+dy);
##   4) waypoint LOCKED alla decisione + recovery anti-freeze.
##
## Rendering: stesso stile/dimensione degli altri sprite (sheet 256x64
## 4 frame con bob, disegnato a 78px come i nemici) + trasparenza
## spettrale, aura ectoplasmatica, scia di fantasmi e fluttuazione.
## ============================================================
extends Node2D
class_name GhostReaper

# Costanti grid (mirror MiniBoss.gd / GameConstants).
const TILE_SIZE: int = 64
const MAZE_COLS: int = 30
const MAZE_ROWS: int = 15
const UI_HEIGHT: int = 80

# Direzioni cardinali (stesso ordine di Enemy.gd/MiniBoss.gd).
const _DC: Array[int] = [0, 1, 0, -1]
const _DR: Array[int] = [-1, 0, 1, 0]
# Anti-stuck (mirror MiniBoss.gd).
const STUCK_THRESHOLD_MS: int = 100

# FIX (velocità = nemici del labirinto): tutti i nemici maze hanno
# speed = 2 (Enemy.STATS). Il fantasma usa la stessa velocità: il player
# (speed 2) può seminarlo solo sfruttando i bivi, non la velocità pura.
const GHOST_SPEED: int = 2
# Dimensione rendering = nemici (78px, gerarchia: player 83 > miniboss 82
# > nemici/fantasma 78 > tesori 73.6).
const GHOST_SIZE: float = 78.0

# Durata dell' apparizione (fade-in ectoplasmatico dal portale).
const SPAWN_DURATION_MS: float = 900.0

# --- Segnali ---
# Emmesso quando il player gli spara addosso: il controller risponde con
# la risata tenebrosa (AudioManager DARK_LAUGH). Payload = posizione.
signal laughed(pos: Vector2)


# --- Stato posizione/movimento (mirror MiniBoss) ---
var pos: Vector2 = Vector2.ZERO:
	set(v):
		pos = v
		position = v

var dx: int = 0
var dy: int = 0
var last_dx: int = 1
var _move_waypoint: Vector2 = Vector2.INF
var stuck_timer_ms: int = 0
var last_pos: Vector2 = Vector2.ZERO
var maze: Node = null

# --- Animazione ---
var anim_time: float = 0.0

# --- Apparizione (fade-in dal portale) ---
var spawn_timer_ms: float = SPAWN_DURATION_MS

# --- Mock pulse (colpito: sobbalza di ghigno mentre ride) ---
var mock_timer_ms: float = 0.0
const MOCK_DURATION_MS: float = 350.0

# --- Sprite (caricato via SpriteManager come i nemici) ---
var _sprite_sheet = null  # SpriteManager.Sheet (SD 256x64, 4 frame)
var _sprite_loaded: bool = false

# --- Scia spettrale (posizioni recenti ridisegnate in alpha bassa) ---
var _trail_positions: Array = []
var _trail_timer_ms: float = 0.0
const TRAIL_INTERVAL_MS: float = 80.0
const TRAIL_MAX_POINTS: int = 7


# ============================================================
# Setup
# ============================================================
func setup(start_col: int, start_row: int) -> void:
	pos = Vector2(start_col * TILE_SIZE + TILE_SIZE / 2.0,
			start_row * TILE_SIZE + UI_HEIGHT + TILE_SIZE / 2.0)
	dx = 0
	dy = 0
	last_dx = 1
	_move_waypoint = Vector2.INF
	spawn_timer_ms = SPAWN_DURATION_MS
	mock_timer_ms = 0.0
	_load_sprite()


func _load_sprite() -> void:
	if SpriteManager == null:
		_sprite_loaded = false
		return
	if SpriteManager.has_method("get_sheet"):
		_sprite_sheet = SpriteManager.get_sheet("ghost_reaper")
		if _sprite_sheet == null and SpriteManager.has_method("load_all"):
			SpriteManager.load_all()
			_sprite_sheet = SpriteManager.get_sheet("ghost_reaper")
	_sprite_loaded = _sprite_sheet != null and _sprite_sheet.is_loaded()
	if not _sprite_loaded:
		# Fallback: si disegna procedurale (vedi _draw_primitives)
		print("[GhostReaper] WARNING: sheet ghost_reaper non caricato, uso il fallback procedurale")


# ============================================================
# API "immortale"
# ============================================================
# I proiettili NON fanno danno: quando il player gli spara, emette
# `laughed` (il controller suona la risata tenebrosa). Mai morto.
func take_damage(_dmg: int) -> void:
	mock_timer_ms = MOCK_DURATION_MS
	laughed.emit(pos)


func is_dead() -> bool:
	return false


func is_death_anim_done() -> bool:
	return false


func get_pixel_pos() -> Vector2:
	return pos


func get_enemy_name() -> String:
	return "The Immortal Reaper"


# ============================================================
# Update (grid-locked, mirror MiniBoss.update_step)
# ============================================================
func update_step(maze_ref: Node, player_grid_pos: Vector2i,
		_delta_ms: int) -> void:
	maze = maze_ref
	var delta_ms: int = maxi(1, _delta_ms)
	anim_time += float(delta_ms) * 0.001

	# Timer di apparizione / mock pulse.
	if spawn_timer_ms > 0.0:
		spawn_timer_ms = maxf(0.0, spawn_timer_ms - float(delta_ms))
	if mock_timer_ms > 0.0:
		mock_timer_ms = maxf(0.0, mock_timer_ms - float(delta_ms))

	# Scia spettrale: campiona la posizione ogni TRAIL_INTERVAL_MS.
	_trail_timer_ms += float(delta_ms)
	if _trail_timer_ms >= TRAIL_INTERVAL_MS:
		_trail_timer_ms = 0.0
		_trail_positions.push_front(pos)
		if _trail_positions.size() > TRAIL_MAX_POINTS:
			_trail_positions.pop_back()

	# --- Movimento grid-locked (mirror MiniBoss 59dec9c) ---
	var col := int(pos.x / TILE_SIZE)
	var row := int((pos.y - UI_HEIGHT) / TILE_SIZE)
	var center_x: float = col * TILE_SIZE + TILE_SIZE / 2.0
	var center_y: float = row * TILE_SIZE + TILE_SIZE / 2.0 + UI_HEIGHT
	var step_size: float = float(GHOST_SPEED) * (float(delta_ms) / 16.6667)

	# Anti-stuck tracking.
	var dx_pos: float = pos.x - last_pos.x
	var dy_pos: float = pos.y - last_pos.y
	if dx_pos * dx_pos + dy_pos * dy_pos < 1.0:
		stuck_timer_ms += delta_ms
	else:
		stuck_timer_ms = 0
	last_pos = pos

	# (1) Decisione SOLO a coincidenza ESATTA col centro cella.
	if pos.x == center_x and pos.y == center_y:
		var next := _bfs_path(Vector2i(col, row), player_grid_pos)
		if next != Vector2i(-1, -1):
			dx = next.x - col
			if dx != 0:
				last_dx = dx
			dy = next.y - row
			stuck_timer_ms = 0
		elif col == player_grid_pos.x and row == player_grid_pos.y:
			# Stessa cella del player: resta al centro (il danno da contatto
			# scatta nel controller, mirror melee dei nemici).
			dx = 0
			dy = 0
		else:
			_move_greedy(player_grid_pos)

		# Anti-stuck: direzione random aperta come ultima risorsa.
		if dx == 0 and dy == 0 and stuck_timer_ms > STUCK_THRESHOLD_MS:
			if _pick_random_open_dir(col, row):
				stuck_timer_ms = 0

		# Wall check point-based.
		if maze != null and maze.is_wall(col + dx, row + dy):
			dx = 0
			dy = 0
		# Waypoint LOCKED alla decisione.
		if dx != 0 or dy != 0:
			_move_waypoint = Vector2(center_x + dx * TILE_SIZE,
					center_y + dy * TILE_SIZE)
		else:
			_move_waypoint = Vector2.INF
	elif _move_waypoint == Vector2.INF:
		# Fermo ma decentrato, senza waypoint (stato anomalo): recovery.
		pos = pos.move_toward(Vector2(center_x, center_y), step_size)
		last_pos = pos
		dx = 0
		dy = 0

	# (2) Movimento verso il waypoint.
	if (dx != 0 or dy != 0) and _move_waypoint != Vector2.INF:
		pos = pos.move_toward(_move_waypoint, step_size)

	# Safety clamp (ultima difesa, mirror MiniBoss): se la cella corrente
	# è WALL (stato invalido), teleport al centro della cella aperta più
	# vicina (raggio 1-3). Con il movimento grid-locked non dovrebbe MAI
	# attivarsi in gioco.
	var cur_col_after: int = clampi(int(pos.x / TILE_SIZE), 0, MAZE_COLS - 1)
	var cur_row_after: int = clampi(int((pos.y - UI_HEIGHT) / TILE_SIZE), 0, MAZE_ROWS - 1)
	if maze != null and maze.is_wall(cur_col_after, cur_row_after):
		for snap_radius in range(1, 4):
			var found_safe: bool = false
			for sdc in range(-snap_radius, snap_radius + 1):
				for sdr in range(-snap_radius, snap_radius + 1):
					var nnc: int = cur_col_after + sdc
					var nnr: int = cur_row_after + sdr
					if nnc > 0 and nnc < MAZE_COLS - 1 \
							and nnr > 0 and nnr < MAZE_ROWS - 1:
						if not maze.is_wall(nnc, nnr):
							pos = Vector2(
									nnc * TILE_SIZE + TILE_SIZE / 2.0,
									nnr * TILE_SIZE + TILE_SIZE / 2.0 + UI_HEIGHT)
							last_pos = pos
							dx = 0
							dy = 0
							_move_waypoint = Vector2.INF
							stuck_timer_ms = 0
							found_safe = true
							break
				if found_safe:
					break
			if found_safe:
				break

	position = pos
	queue_redraw()


# BFS verso il player (mirror MiniBoss._bfs_path, cap 600 iterazioni).
func _bfs_path(start: Vector2i, target: Vector2i) -> Vector2i:
	if start == target:
		return Vector2i(-1, -1)
	if maze == null:
		return Vector2i(-1, -1)
	var queue: Array = [[start, Vector2i(-1, -1)]]
	var visited := {start: true}
	var dirs := [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]
	var iter := 0
	while queue.size() > 0 and iter < 600:
		iter += 1
		var entry: Array = queue.pop_front()
		var cur: Vector2i = entry[0]
		var first: Vector2i = entry[1]
		if cur == target:
			return first if first != Vector2i(-1, -1) else Vector2i(-1, -1)
		for d in dirs:
			var next: Vector2i = cur + d
			if next.x < 0 or next.x >= MAZE_COLS or next.y < 0 or next.y >= MAZE_ROWS:
				continue
			if maze.is_wall(next.x, next.y):
				continue
			if visited.has(next):
				continue
			visited[next] = true
			var nf: Vector2i = first if first != Vector2i(-1, -1) else next
			queue.append([next, nf])
	return Vector2i(-1, -1)


# Greedy avvicinamento (BFS irraggiungibile), mirror MiniBoss.
func _move_greedy(target_grid: Vector2i) -> void:
	var col := int(pos.x / TILE_SIZE)
	var row := int((pos.y - UI_HEIGHT) / TILE_SIZE)
	var best_dx: int = 0
	var best_dy: int = 0
	var min_dist: float = 999999.0
	var any_open: bool = false
	for i in range(4):
		var nc: int = col + _DC[i]
		var nr: int = row + _DR[i]
		if maze != null and maze.is_wall(nc, nr):
			continue
		any_open = true
		var dist: float = float((nc - target_grid.x) * (nc - target_grid.x)
				+ (nr - target_grid.y) * (nr - target_grid.y))
		if _DC[i] == -dx and _DR[i] == -dy:
			dist += 10.0
		if dist < min_dist:
			min_dist = dist
			best_dx = _DC[i]
			best_dy = _DR[i]
	if any_open and best_dx == 0 and best_dy == 0:
		_pick_random_open_dir(col, row)
		return
	dx = best_dx
	if dx != 0:
		last_dx = dx
	dy = best_dy


# Direzione random aperta (anti-stuck), mirror MiniBoss.
func _pick_random_open_dir(col: int, row: int) -> bool:
	var start: int = randi() % 4
	for i in range(4):
		var idx: int = (start + i) % 4
		var nc: int = col + _DC[idx]
		var nr: int = row + _DR[idx]
		if maze != null and not maze.is_wall(nc, nr):
			dx = _DC[idx]
			if dx != 0:
				last_dx = dx
			dy = _DR[idx]
			return true
	dx = 0
	dy = 0
	return false


# ============================================================
# Rendering
# ============================================================
func _draw() -> void:
	# Alpha complessiva: fade-in durante l'apparizione, poi leggera
	# pulsazione spettrale (0.78..0.92).
	var spawn_ratio: float = 1.0 - (spawn_timer_ms / SPAWN_DURATION_MS)
	var base_alpha: float = 0.78 + 0.14 * (0.5 + 0.5 * sin(anim_time * 2.6))
	var alpha: float = lerpf(0.15, base_alpha, spawn_ratio)

	# Mock pulse (colpito): sobbalza leggermente mentre "ride".
	var mock_ratio: float = 0.0
	if mock_timer_ms > 0.0:
		mock_ratio = mock_timer_ms / MOCK_DURATION_MS

	# Fluttuazione (il fantasma non cammina: ondeggia).
	var bob_y: float = sin(anim_time * 2.2) * 3.0
	var sway_x: float = sin(anim_time * 1.3) * 1.2

	# --- Scia spettrale (dietro il corpo) ---
	for k in range(_trail_positions.size()):
		var tp: Vector2 = _trail_positions[k]
		var t_alpha: float = 0.22 * (1.0 - float(k) / float(TRAIL_MAX_POINTS)) * alpha
		var t_rad: float = 10.0 - float(k) * 1.0
		draw_circle(tp - pos, t_rad,
				Color(0.45, 0.95, 0.55, t_alpha))

	# --- Aura ectoplasmatica ---
	var aura_r: float = 34.0 + sin(anim_time * 3.1) * 3.0
	draw_circle(Vector2(sway_x, bob_y), aura_r + 10.0,
			Color(0.30, 0.85, 0.45, 0.08 * alpha + 0.02))
	draw_circle(Vector2(sway_x, bob_y), aura_r,
			Color(0.35, 0.95, 0.50, 0.12 * alpha + 0.03))
	# Wisps orbitanti.
	for i in 6:
		var ang: float = anim_time * 1.7 + (float(i) / 6.0) * TAU
		var wobble: float = 28.0 + sin(anim_time * 2.0 + i * 1.9) * 5.0
		var wp: Vector2 = Vector2(sway_x + cos(ang) * wobble,
				bob_y + sin(ang) * wobble * 0.7)
		draw_circle(wp, 2.2,
				Color(0.55, 1.0, 0.65, (0.30 + 0.15 * sin(anim_time * 4.0 + i)) * alpha))

	# --- Corpo (sheet come i nemici, 78px, bob fluttuante) ---
	var target_size: float = GHOST_SIZE * (1.0 + 0.10 * mock_ratio)
	var tw: float = target_size
	var th: float = target_size
	if _sprite_loaded and _sprite_sheet != null:
		var at: AtlasTexture = _frame_texture()
		if at != null:
			var dest_rect: Rect2 = Rect2(
					Vector2(-tw * 0.5 + sway_x, -th * 0.5 + bob_y),
					Vector2(tw, th))
			if last_dx < 0:
				draw_set_transform(
						Vector2(dest_rect.position.x + dest_rect.size.x * 0.5, 0.0),
						0.0, Vector2(-1.0, 1.0))
				# FIX trasparenza: draw_texture_rect con modulate parametro
				# (Godot 4.7: draw_texture_rect(texture, rect, tile, modulate)).
				draw_texture_rect(at, dest_rect, false,
						Color(1.0, 1.0, 1.0, alpha))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			else:
				draw_texture_rect(at, dest_rect, false,
						Color(1.0, 1.0, 1.0, alpha))
	else:
		_draw_primitives(alpha, bob_y, sway_x, target_size)

	# --- Anelli di scherno quando viene colpito (ride di te) ---
	if mock_ratio > 0.0:
		for ring in 2:
			var rr: float = (1.0 - mock_ratio) * 46.0 + 14.0 + ring * 12.0
			draw_circle_arc(Vector2(sway_x, bob_y), rr,
					0.0, TAU,
					Color(0.75, 1.0, 0.80, 0.45 * mock_ratio))


# Frame dallo sheet SD (4 frame con bob, ciclo walk ~130ms).
func _frame_texture() -> AtlasTexture:
	if _sprite_sheet == null:
		return null
	var frame_count: int = _sprite_sheet.get_frame_count("walk")
	if frame_count <= 0:
		frame_count = _sprite_sheet.get_frame_count("idle")
	if frame_count <= 0:
		return null
	var frame: int = (int(anim_time * 1000.0) / 130) % frame_count
	var at: AtlasTexture = _sprite_sheet.get_frame_texture("walk", frame)
	if at == null:
		at = _sprite_sheet.get_frame_texture("idle", 0)
	return at


# Cerchio aperto (outline) — helper per gli anelli di scherno.
func draw_circle_arc(center: Vector2, radius: float, start_angle: float,
		end_angle: float, color: Color, segments: int = 40) -> void:
	var points := PackedVector2Array()
	for i in segments + 1:
		var a: float = start_angle + (end_angle - start_angle) * float(i) / float(segments)
		points.append(center + Vector2(cos(a), sin(a)) * radius)
	draw_polyline(points, color, 2.0, true)


# Fallback procedurale (se lo sheet non è disponibile): teschio + braccia.
func _draw_primitives(alpha: float, bob_y: float, sway_x: float,
		size_px: float) -> void:
	var s: float = size_px / 78.0
	var ghost_green: Color = Color(0.55, 0.95, 0.60, alpha)
	var bone: Color = Color(0.88, 0.92, 0.85, alpha)
	var dark: Color = Color(0.10, 0.22, 0.14, alpha)
	var cx: float = sway_x
	var cy: float = bob_y
	# Corpo ectoplasmatico (blob ondulato).
	var body_pts := PackedVector2Array()
	for i in 20:
		var ang: float = PI + (PI * float(i) / 19.0)
		var wob: float = 1.0 + 0.08 * sin(ang * 3.0 + anim_time * 3.0)
		body_pts.append(Vector2(cx + cos(ang) * 24.0 * s * wob,
				cy + 12.0 * s + sin(ang) * 6.0 * s))
	draw_colored_polygon(body_pts, ghost_green)
	draw_circle(Vector2(cx, cy - 4.0 * s), 26.0 * s, ghost_green)
	# Teschio.
	draw_circle(Vector2(cx, cy - 10.0 * s), 15.0 * s, bone)
	draw_rect(Rect2(cx - 10.0 * s, cy - 2.0 * s, 20.0 * s, 9.0 * s), bone, true)
	# Orbite.
	draw_circle(Vector2(cx - 5.5 * s, cy - 11.0 * s), 4.0 * s, dark)
	draw_circle(Vector2(cx + 5.5 * s, cy - 11.0 * s), 4.0 * s, dark)
	# Ghigno.
	for t in 3:
		draw_rect(Rect2(cx - 7.5 * s + t * 5.5 * s, cy + 1.0 * s,
				3.0 * s, 5.5 * s), dark, true)
	# Braccia scheletriche (ossa raggiunge il player).
	for side in [-1, 1]:
		var arm_y: float = cy + 2.0 * s + side * 4.0 * s
		draw_line(Vector2(cx + side * 12.0 * s, arm_y),
				Vector2(cx + side * 30.0 * s, arm_y - 8.0 * s),
				bone, 4.0 * s)
		draw_circle(Vector2(cx + side * 32.0 * s, arm_y - 9.0 * s),
				3.4 * s, bone)
