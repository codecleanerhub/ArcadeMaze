## test_task86_bossdeath.gd — TASK 86: test runtime delle animazioni di
## morte per-tipo dei boss (richiesta utente: "quando vengono uccisi, invece
## di far apparire subito le card delle armi bonus, prima mostra che il boss
## viene 'inghiottito' dal suolo... voragine con fiamme... vortice... per i
## boss di roccia sgretolamento in sassolini, per Dracula pipistrello+lampo,
## ecc. con suoni, animazioni, effetti ambientali").
##
## Check:
##   A — FAMILY_BY_TYPE copre TUTTI i 17 tipi di boss; ogni famiglia ha spec
##       (durata/tinta) valida
##   B — drive diretto della sequenza per OGNI tipo (0..16): begin() +
##       update() a passi da 16ms fino a fine: `finished` emesso, boss
##       nascosto, particelle spawnate, suoni sparati, timing esatto
##   C — integrazione controller (boss DEMON = famiglia hell, livello 8):
##       health=0 → la sequenza parte, le CARD DELLE RELIQUIE NON appaiono
##       subito (dopo ~1s ancora niente bonus), e compaiono DOPO la fine
##       dell'animazione (~2.8s+)
##   D — guardia sorgente: il controller usa la sequenza (preload, start,
##       update nel loop physics, reset trasformazioni a inizio fight)
extends Node

const BossRoomScene = preload("res://scenes/BossRoom.tscn")
const BossScript = preload("res://scripts/bosses/Boss.gd")
const BDS = preload("res://scripts/entities/BossDeathSequences.gd")
const C = preload("res://scripts/core/GameConstants.gd")

const CTRL_SRC := "res://scripts/core/BossRoomController.gd"
const BDS_SRC := "res://scripts/entities/BossDeathSequences.gd"

var fails: int = 0


func _ready() -> void:
        print("[TEST] TASK 86 — animazioni di morte dei boss")
        _test_maps()
        await _test_all_sequences()
        await _test_integration_hell()
        _test_fx_assets()
        _test_source_guards()
        if fails > 0:
                print("[TEST] ESITO: FALLITO (%d errori)" % fails)
                get_tree().quit(1)
        else:
                print("[TEST] ESITO: TUTTI PASSATI")
                get_tree().quit(0)


# --- A: mappe famiglie/tipi ---
func _test_maps() -> void:
        var types: Array = []
        for i in BossScript.BOSS_TYPE_COUNT:
                types.append(i)
        var mapped: Array = BDS.FAMILY_BY_TYPE.keys()
        if mapped.size() != types.size():
                print("[TEST] FALLITO A: FAMILY_BY_TYPE ha %d chiavi, attese %d" % [
                                mapped.size(), types.size()])
                fails += 1
                return
        var families: Dictionary = {}
        for t in types:
                if not mapped.has(t):
                        print("[TEST] FALLITO A: tipo boss %d non mappato" % t)
                        fails += 1
                        return
                var fam: String = BDS.FAMILY_BY_TYPE[t]
                families[fam] = true
                if not BDS.FAMILY_SPEC.has(fam):
                        print("[TEST] FALLITO A: famiglia '%s' senza spec" % fam)
                        fails += 1
                        return
                var spec: Dictionary = BDS.FAMILY_SPEC[fam]
                if float(spec.get("total", 0.0)) < 1000.0:
                        print("[TEST] FALLITO A: famiglia '%s' durata < 1s" % fam)
                        fails += 1
                        return
        print("[TEST] OK A: 17/17 tipi mappati su %d famiglie, spec valide" % (
                        families.size()))


# --- B: drive diretto per ogni tipo ---
func _test_all_sequences() -> void:
        var bad: Array = []
        for idx in BossScript.BOSS_TYPE_COUNT:
                # livello = idx*4 -> get_boss_index = idx (trucco 68->0)
                var level: int = 68 if idx == 0 else idx * 4
                var boss: Node2D = BossScript.new()
                add_child(boss)
                boss.setup(level, C.WINDOW_WIDTH, C.WINDOW_HEIGHT)
                boss.position = Vector2(C.WINDOW_WIDTH * 0.5, 500.0)
                var seq: Node2D = BDS.new()
                add_child(seq)
                var fired: Array = [false]
                seq.finished.connect(func() -> void: fired[0] = true)
                seq.begin(boss)
                var max_chunks: int = 0
                var safety: int = 0
                while not seq._done and safety < 600:
                        seq.update(16.0)
                        max_chunks = maxi(max_chunks, seq.chunks.size())
                        safety += 1
                var fam: String = seq.family
                var snd_count: int = seq._snd_fired.size()
                var elapsed_final: float = seq.elapsed_ms
                var ok: bool = fired[0] and boss.visible == false \
                                and max_chunks >= 5 and snd_count >= 1 \
                                and absf(elapsed_final - seq.total_ms) <= 20.0
                if not ok:
                        bad.append({"idx": idx, "fam": fam, "fired": fired[0],
                                        "visible": boss.visible,
                                        "chunks": max_chunks, "snd": snd_count,
                                        "t": elapsed_final, "tot": seq.total_ms})
                seq.queue_free()
                # reset trasformazioni per il tipo successivo
                boss.scale = Vector2.ONE
                boss.rotation = 0.0
                boss.modulate = Color.WHITE
                boss.visible = true
                boss.queue_free()
                await get_tree().physics_frame
        if bad.is_empty():
                print("[TEST] OK B: 17/17 sequenze complete (finished+hide+chunks+suoni+timing)")
        else:
                fails += 1
                print("[TEST] FALLITO B: %d sequenze incomplete:" % bad.size())
                for b in bad:
                        print("[TEST]   tipo %d (%s): fired=%s visible=%s chunks=%d snd=%d t=%.0f/%.0f" % [
                                        b["idx"], b["fam"], b["fired"], b["visible"],
                                        b["chunks"], b["snd"], b["t"], b["tot"]])


# --- C: integrazione controller — card DOPO l'animazione ---
func _test_integration_hell() -> void:
        # DEMON = tipo 2 = famiglia hell (voragine+fiamme+vortice), livello 8
        GameManager.current_level = 8
        GameManager.game_mode = C.GameMode.STORY
        GameManager.died_in_boss = false
        var room = BossRoomScene.instantiate()
        get_tree().root.add_child(room)
        # attesa boot room + start_boss_fight
        for i in 30:
                await get_tree().physics_frame
        if room.boss == null:
                print("[TEST] FALLITO C: boss non creato nella BossRoom")
                fails += 1
                room.queue_free()
                return
        room.boss.health = 0  # morte immediata
        # frames di attesa: la morte viene rilevata in _check_boss_death
        for i in 15:
                await get_tree().physics_frame
        if room._death_seq == null:
                print("[TEST] FALLITO C: sequenza non avviata dal controller")
                fails += 1
                room.queue_free()
                return
        print("[TEST] OK C1: sequenza avviata alla morte del boss (fam. hell)")
        # CARD NON DEVONO apparire subito: dopo ~60 frame (~1s) niente bonus
        for i in 60:
                await get_tree().physics_frame
        if room._bonus_active or room._bonus_screen != null:
                print("[TEST] FALLITO C2: card reliquie apparse DOPO ~1s (troppo presto!)")
                fails += 1
                room.queue_free()
                return
        print("[TEST] OK C2: a ~1s dalla morte le card NON sono ancora apparse")
        # attesa fine sequenza (hell = 2800ms + margine)
        var waited: int = 0
        while room._death_seq != null and waited < 600:
                await get_tree().physics_frame
                waited += 1
        for i in 20:
                await get_tree().physics_frame
        if room._bonus_active or room._bonus_screen != null:
                print("[TEST] OK C3: card reliquie apparse DOPO l'animazione (~%.1fs)" % (
                                float(waited) / 60.0))
        else:
                print("[TEST] FALLITO C3: card reliquie MAI apparse dopo la sequenza")
                fails += 1
        if room.boss.visible:
                print("[TEST] FALLITO C4: boss ancora visibile a fine sequenza")
                fails += 1
        else:
                print("[TEST] OK C4: boss nascosto a fine sequenza")
        room.queue_free()


# --- E: asset pixel-art PixelLab presenti e caricabili ---
func _test_fx_assets() -> void:
        var seq: Node2D = BDS.new()
        add_child(seq)
        var missing: Array = []
        for id in ["vortex", "bat", "crow", "rubble", "bones"]:
                for i in 4:
                        if seq._fx_frame(id, i) == null:
                                missing.append("%s/%d" % [id, i])
        seq.queue_free()
        if missing.is_empty():
                print("[TEST] OK E: 5 sheet pixel-art (5x4 frame) caricati da assets/sprites/env/")
        else:
                fails += 1
                print("[TEST] FALLITO E: frame mancanti: %s" % ", ".join(missing))


# --- D: guardie sul sorgente ---
func _test_source_guards() -> void:
        var ctrl: String = _read(CTRL_SRC)
        var checks: Array = [
                ["preload BossDeathSequences", "BossDeathSequenceClass = preload(\"res://scripts/entities/BossDeathSequences.gd\")"],
                ["avvio sequenza", "_start_boss_death_sequence()"],
                ["update nel loop physics", "_death_seq.update(delta_ms)"],
                ["flusso post-animazione", "_finish_boss_death(true)"],
                ["reset trasformazioni boss", "boss_node.scale = Vector2.ONE"],
        ]
        for ck in checks:
                if ctrl.find(ck[1]) < 0:
                        print("[TEST] FALLITO D: controller senza %s" % ck[0])
                        fails += 1
        var bds: String = _read(BDS_SRC)
        if bds.find("signal finished") < 0:
                print("[TEST] FALLITO D: sequenza senza segnale finished")
                fails += 1
        # i suoni usano costanti simboliche (non ID numerici grezzi)
        var re := RegEx.new()
        re.compile("_snd\\(\"[a-z_0-9%]+\",\\s*\\d")
        if re.search(bds) != null:
                print("[TEST] FALLITO D: _snd con ID numerico grezzo (attese costanti simboliche)")
                fails += 1
        if fails == 0 or true:
                if ctrl.find("_start_boss_death_sequence()") >= 0 \
                                and bds.find("signal finished") >= 0:
                        print("[TEST] OK D: guardie sorgente controller+sequenza presenti")


func _read(path: String) -> String:
        var f := FileAccess.open(path, FileAccess.READ)
        if f == null:
                return ""
        var txt := f.get_as_text()
        f.close()
        return txt
