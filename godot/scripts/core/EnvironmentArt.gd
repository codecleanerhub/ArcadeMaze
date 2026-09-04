## EnvironmentArt.gd - Autoload generatore di texture procedurali ad alta risoluzione.
##
## Genera texture vettoriali dettagliate per oggetti di scena:
##   - 5 tipi di tesoro (corona, oro, forziere, gemma, coppa)
##   - Bara (coffin)
##   - Colonna di pietra (column)
##   - Ruderi (rubble pile)
##   - Teschio (skull decoration)
##   - Ragnatela (cobweb)
##   - Torcia da muro (wall torch)
##
## Queste texture sono generate con Image + ImageTexture a 128x128 o 256x256,
## molto piu' definite dei PNG AI a 64x64. Sono cached dopo la prima generazione.
##
## Vantaggio Godot: immagini nitide a qualsiasi zoom, stile coerente,
## dettagli programmatici (gemme multifaccettate, ornamenti, ombre).
extends Node

# Cache delle texture generate
var _texture_cache: Dictionary = {}


# ============================================================================
# API pubblica
# ============================================================================
func get_treasure_texture(treasure_type: int) -> Texture2D:
        var key: String = "treasure_%d" % treasure_type
        if _texture_cache.has(key):
                return _texture_cache[key]
        var tex: Texture2D = null
        match treasure_type:
                0: tex = _make_crown()       # TRES_CROWN
                1: tex = _make_gold_pile()   # TRES_GOLD
                2: tex = _make_chest()       # TRES_CHEST
                3: tex = _make_gem()         # TRES_GEM
                4: tex = _make_cup()         # TRES_CUP
                _: tex = _make_crown()
        _texture_cache[key] = tex
        return tex


func get_coffin_texture() -> Texture2D:
        if _texture_cache.has("coffin"):
                return _texture_cache["coffin"]
        var tex := _make_coffin()
        _texture_cache["coffin"] = tex
        return tex


func get_column_texture() -> Texture2D:
        if _texture_cache.has("column"):
                return _texture_cache["column"]
        var tex := _make_column()
        _texture_cache["column"] = tex
        return tex


func get_rubble_texture() -> Texture2D:
        if _texture_cache.has("rubble"):
                return _texture_cache["rubble"]
        var tex := _make_rubble()
        _texture_cache["rubble"] = tex
        return tex


func get_skull_texture() -> Texture2D:
        if _texture_cache.has("skull"):
                return _texture_cache["skull"]
        var tex := _make_skull()
        _texture_cache["skull"] = tex
        return tex


func get_cobweb_texture() -> Texture2D:
        if _texture_cache.has("cobweb"):
                return _texture_cache["cobweb"]
        var tex := _make_cobweb()
        _texture_cache["cobweb"] = tex
        return tex


func get_torch_texture() -> Texture2D:
        if _texture_cache.has("torch"):
                return _texture_cache["torch"]
        var tex := _make_wall_torch()
        _texture_cache["torch"] = tex
        return tex


func get_weapon_pickup_texture(weapon_type: int) -> Texture2D:
        var key: String = "weapon_%d" % weapon_type
        if _texture_cache.has(key):
                return _texture_cache[key]
        var tex: Texture2D = null
        match weapon_type:
                0: tex = _make_weapon_pistol()
                1: tex = _make_weapon_shotgun()
                2: tex = _make_weapon_rocket()
                3: tex = _make_weapon_laser()
                _: tex = _make_weapon_pistol()
        _texture_cache[key] = tex
        return tex


# ============================================================================
# Helper: crea Image 128x128 con sfondo trasparente
# ============================================================================
func _new_image(size: int = 128) -> Image:
        var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
        img.fill(Color(0, 0, 0, 0))  # trasparente
        return img


func _finalize(img: Image) -> ImageTexture:
        return ImageTexture.create_from_image(img)


# Helper: riempie un cerchio pieno
func _fill_circle(img: Image, cx: int, cy: int, r: int, color: Color) -> void:
        var r2: float = float(r * r)
        for y in range(-r, r + 1):
                for x in range(-r, r + 1):
                        if x * x + y * y <= r2:
                                var px: int = cx + x
                                var py: int = cy + y
                                if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
                                        img.set_pixel(px, py, color)


# Helper: cerchio outline
func _draw_circle_outline(img: Image, cx: int, cy: int, r: int, color: Color, thickness: int = 2) -> void:
        var r_out: float = float(r)
        var r_in: float = float(r - thickness)
        for y in range(-r, r + 1):
                for x in range(-r, r + 1):
                        var d2: float = float(x * x + y * y)
                        if d2 <= r_out * r_out and d2 >= r_in * r_in:
                                var px: int = cx + x
                                var py: int = cy + y
                                if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
                                        img.set_pixel(px, py, color)


# Helper: rettangolo pieno
func _fill_rect(img: Image, x: int, y: int, w: int, h: int, color: Color) -> void:
        for py in range(y, y + h):
                for px in range(x, x + w):
                        if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
                                img.set_pixel(px, py, color)


# Helper: rettangolo outline
func _draw_rect_outline(img: Image, x: int, y: int, w: int, h: int, color: Color, thickness: int = 2) -> void:
        # Top + bottom
        _fill_rect(img, x, y, w, thickness, color)
        _fill_rect(img, x, y + h - thickness, w, thickness, color)
        # Left + right
        _fill_rect(img, x, y, thickness, h, color)
        _fill_rect(img, x + w - thickness, y, thickness, h, color)


# Helper: linea
func _draw_line(img: Image, x0: int, y0: int, x1: int, y1: int, color: Color, thickness: int = 1) -> void:
        var dx: int = abs(x1 - x0)
        var dy: int = abs(y1 - y0)
        var sx: int = 1 if x0 < x1 else -1
        var sy: int = 1 if y0 < y1 else -1
        var err: int = dx - dy
        var cx: int = x0
        var cy: int = y0
        while true:
                for tx in range(int(-thickness / 2), int(thickness / 2) + 1):
                        for ty in range(int(-thickness / 2), int(thickness / 2) + 1):
                                var px: int = cx + tx
                                var py: int = cy + ty
                                if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
                                        img.set_pixel(px, py, color)
                if cx == x1 and cy == y1:
                        break
                var e2: int = 2 * err
                if e2 > -dy:
                        err -= dy
                        cx += sx
                if e2 < dx:
                        err += dx
                        cy += sy


# ============================================================================
# GENERATORI: Tesori (5 tipi)
# ============================================================================

# Corona - oro con gemme rosse e blu, dettagli filigrana
func _make_crown() -> Texture2D:
        var img := _new_image(128)
        # Base della corona (oro massiccio)
        _fill_rect(img, 30, 70, 68, 20, Color(1.0, 0.78, 0.0))  # oro
        # Ombra sotto
        _fill_rect(img, 30, 88, 68, 4, Color(0.6, 0.45, 0.0))
        # Punte della corona (3 punte triangolari)
        _fill_triangle(img, 36, 70, 44, 70, 40, 50, Color(1.0, 0.84, 0.0))
        _fill_triangle(img, 60, 70, 68, 70, 64, 45, Color(1.0, 0.84, 0.0))
        _fill_triangle(img, 84, 70, 92, 70, 88, 50, Color(1.0, 0.84, 0.0))
        # Gemma centrale rossa (rubino)
        _fill_circle(img, 64, 60, 5, Color(0.9, 0.1, 0.1))
        _fill_circle(img, 64, 60, 3, Color(1.0, 0.3, 0.3))
        _fill_circle(img, 63, 59, 1, Color(1.0, 0.8, 0.8))  # highlight
        # Gemme laterali blu (zaffiri)
        _fill_circle(img, 40, 60, 3, Color(0.1, 0.3, 0.9))
        _fill_circle(img, 88, 60, 3, Color(0.1, 0.3, 0.9))
        # Filigrana decorativa (linee sottili)
        _draw_line(img, 32, 76, 96, 76, Color(0.7, 0.55, 0.0), 1)
        _draw_line(img, 32, 82, 96, 82, Color(0.7, 0.55, 0.0), 1)
        # Puntini decorativi
        for px in [40, 50, 60, 70, 80, 90]:
                img.set_pixel(px, 80, Color(0.8, 0.65, 0.0))
        # Highlight superiore (riflesso luce)
        _fill_rect(img, 32, 71, 64, 2, Color(1.0, 0.95, 0.5))
        return _finalize(img)


# Mucchio di monete d'oro - pila con dettagli
func _make_gold_pile() -> Texture2D:
        var img := _new_image(128)
        # Mucchio base (cono rovesciato di monete)
        _fill_circle(img, 64, 90, 28, Color(0.85, 0.65, 0.0))  # ombra base
        _fill_circle(img, 64, 85, 25, Color(1.0, 0.78, 0.0))   # oro
        # Strati di monete (pila)
        _fill_circle(img, 50, 75, 10, Color(1.0, 0.82, 0.1))
        _fill_circle(img, 64, 70, 11, Color(1.0, 0.84, 0.15))
        _fill_circle(img, 78, 75, 10, Color(1.0, 0.82, 0.1))
        _fill_circle(img, 64, 55, 9, Color(1.0, 0.86, 0.2))
        # Cerchi interni delle monete (dettagli)
        _draw_circle_outline(img, 50, 75, 6, Color(0.7, 0.55, 0.0), 1)
        _draw_circle_outline(img, 64, 70, 7, Color(0.7, 0.55, 0.0), 1)
        _draw_circle_outline(img, 78, 75, 6, Color(0.7, 0.55, 0.0), 1)
        _draw_circle_outline(img, 64, 55, 5, Color(0.7, 0.55, 0.0), 1)
        # Simboli sulle monete (stelle a 5 punte semplificate)
        _draw_star(img, 50, 75, 2, Color(0.6, 0.45, 0.0))
        _draw_star(img, 64, 70, 2, Color(0.6, 0.45, 0.0))
        _draw_star(img, 78, 75, 2, Color(0.6, 0.45, 0.0))
        # Highlight (riflessi)
        img.set_pixel(47, 72, Color(1.0, 0.95, 0.4))
        img.set_pixel(61, 67, Color(1.0, 0.95, 0.4))
        img.set_pixel(75, 72, Color(1.0, 0.95, 0.4))
        img.set_pixel(61, 52, Color(1.0, 0.95, 0.4))
        return _finalize(img)


# Forziere del tesuro - cassa di legno con bande metalliche
func _make_chest() -> Texture2D:
        var img := _new_image(128)
        # Ombra a terra
        _fill_ellipse(img, 64, 100, 40, 6, Color(0, 0, 0, 0.4))
        # Corpo del forziere (legno scuro)
        _fill_rect(img, 24, 65, 80, 35, Color(0.4, 0.25, 0.1))  # legno
        # Coperchio (semicerchio in alto)
        _fill_ellipse(img, 64, 65, 40, 18, Color(0.5, 0.3, 0.15))  # coperchio legno
        # Bande metalliche (ferro)
        _fill_rect(img, 24, 70, 80, 4, Color(0.5, 0.5, 0.55))   # banda orizzontale
        _fill_rect(img, 24, 90, 80, 4, Color(0.5, 0.5, 0.55))   # banda orizzontale
        _fill_rect(img, 60, 65, 8, 35, Color(0.5, 0.5, 0.55))    # banda verticale centrale
        # Rivetti metallici
        for px in [30, 45, 60, 75, 90]:
                img.set_pixel(px, 72, Color(0.8, 0.8, 0.85))
                img.set_pixel(px, 92, Color(0.8, 0.8, 0.85))
        # Lucchetto (ottone)
        _fill_rect(img, 58, 78, 12, 12, Color(0.85, 0.7, 0.2))   # corpo lucchetto
        _fill_circle(img, 64, 84, 3, Color(0.5, 0.4, 0.1))        # buco serratura
        # Highlight sul coperchio
        _fill_rect(img, 30, 60, 68, 3, Color(0.6, 0.4, 0.2))
        # Venature del legno
        _draw_line(img, 30, 80, 55, 80, Color(0.3, 0.18, 0.08), 1)
        _draw_line(img, 70, 80, 95, 80, Color(0.3, 0.18, 0.08), 1)
        _draw_line(img, 30, 85, 55, 85, Color(0.3, 0.18, 0.08), 1)
        _draw_line(img, 70, 85, 95, 85, Color(0.3, 0.18, 0.08), 1)
        return _finalize(img)


# Gemma tagliata (diamante multifaccettato) - blu con riflessi
func _make_gem() -> Texture2D:
        var img := _new_image(128)
        # Ombra a terra
        _fill_circle(img, 64, 100, 12, Color(0, 0, 0, 0.3))
        # Gemma taglio diamante (esafoide superiore + parte inferiore a punta)
        # Parte superiore (esagono)
        _fill_polygon(img, [
                Vector2(40, 50), Vector2(88, 50),
                Vector2(96, 60), Vector2(32, 60)
        ], Color(0.2, 0.5, 0.95))  # blu base
        # Facce superiori (taglio)
        _fill_polygon(img, [
                Vector2(40, 50), Vector2(64, 35), Vector2(88, 50),
                Vector2(64, 60)
        ], Color(0.3, 0.6, 1.0))  # faccia superiore piu' chiara
        # Parte inferiore (punta verso il basso)
        _fill_polygon(img, [
                Vector2(32, 60), Vector2(96, 60),
                Vector2(64, 95)
        ], Color(0.15, 0.4, 0.85))  # blu piu' scuro
        # Facce laterali (sfumature)
        _fill_polygon(img, [
                Vector2(32, 60), Vector2(64, 60), Vector2(64, 95)
        ], Color(0.1, 0.3, 0.7))
        _fill_polygon(img, [
                Vector2(64, 60), Vector2(96, 60), Vector2(64, 95)
        ], Color(0.2, 0.5, 0.9))
        # Highlight brillante (riflesso luce)
        _fill_polygon(img, [
                Vector2(48, 48), Vector2(60, 40), Vector2(62, 50), Vector2(50, 55)
        ], Color(0.7, 0.85, 1.0))
        # Scintillio (punto bianco)
        _fill_circle(img, 54, 46, 2, Color(1.0, 1.0, 1.0))
        # Outline generale
        _draw_polygon_outline(img, [
                Vector2(40, 50), Vector2(64, 35), Vector2(88, 50),
                Vector2(96, 60), Vector2(64, 95), Vector2(32, 60)
        ], Color(0.05, 0.2, 0.5), 1)
        return _finalize(img)


# Coppa/calice d'oro - calice con coppa superiore
func _make_cup() -> Texture2D:
        var img := _new_image(128)
        # Ombra base
        _fill_ellipse(img, 64, 100, 18, 4, Color(0, 0, 0, 0.4))
        # Base (piattello)
        _fill_ellipse(img, 64, 95, 18, 6, Color(0.85, 0.65, 0.0))
        _fill_ellipse(img, 64, 93, 18, 4, Color(1.0, 0.78, 0.0))
        # Stelo (sottile)
        _fill_rect(img, 60, 70, 8, 25, Color(1.0, 0.78, 0.0))
        _fill_rect(img, 61, 70, 2, 25, Color(1.0, 0.9, 0.3))  # highlight
        # Nodo centrale (sfera decorativa)
        _fill_circle(img, 64, 70, 6, Color(1.0, 0.78, 0.0))
        _fill_circle(img, 64, 70, 4, Color(1.0, 0.84, 0.1))
        _fill_circle(img, 62, 68, 2, Color(1.0, 0.95, 0.5))  # highlight
        # Coppa superiore (calice)
        _fill_ellipse(img, 64, 50, 22, 12, Color(0.85, 0.65, 0.0))  # esterno
        _fill_ellipse(img, 64, 48, 20, 10, Color(1.0, 0.78, 0.0))  # interno oro
        _fill_ellipse(img, 64, 46, 18, 6, Color(0.7, 0.5, 0.0))    # interno scuro (vino)
        # Bordo superiore
        _fill_ellipse(img, 64, 44, 22, 3, Color(1.0, 0.84, 0.1))   # bordo
        # Decorazioni (gemme sul calice)
        _fill_circle(img, 54, 50, 2, Color(0.9, 0.1, 0.1))  # rubino
        _fill_circle(img, 64, 52, 2, Color(0.1, 0.3, 0.9))  # zaffiro
        _fill_circle(img, 74, 50, 2, Color(0.1, 0.8, 0.3))  # smeraldo
        # Highlight coppa
        _fill_ellipse(img, 56, 46, 4, 2, Color(1.0, 0.95, 0.5))
        return _finalize(img)


# ============================================================================
# GENERATORI: Decorazioni dungeon
# ============================================================================

# Bara - cassa di legno scuro con croce e borchie
func _make_coffin() -> Texture2D:
        var img := _new_image(128)
        # Ombra a terra
        _fill_ellipse(img, 64, 115, 35, 6, Color(0, 0, 0, 0.5))
        # Corpo della bara (legno molto scuro, forma a bara)
        _fill_polygon(img, [
                Vector2(30, 30), Vector2(98, 30),
                Vector2(92, 110), Vector2(36, 110)
        ], Color(0.25, 0.12, 0.05))  # legno scuro
        # Coperchio (piu' chiaro, in prospettiva)
        _fill_polygon(img, [
                Vector2(30, 30), Vector2(98, 30),
                Vector2(95, 45), Vector2(33, 45)
        ], Color(0.35, 0.18, 0.08))
        # Croce sul coperchio (ottone)
        _fill_rect(img, 62, 35, 4, 30, Color(0.85, 0.7, 0.2))   # verticale
        _fill_rect(img, 52, 45, 24, 4, Color(0.85, 0.7, 0.2))   # orizzontale
        # Highlight croce
        _fill_rect(img, 62, 35, 1, 30, Color(1.0, 0.9, 0.4))
        # Borchie metalliche (angoli)
        for pos in [[35, 35], [93, 35], [40, 105], [88, 105]]:
                _fill_circle(img, pos[0], pos[1], 3, Color(0.6, 0.6, 0.65))
                img.set_pixel(pos[0] - 1, pos[1] - 1, Color(0.85, 0.85, 0.9))
        # Venature del legno
        _draw_line(img, 35, 55, 38, 105, Color(0.15, 0.07, 0.03), 1)
        _draw_line(img, 90, 55, 87, 105, Color(0.15, 0.07, 0.03), 1)
        _draw_line(img, 60, 55, 60, 105, Color(0.15, 0.07, 0.03), 1)
        # Outline
        _draw_polygon_outline(img, [
                Vector2(30, 30), Vector2(98, 30),
                Vector2(92, 110), Vector2(36, 110)
        ], Color(0.1, 0.05, 0.0), 2)
        return _finalize(img)


# Colonna di pietra - colonna classica con capitello e base
func _make_column() -> Texture2D:
        var img := _new_image(128)
        # Base (piu' larga)
        _fill_rect(img, 24, 105, 80, 12, Color(0.45, 0.43, 0.4))
        _fill_rect(img, 28, 100, 72, 8, Color(0.5, 0.48, 0.45))
        # Fusto (colonna cilindrica)
        _fill_rect(img, 36, 25, 56, 80, Color(0.55, 0.53, 0.5))
        # Scanalature verticali (fogge doriche)
        for x in [40, 48, 56, 64, 72, 80, 88]:
                _fill_rect(img, x, 25, 2, 80, Color(0.4, 0.38, 0.35))
        # Highlight laterale (luce da sinistra)
        _fill_rect(img, 38, 25, 3, 80, Color(0.7, 0.68, 0.65))
        # Ombra laterale destra
        _fill_rect(img, 87, 25, 3, 80, Color(0.35, 0.33, 0.3))
        # Capitello (parte superiore decorata)
        _fill_rect(img, 28, 18, 72, 10, Color(0.5, 0.48, 0.45))  # abaco
        _fill_rect(img, 32, 12, 64, 8, Color(0.55, 0.53, 0.5))   # echino
        # Decorazioni volute (spirali semplificate)
        _fill_circle(img, 36, 16, 3, Color(0.4, 0.38, 0.35))
        _fill_circle(img, 92, 16, 3, Color(0.4, 0.38, 0.35))
        img.set_pixel(36, 16, Color(0.6, 0.58, 0.55))
        img.set_pixel(92, 16, Color(0.6, 0.58, 0.55))
        # Crepe e muschio (dettagli invecchiamento)
        _draw_line(img, 50, 30, 52, 70, Color(0.3, 0.28, 0.25), 1)
        _draw_line(img, 70, 40, 72, 90, Color(0.3, 0.28, 0.25), 1)
        # Muschio alla base (verde)
        _fill_rect(img, 36, 100, 56, 4, Color(0.2, 0.35, 0.15))
        for x in [40, 50, 60, 70, 80, 88]:
                img.set_pixel(x, 100, Color(0.3, 0.45, 0.2))
                img.set_pixel(x, 101, Color(0.25, 0.4, 0.18))
        return _finalize(img)


# Ruderi - pila di pietre rotte
func _make_rubble() -> Texture2D:
        var img := _new_image(128)
        # Ombra a terra
        _fill_ellipse(img, 64, 110, 40, 6, Color(0, 0, 0, 0.4))
        # Pietra grande (base)
        _fill_polygon(img, [
                Vector2(30, 90), Vector2(70, 85), Vector2(95, 92), Vector2(85, 110), Vector2(35, 110)
        ], Color(0.5, 0.48, 0.45))
        # Highlight pietra grande
        _fill_polygon(img, [
                Vector2(30, 90), Vector2(70, 85), Vector2(50, 95), Vector2(35, 95)
        ], Color(0.6, 0.58, 0.55))
        # Pietra media (sopra)
        _fill_polygon(img, [
                Vector2(40, 75), Vector2(75, 70), Vector2(80, 85), Vector2(45, 88)
        ], Color(0.55, 0.53, 0.5))
        _fill_polygon(img, [
                Vector2(40, 75), Vector2(75, 70), Vector2(55, 78), Vector2(45, 80)
        ], Color(0.65, 0.63, 0.6))
        # Pietra piccola (in cima)
        _fill_polygon(img, [
                Vector2(55, 60), Vector2(75, 58), Vector2(78, 70), Vector2(58, 72)
        ], Color(0.5, 0.48, 0.45))
        _fill_polygon(img, [
                Vector2(55, 60), Vector2(75, 58), Vector2(65, 64), Vector2(58, 66)
        ], Color(0.6, 0.58, 0.55))
        # Pietra rotta a sinistra
        _fill_polygon(img, [
                Vector2(20, 100), Vector2(35, 95), Vector2(40, 108), Vector2(22, 110)
        ], Color(0.45, 0.43, 0.4))
        # Crepe
        _draw_line(img, 35, 92, 45, 108, Color(0.3, 0.28, 0.25), 1)
        _draw_line(img, 60, 75, 65, 88, Color(0.3, 0.28, 0.25), 1)
        _draw_line(img, 75, 70, 80, 85, Color(0.3, 0.28, 0.25), 1)
        # Muschio
        for pos in [[40, 110], [70, 108], [85, 105]]:
                img.set_pixel(pos[0], pos[1], Color(0.25, 0.4, 0.18))
                img.set_pixel(pos[0] + 1, pos[1], Color(0.2, 0.35, 0.15))
        return _finalize(img)


# Teschio - decorazione a parete
func _make_skull() -> Texture2D:
        var img := _new_image(128)
        # Cranio (forma ovale)
        _fill_ellipse(img, 64, 55, 30, 35, Color(0.92, 0.88, 0.78))  # avorio
        _fill_ellipse(img, 64, 50, 28, 32, Color(0.95, 0.92, 0.82))  # piu' chiaro
        # Ombre cranio (profondita')
        _fill_ellipse(img, 80, 60, 12, 18, Color(0.8, 0.76, 0.65))   # ombra destra
        # Orbite oculari (cavernose, nere)
        _fill_ellipse(img, 52, 50, 8, 10, Color(0.05, 0.02, 0.0))
        _fill_ellipse(img, 76, 50, 8, 10, Color(0.05, 0.02, 0.0))
        # Lucciola negli occhi (rosso malefico)
        _fill_circle(img, 52, 50, 2, Color(0.9, 0.1, 0.1))
        _fill_circle(img, 76, 50, 2, Color(0.9, 0.1, 0.1))
        img.set_pixel(51, 49, Color(1.0, 0.5, 0.5))
        img.set_pixel(75, 49, Color(1.0, 0.5, 0.5))
        # Naso (triangolo)
        _fill_polygon(img, [
                Vector2(60, 65), Vector2(68, 65), Vector2(64, 75)
        ], Color(0.05, 0.02, 0.0))
        # Dentatura (sotto)
        _fill_rect(img, 44, 80, 40, 18, Color(0.92, 0.88, 0.78))
        # Spazi tra i denti (linee verticali nere)
        for x in [50, 56, 62, 68, 74, 80]:
                _fill_rect(img, x, 80, 2, 18, Color(0.1, 0.05, 0.0))
        # Denti rotti (manca un dente)
        _fill_rect(img, 60, 80, 4, 8, Color(0.1, 0.05, 0.0))
        # Sutura cranica (linea a zigzag)
        _draw_line(img, 64, 25, 60, 35, Color(0.7, 0.65, 0.55), 1)
        _draw_line(img, 60, 35, 68, 45, Color(0.7, 0.65, 0.55), 1)
        # Highlight superiore
        _fill_ellipse(img, 58, 35, 8, 4, Color(1.0, 0.98, 0.9))
        return _finalize(img)


# Ragnatela - decorazione d'angolo
func _make_cobweb() -> Texture2D:
        var img := _new_image(128)
        var cx: int = 0
        var cy: int = 0
        # Raggi della ragnatela (dall'angolo)
        for angle_deg in [0, 30, 60, 90, 120, 150, 180, 210, 240, 270, 300, 330]:
                var a: float = deg_to_rad(float(angle_deg))
                var ex: int = int(cx + cos(a) * 120)
                var ey: int = int(cy + sin(a) * 120)
                _draw_line(img, cx, cy, ex, ey, Color(0.9, 0.9, 0.9, 0.5), 1)
        # Spirali concentriche
        for r in [20, 35, 50, 65, 80, 95, 110]:
                var prev: Vector2 = Vector2(cx + r, cy)
                for i in range(1, 13):
                        var a: float = deg_to_rad(float(i * 30))
                        var nx: int = int(cx + cos(a) * r)
                        var ny: int = int(cy + sin(a) * r)
                        _draw_line(img, int(prev.x), int(prev.y), nx, ny, Color(0.85, 0.85, 0.85, 0.4), 1)
                        prev = Vector2(nx, ny)
        # Piccolo ragno al centro
        _fill_circle(img, 8, 8, 3, Color(0.1, 0.05, 0.05))
        # Zampe ragno
        for i in range(4):
                var a: float = deg_to_rad(float(30 + i * 30))
                _draw_line(img, 8, 8, int(8 + cos(a) * 6), int(8 + sin(a) * 6),
                        Color(0.1, 0.05, 0.05), 1)
        return _finalize(img)


# Torcia da muro - supporto metallico + fiamma
func _make_wall_torch() -> Texture2D:
        var img := _new_image(128)
        # Supporto metallico (braccio)
        _fill_rect(img, 50, 80, 28, 6, Color(0.5, 0.5, 0.55))  # braccio orizzontale
        _fill_rect(img, 60, 86, 8, 15, Color(0.5, 0.5, 0.55))  # supporto verticale
        # Anello metallico (reggi torcia)
        _fill_circle(img, 64, 78, 6, Color(0.4, 0.4, 0.45))
        _fill_circle(img, 64, 78, 4, Color(0.2, 0.15, 0.1))  # interno buio
        # Asta della torcia (legno)
        _fill_rect(img, 60, 60, 8, 20, Color(0.3, 0.18, 0.08))
        # Estremita' superiore carbonizzata
        _fill_rect(img, 58, 55, 12, 8, Color(0.1, 0.05, 0.0))
        # Fiamma (gocce di fuoco sovrapposte)
        _fill_circle(img, 64, 45, 12, Color(1.0, 0.4, 0.0))   # alone esterno arancione
        _fill_circle(img, 64, 45, 9, Color(1.0, 0.6, 0.1))    # medio
        _fill_circle(img, 64, 45, 6, Color(1.0, 0.85, 0.2))   # interno giallo
        _fill_circle(img, 64, 43, 3, Color(1.0, 1.0, 0.7))    # nucleo bianco
        # Scintille
        img.set_pixel(58, 35, Color(1.0, 0.8, 0.2))
        img.set_pixel(70, 38, Color(1.0, 0.8, 0.2))
        img.set_pixel(55, 30, Color(1.0, 0.6, 0.1))
        img.set_pixel(72, 28, Color(1.0, 0.6, 0.1))
        # Highlight sul metallo
        _fill_rect(img, 52, 81, 24, 1, Color(0.7, 0.7, 0.75))
        return _finalize(img)


# ============================================================================
# GENERATORI: Armi pickup (4 tipi) - dettagliate
# ============================================================================
func _make_weapon_pistol() -> Texture2D:
        var img := _new_image(128)
        # Ombra
        _fill_ellipse(img, 64, 95, 24, 4, Color(0, 0, 0, 0.4))
        # Calcio (impugnatura) - legno scuro
        _fill_polygon(img, [
                Vector2(50, 60), Vector2(60, 60), Vector2(62, 90), Vector2(48, 90)
        ], Color(0.35, 0.2, 0.1))
        # Venature impugnatura
        _draw_line(img, 52, 65, 54, 88, Color(0.2, 0.1, 0.05), 1)
        _draw_line(img, 58, 65, 60, 88, Color(0.2, 0.1, 0.05), 1)
        # Cornicetta metallica
        _fill_rect(img, 48, 58, 16, 4, Color(0.6, 0.6, 0.65))
        # Canna (metallo grigio)
        _fill_rect(img, 30, 50, 40, 10, Color(0.55, 0.55, 0.6))
        _fill_rect(img, 30, 50, 40, 2, Color(0.75, 0.75, 0.8))  # highlight superiore
        _fill_rect(img, 30, 58, 40, 2, Color(0.35, 0.35, 0.4))  # ombra inferiore
        # Bocca canna (nero)
        _fill_rect(img, 28, 53, 4, 4, Color(0.1, 0.1, 0.1))
        # Grilletto (curva metallica)
        _fill_rect(img, 60, 60, 3, 12, Color(0.5, 0.5, 0.55))
        # Ponticello grilletto
        _fill_polygon(img, [
                Vector2(60, 70), Vector2(64, 75), Vector2(60, 78), Vector2(58, 75)
        ], Color(0.4, 0.4, 0.45))
        # Mira (pallino rosso)
        _fill_circle(img, 70, 53, 2, Color(0.9, 0.1, 0.1))
        return _finalize(img)


func _make_weapon_shotgun() -> Texture2D:
        var img := _new_image(128)
        # Ombra
        _fill_ellipse(img, 64, 100, 35, 5, Color(0, 0, 0, 0.4))
        # Calcio
        _fill_polygon(img, [
                Vector2(75, 55), Vector2(95, 55), Vector2(98, 95), Vector2(78, 95)
        ], Color(0.35, 0.2, 0.1))
        # Venature
        _draw_line(img, 80, 60, 82, 90, Color(0.2, 0.1, 0.05), 1)
        _draw_line(img, 90, 60, 92, 90, Color(0.2, 0.1, 0.05), 1)
        # Culatta metallica
        _fill_rect(img, 65, 50, 18, 16, Color(0.55, 0.55, 0.6))
        # Canne doppie (fucile a pompa)
        _fill_rect(img, 15, 45, 55, 8, Color(0.5, 0.5, 0.55))   # canna superiore
        _fill_rect(img, 15, 55, 55, 8, Color(0.5, 0.5, 0.55))   # canna inferiore
        _fill_rect(img, 15, 45, 55, 2, Color(0.7, 0.7, 0.75))   # highlight sup
        _fill_rect(img, 15, 61, 55, 2, Color(0.35, 0.35, 0.4))   # ombra inf
        # Bocche canna
        _fill_rect(img, 12, 47, 4, 4, Color(0.1, 0.1, 0.1))
        _fill_rect(img, 12, 57, 4, 4, Color(0.1, 0.1, 0.1))
        # Pompo (sotto le canne)
        _fill_rect(img, 35, 65, 20, 6, Color(0.45, 0.3, 0.15))
        _fill_rect(img, 35, 65, 20, 1, Color(0.6, 0.4, 0.2))
        # Grilletto
        _fill_rect(img, 68, 65, 3, 12, Color(0.5, 0.5, 0.55))
        return _finalize(img)


func _make_weapon_rocket() -> Texture2D:
        var img := _new_image(128)
        # Ombra
        _fill_ellipse(img, 64, 100, 35, 5, Color(0, 0, 0, 0.4))
        # Calcio
        _fill_polygon(img, [
                Vector2(80, 55), Vector2(100, 55), Vector2(103, 95), Vector2(83, 95)
        ], Color(0.3, 0.18, 0.08))
        # Tubo lanciarazzi (verde militare)
        _fill_rect(img, 15, 48, 70, 14, Color(0.3, 0.4, 0.2))   # verde
        _fill_rect(img, 15, 48, 70, 3, Color(0.45, 0.55, 0.3))  # highlight
        _fill_rect(img, 15, 59, 70, 3, Color(0.2, 0.3, 0.1))    # ombra
        # Bocca tubo (nero)
        _fill_rect(img, 12, 50, 5, 10, Color(0.1, 0.1, 0.1))
        # Razzo visibile (in cima)
        _fill_polygon(img, [
                Vector2(15, 50), Vector2(8, 55), Vector2(15, 60)
        ], Color(0.7, 0.5, 0.1))  # punta razzo
        _fill_rect(img, 15, 52, 8, 6, Color(0.8, 0.6, 0.2))     # corpo razzo
        # Impugnatura a pistola
        _fill_polygon(img, [
                Vector2(60, 62), Vector2(72, 62), Vector2(74, 85), Vector2(58, 85)
        ], Color(0.25, 0.15, 0.05))
        # Grilletto
        _fill_rect(img, 65, 75, 3, 10, Color(0.5, 0.5, 0.55))
        # Mirino (ottone)
        _fill_circle(img, 70, 47, 3, Color(0.85, 0.7, 0.2))
        return _finalize(img)


func _make_weapon_laser() -> Texture2D:
        var img := _new_image(128)
        # Ombra
        _fill_ellipse(img, 64, 95, 30, 4, Color(0, 0, 0, 0.4))
        # Calcio (futuristico, viola scuro)
        _fill_polygon(img, [
                Vector2(70, 55), Vector2(95, 55), Vector2(98, 90), Vector2(73, 90)
        ], Color(0.3, 0.15, 0.4))
        # Dettagli calcio (linee blu)
        _draw_line(img, 75, 65, 95, 65, Color(0.2, 0.4, 0.8), 1)
        _draw_line(img, 75, 75, 95, 75, Color(0.2, 0.4, 0.8), 1)
        # Corpo laser (metallo scuro)
        _fill_rect(img, 20, 48, 55, 12, Color(0.3, 0.3, 0.4))
        _fill_rect(img, 20, 48, 55, 2, Color(0.5, 0.5, 0.6))    # highlight
        _fill_rect(img, 20, 58, 55, 2, Color(0.15, 0.15, 0.2))   # ombra
        # Bocca laser (emettitore cyan)
        _fill_rect(img, 14, 50, 8, 8, Color(0.1, 0.4, 0.6))
        _fill_circle(img, 16, 54, 3, Color(0.3, 0.8, 1.0))      # nucleo luminoso
        _fill_circle(img, 16, 54, 1, Color(1.0, 1.0, 1.0))      # bianco
        # Cellula energetica (sopra, cyan glow)
        _fill_rect(img, 45, 42, 15, 8, Color(0.2, 0.6, 0.8))
        _fill_rect(img, 45, 42, 15, 2, Color(0.5, 0.9, 1.0))
        # Grilletto
        _fill_rect(img, 60, 60, 3, 12, Color(0.5, 0.5, 0.55))
        # Impugnatura
        _fill_polygon(img, [
                Vector2(60, 60), Vector2(72, 60), Vector2(74, 85), Vector2(58, 85)
        ], Color(0.2, 0.2, 0.25))
        return _finalize(img)


# ============================================================================
# Helper: poligoni pieni
# ============================================================================
func _fill_polygon(img: Image, points: Array, color: Color) -> void:
        # Scanline fill semplice per poligoni convessi
        if points.size() < 3:
                return
        var min_y: int = 99999
        var max_y: int = -1
        for p in points:
                min_y = min(min_y, int(p.y))
                max_y = max(max_y, int(p.y))
        min_y = max(0, min_y)
        max_y = min(img.get_height() - 1, max_y)
        for y in range(min_y, max_y + 1):
                # Trova intersezioni con gli spigoli
                var x_intersections: Array = []
                for i in points.size():
                        var p1: Vector2 = points[i]
                        var p2: Vector2 = points[(i + 1) % points.size()]
                        if (int(p1.y) <= y and int(p2.y) > y) or (int(p2.y) <= y and int(p1.y) > y):
                                var t: float = float(y - p1.y) / float(p2.y - p1.y)
                                var x: float = p1.x + t * (p2.x - p1.x)
                                x_intersections.append(x)
                x_intersections.sort()
                # Riempi tra coppie di intersezioni
                var i: int = 0
                while i + 1 < x_intersections.size():
                        var x0: int = max(0, int(x_intersections[i]))
                        var x1: int = min(img.get_width() - 1, int(x_intersections[i + 1]))
                        for x in range(x0, x1 + 1):
                                img.set_pixel(x, y, color)
                        i += 2


func _draw_polygon_outline(img: Image, points: Array, color: Color, thickness: int = 1) -> void:
        for i in points.size():
                var p1: Vector2 = points[i]
                var p2: Vector2 = points[(i + 1) % points.size()]
                _draw_line(img, int(p1.x), int(p1.y), int(p2.x), int(p2.y), color, thickness)


func _fill_ellipse(img: Image, cx: int, cy: int, rx: int, ry: int, color: Color) -> void:
        for y in range(-ry, ry + 1):
                for x in range(-rx, rx + 1):
                        if (float(x * x) / float(rx * rx) + float(y * y) / float(ry * ry)) <= 1.0:
                                var px: int = cx + x
                                var py: int = cy + y
                                if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
                                        img.set_pixel(px, py, color)


func _fill_triangle(img: Image, x0: int, y0: int, x1: int, y1: int, x2: int, y2: int, color: Color) -> void:
        _fill_polygon(img, [Vector2(x0, y0), Vector2(x1, y1), Vector2(x2, y2)], color)


func _draw_star(img: Image, cx: int, cy: int, r: int, color: Color) -> void:
        # Stella a 5 punte semplificata (croce + diagonali)
        _fill_rect(img, cx - 1, cy - r, 3, r * 2, color)
        _fill_rect(img, cx - r, cy - 1, r * 2, 3, color)
