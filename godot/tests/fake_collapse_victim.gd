## fake_collapse_victim.gd — TASK 87 test: CharacterBody2D con le API minime
## che PlayerCollapseEffect.setup() tocca (get_pixel_pos, sprite, tint).
## Lo sprite resta null: l'effetto usa il fallback procedurale (sagoma).
extends CharacterBody2D

var tint: Color = Color.WHITE
var sprite = null


func get_pixel_pos() -> Vector2:
        return position
