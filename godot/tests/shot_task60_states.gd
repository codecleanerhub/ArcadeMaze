## shot_task60_states.gd — TASK 60c: screenshot STATI NEMICI con i nuovi
## overlay PixelLab.
##
## 3 nemici identici (ZOMBIE) affiancati su sfondo scuro:
##   x=300  CONGELATO  -> ibrido: cristallo effect_iceblock.png (modulate
##                        0.66) + sparkles procedurali animati
##   x=700  FOLGORATO   -> sheet effect_shockarc (4 frame, jitter 10 fps)
##   x=1100 BRUCIATO    -> sheet effect_fireaura (confronto, invariato)
##
## Verifica: overlay PixelLab sopra sprite reali del nemico, mostro
## visibile in trasparenza nel ghiaccio, nessun crash.
##
## Screenshot via --write-movie (lezione worklog: mai get_image()):
##   Xvfb :99 & DISPLAY=:99 godot --path . --resolution 1920x1080 \
##     --write-movie /home/z/my-project/scripts/task60c_movie/f.png \
##     --fixed-fps 10 --quit-after 40 res://tests/shot_task60_states.tscn
extends Node2D

const EnemyScript = preload("res://scripts/enemies/Enemy.gd")

var t: float = 0.0
var enemies: Array = []


func _ready() -> void:
        LoadingScreen.skip_boot_hold()
        var bg := ColorRect.new()
        bg.color = Color(0.09, 0.08, 0.12)
        bg.size = Vector2(1920, 1080)
        bg.z_index = -10
        add_child(bg)
        for spec in [[300.0, "frozen"], [700.0, "shock"], [1100.0, "burn"]]:
                var e := EnemyScript.new()
                e.init(EnemyScript.EnemyType.ZOMBIE, 3, 3)
                e.position = Vector2(spec[0], 480.0)
                e.last_pos = e.position
                match String(spec[1]):
                        "frozen":
                                e.frozen = true
                        "shock":
                                e.start_electrified(1_000_000)
                        "burn":
                                e.burning_timer = 1_000_000
                add_child(e)
                enemies.append(e)
                print("[STATES60] spawn ", spec[1], " a x=", spec[0])


func _process(delta: float) -> void:
        t += delta
        # pilota anim_time (in ms) per sparkles/jitter/pulse senza update AI
        for e in enemies:
                e.anim_time += int(delta * 1000.0)
                e.queue_redraw()
        if t >= 3.5:
                print("[STATES60] completato senza crash")
                get_tree().quit(0)
