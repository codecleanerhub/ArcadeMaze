// walk_cycle.gdshader
// ============================================================================
// Light/shadow effect shader that complements DeformableSprite.
//
// DeformableSprite handles the mesh deformation (leg swing, breathing, attack
// pulse). This shader adds a procedural light/shadow modulation on top of the
// sprite to enhance the perceived motion:
//
//   * A directional "moonlight" gradient from upper-left
//   * A pulsing warm light when walking (simulates torch light bouncing)
//   * A subtle drop shadow underneath the sprite
//   * Color saturation boost for the "active" frame
//
// Usage: attach as a ShaderMaterial to a Sprite2D / CanvasItem that already
// displays the sprite (e.g. the Enemy's main Sprite2D). DeformableSprite's
// own mesh uses a StandardMaterial3D and does not need this; the shader is
// for any CanvasItem rendering that complements the deform.
//
// Uniforms (all controllable from GDScript):
//   walk_phase   : 0.0 = idle, >0.0 = walking (ramps up the warm pulse)
//   walk_speed   : controls pulse rate (default 8.0 = ~1.3 Hz)
//   facing_right : 1.0 = facing right, 0.0 = facing left (flips light direction)
//   time         : elapsed seconds (set every frame from GDScript)
//   accent_color : per-enemy accent (warm orange for demons, cyan for wraiths,
//                  etc.) - mixed into the warm pulse
// ============================================================================

shader_type canvas_item;

uniform float walk_phase : hint_range(0.0, 1.0) = 0.0;
uniform float walk_speed : hint_range(1.0, 20.0) = 8.0;
uniform float facing_right : hint_range(0.0, 1.0) = 1.0;
uniform float time = 0.0;
uniform vec4 accent_color : source_color = vec4(1.0, 0.5, 0.2, 1.0);
uniform float shadow_strength : hint_range(0.0, 1.0) = 0.35;
uniform float saturation_boost : hint_range(0.8, 1.5) = 1.12;

void vertex() {
        // Vertex shader: nothing to do; the deformation is handled by
        // DeformableSprite's mesh. This shader is applied to the CanvasItem
        // that draws the sprite (e.g. via draw_texture_rect), so the vertex
        // positions are the standard quad corners.
}

void fragment() {
        // Sample the underlying texture.
        vec4 col = texture(TEXTURE, UV);
        if (col.a < 0.01) {
                discard;
        }

        // --- Directional moonlight from upper-left ---
        // Light vector points from upper-left toward lower-right. The brighter
        // side is the upper-left; the darker side is the lower-right.
        vec2 light_dir = vec2(-0.6, -0.8);  // upper-left direction
        if (facing_right < 0.5) {
                light_dir.x = 0.6;  // flip when facing left
        }
        float light_amount = dot(normalize(UV - 0.5) * vec2(1.0, -1.0), -light_dir);
        light_amount = clamp(light_amount * 0.5 + 0.5, 0.0, 1.0);

        // Base ambient + directional light
        vec3 ambient = vec3(0.55, 0.55, 0.65);
        vec3 directional = vec3(0.45, 0.40, 0.30) * light_amount;
        vec3 lit = col.rgb * (ambient + directional);

        // --- Warm pulse when walking ---
        // Simulates torch light bouncing off the sprite as it moves. Pulses
        // at walk_speed Hz. The accent_color tints the pulse so each enemy
        // type has its own walking "signature".
        float pulse = 0.0;
        if (walk_phase > 0.0) {
                pulse = sin(time * walk_speed) * 0.5 + 0.5;  // 0..1
                pulse = pow(pulse, 1.5) * walk_phase;        // shape + ramp
        }
        vec3 warm_light = accent_color.rgb * pulse * 0.25;
        lit += warm_light;

        // --- Subtle drop shadow at the bottom of the sprite ---
        // Strength varies with walk_phase (stronger shadow when moving).
        float bottom_factor = smoothstep(0.7, 1.0, UV.y);
        float shadow = bottom_factor * shadow_strength * (0.7 + 0.3 * walk_phase);
        lit *= (1.0 - shadow * 0.4);

        // --- Saturation boost (gives the sprite a more "active" look) ---
        float gray = dot(lit, vec3(0.299, 0.587, 0.114));
        lit = mix(vec3(gray), lit, saturation_boost);

        COLOR = vec4(lit, col.a);
}
