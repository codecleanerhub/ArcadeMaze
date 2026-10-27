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

# TASK 79 — palette ORO MEDIEVALE con font "Arcadia Gothic" (originale,
# nessuna licenza): header e titolo = font oro (bande bake-ate), righe =
# font osso, righe vuote e hint = font pietra. I colori WHITE mostrano le
# palette bake-ate dei .fnt; color_header (oro antico) resta per ornamenti.
@export var color_title: Color = Color(1.000, 0.840, 0.000)    # oro pieno (fallback testuale)
@export var color_header: Color = Color(0.720, 0.550, 0.160)   # oro antico (ornamenti)
@export var color_row: Color = Color(1.0, 1.0, 1.0)            # WHITE -> palette osso
@export var color_row_top: Color = Color(1.0, 1.0, 1.0)        # WHITE -> palette oro (top 3)
@export var color_empty: Color = Color(1.0, 1.0, 1.0)          # WHITE -> palette pietra

# TASK 79 — font BMFont pre-scalati (32px = 1:1 senza blending).
var _font_gold: Font = null
var _font_bone: Font = null
var _font_stone: Font = null
var _font_title48: Font = null

# Se true, questa istanza è stata aperta dallo standby del menu (alternanza
# con la demo mode): dopo 20s senza input torna al menu da sola.
var from_standby: bool = false

var _bg_texture: Texture2D = null
# TASK 76: header "HALL OF FAME" rosso sangue PixelLab (stesso stile del
# logo del titolo); fallback al testo procedurale se il PNG manca.
var _title_logo: Texture2D = null
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
        # TASK 79: font Arcadia Gothic (fallback silenzioso sul font tema).
        _font_gold = load("res://assets/fonts/arcadia_gothic_gold_32.fnt")
        _font_bone = load("res://assets/fonts/arcadia_gothic_bone_32.fnt")
        _font_stone = load("res://assets/fonts/arcadia_gothic_stone_32.fnt")
        _font_title48 = load("res://assets/fonts/arcadia_gothic_gold_48.fnt")
        var _abs := ProjectSettings.globalize_path("res://assets/backgrounds/bg_halloffame.png")
        if FileAccess.file_exists(_abs):
                var _img := Image.new()
                if _img.load(_abs) == OK:
                        _bg_texture = ImageTexture.create_from_image(_img)
        var _tl_abs := ProjectSettings.globalize_path("res://assets/ui/header_halloffame.png")
        if FileAccess.file_exists(_tl_abs):
                var _tl_img := Image.new()
                if _tl_img.load(_tl_abs) == OK:
                        _title_logo = ImageTexture.create_from_image(_tl_img)
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
                # TASK 23 (sequenza fine partita richiesta dall'utente):
                # congratulazioni -> salvataggio score -> CREDITS -> menu.
                # Se la HOF è stata raggiunta dal flusso di VITTORIA, dopo la
                # classifica si va ai CREDITS (e da lì al menu); dal menu o
                # dallo standby il comportamento resta go_to_menu().
                if GameManager.hof_from_win:
                        GameManager.hof_from_win = false
                        GameManager.go_to_credits()
                        return
                GameManager.go_to_menu()


func _draw() -> void:
        var font := get_theme_default_font()
        # TASK 79: font per elemento — gold = intestazioni, bone = righe,
        # stone = righe vuote/hint. Se l'import manca si resta sul tema.
        var f_head: Font = _font_gold if _font_gold != null else font
        var f_row: Font = _font_bone if _font_bone != null else font
        var f_dim: Font = _font_stone if _font_stone != null else font
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

        # --- Titolo (TASK 79: header oro Arcadia Gothic, fallback testuale) ---
        # TASK 44: "HALL OF FAME" resta in inglese in entrambe le lingue
        # (termine arcade usato anche in Italia, richiesta utente).
        if _title_logo != null:
                # header 350x96 (aspect ~3.6:1): la larghezza deriva dal CAP
                # di ALTEZZA (110px) per non sconfinare nel pannello sotto.
                var lh: float = 110.0
                var lw: float = lh * float(_title_logo.get_width()) / maxf(_title_logo.get_height(), 1.0)
                lw = minf(lw, vp.x * 0.6)
                lh = lw * float(_title_logo.get_height()) / maxf(_title_logo.get_width(), 1.0)
                var lx: float = cx - lw * 0.5
                var ly: float = 118.0 - lh * 0.5
                # alone oro caldo pulsante dietro il logo
                var glow_a: float = 0.10 + 0.05 * sin(_time * 1.7)
                draw_circle(Vector2(cx, 118.0), maxf(lw, lh) * 0.42,
                                Color(0.45, 0.33, 0.08, glow_a))
                draw_texture_rect(_title_logo, Rect2(lx, ly, lw, lh), false,
                                Color(1, 1, 1, 0.93 + 0.07 * sin(_time * 1.9)))
        else:
                var f_big: Font = _font_title48 if _font_title48 != null else f_head
                draw_string(f_big, Vector2(cx - 450, 120), I18n.t("menu.hall_of_fame"),
                        HORIZONTAL_ALIGNMENT_CENTER, 900, 48, color_title)
        # Ornamenti (linea + rombo, come MainMenu)
        var orn_y: float = 148.0
        draw_rect(Rect2(cx - 330, orn_y - 1, 280, 2), color_header)
        draw_rect(Rect2(cx + 50, orn_y - 1, 280, 2), color_header)
        var dpts := PackedVector2Array([
                Vector2(cx, orn_y - 7), Vector2(cx + 9, orn_y),
                Vector2(cx, orn_y + 7), Vector2(cx - 9, orn_y),
        ])
        draw_colored_polygon(dpts, color_header)

        # --- Pannello classifica (pergamena umber con bordo oro antico) ---
        var panel_rect := Rect2(cx - 560, 180, 1120, 700)
        draw_rect(panel_rect, Color(0.09, 0.07, 0.04, 0.85), true)
        draw_rect(panel_rect, Color(0.72, 0.55, 0.16), false, 5.0)

        # --- Intestazione colonne (TASK 44: localizzate; TASK 79: gold 32;
        # colonne ALLARGATE per l'advance del font gotico a 32px) ---
        var head_y: float = 248.0
        draw_string(f_head, Vector2(cx - 530, head_y), I18n.t("hof.rank"),
                HORIZONTAL_ALIGNMENT_LEFT, 160, 32, Color.WHITE)
        draw_string(f_head, Vector2(cx - 350, head_y), I18n.t("hof.name"),
                HORIZONTAL_ALIGNMENT_LEFT, 340, 32, Color.WHITE)
        draw_string(f_head, Vector2(cx - 160, head_y), I18n.t("hof.score"),
                HORIZONTAL_ALIGNMENT_RIGHT, 340, 32, Color.WHITE)
        draw_string(f_head, Vector2(cx + 250, head_y), I18n.t("hof.level"),
                HORIZONTAL_ALIGNMENT_RIGHT, 280, 32, Color.WHITE)
        draw_rect(Rect2(cx - 530, head_y + 12, 1060, 2), Color(0.72, 0.55, 0.16, 0.8), true)

        # --- Righe della classifica ---
        var row_y: float = head_y + 56.0
        var row_h: float = 56.0
        var entries_to_show: int = maxi(1, _entries.size())
        for i in HallOfFameData.MAX_ENTRIES:
                var y: float = row_y + float(i) * row_h
                if i >= _entries.size():
                        # Riga vuota (trattini, stile arcade; font pietra)
                        if i < 10:
                                draw_string(f_dim, Vector2(cx - 530, y), "%d." % (i + 1),
                                        HORIZONTAL_ALIGNMENT_LEFT, 160, 32, color_empty)
                                draw_string(f_dim, Vector2(cx - 350, y), "- - - - - -",
                                        HORIZONTAL_ALIGNMENT_LEFT, 340, 32, color_empty)
                        continue
                var e: Dictionary = _entries[i]
                var is_top3: bool = i < 3
                var is_highlight: bool = (i == highlight_index)
                # TASK 79: il top-3 usa il font ORO, le altre righe l'osso
                var row_font: Font = f_head if is_top3 else f_row
                # Riga evidenziata (voce appena salvata) — alone oro
                if is_highlight:
                        var glow: float = 0.5 + 0.5 * sin(_time * 4.0)
                        draw_rect(Rect2(cx - 550, y - 26, 1100, 44),
                                Color(0.55, 0.42, 0.10, 0.12 + 0.12 * glow), true)
                        draw_rect(Rect2(cx - 550, y - 26, 1100, 44),
                                Color(1.0, 0.84, 0.0, 0.5 * glow + 0.3), false, 2.0)
                # Rango (medaglia per il top 3 — tinta su palette bake-ata)
                var rank_col: Color = Color.WHITE
                if i == 0:
                        rank_col = Color(1.0, 0.85, 0.3)      # oro
                elif i == 1:
                        rank_col = Color(0.85, 0.85, 0.9)      # argento
                elif i == 2:
                        rank_col = Color(0.85, 0.6, 0.35)      # bronzo
                draw_string(row_font, Vector2(cx - 530, y), "%d." % (i + 1),
                        HORIZONTAL_ALIGNMENT_LEFT, 160, 32, rank_col)
                # Nome
                draw_string(row_font, Vector2(cx - 350, y), str(e["name"]),
                        HORIZONTAL_ALIGNMENT_LEFT, 340, 32, Color.WHITE)
                # Punteggio
                draw_string(row_font, Vector2(cx - 160, y), "%d" % int(e["score"]),
                        HORIZONTAL_ALIGNMENT_RIGHT, 340, 32, Color.WHITE)
                # Livello
                draw_string(row_font, Vector2(cx + 250, y), "%d" % int(e.get("level", 1)),
                        HORIZONTAL_ALIGNMENT_RIGHT, 280, 32, Color(0.7, 0.7, 0.7))

        # --- Hint (lampeggiante, font pietra) ---
        var hint_alpha: float = 0.4 + 0.6 * (0.5 + 0.5 * sin(_time * 2.0))
        draw_string(f_dim, Vector2(cx - 640, vp.y - 70),
                I18n.t("screen.return_hint"),
                HORIZONTAL_ALIGNMENT_CENTER, 1280, 32,
                Color(1.0, 1.0, 1.0, hint_alpha))
