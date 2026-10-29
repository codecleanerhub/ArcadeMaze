## shot_task84_freeze.gd — TASK 84: riproduzione IN-GIOCO del bug utente
## "due quadrati bianchi con palla celeste sopra il portale".
##
## Ipotesi da verificare: freeze_kill() congela dei nemici (health=0, statua
## di ghiaccio permanente); al 50% kill il portale li raccoglie in
## dead_indices e li respawn-a con init() che NON resetta 'frozen' → nemici
## VIVI ma congelati per sempre vicino al portale (mostro + iceblock =
## quadrato bianco con centro azzurro che nasconde il portale).
extends Node

const MainGameScene = preload("res://scenes/MainGame.tscn")

var main: Node2D = null
var t: float = 0.0
var stage: int = 0
var portal_seen_ms: float = -1.0
var captured: int = 0

func _ready() -> void:
        LoadingScreen.skip_boot_hold()
        GameManager.num_players = 1
        GameManager.reset_run()
        main = MainGameScene.instantiate()
        get_tree().root.add_child.call_deferred(main)
        print("[SHOT84F] boot MainGame 1P...")

func _physics_process(delta: float) -> void:
        t += delta
        if t > 60.0:
                print("[SHOT84F] TIMEOUT")
                get_tree().quit(1)
                return
        if main == null or not main.is_node_ready():
                return
        if stage == 0:
                _start()
                stage = 1
                return
        var spawner: Node = main.spawner
        var portal: Dictionary = spawner.magic_portal
        if stage == 1 and portal.active:
                stage = 2
                portal_seen_ms = t
                print("[SHOT84F] PORTALE ATTIVO t=%.2f pos=%s" % [t, portal.pos])
        if stage == 2:
                var elapsed: float = t - portal_seen_ms
                # fase spawn: nemici respawnati (open 1s + spawn ogni ~4s)
                if elapsed > 1.2 and captured < 1:
                        captured = 1
                if elapsed > 2.5 and captured < 2:
                        _dump("post-respawn")
                        _snap("task84f_respawn.png")
                        captured = 2
                if elapsed > 6.5 and captured < 3:
                        _dump("t+6.5s")
                        _snap("task84f_late.png")
                        captured = 3
                        print("[SHOT84F] DONE")
                        get_tree().quit(0)

func _start() -> void:
        main.start_level(1)
        await get_tree().physics_frame
        await get_tree().physics_frame
        var spawner: Node = main.spawner
        var n: int = spawner.enemies.size()
        print("[SHOT84F] nemici iniziali: %d" % n)
        # congela 2 nemici (freeze_kill: health=0 + frozen=true, statua)
        # e uccidi 2 normalmente: vivi=2 su 6 → sotto la soglia 50%
        var frozen_n: int = 0
        var killed: int = 0
        for i in range(n):
                var e: Node = spawner.enemies[i]
                if not e or e.is_dead():
                        continue
                if frozen_n < 2:
                        e.freeze_kill()
                        frozen_n += 1
                        print("[SHOT84F] freeze_kill su nemico idx=%d type=%s" % [i, e.type])
                elif killed < 2:
                        e.health = 0
                        killed += 1
        print("[SHOT84F] 2 congelati + 2 uccisi → vivi=2, soglia 50%% superata")

func _dump(tag: String) -> void:
        var spawner: Node = main.spawner
        for e in spawner.enemies:
                if e is Node2D and not e.is_dead():
                        print("[SHOT84F][%s] enemy VIVO type=%s pos=%s frozen=%s" % [
                                tag, e.type, e.position, e.frozen])

func _snap(fname: String) -> void:
        var img: Image = get_viewport().get_texture().get_image()
        img.save_png("/tmp/" + fname)
        print("[SHOT84F] snap: /tmp/%s" % fname)
