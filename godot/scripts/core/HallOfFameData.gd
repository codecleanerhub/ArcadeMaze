## HallOfFameData.gd - Persistenza della Hall of Fame (top 10 punteggi).
## ============================================================
## FIX (Hall of Fame): salvataggio/caricamento dei punteggi del gioco.
## I dati vivono in user://halloffame.json e sopravvivono alle sessioni.
##
## Formato file (JSON):
##   { "entries": [ {"name": "AAA", "score": 120000, "level": 9}, ... ] }
##
## Le voci sono ordinate per punteggio decrescente; vengono conservate solo
## le prime MAX_ENTRIES (10, stile arcade classico).
class_name HallOfFameData
extends RefCounted

const MAX_ENTRIES: int = 10
const SAVE_PATH: String = "user://halloffame.json"
const MAX_NAME_LENGTH: int = 8


## Carica tutte le voci salvate. Se il file non esiste (prima partita) o è
## corrotto, ritorna una lista vuota.
static func load_entries() -> Array:
        if not FileAccess.file_exists(SAVE_PATH):
                return []
        var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
        if f == null:
                return []
        var txt := f.get_as_text()
        f.close()
        var json := JSON.new()
        if json.parse(txt) != OK:
                return []
        var data: Variant = json.data
        if not data is Dictionary:
                return []
        var entries: Variant = data.get("entries", [])
        if not entries is Array:
                return []
        var out: Array = []
        for e in entries:
                if e is Dictionary and e.has("name") and e.has("score"):
                        out.append({
                                "name": str(e["name"]).substr(0, MAX_NAME_LENGTH),
                                "score": int(e["score"]),
                                "level": int(e.get("level", 1)),
                        })
        # Ordina per punteggio decrescente, poi per nome
        out.sort_custom(func(a, b):
                if int(a["score"]) != int(b["score"]):
                        return int(a["score"]) > int(b["score"])
                return str(a["name"]) < str(b["name"]))
        return out


## Aggiunge una voce e salva. Ritorna la posizione (1-based) in classifica,
## oppure -1 se il punteggio non è abbastanza alto per entrare nella top 10.
static func add_entry(player_name: String, score: int, level: int) -> int:
        if player_name.is_empty():
                player_name = "ANONYMOUS"
        var entries := load_entries()
        entries.append({
                "name": player_name.substr(0, MAX_NAME_LENGTH),
                "score": score,
                "level": level,
        })
        entries.sort_custom(func(a, b):
                if int(a["score"]) != int(b["score"]):
                        return int(a["score"]) > int(b["score"])
                return str(a["name"]) < str(b["name"]))
        var pos: int = -1
        for i in entries.size():
                if entries[i]["name"] == player_name.substr(0, MAX_NAME_LENGTH) \
                                and int(entries[i]["score"]) == score:
                        pos = i + 1
                        break
        if entries.size() > MAX_ENTRIES:
                entries.resize(MAX_ENTRIES)
        # Se la nuova voce è stata tagliata fuori, non è entrata in classifica
        if pos > MAX_ENTRIES:
                return -1
        save_entries(entries)
        return pos


## Salva la lista (già ordinata e troncata) su disco.
static func save_entries(entries: Array) -> void:
        var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
        if f == null:
                push_warning("HallOfFameData: impossibile salvare %s" % SAVE_PATH)
                return
        var data := {"entries": entries}
        f.store_string(JSON.stringify(data, "\t"))
        f.close()


## True se `score` basterebbe per entrare in classifica (usato per decidere
## se mostrare la tastiera di inserimento nome a fine partita).
static func qualifies(score: int) -> bool:
        var entries := load_entries()
        if entries.size() < MAX_ENTRIES:
                return true
        var last: int = int(entries[entries.size() - 1]["score"])
        return score > last
