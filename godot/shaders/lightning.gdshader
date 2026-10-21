// lightning.gdshader
// Shader per fulmini del scepter - effetto elettrico con scariche.
shader_type canvas_item;

uniform float time;
uniform float intensity : hint_range(0.0, 1.0) = 1.0;

float hash(vec2 p) {
        return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
        vec4 tex = texture(TEXTURE, UV);
        if (tex.a < 0.1) {
                discard;
        }
        // Scariche elettriche: linee zigzag animate
        float electric = step(0.92, hash(UV * 50.0 + time * 10.0));
        electric += step(0.95, hash(UV * 70.0 - time * 15.0)) * 0.5;
        // Colore elettrico: ciano/bianco
        vec3 spark_col = vec3(0.3, 0.8, 1.0);
        vec3 final_col = mix(tex.rgb, spark_col, electric * intensity * 0.6);
        // Flash bianco dove la scarica e' intensa
        final_col += vec3(1.0) * electric * intensity * 0.3;
        COLOR = vec4(final_col, tex.a);
}
