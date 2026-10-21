// glow.gdshader
// Shader per sprite 2D con effetto glow/bloom.
// Aggiunge un bagliore colorato attorno al sprite, controllabile via uniform.
// Questo e' un vantaggio nativo Godot che il C++/SFML non aveva.
shader_type canvas_item;

// Colore del glow (default oro per player/tesori)
uniform vec4 glow_color : source_color = vec4(1.0, 0.84, 0.0, 1.0);
// Intensita' del glow (0 = spento, 1 = massimo)
uniform float glow_intensity : hint_range(0.0, 2.0) = 0.5;
// Raggio del glow in pixel
uniform float glow_radius : hint_range(1.0, 32.0) = 8.0;

void fragment() {
        // Campiona il texture originale
        vec4 tex = texture(TEXTURE, UV);
        // Se il pixel e' trasparente (fuori dal sprite), disegna il glow
        if (tex.a < 0.1) {
                // Calcola la distanza dal bordo del sprite
                // Usando i derivative per stimare quanto siamo lontani
                vec2 size = 1.0 / TEXTURE_PIXEL_SIZE;
                vec2 center = vec2(0.5, 0.5);
                float dist = length((UV - center) * size);
                // Glow falls off with distance
                float glow = smoothstep(glow_radius, 0.0, dist) * glow_intensity;
                COLOR = vec4(glow_color.rgb, glow * glow_color.a);
        } else {
                // Pixel del sprite: aggiunge una leggera emissione
                COLOR = tex + vec4(glow_color.rgb * glow_intensity * 0.3, 0.0);
        }
}
