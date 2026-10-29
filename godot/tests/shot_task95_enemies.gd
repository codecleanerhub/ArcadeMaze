## shot_task95_enemies.gd — TASK 95: screenshot dei 3 nemici rigenerati
## corpo completo (prima "mezzo busto"): WITCH (la strega dello screenshot
## utente), LOST_SOUL, GIBBERING_MOUTHER. Rendering fedele al gioco:
## Enemy.gd disegna lo sheet SD a scala 78px su sfondo dungeon.
extends Node2D

const EnemyScript = preload("res://scripts/enemies/Enemy.gd")


func _ready() -> void:
        LoadingScreen.skip_boot_hold()
        var bg := ColorRect.new()
        bg.color = Color(0.09, 0.08, 0.12)
        bg.size = Vector2(1920, 1080)
        bg.z_index = -10
        add_child(bg)
        _label(Vector2(960, 50),
                        "TASK 95 — NEMICI RIGENERATI CORPO COMPLETO (PixelLab)",
                        30, true)
        var x: float = 320.0
        for pair in [
                        [EnemyScript.EnemyType.WITCH, "STREGA (monster_007)"],
                        [EnemyScript.EnemyType.LOST_SOUL, "ANIMA PERDUTA (monster_044)"],
                        [EnemyScript.EnemyType.GIBBERING_MOUTHER, "BOCCA FARFUGLIANTE (monster_031)"],
                ]:
                var e := EnemyScript.new()
                e.init(pair[0], 3, 3)
                e.position = Vector2(x, 480.0)
                e.last_pos = e.position
                add_child(e)
                _label(Vector2(x, 600.0), pair[1], 22, false)
                x += 640.0
        # un paio di frame di rendering, poi cattura
        for _i in 3:
                await get_tree().process_frame
        var img: Image = get_viewport().get_texture().get_image()
        img.save_png("/home/z/my-project/download/task95_ingame.png")
        print("[SHOT95] salvato task95_ingame.png")
        get_tree().quit(0)


func _label(at: Vector2, text: String, size: int, bold: bool) -> void:
        var l := Label.new()
        l.text = text
        l.position = at - Vector2(160.0, 0.0)
        l.add_theme_font_size_override("font_size", size)
        if bold:
                l.modulate = Color(0.98, 0.92, 0.75)
        add_child(l)
