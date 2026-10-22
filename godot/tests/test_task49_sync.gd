## test_task49_sync.gd — TASK 49: sincronizzazione posa/proiettile/suono.
##
## Verifica il meccanismo di sparo differito del boss (wind-up -> rilascio):
##   1) al trigger dello shoot timer NON parte nessun proiettile (prima il
##      colpo usciva con la posa ancora neutra: bocca chiusa per il Mimico);
##   2) il timer pending_shot_ms parte a BOSS_ATTACK_WINDUP_MS e la posa
##      d'attacco (riga 1 dello sheet) e' attiva dal primo frame;
##   3) durante il wind-up (~270ms) nessuno sparo prematuro;
##   4) allo scadere del wind-up il colpo parte ESATTAMENTE sul frame di
##      rilascio (frame 3 @ 11 FPS): proiettile e posa nello stesso frame —
##      per il Mimico Colossale e' il frame con la bocca spalancata;
##   5) il flag di rollback BOSS_ATTACK_SYNC_ENABLED e' ON di default.
##
## Soggetto: MIMICO COLOSSALE (livello 52 -> boss index 13, sheet boss_025
## 6x2, 3 goo stream per sparo) — lo stesso boss della segnalazione utente.
extends Node

const BossScript = preload("res://scripts/bosses/Boss.gd")
const C = preload("res://scripts/core/GameConstants.gd")

var failures: Array = []
var checks: int = 0


func _ok(cond: bool, msg: String) -> void:
        checks += 1
        if cond:
                print("[TEST-49] OK: ", msg)
        else:
                failures.append(msg)
                print("[TEST-49] FAIL: ", msg)


func _finish() -> void:
        if failures.is_empty():
                print("[TEST-49] ==== TEST SYNC ATTACCO SUPERATO (", checks,
                                " check) ====")
                get_tree().quit(0)
        else:
                for f in failures:
                        print("[TEST-49] FAIL: ", f)
                print("[TEST-49] ==== TEST SYNC ATTACCO FALLITO (",
                                failures.size(), "/", checks, ") ====")
                get_tree().quit(1)


func _ready() -> void:
        _ok(C.BOSS_ATTACK_SYNC_ENABLED,
                        "flag rollback BOSS_ATTACK_SYNC_ENABLED ON (default)")
        _ok(C.BOSS_ATTACK_WINDUP_MS > 0 and C.BOSS_ATTACK_WINDUP_MS < 500,
                        "BOSS_ATTACK_WINDUP_MS in (0,500): %d ms"
                        % C.BOSS_ATTACK_WINDUP_MS)

        var out: Array = []
        var boss := BossScript.new()
        add_child(boss)
        # livello 52 -> (52/4)%17 = 13 = BOSS_COLOSSAL_MIMIC (boss_025)
        boss.setup(52, 1920, 1080)
        boss._draw()
        if not boss.deform_loaded:
                _fail_quit(boss, "boss_025 (mimic) non caricato")
                return
        _ok(boss.sprite_id == "boss_025",
                        "boss del test = Mimico Colossale (%s)" % boss.sprite_id)

        # ---- 1) trigger dello shoot timer: posa SI, proiettile NO ----
        boss.shoot_timer_ms = 2000  # base_cd lvl52 = 1000 -> 2016 > 1000
        boss.update_step(500.0, 500.0, 16, out)
        _ok(out.is_empty(),
                        "al trigger NESSUN proiettile immediato (wind-up prima del colpo)")
        _ok(boss.pending_shot_ms == C.BOSS_ATTACK_WINDUP_MS,
                        "pending_shot_ms = %d (atteso %d)"
                        % [boss.pending_shot_ms, C.BOSS_ATTACK_WINDUP_MS])
        _ok(boss.attacking_timer_ms == 500,
                        "attacking_timer_ms = 500 (posa d'attacco avviata)")
        var row0 := _sheet_row(boss)
        var col0 := _sheet_col(boss)
        _ok(row0 == 1, "riga sheet = 1 (attacco) dal primo frame")
        _ok(col0 == 0, "frame di partenza = 0 (wind-up)")

        # ---- 2) wind-up: nessuno sparo prematuro ----
        # 280ms / 16ms = 17.5 -> il colpo parte al 18° update post-trigger.
        # Nei primi 17 update pending resta > 0.
        var premature: int = 0
        for i in range(17):
                boss.update_step(500.0, 500.0, 16, out)
                if out.size() > 0:
                        premature = i + 2  # update assoluti (1 = trigger)
                        break
        _ok(out.is_empty() and premature == 0,
                        "wind-up di 17 update SENZA spari prematuri")
        _ok(boss.pending_shot_ms == 8,
                        "pending residuo prima del colpo = %d ms (atteso 8)"
                        % boss.pending_shot_ms)

        # ---- 3) rilascio: colpo + frame di lancio nello stesso update ----
        boss.update_step(500.0, 500.0, 16, out)
        _ok(out.size() == 3,
                        "al rilascio partono 3 goo stream (avuti: %d)" % out.size())
        var colr := _sheet_col(boss)
        var rowr := _sheet_row(boss)
        _ok(rowr == 1, "riga sheet = 1 durante il rilascio")
        _ok(colr == 3,
                        "frame di rilascio = %d (atteso 3: bocca spalancata / smash a terra @ 11 FPS)" % colr)
        _ok(boss.pending_shot_ms == 0, "pending azzerato dopo lo sparo")
        # 19 update totali ma il primo (trigger) SETTA il timer senza
        # decrementarlo: decrementi effettivi = 18 -> 500 - 288 = 212.
        _ok(boss.attacking_timer_ms == 500 - 18 * 16,
                        "attacking_timer_ms = %d (atteso %d: follow-through resta visibile)" % [boss.attacking_timer_ms, 500 - 18 * 16])

        # ---- 4) rollback: flag OFF = sparo immediato (comportamento pre-49) ----
        C.BOSS_ATTACK_SYNC_ENABLED = false
        var out2: Array = []
        var boss2 := BossScript.new()
        add_child(boss2)
        boss2.setup(52, 1920, 1080)
        boss2._draw()
        boss2.shoot_timer_ms = 2000
        boss2.update_step(500.0, 500.0, 16, out2)
        _ok(out2.size() == 3,
                        "flag OFF: sparo immediato al trigger (rollback pre-Task-49)")
        C.BOSS_ATTACK_SYNC_ENABLED = true

        remove_child(boss)
        boss.queue_free()
        remove_child(boss2)
        boss2.queue_free()
        _finish()


func _sheet_col(boss) -> int:
        var sr: Rect2 = boss.deform_sprite.sub_rect
        if sr.size.x <= 0.0:
                return -1
        return int(sr.position.x / sr.size.x)


func _sheet_row(boss) -> int:
        var sr: Rect2 = boss.deform_sprite.sub_rect
        if sr.size.y <= 0.0:
                return -1
        return int(sr.position.y / sr.size.y)


func _fail_quit(boss, msg: String) -> void:
        _ok(false, msg)
        remove_child(boss)
        boss.queue_free()
        _finish()
