# ============================================================================
# HUD.gd  (Control node - game HUD)
#
# Godot port of:
#   - UI.h
#   - UI.cpp
#
# The HUD is an 80 px tall bar at the top of the screen (UI_HEIGHT = 80) that
# shows: SCORE, LIVES (hearts), WEAPON name, AMMO bar, TREASURES
# remaining. Supports both 1P and 2P layouts (in 2P the bar is split between
# the left = P1, center = treasures, right = P2).
#
# TASK 96 (cuori al posto della barra vita): la barra ENERGIA è RIMOSSA.
# Lo stato di salute si legge dal CUORE CORRENTE (l'ultimo della fila):
# integro a energia piena, poi sgretolato in 4 stadi man mano che l'energia
# scende (ogni 20% perso = uno stadio); a energia 0 la vita è persa e il
# cuore sparisce con un burst di frammenti. Al colpo: scossa + detriti che
# cadono. Cuori leggermente più grandi (16->24px 1:1 dallo sheet PixelLab).
#
# Heart sprite:
#   * Sheet 4 stadi PixelLab: res://assets/sprites/ui_heart_crumble_sheet.png
#     (24px/frame: f0 integro, f1 crepe, f2 profondo, f3 quasi distrutto).
#   * Fallback: ui_heart.png singolo (solo stadio 0) o cuore procedurale
#     (_draw_detailed_heart) con degrado per stadio.
#
# Layout (1P mode) - mirrors UI.cpp::render(target, player, remainingTreasures):
#       x=  10  SCORE       + score
#       x= 150  LIVES       + hearts (24px, l'ultimo = cuore corrente sgretolabile)
#       x= 280  STAMINA     + barra stamina (100x10, verde/arancione/rosso)
#       x= 420  WPN         + weapon name (colored)
#       x= 570  AMMO        + ammo bar (100x18, yellow on gray, norm. on 15)
#       x= 700  TRES        + remaining treasures
#
# Layout (2P mode) - mirrors UI.cpp::render(target, p1, p2, remainingTreasures):
#   P1 (left):   P1 score, LIFE hearts (24px), STAMINA, WPN name, ammo#
#   Center:      TRES + remainingTreasures
#   P2 (right):  P2 score, LIFE hearts (24px), STAMINA, WPN name, ammo#
# ============================================================================
extends Control

# --- Layout constants (mirrors Utils.h) -----------------------------------
const WINDOW_WIDTH: int = 1920
const WINDOW_HEIGHT: int = 1080
const UI_HEIGHT: int = 80

# --- Public API ------------------------------------------------------------
# Player snapshot for 1P rendering. Set externally before each render.
# Expected fields (mirror Player accessors used in UI.cpp):
#     score:int, lives:int, energy:float, max_energy:float,
#     weapon_name:String, weapon_color:Color, weapon_ammo:int, weapon_max:int
# Actually we expose a single `set_player_state` API instead of breaking it
# down, so the caller doesn't have to know about the exact field names.

# The "PlayerState" struct is a simple Dictionary with the fields above.
# We keep two slots for 1P/2P and a separate remaining-treasures counter.

# --- Signals ---------------------------------------------------------------
signal heart_clicked()  # currently unused but exposed for future editor hooks

# --- Exported theme colors (mirror SFML palette) --------------------------
@export var color_bg:        Color = Color(0.078, 0.078, 0.078)      # 20,20,20
@export var color_score:     Color = Color(1.000, 1.000, 0.000)      # Yellow
@export var color_label:     Color = Color.WHITE
@export var color_energy_bg:  Color = Color(0.392, 0.392, 0.392)
@export var color_energy_border: Color = Color(0.235, 0.235, 0.235)
@export var color_ammo:       Color = Color(1.000, 1.000, 0.000)
@export var color_p1_label:    Color = Color(0.392, 0.784, 1.000)     # 100,200,255
@export var color_p2_label:    Color = Color(1.000, 0.588, 0.392)     # 255,150,100
@export var color_heart_fill:  Color = Color(0.863, 0.078, 0.078)    # 220,20,20
@export var color_heart_outline: Color = Color(0.392, 0.000, 0.000)  # 100,0,0

const C = preload("res://scripts/core/GameConstants.gd")

# --- Heart sprite (mirror of UI::heartTexture + heartSprite) ---------------
var _heart_texture: Texture2D = null
var _heart_loaded: bool = false

# --- TASK 96: sheet cuore sgretolabile (4 stadi, PixelLab 24px/frame) -------
var _crumble_texture: Texture2D = null
var _crumble_loaded: bool = false

# --- TASK 96: effetto colpo sul cuore corrente (scossa + detriti) ----------
var _heart_fx_p1: float = 0.0        # ms residui dell'effetto
var _heart_fx_p2: float = 0.0
var _heart_burst_p1: bool = false     # true = vita persa (burst grande)
var _heart_burst_p2: bool = false

# --- HUD state (set externally before _draw) ------------------------------
# 1P snapshot
var _p1: Dictionary = {
        "score": 0, "lives": C.STARTING_LIVES, "energy": 5.0, "max_energy": 5.0,
        # TASK 79b: default localizzato (PISTOL/PISTOLA) invece di "PISTOL"
        # fisso: copre il frame iniziale prima del primo set_player_state.
        "weapon_name": C.get_weapon_name(C.WeaponType.PISTOL), "weapon_color": Color(0.784, 0.784, 0.196),
        "weapon_ammo": 15, "weapon_max": 15,
        # FIX (stamina salti): barra sotto quella della vita (verde/arancione/rosso).
        "stamina": 1.0, "stamina_exhausted": false,
        # Salti acquistabili con la stamina corrente (colore della barra:
        # VERDE = tutta la catena, ARANCIONE = almeno 1, ROSSO = 0).
        "stamina_jumps_left": 2, "stamina_jumps_max": 2,
        # TASK 99 (LEVEL UP): livello e punti abilità da spendere.
        "level": 1, "skill_points": 0,
        # RELIC (Task 21): stato armatura reliquia (nessuna = stringa vuota).
        "armor_name": "", "armor_color": Color.WHITE,
        "armor_charges": 0, "armor_max": 0,
}
# 2P snapshot (only used when _num_players == 2)
var _p2: Dictionary = {
        "score": 0, "lives": C.STARTING_LIVES, "energy": 5.0, "max_energy": 5.0,
        "weapon_name": C.get_weapon_name(C.WeaponType.PISTOL), "weapon_color": Color(0.784, 0.784, 0.196),
        "weapon_ammo": 15, "weapon_max": 15,
        # FIX (stamina salti): barra sotto quella della vita, P2 (verde/arancione/rosso).
        "stamina": 1.0, "stamina_exhausted": false,
        "stamina_jumps_left": 2, "stamina_jumps_max": 2,
        # TASK 99 (LEVEL UP): livello e punti abilità (P2).
        "level": 1, "skill_points": 0,
        # RELIC (Task 21): stato armatura reliquia (per P2).
        "armor_name": "", "armor_color": Color.WHITE,
        "armor_charges": 0, "armor_max": 0,
}
var _num_players: int = 1
var _remaining_treasures: int = 0

# Normalisation constant (mirror UI.cpp): ammo bar uses 15 as the max.
const _AMMO_NORMALISER: int = 15

# Built-in font for labels; we use the default Theme font (kept simple).


# ============================================================================
# Lifecycle
# ============================================================================
func _ready() -> void:
        # The HUD spans the full width and is UI_HEIGHT tall at the top.
        set_anchors_preset(Control.PRESET_TOP_WIDE)
        custom_minimum_size = Vector2(WINDOW_WIDTH, UI_HEIGHT)
        # Use set_deferred to avoid "non-equal opposite anchors" warning.
        set_deferred("size", Vector2(WINDOW_WIDTH, UI_HEIGHT))
        mouse_filter = Control.MOUSE_FILTER_IGNORE
        # FIX (HUD invisibile root cause definitiva): il HUD è ora figlio di
        # HUDLayer (CanvasLayer layer=10) nella scena MainGame.tscn.
        # I CanvasLayer sono IGNORATI dalla Camera2D → HUD sempre visibile.
        # Prima il HUD era figlio diretto di MainGame (Node2D) e la Camera2D
        # lo trasformava. Il riparentamento runtime causava che @onready var hud
        # in MainGameController perdesse il riferimento → hud = null →
        # _update_hud ritornava subito senza aggiornare.
        position = Vector2.ZERO
        load_heart_sprite("res://assets/sprites/ui_heart.png")
        _load_crumble_sheet()


func _process(delta: float) -> void:
        # TASK 96: avanzamento degli effetti colpo/vita-persa sui cuori:
        # il ridisegno arriva dai controller ogni physics frame, ma gli
        # effetti vivono sul tempo REALE (funzionano anche in pausa bonus).
        if _heart_fx_p1 > 0.0 or _heart_fx_p2 > 0.0:
                _heart_fx_p1 = maxf(0.0, _heart_fx_p1 - delta * 1000.0)
                _heart_fx_p2 = maxf(0.0, _heart_fx_p2 - delta * 1000.0)
                queue_redraw()


## TASK 96: carica lo sheet 4-stadi del cuore sgretolabile (Pattern
## SpriteManager: Image.load diretto, bypass import system). Se manca si
## resta sul cuore singolo/procedurale con degrado per stadio.
func _load_crumble_sheet() -> void:
        var path := "res://assets/sprites/ui_heart_crumble_sheet.png"
        var abs_path: String = ProjectSettings.globalize_path(path)
        if not FileAccess.file_exists(abs_path):
                return
        var img := Image.new()
        if img.load(abs_path) == OK:
                _crumble_texture = ImageTexture.create_from_image(img)
                _crumble_loaded = _crumble_texture != null


# ----------------------------------------------------------------------------
# loadHeartSprite: load the heart PNG. Returns true on success.
# Mirrors UI::loadHeartSprite(path). If the file is missing, `heartLoaded`
# stays false and drawHeart() will use the procedural fallback.
# ----------------------------------------------------------------------------
func load_heart_sprite(path: String) -> bool:
        # FIX (cuoricini invisibili): usava load() (ResourceLoader) che ritorna
        # null se .godot/imported/ è vuoto. Ora usa Image.load() + ImageTexture.
        var abs_path: String = ProjectSettings.globalize_path(path)
        if not FileAccess.file_exists(abs_path):
                _heart_loaded = false
                _heart_texture = null
                return false
        var img := Image.new()
        if img.load(abs_path) == OK:
                _heart_texture = ImageTexture.create_from_image(img)
                _heart_loaded = _heart_texture != null
                return _heart_loaded
        _heart_loaded = false
        _heart_texture = null
        return false


# ============================================================================
# Public API  (set state before redrawing)
# ============================================================================
# Set the 1P snapshot. The Dictionary may contain any subset of:
# score, lives, energy, max_energy, weapon_name, weapon_color, weapon_ammo,
# weapon_max.
func set_player_state(snap: Dictionary) -> void:
        # TASK 96: rileva il colpo (energia che scende) e la vita persa
        # (vite che scendono) per gli effetti sul cuore corrente.
        var prev_e: float = float(_p1.get("energy", 0.0))
        var prev_l: int = int(_p1.get("lives", 0))
        for k in snap.keys():
                _p1[k] = snap[k]
        var new_e: float = float(_p1.get("energy", 0.0))
        var new_l: int = int(_p1.get("lives", 0))
        if new_l < prev_l:
                _heart_fx_p1 = 620.0
                _heart_burst_p1 = true
        elif new_e < prev_e - 0.001:
                _heart_fx_p1 = 380.0
                _heart_burst_p1 = false
        queue_redraw()


# Set the 2P snapshot (used only when num_players == 2).
func set_player2_state(snap: Dictionary) -> void:
        var prev_e: float = float(_p2.get("energy", 0.0))
        var prev_l: int = int(_p2.get("lives", 0))
        for k in snap.keys():
                _p2[k] = snap[k]
        var new_e: float = float(_p2.get("energy", 0.0))
        var new_l: int = int(_p2.get("lives", 0))
        if new_l < prev_l:
                _heart_fx_p2 = 620.0
                _heart_burst_p2 = true
        elif new_e < prev_e - 0.001:
                _heart_fx_p2 = 380.0
                _heart_burst_p2 = false
        queue_redraw()


# Set the number of players (1 or 2) - selects the layout.
func set_num_players(n: int) -> void:
        _num_players = clampi(n, 1, 2)
        queue_redraw()


# Set the remaining treasures count (drives the "boss is coming" trigger).
func set_remaining_treasures(n: int) -> void:
        _remaining_treasures = n
        queue_redraw()


# FIX (HUD last hit enemy): stato del nemico colpito dal player.
# Mostra nome + barra energia in alto al centro dell'HUD.
var _last_hit_enemy_name: String = ""
var _last_hit_enemy_hp: int = 0
var _last_hit_enemy_max_hp: int = 0

func set_last_hit_enemy(name: String, hp: int, max_hp: int) -> void:
        _last_hit_enemy_name = name
        _last_hit_enemy_hp = hp
        _last_hit_enemy_max_hp = max_hp
        queue_redraw()


# Set the boss HP bar (shown during boss fights).
var _boss_hp: int = 0
var _boss_max_hp: int = 0
var _boss_type: int = 0
var _show_boss_bar: bool = false

func set_boss_hp(hp: int, max_hp: int, boss_type: int) -> void:
        _boss_hp = hp
        _boss_max_hp = max_hp
        _boss_type = boss_type
        _show_boss_bar = true
        queue_redraw()

func hide_boss_bar() -> void:
        _show_boss_bar = false
        queue_redraw()


# ============================================================================
# Drawing
# ============================================================================
func _draw() -> void:
        # Background bar
        draw_rect(Rect2(0, 0, WINDOW_WIDTH, UI_HEIGHT), color_bg)
        if _num_players == 1:
                _draw_1p()
        else:
                _draw_2p()
        # FIX (HUD last hit enemy): disegna nome + barra energia del nemico
        # colpito al centro dell'HUD. Solo se c'è un nemico valido.
        if _last_hit_enemy_name != "" and _last_hit_enemy_max_hp > 0:
                _draw_last_hit_enemy()
        # Boss HP bar (shown during boss fights)
        # FIX (doppia barra boss): disabilitato perché BossRoomController
        # disegna già la sua barra HP vicino al nome del boss.
        # if _show_boss_bar and _boss_max_hp > 0:
        #         _draw_boss_bar()


# FIX (HUD last hit enemy): disegna nome nemico + barra energia al centro.
# Usa lo stesso gradiente verde→arancione→rosso della barra player.
func _draw_last_hit_enemy() -> void:
        # FIX (posizionamento): spostato più a destra (center_x = 1100 invece di 960)
        # per evitare sovrapposizione con "Treasures remaining" a x=700.
        var center_x: float = 1100.0
        var bar_w: float = 180.0
        var bar_h: float = 8.0
        # FIX (margine): bar_y aumentato da 30 a 38 per più spazio tra nome e barra
        var bar_y: float = 38.0
        var bar_x: float = center_x - bar_w * 0.5
        # Etichetta "ENEMY" sopra la barra (y=10, più in alto)
        # TASK 44: localizzata ("NEMICO:" in IT — inizio nome spostato a +75
        # perché l'etichetta italiana è un carattere più lunga).
        _draw_label_colored(I18n.t("hud.enemy"), bar_x, 10.0, Color(0.9, 0.5, 0.5))
        # Nome del nemico (più spazio: +70 invece di +50)
        _draw_label_colored(_last_hit_enemy_name, bar_x + 75, 10.0, Color(1.0, 0.9, 0.5))
        # Background barra
        draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(0.1, 0.0, 0.0, 0.95), true)
        draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(0.8, 0.6, 0.2), false, 1.0)
        # Calcola ratio e colore (gradiente verde→arancione→rosso)
        var r: float = float(_last_hit_enemy_hp) / float(_last_hit_enemy_max_hp) if _last_hit_enemy_max_hp > 0 else 0.0
        r = clampf(r, 0.0, 1.0)
        if r > 0.0:
                var bar_col: Color
                if r > 0.5:
                        var t: float = (1.0 - r) * 2.0
                        bar_col = Color(t * 1.0, 0.9 - t * 0.3, 0.0)
                else:
                        var t2: float = (0.5 - r) * 2.0
                        bar_col = Color(1.0, 0.6 - t2 * 0.5, 0.0)
                # Barra energia
                draw_rect(Rect2(bar_x, bar_y, bar_w * r, bar_h), bar_col, true)
                # Highlight superiore
                var hl_col: Color = Color(bar_col.r + 0.2, bar_col.g + 0.2, bar_col.b + 0.2, 0.6)
                draw_rect(Rect2(bar_x, bar_y, bar_w * r, 3.0), hl_col, true)
        # HP numerico (es. "3/5")
        var hp_text: String = str(_last_hit_enemy_hp) + "/" + str(_last_hit_enemy_max_hp)
        _draw_label_colored(hp_text, bar_x + bar_w + 8, bar_y - 4, Color(1.0, 0.9, 0.5))


func _draw_boss_bar() -> void:
        var bar_x: float = 300.0
        var bar_y: float = 10.0
        var bar_w: float = 424.0
        var bar_h: float = 16.0
        # Background
        draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(0.1, 0.0, 0.0, 0.8), true)
        # HP fill
        var hp_ratio: float = float(_boss_hp) / float(_boss_max_hp)
        var hp_color: Color = Color(0.8, 0.2, 0.1) if hp_ratio < 0.3 else Color(0.9, 0.5, 0.1)
        draw_rect(Rect2(bar_x + 2, bar_y + 2, (bar_w - 4) * hp_ratio, bar_h - 4), hp_color, true)
        # Border
        draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(0.8, 0.6, 0.2), false, 2)
        # Label
        _draw_label_colored(I18n.t("hud.boss"), bar_x + 4, bar_y - 14, Color(0.9, 0.7, 0.3))


# --- 1-player layout (mirror UI::render single-player) ---------------------
func _draw_1p() -> void:
        # SCORE
        _draw_label(I18n.t("hud.score"), 10, 10)
        _draw_label_int(_p1.score, 10, 30, color_score)
        # LIVES (hearts) — TASK 26: oltre 5 cuori non si disegna la fila
        # (si sovrapponeva a ENERGY/WPN): si mostra il numero con la "x"
        # + UN solo simbolo di cuore (es. "6x ♥" = 6 vite).
        _draw_label(I18n.t("hud.lives"), 150, 10)
        _draw_lives_row(int(_p1.lives), 160.0, 35.0, 12.0, 27.0,
                        float(_p1.energy) / maxf(1.0, float(_p1.max_energy)),
                        _heart_fx_p1, _heart_burst_p1)
        # TASK 96: barra ENERGIA RIMOSSA — lo stato di salute si legge dal
        # cuore corrente che si sgretola (vedi _draw_lives_row). Lo slot
        # x=280 resta alla sola barra STAMINA (libera spazio in alto).
        # STAMINA (Task 37/96): VERDE piena (tutti i salti disponibili),
        # ARANCIONE finché resta almeno 1 salto, ROSSA a zero (lampeggia
        # finché la ricarica non è completa). Con più Salti Aggiuntivi la
        # soglia colore segue i salti (non più fissa a metà barra).
        _draw_stamina_bar(280, 52, 100, 10,
                _p1.stamina, _p1.stamina_exhausted,
                int(_p1.get("stamina_jumps_left", -1)),
                int(_p1.get("stamina_jumps_max", 2)))
        # WPN — TASK 26: le armi speciali (reliquie) NON mostrano il nome
        # (sovrapposizione coi cuori); resta l'header WPN + il contatore AMMO.
        _draw_label(I18n.t("hud.wpn"), 420, 10)
        if not str(_p1.weapon_name).is_empty():
                _draw_label_colored(_p1.weapon_name, 420, 30, _p1.weapon_color)
        # AMMO (numero colpi invece di barra)
        _draw_label(I18n.t("hud.ammo"), 570, 10)
        _draw_label_int(_p1.weapon_ammo, 570, 30, color_ammo)
        # RELIC (Task 21): stato ARMATURA nello slot libero tra AMMO e la
        # barra del nemico (x=870..1010). Nessuna armatura = non disegna.
        _draw_armor_status(_p1, 870, 10)
        # TRES — TASK 44: localizzata ("Tesori rimasti:" in IT)
        _draw_label(I18n.t("hud.treasures"), 700, 10)
        _draw_label_int(_remaining_treasures, 700, 30, color_score)
        # TASK 99 (LEVEL UP): livello (dorato) sotto lo score; se ci sono
        # punti abilità da spendere, badge lampeggiante a fianco.
        _draw_level_status(_p1, 10, 58)


# --- 2-player layout (mirror UI::render two-player) ------------------------
# FIX (layout 2P su schermo intero): il layout originale era pensato per una
# finestra ~900px (P2 a x=560): su 1920px la sezione P2 restava pigiata al
# centro-sinistra con oltre metà schermo vuota. Ora il layout è a tutta
# larghezza e SPECULARE: P1 a sinistra, tesori al centro, P2 a destra
# (ogni giocatore ha "il suo angolo" leggibile con la coda dell'occhio).
func _draw_2p() -> void:
        # === PLAYER 1 (left) ===
        _draw_label_colored("P1", 10, 10, color_p1_label)
        _draw_label_int(_p1.score, 10, 30, color_score)
        _draw_label(I18n.t("hud.life"), 80, 10)
        _draw_lives_row(int(_p1.lives), 90.0, 35.0, 11.0, 24.0,
                        float(_p1.energy) / maxf(1.0, float(_p1.max_energy)),
                        _heart_fx_p1, _heart_burst_p1)
        # TASK 96: barra ENERGIA RIMOSSA (cuore corrente sgretolabile);
        # STAMINA P1 al suo posto (verde/arancione/rosso).
        _draw_stamina_bar(180, 50, 60, 8,
                _p1.stamina, _p1.stamina_exhausted,
                int(_p1.get("stamina_jumps_left", -1)),
                int(_p1.get("stamina_jumps_max", 2)))
        if not str(_p1.weapon_name).is_empty():
                _draw_label_colored(_p1.weapon_name, 250, 10, _p1.weapon_color)
        _draw_label_int(_p1.weapon_ammo, 250, 30, color_score)
        # RELIC (Task 21): stato ARMATURA di P1 (tra arma e tesori: x=330).
        _draw_armor_status(_p1, 330, 10)
        # TASK 99 (LEVEL UP): livello sotto lo score di P1.
        _draw_level_status(_p1, 10, 58)

        # === TREASURES (center) — centrata su schermo 1920px. x=800: il
        # testo (~170px, fino a ~970) NON collide con la barra "last hit
        # enemy" che parte da x=1010 (margine 40px) ===
        _draw_label(I18n.t("hud.treasures"), 800, 10)
        _draw_label_int(_remaining_treasures, 800, 30, color_score)

        # === PLAYER 2 (right, speculare a P1) ===
        _draw_label_colored("P2", 1560, 10, color_p2_label)
        _draw_label_int(_p2.score, 1560, 30, color_score)
        _draw_label(I18n.t("hud.life"), 1630, 10)
        _draw_lives_row(int(_p2.lives), 1640.0, 35.0, 11.0, 24.0,
                        float(_p2.energy) / maxf(1.0, float(_p2.max_energy)),
                        _heart_fx_p2, _heart_burst_p2)
        # TASK 96: barra ENERGIA RIMOSSA (cuore corrente sgretolabile);
        # STAMINA P2 al suo posto (verde/arancione/rosso).
        _draw_stamina_bar(1730, 50, 60, 8,
                _p2.stamina, _p2.stamina_exhausted,
                int(_p2.get("stamina_jumps_left", -1)),
                int(_p2.get("stamina_jumps_max", 2)))
        if not str(_p2.weapon_name).is_empty():
                _draw_label_colored(_p2.weapon_name, 1800, 10, _p2.weapon_color)
        _draw_label_int(_p2.weapon_ammo, 1800, 30, color_score)
        # RELIC (Task 21): stato ARMATURA di P2 (riga bassa libera sotto
        # vite/energia: x=1640, i rombi restano dentro la barra di 80px).
        _draw_armor_status(_p2, 1640, 52)
        # TASK 99 (LEVEL UP): livello sotto lo score di P2 (speculare a P1).
        _draw_level_status(_p2, 1560, 58)


# ----------------------------------------------------------------------------
# TASK 99 (LEVEL UP): riga "LV n" dorata + badge "PUNTI +n" lampeggiante
# quando ci sono punti abilità non ancora spesi (richiama il player alla
# modale). Il badge pulsa a ~4 Hz in oro chiaro, stile warning soft.
# TASK 105 (NEW GAME PLUS): badge "NG+"/"NG++" rosso-oro davanti a LV quando
# la run corrente è oltre la partita base (feedback immediato del tier).
# ----------------------------------------------------------------------------
func _draw_level_status(snap: Dictionary, x: float, y: float) -> void:
        var lv: int = int(snap.get("level", 1))
        var pts: int = int(snap.get("skill_points", 0))
        var badge_x: float = x
        if GameManager and GameManager.newgameplus_tier > 0:
                var ngp_label: String = "NG+" if GameManager.newgameplus_tier == 1 else "NG++"
                var ngp_pulse: float = 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.008)
                _draw_label_colored(ngp_label, x, y,
                                Color(1.0, 0.45, 0.25, ngp_pulse))
                badge_x = x + 44.0
        _draw_label_colored(I18n.t("hud.level") % lv, badge_x, y, Color(1.0, 0.84, 0.25))
        if pts > 0:
                var blink: float = 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.012)
                _draw_label_colored(I18n.t("hud.skill_points") % pts,
                                badge_x + 58.0, y, Color(1.0, 0.92, 0.45, blink))


# ----------------------------------------------------------------------------
# RELIC (Task 21): stato ARMATURA reliquia — nome corto colorato + cariche
# come rombi (max 10 visibili; oltre si raggruppano x5). Nessuna armatura
# = non disegna nulla.
# ----------------------------------------------------------------------------
func _draw_armor_status(snap: Dictionary, x: float, y: float) -> void:
        var name_s: String = str(snap.get("armor_name", ""))
        if name_s == "":
                return
        var col: Color = snap.get("armor_color", Color.WHITE)
        var charges: int = int(snap.get("armor_charges", 0))
        var armor_max: int = int(snap.get("armor_max", 0))
        # Nome corto + cariche residue sulla stessa riga (stile WPN/AMMO).
        _draw_label_colored(name_s + " " + str(charges), x, y, col)
        # Tacche a rombo sotto il nome (durabilita' residua a colpo d'occhio;
        # le cariche mancanti restano come fantasmi tenui).
        var pips: int = mini(charges, 10)
        var pip_total: int = mini(armor_max, 10)
        for i in pip_total:
                var px: float = x + 4.0 + float(i) * 8.0
                var py: float = y + 20.0
                if i < pips:
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(px, py - 3.0), Vector2(px + 3.0, py),
                                Vector2(px, py + 3.0), Vector2(px - 3.0, py)]),
                                Color(col.r, col.g, col.b, 0.9))
                else:
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(px, py - 3.0), Vector2(px + 3.0, py),
                                Vector2(px, py + 3.0), Vector2(px - 3.0, py)]),
                                Color(col.r, col.g, col.b, 0.18))


# ----------------------------------------------------------------------------
# TASK 26/96 — fila dei cuori delle vite: fino a 5 cuori singoli; oltre,
# numero + "x" + UN solo cuore (es. "6x ♥" = 6 vite).
#
# TASK 96 (cuori al posto della barra vita): il CUORE CORRENTE (l'ultimo
# della fila, quello che si sta consumando) mostra lo SGRETOLOMENTO
# legato all'energia residua: stadio 0 = integro (energia piena), stadio
# 3 = quasi distrutto (energia al minimo). Quando l'energia arriva a 0
# la vita è persa: il cuore sparisce del tutto e la fila si accorcia.
# Le vite "di scorta" (cuori precedenti) restano integre. Al colpo
# recente: scossa del cuore + detriti che cadono (fx_ms > 0).
# ----------------------------------------------------------------------------
func _draw_lives_row(lives: int, x: float, y: float, size: float,
                spacing: float, energy_ratio: float = 1.0,
                fx_ms: float = 0.0, fx_burst: bool = false) -> void:
        if lives <= 0:
                return
        var stage: int = _heart_crumble_stage(energy_ratio)
        if lives <= 5:
                for i in lives:
                        var is_current: bool = i == lives - 1
                        var st: int = stage if is_current else 0
                        var jx: float = 0.0
                        var jy: float = 0.0
                        if is_current and fx_ms > 0.0:
                                # scossa del cuore colpito (6-7 Hz, si smorza)
                                var k: float = fx_ms / 380.0
                                jx = sin(fx_ms * 0.042) * 1.6 * k
                                jy = cos(fx_ms * 0.061) * 1.1 * k
                        _draw_heart(x + float(i) * spacing + jx, y + jy, size, st)
                        if is_current and fx_ms > 0.0:
                                _draw_heart_debris(x + float(i) * spacing, y,
                                                size, fx_ms, fx_burst)
                return
        # Oltre 5: contatore "Nx" + simbolo singolo (il cuore corrente,
        # con lo sgretolamento dell'energia).
        var txt: String = str(lives) + "x"
        _draw_label_colored(txt, x, y - 12.0, color_heart_fill)
        var font := get_theme_default_font()
        if font == null:
                font = ThemeDB.fallback_font
        var txt_w: float = 34.0
        if font != null:
                txt_w = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT,
                        -1, 16).x
        _draw_heart(x + txt_w + size + 2.0, y, size, stage)
        if fx_ms > 0.0:
                _draw_heart_debris(x + txt_w + size + 2.0, y, size, fx_ms, fx_burst)


## Stadio di sgretolamento del cuore corrente dall'energia residua:
## ogni 20% di energia persa avanza di uno stadio (max 3). Pura funzione
## del ratio — testabile da test_task96_hearts (B). Con max_energy 5:
## 5->0, 4->1, 3->2, 2->3, 1->3 (l'ultimo colpo prima della morte mostra
## il cuore quasi distrutto).
static func _heart_crumble_stage(energy_ratio: float) -> int:
        var r: float = clampf(energy_ratio, 0.0, 1.0)
        # +0.001: epsilon anti-FP (1.0-0.8 = 0.1999... -> int(0.999)=0 sbagliato)
        return clampi(int((1.0 - r + 0.001) / 0.2), 0, 3)


## Detriti del cuore colpito: 5 (9 nel burst di vita persa) frammenti
## rossi che cadono sotto il cuore e svaniscono. Deterministici (seed =
## indice), niente RNG per frame.
func _draw_heart_debris(x: float, y: float, size: float,
                fx_ms: float, burst: bool) -> void:
        var total_ms: float = 620.0 if burst else 380.0
        var k: float = clampf(1.0 - fx_ms / total_ms, 0.0, 1.0)  # 0->1
        var n: int = 9 if burst else 5
        for i in n:
                var a: float = (float(i) / float(n) - 0.5) * 1.7
                var dx: float = a * size * (0.7 + 0.5 * float((i * 37) % 3) / 2.0)
                var dy: float = size * 0.45 + k * k * (26.0 + 10.0 * float(i % 3))
                var al: float = (1.0 - k) * 0.9
                var s: float = 2.4 - float(i % 2) * 0.9
                var col := color_heart_fill if i % 2 == 0 else color_heart_outline
                draw_rect(Rect2(x + dx - s * 0.5, y + dy, s, s),
                                Color(col.r, col.g, col.b, al), true)


# ----------------------------------------------------------------------------
# drawHeart(x, y, size, stage): draws a heart at (x, y) with radius `size`.
# TASK 96: `stage` (0-3) = stadio di sgretolamento del cuore corrente.
#   * Se lo sheet PixelLab 4-stadi è caricato, disegna il frame dello
#     stadio via draw_texture_rect_region (24px, scalato a size*2).
#   * Altrimenti usa il PNG singolo ui_heart.png (solo stadio 0) con
#     degrado procedurale per gli stadi (rimpicciolito + sbiadito).
#   * Fallback finale: cuore procedurale (mirror UI.cpp) con degrado.
# ----------------------------------------------------------------------------
func _draw_heart(x: float, y: float, size: float, stage: int = 0) -> void:
        var st: int = clampi(stage, 0, 3)
        if _crumble_loaded and _crumble_texture != null:
                var fw: float = float(_crumble_texture.get_width()) / 4.0
                var fh: float = float(_crumble_texture.get_height())
                var disp: float = size * 2.0
                draw_texture_rect_region(_crumble_texture,
                                Rect2(x - disp * 0.5, y - disp * 0.5, disp,
                                                disp * (fh / fw)),
                                Rect2(fw * float(st), 0.0, fw, fh),
                                Color(1.0, 1.0, 1.0, 1.0), false,
                                CanvasItem.TEXTURE_FILTER_NEAREST)
                return
        if _heart_loaded and _heart_texture != null:
                # Scale so the sprite is ~size*2 px wide (mirror UI.cpp:scale = size/16).
                var scale: float = size / 16.0
                var mod := Color(1.0, 1.0, 1.0, 1.0)
                if st > 0:
                        # fallback senza sheet: cuore che rimpicciolisce e sbiadisce
                        var k: float = 1.0 - 0.18 * float(st)
                        scale *= k
                        mod = Color(1.0, 1.0, 1.0, 0.95 - 0.18 * float(st))
                var w: float = _heart_texture.get_width() * scale
                var h: float = _heart_texture.get_height() * scale
                var rect := Rect2(x - w / 2.0, y - h / 2.0, w, h)
                draw_texture_rect(_heart_texture, rect, false, mod)
                return
        # degrado procedurale
        var sz: float = size * (1.0 - 0.15 * float(st))
        _draw_detailed_heart(x, y, sz,
                        Color(color_heart_fill.r, color_heart_fill.g,
                                        color_heart_fill.b,
                                        1.0 - 0.15 * float(st)),
                        color_heart_outline)


# ----------------------------------------------------------------------------
# drawDetailedHeart (procedural fallback): mirror of the standalone function
# in UI.cpp. Two semicircles + triangle + white highlight.
# ----------------------------------------------------------------------------
func _draw_detailed_heart(x: float, y: float, size: float,
                                                  fill: Color, outline: Color) -> void:
        # Left lobe
        draw_circle(Vector2(x - size / 2.0, y - size / 4.0), size / 2.0, fill)
        # Right lobe
        draw_circle(Vector2(x, y - size / 4.0), size / 2.0, fill)
        # Bottom triangle (pointed tip)
        var tip := PackedVector2Array([
                Vector2(x - size, y),
                Vector2(x + size, y),
                Vector2(x, y + size),
        ])
        draw_colored_polygon(tip, fill)
        # Outline (drawn as line segments)
        _draw_circle_outline(Vector2(x - size / 2.0, y - size / 4.0), size / 2.0, outline, 1.5)
        _draw_circle_outline(Vector2(x, y - size / 4.0), size / 2.0, outline, 1.5)
        draw_polyline(tip + PackedVector2Array([tip[0]]), outline, 1.5, true)
        # White highlight (small dot in upper-left)
        draw_circle(Vector2(x - size / 3.0, y - size / 4.0), 1.5,
                Color(1, 1, 1, 200.0 / 255.0))


# Draw a circle outline as a polyline (Godot has no direct outline API for
# CircleShape2D in _draw; we approximate with a thin line loop).
func _draw_circle_outline(center: Vector2, radius: float,
                                                  color: Color, width: float) -> void:
        var pts := PackedVector2Array()
        var segs: int = 24
        for i in segs:
                var a: float = TAU * i / segs
                pts.append(center + Vector2(cos(a), sin(a)) * radius)
        draw_polyline(pts + PackedVector2Array([pts[0]]), color, width, true)


# Draw a label with a black outline (mirror of drawTextOutlined()).
func _draw_label(text: String, x: float, y: float) -> void:
        _draw_label_colored(text, x, y, color_label)


func _draw_label_colored(text: String, x: float, y: float, color: Color) -> void:
        # FIX (font null): get_theme_default_font() può ritornare null se
        # non c'è un tema assegnato. Usiamo ThemeDB.fallback_font come fallback.
        var font := get_theme_default_font()
        if font == null:
                font = ThemeDB.fallback_font
        if font == null:
                return  # nessun font disponibile, non disegnare
        var font_size: int = 16
        # 4 shadow copies (offset by ±2 px)
        for off in [Vector2(-2, 0), Vector2(2, 0), Vector2(0, -2), Vector2(0, 2)]:
                draw_string(font, Vector2(x + off.x, y + off.y + font_size), text,
                        HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.BLACK)
        draw_string(font, Vector2(x, y + font_size), text,
                HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


# Draw an integer as outlined text (used for SCORE/TREASURES/AMMO count).
func _draw_label_int(value: int, x: float, y: float, color: Color) -> void:
        _draw_label_colored(str(value), x, y, color)


# FIX (stamina salti): barra della STAMINA sotto quella della vita.
# Colore legato ai salti usati (Task 37): ROSA quando è piena (0 salti
# usati, 2 disponibili), ARANCIONE dopo il 1° salto (metà barra), ROSSA
# dopo il 2° salto (barra svuotata). Ogni salto consuma 1/2 della barra;
# si ricarica da sola quando il player non salta. Quando il player è
# "stanco" (2° salto consecutivo: barra svuotata) la barra LAMPEGGIA in
# rosso — con una traccia minima visibile anche a barra vuota — finché non
# si è ricaricata completamente: in quel momento torna ROSA e il player può
# di nuovo saltare.
func _draw_stamina_bar(x: float, y: float, w: float, h: float,
                                           ratio: float, exhausted: bool,
                                           jumps_left: int = -1,
                                           jumps_max: int = 2) -> void:
        # Sfondo scuro + bordo (stesso stile delle altre barre)
        draw_rect(Rect2(x, y, w, h), color_energy_bg, true)
        draw_rect(Rect2(x, y, w, h), color_energy_border, false, 1.5)
        var r: float = clampf(ratio, 0.0, 1.0)
        # Il ROSSO del 2° salto deve comparire SUBITO, anche a barra
        # completamente vuota (r=0): stub minimo che lampegga.
        var fill_w: float = w * r
        if exhausted and r <= 0.0:
                fill_w = w * 0.12
        if fill_w <= 0.0:
                return
        # Colore per numero di salti DISPONIBILI: con più Salti Aggiuntivi
        # il costo a salto scende (barra_max / salti_massimi), quindi la
        # soglia colore segue i SALTI (VERDE = catena completa, ARANCIONE =
        # almeno uno, ROSSO = zero), non più la metà fissa della barra.
        var fill: Color
        if jumps_left >= 0:
                fill = _stamina_fill_color_jumps(jumps_left, maxi(1, jumps_max))
        else:
                fill = _stamina_fill_color(r)
        # Quando il player è esausto (ultimo salto della catena) la barra
        # LAMPEGGIA in rosso chiaro/scuro finché la ricarica non è completa.
        if exhausted:
                var blink_on: bool = fmod(Time.get_ticks_msec() / 1000.0, 0.36) < 0.18
                fill = Color(1.00, 0.38, 0.38) if blink_on else Color(0.45, 0.06, 0.10)
        draw_rect(Rect2(x, y, fill_w, h), fill, true)
        # Highlight superiore (riflesso luce)
        draw_rect(Rect2(x, y, fill_w, 2.0),
                Color(minf(fill.r + 0.25, 1.0), minf(fill.g + 0.15, 1.0),
                        minf(fill.b + 0.25, 1.0), 0.55), true)


# Colore del riempimento per numero di salti DISPONIBILI (Task 37;
# TASK 96: piena VERDE, era ROSA — feedback utente: "la barra da che era
# rosa diventa verde, gli altri colori non cambiano"):
#   * ratio >= 1.0  → VERDE      (barra piena: 2 salti disponibili)
#   * ratio >= 0.5  → ARANCIONE  (dopo il 1° salto: 1 salto disponibile)
#   * ratio <  0.5  → ROSSO      (dopo il 2° salto: 0 salti disponibili)
# Pura funzione del ratio (testabile da test_stamina_weapons A9 e
# test_task96_hearts A): il lampeggio da esausto vive nel _draw.
func _stamina_fill_color(ratio: float) -> Color:
        if ratio >= 0.999:
                return Color(0.22, 0.85, 0.35)   # VERDE (TASK 96, era rosa)
        if ratio >= 0.5:
                return Color(1.00, 0.55, 0.10)   # ARANCIONE (invariato)
        return Color(0.92, 0.16, 0.16)           # ROSSO (invariato)


## Colore del riempimento per numero di SALTI disponibili (nuova semantica
## coi Salti Aggiuntivi: il costo a salto è barra_max/salti_massimi, la
## metà della barra non è più la soglia giusta):
##   * jumps_left >= jumps_max → VERDE     (catena completa di salti)
##   * jumps_left >= 1          → ARANCIONE (almeno un salto ancora)
##   * jumps_left <= 0          → ROSSO     (zero salti)
func _stamina_fill_color_jumps(jumps_left: int, jumps_max: int) -> Color:
        if jumps_left >= maxi(1, jumps_max):
                return Color(0.22, 0.85, 0.35)   # VERDE (TASK 96)
        if jumps_left >= 1:
                return Color(1.00, 0.55, 0.10)   # ARANCIONE (invariato)
        return Color(0.92, 0.16, 0.16)           # ROSSO (invariato)


# Draw a horizontal bar (mirror of the energy/ammo bar in UI.cpp).
# Background = gray rounded rectangle + colored foreground proportional to ratio.
func _draw_bar(x: float, y: float, w: float, h: float,
                           ratio: float, fg_color: Color) -> void:
        # Background (gray with darker outline)
        draw_rect(Rect2(x, y, w, h), color_energy_bg, true)
        draw_rect(Rect2(x, y, w, h), color_energy_border, false, 2.0)
        # Foreground (clamped ratio)
        var r: float = clampf(ratio, 0.0, 1.0)
        if r > 0.0:
                draw_rect(Rect2(x, y, w * r, h), fg_color, true)


# TASK 96: _draw_energy_bar RIMOSSA — la barra vita è sostituita dallo
# sgretolamento del cuore corrente (vedi _draw_lives_row/_draw_heart).
