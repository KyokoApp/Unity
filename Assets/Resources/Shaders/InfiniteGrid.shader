// Grid kotak-kotak tanpa batas (world-space, anti-aliased, menerima bayangan & fog).
Shader "UAL2/InfiniteGrid"
{
    Properties
    {
        _BaseColor  ("Warna Dasar",  Color) = (0.93, 0.945, 0.965, 1)
        _LineColor  ("Garis Minor",  Color) = (0.63, 0.68, 0.75, 1)
        _MajorColor ("Garis Mayor",  Color) = (0.38, 0.45, 0.58, 1)
        _CellSize   ("Ukuran Kotak (m)", Float) = 1.0
        _MajorEvery ("Mayor Tiap N Kotak", Float) = 10.0
        _LineWidth  ("Tebal Garis (px)", Range(0.5, 4)) = 1.3
    }
    SubShader
    {
        Tags { "RenderType" = "Opaque" }
        LOD 150

        CGPROGRAM
        #pragma surface surf Lambert fullforwardshadows
        #pragma target 3.0

        struct Input
        {
            float3 worldPos;
        };

        fixed4 _BaseColor;
        fixed4 _LineColor;
        fixed4 _MajorColor;
        float _CellSize;
        float _MajorEvery;
        float _LineWidth;

        // Mengembalikan intensitas garis (0..1) untuk domain p, dengan tebal 'px' piksel.
        float gridLine(float2 p, float px)
        {
            float2 w = fwidth(p);
            w = max(w, 1e-5);
            float2 g = abs(frac(p + 0.5) - 0.5) / (w * px);
            return 1.0 - saturate(min(g.x, g.y));
        }

        void surf(Input IN, inout SurfaceOutput o)
        {
            float2 pMinor = IN.worldPos.xz / max(_CellSize, 1e-4);
            float2 pMajor = IN.worldPos.xz / max(_CellSize * _MajorEvery, 1e-4);

            // Redupkan garis saat terlalu rapat di kejauhan (anti moire).
            float fadeMinor = saturate(1.0 - length(fwidth(pMinor)) * 1.6);
            float fadeMajor = saturate(1.0 - length(fwidth(pMajor)) * 1.6);

            float minorL = gridLine(pMinor, _LineWidth) * fadeMinor;
            float majorL = gridLine(pMajor, _LineWidth * 1.6) * fadeMajor;

            fixed3 c = _BaseColor.rgb;
            c = lerp(c, _LineColor.rgb, minorL * 0.85);
            c = lerp(c, _MajorColor.rgb, majorL);

            o.Albedo = c;
            o.Alpha = 1;
        }
        ENDCG
    }
    FallBack "Diffuse"
}
