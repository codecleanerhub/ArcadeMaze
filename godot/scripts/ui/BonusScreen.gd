## BonusScreen.gd — RELIC (Task 21): SCHERMATA BONUS POST-BOSS.
## ============================================================
## Dopo ogni boss sconfitto (finché c'è un livello successivo) il gioco
## si congela e mostra questa schermata: il player SCEGLIE una delle 3
## reliquie offerte (una per famiglia: MISCHIA / DISTANZA / ARMATURA —
## tutte le famiglie sempre disponibili, decisione utente).
##
## TASK 23 (richiesta utente):
##   * TUTTO il testo è in INGLESE (era italiano).
##   * NON compare più il nome della schermata ("SCHERMATA BONUS A"):
##     il titolo è generico ("CHOOSE YOUR RELIC").
##   * Sfondo DEDICATO a tema fucina/armeria (bg_bonus.png, stile degli
##     altri sfondi) — fallback al velo scuro se l'asset manca.
##   * Ogni reliquia è rappresentata dal suo PNG ad alta qualità
##     (RelicArt) con fallback all'icona procedurale se il PNG manca.
##
## L'offerta ruota internamente alle famiglie (cursori sfasati) così in 17
## incontri compaiono tutte le 18 reliquie: GameConstants.get_bonus_offering().
##
## In 2P OGNI player sceglie la SUA reliquia (una per player): prima P1,
## poi P2 (turni consecutivi sulla stessa offerta).
##
## Pure-code CanvasLayer (pattern PauseOverlay): nessun .tscn, il controller
## lo crea con BonusScreen.new(), chiama setup() e ascolta bonus_completed.
## Layer 30 (sopra HUD 10 e pausa 20).
extends CanvasLayer

## Emitted quando TUTTI i choosers hanno scelto (o non c'era nessuno da
## far scegliere): il controller prosegue con la transizione di livello.
signal bonus_completed

const C = preload("res://scripts/core/GameConstants.gd")
const RelicArt = preload("res://scripts/core/RelicArt.gd")

# --- Stato ---
var screen_id: int = 0           # 0=A, 1=B, 2=C (SOLO per l'offerta: NON mostrato)
var offerings: Array[Dictionary] = []   # le 3 reliquie offerte
var choosers: Array = []                # players che scelgono (vivi)
var chooser_idx: int = 0                # chi sta scegliendo ora
var selection: int = 0                  # carta selezionata (0..2)
var completed: bool = false
var level_of_bonus: int = 4

# Flusso: dopo una conferma aspetta un attimo prima del prossimo chooser
# (evita che lo stesso tasto confermi due volte).
const POST_CHOICE_DELAY_MS: float = 700.0
var _wait_ms: float = 0.0
var _last_choice_text: String = ""
var _t: float = 0.0  # tempo per animazioni

# TASK 51 (P1): la conferma avviene TENENDO PREMUTO il fuoco (il tap
# istantaneo non conferma piu'). Sotto la carta selezionata appare una
# barra che si riempie in HOLD_CONFIRM_MS: a riempimento completo la
# reliquia e' confermata. Se il tasto viene rilasciato la barra si
# svuota (si puo' cambiare idea / cambiare carta senza confermare).
const HOLD_CONFIRM_MS: float = 450.0
var _hold_ms: float = 0.0
var _hold_frac: float = 0.0   # 0..1, per il rendering della barra
var _hold_chooser: int = -1   # reset hold quando cambia il chooser

# Pannello di disegno (Control full-rect figlio del layer).
var _panel: Control = null

# Edge-detection dei bottoni joystick (D-pad/conferma), mirror controller.
var _prev_joy_btns: Dictionary = {}


# ============================================================================
# Setup + lifecycle
# ============================================================================
## `players`: Array di CharacterBody2D che possono scegliere (P1 sempre se
## vivo; P2 solo se in partita 2P e non eliminato). Il livello determina
## schermata (A/B/C) e offerta.
func setup(level: int, players: Array) -> void:
        level_of_bonus = level
        screen_id = C.get_bonus_screen_id(level)
        offerings = C.get_bonus_offering(level)
        choosers = players.duplicate()
        chooser_idx = 0
        selection = 0
        completed = choosers.is_empty()
        if completed:
                # Nessuno può scegliere (caso limite): completa al primo tick.
                call_deferred("_finish")


func _ready() -> void:
        layer = 30
        process_mode = Node.PROCESS_MODE_ALWAYS
        _panel = Control.new()
        _panel.name = "BonusPanel"
        _panel.set_anchors_preset(Control.PRESET_FULL_RECT)
        _panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _panel.draw.connect(_draw_screen.bind(_panel))
        add_child(_panel)


func _physics_process(delta: float) -> void:
        _t += delta
        _panel.queue_redraw()
        if completed:
                return
        if _wait_ms > 0.0:
                _wait_ms = maxf(0.0, _wait_ms - delta * 1000.0)
                if _wait_ms == 0.0 and chooser_idx < choosers.size():
                        selection = 0
                return
        _poll_current_chooser(delta * 1000.0)


# ============================================================================
# Input (tastiera + joystick di entrambi i player, mirror BossRoom)
# ============================================================================
func _poll_current_chooser(delta_ms: float) -> void:
        if chooser_idx >= choosers.size():
                _finish()
                return
        # TASK 51 (P1): cambio chooser -> la pressione accumulata si azzera.
        if _hold_chooser != chooser_idx:
                _hold_chooser = chooser_idx
                _hold_ms = 0.0
                _hold_frac = 0.0
        var is_p1: bool = (chooser_idx == 0)
        var moved: int = 0
        var confirmed: bool = false

        # --- Navigazione ---
        if is_p1:
                if Input.is_action_just_pressed("move_left"):
                        moved = -1
                elif Input.is_action_just_pressed("move_right"):
                        moved = 1
                # Joystick P1: D-pad (device configurato o primo pad).
                var p1_joy: int = _resolve_p1_joy()
                if moved == 0 and p1_joy >= 0:
                        if _joy_edge(p1_joy, JOY_BUTTON_DPAD_LEFT):
                                moved = -1
                        elif _joy_edge(p1_joy, JOY_BUTTON_DPAD_RIGHT):
                                moved = 1
        else:
                if Input.is_action_just_pressed("p2_left"):
                        moved = -1
                elif Input.is_action_just_pressed("p2_right"):
                        moved = 1
                # Joystick P2: D-pad del pad configurato (o secondo pad).
                var p2_joy: int = _resolve_p2_joy()
                if moved == 0 and p2_joy >= 0:
                        if _joy_edge(p2_joy, JOY_BUTTON_DPAD_LEFT):
                                moved = -1
                        elif _joy_edge(p2_joy, JOY_BUTTON_DPAD_RIGHT):
                                moved = 1
        if moved != 0 and not offerings.is_empty():
                selection = int(fposmod(float(selection + moved), float(offerings.size())))

        # --- Conferma TASK 51 (P1): TENENDO PREMUTO il fuoco ---
        # Il tap singolo non conferma: il tasto va tenuto per
        # HOLD_CONFIRM_MS. La barra di riempimento sotto la carta
        # selezionata mostra il progresso; muoversi non azzera la
        # pressione (si puo' correggere la mira), rilasciare si'.
        var fire_held: bool = false
        if is_p1:
                fire_held = Input.is_action_pressed("shoot") \
                                or Input.is_action_pressed("confirm")
                var p1_joy2: int = _resolve_p1_joy()
                if not fire_held and p1_joy2 >= 0:
                        var btn: int = ConfigManager.joy_shoot() if ConfigManager else -1
                        if btn < 0:
                                btn = JOY_BUTTON_B
                        fire_held = Input.is_joy_button_pressed(p1_joy2, btn)
        else:
                fire_held = Input.is_action_pressed("p2_shoot")
                var p2_joy2: int = _resolve_p2_joy()
                if not fire_held and p2_joy2 >= 0:
                        var btn2: int = ConfigManager.joy2_shoot() if ConfigManager else -1
                        if btn2 < 0:
                                btn2 = JOY_BUTTON_B
                        fire_held = Input.is_joy_button_pressed(p2_joy2, btn2)
        if fire_held and not offerings.is_empty():
                _hold_ms += delta_ms
        else:
                _hold_ms = 0.0
        _hold_frac = clampf(_hold_ms / HOLD_CONFIRM_MS, 0.0, 1.0)
        if _hold_ms >= HOLD_CONFIRM_MS:
                _hold_ms = 0.0
                _hold_frac = 0.0
                confirmed = true

        if confirmed:
                _apply_choice(offerings[selection])


func _resolve_p1_joy() -> int:
        var pads: Array = Input.get_connected_joypads()
        if ConfigManager and ConfigManager.joy_id() >= 0 and pads.has(ConfigManager.joy_id()):
                return ConfigManager.joy_id()
        if pads.size() > 0:
                return pads[0]
        return -1


func _resolve_p2_joy() -> int:
        var pads: Array = Input.get_connected_joypads()
        var p1: int = _resolve_p1_joy()
        if ConfigManager and ConfigManager.joy2_id() >= 0 \
                        and pads.has(ConfigManager.joy2_id()) \
                        and ConfigManager.joy2_id() != p1:
                return ConfigManager.joy2_id()
        for pad_id in pads:
                if pad_id != p1:
                        return pad_id
        return -1


## Edge-detection di un bottone joystick (true SOLO sul frame di pressione).
func _joy_edge(joy_id: int, btn: int) -> bool:
        var key: String = str(joy_id) + ":" + str(btn)
        var now: bool = Input.is_joy_button_pressed(joy_id, btn)
        var prev: bool = bool(_prev_joy_btns.get(key, false))
        _prev_joy_btns[key] = now
        return now and not prev


# ============================================================================
# Applicazione della scelta
# ============================================================================
func _apply_choice(def: Dictionary) -> void:
        var chooser: CharacterBody2D = choosers[chooser_idx]
        if chooser == null or not is_instance_valid(chooser):
                _advance_chooser()
                return
        var family: String = str(def.get("family", ""))
        if family == "armatura":
                chooser.equip_relic_armor(def)
        else:
                # Sostituisce QUALSIASI arma (anche un'altra reliquia): la
                # schermata bonus è l'UNICO punto in cui si cambia reliquia.
                chooser.current_weapon = C.make_relic_weapon(def)
                if AudioManager:
                        AudioManager.play_sound(AudioManager.SoundType.RELIC_PICKUP)
        _last_choice_text = I18n.t("bonus.chose") % [
                        int(chooser.player_num), I18n.relic_name(def)]
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.MENU_CONFIRM)
        _advance_chooser()


func _advance_chooser() -> void:
        chooser_idx += 1
        if chooser_idx >= choosers.size():
                _finish()
        else:
                selection = 0
                _wait_ms = POST_CHOICE_DELAY_MS


func _finish() -> void:
        if completed:
                return
        completed = true
        _wait_ms = 500.0  # breve pausa finale prima che il layer sparisca
        bonus_completed.emit()


# ============================================================================
# Rendering — TASK 23: icone PNG ad alta qualità (fallback procedurale),
# sfondo fucina dedicato. TASK 44: TUTTI i testi (titoli, famiglie,
# statistiche, nomi e descrizioni delle reliquie) localizzati EN/IT.
# ============================================================================
const FAMILY_LABEL_KEYS := {
        "mischia": "bonus.family_melee",
        "distanza": "bonus.family_ranged",
        "armatura": "bonus.family_armor",
}


func _draw_screen(p: Control) -> void:
        var vp: Vector2 = p.get_viewport_rect().size
        var font: Font = ThemeDB.fallback_font
        if font == null:
                return
        # TASK 23: sfondo DEDICATO a tema fucina/armeria (stile degli altri
        # sfondi) + velo scuro per la leggibilità; fallback velo pieno.
        var bg: Texture2D = RelicArt.get_bonus_background()
        if bg != null:
                var tex_size: Vector2 = bg.get_size()
                var scale_val: float = max(vp.x / tex_size.x, vp.y / tex_size.y)
                var draw_size: Vector2 = tex_size * scale_val
                var draw_pos: Vector2 = (vp - draw_size) / 2.0
                p.draw_texture_rect(bg, Rect2(draw_pos, draw_size), false)
                p.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.02, 0.01, 0.05, 0.62), true)
        else:
                p.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.02, 0.01, 0.05, 0.86))
        var cx: float = vp.x * 0.5

        # TASK 23: titolo generico SENZA nome/lettera di schermata.
        # TASK 44: localizzato (EN/IT).
        var gold: Color = Color(1.0, 0.84, 0.25)
        _draw_text_centered(p, font, I18n.t("bonus.title"),
                Vector2(cx, 140.0), 44, gold)
        _draw_text_centered(p, font, I18n.t("bonus.subtitle"),
                Vector2(cx, 190.0), 18, Color(0.85, 0.75, 0.55))
        # Cornice decorativa a doppia linea sotto il titolo.
        p.draw_line(Vector2(cx - 420.0, 215.0), Vector2(cx + 420.0, 215.0),
                Color(gold.r, gold.g, gold.b, 0.55), 2.0)
        p.draw_line(Vector2(cx - 340.0, 222.0), Vector2(cx + 340.0, 222.0),
                Color(gold.r, gold.g, gold.b, 0.25), 1.0)

        if completed:
                # Schermata completata: riepilogo scelte + saluto finale.
                _draw_text_centered(p, font, _last_choice_text,
                        Vector2(cx, vp.y * 0.5 - 20.0), 26, Color(0.9, 0.95, 1.0))
                _draw_text_centered(p, font, I18n.t("bonus.good_luck"),
                        Vector2(cx, vp.y * 0.5 + 30.0), 20, gold)
                return

        # --- Chi sta scegliendo ---
        var chooser: CharacterBody2D = choosers[chooser_idx] \
                        if chooser_idx < choosers.size() else null
        var pnum: int = chooser_idx + 1
        if chooser != null:
                pnum = int(chooser.player_num)
        var who_col: Color = Color(0.39, 0.78, 1.0) if pnum == 1 else Color(1.0, 0.59, 0.39)
        _draw_text_centered(p, font, I18n.t("bonus.player_choose") % pnum,
                Vector2(cx, 250.0), 26, who_col)
        if _last_choice_text != "" and _wait_ms > 0.0:
                _draw_text_centered(p, font, _last_choice_text,
                        Vector2(cx, 284.0), 16, Color(0.8, 0.85, 0.9))

        # --- Le 3 carte ---
        var card_w: float = 380.0
        var card_h: float = 480.0
        var gap: float = 60.0
        var total_w: float = card_w * 3.0 + gap * 2.0
        var x0: float = cx - total_w * 0.5
        var card_y: float = (vp.y - card_h) * 0.5 + 60.0
        for i in offerings.size():
                _draw_relic_card(p, font, offerings[i],
                        Rect2(x0 + float(i) * (card_w + gap), card_y, card_w, card_h),
                        i == selection, i)

        # --- Istruzioni comandi (TASK 44: localizzate) ---
        var hint: String
        if pnum == 1:
                hint = I18n.t("bonus.hint_1p")
        else:
                hint = I18n.t("bonus.hint_2p")
        _draw_text_centered(p, font, hint,
                Vector2(cx, card_y + card_h + 46.0), 18, Color(0.75, 0.75, 0.8))


func _draw_relic_card(p: Control, font: Font, def: Dictionary,
                rect: Rect2, selected: bool, idx: int) -> void:
        var col: Color = def.get("color", Color.WHITE)
        var pulse: float = 0.5 + 0.5 * sin(_t * 4.0)
        # Sfondo carta (leggermente più trasparente per far respirare lo
        # sfondo-forgia TASK 23, resta comunque leggibile).
        p.draw_rect(rect, Color(0.07, 0.06, 0.10, 0.92), true)
        # Bordo: selezione = colore reliquia pulsante + doppia cornice.
        if selected:
                p.draw_rect(rect, Color(col.r, col.g, col.b, 0.65 + 0.35 * pulse), false, 4.0)
                p.draw_rect(rect.grow(-8.0), Color(col.r, col.g, col.b, 0.30), false, 1.5)
                # Bagliore dietro la carta selezionata.
                p.draw_rect(Rect2(rect.position - Vector2(6, 6),
                        rect.size + Vector2(12, 12)),
                        Color(col.r, col.g, col.b, 0.10 + 0.06 * pulse), true)
        else:
                p.draw_rect(rect, Color(0.35, 0.32, 0.40, 0.9), false, 2.0)

        var cx: float = rect.position.x + rect.size.x * 0.5
        # Etichetta famiglia in alto (TASK 44: localizzata).
        var fam: String = I18n.t(FAMILY_LABEL_KEYS.get(
                        str(def.get("family", "")), "bonus.family_relic"))
        _draw_text_centered(p, font, fam,
                Vector2(cx, rect.position.y + 34.0), 17,
                Color(0.78, 0.72, 0.60))
        # TASK 23: icona PNG ad alta qualità della reliquia (fallback
        # procedurale se l'asset non c'è). Area icona ~200x210.
        _draw_relic_icon(p, def, Vector2(cx, rect.position.y + 140.0), selected)
        # Nome (TASK 44: localizzato; 2 righe se lungo).
        var name_s: String = I18n.relic_name(def)
        var name_size: int = 24 if name_s.length() <= 22 else 20
        _draw_text_centered(p, font, name_s,
                Vector2(cx, rect.position.y + 262.0), name_size, col)
        # Statistiche principali (TASK 44: localizzate).
        var stats: String = _relic_stats_line(def)
        _draw_text_centered(p, font, stats,
                Vector2(cx, rect.position.y + 298.0), 17, Color(0.95, 0.9, 0.7))
        # Descrizione (TASK 44: localizzata, a capo automatico).
        var desc_y: float = rect.position.y + 348.0
        for line in _wrap_text(I18n.relic_desc(def), 38):
                _draw_text_centered(p, font, line, Vector2(cx, desc_y), 15,
                        Color(0.82, 0.82, 0.88))
                desc_y += 22.0
        # Indicatore di selezione (freccia lampeggiante sotto la carta).
        if selected:
                var ay: float = rect.position.y + rect.size.y - 26.0 \
                                + (2.0 * sin(_t * 6.0))
                p.draw_colored_polygon(PackedVector2Array([
                        Vector2(cx - 12.0, ay), Vector2(cx + 12.0, ay),
                        Vector2(cx, ay + 10.0)]),
                        Color(col.r, col.g, col.b, 0.9))
                # TASK 51 (P1): BARRA DI CONFERMA "tieni premuto il fuoco".
                # Traccia rossa scura + riempimento color reliquia che cresce
                # con _hold_frac; a fondo corsa la reliquia e' confermata.
                # Sopra la barra il hint localizzato (solo se la pressione e'
                # in corso o la carta e' selezionata da poco).
                var bar_w: float = rect.size.x - 48.0
                var bar_rect: Rect2 = Rect2(
                        cx - bar_w * 0.5, rect.position.y + rect.size.y - 20.0,
                        bar_w, 8.0)
                p.draw_rect(bar_rect, Color(0.10, 0.05, 0.05, 0.85), true)
                p.draw_rect(bar_rect, Color(0.45, 0.30, 0.20, 0.9), false, 1.0)
                if _hold_frac > 0.005:
                        p.draw_rect(Rect2(bar_rect.position,
                                        Vector2(bar_w * _hold_frac, bar_rect.size.y)),
                                Color(col.r, col.g, col.b, 0.55 + 0.45 * _hold_frac), true)
                        # bagliore della punta che avanza
                        p.draw_circle(Vector2(bar_rect.position.x + bar_w * _hold_frac,
                                        bar_rect.position.y + 4.0), 5.0,
                                Color(1.0, 0.95, 0.8, 0.5 * _hold_frac))
                _draw_text_centered(p, font, I18n.t("bonus.hold_hint"),
                        Vector2(cx, rect.position.y + rect.size.y - 30.0), 14,
                        Color(0.9, 0.82, 0.6, 0.75))


## TASK 23: icona della reliquia sulla carta. PRIMA il PNG ad alta qualità
## (centrato, contenuto in ~200px, lieve glow pulsante se selezionata);
## SE il PNG manca ricade sull'anteprima procedurale storica.
func _draw_relic_icon(p: Control, def: Dictionary, center: Vector2,
                selected: bool) -> void:
        var col: Color = def.get("color", Color.WHITE)
        var tex: Texture2D = RelicArt.get_icon_for_def(def)
        if tex != null:
                var pulse_glow: float = 0.5 + 0.5 * sin(_t * 3.0)
                var glow_r: float = 88.0 + (6.0 if selected else 0.0) * pulse_glow
                p.draw_circle(center, glow_r,
                        Color(col.r, col.g, col.b, 0.10 + 0.08 * pulse_glow))
                # Fit-and-center dentro un box 190x190 (mantiene aspetto).
                var tex_size: Vector2 = tex.get_size()
                var fit: float = min(190.0 / tex_size.x, 190.0 / tex_size.y)
                var draw_size: Vector2 = tex_size * fit
                # Lieve fluttuazione verticale ("appesa" nella vetrina).
                var bob: float = 3.0 * sin(_t * 1.6)
                p.draw_texture_rect(tex,
                        Rect2(center - draw_size * 0.5 + Vector2(0.0, bob),
                                draw_size), false)
                return
        # ---- Fallback procedurale (asset non generato / rollback) ----
        var glow: float = 0.35 + 0.25 * sin(_t * 3.0)
        p.draw_circle(center, 44.0, Color(col.r, col.g, col.b, 0.12 + (0.08 if selected else 0.0)))
        var family: String = str(def.get("family", ""))
        if family == "mischia":
                # Lama diagonale con elsa.
                p.draw_line(center + Vector2(-26, 26), center + Vector2(22, -22), col, 8.0)
                p.draw_line(center + Vector2(-26, 26), center + Vector2(22, -22),
                        Color(1, 1, 1, 0.5), 2.0)
                p.draw_line(center + Vector2(-16, 8), center + Vector2(-4, 20),
                        Color(0.55, 0.45, 0.3), 6.0)
                p.draw_line(center + Vector2(-30, 30), center + Vector2(-20, 20),
                        Color(0.3, 0.2, 0.1), 7.0)
        elif family == "distanza":
                # Ista arcana con nucleo luminoso.
                p.draw_line(center + Vector2(-30, 30), center + Vector2(26, -26),
                        Color(0.5, 0.45, 0.6), 5.0)
                p.draw_circle(center + Vector2(30, -30), 10.0 + glow * 6.0,
                        Color(col.r, col.g, col.b, 0.4))
                p.draw_circle(center + Vector2(30, -30), 6.0, col)
                p.draw_circle(center + Vector2(30, -30), 2.5, Color(1, 1, 1, 0.9))
        else:
                # Armatura: torso + spallacci.
                p.draw_colored_polygon(PackedVector2Array([
                        center + Vector2(-18, -14), center + Vector2(18, -14),
                        center + Vector2(14, 26), center + Vector2(-14, 26)]),
                        Color(col.r, col.g, col.b, 0.85))
                p.draw_circle(center + Vector2(-22, -14), 8.0, col)
                p.draw_circle(center + Vector2(22, -14), 8.0, col)
                p.draw_circle(center + Vector2(-22, -14), 4.0,
                        Color(col.r * 0.5, col.g * 0.5, col.b * 0.5))
                p.draw_circle(center + Vector2(22, -14), 4.0,
                        Color(col.r * 0.5, col.g * 0.5, col.b * 0.5))
                p.draw_colored_polygon(PackedVector2Array([
                        center + Vector2(-8, -4), center + Vector2(8, -4),
                        center + Vector2(0, 8)]), Color(1, 1, 1, 0.65))


## riga statistiche compatta per la carta (TASK 44: localizzata EN/IT).
func _relic_stats_line(def: Dictionary) -> String:
        if str(def.get("family", "")) == "armatura":
                return I18n.t("bonus.stat_charges") % int(def.get("charges", 0))
        var parts: Array[String] = []
        parts.append(I18n.t("bonus.stat_shots") % int(def.get("shots", 0)))
        parts.append(I18n.t("bonus.stat_power") % int(def.get("power", 1)))
        if def.has("pierce_max"):
                parts.append(I18n.t("bonus.tag_piercing"))
        if bool(def.get("homing", false)):
                parts.append(I18n.t("bonus.tag_homing"))
        if def.has("fan"):
                parts.append(I18n.t("bonus.tag_fan") % int(def["fan"]))
        if def.has("chain"):
                parts.append(I18n.t("bonus.tag_chain"))
        if def.has("lob_px"):
                parts.append(I18n.t("bonus.tag_area"))
        if def.has("stun_ms"):
                parts.append(I18n.t("bonus.tag_stuns"))
        if bool(def.get("vampiric", false)):
                parts.append(I18n.t("bonus.tag_vampiric"))
        return "  ·  ".join(parts)


## Testo centrato su `at.x` con ombra (stile della HUD): draw_string centra
## DENTRO il box [pos.x, pos.x+width], quindi pos.x = centro - box_w/2.
func _draw_text_centered(p: Control, font: Font, text: String,
                at: Vector2, size: int, col: Color, box_w: float = 900.0) -> void:
        if text == "":
                return
        var pos_x: float = at.x - box_w * 0.5
        p.draw_string(font, Vector2(pos_x, at.y + 2.0), text,
                HORIZONTAL_ALIGNMENT_CENTER, box_w, size, Color(0, 0, 0, 0.85))
        p.draw_string(font, Vector2(pos_x, at.y), text,
                HORIZONTAL_ALIGNMENT_CENTER, box_w, size, col)


## A capo grossolano per la descrizione.
func _wrap_text(text: String, width_chars: int) -> Array[String]:
        var words: PackedStringArray = text.split(" ", false)
        var lines: Array[String] = []
        var cur: String = ""
        for w in words:
                if cur.length() + w.length() + 1 > width_chars and cur != "":
                        lines.append(cur)
                        cur = w
                else:
                        cur = cur + (" " if cur != "" else "") + w
        if cur != "":
                lines.append(cur)
        return lines
