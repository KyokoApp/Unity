Shader "Stillwater/Porcelain"
{
    Properties
    {
        _BaseColor ("Porcelain / concrete color", Color) = (0.79, 0.82, 0.83, 1)
        _MainTex ("UV source", 2D) = "white" {}
        _NoiseAmount ("Surface variation", Range(0, 0.2)) = 0.04
        _NoiseScale ("Grain scale", Float) = 1
        _Smoothness ("Smoothness", Range(0, 1)) = 0.65
        _Metallic ("Metallic", Range(0, 1)) = 0
        _PanelScale ("Floor panel spacing in UV", Float) = 0
        _PanelWidth ("Panel seam width", Float) = 0.01
        _PanelTint ("Panel seam tint", Color) = (0.38, 0.41, 0.42, 1)
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" }
        LOD 180

        CGPROGRAM
        #pragma surface surf Standard fullforwardshadows
        #pragma target 3.0

        sampler2D _MainTex;
        fixed4 _BaseColor;
        fixed4 _PanelTint;
        float _NoiseAmount;
        float _NoiseScale;
        float _Smoothness;
        float _Metallic;
        float _PanelScale;
        float _PanelWidth;

        struct Input
        {
            float2 uv_MainTex;
        };

        float hash21(float2 p)
        {
            p = frac(p * float2(123.34, 456.21));
            p += dot(p, p + 45.32);
            return frac(p.x * p.y);
        }

        float valueNoise(float2 p)
        {
            float2 cell = floor(p);
            float2 f = frac(p);
            f = f * f * (3.0 - 2.0 * f);
            float a = hash21(cell);
            float b = hash21(cell + float2(1.0, 0.0));
            float c = hash21(cell + float2(0.0, 1.0));
            float d = hash21(cell + float2(1.0, 1.0));
            return lerp(lerp(a, b, f.x), lerp(c, d, f.x), f.y);
        }

        void surf(Input IN, inout SurfaceOutputStandard o)
        {
            float2 uv = IN.uv_MainTex;
            float broad = valueNoise(uv * max(_NoiseScale, 0.01));
            float fine = valueNoise(uv * max(_NoiseScale, 0.01) * 8.0);
            float grain = (broad - 0.5) * 0.65 + (fine - 0.5) * 0.16;
            float3 color = _BaseColor.rgb * (1.0 + grain * _NoiseAmount);

            if (_PanelScale > 0.001)
            {
                float2 cell = uv / _PanelScale;
                float2 edge = min(frac(cell), 1.0 - frac(cell)) * _PanelScale;
                float seam = 1.0 - smoothstep(_PanelWidth, _PanelWidth + 0.004,
                    min(edge.x, edge.y));
                color = lerp(color, _PanelTint.rgb, seam * 0.46);
            }

            o.Albedo = color;
            o.Metallic = _Metallic;
            o.Smoothness = _Smoothness;
            o.Alpha = 1.0;
        }
        ENDCG
    }
    FallBack "Standard"
}
