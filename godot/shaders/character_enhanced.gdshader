// character_enhanced.gdshader
// Shader combinato per personaggi: detail enhance + rim light + depth.
// Applica tutti gli enhancement in un solo passaggio per le performance.
shader_type canvas_item;

uniform float sharpness : hint_range(0.0, 2.0) = 0.6;
uniform float contrast : hint_range(0.5, 2.0) = 1.12;
uniform float saturation : hint_range(0.5, 2.0) = 1.18;
uniform vec4 rim_color : source_color = vec4(1.0, 0.92, 0.7, 1.0);
uniform float rim_intensity : hint_range(0.0, 2.0) = 0.5;
uniform vec2 light_dir = vec2(0.5, -0.7);
uniform vec4 light_tint : source_color = vec4(1.0, 0.95, 0.85, 1.0);
uniform vec4 shadow_tint : source_color = vec4(0.35, 0.3, 0.45, 1.0);
uniform float depth_strength : hint_range(0.0, 1.5) = 0.5;

void fragment() {
        vec4 tex = texture(TEXTURE, UV);
        if (tex.a < 0.1) {
                discard;
        }
        vec2 size = TEXTURE_PIXEL_SIZE;

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

        // --- 4. Rim light (bordo illuminato) ---
        float alpha_up = texture(TEXTURE, UV + vec2(0.0, -size.y)).a;
        float alpha_down = texture(TEXTURE, UV + vec2(0.0, size.y)).a;
        float alpha_left = texture(TEXTURE, UV + vec2(-size.x, 0.0)).a;
        float alpha_right = texture(TEXTURE, UV + vec2(size.x, 0.0)).a;
        float edge = 0.0;
        if (alpha_up < 0.1) edge = max(edge, 1.0);
        if (alpha_down < 0.1) edge = max(edge, 1.0);
        if (alpha_left < 0.1) edge = max(edge, 1.0);
        if (alpha_right < 0.1) edge = max(edge, 1.0);
        enhanced += rim_color.rgb * rim_intensity * edge;

        COLOR = vec4(clamp(enhanced, 0.0, 1.0), tex.a);
}
