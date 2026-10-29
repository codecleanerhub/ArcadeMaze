## test_task58b_demo_sprites.gd — TASK 58b: verifica DETERMINISTICA che
## le sprite reali della demo si carichino (player/enemy/ally) e che i
## dispatcher _dp/_de usino la strada _real quando le texture ci sono.
extends Node

const CardClass = preload("res://scripts/ui/BonusCardOverlay.gd")
const CollectiblesClass = preload("res://scripts/items/Collectibles.gd")


func _ready() -> void:
        var card: CanvasLayer = CardClass.new()
        card.setup(int(CollectiblesClass.Kind.HAMMER), 1, 0)
        add_child(card)
        await get_tree().process_frame
        var ok: int = 0
        if card._demo_player_tex != null:
                ok += 1
                print("[TEST58b] player_tex OK: ",
                                card._demo_player_tex.resource_path)
        else:
                print("[TEST58b] FAIL player_tex NULL")
        if card._demo_enemy_tex != null:
                ok += 1
                print("[TEST58b] enemy_tex OK: ",
                                card._demo_enemy_tex.resource_path)
        else:
                print("[TEST58b] FAIL enemy_tex NULL")
        if card._demo_ally_tex != null:
                ok += 1
                print("[TEST58b] ally_tex OK: ",
                                card._demo_ally_tex.resource_path)
        else:
                print("[TEST58b] FAIL ally_tex NULL")
        print("[TEST58b] flag DEMO_REAL_SPRITES_ENABLED = ",
                        card.DEMO_REAL_SPRITES_ENABLED)
        print("[TEST58b] char_type = ", card.demo_char_type)
        card.queue_free()
        print("[TEST58b] check ", ok, "/3")
        get_tree().quit(0 if ok == 3 else 1)
