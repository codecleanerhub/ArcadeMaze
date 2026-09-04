// rim_light.gdshader
// Shader per personaggi: aggiunge luce sul contorno (rim lighting)
// per dare profondita' e separare il sprite dallo sfondo.
// Questo e' un vantaggio Godot-native: dfeinisce meglio la silhouette.
shader_type canvas_item;

// Colore della luce di contorno (default: bianco caldo)
uniform vec4 rim_color : source_color = vec4(1.0, 0.95, 0.8, 1.0);
// Intensita' della luce di contorno (0 = spento, 1 = massimo)
uniform float rim_intensity : hint_range(0.0, 2.0) = 0.6;
// Spessore del bordo illuminato (in UV units)
uniform float rim_width : hint_range(0.0, 0.1) = 0.02;

void fragment() {
        vec4 tex = texture(TEXTURE, UV);
        if (tex.a < 0.1) {
                discard;
        }
        // Campiona i pixel adiacenti per rilevare i bordi
        vec2 size = TEXTURE_PIXEL_SIZE;
        float alpha_up = texture(TEXTURE, UV + vec2(0.0, -size.y)).a;
        float alpha_down = texture(TEXTURE, UV + vec2(0.0, size.y)).a;
        float alpha_left = texture(TEXTURE, UV + vec2(-size.x, 0.0)).a;
        float alpha_right = texture(TEXTURE, UV + vec2(size.x, 0.0)).a;
        // Se un pixel adiacente e' trasparente, siamo sul bordo
        float edge = 0.0;
        if (alpha_up < 0.1) edge = max(edge, 1.0);
        if (alpha_down < 0.1) edge = max(edge, 1.0);
        if (alpha_left < 0.1) edge = max(edge, 1.0);
        if (alpha_right < 0.1) edge = max(edge, 1.0);
        // Applica la luce di contorno
        vec3 rim = rim_color.rgb * rim_intensity * edge;
        vec3 final_col = tex.rgb + rim;
        COLOR = vec4(final_col, tex.a);
}
