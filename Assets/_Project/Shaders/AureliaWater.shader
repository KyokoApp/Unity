// ============================================================
// AureliaWater.shader
//
// Air stylized: quad DATAR 1 segmen (4 verteks), SEMUA gelombang
// dihitung di FRAGMENT dari posisi dunia + waktu.
//
// Kenapa tidak di vertex (perbaikan bug Tahap 5): quad 8x8 di atas
// bentang 1.400 m berarti 1 verteks tiap 175 m, sementara panjang
// gelombangnya ~110 m — displacement vertex-nya undersampling
// parah dan gelombangnya terlihat acak/nempel. Normal fragment
// tidak punya masalah itu dan justru lebih murah (4 verteks).
//
// Gaya: fresnel lembut + kilau matahari mengeras + glitter anime
// (titik cahaya berkelip di puncak gelombang). Tanpa refleksi/
// refraksi planar — terlalu mahal untuk target HP.
// ============================================================
Shader "Aurelia/Water"
{
    Properties
    {
        _ShallowColor  ("Shallow Color", Color) = (0.36, 0.58, 0.58, 0.55)
        _DeepColor     ("Deep Color", Color)    = (0.09, 0.24, 0.32, 0.88)
        _WaveHeight    ("Wave Height (m)", Float) = 0.06
        _WaveScale     ("Wave Scale", Float) = 0.055
        _WaveSpeed     ("Wave Speed", Float) = 0.55
        _WaveSpeed2    ("Wave Speed (lapis 2)", Float) = -0.33
        _FresnelPower  ("Fresnel Power", Range(0.5, 8)) = 3.0
        _FresnelBoost  ("Fresnel Boost", Range(0, 4)) = 1.6
        _Specular      ("Specular", Range(0, 4)) = 1.2
        _Shininess     ("Shininess", Range(4, 512)) = 96
        _GlitterStrength ("Glitter Anime", Range(0, 2)) = 0.8
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Transparent"
            "RenderPipeline" = "UniversalPipeline"
            "Queue" = "Transparent"
            "IgnoreProjector" = "True"
        }

        Pass
        {
            Name "WaterForward"
            Tags { "LightMode" = "UniversalForward" }

            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            Cull Back

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 2.0

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile_fog

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float  fogFactor  : TEXCOORD1;
            };

            #include "Assets/_Project/Shaders/AureliaWaterInput.hlsl"

            float WaveH(float2 wp, float t)
            {
                float a = sin((wp.x + wp.y) * _WaveScale + t * _WaveSpeed);
                float b = sin((wp.x - wp.y * 1.3) * _WaveScale * 1.7 + t * _WaveSpeed2);
                float c = sin(wp.y * _WaveScale * 0.6 - t * _WaveSpeed * 0.7);
                return (a * 0.5 + b * 0.3 + c * 0.2) * _WaveHeight;
            }

            float Hash21(float2 p)
            {
                p = frac(p * float2(123.34, 456.21));
                p += dot(p, p + 45.32);
                return frac(p.x * p.y);
            }

            Varyings vert(Attributes v)
            {
                Varyings o;
                float3 ws = TransformObjectToWorld(v.positionOS.xyz);
                o.positionWS = ws;
                o.positionCS = TransformWorldToHClip(ws);
                o.fogFactor = ComputeFogFactor(o.positionCS.z);
                return o;
            }

            half4 frag(Varyings v) : SV_Target
            {
                float4 shadowCoord = TransformWorldToShadowCoord(v.positionWS);
                Light mainLight = GetMainLight(shadowCoord);

                // Normal analitik dari turunan gelombang (beda terhingga).
                float t = _Time.y;
                float e = 0.35;
                float2 wp = v.positionWS.xz;
                float hx = WaveH(wp + float2(e, 0), t) - WaveH(wp - float2(e, 0), t);
                float hz = WaveH(wp + float2(0, e), t) - WaveH(wp - float2(0, e), t);
                half3 N = normalize(half3(-hx / (2.0 * e), 1.0, -hz / (2.0 * e)));
                half3 V = normalize(GetWorldSpaceViewDir(v.positionWS));

                float fres = pow(saturate(1.0 - dot(N, V)), _FresnelPower);
                half4 baseCol = lerp(_DeepColor, _ShallowColor, saturate(dot(N, V)));
                half3 col = baseCol.rgb + fres * _FresnelBoost * _ShallowColor.rgb;

                // Kilau matahari mengeras (toon) + glitter berkelip.
                half3 H = normalize(mainLight.direction + V);
                float spec = pow(saturate(dot(N, H)), _Shininess);
                float specBand = smoothstep(0.25, 0.75, spec);
                col += mainLight.color * specBand * _Specular * mainLight.shadowAttenuation;

                float cell = Hash21(floor(wp * 2.5) + floor(t * 2.0) * 0.37);
                float glitter = step(0.985 - specBand * 0.05, cell) * specBand;
                col += mainLight.color * glitter * _GlitterStrength;

                col += SampleSH(N) * baseCol.rgb * 0.35;
                col = MixFog(col, v.fogFactor);

                half alpha = saturate(baseCol.a + fres * 0.35);
                return half4(col, alpha);
            }
            ENDHLSL
        }
    }

    FallBack "Universal Render Pipeline/Unlit"
}
