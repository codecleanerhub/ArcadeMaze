extends Control

# ConfigJoy.gd - Configurazione joystick (2 step per player)
# Porting di Game.cpp STATE_CONFIG_JOY / STATE_CONFIG_JOY_2

signal config_finished

var step: int = 0  # 0 = jump button, 1 = shoot button
var player_num: int = 1
var wait_for_release: bool = false

@onready var step_label: Label = $StepLabel
@onready var player_label: Label = $PlayerLabel

func _ready() -> void:
        # Read which player we're configuring from GameManager (set by MainMenu).
        if GameManager:
                player_num = GameManager.config_joy_player
                step = 0 if GameManager.config_joy_step == 0 else 1
        player_label.text = "PLAYER " + str(player_num)
        _update_step()
        # Self-wire: when config finishes, go back to menu.
        config_finished.connect(_on_config_finished)

func _on_config_finished() -> void:
        # After joystick config, go to character selection (not back to menu)
        if GameManager:
                if GameManager.config_joy_player == 1 and GameManager.num_players == 2:
                        # P2 also needs config
                        GameManager.config_joy_player = 2
                        GameManager.config_joy_step = 0
                        # Reload this scene for P2
                        get_tree().reload_current_scene()
                else:
                        # Both configured (or 1P): go to select player
                        GameManager.go_to_select_player()

func _update_step() -> void:
        match step:
                0: step_label.text = "PRESS JUMP BUTTON"
                1: step_label.text = "PRESS SHOOT BUTTON"

func _process(_delta: float) -> void:
        # ESC: torna al menu
        if Input.is_action_just_pressed("ui_cancel"):
                config_finished.emit()
                return
        
        # Scansiona tutti i pulsanti di tutti i joystick
        if wait_for_release:
                # Aspetta che tutti i pulsanti siano rilasciati
                var any_pressed := false
                for jid in range(8):
                        if Input.is_joy_known(jid):
                                for btn in range(min(128, 128)):
                                        if Input.is_joy_button_pressed(jid, btn):
                                                any_pressed = true
                                                break
                        if any_pressed:
                                break
                if not any_pressed:
                        wait_for_release = false
                return
        
        # Cerca pulsante premuto
        for jid in range(8):
                if not Input.is_joy_known(jid):
                        continue
                var max_btns: int = 128
                if max_btns > 128:
                        max_btns = 128
                for btn in range(max_btns):
                        if Input.is_joy_button_pressed(jid, btn):
                                AudioManager.play_sound(AudioManager.SoundType.MENU_CONFIRM)
                                match step:
                                        0:
                                                # Salva jump button
                                                if player_num == 1:
                                                        ConfigManager.config.joy_jump = btn
                                                else:
                                                        ConfigManager.config.joy2_jump = btn
                                                        ConfigManager.config.joy2_id = jid
                                                step = 1
                                                _update_step()
                                                wait_for_release = true
                                        1:
                                                # Salva shoot button
                                                if player_num == 1:
                                                        ConfigManager.config.joy_shoot = btn
                                                        ConfigManager.save_config()
                                                        if GameManager.num_players == 2:
                                                                player_num = 2
                                                                step = 0
                                                                player_label.text = "PLAYER 2"
                                                                _update_step()
                                                                wait_for_release = true
                                                        else:
                                                                config_finished.emit()
                                                else:
                                                        ConfigManager.config.joy2_shoot = btn
                                                        ConfigManager.save_config()
                                                        config_finished.emit()
                                                wait_for_release = true
                                return
