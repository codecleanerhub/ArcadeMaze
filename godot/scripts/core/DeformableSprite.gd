## DeformableSprite.gd - Real-time mesh deformation of a single sprite frame.
## ============================================================
## Godot port of `src/DeformableSprite.{h,cpp}`.
##
## Takes ONE texture (or one sub-rect of a spritesheet) and animates it by
## deforming an 8x8 grid of vertices at runtime, instead of using multiple
## pre-rendered frames. Three animation modes:
##
##   * IDLE   - breathing (sinusoidal Y scale, gentle X sway)
##   * WALK   - leg swing (lower-half X sway, vertical bob)
##   * ATTACK - quick horizontal pulse
##
## Implementation notes
## --------------------
## Godot's MeshInstance2D can draw an `ArrayMesh` whose vertex buffer we rewrite
## each frame. We use `Mesh.PRIMITIVE_TRIANGLES` (2 tris per quad, 64 quads)
## to stay compatible with the gl_compatibility renderer.
##
## Equivalent to the C++ class's `sf::VertexArray` with `sf::Quads`.
extends MeshInstance2D
class_name DeformableSprite

## TASK 26 — enhancement canvas_item per i boss (fix "colori sbiaditi"):
## shader boss_deform.gdshader campiona la texture via uniform esplicita
## e replica la pipeline di character_enhanced (sharpening + contrasto +
## saturazione + fake-normal + rim). Prima lo shader veniva applicato al
## nodo Boss (apply_enhancement_to_canvas_item) ma i materiali CanvasItem
## NON si propagano ai figli: il DeformableSprite renderizzava con il solo
## StandardMaterial3D (nessun enhancement) -> boss visivamente PIU' SPENTI
## di player/nemici. enable_canvas_enhancement() mette il materiale
## direttamente su QUESTO nodo (validato con lab numerico: i colori seguono
## esattamente la stessa pipeline dei player). Rollback: lasciare
## disabilitato (o GameConstants.BOSS_CANVAS_SHADER_ENABLED = false).
const BOSS_DEFORM_SHADER := preload("res://shaders/boss_deform.gdshader")

## TASK 26 — true = il mesh viene disegnato con lo shader canvas di
## enhancement (parametri in _enh_*). Il materiale di superficie
## StandardMaterial3D resta creato come fallback (se il flag si spegne il
## rendering torna identico al pre-Task-26).
var _canvas_enhanced: bool = false
var _enh_sharpness: float = 0.8
var _enh_contrast: float = 1.2
var _enh_saturation: float = 1.3
var _enh_rim: float = 0.7
var _enh_depth: float = 0.7

enum AnimMode { IDLE, WALK, ATTACK }

## TASK 22 — Profili di animazione proceduale degli arti (per boss).
## Aggiungono spostamenti sinusoidali localizzati (tentacoli in basso,
## braccia ai lati, ali in alto, assetto fluttuante, stalke oculari in alto)
## SENZA frame aggiuntivi: la stessa texture viene deformata sul mesh.
## LP_NONE = comportamento identico al precedente (solo IDLE/WALK/ATTACK).
enum LimbProfile {
        LP_NONE,
        LP_TENTACLES,   # Kraken, Abomination: onda travelling sugli appendici bassi
        LP_ARMS,        # Golem, Spider, Ghoul: braccia/zampe laterali alternate
        LP_WINGS,       # Demone, Drago: battito d'ali in alto ai lati
        LP_HOVER,       # Lich, Wraith, Vampiro...: fluttuazione + scia veste
        LP_STALKS,      # Beholder: stalke oculari in alto che ondeggiano
}

## Default grid resolution (8x8 = 64 quads = 128 tris).
const DEFAULT_GRID_W := 8
const DEFAULT_GRID_H := 8

## TASK 28 — rete di sicurezza anti-glitch: offset massimo (in "unita' frame
## 64px") di OGNI componente dello spostamento vertice. Il gain 2.6 del
## Task 25 portava gli arti a 6-13% del lato dello sprite: la mesh (UV statici
## su vertici in movimento) si LACERAVA -> smearing, doppie immagini, sagome
## che escono dal corpo ("boss glitchati/confusi"). Con il clamp lo
## spostamento resta <= ~3.9% del lato (2.5px su frame SD 64px, 10px su XHD
## 256px): animazione visibile MA integrita' dello sprite garantita per
## qualunque valore di limb_gain (anche futuro). I modalita' IDLE/WALK/ATTACK
## e i nemici/miniboss (offset <= 2.0) NON sono toccati.
const MAX_LIMB_OFFSET_UNITS := 2.5

## TASK 22 — profilo arti corrente (LP_NONE di default: identico al legacy).
var limb_profile: int = LimbProfile.LP_NONE

## TASK 25 — guadagno delle ampiezze degli arti procedurali (1.0 = identico
## al Task 22). Il boss/mini-boss lo imposta da GameConstants.BOSS_LIMB_ANIM_GAIN:
## le ampiezze "subtle" originali (~2-4% del lato) erano invisibili a schermo.
var limb_gain: float = 1.0

## TASK 22 — fattore di scala delle ampiezze di deformazione: tiene
## l'entità dello spostamento A SCHERMO identica tra sheet 64px (unit=1)
## e sheet XHD 256px (unit=4).
var _unit: float = 1.0

## Sub-rect loaded from the source texture (defaults to the full texture).
@export var sub_rect: Rect2 = Rect2(0, 0, 0, 0):
        set(v):
                sub_rect = v
                _rebuild_mesh()

@export var grid_w: int = DEFAULT_GRID_W:
        set(v):
                grid_w = max(2, v)
                _rebuild_mesh()

@export var grid_h: int = DEFAULT_GRID_H:
        set(v):
                grid_h = max(2, v)
                _rebuild_mesh()

## Source texture (PNG spritesheet or single frame).
var _tex: Texture2D = null

# Custom setter (renamed to avoid conflict with MeshInstance2D's native set_texture).
func assign_sprite_texture(v: Texture2D) -> void:
        _tex = v
        texture = v
        if _tex != null and sub_rect == Rect2(0, 0, 0, 0):
                sub_rect = Rect2(0, 0, texture.get_width(), texture.get_height())
        _rebuild_mesh()

var loaded: bool = false

# Cached base positions (Vector2) for each grid vertex (gridW+1)*(gridH+1).
var _base_positions: PackedVector2Array = []
# Cached base UVs.
var _base_uvs: PackedVector2Array = []

# Current animation state.
var _current_scale: float = 1.0
var _current_flipped: bool = false
var _current_mode: int = AnimMode.IDLE

# Internal mesh arrays.
var _mesh: ArrayMesh = null
var _verts: PackedVector2Array = []
var _uvs: PackedVector2Array = []
var _indices: PackedInt32Array = []


func _ready() -> void:
        if _mesh == null:
                _mesh = ArrayMesh.new()
                _rebuild_mesh()
        mesh = _mesh


## Load a PNG file by path. Returns true on success.
func load_file(path: String) -> bool:
        var tex := load(path) as Texture2D
        if tex == null:
                loaded = false
                return false
        texture = tex
        sub_rect = Rect2(0, 0, tex.get_width(), tex.get_height())
        _rebuild_mesh()
        loaded = true
        return true


## Load a sub-rect from a texture path. Equivalent to C++:
##   deformSprite.load(pngPath, frameX, frameY, frameW, frameH)
func load_subrect(path: String, frame_x: int, frame_y: int, frame_w: int, frame_h: int) -> bool:
        var tex := load(path) as Texture2D
        if tex == null:
                loaded = false
                return false
        _tex = tex
        texture = tex
        if frame_w <= 0 or frame_h <= 0:
                sub_rect = Rect2(0, 0, tex.get_width(), tex.get_height())
        else:
                sub_rect = Rect2(frame_x, frame_y, frame_w, frame_h)
        _rebuild_mesh()
        loaded = true
        return true


## Use an already-loaded Texture2D directly.
func assign_texture(tex: Texture2D, sub: Rect2 = Rect2(0, 0, 0, 0)) -> void:
        _tex = tex
        texture = tex
        if sub.size.x > 0 and sub.size.y > 0:
                sub_rect = sub
        elif tex != null:
                sub_rect = Rect2(0, 0, tex.get_width(), tex.get_height())
        _rebuild_mesh()
        loaded = tex != null


func set_grid_size(w: int, h: int) -> void:
        grid_w = max(2, w)
        grid_h = max(2, h)
        _rebuild_mesh()


# -----------------------------------------------------------------------
# TASK 26 — enhancement canvas (vedi commento in testa al file).
# -----------------------------------------------------------------------
## Attiva lo shader canvas di enhancement sul mesh. I default sono i
## parametri "strong" dei boss (identici a CharacterArt._enhanced_strong).
func enable_canvas_enhancement(sharp: float = 0.8, contrast: float = 1.2,
                saturation: float = 1.3, rim: float = 0.7, depth: float = 0.7) -> void:
        _canvas_enhanced = true
        _enh_sharpness = sharp
        _enh_contrast = contrast
        _enh_saturation = saturation
        _enh_rim = rim
        _enh_depth = depth
        if texture != null:
                _apply_canvas_enhancement()


## Spegne lo shader canvas (rendering = pre-Task-26, solo StandardMaterial3D).
func disable_canvas_enhancement() -> void:
        _canvas_enhanced = false
        material = null


func _apply_canvas_enhancement() -> void:
        if texture == null:
                return
        var mat := ShaderMaterial.new()
        mat.shader = BOSS_DEFORM_SHADER
        mat.set_shader_parameter("src_tex", texture)
        mat.set_shader_parameter("texel_size",
                Vector2(1.0 / float(texture.get_width()),
                        1.0 / float(texture.get_height())))
        mat.set_shader_parameter("sharpness", _enh_sharpness)
        mat.set_shader_parameter("contrast", _enh_contrast)
        mat.set_shader_parameter("saturation", _enh_saturation)
        mat.set_shader_parameter("rim_intensity", _enh_rim)
        mat.set_shader_parameter("depth_strength", _enh_depth)
        material = mat
        # Filtro coerente col percorso legacy: NEAREST sui frame 64px
        # (look pixel identico a prima), LINEAR sui frame XHD 256px (bordi
        # lisci: fix "sgranati").
        texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if sub_rect.size.x <= 64.0 \
                        else CanvasItem.TEXTURE_FILTER_LINEAR


## Update the animation. `time` is in seconds (cumulative).
## `scale` is the final scale factor (e.g. boss size / 64).
## `flipped` mirrors the sprite horizontally.
func update(time: float, mode: int, scale_val: float = 1.0, flipped: bool = false) -> void:
        _current_scale = scale_val
        _current_flipped = flipped
        _current_mode = mode
        if not loaded or _mesh == null:
                return
        _apply_deformation(time, mode)
        _sync_mesh()


## Draw the sprite at (x, y) in local coords.
## Godot handles drawing automatically via MeshInstance2D; this method exists
## for API compatibility with the C++ version. Set `position` on the node
## before calling this for direct control.
func render(x: float, y: float) -> void:
        position = Vector2(x, y)


# -----------------------------------------------------------------------
# Internal: mesh construction & deformation
# -----------------------------------------------------------------------

func _rebuild_mesh() -> void:
        if texture == null or sub_rect.size.x <= 0 or sub_rect.size.y <= 0:
                loaded = false
                return

        var n_verts := (grid_w + 1) * (grid_h + 1)
        _base_positions.resize(n_verts)
        _base_uvs.resize(n_verts)

        # Build base positions in [0..subW, 0..subH] and corresponding UVs.
        for gy in range(grid_h + 1):
                for gx in range(grid_w + 1):
                        var idx := gy * (grid_w + 1) + gx
                        var px: float = (float(gx) / float(grid_w)) * sub_rect.size.x
                        var py: float = (float(gy) / float(grid_h)) * sub_rect.size.y
                        _base_positions[idx] = Vector2(px, py)
                        # UVs map into the original texture (use sub_rect offset).
                        var tx: float = (sub_rect.position.x + px) / texture.get_width()
                        var ty: float = (sub_rect.position.y + py) / texture.get_height()
                        _base_uvs[idx] = Vector2(tx, ty)

        # Allocate vertex/index buffers for triangle list (2 tris per quad).
        var n_quads := grid_w * grid_h
        _verts.resize(n_quads * 6)
        _uvs.resize(n_quads * 6)
        _indices.resize(n_quads * 6)
        for i in range(n_quads * 6):
                _indices[i] = i

        # Static UVs (do not change with deformation).
        for gy in range(grid_h):
                for gx in range(grid_w):
                        var v00 := gy * (grid_w + 1) + gx
                        var v10 := gy * (grid_w + 1) + (gx + 1)
                        var v01 := (gy + 1) * (grid_w + 1) + gx
                        var v11 := (gy + 1) * (grid_w + 1) + (gx + 1)
                        var q := (gy * grid_w + gx) * 6
                        _uvs[q + 0] = _base_uvs[v00]
                        _uvs[q + 1] = _base_uvs[v10]
                        _uvs[q + 2] = _base_uvs[v11]
                        _uvs[q + 3] = _base_uvs[v00]
                        _uvs[q + 4] = _base_uvs[v11]
                        _uvs[q + 5] = _base_uvs[v01]

        loaded = true

        # Allocate mesh if needed; we will clear and refill surface each frame.
        if _mesh == null:
                _mesh = ArrayMesh.new()
        _mesh.clear_surfaces()
        if mesh == null:
                mesh = _mesh

        # Build an empty surface (correct layout); vertices will be filled by _sync_mesh.
        var arr := []
        arr.resize(Mesh.ARRAY_MAX)
        arr[Mesh.ARRAY_VERTEX] = _verts
        arr[Mesh.ARRAY_TEX_UV] = _uvs
        arr[Mesh.ARRAY_INDEX] = _indices
        _mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)

        # Apply texture via the mesh surface material.
        # In Godot 4.7, MeshInstance2D renders the ArrayMesh, and the material
        # must be set on the mesh surface itself.
        # TASK 22: filtro adattivo — NEAREST per i frame 64px legacy (look
        # identico a prima), LINEAR per i frame XHD 256px (bordi lisci).
        var mat := StandardMaterial3D.new()
        mat.albedo_texture = texture
        mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST if sub_rect.size.x <= 64.0 \
                        else BaseMaterial3D.TEXTURE_FILTER_LINEAR
        mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        if _mesh.get_surface_count() > 0:
                _mesh.surface_set_material(0, mat)

        # TASK 22: ampiezze in "unità frame 64px" -> costanti a schermo.
        _unit = maxf(sub_rect.size.x, sub_rect.size.y) / 64.0

        # TASK 26: se l'enhancement canvas è attivo, (ri)costruisci il
        # materiale shader sul nodo (la texture è appena cambiata: il
        # uniform src_tex e texel_size vanno aggiornati).
        if _canvas_enhanced:
                _apply_canvas_enhancement()


func _apply_deformation(time: float, mode: int) -> void:
        # Compute per-vertex offsets (we write into _verts directly).
        var gw := grid_w
        var gh := grid_h
        var scale := _current_scale
        var flip := _current_flipped
        var tw: float = sub_rect.size.x
        var th: float = sub_rect.size.y

        for gy in range(gh):
                for gx in range(gw):
                        var v00 := gy * (gw + 1) + gx
                        var v10 := gy * (gw + 1) + (gx + 1)
                        var v01 := (gy + 1) * (gw + 1) + gx
                        var v11 := (gy + 1) * (gw + 1) + (gx + 1)
                        var q := (gy * gw + gx) * 6

                        var p00 := _transform_vertex(v00, mode, time, gw, gh, scale, flip, tw, th)
                        var p10 := _transform_vertex(v10, mode, time, gw, gh, scale, flip, tw, th)
                        var p11 := _transform_vertex(v11, mode, time, gw, gh, scale, flip, tw, th)
                        var p01 := _transform_vertex(v01, mode, time, gw, gh, scale, flip, tw, th)

                        _verts[q + 0] = p00
                        _verts[q + 1] = p10
                        _verts[q + 2] = p11
                        _verts[q + 3] = p00
                        _verts[q + 4] = p11
                        _verts[q + 5] = p01


func _transform_vertex(idx: int, mode: int, time: float,
                gw: int, gh: int, scale: float, flip: bool,
                tw: float, th: float) -> Vector2:
        var base: Vector2 = _base_positions[idx]
        var gx: int = idx % (gw + 1)
        var gy: int = idx / (gw + 1)
        var wx: float = sin(float(gx) / float(gw) * PI)
        var wy: float = sin(float(gy) / float(gh) * PI)
        var weight: float = wx * wy
        var off := Vector2.ZERO

        match mode:
                AnimMode.IDLE:
                        off.x = sin(time * 1.5) * 0.8 * weight
                        off.y = sin(time * 2.0) * 1.5 * weight
                AnimMode.WALK:
                        var vert_w: float = float(gy) / float(gh)
                        vert_w *= vert_w
                        var bob_y: float = sin(time * 8.0) * 1.5 * 0.5
                        var leg_sway: float = 0.0
                        if gy > gh / 2:
                                var side: float = -1.0 if (gx < gw / 2) else 1.0
                                leg_sway = sin(time * 8.0) * 2.0 * side * vert_w
                        var breath: float = sin(time * 2.0) * 0.8 * wx * (1.0 - vert_w)
                        off.x = leg_sway
                        off.y = bob_y + breath
                AnimMode.ATTACK:
                        var pulse: float = sin(time * 15.0) * 2.0
                        var atk_w: float = wx * (1.0 - float(gy) / float(gh) * 0.3)
                        off.x = pulse * atk_w
                        off.y = sin(time * 2.0) * 0.5 * wx

        # TASK 22 — animazione proceduale degli arti (boss). Amplitude in
        # unità-frame (moltiplicate per _unit = 4 sugli XHD) => a schermo è
        # identica tra SD e XHD, e resta SUBTLE (~2-5% del lato dello sprite).
        if limb_profile != LimbProfile.LP_NONE:
                var u: float = float(gx) / float(gw)
                var v: float = float(gy) / float(gh)
                var lg: float = limb_gain
                match limb_profile:
                        LimbProfile.LP_TENTACLES:
                                # onda travelling che cresce verso il basso
                                var vw: float = clampf((v - 0.45) / 0.55, 0.0, 1.0)
                                off.x += sin(time * 2.4 + v * 7.0 + u * 3.0) * 2.2 * vw * lg
                                off.y += cos(time * 3.1 + v * 9.0) * 0.8 * vw * lg
                        LimbProfile.LP_ARMS:
                                # colonne laterali che oscillano in controfase
                                var sw: float = clampf((absf(u - 0.5) - 0.18) / 0.32, 0.0, 1.0)
                                var phase: float = PI if u < 0.5 else 0.0
                                off.y += sin(time * 2.6 + phase) * 2.4 * sw * lg
                                off.x += cos(time * 2.6 + phase) * 1.0 * sw * lg
                        LimbProfile.LP_WINGS:
                                # battito: alto+ai lati, ali che si aprono
                                var top_w: float = clampf((0.55 - v) / 0.55, 0.0, 1.0)
                                var sw2: float = clampf((absf(u - 0.5) - 0.18) / 0.32, 0.0, 1.0)
                                var flap: float = sin(time * 3.4)
                                off.y += flap * 3.2 * sw2 * top_w * lg
                                off.x += (flap * 1.6 + 0.8) * sw2 * top_w * lg
                        LimbProfile.LP_HOVER:
                                # fluttuazione globale + scia della veste in basso
                                off.y += sin(time * 1.7) * 1.8 * weight * lg
                                off.x += sin(time * 2.1 + v * 5.0) * 1.4 * v * v * lg
                        LimbProfile.LP_STALKS:
                                # stalke oculari (in alto) che ondeggiano
                                var tw2: float = clampf((0.5 - v) / 0.5, 0.0, 1.0)
                                off.x += sin(time * 2.2 + (0.5 - v) * 8.0 + u * 2.5) * 2.0 * tw2 * lg
                                off.y += cos(time * 2.8 + u * 3.0) * 1.2 * tw2 * lg

        # TASK 28: tutte le ampiezze sono in "unità frame 64px"; su mesh XHD
        # (256px) vanno moltiplicate per 4 per mantenere lo stesso spostamento
        # A SCHERMO. Con sheet legacy 64px _unit = 1 -> output identico al
        # codice precedente (bit per bit).
        # TASK 28: CLAMP di integrita' (vedi MAX_LIMB_OFFSET_UNITS): qualunque
        # combinazione di gain/profilo non puo' spostare un vertice oltre
        # ~3.9% del lato -> niente smearing/lacerazioni della texture.
        off.x = clampf(off.x, -MAX_LIMB_OFFSET_UNITS, MAX_LIMB_OFFSET_UNITS)
        off.y = clampf(off.y, -MAX_LIMB_OFFSET_UNITS, MAX_LIMB_OFFSET_UNITS)
        off *= _unit
        var pos: Vector2 = base + off
        pos.x *= scale
        pos.y *= scale
        if flip:
                pos.x = tw * scale - pos.x
        return pos


func _sync_mesh() -> void:
        if _mesh == null or _mesh.get_surface_count() == 0:
                return
        # Cheap path: rewrite the vertex array of surface 0.
        var arr := _mesh.surface_get_arrays(0)
        arr[Mesh.ARRAY_VERTEX] = _verts
        _mesh.surface_remove(0)
        _mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
