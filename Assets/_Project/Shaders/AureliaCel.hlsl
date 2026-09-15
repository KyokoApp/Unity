#ifndef AURELIA_CEL_INCLUDED
#define AURELIA_CEL_INCLUDED

// ============================================================
// AureliaCel.hlsl — fungsi cel-shading ala Genshin
//
// Dipakai oleh semua shader Aurelia/*Cel
// - Ramp 3 tingkat (shadow/mid/high) dengan smoothstep kecil
// - Specular stepped
// - Rim light untuk karakter
// - Outline via inverted hull (di shader terpisah)
// ============================================================

// Ramp cel-shading 3 band: shadow, mid, highlight
// ndl: 0..1 (half lambert), shadowStep/midStep: batas band
// Contoh Genshin: shadow 0.3, mid 0.6, highlight 1.0
half CelRamp(half ndl, half shadowStep, half midStep, half feather)
{
    // feather kecil = garis tegas ala cel, besar = lebih halus
    half shadow = smoothstep(shadowStep - feather, shadowStep + feather, ndl);
    half mid = smoothstep(midStep - feather, midStep + feather, ndl);
    // 0..shadowStep = shadow (0.35), shadowStep..midStep = mid (0.65), midStep..1 = high (1.0)
    half ramp = lerp(0.35, 0.65, shadow);
    ramp = lerp(ramp, 1.0, mid);
    return ramp;
}

// Versi dengan 2 band saja (untuk rumput/terrain low)
half CelRamp2(half ndl, half step, half feather)
{
    return smoothstep(step - feather, step + feather, ndl) * 0.5 + 0.5;
}

// Specular stepped ala Genshin (bukan blinn halus)
half CelSpecular(half3 N, half3 H, half shininess, half threshold, half feather)
{
    half ndh = saturate(dot(N, H));
    half spec = pow(ndh, shininess);
    return smoothstep(threshold - feather, threshold + feather, spec);
}

// Rim light untuk karakter (fresnel terbalik)
half CelRim(half3 N, half3 V, half power, half threshold)
{
    half rim = 1.0 - saturate(dot(N, V));
    rim = pow(rim, power);
    return rim > threshold ? rim : 0;
}

// Hash & noise murah tanpa texture (untuk variasi terrain)
float Hash21Cel(float2 p)
{
    p = frac(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return frac(p.x * p.y);
}

float ValueNoiseCel(float2 p)
{
    float2 i = floor(p);
    float2 f = frac(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = Hash21Cel(i);
    float b = Hash21Cel(i + float2(1, 0));
    float c = Hash21Cel(i + float2(0, 1));
    float d = Hash21Cel(i + float2(1, 1));
    return lerp(lerp(a, b, f.x), lerp(c, d, f.x), f.y);
}

#endif
