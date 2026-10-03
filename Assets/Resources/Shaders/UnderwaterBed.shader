Shader "PoolRooms/SubmergedPoolTile"
{
    Properties
    {
        _ShallowColor ("Shallow tile color", Color) = (0.35, 0.47, 0.51, 1)
        _DeepColor ("Deep tile color", Color) = (0.055, 0.13, 0.19, 1)
        _PoolCenterX ("Pool center X", Float) = 0
        _PoolHalfWidth ("Pool half width", Float) = 6.2
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" }
        LOD 150

        CGPROGRAM
        #pragma surface surf Standard
        #pragma target 3.0

        float4 _ShallowColor;
        float4 _DeepColor;
        float _PoolCenterX;
        float _PoolHalfWidth;

        struct Input
        {
            float3 worldPos;
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
            float2 p = IN.worldPos.xz;
            float halfWidth = max(_PoolHalfWidth, 0.1);
            float depth = 1.0 - saturate(abs(IN.worldPos.x - _PoolCenterX) / halfWidth);
            depth = pow(smoothstep(0.0, 1.0, depth), 0.82);
            float3 tile = lerp(_ShallowColor.rgb, _DeepColor.rgb, depth);

            // Soft mineral mottling and faint, regular grout lines remain visible through the clear edge water.
            float broad = valueNoise(p * 0.34);
            float fine = valueNoise(p * 2.7);
            tile *= 0.93 + (broad - 0.5) * 0.18 + (fine - 0.5) * 0.045;
            float2 cell = p / 0.78;
            float2 edge = min(frac(cell), 1.0 - frac(cell)) * 0.78;
            float seam = 1.0 - smoothstep(0.022, 0.055, min(edge.x, edge.y));
            tile = lerp(tile, tile * 0.62, seam * 0.35);

            o.Albedo = tile;
            o.Metallic = 0.01;
            o.Smoothness = 0.30;
            o.Alpha = 1.0;
        }
        ENDCG
    }
    FallBack "Standard"
}
