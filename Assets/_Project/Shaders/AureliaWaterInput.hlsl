#ifndef AURELIA_WATER_INPUT_INCLUDED
#define AURELIA_WATER_INPUT_INCLUDED

// Alasan file ini ada sama persis dengan AureliaTerrainInput.hlsl:
// SRP Batcher butuh properti material di dalam CBUFFER UnityPerMaterial,
// identik di setiap Pass.

CBUFFER_START(UnityPerMaterial)
    half4 _ShallowColor;
    half4 _DeepColor;
    float _WaveHeight;
    float _WaveScale;
    float _WaveSpeed;
    float _WaveSpeed2;
    float _FresnelPower;
    float _FresnelBoost;
    float _Specular;
    float _Shininess;
CBUFFER_END

#endif
