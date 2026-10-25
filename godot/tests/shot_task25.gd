## shot_task25.gd — TASK 25: screenshot REALI di:
##   * player con armatura reliquia equipaggiata: OUTFIT ricolorato dallo
##     shader armor_outfit (Scaglie del Drago: il cuoio rosso-scuro dell'eroe
##     diventa verde + tinta metallo + rim) oltre all'aura procedurale;
##   * Mjolnir pickup RIGENERATO (manico chiaro/lungo/pomo) a terra accanto
##     al player;
##   * 3 boss animati (Golem=LP_ARMS+WALK, Kraken=LP_TENTACLES, Demon=
##     LP_WINGS+WALK) con gain 2.6: frame a ~0.5s di distanza mostrano gli
##     arti in posizioni diverse.
## Nemici ripuliti ogni frame (pattern shot_all_weapons): il player sopravvive.
extends Node2D

const BossScript = preload("res://scripts/bosses/Boss.gd")
const CollectiblesClass = preload("res://scripts/items/Collectibles.gd")

var main: Node2D = null
var bosses: Array = []
var setup_done := false
var t := 0.0


func _ready() -> void:
        LoadingScreen.skip_boot_hold()
        GameManager.num_players = 1
        GameManager.reset_run()
        var scene := load("res://scenes/MainGame.tscn") as PackedScene
        main = scene.instantiate()
        add_child.call_deferred(main)


func _process(delta: float) -> void:
        if main == null or not main.is_node_ready():
                return
        # sicurezza: niente nemici, niente hurry up durante lo shot.
        for e in main.spawner.enemies.duplicate():
                if is_instance_valid(e):
                        e.queue_free()
        main.spawner.enemies.clear()
        main._since_last_treasure_ms = 0.0
        if not setup_done:
                _setup()
                return
        t += delta
        # aggiorna i boss manualmente (la scena maze non ha il controller
        # della boss room): ogni frame la mesh si deforma con anim_time.
        for b in bosses:
                if is_instance_valid(b):
                        var out: Array = []
                        b.update_step(b.pos.x + 1.0, 500.0, int(delta * 1000.0), out)
        # diagnostica (pattern Task 24): mappa frame -> posizioni per i crop
        if fmod(t, 0.2) < delta:
                var pp: Vector2 = main.player.position
                var bs: Array = []
                for b in bosses:
                        if is_instance_valid(b):
                                bs.append("(%.0f,%.0f)" % [b.pos.x, b.pos.y])
                print("SHOT25 t=%.2f player=(%.0f,%.0f) bosses=%s" % [t, pp.x, pp.y, str(bs)])


func _setup() -> void:
        setup_done = true
        var p: CharacterBody2D = main.player
        # 1) OUTFIT ARMATURA: Scaglie del Drago (kind reflect, verde).
        p.equip_relic_armor(GameConstants.RELIC_ARMORS[1])
        p.last_dx = 1
        p.last_dy = 0
        # 2) player in un corridoio della fascia centrale.
        var cell := _find_corridor()
        var ppos := Vector2(cell.x * 64.0 + 32.0, 80.0 + cell.y * 64.0 + 32.0)
        p.set_position_abs(ppos.x, ppos.y)
        # 3) Mjolnir pickup rigenerato a ~1.5 celle sulla destra del player.
        var hammer: Node2D = CollectiblesClass.new()
        hammer.kind = CollectiblesClass.Kind.HAMMER
        var hpos := Vector2(ppos.x + 96.0, ppos.y)
        hammer.pos = hpos
        hammer.position = hpos
        main.collectibles_node.add_child(hammer)
        # 4) boss showcase: Golem (68 -> tipo 0, LP_ARMS + WALK),
        #    Kraken (20 -> tipo 5, LP_TENTACLES), Demon (8 -> tipo 2,
        #    LP_WINGS + WALK). Tre sagome in fascia alta, ben distanziate.
        var specs: Array = [
                [68, Vector2(430.0, 430.0)],
                [20, Vector2(960.0, 470.0)],
                [8, Vector2(1490.0, 430.0)],
        ]
        for s in specs:
                var b := BossScript.new()
                add_child(b)
                b.setup(s[0], 1920, 1080)
                b.pos = s[1]
                b.position = s[1]
                b._draw()   # lazy-load della texture XHD
                bosses.append(b)


func _find_corridor() -> Vector2i:
        for r in range(8, 14):
                for c in range(10, 20):
                        if not main.maze.is_wall(c, r):
                                return Vector2i(c, r)
        return Vector2i(14, 10)
