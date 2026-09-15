// ============================================================
// AureliaWaterCel.shader — air cel-shading Genshin-style
// - Warna shallow/deep dengan cel ramp
// - Gelombang dari posisi dunia + waktu
// - Fresnel + specular stepped
// - Fog
// ============================================================
Shader "Aurelia/WaterCel"
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
        _CelStep       ("Cel Step", Range(0,1)) = 0.5
        _CelFeather    ("Cel Feather", Range(0.001,0.3)) = 0.1
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
            #include "Assets/_Project/Shaders/AureliaCel.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float3 normalWS   : TEXCOORD1;
                float  fogFactor  : TEXCOORD2;
            };

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
                float _CelStep;
                float _CelFeather;
            CBUFFER_END

            float WaveHeight(float2 wp, float t)
            {
                float a = sin((wp.x + wp.y) * _WaveScale + t * _WaveSpeed);
                float b = sin((wp.x - wp.y * 1.3) * _WaveScale * 1.7 + t * _WaveSpeed2);
                float c = sin(wp.y * _WaveScale * 0.6 - t * _WaveSpeed * 0.7);
                return (a * 0.5 + b * 0.3 + c * 0.2) * _WaveHeight;
            }

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                float3 ws = TransformObjectToWorld(IN.positionOS.xyz);
                float t = _Time.y;
                ws.y += WaveHeight(ws.xz, t);

                float e = 0.25;
                float hx = WaveHeight(ws.xz + float2(e, 0), t) - WaveHeight(ws.xz - float2(e, 0), t);
                float hz = WaveHeight(ws.xz + float2(0, e), t) - WaveHeight(ws.xz - float2(0, e), t);
                float3 n = normalize(float3(-hx / (2 * e), 1.0, -hz / (2 * e)));

                OUT.positionWS = ws;
                OUT.normalWS = TransformObjectToWorldNormal(n);
                OUT.positionCS = TransformWorldToHClip(ws);
                OUT.fogFactor = ComputeFogFactor(OUT.positionCS.z);
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                float4 shadowCoord = TransformWorldToShadowCoord(IN.positionWS);
                Light mainLight = GetMainLight(shadowCoord);

                half3 N = normalize(IN.normalWS);
                half3 V = normalize(GetWorldSpaceViewDir(IN.positionWS));

                float fres = pow(saturate(1.0 - dot(N, V)), _FresnelPower);
                half4 baseCol = lerp(_DeepColor, _ShallowColor, saturate(dot(N, V)));

                // Cel shading untuk air: quantize fresnel
                half cel = CelRamp2(fres, _CelStep, _CelFeather);
                half3 col = baseCol.rgb + cel * _FresnelBoost * _ShallowColor.rgb * 0.5;

                half3 H = normalize(mainLight.direction + V);
                float spec = pow(saturate(dot(N, H)), _Shininess);
                // Stepped specular
                spec = smoothstep(0.85, 0.86, spec);
                col += mainLight.color * spec * _Specular * mainLight.shadowAttenuation;

                col += SampleSH(N) * baseCol.rgb * 0.35;
                col = MixFog(col, IN.fogFactor);

                half alpha = saturate(baseCol.a + fres * 0.35);
                return half4(col, alpha);
            }
            ENDHLSL
        }
    }

    FallBack "Universal Render Pipeline/Unlit"
}
