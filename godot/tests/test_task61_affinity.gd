## test_task61_affinity.gd — TASK 61: suite del sistema AFFINITA' ARMI.
##
## Check:
##   A. make_random_weapon per archetipo: umani -> armi da fuoco;
##      non-umani -> solo pool elementale; misto -> entrambi (flag ground).
##   B. Penalita' -50% fuori affinita' (weapon_damage_for con char_type).
##   C. Spawn celle: maze.affinity_char_types=[DRAGO] -> tutte le armi
##      a terra appartengono al pool del Drago.
##   D. Colpo di grazia elementale: fireball_red -> start_burning;
##      flame_blue -> freeze_kill (statua).
##   E. collect_weapon: l'elementale a terra NON ruba la reliquia bonus;
##      si scambia con un'altra elementale ground e con le armi base.
extends Node

const C = preload("res://scripts/core/GameConstants.gd")
const MainGameScene = preload("res://scenes/MainGame.tscn")

var fails: int = 0
var main: Node2D = null


func ok(cond: bool, label: String) -> void:
        if cond:
                print("[T61] OK: ", label)
        else:
                fails += 1
                print("[T61] FAIL: ", label)


func _ready() -> void:
        seed(20261026)
        _test_pools()
        _test_penalty()
        _test_maze_spawn()
        _boot_main()
        # i check D/E aspettano il MainGame pronto
        set_process(true)


var _stage: int = 0


func _process(_delta: float) -> void:
        if _stage == 0:
                if main != null and main.is_node_ready():
                        _test_killing_blow()
                        _test_collect_guard()
                        print("[T61] --- RISULTATO: ",
                                        "TUTTI PASS" if fails == 0 else str(fails) + " FAIL",
                                        " ---")
                        get_tree().quit(1 if fails > 0 else 0)
                        _stage = 1


# ---------------- A. pool per archetipo ----------------
func _test_pools() -> void:
        # legacy: nessun char -> armi da fuoco
        for i in 20:
                var w0: Dictionary = C.make_random_weapon([])
                ok(int(w0["type"]) <= 3, "legacy: arma da fuoco senza char")
                break
        # umano: armi da fuoco
        var human_fire: bool = true
        for i in 40:
                var wh: Dictionary = C.make_random_weapon([C.CharacterType.HERO_M])
                if C.is_relic_weapon(int(wh["type"])):
                        human_fire = false
        ok(human_fire, "umano: 40/40 armi da fuoco")
        # drago: solo il suo pool
        var dragon_ok: bool = true
        var dragon_ids: Array = []
        for i in 60:
                var wd: Dictionary = C.make_random_weapon([C.CharacterType.DRAGON])
                var def: Dictionary = C.get_relic_def(int(wd["type"]))
                var rid: String = str(def.get("id", ""))
                dragon_ids.append(rid)
                if not C.AFFINITY_POOLS[C.CharacterType.DRAGON].has(rid):
                        dragon_ok = false
        ok(dragon_ok, "drago: 60/60 armi nel pool proprio")
        ok(dragon_ids.has("flame_ember") or dragon_ids.has("fireball_red") \
                        or dragon_ids.has("flame_blue") or dragon_ids.has("fire_maelstrom"),
                        "drago: campionamento vario")
        # mago: pool misto storiche+elementali
        var mage_ok: bool = true
        for i in 60:
                var wm: Dictionary = C.make_random_weapon([C.CharacterType.MAGE])
                var defm: Dictionary = C.get_relic_def(int(wm["type"]))
                if not C.AFFINITY_POOLS[C.CharacterType.MAGE].has(str(defm.get("id", ""))):
                        mage_ok = false
        ok(mage_ok, "mago: 60/60 nel pool (storiche+elementali)")
        # flag ground sulle elementali
        var wgr: Dictionary = C.make_random_weapon([C.CharacterType.DRAGON])
        ok(bool(wgr.get("ground", false)), "elementale: flag ground=true")
        # misto: entrambe le famiglie nel campione
        var saw_fire: bool = false
        var saw_elem: bool = false
        for i in 80:
                var wx: Dictionary = C.make_random_weapon(
                                [C.CharacterType.DRAGON, C.CharacterType.HERO_M])
                if C.is_relic_weapon(int(wx["type"])):
                        saw_elem = true
                else:
                        saw_fire = true
        ok(saw_fire and saw_elem, "misto drago+umano: entrambi i tipi spawnano")


# ---------------- B. penalita' -50% ----------------
func _test_penalty() -> void:
        var hp: int = 40
        # HERO con la sua pistola: 4 hits -> dmg 10
        var d_pistol_own: int = C.weapon_damage_for(C.WeaponType.PISTOL, hp, false,
                        C.CharacterType.HERO_M)
        # DRAGO con la pistola (fuori affinita'): hits 8 -> dmg 5
        var d_pistol_wrong: int = C.weapon_damage_for(C.WeaponType.PISTOL, hp, false,
                        C.CharacterType.DRAGON)
        ok(d_pistol_own == 10, "penalita': HERO pistola dmg 10 (4 hits)")
        ok(d_pistol_wrong == 5, "penalita': DRAGO pistola dmg 5 (8 hits, -50%)")
        # DRAGO con fireball_red: 3 hits -> 14
        var d_fb_own: int = C.weapon_damage_for(C.RelicType.FIREBALL_RED, hp, false,
                        C.CharacterType.DRAGON)
        # HERO con fireball_red (fuori affinita'): 6 hits -> 7
        var d_fb_wrong: int = C.weapon_damage_for(C.RelicType.FIREBALL_RED, hp, false,
                        C.CharacterType.HERO_M)
        ok(d_fb_own == 14, "penalita': DRAGO fireball dmg 14 (3 hits)")
        ok(d_fb_wrong == 7, "penalita': HERO fireball dmg 7 (6 hits, -50%)")
        # char_type -1 (bonus screen / boss room): nessuna penalita'
        var d_fb_free: int = C.weapon_damage_for(C.RelicType.FIREBALL_RED, hp, false, -1)
        ok(d_fb_free == 14, "penalita': char -1 (reliquia bonus) resta libera")


# ---------------- C. spawn celle del labirinto ----------------
func _test_maze_spawn() -> void:
        var maze = load("res://scripts/core/Maze.gd").new()
        maze.affinity_char_types = [C.CharacterType.DRAGON]
        maze.generate(3)
        var weapons: Array = []
        var wrong: int = 0
        for cll in range(C.MAZE_COLS):
                for rww in range(C.MAZE_ROWS):
                        if maze.get_cell_type(cll, rww) == C.CellType.WEAPON:
                                var w: Dictionary = maze.get_cell_weapon(cll, rww)
                                weapons.append(int(w["type"]))
                                if not C.AFFINITY_POOLS[C.CharacterType.DRAGON].has(
                                                str(C.get_relic_def(int(w["type"])).get("id", ""))):
                                        wrong += 1
        ok(weapons.size() > 0, "spawn: armi presenti nel labirinto (%d)" % weapons.size())
        ok(wrong == 0, "spawn: 100% armi del pool Drago")


# ---------------- D. colpo di grazia elementale ----------------
func _boot_main() -> void:
        LoadingScreen.skip_boot_hold()
        GameManager.num_players = 1
        GameManager.reset_run()
        main = MainGameScene.instantiate()
        add_child.call_deferred(main)


func _test_killing_blow() -> void:
        # ripulisci i nemici d'esempio e crea una vittima deterministica
        for e in main.spawner.enemies.duplicate():
                if is_instance_valid(e):
                        e.queue_free()
        main.spawner.enemies.clear()
        var e1 = load("res://scripts/enemies/Enemy.gd").new()
        e1.init(0, 5, 5)
        main.spawner.enemies.append(e1)
        main.add_child(e1)
        e1.health = 1   # qualunque colpo e' letale
        main.player.character_type = C.CharacterType.DRAGON
        main.player.projectiles.append({
                "pos": e1.get_pixel_pos(), "dir": Vector2(1, 0),
                "active": true, "type": C.RelicType.FIREBALL_RED, "power": 2,
        })
        main._check_player_projectiles_vs_enemies(main.player)
        ok(e1.is_burning(), "grazia: FIREBALL_RED letale -> nemico che BRUCIA")
        # flame_blue su un secondo nemico -> statua
        var e2 = load("res://scripts/enemies/Enemy.gd").new()
        e2.init(0, 6, 6)
        main.spawner.enemies.append(e2)
        main.add_child(e2)
        e2.health = 1
        main.player.projectiles.append({
                "pos": e2.get_pixel_pos(), "dir": Vector2(1, 0),
                "active": true, "type": C.RelicType.FLAME_BLUE, "power": 2,
        })
        main._check_player_projectiles_vs_enemies(main.player)
        ok(e2.frozen and e2.health <= 0,
                        "grazia: FLAME_BLUE letale -> nemico CONGELATO (statua)")


# ---------------- E. guard collect_weapon ----------------
func _test_collect_guard() -> void:
        var p = main.player
        # 1) reliquia bonus in mano (senza flag ground): l'elementale a
        #    terra NON la sostituisce
        p.current_weapon = C.make_relic_weapon(C.get_relic_def(C.RelicType.SWORD))
        var w_elem: Dictionary = C.make_random_weapon([C.CharacterType.DRAGON])
        p.collect_weapon(w_elem)
        ok(int(p.current_weapon["type"]) == C.RelicType.SWORD,
                        "guard: bonus reliquia NON rubata dall'elementale a terra")
        # 2) elementale ground in mano: un'altra ground la sostituisce
        p.current_weapon = C.make_random_weapon([C.CharacterType.DRAGON])
        var w_elem2: Dictionary = C.make_random_weapon([C.CharacterType.DRAGON])
        p.collect_weapon(w_elem2)
        ok(int(p.current_weapon["type"]) == int(w_elem2["type"]),
                        "guard: ground->ground sostituzione OK")
        # 3) arma base in mano: l'elementale la sostituisce
        p.current_weapon = C.make_weapon(C.WeaponType.PISTOL)
        p.collect_weapon(w_elem2)
        ok(int(p.current_weapon["type"]) == int(w_elem2["type"]),
                        "guard: base->elementale sostituzione OK")
        # 4) elementale in mano: l'arma base a terra resta ignorata (regola storica)
        p.collect_weapon(C.make_weapon(C.WeaponType.SHOTGUN))
        ok(int(p.current_weapon["type"]) == int(w_elem2["type"]),
                        "guard: elementale in mano, base a terra ignorata")
