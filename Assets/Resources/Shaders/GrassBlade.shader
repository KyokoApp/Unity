// Helai rumput geometri (port redesign grass_field.gd): warna gradasi
// pangkal->ujung, goyangan angin halus, dan menyingkir sedikit saat player
// mendekat. vertex color: r = fraksi tinggi, g = 1 bila quad penutup tanah,
// b = variasi acak per rumpun.
Shader "UAL2/GrassBlade"
{
    Properties
    {
        _BaseColor ("Base", Color) = (0.24, 0.46, 0.16, 1)
        _TipColor ("Tip", Color) = (0.52, 0.72, 0.28, 1)
        _PlayerPos ("Player Pos", Vector) = (0, 0, 0, 0)
    }
    SubShader
    {
        Tags { "RenderType" = "Opaque" }
        Cull Off
        LOD 100

        CGPROGRAM
        #pragma surface surf Lambert vertex:vert

        float4 _BaseColor;
        float4 _TipColor;
        float4 _PlayerPos;

        struct Input
        {
            float4 color : COLOR;
        };

        void vert(inout appdata_full v)
        {
            float3 wp = mul(unity_ObjectToWorld, v.vertex).xyz;
            float hFrac = saturate(v.color.r);
            bool isCover = v.color.g > 0.5;

            if (!isCover)
            {
                // angin: dua lapis sinus, amplitudo naik ke ujung helai
                float w = sin(_Time.y * 1.7 + wp.x * 0.35 + wp.z * 0.27) * 0.5
                        + sin(_Time.y * 2.3 + wp.x * 0.13 - wp.z * 0.09) * 0.25;
                v.vertex.xz += float2(w, w * 0.6) * hFrac * hFrac * 0.10;
            }

            // singkir saat player mendekat (tidak menembus badan)
            float2 d = wp.xz - _PlayerPos.xz;
            float dl = length(d);
            float push = 1.0 - smoothstep(0.25, 0.95, dl);
            v.vertex.xz += (d / max(dl, 0.001)) * push * hFrac * 0.30;
        }

        void surf(Input IN, inout SurfaceOutput o)
        {
            float3 col;
            if (IN.color.g > 0.5)
                col = _BaseColor.rgb * 0.85;                       // penutup tanah
            else
                col = lerp(_BaseColor.rgb, _TipColor.rgb, IN.color.r);
            col *= 0.88 + 0.24 * IN.color.b;                       // variasi rumpun
            o.Albedo = col;
            o.Alpha = 1.0;
        }
        ENDCG
    }
    FallBack "Diffuse"
}
