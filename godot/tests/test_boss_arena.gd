## test_boss_arena.gd — TASK 39: test runtime dell'ARENA DEL BOSS.
##
## Verifica: costanti/elementi/debolezze, spawn props (4 pilastri a tema,
## 3 barili con >= 1 elemento debole, cannone), danneggiamento e crollo dei
## pilastri con frammenti, danno dei frammenti al boss, pickup/lancio/
## detonazione dei barili (con moltiplicatore debolezza x2.5), arma SIEGE
## (pickup, proiettile pesante, danno), blocco dei proiettili boss sui
## pilastri, rilascio del barile alla morte del portatore, rinnovo arena
## (TASK 43: SOLO consumabili — le architetture non risorgono MAI),
## ripristino snapshot pilastri al continue, rimbalzo del boss.
##
## Ambiente controllato: mina rimossa, sparo del boss disattivato (timer
## negativo), spawn guard azzerata, boss teletrasportato lontano dai
## pilastri nei check di danno esatto — i danni contati sono SOLO dei
## soggetti del test. NB: il _physics_process del test gira PRIMA di quello
## del controller (ordine dell'albero), quindi i teleport del test valgono
## per il tick del controller nello STESSO frame.
extends Node

const BossRoomScene = preload("res://scenes/BossRoom.tscn")
const ElementalBarrelClass = preload("res://scripts/entities/ElementalBarrel.gd")
const BossArenaRuinClass = preload("res://scripts/entities/BossArenaRuin.gd")
const C = preload("res://scripts/core/GameConstants.gd")

var boss_room: Node2D = null
var phase: int = 0
var t: float = 0.0
var failures: Array = []
var checks: int = 0

# snapshot per confronti tra fasi
var boss_hp_before: int = 0
var pillar_hp_before: int = 0
var initial_ruins: int = 0
var boss_walked_over: bool = false
var player_pushed_out: bool = false
var test_barrel: Node2D = null
var blocked_pillar: Node2D = null
var bounce_pillar: Node2D = null
var bounce_dx_before: int = 0
var siege_proj_seen: bool = false


func _ready() -> void:
        # livello 4 -> boss index 1 (LICH) -> debolezza FUOCO
        GameManager.current_level = 4
        boss_room = BossRoomScene.instantiate()
        get_tree().root.add_child.call_deferred(boss_room)
        print("[TEST-ARENA] boot BossRoom (livello 4, LICH, debolezza FUOCO)...")


func _ok(cond: bool, msg: String) -> void:
        checks += 1
        if cond:
                print("[TEST-ARENA] OK: ", msg)
        else:
                failures.append(msg)
                print("[TEST-ARENA] FAIL: ", msg)


func _fail(msg: String) -> void:
        checks += 1
        failures.append(msg)
        print("[TEST-ARENA] FAIL: ", msg)


func _finish() -> void:
        if failures.is_empty():
                print("[TEST-ARENA] ==== TEST ARENA DEL BOSS SUPERATO (",
                                checks, " check) ====")
                get_tree().quit(0)
        else:
                for f in failures:
                        print("[TEST-ARENA] FAIL: ", f)
                print("[TEST-ARENA] ==== TEST ARENA DEL BOSS FALLITO (",
                                failures.size(), "/", checks, ") ====")
                get_tree().quit(1)


func _physics_process(delta: float) -> void:
        t += delta
        if boss_room == null or not boss_room.is_node_ready():
                return
        # la guardia di nascita (Task 38) va azzerata dove il danno e' soggetto
        boss_room.player.spawn_guard_ms = 0
        match phase:
                0:
                        _phase_constants()
                        phase = 1
                1:
                        if t > 1.2:
                                _phase_spawn()
                                phase = 2
                                t = 0.0
                2:
                        if t > 1.0:
                                _phase_pillar_collapse()
                                phase = 3
                                t = 0.0
                3:
                        if t > 1.4:
                                _phase_debris()
                                phase = 4
                                t = 0.0
                4:
                        _phase_barrel_carry()
                        phase = 5
                        t = 0.0
                5:
                        if t > 0.5:
                                _phase_barrel_drop_on_death()
                                phase = 6
                                t = 0.0
                6:
                        _phase_barrel_throw(true)
                        phase = 7
                        t = 0.0
                7:
                        if t > 1.2:
                                _phase_barrel_damage(true)
                                phase = 8
                                t = 0.0
                8:
                        _phase_barrel_throw(false)
                        phase = 9
                        t = 0.0
                9:
                        if t > 1.2:
                                _phase_barrel_damage(false)
                                phase = 10
                                t = 0.0
                10:
                        _phase_siege_setup()
                        phase = 11
                        t = 0.0
                11:
                        if t > 0.4:
                                _phase_siege_fire()
                                phase = 12
                                t = 0.0
                12:
                        if t > 1.0:
                                _phase_siege_hit()
                                phase = 13
                                t = 0.0
                13:
                        _phase_boss_proj_blocked()
                        phase = 14
                        t = 0.0
                14:
                        if t > 1.6:
                                _phase_renewal_setup()
                                phase = 15
                                t = 0.0
                15:
                        if t > 0.6:
                                _phase_renewal_check()
                                phase = 16
                                t = 0.0
                16:
                        _phase_snapshot_restore()
                        phase = 17
                        t = 0.0
                17:
                        _phase_bounce_setup()
                        phase = 18
                        t = 0.0
                18:
                        if t > 0.4:
                                _phase_bounce_check()
                                phase = 19
                19:
                        _finish()


# ---------------------------------------------------------------------------
# FASE 0 — costanti, elementi, mappa debolezze
# ---------------------------------------------------------------------------
func _phase_constants() -> void:
        _ok(C.BOSS_ARENA_PILLAR_COUNT == 4, "pilastri per set = 4 (legacy)")
        _ok(C.BOSS_ARENA_PILLAR_HP == 3, "HP pilastro = 3 colpi (legacy)")
        _ok(C.BOSS_ARENA_PILLAR_FRAGMENTS == 5, "frammenti per crollo = 5")
        _ok(C.BOSS_ARENA_PILLAR_FRAGMENT_DMG == 3, "danno frammento = 3")
        # TASK 50: muri-labirinto in rovina
        _ok(C.BOSS_ARENA_RUINS_ENABLED, "rovine abilitate (flag TASK 50)")
        _ok(C.BOSS_ARENA_RUIN_HP == 3, "HP muro-rovina = 3 colpi")
        _ok(C.BOSS_ARENA_RUIN_MIN >= 8 and C.BOSS_ARENA_RUIN_MAX <= 18,
                        "segmenti min/max sensati (" + str(C.BOSS_ARENA_RUIN_MIN)
                        + "-" + str(C.BOSS_ARENA_RUIN_MAX) + ")")
        _ok(C.BOSS_ARENA_RUIN_PASS_GAP >= 80.0,
                        "corridoio minimo tra muri >= 80px (player passa)")
        _ok(absf(C.BOSS_ARENA_BARREL_WEAK_MULT - 2.5) < 0.001,
                        "moltiplicatore debolezza = 2.5")
        _ok(C.BOSS_ARENA_SIEGE_AMMO == 4, "colpi cannone = 4")
        _ok(C.BOSS_ARENA_SIEGE_POWER == 5, "potenza cannone = 5")
        _ok(C.get_boss_weakness(0) == C.ElementKind.FROST, "Golem -> GHIACCIO")
        _ok(C.get_boss_weakness(1) == C.ElementKind.FIRE, "Lich -> FUOCO")
        _ok(C.get_boss_weakness(5) == C.ElementKind.LIGHTNING, "Kraken -> FULMINE")
        _ok(C.get_boss_weakness(14) == C.ElementKind.POISON, "Rat King -> VELENO")
        _ok(C.get_boss_weakness_name(1) == "FUOCO", "nome debolezza Lich = FUOCO")
        var pal: Dictionary = C.get_element_palette(C.ElementKind.FROST)
        _ok(str(pal.get("name", "")) == "GHIACCIO", "palette frost nome")
        _ok(pal.get("color", Color.BLACK) != Color.BLACK, "palette frost colore")
        var all_mapped: bool = true
        for bt in 17:
                var el: int = C.get_boss_weakness(bt)
                if el < 0 or el > 3:
                        all_mapped = false
        _ok(all_mapped, "17 boss tutti mappati a un elemento valido")


# ---------------------------------------------------------------------------
# FASE 1 — spawn dell'arena + ambiente controllato
# ---------------------------------------------------------------------------
func _phase_spawn() -> void:
        var boss: Node2D = boss_room.boss
        _ok(boss != null and not boss.is_dead(), "boss vivo (LICH lvl 4)")
        # TASK 50: labirinto di muri-rovina (niente piu' pilastri)
        _ok(boss_room._arena_pillars.size() == 0,
                        "NESSUN pilastro legacy spawnato (sostituiti dalle rovine)")
        var ruin_count: int = boss_room._arena_ruins.size()
        _ok(ruin_count >= C.BOSS_ARENA_RUIN_MIN and ruin_count <= C.BOSS_ARENA_RUIN_MAX,
                        "segmenti muro-rovina nel range (" + str(ruin_count) + ")")
        initial_ruins = ruin_count
        var all_standing: bool = true
        var in_bounds: bool = true
        var keep_out_ok: bool = true
        for ruin in boss_room._arena_ruins:
                if ruin == null or not is_instance_valid(ruin) or not ruin.is_standing():
                        all_standing = false
                        continue
                var r: Rect2 = ruin.get_rect()
                if r.position.x < 100.0 or r.end.x > C.WINDOW_WIDTH - 100.0 \
                                or r.position.y < C.UI_HEIGHT + 100.0 \
                                or r.end.y > C.WINDOW_HEIGHT - 80.0:
                        in_bounds = false
                # zona spawn player libera
                var player_spawn: Vector2 = Vector2(C.WINDOW_WIDTH * 0.5, 880.0)
                if r.grow(60.0).has_point(player_spawn):
                        keep_out_ok = false
        _ok(all_standing, "tutti i muri-rovina in piedi")
        _ok(in_bounds, "tutti i segmenti dentro l'arena")
        _ok(keep_out_ok, "zona spawn player libera dai muri")
        _ok(boss_room._arena_barrels.size() == 3, "3 barili spawnati")
        var weak_count: int = 0
        for barrel in boss_room._arena_barrels:
                if barrel.element == C.get_boss_weakness(boss.boss_type):
                        weak_count += 1
        _ok(weak_count >= 1, "almeno 1 barile dell'elemento debole")
        _ok(boss_room._arena_siege != null and is_instance_valid(boss_room._arena_siege),
                        "cannone d'assedio a terra")
        _ok(C.get_weapon_name(C.WeaponType.SIEGE) == "SIEGE", "nome arma SIEGE in HUD")
        # --- ambiente controllato: niente fonti di danno estranee ---
        if boss_room.mine_item != null and is_instance_valid(boss_room.mine_item):
                boss_room.mine_item.queue_free()
                boss_room.mine_item = null
        boss.shoot_timer_ms = -10000000  # il boss non spara per tutto il test


# ---------------------------------------------------------------------------
# FASE 2 — colpi al muro-rovina e crollo
# ---------------------------------------------------------------------------
func _phase_pillar_collapse() -> void:
        var test_ruin: Node2D = boss_room._arena_ruins[0]
        var felled_too_early: bool = false
        var felled_at_third: bool = false
        for i in 3:
                var felled: bool = test_ruin.take_hit()
                if i < 2 and (felled or not test_ruin.is_standing()):
                        felled_too_early = true
                if i == 2:
                        felled_at_third = felled and not test_ruin.is_standing()
        _ok(not felled_too_early, "muro in piedi dopo 2 colpi (crepe visibili)")
        _ok(felled_at_third, "muro abbattuto al 3° colpo")
        _ok(not test_ruin.blocks_point(test_ruin.origin),
                        "muro crollato NON blocca piu' i proiettili")


# ---------------------------------------------------------------------------
# FASE 3 — frammenti vs boss
# ---------------------------------------------------------------------------
func _phase_debris() -> void:
        var debris: Array = get_tree().get_nodes_in_group("arena_debris")
        _ok(debris.size() >= 3, "frammenti in volo (" + str(debris.size()) + ")")
        var boss: Node2D = boss_room.boss
        # boss lontano dai pilastri (determinismo) + snapshot
        boss.pos = Vector2(960.0, 620.0)
        boss_hp_before = boss.health
        if debris.size() > 0:
                var d0: Node2D = debris[0] as Node2D
                d0.position = boss.pos
                d0.velocity = Vector2.ZERO
        # rimuovi gli ALTRI frammenti (determinismo del danno contato)
        var i: int = 0
        for node in debris:
                if i > 0 and is_instance_valid(node):
                        node.queue_free()
                i += 1


# ---------------------------------------------------------------------------
# FASE 4 — pickup e trasporto barile
# ---------------------------------------------------------------------------
func _phase_barrel_carry() -> void:
        _ok(boss_room.boss.health < boss_hp_before,
                        "frammento sul boss ha tolto energia ("
                        + str(boss_hp_before - boss_room.boss.health) + ")")
        test_barrel = null
        for barrel in boss_room._arena_barrels:
                if barrel != null and is_instance_valid(barrel) and barrel.is_idle():
                        test_barrel = barrel
                        break
        _ok(test_barrel != null, "barile idle disponibile")
        if test_barrel == null:
                return
        var p: CharacterBody2D = boss_room.player
        p.position = test_barrel.position
        var picked: bool = test_barrel.pickup(p)
        _ok(picked, "pickup barile riuscito")
        _ok(test_barrel.state == ElementalBarrelClass.State.CARRIED,
                        "barile in stato CARRIED")
        _ok(boss_room._carried_barrel_of(p) == test_barrel,
                        "controller vede il barile trasportato da P1")
        # prepara il test di rilascio: il portatore "scompare"
        p.visible = false


# ---------------------------------------------------------------------------
# FASE 5 — rilascio alla morte del portatore
# ---------------------------------------------------------------------------
func _phase_barrel_drop_on_death() -> void:
        if test_barrel == null or not is_instance_valid(test_barrel):
                boss_room.player.visible = true
                return
        _ok(test_barrel.state == ElementalBarrelClass.State.IDLE,
                        "barile ricaduto a terra (IDLE) a portatore scomparso")
        boss_room.player.visible = true


# ---------------------------------------------------------------------------
# FASE 6/8 — lancio del barile (debole o neutro)
# ---------------------------------------------------------------------------
func _phase_barrel_throw(weak: bool) -> void:
        var p: CharacterBody2D = boss_room.player
        # lascia cadere eventuali barili auto-raccolti (determinismo)
        var carried: Node2D = boss_room._carried_barrel_of(p)
        if carried != null:
                carried.drop()
        # trova un barile idle dell'elemento voluto (o forzalo: solo test)
        var barrel: Node2D = null
        var want_el: int = C.ElementKind.FIRE if weak else C.ElementKind.FROST
        for b in boss_room._arena_barrels:
                if b != null and is_instance_valid(b) and b.is_idle():
                        barrel = b
                        if b.element == want_el:
                                break
        if barrel == null:
                _fail("nessun barile idle per il lancio "
                                + ("DEBOLE" if weak else "NEUTRO"))
                return
        if barrel.element != want_el:
                barrel.element = want_el
        test_barrel = barrel
        p.position = barrel.position
        barrel.pickup(p)
        p.last_dx = 1
        p.last_dy = 0
        var thrown: bool = boss_room._try_throw_carried_barrel(p)
        _ok(thrown, "lancio barile " + ("DEBOLE" if weak else "NEUTRO")
                        + " da P1 (intercetto tasto fuoco)")
        _ok(barrel.state == ElementalBarrelClass.State.THROWN, "barile in stato THROWN")
        # boss al centro (lontano dai pilastri) + detonazione al contatto
        boss_room.boss.pos = Vector2(960.0, 620.0)
        barrel.position = boss_room.boss.pos
        barrel.velocity = Vector2.ZERO
        boss_hp_before = boss_room.boss.health


# ---------------------------------------------------------------------------
# FASE 7/9 — danno della detonazione
# ---------------------------------------------------------------------------
func _phase_barrel_damage(weak: bool) -> void:
        var boss: Node2D = boss_room.boss
        if boss == null or not is_instance_valid(boss) or boss.is_dead():
                _fail("boss morto durante i test barile")
                return
        var dmg: int = boss_hp_before - boss.health
        var expect: int = int(round(float(boss.max_health)
                        * C.BOSS_ARENA_BARREL_BASE_PCT
                        * (C.BOSS_ARENA_BARREL_WEAK_MULT if weak else 1.0)))
        _ok(dmg == expect, "danno barile " + ("DEBOLE" if weak else "NEUTRO")
                        + " = " + str(dmg) + " (atteso " + str(expect) + ")")


# ---------------------------------------------------------------------------
# FASE 10 — preparazione pickup cannone
# ---------------------------------------------------------------------------
func _phase_siege_setup() -> void:
        if boss_room._arena_siege == null or not is_instance_valid(boss_room._arena_siege):
                _fail("cannone non presente al pickup")
                return
        boss_room.player.position = boss_room._arena_siege.position
        boss_hp_before = boss_room.boss.health


# ---------------------------------------------------------------------------
# FASE 11 — sparo cannone
# ---------------------------------------------------------------------------
func _phase_siege_fire() -> void:
        var p: CharacterBody2D = boss_room.player
        _ok(int(p.current_weapon.get("type", -1)) == C.WeaponType.SIEGE,
                        "arma equipaggiata = SIEGE")
        _ok(int(p.current_weapon.get("ammo", 0)) == C.BOSS_ARENA_SIEGE_AMMO,
                        "munizioni cannone = 4")
        _ok(int(p.current_weapon.get("power", 0)) == C.BOSS_ARENA_SIEGE_POWER,
                        "potenza cannone = 5")
        p.dx = 1
        p.dy = 0
        p.last_dx = 1
        p.last_dy = 0
        p.shoot_cooldown = 0
        p.shoot()
        var siege_proj: Dictionary = {}
        for proj in p.projectiles:
                if proj.get("siege", false):
                        siege_proj = proj
                        break
        siege_proj_seen = not siege_proj.is_empty()
        _ok(siege_proj_seen, "proiettile siege sparato")
        if siege_proj.is_empty():
                return
        _ok(absf(float(siege_proj.get("speed_px", 0.0)) - 6.0) < 0.01,
                        "palla di cannone lenta (6 px/frame)")
        _ok(int(p.current_weapon.get("ammo", 0)) == C.BOSS_ARENA_SIEGE_AMMO - 1,
                        "munizioni decrementate")
        # boss al centro (lontano dai pilastri) + palla PIASTA sul boss
        boss_room.boss.pos = Vector2(960.0, 620.0)
        siege_proj["pos"] = boss_room.boss.pos
        siege_proj["dir"] = Vector2(1.0, 0.0)


# ---------------------------------------------------------------------------
# FASE 12 — colpo cannone sul boss
# ---------------------------------------------------------------------------
func _phase_siege_hit() -> void:
        var boss: Node2D = boss_room.boss
        if boss == null or boss.is_dead():
                _fail("boss morto prima del colpo cannone")
                return
        var dmg: int = boss_hp_before - boss.health
        var expect: int = maxi(C.BOSS_ARENA_SIEGE_POWER,
                        int(round(float(boss.max_health) * C.BOSS_ARENA_SIEGE_PCT)))
        _ok(dmg >= expect, "colpo cannone >= " + str(expect)
                        + " (danno " + str(dmg) + ")")


# ---------------------------------------------------------------------------
# FASE 13 — proiettile del boss bloccato dal muro-rovina
# ---------------------------------------------------------------------------
func _phase_boss_proj_blocked() -> void:
        blocked_pillar = null
        for rn in boss_room._arena_ruins:
                if rn != null and is_instance_valid(rn) and rn.is_standing():
                        blocked_pillar = rn
                        break
        if blocked_pillar == null:
                _fail("nessun muro in piedi per il test blocco")
                return
        pillar_hp_before = blocked_pillar.hp
        # proiettile finto che vola VERSO il centro del muro lungo la
        # perpendicolare all'asse del segmento
        var perpendicular: Vector2 = Vector2(0.0, 1.0) if blocked_pillar.axis == "h" \
                        else Vector2(1.0, 0.0)
        var fake := Node2D.new()
        fake.position = blocked_pillar.origin - perpendicular * 90.0
        boss_room.boss_projectiles_node.add_child(fake)
        fake.set_meta("velocity", perpendicular * 6.0)


# ---------------------------------------------------------------------------
# FASE 14 — verifica blocco + preparazione rinnovo
# ---------------------------------------------------------------------------
func _phase_renewal_setup() -> void:
        if blocked_pillar != null and is_instance_valid(blocked_pillar):
                _ok(blocked_pillar.hp < pillar_hp_before,
                                "proiettile del boss BLOCCATO dal muro-rovina "
                                + "(HP " + str(pillar_hp_before) + " -> "
                                + str(blocked_pillar.hp) + ")")
        _ok(boss_room.boss != null and not boss_room.boss.is_dead(),
                        "fight ancora vivo")
        # boss lontano dai barili che sta per far esplodere
        boss_room.boss.pos = Vector2(960.0, 620.0)
        # forza l'arena SACCHESGGIATA: arma scarica, muri giu', barili via
        var p: CharacterBody2D = boss_room.player
        var carried: Node2D = boss_room._carried_barrel_of(p)
        if carried != null:
                carried.drop()
        p.current_weapon = {"type": 0, "power": 1, "ammo": 0}
        # allontana il player dal punto di respawn del cannone (960,850):
        # altrimenti lo raccoglie all'istante e il check del rinnovo fallisce
        p.position = Vector2(320.0, 950.0)
        for rn in boss_room._arena_ruins:
                if rn != null and is_instance_valid(rn) and rn.is_standing():
                        rn.take_hit()
                        rn.take_hit()
                        rn.take_hit()
        for b in boss_room._arena_barrels:
                if b != null and is_instance_valid(b):
                        # allontana i barili prima di farli esplodere
                        # (nessun danno extra al boss nel test di rinnovo)
                        if b.state == ElementalBarrelClass.State.IDLE:
                                b.position = Vector2(70.0, 130.0)
                        b.detonate()
        boss_room._arena_renewal_ms = C.BOSS_ARENA_RENEWAL_MS - 1.0


# ---------------------------------------------------------------------------
# FASE 15 — verifica rinnovo arena (TASK 43: SOLO consumabili)
# ---------------------------------------------------------------------------
func _phase_renewal_check() -> void:
        var standing: int = 0
        var rubble_nodes: int = 0
        for rn in boss_room._arena_ruins:
                if rn != null and is_instance_valid(rn):
                        if rn.is_standing():
                                standing += 1
                        elif rn.state == int(BossArenaRuinClass.RuinState.RUBBLE):
                                rubble_nodes += 1
        # TASK 43/50 (richiesta utente): le architetture distrutte NON
        # risorgono ne' col rinnovo periodico, ne' alla morte del player.
        _ok(standing == 0,
                        "rinnovo arena: NESSUN muro risorto ("
                        + str(standing) + " in piedi)")
        _ok(rubble_nodes == initial_ruins,
                        "rinnovo arena: tutti i cumuli di macerie persistenti ("
                        + str(rubble_nodes) + "/" + str(initial_ruins) + ")")
        var usable_barrels: int = 0
        for b in boss_room._arena_barrels:
                if b != null and is_instance_valid(b) \
                                and b.state != ElementalBarrelClass.State.EXPLODING:
                        usable_barrels += 1
        _ok(usable_barrels >= 2, "rinnovo arena: barili ricomparsi ("
                        + str(usable_barrels) + ")")
        _ok(boss_room._arena_siege != null and is_instance_valid(boss_room._arena_siege),
                        "rinnovo arena: cannone ricomparso")
        _ok(siege_proj_seen, "proiettile siege osservato")


# ---------------------------------------------------------------------------
# FASE 16 — TASK 43/50: snapshot architetture + continue senza resurrezione
# ---------------------------------------------------------------------------
func _phase_snapshot_restore() -> void:
        # TASK 50: il layout e' rigenerato dal SEED salvato, poi si riapplicano
        # gli stati: il muro 0 era gia' crollato (macerie), il muro 1 in piedi
        # con 2 HP. Prima del restore, annota il layout atteso (posizioni).
        var saved_seed: int = boss_room._arena_ruin_seed
        var expected_origins: Array = []
        for rn in boss_room._arena_ruins:
                if rn != null and is_instance_valid(rn):
                        expected_origins.append(rn.origin)
        var snap_states: Array = []
        for i in boss_room._arena_ruins.size():
                if i == 0:
                        snap_states.append({"idx": 0, "state": 1, "hp": 0})
                elif i == 1:
                        snap_states.append({"idx": 1, "state": 0, "hp": 2})
                else:
                        snap_states.append(boss_room._arena_ruins[i].snapshot())
        boss_room._restore_arena_pillars_from_snapshot({
                "arena_ruins": snap_states,
                "arena_ruin_seed": saved_seed,
        })
        var r0: Node2D = null
        var r1: Node2D = null
        for rn in boss_room._arena_ruins:
                if rn != null and is_instance_valid(rn):
                        if rn.ruin_index == 0:
                                r0 = rn
                        elif rn.ruin_index == 1:
                                r1 = rn
        _ok(r0 != null and not r0.is_standing()
                        and r0.state == int(BossArenaRuinClass.RuinState.RUBBLE),
                        "snapshot: muro 0 resta MACERIE (non risorge)")
        _ok(r1 != null and r1.is_standing() and r1.hp == 2,
                        "snapshot: muro 1 in piedi con HP residuo 2")
        # il layout rigenerato dal seed e' IDENTICO (stesse posizioni)
        var same_layout: bool = boss_room._arena_ruins.size() == expected_origins.size()
        if same_layout:
                for i in boss_room._arena_ruins.size():
                        var rn2: Node2D = boss_room._arena_ruins[i]
                        if rn2 == null or not is_instance_valid(rn2) \
                                        or rn2.origin != expected_origins[i]:
                                same_layout = false
                                break
        _ok(same_layout,
                        "snapshot: layout rigenerato IDENTICO dal seed ("
                        + str(boss_room._arena_ruins.size()) + " segmenti)")
        # Continue (2P in-scena): rinnova SOLO i consumabili, non tocca
        # le architetture — nessun muro nuovo, le macerie restano.
        var nodes_before: int = boss_room._arena_ruins.size()
        boss_room._respawn_boss_arena()
        var standing_after: int = 0
        for rn in boss_room._arena_ruins:
                if rn != null and is_instance_valid(rn) and rn.is_standing():
                        standing_after += 1
        _ok(boss_room._arena_ruins.size() == nodes_before,
                        "continue: NESSUN muro nuovo creato ("
                        + str(boss_room._arena_ruins.size()) + ")")
        _ok(standing_after == 1,
                        "continue: resta solo il muro 1 in piedi, le macerie restano ("
                        + str(standing_after) + ")")
        var barrels_after: int = 0
        for b in boss_room._arena_barrels:
                if b != null and is_instance_valid(b) \
                                and b.state != ElementalBarrelClass.State.EXPLODING:
                        barrels_after += 1
        _ok(barrels_after >= 2, "continue: barili rinnovati ("
                        + str(barrels_after) + ")")
        _ok(boss_room._arena_siege != null and is_instance_valid(boss_room._arena_siege),
                        "continue: cannone rinnovato")


# ---------------------------------------------------------------------------
# FASE 17/18 — TASK 50: il boss CALPESTA i muri, il player COLLIDE
# ---------------------------------------------------------------------------
func _phase_bounce_setup() -> void:
        var boss: Node2D = boss_room.boss
        bounce_pillar = null
        for rn in boss_room._arena_ruins:
                if rn != null and is_instance_valid(rn) and rn.is_standing():
                        bounce_pillar = rn
                        break
        if bounce_pillar == null or boss == null or boss.is_dead():
                _fail("nessun muro in piedi per il test collisioni")
                return
        # --- il boss passa SOPRA il muro (niente repulsione: e' gigante) ---
        boss.pos = bounce_pillar.origin
        boss.dx = 0
        boss.dy = 0
        var pos_before: Vector2 = boss.pos
        boss_room._update_boss_arena(16.0)
        boss_walked_over = boss.pos.distance_to(pos_before) < 0.5
        # --- il player COLLIDE col muro (spinto fuori dal rettangolo) ---
        var p: CharacterBody2D = boss_room.player
        p.ghost_mode = false
        p.position = bounce_pillar.origin
        p._collide_arena_ruins()
        player_pushed_out = not bounce_pillar.get_rect(12.0).has_point(p.position)


func _phase_bounce_check() -> void:
        if bounce_pillar == null or not is_instance_valid(bounce_pillar):
                return
        _ok(boss_walked_over,
                        "boss passa SOPRA il muro-rovina (niente repulsione TASK 50)")
        _ok(player_pushed_out,
                        "player COLLIDE col muro e viene spinto fuori (scivolamento)")
        _ok(bounce_pillar.is_standing(),
                        "il muro e' ancora in piedi dopo il contatto (nessun danno da collisione)")
