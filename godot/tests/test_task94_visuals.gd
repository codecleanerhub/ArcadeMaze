## test_task94_visuals.gd — TASK 94: test runtime degli asset visivi
## (feedback utente: (1) portali morte boss procedurali -> pixel-art
## PixelLab; (2) lame "sembrano dischi" -> lame affilate; (3) blocchi blu
## delle fosse -> integrati nella palette del labirinto).
##
## Check:
##   A — sheet LAMA AFFILATA: 4 frame 64x64, forma a X (angoli
##       trasparenti, copertura < 40% = non-disco, mozzo centrale opaco),
##       frame diversi tra loro (rotazione)
##   B — sheet PORTALE infernale: 4 frame 128x128 (autodetect larghezza/4
##       del loader _fx_frame), frame diversi (apertura progressiva),
##       centro lava incandescente nel frame aperto
##   C — sheet ANELLO runico: 4 frame 128x128, keyato per luminanza
##       (copertura glow 8-35%, luminanza media > 120 = niente pietra scura)
##   D — ricolorazione VORAGINI: chasm_crack caldo (R medio > B medio),
##       crepe scure opache + superficie semitrasparente (>25% pixel con
##       alpha 150-235); chasm_open caldo con bordo pietra leggibile
##   E — loader retrocompatibile: _fx_frame("vortex") resta 64x64
##   F — guardie sorgente (portal/ring nel draw, blade_sharp_sheet
##       preferito, blink caldo della crepa)
extends Node

const BDS = preload("res://scripts/entities/BossDeathSequences.gd")
const HazardsScript = preload("res://scripts/entities/MazeHazards.gd")

const BDS_SRC := "res://scripts/entities/BossDeathSequences.gd"
const HZ_SRC := "res://scripts/entities/MazeHazards.gd"
const ENV_DIR := "res://assets/sprites/env/"
const HZ_DIR := "res://assets/sprites/hazards/"

var fails: int = 0


func _ready() -> void:
        print("[TEST] TASK 94 — portali/lame/voragini pixel-art coerenti")
        _test_blade_sharp()
        _test_portal_sheet()
        _test_ring_sheet()
        _test_chasm_recolor()
        _test_loader_compat()
        _test_source_guards()
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


func _load_img(res_path: String) -> Image:
        var img := Image.new()
        var abs_p: String = ProjectSettings.globalize_path(res_path)
        if FileAccess.file_exists(abs_p) and img.load(abs_p) == OK:
                return img
        return null


# --- A: lama affilata (shuriken, non disco) ---
func _test_blade_sharp() -> void:
        var hz: Node2D = HazardsScript.new()
        add_child(hz)
        for i in 4:
                var tex: Texture2D = hz._blade_frame(i)
                if tex == null:
                        _fail("A: frame lama %d non caricabile" % i)
                        hz.queue_free()
                        return
                if tex.get_width() != 64 or tex.get_height() != 64:
                        _fail("A: frame lama %d %dx%d atteso 64x64" % [
                                        i, tex.get_width(), tex.get_height()])
                        hz.queue_free()
                        return
        hz.queue_free()
        var img := _load_img(HZ_DIR + "blade_sharp_sheet.png")
        if img == null:
                _fail("A: blade_sharp_sheet.png mancante")
                return
        # forma: per OGNI frame angoli trasparenti (non-quadrato pieno),
        # copertura < 40% (il disco pieno del Task 88 era ~60%+), mozzo
        # centrale opaco, frame tutti diversi (rotazione reale)
        var prev_hash: int = -1
        var all_diff: bool = true
        for i in 4:
                var op: int = 0
                var corners_ok: int = 0
                var hub_ok: bool = false
                var h: int = 0
                for y in 64:
                        for x in 64:
                                var p: Color = img.get_pixel(i * 64 + x, y)
                                if p.a > 0.5:
                                        op += 1
                                        h = (h * 31 + int(p.r * 255.0)
                                                        + int(p.g * 255.0) * 7
                                                        + int(p.b * 255.0) * 13) % 999999937
                for cpt in [Vector2i(2, 2), Vector2i(61, 2),
                                Vector2i(2, 61), Vector2i(61, 61)]:
                        if img.get_pixel(i * 64 + cpt.x, cpt.y).a < 0.2:
                                corners_ok += 1
                for dy in range(-2, 3):
                        for dx in range(-2, 3):
                                if img.get_pixel(i * 64 + 32 + dx, 32 + dy).a > 0.5:
                                        hub_ok = true
                if corners_ok < 4:
                        _fail("A: frame %d angoli non trasparenti (%d/4)" % [i, corners_ok])
                        return
                if float(op) / 4096.0 >= 0.40:
                        _fail("A: frame %d copertura %.0f%% (>= 40%%: sembra un disco)" % [
                                        i, float(op) / 4096.0 * 100.0])
                        return
                if not hub_ok:
                        _fail("A: frame %d senza mozzo centrale opaco" % i)
                        return
                if prev_hash >= 0 and h == prev_hash:
                        all_diff = false
                prev_hash = h
        if not all_diff:
                _fail("A: frame identici tra loro (nessuna rotazione)")
                return
        _ok("A: lama affilata 4 frame 64x64 — angoli vuoti, copertura < 40%, mozzo, rotazione")


# --- B: portale infernale (apertura progressiva) ---
func _test_portal_sheet() -> void:
        var seq: Node2D = BDS.new()
        add_child(seq)
        var first_hash: int = -1
        var all_diff: bool = true
        for i in 4:
                var at: AtlasTexture = seq._fx_frame("portal", i)
                if at == null:
                        _fail("B: frame portale %d non caricabile" % i)
                        seq.queue_free()
                        return
                if int(at.region.size.x) != 128 or int(at.region.size.y) != 128:
                        _fail("B: frame portale %d region %s attesa 128x128" % [
                                        i, at.region.size])
                        seq.queue_free()
                        return
                var img := at.atlas.get_image()
                var h: int = 0
                for y in range(0, 128, 2):
                        for x in range(0, 128, 2):
                                var p: Color = img.get_pixel(
                                                int(at.region.position.x) + x, y)
                                h = (h * 31 + int(p.r * 255.0)
                                                + int(p.a * 255.0) * 17) % 999999937
                if first_hash >= 0 and h == first_hash:
                        all_diff = false
                first_hash = h
        # centro del frame piu' aperto = lava incandescente (rosso alto)
        var at3: AtlasTexture = seq._fx_frame("portal", 3)
        var img3 := at3.atlas.get_image()
        var c: Color = img3.get_pixel(int(at3.region.position.x) + 64, 64)
        if c.r < 0.55 or c.a < 0.5:
                _fail("B: centro portale aperto non incandescente (%s)" % [c])
                seq.queue_free()
                return
        seq.queue_free()
        if not all_diff:
                _fail("B: frame portale identici (nessuna apertura progressiva)")
                return
        _ok("B: portale 4 frame 128x128 (autodetect), apertura progressiva, centro lava")


# --- C: anello runico keyato (solo glow) ---
func _test_ring_sheet() -> void:
        var seq: Node2D = BDS.new()
        add_child(seq)
        for i in 4:
                var at: AtlasTexture = seq._fx_frame("ring", i)
                if at == null:
                        _fail("C: frame anello %d non caricabile" % i)
                        seq.queue_free()
                        return
                if int(at.region.size.x) != 128 or int(at.region.size.y) != 128:
                        _fail("C: frame anello %d region %s attesa 128x128" % [
                                        i, at.region.size])
                        seq.queue_free()
                        return
        seq.queue_free()
        var img := _load_img(ENV_DIR + "bossdeath_ring_sheet.png")
        if img == null:
                _fail("C: bossdeath_ring_sheet.png mancante")
                return
        # keying: copertura glow ridotta (8-35%) e luminanza media ALTA
        # (la pietra scura di contorno e' stata rimossa)
        var op: int = 0
        var lum_sum: float = 0.0
        for y in img.get_height():
                for x in img.get_width():
                        var p: Color = img.get_pixel(x, y)
                        if p.a > 0.25:
                                op += 1
                                lum_sum += 0.299 * p.r + 0.587 * p.g + 0.114 * p.b
        var cov: float = float(op) / float(img.get_width() * img.get_height())
        var mean_lum: float = lum_sum / maxi(1, op)
        if cov < 0.08 or cov > 0.35:
                _fail("C: copertura anello %.0f%% (attesa 8-35%%: keying mancante?)" % [
                                cov * 100.0])
                return
        if mean_lum < 0.47:
                _fail("C: luminanza media glow %.2f < 0.47 (pietra scura residua)" % mean_lum)
                return
        _ok("C: anello runico 4 frame 128x128 — keyato (copertura %.0f%%, glow luminoso %.2f)" % [
                        cov * 100.0, mean_lum])


# --- D: voragini ricolorate in palette dungeon ---
func _test_chasm_recolor() -> void:
        for name in ["chasm_crack.png", "chasm_open.png"]:
                var img := _load_img(HZ_DIR + name)
                if img == null:
                        _fail("D: %s mancante" % name)
                        return
                var r_sum: float = 0.0
                var b_sum: float = 0.0
                var op: int = 0
                var semi: int = 0
                var dark_opaque: int = 0
                var light_px: int = 0
                for y in img.get_height():
                        for x in img.get_width():
                                var p: Color = img.get_pixel(x, y)
                                if p.a <= 0.05:
                                        continue
                                op += 1
                                r_sum += p.r
                                b_sum += p.b
                                if p.a > 0.55 and p.a < 0.95:
                                        semi += 1
                                if p.a > 0.95 and 0.299 * p.r + 0.587 * p.g \
                                                + 0.114 * p.b < 0.16:
                                        dark_opaque += 1
                                if 0.299 * p.r + 0.587 * p.g + 0.114 * p.b > 0.2:
                                        light_px += 1
                if r_sum <= b_sum:
                        _fail("D: %s ancora blu (R medio %.3f <= B medio %.3f)" % [
                                        name, r_sum / maxi(1, op), b_sum / maxi(1, op)])
                        return
                if name == "chasm_crack.png":
                        if float(semi) / maxi(1, op) < 0.25:
                                _fail("D: crack senza superficie semitrasparente (%.0f%%)" % [
                                                float(semi) / maxi(1, op) * 100.0])
                                return
                        if dark_opaque < 800:
                                _fail("D: crack senza crepe scure opache (%d px)" % dark_opaque)
                                return
                else:
                        if light_px < 800:
                                _fail("D: open senza bordo pietra leggibile (%d px)" % light_px)
                                return
                        if dark_opaque < 2000:
                                _fail("D: open senza vuoto scuro (%d px)" % dark_opaque)
                                return
        _ok("D: voragini ricolorate — palette calda, crepe scure, superficie blend, bordo leggibile")


# --- E: loader retrocompatibile (sheet 64px non rotti dall'autodetect) ---
func _test_loader_compat() -> void:
        var seq: Node2D = BDS.new()
        add_child(seq)
        for id in ["vortex", "bat", "crow"]:
                var at: AtlasTexture = seq._fx_frame(id, 0)
                if at == null:
                        _fail("E: sheet legacy %s non caricabile" % id)
                        seq.queue_free()
                        return
                if int(at.region.size.x) != 64 or int(at.region.size.y) != 64:
                        _fail("E: sheet legacy %s region %s attesa 64x64" % [
                                        id, at.region.size])
                        seq.queue_free()
                        return
        seq.queue_free()
        _ok("E: sheet 64px legacy (vortex/bat/crow) intatti con autodetect frame")


# --- F: guardie sul sorgente ---
func _test_source_guards() -> void:
        var bds: String = _read(BDS_SRC)
        var hz: String = _read(HZ_SRC)
        var checks: Array = [
                ["draw portale in hell", '_fx_frame("portal"'],
                ["draw anello runico", '_fx_frame("ring"'],
                ["tint anello schiarito", "lightened(0.35)"],
                ["sheet lama affilata preferito", "blade_sharp_sheet.png"],
                ["blink caldo crepa", "0.72 + 0.28 * blink"],
        ]
        for ck in checks:
                var found: bool = (ck[1] as String) in bds or (ck[1] as String) in hz
                if not found:
                        _fail("F: sorgente senza %s (%s)" % [ck[0], ck[1]])
                else:
                        _ok("F: guardia %s" % ck[0])


func _read(path: String) -> String:
        var f := FileAccess.open(path, FileAccess.READ)
        if f == null:
                return ""
        return f.get_as_text()
