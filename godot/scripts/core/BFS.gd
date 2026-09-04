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

# Maze grid dimensions (mirror Utils.h)
const TILE_SIZE: int = 48
const MAZE_COLS: int = 21
const MAZE_ROWS: int = 19

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
			# Bounds + wall check (out of grid treated as wall by is_wall).
			if nc < 0 or nc >= MAZE_COLS or nr < 0 or nr >= MAZE_ROWS:
				continue
			var nb := Vector2i(nc, nr)
			if visited.has(nb):
				continue
			if maze.is_wall(nc, nr):
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
	return curr


# ---------------------------------------------------------------------------
# find_path_dir: convenience wrapper that returns the *direction* (dx, dy)
# the enemy should move on this frame, or Vector2i.ZERO if no path.
# Useful for enemies that just want to know which way to step.
# ---------------------------------------------------------------------------
static func find_path_dir(maze: Object, start: Vector2i, target: Vector2i) -> Vector2i:
	var next := find_path(maze, start, target)
	if next.x < 0:
		return Vector2i.ZERO
	return next - start
