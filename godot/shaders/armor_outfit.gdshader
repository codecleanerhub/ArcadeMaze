// armor_outfit.gdshader
// TASK 25 — Outfit delle armature reliquia.
// Il materiale SOSTITUISCE character_enhanced mentre il player indossa
// un'armatura reliquia e aggiunge, oltre al pipeline enhancement identico
// (sharpening + contrasto/saturazione + depth + rim), la RICOLORAZIONE
// procedurale del vestiario:
//   * CLOTH  -> i pixel con hue vicino a `cloth_hue` (il colore dominante
//               del vestito del personaggio, calcolato da Player.gd sul
//               frame 0 dello sheet) vengono spostati verso l'hue
//               dell'armatura mantenendo la LUMINANZA originale (le ombre
//               e le pieghe del vestito restano). La pelle e' protetta da
//               una guardia hue+saturazione+valore.
//   * METAL  -> i pixel desaturati (acciaio/pietra del knight o del golem)
//               ricevono una tinta dell'armatura modulata dalla luminanza.
//   * RIM    -> il bordo del contorno rischiara col colore dell'armatura.
// Tutto disattivabile: armor_active=false + parametri base = character_enhanced.
shader_type canvas_item;

uniform float sharpness : hint_range(0.0, 2.0) = 0.6;
uniform float contrast : hint_range(0.5, 2.0) = 1.12;
uniform float saturation : hint_range(0.5, 2.0) = 1.18;
uniform float rim_intensity : hint_range(0.0, 2.0) = 0.5;
uniform vec2 light_dir = vec2(0.5, -0.7);
uniform vec4 light_tint : source_color = vec4(1.0, 0.95, 0.85, 1.0);
uniform vec4 shadow_tint : source_color = vec4(0.35, 0.3, 0.45, 1.0);
uniform float depth_strength : hint_range(0.0, 1.5) = 0.5;

uniform bool armor_active = false;
uniform vec4 armor_color : source_color = vec4(1.0, 0.8, 0.25, 1.0);
uniform float cloth_hue : hint_range(0.0, 1.0) = 0.6;
uniform float cloth_window : hint_range(0.02, 0.25) = 0.09;
uniform float cloth_strength : hint_range(0.0, 1.0) = 0.85;
uniform float metal_strength : hint_range(0.0, 1.0) = 0.5;
uniform float armor_rim : hint_range(0.0, 2.0) = 0.9;

vec3 rgb2hsv(vec3 c) {
        vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
        vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
        vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
        float d = q.x - min(q.w, q.y);
        float e = 1.0e-10;
        return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
        vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
        vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.w);
        return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

float hue_dist(float a, float b) {
        float d = abs(a - b);
        return min(d, 1.0 - d);
}

void fragment() {
        vec4 tex = texture(TEXTURE, UV);
        if (tex.a < 0.1) {
                discard;
        }
        vec2 size = TEXTURE_PIXEL_SIZE;

        // --- Classificazione sul colore ORIGINALE (pre-enhancement: stabile) ---
        vec3 hsv0 = rgb2hsv(tex.rgb);
        // Pelle: hue arancio-rossiccio, mediamente satura, sufficientemente
        // chiara. Il cuoio scuro (v < 0.4) NON passa -> resta ricolorabile.
        bool is_skin = hue_dist(hsv0.x, 0.08) < 0.065
                        && hsv0.y > 0.22 && hsv0.y < 0.92 && hsv0.z > 0.4;
        bool is_cloth = armor_active && hsv0.y > 0.20
                        && hue_dist(hsv0.x, cloth_hue) < cloth_window && !is_skin;
        bool is_metal = armor_active && hsv0.y <= 0.20 && hsv0.z > 0.20;

        // --- 1. Unsharp masking (sharpening) ---
        vec4 blur = (
                texture(TEXTURE, UV + vec2(-size.x, 0.0)) +
                texture(TEXTURE, UV + vec2(size.x, 0.0)) +
                texture(TEXTURE, UV + vec2(0.0, -size.y)) +
                texture(TEXTURE, UV + vec2(0.0, size.y))
        ) * 0.25;
        vec3 detail = (tex.rgb - blur.rgb) * sharpness;
        vec3 enhanced = tex.rgb + detail;

        // --- 2. Contrast + saturation ---
        enhanced = (enhanced - 0.5) * contrast + 0.5;
        float gray = dot(enhanced, vec3(0.299, 0.587, 0.114));
        enhanced = mix(vec3(gray), enhanced, saturation);

        // --- 3. Fake normal map per depth ---
        float a_l = texture(TEXTURE, UV - vec2(size.x, 0.0)).a;
        float a_r = texture(TEXTURE, UV + vec2(size.x, 0.0)).a;
        float a_u = texture(TEXTURE, UV - vec2(0.0, size.y)).a;
        float a_d = texture(TEXTURE, UV + vec2(0.0, size.y)).a;
        vec3 normal = normalize(vec3(
                (a_l - a_r) * depth_strength,
                (a_u - a_d) * depth_strength,
                1.0
        ));
        vec3 light = normalize(vec3(light_dir.x, light_dir.y, 0.8));
        float ndotl = max(dot(normal, light), 0.0);
        vec3 lit_tint = mix(shadow_tint.rgb, light_tint.rgb, ndotl);
        enhanced *= lit_tint;

        // --- 4. TASK 25: outfit armatura ---
        if (is_cloth) {
                // hue -> colore armatura; la luminanza (V) del vestito si
                // conserva: ombre, pieghe e shading restano quelli del
                // personaggio. Saturazione: via di mezzo col colore armatura.
                vec3 a_hsv = rgb2hsv(armor_color.rgb);
                vec3 target = vec3(
                        a_hsv.x,
                        clamp(mix(hsv0.y, a_hsv.y, 0.55), 0.25, 1.0),
                        hsv0.z);
                enhanced = mix(enhanced, hsv2rgb(target), cloth_strength);
        } else if (is_metal) {
                // acciaio/pietra: tinta armatura modulata dalla luminanza
                // (le parti scure restano scure, i riflessi restano chiari).
                vec3 tint = armor_color.rgb * (0.45 + 0.75 * hsv0.z);
                enhanced = mix(enhanced, tint, metal_strength);
        }

        // --- 5. Rim light (bordo illuminato) ---
        float edge = 0.0;
        if (a_u < 0.1) edge = max(edge, 1.0);
        if (a_d < 0.1) edge = max(edge, 1.0);
        if (a_l < 0.1) edge = max(edge, 1.0);
        if (a_r < 0.1) edge = max(edge, 1.0);
        vec3 rim_col = armor_active
                        ? clamp(armor_color.rgb * 1.3 + 0.05, 0.0, 1.0)
                        : vec3(1.0, 0.92, 0.7);
        float rim_amt = armor_active ? armor_rim : rim_intensity;
        enhanced += rim_col * rim_amt * edge;

        COLOR = vec4(clamp(enhanced, 0.0, 1.0), tex.a);
}
