## shot_env_props.gd — TASK 50: screenshot ARCHITETTURE ARENA BLOODBORNE.
##
## Verifica visiva in-game dei 10 props PixelLab 256x256 (colonne ricche,
## archi rotti, statue, candelieri, altare, obelischi, doccioni, inferriate,
## candelabri, sarcofaghi) disposti a incorniciare l'arena.
##
## Check:
##   1. le decorazioni sono spawnate (19 istanze attese su 1920x1080);
##   2. screenshot overview completa + crop di dettaglio (colonna sinistra
##      e fascia bassa);
##   3. nessun crash durante il rendering.
extends Node

const BossRoomScene = preload("res://scenes/BossRoom.tscn")

var boss_room: Node2D = null
var stage: int = 0
var t: float = 0.0


func _ready() -> void:
        GameManager.current_level = 52
        boss_room = BossRoomScene.instantiate()
        get_tree().root.add_child.call_deferred(boss_room)
        print("[SHOT-ENV] boot BossRoom lvl 52 (Mimico)...")


func _capture(tag: String, rect: Rect2i = Rect2i(0, 0, 0, 0)) -> void:
        var img: Image = get_viewport().get_texture().get_image()
        if rect.size.x > 0:
                img = img.get_region(rect)
        img.save_png("/home/z/my-project/download/" + tag + ".png")
        print("[SHOT-ENV] salvato ", tag, ".png")


func _physics_process(delta: float) -> void:
        t += delta
        if boss_room == null or not boss_room.is_node_ready():
                return
        match stage:
                0:
                        if t > 1.8:
                                var n: int = boss_room._boss_room_decorations.size()
                                print("[SHOT-ENV] decorazioni spawnate: ", n,
                                                " (attese 19)")
                                _capture("env50_overview")
                                stage = 1
                                t = 0.0
                1:
                        if t > 0.3:
                                # crop colonna cattedrale sinistra (dettaglio)
                                _capture("env50_crop_column",
                                                Rect2i(0, 300, 420, 780))
                                stage = 2
                                t = 0.0
                2:
                        if t > 0.3:
                                # crop fascia bassa: obelischi + sarcofaghi
                                _capture("env50_crop_bottom",
                                                Rect2i(380, 850, 1160, 230))
                                stage = 3
                                t = 0.0
                3:
                        print("[SHOT-ENV] completato senza crash.")
                        get_tree().quit(0)
