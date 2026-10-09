## LoseScreen.gd
## ============================================================
## Porting of Game.cpp STATE_LOSE.
## Shows the game over screen with bg_gameover.jpg background.
##
## FIX (Hall of Fame): se il punteggio finale merita un posto in classifica,
## dopo un attimo appare la TASTIERA ALFANUMERICA VIRTUALE per inserire il
## nome (movimenti direzionali + tasto fuoco; CANC cancella; OK conferma).
## Dopo la conferma il punteggio viene salvato e il gioco mostra la
## schermata HALL OF FAME con la nuova voce evidenziata.
## ============================================================
extends Control

signal back_to_menu_requested()

@export var color_title:    Color = Color(0.863, 0.157, 0.157)
@export var color_subtitle: Color = Color(0.784, 0.784, 0.784)
@export var color_hint:     Color = Color(0.588, 0.588, 0.588)

var _bg_texture: Texture2D = null
var _time: float = 0.0
var _finished: bool = false
# FIX (Hall of Fame): tastiera virtuale di inserimento nome
var _keyboard: Control = null
var _keyboard_timer: float = 0.0
const KEYBOARD_DELAY: float = 1.6  # secondi prima che appaia la tastiera
var _keyboard_shown: bool = false


func _ready() -> void:
        set_anchors_preset(Control.PRESET_FULL_RECT)
        mouse_filter = Control.MOUSE_FILTER_STOP
        focus_mode = Control.FOCUS_ALL
        _finished = false
        var _abs := ProjectSettings.globalize_path("res://assets/backgrounds/bg_gameover.jpg")
        if FileAccess.file_exists(_abs):
                var _img := Image.new()
                if _img.load(_abs) == OK:
                        _bg_texture = ImageTexture.create_from_image(_img)
        if AudioManager:
                AudioManager.stop_music()


func _process(delta: float) -> void:
        _time += delta
        # FIX (Hall of Fame): dopo il delay, se il punteggio merita la
        # classifica, mostra la tastiera di inserimento nome.
        if not _keyboard_shown and not _finished:
                _keyboard_timer += delta
                if _keyboard_timer >= KEYBOARD_DELAY:
                        _maybe_show_keyboard()
        queue_redraw()


# Crea la tastiera virtuale se il punteggio finale è da Hall of Fame.
func _maybe_show_keyboard() -> void:
        _keyboard_shown = true
        var score: int = 0
        var level: int = 1
        if GameManager:
                score = GameManager.final_score
                level = GameManager.final_level
        if not HallOfFameData.qualifies(score):
                return  # punteggio troppo basso: niente inserimento nome
        var kb_script := load("res://scripts/ui/NameEntryKeyboard.gd")
        _keyboard = Control.new()
        _keyboard.set_script(kb_script)
        _keyboard.set_anchors_preset(Control.PRESET_FULL_RECT)
        _keyboard.display_score = score
        _keyboard.display_level = level
        _keyboard.save_on_confirm = true
        add_child(_keyboard)
        _keyboard.entry_confirmed.connect(_on_name_confirmed)


# Chiamato quando il player conferma il nome: salva (già fatto dalla
# tastiera) e porta alla schermata Hall of Fame con la voce evidenziata.
func _on_name_confirmed(player_name: String) -> void:
        if _finished:
                return
        _finished = true
        if GameManager:
                # Trova la posizione della nuova voce per evidenziarla
                var entries := HallOfFameData.load_entries()
                var pos: int = -1
                for i in entries.size():
                        if str(entries[i]["name"]) == player_name \
                                        and int(entries[i]["score"]) == GameManager.final_score:
                                pos = i
                                break
                GameManager.hof_highlight_index = pos
                GameManager.go_to_hall_of_fame()


func _unhandled_input(event: InputEvent) -> void:
        if _finished:
                return
        # FIX (Hall of Fame): mentre la tastiera è attiva, questa schermata
        # non consuma input (li gestisce la tastiera).
        if _keyboard != null and is_instance_valid(_keyboard):
                return
        if event is InputEventKey and event.pressed and not event.echo:
                if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
                        # FIX (possibilità di salvare il record): se il punteggio
                        # merita la classifica, ENTER/SPACE NON salta il salvataggio
                        # ma apre SUBITO la tastiera di inserimento nome (di norma
                        # appare da sola dopo 1.6s). Solo se il punteggio NON
                        # qualifica, ENTER porta al menu.
                        if not _keyboard_shown:
                                var sc: int = 0
                                if GameManager:
                                        sc = GameManager.final_score
                                if sc > 0 and HallOfFameData.qualifies(sc):
                                        _maybe_show_keyboard()
                                        return
                        _finish()
                elif event.keycode == KEY_ESCAPE:
                        _finish()
        elif event is InputEventJoypadButton and event.pressed:
                if event.button_index == JOY_BUTTON_A:
                        if not _keyboard_shown:
                                var sc2: int = 0
                                if GameManager:
                                        sc2 = GameManager.final_score
                                if sc2 > 0 and HallOfFameData.qualifies(sc2):
                                        _maybe_show_keyboard()
                                        return
                        _finish()


func _finish() -> void:
        _finished = true
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.MENU_CONFIRM)
        back_to_menu_requested.emit()
        if GameManager:
                GameManager.go_to_menu()


func _draw() -> void:
        # Background
        if _bg_texture:
                var vp_size: Vector2 = size
                var tex_size: Vector2 = _bg_texture.get_size()
                var scale_val: float = max(vp_size.x / tex_size.x, vp_size.y / tex_size.y)
                var draw_size: Vector2 = tex_size * scale_val
                var draw_pos: Vector2 = (vp_size - draw_size) / 2.0
                draw_texture_rect(_bg_texture, Rect2(draw_pos, draw_size), false)
        else:
                draw_rect(Rect2(0, 0, size.x, size.y), Color(0.02, 0.0, 0.0, 1.0), true)

        # Dark overlay for readability
        draw_rect(Rect2(0, 0, size.x, size.y), Color(0, 0, 0, 0.4), true)

        var font := get_theme_default_font()
        var cx: float = size.x / 2.0

        # Title "GAME OVER" (subtle pulse)
        var pulse: float = 1.0 + 0.03 * sin(_time * 2.0)
        var title_size: int = int(80 * pulse)
        draw_string(font, Vector2(cx - 350, 120), "GAME OVER",
                HORIZONTAL_ALIGNMENT_CENTER, 700, title_size, color_title)

        # Subtitle
        draw_string(font, Vector2(cx - 300, 240),
                "The maze has claimed another soul...",
                HORIZONTAL_ALIGNMENT_CENTER, 600, 28, color_subtitle)

        # FIX (Hall of Fame): punteggio finale raggiunto
        var score: int = 0
        var level: int = 1
        if GameManager:
                score = GameManager.final_score
                level = GameManager.final_level
        draw_string(font, Vector2(cx - 300, 300),
                "FINAL SCORE: %d    LEVEL: %d" % [score, level],
                HORIZONTAL_ALIGNMENT_CENTER, 600, 30, Color(1.0, 0.84, 0.3))

        # Hint (blinking) — cambia se la tastiera sta per apparire
        var hint_alpha: float = 0.5 + 0.5 * sin(_time * 2.0)
        var hint_text: String = "PRESS ENTER TO RETURN TO MENU"
        if not _keyboard_shown and HallOfFameData.qualifies(score):
                hint_text = "NEW HIGH SCORE! PREPARE TO ENTER YOUR NAME..."
        elif _keyboard_shown and _keyboard != null and is_instance_valid(_keyboard):
                hint_text = ""
        draw_string(font, Vector2(cx - 300, size.y - 80),
                hint_text,
                HORIZONTAL_ALIGNMENT_CENTER, 600, 24,
                Color(color_hint.r, color_hint.g, color_hint.b, hint_alpha))
