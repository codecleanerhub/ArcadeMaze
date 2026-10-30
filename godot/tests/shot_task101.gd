## shot_task101.gd — TASK 101: screenshot di verifica visiva delle due fix.
##
## Catture (in /home/z/my-project/download/):
##   1. task101_barrel_ground  — player fermo col barile trasportato sopra la
##                               testa (baseline: barile a quota terra)
##   2. task101_barrel_jump    — player a metà salto (picco, jump_offset 25):
##                               il barile è salito CON lui (fix: prima restava
##                               fermo a quota terra)
##   3. task101_siege_ground   — Cannone d'Assedio IN MANO (fix: prima il tipo
##                               SIEGE non veniva disegnato affatto)
##   4. task101_siege_jump     — cannone a metà salto: segue l'arco come ogni
##                               arma (y = -4 - jump_offset)
##   5. task101_collapse       — animazione di morte in corso (corpo accasciato
##                               a terra) con NESSUNA schermata continue
##   6. task101_continue_after — la schermata CONTINUE? che nel flusso reale
##                               appare SOLO DOPO la fine dell'animazione
##                               (~1.2s più tardi): qui istanziata direttamente
##                               come figlia della root con lo STESSO stato
##                               GameManager che il controller produce a fine
##                               animazione (il timing animazione->continue è
##                               verificato dal test runtime test_task101).
##
## Ambiente: boss LICH lvl 4, sparo del boss disattivato per stati
## deterministici.
extends Node

const BossRoomScene = preload("res://scenes/BossRoom.tscn")
const BossSiegeCannonClass = preload("res://scripts/entities/BossSiegeCannon.gd")
const ContinuesScreenScene = preload("res://scenes/ContinuesScreen.tscn")

var boss_room: Node2D = null
var stage: int = 0
var t: float = 0.0
var wait_frames: int = 0
var barrel: Node2D = null


func _ready() -> void:
        process_mode = Node.PROCESS_MODE_ALWAYS  # sopravvive a pause/modal
        LoadingScreen.skip_boot_hold()
        GameManager.current_level = 4
        boss_room = BossRoomScene.instantiate()
        get_tree().root.add_child.call_deferred(boss_room)
        print("[SHOT-101] boot BossRoom (LICH)...")


func _capture(tag: String) -> void:
        var img: Image = get_viewport().get_texture().get_image()
        img.save_png("/home/z/my-project/download/" + tag + ".png")
        var p: CharacterBody2D = boss_room.player \
                        if boss_room != null and is_instance_valid(boss_room) else null
        var bp: Vector2 = barrel.position \
                        if barrel != null and is_instance_valid(barrel) else Vector2.INF
        print("[SHOT-101] salvato ", tag, ".png | player=(",
                        p.position.x if p != null else -1, ",", p.position.y if p != null else -1,
                        ") jump_offset=", p.jump_offset if p != null else -1,
                        " | barile=(", bp.x, ",", bp.y, ")")


func _crop_capture(tag: String, region: Rect2i) -> void:
        var img: Image = get_viewport().get_texture().get_image()
        var crop: Image = img.get_region(region)
        crop.save_png("/home/z/my-project/download/" + tag + "_crop.png")
        print("[SHOT-101] salvato ", tag, "_crop.png")


## Ritaglio attorno al player fermo a (500, 700): copre corpo (64x64),
## barile sopra la testa (y ~630 anche a quota -34) e arma in mano.
func _player_crop() -> Rect2i:
        return Rect2i(340, 560, 400, 300)


func _idle_barrel() -> Node2D:
        for b in boss_room._arena_barrels:
                if b != null and is_instance_valid(b) and b.is_idle():
                        return b
        return null


func _physics_process(delta: float) -> void:
        t += delta
        if boss_room == null or not boss_room.is_node_ready():
                return
        match stage:
                0:
                        if t > 1.6:
                                # ambiente deterministico: boss silente,
                                # niente mina vagante
                                boss_room.boss.shoot_timer_ms = -10000000
                                if boss_room.mine_item != null \
                                                and is_instance_valid(boss_room.mine_item):
                                        boss_room.mine_item.queue_free()
                                        boss_room.mine_item = null
                                # player in area libera, rivolto a destra
                                var p: CharacterBody2D = boss_room.player
                                p.position = Vector2(500.0, 700.0)
                                p.last_dx = 1
                                p.last_dy = 0
                                # raccoglie un barile (pickup diretto)
                                barrel = _idle_barrel()
                                if barrel == null:
                                        print("[SHOT-101] NESSUN barile idle!")
                                        _next(9)
                                        return
                                barrel.pickup(p)
                                _next(1)
                1:
                        # il barile converge sopra la testa: si POLLA la
                        # posizione (il lerp corre a ~10 fps idle sotto
                        # llvmpipe/Xvfb: contare i frame non è affidabile).
                        var tgt: Vector2 = Vector2(500.0, 666.0)
                        if barrel.position.distance_to(tgt) < 3.0 \
                                        or wait_frames > 400:
                                _next(2)
                        else:
                                wait_frames += 1
                2:
                        _capture("task101_barrel_ground")
                        _crop_capture("task101_barrel_ground", _player_crop())
                        # salto: picco a ~20 frame (jump_offset = 25)
                        boss_room.player.activate_jump()
                        _next(3)
                3:
                        _tick_wait(20, 4)
                4:
                        _capture("task101_barrel_jump")
                        _crop_capture("task101_barrel_jump", _player_crop())
                        _next(5)
                5:
                        # fine salto (altri ~22 frame) prima del cannone
                        _tick_wait(25, 6)
                6:
                        # cannone d'assedio in mano (prima invisibile)
                        if barrel != null and is_instance_valid(barrel):
                                barrel.queue_free()
                                barrel = null
                        boss_room.player.current_weapon = \
                                        BossSiegeCannonClass.make_siege_weapon()
                        _tick_wait(5, 7)
                7:
                        _capture("task101_siege_ground")
                        _crop_capture("task101_siege_ground", _player_crop())
                        boss_room.player.activate_jump()
                        _next(8)
                8:
                        _tick_wait(20, 10)
                10:
                        _capture("task101_siege_jump")
                        _crop_capture("task101_siege_jump", _player_crop())
                        _next(11)
                11:
                        # fine del secondo salto prima della sequenza morte
                        _tick_wait(25, 12)
                12:
                        var pd: CharacterBody2D = boss_room.player
                        pd.lives = 1
                        pd.energy = 1
                        pd.damage_timer = 0
                        pd.spawn_guard_ms = 0
                        pd.take_damage()  # ultima vita -> animazione
                        print("[SHOT-101] morte inflitta (soul=", pd.soul_pending,
                                        " lives=", pd.lives, ")")
                        _next(13)
                13:
                        # ~0.5s: corpo accasciato, NESSUNA schermata continue
                        _tick_wait(30, 14)
                14:
                        _capture("task101_collapse")
                        _crop_capture("task101_collapse", _player_crop())
                        # Congela il controller (NON l'animazione di morte,
                        # che è self-driving su un nodo figlio): la sequenza
                        # screenshot resta deterministica. Il flusso reale
                        # (controller che transita da solo DOPO l'animazione)
                        # è verificato dal test runtime test_task101.
                        boss_room.set_physics_process(false)
                        _next(15)
                15:
                        # fine naturale dell'animazione di morte
                        if not boss_room._is_collapsing(boss_room.player) \
                                        and wait_frames > 5:
                                _next(16)
                        elif wait_frames > 300:
                                print("[SHOT-101] TIMEOUT: animazione mai finita")
                                _next(9)
                        else:
                                wait_frames += 1
                16:
                        # STESSO stato GameManager che il controller produce a
                        # fine animazione (player_died(true) nel flusso reale)
                        # e STESSA scena che il cambio scena carica: qui la
                        # schermata viene istanziata direttamente come figlia
                        # della root, così l'harness resta vivo per la cattura.
                        print("[SHOT-101] animazione conclusa -> CONTINUES")
                        GameManager.died_in_boss = true
                        GameManager.current_state = GameConstants.GameState.CONTINUES
                        var cont: Node = ContinuesScreenScene.instantiate()
                        get_tree().root.add_child(cont)
                        _next(17)
                17:
                        # la schermata è appena apparsa: qualche frame di
                        # assestamento (bg + countdown)
                        _tick_wait(15, 18)
                18:
                        _capture("task101_continue_after")
                        print("[SHOT-101] ==== SEQUENZA TASK 101 COMPLETA "
                                        + "(barile/salto, cannone in mano, "
                                        + "morte->continue) ====")
                        _next(9)
                9:
                        get_tree().quit(0)


func _next(next_stage: int) -> void:
        stage = next_stage
        wait_frames = 0


func _tick_wait(frames: int, next_stage: int) -> void:
        if wait_frames >= frames:
                _next(next_stage)
        else:
                wait_frames += 1
