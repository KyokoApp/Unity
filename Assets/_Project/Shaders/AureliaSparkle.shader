// ============================================================
// AureliaSparkle.shader — partikel anime (sparkle, sihir, skill).
//
// Unlit additive: inti bersinar + garis silang 4-titik (model
// "kilau" ala anime), tanpa tekstur — bentuknya murni dari UV.
// Warna PER PARTIKEL lewat instancing (_InstColor), diisi oleh
// AnimeVFX.cs lewat MaterialPropertyBlock. Billboard dikerjakan
// di CPU (matriks sudah menghadap kamera), jadi shader ini kecil
// dan lolos target 2.0 untuk HP lama.
//
// VFX Graph SENGAJA tidak dipakai: butuh compute shader yang tidak
// ada di sebagian GPU Android kelas bawah. Pool CPU + 1 draw call
// instanced ini jalan di semua perangkat.
// ============================================================
Shader "Aurelia/Sparkle"
{
    Properties
    {
        _Tint ("Tint Global", Color) = (1, 1, 1, 1)
        _Intensity ("Intensitas", Range(0, 4)) = 2
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
            Name "Sparkle"
            Tags { "LightMode" = "SRPDefaultUnlit" }

            Blend One One
            ZWrite Off
            ZTest LEqual
            Cull Off

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 2.0
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv         : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            CBUFFER_START(UnityPerMaterial)
                float4 _Tint;
                float  _Intensity;
            CBUFFER_END

            UNITY_INSTANCING_BUFFER_START(Props)
                UNITY_DEFINE_INSTANCED_PROP(float4, _InstColor)
            UNITY_INSTANCING_BUFFER_END(Props)

            Varyings vert(Attributes v)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_TRANSFER_INSTANCE_ID(v, o);
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                o.uv = v.uv;
                return o;
            }

            half4 frag(Varyings v) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(v);
                half4 inst = UNITY_ACCESS_INSTANCED_PROP(Props, _InstColor);

                float2 p = v.uv - 0.5;
                float core = pow(saturate(1.0 - length(p) * 2.4), 2.0);
                float sx = pow(saturate(1.0 - abs(p.y) * 7.0), 2.0)
                         * pow(saturate(1.0 - abs(p.x) * 2.0), 1.5);
                float sy = pow(saturate(1.0 - abs(p.x) * 7.0), 2.0)
                         * pow(saturate(1.0 - abs(p.y) * 2.0), 1.5);
                float a = core + (sx + sy) * 0.8;

                half3 col = inst.rgb * _Tint.rgb * (a * _Intensity * inst.a);
                return half4(col, 1.0);
            }
            ENDHLSL
        }
    }

    FallBack Off
}
