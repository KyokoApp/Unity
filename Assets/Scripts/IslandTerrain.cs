using System.Collections.Generic;
using UnityEngine;

/// <summary>
/// Pulau deterministik 200 m x 200 m — bentuk port dari world Godot dalam
/// koordinat sumber 1 km, diperkecil seragam agar ukuran fitur dan kemiringan
/// tetap proporsional (terrain, air, jalan, arena, dan spawn).
///
/// Redesign "lebih smooth" dibanding aslinya: normal terrain halus (tanpa
/// facet low-poly cliff), batas jalan/batu plaza dihitung per-fragment di
/// shader (bukan warna vertex per-segitiga), rumput & nature tetap deterministik.
///
/// Semua bentuk ANALITIK (tidak ada texture heightmap): pantai berlekuk,
/// dua bukit, plateau tebing timur, jalan pedesaan berkelok yang menyatu
/// permukaan, danau berkantung + sungai berkelok ke laut tenggara, serta
/// plaza batu (arena) — sama persis rumusnya dengan world Godot-mu.
/// </summary>
public class IslandTerrain : MonoBehaviour
{
    public static IslandTerrain I;

    public const float WorldScale = 0.2f;
    public const float WorldSize = 200f;
    public const float WorldHalfSize = WorldSize * 0.5f;

    const int Cells = 200;
    const float Step = 5f;                 // jarak sampel dalam koordinat sumber
    const float SourceHalfSize = 500f;
    const float SeaLevel = 0f;

    static readonly Color GrassCol = new Color(0.349f, 0.647f, 0.255f);   // #59a541
    static readonly Color CliffCol = new Color(0.467f, 0.486f, 0.494f);   // #777c7e
    static readonly Color SandCol = new Color(0.788f, 0.678f, 0.447f);    // #c9ad72

    public Vector3 SpawnPoint { get; private set; }
    public List<Vector3> RockClearances { get; } = new List<Vector3>();

    float[] heights = new float[(Cells + 1) * (Cells + 1)];
    Mesh terrainMesh;
    Mesh inlandWaterMesh;
    Material terrainMaterial;
    Material waterMaterial;

    // ================= bentuk analitik (port 1:1 dari Godot) =================

    public static float Smoothstep(float a, float b, float x)
    {
        float t = Mathf.Clamp01((x - a) / (b - a));
        return t * t * (3f - 2f * t);
    }

    static float Lerp(float a, float b, float t) { return a + (b - a) * t; }

    static float SourceRoadX(float z)
    {
        return 65f * Mathf.Sin(z / 95f) + 22f * Mathf.Sin(z / 43f);
    }

    static float SourceRoadHeight(float z)
    {
        return 5f + 7f * (1f - Mathf.Cos(z / 110f)) + 1.1f * (1f - Mathf.Cos(z / 28f));
    }

    static float SourceRoadDistance(float x, float z)
    {
        float slope = (65f / 95f) * Mathf.Cos(z / 95f) + (22f / 43f) * Mathf.Cos(z / 43f);
        return Mathf.Abs(x - SourceRoadX(z)) / Mathf.Sqrt(1f + slope * slope);
    }

    // API dunia menerima meter Unity (rentang x/z -100..100), sedangkan rumus
    // bentuk tetap ditulis dalam koordinat sumber 1 km.
    public static float RoadX(float z) { return SourceRoadX(z / WorldScale) * WorldScale; }
    public static float RoadHeight(float z) { return SourceRoadHeight(z / WorldScale) * WorldScale; }
    public static float RoadDistance(float x, float z)
    {
        return SourceRoadDistance(x / WorldScale, z / WorldScale) * WorldScale;
    }

    // ---- danau + sungai (water_shape.gd) ----
    static readonly Vector2 LakeCenter = new Vector2(105f, -50f);
    const float LakeLevel = 4.5f;
    static readonly Vector2 LakeAxes = new Vector2(54f, 38f);
    const float RiverBegin = -55f;
    const float RiverEnd = 330f;

    static float RiverX(float z)
    {
        return 142f + 0.30f * (z + 40f) + 22f * Mathf.Sin((z + 40f) / 40f);
    }

    static float RiverSlope(float z)
    {
        return 0.30f + 0.55f * Mathf.Cos((z + 40f) / 40f);
    }

    static float LakeDistance(float x, float z)
    {
        Vector2 p = new Vector2(x - LakeCenter.x, z - LakeCenter.y);
        p = new Vector2(p.x / LakeAxes.x, p.y / LakeAxes.y);
        float angle = Mathf.Atan2(p.y, p.x);
        float shore = 1f + 0.14f * Mathf.Sin(3f * angle) + 0.08f * Mathf.Sin(5f * angle);
        shore += 0.07f * Mathf.Cos(2f * angle);
        return (p.magnitude - shore) * LakeAxes.y;
    }

    static float RiverDistance(float x, float z)
    {
        float width = 9f + 2f * Mathf.Sin(z / 31f) + 1.4f * Mathf.Cos(z / 17f);
        float slope = RiverSlope(z);
        float distance = Mathf.Abs(x - RiverX(z)) / Mathf.Sqrt(1f + slope * slope) - width;
        return Mathf.Max(distance, Mathf.Max(RiverBegin - z, z - RiverEnd));
    }

    static float SourceDistanceToWater(float x, float z)
    {
        if (x < 15f || x > 340f || z < -125f || z > 355f) return 1000f;
        return Mathf.Min(LakeDistance(x, z), RiverDistance(x, z));
    }

    static float SourceWaterLevel(float z)
    {
        return LakeLevel * (1f - Smoothstep(0f, 320f, z));
    }

    static bool SourceWaterCovers(float x, float z, float margin = 0f)
    {
        return SourceDistanceToWater(x, z) < 6f + margin;
    }

    public static float DistanceToWater(float x, float z)
    {
        return SourceDistanceToWater(x / WorldScale, z / WorldScale) * WorldScale;
    }

    public static float WaterLevel(float z)
    {
        return SourceWaterLevel(z / WorldScale) * WorldScale;
    }

    public static bool WaterCovers(float x, float z, float margin = 0f)
    {
        return SourceWaterCovers(x / WorldScale, z / WorldScale, margin / WorldScale);
    }

    // ---- plaza batu / arena (arena_shape.gd) ----
    static readonly Vector2 ArenaCenter = new Vector2(-145f, 140f);
    const float ArenaRadius = 42f;
    const float ArenaHeight = 9f;

    static float SourceArenaDistance(float x, float z)
    {
        Vector2 p = new Vector2(x - ArenaCenter.x, z - ArenaCenter.y);
        float angle = Mathf.Atan2(p.y, p.x);
        float r = ArenaRadius + 1.4f * Mathf.Sin(angle * 5f) + 0.7f * Mathf.Cos(angle * 9f);
        return p.magnitude - r;
    }

    public static float ArenaDistance(float x, float z)
    {
        return SourceArenaDistance(x / WorldScale, z / WorldScale) * WorldScale;
    }

    // ---- tinggi terrain dalam koordinat sumber, lalu wrapper meter Unity ----
    static float SourceTerrainHeight(float x, float z)
    {
        float angle = Mathf.Atan2(z, x);
        float radius = 435f + 22f * Mathf.Sin(angle * 3f) + 18f * Mathf.Cos(angle * 5f);
        float inland = radius - new Vector2(x, z).magnitude;
        float coast = Smoothstep(-20f, 85f, inland);

        float hills = 48f * Mathf.Exp(-((x + 160f) * (x + 160f) + (z + 110f) * (z + 110f)) / 17000f);
        hills += 35f * Mathf.Exp(-((x - 120f) * (x - 120f) + (z - 180f) * (z - 180f)) / 12000f);

        // plateau tebing timur (gunung/tebing berbatu)
        float dCliff = new Vector2(x - 230f, z + 110f).magnitude;
        float cliff = 44f * (1f - Smoothstep(65f, 92f, dCliff));

        float rolling = 3f * Mathf.Sin(x / 48f) * Mathf.Cos(z / 61f);
        float height = -7f + coast * (12f + hills + cliff + rolling);

        float roadWeight = (1f - Smoothstep(13f, 38f, SourceRoadDistance(x, z)))
                         * (1f - Smoothstep(300f, 350f, Mathf.Abs(z)));
        height = Lerp(height, SourceRoadHeight(z), roadWeight);

        // ukir badan air (danau+sungai), lalu plaza arena
        float dw = SourceDistanceToWater(x, z);
        if (dw < 22f)
        {
            float bed = SourceWaterLevel(z) - 2.6f * (1f - Smoothstep(-12f, 1.5f, dw));
            float infl = 1f - Smoothstep(0f, 22f, dw);
            height = Mathf.Min(height, Lerp(height, bed, infl));
        }
        height = Lerp(ArenaHeight, height, Smoothstep(0f, 22f, SourceArenaDistance(x, z)));
        return height;
    }

    public static float TerrainHeight(float x, float z)
    {
        return SourceTerrainHeight(x / WorldScale, z / WorldScale) * WorldScale;
    }

    /// <summary>Interpolasi segitiga yang SAMA dengan mesh collider.</summary>
    public float SurfaceHeight(float x, float z)
    {
        // Input/output dalam koordinat dunia; mesh dan height array tetap
        // disimpan pada grid sumber berukuran 1 km dan diperkecil oleh transform.
        Vector3 local = transform.InverseTransformPoint(new Vector3(x, 0f, z));
        float gx = Mathf.Clamp((local.x + SourceHalfSize) / Step, 0f, Cells - 0.001f);
        float gz = Mathf.Clamp((local.z + SourceHalfSize) / Step, 0f, Cells - 0.001f);
        int ix = (int)gx, iz = (int)gz;
        float fx = gx - ix, fz = gz - iz;
        float a = H(ix, iz), b = H(ix + 1, iz), c = H(ix, iz + 1), d = H(ix + 1, iz + 1);
        float localHeight = fx + fz <= 1f
            ? a + (b - a) * fx + (c - a) * fz
            : d + (c - d) * (1f - fx) + (b - d) * (1f - fz);
        return transform.TransformPoint(new Vector3(local.x, localHeight, local.z)).y;
    }

    float H(int x, int z)
    {
        return heights[Mathf.Clamp(z, 0, Cells) * (Cells + 1) + Mathf.Clamp(x, 0, Cells)];
    }

    /// <summary>Permukaan air di titik itu (laut 0 / danau-sungai level(z)); -999 bila kering.</summary>
    public float WaterLevelAt(float x, float z)
    {
        float surf = SurfaceHeight(x, z);
        float lake = WaterCovers(x, z) ? WaterLevel(z) : -999f;
        return Mathf.Max(surf < 0f ? 0f : -999f, lake);
    }

    public bool IsWalkableShore(float x, float z)
    {
        float wl = WaterCovers(x, z) ? Mathf.Max(WaterLevel(z), 0f) : 0f;
        return SurfaceHeight(x, z) >= wl + 0.6f * WorldScale;
    }

    void OnDestroy()
    {
        if (I == this) I = null;
        if (terrainMesh != null) Destroy(terrainMesh);
        if (inlandWaterMesh != null) Destroy(inlandWaterMesh);
        if (terrainMaterial != null) Destroy(terrainMaterial);
        if (waterMaterial != null) Destroy(waterMaterial);
    }

    // ================= build =================

    public static IslandTerrain Build()
    {
        var go = new GameObject("Island");
        go.transform.localScale = Vector3.one * WorldScale;
        var it = go.AddComponent<IslandTerrain>();
        it.BuildInternal();
        I = it;
        return it;
    }

    void BuildInternal()
    {
        for (int z = 0; z <= Cells; z++)
            for (int x = 0; x <= Cells; x++)
                heights[z * (Cells + 1) + x] = SourceTerrainHeight(x * Step - SourceHalfSize, z * Step - SourceHalfSize);

        BuildTerrainMesh();
        BuildWater();
        BuildRocks();

        SpawnPoint = new Vector3(ArenaCenter.x * WorldScale,
                                 ArenaHeight * WorldScale + 0.05f,
                                 ArenaCenter.y * WorldScale);
    }

    void BuildTerrainMesh()
    {
        int n = Cells + 1;
        var verts = new Vector3[n * n];
        var norms = new Vector3[n * n];
        var cols = new Color[n * n];

        for (int z = 0; z <= Cells; z++)
        {
            for (int x = 0; x <= Cells; x++)
            {
                float h = H(x, z);
                verts[z * n + x] = new Vector3(x * Step - SourceHalfSize, h, z * Step - SourceHalfSize);

                // normal halus (beda pusat) — redesign: tanpa facet low-poly
                float hx = H(x - 1, z) - H(x + 1, z);
                float hz = H(x, z - 1) - H(x, z + 1);
                Vector3 nrm = new Vector3(hx, 2f * Step, hz).normalized;
                norms[z * n + x] = nrm;

                // warna lahan: rumput datar, batu di sisi curam, pasir di pantai
                Color col = Color.Lerp(GrassCol, CliffCol, 1f - Smoothstep(0.65f, 0.88f, nrm.y));
                col = Color.Lerp(SandCol, col, Smoothstep(1f, 5f, h));
                cols[z * n + x] = col;
            }
        }

        var tris = new int[Cells * Cells * 6];
        int ti = 0;
        for (int z = 0; z < Cells; z++)
        {
            for (int x = 0; x < Cells; x++)
            {
                int a = z * n + x, b = a + 1, c = a + n, d = c + 1;
                tris[ti++] = a; tris[ti++] = c; tris[ti++] = b;
                tris[ti++] = b; tris[ti++] = c; tris[ti++] = d;
            }
        }

        terrainMesh = new Mesh();
        var mesh = terrainMesh;
        mesh.name = "IslandTerrain";
        mesh.indexFormat = UnityEngine.Rendering.IndexFormat.UInt32;
        mesh.vertices = verts;
        mesh.normals = norms;
        mesh.colors = cols;
        mesh.triangles = tris;
        mesh.RecalculateBounds();

        var mf = gameObject.AddComponent<MeshFilter>();
        mf.sharedMesh = mesh;
        var mr = gameObject.AddComponent<MeshRenderer>();
        var shader = Resources.Load<Shader>("Shaders/IslandTerrain");
        if (shader == null) shader = Shader.Find("UAL2/IslandTerrain");
        terrainMaterial = new Material(shader);
        var mat = terrainMaterial;
        if (mat.HasProperty("_WorldScale")) mat.SetFloat("_WorldScale", WorldScale);
        var meadow = RemoteAssetCatalog.Load<Texture2D>("arpg-world", "meadow_cover");
        if (meadow == null) meadow = Resources.Load<Texture2D>("WorldGen/Textures/meadow_cover");
        if (meadow != null) mat.SetTexture("_MeadowCover", meadow);
        mr.sharedMaterial = mat;
        mr.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.On;
        mr.receiveShadows = true;

        var mc = gameObject.AddComponent<MeshCollider>();
        mc.sharedMesh = mesh;
    }

    void BuildWater()
    {
        waterMaterial = new Material(Shader.Find("Standard"));
        var waterMat = waterMaterial;
        waterMat.SetColor("_Color", new Color(0.396f, 0.725f, 0.784f, 0.82f));  // #65b9c8
        waterMat.SetFloat("_Mode", 3f);
        waterMat.EnableKeyword("_ALPHABLEND_ON");
        waterMat.SetFloat("_Glossiness", 0.72f);
        waterMat.SetFloat("_Metallic", 0f);
        waterMat.SetOverrideTag("RenderType", "Transparent");
        waterMat.renderQueue = 3000;

        // Laut lepas: ukuran sumber ikut diperkecil oleh transform pulau.
        var sea = GameObject.CreatePrimitive(PrimitiveType.Plane);
        sea.name = "Sea";
        sea.transform.SetParent(transform, false);
        sea.transform.localPosition = new Vector3(0f, SeaLevel, 0f);
        sea.transform.localScale = new Vector3(400f, 1f, 400f);   // 800 m setelah skala dunia
        Object.Destroy(sea.GetComponent<Collider>());
        var seaMr = sea.GetComponent<MeshRenderer>();
        seaMr.sharedMaterial = waterMat;
        seaMr.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;

        // permukaan danau + sungai (mengikuti level(z) yang menurun ke laut)
        var verts = new List<Vector3>();
        var norms = new List<Vector3>();
        var tris = new List<int>();
        const float tile = 40f, wstep = 2.5f;
        for (float z0 = -120f; z0 < 360f; z0 += tile)
        {
            for (float x0 = 0f; x0 < 360f; x0 += tile)
            {
                for (float z = z0; z < z0 + tile - 0.01f; z += wstep)
                {
                    for (float x = x0; x < x0 + tile - 0.01f; x += wstep)
                    {
                        if (SourceDistanceToWater(x + wstep * 0.5f, z + wstep * 0.5f) > 7f) continue;
                        if (z >= 317.5f) continue;   // di sana laut sudah menyambung
                        int b = verts.Count;
                        AddWaterQuad(verts, norms, tris, b, x, z, wstep);
                    }
                }
            }
        }
        if (verts.Count > 0)
        {
            inlandWaterMesh = new Mesh();
            var wm = inlandWaterMesh;
            wm.name = "InlandWater";
            wm.indexFormat = UnityEngine.Rendering.IndexFormat.UInt32;
            wm.SetVertices(verts);
            wm.SetNormals(norms);
            wm.SetTriangles(tris, 0);
            var wgo = new GameObject("InlandWater");
            wgo.transform.SetParent(transform, false);
            var wmf = wgo.AddComponent<MeshFilter>();
            wmf.sharedMesh = wm;
            var wmr = wgo.AddComponent<MeshRenderer>();
            wmr.sharedMaterial = waterMat;
            wmr.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
        }
    }

    static void AddWaterQuad(List<Vector3> verts, List<Vector3> norms, List<int> tris,
                             int b, float x, float z, float s)
    {
        Vector2[] corners = { new Vector2(0, 0), new Vector2(s, 0), new Vector2(0, s), new Vector2(s, s) };
        for (int i = 0; i < 4; i++)
        {
            float px = x + corners[i].x, pz = z + corners[i].y;
            verts.Add(new Vector3(px, SourceWaterLevel(pz) - 0.02f, pz));
            norms.Add(Vector3.up);
        }
        tris.Add(b); tris.Add(b + 2); tris.Add(b + 1);
        tris.Add(b + 1); tris.Add(b + 2); tris.Add(b + 3);
    }

    void BuildRocks()
    {
        var prefabs = RemoteAssetCatalog.LoadAll<GameObject>("arpg-world");
        if (prefabs.Length == 0) prefabs = Resources.LoadAll<GameObject>("WorldGen/Prefabs");
        GameObject r1 = null, r2 = null;
        foreach (var p in prefabs)
        {
            if (p.name == "Rock_Medium_1") r1 = p;
            else if (p.name == "Rock_Medium_2") r2 = p;
        }
        if (r1 == null || r2 == null) return;

        var rng = new System.Random(42017);
        // Boulder tetap berukuran realistis (dalam meter Unity); hanya
        // koordinat fitur terrain yang diperkecil.
        var parent = new GameObject("Boulders").transform;
        int placed = 0;
        for (int i = 0; i < 60 && placed < 40; i++)
        {
            float sourceX = (float)(rng.NextDouble() * 740.0 - 370.0);
            float sourceZ = (float)(rng.NextDouble() * 740.0 - 370.0);
            float x = sourceX * WorldScale, z = sourceZ * WorldScale;
            float y = SurfaceHeight(x, z);
            if (ArenaDistance(x, z) < 5f) continue;
            if (y < 2f * WorldScale || RoadDistance(x, z) < 24f * WorldScale
                || WaterCovers(x, z, 5f)) continue;

            var prefab = rng.NextDouble() < 0.5 ? r1 : r2;
            var go = Instantiate(prefab, parent);
            float s = 1.4f + (float)rng.NextDouble() * 2.2f;
            go.transform.position = new Vector3(x, y - 0.3f * s, z);
            go.transform.rotation = Quaternion.Euler(0f, (float)rng.NextDouble() * 360f, 0f);
            go.transform.localScale = new Vector3(
                s * (0.85f + (float)rng.NextDouble() * 0.5f),
                s * (0.7f + (float)rng.NextDouble() * 0.5f),
                s * (0.85f + (float)rng.NextDouble() * 0.5f));
            RockClearances.Add(new Vector3(x, s * 1.2f, z));
            placed++;
        }
        Debug.Log("[Island] boulder terpasang: " + placed);
    }
}
