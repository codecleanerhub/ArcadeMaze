## perf_maze81.gd — TASK 81: benchmark A/B delle due nuove meccaniche
## (fantasmi lenzuolo + celle zombie) nello STESSO run:
##   - fase 1: GHOSTS + ZOMBIE_CELLS ON  ~4s
##   - fase 2: entrambi OFF             ~4s
## Misura avg / p95 / worst ms per frame (Xvfb attivo, niente vsync).
## Uso: scripts/xvfb_shot.sh 1920x1080 res://tests/perf_maze81.tscn 120
extends Node

const C = preload("res://scripts/core/GameConstants.gd")
const MainGameScene = preload("res://scenes/MainGame.tscn")

const WARMUP_S: float = 1.5
const MEASURE_S: float = 4.0
const SETTLE_S: float = 0.5

var main: Node2D = null
var stage: int = 0
var t: float = 0.0
var deltas: Array = []


func _ready() -> void:
        process_mode = Node.PROCESS_MODE_ALWAYS
        LoadingScreen.skip_boot_hold()
        GameManager.reset_run()
        GameManager.current_level = 8  # 3 celle zombie + ritmo fantasmi alto
        main = MainGameScene.instantiate()
        get_tree().root.add_child.call_deferred(main)
        print("[PERF81] harness maze L8, A/B meccaniche on/off")


func _process(delta: float) -> void:
        t += delta
        if main == null or not main.is_node_ready():
                return
        match stage:
                0:
                        if t >= WARMUP_S:
                                deltas.clear()
                                stage = 1
                                t = 0.0
                1:  # misura con ON
                        deltas.append(delta)
                        if t >= MEASURE_S:
                                _report("ON  ")
                                C.GHOSTS_ENABLED = false
                                C.ZOMBIE_CELLS_ENABLED = false
                                stage = 2
                                t = 0.0
                2:  # assestamento
                        if t >= SETTLE_S:
                                deltas.clear()
                                stage = 3
                                t = 0.0
                3:  # misura con OFF
                        deltas.append(delta)
                        if t >= MEASURE_S:
                                _report("OFF ")
                                C.GHOSTS_ENABLED = true
                                C.ZOMBIE_CELLS_ENABLED = true
                                print("[PERF81] done")
                                get_tree().quit(0)


func _report(label: String) -> void:
        if deltas.is_empty():
                return
        var s: Array = deltas.duplicate()
        s.sort()
        var n: int = s.size()
        var total: float = 0.0
        for d in s:
                total += d
        var avg_ms: float = total / float(n) * 1000.0
        var p95_ms: float = s[int(float(n) * 0.95)] * 1000.0
        var worst_ms: float = s[n - 1] * 1000.0
        print("[PERF81] %s: n=%d avg=%.2fms p95=%.2fms worst=%.2fms | celle=%d fantasmi=%d" % [
                label, n, avg_ms, p95_ms, worst_ms,
                main.zombie_cells.cell_count(), main.maze_ghosts.active_count(),
        ])
