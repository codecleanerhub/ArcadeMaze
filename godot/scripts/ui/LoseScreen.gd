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

# FIX (game over sparita in 1 secondo — bug utente): in test mode si salta i
# livelli martellando SPACE (o il tasto fuoco del joystick): la pressione
# residua, riflessa sulla schermata GAME OVER appena comparsa, la chiudeva
# subito (SPACE/ENTER/A = uscita immediata) senza che il player percepisse la
# pressione come volontaria — e senza salvare il record in Hall of Fame.
# GRAZIA INPUT: per i primi MIN_DISPLAY_SECONDS la schermata NON accetta
# input: il game over deve restare leggibile e il salvataggio del record
# non puo' essere scavalcato da una pressione accidentale.
const MIN_DISPLAY_SECONDS: float = 3.0

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
var _display_timer: float = 0.0
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
        var _abs := ProjectSettings.globalize_path("res://assets/backgrounds/bg_gameover.jpg")
        if FileAccess.file_exists(_abs):
                var _img := Image.new()
                if _img.load(_abs) == OK:
                        _bg_texture = ImageTexture.create_from_image(_img)
        if AudioManager:
                AudioManager.stop_music()


func _process(delta: float) -> void:
        _time += delta
        _display_timer += delta
        # FIX (game over sparita): aggiorna l'hint in base alla grazia input.
        queue_redraw()
        # FIX (Hall of Fame): dopo il delay, se il punteggio merita la
        # classifica, mostra la tastiera di inserimento nome. La tastiera NON
        # appare durante la grazia input (l'utente potrebbe avere SPACE ancora
        # pigiato dal salto livelli: aprire la tastiera subito farebbe
        # selezionare/consentire caratteri per errore).
        if not _keyboard_shown and not _finished \
                        and _display_timer >= MIN_DISPLAY_SECONDS:
                _keyboard_timer += delta
                if _keyboard_timer >= KEYBOARD_DELAY:
                        _maybe_show_keyboard()


# FIX (Hall of Fame 2P): costruisce la coda dei punteggi qualificanti.
# In 1P: il punteggio unico. In 2P: PRIMA il punteggio di P1, POI quello di
# P2 (ognuno con la propria tastiera: entrambi possono entrare in
# classifica). Solo i punteggi che qualificano entrano in coda.
func _build_hof_queue() -> void:
        _hof_queue.clear()
        if GameManager == null:
                return
        _hof_level = GameManager.final_level
        if GameManager.num_players == 2:
                if HallOfFameData.qualifies(GameManager.final_score_p1):
                        _hof_queue.append({"label": I18n.t("hud.player") % 1,
                                        "score": GameManager.final_score_p1})
                if HallOfFameData.qualifies(GameManager.final_score_p2):
                        _hof_queue.append({"label": I18n.t("hud.player") % 2,
                                        "score": GameManager.final_score_p2})
        else:
                if HallOfFameData.qualifies(GameManager.final_score):
                        _hof_queue.append({"label": "", "score": GameManager.final_score})


# Mostra la tastiera per il primo punteggio in coda (se c'è).
func _maybe_show_keyboard() -> void:
        _keyboard_shown = true
        if _hof_queue.is_empty():
                _build_hof_queue()
        if _hof_queue.is_empty():
                return  # nessun punteggio qualificante: niente inserimento nome
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


# Chiamato quando il player conferma il nome: la tastiera ha già salvato la
# voce. Se resta un altro player in coda, mostra la sua tastiera; altrimenti
# porta alla schermata Hall of Fame con l'ultima voce salvata evidenziata.
func _on_name_confirmed(player_name: String) -> void:
        if _finished:
                return
        # Rimuovi il punteggio appena salvato dalla coda.
        if not _hof_queue.is_empty():
                _hof_queue.pop_front()
        if not _hof_queue.is_empty():
                # C'è ancora il secondo player: nuova tastiera per lui.
                if _keyboard != null and is_instance_valid(_keyboard):
                        _keyboard.queue_free()
                _keyboard = null
                _show_next_keyboard()
                return
        _finished = true
        if GameManager:
                # Trova la posizione dell'ultima voce salvata per evidenziarla
                # (l'ultima salvata è quella di P2 in 2P, altrimenti P1).
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


func _unhandled_input(event: InputEvent) -> void:
        if _finished:
                return
        # FIX (game over sparita in 1 secondo): durante la grazia input la
        # schermata NON consuma nessun tasto (nemmeno ESC): la pressione
        # residua del tasto di salto livelli (SPACE in test mode) o del tasto
        # fuoco del joystick non puo' chiudere il game over prima che sia
        # leggibile e prima che il record venga salvato.
        if _display_timer < MIN_DISPLAY_SECONDS:
                return
        # FIX (Hall of Fame): mentre la tastiera è attiva, questa schermata
        # non consuma input (li gestisce la tastiera).
        if _keyboard != null and is_instance_valid(_keyboard):
                return
        if event is InputEventKey and event.pressed and not event.echo:
                if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
                        # FIX (possibilità di salvare il record): se un punteggio
                        # merita la classifica, ENTER/SPACE NON salta il salvataggio
                        # ma apre SUBITO la tastiera di inserimento nome (di norma
                        # appare da sola dopo 1.6s). Solo se NESSUN punteggio
                        # qualifica, ENTER porta al menu.
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
                I18n.t("lose.body"),
                HORIZONTAL_ALIGNMENT_CENTER, 600, 28, color_subtitle)

        # FIX (Hall of Fame): punteggio finale raggiunto. In 2P mostra i
        # punteggi SINGOLI dei due player più il totale.
        var score: int = 0
        var level: int = 1
        if GameManager:
                score = GameManager.final_score
                level = GameManager.final_level
        var score_text: String = I18n.t("lose.final") % [score, level]
        if GameManager and GameManager.num_players == 2:
                score_text = I18n.t("lose.p_final") % [
                        GameManager.final_score_p1, GameManager.final_score_p2, level]
        draw_string(font, Vector2(cx - 300, 300),
                score_text,
                HORIZONTAL_ALIGNMENT_CENTER, 600, 30, Color(1.0, 0.84, 0.3))

        # Hint (blinking) — cambia se la tastiera sta per apparire
        var hint_alpha: float = 0.5 + 0.5 * sin(_time * 2.0)
        var hint_text: String = I18n.t("screen.return_hint")
        # FIX (game over sparita): durante la grazia input l'hint resta nascosto
        # (non e' ancora possibile premere nulla).
        if _display_timer < MIN_DISPLAY_SECONDS:
                hint_text = ""
        else:
                var pending_p1: bool = score > 0 and HallOfFameData.qualifies(
                                GameManager.final_score_p1 \
                                if GameManager.num_players == 2 else score)
                var pending_p2: bool = GameManager.num_players == 2 \
                                and HallOfFameData.qualifies(GameManager.final_score_p2)
                if not _keyboard_shown and (pending_p1 or pending_p2):
                        hint_text = I18n.t("lose.new_high")
                elif _keyboard_shown and _keyboard != null and is_instance_valid(_keyboard):
                        hint_text = ""
        draw_string(font, Vector2(cx - 300, size.y - 80),
                hint_text,
                HORIZONTAL_ALIGNMENT_CENTER, 600, 24,
                Color(color_hint.r, color_hint.g, color_hint.b, hint_alpha))
