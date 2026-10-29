## WinScreen.gd
## ============================================================
## Porting of Game.cpp STATE_WIN_STORY.
## Shows the victory screen with bg_win.jpg background and
## animated fireworks. "PRESS ENTER TO RETURN TO MENU".
## ============================================================
extends Control

signal back_to_menu_requested()

# FIX (schermata chiusa involontariamente in 1 secondo — mirror LoseScreen):
# in test mode si arriva alla vittoria martellando SPACE (salto livelli): la
# pressione residua chiudeva la schermata di vittoria PRIMA dei fuochi
# d'artificio e PRIMA del salvataggio del record. GRAZIA INPUT: per i primi
# MIN_DISPLAY_SECONDS la schermata non accetta input.
const MIN_DISPLAY_SECONDS: float = 3.0

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
var _display_timer: float = 0.0
# FIX (Hall of Fame 2P): coda dei punteggi da salvare. In 2P ogni player
# salva il PROPRIO punteggio: prima la tastiera per P1, poi (se qualifica)
# quella per P2, infine la Hall of Fame con l'ultima voce evidenziata.
var _hof_queue: Array = []  # [{"label": "PLAYER 1", "score": int}, ...]
var _hof_level: int = 1

# TASK 76 (richiesta utente: "nella schermata di fine gioco, nello sfondo
# deve essere rappresentato il personaggio o i personaggi usati per
# giocare"): sprite dei PG usati in partita (XHD 256px/frame se presente,
# fallback SD 64px), animati col ciclo di camminata mentre i fuochi
# d'artificio esplodono attorno. 1P = un eroe al centro; 2P = i due affiancati.
const CHAR_SHEET_BASES: Array[String] = [
        "player1", "player2", "char_mage", "char_orc", "char_elf",
        "char_knight", "char_golem", "char_dragon", "char_vampire",
]
var _char_textures: Array[Texture2D] = []  # uno per PG usato (1 o 2)
var _char_anim_time: float = 0.0


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
        _load_played_characters()


func _process(delta: float) -> void:
        _time += delta
        _char_anim_time += delta
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
        # classifica, mostra la tastiera di inserimento nome. La tastiera NON
        # appare durante la grazia input (pressione residua di SPACE/fuoco).
        if not _keyboard_shown and not _finished \
                        and _display_timer >= MIN_DISPLAY_SECONDS:
                _keyboard_timer += delta
                if _keyboard_timer >= KEYBOARD_DELAY:
                        _maybe_show_keyboard()
        _display_timer += delta
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
                        _hof_queue.append({"label": I18n.t("hud.player") % 1,
                                        "score": GameManager.final_score_p1})
                if HallOfFameData.qualifies(GameManager.final_score_p2):
                        _hof_queue.append({"label": I18n.t("hud.player") % 2,
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
                # TASK 23 (sequenza fine partita): dopo il salvataggio dello
                # score la Hall of Fame porterà ai CREDITS e poi al menu
                # (congratulazioni -> salvataggio score -> credits -> menu).
                GameManager.hof_from_win = true
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
        # FIX (grazia input — mirror LoseScreen): durante i primi secondi la
        # schermata NON consuma nessun tasto: la pressione residua del tasto di
        # salto livelli (SPACE in test mode) o del fuoco del joystick non puo'
        # chiudere la vittoria prima che sia leggibile e prima del salvataggio
        # del record.
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


# TASK 76 — carica gli sheet dei personaggi USATI in partita (P1 e, in 2P,
# P2), con la stessa priorita XHD della ruota di selezione.
func _load_played_characters() -> void:
        _char_textures.clear()
        if GameManager == null:
                return
        var idxs: Array[int] = [GameManager.player1_character]
        if GameManager.num_players == 2:
                idxs.append(GameManager.player2_character)
        for ci in idxs:
                var base: String = CHAR_SHEET_BASES[ci % CHAR_SHEET_BASES.size()]
                var tex: Texture2D = null
                var xhd_path: String = "res://assets/sprites/xhd/%s_xhd_sheet.png" % base
                var xhd_abs: String = ProjectSettings.globalize_path(xhd_path)
                if FileAccess.file_exists(xhd_abs):
                        var img := Image.new()
                        if img.load(xhd_abs) == OK:
                                tex = ImageTexture.create_from_image(img)
                if tex == null:
                        var sd_path: String = "res://assets/sprites/%s_sheet.png" % base
                        var sd_abs: String = ProjectSettings.globalize_path(sd_path)
                        if FileAccess.file_exists(sd_abs):
                                var img2 := Image.new()
                                if img2.load(sd_abs) == OK:
                                        tex = ImageTexture.create_from_image(img2)
                if tex != null:
                        _char_textures.append(tex)


# TASK 76 — disegna i PG usati: ciclo di camminata (4 frame ~8fps) su un
# gradino luminoso caldo, con alone rosato da "trionfo".
func _draw_played_characters() -> void:
        if _char_textures.is_empty():
                return
        var n: int = _char_textures.size()
        var spacing: float = 300.0
        var cx: float = size.x * 0.5
        var base_y: float = size.y * 0.80
        var glow_pulse: float = 0.55 + 0.20 * sin(_time * 2.2)
        for k in n:
                var tex: Texture2D = _char_textures[k]
                var px: float = cx + (float(k) - float(n - 1) * 0.5) * spacing
                # alone caldo sotto il personaggio
                draw_circle(Vector2(px, base_y - 8.0), 120.0,
                                Color(1.0, 0.72, 0.28, 0.10 * glow_pulse))
                draw_circle(Vector2(px, base_y - 8.0), 70.0,
                                Color(1.0, 0.62, 0.22, 0.16 * glow_pulse))
                # frame del ciclo di camminata (4 frame, ~8 fps)
                var fpx: int = 256 if tex.get_width() >= 1024 else 64
                var frame: int = int(_char_anim_time * 8.0) % 4
                var at := AtlasTexture.new()
                at.atlas = tex
                at.region = Rect2(frame * fpx, 0, fpx, fpx)
                var char_h: float = 300.0 if n == 1 else 260.0
                var char_w: float = char_h
                draw_texture_rect(at, Rect2(px - char_w * 0.5,
                                base_y - char_h, char_w, char_h), false)


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

        # TASK 76: leggero velo scuro in basso per staccare i personaggi
        # dall'immagine di sfondo.
        var veil_h: float = size.y * 0.55
        draw_rect(Rect2(0, size.y - veil_h, size.x, veil_h),
                        Color(0.01, 0.01, 0.03, 0.35), true)

        # Personaggi usati in partita (camminata trionfale)
        _draw_played_characters()

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
        draw_string(font, Vector2(cx - 300, 100), I18n.t("win.title"),
                HORIZONTAL_ALIGNMENT_CENTER, 600, title_size, color_title)

        # Subtitle
        draw_string(font, Vector2(cx - 350, 220),
                I18n.t("win.subtitle"),
                HORIZONTAL_ALIGNMENT_CENTER, 700, 32, color_subtitle)
        draw_string(font, Vector2(cx - 200, 280),
                I18n.t("win.body"),
                HORIZONTAL_ALIGNMENT_CENTER, 400, 22, color_hint)

        # Final score (FIX Hall of Fame 2P: punteggi singoli + totale)
        if GameManager:
                var score_text: String = I18n.t("win.final_score") % GameManager.final_score
                if GameManager.num_players == 2:
                        score_text = I18n.t("win.p_score") % [
                                        GameManager.final_score_p1, GameManager.final_score_p2]
                draw_string(font, Vector2(cx - 150, 350),
                        score_text,
                        HORIZONTAL_ALIGNMENT_CENTER, 300, 28, color_title)

        # Hint (blinking)
        var hint_alpha: float = 0.5 + 0.5 * sin(_time * 2.0)
        draw_string(font, Vector2(cx - 300, size.y - 80),
                I18n.t("screen.return_hint"),
                HORIZONTAL_ALIGNMENT_CENTER, 600, 24,
                Color(color_hint.r, color_hint.g, color_hint.b, hint_alpha))
