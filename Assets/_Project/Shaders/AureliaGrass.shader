// ============================================================
// AureliaGrass.shader
//
// Rumput Tahap 4. Dipasangkan dengan GrassField.cs yang menggambar
// ribuan instance rumpun lewat DrawMeshInstanced.
//
// Pilihan yang disengaja:
//   * OPAQUE, bukan alpha-tested. Siluet bilah sudah meruncing di
//     geometri, jadi tidak butuh tekstur alpha -- dan opaque berarti
//     tanpa sortir, tanpa overdraw, ramah HP menengah.
//   * Angin di VERTEX shader: simpangan = sin(waktu + posisi dunia),
//     dikalikan uv.y supaya pangkal tetap diam dan ujung yang paling
//     bergerak, seperti rumput sungguhan.
//   * Jarak jauh tidak di-alpha-fade tapi DITENGELAMKAN ke titik
//     pangkalnya (scale menuju nol), lalu kabut (fog) menyamarkan
//     sisanya. Fade alpha pada opaque butuh dithering yang berisik di
//     layar HP.
//   * Tidak melempar bayangan (tidak ada pass ShadowCaster): bayangan
//     rumput 3 cm tidak terbaca di layar 6 inci, tapi biaya shadow
//     pass-nya nyata.
//   * SRP Batcher: semua properti material di dalam CBUFFER
//     UnityPerMaterial.
// ============================================================
Shader "Aurelia/Grass"
{
    Properties
    {
        _BaseColor     ("Warna Pangkal", Color) = (0.16, 0.34, 0.13, 1)
        _TipColor      ("Warna Ujung",   Color) = (0.45, 0.66, 0.24, 1)
        _WindStrength  ("Kekuatan Angin (m)", Range(0, 0.6)) = 0.16
        _WindSpeed     ("Kecepatan Angin", Range(0, 4)) = 1.1
        _FadeStart     ("Mulai Tenggelam (m)", Range(10, 80)) = 22
        _FadeEnd       ("Tenggelam Penuh (m)", Range(20, 120)) = 30
        _WindNoise     ("Noise Angin (RG=arah, B=kekuatan)", 2D) = "gray" {}
        _WindNoiseStrength ("Kekuatan Noise (0=sin murni)", Range(0, 1)) = 0
        _WindNoiseScale ("Skala Noise (per meter)", Float) = 0.045
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
            #include "Assets/_Project/Shaders/AureliaLitFill.hlsl"

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
                float  _WindStrength;
                float  _WindSpeed;
                float  _FadeStart;
                float  _FadeEnd;
                float  _WindNoiseStrength;
                float  _WindNoiseScale;
            CBUFFER_END

            // Tekstur di luar cbuffer (aturan Unity). Dibake oleh
            // tools/bake_toon_textures.py, dipasang oleh scene builder.
            TEXTURE2D(_WindNoise);   SAMPLER(sampler_WindNoise);

            /* Hash murah dari posisi dunia instance: tiap rumpun punya
               fase angin dan variasi rona sendiri, tanpa data per-instance. */
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

                /* Posisi dunia PANGKAL rumpun (titik origin instance). */
                float3 originWS = TransformObjectToWorld(float3(0, 0, 0));
                float  h        = Hash21(originWS.xz);

                /* Angin: pangkal (uv.y=0) diam, ujung (uv.y=1) penuh.
                   Dua gelombang berfrekuensi beda supaya tidak terlihat
                   seperti sin() murni. */
                float t   = _Time.y * _WindSpeed;
                float w1  = sin(t * 1.7 + originWS.x * 0.35 + originWS.z * 0.22);
                float w2  = sin(t * 3.9 + originWS.x * 0.11 - originWS.z * 0.31) * 0.35;
                float amp = (w1 + w2) * _WindStrength * i.uv.y * i.uv.y;

                float3 posOS = i.positionOS;
                posOS.x += amp;
                posOS.z += amp * 0.6;

                float3 positionWS = TransformObjectToWorld(posOS);
                o.normalWS = TransformObjectToWorldNormal(i.normalOS);

                /* Tenggelamkan rumpun jauh ke pangkalnya supaya tidak pop
                   saat sel cache dibangun; kabut menutupi transisinya. */
                float dist  = distance(positionWS, GetCameraPositionWS());
                float fade  = 1.0 - smoothstep(_FadeStart, _FadeEnd, dist);
                positionWS  = lerp(originWS, positionWS, fade);

                /* Variasi rona per rumpun (+/- 8%) supaya hamparan tidak
                   terlihat sebagai satu warna datar. */
                o.uv = float2(i.uv.x, i.uv.y * (0.92 + h * 0.16));

                o.positionWS = positionWS;
                o.positionCS = TransformWorldToHClip(positionWS);
                o.fogFactor  = ComputeFogFactor(o.positionCS.z);
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);

                /* Gradasi pangkal->ujung: bagian paling terang ada di
                   ujung bilah, seperti rumput yang tersinari matahari. */
                half3 albedo = lerp((half3)_BaseColor.rgb, (half3)_TipColor.rgb, saturate(i.uv.y));

                /* Half-Lambert dari matahari: sisi yang membelakangi
                   cahaya tetap menerima separuh, supaya rumpun tidak
                   pernah hitam pekat (murah, dan cocok untuk stylized). */
                Light main = GetMainLight();
                half  ndl  = dot(normalize(i.normalWS), main.direction) * 0.5 + 0.5;
                half  atten = AureliaMinShadow(main.shadowAttenuation);
                half3 lit  = albedo * main.color * (ndl * 0.75 + 0.25) * atten;

                /* Ambient proyek (diatur DayNightCycle) masuk lewat SH. */
                lit += albedo * AureliaAmbientOrFloor(SampleSH(normalize(i.normalWS)), 1.0);
                lit += AureliaFill(albedo, 1.0);

                half4 col = half4(lit, 1.0);
                col.rgb = MixFog(col.rgb, i.fogFactor);
                col.rgb = AureliaKeepVisible(col.rgb, albedo);
                return col;
            }
            ENDHLSL
        }
    }

    FallBack Off
}
