## LoadingScreen.gd - Autoload "LoadingScreen": overlay "Loading..." con il
## sangue SOLO sui 3 puntini (TASK 45 - richiesta utente: ogni puntino e'
## una goccia di sangue sgocciolante REALISTICA, forma a goccia pendente,
## NIENTE tubi/rettangoli; le lettere restano pulite, in osso invecchiato).
##
## COPRE tutte le attese che prima erano SCHERMO NERO:
##   * BOOT: l'autoload si mostra da subito; si nasconde da solo dopo 3 frame
##     renderizzati (la fase engine/autoload e' coperta dal boot_splash PNG
##     rigenerato nello stesso stile, vedi project.godot).
##   * TRANSIZIONI DI SCENA: GameManager.change_scene() chiama show_loading()
##     prima di change_scene_to_file(); l'overlay resta sopra la scena nuova
##     finche' non sono passati 3 frame renderizzati.
##
## STILE (TASK 45, ridefinizione dell'idea del TASK 44):
##   * TESTO: "Loading" / "Caricamento" in osso chiaro invecchiato (testo
##     pre-renderizzato 4x da scripts/gen_loading_blood.py con grunge,
##     venature e ombra di contatto cotta) - NESSUN sangue sulle lettere.
##   * PUNTINI: al posto dei 3 punti sospensione, 3 GOCCE di sangue
##     photorealistiche (asset PIL: morph a 8 frame da puntino-calotta a
##     goccia pendente con collo concavo, shading radiale limb-darkening,
##     speculare a sinistra, glow subsurface ambra sul bordo inferiore).
##     Ogni goccia: cresce -> si allunga pre-distacco -> si stacca e cade
##     (accelerata, si schiaccia verticalmente, sfuma) -> resta un residuo
##     bagnato che si asciuga + una scia bagnata che si ritira.
##   * Le 3 gocce sono SFALSATE a cascata (sinistra guida). Tutto
##     DETERMINISTICO: nessun random, fase resettata a ogni show_loading()
##     (partiamo da ANIM_T_START = istante "ricco" con caduta in corso, cosi'
##     anche un singolo frame congelato mostra la scena migliore).
##   * Tremolio orror +-1px e lenta pulsazione di luminosita' (mai blink:
##     la scritta di caricamento deve restare LEGGIBILE).
##
## FALLBACK: se gli asset PNG mancano, testo osseo col font di sistema +
## gocce vettoriali (poligoni a goccia: comunque MAI rettangoli).
extends Node

## Frame renderizzati dopo i quali l'overlay si auto-nasconde (modalita'
## automatica: scene change / boot). 3 frame = la nuova scena e' gia' comparsa
## dietro l'overlay per almeno un frame intero.
const AUTO_HIDE_FRAMES: int = 3

## TASK 50 (scritta animata): al BOOT l'overlay resta visibile per questo
## tempo (secondi) invece di 3 frame — prima l'utente vedeva quasi solo il
## boot_splash PNG statico; ora vede il ciclo completo (sweep luminoso sul
## testo + gocce che crescono/cadono) prima del menu.
const BOOT_HOLD_S: float = 2.2

## TASK 50: banda di luce che percorre le lettere (periodo e larghezza in
## frazione dell'ink del testo).
const SWEEP_PERIOD: float = 2.6
const SWEEP_SIGMA: float = 0.16   # larghezza gaussiana (frazione ink_w)
const SWEEP_SLICES: int = 26
const SWEEP_AMP: float = 0.85      # spinta luminosa massima in testa alla banda

const LOAD_FONT_SIZE: int = 64
const LOAD_CENTER_Y_FRAC: float = 0.44   # centro verticale del blocco testo

# --- Asset sangue (generati da scripts/gen_loading_blood.py, commit accanto) ---
const ASSET_DIR: String = "res://assets/loading/"

# --- Timing del ciclo di ogni puntino-goccia (deterministico) ---
const DROP_CYCLE: float = 3.0                    # durata ciclo (s)
const DROP_LEAD: Array[float] = [0.62, 0.31, 0.0]  # sfalsamento cascata
const GROW_FRAC: float = 0.62                    # frazione del ciclo: crescita
const ANIM_T_START: float = 1.52                 # fase iniziale "ricca"
const FALL_TIME: float = 0.62                    # durata caduta (s)
const FALL_TRAVEL: float = 250.0                 # px di caduta (accelerata)
const TRAIL_FADE: float = 0.95                   # vita scia bagnata (s)
const RESIDUE_SHRINK: float = 0.38               # asciugatura del residuo

# --- TASK 51 (P6): gocce PIXELLAB (frame recuperati) — ciclo FORMA ->
# SI ALLUNGA -> SI RITIRA senza cadere (specifiche utente). I 6 frame
# del character "arcade-blood-drop" forniscono la qualita' pittorica
# (bagnato, speculare, subsurface); il codice AMPLIFICA il ciclo perche'
# il respiro nativo dei frame e' sottile (~5%): scala di formazione +
# stretch verticale in elongazione + rientro in retrazione.
const PL_CYCLE: float = 2.4                      # durata ciclo PixelLab (s)
const PL_LEAD: Array[float] = [0.0, 0.80, 1.60]  # cascata sfalsata
const PL_DISP_H: float = 58.0                    # altezza display (px)
const PL_DISP_W: float = 36.0                    # larghezza display (px)

var _canvas: CanvasLayer
var _painter: Control
var _visible: bool = false
var _auto_hide: bool = true
var _frames_since_show: int = 0
var _anim_t: float = 0.0
var _meta: Dictionary = {}
var _tex_text: Dictionary = {}
var _tex_grow: Array[Texture2D] = []
var _tex_fall: Texture2D = null
var _tex_residue: Texture2D = null
var _tex_trail: Texture2D = null
# TASK 51 (P6): frame PixelLab del blood-drop (6, drip-cycle)
var _tex_pl: Array[Texture2D] = []
var _pl_meta: Dictionary = {}
# diagnostica screenshot (congela l'animazione per catture deterministiche)
var _dbg_freeze: bool = false
# TASK 50: tempo residuo di visibilita' forzata al boot
var _boot_hold_left: float = 0.0


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
        _load_assets()
        # BOOT: mostrati per BOOT_HOLD_S (TASK 50: la scritta animata deve
        # essere VISTA — 3 frame non bastavano); il primo frame utile del menu
        # appare sotto l'overlay e dopo il hold si dissolve nel menu vivo.
        _boot_hold_left = BOOT_HOLD_S
        show_loading(false)


func _process(delta: float) -> void:
        if not _dbg_freeze:
                _anim_t += delta
        if not _visible:
                return
        _frames_since_show += 1
        if _auto_hide and _frames_since_show >= AUTO_HIDE_FRAMES:
                hide_loading()
                return
        # TASK 50: hold del boot — l'overlay resta finche' il timer non scade.
        if _boot_hold_left > 0.0:
                _boot_hold_left -= delta
                if _boot_hold_left <= 0.0:
                        _boot_hold_left = 0.0
                        hide_loading()
                        return
        _painter.queue_redraw()


# ============================================================================
# API pubblica
# ============================================================================

## Mostra l'overlay. `auto_hide` = true (default) lo nasconde da solo dopo
## AUTO_HIDE_FRAMES frame renderizzati (per scene change e boot); false lo
## mantiene finche' il chiamante non chiama hide_loading().
## L'animazione delle gocce riparte SEMPRE dalla stessa fase (determinismo).
func show_loading(auto_hide: bool = true) -> void:
        _visible = true
        _auto_hide = auto_hide
        _frames_since_show = 0
        _anim_t = ANIM_T_START
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


## True se gli asset sangue/osso del TASK 45 sono caricati (usato dai test).
## TASK 51: pronti anche con i soli frame PixelLab (P6).
func assets_ready() -> bool:
        var old_ok: bool = not _tex_text.is_empty() and _tex_grow.size() >= 2 \
                        and _tex_fall != null and _tex_trail != null \
                        and _tex_residue != null
        return old_ok or (_tex_pl.size() >= 6 and not _tex_text.is_empty())


## Il dizionario loading_meta.json (vuoto se gli asset mancano) - per i test.
func get_meta_json() -> Dictionary:
        return _meta


## Tempo di animazione corrente (diagnostica screenshot; NON usato dal gioco).
func get_anim_t() -> float:
        return _anim_t


## Forza un redraw del painter (diagnostica screenshot).
func force_redraw() -> void:
        if _painter:
                _painter.queue_redraw()


## Diagnostica screenshot: sblocca l'animazione (congela a `anim_t`) e ridisegna.
func set_anim_t_debug(v: float) -> void:
        _anim_t = v
        _dbg_freeze = true
        if _painter:
                _painter.queue_redraw()


## TASK 50: gli SCREENSHOT TEST catturano nei primi secondi — l'hold del
## boot coprirebbe la scena con l'overlay. Chiamato dai test nel _ready.
func skip_boot_hold() -> void:
        _boot_hold_left = 0.0
        hide_loading()


## Diagnostica screenshot: sblocca l'avanzamento dell'animazione.
func unset_anim_t_debug() -> void:
        _dbg_freeze = false


# ============================================================================
# Caricamento asset (pattern Collectibles: Image.load, NESSUN import)
# ============================================================================

func _load_assets() -> void:
        var meta_path: String = ProjectSettings.globalize_path(
                        ASSET_DIR + "loading_meta.json")
        if not FileAccess.file_exists(meta_path):
                return
        var f: FileAccess = FileAccess.open(meta_path, FileAccess.READ)
        if f == null:
                return
        var parsed: Variant = JSON.parse_string(f.get_as_text())
        if typeof(parsed) != TYPE_DICTIONARY:
                return
        _meta = parsed
        var texts: Dictionary = _meta.get("texts", {})
        for key in texts.keys():
                var entry: Dictionary = texts[key]
                var tex: Texture2D = _load_png(
                                ASSET_DIR + String(entry.get("file", "")))
                if tex != null:
                        _tex_text[key] = tex
        var frames: int = int(_meta.get("hang_frames", 0))
        for i in frames:
                var ft: Texture2D = _load_png(
                                ASSET_DIR + "drop_hang_%d.png" % i)
                if ft != null:
                        _tex_grow.append(ft)
        _tex_fall = _load_png(ASSET_DIR + "drop_fall.png")
        _tex_residue = _load_png(ASSET_DIR + "drop_residue.png")
        _tex_trail = _load_png(ASSET_DIR + "drop_trail.png")
        # TASK 51 (P6): frame PixelLab blood-drop (drip-cycle 6 frame)
        var pl_meta_path: String = ProjectSettings.globalize_path(
                        ASSET_DIR + "drop_pl_meta.json")
        if FileAccess.file_exists(pl_meta_path):
                var pf: FileAccess = FileAccess.open(pl_meta_path, FileAccess.READ)
                if pf != null:
                        var pp: Variant = JSON.parse_string(pf.get_as_text())
                        if typeof(pp) == TYPE_DICTIONARY:
                                _pl_meta = pp
                                for i in int(pp.get("count", 6)):
                                        var ft: Texture2D = _load_png(
                                                        ASSET_DIR + "drop_pl_%d.png" % i)
                                        if ft != null:
                                                _tex_pl.append(ft)


func _load_png(path: String) -> Texture2D:
        var abs_path: String = ProjectSettings.globalize_path(path)
        if not FileAccess.file_exists(abs_path):
                return null
        var img: Image = Image.new()
        if img.load(abs_path) != OK:
                return null
        return ImageTexture.create_from_image(img)


# ============================================================================
# Disegno: testo osseo pulito + 3 gocce di sangue animate
# ============================================================================

func _on_draw() -> void:
        var ci: Control = _painter
        var vp: Vector2 = ci.get_viewport_rect().size
        if vp.x <= 1.0 or vp.y <= 1.0:
                return

        # --- Fondale: nero pieno (era lo "schermo nero" - ora fa da tela) ---
        ci.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.02, 0.01, 0.02, 1.0), true)
        # Vignettatura neutra leggera (niente alone rosso: il sangue e'
        # SOLO sui puntini).
        var vg: float = minf(vp.x, vp.y) * 0.55
        for i in 3:
                var k: float = 1.0 - float(i) * 0.28
                ci.draw_rect(Rect2(Vector2(vp.x * 0.5 - vg * k, vp.y * 0.5 - vg * k),
                                Vector2(vg * 2.0 * k, vg * 2.0 * k)),
                        Color(0.05, 0.03, 0.04, 0.06), false, 3.0)

        # --- Testo localizzato SENZA puntini (base = "Loading"/"Caricamento") ---
        var txt: String = "Loading..."
        if I18n:
                txt = I18n.t("loading")
        var base: String = txt.trim_suffix("...")
        # Pulsazione lenta (SEMPRE visibile: niente blink on/off).
        var alpha: float = 0.88 + 0.12 * sin(_anim_t * 1.9)
        # Tremolio orror +-1px.
        var shiver_x: float = sin(_anim_t * 31.0) * 1.1 * alpha
        var shiver_y: float = cos(_anim_t * 24.0) * 0.7 * alpha
        var baseline: float = vp.y * LOAD_CENTER_Y_FRAC \
                        + LOAD_FONT_SIZE * 0.30 + shiver_y

        var tex: Texture2D = _tex_text.get(base)
        if tex != null and not _meta.is_empty() \
                        and _meta.get("texts", {}).has(base):
                # --- Modalita' asset: testo osseo 4x + gocce reali ---
                var tm: Dictionary = _meta["texts"][base]
                var dot_adv: float = float(_meta.get("dot_advance", 22.0))
                var gap: float = float(_meta.get("gap", 12.0))
                var period_h: float = float(_meta.get("period_h", 12.0))
                var ink_w: float = float(tm.get("ink_w", 0.0))
                var total_w: float = ink_w + gap + 3.0 * dot_adv
                var x0: float = vp.x * 0.5 - total_w * 0.5 + shiver_x
                # texture 4x disegnata a scala 1/4 (nitida, LANCZOS-like)
                var tw: float = float(tm.get("w4", 1)) * 0.25
                var th: float = float(tm.get("h4", 1)) * 0.25
                var tpos: Vector2 = Vector2(
                                x0 - float(tm.get("ink_x", 0.0)),
                                baseline - float(tm.get("baseline", 0.0)))
                ci.draw_texture_rect(tex, Rect2(tpos, Vector2(tw, th)), false,
                                Color(1.0, 1.0, 1.0, alpha))
                # --- TASK 50: SWEEP luminoso che percorre le lettere ---
                # Ridisegna il testo a FETTE verticali con una spinta di
                # luminosita' gaussiana centrata sulla banda in movimento:
                # effetto "luce che sfiora l'osso" percettibile ma sobrio.
                var sweep_x: float = fposmod(_anim_t / SWEEP_PERIOD, 1.0) \
                                * (ink_w * 1.3) - ink_w * 0.15
                var slice_w: float = ink_w / float(SWEEP_SLICES)
                var tex_scale: float = 4.0  # asset 4x disegnati a scala 1/4
                for s in SWEEP_SLICES:
                        var sx_c: float = x0 + (float(s) + 0.5) * slice_w
                        var d: float = (sx_c - x0 - sweep_x) / (ink_w * SWEEP_SIGMA)
                        var boost: float = SWEEP_AMP * exp(-d * d)
                        if boost < 0.04:
                                continue
                        var srect := Rect2(
                                        Vector2((x0 + float(s) * slice_w - tpos.x) * tex_scale, 0.0),
                                        Vector2(slice_w * tex_scale + 1.0, th * tex_scale))
                        ci.draw_texture_rect_region(tex,
                                        Rect2(Vector2(x0 + float(s) * slice_w, tpos.y),
                                                Vector2(slice_w + 1.0, th)),
                                        srect,
                                        Color(1.0 + boost, 1.0 + boost * 0.92,
                                                        1.0 + boost * 0.80, alpha * 0.95))
                for i in 3:
                        var dx: float = x0 + ink_w + gap \
                                        + dot_adv * (float(i) + 0.5)
                        if _tex_pl.size() >= 6:
                                # TASK 51 (P6): gocce PIXELLAB — forma, si
                                # allunga, si ritira (senza cadere)
                                _draw_blood_dot_pl(ci, dx, baseline - period_h,
                                                i, alpha)
                        else:
                                _draw_blood_dot(ci, dx, baseline - period_h, i, alpha)
        else:
                _draw_fallback(ci, base, vp, baseline, alpha, shiver_x)


## Disegna un puntino-goccia nella fase corrente del suo ciclo.
## Cresce (morph 8 frame in crossfade + stretch pre-distacco), poi si stacca:
## caduta accelerata con scia e residuo bagnato che si asciuga.
func _draw_blood_dot(ci: Control, dx: float, attach_y: float, idx: int,
                alpha: float) -> void:
        # NB: fposmod e NON posmod: in Godot 4.7.2 posmod TRONCA a intero
        # anche con argomenti float (verificato con probe: posmod(2.31, 3.0)
        # restituisce 2) -> le fasi delle gocce saltavano a gradini interi.
        var phase: float = fposmod(_anim_t + DROP_LEAD[idx], DROP_CYCLE)
        var grow_dur: float = DROP_CYCLE * GROW_FRAC
        var hang_size: Array = _meta.get("hang_size", [48, 50])
        var hw: float = float(hang_size[0])
        var hh: float = float(hang_size[1])
        var hang_att: Array = _meta.get("hang_attach", [24.0, 2.0])
        var hax: float = float(hang_att[0])
        var hay: float = float(hang_att[1])

        if phase <= grow_dur:
                # ---- FASE CRESCITA: puntino -> goccia pendente ----
                var n: int = _tex_grow.size()
                if n <= 0:
                        return
                var gt: float = phase / grow_dur
                var fpos: float = gt * (n - 1)
                var i0: int = int(fpos)
                var i1: int = mini(i0 + 1, n - 1)
                var w: float = fpos - float(i0)
                # pre-distacco: la goccia si allunga sotto il peso
                var sy: float = 1.0
                if gt > 0.94:
                        sy = 1.0 + 0.14 * (gt - 0.94) / 0.06
                var rect: Rect2 = Rect2(Vector2(dx - hax, attach_y - hay),
                                Vector2(hw, hh * sy))
                if i0 == i1 or w <= 0.001:
                        _blit(ci, _tex_grow[i0], rect, alpha)
                else:
                        _blit(ci, _tex_grow[i0], rect, (1.0 - w) * alpha)
                        _blit(ci, _tex_grow[i1], rect, w * alpha)
                return

        # ---- FASE DISTACCO + CADUTA ----
        var tf: float = phase - grow_dur
        # residuo bagnato che si asciuga (resta fino al prossimo ciclo)
        if _tex_residue != null:
                var res_size: Array = _meta.get("residue_size", [28, 16])
                var res_att: Array = _meta.get("residue_attach", [14.0, 2.0])
                var rw: float = float(res_size[0])
                var rh: float = float(res_size[1])
                var rax: float = float(res_att[0])
                var ray: float = float(res_att[1])
                var s: float = 1.0 - RESIDUE_SHRINK * clampf(tf / 0.9, 0.0, 1.0)
                _blit(ci, _tex_residue,
                                Rect2(Vector2(dx - rax * s, attach_y - ray),
                                                Vector2(rw * s, rh)), alpha)
        # scia bagnata che si ritira verso l'alto
        if _tex_trail != null and tf < TRAIL_FADE:
                var tr_size: Array = _meta.get("trail_size", [12, 140])
                var tr_att: Array = _meta.get("trail_attach", [6.0, 1.0])
                var twd: float = float(tr_size[0])
                var tht: float = float(tr_size[1])
                var tax: float = float(tr_att[0])
                var k: float = tf / TRAIL_FADE
                var trail_len: float = tht * (1.0 - 0.45 * k)
                _blit(ci, _tex_trail,
                                Rect2(Vector2(dx - tax, attach_y + 1.0),
                                                Vector2(twd, trail_len)),
                                (1.0 - k) * alpha)
        # goccia in caduta: accelerata, si schiaccia verticalmente, sfuma
        if _tex_fall != null and tf < FALL_TIME:
                var fall_size: Array = _meta.get("fall_size", [40, 44])
                var fall_c: Array = _meta.get("fall_c", [20.0, 25.0])
                var fw: float = float(fall_size[0])
                var fh: float = float(fall_size[1])
                var fcx: float = float(fall_c[0])
                var fcy: float = float(fall_c[1])
                var prog: float = (tf / FALL_TIME) * (tf / FALL_TIME)
                var af: float = 1.0 - clampf((prog - 0.55) / 0.45, 0.0, 1.0)
                var syf: float = 1.0 + 0.20 * prog
                var fy: float = attach_y + 30.0 + FALL_TRAVEL * prog
                _blit(ci, _tex_fall,
                                Rect2(Vector2(dx - fcx, fy - fcy * syf),
                                                Vector2(fw, fh * syf)),
                                af * alpha)


func _blit(ci: Control, tex: Texture2D, rect: Rect2, alpha: float) -> void:
        if tex == null or alpha <= 0.01:
                return
        ci.draw_texture_rect(tex, rect, false, Color(1.0, 1.0, 1.0, alpha))


# ============================================================================
# TASK 51 (P6) — puntino-goccia PIXELLAB: FORMA -> SI ALLUNGA -> SI RITIRA
# ============================================================================
## Ciclo chiuso senza distacco (richiesta utente: "le gocce si formano, si
## allungano e si ritirano senza cadere"). I 6 frame del character
## blood-drop vengono percorsi in PING-PONG (0..5..0) in crossfade; il
## codice amplifica il movimento: crescita in scala durante la formazione,
## stretch verticale 1.30x nell'allungamento, rientro morbido in
## retrazione. La sommita' resta ANCORATA alla baseline del testo.
func _draw_blood_dot_pl(ci: Control, dx: float, attach_y: float, idx: int,
                alpha: float) -> void:
        var phase: float = fposmod(_anim_t + PL_LEAD[idx], PL_CYCLE)
        var t: float = phase / PL_CYCLE
        # --- profilo del ciclo ---
        var scale_xy: float = 1.0   # scala complessiva (formazione)
        var stretch_y: float = 1.0  # allungamento verticale
        if t < 0.40:
                # FORMA: da puntino bagnato a goccia piena (ease-out morbido)
                var k: float = t / 0.40
                scale_xy = 0.30 + 0.70 * (1.0 - pow(1.0 - k, 2.2))
        elif t < 0.72:
                # SI ALLUNGA: la massa scende, il collo si assottiglia
                var k: float = (t - 0.40) / 0.32
                stretch_y = 1.0 + 0.30 * sin(k * PI * 0.5)
                scale_xy = 1.0 - 0.08 * k
        else:
                # SI RITIRA: rientro veloce all'inizio, atterraggio morbido
                var k: float = (t - 0.72) / 0.28
                stretch_y = 1.30 - 0.36 * (1.0 - pow(1.0 - k, 2.4))
                scale_xy = 0.92 - 0.24 * k
        # fade-in rapido a inizio ciclo (la goccia si materializza)
        var a: float = alpha
        if t < 0.06:
                a *= t / 0.06
        # --- frame ping-pong 0..5..0 in crossfade ---
        var n: int = _tex_pl.size()
        var fposv: float = pingpong(t * float(n * 2 - 2), float(n - 1))
        var i0: int = clampi(int(fposv), 0, n - 1)
        var i1: int = clampi(i0 + (1 if fposv > float(i0) else -1), 0, n - 1)
        var w: float = fposv - float(i0)
        w = absf(w)
        # --- disegno: TOP ancorato ad attach_y ---
        var dw: float = PL_DISP_W * scale_xy
        var dh: float = PL_DISP_H * scale_xy * stretch_y
        var rect: Rect2 = Rect2(dx - dw * 0.5, attach_y, dw, dh)
        if i0 == i1 or w <= 0.001:
                _blit(ci, _tex_pl[i0], rect, a)
        else:
                _blit(ci, _tex_pl[i0], rect, (1.0 - w) * a)
                _blit(ci, _tex_pl[i1], rect, w * a)
        # puntino bagnato all'ancora (la goccia "nasce" da qui)
        ci.draw_circle(Vector2(dx, attach_y + 1.0), 2.6,
                        Color(0.45, 0.05, 0.04, 0.55 * a))


# ============================================================================
# Fallback vettoriale (asset mancanti): comunque NIENTE rettangoli
# ============================================================================

func _draw_fallback(ci: Control, base: String, vp: Vector2, baseline: float,
                alpha: float, shiver_x: float) -> void:
        var font: Font = ThemeDB.fallback_font
        if font == null:
                return
        var text_size: Vector2 = font.get_string_size(base,
                        HORIZONTAL_ALIGNMENT_LEFT, -1, LOAD_FONT_SIZE)
        var dot_adv: float = LOAD_FONT_SIZE * 0.35
        var total_w: float = text_size.x + dot_adv * 3.0
        var x0: float = vp.x * 0.5 - total_w * 0.5 + shiver_x
        ci.draw_string(font, Vector2(x0 + 2.5, baseline + 3.0), base,
                        HORIZONTAL_ALIGNMENT_LEFT, -1, LOAD_FONT_SIZE,
                        Color(0.05, 0.03, 0.03, 0.8 * alpha))
        ci.draw_string(font, Vector2(x0, baseline), base,
                        HORIZONTAL_ALIGNMENT_LEFT, -1, LOAD_FONT_SIZE,
                        Color(0.86, 0.81, 0.70, alpha))
        ci.draw_string(font, Vector2(x0, baseline - 1.5), base,
                        HORIZONTAL_ALIGNMENT_LEFT, -1, LOAD_FONT_SIZE,
                        Color(0.95, 0.92, 0.84, 0.35 * alpha))
        for i in 3:
                var dx: float = x0 + text_size.x + dot_adv * (float(i) + 0.5)
                _draw_vector_drop(ci, dx, baseline - LOAD_FONT_SIZE * 0.18,
                                i, alpha)


## Goccia vettoriale semplice (solo emergenza): poligono a goccia pendente.
func _draw_vector_drop(ci: Control, dx: float, attach_y: float, idx: int,
                alpha: float) -> void:
        var phase: float = fposmod(_anim_t + DROP_LEAD[idx], DROP_CYCLE)
        var grow_dur: float = DROP_CYCLE * GROW_FRAC
        var blood: Color = Color(0.62, 0.08, 0.05, alpha)
        var blood_dark: Color = Color(0.35, 0.02, 0.02, alpha)
        if phase <= grow_dur:
                var gt: float = phase / grow_dur
                var r: float = 5.5 + 5.0 * gt
                var l: float = 11.0 + 27.0 * gt * gt
                var pts: PackedVector2Array = PackedVector2Array()
                pts.append(Vector2(dx - r * 0.30, attach_y))
                pts.append(Vector2(dx - r * 0.75, attach_y + l * 0.55))
                pts.append(Vector2(dx - r, attach_y + l))
                var steps: int = 10
                for j in steps + 1:
                        var a: float = PI * float(j) / float(steps)
                        pts.append(Vector2(dx - r * cos(a),
                                        attach_y + l + r * sin(a)))
                pts.append(Vector2(dx + r, attach_y + l))
                pts.append(Vector2(dx + r * 0.75, attach_y + l * 0.55))
                pts.append(Vector2(dx + r * 0.30, attach_y))
                var cols: PackedColorArray = PackedColorArray()
                for j in pts.size():
                        cols.append(blood)
                ci.draw_polygon(pts, cols)
                # speculare
                ci.draw_circle(Vector2(dx - r * 0.35, attach_y + l * 0.62),
                                r * 0.16, Color(0.95, 0.55, 0.45, 0.75 * alpha))
        else:
                var tf: float = phase - grow_dur
                ci.draw_circle(Vector2(dx, attach_y + 5.0), 4.0, blood_dark)
                if tf < FALL_TIME:
                        var prog: float = (tf / FALL_TIME) * (tf / FALL_TIME)
                        var af: float = 1.0 - clampf((prog - 0.55) / 0.45, 0.0, 1.0)
                        ci.draw_circle(Vector2(dx, attach_y + 30.0
                                        + FALL_TRAVEL * prog), 5.5,
                                Color(0.62, 0.08, 0.05, af * alpha))
                        ci.draw_line(Vector2(dx, attach_y + 8.0),
                                        Vector2(dx, attach_y + 24.0),
                                        Color(0.55, 0.06, 0.04, 0.5 * af * alpha), 2.0)
