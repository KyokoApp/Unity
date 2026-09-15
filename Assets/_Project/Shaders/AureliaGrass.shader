// ============================================================
// AureliaGrass.shader — rumput cel-shading Genshin-style (FIX)
// - Opaque, tanpa alpha
// - Cel ramp 2 tingkat (shadow/high) untuk kesan toon
// - Angin di vertex, fade via tenggelam
// - FIX: clear bug + cel shading
// ============================================================
Shader "Aurelia/Grass"
{
    Properties
    {
        _BaseColor     ("Warna Pangkal", Color) = (0.16, 0.34, 0.13, 1)
        _TipColor      ("Warna Ujung",   Color) = (0.45, 0.66, 0.24, 1)
        _ShadowColor   ("Warna Bayangan", Color) = (0.12, 0.22, 0.10, 1)
        _WindStrength  ("Kekuatan Angin (m)", Range(0, 0.6)) = 0.16
        _WindSpeed     ("Kecepatan Angin", Range(0, 4)) = 1.1
        _FadeStart     ("Mulai Tenggelam (m)", Range(10, 80)) = 22
        _FadeEnd       ("Tenggelam Penuh (m)", Range(20, 120)) = 30
        _CelStep       ("Cel Step", Range(0, 1)) = 0.35
        _CelFeather    ("Cel Feather", Range(0.001, 0.3)) = 0.08
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
            "Queue" = "Geometry"
        }

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }
            Cull Off

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.0
            #pragma multi_compile_fog
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Assets/_Project/Shaders/AureliaCel.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 normalWS   : NORMAL;
                float2 uv         : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float  fogFactor  : TEXCOORD2;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
                float4 _TipColor;
                float4 _ShadowColor;
                float  _WindStrength;
                float  _WindSpeed;
                float  _FadeStart;
                float  _FadeEnd;
                float  _CelStep;
                float  _CelFeather;
            CBUFFER_END

            static float Hash21(float2 p)
            {
                p = frac(p * float2(123.34, 456.21));
                p += dot(p, p + 45.32);
                return frac(p.x * p.y);
            }

            Varyings vert(Attributes i)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(i);
                UNITY_TRANSFER_INSTANCE_ID(i, o);

                float3 originWS = TransformObjectToWorld(float3(0, 0, 0));
                float  h        = Hash21(originWS.xz);

                float t   = _Time.y * _WindSpeed;
                float w1  = sin(t * 1.7 + originWS.x * 0.35 + originWS.z * 0.22);
                float w2  = sin(t * 3.9 + originWS.x * 0.11 - originWS.z * 0.31) * 0.35;
                float amp = (w1 + w2) * _WindStrength * i.uv.y * i.uv.y;

                float3 posOS = i.positionOS;
                posOS.x += amp;
                posOS.z += amp * 0.6;

                float3 positionWS = TransformObjectToWorld(posOS);
                o.normalWS = TransformObjectToWorldNormal(i.normalOS);

                float dist  = distance(positionWS, GetCameraPositionWS());
                float fade  = 1.0 - smoothstep(_FadeStart, _FadeEnd, dist);
                positionWS  = lerp(originWS, positionWS, fade);

                o.uv = float2(i.uv.x, i.uv.y * (0.92 + h * 0.16));

                o.positionWS = positionWS;
                o.positionCS = TransformWorldToHClip(positionWS);
                o.fogFactor  = ComputeFogFactor(o.positionCS.z);
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);

                half3 albedo = lerp((half3)_BaseColor.rgb, (half3)_TipColor.rgb, saturate(i.uv.y));

                Light main = GetMainLight();
                half3 N = normalize(i.normalWS);
                half ndl = dot(N, main.direction) * 0.5 + 0.5;

                half cel = CelRamp2(ndl, _CelStep, _CelFeather);
                half3 shadowAlbedo = _ShadowColor.rgb;
                half3 celAlbedo = lerp(shadowAlbedo, albedo, cel);

                half3 lit = celAlbedo * main.color * (cel * 0.7 + 0.3) * main.shadowAttenuation;
                lit += celAlbedo * SampleSH(N) * 0.6;

                half4 col = half4(lit, 1.0);
                col.rgb = MixFog(col.rgb, i.fogFactor);
                return col;
            }
            ENDHLSL
        }
    }

    FallBack Off
}
