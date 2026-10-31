## SaveSystem.gd — TASK 106 (SALVA PARTITA): slot di salvataggio su disco.
## ============================================================
## Autoload che gestisce fino a C.SAVE_SLOTS_MAX (10) slot, UNO PER RUN:
##   * dopo ogni boss vinto il gioco salva automaticamente (il BossRoom
##     sovrascrive SEMPRE lo slot della run corrente);
##   * una run nuova occupa il primo slot libero; se sono tutti pieni,
##     prima di salvare viene chiesto quale slot eliminare;
##   * la voce CONTINUA del menu principale elenca gli slot (data/ora,
##     livello di gioco, livello del player, tipo del player) e riprende
##     la run scelta.
## Persistenza: JSON in user://save_slots.json (pattern HallOfFameData:
## FileAccess + duplicate(true) per le copie profonde — niente riferimenti
## condivisi tra disco e GameManager.carry_*).
## Ogni slot:
##   { "slot": 0, "saved_at": "31/10/2026 18:30", "num_players": 1,
##     "game_mode": 0, "newgameplus_tier": 0, "current_level": 5,
##     "char1": 4, "char2": 1, "carry_p1": {...}, "carry_p2": {...} }
extends Node

const C = preload("res://scripts/core/GameConstants.gd")

const SAVE_PATH: String = "user://save_slots.json"
const SAVE_VERSION: int = 1

## Slot caricati dal disco (ordinati per indice). Solo i metodi di questa
## classe scrivono su disco: la RAM non può desincronizzarsi.
var _slots: Array = []


func _ready() -> void:
        _load_from_disk()


# ---------------------------------------------------------------------------
# API di lettura
# ---------------------------------------------------------------------------
func has_slots() -> bool:
        return not _slots.is_empty()


func slot_count() -> int:
        return _slots.size()


## Copia difensiva della lista (mai l'array interno).
func get_slots() -> Array:
        return _slots.duplicate(true)


## Dati completi dello slot (copia difensiva) o {} se inesistente.
func load_slot(slot: int) -> Dictionary:
        var found: Dictionary = _find(slot)
        if found.is_empty():
                return {}
        return found.duplicate(true)


## Primo slot libero (0..SAVE_SLOTS_MAX-1) o -1 se sono tutti occupati.
func first_free_slot() -> int:
        for i in C.SAVE_SLOTS_MAX:
                if _find(i).is_empty():
                        return i
        return -1


## Riga riassuntiva per la card CONTINUA: data/ora, livello di gioco,
## livello del player, tipo del player (nome localizzato I18n).
## Ritorna {} se lo slot non esiste.
func slot_summary(slot: int) -> Dictionary:
        var d: Dictionary = _find(slot)
        if d.is_empty():
                return {}
        var carry1: Dictionary = d.get("carry_p1", {})
        var names: Array = []
        var c1: int = int(d.get("char1", 0))
        var c2: int = int(d.get("char2", 0))
        names.append(_char_display_name(c1))
        if int(d.get("num_players", 1)) == 2:
                names.append(_char_display_name(c2))
        return {
                        "slot": slot,
                        "saved_at": str(d.get("saved_at", "")),
                        "game_level": int(d.get("current_level", 1)),
                        "player_level": int(carry1.get("level", 1)),
                        "char_names": names,
                        "num_players": int(d.get("num_players", 1)),
        }


## Sommari di TUTTI gli slot occupati (per la card).
func all_summaries() -> Array:
        var out: Array = []
        for d in _slots:
                out.append(slot_summary(int(d.get("slot", -1))))
        return out


# ---------------------------------------------------------------------------
# Scrittura
# ---------------------------------------------------------------------------
## Salva (o sovrascrive) lo slot con `data` (senza "slot"/"saved_at":
## li riempie qui — la data viene generata se non fornita, così i TEST
## possono passare date deterministiche). Ritorna true se scritto.
func save_run(slot: int, data: Dictionary) -> bool:
        slot = clampi(slot, 0, C.SAVE_SLOTS_MAX - 1)
        var rec: Dictionary = data.duplicate(true)
        rec["slot"] = slot
        if str(rec.get("saved_at", "")).is_empty():
                rec["saved_at"] = format_now()
        # Sostituisci lo slot esistente mantenendo l'ordine per indice.
        for i in _slots.size():
                if int(_slots[i].get("slot", -1)) == slot:
                        _slots[i] = rec
                        return _flush()
        _slots.append(rec)
        _slots.sort_custom(func(a, b): return int(a.get("slot", 0)) < int(b.get("slot", 0)))
        return _flush()


## Elimina lo slot dal disco.
func delete_slot(slot: int) -> void:
        for i in _slots.size():
                if int(_slots[i].get("slot", -1)) == slot:
                        _slots.remove_at(i)
                        _flush()
                        return


## Svuota TUTTI gli slot (uso: pulizia dei test automatici).
func clear_all() -> void:
        _slots.clear()
        _flush()


## Ricarica dal disco (uso: test dopo aver manipolato il file).
func reload_from_disk() -> void:
        _load_from_disk()


# ---------------------------------------------------------------------------
# Data/ora (formato europeo GG/MM/AAAA HH:MM, come richiesto: "data e ora")
# ---------------------------------------------------------------------------
static func format_now() -> String:
        var dt: Dictionary = Time.get_datetime_dict_from_system()
        return "%02d/%02d/%04d %02d:%02d" % [dt.day, dt.month, dt.year,
                        dt.hour, dt.minute]


# ---------------------------------------------------------------------------
# I/O su disco (pattern HallOfFameData)
# ---------------------------------------------------------------------------
func _load_from_disk() -> void:
        _slots.clear()
        if not FileAccess.file_exists(SAVE_PATH):
                return
        var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
        if f == null:
                return
        var raw: String = f.get_as_text()
        f.close()
        if raw.strip_edges().is_empty():
                return
        var parsed = JSON.parse_string(raw)
        if parsed is Dictionary:
                var arr: Array = (parsed as Dictionary).get("slots", [])
                for d in arr:
                        if d is Dictionary:
                                _slots.append((d as Dictionary).duplicate(true))
        _slots.sort_custom(func(a, b):
                        return int(a.get("slot", 0)) < int(b.get("slot", 0)))


func _flush() -> bool:
        var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
        if f == null:
                push_warning("[SaveSystem] impossibile scrivere " + SAVE_PATH)
                return false
        var doc: Dictionary = {"version": SAVE_VERSION, "slots": _slots}
        f.store_string(JSON.stringify(doc, "\t"))
        f.close()
        return true


func _find(slot: int) -> Dictionary:
        for d in _slots:
                if int(d.get("slot", -1)) == slot:
                        return d
        return {}


# ---------------------------------------------------------------------------
# Nomi personaggio localizzati (enum CharacterType -> I18n char.*)
# ---------------------------------------------------------------------------
static func _char_display_name(ct: int) -> String:
        if I18n == null:
                return "PLAYER %d" % (ct + 1)
        match ct:
                C.CharacterType.HERO_M:   return I18n.t("char.hero")
                C.CharacterType.HERO_F:   return I18n.t("char.heroine")
                C.CharacterType.MAGE:     return I18n.t("char.mage")
                C.CharacterType.ORC:      return I18n.t("char.orc")
                C.CharacterType.ELF:      return I18n.t("char.elf")
                C.CharacterType.KNIGHT:   return I18n.t("char.knight")
                C.CharacterType.GOLEM:    return I18n.t("char.golem")
                C.CharacterType.DRAGON:   return I18n.t("char.dragon")
                C.CharacterType.VAMPIRE:  return I18n.t("char.vampire")
        return I18n.t("char.hero")
