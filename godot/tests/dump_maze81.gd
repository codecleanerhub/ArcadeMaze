## dump_maze81.gd — TASK 81b: dump headless della geometria delle celle
## zombie per la verifica pixel degli screenshot (stessi seed di
## shot_task81.gd: stesse celle, stesse facciate).
##
## Stampa su stdout una riga "DUMP81 <json>" per livello con:
##   wall_color  [r,g,b]   — palette del livello (Maze.generate)
##   cells       [{c,r,dir:[dx,dy]}]
##   ref_walls   [[c,r]x3] — piastrelle muro lontane dalle celle (riferi-
##                            mento per il check "niente quadrato chiaro")
##
## Uso: Godot --headless --path . res://tests/dump_maze81.tscn
extends Node

const C = preload("res://scripts/core/GameConstants.gd")
const MazeScript = preload("res://scripts/core/Maze.gd")
const ZombieCellsScript = preload("res://scripts/entities/ZombieCells.gd")


func _ready() -> void:
        # stesso reset dello shot script: il maze del MainGame e' generato
        # dopo GameManager.reset_run() (RNG globale deterministicato).
        GameManager.reset_run()
        for lvl in [2, 8]:
                var maze: Node = MazeScript.new()
                add_child(maze)
                maze.generate(lvl)
                var zc: Node = ZombieCellsScript.new()
                add_child(zc)
                zc.generate(lvl, maze)
                var cells: Array = []
                for p in zc.cell_positions():
                        var d: Vector2i = zc.cell_facing(p.x, p.y)
                        cells.append({"c": p.x, "r": p.y, "dir": [d.x, d.y]})
                # muri di riferimento: 3 celle WALL statiche lontane dalle
                # celle zombie (>= 4 Manhattan) per confronto luminanza
                var refs: Array = []
                var done: bool = false
                for r in range(2, C.MAZE_ROWS - 2):
                        if done:
                                break
                        for c in range(2, C.MAZE_COLS - 2):
                                if not maze.is_wall(c, r):
                                        continue
                                if maze.dynamic_walls.has("%d,%d" % [c, r]):
                                        continue
                                var far: bool = true
                                for p in zc.cell_positions():
                                        if absi(c - p.x) + absi(r - p.y) < 4:
                                                far = false
                                                break
                                if far:
                                        refs.append([c, r])
                                        if refs.size() >= 3:
                                                done = true
                                                break
                var wc: Color = maze.wall_color
                var payload: Dictionary = {
                        "level": lvl,
                        "wall_color": [wc.r, wc.g, wc.b],
                        "cells": cells,
                        "ref_walls": refs,
                }
                print("DUMP81 ", JSON.stringify(payload))
        get_tree().quit(0)
