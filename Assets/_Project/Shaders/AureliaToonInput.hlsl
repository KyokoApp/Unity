#ifndef AURELIA_TOON_INPUT_INCLUDED
#define AURELIA_TOON_INPUT_INCLUDED

// ============================================================
// Properti material toon, dideklarasikan SEKALI di sini dan
// di-include oleh SEMUA Pass (Forward, Outline, ShadowCaster)
// di AureliaToon maupun AureliaToonLite.
//
// Syarat SRP Batcher (sama seperti terrain): semua properti
// material di dalam CBUFFER UnityPerMaterial, isinya IDENTIK
// di setiap Pass. Dicek mekanis oleh
// _verify/shaders/check_shader.py — kalau tidak cocok, CI merah.
//
// Yang SENGAJA tidak ada di sini: _BaseMap dan _RampMap.
// Tekstur + sampler TIDAK boleh di dalam cbuffer (aturan Unity);
// mereka dideklarasikan di file .shader lewat TEXTURE2D().
// ============================================================

CBUFFER_START(UnityPerMaterial)
    float4 _BaseColor;
    float  _RampStrength;
    float  _ToonSteps;
    float  _ToonSoftness;
    float4 _ShadowColor;
    float  _AmbientBoost;
    float4 _OutlineColor;
    float  _OutlineWidth;
    float4 _RimColor;
    float  _RimPower;
    float  _RimStrength;
    float4 _SpecColor;
    float  _SpecPower;
    float  _SpecStrength;
    float4 _EmissionColor;
    float  _EmissionStrength;
    // Blok surface ala URP Lit: opaque/transparent/cutout dipilih
    // PER MATERIAL (bukan per shader), supaya 43 material VRM yang
    // campur opaque + transparan bisa memakai satu shader toon.
    float _Surface;
    float _Blend;
    float _SrcBlend;
    float _DstBlend;
    float _ZWrite;
    float _Cull;
    float _AlphaClip;
    float _Cutoff;
CBUFFER_END

#endif
