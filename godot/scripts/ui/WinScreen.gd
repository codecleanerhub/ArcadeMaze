## WinScreen.gd
## ============================================================
## Porting of Game.cpp STATE_WIN_STORY.
## Shows the victory screen with bg_win.jpg background and
## animated fireworks. "PRESS ENTER TO RETURN TO MENU".
## ============================================================
extends Control

signal back_to_menu_requested()

@export var color_title:    Color = Color(1.000, 0.843, 0.000)
@export var color_subtitle: Color = Color(0.961, 0.922, 0.784)
@export var color_hint:     Color = Color(0.745, 0.745, 0.745)

var _bg_texture: Texture2D = null
var _time: float = 0.0
var _fireworks: Array = []
var _finished: bool = false
# FIX (Hall of Fame): tastiera virtuale di inserimento nome
var _keyboard: Control = null
var _keyboard_timer: float = 0.0
const KEYBOARD_DELAY: float = 2.2  # secondi di fuochi d'artificio prima della tastiera
var _keyboard_shown: bool = false
# FIX (Hall of Fame 2P): coda dei punteggi da salvare. In 2P ogni player
# salva il PROPRIO punteggio: prima la tastiera per P1, poi (se qualifica)
# quella per P2, infine la Hall of Fame con l'ultima voce evidenziata.
var _hof_queue: Array = []  # [{"label": "PLAYER 1", "score": int}, ...]
var _hof_level: int = 1


func _ready() -> void:
        set_anchors_preset(Control.PRESET_FULL_RECT)
        mouse_filter = Control.MOUSE_FILTER_STOP
        focus_mode = Control.FOCUS_ALL
        _finished = false
        var _abs := ProjectSettings.globalize_path("res://assets/backgrounds/bg_win.jpg")
        if FileAccess.file_exists(_abs):
                var _img := Image.new()
                if _img.load(_abs) == OK:
                        _bg_texture = ImageTexture.create_from_image(_img)
        if AudioManager:
                AudioManager.stop_music()
                if AudioManager.music_enabled:
                        AudioManager.play_epic_music(7)  # victory track


func _process(delta: float) -> void:
        _time += delta
        # Spawn fireworks periodically
        if randf() < delta * 2.0:  # ~2 per second
                _spawn_firework()
        # Update fireworks
        var alive: Array = []
        for fw in _fireworks:
                fw["pos"] += fw.get("vel", Vector2.ZERO)
                fw["vel"].y += 15.0 * delta  # gravity
                fw["life"] -= 1
                if int(fw.get("life", 0)) > 0:
                        alive.append(fw)
        _fireworks = alive
        # FIX (Hall of Fame): dopo il delay, se il punteggio merita la
        # classifica, mostra la tastiera di inserimento nome.
        if not _keyboard_shown and not _finished:
                _keyboard_timer += delta
                if _keyboard_timer >= KEYBOARD_DELAY:
                        _maybe_show_keyboard()
        queue_redraw()


# FIX (Hall of Fame 2P): costruisce la coda dei punteggi qualificanti
# (1P: punteggio unico; 2P: PRIMA P1 poi P2, ognuno salva il proprio).
func _build_hof_queue() -> void:
        _hof_queue.clear()
        if GameManager == null:
                return
        _hof_level = GameManager.final_level
        if GameManager.num_players == 2:
                if HallOfFameData.qualifies(GameManager.final_score_p1):
                        _hof_queue.append({"label": "PLAYER 1",
                                        "score": GameManager.final_score_p1})
                if HallOfFameData.qualifies(GameManager.final_score_p2):
                        _hof_queue.append({"label": "PLAYER 2",
                                        "score": GameManager.final_score_p2})
        else:
                if HallOfFameData.qualifies(GameManager.final_score):
                        _hof_queue.append({"label": "", "score": GameManager.final_score})


# FIX (Hall of Fame 2P): mostra la tastiera per il primo punteggio in coda.
func _maybe_show_keyboard() -> void:
        _keyboard_shown = true
        if _hof_queue.is_empty():
                _build_hof_queue()
        if _hof_queue.is_empty():
                return
        _show_next_keyboard()


func _show_next_keyboard() -> void:
        var entry: Dictionary = _hof_queue[0]
        var kb_script := load("res://scripts/ui/NameEntryKeyboard.gd")
        _keyboard = Control.new()
        _keyboard.set_script(kb_script)
        _keyboard.set_anchors_preset(Control.PRESET_FULL_RECT)
        _keyboard.display_score = int(entry["score"])
        _keyboard.display_level = _hof_level
        _keyboard.display_label = str(entry["label"])
        _keyboard.save_on_confirm = true
        add_child(_keyboard)
        _keyboard.entry_confirmed.connect(_on_name_confirmed)


# FIX (Hall of Fame 2P): nome confermato (la tastiera ha già salvato la
# voce). Se resta il secondo player in coda mostra la sua tastiera, poi
# porta alla Hall of Fame con l'ultima voce evidenziata.
func _on_name_confirmed(player_name: String) -> void:
        if _finished:
                return
        if not _hof_queue.is_empty():
                _hof_queue.pop_front()
        if not _hof_queue.is_empty():
                if _keyboard != null and is_instance_valid(_keyboard):
                        _keyboard.queue_free()
                _keyboard = null
                _show_next_keyboard()
                return
        _finished = true
        if GameManager:
                var entries := HallOfFameData.load_entries()
                var pos: int = -1
                var last_score: int = GameManager.final_score_p2 if \
                                (GameManager.num_players == 2 \
                                and HallOfFameData.qualifies(GameManager.final_score_p2)) \
                                else GameManager.final_score_p1 if (GameManager.num_players == 2 \
                                and HallOfFameData.qualifies(GameManager.final_score_p1)) \
                                else GameManager.final_score
                for i in entries.size():
                        if str(entries[i]["name"]) == player_name \
                                        and int(entries[i]["score"]) == last_score:
                                pos = i
                                break
                if pos < 0:
                        for i in entries.size():
                                if str(entries[i]["name"]) == player_name:
                                        pos = i
                                        break
                GameManager.hof_highlight_index = pos
                GameManager.go_to_hall_of_fame()


func _spawn_firework() -> void:
        var cx: float = randf() * size.x
        var cy: float = randf() * size.y * 0.6 + size.y * 0.1
        var col: Color = Color.from_hsv(randf(), 0.8, 1.0)
        var count: int = 20 + randi() % 15
        for i in count:
                var angle: float = (float(i) / float(count)) * TAU
                var speed: float = 80.0 + randf() * 60.0
                _fireworks.append({
                        "pos": Vector2(cx, cy),
                        "vel": Vector2(cos(angle), sin(angle)) * speed,
                        "life": 40 + randi() % 20,
                        "color": col,
                        "size": 2.0 + randf() * 2.0,
                })


func _unhandled_input(event: InputEvent) -> void:
        if _finished:
                return
        # FIX (Hall of Fame): mentre la tastiera è attiva, questa schermata
        # non consuma input (li gestisce la tastiera).
        if _keyboard != null and is_instance_valid(_keyboard):
                return
        if event is InputEventKey and event.pressed and not event.echo:
                if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
                        # FIX (possibilità di salvare il record): se un punteggio
                        # merita la classifica, ENTER/SPACE NON salta il salvataggio
                        # ma apre SUBITO la tastiera (di norma appare dopo 2.2s
                        # di fuochi d'artificio). Solo se non qualifica, si prosegue.
                        if not _keyboard_shown:
                                _build_hof_queue()
                                if not _hof_queue.is_empty():
                                        _maybe_show_keyboard()
                                        return
                        _finish()
                elif event.keycode == KEY_ESCAPE:
                        _finish()
        elif event is InputEventJoypadButton and event.pressed:
                if event.button_index == JOY_BUTTON_A:
                        if not _keyboard_shown:
                                _build_hof_queue()
                                if not _hof_queue.is_empty():
                                        _maybe_show_keyboard()
                                        return
                        _finish()


func _finish() -> void:
        _finished = true
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.MENU_CONFIRM)
        back_to_menu_requested.emit()
        if GameManager:
                GameManager.go_to_credits()


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
                draw_rect(Rect2(0, 0, size.x, size.y), Color(0.02, 0.04, 0.08, 1.0), true)

        # Fireworks
        for fw in _fireworks:
                var pos: Vector2 = fw.get("pos", Vector2.ZERO)
                var col: Color = fw.get("color", Color.WHITE)
                var sz: float = float(fw.get("size", 3))
                var life: int = int(fw.get("life", 0))
                var alpha: float = min(1.0, float(life) / 30.0)
                draw_circle(pos, sz, Color(col.r, col.g, col.b, alpha))

        # Title "VICTORY!" (pulsing)
        var font := get_theme_default_font()
        var cx: float = size.x / 2.0
        var pulse: float = 1.0 + 0.05 * sin(_time * 3.0)
        var title_size: int = int(72 * pulse)
        draw_string(font, Vector2(cx - 300, 100), "VICTORY!",
                HORIZONTAL_ALIGNMENT_CENTER, 600, title_size, color_title)

        # Subtitle
        draw_string(font, Vector2(cx - 350, 220),
                "YOU CONQUERED THE ARCADE MAZE",
                HORIZONTAL_ALIGNMENT_CENTER, 700, 32, color_subtitle)
        draw_string(font, Vector2(cx - 200, 280),
                "All 68 levels cleared. The treasure is yours.",
                HORIZONTAL_ALIGNMENT_CENTER, 400, 22, color_hint)

        # Final score (FIX Hall of Fame 2P: punteggi singoli + totale)
        if GameManager:
                var score_text: String = "FINAL SCORE: %d" % GameManager.final_score
                if GameManager.num_players == 2:
                        score_text = "P1 SCORE: %d    P2 SCORE: %d" % [
                                        GameManager.final_score_p1, GameManager.final_score_p2]
                draw_string(font, Vector2(cx - 150, 350),
                        score_text,
                        HORIZONTAL_ALIGNMENT_CENTER, 300, 28, color_title)

        # Hint (blinking)
        var hint_alpha: float = 0.5 + 0.5 * sin(_time * 2.0)
        draw_string(font, Vector2(cx - 300, size.y - 80),
                "PRESS ENTER TO RETURN TO MENU",
                HORIZONTAL_ALIGNMENT_CENTER, 600, 24,
                Color(color_hint.r, color_hint.g, color_hint.b, hint_alpha))
