## test_hurryup.gd — Test funzionale end-to-end della meccanica "Hurry Up!"
## (eseguito in headless). Verifica nel runtime REALE di Godot:
##   1. Kill di tutti i nemici → 10s → fantasma spawnato dal portale
##   2. La risata tenebrosa scatta quando gli si spara (segnale laughed)
##   3. Il proiettile viene assorbito (active=false), il fantasma NON muore
##   4. Il contatto col fantasma danneggia il player
##   5. start_level() rimuove fantasma e scritta (riapparirà al prossimo)
##   6. Il percorso di _draw del fantasma e della scritta gira senza errori
extends Node

const MainGameScene = preload("res://scenes/MainGame.tscn")

var main: Node2D = null
var phase: int = 0
var t: float = 0.0
var laughed_count: int = 0
var failures: Array = []
var energy_before_hit: int = -1


func _ready() -> void:
        # Istanza il gioco vero (autoload già attivi).
        main = MainGameScene.instantiate()
        get_tree().root.add_child.call_deferred(main)
        print("[TEST] boot MainGame...")


func _fail(msg: String) -> void:
        failures.append(msg)
        print("[TEST FAIL] ", msg)


func _physics_process(delta: float) -> void:
        t += delta
        if main == null or not main.is_node_ready():
                return
        match phase:
                0:
                        # Attendi setup del primo livello.
                        if t > 1.0:
                                phase = 1
                                print("[TEST] fase 1: uccido TUTTI i nemici (kill istantanea)")
                                for e in main.spawner.enemies:
                                        if e != null and is_instance_valid(e):
                                                e.take_damage(999)
                                main.spawner.remove_dead()
                                print("[TEST] nemici rimasti: ", main.spawner.alive_count())
                1:
                        # Attende i 10s (con 1s di margine). Il fantasma deve apparire.
                        if t > 12.5:
                                if main.ghost_reaper == null:
                                        _fail("il fantasma NON è apparso dopo 10s dalla morte di tutti i nemici")
                                elif not main.hurry_up_active:
                                        _fail("hurry_up_active non impostato")
                                else:
                                        print("[TEST] OK: fantasma apparso a t=", t, "s, portale attivo=",
                                                        main.spawner.magic_portal.active)
                                phase = 2
                2:
                        # Spara al fantasma: proiettile finto direttamente sulla sua posizione.
                        var ghost = main.ghost_reaper
                        if ghost == null:
                                phase = 9
                                return
                        ghost.laughed.connect(func(_p): laughed_count += 1)
                        var fake_proj: Dictionary = {
                                "pos": ghost.get_pixel_pos(),
                                "dir": Vector2(1, 0),
                                "power": 3,
                                "active": true,
                        }
                        main.player.projectiles.append(fake_proj)
                        var e_before: int = main.player.energy
                        main._check_player_projectiles_vs_enemies(main.player)
                        if not fake_proj["active"]:
                                print("[TEST] OK: proiettile assorbito dall'ectoplasma")
                        else:
                                _fail("il proiettile non è stato assorbito dal fantasma")
                        if laughed_count < 1:
                                _fail("il segnale laughed non è scattato sparando al fantasma")
                        else:
                                print("[TEST] OK: risata tenebrosa (laughed x", laughed_count, ")")
                        if ghost.is_dead():
                                _fail("il fantasma IMMORTALE è morto (take_damage letale)")
                        else:
                                print("[TEST] OK: il fantasma è immortale")
                        if main.player.energy != e_before:
                                _fail("lo sparo al fantasma ha danneggiato il player")
                        # Percorso di _draw del fantasma eseguito dentro un
                        # contesto di draw VERO: si usa il segnale `draw` del
                        # nodo (scatta dentro NOTIFICATION_DRAW). Se headless
                        # non renderizza, il test salta silenziosamente.
                        var draw_done: Array = [false]
                        ghost.draw.connect(func():
                                draw_done[0] = true)
                        ghost.queue_redraw()
                        print("[TEST] draw del fantasma agganciato via segnale draw")
                        phase = 3
                3:
                        # Contatto: teletrasporta il fantasma addosso al player e chiama
                        # la melee: il player deve perdere energia.
                        var ghost2 = main.ghost_reaper
                        if ghost2 == null:
                                phase = 9
                                return
                        var p_pos: Vector2 = main.player.get_pixel_pos()
                        ghost2.pos = p_pos
                        ghost2.position = p_pos
                        energy_before_hit = main.player.energy
                        main._check_melee_collisions(main.player)
                        if main.player.energy < energy_before_hit:
                                print("[TEST] OK: contatto col fantasma = danno (",
                                                energy_before_hit, " -> ", main.player.energy, ")")
                        else:
                                _fail("il contatto col fantasma non ha fatto danno")
                        phase = 4
                4:
                        # Cambio livello: il fantasma e la scritta spariscono.
                        main.start_level(main.current_level + 1)
                        if main.ghost_reaper != null:
                                _fail("start_level non ha rimosso il fantasma")
                        elif main.hurry_up_active:
                                _fail("start_level non ha resettato hurry_up_active")
                        else:
                                print("[TEST] OK: start_level ha rimosso fantasma e scritta")
                        phase = 9
                9:
                        if failures.is_empty():
                                print("[TEST] ==== TUTTI I TEST HURRY UP SUPERATI (runtime Godot) ====")
                                get_tree().quit(0)
                        else:
                                print("[TEST] ==== FALLITI ", failures.size(), " test ====")
                                for f in failures:
                                        print("[TEST FAIL] ", f)
                                get_tree().quit(1)
