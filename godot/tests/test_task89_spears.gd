## test_task89_spears.gd — TASK 89: test runtime dei BLOCCHI DI LANCE
## (richiesta utente: "lance appuntite che escono dal pavimento: si vedono
## appena le punte e, ad un certo momento casuale iniziano a vibrare e poi
## si alzano per infilzare il player... colpito = 50% vita, NON saltabili,
## attendere che ritornino giu'... dopo 5 secondi vibrano e ritornano giu'...
## massimo 4 per livello... distanziate dalle lame").
##
## Check:
##   A — formula count: L11=0, L12=1, L24=2, L36=3, L48=4, cap 4
##   B — asset pixel-art: sheet 4 varianti 64x64 caricabili
##   C — generazione: L24 = 2 lance; celle NON sulle corsie delle lame
##       (riga non in blade_rows E colonna non in blade_cols); gap >= 2 da
##       ogni altro hazard; cella pavimento valida
##   D — macchina a stati completa: HIDDEN (punte, scale ~0.18) -> WARN
##       (vibrazione) -> RISING (scale 0.24->1.0) -> UP esattamente 5s ->
##       RETRACT_WARN -> RETRACTING -> HIDDEN con nuovo delay casuale
##   E — danno: player sulla cella con lance FUORI = -50% energia max ANCHE
##       se sta saltando (unblockable); player fuori cella = incolume;
##       invulnerabilita' post-colpo blocca il secondo hit
##   F — HIDDEN: nessun danno con le punte appena visibili
##   G — guardie sorgente
extends Node

const MainGameScene = preload("res://scenes/MainGame.tscn")
const MazeScript = preload("res://scripts/core/Maze.gd")
const HazardsScript = preload("res://scripts/entities/MazeHazards.gd")
const C = preload("res://scripts/core/GameConstants.gd")

var fails: int = 0
var main: Node2D = null


func _ready() -> void:
        print("[TEST] TASK 89 — blocchi di lance")
        _test_formula()
        _test_asset()
        await _test_generation_and_states()
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


# --- A: formula ---
func _test_formula() -> void:
        var cases: Array = [
                [11, 0], [12, 1], [23, 1], [24, 2], [36, 3],
                [48, 4], [70, 4], [200, 4],
        ]
        for cse in cases:
                var got: int = C.spear_count_for_level(cse[0])
                if got != cse[1]:
                        _fail("A: spear_count_for_level(%d)=%d atteso %d" % [
                                        cse[0], got, cse[1]])
                        return
        _ok("A: formula L12:1 +1/12lv cap 4 (L11:0, L24:2, L48:4)")


# --- B: asset ---
func _test_asset() -> void:
        var hz: Node2D = HazardsScript.new()
        add_child(hz)
        for i in 4:
                var tex: Texture2D = hz._spear_frame(i)
                if tex == null:
                        _fail("B: variante lance %d non caricabile" % i)
                        hz.queue_free()
                        return
                if tex.get_width() != 64 or tex.get_height() != 64:
                        _fail("B: variante %d %dx%d attesa 64x64" % [i,
                                        tex.get_width(), tex.get_height()])
                        hz.queue_free()
                        return
        hz.queue_free()
        _ok("B: sheet spear_tips (4 varianti 64x64, PixelLab) caricato")


# --- C+D+E+F: generazione + stati + danno (maze standalone + player reale) ---
func _test_generation_and_states() -> void:
        # maze standalone livello 24 (2 lame + 2 lance)
        var maze: Node2D = MazeScript.new()
        add_child(maze)
        maze.generate(24)
        var hz: Node2D = HazardsScript.new()
        add_child(hz)
        hz.generate(24, maze, null)
        var spears: Array = []
        var others: Array = []
        for h in hz.hazard_list:
                if h["type"] == HazardsScript.HazardType.SPEAR:
                        spears.append(h)
                else:
                        others.append(h["cell"])
        # C: count e posizioni
        if spears.size() != 2:
                _fail("C: livello 24 ha %d blocchi di lance (attesi 2)" % spears.size())
        for h in spears:
                var cell: Vector2i = h["cell"]
                if hz.blade_rows.has(cell.y) or hz.blade_cols.has(cell.x):
                        _fail("C: lance %s su corsia di lama (rows=%s cols=%s)" % [
                                        cell, hz.blade_rows, hz.blade_cols])
                if maze.get_cell_type(cell.x, cell.y) != C.CellType.EMPTY:
                        _fail("C: lance %s non su cella pavimento" % cell)
                for o in others:
                        if absi(cell.x - o.x) + absi(cell.y - o.y) < C.HAZARD_MIN_GAP:
                                _fail("C: lance %s troppo vicina a hazard %s" % [cell, o])
        if fails == 0:
                _ok("C: 2 lance a L24, fuori dalle corsie delle lame, gap >= 2, su pavimento")

        # D: macchina a stati completa su una lancia (players vuoti)
        var sp: Dictionary = spears[0]
        var states_seen: Array = [0]  # parte da HIDDEN (impostato qui sotto)
        var scale_at_up: float = 0.0
        var up_frames: int = 0
        var hidden_after: float = -1.0
        # accorcia l'attesa iniziale per il test
        sp["timer_ms"] = 10.0
        var total_ms: float = 0.0
        while total_ms < 9000.0 and states_seen.size() < 6 or (total_ms < 9000.0
                        and not (states_seen.has(5) and hidden_after >= 0.0)):
                hz.update_hazards(16.0, maze)
                total_ms += 16.0
                var st: int = sp["state"]
                if states_seen.is_empty() or states_seen[states_seen.size() - 1] != st:
                        states_seen.append(st)
                if st == HazardsScript.SpearState.UP:
                        up_frames += 1
                        scale_at_up = (sp["sprite"] as Sprite2D).scale.y
                if st == HazardsScript.SpearState.HIDDEN and states_seen.has(5):
                        hidden_after = float(sp["timer_ms"])
                        break
                if total_ms > 9000.0:
                        break
        var expect: Array = [0, 1, 2, 3, 4, 5]  # HIDDEN..RETRACTING
        if states_seen.slice(0, 6) != expect:
                _fail("D: stati visti %s attesi %s" % [
                                states_seen.slice(0, 6), expect])
        elif absf(scale_at_up - 1.0) > 0.01:
                _fail("D: scale a UP = %.2f attesa 1.0" % scale_at_up)
        elif absf(float(up_frames) * 16.0 - float(C.SPEAR_HOLD_MS)) > 80.0:
                _fail("D: tempo UP = %.0fms atteso ~%dms" % [
                                float(up_frames) * 16.0, C.SPEAR_HOLD_MS])
        elif hidden_after < 0.0:
                _fail("D: mai tornata HIDDEN con nuovo delay")
        else:
                _ok("D: ciclo completo HIDDEN->WARN->RISING->UP(%.1fs)->RETRACT->HIDDEN" % [
                                float(up_frames) * 16.0 / 1000.0])

        # E+F: danno con player reale (MainGame L24)
        maze.queue_free()
        hz.queue_free()
        GameManager.reset_run()
        GameManager.current_level = 24
        GameManager.game_mode = C.GameMode.STORY
        main = MainGameScene.instantiate()
        get_tree().root.add_child.call_deferred(main)
        for i in 30:
                await get_tree().physics_frame
        var hz2: Node2D = main.hazards
        var sp2: Dictionary = {}
        for h in hz2.hazard_list:
                if h["type"] == HazardsScript.HazardType.SPEAR:
                        sp2 = h
                        break
        if sp2.is_empty():
                _fail("E: nessuna lancia nel MainGame L24")
                main.queue_free()
                return
        var p = main.player
        var spear_cell: Vector2i = sp2["cell"]
        var cc: Vector2 = sp2["cc"]
        # F: HIDDEN — punte appena visibili, NESSUN danno
        sp2["state"] = HazardsScript.SpearState.HIDDEN
        sp2["timer_ms"] = 5000.0
        p.position = cc
        p.jump_timer = 0
        p.damage_timer = 0
        p.spawn_guard_ms = 0
        p.energy = p.max_energy
        var e0: int = p.energy
        hz2.update_hazards(16.0, main.maze)
        if p.energy != e0:
                _fail("F: danno con lance in HIDDEN (punte)")
        else:
                _ok("F: HIDDEN (punte appena visibili) = nessun danno")
        # E1: UP — danno 50% ANCHE saltando (unblockable)
        sp2["state"] = HazardsScript.SpearState.UP
        sp2["timer_ms"] = 3000.0
        p.damage_timer = 0
        p.energy = p.max_energy
        p.jump_timer = 20  # IN SALTO
        var e1: int = p.energy
        hz2.update_hazards(16.0, main.maze)
        var dmg: int = maxi(1, int(float(p.max_energy) * C.SPEAR_DAMAGE_PCT))
        if p.energy != e1 - dmg:
                _fail("E1: player in salto sulle lance: -%d atteso -%d (%d -> %d)" % [
                                e1 - p.energy, dmg, e1, p.energy])
        else:
                _ok("E1: lance FUORI colpiscono ANCHE in salto (-%d/%d, unblockable)" % [
                                dmg, e1])
        # E2: invulnerabilita' post-colpo
        var e2: int = p.energy
        hz2.update_hazards(16.0, main.maze)
        if p.energy != e2:
                _fail("E2: secondo colpo durante l'invulnerabilita'")
        else:
                _ok("E2: invulnerabilita' post-colpo blocca il secondo hit")
        # E3: player FUORI dalla cella = incolume
        p.damage_timer = 0
        p.energy = p.max_energy
        p.jump_timer = 0
        p.position = cc + Vector2(200.0, 0.0)
        var e3: int = p.energy
        hz2.update_hazards(16.0, main.maze)
        if p.energy != e3:
                _fail("E3: colpito player fuori dalla cella lance")
        else:
                _ok("E3: player fuori dalla cella = incolume")
        main.queue_free()


# --- G: guardie sorgente ---
func _test_source_guards() -> void:
        var hsrc := _read("res://scripts/entities/MazeHazards.gd")
        var checks: Array = [
                ["enum SPEAR", "HazardType.SPEAR"],
                ["stati lance", "enum SpearState { HIDDEN, WARN, RISING, UP, RETRACT_WARN, RETRACTING }"],
                ["update lance", "_update_spear(h, delta_ms, players)"],
                ["spawn lance", "_spawn_spear(spear_cell)"],
                ["esclusione corsie lame", "not blade_rows.has(cell.y) and not blade_cols.has(cell.x)"],
        ]
        for ck in checks:
                if hsrc.find(ck[1]) < 0:
                        _fail("G: MazeHazards senza %s" % ck[0])
        var csrc := _read("res://scripts/core/GameConstants.gd")
        if csrc.find("static func spear_count_for_level") < 0:
                _fail("G: GameConstants senza spear_count_for_level")
        if fails == 0:
                _ok("G: guardie sorgente MazeHazards + GameConstants presenti")


func _read(path: String) -> String:
        var f := FileAccess.open(path, FileAccess.READ)
        if f == null:
                return ""
        var txt := f.get_as_text()
        f.close()
        return txt
