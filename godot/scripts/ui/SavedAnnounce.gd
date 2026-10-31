## SavedAnnounce.gd — TASK 106 (SALVA PARTITA).
## ============================================================
## Annuncio NON-BLOCCANTE "Partita salvata...": appare al CENTRO dello
## schermo al livello successivo a un boss vinto (l'auto-save ha appena
## scritto lo slot) e resta ~2 secondi, SParendo via via più trasparente
## (alpha pieno nella prima parte, poi fade lineare fino a zero).
##
## Stile (richiesta utente): "con lo stile del titolo del gioco ma con
## caratteri piccoli come le voci di menu" -> font medievale Goth And
## Gothic a 30px (le voci menu sono 28), palette ORO del titolo
## (oro caldo + ombra bruno cupa, mirror MainMenu TASK 78) con contorno
## nero per la leggibilità sopra il labirinto.
##
## Pure-code CanvasLayer (pattern LevelUpAnnounce):
##   * layer 27 (sopra HUD 10 e pause 20, sotto le card 30+)
##   * PROCESS_MODE_ALWAYS, NESSUNA pausa: il livello è già partito
##   * signal announcement_done -> il controller libera il layer
extends CanvasLayer

signal announcement_done

const C = preload("res://scripts/core/GameConstants.gd")

## Alpha pieno fino al 45% della durata, poi fade lineare a zero (il
## testo "diventa sempre più trasparente" fino a sparire).
const FULL_ALPHA_FRACTION: float = 0.45

## Palette oro del titolo (mirror MainMenu.color_title_gold/shadow).
const COL_GOLD: Color = Color(0.941, 0.780, 0.373)
const COL_GOLD_LIGHT: Color = Color(1.000, 0.920, 0.600)
const COL_SHADOW: Color = Color(0.180, 0.110, 0.020)

var _t_ms: float = 0.0
var _done: bool = false
var _panel: Control = null
var _font: Font = null


func _ready() -> void:
        layer = 27
        process_mode = Node.PROCESS_MODE_ALWAYS
        # Font medievale del titolo (fallback: font di default).
        _font = C.gothic_font()
        if _font == null:
                _font = ThemeDB.fallback_font
        _panel = Control.new()
        _panel.name = "SavedAnnouncePanel"
        _panel.set_anchors_preset(Control.PRESET_FULL_RECT)
        _panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _panel.draw.connect(_draw_panel)
        add_child(_panel)
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.TREASURE)


func _process(delta: float) -> void:
        if _done:
                return
        _t_ms += delta * 1000.0
        _panel.queue_redraw()
        if _t_ms >= C.SAVE_ANNOUNCE_MS:
                _done = true
                set_process(false)
                announcement_done.emit()
                queue_free()


func _draw_panel() -> void:
        var font: Font = _font
        var vp: Vector2 = _panel.get_viewport_rect().size
        if vp.x <= 1.0:
                vp = Vector2(1920.0, 1080.0)
        var text: String = I18n.t("save.saved") if I18n != null else "Partita salvata..."
        var font_size: int = 30
        var tw: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER,
                        -1, font_size).x
        var cx: float = vp.x * 0.5
        var cy: float = vp.y * 0.5 - float(font_size) * 0.5

        # alpha: pieno -> fade lineare fino a sparire (richiesta utente:
        # "resta 2 secondi e scompare diventando sempre più trasparente").
        var fade_start: float = C.SAVE_ANNOUNCE_MS * FULL_ALPHA_FRACTION
        var a: float = 1.0
        if _t_ms > fade_start:
                a = clampf(1.0 - (_t_ms - fade_start)
                                / (C.SAVE_ANNOUNCE_MS - fade_start), 0.0, 1.0)
        if a <= 0.005:
                return

        # bagliore caldo dietro il testo (molto tenue, non copre il gioco)
        _panel.draw_circle(Vector2(cx, cy + 14.0), 170.0,
                        Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b, 0.10 * a))
        _panel.draw_circle(Vector2(cx, cy + 14.0), 110.0,
                        Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b, 0.08 * a))

        # testo con stile titolo: ombra bruno cupa, corpo oro caldo,
        # luce in alto a sinistra e contorno nero a 4 offset.
        var tx: float = cx - tw * 0.5
        var ty: float = cy + float(font_size)
        for off in [Vector2(-2, 0), Vector2(2, 0), Vector2(0, -2), Vector2(0, 2)]:
                _panel.draw_string(font, Vector2(tx + off.x, ty + off.y), text,
                                HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
                                Color(0.0, 0.0, 0.0, 0.85 * a))
        _panel.draw_string(font, Vector2(tx + 4.0, ty + 4.0), text,
                        HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
                        Color(COL_SHADOW.r, COL_SHADOW.g, COL_SHADOW.b, 0.9 * a))
        _panel.draw_string(font, Vector2(tx, ty), text,
                        HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
                        Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b, a))
        _panel.draw_string(font, Vector2(tx - 1.5, ty - 1.5), text,
                        HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
                        Color(COL_GOLD_LIGHT.r, COL_GOLD_LIGHT.g,
                                        COL_GOLD_LIGHT.b, 0.55 * a))
