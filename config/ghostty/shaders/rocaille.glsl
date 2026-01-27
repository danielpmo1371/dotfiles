/*
    "Rocaille" by @XorDev - Modified for Ghostty
    Original: https://www.shadertoy.com/view/WXyczK

    EFFECT_STRENGTH: 0.0 (off) to 1.0 (full effect)
*/

#define EFFECT_STRENGTH 0.2

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    vec2 uv = fragCoord / iResolution.xy;
    vec4 terminal = texture(iChannel0, uv);

    // --- Rocaille effect ---
    vec2 v = iResolution.xy;
    vec2 p = (fragCoord * 2.0 - v) / v.y / 0.3;

    vec4 effect = vec4(0.0);

    for (float i = 0.0; i < 10.0; i += 1.0)
    {
        effect += (cos(i + vec4(0.0, 1.0, 2.0, 3.0)) + 1.0) / 6.0 / length(v);

        vec2 turbulence = p;
        for (float f = 1.0; f < 9.0; f += 1.0)
        {
            turbulence += sin(turbulence.yx * f + i + iTime) / f;
        }
        v = iResolution.xy;
    }

    effect = tanh(effect * effect);

    // Blend with terminal
    vec3 blended = terminal.rgb + effect.rgb * EFFECT_STRENGTH;
    fragColor = vec4(blended, terminal.a);
}
