// screen_vignette.gdshader
// Post-processing: vignette + leggero bloom per dare profondita' alla scena.
shader_type canvas_item;

uniform float vignette_intensity : hint_range(0.0, 2.0) = 0.8;
uniform vec3 vignette_color : source_color = vec3(0.0, 0.0, 0.0);

void fragment() {
        vec4 col = texture(TEXTURE, UV);
        // Vignette: scurisce i bordi
        vec2 center = UV - 0.5;
        float dist = length(center);
        float vignette = smoothstep(0.3, 0.8, dist);
        col.rgb = mix(col.rgb, vignette_color, vignette * vignette_intensity);
        COLOR = col;
}
