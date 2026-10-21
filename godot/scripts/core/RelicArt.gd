## RelicArt.gd — TASK 23: caricamento delle icone PNG ad alta qualità delle
## 18 reliquie (godot/assets/sprites/relics/<id>.png), generate con pipeline
## AI + chroma-key (scripts/gen_relic_icons.sh + process_relic_icons.py).
##
## Pattern di caricamento runtime Image.load (mirror ContinuesScreen/
## HallOfFameScreen): robusto anche prima del primo import dell'editor.
## Cache statica condivisa (pattern _hammer_tex del Player).
##
## FALLBACK: se il PNG non esiste (asset non ancora generato/rollback),
## get_icon() ritorna null e i chiamanti ricadono sulla grafica procedurale
## — il gioco resta giocabile in ogni caso.
class_name RelicArt
extends Object

const BASE_DIR: String = "res://assets/sprites/relics/"

## Cache statica: id -> Texture2D (o null se il file non esiste: il null
## viene cachato anch'esso per non tastare il filesystem a ogni frame).
static var _cache: Dictionary = {}


## Texture dell'icona della reliquia `relic_id` (null se assente).
static func get_icon(relic_id: String) -> Texture2D:
        if _cache.has(relic_id):
                return _cache[relic_id]
        var tex: Texture2D = null
        var abs_path: String = ProjectSettings.globalize_path(BASE_DIR + relic_id + ".png")
        if FileAccess.file_exists(abs_path):
                var img := Image.new()
                if img.load(abs_path) == OK:
                        tex = ImageTexture.create_from_image(img)
        _cache[relic_id] = tex
        return tex


## Texture dell'icona a partire dalla DEFINIZIONE reliquia (Dictionary).
static func get_icon_for_def(def: Dictionary) -> Texture2D:
        return get_icon(str(def.get("id", "")))


## Sfondo dedicato della schermata bonus (fucina/armeria). null se assente.
static func get_bonus_background() -> Texture2D:
        if _cache.has("__bg_bonus"):
                return _cache["__bg_bonus"]
        var tex: Texture2D = null
        var abs_path: String = ProjectSettings.globalize_path(
                        "res://assets/backgrounds/bg_bonus.png")
        if FileAccess.file_exists(abs_path):
                var img := Image.new()
                if img.load(abs_path) == OK:
                        tex = ImageTexture.create_from_image(img)
        _cache["__bg_bonus"] = tex
        return tex


## Svuota la cache (usata dai test per verificare il fallback).
static func clear_cache() -> void:
        _cache.clear()
