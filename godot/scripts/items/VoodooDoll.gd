## VoodooDoll.gd — TASK 108 (BAMBOLA VOODOO): la bambola LANCEIATA dal
## player col tasto FUOCO (utilizzo singolo, acquistata dallo shop del
## mago). Volo dritto nella direzione di lancio (pattern Hammer.gd):
##   * colpisce un NEMICO (NON il mini-boss): la sua anima entra nel corpo
##     e il player lo POSSIEDE (MainGameController._apply_voodoo_possession);
##   * colpisce un muro: la bambola si disintegra (uso perso);
##   * il mini-boss NON è un bersaglio valido: la bambola gli passa
##     attraverso senza effetto (richiesta utente: "contro un nemico (non
##     mid-boss)").
##
## Questo nodo possiede SOLO lo stato di volo e il DISEGNO (rottazione +
## scia + aura). La logica di collisioni vive in
## MainGameController._update_thrown_voodoo.
extends Node2D

const C = preload("res://scripts/core/GameConstants.gd")

## Direzione di lancio (vettore unitario).
var dir: Vector2 = Vector2(1.0, 0.0)
## Velocita' in px/frame @60fps (scalata per delta reale dal controller).
var speed: float = 11.0
## Rotazione corrente (deg): la bambola rotea piano come un oggetto leggero.
var spin_deg: float = 0.0
## Scia (ultimi punti percorsi, disegnati in alpha decrescente).
var trail: Array = []
## Flag: impatto avvenuto (il controller la legge per gli one-shot).
var impacted: bool = false
## Distanza percorsa (px): a fine corsa la bambola cade a terra e svanisce.
var travelled_px: float = 0.0

## Massima corsa in andata (~20 celle) prima di dissiparsi.
const MAX_TRAVEL_PX: float = 1300.0
## Dimensione del disegno in volo (px).
const DRAW_SIZE: float = 40.0

## Cache statica della texture (item_voodoo.png, PixelLab Task 108).
static var _tex_cache: Texture2D = null


func _ready() -> void:
        z_index = 5


static func _get_texture() -> Texture2D:
        if _tex_cache != null:
                return _tex_cache
        var abs_path: String = ProjectSettings.globalize_path(
                        "res://assets/sprites/collectibles/item_voodoo.png")
        if FileAccess.file_exists(abs_path):
                var img := Image.new()
                if img.load(abs_path) == OK:
                        _tex_cache = ImageTexture.create_from_image(img)
                        return _tex_cache
        push_warning("[Voodoo] item_voodoo.png non trovato: fallback procedurale")
        return null


## Registra un punto della scia (chiamato dal controller a ogni frame).
func push_trail_point(p: Vector2) -> void:
        trail.append(p)
        if trail.size() > 4:
                trail.pop_front()


func _draw() -> void:
        var tex: Texture2D = _get_texture()
        # --- Scia eterea (presagio di possessione: viola tenue) ---
        for i in range(trail.size()):
                var t: float = float(i + 1) / float(trail.size() + 1)
                var alpha: float = 0.08 + 0.14 * t
                var gp: Vector2 = trail[i]
                if tex != null:
                        var prev_rot: float = spin_deg - (trail.size() - i) * 28.0
                        draw_set_transform(gp, deg_to_rad(prev_rot), Vector2.ONE)
                        draw_texture_rect(tex,
                                        Rect2(-DRAW_SIZE / 2.0, -DRAW_SIZE / 2.0,
                                                        DRAW_SIZE, DRAW_SIZE),
                                        false, Color(0.8, 0.55, 1.0, alpha))
                else:
                        draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
                        draw_circle(gp, DRAW_SIZE * 0.22,
                                        Color(0.72, 0.5, 0.95, alpha))
        draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
        # --- Aura magica pulsante attorno alla bambola ---
        var aura_a: float = 0.16 + 0.08 * sin(spin_deg * 0.12)
        draw_circle(Vector2.ZERO, DRAW_SIZE * 0.62, Color(0.72, 0.50, 1.0, aura_a))
        draw_circle(Vector2.ZERO, DRAW_SIZE * 0.44, Color(0.80, 0.60, 1.0, aura_a * 1.2))
        # --- La bambola (rotea su se stessa) ---
        if tex != null:
                draw_set_transform(Vector2.ZERO, deg_to_rad(spin_deg), Vector2.ONE)
                draw_texture_rect(tex,
                                Rect2(-DRAW_SIZE / 2.0, -DRAW_SIZE / 2.0,
                                                DRAW_SIZE, DRAW_SIZE), false)
        else:
                # Fallback procedurale: sagoma di stoffa con spilli
                draw_set_transform(Vector2.ZERO, deg_to_rad(spin_deg), Vector2.ONE)
                draw_rect(Rect2(-9, -12, 18, 24), Color(0.78, 0.68, 0.45), true)
                draw_circle(Vector2(0, -12), 7.0, Color(0.70, 0.58, 0.38))
                draw_line(Vector2(-4, -13), Vector2(-1, -11), Color(0.2, 0.1, 0.05), 2.0)
                draw_line(Vector2(4, -13), Vector2(1, -11), Color(0.2, 0.1, 0.05), 2.0)
                draw_line(Vector2(0, -19), Vector2(0, -14), Color(0.9, 0.2, 0.2), 2.0)
                draw_line(Vector2(-12, -2), Vector2(-7, -2), Color(0.2, 0.4, 0.9), 2.0)
        draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
