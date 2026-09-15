// ============================================================
// AureliaCharCel.shader — karakter cel-shading ala Genshin Impact
//
// Fitur Genshin yang ditiru:
// - Diffuse ramp 3 tingkat (shadow/mid/high) dengan feather kecil
// - Shadow tint kebiruan (bukan hitam)
// - Specular stepped untuk rambut/kulit
// - Rim light untuk siluet
// - Outline via inverted hull (pass kedua)
// - Menerima texture base color (untuk VRM)
//
// Untuk VRM: MToon Built-in tidak support URP, jadi di VrmPrefabBuilder
// material MToon akan di-convert ke shader ini secara otomatis.
// ============================================================
Shader "Aurelia/CharCel"
{
    Properties
    {
        _BaseMap       ("Base Map", 2D) = "white" {}
        _BaseColor     ("Base Color", Color) = (1,1,1,1)
        _ShadeMap      ("Shade Map (optional)", 2D) = "white" {}
        _ShadeColor    ("Shade Color", Color) = (0.78, 0.82, 0.90, 1)
        _ShadowStep    ("Shadow Step", Range(0,1)) = 0.32
        _MidStep       ("Mid Step", Range(0,1)) = 0.62
        _Feather       ("Feather", Range(0.001,0.2)) = 0.05
        _SpecColor     ("Specular Color", Color) = (1,1,1,1)
        _Shininess     ("Shininess", Range(4,128)) = 32
        _SpecThreshold ("Spec Threshold", Range(0,1)) = 0.8
        _RimColor      ("Rim Color", Color) = (0.8, 0.9, 1, 0.6)
        _RimPower      ("Rim Power", Range(0.5,8)) = 3.5
        _RimThreshold  ("Rim Threshold", Range(0,1)) = 0.5
        _OutlineWidth  ("Outline Width", Range(0,0.1)) = 0.02
        _OutlineColor  ("Outline Color", Color) = (0.12, 0.10, 0.14, 1)
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
            "Queue" = "Geometry"
        }
        LOD 200

        // -------------------------------------------------- Forward
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }
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
                float3 normalOS   : NORMAL;
                float4 tangentOS  : TANGENT;
                float2 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float3 normalWS   : TEXCOORD1;
                float2 uv         : TEXCOORD2;
                float  fogFactor  : TEXCOORD3;
            };

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                float4 _BaseColor;
                float4 _ShadeMap_ST;
                float4 _ShadeColor;
                float  _ShadowStep;
                float  _MidStep;
                float  _Feather;
                float4 _SpecColor;
                float  _Shininess;
                float  _SpecThreshold;
                float4 _RimColor;
                float  _RimPower;
                float  _RimThreshold;
                float  _OutlineWidth;
                float4 _OutlineColor;
            CBUFFER_END

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);
            TEXTURE2D(_ShadeMap); SAMPLER(sampler_ShadeMap);

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                VertexPositionInputs vpi = GetVertexPositionInputs(IN.positionOS.xyz);
                VertexNormalInputs vni = GetVertexNormalInputs(IN.normalOS, IN.tangentOS);
                OUT.positionCS = vpi.positionCS;
                OUT.positionWS = vpi.positionWS;
                OUT.normalWS = vni.normalWS;
                OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);
                OUT.fogFactor = ComputeFogFactor(vpi.positionCS.z);
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                half4 baseTex = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv);
                half3 albedo = baseTex.rgb * _BaseColor.rgb;

                // Shade map optional: kalau ada, pakai untuk shadow color
                half4 shadeTex = SAMPLE_TEXTURE2D(_ShadeMap, sampler_ShadeMap, IN.uv);
                half3 shadeAlbedo = shadeTex.rgb * _ShadeColor.rgb;
                // Kalau shade map putih (tidak ada), pakai ShadeColor * albedo
                // Deteksi simple: kalau shadeTex ~1, pakai lerp
                half shadeMapExists = dot(shadeTex.rgb, half3(1,1,1)) < 2.9 ? 1 : 0;
                shadeAlbedo = lerp(albedo * _ShadeColor.rgb, shadeAlbedo, shadeMapExists);

                float4 shadowCoord = TransformWorldToShadowCoord(IN.positionWS);
                Light mainLight = GetMainLight(shadowCoord);

                half3 N = normalize(IN.normalWS);
                half3 V = normalize(GetWorldSpaceViewDir(IN.positionWS));
                half ndl = dot(N, mainLight.direction);
                half halfLambert = saturate(ndl * 0.5 + 0.5);

                half cel = CelRamp(halfLambert, _ShadowStep, _MidStep, _Feather);

                half3 litAlbedo = lerp(shadeAlbedo, albedo, cel);

                half3 ambient = SampleSH(N) * 0.6;
                half3 diffuse = litAlbedo * (ambient + mainLight.color * mainLight.distanceAttenuation * mainLight.shadowAttenuation * lerp(0.4, 1.0, cel));

                // Specular stepped (untuk rambut)
                half3 H = normalize(mainLight.direction + V);
                half spec = CelSpecular(N, H, _Shininess, _SpecThreshold, 0.08);
                half3 specular = spec * _SpecColor.rgb * mainLight.color * mainLight.shadowAttenuation;

                // Rim light ala Genshin (siluet terang di tepi)
                half rim = CelRim(N, V, _RimPower, _RimThreshold);
                half3 rimLight = rim * _RimColor.rgb * _RimColor.a;

                half3 final = diffuse + specular + rimLight * 0.6;

                final = MixFog(final, IN.fogFactor);
                return half4(final, baseTex.a * _BaseColor.a);
            }
            ENDHLSL
        }

        // -------------------------------------------------- Outline (inverted hull)
        Pass
        {
            Name "Outline"
            Tags { "LightMode" = "SRPDefaultUnlit" }
            Cull Front
            ZWrite On
            ZTest LEqual

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 2.0

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                float4 _BaseColor;
                float4 _ShadeMap_ST;
                float4 _ShadeColor;
                float  _ShadowStep;
                float  _MidStep;
                float  _Feather;
                float4 _SpecColor;
                float  _Shininess;
                float  _SpecThreshold;
                float4 _RimColor;
                float  _RimPower;
                float  _RimThreshold;
                float  _OutlineWidth;
                float4 _OutlineColor;
            CBUFFER_END

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                // Extrude along normal (in object space, then to clip)
                float3 posOS = IN.positionOS.xyz + IN.normalOS * _OutlineWidth;
                OUT.positionCS = TransformObjectToHClip(posOS);
                OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                return half4(_OutlineColor.rgb, 1.0);
            }
            ENDHLSL
        }

        // -------------------------------------------------- ShadowCaster
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
                float4 _BaseMap_ST;
                float4 _BaseColor;
                float4 _ShadeMap_ST;
                float4 _ShadeColor;
                float  _ShadowStep;
                float  _MidStep;
                float  _Feather;
                float4 _SpecColor;
                float  _Shininess;
                float  _SpecThreshold;
                float4 _RimColor;
                float  _RimPower;
                float  _RimThreshold;
                float  _OutlineWidth;
                float4 _OutlineColor;
            CBUFFER_END

            float3 _LightDirection;
            float3 _LightPosition;

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; float2 uv : TEXCOORD0; };
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
