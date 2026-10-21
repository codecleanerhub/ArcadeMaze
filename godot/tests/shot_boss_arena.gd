## shot_boss_arena.gd — TASK 39: screenshot dell'ARENA DEL BOSS.
##
## Catture (in /home/z/my-project/download/):
##   1. boss_arena_overview        — arena completa: pilastri a tema, barili,
##                                    cannone, boss (TASK 41: hint debolezza
##                                    RIMOSSO dall'HUD; TASK 43: architetture
##                                    gotiche Bloodborne 68x184)
##   2. boss_arena_pillar_cracked  — pilastro a 2 colpi (crepe visibili)
##   3. boss_arena_collapse        — crollo con frammenti in volo
##   3b. boss_arena_rubble         — TASK 43: cumulo di macerie fermo
##                                    (test che NON risorgono al rinnovo)
##   4. boss_arena_explosion       — detonazione FUOCO sul boss con testo
##                                    "DEBOLEZZA!" (moltiplicatore x2.5)
##   5. boss_arena_siege           — player con cannone equipaggiato + pickup
##                                    + crop ravvicinati (pilastro/barile/canna)
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


func _ready() -> void:
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
                        # overview: tutto appena spawnato
                        if t > 0.6:
                                _capture("boss_arena_overview")
                                # 2 colpi al pilastro 0 -> crepe visibili
                                boss_room._arena_pillars[0].take_hit()
                                boss_room._arena_pillars[0].take_hit()
                                stage = 2
                                t = 0.0
                2:
                        if t > 0.45:
                                _capture("boss_arena_pillar_cracked")
                                _crop_capture("boss_arena_pillar_cracked",
                                        Rect2i(315, 275, 230, 330))
                                # colpo finale -> crollo
                                boss_room._arena_pillars[0].take_hit()
                                stage = 3
                                t = 0.0
                3:
                        # frammenti in volo (~300ms dal crollo)
                        if t > 0.32:
                                _capture("boss_arena_collapse")
                                _crop_capture("boss_arena_collapse",
                                        Rect2i(265, 225, 330, 440))
                                stage = 4
                                t = 0.0
                4:
                        # TASK 43: macerie ferme (il crollo dura 430ms)
                        if t > 1.2:
                                _capture("boss_arena_rubble")
                                _crop_capture("boss_arena_rubble",
                                        Rect2i(315, 275, 230, 330))
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
