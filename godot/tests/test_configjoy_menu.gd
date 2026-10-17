## test_configjoy_menu.gd — Test funzionale runtime (headless) del fix:
## "quando configuro il joystick dal menu OPTIONS, a fine configurazione
##  il gioco PARTIVA invece di tornare al menu principale".
##
##  A. OPTIONS -> CONFIGURE JOYSTICK (1P): jump + shoot -> si torna al MENU
##     PRINCIPALE col sottomenu OPTIONS aperto e cursore su CONFIGURE
##     JOYSTICK (NON su SelectPlayer/partita).
##  B. OPTIONS -> CONFIGURE JOYSTICK (2P): P1 (jump+shoot) -> switch in-place
##     a PLAYER 2 -> P2 (jump+shoot) -> si torna al menu (stesso comportamento).
##  C. START GAME (flusso legacy, from_options=false): a fine configurazione
##     si prosegue verso SelectPlayer come prima (nessuna regressione).
extends Node

const C = preload("res://scripts/core/GameConstants.gd")

var phase: int = 0
var st: float = 0.0
var failures: Array = []
var menu: Control = null
var _booted: bool = false


func _fail(msg: String) -> void:
        failures.append(msg)
        print("[TEST FAIL] ", msg)


func _ready() -> void:
        # Il test guida cambi di scena reali (MainMenu -> ConfigJoy -> menu):
        # per sopravvivere a change_scene_to_file (che libera SOLO la scena
        # corrente) il nodo test si sposta DIRETTAMENTE sotto il root, dove
        # nessun cambio di scena lo tocca, e azzera current_scene.
        get_parent().remove_child.call_deferred(self)
        get_tree().root.add_child.call_deferred(self)


func _joy(btn: int, pressed: bool) -> void:
        var ev := InputEventJoypadButton.new()
        ev.device = 0
        ev.button_index = btn
        ev.pressed = pressed
        Input.parse_input_event(ev)


func _scene_name() -> String:
        var cs: Node = get_tree().current_scene
        if cs == null or cs.scene_file_path.is_empty():
                return ""
        return cs.scene_file_path.get_file()


func _physics_process(delta: float) -> void:
        if not _booted:
                # Primo frame: i reparent differitati sono stati risolti.
                # Azzera la scena corrente e apri il MainMenu come farebbe
                # l'avvio normale del gioco.
                _booted = true
                get_tree().current_scene = null
                get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
                print("[TEST] boot MainMenu per test ConfigJoy...")
                return
        st += delta
        match phase:
                0:
                        # Attende il boot del MainMenu (scena principale del test).
                        if st > 1.0:
                                menu = get_tree().current_scene as Control
                                if menu == null or _scene_name() != "MainMenu.tscn":
                                        _fail("A: il test non parte dal MainMenu ("
                                                        + _scene_name() + ")")
                                        _finish()
                                        return
                                # Simula l'utente: OPTIONS -> CONFIGURE JOYSTICK.
                                menu._in_options = true
                                menu._menu_item_index = 1
                                menu._activate_current()
                                phase = 1
                                st = 0.0
                1:
                        # ConfigJoy deve apparire con il flag from_options attivo.
                        if st > 0.8:
                                if _scene_name() != "ConfigJoy.tscn":
                                        _fail("A: ConfigJoy non aperta dal menu OPTIONS ("
                                                        + _scene_name() + ")")
                                        _finish()
                                        return
                                if not GameManager.config_joy_from_options:
                                        _fail("A: config_joy_from_options non impostato")
                                print("[TEST] OK A1: OPTIONS -> ConfigJoy (from_options=true)")
                                _joy(0, true)  # jump
                                phase = 2
                                st = 0.0
                2:
                        if st > 0.2:
                                _joy(0, false)
                                phase = 3
                                st = 0.0
                3:
                        if st > 0.3:
                                _joy(2, true)  # shoot
                                phase = 4
                                st = 0.0
                4:
                        if st > 0.2:
                                _joy(2, false)
                                phase = 5
                                st = 0.0
                5:
                        # A fine configurazione (1P) si deve tornare al MENU.
                        if st > 0.8:
                                if _scene_name() != "MainMenu.tscn":
                                        _fail("A: dopo la configurazione il gioco e' PARTITO ("
                                                        + _scene_name() + ") invece di tornare al menu")
                                elif GameManager.config_joy_from_options:
                                        _fail("A: flag from_options non resettato")
                                elif not menu_visible_and_options():
                                        _fail("A: menu riaperto ma sottomenu OPTIONS non attivo"
                                                        + " o cursore non su CONFIGURE JOYSTICK")
                                else:
                                        print("[TEST] OK A: configurazione completata -> "
                                                        + "MENU PRINCIPALE (sottomenu OPTIONS, "
                                                        + "cursore su CONFIGURE JOYSTICK)")
                                # --- B: stesso flusso in 2P ---
                                GameManager.num_players = 2
                                GameManager.config_joy_player = 1
                                GameManager.config_joy_step = 0
                                menu = get_tree().current_scene as Control
                                menu._in_options = true
                                menu._menu_item_index = 1
                                menu._activate_current()
                                phase = 6
                                st = 0.0
                6:
                        if st > 0.8:
                                if _scene_name() != "ConfigJoy.tscn":
                                        _fail("B: ConfigJoy 2P non aperta (" + _scene_name() + ")")
                                        _finish()
                                        return
                                _joy(0, true)  # P1 jump
                                phase = 7
                                st = 0.0
                7:
                        if st > 0.2:
                                _joy(0, false)
                                phase = 8
                                st = 0.0
                8:
                        if st > 0.3:
                                _joy(2, true)  # P1 shoot -> switch in-place a P2
                                phase = 9
                                st = 0.0
                9:
                        if st > 0.2:
                                _joy(2, false)
                                phase = 10
                                st = 0.0
                10:
                        # Dopo P1: ConfigJoy deve essere passata a PLAYER 2
                        # (stessa scena, nessuna partita avviata).
                        if st > 0.5:
                                if _scene_name() != "ConfigJoy.tscn":
                                        _fail("B: dopo P1 il gioco e' PARTITO (" + _scene_name() + ")")
                                        _finish()
                                        return
                                if GameManager.config_joy_player != 2:
                                        _fail("B: non e' passato a configurare P2 ("
                                                        + str(GameManager.config_joy_player) + ")")
                                else:
                                        print("[TEST] OK B1: P1 configurato -> switch a PLAYER 2 "
                                                        + "(in-place, nessuna partita)")
                                _joy(1, true)  # P2 jump (bottone diverso)
                                phase = 11
                                st = 0.0
                11:
                        if st > 0.2:
                                _joy(1, false)
                                phase = 12
                                st = 0.0
                12:
                        if st > 0.3:
                                _joy(3, true)  # P2 shoot
                                phase = 13
                                st = 0.0
                13:
                        if st > 0.2:
                                _joy(3, false)
                                phase = 14
                                st = 0.0
                14:
                        # Dopo P2: si torna al menu (2P).
                        if st > 0.8:
                                if _scene_name() != "MainMenu.tscn":
                                        _fail("B: dopo P2 il gioco e' PARTITO (" + _scene_name() + ")")
                                elif not menu_visible_and_options():
                                        _fail("B: menu riaperto senza sottomenu OPTIONS attivo")
                                else:
                                        print("[TEST] OK B: 2P configurato (P1+P2) -> MENU "
                                                        + "PRINCIPALE (sottomenu OPTIONS)")
                                # --- C: flusso START GAME non regresso ---
                                GameManager.num_players = 1
                                GameManager.config_joy_player = 1
                                GameManager.config_joy_step = 0
                                # Simula START GAME: il flag from_options si azzera.
                                menu = get_tree().current_scene as Control
                                menu._on_start_requested(1, 0, false,
                                                C.CharacterType.HERO_M, C.CharacterType.HERO_F)
                                phase = 15
                                st = 0.0
                15:
                        # START GAME senza joystick collegati -> SelectPlayer
                        # (comportamento pre-esistente, nessuna regressione).
                        if st > 0.8:
                                if GameManager.config_joy_from_options:
                                        _fail("C: START GAME non ha azzerato from_options")
                                elif _scene_name() != "SelectPlayer.tscn":
                                        _fail("C: START GAME non porta a SelectPlayer ("
                                                        + _scene_name() + ")")
                                else:
                                        print("[TEST] OK C: START GAME -> SelectPlayer "
                                                        + "(flusso legacy intatto)")
                                # ConfigJoy forzata con from_options=false: a fine
                                # configurazione deve andare a SelectPlayer.
                                GameManager.config_joy_from_options = false
                                GameManager.config_joy_player = 1
                                GameManager.config_joy_step = 0
                                GameManager.go_to_config_joy()
                                phase = 16
                                st = 0.0
                16:
                        if st > 0.8:
                                if _scene_name() != "ConfigJoy.tscn":
                                        _fail("C: ConfigJoy legacy non aperta (" + _scene_name() + ")")
                                        _finish()
                                        return
                                _joy(0, true)
                                phase = 17
                                st = 0.0
                17:
                        if st > 0.2:
                                _joy(0, false)
                                phase = 18
                                st = 0.0
                18:
                        if st > 0.3:
                                _joy(2, true)
                                phase = 19
                                st = 0.0
                19:
                        if st > 0.2:
                                _joy(2, false)
                                phase = 20
                                st = 0.0
                20:
                        # Flusso legacy: dopo la configurazione si va a SelectPlayer.
                        if st > 0.8:
                                if _scene_name() != "SelectPlayer.tscn":
                                        _fail("C: flusso legacy rotto: dopo ConfigJoy si va a "
                                                        + _scene_name() + " invece di SelectPlayer")
                                else:
                                        print("[TEST] OK C: ConfigJoy legacy -> SelectPlayer "
                                                        + "(START GAME non toccato dal fix)")
                                _finish()


func menu_visible_and_options() -> bool:
        var m: Control = get_tree().current_scene as Control
        if m == null or _scene_name() != "MainMenu.tscn":
                return false
        return m._in_options and m._menu_item_index == 1


func _finish() -> void:
        if failures.is_empty():
                print("[TEST] ==== TEST CONFIGJOY->MENU SUPERATO (runtime Godot) ====")
                get_tree().quit(0)
        else:
                print("[TEST] ==== FALLITI ", failures.size(), " test ====")
                for f in failures:
                        print("[TEST FAIL] ", f)
                get_tree().quit(1)
