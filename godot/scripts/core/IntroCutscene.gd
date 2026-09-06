extends Control

# IntroCutscene.gd - Cutscene a fumetti (4 immagini, 8s ciascuna)
# Porting di Game.cpp startIntro/updateIntro/drawIntro

signal intro_finished

const CAPTIONS: Array[String] = [
        "It all began with the search for an island that appears on no map.\nWe chose the course. It was the storm that chose us.\nThe island welcomed us with cliffs black and hard as steel,\nelements unseen, and whispers from below.",
        "The ruins were not dead. They were waiting.\nEvery corridor breathed. Every shadow had teeth.\nWe lit our torches and pressed deeper, driven by gold and glory.\nThe maze would test our worth.",
        "Creatures of nightmare roamed these halls.\nSkeletons of ancient warriors, demons of fire and shadow,\nbeasts twisted by centuries of darkness.\nWe fought. We bled. We pressed on.",
        "At the heart of the island, the Treasure awaited.\nBut it was guarded by the oldest evil.\nA dragon of bone and fire, the last sentinel of a forgotten age.\nThis is where our legend begins."
]

var _images: Array[Texture2D] = []
var _current_frame: int = 0
var _frame_timer: float = 0.0
var _skip_key_held: bool = false

@onready var image_display: TextureRect = $ImageDisplay
@onready var caption: Label = $Caption
@onready var skip_hint: Label = $SkipHint
@onready var progress: Label = $Progress
@onready var timer: Timer = $Timer

func _ready() -> void:
        print("[IntroCutscene] VERSION: 35ab8b3 - loading intro images...")
        # Carica le 4 immagini intro usando Image.load() (piu' robusto di load())
        for i in range(1, 5):
                var path := "res://assets/cutscene/intro_" + str(i) + ".png"
                # Try ResourceLoader first, then Image.load as fallback
                var tex = null
                if ResourceLoader.exists(path):
                        tex = load(path)
                if tex == null:
                        # Fallback: load raw image and convert to texture
                        var img := Image.new()
                        var err := img.load(path)
                        if err == OK:
                                tex = ImageTexture.create_from_image(img)
                                print("[IntroCutscene] Loaded via Image.load: %s" % path)
                        else:
                                print("[IntroCutscene] Image.load failed for %s err=%d" % [path, err])
                if tex != null:
                        _images.append(tex)
                else:
                        _images.append(null)
        
        if _images.is_empty() or _images[0] == null:
                print("[IntroCutscene] No images found, skipping to game")
                _finish()
                return
        
        _show_frame(0)
        timer.timeout.connect(_on_timer_timeout)
        skip_hint.visible = true

func _show_frame(idx: int) -> void:
        if idx < 0 or idx >= _images.size():
                _finish()
                return
        
        _current_frame = idx
        if _images[idx] != null:
                image_display.texture = _images[idx]
        caption.text = CAPTIONS[idx] if idx < CAPTIONS.size() else ""
        progress.text = str(idx + 1) + "/4"
        _frame_timer = 0.0
        timer.start(180.0)

func _on_timer_timeout() -> void:
        if _current_frame < _images.size() - 1:
                _show_frame(_current_frame + 1)
        else:
                _finish()

func _finish() -> void:
        timer.stop()
        intro_finished.emit()
        # Transition to the first maze level via GameManager.
        if GameManager:
                GameManager.current_level = 1
                GameManager.go_to_maze()
        else:
                var err := get_tree().change_scene_to_file("res://scenes/MainGame.tscn")
                if err != OK:
                        push_error("Errore nel caricamento di MainGame.tscn")

func _process(delta: float) -> void:
        # Pulsante skip: Enter o qualsiasi tasto di azione
        # FIX: oltre all'azione "confirm"/"jump" standard (che include
        # JOY_BUTTON_A/B/START), controlliamo anche il tasto di fuoco e di
        # salto CONFIGURATO dell'utente (ConfigManager.joy_shoot/joy_jump).
        # Se l'utente ha configurato un tasto custom diverso da A/B/Start
        # (es. X o Y), l'action map non lo triggererebbe.
        var skip_pressed: bool = false
        skip_pressed = skip_pressed or Input.is_action_just_pressed("confirm")
        skip_pressed = skip_pressed or Input.is_action_just_pressed("jump")
        # Check configured joystick buttons directly.
        if ConfigManager and not skip_pressed:
                var joy_pads: Array = Input.get_connected_joypads()
                if joy_pads.size() > 0:
                        var jid: int = joy_pads[0]
                        var joy_shoot_btn: int = ConfigManager.joy_shoot()
                        var joy_jump_btn: int = ConfigManager.joy_jump()
                        if joy_shoot_btn >= 0 and Input.is_joy_button_pressed(jid, joy_shoot_btn):
                                skip_pressed = true
                        if joy_jump_btn >= 0 and Input.is_joy_button_pressed(jid, joy_jump_btn):
                                skip_pressed = true
        if skip_pressed:
                if _skip_key_held:
                        pass  # already pressed last frame, don't re-trigger
                else:
                        _skip_key_held = true
                        if _current_frame < _images.size() - 1:
                                _show_frame(_current_frame + 1)
                        else:
                                _finish()
        else:
                _skip_key_held = false
        
        # ESC: salta tutto
        if Input.is_action_just_pressed("ui_cancel"):
                _finish()
        
        # Fade animazione skip_hint
        _frame_timer += delta
        skip_hint.modulate.a = 0.5 + sin(_frame_timer * 3.0) * 0.3
