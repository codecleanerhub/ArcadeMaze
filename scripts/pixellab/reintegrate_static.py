#!/usr/bin/env python3
"""Task 53 helper: reintegra la clean.png di una entity (zero generazioni).

Uso: python3 reintegrate_static.py <entity_id>
"""
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pl_integrate
from PIL import Image
from defs_items import ENTITIES

eid = sys.argv[1]
d = ENTITIES[eid]
img = Image.open(os.path.join("out", eid, "clean.png")).convert("RGBA")
out = pl_integrate.write_static(d["target"], img, tuple(d["size"]))
new = Image.open(out)
cols = len({(p[0], p[1], p[2]) for p in new.getdata() if p[3] > 0})
op = sum(1 for p in new.getdata() if p[3] > 0)
print(f"reintegrato {eid} -> {out} ({new.size}, {cols} colori, "
      f"coverage {100 * op // (new.size[0] * new.size[1])}%)")
