## test_task51_phase2.gd — TASK 51 (richiesta utente): FASE 2 DEL BOSS.
##
## A (unitaria, senza scena):
##   A1 — soglia 50%: sopra la soglia resta fase 1; al 50% esatto entra in
##        fase 2 (dimensione +12%, segnale phase2_entered, velocita' +1 per
##        i non-saltatori). Un boss UCCISO non entra mai in fase 2.
##   A2 — LICH (SKY_STRIKE): colonne che piombano dall'alto (spawn in alto,
##        direzione verso il basso, variante 5 potenziata).
##   A3 — GOLEM (JUMP_SLAM): telegrafo -> volo parabolico verso il bersaglio
##        -> segnale slam_landed con raggio -> recupero -> stato 0.
##   A4 — SPIDER (PIT_SPAWNER): 3 segnali spawn_pit attorno al player.
##   A5 — VAMPIRE (HOMING_VOLLEY): 3 proiettili a inseguimento (homing>0,
##        variante 5).
##   A6 — potenziamento del fuoco base: in fase 2 ogni _shoot_pattern
##        aggiunge un proiettile potenziato a inseguimento.
## B (scena BossRoom, integrazione controller):
##   B1 — segnali collegati al boss della scena.
##   B2 — take_damage al 50%: flash del controller innescato (700ms).
##   B3 — buca: crepa (900ms) -> aperta + danno una tantum al player dentro.
##   B4 — salto: onda d'urto danneggia il player nel raggio.
##   B5 — buca: scadenza 5s -> rimossa.
extends Node

const BossRoomScene = preload("res://scenes/BossRoom.tscn")
const BossScript = preload("res://scripts/bosses/Boss.gd")
const C = preload("res://scripts/core/GameConstants.gd")

var boss_room: Node2D = null
var phase: int = 0
var failures: Array = []
var checks: int = 0
var _slams: Array = []
var _pits_signaled: Array = []


func _ready() -> void:
        # la parte A e' sincrona; B dopo il boot della scena
        GameManager.current_level = 4
        boss_room = BossRoomScene.instantiate()
        get_tree().root.add_child.call_deferred(boss_room)
        print("[TEST-51P2] boot BossRoom (livello 4, LICH)...")
        phase = 0


func _ok(cond: bool, msg: String) -> void:
        checks += 1
        if cond:
                print("[TEST-51P2] OK: ", msg)
        else:
                failures.append(msg)
                print("[TEST-51P2] FAIL: ", msg)


func _finish() -> void:
        if failures.is_empty():
                print("[TEST-51P2] ==== TEST FASE 2 BOSS SUPERATO (",
                                checks, " check) ====")
                get_tree().quit(0)
        else:
                for f in failures:
                        print("[TEST-51P2] FAIL: ", f)
                print("[TEST-51P2] ==== TEST FASE 2 BOSS FALLITO (",
                                failures.size(), "/", checks, ") ====")
                get_tree().quit(1)


# ===========================================================================
# A — unitario
# ===========================================================================
func _run_unit_tests() -> void:
        # --- A1: soglia, crescita, segnale, morte ---
        var b := BossScript.new()
        add_child(b)
        b.setup(4, 1920, 1080)  # livello 4 -> LICH
        var size0: float = b.size
        var speed0: int = b.speed
        var got_signal: Array = []
        b.phase2_entered.connect(func(_boss): got_signal.append(1))
        # boss ucciso: mai fase 2
        b.take_damage(b.max_health + 10)
        b.update_step(500.0, 500.0, 16, [])
        _ok(b.phase == 1 and not b.is_dead() == false,
                        "A1: boss ucciso NON entra in fase 2 (phase=%d)" % b.phase)
        b.queue_free()

        var b2 := BossScript.new()
        add_child(b2)
        b2.setup(4, 1920, 1080)
        size0 = b2.size
        speed0 = b2.speed
        got_signal.clear()
        b2.phase2_entered.connect(func(_boss): got_signal.append(1))
        # sopra la soglia: resta fase 1
        b2.health = int(float(b2.max_health) * 0.51)
        b2.update_step(500.0, 500.0, 16, [])
        _ok(b2.phase == 1, "A1: al 51% di energia resta in FASE 1")
        # al 50% esatto: fase 2
        b2.health = int(float(b2.max_health) * 0.5)
        b2.update_step(500.0, 500.0, 16, [])
        _ok(b2.phase == 2 and got_signal.size() == 1,
                        "A1: al 50% entra in FASE 2 con segnale (got=%d)" % got_signal.size())
        _ok(is_equal_approx(b2.size, size0 * C.BOSS_PHASE2_SIZE_BONUS),
                        "A1: dimensione +12%% in fase 2 (%.1f -> %.1f)" % [size0, b2.size])
        _ok(b2.speed == mini(speed0 + 1, 3),
                        "A1: LICH non-saltatore accelera in fase 2 (%d -> %d)"
                                        % [speed0, b2.speed])

        # --- A2: LICH sky strike ---
        b2.special_timer_ms = C.BOSS_PHASE2_SPECIAL_CD_MS
        var out: Array = []
        b2.update_step(900.0, 500.0, 16, out)
        var sky_count := 0
        for p in out:
                if p is Projectile and p.variant == 5 and p.dir.y > 4.0 \
                                and p.pos.y < 100.0:
                        sky_count += 1
        _ok(sky_count >= 2, "A2: SKY_STRIKE — %d colonne dall'alto (variante 5)"
                        % sky_count)
        b2.queue_free()

        # --- A6: fuoco base potenziato ---
        var b3 := BossScript.new()
        add_child(b3)
        b3.setup(4, 1920, 1080)
        b3.health = int(float(b3.max_health) * 0.5)
        b3.update_step(500.0, 500.0, 16, [])
        var out3: Array = []
        b3._shoot_pattern(900.0, 600.0, out3)
        var empowered := 0
        for p in out3:
                if p is Projectile and p.variant == 5 and p.homing_timer_ms > 0:
                        empowered += 1
        _ok(empowered >= 1, "A6: fuoco base + proiettile POTENZIATO a inseguimento")
        b3.queue_free()

        # --- A3: GOLEM salto schiacciante ---
        var g := BossScript.new()
        add_child(g)
        g.setup(68, 1920, 1080)  # 68/4 % 17 = 0 -> GOLEM
        _ok(g.boss_type == BossScript.Type.BOSS_GOLEM,
                        "A3: livello 68 -> GOLEM (type=%d)" % g.boss_type)
        g.health = int(float(g.max_health) * 0.5)
        g.update_step(500.0, 500.0, 16, [])
        _slams.clear()
        g.slam_landed.connect(func(world_pos: Vector2, radius: float):
                        _slams.append({"pos": world_pos, "radius": radius}))
        # forza il primo speciale
        g.special_timer_ms = C.BOSS_PHASE2_SPECIAL_CD_MS
        var outg: Array = []
        g.update_step(900.0, 500.0, 16, outg)
        _ok(g._slam_state == 1, "A3: telegrafo del salto attivo (ombra)")
        # telegrafo 650ms
        for _i in range(41):
                g.update_step(900.0, 500.0, 16, outg)
        _ok(g._slam_state == 2, "A3: volo iniziato dopo il telegrafo")
        var dist_before := g.pos.distance_to(Vector2(900.0, 500.0))
        for _i in range(33):
                g.update_step(900.0, 500.0, 16, outg)
        _ok(g._slam_state == 3 and _slams.size() == 1,
                        "A3: atterraggio con onda d'urto (segnali=%d)" % _slams.size())
        if _slams.size() == 1:
                _ok(is_equal_approx(float(_slams[0]["radius"]),
                                C.BOSS_PHASE2_SLAM_RADIUS),
                                "A3: raggio d'urto corretto (%.0f)"
                                                % float(_slams[0]["radius"]))
        _ok(dist_before > 0.0 and g.pos.distance_to(Vector2(900.0, 500.0)) <= 1.0,
                        "A3: il boss atterra ESATTO sul bersaglio")
        # recupero 450ms
        for _i in range(29):
                g.update_step(900.0, 500.0, 16, outg)
        _ok(g._slam_state == 0, "A3: recupero concluso (torna al movimento)")
        g.queue_free()

        # --- A4: SPIDER buche ---
        var s := BossScript.new()
        add_child(s)
        s.setup(12, 1920, 1080)  # 12/4 = 3 -> SPIDER
        _ok(s.boss_type == BossScript.Type.BOSS_SPIDER, "A4: livello 12 -> SPIDER")
        s.health = int(float(s.max_health) * 0.5)
        s.update_step(500.0, 500.0, 16, [])
        _pits_signaled.clear()
        s.spawn_pit.connect(func(world_pos: Vector2, _tint: Color):
                        _pits_signaled.append(world_pos))
        s.special_timer_ms = C.BOSS_PHASE2_SPECIAL_CD_MS
        var outs: Array = []
        s.update_step(900.0, 500.0, 16, outs)
        _ok(_pits_signaled.size() == 3,
                        "A4: PIT_SPAWNER — 3 buche segnalate attorno al player (got=%d)"
                        % _pits_signaled.size())
        var near := true
        for pp in _pits_signaled:
                if pp.distance_to(Vector2(900.0, 500.0)) > 260.0:
                        near = false
        _ok(near, "A4: le buche sono tutte raggiungibili/vicine al player")
        s.queue_free()

        # --- A5: VAMPIRE raffica a inseguimento ---
        var v := BossScript.new()
        add_child(v)
        v.setup(32, 1920, 1080)  # 32/4 = 8 -> VAMPIRE
        _ok(v.boss_type == BossScript.Type.BOSS_VAMPIRE, "A5: livello 32 -> VAMPIRE")
        v.health = int(float(v.max_health) * 0.5)
        v.update_step(500.0, 500.0, 16, [])
        v.special_timer_ms = C.BOSS_PHASE2_SPECIAL_CD_MS
        var outv: Array = []
        v.update_step(900.0, 500.0, 16, outv)
        var homing := 0
        for p in outv:
                if p is Projectile and p.homing_timer_ms > 2500 and p.variant == 5:
                        homing += 1
        _ok(homing == 3, "A5: HOMING_VOLLEY — 3 inseguitori potenziati (got=%d)"
                        % homing)
        v.queue_free()


# ===========================================================================
# B — integrazione scena
# ===========================================================================
func _run_scene_tests() -> void:
        var ctrl: Node2D = boss_room
        var boss: Node2D = ctrl.boss
        _ok(boss != null, "B1: boss della scena presente")
        if boss == null:
                return
        _ok(boss.phase2_entered.is_connected(ctrl._on_boss_phase2_entered)
                        and boss.spawn_pit.is_connected(ctrl._on_boss_spawn_pit)
                        and boss.slam_landed.is_connected(ctrl._on_boss_slam_landed),
                        "B1: segnali fase-2 collegati al controller")

        # B2: ingresso in fase 2 -> flash
        boss.health = int(float(boss.max_health) * 0.5)
        boss.update_step(500.0, 500.0, 16, [])
        _ok(boss.phase == 2 and ctrl._phase2_flash_ms > 0.0,
                        "B2: ingresso fase 2 -> flash controller (%.0fms)"
                        % ctrl._phase2_flash_ms)

        # B3: buca — crepa, apertura, danno una tantum
        var player: CharacterBody2D = ctrl.player
        # azzera TUTTE le invulnerabilita' di boot (guardia spawn ecc.)
        player.damage_timer = 0
        player.invincible_timer = 0
        player.spawn_guard_ms = 0
        player.position = Vector2(700.0, 600.0)
        var energy0: int = player.energy
        ctrl._on_boss_spawn_pit(Vector2(700.0, 600.0), Color(0.6, 0.3, 0.9))
        _ok(ctrl.boss_pits.size() == 1 and int(ctrl.boss_pits[0]["state"]) == 0,
                        "B3: buca in telegrafo (crepa)")
        ctrl._update_boss_pits(1000.0)  # esaurisce il telegrafo
        _ok(int(ctrl.boss_pits[0]["state"]) == 1, "B3: buca APERTA dopo 900ms")
        ctrl._update_boss_pits(16.0)  # check danno
        _ok(bool(ctrl.boss_pits[0]["hit_p1"]) and player.energy == energy0 - 1,
                        "B3: player nella buca colpito UNA volta (%d -> %d)"
                        % [energy0, player.energy])
        # niente doppio colpo
        ctrl._update_boss_pits(16.0)
        _ok(player.energy == energy0 - 1, "B3: niente danno ripetuto")

        # B4: onda d'urto del salto
        player.damage_timer = 0
        player.invincible_timer = 0
        player.spawn_guard_ms = 0
        player.position = Vector2(700.0, 600.0)
        var energy1: int = player.energy
        ctrl._on_boss_slam_landed(Vector2(710.0, 590.0), C.BOSS_PHASE2_SLAM_RADIUS)
        _ok(player.energy == energy1 - 1,
                        "B4: salto atterrato sul player = danno (%d -> %d)"
                        % [energy1, player.energy])
        # fuori raggio: incolume
        player.damage_timer = 0
        player.position = Vector2(300.0, 300.0)
        var energy2: int = player.energy
        ctrl._on_boss_slam_landed(Vector2(1000.0, 700.0), C.BOSS_PHASE2_SLAM_RADIUS)
        _ok(player.energy == energy2, "B4: player fuori dal raggio = incolume")

        # B5: scadenza buca
        ctrl._update_boss_pits(float(C.BOSS_PHASE2_PIT_OPEN_MS) + 100.0)
        _ok(ctrl.boss_pits.is_empty(), "B5: buca rimossa dopo la scadenza")


func _physics_process(_delta: float) -> void:
        match phase:
                0:
                        if boss_room != null and boss_room.is_node_ready():
                                phase = 1
                                _run_unit_tests()
                1:
                        phase = 2
                2:
                        _run_scene_tests()
                        _finish()
                        phase = 3
