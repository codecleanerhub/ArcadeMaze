#!/usr/bin/env python3
# build_bestiary_package.py
# ---------------------------------------------------------------------------
# Crea prompt, manifest JSON e impacchetta tutto in fantasy_horror_bestiary.zip
# Requisiti: Python 3.8+, pip install pillow numpy (opzionale per la palette)
# ---------------------------------------------------------------------------
import os
import json
import zipfile
from pathlib import Path
from PIL import Image
import numpy as np

FRAME_W, FRAME_H = 64, 64
COLUMNS = 6
ROWS = 4
PROMPT_DIR = Path("prompts")
OUTPUT_DIR = Path("output")
ZIP_NAME = "fantasy_horror_bestiary.zip"

PALETTE = [
  (12,12,12),(48,40,36),(96,80,72),(160,128,112),
  (200,180,160),(120,140,160),(80,120,100),(40,80,60),
  (160,40,40),(200,80,80),(220,160,40),(200,200,80),
  (120,200,200),(80,160,220),(160,120,200),(240,240,240)
]

CREATURES = [
  ("monster_001","Sghignazzante Ghoul","rotten skeletal ghoul, long claws, ragged flesh, hunched posture"),
  ("monster_002","Ragno Abissale","abyssal spider, armored carapace, multiple glowing red eyes, dangling webs"),
  ("monster_003","Lupo Spettrale","spectral wolf, smoky fur, glowing green eyes, tattered collar"),
  ("monster_004","Cultista Corrotto","corrupted cultist, hooded robe, runic tattoos, ritual dagger"),
  ("monster_005","Mimic Borsa","mimic bag, mouth of teeth, leather straps, tongue flicking"),
  ("monster_006","Ratto Gigante","giant rat, matted fur, rotten teeth, scavenger posture"),
  ("monster_007","Strega delle Paludi","swamp witch, pointed hat, potion vials, greenish skin"),
  ("monster_008","Scheletro Lanciere","skeleton lancer, rusted armor, broken spear, hollow eyes"),
  ("monster_009","Ombra Strisciante","creeping shadow, amorphous form, smoky tendrils, no visible legs"),
  ("monster_010","Golem di Ossa","bone golem, massive ribcage, clanking joints, slow gait"),
  ("monster_011","Serpente di Cenere","ash serpent, smoky scales, ember eyes, sinuous body"),
  ("monster_012","Cavaliere Dannato","damned knight, blackened armor, ember cracks, tattered cape"),
  ("monster_013","Mago Folle","mad wizard, glowing eyes, torn robes, floating scrolls"),
  ("monster_014","Vampiro Minore","minor vampire, thin cloak, pale skin, small fangs"),
  ("monster_015","Corvo Demoniaco","demonic crow, ragged wings, metallic beak, red eyes"),
  ("monster_016","Tentacolo Sotterraneo","subterranean tentacle, mucous skin, scattered eyes, writhing"),
  ("monster_017","Gargoyle Vegliante","watchful gargoyle, stone texture, broken wings, perched stance"),
  ("monster_018","Spirito del Pozzo","well spirit, watery face, bubble effects, translucent"),
  ("monster_019","Cinghiale Maledetto","cursed boar, mud-caked, tusks encrusted, low center of gravity"),
  ("monster_020","Fungo Predatore","predator fungus, glowing cap, spore puffs, stalky legs"),
  ("boss_021","Signore dei Ghoul","ghoul lord, necromancer aura, bone crown, commanding pose"),
  ("boss_022","Regina Ragno Abissale","queen spider, enormous abdomen, web banners, many eyes"),
  ("boss_023","Lupo Alpha Spettrale","spectral alpha wolf, larger, mane of smoke, howling stance"),
  ("boss_024","Araldo del Culto","cult herald, ornate robes, summoning staff, minion sigils"),
  ("boss_025","Mimic Colossale","colossal mimic, shifting form, treasure chest motifs, huge maw"),
  ("boss_026","Re dei Topi","rat king, bone crown, swarm motif, regal hunched posture"),
  ("boss_027","Strega Suprema delle Paludi","supreme swamp witch, larger potions, animated vines, crown of reeds"),
  ("boss_028","Cavaliere del Crepuscolo","twilight knight, shield absorbing light, lance, imposing helm"),
  ("boss_029","Vescovo Vampiro","vampire bishop, ornate vestments, draining aura, teleport flicker"),
  ("boss_030","Guardiano delle Profondita'","depths guardian, many tentacles, water shockwave, barnacle armor")
]

ANIMATIONS = {
  "idle": (0,4,200),
  "walk": (1,6,100),
  "attack": (2,6,100),
  "death": (3,6,120)
}

MASTER_PROMPT = (
"Pixel art 64x64, detailed 16-color palette, fantasy horror, inspired by Dungeon & Dragons and Ghosts'n Goblins, "
"transparent background, consistent character proportions across frames, no text, no UI, no watermark. "
"Character: {CREATURE_DESC}. Animation: {ANIMATION} frame {FRAME_INDEX} of {TOTAL_FRAMES}. "
"Mood: menacing, gothic lighting, subtle rim light, high contrast shading. Emphasize silhouette clarity, readable pose, "
"crisp outlines, small pixel highlights, anchor feet at y=56. Output: PNG 64x64 exact size, alpha channel preserved.\n"
"Negative prompt: no background; no extra limbs beyond described; no photorealism; no text; no watermark; no UI elements.\n"
"Seed: {SEED}"
)

def ensure_dirs():
    PROMPT_DIR.mkdir(exist_ok=True)
    OUTPUT_DIR.mkdir(exist_ok=True)

def save_prompt_file(creature_id, anim, idx, total, desc, seed):
    fname = PROMPT_DIR / f"{creature_id}_{anim}_{idx}.txt"
    text = MASTER_PROMPT.format(CREATURE_DESC=desc, ANIMATION=anim, FRAME_INDEX=idx, TOTAL_FRAMES=total, SEED=seed)
    with open(fname, "w", encoding="utf-8") as f:
        f.write(text)
    return fname

def call_image_api(prompt_path, out_png_path):
    raise NotImplementedError("Implement call_image_api to generate images via your chosen AI service.")

def reduce_palette_keep_alpha(png_path):
    img = Image.open(png_path).convert("RGBA")
    arr = np.array(img)
    rgb = arr[...,:3].reshape(-1,3).astype(int)
    palette_arr = np.array(PALETTE)
    dists = np.sum((rgb[:,None,:] - palette_arr[None,:,:])**2, axis=2)
    idxs = np.argmin(dists, axis=1)
    new_rgb = palette_arr[idxs].reshape(arr.shape[0], arr.shape[1], 3)
    new_img = np.dstack([new_rgb, arr[...,3]])
    out = Image.fromarray(new_img.astype('uint8'), 'RGBA')
    out.save(png_path)

def build_manifest():
    manifest = {
        "meta": {
            "project": "Fantasy Horror Bestiary",
            "frameSize": {"width": FRAME_W, "height": FRAME_H},
            "palette": "16-color recommended",
            "padding": 2,
            "anchorDefault": {"x": 32, "y": 56},
            "layout": {"columns": COLUMNS, "rowsPerCreature": ROWS, "rowsOrder": ["idle","walk","attack","death"]}
        },
        "creatures": []
    }
    for cid, name, desc in CREATURES:
        is_boss = cid.startswith("boss")
        anims = {}
        for k,v in ANIMATIONS.items():
            anims[k] = {"row": v[0], "frames": v[1], "frameDuration": v[2]}
        manifest["creatures"].append({
            "id": cid,
            "name": name,
            "type": "boss" if is_boss else "monster",
            "image": f"{cid}_sheet.png",
            "frameWidth": FRAME_W,
            "frameHeight": FRAME_H,
            "columns": COLUMNS,
            "rows": ROWS,
            "anchor": {"x":32,"y":56},
            "animations": anims
        })
    with open("bestiary_manifest.json","w",encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)
    return "bestiary_manifest.json"

def assemble_sheet_for(creature_id):
    sheet = Image.new("RGBA", (FRAME_W*COLUMNS, FRAME_H*ROWS), (0,0,0,0))
    for anim, (row, count, dur) in ANIMATIONS.items():
        for i in range(count):
            frame_path = OUTPUT_DIR / creature_id / f"{anim}_{i}.png"
            if frame_path.exists():
                img = Image.open(frame_path).convert("RGBA")
            else:
                img = Image.new("RGBA", (FRAME_W, FRAME_H), (0,0,0,0))
            x = i * FRAME_W
            y = row * FRAME_H
            sheet.paste(img, (x,y), img)
    out_img = OUTPUT_DIR / f"{creature_id}_sheet.png"
    sheet.save(out_img)
    meta = {
        "image": out_img.name,
        "frameWidth": FRAME_W,
        "frameHeight": FRAME_H,
        "anchor": {"x":32,"y":56},
        "animations": {k:{"row":v[0],"frames":v[1],"frameDuration":v[2]} for k,v in ANIMATIONS.items()}
    }
    with open(OUTPUT_DIR / f"{creature_id}_meta.json","w",encoding="utf-8") as f:
        json.dump(meta, f, indent=2)

def create_readme():
    text = (
        "Fantasy Horror Bestiary\n\n"
        "Contenuto:\n"
        "- prompts/: 660 file .txt con i prompt per ogni frame\n"
        "- bestiary_manifest.json: manifest principale per il gioco\n"
        "- output/: cartelle per ogni creatura, qui vanno i PNG generati e gli spritesheet\n\n"
        "Esegui build_bestiary_package.py per rigenerare i file. Implementa call_image_api() per generare immagini automaticamente.\n"
    )
    with open("README.txt","w",encoding="utf-8") as f:
        f.write(text)

def zip_all():
    with zipfile.ZipFile(ZIP_NAME, "w", zipfile.ZIP_DEFLATED) as z:
        for root, _, files in os.walk(PROMPT_DIR):
            for file in files:
                z.write(os.path.join(root, file), arcname=os.path.join("prompts", file))
        z.write("bestiary_manifest.json", arcname="bestiary_manifest.json")
        z.write("README.txt", arcname="README.txt")
        for root, _, files in os.walk(OUTPUT_DIR):
            for file in files:
                full = os.path.join(root, file)
                arc = os.path.join("output", os.path.relpath(full, OUTPUT_DIR))
                z.write(full, arcname=arc)
    print(f"Created {ZIP_NAME}")

def main(generate_images=False):
    ensure_dirs()
    seed_base = 10001
    for idx, (cid, name, desc) in enumerate(CREATURES):
        creature_folder = OUTPUT_DIR / cid
        creature_folder.mkdir(parents=True, exist_ok=True)
        for anim, (row, count, dur) in ANIMATIONS.items():
            for i in range(count):
                seed = seed_base + idx*22 + (list(ANIMATIONS.keys()).index(anim)*100) + i
                prompt_file = save_prompt_file(cid, anim, i, count, desc, seed)
                if generate_images:
                    out_png = creature_folder / f"{anim}_{i}.png"
                    try:
                        call_image_api(prompt_file, out_png)
                        reduce_palette_keep_alpha(out_png)
                    except NotImplementedError:
                        print("call_image_api not implemented; skipping image generation.")
                        generate_images = False
                        break
        assemble_sheet_for(cid)
    manifest_path = build_manifest()
    create_readme()
    zip_all()
    print("Done. Controlla", ZIP_NAME)

if __name__ == "__main__":
    main(generate_images=False)
