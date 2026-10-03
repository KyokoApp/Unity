Shader "Stillwater/UnderwaterBed"
{
    Properties
    {
        _ShallowColor ("Shallow basin stone", Color) = (0.40, 0.49, 0.48, 1)
        _DeepColor ("Deep basin stone", Color) = (0.075, 0.15, 0.18, 1)
        _WaterStartX ("Shallow edge", Float) = 0.63
        _RightWallX ("Deep wall", Float) = 38
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
        float _WaterStartX;
        float _RightWallX;

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
            float across = saturate((IN.worldPos.x - _WaterStartX) / max(_RightWallX - _WaterStartX, 0.01));
            float depth = pow(smoothstep(0.0, 1.0, across), 0.78);
            float3 stone = lerp(_ShallowColor.rgb, _DeepColor.rgb, depth);

            // Mottled mineral sediment and very faint submerged slab joints.
            float broad = valueNoise(p * 0.34);
            float fine = valueNoise(p * 2.7);
            stone *= 0.93 + (broad - 0.5) * 0.18 + (fine - 0.5) * 0.045;
            float2 cell = p / 4.0;
            float2 edge = min(frac(cell), 1.0 - frac(cell)) * 4.0;
            float seam = 1.0 - smoothstep(0.025, 0.075, min(edge.x, edge.y));
            stone = lerp(stone, stone * 0.66, seam * 0.42);

            o.Albedo = stone;
            o.Metallic = 0.015;
            o.Smoothness = 0.24;
            o.Alpha = 1.0;
        }
        ENDCG
    }
    FallBack "Standard"
}
