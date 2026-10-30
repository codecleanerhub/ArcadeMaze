#!/usr/bin/env python3
"""Estrazione inventario testi — Arcade Maze Fantasy (Godot 4.7.2).

Recovery Task R1 (reset totale sandbox 31/10/2026): ricrea l'inventario dei
testi per la revisione linguistica (l'originale del Task 103 e' andato perso
insieme agli script agent). Le fonti sono TUTTE nel repo:

  - godot/scripts/core/I18nManager.gd   TEXTS (chiavi flat "sezione.chiave", en/it)
  - godot/scripts/core/GameConstants.gd SKILL_DEFS, RELIC_MELEE, RELIC_RANGED,
                                        RELIC_ARMORS, ELEMENTAL_WEAPONS,
                                        get_weapon_name()
  - godot/scripts/bosses/Boss.gd        get_boss_name() (17 boss, bilingue)
  - stringhe hardcoded note (GAME OVER, footer menu, crediti, P1/P2)
  - PNG testuali (assets/ui/, assets/loading/)

Output: JSON con entries {sheet, rif, it, en, dove, pos, note} + statistiche.
Il verdetto va controllato sulle statistiche stampate (conteggi attesi:
TEXTS=291, boss=17, armi base=5, skill=8, reliquie=6+6+6).

Uso:
  python3 extract_game_texts.py [--repo /path/to/ArcadeMaze] [--out game_texts.json]
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from datetime import date

# ---------------------------------------------------------------- costanti --

SHEET_BY_PREFIX = {
    "menu": "Menu", "mode": "Menu",
    "char": "Selezione", "select": "Selezione",
    "intro": "Intro",
    "hud": "HUD-pausa", "pause": "HUD-pausa",
    "levelup": "Level Up",
    "win": "Fine partita", "lose": "Fine partita", "screen": "Fine partita",
    "cont": "Fine partita", "hof": "Fine partita", "ne": "Fine partita",
    "bonus": "Bonus reliquie",
    "bonuscard": "Card bonus",
    "enemy": "Nemici-Boss", "boss": "Nemici-Boss", "weakness": "Nemici-Boss",
    "cr": "Crediti",
    "joy": "Altro", "demo": "Altro", "loading": "Altro", "misc": "Altro",
}

DOVE_BY_PREFIX = {
    "menu": "Menu principale / sottomenu OPTIONS",
    "mode": "Menu principale — voce MODALITA'",
    "char": "Ruota personaggi (menu, demo, SelectPlayer)",
    "select": "Selezione personaggio (P1 e P2)",
    "joy": "Configurazione joystick (ConfigJoy)",
    "intro": "Intro cutscene (didascalie)",
    "hud": "HUD di gioco",
    "pause": "Overlay di pausa",
    "levelup": "Level Up — annuncio e modale abilita'",
    "win": "Schermata di vittoria",
    "lose": "Schermata di sconfitta",
    "screen": "Schermate di fine partita (hint di ritorno)",
    "cont": "Overlay CONTINUE / schermata continue",
    "hof": "Hall of Fame",
    "ne": "Inserimento nome (nuovo record)",
    "bonus": "Schermata bonus — scelta reliquia",
    "bonuscard": "Card bonus (prima raccolta reliquia)",
    "enemy": "Nemici (nomi/UI)",
    "boss": "Banner stanza boss",
    "weakness": "Boss room — colpo sulla debolezza",
    "cr": "Crediti (sezioni e ruoli)",
    "demo": "Overlay demo mode",
    "loading": "Loading screen",
    "misc": "Testi vari",
}

KNOWN_NOTES = {
    "hud.energy": "Chiave orfana: barra ENERGIA rimossa (HUD a cuori, Task 96)",
    "hud.en": "Chiave orfana: barra ENERGIA rimossa (HUD a cuori, Task 96)",
    "menu.lang_english": "Chiave orfana documentata (Task 103)",
    "menu.lang_italian": "Chiave orfana documentata (Task 103)",
    "enemy.generic": "Chiave orfana documentata (Task 103)",
    "cr.title": "Chiave orfana documentata (Task 103)",
}

HARDCODED = [
    # (sheet, rif, it, en, dove, pos, note)
    ("Fine partita", "LoseScreen 'GAME OVER'", "GAME OVER", "GAME OVER",
     "Schermata di sconfitta — titolo",
     "scripts/ui/LoseScreen.gd:233",
     "HARDCODED: non passa da I18n (anomalia Task 103); resta in inglese anche in IT"),
    ("Menu", "MainMenu footer 'By'", "By", "By",
     "Menu principale — footer (riga superiore)",
     "scripts/ui/MainMenu.gd:610",
     "HARDCODED: non passa da I18n"),
    ("Menu", "MainMenu footer 'Marled Software'", "Marled Software", "Marled Software",
     "Menu principale — footer (editore)",
     "scripts/ui/MainMenu.gd:629",
     "HARDCODED: non passa da I18n"),
    ("Crediti", "CreditsScreen ruoli 'Luca A. Greco'", "Luca A. Greco", "Luca A. Greco",
     "Crediti — nome accreditato su OGNI ruolo (scherzoso)",
     "scripts/ui/CreditsScreen.gd:229",
     "HARDCODED: non passa da I18n (anomalia Task 103)"),
    ("Crediti", "CreditsScreen publisher 'Marled Software'", "Marled Software", "Marled Software",
     "Crediti — PUBLISHED BY + chiusura scroll",
     "scripts/ui/CreditsScreen.gd:221 e :323",
     "HARDCODED: non passa da I18n (anomalia Task 103)"),
    ("HUD-pausa", "HUD 2P 'P1'", "P1", "P1",
     "HUD 2P — etichetta giocatore 1",
     "scripts/ui/HUD.gd:405",
     "HARDCODED: non passa da I18n (anomalia Task 103)"),
    ("HUD-pausa", "HUD 2P 'P2'", "P2", "P2",
     "HUD 2P — etichetta giocatore 2",
     "scripts/ui/HUD.gd:430",
     "HARDCODED: non passa da I18n (anomalia Task 103)"),
]

IMAGES = [
    # (percorso, descrizione_it, dove, hint_uso_manuale)
    ("assets/ui/title_logo.png", "ARCADE MAZE FANTASY (logo)", "Menu principale — logo", None),
    ("assets/ui/header_options.png", "OPTIONS (EN)", "OPTIONS — header inglese", None),
    ("assets/ui/header_options_it.png", "IMPOSTAZIONI (IT)", "OPTIONS — header italiano", None),
    ("assets/ui/header_halloffame.png", "HALL OF FAME", "Hall of Fame — header", None),
    ("assets/ui/header_credits.png", "CREDITS", "Crediti — header (orfano?)", None),
    ("assets/ui/header_gameover.png", "GAME OVER", "Game over — header (orfano?)", None),
    ("assets/ui/header_relic.png", "RELIQUIA", "Reliquia — header (orfano?)", None),
    ("assets/loading/loading_text_en.png", "Loading... (EN)", "Loading — testo inglese",
     "assets/loading/loading_meta.json (chiave file) — caricato dinamicamente da LoadingScreen.gd"),
    ("assets/loading/loading_text_it.png", "Caricamento... (IT)", "Loading — testo italiano",
     "assets/loading/loading_meta.json (chiave file) — caricato dinamicamente da LoadingScreen.gd"),
]

# ------------------------------------------------------------------ parsing --

def unescape_gd(s: str) -> str:
    out = []
    i = 0
    while i < len(s):
        c = s[i]
        if c == "\\" and i + 1 < len(s):
            n = s[i + 1]
            if n == "n":
                out.append("\n")
            elif n == "t":
                out.append("\t")
            elif n == '"':
                out.append('"')
            elif n == "'":
                out.append("'")
            elif n == "\\":
                out.append("\\")
            else:
                out.append("\\" + n)
            i += 2
        else:
            out.append(c)
            i += 1
    return "".join(out)


def skip_ws_comments(text: str, pos: int) -> int:
    while pos < len(text):
        c = text[pos]
        if c in " \t\r\n":
            pos += 1
        elif c == "#":
            while pos < len(text) and text[pos] != "\n":
                pos += 1
        else:
            break
    return pos


NUM_RE = re.compile(r"-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?")
IDENT_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+)*")


def parse_gd_value(text: str, pos: int):
    """Parser tollerante di literal GDScript (dict/array/string/numero/enum/Color).
    Ritorna (valore, nuova_pos). I valori non-stringa diventano stringhe '@...'."""
    pos = skip_ws_comments(text, pos)
    c = text[pos]
    if c == '"':
        pos += 1
        buf = []
        while text[pos] != '"':
            if text[pos] == "\\":
                buf.append(text[pos:pos + 2])
                pos += 2
            else:
                buf.append(text[pos])
                pos += 1
        pos += 1
        val = unescape_gd("".join(buf))
        p2 = skip_ws_comments(text, pos)
        if p2 < len(text) and text[p2] == "+":  # concatenazione "a" + "b"
            nxt, pos2 = parse_gd_value(text, p2 + 1)
            return val + nxt, pos2
        return val, pos
    if c == "{":
        pos += 1
        d = {}
        while True:
            pos = skip_ws_comments(text, pos)
            if text[pos] == "}":
                pos += 1
                break
            k, pos = parse_gd_value(text, pos)
            pos = skip_ws_comments(text, pos)
            if text[pos] != ":":
                raise ValueError(f"atteso ':' a offset {pos}: {text[pos:pos+40]!r}")
            v, pos = parse_gd_value(text, pos + 1)
            d[k] = v
            pos = skip_ws_comments(text, pos)
            if pos < len(text) and text[pos] == ",":
                pos += 1
        return d, pos
    if c == "[":
        pos += 1
        lst = []
        while True:
            pos = skip_ws_comments(text, pos)
            if text[pos] == "]":
                pos += 1
                break
            v, pos = parse_gd_value(text, pos)
            lst.append(v)
            pos = skip_ws_comments(text, pos)
            if pos < len(text) and text[pos] == ",":
                pos += 1
        return lst, pos
    m = NUM_RE.match(text, pos)
    if m and (c == "-" or c.isdigit()):
        tok = m.group(0)
        pos = m.end()
        return (float(tok) if "." in tok or "e" in tok.lower() else int(tok)), pos
    m = IDENT_RE.match(text, pos)
    if not m:
        raise ValueError(f"token inatteso a offset {pos}: {text[pos:pos+40]!r}")
    tok = m.group(0)
    pos = m.end()
    p2 = skip_ws_comments(text, pos)
    if p2 < len(text) and text[p2] == "(":  # es. Color(0.8, 0.2, 0.3)
        depth = 1
        pos = p2 + 1
        while depth > 0:
            if text[pos] == "(":
                depth += 1
            elif text[pos] == ")":
                depth -= 1
            pos += 1
        return "@call:" + tok, pos
    if tok == "true":
        return True, pos
    if tok == "false":
        return False, pos
    if tok == "null":
        return None, pos
    return "@ident:" + tok, pos


def extract_block(text: str, const_name: str):
    """Ritorna (blocco, offset_assoluto_inizio_blocco) di `const NAME ... = {/[`."""
    m = re.search(r"^const %s\b[^\n]*?=\s*([\[{])" % re.escape(const_name),
                  text, re.M)
    if not m:
        raise ValueError(f"const {const_name} non trovato")
    open_ch = m.group(1)
    close_ch = "}" if open_ch == "{" else "]"
    start = m.end()
    pos = start
    depth = 1
    while depth > 0:
        c = text[pos]
        if c == '"':
            pos += 1
            while text[pos] != '"':
                if text[pos] == "\\":
                    pos += 1
                pos += 1
        elif c == "#":
            while text[pos] != "\n":
                pos += 1
        elif c == open_ch:
            depth += 1
        elif c == close_ch:
            depth -= 1
        pos += 1
    return text[start:pos - 1], start


def parse_texts(text: str):
    """TEXTS di I18nManager.gd -> [(key, en, it, linea)]."""
    m = re.search(r"^const TEXTS: Dictionary = \{", text, re.M)
    if not m:
        raise ValueError("const TEXTS non trovato")
    start = m.end()
    end = text.find("\n}", start)
    region = text[start:end]
    entry_re = re.compile(r'"((?:[^"\\]|\\.)*)"\s*:\s*\{(.*?)\}', re.S)
    entries = []
    for em in entry_re.finditer(region):
        key = unescape_gd(em.group(1))
        inner = em.group(2)
        en = extract_lang(inner, "en")
        it = extract_lang(inner, "it")
        line = text.count("\n", 0, start + em.start()) + 1
        entries.append((key, en, it, line))
    return entries


def extract_lang(inner: str, lang: str):
    m = re.search(r'"%s"\s*:\s*((?:\s*"(?:[^"\\]|\\.)*"\s*\+?\s*)+)' % lang, inner)
    if not m:
        return None
    parts = re.findall(r'"((?:[^"\\]|\\.)*)"', m.group(1))
    return "".join(unescape_gd(p) for p in parts)


def line_of(text: str, needle: str):
    i = text.find(needle)
    return None if i < 0 else text.count("\n", 0, i) + 1


def parse_match_names(text: str, enum_prefix: str, allow_single: bool):
    """Rami `Enum.VALUE: return "IT" if it else "EN"` (o solo return "X")."""
    pat = re.compile(
        r"%s\.(\w+):\s*\n?\s*return\s+" % enum_prefix
        + r'"((?:[^"\\]|\\.)*)"'
        + (r'(?:\s+if\s+it\s+else\s+"((?:[^"\\]|\\.)*)")?' if allow_single else
           r'\s+if\s+it\s+else\s+"((?:[^"\\]|\\.)*)"'))
    out = []
    for m in pat.finditer(text):
        it_txt = m.group(2)
        en_txt = m.group(3) if m.group(3) is not None else m.group(2)
        line = text.count("\n", 0, m.start()) + 1
        out.append((m.group(1), it_txt, en_txt, line))
    return out


# -------------------------------------------------------------------- main --

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    here = os.path.dirname(os.path.abspath(__file__))
    candidates = []
    parent = os.path.dirname(here)
    if os.path.isdir(os.path.join(parent, "godot")):
        candidates.append(parent)
    candidates.append("/home/z/my-project/ArcadeMaze")
    ap.add_argument("--repo", default=candidates[0])
    ap.add_argument("--out", default=os.path.join(here, "game_texts.json"))
    args = ap.parse_args()

    repo = os.path.abspath(args.repo)
    gd_dir = os.path.join(repo, "godot", "scripts")
    i18n_path = os.path.join(gd_dir, "core", "I18nManager.gd")
    gc_path = os.path.join(gd_dir, "core", "GameConstants.gd")
    boss_path = os.path.join(gd_dir, "bosses", "Boss.gd")
    for p in (i18n_path, gc_path, boss_path):
        if not os.path.isfile(p):
            print(f"ERRORE: manca {p}", file=sys.stderr)
            return 2

    i18n_text = open(i18n_path, encoding="utf-8").read()
    gc_text = open(gc_path, encoding="utf-8").read()
    boss_text = open(boss_path, encoding="utf-8").read()

    # indice dei file .gd per la ricerca utilizzi (esclude I18nManager)
    usage_files = []
    for root, _dirs, fnames in os.walk(gd_dir):
        for fn in sorted(fnames):
            if fn.endswith(".gd") and "I18nManager" not in fn:
                full = os.path.join(root, fn)
                rel = os.path.relpath(full, os.path.join(repo, "godot"))
                usage_files.append((rel, open(full, encoding="utf-8").read()))

    def find_usages(quoted_needle: str, limit: int = 2):
        hits = []
        for rel, txt in usage_files:
            start = 0
            while True:
                i = txt.find(quoted_needle, start)
                if i < 0:
                    break
                hits.append(f"{rel}:{txt.count(chr(10), 0, i) + 1}")
                start = i + 1
                if len(hits) >= limit:
                    return hits
        return hits

    entries = []
    warnings = []

    def add(sheet, rif, it, en, dove, pos, note=""):
        entries.append({"sheet": sheet, "rif": rif, "it": it, "en": en,
                        "dove": dove, "pos": pos, "note": note})

    # ---------------------------------------------------------- 1) TEXTS --
    texts = parse_texts(i18n_text)
    if len(texts) != 291:
        warnings.append(f"TEXTS: trovate {len(texts)} chiavi (attese 291)")
    for key, en, it, line in texts:
        prefix = key.split(".")[0]
        sheet = SHEET_BY_PREFIX.get(prefix)
        if sheet is None:
            sheet = "Altro"
            warnings.append(f"prefisso non mappato: '{prefix}' (chiave {key}) -> Altro")
        dove = DOVE_BY_PREFIX.get(prefix, "Varie")
        pos = f"scripts/core/I18nManager.gd:{line}"
        usages = find_usages(f'"{key}"')
        if usages:
            pos += " · uso: " + ", ".join(usages)
        else:
            pos += " (nessun uso trovato)"
        note = KNOWN_NOTES.get(key, "")
        if not note and not usages:
            note = "Chiave non richiamata nel codice (possibile orfana)"
        if prefix == "boss" and not note:
            note = ("Doppia definizione: la fonte REALE dei nomi boss a schermo "
                    "e' Boss.get_boss_name() (Boss.gd)")
        if it is None or en is None:
            warnings.append(f"TEXTS {key}: manca en o it")
        add(sheet, key, it if it is not None else "(manca)",
            en if en is not None else "(manca)", dove, pos, note)

    # ------------------------------------------------------ 2) SKILL_DEFS --
    block, _ = extract_block(gc_text, "SKILL_DEFS")
    # il blocco e' il CONTENUTO del dict: riapriamo le parentesi
    skills, _ = parse_gd_value("{" + block + "}", 0)
    if len(skills) != 8:
        warnings.append(f"SKILL_DEFS: {len(skills)} skill (attese 8)")
    for skill_id, sd in skills.items():
        base_line = line_of(gc_text, f'"{skill_id}": {{')
        for field, dove in (("name", "nome abilita'"), ("desc", "descrizione")):
            it_v = sd.get(f"{field}_it")
            en_v = sd.get(f"{field}_en")
            add("Level Up", f"SKILL_DEFS.{skill_id}.{field}",
                it_v if it_v is not None else "(manca)",
                en_v if en_v is not None else "(manca)",
                f"Modale Level Up — {dove}",
                f"scripts/core/GameConstants.gd:{base_line}")

    # --------------------------------------------------- 3) armi base ------
    # limita i rami match alla funzione get_weapon_name (con offset righe assoluto)
    gwn_start = gc_text.find("static func get_weapon_name")
    gwn = gc_text[gwn_start:gc_text.find("static func get_weapon_color")]
    weapons = parse_match_names(gwn, "WeaponType", allow_single=True)
    gwn_line0 = gc_text.count("\n", 0, gwn_start)
    if len(weapons) != 5:
        warnings.append(f"get_weapon_name: {len(weapons)} armi (attese 5)")
    for wtype, it_v, en_v, line in weapons:
        add("Armi", f"get_weapon_name({wtype})", it_v, en_v,
            "HUD — nome arma corrente",
            f"scripts/core/GameConstants.gd:{gwn_line0 + line}",
            "Bilingue via ui_is_italian()")

    # --------------------------------------------- 4) ELEMENTAL_WEAPONS ---
    block, _ = extract_block(gc_text, "ELEMENTAL_WEAPONS")
    elementals, _ = parse_gd_value("[" + block + "]", 0)
    for wd in elementals:
        wid = wd.get("id", "?")
        line = line_of(gc_text, f'"id": "{wid}"')
        for field, dove, nota in (
                ("name", "nome arma", "Nome MAI mostrato a schermo (anomalia Task 103)"),
                ("short", "nome corto", "Short MAI mostrato a schermo (anomalia Task 103)"),
                ("desc", "descrizione", "Descrizione MAI mostrata a schermo (anomalia Task 103)")):
            it_v, en_v = wd.get(field), wd.get(f"{field}_en")
            if it_v is None and en_v is None:
                continue
            add("Armi", f"ELEMENTAL_WEAPONS.{wid}.{field}",
                it_v if it_v is not None else "(manca)",
                en_v if en_v is not None else "(manca)",
                f"Armi elementali per archetipo (Task 61) — {dove}",
                f"scripts/core/GameConstants.gd:{line}", nota)

    # -------------------------------------------------- 5) reliquie --------
    relic_blocks = [("RELIC_MELEE", "Bonus reliquie", "mischia"),
                    ("RELIC_RANGED", "Bonus reliquie", "distanza"),
                    ("RELIC_ARMORS", "Armature", "armatura")]
    relic_count = 0
    for const_name, sheet, famiglia in relic_blocks:
        block, _ = extract_block(gc_text, const_name)
        relics, _ = parse_gd_value("[" + block + "]", 0)
        relic_count += len(relics)
        for rd in relics:
            rid = rd.get("id", "?")
            line = line_of(gc_text, f'"id": "{rid}"')
            for field, dove, nota in (
                    ("name", "nome reliquia", ""),
                    ("short", "nome corto",
                     "Short reliquia MAI mostrato a schermo (anomalia Task 103)"),
                    ("desc", "descrizione", "")):
                it_v, en_v = rd.get(field), rd.get(f"{field}_en")
                if it_v is None and en_v is None:
                    continue
                add(sheet, f"{const_name}.{rid}.{field}",
                    it_v if it_v is not None else "(manca)",
                    en_v if en_v is not None else "(manca)",
                    f"Schermata bonus post-boss ({famiglia}) — {dove}",
                    f"scripts/core/GameConstants.gd:{line}", nota)
    if relic_count != 18:
        warnings.append(f"Reliquie: {relic_count} (attese 18: 6+6+6)")

    # ---------------------------------------------------- 6) nomi boss -----
    bosses = parse_match_names(boss_text, "Type", allow_single=False)
    if len(bosses) != 17:
        warnings.append(f"get_boss_name: {len(bosses)} boss (attesi 17)")
    for btype, it_v, en_v, line in bosses:
        add("Nemici-Boss", f"get_boss_name({btype})", it_v, en_v,
            "Boss room — banner nome boss",
            f"scripts/bosses/Boss.gd:{line}",
            "Fonte REALE dei nomi boss (le chiavi boss.* di TEXTS non sono usate)")

    # ------------------------------------------------ 7) hardcoded --------
    for sheet, rif, it_v, en_v, dove, pos, note in HARDCODED:
        add(sheet, rif, it_v, en_v, dove, pos, note)

    # ----------------------------------------------------- 8) immagini ----
    for path, desc, dove, hint in IMAGES:
        full = os.path.join(repo, "godot", path)
        exists = os.path.isfile(full)
        stem = os.path.splitext(os.path.basename(path))[0]
        usages = []
        for needle in (f'"res://{path}"', f"res://{path}", f'"{stem}"',
                       f'"{stem}', f"'{stem}", stem):
            usages = find_usages(needle, limit=3)
            if usages:
                break
        note = "PNG testuale: per cambiarlo serve RIGENERARE l'immagine, non modificare testo"
        if hint:
            pos = f"{path} · uso: {hint}"
        elif usages:
            pos = f"{path} · uso: " + ", ".join(usages)
        else:
            pos = path
            note += " — NON referenziato dal codice (PNG orfano)"
        if not exists:
            note += " — FILE MANCANTE nel repo!"
        add("Immagini", path, desc, desc, dove, pos, note)

    # ------------------------------------------------------ statistiche --
    from collections import Counter
    per_sheet = Counter(e["sheet"] for e in entries)
    print(f"entries totali: {len(entries)}")
    for sheet in ["Menu", "Selezione", "Intro", "HUD-pausa", "Level Up",
                  "Fine partita", "Bonus reliquie", "Card bonus", "Armi",
                  "Armature", "Nemici-Boss", "Crediti", "Altro", "Immagini"]:
        print(f"  {sheet:<16} {per_sheet.get(sheet, 0)}")
    print(f"TEXTS: {len(texts)} · skill: {len(skills)} · armi base: {len(weapons)} "
          f"· elementali: {len(elementals)} · reliquie: {relic_count} · boss: {len(bosses)}")
    if warnings:
        print("\nAVVISI:")
        for w in warnings:
            print(f"  ! {w}")

    out = {
        "generated": date.today().isoformat(),
        "repo": repo,
        "total": len(entries),
        "warnings": warnings,
        "entries": entries,
    }
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
    print(f"\nJSON scritto: {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
