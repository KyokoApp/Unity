Shader "Stillwater/DeepCalmWater"
{
    Properties
    {
        _NearColor ("Shallow water tint", Color) = (0.13, 0.29, 0.32, 1)
        _DeepColor ("Deep water tint", Color) = (0.018, 0.060, 0.082, 1)
        _ReflectionColor ("Cool reflection", Color) = (0.42, 0.60, 0.66, 1)
        _WaterStartX ("Water edge", Float) = 0.63
        _ShallowOpacity ("Shallow transparency", Range(0.05, 0.8)) = 0.24
        _DeepOpacity ("Deep transparency", Range(0.2, 1)) = 0.82
        _Metallic ("Reflectivity", Range(0, 1)) = 0.05
        _Smoothness ("Surface smoothness", Range(0, 1)) = 0.88
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
        float _WaterStartX;
        half _ShallowOpacity;
        half _DeepOpacity;
        half _Metallic;
        half _Smoothness;

        struct Input
        {
            float3 worldPos;
        };

        float waveHeight(float2 p, float time)
        {
            const float zA = 0.2617994; // 24 m period: exactly matches a room module
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

            // Tangent UVs on the water mesh follow X/Z, so small ripples tilt normals
            // without textures, large meshes, or extra draw calls.
            o.Normal = normalize(float3(-dhdx * 13.0, -dhdz * 13.0, 1.0));

            // The basin slopes away from the walkway: shallow water stays clear,
            // while the deeper far side absorbs more light and hides the bottom.
            float depth = saturate((p.x - _WaterStartX) / 34.0);
            depth = smoothstep(0.0, 1.0, depth);
            float shimmer = 0.96 + 0.025 * sin(p.x * 1.8 + p.y * (2.0 * zA) + t * 0.21)
                                  + 0.015 * sin(p.x * 3.1 - p.y * (2.0 * zB) - t * 0.15);
            o.Albedo = lerp(_NearColor.rgb, _DeepColor.rgb, depth) * shimmer;
            o.Metallic = _Metallic;
            o.Smoothness = _Smoothness;

            float3 normalWS = normalize(float3(-dhdx * 13.0, 1.0, -dhdz * 13.0));
            float3 viewWS = normalize(_WorldSpaceCameraPos.xyz - IN.worldPos);
            float grazing = 1.0 - saturate(dot(normalWS, viewWS));
            float fresnel = 0.02 + 0.98 * pow(grazing, 5.0);

            // Soft broken ceiling-light reflections remain visible over the clear shallows.
            float drift = 0.18 * sin(p.y * zB + t * 0.10)
                        + 0.09 * sin(p.y * zC - t * 0.08);
            float broken = saturate(0.58 + 0.21 * sin(p.y * zC + t * 0.12)
                                         + 0.15 * sin(p.y * zB - t * 0.09));
            float laneA = exp(-pow((p.x - (8.5 + drift)) * 1.25, 2.0));
            float laneB = exp(-pow((p.x - (20.0 - drift * 0.65)) * 1.15, 2.0));
            float laneC = exp(-pow((p.x - (31.5 + drift * 0.45)) * 1.05, 2.0));
            float reflectedLights = (laneA + laneB + laneC) * broken;

            float micro = abs(sin(p.x * 2.2 + p.y * (2.0 * zC) + t * 0.18)
                            * sin(p.x * 1.65 - p.y * 1.5 * zC - t * 0.13));
            float3 reflection = _ReflectionColor.rgb * (0.018 + fresnel * 0.22);
            reflection += float3(0.48, 0.61, 0.63) * reflectedLights * (0.08 + fresnel * 0.28);
            reflection += float3(0.075, 0.12, 0.13) * micro * fresnel * 0.12;
            o.Emission = reflection;

            // Clear when viewed from above and near the ledge; reflective/opaque at depth or grazing angles.
            float alpha = lerp(_ShallowOpacity, _DeepOpacity, depth);
            alpha = lerp(alpha, 0.96, saturate((fresnel - 0.10) * 1.2));
            o.Alpha = alpha;
        }
        ENDCG
    }
    FallBack "Transparent/VertexLit"
}
