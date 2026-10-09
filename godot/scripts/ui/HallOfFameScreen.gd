## HallOfFameScreen.gd - Schermata "Hall of Fame" (top 10 punteggi).
## ============================================================
## FIX (Hall of Fame): mostra la classifica dei migliori punteggi salvati.
## - Background dedicato in stile fantasy (bg_halloffame.png: sala del
##   trono con trofei, scudi e torce, stesso stile delle altre schermate)
## - Lista top 10: RANGO, NOME, PUNTEGGIO, LIVELLO
## - Accessibile dalla voce dedicata del menu principale
## - Appare anche in alternanza con la demo mode dopo il periodo di standby
##   (una volta la demo, la volta dopo la Hall of Fame)
## - ESC / Enter / qualsiasi tasto di conferma = ritorno al menu
extends Control

const C = preload("res://scripts/core/GameConstants.gd")

@export var color_title: Color = Color(0.95, 0.82, 0.35)
@export var color_header: Color = Color(0.78, 0.62, 0.20)
@export var color_row: Color = Color(0.92, 0.88, 0.78)
@export var color_row_top: Color = Color(1.0, 0.84, 0.3)
@export var color_empty: Color = Color(0.55, 0.50, 0.45)

# Se true, questa istanza è stata aperta dallo standby del menu (alternanza
# con la demo mode): dopo 20s senza input torna al menu da sola.
var from_standby: bool = false

var _bg_texture: Texture2D = null
var _time: float = 0.0
var _standby_timer: float = 0.0
var _entries: Array = []
# Indice della voce appena inserita da evidenziare (da NameEntryKeyboard)
var highlight_index: int = -1
# Se true, la schermata è già stata "lasciata" (evita doppie transizioni)
var _left: bool = false


func _ready() -> void:
        set_anchors_preset(Control.PRESET_FULL_RECT)
        mouse_filter = Control.MOUSE_FILTER_STOP
        focus_mode = Control.FOCUS_ALL
        var _abs := ProjectSettings.globalize_path("res://assets/backgrounds/bg_halloffame.png")
        if FileAccess.file_exists(_abs):
                var _img := Image.new()
                if _img.load(_abs) == OK:
                        _bg_texture = ImageTexture.create_from_image(_img)
        _entries = HallOfFameData.load_entries()
        # FIX (Hall of Fame): evidenzia la voce appena salvata (se richiesta)
        # e resetta il flag di apertura da standby.
        if GameManager:
                highlight_index = GameManager.hof_highlight_index
                GameManager.hof_highlight_index = -1
                from_standby = GameManager.hof_from_standby
                GameManager.hof_from_standby = false
        if AudioManager:
                AudioManager.stop_music()
                AudioManager.stop_epic_music()
                AudioManager.stop_ghost_music()
                # Musica del menu se attiva (la Hall of Fame è una schermata
                # di menu: usa la stessa traccia)
                if GameManager and GameManager.music_enabled:
                        AudioManager.play_menu_music()


func _process(delta: float) -> void:
        _time += delta
        if from_standby:
                _standby_timer += delta
                if _standby_timer >= 20.0:
                        _go_back()
                        return
        queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
        if _left:
                return
        if event is InputEventKey and event.pressed and not event.echo:
                if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE \
                                or event.keycode == KEY_ESCAPE:
                        _go_back()
        elif event is InputEventJoypadButton and event.pressed:
                var configured_shoot: int = -1
                if ConfigManager and ConfigManager.p1_joystick_ready():
                        configured_shoot = ConfigManager.joy_shoot()
                if configured_shoot >= 0 and event.button_index == configured_shoot:
                        _go_back()
                        return
                if event.button_index == JOY_BUTTON_A or event.button_index == JOY_BUTTON_START:
                        _go_back()


func _go_back() -> void:
        if _left:
                return
        _left = true
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.MENU_CONFIRM)
        if GameManager:
                GameManager.go_to_menu()


func _draw() -> void:
        var font := get_theme_default_font()
        var vp: Vector2 = size
        var cx: float = vp.x * 0.5

        # --- Background (cover-fit come MainMenu) ---
        if _bg_texture:
                var tex_size: Vector2 = _bg_texture.get_size()
                var scale_val: float = max(vp.x / tex_size.x, vp.y / tex_size.y)
                var draw_size: Vector2 = tex_size * scale_val
                var draw_pos: Vector2 = (vp - draw_size) / 2.0
                draw_texture_rect(_bg_texture, Rect2(draw_pos, draw_size), false)
        else:
                draw_rect(Rect2(0, 0, vp.x, vp.y), Color(0.05, 0.04, 0.03), true)

        # --- Overlay scuro per leggibilità ---
        draw_rect(Rect2(0, 0, vp.x, vp.y), Color(0.0, 0.0, 0.0, 0.45), true)

        # --- Titolo con pulsazione dorata ---
        var title_pulse: float = 1.0 + 0.03 * sin(_time * 2.0)
        draw_string(font, Vector2(cx - 450, 120), "HALL OF FAME",
                HORIZONTAL_ALIGNMENT_CENTER, 900, int(58 * title_pulse), color_title)
        # Ornamenti (linea + rombo, come MainMenu)
        var orn_y: float = 148.0
        draw_rect(Rect2(cx - 330, orn_y - 1, 280, 2), color_header)
        draw_rect(Rect2(cx + 50, orn_y - 1, 280, 2), color_header)
        var dpts := PackedVector2Array([
                Vector2(cx, orn_y - 7), Vector2(cx + 9, orn_y),
                Vector2(cx, orn_y + 7), Vector2(cx - 9, orn_y),
        ])
        draw_colored_polygon(dpts, color_header)

        # --- Pannello classifica (pergamena scura) ---
        var panel_rect := Rect2(cx - 560, 180, 1120, 700)
        draw_rect(panel_rect, Color(0.06, 0.045, 0.03, 0.82), true)
        draw_rect(panel_rect, Color(0.55, 0.39, 0.20), false, 5.0)

        # --- Intestazione colonne ---
        var head_y: float = 248.0
        draw_string(font, Vector2(cx - 500, head_y), "RANK",
                HORIZONTAL_ALIGNMENT_LEFT, 120, 24, color_header)
        draw_string(font, Vector2(cx - 380, head_y), "NAME",
                HORIZONTAL_ALIGNMENT_LEFT, 260, 24, color_header)
        draw_string(font, Vector2(cx - 60, head_y), "SCORE",
                HORIZONTAL_ALIGNMENT_RIGHT, 260, 24, color_header)
        draw_string(font, Vector2(cx + 300, head_y), "LEVEL",
                HORIZONTAL_ALIGNMENT_RIGHT, 200, 24, color_header)
        draw_rect(Rect2(cx - 500, head_y + 10, 1000, 2), Color(0.55, 0.39, 0.20, 0.8), true)

        # --- Righe della classifica ---
        var row_y: float = head_y + 56.0
        var row_h: float = 56.0
        var entries_to_show: int = maxi(1, _entries.size())
        for i in HallOfFameData.MAX_ENTRIES:
                var y: float = row_y + float(i) * row_h
                if i >= _entries.size():
                        # Riga vuota (trattini, stile arcade)
                        if i < 10:
                                draw_string(font, Vector2(cx - 500, y), "%d." % (i + 1),
                                        HORIZONTAL_ALIGNMENT_LEFT, 120, 26, color_empty)
                                draw_string(font, Vector2(cx - 380, y), "- - - - - -",
                                        HORIZONTAL_ALIGNMENT_LEFT, 260, 26, color_empty)
                        continue
                var e: Dictionary = _entries[i]
                var is_top3: bool = i < 3
                var is_highlight: bool = (i == highlight_index)
                var row_col: Color = color_row_top if is_top3 else color_row
                # Riga evidenziata (voce appena salvata)
                if is_highlight:
                        var glow: float = 0.5 + 0.5 * sin(_time * 4.0)
                        draw_rect(Rect2(cx - 520, y - 26, 1040, 44),
                                Color(0.78, 0.62, 0.20, 0.10 + 0.10 * glow), true)
                        draw_rect(Rect2(cx - 520, y - 26, 1040, 44),
                                Color(1.0, 0.84, 0.3, 0.5 * glow + 0.3), false, 2.0)
                # Rango (medaglia per il top 3)
                var rank_col: Color = row_col
                if i == 0:
                        rank_col = Color(1.0, 0.85, 0.3)      # oro
                elif i == 1:
                        rank_col = Color(0.85, 0.85, 0.9)      # argento
                elif i == 2:
                        rank_col = Color(0.85, 0.6, 0.35)      # bronzo
                draw_string(font, Vector2(cx - 500, y), "%d." % (i + 1),
                        HORIZONTAL_ALIGNMENT_LEFT, 120, 28, rank_col)
                # Nome
                draw_string(font, Vector2(cx - 380, y), str(e["name"]),
                        HORIZONTAL_ALIGNMENT_LEFT, 260, 28, row_col)
                # Punteggio
                draw_string(font, Vector2(cx - 60, y), "%d" % int(e["score"]),
                        HORIZONTAL_ALIGNMENT_RIGHT, 260, 28, row_col)
                # Livello
                draw_string(font, Vector2(cx + 300, y), "%d" % int(e.get("level", 1)),
                        HORIZONTAL_ALIGNMENT_RIGHT, 200, 28,
                        Color(row_col.r * 0.7, row_col.g * 0.7, row_col.b * 0.7))

        # --- Hint (lampeggiante) ---
        var hint_alpha: float = 0.4 + 0.6 * (0.5 + 0.5 * sin(_time * 2.0))
        draw_string(font, Vector2(cx - 400, vp.y - 70),
                "PRESS ENTER TO RETURN TO MENU",
                HORIZONTAL_ALIGNMENT_CENTER, 800, 24,
                Color(0.59, 0.59, 0.59, hint_alpha))
