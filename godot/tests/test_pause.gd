## test_pause.gd — Verifica runtime del toggle pausa "P" (MainGame e BossRoom).
## ROOT CAUSE storica: nella BossRoom il check della pausa era dentro
## _handle_input chiamato da _physics_process che fa `return` quando
## is_paused → il secondo P non veniva MAI rilevato. Il fix sposta il
## toggle in _unhandled_input (attivo anche con tree paused grazie a
## process_mode ALWAYS). Questo test inietta VARI eventi P reali.
extends Node

const MainGameScene = preload("res://scenes/MainGame.tscn")
const BossRoomScene = preload("res://scenes/BossRoom.tscn")

var scene: Node2D = null
var phase: int = 0
var t: float = 0.0
var p_count: int = 0
var failures: Array = []
var _wait_since: float = 0.0
var _dbg: int = 0


func _fail(msg: String) -> void:
        failures.append(msg)
        print("[TEST FAIL] ", msg)


func _press_p() -> void:
        p_count += 1
        var ev_down := InputEventKey.new()
        ev_down.keycode = KEY_P
        ev_down.pressed = true
        Input.parse_input_event(ev_down)
        var ev_up := InputEventKey.new()
        ev_up.keycode = KEY_P
        ev_up.pressed = false
        Input.parse_input_event(ev_up)
        print("[TEST] P premuto (", p_count, ")")


func _ready() -> void:
        # Il nodo di test DEVE continuare a girare con il tree in pausa per
        # poter iniettare il secondo P (il freeze del test è di per sé la
        # prova indiretta che la pausa scatta!).
        process_mode = Node.PROCESS_MODE_ALWAYS
        scene = MainGameScene.instantiate()
        get_tree().root.add_child.call_deferred(scene)
        print("[TEST] boot MainGame per test pausa...")


func _physics_process(delta: float) -> void:
        t += delta
        # heartbeat diagnostico
        if int(t * 2.0) != int((t - delta) * 2.0):
                print("[TEST] heartbeat t=", t, " phase=", phase, " paused=", get_tree().paused,
                                " scene_null=", scene == null)
        # Fase 3 = transizione (istanzia la nuova scena); fase 4 = attesa ready
        # con guard dedicato. Le altre fasi richiedono la scena pronta.
        if phase != 3 and phase != 4:
                if scene == null or not scene.is_node_ready():
                        return
        match phase:
                0:
                        if t > 1.0:
                                phase = 1
                                _press_p()
                1:
                        if t > 1.3:
                                if not get_tree().paused:
                                        _fail("MAINGAME: primo P non ha messo in pausa")
                                elif scene.is_paused != true:
                                        _fail("MAINGAME: is_pausa non true dopo il primo P")
                                else:
                                        print("[TEST] MAINGAME OK: P -> pausa attiva (tree.paused=true)")
                                _press_p()
                                phase = 2
                2:
                        if t > 1.6:
                                if get_tree().paused:
                                        _fail("MAINGAME: secondo P NON ha tolto la pausa (bug storico)")
                                elif scene.is_paused != false:
                                        _fail("MAINGAME: is_paused non false dopo il secondo P")
                                else:
                                        print("[TEST] MAINGAME OK: secondo P -> pausa tolta (toggle funziona)")
                                # Passa alla BossRoom
                                scene.queue_free()
                                scene = null
                                phase = 3
                3:
                        scene = BossRoomScene.instantiate()
                        get_tree().root.add_child.call_deferred(scene)
                        print("[TEST] BossRoom istanziata, attesa ready...")
                        _wait_since = t
                        phase = 4
                4:
                        if scene == null:
                                return
                        if not scene.is_node_ready():
                                if t - _wait_since > float(_dbg) + 1.0:
                                        _dbg += 1
                                        print("[TEST] attesa ready t=", t,
                                                " inside_tree=", scene.is_inside_tree(),
                                                " ready=", scene.is_node_ready())
                                return
                        if t > 2.2:
                                # Safety: la BossRoom al boot deve ripristinare pause residue.
                                if get_tree().paused:
                                        _fail("BOSSROOM: avvio con tree paused residuo")
                                _press_p()
                                phase = 5
                5:
                        if t > 2.5:
                                if not get_tree().paused:
                                        _fail("BOSSROOM: primo P non ha messo in pausa")
                                else:
                                        print("[TEST] BOSSROOM OK: P -> pausa attiva")
                                _press_p()
                                phase = 6
                6:
                        if t > 2.8:
                                if get_tree().paused:
                                        _fail("BOSSROOM: secondo P NON ha tolto la pausa (BUG SEGNALATO DALL'UTENTE)")
                                else:
                                        print("[TEST] BOSSROOM OK: secondo P -> pausa tolta (bug fixato)")
                                if scene._pause_overlay != null and scene._pause_overlay.visible:
                                        _fail("BOSSROOM: overlay PAUSE non nascosto dopo il resume")
                                phase = 9
                9:
                        if failures.is_empty():
                                print("[TEST] ==== TUTTI I TEST PAUSA SUPERATI (runtime Godot) ====")
                                get_tree().quit(0)
                        else:
                                print("[TEST] ==== FALLITI ", failures.size(), " test ====")
                                for f in failures:
                                        print("[TEST FAIL] ", f)
                                get_tree().quit(1)
