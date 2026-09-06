## SpriteManager.gd - Autoload
## ============================================================
## Loads and caches all sprites from `res://assets/sprites/`.
##
## Spritesheet layout conventions (from the C++ SpriteSheet module):
##   - `<id>_sheet.png`         - PNG spritesheet (256x64 = 4 frames, 64x64 = 1 frame)
##   - `<id>_meta.json`         - optional metadata (frameW/frameH/cols/rows + animations)
##
## Standard spritesheets have a single row of 4 frames (idle/walk/attack/death all
## collapsed into one row, see `boss_021_meta.json` columns=4 rows=1). Larger sheets
## (384x256, 6 cols x 4 rows) are also supported via the metadata file.
##
## Usage:
##   SpriteManager.load_all()
##   var sheet := SpriteManager.get_sheet("boss_021")
##   var tex   := sheet.get_frame_texture("idle", 0)
extends Node


## Emitted once after load_all() finishes (success or partial failure).
signal loaded()

## A loaded spritesheet entry.
class Sheet:
        var texture: Texture2D = null
        var frame_w: int = 64
        var frame_h: int = 64
        var columns: int = 4
        var rows: int = 1
        var animations: Dictionary = {}   # anim_name -> { "row": int, "frames": int, "frameDuration": int }

        func is_loaded() -> bool:
                return texture != null

        ## Get frame index as a sub-rect of the underlying texture.
        func get_frame_rect(anim_name: String, frame_idx: int) -> Rect2:
                var info: Dictionary = animations.get(anim_name, {})
                var row: int = int(info.get("row", 0))
                var nframes: int = int(info.get("frames", 1))
                if nframes <= 0:
                        nframes = 1
                frame_idx = clampi(frame_idx, 0, nframes - 1)
                var x: int = frame_idx * frame_w
                var y: int = row * frame_h
                return Rect2(x, y, frame_w, frame_h)

        ## Get a sub-rect texture for a single frame (cached lazily per call).
        func get_frame_texture(anim_name: String, frame_idx: int) -> AtlasTexture:
                if texture == null:
                        return null
                var rect := get_frame_rect(anim_name, frame_idx)
                var at := AtlasTexture.new()
                at.atlas = texture
                at.region = rect
                return at

        func get_frame_count(anim_name: String) -> int:
                var info: Dictionary = animations.get(anim_name, {})
                return int(info.get("frames", 0))


## ---- Public API ----

## Autoload lifecycle: load all sprites on startup.
func _ready() -> void:
        load_all()


## Load all `<id>_sheet.png` sprites found under the sprites folder.
## Missing files / JSON metadata are skipped silently (same behaviour as C++).
func load_all(base_path: String = "res://assets/sprites/") -> void:
        _sheets.clear()
        var dir := DirAccess.open(base_path)
        if dir == null:
                push_warning("SpriteManager: cannot open %s" % base_path)
                loaded.emit()
                return

        dir.list_dir_begin()
        var file_name := dir.get_next()
        while file_name != "":
                if not dir.current_is_dir() and file_name.ends_with("_sheet.png"):
                        var id := file_name.substr(0, file_name.length() - "_sheet.png".length())
                        _load_sheet(base_path, id)
                file_name = dir.get_next()
        dir.list_dir_end()
        loaded.emit()


## Retrieve a cached Sheet by id (e.g. "boss_021" or "miniboss_05").
func get_sheet(id: String) -> Sheet:
        if _sheets.has(id):
                return _sheets[id]
        return null


## Convenience: get a frame texture directly.
func get_frame(id: String, anim: String, idx: int) -> AtlasTexture:
        var s: Sheet = get_sheet(id)
        if s == null:
                return null
        return s.get_frame_texture(anim, idx)


## Convenience: get frame count for an animation.
func get_frame_count(id: String, anim: String) -> int:
        var s: Sheet = get_sheet(id)
        if s == null:
                return 0
        return s.get_frame_count(anim)


## ---- Internals ----

var _sheets: Dictionary = {}   # id -> Sheet


func _load_sheet(base_path: String, id: String) -> void:
        var png_path := base_path + id + "_sheet.png"
        var meta_path := base_path + id + "_meta.json"

        # --- HD PRIORITY: carica la versione HD 256x256 se disponibile ---
        # Gli HD sheet sono in res://assets/sprites/hd/<id>_hd_sheet.png
        # e hanno 4x la risoluzione degli originali 64x64 (256x256 totali).
        var hd_png_path := "res://assets/sprites/hd/" + id + "_hd_sheet.png"
        var tex: Texture2D = null
        var is_hd: bool = false
        if ResourceLoader.exists(hd_png_path):
                tex = load(hd_png_path) as Texture2D
                if tex != null:
                        is_hd = true
        # Fallback: carica lo sheet originale se l'HD non esiste
        if tex == null:
                tex = load(png_path) as Texture2D
        if tex == null:
                return

        var sheet := Sheet.new()
        sheet.texture = tex

        # Default size: 64x64 frames per originali, 64x64 (4x4 grid) per HD.
        # FIX (graphics gap #2 — HD sprites treated as single 256x256 frame):
        # The HD sheets are 256x256 RGBA and contain a TRUE 4x4 grid of 16
        # distinct 64x64 frames (verified by inspecting boss_021_hd_sheet.png:
        # the 4 quadrants are visually different images). The previous code
        # treated the whole 256x256 as ONE giant frame, throwing away 15/16 of
        # the pixel data and preventing HD sprites from animating. We now treat
        # HD sheets as 4x4 = 16 frames, matching the asset pipeline intent and
        # letting every HD creature animate through 4 idle / 4 walk / 4 attack
        # / 4 death frames at no extra art cost.
        if is_hd:
                # HD sheet: 256x256 = 4 cols x 4 rows of 64x64 frames.
                sheet.frame_w = 64
                sheet.frame_h = 64
                sheet.columns = 4
                sheet.rows = 4
        else:
                # Sheet originale 256x64 = 4 frame da 64x64
                sheet.frame_w = 64
                sheet.frame_h = 64
                sheet.columns = 4
                sheet.rows = 1

        # Try metadata JSON for exact dimensions/animations (solo per sheet originali).
        # Gli HD sheet sono singoli frame, ignorano i metadata delle animazioni.
        if not is_hd:
                var meta: Variant = _load_json(meta_path)
                if meta != null and not meta.is_empty():
                        sheet.frame_w = int(meta.get("frameWidth", 64))
                        sheet.frame_h = int(meta.get("frameHeight", 64))
                        sheet.columns = int(meta.get("columns", 4))
                        sheet.rows = int(meta.get("rows", 1))
                        var anims: Dictionary = meta.get("animations", {})
                        for anim_name in anims:
                                var info = anims[anim_name]
                                if info is Dictionary:
                                        sheet.animations[anim_name] = {
                                                "row": int(info.get("row", 0)),
                                                "frames": int(info.get("frames", 1)),
                                                "frameDuration": int(info.get("frameDuration", 200)),
                                        }
                else:
                        # No meta - infer from texture size assuming 64x64 frames.
                        var tw: int = tex.get_width()
                        var th: int = tex.get_height()
                        if tw > 0 and th > 0:
                                sheet.columns = int(tw) / sheet.frame_w
                                sheet.rows = int(th) / sheet.frame_h
                                if sheet.columns < 1:
                                        sheet.columns = 1
                                if sheet.rows < 1:
                                        sheet.rows = 1
                # Default animations: single row, columns = idle frame count.
                sheet.animations["idle"] = {"row": 0, "frames": sheet.columns, "frameDuration": 200}
                sheet.animations["walk"] = {"row": 0, "frames": sheet.columns, "frameDuration": 120}
                sheet.animations["attack"] = {"row": 0, "frames": sheet.columns, "frameDuration": 90}
                sheet.animations["death"] = {"row": 0, "frames": 1, "frameDuration": 120}
        else:
                # HD sheet (4x4 grid). Use the standard 4-row animation layout
                # matching the C++ SpriteSheet convention (SpriteSheet.cpp:54):
                #   row 0 = idle (4 frames)
                #   row 1 = walk  (4 frames)
                #   row 2 = attack (4 frames)
                #   row 3 = death (4 frames)
                # This finally realises the README's original 4-row spritesheet
                # spec at HD resolution for all 106 HD creatures.
                sheet.animations["idle"] = {"row": 0, "frames": 4, "frameDuration": 200}
                sheet.animations["walk"] = {"row": 1, "frames": 4, "frameDuration": 120}
                sheet.animations["attack"] = {"row": 2, "frames": 4, "frameDuration": 90}
                sheet.animations["death"] = {"row": 3, "frames": 4, "frameDuration": 120}

        _sheets[id] = sheet


func _load_json(path: String) -> Variant:
        if not FileAccess.file_exists(path):
                return null
        var f := FileAccess.open(path, FileAccess.READ)
        if f == null:
                return null
        var txt := f.get_as_text()
        f.close()
        var json := JSON.new()
        var err := json.parse(txt)
        if err != OK:
                return null
        return json.data
