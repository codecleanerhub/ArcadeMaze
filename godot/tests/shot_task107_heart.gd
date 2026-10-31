## shot_task107_heart.gd — TASK 107: screenshot del CUORE NASCOSTO
## (Collectibles.Kind.HEART) a tre scale su fondo scuro: PNG ui_heart.png
## + doppio alone rosso pulsante + ombra a terra (pattern medikit).
extends Node2D

const CollectiblesClass = preload("res://scripts/items/Collectibles.gd")

var hearts: Array = []
var t := 0.0


func _ready() -> void:
        LoadingScreen.skip_boot_hold()
        var positions := [Vector2(640, 420), Vector2(960, 560), Vector2(1280, 700)]
        var scales := [3.2, 2.2, 1.4]
        for i in positions.size():
                var holder := Node2D.new()
                holder.position = positions[i]
                holder.scale = Vector2(scales[i], scales[i])
                var h := CollectiblesClass.make_heart(Vector2.ZERO)
                holder.add_child(h)
                add_child(holder)
                hearts.append(h)


func _process(delta: float) -> void:
        t += delta
        for h in hearts:
                h.update_step(int(delta * 1000.0), Vector2.ZERO)


func _draw() -> void:
        # fondo scuro tipo corridoio di labirinto per leggere gli aloni
        draw_rect(Rect2(Vector2.ZERO, Vector2(1920, 1080)),
                Color(0.09, 0.08, 0.12, 1.0), true)
