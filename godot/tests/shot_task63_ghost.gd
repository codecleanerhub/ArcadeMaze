## shot_task63_ghost.gd — TASK 63a: screenshot GHOST REAPER rigenerato
## PixelLab v2 (verde P1 + rosso P2) a confronto su sfondo scuro.
##
## Harness: 2 fantasmi affiancati (come compaiono dalla Hurry Up!),
## fade-in completato, anim_time avanzata dall'harness (frame walk 130ms),
## bob/aura/scia procedurali attivi come in gioco.
##
## Screenshot via --write-movie (lezione worklog: mai get_image()):
##   Xvfb :99 & DISPLAY=:99 godot --path . --resolution 1920x1080 \
##     --write-movie /home/z/my-project/scripts/task63_movie/f.png \
##     --fixed-fps 10 --quit-after 40 res://tests/shot_task63_ghost.tscn
extends Node2D

const GhostScript = preload("res://scripts/entities/GhostReaper.gd")

var t: float = 0.0
var ghosts: Array = []


func _ready() -> void:
        LoadingScreen.skip_boot_hold()
        var bg := ColorRect.new()
        bg.color = Color(0.09, 0.08, 0.12)
        bg.size = Vector2(1920, 1080)
        bg.z_index = -10
        add_child(bg)

        # Verde P1 (x=560) e rosso P2 (x=1360), come in gioco.
        for spec in [[8, "green"], [20, "red"]]:
                var g := GhostScript.new()
                g.is_red_variant = String(spec[1]) == "red"
                g.setup(int(spec[0]), 6)
                # fade-in gia' completo: alpha pieno come dopo 900ms in gioco
                g.spawn_timer_ms = 0.0
                # fase iniziale sfasata per mostrare frame diversi
                g.anim_time = 0.0 if String(spec[1]) == "green" else 0.2
                add_child(g)
                ghosts.append(g)


func _process(delta: float) -> void:
        t += delta
        var ms := int(delta * 1000.0)
        for g in ghosts:
                # solo animazione: niente update_step (richiederebbe il maze)
                g.anim_time += float(ms) * 0.001
                g.queue_redraw()
