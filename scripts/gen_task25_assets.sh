#!/bin/bash
# Task 25 — Rigenerazione asset danneggiati:
#   * item_hammer.png (Mjolnir: manico scuro/corto -> invisibile su pavimento scuro)
#   * reliquie frammentate dal chroma-key: axe, mace, halberd, ranger_bow, vampire_blade
# LEZIONE Task 25: i manici con parti ROSSO/CRIMSON passano la guardia della
# famiglia MAGENTA (r>g+25 & b>g-8) e vengono mangiati dal flood -> manici
# spezzati. Rigenerazione su sfondo CIANO (famiglia opposta): acciaio/legno/
# oro/crimson NON passano MAI la guardia ciano (b>r+25 & g>r+10).
# Uscita: /tmp/relic_gen25/<id>.png (1024x1024, sfondo ciano piatto)

OUT=/tmp/relic_gen25
mkdir -p "$OUT"

STYLE_COMMON="dark fantasy video game item icon, high quality detailed digital painting, painterly style, dramatic warm rim lighting, strong contrast, centered single item filling about 70 percent of the frame with margins, full item fully visible, plain flat solid pure cyan background color #00FFFF, absolutely uniform background everywhere, no gradient background, no drop shadow on the background, no text, no watermark, no border, no frame"

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

# --- Martello Mjolnir (pickup labirinto): manico LUNGO, SPESSO, CHIARO,
# continuo, con pomo evidente -> leggibile anche ridotto a 64px su sfondo scuro ---
gen item_hammer "a mighty dwarven war hammer game item held diagonally, massive blocky steel head with squared faces and glowing blue rune engravings, LONG THICK SOLID CONTINUOUS wooden handle with NO gaps fully wrapped in bright light-brown leather straps with steel studs, large round polished steel pommel at the handle end, high contrast bright handle clearly visible against dark backgrounds"

# --- 5 reliquie con manici/lame CONTINUI (no fasce con intercapedini) ---
gen axe "a savage berserker battle axe held diagonally, single huge curved steel blade with glowing crimson engravings, notched battle-worn edge, SOLID CONTINUOUS dark iron haft with NO gaps wrapped edge to edge in smooth bright red-brown leather, round steel pommel at the haft end"
gen mace "a heavy flanged iron mace held vertically, steel head with six wicked flanges and dark rivets, battle-worn metal texture, SOLID CONTINUOUS dark wooden shaft with NO gaps, wide smooth tan leather grip wrap and iron rings, round iron pommel at the bottom"
gen halberd "a royal guard halberd held diagonally, long polearm combining a broad axe blade, a back hook and a long spear tip on top, polished steel with golden royal engravings, SOLID CONTINUOUS long dark walnut wooden pole with NO gaps, golden tassel below the head"
gen vampire_blade "an elegant vampire blade held diagonally, slender curved rapier-like sword with one CONTINUOUS unbroken blade from crossguard to sharp tip, deep crimson blade with dark veins pulsing like blood, black ornate guard shaped like bat wings, ruby set in the round pommel"
gen ranger_bow "a ranger recurve bow held vertically with string drawn taut, CONTINUOUS unbroken laminated yew wood bow limbs, green leather wrapped grip, horn tips, one wooden arrow with grey goose feather fletching nocked on the string"

ls -la "$OUT"
