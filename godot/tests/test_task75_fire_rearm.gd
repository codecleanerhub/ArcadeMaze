## test_task75_fire_rearm.gd — TASK 75: regressione del GATE anti-sparo
## alla chiusura della card bonus (feedback utente: "quando si chiude la
## card tenendo premuto il pulsante di fuoco... la dinamite viene lanciata
## subito dopo la chiusura della card").
##
## Meccanica da verificare (MainGameController):
##   A. _on_bonus_card_closed() ARMA il gate di riarmo per P1 e P2
##   B. con il gate armato e il fuoco PREMUTO, _handle_input() NON spara
##      (ne' edge ne' autofire: nessun colpo sprecato)
##   C. dopo il RILASCIO il gate si sblocca da solo (_update_fire_rearm)
##   D. una NUOVA pressione dopo il rilascio spara regolarmente
##   E. senza card chiusa (flusso normale) il fuoco funziona (no regression)
##
## Il percorso tastiera e' verificabile headless via Input.action_press;
## il percorso joystick e' coperto dallo stesso gate (fire_now/fire_edge
## azzerati quando il gate e' armato, vedi MainGameController TASK 75).
extends Node

const MainGameScene = preload("res://scenes/MainGame.tscn")

var main: Node2D = null
var failures: Array = []
var checks: int = 0


func _fail(msg: String) -> void:
        failures.append(msg)
        print("[TEST-75] FAIL: ", msg)


func _ok(msg: String) -> void:
        checks += 1
        print("[TEST-75] OK: ", msg)


func _ready() -> void:
        process_mode = Node.PROCESS_MODE_ALWAYS
        LoadingScreen.skip_boot_hold()
        GameManager.reset_run()
        main = MainGameScene.instantiate()
        get_tree().root.add_child.call_deferred(main)
        print("[TEST-75] boot MainGame")
        _run_all.call_deferred()


func _weapon_ammo() -> int:
        return int(main.player.current_weapon.get("ammo", 0))


func _run_all() -> void:
        # attesa boot (pattern degli altri test runtime)
        for i in 30:
                await get_tree().physics_frame
        if main == null or main.player == null:
                _fail("boot: MainGame/player non pronti")
                _finish()
                return

        # arma di test con munizioni (niente reliquia: ramo pistola)
        main.player.current_weapon = {
                "name": "test_gun", "type": 0, "ammo": 50,
                "damage": 1, "speed": 300.0, "melee": false,
        }
        main.player.set_direction(1, 0)
        main.dynamite_equipped = false
        Input.action_release("shoot")
        await get_tree().physics_frame

        # --- E. flusso normale: il fuoco FUNZIONA (no regressione) -------
        # NB: Input.action_press rende is_action_just_pressed true solo dal
        # frame fisica SUCCESSIVO (verificato con micro-test): await frame
        # tra la pressione e _handle_input.
        var ammo0: int = _weapon_ammo()
        main.player.shoot_cooldown = 0
        Input.action_press("shoot")
        await get_tree().physics_frame
        main._handle_input()
        Input.action_release("shoot")
        if _weapon_ammo() < ammo0 or main.player.shoot_cooldown > 0:
                _ok("E: pressione normale spara (flusso intatto)")
        else:
                _fail("E: il fuoco normale non funziona piu' (regressione!)")
        # raffreddamento e rilascio
        for i in 5:
                await get_tree().physics_frame
        Input.action_release("shoot")
        main.player.shoot_cooldown = 0
        var ammo1: int = _weapon_ammo()
        await get_tree().physics_frame
        main._handle_input()  # consuma l'eventuale fronte residuo

        # --- A. chiusura card ARMA il gate --------------------------------
        main._on_bonus_card_closed()
        if main._fire_rearm_p1 and main._fire_rearm_p2:
                _ok("A: card chiusa -> gate riarmo attivo per P1 e P2")
        else:
                _fail("A: gate di riarmo non armato alla chiusura")

        # --- B. fuoco TENUTO PREMUTO dopo la chiusura: NESSUN colpo -------
        Input.action_press("shoot")  # nuova pressione col gate armato
        await get_tree().physics_frame
        main._handle_input()
        if _weapon_ammo() == ammo1 and main.player.shoot_cooldown == 0:
                _ok("B: pressione col gate armato NON spara (colpo risparmiato)")
        else:
                _fail("B: colpo partito col gate armato (ammo %d->%d, cd %d)"
                                % [ammo1, _weapon_ammo(), main.player.shoot_cooldown])
        # resta premuto ancora un frame (autofire inibito)
        main._handle_input()
        if _weapon_ammo() == ammo1 and main.player.shoot_cooldown == 0:
                _ok("B2: tenuto premuto, autofire inibito")
        else:
                _fail("B2: autofire partito col gate armato")

        # --- C. rilascio -> gate si sblocca da solo -----------------------
        Input.action_release("shoot")
        await get_tree().physics_frame
        main._handle_input()
        if not main._fire_rearm_p1:
                _ok("C: rilascio -> gate P1 sbloccato")
        else:
                _fail("C: gate P1 non sbloccato dopo il rilascio")
        if not main._fire_rearm_p2:
                _ok("C2: gate P2 sbloccato (pulsante mai premuto)")
        else:
                _fail("C2: gate P2 ancora armato senza pulsante premuto")

        # --- D. nuova pressione DOPO il rilascio: spara -------------------
        main.player.shoot_cooldown = 0
        Input.action_press("shoot")
        await get_tree().physics_frame
        main._handle_input()
        Input.action_release("shoot")
        if _weapon_ammo() < ammo1 or main.player.shoot_cooldown > 0:
                _ok("D: nuova pressione dopo il rilascio spara")
        else:
                _fail("D: fuoco morto dopo il gate (ammo %d, cd %d)"
                                % [_weapon_ammo(), main.player.shoot_cooldown])

        _finish()


func _finish() -> void:
        Input.action_release("shoot")
        await get_tree().physics_frame
        if failures.is_empty():
                print("[TEST-75] ==== TEST GATE FUOCO POST-CARD SUPERATO "
                                + str(checks) + " check ====")
        else:
                print("[TEST-75] ==== TEST GATE FUOCO POST-CARD: "
                                + str(failures.size()) + " FALLI ====")
                for f in failures:
                        print("  - ", f)
        get_tree().quit(0 if failures.is_empty() else 1)
