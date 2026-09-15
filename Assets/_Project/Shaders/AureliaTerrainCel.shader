// ============================================================
// AureliaTerrainCel.shader — terrain cel-shading ala Genshin
//
// Beda dengan Aurelia/Terrain yang half-Lambert halus:
// - Diffuse di-quantize jadi 3 tingkat (shadow/mid/high) via CelRamp
// - Detail noise tetap ada tapi lebih subtle
// - Shadow tetap pakai mainLight.shadowAttenuation
// - SRP Batcher compatible (Properties == CBUFFER)
// ============================================================
Shader "Aurelia/TerrainCel"
{
    Properties
    {
        _DetailScale    ("Detail Scale", Float) = 0.35
        _DetailStrength ("Detail Strength", Range(0, 0.5)) = 0.10
        _LargeScale     ("Large Variation Scale", Float) = 0.012
        _LargeStrength  ("Large Variation Strength", Range(0, 0.5)) = 0.14
        _AmbientBoost   ("Ambient Boost", Range(0, 2)) = 1.0
        _ShadowStep     ("Cel Shadow Step", Range(0, 1)) = 0.28
        _MidStep        ("Cel Mid Step", Range(0, 1)) = 0.58
        _Feather        ("Cel Feather", Range(0.001, 0.2)) = 0.04
        _ShadowTint     ("Shadow Tint", Color) = (0.78, 0.82, 0.88, 1)
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
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 2.0
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile_fog

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Assets/_Project/Shaders/AureliaCel.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                half4  color      : COLOR;
            };

            struct Varyings
            {
                float4 positionCS  : SV_POSITION;
                float3 positionWS  : TEXCOORD0;
                float3 normalWS    : TEXCOORD1;
                half4  color       : TEXCOORD2;
                float  fogFactor   : TEXCOORD3;
            };

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

            // hash & noise dari cel include, tapi butuh yang lama juga untuk kompatibilitas
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
                VertexNormalInputs   vni = GetVertexNormalInputs(IN.normalOS);
                OUT.positionCS = vpi.positionCS;
                OUT.positionWS = vpi.positionWS;
                OUT.normalWS   = vni.normalWS;
                OUT.color      = IN.color;
                OUT.fogFactor  = ComputeFogFactor(vpi.positionCS.z);
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                float2 wp = IN.positionWS.xz;
                float fine   = ValueNoise(wp * _DetailScale) - 0.5;
                float coarse = ValueNoise(wp * _LargeScale + 17.3) - 0.5;
                half3 albedo = IN.color.rgb * (1.0 + fine * _DetailStrength * 2.0
                                                 + coarse * _LargeStrength * 2.0);

                float4 shadowCoord = TransformWorldToShadowCoord(IN.positionWS);
                Light mainLight = GetMainLight(shadowCoord);

                half3 N = normalize(IN.normalWS);
                half ndl = dot(N, mainLight.direction);
                half halfLambert = saturate(ndl * 0.5 + 0.5);

                // Cel ramp 3 tingkat ala Genshin
                half cel = CelRamp(halfLambert, _ShadowStep, _MidStep, _Feather);

                // Shadow tint: area shadow tidak hitam, tapi agak kebiruan seperti Genshin
                half3 shadowAlbedo = albedo * _ShadowTint.rgb;
                half3 litAlbedo = lerp(shadowAlbedo, albedo, cel);

                half3 ambient = SampleSH(N) * _AmbientBoost;
                half shadowAtten = mainLight.shadowAttenuation;

                // Di area shadow, pakai ambient + sedikit main light yang sudah di-tint
                // Di area terang, pakai full main light
                half3 lit = litAlbedo * (ambient + mainLight.color * mainLight.distanceAttenuation * shadowAtten * lerp(0.35, 1.0, cel));

                lit = MixFog(lit, IN.fogFactor);
                return half4(lit, 1.0);
            }
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }
            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull Back

            HLSLPROGRAM
            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment
            #pragma target 2.0

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

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

            float3 _LightDirection;
            float3 _LightPosition;

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; };
            struct Varyings   { float4 positionCS : SV_POSITION; };

            float4 GetShadowPositionHClip(Attributes input)
            {
                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 normalWS   = TransformObjectToWorldNormal(input.normalOS);
            #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                float3 lightDirWS = normalize(_LightPosition - positionWS);
            #else
                float3 lightDirWS = _LightDirection;
            #endif
                float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirWS));
            #if UNITY_REVERSED_Z
                positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
            #else
                positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
            #endif
                return positionCS;
            }

            Varyings ShadowPassVertex(Attributes input)
            {
                Varyings OUT;
                OUT.positionCS = GetShadowPositionHClip(input);
                return OUT;
            }

            half4 ShadowPassFragment(Varyings input) : SV_Target { return 0; }
            ENDHLSL
        }
    }

    FallBack "Universal Render Pipeline/Lit"
}
