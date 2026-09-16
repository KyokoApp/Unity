// ============================================================
// AureliaToon.shader — karakter & objek gaya Genshin untuk URP.
//
// Satu shader untuk SEMUA material karakter (opaque, cutout,
// transparan) supaya SRP Batcher bisa bekerja dan konversi VRM
// jadi satu klik (lihat ToonCharacterSetup.cs):
//   * diffuse bertingkat 2-4 yang HALUS (bukan posterize keras)
//   * ramp 1D opsional (_RampStrength 0 = prosedural murni,
//     tanpa butuh aset tekstur apa pun)
//   * outline inverted-hull, tebal per material
//   * rim lembut + specular anime mengeras + emission (mata)
//   * bayangan berwarna (biru lembut ala anime, bukan hitam)
//
// Versi tanpa outline ada di AureliaToonLite — dipakai untuk
// lapisan wajah transparan dan untuk preset Rendah (menghemat
// 1 draw call + 1x vertex per material).
// ============================================================
Shader "Aurelia/Toon"
{
    Properties
    {
        _BaseMap ("Albedo (RGB) Alpha (A)", 2D) = "white" {}
        _BaseColor ("Warna Dasar", Color) = (1, 1, 1, 1)
        _RampMap ("Ramp 1D (opsional)", 2D) = "white" {}
        _RampStrength ("Kekuatan Ramp (0=prosedural)", Range(0, 1)) = 0
        _ToonSteps ("Tingkat Cahaya (2-4)", Range(2, 4)) = 3
        _ToonSoftness ("Kelembutan Tepi", Range(0, 0.5)) = 0.18
        _ShadowColor ("Warna Bayangan", Color) = (0.62, 0.66, 0.82, 1)
        _AmbientBoost ("Penguat Ambient", Range(0, 2)) = 1
        _OutlineColor ("Warna Outline", Color) = (0.08, 0.07, 0.10, 1)
        _OutlineWidth ("Tebal Outline (object-space)", Range(0, 0.05)) = 0.008
        _RimColor ("Warna Rim", Color) = (1, 0.95, 0.88, 1)
        _RimPower ("Rim Power", Range(1, 8)) = 3.5
        _RimStrength ("Rim Strength", Range(0, 1)) = 0.35
        _SpecColor ("Warna Specular", Color) = (1, 1, 1, 1)
        _SpecPower ("Specular Power", Range(8, 160)) = 48
        _SpecStrength ("Specular Strength", Range(0, 2)) = 0.6
        _EmissionColor ("Emission", Color) = (0, 0, 0, 1)
        _EmissionStrength ("Emission Strength", Range(0, 4)) = 1
        _Surface ("__surface", Float) = 0
        _Blend ("__blend", Float) = 0
        _SrcBlend ("__src", Float) = 1
        _DstBlend ("__dst", Float) = 0
        _ZWrite ("__zw", Float) = 1
        _Cull ("__cull", Float) = 2
        _AlphaClip ("__clip", Float) = 0
        _Cutoff ("Alpha Cutoff", Range(0, 1)) = 0.5
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

            Blend [_SrcBlend] [_DstBlend]
            ZWrite [_ZWrite]
            Cull [_Cull]

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 2.0

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile_fog

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Assets/_Project/Shaders/AureliaToonInput.hlsl"
            #include "Assets/_Project/Shaders/AureliaToonLighting.hlsl"

            TEXTURE2D(_BaseMap);   SAMPLER(sampler_BaseMap);
            TEXTURE2D(_RampMap);   SAMPLER(sampler_RampMap);

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
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

            Varyings vert(Attributes v)
            {
                Varyings o;
                VertexPositionInputs vpi = GetVertexPositionInputs(v.positionOS.xyz);
                VertexNormalInputs   vni = GetVertexNormalInputs(v.normalOS);
                o.positionCS = vpi.positionCS;
                o.positionWS = vpi.positionWS;
                o.normalWS   = vni.normalWS;
                o.uv         = v.uv;
                o.fogFactor  = ComputeFogFactor(vpi.positionCS.z);
                return o;
            }

            half4 frag(Varyings v) : SV_Target
            {
                half4 tex = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, v.uv);
                half3 albedo = tex.rgb * _BaseColor.rgb;
                half  alpha  = tex.a * _BaseColor.a;
                if (_AlphaClip > 0.5) clip(alpha - _Cutoff);

                half3 N = normalize(v.normalWS);
                half3 V = normalize(GetWorldSpaceViewDir(v.positionWS));

                float4 shadowCoord = TransformWorldToShadowCoord(v.positionWS);
                Light mainLight = GetMainLight(shadowCoord);
                float atten = AureliaMinShadow(mainLight.shadowAttenuation)
                            * max(mainLight.distanceAttenuation, 0.5);

                // Half-lambert: sisi membelakangi cahaya jatuh ke tingkat
                // bayangan dengan lembut, tidak pernah hitam mendadak.
                float ndl = dot(N, mainLight.direction);
                float rampT = ndl * 0.5 + 0.5;

                half3 rampSample = SAMPLE_TEXTURE2D(_RampMap, sampler_RampMap,
                                                   float2(saturate(rampT * atten), 0.5)).rgb;
                half3 lightCol = AureliaToonLight(rampT, atten, _ToonSteps,
                    _ToonSoftness, _RampStrength, rampSample, _ShadowColor.rgb);

                half3 ambient = AureliaAmbientOrFloor(SampleSH(N), _AmbientBoost);
                half3 col = albedo * (ambient + mainLight.color * lightCol)
                          + AureliaFill(albedo, _AmbientBoost);

                // Rim lembut: tepi objek menangkap warna cahaya.
                float rim = pow(1.0 - saturate(dot(N, V)), _RimPower) * _RimStrength;
                col += _RimColor.rgb * rim * mainLight.color * (0.35 + 0.65 * atten);

                // Specular anime: blob mengeras, bukan pantulan fisik.
                half3 H = normalize(mainLight.direction + V);
                float specPow = pow(saturate(dot(N, H)), _SpecPower);
                float spec = smoothstep(0.45, 0.75, specPow) * _SpecStrength;
                col += _SpecColor.rgb * spec * atten * mainLight.color;

                col += _EmissionColor.rgb * _EmissionStrength;
                col = AureliaKeepVisible(col, albedo);
                return half4(col, alpha);
            }
            ENDHLSL
        }

        Pass
        {
            Name "Outline"
            Tags { "LightMode" = "SRPDefaultUnlit" }

            Cull Front
            ZWrite [_ZWrite]
            ZTest LEqual
            Blend [_SrcBlend] [_DstBlend]

            HLSLPROGRAM
            #pragma vertex OutlineVert
            #pragma fragment OutlineFrag
            #pragma target 2.0
            #pragma multi_compile_fog

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Assets/_Project/Shaders/AureliaToonInput.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float  fogFactor  : TEXCOORD0;
            };

            // Inverted hull klasik: kembangkan mesh sepanjang normal
            // object-space (aman untuk skinned mesh — pelebaran terjadi
            // SEBELUM skinning), lalu gambar sisi belakangnya saja.
            Varyings OutlineVert(Attributes v)
            {
                Varyings o;
                float3 expanded = v.positionOS.xyz + v.normalOS * _OutlineWidth;
                VertexPositionInputs vpi = GetVertexPositionInputs(expanded);
                o.positionCS = vpi.positionCS;
                o.fogFactor = ComputeFogFactor(vpi.positionCS.z);
                return o;
            }

            half4 OutlineFrag(Varyings v) : SV_Target
            {
                half3 c = MixFog(_OutlineColor.rgb, v.fogFactor);
                return half4(c, 1.0);
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
            Cull [_Cull]

            HLSLPROGRAM
            #pragma vertex ShadowVert
            #pragma fragment ShadowFrag
            #pragma target 2.0

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
            #include "Assets/_Project/Shaders/AureliaToonInput.hlsl"

            TEXTURE2D(_BaseMap);   SAMPLER(sampler_BaseMap);
            TEXTURE2D(_RampMap);   SAMPLER(sampler_RampMap);

            float3 _LightDirection;
            float3 _LightPosition;

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
            };

            Varyings ShadowVert(Attributes v)
            {
                Varyings o;
                float3 positionWS = TransformObjectToWorld(v.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(v.normalOS);
            #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                float3 lightDirWS = normalize(_LightPosition - positionWS);
            #else
                float3 lightDirWS = _LightDirection;
            #endif
                o.positionCS = TransformWorldToHClip(
                    ApplyShadowBias(positionWS, normalWS, lightDirWS));
            #if UNITY_REVERSED_Z
                o.positionCS.z = min(o.positionCS.z, UNITY_NEAR_CLIP_VALUE);
            #else
                o.positionCS.z = max(o.positionCS.z, UNITY_NEAR_CLIP_VALUE);
            #endif
                o.uv = v.uv;
                return o;
            }

            half4 ShadowFrag(Varyings v) : SV_Target
            {
                // Rambut cutout harus melempar bayangan sesuai lubangnya.
                if (_AlphaClip > 0.5)
                {
                    half a = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, v.uv).a
                           * _BaseColor.a;
                    clip(a - _Cutoff);
                }
                return 0;
            }
            ENDHLSL
        }
    }

    FallBack "Universal Render Pipeline/Lit"
}
