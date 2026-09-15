#ifndef AURELIA_TERRAIN_INPUT_INCLUDED
#define AURELIA_TERRAIN_INPUT_INCLUDED

// Semua properti material terrain, dideklarasikan SEKALI di sini
// dan di-include oleh SETIAP Pass. SRP Batcher butuh identik.

CBUFFER_START(UnityPerMaterial)
    float _DetailScale;
    float _DetailStrength;
    float _LargeScale;
    float _LargeStrength;
    float _AmbientBoost;
    float _ShadowStep;
    float _MidStep;
    float _Feather;
    float4 _ShadowTint;
CBUFFER_END

#endif
