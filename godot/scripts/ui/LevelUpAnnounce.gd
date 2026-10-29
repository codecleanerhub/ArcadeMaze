## LevelUpAnnounce.gd — TASK 99 (Level Up).
##
## ANNUNCIO NON-BLOCCANTE del level up: il gioco CONTINUA a girare mentre
## il FULMINE PIXEL-LAB bianco-oro (sheet 4 frame levelup_bolt_sheet.png,
## flicker a ~9 fps) si abbatte sulla testa del player che è salito di
## livello, e al centro dello schermo cresce la SCRITTA "LEVEL UP!"
## pixel-font dorato (levelup_title.png, PixelLab) con il livello
## raggiunto e i punti abilità guadagnati.
##
## Sequence (report Task 98 §4.4): soglia superata -> fulmine -> scritta
## ~1.7s -> il gioco va in pausa e si apre la modale abilità.
## L'annuncio è pure-code CanvasLayer (pattern BonusCardOverlay):
##   * layer 27 (sopra HUD 10 e pause 20, sotto il bonus screen 30)
##   * PROCESS_MODE_ALWAYS (gira anche se un altro overlay pausa il tree)
##
## FASE 3 (grafica tutta PixelLab, come richiesto): il vecchio fulmine
## procedurale (LightningStrikeEffect) e la scritta draw_string sono il
## FALLBACK se gli asset mancano; con gli asset presenti l'annuncio usa
## SOLO grafica generata.
##
## In 2P le celebrazioni sono in sequenza (prima P1 poi P2): il
## controller le concatena consumando pending_levelup_fx una alla volta.
extends CanvasLayer

## Emitted when the announcement is over. The host controller frees the
## layer and opens the skills modal for the same player.
signal announcement_done(player_num: int)

const LightningStrikeFx = preload("res://scripts/entities/LightningStrikeEffect.gd")

## Durata totale dell'annuncio (ms): fulmine ~800ms + testo che resta
## in campo il tempo di leggere livello e punti guadagnati.
const DURATION_MS: float = 1700.0
## Durata del fulmine PixelLab (ms) e velocita' del flicker (ms/frame).
const BOLT_MS: float = 800.0
const BOLT_FRAME_MS: float = 110.0
## Pop-in della scritta: parte grande e si assesta (ms).
const TITLE_POP_MS: float = 220.0
## Palette bianco-oro (domanda aperta n.1 del report Task 98: opzione
## consigliata e scelta di default — coerente con oro UI e distinta dalle
## pergamene arancio/viola/ciano).
const TINT: Color = Color(1.0, 0.85, 0.35)
const TITLE_COL: Color = Color(1.0, 0.86, 0.30)
const TITLE_HIGHLIGHT: Color = Color(1.0, 0.98, 0.85)
const SUBTITLE_COL: Color = Color(0.98, 0.94, 0.80)
const TITLE_FONT_SIZE: int = 92
const SUBTITLE_FONT_SIZE: int = 30

## FASE 3 — asset PixelLab (PNG-first, pattern SpriteManager: Image.load
## diretto così funziona anche con .godot/imported vuoto nei test CI).
const BOLT_SHEET_PATH := "res://assets/sprites/skills/levelup_bolt_sheet.png"
const TITLE_SPRITE_PATH := "res://assets/sprites/skills/levelup_title.png"

var _player_num: int = 1
var _level_reached: int = 2
var _levels_gained: int = 1
var _impact_pos: Vector2 = Vector2.ZERO
var _world_host: Node = null
var _panel: Control
var _t_ms: float = 0.0
var _done: bool = false
var _jingle_played: bool = false
## FASE 3: frame del fulmine PixelLab (4 ImageTexture da sheet 256x64)
## e scritta dorata (null se l'asset manca -> fallback procedurale).
var _bolt_frames: Array = []
var _title_texture: ImageTexture = null


## `impact_pos`: posizione MONDO del player che è salito di livello (il
## fulmine si abbatte lì). `world_host`: nodo della scena di gioco a cui
## agganciare il fulmine (coordinate mondo, es. il controller stesso).
func setup(player_num: int, level_reached: int, levels_gained: int,
                impact_pos: Vector2, world_host: Node) -> void:
        _player_num = player_num
        _level_reached = level_reached
        _levels_gained = levels_gained
        _impact_pos = impact_pos
        _world_host = world_host


func _ready() -> void:
        layer = 27
        process_mode = Node.PROCESS_MODE_ALWAYS
        _panel = Control.new()
        _panel.name = "LevelUpAnnouncePanel"
        _panel.set_anchors_preset(Control.PRESET_FULL_RECT)
        _panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _panel.draw.connect(_draw_panel.bind(_panel))
        add_child(_panel)
        # FASE 3 — asset PixelLab: fulmine 4-frame + scritta dorata.
        _load_pixellab_assets()
        # Fulmine: se lo sheet PixelLab c'e' lo disegna il panel (sotto);
        # ALTRIMENTI fallback procedurale LightningStrikeEffect tinto
        # (coordinate MONDO, figlio della scena di gioco).
        if _bolt_frames.is_empty() \
                        and _world_host != null and is_instance_valid(_world_host):
                var strike: Node2D = LightningStrikeFx.new()
                strike.setup(_impact_pos, TINT)
                _world_host.add_child(strike)
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.LIGHTNING)
        if EffectsManager:
                EffectsManager.screen_shake(6.0, 0.45)


## FASE 3: caricamento PNG-first degli asset PixelLab (sheet fulmine 4
## frame da 256x64 + scritta dorata). Null-safe: senza file si resta sul
## fallback procedurale.
func _load_pixellab_assets() -> void:
        var bolt_img := Image.new()
        var bolt_abs: String = ProjectSettings.globalize_path(BOLT_SHEET_PATH)
        if FileAccess.file_exists(bolt_abs) \
                        and bolt_img.load(bolt_abs) == OK \
                        and bolt_img.get_width() >= 256 \
                        and bolt_img.get_height() >= 64:
                for i in 4:
                        var frame := Image.create(64, 64, false, Image.FORMAT_RGBA8)
                        frame.blit_rect(bolt_img, Rect2i(i * 64, 0, 64, 64),
                                        Vector2i.ZERO)
                        _bolt_frames.append(ImageTexture.create_from_image(frame))
        var title_img := Image.new()
        var title_abs: String = ProjectSettings.globalize_path(TITLE_SPRITE_PATH)
        if FileAccess.file_exists(title_abs) \
                        and title_img.load(title_abs) == OK:
                _title_texture = ImageTexture.create_from_image(title_img)


func _process(delta: float) -> void:
        if _done:
                return
        _t_ms += delta * 1000.0
        # TASK 99: il jingle trionfale parte quando la scritta LEVEL UP!
        # prende il posto del crack del fulmine (250ms dopo l'impatto).
        if not _jingle_played and _t_ms >= 250.0:
                _jingle_played = true
                if AudioManager:
                        AudioManager.play_sound(AudioManager.SoundType.LEVEL_UP)
        _panel.queue_redraw()
        if _t_ms >= DURATION_MS:
                _done = true
                set_process(false)
                announcement_done.emit(_player_num)


func _draw_panel(_p: Control) -> void:
        var font := ThemeDB.fallback_font
        var vp: Vector2 = _panel.size
        if vp.x <= 1.0:
                vp = Vector2(1920.0, 1080.0)
        var cx: float = vp.x * 0.5
        var cy: float = vp.y * 0.42

        # --- 1) velo caldo che sfuma nei primi 400 ms (impatto) ---------
        var veil_a: float = clampf(1.0 - _t_ms / 400.0, 0.0, 1.0) * 0.22
        if veil_a > 0.005:
                _panel.draw_rect(Rect2(Vector2.ZERO, vp),
                                Color(TINT.r, TINT.g, TINT.b, veil_a), true)

        # --- 1b) FASE 3: fulmine PixelLab sul player (4 frame, flicker) --
        # Il bolt 64px viene scalato a coprire dal bordo alto dello schermo
        # fino all'impatto (pixel-art chunky, coerente con lo stile).
        if not _bolt_frames.is_empty() and _t_ms < BOLT_MS:
                var bolt_alpha: float = clampf((BOLT_MS - _t_ms) / 200.0, 0.0, 1.0)
                var f_idx: int = int(_t_ms / BOLT_FRAME_MS) % _bolt_frames.size()
                var bolt_h: float = maxf(180.0, _impact_pos.y - 10.0)
                var scale_f: float = bolt_h / 64.0
                var bolt_w: float = 64.0 * scale_f
                # leggero tremolio orizzontale del colpo (vita elettrica)
                var jitter: float = sin(_t_ms * 0.05) * 6.0 * bolt_alpha
                _panel.draw_texture_rect(_bolt_frames[f_idx],
                                Rect2(_impact_pos.x - bolt_w * 0.5 + jitter,
                                                _impact_pos.y - bolt_h,
                                                bolt_w, bolt_h),
                                false, Color(1, 1, 1, bolt_alpha))
                # bagliore d'impatto tinto sotto la punta del bolt
                var glow_a: float = bolt_alpha * (0.5 + 0.3 * sin(_t_ms * 0.04))
                for i in 3:
                        _panel.draw_circle(_impact_pos,
                                        30.0 * (1.0 - 0.2 * float(i)),
                                        Color(TINT.r, TINT.g, TINT.b, 0.14 * glow_a))

        # --- 2) alpha globale: rapido in-in, tenuta, out finale ---------
        var fade_in: float = clampf(_t_ms / 140.0, 0.0, 1.0)
        var fade_out: float = clampf((DURATION_MS - _t_ms) / 300.0, 0.0, 1.0)
        var a: float = minf(fade_in, fade_out)

        # --- 3) scritta "LEVEL UP!" con pop-in (grande -> assesta) ------
        var pop_t: float = clampf(_t_ms / TITLE_POP_MS, 0.0, 1.0)
        var pop: float = 1.0 + 0.45 * (1.0 - pop_t) * (1.0 - pop_t)
        # pulsazione morbida della scala (il testo "respira")
        var breathe: float = 1.0 + 0.012 * sin(_t_ms * 0.012)
        var title: String = I18n.t("levelup.title")
        var sub_y: float
        if _title_texture != null:
                # FASE 3: sprite PixelLab pixel-font dorato (larghezza target
                # ~35% dello schermo, pop-in + respiro, ombra offset).
                var tw: float = _title_texture.get_width()
                var th: float = _title_texture.get_height()
                var target_w: float = minf(vp.x * 0.38, 760.0)
                var k: float = target_w / tw * pop * breathe
                var rw: float = tw * k
                var rh: float = th * k
                var rx: float = cx - rw * 0.5
                var ry: float = cy - rh * 0.5
                _panel.draw_texture_rect(_title_texture,
                                Rect2(rx + 5.0, ry + 5.0, rw, rh),
                                false, Color(0.0, 0.0, 0.0, 0.65 * a))
                _panel.draw_texture_rect(_title_texture,
                                Rect2(rx, ry, rw, rh),
                                false, Color(1.0, 1.0, 1.0, a))
                sub_y = ry + rh + 36.0
        else:
                # Fallback: draw_string triplo (ombra, corpo oro, luce).
                var title_size: int = int(float(TITLE_FONT_SIZE) * pop * breathe)
                var title_w: float = font.get_string_size(title,
                                HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x
                var tx: float = cx - title_w * 0.5
                var ty: float = cy
                _panel.draw_string(font, Vector2(tx + 3.0, ty + 3.0), title,
                                HORIZONTAL_ALIGNMENT_LEFT, title_w, title_size,
                                Color(0.0, 0.0, 0.0, 0.85 * a))
                _panel.draw_string(font, Vector2(tx, ty), title,
                                HORIZONTAL_ALIGNMENT_LEFT, title_w, title_size,
                                Color(TITLE_COL.r, TITLE_COL.g, TITLE_COL.b, a))
                _panel.draw_string(font, Vector2(tx - 1.5, ty - 1.5), title,
                                HORIZONTAL_ALIGNMENT_LEFT, title_w, title_size,
                                Color(TITLE_HIGHLIGHT.r, TITLE_HIGHLIGHT.g,
                                                TITLE_HIGHLIGHT.b, 0.55 * a))
                sub_y = ty + 46.0

        # --- 4) sottotitolo: livello raggiunto + punti guadagnati ------
        var sub1: String = I18n.t("levelup.reached") % _level_reached
        var sub2: String
        if _levels_gained == 1:
                sub2 = I18n.t("levelup.gained_one")
        else:
                sub2 = I18n.t("levelup.gained_many") % _levels_gained
        var sub_w: float = 900.0
        _panel.draw_string(font, Vector2(cx - sub_w * 0.5, sub_y), sub1,
                        HORIZONTAL_ALIGNMENT_CENTER, sub_w, SUBTITLE_FONT_SIZE,
                        Color(0.0, 0.0, 0.0, 0.7 * a))
        _panel.draw_string(font, Vector2(cx - sub_w * 0.5, sub_y - 1.0), sub1,
                        HORIZONTAL_ALIGNMENT_CENTER, sub_w, SUBTITLE_FONT_SIZE,
                        Color(SUBTITLE_COL.r, SUBTITLE_COL.g, SUBTITLE_COL.b, a))
        var sub_y2: float = sub_y + 34.0
        _panel.draw_string(font, Vector2(cx - sub_w * 0.5, sub_y2), sub2,
                        HORIZONTAL_ALIGNMENT_CENTER, sub_w, 22,
                        Color(0.0, 0.0, 0.0, 0.6 * a))
        _panel.draw_string(font, Vector2(cx - sub_w * 0.5, sub_y2 - 1.0), sub2,
                        HORIZONTAL_ALIGNMENT_CENTER, sub_w, 22,
                        Color(TINT.r, TINT.g * 0.97, TINT.b * 0.8, 0.9 * a))

        # --- 5) in 2P: chi è salito di livello (P1/P2) -----------------
        if GameManager != null and GameManager.num_players == 2:
                var who: String = "P%d" % _player_num
                _panel.draw_string(font, Vector2(cx - sub_w * 0.5, sub_y2 + 30.0),
                                who, HORIZONTAL_ALIGNMENT_CENTER, sub_w, 20,
                                Color(0.8, 0.85, 0.95, 0.8 * a))
