// fire.gdshader
// Shader per effetto fuoco su nemici che bruciano (chalice effect).
// Anima una texture di fiamma sul sprite con rumore procedurale.
shader_type canvas_item;

uniform float time;
uniform float burn_intensity : hint_range(0.0, 1.0) = 1.0;

// Hash function per rumore
float hash(vec2 p) {
        return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Rumore bilineare
float noise(vec2 p) {
        vec2 i = floor(p);
        vec2 f = fract(p);
        f = f * f * (3.0 - 2.0 * f);
        return mix(
                mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
                mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x),
                f.y
        );
}

void fragment() {
        vec4 tex = texture(TEXTURE, UV);
        if (tex.a < 0.1) {
                discard;
        }
        // Coordinate UV distorte dal rumore per effetto fiamma
        vec2 fire_uv = UV * 4.0;
        fire_uv.y -= time * 2.0;  // fiamma sale
        float n = noise(fire_uv);
        n += noise(fire_uv * 2.0) * 0.5;
        // Colore fuoco: giallo->arancione->rosso
        vec3 fire_col = mix(
                vec3(1.0, 0.2, 0.0),   // rosso
                vec3(1.0, 0.9, 0.2),   // giallo
                n
        );
        // Mix tra sprite originale e fuoco
        float fire_mask = n * burn_intensity;
        vec3 final_col = mix(tex.rgb, fire_col, fire_mask * 0.7);
        // Aumenta luminosita' dove il fuoco e' piu' forte
        final_col += fire_col * fire_mask * 0.3;
        COLOR = vec4(final_col, tex.a);
}
