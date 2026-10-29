## perf_maze80.gd — TASK 80: benchmark prestazioni del LABIRINTO con le
## luci lanterne (pozze bakeate + alone + 6 PointLight2D raggio 140).
##
## Boot MainGame (maze) livello 2 con l'ELF, poi misura A/B nello STESSO run:
##   - fase 1: LANTERNE ON  (default) per ~4s
##   - fase 2: LANTERNE OFF (flag runtime, niente rebuild) per ~4s
##
## Misura avg / p50 / p95 / worst ms per frame (renderer Xvfb attivo, niente
## vsync: delta = costo reale del frame) + torce/pozze contate dal Maze.
##
## Uso: scripts/xvfb_shot.sh 1920x1080 res://tests/perf_maze80.tscn 120
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
        GameManager.player1_character = C.CharacterType.ELF
        GameManager.current_level = 2
        main = MainGameScene.instantiate()
        get_tree().root.add_child.call_deferred(main)
        print("[PERF80] harness maze livello 2 (elf), A/B lanterne on/off")


func _process(delta: float) -> void:
        t += delta
        if main == null or not main.is_node_ready():
                return
        match stage:
                0:  # warmup (maze generato, nemici in caccia)
                        if t >= WARMUP_S:
                                deltas.clear()
                                stage = 1
                                t = 0.0
                1:  # misura con LANTERNE ON
                        deltas.append(delta)
                        if t >= MEASURE_S:
                                _report("LANTERNE ON ")
                                C.LANTERN_LIGHT_ENABLED = false
                                stage = 2
                                t = 0.0
                2:  # assestamento (un frame col flag nuovo basta, ma abbondiamo)
                        if t >= SETTLE_S:
                                deltas.clear()
                                stage = 3
                                t = 0.0
                3:  # misura con LANTERNE OFF
                        deltas.append(delta)
                        if t >= MEASURE_S:
                                _report("LANTERNE OFF")
                                C.LANTERN_LIGHT_ENABLED = true
                                print("[PERF80] done")
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
        var p50_ms: float = s[n / 2] * 1000.0
        var p95_ms: float = s[int(float(n) * 0.95)] * 1000.0
        var worst_ms: float = s[n - 1] * 1000.0
        var n_torches: int = main.maze._all_torch_positions.size()
        var n_pool: int = n_torches * 2 + main.maze.player_light_positions.size()
        print("[PERF80] %s: n=%d avg=%.2fms p50=%.2fms p95=%.2fms worst=%.2fms | torce=%d draw_pozze/frame=%d" % [
                label, n, avg_ms, p50_ms, p95_ms, worst_ms, n_torches, n_pool,
        ])
