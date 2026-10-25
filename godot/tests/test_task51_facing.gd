## test_task51_facing.gd — TASK 51 (richieste utente):
##   F1 — Facing nativo: gli sheet disegnati verso SINISTRA (meta
##        "facesLeft": true — monster_010 BoneGolem, miniboss_08,
##        miniboss_18) propagano il flag su Enemy/MiniBoss; tutti gli
##        altri restano a false (convenzione destra).
##   F2 — Pozione fantasma: un player GHOST dentro la cella di un muro
##        di roccia CHIUSO non viene piu' imprigionato (held_by_wall
##        resta false e viene liberato se era tenuto).
##   F3 — Nessuno screen shake alla chiusura dei muri di roccia (il
##        registro di EffectsManager non registra shake da _close_wall).
extends Node


const C = preload("res://scripts/core/GameConstants.gd")
const EnemyScript = preload("res://scripts/enemies/Enemy.gd")
const MiniBossScript = preload("res://scripts/bosses/MiniBoss.gd")
const MazeHazardsScript = preload("res://scripts/entities/MazeHazards.gd")


## Stub player duck-typed per MazeHazards (serve solo position/ghost/jump).
class StubPlayer extends CharacterBody2D:
        var soul_pending: bool = false
        var held_by_wall: bool = false
        var held_by_trap: bool = false
        var _ghost: bool = false
        var _jump: bool = false

        func is_ghost() -> bool:
                return _ghost

        func is_jumping() -> bool:
                return _jump


## Stub spawner duck-typed (sola lista enemies).
class StubSpawner extends Node:
        var enemies: Array = []


## Stub controller duck-typed (player/player2/spawner.enemies).
class StubController extends Node:
        var player: CharacterBody2D = null
        var player2: CharacterBody2D = null
        var spawner: Node = null


        func _init() -> void:
                spawner = StubSpawner.new()


var _fails: int = 0
var _checks: int = 0


func _ready() -> void:
        _test_f1_enemy_facing()
        _test_f1_miniboss_facing()
        _test_f2_ghost_wall_immunity()
        _test_f3_no_close_shake()
        _report()
        get_tree().quit(1 if _fails > 0 else 0)


func _ok(msg: String) -> void:
        _checks += 1
        print("[TEST-51F] OK: %s" % msg)


func _fail(msg: String) -> void:
        _checks += 1
        _fails += 1
        print("[TEST-51F] FAIL: %s" % msg)


# ===========================================================================
# F1 — facing nativo Enemy
# ===========================================================================
func _test_f1_enemy_facing() -> void:
        # Monster_010 = BONE_GOLEM (audit: guarda a sinistra)
        var e := EnemyScript.new()
        add_child(e)
        e.init(C.EnemyType.BONE_GOLEM, 2, 2)
        if e._sprite_loaded and e._faces_left_native:
                _ok("F1: BONE_GOLEM (monster_010) facesLeft=true propagato")
        else:
                _fail("F1: BONE_GOLEM facesLeft=%s loaded=%s (atteso true/true)"
                                % [str(e._faces_left_native), str(e._sprite_loaded)])
        e.queue_free()

        # Monster_001 = GHOUL (frontale, non flaggato)
        var g := EnemyScript.new()
        add_child(g)
        g.init(C.EnemyType.GHOUL, 2, 3)
        if not g._faces_left_native:
                _ok("F1: GHOUL (monster_001) facesLeft=false (default)")
        else:
                _fail("F1: GHOUL facesLeft=true inatteso")
        g.queue_free()

        # SpriteManager: helper meta
        if SpriteManager.meta_faces_left("monster_010") \
                        and SpriteManager.meta_faces_left("miniboss_08") \
                        and SpriteManager.meta_faces_left("miniboss_18") \
                        and not SpriteManager.meta_faces_left("monster_001") \
                        and not SpriteManager.meta_faces_left("miniboss_01"):
                _ok("F1: SpriteManager.meta_faces_left coerente su 5 id")
        else:
                _fail("F1: meta_faces_left incoerente")


# ===========================================================================
# F1 — facing nativo MiniBoss (type 0-based: 7 -> miniboss_08, 17 -> miniboss_18)
# ===========================================================================
func _test_f1_miniboss_facing() -> void:
        var mb := MiniBossScript.new()
        add_child(mb)
        mb.setup(7, 1, 5, 5)
        if mb._faces_left_native:
                _ok("F1: miniboss_08 facesLeft=true propagato")
        else:
                _fail("F1: miniboss_08 facesLeft=false (atteso true, loaded=%s)"
                                % str(mb.sprite_loaded))
        mb.queue_free()

        var mb2 := MiniBossScript.new()
        add_child(mb2)
        mb2.setup(0, 1, 6, 6)
        if not mb2._faces_left_native:
                _ok("F1: miniboss_01 facesLeft=false (default)")
        else:
                _fail("F1: miniboss_01 facesLeft=true inatteso")
        mb2.queue_free()


# ===========================================================================
# F2 — pozione fantasma: mai imprigionato dai muri che si aprono/chiudono
# ===========================================================================
func _test_f2_ghost_wall_immunity() -> void:
        var hz := MazeHazardsScript.new()
        add_child(hz)
        var ctrl := StubController.new()
        add_child(ctrl)
        var p := StubPlayer.new()
        add_child(p)
        ctrl.player = p
        hz.controller = ctrl

        # player al centro della cella (5,5)
        p.position = Vector2(5 * 64 + 32, C.UI_HEIGHT + 5 * 64 + 32)
        var h := {
                "type": MazeHazardsScript.HazardType.ROCK_WALL,
                "cell": Vector2i(5, 5),
                "phase": MazeHazardsScript.WallPhase.CLOSED,
                "phase_ms": 0.0,
                "axis": "h",
        }

        # 1) player solido: la cella chiusa lo tiene
        hz._hold_entities_in_wall(h, null)
        if p.held_by_wall:
                _ok("F2: player solido in cella chiusa = tenuto (spec Task 30)")
        else:
                _fail("F2: player solido non tenuto dal muro chiuso")
        # rilascio per il check successivo
        hz._release_entities_in_wall(h, null)
        if not p.held_by_wall:
                _ok("F2: apertura = rilascio del player tenuto")
        else:
                _fail("F2: il player resta tenuto dopo l'apertura")

        # 2) player FANTASMA (pozione attraversa-muri): mai imprigionato,
        #    anche se era tenuto prima di bere la pozione
        p._ghost = true
        p.held_by_wall = true  # era tenuto, poi beve la pozione
        hz._hold_entities_in_wall(h, null)
        if not p.held_by_wall:
                _ok("F2: player GHOST nella cella chiusa = LIBERO (fix Task 51)")
        else:
                _fail("F2: il fantasma resta imprigionato nel muro chiuso")

        # 3) player che salta: anch'esso immune (vola sopra)
        p._ghost = false
        p._jump = true
        p.held_by_wall = false
        hz._hold_entities_in_wall(h, null)
        if not p.held_by_wall:
                _ok("F2: player in salto sulla cella chiusa = immune")
        else:
                _fail("F2: il player in salto viene imprigionato")

        hz.queue_free()
        ctrl.queue_free()
        p.queue_free()


# ===========================================================================
# F3 — niente screen shake alla chiusura dei muri di roccia
# ===========================================================================
func _test_f3_no_close_shake() -> void:
        var hz := MazeHazardsScript.new()
        add_child(hz)
        # maze duck-typed con la sola proprieta' dynamic_walls (Dictionary)
        var duck := GDScript.new()
        duck.source_code = "extends Node\nvar dynamic_walls: Dictionary = {}\n"
        duck.reload()
        var mn := Node.new()
        mn.set_script(duck)
        add_child(mn)
        var h := {
                "type": MazeHazardsScript.HazardType.ROCK_WALL,
                "cell": Vector2i(5, 5),
                "phase": MazeHazardsScript.WallPhase.WARN,
                "phase_ms": 99999.0,
                "axis": "h",
                "slab_a": null,
                "slab_b": null,
                "off_a": 64.0,
                "off_b": 64.0,
        }
        hz.controller = null
        var timer_before: float = 0.0
        var amount_before: float = 0.0
        if EffectsManager:
                timer_before = EffectsManager._shake_timer
                amount_before = EffectsManager._shake_amount
        hz._close_wall(h, mn)
        if EffectsManager and EffectsManager._shake_timer == timer_before \
                        and EffectsManager._shake_amount == amount_before:
                _ok("F3: chiusura muro di roccia = NESSUNO screen shake")
        else:
                _fail("F3: la chiusura del muro ha innescato uno shake (%s/%s)"
                                % [str(EffectsManager._shake_timer),
                                   str(EffectsManager._shake_amount)])
        if mn.dynamic_walls.get("5,5", null) == true:
                _ok("F3: dynamic_walls registrata dallo stub maze (chiusa)")
        else:
                _fail("F3: dynamic_walls non popolata (maze stub rotto)")
        hz.queue_free()
        mn.queue_free()


func _report() -> void:
        print("[TEST-51F] ==== %s (%d check, %d falliti) ===="
                        % ["TEST TASK 51 FACING SUPERATO" if _fails == 0
                                        else "TEST TASK 51 FALLITO",
                                _checks, _fails])
