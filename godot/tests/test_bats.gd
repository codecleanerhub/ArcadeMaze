## test_bats.gd — Test funzionale runtime (headless) della NUBE DI
## PIPISTRELLI (Task 32):
##   A. COSTANTI: bat_events_for_level (0 < liv 5, 1 fino al 30, 2 dal 31),
##      rollback BATS_ENABLED.
##   B. SCHEDULING: start_level(10) -> 1 evento armato con timer in finestra;
##      timer forzato -> spawn dello sciame LONTANO dal player (>= 6 celle).
##   C. CACCIA: lo sciame si avvicina al player (volo libero sopra i muri).
##   D. MORSO: player a contatto = -20% energia max, poi FLEE (niente
##      secondo morso immediato grazie al cooldown).
##   E. ABBATTIMENTO: 1° colpo = -1 pipistrello; 2° colpo = dispersione
##      +5000 punti al tiratore; controller libera lo sciame.
##   F. SCADENZA: lifetime esaurito -> vola via (LEAVE) -> gone.
##   G. ROLLBACK: BATS_ENABLED=false -> nessun evento armato.
extends Node

const C = preload("res://scripts/core/GameConstants.gd")
const H = preload("res://scripts/entities/MazeHazards.gd")
const BC = preload("res://scripts/entities/BatCloud.gd")
const MainGameScene = preload("res://scenes/MainGame.tscn")

var main: Node2D = null
var phase: int = 0
var t: float = 0.0
var phase_t: float = 0.0
var failures: Array = []


func _ready() -> void:
        print("[TEST] boot MainGame per nube di pipistrelli...")
        main = MainGameScene.instantiate()
        get_tree().root.add_child.call_deferred(main)


func _fail(msg: String) -> void:
        failures.append(msg)
        print("[TEST FAIL] ", msg)


func _ok(msg: String) -> void:
        print("[TEST] OK ", msg)


func _next(next_phase: int) -> void:
        phase = next_phase
        phase_t = 0.0


func _physics_process(delta: float) -> void:
        t += delta
        phase_t += delta
        if t > 60.0:
                _fail("timeout globale del test (60s)")
                get_tree().quit(1)
                return
        match phase:
                0:
                        if phase_t > 0.1:
                                _phaseA_constants()
                                _next(1)
                1:
                        if main == null or not main.is_node_ready():
                                return
                        if phase_t > 1.5:
                                _phaseB_scheduling()
                                _next(2)
                2:
                        _phaseC_chase()
                        _next(3)
                3:
                        _phaseD_bite()
                        _next(4)
                4:
                        _phaseE_kill()
                        _next(5)
                5:
                        _phaseF_expiry()
                        _next(6)
                6:
                        _phaseG_rollback()
                        _finish()


func _center(c: int, r: int) -> Vector2:
        return Vector2(c * 64.0 + 32.0, r * 64.0 + 32.0 + 80.0)


# ===========================================================================
# A — COSTANTI
# ===========================================================================
func _phaseA_constants() -> void:
        var cases: Dictionary = {1: 0, 4: 0, 5: 1, 30: 1, 31: 2, 68: 2}
        for lvl in cases:
                var got: int = C.bat_events_for_level(lvl)
                if got != cases[lvl]:
                        _fail("A: bat_events_for_level(%d) = %d, atteso %d"
                                        % [lvl, got, cases[lvl]])
        _ok("A: eventi per livello (0 < liv 5, 1 fino al 30, 2 dal 31)")
        C.BATS_ENABLED = false
        if C.bat_events_for_level(10) != 0:
                _fail("A: BATS_ENABLED=false non azzera gli eventi")
        C.BATS_ENABLED = true
        _ok("A: rollback BATS_ENABLED")


# ===========================================================================
# B — SCHEDULING + SPAWN
# ===========================================================================
func _phaseB_scheduling() -> void:
        main.is_paused = true
        main.start_level(10)
        if main.bat_events_left != 1:
                _fail("B: eventi pipistrelli al liv 10 = %d, atteso 1"
                                % main.bat_events_left)
        elif main.bat_event_timer_ms < float(C.BAT_CLOUD_FIRST_MIN_MS) \
                        or main.bat_event_timer_ms > float(C.BAT_CLOUD_FIRST_MAX_MS):
                _fail("B: timer spawn fuori finestra (%.0f)" % main.bat_event_timer_ms)
        else:
                _ok("B: evento armato (timer %.0fs)" % (main.bat_event_timer_ms / 1000.0))
        # forza lo spawn
        main.bat_event_timer_ms = 1.0
        main._update_bat_cloud(16.0)
        if main.bat_cloud == null:
                _fail("B: sciame non spawnato alla scadenza del timer")
                return
        var dist: float = main.player.position.distance_to(main.bat_cloud.position)
        if dist < C.BAT_CLOUD_MIN_SPAWN_DIST:
                _fail("B: spawn troppo vicino al player (%.0f px < %.0f)"
                                % [dist, C.BAT_CLOUD_MIN_SPAWN_DIST])
        else:
                _ok("B: sciame spawnato a %.0fpx dal player (min %.0f)"
                                % [dist, C.BAT_CLOUD_MIN_SPAWN_DIST])
        if main.bat_cloud.bats.size() != 5:
                _fail("B: pipistrelli nello sciame = %d, attesi 5"
                                % main.bat_cloud.bats.size())
        else:
                _ok("B: sciame di 5 pipistrelli (hp %d)" % main.bat_cloud.get_hp())


# ===========================================================================
# C — CACCIA
# ===========================================================================
func _phaseC_chase() -> void:
        if main.bat_cloud == null:
                _fail("C: precondizione mancante (sciame)")
                return
        var p: CharacterBody2D = main.player
        p.set_position_abs(_center(3, 3).x, _center(3, 3).y)
        var players: Array = [p]
        var d_before: float = main.bat_cloud.position.distance_to(p.position)
        for _i in 30:
                main.bat_cloud.update_cloud(16.0, players)
        var d_after: float = main.bat_cloud.position.distance_to(p.position)
        if d_after >= d_before:
                _fail("C: lo sciame non si avvicina (%.0f -> %.0f)" % [d_before, d_after])
        else:
                _ok("C: caccia attiva — distanza %.0f -> %.0f px" % [d_before, d_after])


# ===========================================================================
# D — MORSO
# ===========================================================================
func _phaseD_bite() -> void:
        if main.bat_cloud == null:
                _fail("D: precondizione mancante (sciame)")
                return
        var p: CharacterBody2D = main.player
        var cloud = main.bat_cloud
        p.damage_timer = 0
        p.jump_timer = 0
        p.energy = p.max_energy
        var e_before: int = p.energy
        cloud.position = p.position + Vector2(10.0, 0.0)
        cloud.update_cloud(16.0, [p])
        var expect_dmg: int = maxi(1, int(round(
                        p.max_energy * C.BAT_CLOUD_PLAYER_DAMAGE_PCT)))
        if p.energy != e_before - expect_dmg:
                _fail("D: morso %d danni, attesi %d" % [e_before - p.energy, expect_dmg])
        elif cloud.state != BC.CloudState.FLEE:
                _fail("D: dopo il morso lo sciame non e' in FLEE (%d)" % cloud.state)
        else:
                _ok("D: morso = -%d energia + rimbalzo via" % expect_dmg)
        # durante il FLEE niente secondo morso (cooldown): energia invariata
        cloud.position = p.position + Vector2(10.0, 0.0)
        var e_mid: int = p.energy
        cloud.update_cloud(16.0, [p])
        cloud.update_cloud(16.0, [p])
        if p.energy != e_mid:
                _fail("D: morso ripetuto durante il cooldown (%d -> %d)"
                                % [e_mid, p.energy])
        else:
                _ok("D: cooldown rispettato (nessun drain a raffica)")


# ===========================================================================
# E — ABBATTIMENTO
# ===========================================================================
func _phaseE_kill() -> void:
        if main.bat_cloud == null:
                _fail("E: precondizione mancante (sciame)")
                return
        var p: CharacterBody2D = main.player
        var cloud = main.bat_cloud
        # ripristina lo stato di caccia per il test dei colpi
        cloud.state = BC.CloudState.CHASE
        cloud.state_ms = 0.0
        var score_before: int = p.score
        # 1° colpo: proiettile entro 34px dal centro
        p.projectiles.clear()
        p.projectiles.append({"pos": cloud.position, "active": true})
        cloud.update_cloud(16.0, [p])
        if cloud.get_hp() != C.BAT_CLOUD_HITS_TO_DIE - 1:
                _fail("E: 1o colpo non registrato (hp %d)" % cloud.get_hp())
        elif p.projectiles[0]["active"] != false:
                _fail("E: proiettile del 1o colpo non consumato")
        elif cloud.bats.size() != 4:
                _fail("E: 1o colpo non ha disperso un pipistrello (%d)" % cloud.bats.size())
        else:
                _ok("E: 1o colpo = -1 pipistrello (hp %d, 4 superstiti)" % cloud.get_hp())
        p.projectiles.clear()
        # 2o colpo: dispersione + punti
        p.projectiles.append({"pos": cloud.position, "active": true})
        cloud.update_cloud(16.0, [p])
        if cloud.state != BC.CloudState.DYING:
                _fail("E: 2o colpo non porta alla dispersione (stato %d)" % cloud.state)
        elif p.score != score_before + C.BAT_CLOUD_KILL_POINTS:
                _fail("E: punti abbattimento %d, attesi %d"
                                % [p.score - score_before, C.BAT_CLOUD_KILL_POINTS])
        else:
                _ok("E: 2o colpo = dispersione (+%d punti)" % C.BAT_CLOUD_KILL_POINTS)
        p.projectiles.clear()
        # il controller ripulisce quando is_gone
        for _i in 60:
                main._update_bat_cloud(16.0)
        if main.bat_cloud != null:
                _fail("E: controller non ha liberato lo sciame disperso")
        else:
                _ok("E: sciame rimosso dal controller")


# ===========================================================================
# F — SCADENZA
# ===========================================================================
func _phaseF_expiry() -> void:
        # ri-arma un evento e forza lo spawn per testare la partenza spontanea
        main.bat_events_left = 1
        main.bat_event_timer_ms = 1.0
        main._update_bat_cloud(16.0)
        if main.bat_cloud == null:
                _fail("F: precondizione mancante (sciame 2)")
                return
        var cloud = main.bat_cloud
        cloud.lifetime_ms = 1.0
        cloud.update_cloud(16.0, [main.player])
        if cloud.state != BC.CloudState.LEAVE:
                _fail("F: lifetime esaurito non fa volar via lo sciame (%d)" % cloud.state)
        else:
                _ok("F: scadenza = lo sciame svolazza via")
        for _i in 80:
                main._update_bat_cloud(16.0)
        if main.bat_cloud != null:
                _fail("F: sciame non rimosso dopo la partenza")
        else:
                _ok("F: sciame partito e rimosso")


# ===========================================================================
# G — ROLLBACK
# ===========================================================================
func _phaseG_rollback() -> void:
        C.BATS_ENABLED = false
        main.start_level(10)
        if main.bat_events_left != 0:
                _fail("G: BATS_ENABLED=false ma eventi programmati")
        else:
                _ok("G: rollback — nessun evento pipistrelli")
        C.BATS_ENABLED = true


func _finish() -> void:
        if failures.is_empty():
                print("[TEST] TUTTI I TEST PIPISTRELLI SUPERATI")
                get_tree().quit(0)
        else:
                print("[TEST] %d TEST PIPISTRELLI FALLITI:" % failures.size())
                for f in failures:
                        print("  - ", f)
                get_tree().quit(1)
