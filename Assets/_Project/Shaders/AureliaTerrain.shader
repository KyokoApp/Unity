// ============================================================
// AureliaTerrain.shader
//
// Terrain Tahap 3: opaque, albedo dari VERTEX COLOR (dipanggang oleh
// TerrainSurface di RPG.Core), diffuse half-Lambert dari satu directional
// light + shadow, detail noise prosedural supaya warna per-region yang
// mulus tidak terlihat seperti plastik, dan fog.
//
// Kenapa vertex color dan bukan texture splat:
//   - warnanya sudah dihitung murni di RPG.Core dan SUDAH DIUJI
//     (TerrainMeshTests), jadi apa yang terlihat di layar = apa yang
//     diuji, bukan hasil campuran tekstur yang tidak bisa dites
//   - nol tekstur = nol memori tambahan, penting untuk target Android
//   - splat map 4-layer baru masuk akal di Tahap 4 setelah aset Kenney
//     ada dan ada alasan visual untuk menggunakannya
//
// Detail noise sengaja dari posisi DUNIA, bukan UV, supaya tidak ada
// jahitan di perbatasan chunk.
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

        // ---------------------------------------------------------- forward
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

            #include "Assets/_Project/Shaders/AureliaTerrainInput.hlsl"

            // hash & value noise murah, tanpa tekstur
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
                // dua lapis variasi dari posisi dunia XZ: halus & kasar.
                // Tidak memakai UV chunk supaya perbatasan chunk tidak terlihat.
                float2 wp = IN.positionWS.xz;
                float fine   = ValueNoise(wp * _DetailScale) - 0.5;
                float coarse = ValueNoise(wp * _LargeScale + 17.3) - 0.5;
                half3 albedo = IN.color.rgb * (1.0 + fine * _DetailStrength * 2.0
                                                 + coarse * _LargeStrength * 2.0);

                float4 shadowCoord = TransformWorldToShadowCoord(IN.positionWS);
                Light mainLight = GetMainLight(shadowCoord);

                half3 N = normalize(IN.normalWS);
                half ndl = dot(N, mainLight.direction);
                // half-Lambert: terrain low-poly terlihat keras dengan Lambert
                // murni, dan dunia ini memang bergaya flat-shaded (lihat
                // DESAIN.md §4 tentang aset Kenney).
                half diffuse = saturate(ndl * 0.5 + 0.5);
                diffuse = diffuse * diffuse;

                half3 ambient = SampleSH(N) * _AmbientBoost;
                half3 lit = albedo * (ambient + mainLight.color * (mainLight.distanceAttenuation
                            * mainLight.shadowAttenuation) * diffuse);

                lit = MixFog(lit, IN.fogFactor);
                return half4(lit, 1.0);
            }
            ENDHLSL
        }

        // ------------------------------------------------------ shadowcaster
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
            /* Common.hlsl DEFINSI LerpWhiteTo yang dipakai Shadows.hlsl(327).
               Tanpa include eksplisit ini, pass ShadowCaster gagal kompilasi
               di glcore & gles3 (run 34944558100) walau pass utama sehat. */
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
            // cbuffer yang sama dengan Pass utama -- wajib, lihat catatan
            // di AureliaTerrainInput.hlsl
            #include "Assets/_Project/Shaders/AureliaTerrainInput.hlsl"

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
