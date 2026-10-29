## LevelUpAnnounce.gd — TASK 99 (Level Up), FASE 1.
##
## ANNUNCIO NON-BLOCCANTE del level up: il gioco CONTINUA a girare mentre
## parte il fulmine bianco-oro (stesso sistema grafico delle pergamene,
## LightningStrikeEffect tinto) sulla testa del player che è salito di
## livello, e al centro dello schermo cresce la scritta "LEVEL UP!" con
## il livello raggiunto e i punti abilità guadagnati.
##
## Sequence (report Task 98 §4.4): soglia superata -> fulmine -> scritta
## ~1.7s -> (FASE 2) il gioco va in pausa e si apre la modale abilità.
## L'annuncio è pure-code CanvasLayer (pattern BonusCardOverlay):
##   * layer 27 (sopra HUD 10 e pause 20, sotto il bonus screen 30)
##   * PROCESS_MODE_ALWAYS (gira anche se un altro overlay pausa il tree)
##   * il fulmine è aggiunto al NODO MONDO del controller ospite
##     (coordinate mondo sul player, z_index 46 come le pergamene)
##
## In 2P le celebrazioni sono in sequenza (prima P1 poi P2): il
## controller le concatena consumando pending_levelup_fx una alla volta.
extends CanvasLayer

## Emitted when the announcement is over. The host controller frees the
## layer and (FASE 2) opens the skills modal for the same player.
signal announcement_done(player_num: int)

const LightningStrikeFx = preload("res://scripts/entities/LightningStrikeEffect.gd")

## Durata totale dell'annuncio (ms): fulmine ~750ms + testo che resta
## in campo il tempo di leggere livello e punti guadagnati.
const DURATION_MS: float = 1700.0
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

var _player_num: int = 1
var _level_reached: int = 2
var _levels_gained: int = 1
var _impact_pos: Vector2 = Vector2.ZERO
var _world_host: Node = null
var _panel: Control
var _t_ms: float = 0.0
var _done: bool = false
var _jingle_played: bool = false


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
        # Fulmine sul player (coordinate MONDO: nodo figlio della scena di
        # gioco, non del CanvasLayer). Tinta bianco-oro: alone/onda/braci
        # colorati, core bianco-caldo come le pergamene.
        if _world_host != null and is_instance_valid(_world_host):
                var strike: Node2D = LightningStrikeFx.new()
                strike.setup(_impact_pos, TINT)
                _world_host.add_child(strike)
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.LIGHTNING)
        if EffectsManager:
                EffectsManager.screen_shake(6.0, 0.45)


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

        # --- 2) alpha globale: rapido in-in, tenuta, out finale ---------
        var fade_in: float = clampf(_t_ms / 140.0, 0.0, 1.0)
        var fade_out: float = clampf((DURATION_MS - _t_ms) / 300.0, 0.0, 1.0)
        var a: float = minf(fade_in, fade_out)

        # --- 3) scritta "LEVEL UP!" con pop-in (grande -> assesta) ------
        var pop_t: float = clampf(_t_ms / TITLE_POP_MS, 0.0, 1.0)
        var pop: float = 1.0 + 0.45 * (1.0 - pop_t) * (1.0 - pop_t)
        var title_size: int = int(float(TITLE_FONT_SIZE) * pop)
        var title: String = I18n.t("levelup.title")
        var title_w: float = font.get_string_size(title,
                        HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x
        # pulsazione morbida della scala (il testo "respira")
        var breathe: float = 1.0 + 0.012 * sin(_t_ms * 0.012)
        title_size = int(float(title_size) * breathe)
        var tx: float = cx - title_w * 0.5
        var ty: float = cy
        # tre passaggi (pattern _draw_hurry_up_text): ombra, corpo oro,
        # luce interna bianco-calda in alto
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

        # --- 4) sottotitolo: livello raggiunto + punti guadagnati ------
        var sub1: String = I18n.t("levelup.reached") % _level_reached
        var sub2: String
        if _levels_gained == 1:
                sub2 = I18n.t("levelup.gained_one")
        else:
                sub2 = I18n.t("levelup.gained_many") % _levels_gained
        var sub_w: float = 900.0
        var sub_y: float = ty + 46.0
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
