#!/usr/bin/env python3
"""
generate_hd_sprites_serial.py - Rigenera tutti gli sprite AI a 256x256 in SERIALE.

Approccio seriale con delay di 5s tra generazioni per evitare rate limit 429.
Salta gli sprite gia' generati (resume capability).
"""

import os
import subprocess
import time
import sys
from pathlib import Path
from PIL import Image

HD_DIR = Path("/home/z/my-project/ArcadeMaze/godot/assets/sprites/hd")
HD_DIR.mkdir(parents=True, exist_ok=True)

PROMPT_TEMPLATE = (
    "Fantasy game sprite, high quality digital illustration, "
    "detailed character art, professional pixel art style but high resolution, "
    "transparent background, centered, full body view, side-facing right, "
    "dungeon crawler RPG character, Lord of the Rings and D&D inspired, "
    "gothic horror mood, dramatic lighting, rim light, "
    "high detail textures, shading, professional game art. "
    "Character: {DESC}. "
    "Output: clean isolated sprite, no background, no text, no UI."
)

CHARACTERS = [
    ("player1", "heroic male warrior knight, steel armor, blue tunic, sword and shield, blonde hair, heroic stance"),
    ("player2", "heroic female warrior, silver armor, red cape, longsword, brown hair, valiant stance"),
    ("char_mage", "mysterious wizard mage, pointed hat, flowing robes, glowing staff, long beard, arcane symbols"),
    ("char_orc", "muscular green orc warrior, tusks, leather armor, battle axe, fierce expression, brutish"),
    ("char_elf", "agile elf archer, blonde hair, pointed ears, leather armor, longbow, graceful stance"),
    ("char_knight", "heavy armored knight, full plate armor, great helm, longsword, cross emblem, crusader"),
    ("char_golem", "massive stone golem, glowing orange eyes, mossy cracked stone, ancient runes carved, imposing"),
    ("char_dragon", "dragon-man hybrid, red scales, leathery wings, tail, horns, fire breath, fearsome"),
    ("char_vampire", "elegant vampire noble, black cape, pale skin, fangs, red eyes, aristocratic, gothic"),
]

MONSTERS = [
    ("monster_001", "rotten skeletal ghoul, long claws, ragged flesh, hunched posture, glowing eyes"),
    ("monster_002", "abyssal spider, armored carapace, multiple glowing red eyes, dangling webs, menacing"),
    ("monster_003", "spectral wolf, smoky fur, glowing green eyes, tattered collar, ghostly"),
    ("monster_004", "corrupted cultist, hooded robe, runic tattoos, ritual dagger, sinister"),
    ("monster_005", "mimic treasure bag, mouth full of teeth, leather straps, tongue flicking"),
    ("monster_006", "giant rat, matted fur, rotten teeth, scavenger posture, diseased"),
    ("monster_007", "swamp witch, pointed hat, potion vials, greenish skin, warty nose"),
    ("monster_008", "skeleton lancer, rusted armor, broken spear, hollow eyes, undead"),
    ("monster_009", "creeping shadow, amorphous dark form, smoky tendrils, no visible legs, eerie"),
    ("monster_010", "bone golem, massive ribcage, clanking joints, skull head, slow gait"),
    ("monster_011", "ash serpent, smoky scales, ember eyes, sinuous body, fiery"),
    ("monster_012", "damned knight, blackened armor, ember cracks, tattered cape, cursed"),
    ("monster_013", "mad wizard, glowing eyes, torn robes, floating scrolls, chaotic energy"),
    ("monster_014", "minor vampire, thin cloak, pale skin, small fangs, aristocratic"),
    ("monster_015", "demonic crow, ragged wings, metallic beak, red eyes, dark"),
    ("monster_016", "subterranean tentacle, mucous skin, scattered eyes, writhing, slimy"),
    ("monster_017", "watchful gargoyle, stone texture, broken wings, perched stance, gothic"),
    ("monster_018", "well spirit, watery face, bubble effects, translucent, eerie"),
    ("monster_019", "cursed boar, mud-caked, tusks encrusted, low center of gravity, savage"),
    ("monster_020", "predator fungus, glowing cap, spore puffs, stalky legs, alien"),
    ("monster_021", "undead zombie, rotting flesh, tattered clothes, milky eyes, shambling"),
    ("monster_022", "giant bat, leathery wings, fangs, dark fur, flying menace"),
    ("monster_023", "green slime blob, gelatinous, dripping acid, translucent, amorphous"),
    ("monster_024", "horned demon, red skin, goat legs, barbed tail, infernal"),
    ("monster_025", "mechanical robot, metallic plates, glowing eyes, steam pipes, construct"),
    ("monster_026", "goblin raider, green skin, sharp ears, leather armor, crude club"),
    ("monster_027", "orc brute, muscular, tusks, iron armor, war hammer, fierce"),
    ("monster_028", "wraith, tattered dark cloak, no face, ghostly claws, ethereal"),
    ("monster_029", "imp, small demon, bat wings, mischievous grin, fire magic"),
]

BOSSES = [
    ("boss_021", "ghoul lord necromancer, bone crown, commanding pose, dark aura, tattered royal robes, massive skeletal warrior, menacing, very large imposing epic scale"),
    ("boss_022", "queen spider enormous, giant abdomen, web banners, many glowing eyes, monstrous arachnid matriarch, terrifying, very large imposing epic scale"),
    ("boss_023", "spectral alpha wolf, larger than normal, mane of smoke, howling stance, ghostly pack leader, ethereal, very large imposing epic scale"),
    ("boss_024", "cult herald, ornate flowing robes, summoning staff, minion sigils floating, dark priest, imposing, very large imposing epic scale"),
    ("boss_025", "colossal mimic, shifting treasure chest form, huge maw of teeth, gold and gems, monstrous, very large imposing epic scale"),
    ("boss_026", "rat king, bone crown, swarm of rats, regal hunched posture, diseased sovereign, grotesque, very large imposing epic scale"),
    ("boss_027", "supreme swamp witch, larger than normal, animated vines, crown of reeds, multiple potions, powerful, very large imposing epic scale"),
    ("boss_028", "twilight knight, shield absorbing light, lance, imposing helm, dark armor, legendary warrior, very large imposing epic scale"),
    ("boss_029", "vampire bishop, ornate vestments, draining aura, teleport flicker effect, fangs, gothic noble, very large imposing epic scale"),
    ("boss_030", "depths guardian, many tentacles, water shockwave, barnacle armor, kraken-like, massive, very large imposing epic scale"),
    ("boss_031", "ancient lich king, skeletal mage, crown of bones, glowing eye sockets, dark robes, undead sorcerer, very large imposing epic scale"),
    ("boss_032", "demon lord, massive horns, bat wings, fire aura, goat legs, infernal ruler, terrifying, very large imposing epic scale"),
    ("boss_033", "abomination, flesh golem, stitched body, multiple eyes, grotesque, massive horror, very large imposing epic scale"),
    ("boss_034", "kraken titan, giant squid head, tentacle beard, watery body, ocean depths ruler, very large imposing epic scale"),
    ("boss_035", "ancient dragon, red scales, massive wings, horns, fire breath, treasure hoard, wyrm, very large imposing epic scale"),
    ("boss_036", "wraith lord, tattered dark cloak, crown of shadow, no face, spectral claws, death knight, very large imposing epic scale"),
    ("boss_037", "beholder, floating eyeball, many eyestalks, central maw, chitinous shell, aberration, very large imposing epic scale"),
]

MINIBOSSES = [
    ("miniboss_01", "goblin chieftain, crude crown, battle axe, green skin, cunning grin, warlord, medium-large size muscular"),
    ("miniboss_02", "cave troll, massive grey skin, wooden club, hunched, dumb but powerful, medium-large size muscular"),
    ("miniboss_03", "orc berserker, frothing mouth, twin scimitars, scarred, raging, muscular green, medium-large size muscular"),
    ("miniboss_04", "warg rider, goblin on dire wolf, spear, feral mount, fast cavalry, medium-large size muscular"),
    ("miniboss_05", "uruk-hai, black armor, white hand mark, scimitar, brutal, scarred face, medium-large size muscular"),
    ("miniboss_06", "nazgul, black robes, ringwraith, hooded, invisible face, Morgul blade, fell, medium-large size muscular"),
    ("miniboss_07", "ogre brute, massive, belly, morning star, stupid grin, dirty loincloth, medium-large size muscular"),
    ("miniboss_08", "gnoll packlord, hyena head, armor, greataxe, laughing, savage chieftain, medium-large size muscular"),
    ("miniboss_09", "bugbear chief, furry goblinoid, chain weapon, shaggy, ambush predator, medium-large size muscular"),
    ("miniboss_10", "minotaur, bull head, muscular, double axe, maze dweller, bestial, medium-large size muscular"),
    ("miniboss_11", "wight lord, spectral armor, ghostly sword, blue glow, barrow wight, undead noble, medium-large size muscular"),
    ("miniboss_12", "cave giant, huge, rough skin, wooden maul, primitive, dim-witted, medium-large size muscular"),
    ("miniboss_13", "death knight, black armor, skull helm, undead, cursed blade, fallen paladin, medium-large size muscular"),
    ("miniboss_14", "illithid mind flayer, purple skin, tentacle face, robes, psionic, aberration, medium-large size muscular"),
    ("miniboss_15", "ettin, two heads, two clubs, massive, stupid, giant-kin, brutish, medium-large size muscular"),
    ("miniboss_16", "fomorian, deformed giant, one eye, club, ugly, celtic myth, savage, medium-large size muscular"),
    ("miniboss_17", "balrog cultist, fire whip, dark robes, infernal, flame aura, corrupted, medium-large size muscular"),
    ("miniboss_18", "fenris wolf, massive grey dire wolf, golden eyes, Norse myth, alpha predator, medium-large size muscular"),
    ("miniboss_19", "white witch guard, ice armor, frozen sword, pale, winter knight, cold aura, medium-large size muscular"),
    ("miniboss_20", "narnia minotaur, white fur, ice axe, winter, frost breath, maze dweller, medium-large size muscular"),
    ("miniboss_21", "dwarf berserker, red beard, chainmail, war axe, stocky, fierce warrior, medium-large size muscular"),
    ("miniboss_22", "witch knight, ice lance, silver armor, cold aura, winter, fallen templar, medium-large size muscular"),
    ("miniboss_23", "talking beast corrupted, dark fur, claws, feral, once noble, twisted, medium-large size muscular"),
    ("miniboss_24", "ice giant, frost skin, icy maul, winter, massive, cold aura, jotun, medium-large size muscular"),
    ("miniboss_25", "leshen, antler head, wooden body, root claws, forest spirit, eerie, medium-large size muscular"),
    ("miniboss_26", "bruxa, vampire woman, fangs, black hair, wail, seductive yet deadly, medium-large size muscular"),
    ("miniboss_27", "katakan, muscular vampire, red eyes, claws, bat-like, feral bloodsucker, medium-large size muscular"),
    ("miniboss_28", "fiend, massive beast, large horns, glowing eye, demonic, rhino-like, medium-large size muscular"),
    ("miniboss_29", "witcher golem, stone construct, glowing core, massive fists, magical, medium-large size muscular"),
    ("miniboss_30", "noonwraith, spectral woman, flowing tattered dress, sun glare, ghostly, medium-large size muscular"),
    ("miniboss_31", "foglet, misty form, claws, fog aura, ghostly, deceptive predator, medium-large size muscular"),
    ("miniboss_32", "grave hag, old crone, long claws, hunched, cemetery, decayed, medium-large size muscular"),
    ("miniboss_33", "manticore, lion body, human face, scorpion tail, wings, chimera, medium-large size muscular"),
    ("miniboss_34", "cyclops witcher, one eye, massive, club, Greek myth, brute, medium-large size muscular"),
    ("miniboss_35", "doom imp, brown demon, fireballs, horns, leathery, fast, hellspawn, medium-large size muscular"),
    ("miniboss_36", "pinky demon, pink bulky, horns, fast charge, feral, hell beast, medium-large size muscular"),
    ("miniboss_37", "revenant, skeleton with rocket launchers on shoulders, military undead, medium-large size muscular"),
    ("miniboss_38", "cacodemon, floating red sphere, single eye, horns, plasma, hell, medium-large size muscular"),
    ("miniboss_39", "hell knight, muscular tan demon, horns, fists, leaping, hellish, medium-large size muscular"),
    ("miniboss_40", "mancubus, fat demon, fire cannons on arms, waddling, infernal, medium-large size muscular"),
    ("miniboss_41", "archvile, slender demon, fire aura, resurrects dead, priest of hell, medium-large size muscular"),
    ("miniboss_42", "baron of hell, pink goat-leg demon, claws, horns, noble hellspawn, medium-large size muscular"),
    ("miniboss_43", "pain elemental, floating brown head, huge mouth, lost souls, hell, medium-large size muscular"),
    ("miniboss_44", "cyberdemon, massive, rocket launcher arm, metal legs, hellish, mechanical, medium-large size muscular"),
    ("miniboss_45", "shadow assassin, dark cloak, twin daggers, hooded, stealthy, ninja, medium-large size muscular"),
    ("miniboss_46", "crystal golem, translucent body, crystal fists, refracted light, magical, medium-large size muscular"),
    ("miniboss_47", "void walker, dark form, dimensional claws, rifts around, eldritch, medium-large size muscular"),
    ("miniboss_48", "blood elemental, crimson fluid body, blood blades, dripping, vampire, medium-large size muscular"),
    ("miniboss_49", "storm titan, lightning aura, thunder maul, electric, giant, tempest, medium-large size muscular"),
    ("miniboss_50", "plague lord, diseased body, infected staff, pustules, vermin, decayed, medium-large size muscular"),
    ("miniboss_51", "void serpent, dark scaled snake, dimensional fangs, ethereal, ancient, medium-large size muscular"),
]

ALL_SPRITES = CHARACTERS + MONSTERS + BOSSES + MINIBOSSES


def generate_one(sprite_id: str, desc: str, max_retries: int = 3) -> bool:
    out_path = HD_DIR / f"{sprite_id}_hd_sheet.png"
    if out_path.exists():
        return True
    prompt = PROMPT_TEMPLATE.format(DESC=desc)
    for attempt in range(max_retries):
        cmd = ["z-ai", "image", "-p", prompt, "-o", str(out_path), "-s", "1024x1024"]
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
            if result.returncode == 0 and out_path.exists():
                # Ridimensiona a 256x256
                img = Image.open(out_path).convert("RGBA")
                img = img.resize((256, 256), Image.LANCZOS)
                img.save(out_path)
                return True
        except Exception:
            pass
        if attempt < max_retries - 1:
            time.sleep(8)  # delay per rate limit
    return False


def main():
    # Argomenti opzionali: categoria e limite
    category = sys.argv[1] if len(sys.argv) > 1 else "all"
    limit = int(sys.argv[2]) if len(sys.argv) > 2 else 0

    if category == "characters":
        items = CHARACTERS
    elif category == "monsters":
        items = MONSTERS
    elif category == "bosses":
        items = BOSSES
    elif category == "minibosses":
        items = MINIBOSSES
    else:
        items = ALL_SPRITES

    if limit > 0:
        items = items[:limit]

    print(f"Generating {len(items)} sprites (category={category})...")
    success = 0
    failed = []
    for i, (sprite_id, desc) in enumerate(items, 1):
        # Skip se esiste gia'
        out_path = HD_DIR / f"{sprite_id}_hd_sheet.png"
        if out_path.exists():
            print(f"[{i}/{len(items)}] SKIP {sprite_id} (exists)")
            success += 1
            continue
        print(f"[{i}/{len(items)}] Generating {sprite_id}...", flush=True)
        if generate_one(sprite_id, desc):
            print(f"  OK")
            success += 1
        else:
            print(f"  FAIL")
            failed.append(sprite_id)
        # Delay tra generazioni per evitare rate limit
        time.sleep(3)
    print(f"\n=== Done: {success}/{len(items)} success ===")
    if failed:
        print(f"Failed: {failed}")


if __name__ == "__main__":
    main()
