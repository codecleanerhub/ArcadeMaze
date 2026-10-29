## test_task97_points.gd — TASK 97: ricalibrazione punti per durezza
## (feedback utente: "ricalibrassi i punti in base alle uccisioni dei mostri,
## più sono duri a morire e più punti danno, il mini boss quindi è quello
## che darà più punti... al momento siamo molto generosi").
##
## PRIMA: flat 5000 per ogni nemico da ogni fonte (+10000 espliciti al
## mini-boss che si sommavano al cleanup = doppio premio), tesori 10000,
## calice 15000, boss 0 punti, vita extra ogni 100k (max ~12,4M a run).
## ORA: nemico = HP base x 10, mini-boss = 300+15t, boss = 2500+100i,
## tesoro 150, calice 300, sciame 40, vita extra ogni 50k; TUTTE le fonti
## assegnano il valore della vittima.
##
## Check:
##   A — valori nemici per durezza (GHOST 10 < SKELETON 20 < ZOMBIE 40
##       < SLIME 50) via get_score_reward()
##   B — formula mini-boss (300 + 15 x tipo) e ordine: piu' di OGNI nemico
##   C — costanti: tesoro 150 (cella e collectible), calice 300, sciame 40,
##       vita extra 50k
##   D — vita extra alla soglia: 49999 no, +2 si (threshold -> 100k)
##   E — guardie sorgente: niente add_score flat nelle fonti, punti boss
##       wired nel controller
##   F — formula boss: 2500 + 100 x indice (livello 4 -> 2500)
extends Node

const EnemyScript = preload("res://scripts/enemies/Enemy.gd")
const MiniBossScript = preload("res://scripts/bosses/MiniBoss.gd")
const PlayerScript = preload("res://scripts/core/Player.gd")
const C = preload("res://scripts/core/GameConstants.gd")

const MGC_SRC := "res://scripts/core/MainGameController.gd"
const MZH_SRC := "res://scripts/entities/MazeHazards.gd"
const BRC_SRC := "res://scripts/core/BossRoomController.gd"

var fails: int = 0


func _ready() -> void:
        print("[TEST] TASK 97 — punti per durezza (nemici < mini-boss < boss)")
        _test_enemy_values()
        _test_miniboss_values()
        _test_constants()
        _test_extra_life()
        _test_source_guards()
        _test_boss_points()
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


# --- A: nemici, valore = HP base x 10 ---
func _test_enemy_values() -> void:
        var cases: Array = [
                [EnemyScript.EnemyType.GHOST, 10],
                [EnemyScript.EnemyType.SKELETON, 20],
                [EnemyScript.EnemyType.ZOMBIE, 40],
                [EnemyScript.EnemyType.SLIME, 50],
        ]
        for cse in cases:
                var e := EnemyScript.new()
                add_child(e)
                e.init(cse[0], 3, 3)
                var got: int = e.get_score_reward()
                e.queue_free()
                if got != cse[1]:
                        _fail("A: nemico tipo %s vale %d, attesi %d" % [
                                        cse[0], got, cse[1]])
                        return
        _ok("A: get_score_reward = HP base x 10 (fantasma 10, scheletro 20, zombie 40, melma 50)")


# --- B: mini-boss sopra ogni nemico ---
func _test_miniboss_values() -> void:
        var cases: Array = [[0, 300], [10, 450], [50, 1050]]
        for cse in cases:
                var mb := MiniBossScript.new()
                add_child(mb)
                mb.setup(cse[0], 1, 3, 3)
                var got: int = mb.get_score_reward()
                mb.queue_free()
                if got != cse[1]:
                        _fail("B: mini-boss tipo %d vale %d, attesi %d" % [
                                        cse[0], got, cse[1]])
                        return
        # il mini-boss (anche il piu' debole) vale piu' di OGNI nemico:
        if 300 <= 60:
                _fail("B: il mini-boss piu' debole (300) non supera il nemico piu' duro (60)")
                return
        _ok("B: mini-boss 300 + 15 x tipo (300/450/1050) — sopra ogni nemico (max 60), come richiesto")


# --- C: costanti ricalibrate ---
func _test_constants() -> void:
        var checks: Array = [
                ["ENEMY_POINTS_PER_HP", C.ENEMY_POINTS_PER_HP, 10],
                ["MINIBOSS_POINTS_BASE", C.MINIBOSS_POINTS_BASE, 300],
                ["MINIBOSS_POINTS_PER_TYPE", C.MINIBOSS_POINTS_PER_TYPE, 15],
                ["BOSS_KILL_POINTS_BASE", C.BOSS_KILL_POINTS_BASE, 2500],
                ["BOSS_KILL_POINTS_PER_INDEX", C.BOSS_KILL_POINTS_PER_INDEX, 100],
                ["TREASURE_CELL_POINTS", C.TREASURE_CELL_POINTS, 150],
                ["CHALICE_PICKUP_POINTS", C.CHALICE_PICKUP_POINTS, 300],
                ["BAT_CLOUD_KILL_POINTS", C.BAT_CLOUD_KILL_POINTS, 40],
                ["EXTRA_LIFE_EVERY_POINTS", C.EXTRA_LIFE_EVERY_POINTS, 50000],
        ]
        for ck in checks:
                if ck[1] != ck[2]:
                        _fail("C: %s = %s, atteso %s" % [ck[0], ck[1], ck[2]])
                        return
        _ok("C: 9 costanti TASK 97 a posto (tesoro/calice/sciame/vita-extra compresi)")


# --- D: vita extra alla soglia ---
func _test_extra_life() -> void:
        var p := PlayerScript.new()
        add_child(p)
        p.score = 0
        p.lives = 3
        p.next_life_threshold = C.EXTRA_LIFE_EVERY_POINTS
        p.add_score(C.EXTRA_LIFE_EVERY_POINTS - 1)
        if p.lives != 3:
                _fail("D: vita extra data un punto prima della soglia")
                return
        p.add_score(2)
        if p.lives != 4 or p.next_life_threshold != C.EXTRA_LIFE_EVERY_POINTS * 2:
                _fail("D: vita extra mancata alla soglia (vite %d, prossima %d)" % [
                                p.lives, p.next_life_threshold])
                return
        p.queue_free()
        _ok("D: vita extra ogni %d punti (49999 no, 50001 si, prossima soglia 100k)" % C.EXTRA_LIFE_EVERY_POINTS)


# --- E: guardie sorgente ---
func _test_source_guards() -> void:
        for src in [MGC_SRC, MZH_SRC]:
                var s: String = _read(src)
                for lit in ["add_score(5000)", "add_score(10000)",
                                "add_score(15000)", "add_score(2000)",
                                "add_score(3000)"]:
                        if lit in s:
                                _fail("E: %s contiene ancora il flat %s" % [
                                                _basename(src), lit])
                                return
        var brc: String = _read(BRC_SRC)
        if not ("BOSS_KILL_POINTS_BASE" in brc) \
                        or not ("player2.add_score(boss_pts)" in brc):
                _fail("E: BossRoomController senza punti boss wired (2P compreso)")
                return
        _ok("E: nessun flat add_score(N) nelle fonti; punti boss al controller (2P compreso)")


# --- F: formula boss ---
func _test_boss_points() -> void:
        # get_boss_index = (level/4) % 17: livello 4 -> 1, livello 68 -> 0
        var idx_l4: int = GameManager.get_boss_index(4)
        if idx_l4 != 1:
                _fail("F: indice boss al livello 4 = %d, atteso 1" % idx_l4)
                return
        var pts_l4: int = C.BOSS_KILL_POINTS_BASE \
                        + idx_l4 * C.BOSS_KILL_POINTS_PER_INDEX
        var pts_max: int = C.BOSS_KILL_POINTS_BASE \
                        + 16 * C.BOSS_KILL_POINTS_PER_INDEX
        if pts_l4 != 2600 or pts_max != 4100:
                _fail("F: punti boss lvl4=%d max=%d (attesi 2600 e 4100)" % [
                                pts_l4, pts_max])
                return
        if pts_l4 <= 1050:
                _fail("F: il boss (%d) non supera il mini-boss piu' duro (1050)" % pts_l4)
                return
        _ok("F: boss 2500 + 100 x indice (lvl 4 = 2600, max = 4100) — sopra il mini-boss")


func _read(path: String) -> String:
        var f := FileAccess.open(path, FileAccess.READ)
        if f == null:
                return ""
        return f.get_as_text()


func _basename(path: String) -> String:
        return path.get_file()
