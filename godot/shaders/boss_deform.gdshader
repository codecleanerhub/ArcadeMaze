// boss_deform.gdshader — TASK 26: enhancement canvas_item per i boss.
// ====================================================================
// I boss renderizzano via DeformableSprite (MeshInstance2D) con un
// StandardMaterial3D sulla superficie del mesh: pipeline 3D in cui lo
// shader canvas_item del nodo Boss NON ha effetto (i materiali CanvasItem
// non si propagano ai figli) -> nessuno sharpening/contrasto/rim, e la
// conversione di colore della pipeline 3D su mesh 2D puo' slavare i colori
// ("boss sbiaditi" segnalati dall'utente).
// Questo shader campiona ESPPLICITAMENTE la texture via uniform (non si
// affida al binding del TEXTURE built-in, non garantito sui MeshInstance2D)
// e replica la pipeline di character_enhanced.gdshader (sharpening +
// contrasto/saturazione + fake normal + rim light) con i parametri
// "strong" riservati ai boss (sharpness .8 / contrast 1.2 / sat 1.3 /
// rim .7 / depth .7 = CharacterArt._enhanced_strong).
// `texel_size` va impostato dal chiamante (1/width, 1/height della sheet).
shader_type canvas_item;

uniform sampler2D src_tex;
uniform vec2 texel_size = vec2(0.0009765625, 0.00390625);
uniform float sharpness : hint_range(0.0, 2.0) = 0.8;
uniform float contrast : hint_range(0.5, 2.0) = 1.2;
uniform float saturation : hint_range(0.5, 2.0) = 1.3;
uniform vec4 rim_color : source_color = vec4(1.0, 0.92, 0.7, 1.0);
uniform float rim_intensity : hint_range(0.0, 2.0) = 0.7;
uniform vec2 light_dir = vec2(0.5, -0.7);
uniform vec4 light_tint : source_color = vec4(1.0, 0.95, 0.85, 1.0);
uniform vec4 shadow_tint : source_color = vec4(0.35, 0.3, 0.45, 1.0);
uniform float depth_strength : hint_range(0.0, 1.5) = 0.7;

void fragment() {
        vec4 tex = texture(src_tex, UV);
        if (tex.a < 0.1) {
                discard;
        }
        vec2 px = texel_size;

        // --- 1. Unsharp masking (sharpening) ---
        vec4 blur = (
                texture(src_tex, UV + vec2(-px.x, 0.0)) +
                texture(src_tex, UV + vec2(px.x, 0.0)) +
                texture(src_tex, UV + vec2(0.0, -px.y)) +
                texture(src_tex, UV + vec2(0.0, px.y))
        ) * 0.25;
        vec3 enhanced = tex.rgb + (tex.rgb - blur.rgb) * sharpness;

        // --- 2. Contrast + saturation ---
        enhanced = (enhanced - 0.5) * contrast + 0.5;
        float gray = dot(enhanced, vec3(0.299, 0.587, 0.114));
        enhanced = mix(vec3(gray), enhanced, saturation);

        // --- 3. Fake normal map per profondita' (gradiente alpha) ---
        float a_l = texture(src_tex, UV - vec2(px.x, 0.0)).a;
        float a_r = texture(src_tex, UV + vec2(px.x, 0.0)).a;
        float a_u = texture(src_tex, UV - vec2(0.0, px.y)).a;
        float a_d = texture(src_tex, UV + vec2(0.0, px.y)).a;
        vec3 normal = normalize(vec3(
                (a_l - a_r) * depth_strength,
                (a_u - a_d) * depth_strength,
                1.0
        ));
        vec3 light = normalize(vec3(light_dir.x, light_dir.y, 0.8));
        float ndotl = max(dot(normal, light), 0.0);
        vec3 lit_tint = mix(shadow_tint.rgb, light_tint.rgb, ndotl);
        enhanced *= lit_tint;

        // --- 4. Rim light (bordo illuminato) ---
        float edge = 0.0;
        if (a_u < 0.1) { edge = max(edge, 1.0); }
        if (a_d < 0.1) { edge = max(edge, 1.0); }
        if (a_l < 0.1) { edge = max(edge, 1.0); }
        if (a_r < 0.1) { edge = max(edge, 1.0); }
        enhanced += rim_color.rgb * rim_intensity * edge;

        COLOR = vec4(clamp(enhanced, 0.0, 1.0), tex.a);
}
