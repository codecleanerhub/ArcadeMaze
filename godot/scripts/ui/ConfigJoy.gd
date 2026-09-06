extends Control

# ConfigJoy.gd - Configurazione joystick (2 step per player)
# Porting di Game.cpp STATE_CONFIG_JOY / STATE_CONFIG_JOY_2
#
# Background: uses the same AI-generated crypt/ruderi image as SelectPlayer
# (bg_select_player.png) for visual consistency across the menu chain. The
# procedural crypt (EnvironmentArt.draw_crypt_background) is kept as a
# fallback if the AI image is missing. A subtle dark overlay ensures the
# label text stays readable on top of the busy art.

signal config_finished

var step: int = 0  # 0 = jump button, 1 = shoot button
var player_num: int = 1
var wait_for_release: bool = false
var _anim_time: float = 0.0  # for animated background elements (torches, fog)
# AI-generated background texture (loaded once). Same image as SelectPlayer
# so the menu chain (MainMenu → ConfigJoy → SelectPlayer) feels cohesive.
var _bg_texture: Texture2D = null

@onready var step_label: Label = $StepLabel
@onready var player_label: Label = $PlayerLabel
@onready var hint_label: Label = $HintLabel

func _ready() -> void:
        # Read which player we're configuring from GameManager (set by MainMenu).
        if GameManager:
                player_num = GameManager.config_joy_player
                step = 0 if GameManager.config_joy_step == 0 else 1
        player_label.text = "PLAYER " + str(player_num)
        _update_step()
        # Preload the AI-generated crypt/ruderi background (same as SelectPlayer).
        var bg_path := "res://assets/backgrounds/bg_select_player.png"
        if ResourceLoader.exists(bg_path):
                _bg_texture = load(bg_path) as Texture2D
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
        # Update the hint label to remind the user they can cancel with ESC.
        if hint_label:
                hint_label.text = "ESC TO CANCEL  •  STEP %d OF 2" % (step + 1)

func _process(delta: float) -> void:
        _anim_time += delta
        # Redraw the animated background each frame (torches flicker, fog drifts).
        queue_redraw()
        # ESC: torna al menu
        if Input.is_action_just_pressed("ui_cancel"):
                config_finished.emit()
                return
        
        # FIX (configurati tasti sbagliati): il polling diretto con
        # Input.is_joy_button_pressed parte sempre da btn=0 e rileva il primo
        # tasto premuto. Se l'utente tiene premuto X (es. button 2) mentre
        # preme Y (button 3) per il secondo step, il loop rileva X PRIMA di Y
        # perché btn=2 < btn=3. Inoltre alcuni controller inviano eventi
        # "ghost" su button 0 o 1 quando altri vengono premuti.
        # Usiamo _unhandled_input con InputEventJoypadButton che fornisce il
        # button_index ESATTO dell'evento appena verificatosi, non un polling.
        # La logica wait_for_release è gestita qui: aspettiamo che TUTTI i
        # pulsanti siano rilasciati prima di accettare un nuovo evento.
        if wait_for_release:
                # Aspetta che tutti i pulsanti siano rilasciati
                var any_pressed := false
                for jid in range(8):
                        if Input.is_joy_known(jid):
                                for btn in range(128):
                                        if Input.is_joy_button_pressed(jid, btn):
                                                any_pressed = true
                                                break
                        if any_pressed:
                                break
                if not any_pressed:
                        wait_for_release = false
                return


# Input event handler: riceve l'evento del joystick ESATTO appena premuto,
# non un polling. Questo evita il bug dove il tasto sbagliato viene
# registrato perché il polling parte da btn=0.
func _unhandled_input(event: InputEvent) -> void:
        if not (event is InputEventJoypadButton):
                return
        # FIX CRASH: InputEventJoypadButton non ha la property 'echo'
        # (solo InputEventKey ce l'ha). Usa event.pressed per il check.
        if not event.pressed:
                return
        # Se siamo in attesa di release, ignora qualsiasi pressione.
        if wait_for_release:
                return
        var jid: int = event.device
        var btn: int = event.button_index
        # Salta i tasti "virtuali" che alcuni controller inviano (es. il
        # guide button o combo keys che non dovrebbero essere mappati).
        # Permettiamo btn 0..15 (standard Xbox/PS layout: A/B/X/Y/LB/RB/
        # Back/Start/LStick/RStick/DPad×4/Touchpad).
        if btn < 0 or btn > 15:
                return
        AudioManager.play_sound(AudioManager.SoundType.MENU_CONFIRM)
        match step:
                0:
                        # Jump button
                        if player_num == 1:
                                ConfigManager.config.joy_jump = btn
                                print("[ConfigJoy] P1 jump button = ", btn)
                        else:
                                ConfigManager.config.joy2_jump = btn
                                ConfigManager.config.joy2_id = jid
                                print("[ConfigJoy] P2 jump button = ", btn, " on joy_id ", jid)
                        step = 1
                        _update_step()
                        wait_for_release = true
                1:
                        # Shoot button — assicuriamoci che sia diverso da jump
                        # (lo stesso tasto non può essere sia jump che shoot).
                        var jump_btn: int = ConfigManager.config.joy_jump if player_num == 1 else ConfigManager.config.joy2_jump
                        if btn == jump_btn:
                                # Stesso tasto: ignora e aspetta un altro
                                print("[ConfigJoy] same button as jump, ignoring")
                                return
                        if player_num == 1:
                                ConfigManager.config.joy_shoot = btn
                                print("[ConfigJoy] P1 shoot button = ", btn)
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
                                print("[ConfigJoy] P2 shoot button = ", btn)
                                ConfigManager.save_config()
                                config_finished.emit()
                        wait_for_release = true
        get_viewport().set_input_as_handled()


# Draw the background. Uses the same AI crypt/ruderi image as SelectPlayer
# for visual consistency; falls back to the procedural crypt if the AI image
# is missing. A subtle dark overlay keeps the label text legible.
func _draw() -> void:
        var vp_size: Vector2 = size
        # Defensive fallback: if the Control root hasn't resolved its anchors
        # yet (size == 0), use the viewport size directly so the background
        # is always drawn covering the full screen.
        if vp_size.x < 1.0 or vp_size.y < 1.0:
                vp_size = get_viewport_rect().size
        if _bg_texture != null:
                # Cover-fit math (same as SelectPlayer/WinScreen/LoseScreen):
                # scale = max(vp/tex) so the entire viewport is filled with no
                # black bars, and center the draw rect.
                var tex_size: Vector2 = _bg_texture.get_size()
                var scale_x: float = vp_size.x / tex_size.x
                var scale_y: float = vp_size.y / tex_size.y
                var bg_scale: float = maxf(scale_x, scale_y)
                var draw_size: Vector2 = tex_size * bg_scale
                var draw_pos: Vector2 = (vp_size - draw_size) * 0.5
                draw_texture_rect(_bg_texture, Rect2(draw_pos, draw_size), false)
        elif EnvironmentArt:
                # Fallback: procedural crypt background (if AI image missing)
                EnvironmentArt.draw_crypt_background(self, vp_size, _anim_time)
        # Subtle dark overlay (25%) so the labels stand out without crushing
        # the rich crypt detail. Previous value was 0.45 which made the
        # already-dark gradient nearly invisible.
        draw_rect(Rect2(0, 0, vp_size.x, vp_size.y), Color(0, 0, 0, 0.25), true)
