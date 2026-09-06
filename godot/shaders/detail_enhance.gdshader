// detail_enhance.gdshader
// Shader per personaggi:增强 i dettagli dello sprite tramite unsharp masking.
// Rende i contorni piu' nitidi e i dettagli piu' visibili.
shader_type canvas_item;

uniform float sharpness : hint_range(0.0, 2.0) = 0.8;
uniform float contrast : hint_range(0.5, 2.0) = 1.15;
uniform float saturation : hint_range(0.5, 2.0) = 1.2;

void fragment() {
        vec4 tex = texture(TEXTURE, UV);
        if (tex.a < 0.1) {
                discard;
        }
        // Unsharp masking: campiona i pixel vicini e sottrai una versione sfocata
        vec2 size = TEXTURE_PIXEL_SIZE;
        vec4 blur = (
                texture(TEXTURE, UV + vec2(-size.x, 0.0)) +
                texture(TEXTURE, UV + vec2(size.x, 0.0)) +
                texture(TEXTURE, UV + vec2(0.0, -size.y)) +
                texture(TEXTURE, UV + vec2(0.0, size.y))
        ) * 0.25;
        // Dettaglio = originale - sfocato
        vec3 detail = (tex.rgb - blur.rgb) * sharpness;
        vec3 enhanced = tex.rgb + detail;
        // Aumenta contrasto
        enhanced = (enhanced - 0.5) * contrast + 0.5;
        // Aumenta saturazione
        float gray = dot(enhanced, vec3(0.299, 0.587, 0.114));
        enhanced = mix(vec3(gray), enhanced, saturation);
        COLOR = vec4(clamp(enhanced, 0.0, 1.0), tex.a);
}
