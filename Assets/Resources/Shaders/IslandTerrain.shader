// Terrain pulau: warna vertex (rumput/batu/pasir) + batas JALAN pedesaan dan
// plaza batu ARENA dihitung per-fragment (analitik, mulus — bukan interpolasi
// warna vertex), plus corak meadow_cover agar bidang hijau tidak rata-plastik.
// Port redesign dari project/src/game/terrain.gdshader (Godot).
Shader "UAL2/IslandTerrain"
{
    Properties
    {
        _MeadowCover ("Meadow Cover", 2D) = "white" {}
        _DirtColor ("Dirt Road", Color) = (0.663, 0.471, 0.282, 1)
        _WorldScale ("World Scale", Float) = 0.2
    }
    SubShader
    {
        Tags { "RenderType" = "Opaque" }
        LOD 100

        CGPROGRAM
        #pragma surface surf Lambert fullforwardshadows

        sampler2D _MeadowCover;
        float4 _DirtColor;
        float _WorldScale;

        struct Input
        {
            float3 worldPos;
            float3 worldNormal;
            float4 color : COLOR;
        };

        float grain(float2 p)
        {
            return frac(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
        }

        // lantai plaza: voronoi batu + retakan radial (dari terrain.gdshader)
        float3 arena_ground(float2 p)
        {
            float2 cells = p * 0.65;
            float2 base = floor(cells);
            float2 local = fract(cells);
            float first = 9.0, second = 9.0, seed = 0.0;
            for (int y = -1; y <= 1; y++)
            {
                for (int x = -1; x <= 1; x++)
                {
                    float2 offset = float2(float(x), float(y));
                    float2 site = offset + float2(grain(base + offset), grain(base + offset + 19.3));
                    float d = length(site - local);
                    if (d < first) { second = first; first = d; seed = grain(base + offset); }
                    else { second = min(second, d); }
                }
            }
            float seams = 1.0 - smoothstep(0.018, 0.065, second - first);
            float3 stone = lerp(float3(0.24, 0.21, 0.17), float3(0.42, 0.39, 0.32), seed);
            stone *= 0.94 + 0.06 * grain(floor(p * 12.0));
            stone = lerp(stone, float3(0.12, 0.10, 0.08), seams * 0.65);
            float r = length(p);
            float angle = atan2(p.y, p.x);
            float crack = abs(sin(angle * 5.5 + sin(r * 0.6) * 0.10 + sin(r * 1.8) * 0.04));
            float width = 0.22 / max(r, 0.7);
            float fracture = 1.0 - smoothstep(width, width * 2.0 + 0.005, crack);
            fracture *= 1.0 - smoothstep(30.0, 42.0, r);
            return lerp(stone, float3(0.065, 0.055, 0.045), fracture * 0.9);
        }

        void surf(Input IN, inout SurfaceOutput o)
        {
            // Terrain mesh diperkecil oleh transform, tetapi definisi visual
            // jalan/plaza tetap memakai koordinat sumber supaya tepat bertemu
            // dengan mesh dan collider yang sama.
            float2 sourcePos = IN.worldPos.xz / max(_WorldScale, 0.0001);
            float3 land = IN.color.rgb;

            // corak meadow hanya di lahan hijau datar
            float greenLand = smoothstep(0.04, 0.12, land.g - max(land.r, land.b));
            greenLand *= smoothstep(0.88, 0.95, IN.worldNormal.y);
            float pattern = tex2D(_MeadowCover, sourcePos * 0.16).r;
            land *= lerp(1.0, lerp(0.82, 1.02, pattern), greenLand);

            // jalan pedesaan per-fragment (tepi mulus)
            float z = sourcePos.y;
            float center = 65.0 * sin(z / 95.0) + 22.0 * sin(z / 43.0);
            float slope = (65.0 / 95.0) * cos(z / 95.0) + (22.0 / 43.0) * cos(z / 43.0);
            float distance = abs(sourcePos.x - center) / sqrt(1.0 + slope * slope);
            float road = 1.0 - smoothstep(9.0, 11.0, distance);
            road *= 1.0 - smoothstep(300.0, 335.0, abs(z));
            float3 col = lerp(land, _DirtColor.rgb, road);

            // plaza batu arena
            float2 ap = sourcePos - float2(-145.0, 140.0);
            float angle = atan2(ap.y, ap.x);
            float boundary = 42.0 + 1.4 * sin(angle * 5.0) + 0.7 * cos(angle * 9.0);
            float arenaMask = 1.0 - smoothstep(-0.5, 1.2, length(ap) - boundary);
            col = lerp(col, arena_ground(ap), arenaMask);

            o.Albedo = col;
            o.Alpha = 1.0;
        }
        ENDCG
    }
    FallBack "Diffuse"
}
