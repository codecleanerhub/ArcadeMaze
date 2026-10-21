## MazeLightWaveEffect.gd — TASK 38 (onda di luce delle pergamene).
##
## BAGLIORE CHE SI DIFFONDE PER TUTTO IL LABIRINTO dopo il fulmine:
## un'ondata di luce che NASCE dal punto in cui la saetta colpisce il
## pavimento e si estende per TUTTA la dimensione del labirinto, come
## un'esplosione di luce che investe corridoi, muri e oggetti al suo
## passaggio.
##
## Tre fasi (durata totale ~1.62s, si incastra nel tuono lungo da 1.9s
## dello SCROLL_LIGHTNING del Task 36):
##   1. DELAY (~120ms): il fulmine sta ancora colpendo (la saetta vive
##      in LightningStrikeEffect): il lampo viene PRIMA, il bagliore DOPO;
##   2. WAVE (~1150ms): fronte luminoso ad anello che si espande dal
##      punto d'impatto fino all'angolo piu' lontano del labirinto
##      (ease-out: esplosione violenta che decelera verso i bordi), con
##      scia di bagliore alle spalle a gradiente, secondo fronte in
##      ritardo e riflesso pulsante sull'impatto;
##   3. FADE (~350ms): la luce che ha riempito il labirinto si spegne
##      dolcemente (bagliore ambientale su tutta l'area).
##
## MATERIALE ADDITIVO (CanvasItemMaterial BLEND_MODE_ADD): l'onda non
## copre il labirinto, lo ILLUMINA davvero — la luce si somma a pavimento,
## muri e hazard man mano che il fronte li attraversa.
##
## L'onda e' TINTA col colore della pergamena (arancio fuoco per il
## terremoto, viola psichico per le voragini) con fronte bianco-caldo.
##
## Pattern LightningStrikeEffect: PROCESS_MODE_PAUSABLE, z_index 45
## (sotto la saetta 46, sotto HUD), autodistruzione a fine durata.
extends Node2D

## Ritardo rispetto all'impatto: prima il LAMPO, poi l'ONDATA.
const DELAY_MS: float = 120.0
## Espansione del fronte luminoso fino al raggio massimo.
const WAVE_MS: float = 1150.0
## Dissolvenza del bagliore che ha riempito il labirinto.
const FADE_MS: float = 350.0
const DURATION_MS: float = DELAY_MS + WAVE_MS + FADE_MS

var _tint: Color = Color(1.0, 0.62, 0.22)
var _max_radius: float = 1150.0
var _life_ms: float = DURATION_MS
var _t: float = 0.0


## `impact_pos`: coordinate MONDO del punto in cui il fulmine colpisce
## il pavimento (la pergamena). `tint`: colore della pergamena.
## `max_radius`: distanza dal punto d'impatto all'angolo piu' lontano
## del labirinto (+ margine), calcolata dal MainGameController: l'onda
## copre TUTTA la dimensione del labirinto, qualunque sia la cella.
func setup(impact_pos: Vector2, tint: Color, max_radius: float) -> void:
        position = impact_pos
        _tint = tint
        _max_radius = maxf(400.0, max_radius)


func _ready() -> void:
        z_index = 45
        process_mode = Node.PROCESS_MODE_PAUSABLE
        # MATERIALE ADDITIVO: la luce si SOMMA alla scena sotto di lei
        # (vero effetto "esplosione di luce" sul labirinto disegnato).
        var mat := CanvasItemMaterial.new()
        mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
        material = mat


func _process(delta: float) -> void:
        _t += delta
        _life_ms -= delta * 1000.0
        if _life_ms <= 0.0:
                queue_free()
                return
        queue_redraw()


func _draw() -> void:
        var elapsed: float = DURATION_MS - _life_ms
        if elapsed < DELAY_MS:
                return  # fase 1: il fulmine sta ancora colpendo
        # fase 2: espansione dell'ondata (0 -> 1)
        var wave_t: float = clampf((elapsed - DELAY_MS) / WAVE_MS, 0.0, 1.0)
        # ease-out: esplosione violenta alla nascita che decelera
        var eased: float = 1.0 - pow(1.0 - wave_t, 2.2)
        var front: float = _max_radius * eased
        # fase 3: dissolvenza del bagliore che ha riempito il labirinto
        var fade: float = 1.0
        if wave_t >= 1.0:
                fade = clampf(_life_ms / FADE_MS, 0.0, 1.0)
        # flicker sottile del fronte (la luce "vive")
        var flick: float = 0.88 + 0.12 * sin(_t * 27.0)

        # --- 1) scia di bagliore alle spalle del fronte -----------------
        # Bande anulari concentriche con alpha a decadimento geometrico:
        # gradiente radiale LUMINOSO AL FRONTE che si raffredda verso il
        # punto d'impatto, e che si spegne lentamente mentre l'onda corre.
        var bands: int = 7
        for i in bands:
                var rr: float = front * (1.0 - 0.065 * float(i))
                var band_w: float = front * 0.065 + 5.0
                var band_a: float = 0.16 * pow(0.70, float(i)) \
                                * (1.0 - 0.45 * wave_t) * fade
                draw_arc(Vector2.ZERO, maxf(4.0, rr), 0.0, TAU, 128,
                        Color(_tint.r, _tint.g, _tint.b, band_a), band_w)

        # --- 1b) bagliore residuo sull'area gia' spazzata ----------------
        # La luce non e' solo il fronte: tutto cio' che l'ondata ha gia'
        # investito resta immerso in un bagliore tenue che si raffredda
        # mentre l'onda corre verso i bordi del labirinto.
        if front > 8.0:
                draw_circle(Vector2.ZERO, front * 0.985,
                        Color(_tint.r, _tint.g, _tint.b,
                                0.045 * (1.0 - 0.35 * wave_t) * fade))

        # --- 2) fronte luminoso (il cuore dell'ondata) ------------------
        # alone largo tinto
        draw_arc(Vector2.ZERO, front, 0.0, TAU, 128,
                Color(_tint.r, _tint.g, _tint.b, 0.55 * flick * fade), 16.0)
        # tratto intermedio pallido
        draw_arc(Vector2.ZERO, front, 0.0, TAU, 128,
                Color(0.88, 0.92, 1.0, 0.45 * flick * fade), 7.0)
        # core bianco-caldo
        draw_arc(Vector2.ZERO, front, 0.0, TAU, 128,
                Color(1.0, 1.0, 1.0, 0.80 * flick * fade), 3.0)
        # secondo fronte in ritardo (profondita' dell'esplosione)
        if front > 40.0:
                draw_arc(Vector2.ZERO, front * 0.87, 0.0, TAU, 128,
                        Color(_tint.r, _tint.g, _tint.b, 0.22 * fade), 5.0)

        # --- 3) riflesso pulsante sul punto d'impatto --------------------
        # La sorgente resta calda mentre l'onda corre via.
        var core_a: float = (1.0 - wave_t) * fade
        if core_a > 0.01:
                for i in 4:
                        var glow_r: float = (44.0 - 8.0 * float(i)) \
                                        + 7.0 * sin(_t * 9.0 + float(i))
                        draw_circle(Vector2.ZERO, glow_r,
                                Color(_tint.r, _tint.g, _tint.b, 0.11 * core_a))
                draw_circle(Vector2.ZERO, 10.0,
                        Color(1.0, 1.0, 1.0, 0.45 * core_a))

        # --- 4) bagliore ambientale di fine corsa ------------------------
        # L'onda ha raggiunto i bordi: per un attimo TUTTO il labirinto
        # resta immerso nella luce, poi si spegne dolcemente.
        if wave_t >= 1.0:
                draw_circle(Vector2.ZERO, _max_radius,
                        Color(_tint.r, _tint.g, _tint.b, 0.055 * fade))
                draw_circle(Vector2.ZERO, _max_radius * 0.82,
                        Color(_tint.r, _tint.g, _tint.b, 0.040 * fade))
                draw_circle(Vector2.ZERO, _max_radius * 0.60,
                        Color(1.0, 0.97, 0.90, 0.030 * fade))
