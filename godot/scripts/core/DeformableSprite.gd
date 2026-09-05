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

enum AnimMode { IDLE, WALK, ATTACK }

## Default grid resolution (8x8 = 64 quads = 128 tris).
const DEFAULT_GRID_W := 8
const DEFAULT_GRID_H := 8

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
        var mat := StandardMaterial3D.new()
        mat.albedo_texture = texture
        mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
        mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        if _mesh.get_surface_count() > 0:
                _mesh.surface_set_material(0, mat)


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
