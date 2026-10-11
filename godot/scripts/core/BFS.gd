# ===========================================================================
# BFS.gd - Static pathfinding utility for the maze grid.
#
# Direct port of the BFS algorithm in src/Enemy.cpp (Enemy::bfsPath).
# Uses a standard breadth-first-search on the 4-connected grid of the maze
# to find the SHORTEST PATH from `start` to `target`, then returns the
# next cell the enemy should step onto.
#
# Constants (matching src/Utils.h):
#   TILE_SIZE  = 48
#   MAZE_COLS  = 21
#   MAZE_ROWS  = 19
#
# Usage:
#   var next := BFS.find_path(maze, start_cell, target_cell)
#   if next != Vector2i(-1, -1):
#       var dir := next - start_cell
#       # move by `dir`
#
# `maze` is a Maze node (or any Object exposing `is_wall(col, row)`).
# `start` / `target` are Vector2i in grid coordinates (col, row).
# Returns Vector2i(-1, -1) if no path exists.
# ===========================================================================
class_name BFS
extends RefCounted

# Maze grid dimensions — use GameConstants (FIX: erano hardcoded a 21x19,
# ma ora il maze è 40x22. I nemici nella parte destra/bassa non trovavano
# percorso perché il BFS scartava tutte le celle oltre col 21 / row 19).
const C = preload("res://scripts/core/GameConstants.gd")
const TILE_SIZE: int = C.TILE_SIZE
const MAZE_COLS: int = C.MAZE_COLS
const MAZE_ROWS: int = C.MAZE_ROWS

# 4-connected neighbours. Order matches the C++ dc[]/dr[] arrays
# (up, right, down, left). Important: keeps BFS deterministic and
# identical to the C++ version so enemies behave the same.
const _DC: Array[int] = [0, 1, 0, -1]
const _DR: Array[int] = [-1, 0, 1, 0]


# ---------------------------------------------------------------------------
# find_path: BFS over the maze grid.
#
# Returns the FIRST cell on the shortest path from `start` to `target`
# (i.e. the next step the enemy should take). Returns Vector2i(-1, -1) if
# `start == target` or no path exists.
#
# Mirrors Enemy::bfsPath() in src/Enemy.cpp line 217-245.
# ---------------------------------------------------------------------------
static func find_path(maze: Object, start: Vector2i, target: Vector2i) -> Vector2i:
        # Same cell: nothing to do (mirrors early-return in C++).
        if start == target:
                return Vector2i(-1, -1)

        # 2D visited / parent maps. Using Dictionary keyed by Vector2i keeps
        # allocation cheap and avoids building 21*19 vectors per call.
        var visited: Dictionary = {}
        var parent: Dictionary = {}

        var queue: Array[Vector2i] = []
        queue.append(start)
        visited[start] = true

        var found: bool = false
        var head: int = 0
        while head < queue.size():
                var curr: Vector2i = queue[head]
                head += 1
                if curr == target:
                        found = true
                        break
                for i in range(4):
                        var nc: int = curr.x + _DC[i]
                        var nr: int = curr.y + _DR[i]
                        var nb := Vector2i(nc, nr)
                        # FIX (tunnel Pac-Man): fuori griglia e' valido SOLO se
                        # e' la prosecuzione VIRTUALE di una galleria: in quel
                        # caso il vicino di grafo reale e' la cella di bordo
                        # OPPOSTA (chi entra riemerge dall'altro lato), cosi'
                        # il BFS considera il tunnel la via piu' corta per
                        # attraversare il labirinto.
                        if nc < 0 or nc >= MAZE_COLS or nr < 0 or nr >= MAZE_ROWS:
                                if not C.is_tunnel_virtual_cell(nc, nr):
                                        continue
                                var partner := C.tunnel_partner(curr.x, curr.y)
                                if partner.x < 0:
                                        continue
                                nb = partner
                        if visited.has(nb):
                                continue
                        if maze.is_wall(nb.x, nb.y):
                                continue
                        visited[nb] = true
                        parent[nb] = curr
                        queue.append(nb)

        if not found:
                return Vector2i(-1, -1)

        # Walk parent chain from target back to the cell whose parent is `start`:
        # that cell is the first step away from start (i.e. nextStep in C++).
        var curr: Vector2i = target
        while parent.has(curr) and parent[curr] != start:
                curr = parent[curr]

        # If target itself is adjacent to start, parent[target] == start and the
        # loop above never executes - curr stays as target, which is correct.
        # FIX (tunnel Pac-Man): se il primo passo e' un EDGE di galleria, la
        # cella risalita NON e' adiacente a start (es. (14,0) -> (14,14)):
        # la direzione reale da seguire e' quella della cella VIRTUALE di
        # uscita (es. (14,-1) = su), che il chiamante traduce in dy=-1 e
        # waypoint nel tunnel. Senza questo fix dx/dy sarebbe 0/14 (invalido).
        var step_d: Vector2i = curr - start
        if abs(step_d.x) > 1 or abs(step_d.y) > 1:
                var ex: int = 0
                var ey: int = 0
                if absi(step_d.x) > 1:
                        ex = -signi(step_d.x)
                else:
                        ey = -signi(step_d.y)
                return Vector2i(start.x + ex, start.y + ey)
        return curr


# ---------------------------------------------------------------------------
# find_path_dir: convenience wrapper that returns the *direction* (dx, dy)
# the enemy should move on this frame, or Vector2i.ZERO if no path.
# Useful for enemies that just want to know which way to step.
# ---------------------------------------------------------------------------
static func find_path_dir(maze: Object, start: Vector2i, target: Vector2i) -> Vector2i:
        var next := find_path(maze, start, target)
        # FIX (tunnel): non basta testare next.x < 0: la prima cella del
        # passo puo' essere la VIRTUALE della galleria sinistra (-1,7),
        # che e' una direzione valida (-1, 0). Confrontiamo il sentinella
        # esatto di "nessun percorso".
        if next == Vector2i(-1, -1):
                return Vector2i.ZERO
        return next - start
