## test_relics.gd — Test funzionale runtime (headless) delle RELIQUIE (Task 21):
##   A. COSTANTI: 18 reliquie (6 mischia + 6 distanza + 6 armature), tipi
##      unici 101..113, WEAPON_HITS_TO_KILL complete, danno furore.
##   B. ROTAZIONE: schermata A/B/C (6/6/5 sui 17 boss); offerta = 1 reliquia
##      per famiglia con cursori sfasati; tutte le 18 offerte in 17 incontri.
##   C. PLAYER: equip armatura (+2 energia max, cura piena); Corazza d'Oro
##      assorbe (energia intatta, carica-1, 10 cariche); MORTE = reliquia e
##      armatura PERSE; armi a terra NON sovrascrivono la reliquia; colpi
##      esauriti = rottura -> PISTOL.
##   D. MISCHIA (labirinto): Spadone colpisce davanti e NON dietro; Mazza
##      stordisce; Lama del Vampiro cura.
##   E. DISTANZA (labirinto): Balestra perfora esattamente 3 nemici; Pugnali
##      ventaglio di 3; Verga a catena; Bombe esplodono ad area.
##   F. ARMATURE (labirinto): Scaglie riflettono il proiettile nemico (power
##      = miglior colpo); Ossidiana spine al tocco; Veste rigenera; Fuoco
##      aura; Furore potenzia e si consuma.
##   G. BOSS ROOM: colpi infiniti; arma reliquia NON potenziata/sovrascritta
##      all'ingresso; riflessione verso il BOSS; morte boss -> SCHERMATA
##      BONUS (2 choosers, 3 offerte una per famiglia); scelte applicate;
##      segnale completamento; carry con reliquie.
extends Node

const C = preload("res://scripts/core/GameConstants.gd")
const MainGameScene = preload("res://scenes/MainGame.tscn")
const BossRoomScene = preload("res://scenes/BossRoom.tscn")
const ProjectileClass = preload("res://scripts/items/Projectile.gd")

var main: Node2D = null
var boss_room: Node2D = null
var phase: int = 0
var t: float = 0.0
var phase_t: float = 0.0
var failures: Array = []
# Enemy di test (vivi, congelati dal loop in pausa).
var test_enemies: Array = []
# Celle corridoio sicure (EMPTY) trovate a runtime.
var corridor_cells: Array[Vector2i] = []


func _ready() -> void:
        GameManager.num_players = 2
        print("[TEST] boot MainGame 2P per reliquie...")
        main = MainGameScene.instantiate()
        get_tree().root.add_child.call_deferred(main)


func _fail(msg: String) -> void:
        failures.append(msg)
        print("[TEST FAIL] ", msg)


func _ok(msg: String) -> void:
        print("[TEST] OK ", msg)


func _next(next_phase: int) -> void:
        phase = next_phase
        phase_t = 0.0


func _ready_main() -> bool:
        return main != null and main.is_node_ready()


func _ready_boss() -> bool:
        return boss_room != null and boss_room.is_node_ready()


func _cell_center(c: int, r: int) -> Vector2:
        return Vector2(c * 64.0 + 32.0, r * 64.0 + 32.0 + 80.0)


## Posiziona un nemico di test su una cella corridoio.
func _place_enemy(idx: int, c: int, r: int) -> void:
        var e = test_enemies[idx]
        e.position = _cell_center(c, r)
        e.health = e.max_health
        # TASK 94 (indurimento flake): se il nemico e' MORTO in una fase
        # precedente (dying_timer > 0 — es. GHOST da 1 HP ucciso dalla Lama
        # del Vampiro in D3) il suo take_damage ignora TUTTI i colpi
        # successivi: con gioco in pausa il timer di morte non scende mai e
        # le fasi E/F fallivano a raffica (~12% dei run: test_enemies[0]
        # GHOST per RNG per-run). Il nemico di test dev'essere sempre VIVO
        # quando viene (ri)piazzato: reset anche dello stato di
        # morte/congelamento, non solo della salute.
        e.dying_timer = 0
        e.frozen = false


func _physics_process(delta: float) -> void:
        t += delta
        phase_t += delta
        if t > 60.0:
                _fail("timeout globale del test (60s)")
                get_tree().quit(1)
                return
        match phase:
                0:
                        # --- A/B: costanti + rotazione (puro calcolo) ---
                        if phase_t > 0.1 and not test_enemies.size() > 0 \
                                        and _phaseAB():
                                _next(1)
                1:
                        # --- boot MainGame: congela, pulisci, prepara nemici ---
                        if not _ready_main():
                                return
                        if phase_t > 1.2:
                                _prepare_maze()
                                _next(2)
                2:
                        _phaseC_player_armor()
                        _next(3)
                3:
                        _phaseD_melee()
                        _next(4)
                4:
                        _phaseE_ranged()
                        _next(5)
                5:
                        _phaseF_armors_maze()
                        _next(6)
                6:
                        # --- boot BossRoom per i test G ---
                        if boss_room == null:
                                if phase_t > 0.1:
                                        boss_room = BossRoomScene.instantiate()
                                        get_tree().root.add_child.call_deferred(boss_room)
                                        phase_t = 0.0
                                return
                        if _ready_boss() and phase_t > 1.0:
                                boss_room.is_paused = true
                                _next(7)
                7:
                        _phaseG_boss_room()
                        _next(8)
                8:
                        if failures.is_empty():
                                print("[TEST] ==== TUTTI I TEST RELIQUIE SUPERATI ====")
                                get_tree().quit(0)
                        else:
                                print("[TEST] ==== FALLITI ", failures.size(), " test ====")
                                for f in failures:
                                        print("[TEST FAIL] ", f)
                                get_tree().quit(1)


# ============================================================================
# FASE A/B — costanti e rotazione (puro calcolo, nessuna scena)
# ============================================================================
func _phaseAB() -> bool:
        # A1: conteggi famiglie.
        if C.RELIC_MELEE.size() != 6:
                _fail("A1: RELIC_MELEE != 6 reliquie (" + str(C.RELIC_MELEE.size()) + ")")
        if C.RELIC_RANGED.size() != 6:
                _fail("A1: RELIC_RANGED != 6 reliquie")
        if C.RELIC_ARMORS.size() != 6:
                _fail("A1: RELIC_ARMORS != 6 reliquie")
        # A2: tipi unici 101..113 tutti in WEAPON_HITS_TO_KILL.
        var seen: Dictionary = {}
        for def in C.RELIC_MELEE + C.RELIC_RANGED:
                var ty: int = int(def.get("type", 0))
                if seen.has(ty):
                        _fail("A2: type duplicato " + str(ty))
                seen[ty] = true
                if not C.WEAPON_HITS_TO_KILL.has(ty):
                        _fail("A2: type " + str(ty) + " mancante in WEAPON_HITS_TO_KILL")
                if int(C.WEAPON_HITS_TO_KILL[ty]) < 2:
                        _fail("A2: reliquia one-shot?! type " + str(ty))
        if seen.size() != 12:
                _fail("A2: attesi 12 tipi arma, trovati " + str(seen.size()))
        # A3: danno furore (floor 2, mai one-shot).
        if C.weapon_damage_for(C.WeaponType.PISTOL, 40, false) != 10:
                _fail("A3: danno PISTOL base errato")
        if C.weapon_damage_for(C.WeaponType.PISTOL, 40, true) != 14:
                _fail("A3: furore PISTOL 4->3 colpi atteso 14, avuto "
                                + str(C.weapon_damage_for(C.WeaponType.PISTOL, 40, true)))
        if C.weapon_damage_for(C.WeaponType.ROCKET, 40, true) != 20:
                _fail("A3: furore non rispetta il floor 2 colpi")
        # B1: rotazione schermate A/B/C sui 17 boss (A=6, B=6, C=5).
        var counts := {"A": 0, "B": 0, "C": 0}
        for boss_idx in range(17):
                var lvl: int = (boss_idx + 1) * 4
                counts[["A", "B", "C"][C.get_bonus_screen_id(lvl)]] += 1
        if counts["A"] != 6 or counts["B"] != 6 or counts["C"] != 5:
                _fail("B1: rotazione A/B/C = " + str(counts) + " (attesi 6/6/5)")
        # B2: dopo il boss 1 la A, boss 2 la B, boss 3 la C, boss 4 la A.
        if C.get_bonus_screen_id(4) != 0 or C.get_bonus_screen_id(8) != 1 \
                        or C.get_bonus_screen_id(12) != 2 or C.get_bonus_screen_id(16) != 0:
                _fail("B2: sequenza A->B->C->A sbagliata")
        # B3: offerta = 3 reliquie, UNA per famiglia, per OGNI incontro.
        var all_ids: Dictionary = {}
        var prev_melee_id := ""
        for e in range(17):
                var lvl2: int = (e + 1) * 4
                var offer: Array[Dictionary] = C.get_bonus_offering(lvl2)
                if offer.size() != 3:
                        _fail("B3: offerta != 3 reliquie al livello " + str(lvl2))
                var fams := {}
                for d in offer:
                        fams[d.get("family", "?")] = true
                        all_ids[str(d.get("id", ""))] = true
                if fams.size() != 3 or not fams.has("mischia") \
                                or not fams.has("distanza") or not fams.has("armatura"):
                        _fail("B3: famiglie incomplete al livello " + str(lvl2))
                # il ciclo interno alla famiglia non ripete lo stesso pezzo.
                if str(offer[0].get("id")) == prev_melee_id:
                        _fail("B3: mischia ripetuta due volte di fila (" + prev_melee_id + ")")
                prev_melee_id = str(offer[0].get("id"))
        if all_ids.size() != 18:
                _fail("B3: offerte totali != 18 reliquie (" + str(all_ids.size()) + ")")
        # B5 (TASK 33): ordinamento di POTENZA CRESCENTE — il primo boss
        # offre le piu' scarse (Mazza / Arco / Ossidiana), il sesto le piu'
        # forti (Ascia / Bombe / Furore), e la potenza non cala mai dentro
        # il ciclo per mischia e distanza (campo "power").
        var first: Array[Dictionary] = C.get_bonus_offering(4)
        if str(first[0].get("id")) != "mace" or str(first[1].get("id")) != "ranger_bow" \
                        or str(first[2].get("id")) != "obsidian":
                _fail("B5: incontro 1 non offre le piu' scarse (%s/%s/%s)"
                                % [first[0].get("id"), first[1].get("id"), first[2].get("id")])
        var sixth: Array[Dictionary] = C.get_bonus_offering(24)
        if str(sixth[0].get("id")) != "axe" or str(sixth[1].get("id")) != "alchemist_bombs" \
                        or str(sixth[2].get("id")) != "fury":
                _fail("B5: incontro 6 non offre le piu' forti (%s/%s/%s)"
                                % [sixth[0].get("id"), sixth[1].get("id"), sixth[2].get("id")])
        for e in range(5):
                var lo: Array[Dictionary] = C.get_bonus_offering((e + 1) * 4)
                var hi: Array[Dictionary] = C.get_bonus_offering((e + 2) * 4)
                if int(lo[0].get("power", 0)) > int(hi[0].get("power", 0)):
                        _fail("B5: potenza mischia non crescente al tier %d" % e)
                if int(lo[1].get("power", 0)) > int(hi[1].get("power", 0)):
                        _fail("B5: potenza distanza non crescente al tier %d" % e)
        # B4: encounters/levels chiavi.
        if C.get_bonus_encounter(4) != 0 or C.get_bonus_encounter(68) != 16:
                _fail("B4: encounter 4->0 / 68->16 sbagliati")
        if failures.is_empty():
                _ok("A/B: costanti (18 reliquie, tipi, hits, furore), rotazione 6/6/5"
                                + " e ordine potenza crescente (Task 33)")
        return true


# ============================================================================
# Preparazione del labirinto (nemici congelati + corridoi)
# ============================================================================
func _prepare_maze() -> void:
        # Congela il loop: da qui solo chiamate dirette (pattern test FF F1).
        main.is_paused = true
        # TASK 38 (spawn guard): il player nasce con 3s di immortalita' —
        # azzerata perche' le fasi C-F verificano assorbimenti, spine e
        # aura su un player VULNERABILE (deterministico, niente timing).
        main.player.spawn_guard_ms = 0
        main.player2.spawn_guard_ms = 0
        # Nemici: tienine 3, elimina il resto; posizioni sotto controllo.
        test_enemies.clear()
        var alive: Array = []
        for e in main.spawner.enemies:
                if test_enemies.size() < 3:
                        test_enemies.append(e)
                else:
                        e.take_damage(99999)
        # Rimuove gli item a terra (medikit/pozione altererebbero l'energia).
        for item in main.collectibles_node.get_children():
                item.queue_free()
        # Cerca 4 celle EMPTY consecutive su una riga (per perforante/bombe).
        corridor_cells.clear()
        var found_run: bool = false
        for r in range(1, 14):
                if found_run:
                        break
                var run: Array[Vector2i] = []
                for c2 in range(1, 27):
                        if main.maze.get_cell_type(c2, r) == 0:
                                run.append(Vector2i(c2, r))
                                if run.size() >= 5:
                                        corridor_cells = run
                                        found_run = true
                                        break
                        else:
                                run.clear()
        if not found_run:
                _fail("prep: nessun corridoio di 5 celle trovato")
                # fallback: cella (1,1)
                corridor_cells = [Vector2i(1, 1), Vector2i(1, 1), Vector2i(1, 1)]
        # Player su la 1a cella del corridoio, guardando a destra.
        var p: CharacterBody2D = main.player
        var start_pos: Vector2 = _cell_center(corridor_cells[0].x, corridor_cells[0].y)
        p.set_position_abs(start_pos.x, start_pos.y)
        p.set_direction(0, 0)
        p.last_dx = 1
        p.last_dy = 0
        p.damage_timer = 0
        p.invincible_timer = 0
        _ok("prep: labirinto congelato, 3 nemici di test, corridoio "
                        + str(corridor_cells[0]))


# ============================================================================
# FASE C — logica armatura/regole sul player (chiamate dirette)
# ============================================================================
func _phaseC_player_armor() -> void:
        var p: CharacterBody2D = main.player

        # C1: equip armatura: +2 energia max (5->7) e CURA PIENA.
        p.armor_relic = {}
        p.max_energy = 5
        p.energy = 2
        p.equip_relic_armor(C.RELIC_ARMORS[0])  # Corazza d'Oro
        if p.max_energy != 7 or p.energy != 7:
                _fail("C1: equip non da +2 energia max con cura piena ("
                                + str(p.max_energy) + "/" + str(p.energy) + ")")
        elif p.armor_charges() != 10:
                _fail("C1: Corazza d'Oro deve avere 10 cariche, ha " + str(p.armor_charges()))
        else:
                _ok("C1: equip armatura (+2 max energia, cura piena, 10 cariche)")

        # C2: assorbimento — l'energia NON cala, la carica si consuma.
        var charges_before: int = p.armor_charges()
        p.damage_timer = 0
        p.take_damage()
        if p.energy != 7:
                _fail("C2: energia calata nonostante assorbimento (" + str(p.energy) + ")")
        elif p.armor_charges() != charges_before - 1:
                _fail("C2: carica non consumata dall'assorbimento")
        else:
                _ok("C2: Corazza d'Oro assorbe il colpo (energia intatta, -1 carica)")

        # C3: 10 assorbimenti -> l'armatura SI ROMPE e il colpo 11 arriva.
        for i in range(9):
                p.damage_timer = 0
                p.take_damage()
        if p.has_relic_armor():
                _fail("C3: armatura d'Oro non si è rotta dopo 10 assorbimenti")
        elif p.max_energy != 5:
                _fail("C3: energia max non tornata a 5 dopo la rottura")
        else:
                _ok("C3: 10 cariche esaurite -> armatura rotta, energia max torna a 5")

        # C4: MORTE = reliquia arma E armatura PERSE (decisione utente).
        p.current_weapon = C.make_relic_weapon(C.RELIC_MELEE[0])
        p.equip_relic_armor(C.RELIC_ARMORS[3])  # Veste
        p.energy = 1
        p.damage_timer = 0
        var lives_before: int = p.lives
        p.take_damage()
        # TASK 87: la morte ora avvia il collasso (respawn differito alla
        # fine dell'animazione): lo completiamo subito come fa il controller
        # a fine animazione, cosi' i check successivi lavorano sul player
        # respawnato (vita persa + reliquie perse sono gia' avvenute nel
        # ramo morte sincrono).
        p.respawn_after_soul()
        if p.lives != lives_before - 1:
                _fail("C4: vita non persa")
        elif p.current_weapon.has("relic"):
                _fail("C4: arma reliquia NON persa alla morte")
        elif p.has_relic_armor():
                _fail("C4: armatura NON persa alla morte")
        elif p.max_energy != 5:
                _fail("C4: energia max non ripristinata a 5 dopo la morte")
        else:
                _ok("C4: alla morte si perdono arma reliquia E armatura")

        # C5: le armi a terra NON sovrascrivono la reliquia.
        p.current_weapon = C.make_relic_weapon(C.RELIC_RANGED[0])
        p.collect_weapon({"type": C.WeaponType.ROCKET, "power": 5, "ammo": 4})
        if int(p.current_weapon.get("type", 0)) != C.RelicType.CROSSBOW:
                _fail("C5: arma base a terra ha sovrascritto la reliquia!")
        else:
                _ok("C5: le armi a terra NON sovrascrivono la reliquia")

        # C6: colpi esauriti -> la reliquia SI ROMPE -> PISTOL.
        p.current_weapon = C.make_relic_weapon(C.RELIC_RANGED[0])
        p.current_weapon["ammo"] = 1
        p.relic_infinite_shots = false
        p.last_dx = 1
        p.last_dy = 0
        p.projectiles.clear()
        p.shoot()
        if p.current_weapon.has("relic"):
                _fail("C6: reliquia non rotta a colpi esauriti")
        elif int(p.current_weapon.get("type", -1)) != C.WeaponType.PISTOL:
                _fail("C6: non si torna alla PISTOL dopo la rottura")
        else:
                _ok("C6: colpi esauriti -> reliquia rotta -> PISTOL")

        # C7: in boss room (flag) i colpi NON si consumano.
        p.current_weapon = C.make_relic_weapon(C.RELIC_RANGED[0])
        p.relic_infinite_shots = true
        p.projectiles.clear()
        p.shoot()
        if int(p.current_weapon.get("ammo", 0)) != int(C.RELIC_RANGED[0]["shots"]):
                _fail("C7: colpi consumati nonostante flag infiniti")
        else:
                _ok("C7: flag boss room = colpi infiniti")
        p.relic_infinite_shots = false
        p.projectiles.clear()

        # C8: Pugnali Gemelli = ventaglio di 3 proiettili per salve.
        p.current_weapon = C.make_relic_weapon(C.RELIC_RANGED[2])
        p.projectiles.clear()
        p.shoot()
        if p.projectiles.size() != 3:
                _fail("C8: Pugnali Gemelli sparano " + str(p.projectiles.size()) + " lame, attese 3")
        else:
                var dirs_ok: bool = p.projectiles[0]["dir"].angle() \
                                < p.projectiles[2]["dir"].angle()
                if not dirs_ok:
                        _fail("C8: il ventaglio non e' ordinato per angolo")
                else:
                        _ok("C8: Pugnali Gemelli = ventaglio di 3 lame")
        p.projectiles.clear()
        p.armor_relic = {}


# ============================================================================
# FASE D — mischia nel labirinto
# ============================================================================
func _phaseD_melee() -> void:
        var p: CharacterBody2D = main.player
        var pos_d: Vector2 = _cell_center(corridor_cells[0].x, corridor_cells[0].y)
        p.set_position_abs(pos_d.x, pos_d.y)
        p.set_direction(0, 0)
        p.last_dx = 1
        p.last_dy = 0
        p.armor_relic = {}

        # D1: Spadone — colpisce DAVANTI (settore 120 gradi, 2 celle), non dietro.
        _place_enemy(0, corridor_cells[0].x + 1, corridor_cells[0].y)
        _place_enemy(1, corridor_cells[0].x - 1, corridor_cells[0].y)  # dietro
        var hp_front: int = test_enemies[0].health
        var hp_back: int = test_enemies[1].health
        p.current_weapon = C.make_relic_weapon(C.RELIC_MELEE[0])
        p.projectiles.clear()
        p.shoot()  # alza melee_pending (niente proiettile)
        if p.projectiles.size() != 0:
                _fail("D1: la mischia non deve spawnare proiettili")
        if not p.melee_pending:
                _fail("D1: melee_pending non alzato dallo sparo in mischia")
                return
        main._check_pending_relic_melee(p)
        var dmg_expected: int = int(ceil(float(test_enemies[0].max_health) / 2.0))
        if test_enemies[0].health != hp_front - dmg_expected:
                _fail("D1: Spadone non fa 2-colpi-vita al nemico davanti ("
                                + str(hp_front - test_enemies[0].health) + " vs attesi " + str(dmg_expected) + ")")
        elif test_enemies[1].health != hp_back:
                _fail("D1: lo Spadone ha colpito anche DIETRO?!")
        else:
                _ok("D1: Spadone fende davanti (50% HP) e ignora chi sta dietro")

        # D2: Mazza Ferrata — colpisce a 360 gradi e STORDISCE (1s).
        _place_enemy(1, corridor_cells[0].x - 1, corridor_cells[0].y)
        test_enemies[1].stun_timer_ms = 0
        p.current_weapon = C.make_relic_weapon(C.RELIC_MELEE[2])
        p.shoot()
        main._check_pending_relic_melee(p)
        if test_enemies[1].stun_timer_ms <= 0:
                _fail("D2: la Mazza non stordisce il nemico alle spalle")
        else:
                _ok("D2: Mazza Ferrata 360 gradi + stordimento (" + str(test_enemies[1].stun_timer_ms) + "ms)")

        # D3: Lama del Vampiro — cura 1 energia per nemico colpito.
        _place_enemy(0, corridor_cells[0].x + 1, corridor_cells[0].y)
        p.current_weapon = C.make_relic_weapon(C.RELIC_MELEE[4])
        p.energy = 3
        p.max_energy = 5
        p.shoot()
        main._check_pending_relic_melee(p)
        if p.energy != 4:
                _fail("D3: la Lama del Vampiro non ha curato (energia " + str(p.energy) + ")")
        else:
                _ok("D3: Lama del Vampiro cura 1 energia per nemico colpito")
        p.projectiles.clear()


# ============================================================================
# FASE E — distanza nel labirinto
# ============================================================================
func _phaseE_ranged() -> void:
        var p: CharacterBody2D = main.player
        var pos_e: Vector2 = _cell_center(corridor_cells[0].x, corridor_cells[0].y)
        p.set_position_abs(pos_e.x, pos_e.y)
        p.set_direction(0, 0)
        p.last_dx = 1
        p.last_dy = 0
        p.armor_relic = {}

        # E1: Balestra d'Argento — perfora ESATTAMENTE 3 nemici in fila.
        _place_enemy(0, corridor_cells[1].x, corridor_cells[1].y)
        _place_enemy(1, corridor_cells[2].x, corridor_cells[2].y)
        _place_enemy(2, corridor_cells[3].x, corridor_cells[3].y)
        var hps: Array = [test_enemies[0].health, test_enemies[1].health,
                        test_enemies[2].health]
        p.current_weapon = C.make_relic_weapon(C.RELIC_RANGED[0])
        p.projectiles.clear()
        p.shoot()
        # Avanza il dardo (update_player muove i proiettili) e checka i colpi.
        for i in 60:
                p.update_player(main.maze, false, 16.0)
                main._check_player_projectiles_vs_enemies(p)
                if p.projectiles.is_empty():
                        break
        var hit_count: int = 0
        for i in 3:
                if test_enemies[i].health < hps[i]:
                        hit_count += 1
        if hit_count != 3:
                _fail("E1: la Balestra ha colpito " + str(hit_count) + " nemici su 3 (perforante)")
        elif not p.projectiles.is_empty():
                _fail("E1: il dardo perforante non si è fermato dopo il 3° nemico")
        else:
                _ok("E1: Balestra d'Argento perfora esattamente 3 nemici in fila")

        # E2: Verga della Tempesta — catena su nemici vicini al bersaglio.
        _place_enemy(0, corridor_cells[1].x, corridor_cells[1].y)
        _place_enemy(1, corridor_cells[2].x, corridor_cells[2].y)  # a 64px: entro 128px
        var hp0: int = test_enemies[0].health
        var hp1: int = test_enemies[1].health
        p.current_weapon = C.make_relic_weapon(C.RELIC_RANGED[4])
        p.projectiles.clear()
        p.shoot()
        for i in 60:
                p.update_player(main.maze, false, 16.0)
                main._check_player_projectiles_vs_enemies(p)
                if p.projectiles.is_empty():
                        break
        if test_enemies[0].health >= hp0:
                _fail("E2: la Verga non ha colpito il bersaglio primario")
        elif test_enemies[1].health >= hp1:
                _fail("E2: la catena non è saltata al nemico vicino")
        else:
                _ok("E2: Verga della Tempesta — catena a 2 nemici")
        p.projectiles.clear()

        # E3: Bombe dell'Alchimista — parabola che ESPLODE ad area.
        _place_enemy(0, corridor_cells[2].x, corridor_cells[2].y)  # a 128px: entro il raggio 96 del centro esplosione
        var hpb: int = test_enemies[0].health
        p.current_weapon = C.make_relic_weapon(C.RELIC_RANGED[5])
        p.projectiles.clear()
        p.shoot()
        # 160px di parabola = 20 frame da 8px.
        for i in 25:
                p.update_player(main.maze, false, 16.0)
        main._consume_relic_bombs(p)
        if test_enemies[0].health >= hpb:
                _fail("E3: la bomba non ha danneggiato il nemico nell'area")
        elif not p.projectiles.is_empty():
                _fail("E3: la bomba esplosa non è stata rimossa")
        else:
                _ok("E3: Bombe dell'Alchimista esplodono ad area dopo la parabola")
        p.projectiles.clear()


# ============================================================================
# FASE F — armature nel labirinto
# ============================================================================
func _phaseF_armors_maze() -> void:
        var p: CharacterBody2D = main.player
        var pos_f: Vector2 = _cell_center(corridor_cells[0].x, corridor_cells[0].y)
        p.set_position_abs(pos_f.x, pos_f.y)
        p.set_direction(0, 0)
        p.last_dx = 1
        p.last_dy = 0
        p.damage_timer = 0
        p.invincible_timer = 0
        # TASK 38 (spawn guard): eventuale guardia di nascita/rinascita a
        # zero — le fasi F verificano spine e aura su player vulnerabile.
        p.spawn_guard_ms = 0

        # F1: Scaglie del Drago — riflettono il proiettile NEMICO (labirinto):
        # direzione OPPOSTA, potenza del MIGLIOR colpo (max 5).
        p.equip_relic_armor(C.RELIC_ARMORS[1])
        p.current_weapon = {"type": C.WeaponType.PISTOL, "power": 1, "ammo": 15}
        var proj := Node2D.new()
        proj.position = p.get_pixel_pos()
        proj.set_meta("velocity", Vector2(4.0, 0.0))
        proj.visible = true
        main.enemy_projectiles_node.add_child(proj)
        var bolts_before: int = p.projectiles.size()
        main._check_enemy_projectiles_vs_player(p)
        if p.projectiles.size() != bolts_before + 1:
                _fail("F1: nessun proiettile riflesso dalle Scaglie")
        else:
                var bolt: Dictionary = p.projectiles[p.projectiles.size() - 1]
                if int(bolt.get("type", 0)) != C.RelicType.REFLECT_BOLT:
                        _fail("F1: il rimbalzo non è un REFLECT_BOLT")
                elif int(bolt.get("power", 0)) != 5:
                        _fail("F1: il rimbalzo non ha la potenza del miglior colpo ("
                                        + str(bolt.get("power")) + ")")
                elif bolt.get("dir", Vector2.ZERO).x >= 0.0:
                        _fail("F1: il rimbalzo non torna indietro")
                elif p.armor_charges() != 3:
                        _fail("F1: carica non consumata dal rimbalzo (" + str(p.armor_charges()) + ")")
                else:
                        _ok("F1: Scaglie del Drago riflettono (power 5, indietro, -1 carica)")
        p.projectiles.clear()
        p.armor_relic = {}

        # F2: Ossidiana — chi TOCCA prende 2 danni da spine.
        _place_enemy(0, corridor_cells[0].x, corridor_cells[0].y)  # addosso
        var hp_touch: int = test_enemies[0].health
        p.energy = 5
        p.damage_timer = 0
        p.equip_relic_armor(C.RELIC_ARMORS[2])
        main._check_melee_collisions(p)
        if test_enemies[0].health != hp_touch - 2:
                _fail("F2: le spine non fanno 2 danni (danno " + str(hp_touch - test_enemies[0].health) + ")")
        elif p.armor_charges() != 4:
                _fail("F2: tacca non consumata dalle spine")
        else:
                _ok("F2: Ossidiana del Crepuscolo — spine 2 danni al tocco")
        p.armor_relic = {}

        # F3: Veste dell'Arcimago — rigenera 1 energia ogni 5s (12 volte).
        p.equip_relic_armor(C.RELIC_ARMORS[3])
        p.energy = 3
        p.max_energy = 7
        p._armor_regen_timer_ms = 4990.0
        p.update_player(main.maze, false, 16.0)
        if p.energy != 4:
                _fail("F3: la Veste non rigenera l'energia")
        elif p.armor_charges() != 11:
                _fail("F3: rigenerazione non consuma carica")
        else:
                _ok("F3: Veste dell'Arcimago rigenera (1 energia / 5s, -1 carica)")

        # F4: Corazza di Fuoco — aura: tutti i nemici nel raggio prendono 1.
        # (Nemico vicino ADDOSSO al player: a 64px esatti sarebbe sul bordo
        # stretto del raggio — si usa la stessa cella del player.)
        _place_enemy(0, corridor_cells[0].x, corridor_cells[0].y)
        _place_enemy(1, corridor_cells[4].x, corridor_cells[4].y)  # lontano
        var hp_near: int = test_enemies[0].health
        var hp_far: int = test_enemies[1].health
        p.equip_relic_armor(C.RELIC_ARMORS[4])
        main._tick_fire_armor(p, 2000.0)
        if test_enemies[0].health != hp_near - 1:
                _fail("F4: l'aura non danneggia il nemico vicino")
        elif test_enemies[1].health != hp_far:
                _fail("F4: l'aura colpisce anche il nemico lontano?!")
        elif p.armor_charges() != 19:
                _fail("F4: la pulsazione non consuma carica")
        else:
                _ok("F4: Corazza di Fuoco — aura 1 danno ai nemici nel raggio")

        # F5: Corazza del Furore — attiva, potenzia il danno, si consuma.
        p.equip_relic_armor(C.RELIC_ARMORS[5])
        if not p.is_fury_active():
                _fail("F5: il Furore non risulta attivo dopo l'equip")
        else:
                p.current_weapon = {"type": C.WeaponType.PISTOL, "power": 1, "ammo": 15}
                p.last_dx = 1
                p.last_dy = 0
                p.projectiles.clear()
                p.shoot()
                if p.armor_charges() != 29:
                        _fail("F5: il Furore non consuma carica a colpo sparato")
                else:
                        _ok("F5: Corazza del Furore attiva + consumo a colpo")
        p.projectiles.clear()
        p.armor_relic = {}


# ============================================================================
# FASE G — boss room: infiniti, guardia arma, riflessione, SCHERMATA BONUS
# ============================================================================
func _phaseG_boss_room() -> void:
        var brp1: CharacterBody2D = boss_room.player
        var brp2: CharacterBody2D = boss_room.player2

        # G1: flag colpi infiniti attivo per entrambi in boss room.
        if not brp1.relic_infinite_shots or not brp2.relic_infinite_shots:
                _fail("G1: relic_infinite_shots non attivo in boss room")
        else:
                _ok("G1: boss room = colpi reliquia infiniti (P1 e P2)")

        # G2: l'arma reliquia NON viene potenziata/sovrascritta all'ingresso
        # (start_boss_fight la lascia intatta: power 3 e i colpi "shots" dello
        # Spadone — TASK 26: 33 dopo il +30% munizioni, letto dalla definizione).
        brp1.current_weapon = C.make_relic_weapon(C.RELIC_MELEE[0])
        boss_room.start_boss_fight(false)
        if int(brp1.current_weapon.get("type", 0)) != C.RelicType.SWORD:
                _fail("G2: l'arma reliquia è stata sovrascritta dalla regola d'ingresso")
        elif int(brp1.current_weapon.get("ammo", 0)) != int(C.RELIC_MELEE[0]["shots"]) \
                        or int(brp1.current_weapon.get("power", 0)) != 3:
                _fail("G2: la reliquia è stata alterata (power/ammo)")
        else:
                _ok("G2: la regola d'ingresso boss room NON tocca la reliquia")

        # G3: Scaglie del Drago in boss room — il colpo rimbalza VERSO IL BOSS.
        brp1.equip_relic_armor(C.RELIC_ARMORS[1])
        brp1.current_weapon = {"type": C.WeaponType.PISTOL, "power": 2, "ammo": 30}
        brp1.set_position_abs(400.0, 700.0)
        var bproj := ProjectileClass.new()
        bproj.position = brp1.get_pixel_pos()
        bproj.visible = true
        boss_room.boss_projectiles_node.add_child(bproj)
        var p1_bolts: int = brp1.projectiles.size()
        var boss_pos: Vector2 = boss_room.boss.pos
        boss_room._check_boss_projectiles_vs_player(brp1)
        if brp1.projectiles.size() != p1_bolts + 1:
                _fail("G3: nessun rimbalzo in boss room")
        else:
                var rb: Dictionary = brp1.projectiles[brp1.projectiles.size() - 1]
                var to_boss: Vector2 = (boss_pos - bproj.position).normalized()
                if int(rb.get("power", 0)) != 5:
                        _fail("G3: il rimbalzo non ha potenza 5 (miglior colpo)")
                elif rb.get("dir", Vector2.ZERO).dot(to_boss) < 0.9:
                        _fail("G3: il rimbalzo non punta al boss")
                elif brp1.armor_charges() != 3:
                        _fail("G3: carica Scaglie non consumata")
                else:
                        _ok("G3: Scaglie del Drago in boss room: rimbalzo verso il boss (power 5)")
        brp1.projectiles.clear()
        brp1.armor_relic = {}

        # G4: morte del boss -> SEQUENZA DI MORTE (Task 86) -> SCHERMATA BONUS.
        brp1.current_weapon = C.make_relic_weapon(C.RELIC_MELEE[0])
        brp2.visible = true
        boss_room.boss.take_damage(99999)
        boss_room._check_boss_death()
        # TASK 86: alla morte il controller avvia ora l'animazione per-tipo
        # (~2.4-2.8s in gioco) e le card compaiono SOLO a `finished`. Qui la
        # sequenza viene guidata a passi sincroni da 16ms fino alla fine,
        # poi il flusso originale apre la schermata bonus.
        var seq_guard: int = 0
        while boss_room._death_seq != null and seq_guard < 400:
                boss_room._death_seq.update(16.0)
                seq_guard += 1
        if not boss_room._bonus_active or boss_room._bonus_screen == null:
                _fail("G4: la schermata bonus non si è aperta dopo la sequenza di morte")
        else:
                _ok("G4: morte del boss -> sequenza morte -> schermata bonus (fight congelato)")

        # G5: offerta corretta + 2 choosers (2P, entrambi vivi).
        var screen = boss_room._bonus_screen
        if screen.choosers.size() != 2:
                _fail("G5: choosers = " + str(screen.choosers.size()) + ", attesi 2")
        elif screen.offerings.size() != 3:
                _fail("G5: offerte = " + str(screen.offerings.size()))
        else:
                var fams := {}
                for d in screen.offerings:
                        fams[d.get("family", "?")] = true
                if fams.size() != 3:
                        _fail("G5: offerte senza una-per-famiglia")
                else:
                        _ok("G5: 2P = 2 choosers; offerta 1-per-famiglia")

        # G6: le scelte si applicano (P1 arma, P2 armatura) e completano.
        # (Il gestore del controller resta scollegato: niente cambio scena.)
        if boss_room._bonus_screen.bonus_completed.is_connected(boss_room._on_bonus_completed):
                boss_room._bonus_screen.bonus_completed.disconnect(boss_room._on_bonus_completed)
        var completed_flag: Array = []
        boss_room._bonus_screen.bonus_completed.connect(
                        func(): completed_flag.append(true))
        var offer1: Array[Dictionary] = screen.offerings
        screen._apply_choice(offer1[1])  # P1 -> DISTANZA
        if int(brp1.current_weapon.get("type", 0)) != int(offer1[1]["type"]):
                _fail("G6: P1 non ha ricevuto la reliquia a distanza scelta")
        screen._apply_choice(offer1[2])  # P2 -> ARMATURA
        if not brp2.has_relic_armor() or brp2.armor_kind() != str(offer1[2]["kind"]):
                _fail("G6: P2 non ha ricevuto l'armatura scelta")
        if not completed_flag.size() > 0:
                _fail("G6: bonus_completed non emesso dopo le scelte")
        elif not screen.completed:
                _fail("G6: schermata non completata")
        else:
                _ok("G6: P1 sceglie l'arma, P2 l'armatura, schermata completata")

        # G7: il carry tra scene include reliquie e armature.
        GameManager.save_player_carry(brp1, brp2)
        var cp1: Dictionary = GameManager.carry_p1
        var cp2: Dictionary = GameManager.carry_p2
        if not cp1.has("relic_weapon") or int(cp1.get("relic_weapon", {}).get("type", 0)) != int(offer1[1]["type"]):
                _fail("G7: carry P1 senza l'arma reliquia scelta")
        elif not cp2.has("relic_armor") or cp2.get("relic_armor", {}).is_empty():
                _fail("G7: carry P2 senza l'armatura scelta")
        else:
                _ok("G7: il carry tra scene trasporta reliquia e armatura")

        # G8: il restore del carry riapplica l'arma reliquia su un player nuovo.
        brp1.current_weapon = {"type": C.WeaponType.PISTOL, "power": 1, "ammo": 15}
        brp1.armor_relic = {}
        GameManager.restore_player_carry(brp1, brp2)
        if int(brp1.current_weapon.get("type", 0)) != int(offer1[1]["type"]):
                _fail("G8: il restore del carry non ripristina l'arma reliquia")
        else:
                _ok("G8: restore del carry -> reliquia riapplicata")
