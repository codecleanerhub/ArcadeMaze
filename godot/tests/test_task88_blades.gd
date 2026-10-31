## test_task88_blades.gd — TASK 88: test runtime delle LAME-RUOTA
## (richiesta utente: "dal livello 10 in poi ... ruote che sono lame, che
## partono da un muro e arrivano al muro opposto, avanti e indietro in
## loop ... numero progressivo fino a 5 ... tocco = 50% vita, il salto
## protegge ... effetti di scorrimento di ruota").
##
## Check:
##   A — formula count: L9=0, L10=1, L22=2, L34=3, L46=4, L58=5, cap 5
##   B — asset pixel-art: sheet 4 frame 64x64 caricabili (PixelLab)
##   C — generazione su piu' livelli: L10 >= 1 lama, L58 >= 3, mai > 5
##   D — invarianti piazzamento: corridoio muro-muro di celle EMPTY,
##       corsie con gap >= BLADE_MIN_LANE_GAP, nessun hazard statico DENTRO
##       un corridoio con lama (spazio di manovra per saltare)
##   E — movimento: pattinaggio avanti-indietro entro i limiti muro-muro
##       (rimbalzo con inversione di direzione), sprite agganciato
##   F — danno: player grounded sulla traiettoria = -50% energia max;
##       player in salto = NESSUN danno; invulnerabilita' post-colpo
##       blocca il secondo hit
##   G — guardie sorgente (enum BLADE, update, costanti)
extends Node

const MainGameScene = preload("res://scenes/MainGame.tscn")
const MazeScript = preload("res://scripts/core/Maze.gd")
const HazardsScript = preload("res://scripts/entities/MazeHazards.gd")
const C = preload("res://scripts/core/GameConstants.gd")

var fails: int = 0
var main: Node2D = null


func _ready() -> void:
        print("[TEST] TASK 88 — lame-ruota del labirinto")
        _test_formula()
        _test_asset()
        var gen_report: Dictionary = await _test_generation()
        _test_placement_invariants(gen_report)
        await _test_gameplay()
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


# --- A: formula count ---
func _test_formula() -> void:
        var cases: Array = [
                [9, 0], [10, 1], [21, 1], [22, 2], [34, 3],
                [46, 4], [58, 5], [70, 5], [200, 5],
        ]
        for cse in cases:
                var got: int = C.blade_count_for_level(cse[0])
                if got != cse[1]:
                        _fail("A: blade_count_for_level(%d)=%d atteso %d" % [
                                        cse[0], got, cse[1]])
                        return
        _ok("A: formula L10:1 +1/12lv cap 5 (L9:0, L22:2, L58:5, cap oltre)")


# --- B: asset pixel-art ---
func _test_asset() -> void:
        var hz: Node2D = HazardsScript.new()
        add_child(hz)
        for i in 4:
                var tex: Texture2D = hz._blade_frame(i)
                if tex == null:
                        _fail("B: frame %d della lama non caricabile" % i)
                        hz.queue_free()
                        return
                if tex.get_width() != 64 or tex.get_height() != 64:
                        _fail("B: frame %d %dx%d atteso 64x64" % [i,
                                        tex.get_width(), tex.get_height()])
                        hz.queue_free()
                        return
        hz.queue_free()
        _ok("B: sheet lama (4 frame 64x64, PixelLab — sharp dal Task 94) caricato")


# --- C+D: generazione su piu' livelli + invarianti ---
func _test_generation() -> Dictionary:
        var report: Dictionary = {}
        var min_by_level: Dictionary = {10: 1, 58: 3}
        for lvl in [10, 22, 34, 46, 58]:
                var maze: Node2D = MazeScript.new()
                add_child(maze)
                maze.generate(lvl)
                var hz: Node2D = HazardsScript.new()
                add_child(hz)
                hz.generate(lvl, maze, null)
                var blades: Array = []
                var stationary: Array = []
                for h in hz.hazard_list:
                        if h["type"] == HazardsScript.HazardType.BLADE:
                                blades.append(h)
                        else:
                                stationary.append(h["cell"])
                if blades.size() > C.BLADE_MAX_PER_LEVEL:
                        _fail("C: livello %d ha %d lame (max %d)" % [
                                        lvl, blades.size(), C.BLADE_MAX_PER_LEVEL])
                if min_by_level.has(lvl) and blades.size() < min_by_level[lvl]:
                        _fail("C: livello %d ha solo %d lame (attese >= %d)" % [
                                        lvl, blades.size(), min_by_level[lvl]])
                report[lvl] = {"maze": maze, "hz": hz, "blades": blades,
                                "stationary": stationary}
                print("[TEST] livello %d: %d lame, %d hazard statici" % [
                                lvl, blades.size(), stationary.size()])
        if fails == 0:
                _ok("C: generazione L10->L58 (1..5 lame, cap rispettato)")
        return report


func _test_placement_invariants(report: Dictionary) -> void:
        var inv_fails: int = 0
        for lvl in report.keys():
                var rep: Dictionary = report[lvl]
                var maze: Node2D = rep["maze"]
                var hz: Node2D = rep["hz"]
                var stationary: Array = rep["stationary"]
                var lanes_h: Array[int] = []
                var lanes_v: Array[int] = []
                for h in rep["blades"]:
                        var axis: String = h["axis"]
                        var lane: int = h["lane"]
                        var c0: int = h["c0"]
                        var c1: int = h["c1"]
                        if axis == "h":
                                lanes_h.append(lane)
                        else:
                                lanes_v.append(lane)
                        # corridoio: celle EMPTY, muri alle estremita'
                        var run_cells: Array = []
                        var clean: bool = true
                        for i in range(c0, c1 + 1):
                                var cc: int = i if axis == "h" else lane
                                var rr: int = lane if axis == "h" else i
                                run_cells.append(Vector2i(cc, rr))
                                if maze.get_cell_type(cc, rr) != C.CellType.EMPTY:
                                        clean = false
                        if axis == "h":
                                if not (maze.is_wall(c0 - 1, lane) and maze.is_wall(c1 + 1, lane)):
                                        clean = false
                        else:
                                if not (maze.is_wall(lane, c0 - 1) and maze.is_wall(lane, c1 + 1)):
                                        clean = false
                        if not clean:
                                inv_fails += 1
                                print("[TEST] livello %d: corridoio lama non muro-muro" % lvl)
                        # nessun hazard statico DENTRO il corridoio (spazio per saltare)
                        for s in stationary:
                                if run_cells.has(s):
                                        inv_fails += 1
                                        print("[TEST] livello %d: hazard statico %s dentro il corridoio lama" % [
                                                        lvl, s])
                # gap corsie >= 2 per asse
                for lanes in [lanes_h, lanes_v]:
                        for i in lanes.size():
                                for j in range(i + 1, lanes.size()):
                                        if absi(lanes[i] - lanes[j]) < C.BLADE_MIN_LANE_GAP:
                                                inv_fails += 1
                                                print("[TEST] livello %d: corsie lame troppo vicine (%d,%d)" % [
                                                                lvl, lanes[i], lanes[j]])
                hz.queue_free()
                maze.queue_free()
        if inv_fails > 0:
                _fail("D: %d violazioni di piazzamento" % inv_fails)
        else:
                _ok("D: corridoi muro-muro EMPTY, gap corsie >= 2, hazard statici fuori dai corridoi")


# --- E+F: movimento + danno (MainGame reale, livello 10) ---
func _test_gameplay() -> void:
        GameManager.reset_run()
        GameManager.current_level = 10
        GameManager.game_mode = C.GameMode.STORY
        main = MainGameScene.instantiate()
        get_tree().root.add_child.call_deferred(main)
        for i in 30:
                await get_tree().physics_frame
        var hz: Node2D = main.hazards
        var blades: Array = []
        for h in hz.hazard_list:
                if h["type"] == HazardsScript.HazardType.BLADE:
                        blades.append(h)
        if blades.is_empty():
                _fail("E: nessuna lama generata nel MainGame livello 10")
                main.queue_free()
                return
        var b: Dictionary = blades[0]
        var p = main.player
        p.position = Vector2(64.0, 64.0)  # lontano dalle lame (spawn)

        # --- E: movimento + rimbalzo ---
        var start_pos: Vector2 = b["pos"]
        var moved: bool = false
        var bounced: bool = false
        var last_dir: float = b["dir"]
        for i in 400:
                hz.update_hazards(16.0, main.maze)
                var pos: Vector2 = b["pos"]
                if pos.distance_to(start_pos) > 8.0:
                        moved = true
                if b["dir"] != last_dir:
                        bounced = true
                        last_dir = b["dir"]
                # dentro i limiti muro-muro
                var along: float = pos.x if b["axis"] == "h" else pos.y
                if along < b["lo"] - 1.0 or along > b["hi"] + 1.0:
                        _fail("E: lama fuori dai limiti (%.0f non in [%.0f, %.0f])" % [
                                        along, b["lo"], b["hi"]])
                        main.queue_free()
                        return
                # sprite agganciato
                if (b["sprite"] as Sprite2D).position != pos:
                        _fail("E: sprite lama non agganciato alla posizione")
                        main.queue_free()
                        return
        if not moved:
                _fail("E: la lama non si muove")
        elif not bounced:
                _fail("E: la lama non rimbalza mai (400 frame ~6.4s)")
        else:
                _ok("E: pattinaggio muro-muro con rimbalzo (avanti/indietro in loop)")

        # --- F: danno 50% / salto protegge / invulnerabilita' ---
        p.position = b["pos"] + Vector2(0.0, 0.0)
        p.jump_timer = 0
        p.damage_timer = 0
        p.spawn_guard_ms = 0
        p.energy = p.max_energy
        var e0: int = p.energy
        hz.update_hazards(16.0, main.maze)
        var dmg: int = maxi(1, int(float(p.max_energy) * C.BLADE_DAMAGE_PCT))
        if p.energy != e0 - dmg:
                _fail("F: danno lama %d atteso -%d (energia %d -> %d)" % [
                                e0 - p.energy, dmg, e0, p.energy])
        elif p.lives != C.STARTING_LIVES:
                _fail("F: la lama non deve uccidere (50%% non letale)")
        else:
                _ok("F1: tocco lama grounded = -%d/%d energia (50%%), non letale" % [
                                dmg, e0])
        # invulnerabilita' post-colpo: secondo update nessun danno extra
        var e1: int = p.energy
        hz.update_hazards(16.0, main.maze)
        if p.energy != e1:
                _fail("F2: secondo colpo durante l'invulnerabilita' post-colpo")
        else:
                _ok("F2: invulnerabilita' post-colpo blocca il secondo hit")
        # il salto scavalca la lama
        p.damage_timer = 0
        p.energy = p.max_energy
        p.jump_timer = 20  # in salto
        var e2: int = p.energy
        hz.update_hazards(16.0, main.maze)
        if p.energy != e2:
                _fail("F3: la lama ha colpito il player in salto")
        else:
                _ok("F3: il salto scavalca la lama (nessun danno)")
        p.jump_timer = 0
        main.queue_free()


# --- G: guardie sorgente ---
func _test_source_guards() -> void:
        var hsrc := _read("res://scripts/entities/MazeHazards.gd")
        var checks: Array = [
                ["enum BLADE", "HazardType.BLADE"],
                ["update della lama", "_update_blade(h, delta_ms, players)"],
                ["spawn della lama", "_spawn_blade(run)"],
                ["raccolta corridoi", "_collect_blade_runs(maze)"],
        ]
        for ck in checks:
                if hsrc.find(ck[1]) < 0:
                        _fail("G: MazeHazards senza %s" % ck[0])
        var csrc := _read("res://scripts/core/GameConstants.gd")
        if csrc.find("static func blade_count_for_level") < 0:
                _fail("G: GameConstants senza blade_count_for_level")
        if fails == 0:
                _ok("G: guardie sorgente MazeHazards + GameConstants presenti")


func _read(path: String) -> String:
        var f := FileAccess.open(path, FileAccess.READ)
        if f == null:
                return ""
        var txt := f.get_as_text()
        f.close()
        return txt
