## shot_task60_proj.gd — TASK 60b: screenshot PROIETTILI BOSS PixelLab.
##
## Spawn statico dei 6 tipi di punta (fireball DEMONE variante 0+1,
## dragon_breath DRAGO, necro_bolt LICH, boulder GOLEM, ghost_bolt
## WRAITH_LORD, cult_orb CULT_HERALD) su sfondo piatto scuro, con etichetta
## di posizione stampata a log. Verifica:
##   1. i PNG vengono caricati e disegnati (PNG-first attivo);
##   2. il flicker 4-frame dei 2 sheet animati (age_ms avanza nel harness);
##   3. nessun crash in _draw.
##
## Screenshot via --write-movie (lezione worklog: mai get_image()):
##   Xvfb :99 & DISPLAY=:99 godot --path . --resolution 1920x1080 \
##     --write-movie /home/z/my-project/scripts/task60b_movie/f.png \
##     --fixed-fps 10 --quit-after 40 res://tests/shot_task60_proj.tscn
extends Node2D

const ProjectileScript = preload("res://scripts/items/Projectile.gd")

var t: float = 0.0
var projs: Array = []


func _ready() -> void:
        LoadingScreen.skip_boot_hold()
        var bg := ColorRect.new()
        bg.color = Color(0.09, 0.08, 0.12)
        bg.size = Vector2(1920, 1080)
        bg.z_index = -10
        add_child(bg)
        # [kind, variant, x, nome]
        var specs := [
                [ProjectileScript.BossProjKind.BP_FIREBALL, 0, 260.0, "FIREBALL"],
                [ProjectileScript.BossProjKind.BP_FIREBALL, 1, 520.0, "FIREBALL-v1"],
                [ProjectileScript.BossProjKind.BP_DRAGON_BREATH, 0, 780.0, "DRAGON"],
                [ProjectileScript.BossProjKind.BP_NECRO_BOLT, 0, 1040.0, "NECRO"],
                [ProjectileScript.BossProjKind.BP_BOULDER, 0, 1300.0, "BOULDER"],
                [ProjectileScript.BossProjKind.BP_GHOST_BOLT, 0, 1560.0, "GHOST"],
                [ProjectileScript.BossProjKind.BP_CULT_ORB, 0, 1810.0, "CULT"],
        ]
        for s in specs:
                var p := ProjectileScript.new()
                p.bp_kind = s[0]
                p.variant = s[1]
                p.pos = Vector2(s[2], 480.0)
                p.sync_position()
                p.active = true
                p.dir = Vector2(3.0, 0.0)   # direzione destra (scie/fiamme)
                add_child(p)
                projs.append(p)
                print("[PROJ60] spawn ", s[3], " a x=", s[2], " y=480")


func _process(delta: float) -> void:
        t += delta
        # avanza l'eta' per il flicker dei frame animati (senza muovere pos)
        for p in projs:
                p.age_ms += int(delta * 1000.0)
                p.queue_redraw()
        if t >= 3.0:
                print("[PROJ60] completato senza crash")
                get_tree().quit(0)
