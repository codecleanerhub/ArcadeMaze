## Hammer.gd - Il martello di Thor (Mjolnir) lanciato dal player.
## ============================================================
## Nuova meccanica richiesta dall'utente:
##   * quando il player ha il martello e spara, NON esce un proiettile
##     generico: viene lanciato IL MARTELLO STESSO, che vola roteando
##     (stile Mjolnir) fino al primo bersaglio;
##   * se colpisce un NEMICO infligge il 50% dei suoi HP massimi;
##   * se colpisce un MURO INTERNO del labirinto lo ROMPE con effetto
##     sgretolamento, creando un passaggio scorciatoia usabile sia dal
##     player che dai nemici (i muri di bordo NON si rompono, altrimenti
##     si creerebbe un ulteriore effetto Pac-Man);
##   * dopo l'impatto il martello RITORNA in mano al player (fase di
##     ritorno, scia dorata e rotazione piu' veloce) finche' ha usi
##     residui: dopo il SECONDO lancio il martello scompare dal player.
##
## Questo nodo possiede SOLO lo stato di volo e il DISEGNO (rotazione +
## scia + aura elettrica). La logica di gioco (collisioni, danni, rottura
## muri, ricattura) vive in MainGameController._update_thrown_hammer,
## che ogni frame muove il nodo e chiama start_return() quando serve.
## ============================================================
extends Node2D

const C = preload("res://scripts/core/GameConstants.gd")

## Fasi di volo.
enum Phase { OUTBOUND, RETURN }

## Direzione di lancio (vettore unitario).
var dir: Vector2 = Vector2(1.0, 0.0)
## Velocita' corrente in px/frame @60fps (scalata per delta reale dal controller).
var speed: float = 13.0
## Fase corrente di volo.
var phase: int = Phase.OUTBOUND
## Rotazione corrente del martello (gradi, usata dal _draw).
var spin_deg: float = 0.0
## Ultimi N punti percorsi: disegnati come sciafantasma.
var trail: Array = []
## Distanza percorsa in andata (px) — per il range massimo.
var travelled_px: float = 0.0
## Flag: impatto avvenuto (il controller la legge per gli effetti one-shot).
var impacted: bool = false

## Distanza massima di volo in andata prima del ritorno automatico
## (~25 celle: attraversa tutto il labirinto in linea d'aria, ma i muri
## fermano prima quasi sempre; attraverso i tunnel puo' wrappare).
const MAX_TRAVEL_PX: float = 1600.0
## Dimensione del disegno del martello in volo (px).
const DRAW_SIZE: float = 46.0

## Cache statica della texture (condivisa da tutte le istanze).
static var _tex_cache: Texture2D = null


func _ready() -> void:
        z_index = 5  # sopra il pavimento, sotto l'HUD


static func _get_texture() -> Texture2D:
        if _tex_cache != null:
                return _tex_cache
        var abs_path: String = ProjectSettings.globalize_path(
                        "res://assets/sprites/collectibles/item_hammer.png")
        if FileAccess.file_exists(abs_path):
                var img := Image.new()
                if img.load(abs_path) == OK:
                        _tex_cache = ImageTexture.create_from_image(img)
                        return _tex_cache
        push_warning("[Hammer] item_hammer.png non trovato: fallback procedurale")
        return null


## Passa in fase di ritorno: inverte la direzione concettuale e accelera la
## rotazione. Chiamato dal controller all'impatto (o a fine corsa).
func start_return() -> void:
        if phase == Phase.RETURN:
                return
        phase = Phase.RETURN
        speed = 16.0
        spin_deg = fmod(spin_deg, 360.0)


## Registra un punto della scia (chiamato dal controller a ogni frame).
func push_trail_point(p: Vector2) -> void:
        trail.append(p)
        if trail.size() > 5:
                trail.pop_front()


func _draw() -> void:
        var tex: Texture2D = _get_texture()
        # --- Scia fantasma (4 copie decrescenti in alpha) ---
        for i in range(trail.size()):
                var t: float = float(i + 1) / float(trail.size() + 1)
                var alpha: float = 0.10 + 0.16 * t
                var ghost_size: float = DRAW_SIZE * (0.55 + 0.35 * t)
                var gp: Vector2 = trail[i]
                if tex != null:
                        var prev_rot: float = spin_deg - (trail.size() - i) * 34.0
                        draw_set_transform(gp, deg_to_rad(prev_rot),
                                        Vector2.ONE * (ghost_size / DRAW_SIZE))
                        draw_texture_rect(tex,
                                        Rect2(-DRAW_SIZE / 2.0, -DRAW_SIZE / 2.0,
                                                        DRAW_SIZE, DRAW_SIZE),
                                        false, Color(1, 1, 1, alpha))
                else:
                        draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
                        draw_circle(gp, ghost_size * 0.3,
                                        Color(0.65, 0.7, 0.8, alpha))
        draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
        # --- Aura elettrica attorno al martello ---
        var aura_col: Color = Color(0.45, 0.75, 1.0, 0.16)
        if phase == Phase.RETURN:
                aura_col = Color(1.0, 0.82, 0.35, 0.18)
        draw_circle(Vector2.ZERO, DRAW_SIZE * 0.62, aura_col)
        draw_circle(Vector2.ZERO, DRAW_SIZE * 0.44, aura_col * Color(1, 1, 1, 1.35))
        # --- Il martello (ruota su se stesso come Mjolnir) ---
        if tex != null:
                draw_set_transform(Vector2.ZERO, deg_to_rad(spin_deg), Vector2.ONE)
                draw_texture_rect(tex,
                                Rect2(-DRAW_SIZE / 2.0, -DRAW_SIZE / 2.0,
                                                DRAW_SIZE, DRAW_SIZE), false)
        else:
                # Fallback procedurale: testa squadrata + manico (stile Mjolnir)
                draw_set_transform(Vector2.ZERO, deg_to_rad(spin_deg), Vector2.ONE)
                draw_rect(Rect2(-14, -20, 28, 14), Color(0.62, 0.66, 0.74), true)
                draw_rect(Rect2(-14, -20, 28, 4), Color(0.78, 0.82, 0.9), true)
                draw_rect(Rect2(-16, -18, 4, 10), Color(0.5, 0.54, 0.62), true)
                draw_rect(Rect2(12, -18, 4, 10), Color(0.5, 0.54, 0.62), true)
                draw_rect(Rect2(-3, -6, 6, 22), Color(0.45, 0.3, 0.18), true)
                draw_rect(Rect2(-3, 14, 6, 4), Color(0.7, 0.55, 0.3), true)
        draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
