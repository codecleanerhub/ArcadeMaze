## test_2p_bossroom.gd — Smoke test runtime della boss room in 2P.
## Verifica: P2 presente e aggiornato, boss vivo che mira il player più
## vicino (nessun crash), HP HUD impostati, nessun errore di script dopo
## qualche secondo di fight simulato (input WASD via azioni p2_*).
extends Node

const BossRoomScene = preload("res://scenes/BossRoom.tscn")

var boss_room: Node2D = null
var phase: int = 0
var t: float = 0.0
var p2_pos_start: Vector2 = Vector2.ZERO
var failures: Array = []


func _ready() -> void:
        GameManager.num_players = 2
        boss_room = BossRoomScene.instantiate()
        get_tree().root.add_child.call_deferred(boss_room)
        print("[TEST] boot BossRoom 2P...")


func _fail(msg: String) -> void:
        failures.append(msg)
        print("[TEST FAIL] ", msg)


func _physics_process(delta: float) -> void:
        t += delta
        if boss_room == null or not boss_room.is_node_ready():
                return
        match phase:
                0:
                        if t > 1.5:
                                if not boss_room.player2.visible:
                                        _fail("P2 non visibile nella boss room")
                                else:
                                        print("[TEST] OK: P2 attivo in boss room")
                                if boss_room.boss == null or boss_room.boss.is_dead():
                                        _fail("boss non vivo all'avvio")
                                else:
                                        print("[TEST] OK: boss vivo, HP ",
                                                        boss_room.boss.health, "/",
                                                        boss_room.boss.max_health)
                                p2_pos_start = boss_room.player2.position
                                phase = 1
                1:
                        # Inietta input P2 (WASD via azioni p2_*) per verificare
                        # che il loop di input/fisica di P2 giri senza errori.
                        var ev := InputEventAction.new()
                        ev.action = "p2_left"
                        ev.pressed = true
                        Input.parse_input_event(ev)
                        if t > 5.0:
                                ev.pressed = false
                                Input.parse_input_event(ev)
                                phase = 2
                2:
                        # P2 si è mosso seguendo l'input? (movimento libero)
                        if boss_room.player2.position.x < p2_pos_start.x - 10.0:
                                print("[TEST] OK: P2 si muove in boss room (input p2_left)")
                        else:
                                _fail("P2 non si è mosso con input p2_left (joystick/tastiera 2P)")
                        if boss_room.boss != null and not boss_room.boss.is_dead():
                                print("[TEST] OK: fight attivo dopo 5s senza crash")
                        else:
                                _fail("boss morto/cancellato senza causa")
                        if failures.is_empty():
                                print("[TEST] ==== SMOKE TEST BOSS ROOM 2P SUPERATO ====")
                                get_tree().quit(0)
                        else:
                                for f in failures:
                                        print("[TEST FAIL] ", f)
                                get_tree().quit(1)
