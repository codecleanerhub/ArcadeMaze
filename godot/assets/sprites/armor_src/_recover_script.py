#!/usr/bin/env python3
"""RECOVERY Task 51: download all animation frames from PixelLab server-side
storage (already paid for in the lost session). Zero new credits spent.

Saves to: /home/z/my-project/scripts/pixellab_v2/recovered_task51/
  {name}/meta.json          - character details (prompt, view, size)
  {name}/{anim}_{i}.png     - every frame of every animation
"""
import json
import os
import sys
import time
import urllib.request

ENV_FILE = "/home/z/my-project/secrets/.env.pixellab"
OUT = "/home/z/my-project/scripts/pixellab_v2/recovered_task51"

TASK51 = [
    ("58289db5-96b2-4325-9361-e1358be9122b", "blood-drop"),
    ("f4a635f1-b0cc-48bf-a84a-68c2b3a4bc07", "player1-armored"),
    ("ceb2e2cc-4377-4de7-9c2b-bac4eaee119c", "player2-armored"),
    ("1c7b0913-ec8e-4ac3-99f5-5792cb362048", "mage-armored"),
    ("b83cd33c-6343-4d4b-b9e6-977a968d0218", "orc-armored"),
    ("55ac76b7-a493-43db-a5bf-88f9edf00912", "elf-armored"),
    ("4d944c64-6e03-4881-9653-4f38d0b465ad", "knight-armored"),
    ("8cb5892e-ed57-4e45-94be-53374d9182b9", "golem-armored"),
    ("065fa555-9075-43d7-abb1-bec0e40341bf", "dragon-armored"),
]


def load_env() -> str:
    key = os.environ.get("PIXELLAB_API_KEY")
    if key:
        return key
    with open(ENV_FILE) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                if k == "PIXELLAB_API_KEY":
                    os.environ[k] = v
                    return v
    raise SystemExit("no key")


def api(method: str, path: str):
    key = os.environ["PIXELLAB_API_KEY"]
    url = f"https://api.pixellab.ai{path}"
    req = urllib.request.Request(url, headers={
        "Authorization": f"Bearer {key}", "Accept": "application/json"},
        method=method)
    with urllib.request.urlopen(req, timeout=60) as resp:
        body = resp.read().decode("utf-8")
        return json.loads(body) if body else {}


def dl(url: str, path: str) -> bool:
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=60) as r:
            data = r.read()
        with open(path, "wb") as f:
            f.write(data)
        return True
    except Exception as e:
        print(f"    DL FAIL {os.path.basename(path)}: {e}")
        return False


def main() -> None:
    load_env()
    os.makedirs(OUT, exist_ok=True)
    summary = {}
    for cid, name in TASK51:
        cdir = os.path.join(OUT, name)
        os.makedirs(cdir, exist_ok=True)
        try:
            data = api("GET", f"/v2/characters/{cid}")
        except Exception as e:
            print(f"=== {name}: FETCH ERROR {e}")
            continue
        meta = {
            "id": cid, "name": data.get("name"), "size": data.get("size"),
            "view": data.get("view"), "prompt": data.get("prompt"),
            "created_at": data.get("created_at"),
            "tags": data.get("tags"),
        }
        anims = data.get("animations", [])
        meta["animations"] = []
        n_frames = 0
        for a in anims:
            disp = a.get("display_name", "anim")
            gid = a.get("animation_group_id", "")
            meta["animations"].append({
                "display_name": disp, "group_id": gid,
                "animation_type": a.get("animation_type", "")})
            for d in a.get("directions", []):
                dirname = d.get("direction", "south")
                for i, url in enumerate(d.get("frames", [])):
                    fp = os.path.join(cdir, f"{disp}_{dirname}_{i}.png")
                    if not os.path.exists(fp):
                        if dl(url, fp):
                            n_frames += 1
                    else:
                        n_frames += 1
                # save a frame-list for reference
                with open(os.path.join(cdir, f"{disp}_{dirname}_urls.json"), "w") as f:
                    json.dump(d.get("frames", []), f, indent=1)
        with open(os.path.join(cdir, "meta.json"), "w") as f:
            json.dump(meta, f, indent=1)
        summary[name] = {"anims": [a.get("display_name") for a in anims],
                          "frames_downloaded": n_frames}
        print(f"=== {name}: {len(anims)} anim(s), {n_frames} frames OK")
        time.sleep(0.3)
    with open(os.path.join(OUT, "_summary.json"), "w") as f:
        json.dump(summary, f, indent=1)
    print("\nSUMMARY:")
    print(json.dumps(summary, indent=1))


if __name__ == "__main__":
    main()
