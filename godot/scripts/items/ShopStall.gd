## ShopStall.gd — TASK 108 (SHOP): la CASA STREGA / CAPANNA HOBBIT nel
## labirinto. Sprite PixelLab (shop_witch_hut.png, 128x128) piazzato su un
## blocco 2x2 di celle all'estremità del labirinto (angolo). Il player ci
## ENTRA camminandoci sopra: il controller apre ShopScreen. All'uscita lo
## shop si CHIUDE: sulla porta viene appeso il cartello di legno
## (shop_sign_closed.png) con la scritta "CHIUSO" resa col font medievale
## di gioco (Goth And Gothic, Task 78) — leggibile a ogni scala.
##
## Nodo puramente VISUALE + stato (open/closed): la logica di ingresso
## vive in MainGameController (pattern Collectibles: il pickup/ingresso è
## centralizzato nel controller).
extends Node2D

const C = preload("res://scripts/core/GameConstants.gd")

## Cella della PORTA della capanna (cella percorribile su cui sorge lo
## shop: lo sprite 128x128 copre anche i muri circostanti, i corridoi sono
## larghi una cella).
var block_cell: Vector2i = Vector2i.ZERO
## true finché il player non è entrato e uscito (una sola visita per livello).
var open: bool = true

var _t: float = 0.0
var _hut_tex: Texture2D = null
var _sign_tex: Texture2D = null
static var _tex_cache: Dictionary = {}


func _ready() -> void:
        z_index = 4  # sopra il pavimento e gli item ( come la exit door)
        _hut_tex = _cached_png("res://assets/sprites/collectibles/shop_witch_hut.png")
        _sign_tex = _cached_png("res://assets/sprites/collectibles/shop_sign_closed.png")


static func _cached_png(path: String) -> Texture2D:
        if _tex_cache.has(path):
                return _tex_cache[path]
        var tex: Texture2D = null
        var abs_path: String = ProjectSettings.globalize_path(path)
        if FileAccess.file_exists(abs_path):
                var img := Image.new()
                if img.load(abs_path) == OK:
                        tex = ImageTexture.create_from_image(img)
        _tex_cache[path] = tex
        return tex


## Centro del blocco 2x2 in pixel (per l'alone e i calcoli del controller).
func center_pos() -> Vector2:
        return position


## Rect di ingresso (cella della porta, leggermente ristretto): il player
## "entra" quando la sua posizione cade sulla porta.
func entry_rect() -> Rect2:
        return Rect2(position.x - 20.0, position.y - 20.0, 40.0, 40.0)


## Posizione di uscita approssimata (il controller la raffina con la cella
## EMPTY adiacente: vedi _shop_exit_pos).
func exit_pos() -> Vector2:
        return position + Vector2(0.0, float(C.TILE_SIZE) * 1.1)


func _process(delta: float) -> void:
        _t += delta
        queue_redraw()


func _draw() -> void:
        var pulse: float = 0.5 + 0.5 * sin(_t * 2.2)
        # Alone caldo pulsante attorno alla casa (la lanterna accesa):
        # richiama l'occhio nel buio delle palette scure, come il medikit.
        if open:
                draw_circle(Vector2(0.0, -6.0), 66.0,
                        Color(1.0, 0.72, 0.30, 0.05 + 0.035 * pulse))
                draw_circle(Vector2(0.0, -6.0), 44.0,
                        Color(1.0, 0.72, 0.30, 0.04 + 0.03 * pulse))
        # L'edificio: 128x128 centrato sul blocco 2x2 (96x96).
        if _hut_tex != null:
                draw_texture_rect(_hut_tex,
                        Rect2(-64.0, -64.0, 128.0, 128.0), false,
                        Color(1, 1, 1, 1.0 if open else 0.82))
        else:
                # Fallback procedurale: capanna quadrata col tetto a spioventi.
                var wall: Color = Color(0.42, 0.28, 0.16)
                var roof: Color = Color(0.25, 0.38, 0.20)
                draw_colored_polygon(PackedVector2Array([
                        Vector2(-40, -10), Vector2(40, -10), Vector2(0, -48)]), roof)
                draw_rect(Rect2(-36, -10, 72, 52), wall, true)
                draw_rect(Rect2(-36, -10, 72, 52), Color(0.2, 0.13, 0.08), false, 2.0)
                # Porta
                draw_rect(Rect2(-12, 12, 24, 30),
                        Color(0.12, 0.07, 0.04) if open else Color(0.30, 0.18, 0.10), true)
                # Finestra calda
                draw_rect(Rect2(14, 0, 14, 12), Color(1.0, 0.78, 0.35), true)
        # Cartello "CHIUSO" appeso sulla porta quando il negozio è chiuso.
        if not open:
                if _sign_tex != null:
                        draw_texture_rect(_sign_tex,
                                Rect2(-16.0, 14.0, 32.0, 32.0), false)
                else:
                        draw_rect(Rect2(-16, 14, 32, 24), Color(0.38, 0.24, 0.12), true)
                        draw_rect(Rect2(-16, 14, 32, 24), Color(0.18, 0.11, 0.06), false, 2.0)
                var label: String = I18n.t("shop.closed")
                # Font medievale di gioco (Task 78, static): null se manca il file.
                var med: Font = C.gothic_font()
                var use_font: Font = med if med != null else ThemeDB.fallback_font
                draw_string(use_font, Vector2(-24.0, 33.0), label,
                                HORIZONTAL_ALIGNMENT_CENTER, 48.0, 11,
                                Color(0.05, 0.02, 0.02, 0.9))
                draw_string(use_font, Vector2(-24.0, 31.0), label,
                                HORIZONTAL_ALIGNMENT_CENTER, 48.0, 11,
                                Color(0.95, 0.85, 0.55))
