// normal_depth.gdshader
// Shader per personaggi: simula una normal map per dare profondita'
// e volume agli sprite 2D. Genera illuminazione direzionale finta.
shader_type canvas_item;

// Direzione della luce (normalizzata)
uniform vec2 light_dir = vec2(0.5, -0.7);
// Colore della luce
uniform vec4 light_color : source_color = vec4(1.0, 0.95, 0.8, 1.0);
// Colore dell'ombra
uniform vec4 shadow_color : source_color = vec4(0.3, 0.25, 0.4, 1.0);
// Intensita' dell'effetto 3D
uniform float depth_strength : hint_range(0.0, 2.0) = 0.7;

void fragment() {
        vec4 tex = texture(TEXTURE, UV);
        if (tex.a < 0.1) {
                discard;
        }
        // Genera una finta normal map dai gradienti del canale alpha
        vec2 size = TEXTURE_PIXEL_SIZE;
        float a_l = texture(TEXTURE, UV - vec2(size.x, 0.0)).a;
        float a_r = texture(TEXTURE, UV + vec2(size.x, 0.0)).a;
        float a_u = texture(TEXTURE, UV - vec2(0.0, size.y)).a;
        float a_d = texture(TEXTURE, UV + vec2(0.0, size.y)).a;
        // Gradiente = direzione della normale (finta)
        vec3 normal = normalize(vec3(
                (a_l - a_r) * depth_strength,
                (a_u - a_d) * depth_strength,
                1.0
        ));
        // Calcola illuminazione direzionale
        vec3 light = normalize(vec3(light_dir.x, light_dir.y, 0.8));
        float ndotl = max(dot(normal, light), 0.0);
        // Mix tra ombra e luce
        vec3 lit_color = mix(shadow_color.rgb, light_color.rgb, ndotl);
        // Combina con il colore originale
        vec3 final_col = tex.rgb * lit_color;
        COLOR = vec4(final_col, tex.a);
}
