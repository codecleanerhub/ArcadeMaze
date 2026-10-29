## test_task90_budget.gd — TASK 90: test del BUDGET DEI MALUS
## (richiesta utente: "fai un'analisi di distribuzione dei malus in
## funzione del numero di livelli e della difficoltà crescente... i tipi
## devono avere priorità sul numero, poi al crescere ancora aumenta anche
## la quantità per lo stesso tipo... troppi elementi potrebbero rallentare
## il gioco").
##
## Check:
##   A — cap globale: per OGNI livello 1..90 la somma dei counts del budget
##       resta <= MALUS_BUDGET_CAP (15)
##   B — diversita' monotona: un tipo attivo a L resta attivo (>= 1) a L+1
##   C — priorita' tipi > numero: il numero di TIPI attivi non-decresce col
##       livello; i nuovi tipi entrano scaglionati (L4 hazard base, L10
##       lame, L12 lance)
##   D — integrazione: generate() a L58 piazza <= 15 malus totali
##   E — tabella di analisi stampata (L1..L68 campionata) per documentazione
##   F — guardie sorgente (planner usato da generate)
extends Node

const MazeScript = preload("res://scripts/core/Maze.gd")
const HazardsScript = preload("res://scripts/entities/MazeHazards.gd")
const C = preload("res://scripts/core/GameConstants.gd")

var fails: int = 0


func _ready() -> void:
        print("[TEST] TASK 90 — budget di distribuzione dei malus")
        _test_cap()
        _test_monotonic()
        _test_types_priority()
        _test_integration()
        _print_analysis()
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


func _budget_total(level: int) -> int:
        var b: Dictionary = C.malus_budget_for_level(level)
        var t: int = 0
        for k in b:
                t += int(b[k])
        return t


# --- A: cap globale ---
func _test_cap() -> void:
        var worst: int = 0
        for lvl in range(1, 91):
                var t: int = _budget_total(lvl)
                worst = maxi(worst, t)
                if t > C.MALUS_BUDGET_CAP:
                        _fail("A: livello %d budget totale %d > cap %d" % [
                                        lvl, t, C.MALUS_BUDGET_CAP])
                        return
        _ok("A: cap globale rispettato su L1-L90 (picco %d <= %d)" % [
                        worst, C.MALUS_BUDGET_CAP])


# --- B: diversita' monotona ---
func _test_monotonic() -> void:
        for lvl in range(1, 90):
                var b0: Dictionary = C.malus_budget_for_level(lvl)
                var b1: Dictionary = C.malus_budget_for_level(lvl + 1)
                for k in b0:
                        if int(b0[k]) >= 1 and int(b1[k]) < 1:
                                _fail("B: tipo '%s' attivo a L%d ma non a L%d" % [
                                                k, lvl, lvl + 1])
                                return
        _ok("B: un tipo attivo non sparisce mai salendo di livello")


# --- C: priorita' tipi > numero ---
func _test_types_priority() -> void:
        var types_by_level: Array = []
        for lvl in range(1, 91):
                var b: Dictionary = C.malus_budget_for_level(lvl)
                var n: int = 0
                for k in b:
                        if int(b[k]) >= 1:
                                n += 1
                types_by_level.append(n)
        # non-decrescente
        for i in range(1, types_by_level.size()):
                if types_by_level[i] < types_by_level[i - 1]:
                        _fail("C: tipi attivi calano da L%d (%d) a L%d (%d)" % [
                                        i, types_by_level[i - 1], i + 1, types_by_level[i]])
                        return
        # entrate scaglionate attese
        var exp: Dictionary = {4: 5, 10: 6, 12: 7}  # L4: 5 tipi (qs+trap+chasm+wall+barrel), L10 +lame, L12 +lance
        for lvl in exp:
                if types_by_level[lvl - 1] != exp[lvl]:
                        _fail("C: a L%d tipi attivi %d attesi %d" % [
                                        lvl, types_by_level[lvl - 1], exp[lvl]])
                        return
        # le LAME crescono fino al loro cap 5 e le LANCE fino a 4 anche col
        # budget attivo (priorita' dei tipi nuovi sui base)
        var b58: Dictionary = C.malus_budget_for_level(58)
        if int(b58["blade"]) != 5 or int(b58["spear"]) != 4:
                _fail("C: a L58 lame=%d lance=%d (attese 5 e 4: i tipi nuovi crescono fino al cap)" % [
                                b58["blade"], b58["spear"]])
                return
        _ok("C: tipi non-decrescenti; entrate L4:5, L10:6 (lame), L12:7 (lance); a L58 lame=5 lance=4")


# --- D: integrazione generate ---
func _test_integration() -> void:
        for lvl in [34, 58, 68, 80]:
                var maze: Node2D = MazeScript.new()
                add_child(maze)
                maze.generate(lvl)
                var hz: Node2D = HazardsScript.new()
                add_child(hz)
                hz.generate(lvl, maze, null)
                var placed: int = hz.hazard_list.size()
                if placed > C.MALUS_BUDGET_CAP:
                        _fail("D: L%d piazza %d malus > cap %d" % [
                                        lvl, placed, C.MALUS_BUDGET_CAP])
                hz.queue_free()
                maze.queue_free()
        if fails == 0:
                _ok("D: generate() a L34/L58/L68/L80 piazza <= %d malus" % C.MALUS_BUDGET_CAP)


# --- E: tabella di analisi (documentazione) ---
func _print_analysis() -> void:
        print("[TEST] --- ANALISI DISTRIBUZIONE MALUS (budget per livello) ---")
        print("[TEST] %5s %4s %4s %4s %4s %4s %4s %4s %4s | %s" % [
                        "liv", "qs", "trap", "chsm", "wall", "barl", "lame", "lanc", "TOT", "note"])
        for lvl in [1, 3, 4, 6, 10, 12, 22, 34, 46, 58, 68, 80]:
                var b: Dictionary = C.malus_budget_for_level(lvl)
                var t: int = _budget_total(lvl)
                var note: String = ""
                if lvl == 4:
                        note = "grace hazard base (sabbie/ganasce/voragini/muri+barili)"
                elif lvl == 6:
                        note = "+ terremoto (evento)"
                elif lvl == 10:
                        note = "+ LAME-RUOTA (nuovo tipo)"
                elif lvl == 12:
                        note = "+ LANCE (nuovo tipo)"
                elif t == C.MALUS_BUDGET_CAP:
                        note = "cap attivo: si cresce dai tipi/timing"
                print("[TEST] %5d %4d %4d %4d %4d %4d %4d %4d %4d | %s" % [
                                lvl, b["quicksand"], b["trap"], b["chasm"],
                                b["rock_wall"], b["barrel"], b["blade"],
                                b["spear"], t, note])
        print("[TEST] -------------------------------------------------------")


# --- F: guardie sorgente ---
func _test_source_guards() -> void:
        var csrc := _read("res://scripts/core/GameConstants.gd")
        if csrc.find("static func malus_budget_for_level") < 0:
                _fail("F: GameConstants senza malus_budget_for_level")
        var hsrc := _read("res://scripts/entities/MazeHazards.gd")
        if hsrc.find("C.malus_budget_for_level(level)") < 0:
                _fail("F: generate() non usa il budget planner")
        if fails == 0:
                _ok("F: planner in GameConstants + uso in MazeHazards.generate")


func _read(path: String) -> String:
        var f := FileAccess.open(path, FileAccess.READ)
        if f == null:
                return ""
        var txt := f.get_as_text()
        f.close()
        return txt
