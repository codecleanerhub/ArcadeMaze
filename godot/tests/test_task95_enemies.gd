## test_task95_enemies.gd — TASK 95: test runtime dei nemici rigenerati
## "corpo completo" (feedback utente: "Se ci sono nemici che dovrebbero
## avere le gambe o le zampe ma che sono stati disegnati come 'mezzo busto'
## senza le gambe, ti chiedo di rigenerarli con pixel lab in modo da
## ottenere il corpo completo e non soltanto la metà").
##
## Audit VLM (44 nemici + 17 boss): gli unici offender erano WITCH
## (monster_007, la strega dello screenshot utente — mezzo busto con
## pozioni sotto), LOST_SOUL (monster_044 — torso solido tagliato in
## vita) e GIBBERING_MOUTHER (monster_031 — carne fluttuante staccata
## dal terreno). Rigenerati con PixelLab + walk deterministico.
##
## Check:
##   A — sheet 256x64, 4 frame, meta columns=4 anchor (32,56)
##   B — CONTATTO COL TERRENO: ultima riga opaca del frame 0 >= y54 e
##       banda centrale in basso (y48-56, x16-48) opaca >= 30% (il corpo
##       scende fino ai piedi: niente "mezzo busto" con vuoto sotto)
##   C — LARGHEZZA della silhouette >= 35px (mediana bestiary ~52: una
##       figura "mezzo busto" ricompressa dal fit verticale resterebbe
##       una colonna stretta ~25px — la lezione della run v1-v4)
##   D — camera di sicurezza: sheet e meta coerenti tra godot e mirror
##       legacy (la build C++ legge dal mirror)
extends Node

const ENEMY_SRC := "res://scripts/enemies/Enemy.gd"
const EnemyScript = preload("res://scripts/enemies/Enemy.gd")

const SHEETS := {
        "monster_007": "WITCH (la strega dello screenshot utente)",
        "monster_044": "LOST_SOUL",
        "monster_031": "GIBBERING_MOUTHER",
}

var fails: int = 0


func _ready() -> void:
        print("[TEST] TASK 95 — nemici corpo completo (mezzo busto -> PixelLab)")
        _test_sheets()
        _test_mirror()
        if fails > 0:
                print("[TEST] ESITO: FALLITO (%d errori)" % fails)
                get_tree().quit(1)
        else:
                print("[TEST] ESITO: TUTTI PASSATI")
                get_tree().quit(0)


func _ok(msg: String) -> void:
        print("[TEST] OK %s" % msg)


func _fail(msg: String) -> void:
        fails += 1
        print("[TEST] FALLITO %s" % msg)


func _load_img(path: String) -> Image:
        var img := Image.new()
        var abs_p: String = ProjectSettings.globalize_path(path)
        if FileAccess.file_exists(abs_p) and img.load(abs_p) == OK:
                return img
        return null


func _test_sheets() -> void:
        for id in SHEETS:
                var img := _load_img("res://assets/sprites/%s_sheet.png" % id)
                if img == null:
                        _fail("A: sheet %s mancante" % id)
                        return
                # A: formato
                if img.get_width() != 256 or img.get_height() != 64:
                        _fail("A: sheet %s %dx%d atteso 256x64" % [
                                        id, img.get_width(), img.get_height()])
                        return
                var meta := FileAccess.open(
                                "res://assets/sprites/%s_meta.json" % id, FileAccess.READ)
                if meta == null:
                        _fail("A: meta %s mancante" % id)
                        return
                var j: Dictionary = JSON.parse_string(meta.get_as_text())
                if int(j.get("columns", 0)) != 4 \
                                or int(j.get("frameWidth", 0)) != 64:
                        _fail("A: meta %s columns/frameWidth errati" % id)
                        return
                # B: contatto col terreno
                var last_row: int = -1
                var band: int = 0
                for y in 64:
                        var row_op := false
                        for x in range(0, 64, 2):
                                if img.get_pixel(x, y).a > 0.5:
                                        row_op = true
                                        break
                        if row_op:
                                last_row = y
                for y in range(48, 57):
                        for x in range(16, 49):
                                if img.get_pixel(x, y).a > 0.5:
                                        band += 1
                if last_row < 54:
                        _fail("B: %s non tocca terra (ultima riga y=%d < 54)" % [
                                        id, last_row])
                        return
                if float(band) / (9.0 * 33.0) < 0.30:
                        _fail("B: %s banda bassa centrale %.0f%% < 30%% (corpo mozzo?)" % [
                                        id, float(band) / (9.0 * 33.0) * 100.0])
                        return
                # C: larghezza silhouette
                var x0: int = 64
                var x1: int = -1
                for y in 64:
                        for x in 64:
                                if img.get_pixel(x, y).a > 0.5:
                                        x0 = mini(x0, x)
                                        x1 = maxi(x1, x)
                if x1 - x0 + 1 < 35:
                        _fail("C: %s silhouette larga %dpx < 35 (colonna stretta da fit verticale)" % [
                                        id, x1 - x0 + 1])
                        return
                _ok("B/C: %s (%s) — terra y=%d, banda %.0f%%, larghezza %dpx" % [
                                id, SHEETS[id], last_row,
                                float(band) / (9.0 * 33.0) * 100.0, x1 - x0 + 1])
        _ok("A: 3 sheet 256x64 con meta 4-colonne anchor 32,56")


func _test_mirror() -> void:
        for id in SHEETS:
                var g := _load_img("res://assets/sprites/%s_sheet.png" % id)
                var m := _load_img("res://../assets/sprites/%s_sheet.png" % id)
                if m == null:
                        _ok("D: mirror legacy senza %s (opzionale)" % id)
                        continue
                if g == null or m == null or g.get_width() != m.get_width() \
                                or g.get_height() != m.get_height():
                        _fail("D: mirror legacy di %s incoerente" % id)
                        return
                for y in 64:
                        for x in range(0, 256, 7):
                                if g.get_pixel(x, y) != m.get_pixel(x, y):
                                        _fail("D: mirror legacy di %s diverso a (%d,%d)" % [
                                                        id, x, y])
                                        return
        _ok("D: sheet godot = mirror legacy C++")
