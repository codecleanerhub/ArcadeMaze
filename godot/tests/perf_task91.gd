## perf_task91.gd — TASK 91: benchmark dei frame attorno alle DISTRUZIONI
## degli elementi ambientali della boss room (rovine + barili), con i fix
## applicati (prewarm EffectsManager, spawn deferred, sbuffi ridotti,
## redraw condizionale del pilastro, SFX arena in testa alla coda synth).
##
## Scenario: boot BossRoom (LICH), player invulnerabile; ogni ~500ms viene
## distrutta una rovina (3 colpi) o detonato un barile; quando non restano
## rovine in piedi l'arena si rinnova (_spawn_boss_arena). 24s di misura.
## Report: avg / p95 / worst ms + istogramma (>16.6 / >25 / >40 ms).
## Uso (Xvfb + llvmpipe, niente vsync):
##   DISPLAY=:66 <godot> --path . res://tests/perf_task91.tscn --resolution 1920x1080
extends Node

const BossRoomScene = preload("res://scenes/BossRoom.tscn")
const C = preload("res://scripts/core/GameConstants.gd")

var room: Node2D = null
var t: float = 0.0
var warmup: float = 1.0
var measure_s: float = 24.0
var next_action: float = 1.5
var deltas: Array[float] = []
var destroyed: int = 0
var detonated: int = 0
var renewals: int = 0


func _ready() -> void:
        process_mode = Node.PROCESS_MODE_ALWAYS
        LoadingScreen.skip_boot_hold()
        GameManager.reset_run()
        GameManager.current_level = 4
        GameManager.died_in_boss = false
        room = BossRoomScene.instantiate()
        get_tree().root.add_child.call_deferred(room)
        print("[PERF91] boot BossRoom (LICH) — distruzioni ripetute con fix attivi")


func _process(delta: float) -> void:
        t += delta
        if room == null or not room.is_node_ready():
                return
        if room.player != null:
                room.player.spawn_guard_ms = 600000.0
                room.player.energy = 999.0
        if t < warmup:
                return
        if t - warmup <= measure_s:
                deltas.append(delta)
        # azione periodica: distruggi una rovina o detona un barile
        if t >= next_action:
                next_action = t + 0.5
                _do_destruction()
        if t - warmup >= measure_s and deltas.size() > 60:
                _report()
                get_tree().quit(0)


func _do_destruction() -> void:
        # prima una rovina in piedi (3 colpi = crollo)
        for ruin in room._arena_ruins:
                if ruin != null and is_instance_valid(ruin) and ruin.is_standing():
                        var pos: Vector2 = ruin.position
                        for i in 3:
                                ruin.take_hit()
                        room._damage_ruin(ruin, pos)
                        destroyed += 1
                        return
        # poi un barile (detonazione)
        for child in room.boss_room_weapons_node.get_children():
                if child.get_script() != null \
                                and child.get_script().get_path().find("ElementalBarrel") >= 0 \
                                and child.state == 0:
                        child.detonate()
                        detonated += 1
                        return
        # niente piu' bersagli: rinnova l'arena (rovine fresche)
        room._clear_boss_arena()
        room._spawn_boss_arena()
        renewals += 1


func _report() -> void:
        deltas.sort()
        var n: int = deltas.size()
        var total: float = 0.0
        for d in deltas:
                total += d
        var avg: float = total / float(n) * 1000.0
        var p95: float = deltas[int(clampf(float(n) * 0.95, 0.0, float(n - 1)))] * 1000.0
        var worst: float = deltas[n - 1] * 1000.0
        var over16: int = 0
        var over25: int = 0
        var over40: int = 0
        for d in deltas:
                var ms: float = d * 1000.0
                if ms > 16.6:
                        over16 += 1
                if ms > 25.0:
                        over25 += 1
                if ms > 40.0:
                        over40 += 1
        print("[PERF91] frame=%d  avg=%.2fms  p95=%.2fms  worst=%.2fms" % [
                        n, avg, p95, worst])
        print("[PERF91] istogramma: >16.6ms=%d (%.1f%%)  >25ms=%d (%.1f%%)  >40ms=%d (%.1f%%)" % [
                        over16, float(over16) * 100.0 / float(n),
                        over25, float(over25) * 100.0 / float(n),
                        over40, float(over40) * 100.0 / float(n)])
        print("[PERF91] eventi: rovine crollate=%d  barili detonati=%d  rinnovi arena=%d" % [
                        destroyed, detonated, renewals])
        # NOTA METRICA: su llvmpipe (rendering SOFTWARE) la baseline di un
        # frame pieno 1920x1080 e' ~100-150ms: il segnale di uno SCATTO da
        # distruzione non e' il valore assoluto ma lo SPIKE RELATIVO rispetto
        # alla baseline locale. Prima dei fix (first-use Image.load + upload
        # GPU + burst di nodi nel frame del crollo) lo spike era >>2x la
        # media; criterio di riuscita post-fix: worst <= 1.6x la media e
        # p95 <= 1.35x (nessun outlier isolato significativo).
        var spike: float = worst / maxf(avg, 0.01)
        print("[PERF91] spike-ratio worst/avg = %.2fx (baseline llvmpipe %.1fms)" % [
                        spike, avg])
        if spike > 1.6 or p95 > avg * 1.35:
                print("[PERF91] ESITO: FAIL (spike %.2fx > 1.6x o p95 %.2fx > 1.35x avg)" % [
                                spike, p95 / maxf(avg, 0.01)])
        else:
                print("[PERF91] ESITO: OK — nessuno scatto relativo significativo alle distruzioni")
