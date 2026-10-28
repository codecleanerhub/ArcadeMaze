## perf_boss79d.gd — TASK 79d: benchmark prestazioni boss fight (fase 2).
##
## Per OGNI tipo di boss (0..16): istanzia BossRoom, forza la FASE 2
## (energia al di sotto del 50%), mantiene il player invulnerabile e misura
## i tempi di frame REALI (renderer Xvfb attivo, niente vsync = delta è il
## costo effettivo del frame) per ~4s.
##
## Misura: avg / p95 / worst ms per frame + contatori oggetti (proiettili+FX
## vivi, buche attive) per capire il carico per boss.
##
## Uso: scripts/xvfb_shot.sh 1920x1080 res://tests/perf_boss79d.tscn 600
## Output: tabella + JSON in /tmp/perf_boss79d.json (baseline vs post-fix).
extends Node

const BossRoomScene = preload("res://scenes/BossRoom.tscn")
const C = preload("res://scripts/core/GameConstants.gd")
const BossScript = preload("res://scripts/bosses/Boss.gd")

const BOSS_COUNT: int = 17
const WARMUP_S: float = 1.0
const MEASURE_S: float = 4.0

var boss_idx: int = 0
var stage: int = 0
var t: float = 0.0
var room: Node2D = null

# misure del boss corrente
var deltas: Array = []
var max_children: int = 0
var max_pits: int = 0
var rows: Array = []

# ripristino config a fine test
var _orig_lang: int = 0


func _ready() -> void:
        process_mode = Node.PROCESS_MODE_ALWAYS
        LoadingScreen.skip_boot_hold()
        GameManager.reset_run()
        _orig_lang = I18n.language
        print("[PERF] harness avviato: 17 boss, fase 2 forzata")


func _process(delta: float) -> void:
        t += delta
        match stage:
                0:  # istanzia la stanza del boss corrente
                        if room == null:
                                _boot_room()
                        elif room.is_node_ready() and room.boss != null:
                                _force_phase2()
                                stage = 1
                                t = 0.0
                1:  # warmup (popola la scena: spari, FX, buche)
                        _keep_player_alive()
                        if t >= WARMUP_S:
                                deltas.clear()
                                stage = 2
                                t = 0.0
                2:  # misura
                        _keep_player_alive()
                        deltas.append(delta)
                        var n_kids: int = room.boss_projectiles_node.get_child_count()
                        if n_kids > max_children:
                                max_children = n_kids
                        if room.boss_pits.size() > max_pits:
                                max_pits = int(room.boss_pits.size())
                        if t >= MEASURE_S:
                                _record_row()
                                _next_boss()
                _:
                        pass


func _boot_room() -> void:
        # livello = boss_idx*4 -> get_boss_index = (livello/4) % 17 = boss_idx
        # (boss 0 = GOLEM: livello 68 -> 17 % 17 = 0; evita il livello 0)
        var level: int = 68 if boss_idx == 0 else boss_idx * 4
        GameManager.current_level = level
        room = BossRoomScene.instantiate()
        get_tree().root.add_child.call_deferred(room)
        print("[PERF] boss %d/17 (%s) — livello %d" % [
                        boss_idx + 1, BossScript.get_boss_name(boss_idx), level])


func _force_phase2() -> void:
        var b = room.boss
        b.health = int(float(b.max_health) * C.BOSS_PHASE2_TRIGGER_RATIO) - 5
        if b.health < 1:
                b.health = 1
        room.player.spawn_guard_ms = 600000.0
        if room.player2:
                room.player2.spawn_guard_ms = 600000.0
        print("[PERF] fase 2 forzata: HP %d/%d" % [b.health, b.max_health])


func _keep_player_alive() -> void:
        var p = room.player
        if p:
                p.spawn_guard_ms = 600000.0
                p.energy = 999.0
                p.lives = 9


func _record_row() -> void:
        deltas.sort()
        var n: int = deltas.size()
        if n == 0:
                return
        var total: float = 0.0
        for d in deltas:
                total += d
        var p95: float = deltas[int(clampf(n * 0.95, 0.0, float(n - 1)))] * 1000.0
        rows.append({
                "boss": BossScript.get_boss_name(boss_idx),
                "type": boss_idx,
                "avg_ms": snappedf(total / float(n) * 1000.0, 0.01),
                "p95_ms": snappedf(p95, 0.01),
                "worst_ms": snappedf(deltas[n - 1] * 1000.0, 0.01),
                "frames": n,
                "max_proj_children": max_children,
                "max_pits": max_pits,
        })
        var r: Dictionary = rows[rows.size() - 1]
        print("[PERF] %-28s avg %6.2f  p95 %6.2f  worst %6.2f ms  (obj max %d, buche %d, frame %d)" % [
                        r.boss, r.avg_ms, r.p95_ms, r.worst_ms,
                        r.max_proj_children, r.max_pits, r.frames])


func _next_boss() -> void:
        room.queue_free()
        room = null
        deltas = []
        max_children = 0
        max_pits = 0
        boss_idx += 1
        if boss_idx >= BOSS_COUNT:
                _finish()
                return
        stage = 0
        t = 0.0


func _finish() -> void:
        var f := FileAccess.open("/tmp/perf_boss79d.json", FileAccess.WRITE)
        if f:
                f.store_string(JSON.stringify(rows, "  "))
                f.close()
        # aggregato
        var tot_avg: float = 0.0
        var tot_worst: float = 0.0
        var tot_p95: float = 0.0
        for r in rows:
                tot_avg += r.avg_ms
                tot_worst += r.worst_ms
                tot_p95 += r.p95_ms
        print("[PERF] ==== TOTALE (17 boss): avg %.2f  p95 %.2f  worst %.2f ms ====" % [
                        tot_avg / float(rows.size()), tot_p95 / float(rows.size()),
                        tot_worst / float(rows.size())])
        I18n.set_language(_orig_lang)
        get_tree().quit(0)
