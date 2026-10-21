## LoadingScreen.gd - Autoload "LoadingScreen": overlay "Loading..." stile
## orrore sangue GOCCIOLANTE (stessa famiglia visiva della scritta "Hurry Up!"
## del MainGameController — richiesta utente TASK 44).
##
## COPRE tutte le attese che prima erano SCHERMO NERO:
##   * BOOT: l'autoload si mostra da subito; si nasconde da solo dopo 3 frame
##     renderizzati (la fase di caricamento engine/autoload è coperta dallo
##     boot_splash PNG, vedi project.godot — questo overlay prende il resto).
##   * TRANSIZIONI DI SCENA: GameManager.change_scene() chiama show_loading()
##     prima di change_scene_to_file(); l'overlay resta sopra la scena nuova
##     finché non sono passati 3 frame renderizzati (se il _ready della scena
##     è pesante — es. generazione labirinto — i frame non avanzano e la
##     scritta resta visibile per tutta l'elaborazione: nessun nero).
##
## STILE (analogo a "Hurry Up!"): testo rosso sangue con ombra scura e riflesso
## bagnato, alalone scuro che trasuda, gocce deterministiche sotto la baseline
## che crescono, si staccano e cadono con scia. Differenza voluta: NESSUN
## lampeggio on/off (la scritta di caricamento deve restare LEGGIBILE), c'è
## solo una lenta pulsazione di luminosità e il tremolio orror ±1px.
extends Node

## Frame renderizzati dopo i quali l'overlay si auto-nasconde (modalità
## automatica: scene change / boot). 3 frame = la nuova scena è già comparsa
## dietro l'overlay per almeno un frame intero.
const AUTO_HIDE_FRAMES: int = 3

# --- Stile sangue (palette condivisa con _draw_hurry_up_text) ---
const LOAD_FONT_SIZE: int = 64
const LOAD_CENTER_Y_FRAC: float = 0.44   # centro verticale del testo
# Posizioni delle gocce in frazione della larghezza del testo + fase iniziale
# (deterministiche, come in Hurry Up: nessun random per-frame).
const DRIP_T: Array[float] = [0.08, 0.20, 0.33, 0.46, 0.58, 0.71, 0.84, 0.95]
const DRIP_PHASE: Array[float] = [0.0, 1.15, 0.55, 1.7, 0.3, 1.0, 1.5, 0.8]
const DRIP_CYCLE: float = 2.4            # durata del ciclo di ogni goccia (s)

var _canvas: CanvasLayer
var _painter: Control
var _visible: bool = false
var _auto_hide: bool = true
var _frames_since_show: int = 0
var _time: float = 0.0


func _ready() -> void:
        process_mode = Node.PROCESS_MODE_ALWAYS
        _canvas = CanvasLayer.new()
        _canvas.name = "LoadingScreenLayer"
        _canvas.layer = 100  # sopra TUTTO (HUD compresa)
        add_child(_canvas)
        _painter = Control.new()
        _painter.name = "LoadingPainter"
        _painter.set_anchors_preset(Control.PRESET_FULL_RECT)
        _painter.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _painter.draw.connect(_on_draw)
        _canvas.add_child(_painter)
        # BOOT: mostrati subito; il primo frame utile del menu appare sotto
        # l'overlay e dopo 3 frame si dissolve (niente nero tra splash e menu).
        show_loading()


func _process(delta: float) -> void:
        _time += delta
        if not _visible:
                return
        _frames_since_show += 1
        if _auto_hide and _frames_since_show >= AUTO_HIDE_FRAMES:
                hide_loading()
                return
        _painter.queue_redraw()


# ============================================================================
# API pubblica
# ============================================================================

## Mostra l'overlay. `auto_hide` = true (default) lo nasconde da solo dopo
## AUTO_HIDE_FRAMES frame renderizzati (per scene change e boot); false lo
## mantiene finché il chiamante non chiama hide_loading().
func show_loading(auto_hide: bool = true) -> void:
        _visible = true
        _auto_hide = auto_hide
        _frames_since_show = 0
        if _canvas:
                _canvas.visible = true
        if _painter:
                _painter.queue_redraw()


func hide_loading() -> void:
        _visible = false
        _auto_hide = true
        if _canvas:
                _canvas.visible = false


func is_showing() -> bool:
        return _visible


# ============================================================================
# Disegno (stile "Hurry Up!" senza lampeggio: pulsazione lenta + gocce)
# ============================================================================

func _on_draw() -> void:
        var ci: Control = _painter
        var font: Font = ThemeDB.fallback_font
        if font == null:
                return
        var vp: Vector2 = ci.get_viewport_rect().size
        if vp.x <= 1.0 or vp.y <= 1.0:
                return

        # --- Fondale: nero pieno (era lo "schermo nero" — ora fa da tela) ---
        ci.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.02, 0.01, 0.02, 1.0), true)
        # Vignettatura leggera per non lasciare il nero "piatto".
        var vg: float = minf(vp.x, vp.y) * 0.55
        for i in 3:
                var k: float = 1.0 - float(i) * 0.28
                ci.draw_rect(Rect2(Vector2(vp.x * 0.5 - vg * k, vp.y * 0.5 - vg * k),
                                Vector2(vg * 2.0 * k, vg * 2.0 * k)),
                        Color(0.10, 0.0, 0.0, 0.05), false, 3.0)

        # --- Testo localizzato ("Loading..." / "Caricamento...") ---
        var txt: String = "Loading..."
        if I18n:
                txt = I18n.t("loading")
        # Pulsazione lenta (SEMPRE visibile: niente blink on/off).
        var alpha: float = 0.84 + 0.16 * sin(_time * 2.3)
        # Tremolio orror ±1px (come Hurry Up).
        var shiver_x: float = sin(_time * 31.0) * 1.1 * alpha
        var shiver_y: float = cos(_time * 24.0) * 0.7 * alpha

        var text_size: Vector2 = font.get_string_size(txt,
                        HORIZONTAL_ALIGNMENT_LEFT, -1, LOAD_FONT_SIZE)
        var x0: float = vp.x * 0.5 - text_size.x * 0.5 + shiver_x
        var baseline: float = vp.y * LOAD_CENTER_Y_FRAC + text_size.y * 0.5 + shiver_y

        # Alalone scuro dietro il testo (sangue che trasuda).
        ci.draw_rect(Rect2(x0 - 30.0, baseline - LOAD_FONT_SIZE - 16.0,
                        text_size.x + 60.0, LOAD_FONT_SIZE + 36.0),
                Color(0.28, 0.0, 0.0, 0.16 * alpha), true)
        ci.draw_rect(Rect2(x0 - 22.0, baseline - LOAD_FONT_SIZE - 9.0,
                        text_size.x + 44.0, LOAD_FONT_SIZE + 22.0),
                Color(0.34, 0.0, 0.0, 0.14 * alpha), true)

        # Gocce di sangue deterministiche sotto la baseline.
        for i in DRIP_T.size():
                var drip_x: float = x0 + text_size.x * DRIP_T[i]
                var ct: float = fmod(_time + DRIP_PHASE[i], DRIP_CYCLE)
                var max_len: float = 20.0 + 15.0 * (0.5 + 0.5 * sin(float(i) * 2.7))
                var blood: Color = Color(0.62, 0.02, 0.02, alpha)
                var blood_dark: Color = Color(0.38, 0.0, 0.0, alpha)
                if ct < 1.6:
                        # fase 1: la goccia cresce pendendo dalla lettera.
                        var len: float = max_len * (ct / 1.6)
                        ci.draw_rect(Rect2(drip_x - 2.3, baseline + 2.0, 4.6, len),
                                blood, true)
                        ci.draw_circle(Vector2(drip_x, baseline + 2.0 + len), 3.1, blood)
                else:
                        # fase 2: si stacca e cade, il residuo si accorcia.
                        var ft: float = (ct - 1.6) / (DRIP_CYCLE - 1.6)
                        var resid: float = max_len * (1.0 - ft * 0.55)
                        ci.draw_rect(Rect2(drip_x - 2.3, baseline + 2.0, 4.6, resid),
                                blood_dark, true)
                        var drop_y: float = baseline + 2.0 + resid + ft * ft * 66.0
                        var drop_alpha: float = (1.0 - ft) * alpha
                        ci.draw_circle(Vector2(drip_x, drop_y), 3.5,
                                Color(0.62, 0.02, 0.02, drop_alpha))
                        if ft > 0.15:
                                ci.draw_rect(Rect2(drip_x - 1.4, drop_y - 9.0, 2.8, 7.0),
                                        Color(0.55, 0.02, 0.02, drop_alpha * 0.55), true)

        # Testo: ombra scura sotto + passata sangue + riflesso bagnato.
        ci.draw_string(font, Vector2(x0 + 3.0, baseline + 3.0), txt,
                        HORIZONTAL_ALIGNMENT_LEFT, -1, LOAD_FONT_SIZE,
                        Color(0.16, 0.0, 0.0, 0.85 * alpha))
        ci.draw_string(font, Vector2(x0, baseline), txt,
                        HORIZONTAL_ALIGNMENT_LEFT, -1, LOAD_FONT_SIZE,
                        Color(0.72, 0.03, 0.03, alpha))
        ci.draw_string(font, Vector2(x0, baseline - 1.5), txt,
                        HORIZONTAL_ALIGNMENT_LEFT, -1, LOAD_FONT_SIZE,
                        Color(0.85, 0.10, 0.08, 0.32 * alpha))
