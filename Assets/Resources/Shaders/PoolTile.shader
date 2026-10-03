Shader "PoolRooms/TileSurface"
{
    Properties
    {
        _MainTex ("UV source", 2D) = "white" {}
        _TileColor ("Tile color", Color) = (0.48, 0.59, 0.63, 1)
        _GroutColor ("Grout color", Color) = (0.16, 0.23, 0.27, 1)
        _TileSize ("Tile width in metres", Range(0.2, 2.5)) = 0.65
        _GroutWidth ("Grout width", Range(0.005, 0.12)) = 0.035
        _Variation ("Tile variation", Range(0, 0.3)) = 0.08
        _Smoothness ("Wet polish", Range(0, 1)) = 0.28
        _Metallic ("Metallic", Range(0, 1)) = 0
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" }
        LOD 150

        CGPROGRAM
        #pragma surface surf Standard
        #pragma target 3.0

        sampler2D _MainTex;
        fixed4 _TileColor;
        fixed4 _GroutColor;
        float _TileSize;
        float _GroutWidth;
        float _Variation;
        half _Smoothness;
        half _Metallic;

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
            float tileSize = max(_TileSize, 0.05);
            float2 cell = floor(IN.uv_MainTex / tileSize);
            float2 local = frac(IN.uv_MainTex / tileSize);
            float2 edge = min(local, 1.0 - local) * tileSize;
            float grout = 1.0 - smoothstep(_GroutWidth, _GroutWidth + 0.025,
                min(edge.x, edge.y));

            float randomTone = hash21(cell) - 0.5;
            float broad = valueNoise(IN.uv_MainTex * 1.35) - 0.5;
            float3 tile = _TileColor.rgb * (1.0 + randomTone * _Variation + broad * 0.035);
            o.Albedo = lerp(tile, _GroutColor.rgb, grout);
            o.Metallic = _Metallic;
            o.Smoothness = lerp(_Smoothness, _Smoothness * 0.55, grout);
            o.Alpha = 1.0;
        }
        ENDCG
    }
    FallBack "Standard"
}
