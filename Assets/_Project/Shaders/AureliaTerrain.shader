// ============================================================
// AureliaTerrain.shader
//
// UNLIT vertex color. Bukan lit/shadow/fog.
//
// Screenshot HP 2026-09-16 + build CI ke-5: shader lit
// (GetMainLight × SampleSH × MixFog) menghasilkan HITAM PEKAT
// di GLES/Vulkan walau 49 chunk hidup. Vertex color sudah
// diuji (TerrainMeshTests) dan cukup untuk "dunia kelihatan".
// Pencahayaan toon menyusul setelah HP menampilkan tanah.
// ============================================================
Shader "Aurelia/Terrain"
{
    Properties
    {
        _DetailScale    ("Detail Scale (per meter dunia)", Float) = 0.35
        _DetailStrength ("Detail Strength", Range(0, 0.5)) = 0.10
        _LargeScale     ("Large Variation Scale", Float) = 0.012
        _LargeStrength  ("Large Variation Strength", Range(0, 0.5)) = 0.14
        _AmbientBoost   ("Ambient Boost", Range(0, 2)) = 1.0
        _ToonSteps      ("Tingkat Cahaya Toon (2-5)", Range(2, 5)) = 3
        _ToonSoftness   ("Kelembutan Tingkat (0=keras)", Range(0, 0.5)) = 0.30
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
            "Queue" = "Geometry"
            "IgnoreProjector" = "True"
        }
        LOD 200

        Pass
        {
            Name "UnlitColor"
            Tags { "LightMode" = "UniversalForward" }

            ZWrite On
            Cull Back

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 2.0

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Assets/_Project/Shaders/AureliaTerrainInput.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                half4  color      : COLOR;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                half4  color      : TEXCOORD1;
            };

            float Hash21(float2 p)
            {
                p = frac(p * float2(123.34, 456.21));
                p += dot(p, p + 45.32);
                return frac(p.x * p.y);
            }

            float ValueNoise(float2 p)
            {
                float2 i = floor(p);
                float2 f = frac(p);
                f = f * f * (3.0 - 2.0 * f);
                float a = Hash21(i);
                float b = Hash21(i + float2(1, 0));
                float c = Hash21(i + float2(0, 1));
                float d = Hash21(i + float2(1, 1));
                return lerp(lerp(a, b, f.x), lerp(c, d, f.x), f.y);
            }

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                VertexPositionInputs vpi = GetVertexPositionInputs(IN.positionOS.xyz);
                OUT.positionCS = vpi.positionCS;
                OUT.positionWS = vpi.positionWS;
                OUT.color = IN.color;
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                float2 wp = IN.positionWS.xz;
                float fine   = ValueNoise(wp * _DetailScale) - 0.5;
                float coarse = ValueNoise(wp * _LargeScale + 17.3) - 0.5;
                half3 albedo = IN.color.rgb * (1.0 + fine * _DetailStrength * 2.0
                                                 + coarse * _LargeStrength * 2.0);
                albedo *= max(_AmbientBoost, 0.75);
                // Jaring: vertex color 0 (mesh rusak) tetap hijau padang,
                // jangan hitam.
                half lum = albedo.r + albedo.g + albedo.b;
                if (lum < 0.08)
                    albedo = half3(0.42, 0.56, 0.28);
                return half4(albedo, 1.0);
            }
            ENDHLSL
        }
    }

    FallBack Off
}
