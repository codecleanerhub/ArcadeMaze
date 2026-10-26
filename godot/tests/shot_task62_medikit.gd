## shot_task62_medikit.gd — TASK 62: screenshot in-game del medikit
## DOPO il fix di leggibilita' (size 48px + ombra + doppio alone).
##
## Confronto con i "before" (urn60_stone.png / dragon61_*.png /
## t61w_*.png in download/) dove il medikit 64px grigio-scuro a cella
## piena si fondeva con i muri ("sopra un muro, irraggiungibile").
##
## Screenshot via --write-movie (lezione worklog: MAI get_image() sotto
## llvmpipe):
##   Xvfb :99 & DISPLAY=:99 godot --path . --resolution 1920x1080 \
##     --write-movie /home/z/my-project/scripts/task62_movie/f.png \
##     --fixed-fps 10 --quit-after 30 res://tests/shot_task62_medikit.tscn
extends Node2D

var main: Node2D = null
var t: float = 0.0
var printed: bool = false


func _ready() -> void:
        LoadingScreen.skip_boot_hold()
        GameManager.num_players = 1
        GameManager.reset_run()
        var scene := load("res://scenes/MainGame.tscn") as PackedScene
        main = scene.instantiate()
        add_child.call_deferred(main)


func _process(delta: float) -> void:
        if main == null or not main.is_node_ready():
                return
        # sicurezza: niente nemici durante lo shot.
        for e in main.spawner.enemies.duplicate():
                if is_instance_valid(e):
                        e.queue_free()
        main.spawner.enemies.clear()
        if not printed:
                printed = true
                var mk: Node2D = main.medikit_item
                if mk != null and is_instance_valid(mk):
                        print("[MED62] medikit pos=", mk.position,
                                        " cella=(", int(mk.position.x / 64), ",",
                                        int((mk.position.y - 80.0) / 64.0), ")")
                else:
                        print("[MED62] WARNING: medikit_item nullo!")
        t += delta
        if t >= 2.6:
                print("[MED62] done, frame=", Engine.get_frames_drawn())
                get_tree().quit(0)
