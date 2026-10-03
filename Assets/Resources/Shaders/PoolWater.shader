Shader "PoolRooms/QuietPoolWater"
{
    Properties
    {
        _NearColor ("Shallow water tint", Color) = (0.17, 0.37, 0.43, 1)
        _DeepColor ("Deep water tint", Color) = (0.018, 0.085, 0.13, 1)
        _ReflectionColor ("Cool ceiling reflection", Color) = (0.48, 0.68, 0.74, 1)
        _PoolCenterX ("Pool center X", Float) = 0
        _PoolHalfWidth ("Pool half width", Float) = 6.2
        _ShallowOpacity ("Shallow transparency", Range(0.05, 0.8)) = 0.20
        _DeepOpacity ("Deep transparency", Range(0.2, 1)) = 0.78
        _Smoothness ("Water smoothness", Range(0, 1)) = 0.9
    }

    SubShader
    {
        Tags { "Queue" = "Transparent" "RenderType" = "Transparent" "IgnoreProjector" = "True" }
        LOD 180

        CGPROGRAM
        #pragma surface surf Standard alpha:fade vertex:vert fullforwardshadows
        #pragma target 3.0

        float4 _NearColor;
        float4 _DeepColor;
        float4 _ReflectionColor;
        float _PoolCenterX;
        float _PoolHalfWidth;
        half _ShallowOpacity;
        half _DeepOpacity;
        half _Smoothness;

        struct Input
        {
            float3 worldPos;
        };

        float waveHeight(float2 p, float time)
        {
            const float zA = 0.2617994; // 24 m repeat so recycled rooms remain seamless
            const float zB = 0.5235988;
            const float zC = 1.0471976;
            return 0.010 * sin(p.x * 0.38 + p.y * zA + time * 0.22)
                 + 0.007 * sin(p.x * 0.72 - p.y * zB - time * 0.14)
                 + 0.0035 * sin(p.x * 1.40 + p.y * zC + time * 0.17);
        }

        void vert(inout appdata_full v)
        {
            float3 world = mul(unity_ObjectToWorld, v.vertex).xyz;
            v.vertex.y += waveHeight(world.xz, _Time.y);
        }

        void surf(Input IN, inout SurfaceOutputStandard o)
        {
            float2 p = IN.worldPos.xz;
            float t = _Time.y;
            const float zA = 0.2617994;
            const float zB = 0.5235988;
            const float zC = 1.0471976;

            float a = p.x * 0.38 + p.y * zA + t * 0.22;
            float b = p.x * 0.72 - p.y * zB - t * 0.14;
            float c = p.x * 1.40 + p.y * zC + t * 0.17;
            float dhdx = 0.010 * 0.38 * cos(a)
                       + 0.007 * 0.72 * cos(b)
                       + 0.0035 * 1.40 * cos(c);
            float dhdz = 0.010 * zA * cos(a)
                       - 0.007 * zB * cos(b)
                       + 0.0035 * zC * cos(c);

            // Fine tangent-space normal variation; water remains calm and phone-friendly.
            o.Normal = normalize(float3(-dhdx * 13.0, -dhdz * 13.0, 1.0));

            // The basin is shallow around its tiled edge and deepest near its center.
            float halfWidth = max(_PoolHalfWidth, 0.1);
            float depth = 1.0 - saturate(abs(p.x - _PoolCenterX) / halfWidth);
            depth = smoothstep(0.0, 1.0, depth);
            float shimmer = 0.96 + 0.025 * sin(p.x * 1.8 + p.y * (2.0 * zA) + t * 0.21)
                                  + 0.015 * sin(p.x * 3.1 - p.y * (2.0 * zB) - t * 0.15);
            o.Albedo = lerp(_NearColor.rgb, _DeepColor.rgb, depth) * shimmer;
            o.Metallic = 0.025;
            o.Smoothness = _Smoothness;

            float3 normalWS = normalize(float3(-dhdx * 13.0, 1.0, -dhdz * 13.0));
            float3 viewWS = normalize(_WorldSpaceCameraPos.xyz - IN.worldPos);
            float grazing = 1.0 - saturate(dot(normalWS, viewWS));
            float fresnel = 0.02 + 0.98 * pow(grazing, 5.0);

            // Ceiling strips break into soft, elongated highlights in the small ripples.
            float drift = 0.14 * sin(p.y * zB + t * 0.10)
                        + 0.07 * sin(p.y * zC - t * 0.08);
            float broken = saturate(0.58 + 0.21 * sin(p.y * zC + t * 0.12)
                                         + 0.15 * sin(p.y * zB - t * 0.09));
            float laneDeltaA = (p.x - (_PoolCenterX - halfWidth * 0.54 + drift)) * 1.15;
            float laneDeltaB = (p.x - (_PoolCenterX + drift * 0.25)) * 1.10;
            float laneDeltaC = (p.x - (_PoolCenterX + halfWidth * 0.54 - drift)) * 1.15;
            float laneA = exp(-laneDeltaA * laneDeltaA);
            float laneB = exp(-laneDeltaB * laneDeltaB);
            float laneC = exp(-laneDeltaC * laneDeltaC);
            float reflectedLights = (laneA + laneB + laneC) * broken;
            float micro = abs(sin(p.x * 2.2 + p.y * (2.0 * zC) + t * 0.18)
                            * sin(p.x * 1.65 - p.y * 1.5 * zC - t * 0.13));
            o.Emission = _ReflectionColor.rgb * (0.012 + fresnel * 0.22)
                       + float3(0.48, 0.61, 0.67) * reflectedLights * (0.06 + fresnel * 0.24)
                       + float3(0.06, 0.11, 0.14) * micro * fresnel * 0.10;

            // Transparent overhead view; stronger reflection hides the very deep center at grazing angles.
            float alpha = lerp(_ShallowOpacity, _DeepOpacity, depth);
            alpha = lerp(alpha, 0.96, saturate((fresnel - 0.10) * 1.2));
            o.Alpha = alpha;
        }
        ENDCG
    }
    FallBack "Transparent/VertexLit"
}
