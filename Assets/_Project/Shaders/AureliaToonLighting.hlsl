#ifndef AURELIA_TOON_LIGHTING_INCLUDED
#define AURELIA_TOON_LIGHTING_INCLUDED

// ============================================================
// Fungsi cahaya toon bersama — dipakai Pass Forward di
// AureliaToon dan AureliaToonLite supaya hasilnya IDENTIK.
//
// Modelnya: diffuse bertingkat 2-4 dengan tepi HALUS (bukan
// posterize keras), bayangan berwarna (bukan hitam), rim lembut,
// specular anime yang mengeras di tengah. Satu directional light
// + ambient SH — cukup untuk stylized mobile.
// ============================================================

// Tingkat bertingkat dengan tepi antialiased.
// t: 0..1 (cahaya), steps: 2..4, softness: 0 (keras) .. 0.5 (halus total).
float AureliaSoftStep(float t, float steps, float softness)
{
    float x = saturate(t) * steps;
    float band = floor(x);
    float f = frac(x);
    band += smoothstep(0.5 - softness, 0.5 + softness, f);
    return band / steps;
}

// Warna cahaya toon: putih di terang, _ShadowColor di gelap.
// rampT: 0..1 dari half-lambert. atten: 0..1 bayangan peta.
// rampSample: warna dari tekstur ramp (sudah di-sample pemanggil).
half3 AureliaToonLight(float rampT, float atten,
                       float steps, float softness, float rampStrength,
                       half3 rampSample, half3 shadowColor)
{
    float stepped = AureliaSoftStep(rampT * atten, steps, softness);
    half3 procedural = lerp(shadowColor, half3(1.0, 1.0, 1.0), stepped);
    return lerp(procedural, rampSample, saturate(rampStrength));
}

#endif
