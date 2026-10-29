## shot_boss_arena.gd — TASK 39/50: screenshot dell'ARENA DEL BOSS.
##
## Catture (in /home/z/my-project/download/):
##   1. boss_arena_overview        — TASK 50: labirinto di muri-rovina
##                                    PixelLab + barili, cannone, boss
##   2. boss_arena_pillar_cracked  — muro-rovina a 2 colpi (crepe visibili)
##   3. boss_arena_collapse        — crollo con schegge di pietra in volo
##   3b. boss_arena_rubble         — cumulo di macerie fermo
##                                    (test che NON risorgono al rinnovo)
##   4. boss_arena_explosion       — detonazione FUOCO sul boss con testo
##                                    "DEBOLEZZA!" (moltiplicatore x2.5)
##   5. boss_arena_siege           — player con cannone equipaggiato + pickup
##                                    + crop ravvicinati
##
## Ambiente: boss LICH lvl 4 (debolezza FUOCO), sparo del boss disattivato
## per stati deterministici.
extends Node

const BossRoomScene = preload("res://scenes/BossRoom.tscn")
const ElementalBarrelClass = preload("res://scripts/entities/ElementalBarrel.gd")

var boss_room: Node2D = null
var stage: int = 0
var t: float = 0.0
var fire_barrel: Node2D = null
var test_ruin: Node2D = null


func _ready() -> void:
        LoadingScreen.skip_boot_hold()
        GameManager.current_level = 4
        boss_room = BossRoomScene.instantiate()
        get_tree().root.add_child.call_deferred(boss_room)
        print("[SHOT-ARENA] boot BossRoom (LICH, debolezza FUOCO)...")


func _capture(tag: String) -> void:
        var img: Image = get_viewport().get_texture().get_image()
        img.save_png("/home/z/my-project/download/" + tag + ".png")
        print("[SHOT-ARENA] salvato ", tag, ".png")


func _crop_capture(tag: String, region: Rect2i) -> void:
        var img: Image = get_viewport().get_texture().get_image()
        var crop: Image = img.get_region(region)
        crop.save_png("/home/z/my-project/download/" + tag + "_crop.png")
        print("[SHOT-ARENA] salvato ", tag, "_crop.png")


func _find_idle_barrel_of_element(el: int) -> Node2D:
        for b in boss_room._arena_barrels:
                if b != null and is_instance_valid(b) and b.is_idle() \
                                and b.element == el:
                        return b
        return null


func _physics_process(delta: float) -> void:
        t += delta
        if boss_room == null or not boss_room.is_node_ready():
                return
        match stage:
                0:
                        if t > 1.6:
                                # ambiente deterministico: il boss non spara
                                boss_room.boss.shoot_timer_ms = -10000000
                                if boss_room.mine_item != null \
                                                and is_instance_valid(boss_room.mine_item):
                                        boss_room.mine_item.queue_free()
                                        boss_room.mine_item = null
                                stage = 1
                                t = 0.0
                1:
                        # overview: tutto appena spawnato (TASK 50: rovine)
                        if t > 0.6:
                                _capture("boss_arena_overview")
                                if boss_room._arena_ruins.size() > 0:
                                        test_ruin = boss_room._arena_ruins[0]
                                        # 2 colpi -> crepe visibili
                                        test_ruin.take_hit()
                                        test_ruin.take_hit()
                                        # crop centrato sul muro di test
                                        var rr: Rect2 = test_ruin.get_rect()
                                        _crop_capture("boss_arena_pillar_cracked",
                                                        Rect2i(int(rr.position.x) - 40,
                                                        int(rr.position.y) - 60,
                                                        int(rr.size.x) + 80,
                                                        int(rr.size.y) + 120))
                                stage = 2
                                t = 0.0
                2:
                        if t > 0.45:
                                _capture("boss_arena_pillar_cracked")
                                # colpo finale -> crollo
                                if test_ruin != null and is_instance_valid(test_ruin):
                                        test_ruin.take_hit()
                                stage = 3
                                t = 0.0
                3:
                        # schegge in volo (~300ms dal crollo)
                        if t > 0.32:
                                _capture("boss_arena_collapse")
                                if test_ruin != null and is_instance_valid(test_ruin):
                                        var rc: Rect2 = test_ruin.get_rect()
                                        _crop_capture("boss_arena_collapse",
                                                        Rect2i(int(rc.position.x) - 90,
                                                        int(rc.position.y) - 130,
                                                        int(rc.size.x) + 180,
                                                        int(rc.size.y) + 260))
                                stage = 4
                                t = 0.0
                4:
                        # TASK 43: macerie ferme (le schegge volano ~2.1s)
                        if t > 1.6:
                                _capture("boss_arena_rubble")
                                stage = 5
                                t = 0.0
                5:
                        # prepara la detonazione DEBOLE sul boss
                        if t > 0.9:
                                fire_barrel = _find_idle_barrel_of_element(1)  # FIRE
                                if fire_barrel == null:
                                        # forza un barile idle a FUOCO
                                        for b in boss_room._arena_barrels:
                                                if b != null and is_instance_valid(b) \
                                                                and b.is_idle():
                                                        fire_barrel = b
                                                        fire_barrel.element = 1
                                                        break
                                if fire_barrel != null:
                                        boss_room.boss.pos = Vector2(960.0, 620.0)
                                        # boss fermo: l'esplosione resta
                                        # centrata sullo sprite alla cattura
                                        boss_room.boss.dx = 0
                                        boss_room.boss.dy = 0
                                        fire_barrel.position = boss_room.boss.pos
                                        fire_barrel.detonate()
                                        fire_barrel.confirm_weakness()
                                stage = 6
                                t = 0.0
                6:
                        # esplosione a metà (~280ms): core + onde + DEBOLEZZA!
                        if t > 0.28:
                                _capture("boss_arena_explosion")
                                _crop_capture("boss_arena_explosion",
                                        Rect2i(700, 380, 520, 480))
                                stage = 7
                                t = 0.0
                7:
                        # player raccoglie il cannone + un barile in spalla
                        if t > 1.4:
                                if boss_room._arena_siege != null \
                                                and is_instance_valid(boss_room._arena_siege):
                                        boss_room.player.position = \
                                                        boss_room._arena_siege.position
                                var other: Node2D = null
                                for b in boss_room._arena_barrels:
                                        if b != null and is_instance_valid(b) \
                                                        and b.is_idle():
                                                other = b
                                                break
                                if other != null:
                                        other.pickup(boss_room.player)
                                boss_room.player.dx = 1
                                boss_room.player.last_dx = 1
                                stage = 8
                                t = 0.0
                8:
                        if t > 0.7:
                                _capture("boss_arena_siege")
                                _crop_capture("boss_arena_siege",
                                        Rect2i(820, 700, 280, 300))
                                print("[SHOT-ARENA] ==== SCREENSHOT ARENA COMPLETI ====")
                                get_tree().quit(0)
