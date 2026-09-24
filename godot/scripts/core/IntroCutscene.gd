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
@onready var timer: Timer = $Timer
@onready var text_overlay: Control = $TextOverlay

# Colore pietra per outline
const STONE_COLOR: Color = Color(0.35, 0.28, 0.18, 0.9)
const GOLD_COLOR: Color = Color(0.85, 0.72, 0.25, 1.0)
const STONE_DARK: Color = Color(0.15, 0.10, 0.05, 0.8)

func _ready() -> void:
        print("[IntroCutscene] VERSION: 35ab8b3 - loading intro images...")
        for i in range(1, 5):
                var path := "res://assets/cutscene/intro_" + str(i) + ".png"
                var tex = null
                var abs_path: String = ProjectSettings.globalize_path(path)
                if FileAccess.file_exists(abs_path):
                        var img := Image.new()
                        if img.load(abs_path) == OK:
                                tex = ImageTexture.create_from_image(img)
                                print("[IntroCutscene] Loaded: %s" % path)
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
        text_overlay.controller = self

func _show_frame(idx: int) -> void:
        if idx < 0 or idx >= _images.size():
                _finish()
                return
        _current_frame = idx
        if _images[idx] != null:
                image_display.texture = _images[idx]
        _frame_timer = 0.0
        timer.start(180.0)
        text_overlay.queue_redraw()

func _on_timer_timeout() -> void:
        if _current_frame < _images.size() - 1:
                _show_frame(_current_frame + 1)
        else:
                _finish()

func _finish() -> void:
        timer.stop()
        intro_finished.emit()
        if GameManager:
                GameManager.current_level = 1
                GameManager.go_to_maze()
        else:
                var err := get_tree().change_scene_to_file("res://scenes/MainGame.tscn")
                if err != OK:
                        push_error("Errore nel caricamento di MainGame.tscn")

func _process(delta: float) -> void:
        var skip_pressed: bool = false
        skip_pressed = skip_pressed or Input.is_action_just_pressed("confirm")
        skip_pressed = skip_pressed or Input.is_action_just_pressed("jump")
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
                        pass
                else:
                        _skip_key_held = true
                        if _current_frame < _images.size() - 1:
                                _show_frame(_current_frame + 1)
                        else:
                                _finish()
        else:
                _skip_key_held = false

        if Input.is_action_just_pressed("ui_cancel"):
                _finish()

        _frame_timer += delta
        text_overlay.queue_redraw()

# Custom draw: stile geroglifici scolpiti su pietra
# Chiamato da TextOverlay._draw() che è SOPRA l'immagine.
func draw_overlay(ci: CanvasItem) -> void:
        var font := ci.get_theme_default_font()
        if font == null:
                font = ThemeDB.fallback_font
        if font == null:
                return

        var vp_size: Vector2 = ci.get_viewport_rect().size

        # --- Pannello di pietra per il testo (sotto, semi-trasparente) ---
        var panel_y: float = vp_size.y * 0.72
        var panel_h: float = vp_size.y * 0.25
        var panel_x: float = vp_size.x * 0.08
        var panel_w: float = vp_size.x * 0.84
        # Sfondo pietra scuro
        ci.draw_rect(Rect2(panel_x, panel_y, panel_w, panel_h),
                Color(0.12, 0.08, 0.04, 0.88), true)
        # Bordo pietra dorato
        ci.draw_rect(Rect2(panel_x, panel_y, panel_w, panel_h),
                Color(0.6, 0.5, 0.2, 0.8), false, 3.0)
        # Bordo interno
        ci.draw_rect(Rect2(panel_x + 6, panel_y + 6, panel_w - 12, panel_h - 12),
                Color(0.4, 0.3, 0.1, 0.5), false, 1.0)

        # --- Testo caption (scolpito su pietra) ---
        var caption_text: String = CAPTIONS[_current_frame] if _current_frame < CAPTIONS.size() else ""
        var font_size: int = 24
        var text_y: float = panel_y + 25
        var lines: PackedStringArray = caption_text.split("\n")
        for line_idx in lines.size():
                var line: String = lines[line_idx]
                var line_w: float = font.get_string_size(line, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x
                var line_x: float = (vp_size.x - line_w) * 0.5
                var ly: float = text_y + float(line_idx) * (font_size + 8) + font_size
                # Ombra profonda (effetto incisione)
                for off in [Vector2(-2, 2), Vector2(2, 2), Vector2(0, 3)]:
                        ci.draw_string(font, Vector2(line_x + off.x, ly + off.y), line,
                                HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, STONE_DARK)
                # Outline pietra
                for off in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
                        ci.draw_string(font, Vector2(line_x + off.x, ly + off.y), line,
                                HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, STONE_COLOR)
                # Fill dorato (testo principale)
                ci.draw_string(font, Vector2(line_x, ly), line,
                        HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, GOLD_COLOR)

        # --- Progress indicator (in alto a sinistra, scolpito) ---
        var prog_text: String = str(_current_frame + 1) + " / 4"
        var prog_size: int = 22
        var prog_y: float = 35.0
        ci.draw_rect(Rect2(15, 15, 90, 35), Color(0.12, 0.08, 0.04, 0.88), true)
        ci.draw_rect(Rect2(15, 15, 90, 35), Color(0.6, 0.5, 0.2, 0.7), false, 2.0)
        for off in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
                ci.draw_string(font, Vector2(28 + off.x, prog_y + off.y), prog_text,
                        HORIZONTAL_ALIGNMENT_LEFT, -1, prog_size, STONE_COLOR)
        ci.draw_string(font, Vector2(28, prog_y), prog_text,
                HORIZONTAL_ALIGNMENT_LEFT, -1, prog_size, GOLD_COLOR)

        # --- Skip hint (in basso a destra, pulsante) ---
        var skip_alpha: float = 0.5 + sin(_frame_timer * 3.0) * 0.3
        var skip_text: String = "PRESS FIRE TO SKIP"
        var skip_size: int = 20
        var skip_w: float = font.get_string_size(skip_text, HORIZONTAL_ALIGNMENT_RIGHT, -1, skip_size).x
        var skip_x: float = vp_size.x - skip_w - 35
        var skip_y: float = vp_size.y - 20
        for off in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
                ci.draw_string(font, Vector2(skip_x + off.x, skip_y + off.y), skip_text,
                        HORIZONTAL_ALIGNMENT_LEFT, -1, skip_size,
                        Color(STONE_COLOR.r, STONE_COLOR.g, STONE_COLOR.b, skip_alpha))
        ci.draw_string(font, Vector2(skip_x, skip_y), skip_text,
                HORIZONTAL_ALIGNMENT_LEFT, -1, skip_size,
                Color(GOLD_COLOR.r, GOLD_COLOR.g, GOLD_COLOR.b, skip_alpha))
