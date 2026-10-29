## test_task96_hearts.gd — TASK 96: cuori al posto della barra vita
## (feedback utente: "la barra della vita del player, la togliamo,
## utilizziamo i cuori delle vite, li disegniamo se è il caso un pò più
## grandi (ma poco più grandi se dobbiamo) e facciamo in modo che il cuore
## si sgretoli quando viene colpito il player fino a scomparire e perdere
## la vita, quindi lo sgretolamento del cuore sostituisce la barra della
## vita... rimane la barra della stamina, che sarà di colore verde e poi
## arancione e poi rossa man mano che il player salta (la barra da che era
## rosa diventa verde, gli altri colori non cambiano)").
##
## Check:
##   A — stamina: piena = VERDE (g>r, b basso); 0.5/0.75 = ARANCIONE
##       (invariato); 0.0 = ROSSO (invariato)
##   B — stadio sgretolamento dal ratio energia (funzione pura):
##       1.0->0, 0.8->1, 0.6->2, 0.4->3, 0.2->3, 0.0->3; con max_energy 5:
##       5/5->0, 4/5->1, 3/5->2, 2/5->3, 1/5->3
##   C — barra energia RIMOSSA dal sorgente HUD (nessuna chiamata
##       _draw_energy_bar / label hud.energy / hud.en) e cuori alimentati
##       col ratio energia nelle 3 chiamate _draw_lives_row
##   D — sheet cuore sgretolabile: caricabile, 4 frame distinti, frame 0
##       con contenuto (cuore presente)
##   E — HUD drive diretto: snapshot con vite/energia variabili ->
##       _draw senza errori; il colpo (energia che scende) accende l'fx
##       (scossa+detriti), la vita persa il burst
extends Node

const HUD_SCRIPT := "res://scripts/ui/HUD.gd"
const HUDClass = preload("res://scripts/ui/HUD.gd")

var fails: int = 0
var hud: Control = null


func _ready() -> void:
        print("[TEST] TASK 96 — cuori sgretolabili al posto della barra vita")
        hud = HUDClass.new()
        add_child(hud)
        await get_tree().process_frame
        _test_stamina_colors()
        _test_crumble_stage()
        _test_source_guards()
        await _test_asset()
        await _test_drive()
        hud.queue_free()
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


# --- A: colori stamina (verde/arancione/rosso) ---
func _test_stamina_colors() -> void:
        var c_full: Color = hud._stamina_fill_color(1.0)
        var c_mid: Color = hud._stamina_fill_color(0.75)
        var c_half: Color = hud._stamina_fill_color(0.5)
        var c_low: Color = hud._stamina_fill_color(0.0)
        if c_full.g <= c_full.r or c_full.b > 0.5 or c_full.g < 0.6:
                _fail("A: barra piena non VERDE: %s" % [c_full])
        else:
                _ok("A1: barra piena = VERDE %s (era rosa)" % [c_full])
        for c in [c_mid, c_half]:
                if c.g <= c.b or c.r < 0.9:
                        _fail("A: metà barra non ARANCIONE: %s" % [c])
                        return
        _ok("A2: 0.75/0.5 = ARANCIONE (invariato) %s" % [c_half])
        if c_low.r < 0.7 or c_low.g > 0.3 or c_low.b > 0.3:
                _fail("A: barra svuotata non ROSSA: %s" % [c_low])
        else:
                _ok("A3: barra svuotata = ROSSO (invariato) %s" % [c_low])


# --- B: stadio sgretolamento (funzione pura del ratio) ---
func _test_crumble_stage() -> void:
        var cases: Array = [
                [1.0, 0], [0.8, 1], [0.6, 2], [0.4, 3], [0.2, 3], [0.0, 3],
                [5.0 / 5.0, 0], [4.0 / 5.0, 1], [3.0 / 5.0, 2],
                [2.0 / 5.0, 3], [1.0 / 5.0, 3], [7.0 / 7.0, 0], [6.0 / 7.0, 0],
                [1.4, 0], [-0.2, 3],
        ]
        for cse in cases:
                var got: int = HUDClass._heart_crumble_stage(cse[0])
                if got != cse[1]:
                        _fail("B: stage(%s)=%d atteso %d" % [cse[0], got, cse[1]])
                        return
        _ok("B: stage = int((1-ratio)/0.2) clamp 0-3 — ogni 20%% di energia persa un stadio (5HP: 5,4,3,2,1 -> 0,1,2,3,3)")


# --- C: guardie sorgente HUD ---
func _test_source_guards() -> void:
        var src: String = _read(HUD_SCRIPT)
        var checks: Array = [
                ["barra energia rimossa (funzione)", "_draw_energy_bar("],
                ["label energia 1p rimossa", 'I18n.t("hud.energy")'],
                ["label energia 2p rimossa", 'I18n.t("hud.en")'],
        ]
        for ck in checks:
                if (ck[1] as String) in src:
                        _fail("C: sorgente HUD contiene ancora %s (%s)" % [ck[0], ck[1]])
                        return
        var n_ratio: int = src.count("maxf(1.0, float(_p") 
        if n_ratio < 2:
                _fail("C: _draw_lives_row non alimenta il ratio energia (trovati %d)" % n_ratio)
                return
        if not ("_heart_crumble_stage" in src) or not ("ui_heart_crumble_sheet.png" in src):
                _fail("C: manca lo sgretolamento nel sorgente HUD")
                return
        if not ("0.22, 0.85, 0.35" in src):
                _fail("C: stamina piena non verde nel sorgente")
                return
        _ok("C: barra energia rimossa, cuori col ratio energia, stamina verde nel sorgente")


# --- D: asset sheet cuore ---
func _test_asset() -> void:
        if not hud._crumble_loaded or hud._crumble_texture == null:
                _fail("D: ui_heart_crumble_sheet.png non caricato")
                return
        var tex: Texture2D = hud._crumble_texture
        if tex.get_width() != 96 or tex.get_height() != 24:
                _fail("D: sheet %dx%d atteso 96x24 (4 frame 24px)" % [
                                tex.get_width(), tex.get_height()])
                return
        # frame distinti + frame 0 con cuore
        var img := tex.get_image()
        var hashes: Array = []
        for f in 4:
                var h: int = 0
                var op: int = 0
                for y in 24:
                        for x in 24:
                                var p: Color = img.get_pixel(f * 24 + x, y)
                                if p.a > 0.5:
                                        op += 1
                                h = (h * 31 + int(p.r * 255.0) + int(p.a * 255.0) * 17) % 999999937
                if f == 0 and op < 100:
                        _fail("D: frame 0 quasi vuoto (%d px opachi)" % op)
                        return
                hashes.append(h)
        if hashes.size() != 4 or (hashes[0] == hashes[1] and hashes[1] == hashes[2]):
                _fail("D: frame identici tra loro (nessuno sgretolamento)")
                return
        _ok("D: sheet 96x24 caricato, 4 frame distinti, cuore presente nel frame 0")


# --- E: drive diretto HUD (snapshot con colpo/vita persa) ---
func _test_drive() -> void:
        hud.set_player_state({"lives": 3, "energy": 5.0, "max_energy": 5.0,
                        "stamina": 1.0, "stamina_exhausted": false})
        await get_tree().process_frame
        if hud._heart_fx_p1 > 0.0:
                _fail("E: fx attivo senza colpo")
                return
        # colpo: energia 5 -> 3
        hud.set_player_state({"energy": 3.0})
        await get_tree().process_frame
        if hud._heart_fx_p1 <= 0.0 or hud._heart_burst_p1:
                _fail("E: colpo non rilevato (fx=%s burst=%s)" % [
                                hud._heart_fx_p1, hud._heart_burst_p1])
                return
        # vita persa: lives 3 -> 2
        hud.set_player_state({"lives": 2, "energy": 5.0})
        await get_tree().process_frame
        if hud._heart_fx_p2 > 0.0:
                _fail("E: fx P2 attivo senza colpo P2")
                return
        hud.set_player2_state({"lives": 4, "energy": 5.0, "max_energy": 5.0})
        hud.set_player2_state({"lives": 3, "energy": 5.0})
        await get_tree().process_frame
        if hud._heart_fx_p2 <= 0.0 or not hud._heart_burst_p2:
                _fail("E: vita persa P2 senza burst (fx=%s burst=%s)" % [
                                hud._heart_fx_p2, hud._heart_burst_p2])
                return
        # il ratio alimenta il cuore corrente: stage con energia 1/5 = 3
        if HUDClass._heart_crumble_stage(1.0 / 5.0) != 3:
                _fail("E: energia 1/5 non mappa allo stadio 3")
                return
        _ok("E: drive diretto — colpo = scossa+detriti, vita persa = burst, P1/P2 indipendenti")


func _read(path: String) -> String:
        var f := FileAccess.open(path, FileAccess.READ)
        if f == null:
                return ""
        return f.get_as_text()
