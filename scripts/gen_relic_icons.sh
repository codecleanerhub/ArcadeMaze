#!/bin/bash
# Task 23 — PNG alta qualità per le 18 RELIQUIE (12 armi + 6 armature).
# Genera su sfondo MAGENTA piatto uniforme per chroma-key affidabile
# (il magenta non esiste nella palette delle reliquie: distanza cromatica
# massima da oro/acciaio/verde/viola-arcano dei singoli oggetti).
# Output: /tmp/relic_gen/<id>.png (1024x1024)

OUT=/tmp/relic_gen
mkdir -p "$OUT"

STYLE_COMMON="dark fantasy video game item icon, high quality detailed digital painting, painterly style, dramatic warm rim lighting, strong contrast, centered single item filling about 70 percent of the frame with margins, full item fully visible, plain flat solid pure magenta background color #FF00FF, absolutely uniform background, no gradient background, no drop shadow on the background, no text, no watermark, no border, no frame"

gen() {
  local id="$1"; shift
  local desc="$1"
  if [ -s "$OUT/$id.png" ]; then
    echo "SKIP $id (già presente)"
    return 0
  fi
  echo "=== $id ==="
  z-ai image -p "$desc, $STYLE_COMMON" -o "$OUT/$id.png" -s 1024x1024 \
    && echo "OK $id" || echo "FAIL $id"
}

# --- MISCHIA (6) ---
gen sword "an epic knight greatsword held vertically, massive two-handed longsword, polished silver steel blade with central fuller and gleaming edge, ornate golden crossguard with heraldic lion details, blue leather-wrapped grip, golden wheel pommel with ruby gem"
gen axe "a savage berserker battle axe held diagonally, single huge curved steel blade with glowing crimson engravings, notched battle-worn edge, dark iron haft wrapped in blood-red leather straps with metal studs"
gen mace "a heavy flanged iron mace held vertically, steel head with six wicked flanges and dark rivets, battle-worn metal texture, dark wooden shaft with iron rings and leather grip"
gen halberd "a royal guard halberd held diagonally, long polearm combining a broad axe blade, a back hook and a long spear tip on top, polished steel with golden royal engravings, dark red and gold tassel below the head"
gen vampire_blade "an elegant vampire blade held diagonally, slender curved rapier-like sword, deep crimson blade with dark veins pulsing like blood, black ornate guard shaped like bat wings, ruby set in the pommel, faint red mist around the blade"
gen golem_hammer "a massive stone golem war hammer held diagonally, gigantic carved granite head with glowing amber runic engravings and cracks, thick dark iron core, heavy wooden handle bound with aged iron bands"

# --- DISTANZA (6) ---
gen crossbow "an ornate silver crossbow held diagonally, heavy arbalest with gleaming silver-plated limbs, engraved filigree, loaded with a silver-tipped bolt, dark walnut stock with silver inlays"
gen arcane_orb "a tall archmage staff held vertically, twisted dark wood shaft with silver spiral bindings, topped with a large glowing violet orb held by silver claw prongs, small arcane sparkles around the orb"
gen twin_daggers "a pair of twin curved throwing daggers crossed in an X shape, teal-emerald gleaming blades with wavy damascus pattern, dark bronze guards and wrapped grips, subtle teal glint"
gen ranger_bow "a ranger recurve bow held vertically with string drawn taut, laminated yew wood bow with green leather wrapped grip, horn tips, one wooden arrow with grey goose feather fletching nocked"
gen storm_rod "a short storm rod wand held diagonally, azure-crystal tipped rod with spiraling copper wires, crackling electric blue lightning arcs coiling around the crystal tip, dark blue handle with silver bands"
gen alchemist_bombs "two round black cast-iron alchemist bombs, one large one small, studded rivets and pressure plates, short wooden plugs, sputtering lit fuses with bright orange sparks and thin smoke curls"

# --- ARMATURE (6) ---
gen golden "a shining golden plate armor cuirass on an invisible mannequin, front view, radiant polished gold breastplate with sun emblem embossed on the chest, golden pauldrons, mirror-bright reflections"
gen dragon "a green dragon scale armor cuirass on an invisible mannequin, front view, overlapping emerald dragon scales with bronze trim, dragonbone shoulder guards, faint green sheen"
gen obsidian "an obsidian twilight armor cuirass on an invisible mannequin, front view, glossy black volcanic glass plates with sharp edges, glowing purple runic sigils etched on the chest plates"
gen archmage "a blue archmage hooded robe on an invisible mannequin, front view, deep blue-violet enchanted fabric with silver runic embroidery on the chest, tall hood with shadowed face opening, golden cord belt"
gen fire "a black iron fire armor cuirass on an invisible mannequin, front view, scorched dark plate armor engulfed in living orange flames rising from the pauldrons and edges, ember glow in the cracks"
gen fury "a crimson fury spiked armor cuirass on an invisible mannequin, front view, blood-red lacquered steel plates with jagged black spikes on shoulders and arms, glowing hot vents on the chest"

ls -la "$OUT"
