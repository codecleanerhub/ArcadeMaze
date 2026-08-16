#!/usr/bin/env python3
# generate_and_assemble.py
# ---------------------------------------------------------------------------
# Genera i prompt testuali per ogni creatura e ogni frame (salva in prompts/),
# (opzionale) invoca una funzione placeholder call_image_api(prompt, out_path)
# che devi implementare per la tua API, verifica dimensioni e alpha, applica
# palette ridotta con Pillow, assembla spritesheet 6x4 e salva *_sheet.png
# e *_meta.json.
#
# Prerequisiti: Python 3.8+, Pillow, numpy.
# ---------------------------------------------------------------------------
import os
import json
from PIL import Image, ImageOps
import numpy as np

# CONFIG
FRAME_W, FRAME_H = 64, 64
COLUMNS = 6
ROWS = 4
OUTPUT_DIR = "output"
PROMPT_DIR = "prompts"
PALETTE = [
  # 16-color example palette (hex -> RGB tuples)
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

MASTER_PROMPT = """Pixel art 64x64, detailed 16-color palette, fantasy horror, inspired by Dungeon & Dragons and Ghosts'n Goblins, transparent background, consistent character proportions across frames, no text, no UI, no watermark. Character: {CREATURE_DESC}. Animation: {ANIMATION} frame {FRAME_INDEX} of {TOTAL_FRAMES}. Mood: menacing, gothic lighting, subtle rim light, high contrast shading. Emphasize silhouette clarity, readable pose, crisp outlines, small pixel highlights, anchor feet at y=56. Output: PNG 64x64 exact size, alpha channel preserved.
Negative prompt: no background; no extra limbs beyond described; no photorealism; no text; no watermark; no UI elements.
Seed: {SEED}
"""

os.makedirs(OUTPUT_DIR, exist_ok=True)
os.makedirs(PROMPT_DIR, exist_ok=True)

def save_prompt(creature_id, anim, idx, total, desc, seed):
    p = MASTER_PROMPT.format(CREATURE_DESC=desc, ANIMATION=anim, FRAME_INDEX=idx, TOTAL_FRAMES=total, SEED=seed)
    fname = f"{PROMPT_DIR}/{creature_id}_{anim}_{idx}.txt"
    with open(fname, "w", encoding="utf-8") as f:
        f.write(p)
    return fname

def call_image_api(prompt_path, out_png_path):
    """
    Placeholder function.
    Implement this to call your image generation API, reading the prompt text from prompt_path
    and saving a 64x64 PNG with alpha to out_png_path.
    """
    raise NotImplementedError("Implement call_image_api to integrate with your chosen AI service.")

def verify_and_apply_palette(png_path):
    img = Image.open(png_path).convert("RGBA")
    if img.size != (FRAME_W, FRAME_H):
        print("Resizing", png_path)
        img = img.resize((FRAME_W, FRAME_H), resample=Image.NEAREST)
    if img.mode != "RGBA":
        img = img.convert("RGBA")
    arr = np.array(img)
    rgb = arr[...,:3].reshape(-1,3).astype(int)
    palette_arr = np.array(PALETTE)
    dists = np.sum((rgb[:,None,:] - palette_arr[None,:,:])**2, axis=2)
    idxs = np.argmin(dists, axis=1)
    new_rgb = palette_arr[idxs].reshape(arr.shape[0], arr.shape[1], 3)
    new_img = np.dstack([new_rgb, arr[...,3]])
    out = Image.fromarray(new_img.astype('uint8'), 'RGBA')
    out.save(png_path)

def assemble_sheet(creature_id):
    sheet = Image.new("RGBA", (FRAME_W*COLUMNS, FRAME_H*ROWS), (0,0,0,0))
    for anim, (row, count, dur) in ANIMATIONS.items():
        for i in range(count):
            frame_path = f"{OUTPUT_DIR}/{creature_id}/{anim}_{i}.png"
            if not os.path.exists(frame_path):
                print("Missing frame", frame_path)
                img = Image.new("RGBA", (FRAME_W, FRAME_H), (0,0,0,0))
            else:
                img = Image.open(frame_path).convert("RGBA")
            x = i * FRAME_W
            y = row * FRAME_H
            sheet.paste(img, (x,y), img)
    out_img = f"{OUTPUT_DIR}/{creature_id}_sheet.png"
    os.makedirs(os.path.dirname(out_img), exist_ok=True)
    sheet.save(out_img)
    meta = {
        "image": os.path.basename(out_img),
        "frameWidth": FRAME_W,
        "frameHeight": FRAME_H,
        "anchor": {"x":32,"y":56},
        "animations": {k:{"row":v[0],"frames":v[1],"frameDuration":v[2]} for k,v in ANIMATIONS.items()}
    }
    with open(f"{OUTPUT_DIR}/{creature_id}_meta.json","w",encoding="utf-8") as f:
        json.dump(meta, f, indent=2)
    print("Assembled", out_img)

def main(generate_images=False):
    for cid, name, desc in CREATURES:
        creature_folder = f"{OUTPUT_DIR}/{cid}"
        os.makedirs(creature_folder, exist_ok=True)
        for anim, (row, count, dur) in ANIMATIONS.items():
            for i in range(count):
                seed = 1000 + hash(cid + anim + str(i)) % 90000
                prompt_file = save_prompt(cid, anim, i, count, desc, seed)
                if generate_images:
                    out_png = f"{creature_folder}/{anim}_{i}.png"
                    call_image_api(prompt_file, out_png)
                    verify_and_apply_palette(out_png)
        assemble_sheet(cid)

if __name__ == "__main__":
    main(generate_images=False)
