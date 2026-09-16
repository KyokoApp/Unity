// ============================================================
// AureliaSky.shader — langit gradien stylized + piringan matahari.
//
// Dipasang sebagai RenderSettings.skybox oleh scene builder, lalu
// warnanya digerakkan DayNightCycle per keyframe jam (pagi keemasan,
// siang biru lembut, senja jingga, malam biru tua).
//
// Murah: tanpa tekstur, tanpa noise, satu fungsi gradien + disc.
// Fog TIDAK diterapkan ke langit (langit adalah acuan warna kabut,
// bukan sebaliknya — kabut mengambil warna horizon).
// ============================================================
Shader "Aurelia/Sky"
{
    Properties
    {
        _TopColor ("Warna Zenith", Color) = (0.36, 0.55, 0.82, 1)
        _HorizonColor ("Warna Horizon", Color) = (0.75, 0.82, 0.88, 1)
        _BottomColor ("Warna Bawah", Color) = (0.55, 0.58, 0.62, 1)
        _SunColor ("Warna Matahari", Color) = (1, 0.95, 0.85, 1)
        _SunDirection ("Arah Matahari", Vector) = (0, 1, 0.3, 0)
        _SunSize ("Ukuran Piringan", Range(0.001, 0.05)) = 0.012
        _SunGlow ("Kekuatan Halo", Range(0, 1)) = 0.35
    }

    SubShader
    {
        Tags
        {
            "Queue" = "Background"
            "RenderPipeline" = "UniversalPipeline"
            "PreviewType" = "Skybox"
            "IgnoreProjector" = "True"
        }

        Pass
        {
            Name "Skybox"
            Tags { "LightMode" = "SRPDefaultUnlit" }

            ZWrite Off
            ZTest LEqual
            Cull Front
            Fog { Mode Off }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 2.0

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 direction  : TEXCOORD0;
            };

            CBUFFER_START(UnityPerMaterial)
                float4 _TopColor;
                float4 _HorizonColor;
                float4 _BottomColor;
                float4 _SunColor;
                float4 _SunDirection;
                float  _SunSize;
                float  _SunGlow;
            CBUFFER_END

            Varyings vert(Attributes v)
            {
                Varyings o;
                // Box skybox selalu berpusat di kamera, jadi posisi
                // object-space-nya langsung bisa dipakai sebagai arah.
                float3 worldPos = TransformObjectToWorld(v.positionOS.xyz);
                o.positionCS = TransformWorldToHClip(worldPos);
                o.direction = v.positionOS.xyz;
                return o;
            }

            half4 frag(Varyings v) : SV_Target
            {
                float3 d = normalize(v.direction);
                half3 top = _TopColor.rgb;
                half3 hor = _HorizonColor.rgb;
                half3 bot = _BottomColor.rgb;

                half3 col;
                if (d.y >= 0.0)
                    col = lerp(hor, top, pow(d.y, 0.55));
                else
                    col = lerp(hor, bot, pow(-d.y, 0.6));

                // Piringan matahari + halo lembut.
                float3 sunDir = normalize(_SunDirection.xyz);
                float s = dot(d, sunDir);
                float disc = smoothstep(1.0 - _SunSize, 1.0 - _SunSize * 0.45, s);
                float glow = pow(saturate(s), 6.0) * _SunGlow;
                col += _SunColor.rgb * (disc * 1.6 + glow);

                return half4(col, 1.0);
            }
            ENDHLSL
        }
    }

    FallBack Off
}
