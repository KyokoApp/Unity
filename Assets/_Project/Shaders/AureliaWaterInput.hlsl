#ifndef AURELIA_WATER_INPUT_INCLUDED
#define AURELIA_WATER_INPUT_INCLUDED

// Cbuffer tunggal material air — lihat catatan SRP Batcher di
// AureliaTerrainInput.hlsl (aturan yang sama berlaku di sini).

CBUFFER_START(UnityPerMaterial)
    float4 _ShallowColor;
    float4 _DeepColor;
    float  _WaveHeight;
    float  _WaveScale;
    float  _WaveSpeed;
    float  _WaveSpeed2;
    float  _FresnelPower;
    float  _FresnelBoost;
    float  _Specular;
    float  _Shininess;
    float  _GlitterStrength;
CBUFFER_END

#endif
