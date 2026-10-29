## shot_task84_portalbug.gd — TASK 84: riproduzione IN-GIOCO del bug utente
## "appena appare il portale, due quadrati bianchi con palla celeste dentro
##  compaiono sopra il portale e lo nascondono".
##
## Istanzia la scena REALE MainGame.tscn, avvia un livello con nemici,
## uccide il 50% dei nemici (soglia portale), lascia girare il flusso NATURALE
## (trigger_portal_if_needed viene chiamato dall'update del controller),
## aspetta: apertura portale (1s) + spawn miniboss + uscita nemici respawnati
## (4s cad.) e scatta screenshot multipli:
##   t+0.3s (appena apparso), t+1.5s, t+5s (miniboss+nemico fuori), t+9.5s
## Stampa posizioni di portale/miniboss/nemici per l'analisi pixel.
extends Node

const MainGameScene = preload("res://scenes/MainGame.tscn")

var main: Node2D = null
var t: float = 0.0
var stage: int = 0
var portal_seen_ms: float = -1.0

func _ready() -> void:
        LoadingScreen.skip_boot_hold()
        GameManager.num_players = 1
        GameManager.reset_run()
        main = MainGameScene.instantiate()
        get_tree().root.add_child.call_deferred(main)
        print("[SHOT84] boot MainGame 1P...")

func _physics_process(delta: float) -> void:
        t += delta
        if t > 60.0:
                print("[SHOT84] TIMEOUT")
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
                print("[SHOT84] PORTALE ATTIVO t=%.2f pos=%s cell=%s" % [
                        t, portal.pos,
                        Vector2i(int(portal.pos.x) / 64, int(portal.pos.y - 80) / 64)])
                _dump_entities("portale-apparso")
        # scatti a vari tempi dall'attivazione
        if stage == 2:
                var elapsed: float = t - portal_seen_ms
                if elapsed > 0.35 and captured < 1:
                        _snap("task84_p1_appena.png"); captured = 1
                if elapsed > 1.5 and captured < 2:
                        _snap("task84_p2_aperto.png"); captured = 2
                if elapsed > 5.0 and captured < 3:
                        _dump_entities("miniboss+respawn")
                        _snap("task84_p3_spawn.png"); captured = 3
                if elapsed > 9.5 and captured < 4:
                        _dump_entities("fine-ciclo")
                        _snap("task84_p4_fine.png"); captured = 4
                        print("[SHOT84] DONE")
                        get_tree().quit(0)

var captured: int = 0

func _start() -> void:
        main.start_level(1)
        var spawner: Node = main.spawner
        # attendi che gli nemici siano spawnati dal flusso naturale
        await get_tree().physics_frame
        await get_tree().physics_frame
        var n: int = spawner.enemies.size()
        print("[SHOT84] nemici iniziali: %d" % n)
        # uccidi meta' dei nemici -> soglia 50% superata al prossimo update
        var to_kill: int = n / 2 + 1
        for i in range(to_kill):
                var e: Node = spawner.enemies[i]
                if e and not e.is_dead():
                        e.health = 0
                        e.set("death_timer_ms", 1.0)
        print("[SHOT84] uccisi %d nemici (soglia 50%%)" % to_kill)

func _dump_entities(tag: String) -> void:
        var spawner: Node = main.spawner
        var portal: Dictionary = spawner.magic_portal
        print("[SHOT84][%s] portal.active=%s phase=%s to_spawn=%s" % [
                tag, portal.active, portal.get("phase"), portal.get("enemies_to_spawn")])
        for e in spawner.enemies:
                if e is Node2D and not e.is_dead():
                        print("[SHOT84][%s] enemy type=%s pos=%s frozen=%s" % [
                                tag, e.type, e.position, e.get("frozen")])
        var mbs: Array = get_tree().get_nodes_in_group("mini_boss") if get_tree().has_group("mini_boss") else []
        for mb in mbs:
                if mb is Node2D:
                        print("[SHOT84][%s] MINIBOSS pos=%s sprite=%s deform=%s" % [
                                tag, mb.position,
                                mb.get("sprite_id"), mb.get("_deform_loaded")])

func _snap(fname: String) -> void:
        var img: Image = get_viewport().get_texture().get_image()
        img.save_png("/tmp/" + fname)
        print("[SHOT84] snap salvato: /tmp/%s" % fname)
