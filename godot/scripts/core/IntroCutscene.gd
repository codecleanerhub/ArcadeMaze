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
        print("[IntroCutscene] VERSION: 48eed09 - loading intro images...")
        # Carica le 4 immagini intro
        for i in range(1, 5):
                var path := "res://assets/cutscene/intro_" + str(i) + ".png"
                print("[IntroCutscene] Loading %s exists=%s" % [path, ResourceLoader.exists(path)])
                if ResourceLoader.exists(path):
                        var tex = load(path)
                        if tex != null:
                                _images.append(tex)
                        else:
                                print("[IntroCutscene] WARN: load returned null for %s" % path)
                                _images.append(null)
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
        timer.start(8.0)

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
        if Input.is_action_just_pressed("confirm") or Input.is_action_just_pressed("jump"):
                if _current_frame < _images.size() - 1:
                        _show_frame(_current_frame + 1)
                else:
                        _finish()
        
        # ESC: salta tutto
        if Input.is_action_just_pressed("ui_cancel"):
                _finish()
        
        # Fade animazione skip_hint
        _frame_timer += delta
        skip_hint.modulate.a = 0.5 + sin(_frame_timer * 3.0) * 0.3
