using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

/// <summary>
/// Lorong modular tanpa ujung: jalur beton terang di kiri, dinding/atap putih,
/// dan kolam jernih yang makin dalam di kanan. Modul 24 meter didaur ulang
/// saat pemain melangkah, sehingga dunia tidak memiliki ujung atau batas float.
/// </summary>
public class EndlessRoom : MonoBehaviour
{
    public const float SegmentLength = 24f;
    public const int SegmentCount = 11;
    public const float LeftWallX = -4.6f;
    public const float WalkwayEdgeX = 0.63f;
    public const float WaterStartX = 0.63f;
    public const float RightWallX = 38f;
    public const float CeilingY = 8.2f;
    public const float WaterY = -0.38f;
    public const float ShallowWaterDepth = 0.95f;
    public const float DeepWaterDepth = 5.2f;
    public const float SpawnX = -2.35f;
    public const float MinWalkX = -4.25f;
    public const float MaxWalkX = -0.16f;

    public int ActiveSegmentCount { get { return segments.Count; } }
    public int WrapCount { get; private set; }
    public bool IsBuilt { get; private set; }
    public float WaterWidth { get { return RightWallX - WaterStartX; } }

    readonly List<Transform> segments = new List<Transform>();
    FirstPersonRoomController player;

    Material wallMaterial;
    Material floorMaterial;
    Material trimMaterial;
    Material edgeMaterial;
    Material lightMaterial;
    Material waterMaterial;
    Material waterBedMaterial;

    Mesh architectureMesh;
    Mesh floorMesh;
    Mesh detailMesh;
    Mesh edgeMesh;
    Mesh fixtureMesh;
    Mesh waterMesh;
    Mesh waterBedMesh;

    public static EndlessRoom Build(Transform parent, FirstPersonRoomController controller)
    {
        var root = new GameObject("Endless White Room + Stillwater");
        root.transform.SetParent(parent, false);
        var room = root.AddComponent<EndlessRoom>();
        room.Initialize(controller);
        return room;
    }

    void Initialize(FirstPersonRoomController controller)
    {
        player = controller;
        CreateMaterials();
        CreateMeshes();
        CreateCollisionVolumes();

        int first = -(SegmentCount - 1) / 2;
        for (int i = 0; i < SegmentCount; i++)
        {
            float z = (first + i) * SegmentLength;
            segments.Add(CreateSegment(i, z));
        }

        IsBuilt = true;
        Debug.Log("[Room] Lorong first-person siap; modul aktif: " + segments.Count
            + ", lebar air: " + WaterWidth.ToString("F1") + " m.");
    }

    void CreateMaterials()
    {
        Shader porcelain = Resources.Load<Shader>("Shaders/RoomPorcelain");
        if (porcelain == null) porcelain = Shader.Find("Stillwater/Porcelain");
        if (porcelain == null) porcelain = Shader.Find("Standard");

        wallMaterial = MakePorcelain(porcelain, "Wall | warm white", new Color(0.79f, 0.82f, 0.83f),
            0.025f, 0.85f, 0.66f, 0f, 0f, Color.white);
        floorMaterial = MakePorcelain(porcelain, "Walkway | honed concrete", new Color(0.56f, 0.59f, 0.60f),
            0.075f, 1.15f, 0.58f, 0.055f, 1.44f, new Color(0.38f, 0.41f, 0.42f));
        trimMaterial = MakePorcelain(porcelain, "Edge | pale stone", new Color(0.64f, 0.68f, 0.69f),
            0.035f, 1.1f, 0.58f, 0.035f, 0f, Color.white);
        edgeMaterial = MakePorcelain(porcelain, "Depth | blue-black", new Color(0.009f, 0.025f, 0.032f),
            0.02f, 1.0f, 0.78f, 0f, 0f, Color.white);

        Shader standard = Shader.Find("Standard");
        if (standard == null) standard = porcelain;
        lightMaterial = new Material(standard);
        lightMaterial.name = "Soft ceiling light";
        if (lightMaterial.HasProperty("_Color"))
            lightMaterial.SetColor("_Color", new Color(0.94f, 0.98f, 1f, 1f));
        if (lightMaterial.HasProperty("_Glossiness")) lightMaterial.SetFloat("_Glossiness", 0.82f);
        lightMaterial.EnableKeyword("_EMISSION");
        if (lightMaterial.HasProperty("_EmissionColor"))
            lightMaterial.SetColor("_EmissionColor", new Color(1.35f, 1.42f, 1.45f, 1f));

        Shader waterShader = Resources.Load<Shader>("Shaders/StillWater");
        if (waterShader == null) waterShader = Shader.Find("Stillwater/DeepCalmWater");
        if (waterShader == null) waterShader = standard;
        waterMaterial = new Material(waterShader);
        waterMaterial.name = "Clear shallow-to-deep water";
        waterMaterial.renderQueue = (int)RenderQueue.Transparent;
        SetIfPresent(waterMaterial, "_NearColor", new Color(0.13f, 0.29f, 0.32f, 1f));
        SetIfPresent(waterMaterial, "_DeepColor", new Color(0.018f, 0.060f, 0.082f, 1f));
        SetIfPresent(waterMaterial, "_ReflectionColor", new Color(0.42f, 0.60f, 0.66f, 1f));
        SetIfPresent(waterMaterial, "_WaterStartX", WaterStartX);
        SetIfPresent(waterMaterial, "_ShallowOpacity", 0.24f);
        SetIfPresent(waterMaterial, "_DeepOpacity", 0.82f);

        Shader waterBedShader = Resources.Load<Shader>("Shaders/UnderwaterBed");
        if (waterBedShader == null) waterBedShader = Shader.Find("Stillwater/UnderwaterBed");
        if (waterBedShader == null) waterBedShader = porcelain;
        waterBedMaterial = new Material(waterBedShader);
        waterBedMaterial.name = "Submerged basin stone";
        SetIfPresent(waterBedMaterial, "_ShallowColor", new Color(0.40f, 0.49f, 0.48f, 1f));
        SetIfPresent(waterBedMaterial, "_DeepColor", new Color(0.075f, 0.15f, 0.18f, 1f));
        SetIfPresent(waterBedMaterial, "_WaterStartX", WaterStartX);
        SetIfPresent(waterBedMaterial, "_RightWallX", RightWallX);
    }

    static Material MakePorcelain(Shader shader, string materialName, Color color,
        float noiseAmount, float noiseScale, float smoothness, float metallic,
        float panelScale, Color panelTint)
    {
        var material = new Material(shader);
        material.name = materialName;
        SetIfPresent(material, "_BaseColor", color);
        SetIfPresent(material, "_Color", color);
        SetIfPresent(material, "_NoiseAmount", noiseAmount);
        SetIfPresent(material, "_NoiseScale", noiseScale);
        SetIfPresent(material, "_Smoothness", smoothness);
        SetIfPresent(material, "_Metallic", metallic);
        SetIfPresent(material, "_PanelScale", panelScale);
        SetIfPresent(material, "_PanelWidth", 0.003f);
        SetIfPresent(material, "_PanelTint", panelTint);
        return material;
    }

    static void SetIfPresent(Material material, string property, Color value)
    {
        if (material.HasProperty(property)) material.SetColor(property, value);
    }

    static void SetIfPresent(Material material, string property, float value)
    {
        if (material.HasProperty(property)) material.SetFloat(property, value);
    }

    void CreateMeshes()
    {
        architectureMesh = BuildArchitectureMesh();
        floorMesh = BuildFloorMesh();
        detailMesh = BuildDetailMesh();
        edgeMesh = BuildEdgeMesh();
        fixtureMesh = BuildFixtureMesh();
        waterMesh = BuildWaterMesh();
        waterBedMesh = BuildWaterBedMesh();
    }

    Transform CreateSegment(int index, float z)
    {
        var segment = new GameObject("Room module " + index.ToString("00"));
        segment.transform.SetParent(transform, false);
        segment.transform.localPosition = new Vector3(0f, 0f, z);

        AddMeshObject(segment.transform, "White architecture", architectureMesh, wallMaterial, true, true);
        AddMeshObject(segment.transform, "Left walkway", floorMesh, floorMaterial, true, true);
        AddMeshObject(segment.transform, "Trim and wall panels", detailMesh, trimMaterial, false, true);
        AddMeshObject(segment.transform, "Deep water edge", edgeMesh, edgeMaterial, false, true);
        AddMeshObject(segment.transform, "Diffused ceiling panels", fixtureMesh, lightMaterial, false, false);
        AddMeshObject(segment.transform, "Sloped submerged basin floor", waterBedMesh, waterBedMaterial, false, false);
        AddMeshObject(segment.transform, "Clear shallow-to-deep water", waterMesh, waterMaterial, false, false);

        // Sumber cahaya lembut tiap 24 m. Bayangan diserahkan ke satu sun
        // berintensitas rendah agar tetap ringan untuk GPU ponsel.
        var lightGO = new GameObject("Soft ceiling bounce");
        lightGO.transform.SetParent(segment.transform, false);
        lightGO.transform.localPosition = new Vector3(-2.1f, CeilingY - 0.8f, 0f);
        var light = lightGO.AddComponent<Light>();
        light.type = LightType.Point;
        light.color = new Color(0.80f, 0.88f, 0.94f);
        light.intensity = 0.82f;
        light.range = 18f;
        light.shadows = LightShadows.None;

        return segment.transform;
    }

    static void AddMeshObject(Transform parent, string name, Mesh mesh, Material material,
        bool castShadows, bool receiveShadows)
    {
        var go = new GameObject(name);
        go.transform.SetParent(parent, false);
        var filter = go.AddComponent<MeshFilter>();
        filter.sharedMesh = mesh;
        var renderer = go.AddComponent<MeshRenderer>();
        renderer.sharedMaterial = material;
        renderer.shadowCastingMode = castShadows ? ShadowCastingMode.On : ShadowCastingMode.Off;
        renderer.receiveShadows = receiveShadows;
    }

    void CreateCollisionVolumes()
    {
        var collisionRoot = new GameObject("Continuous walkway collision");
        collisionRoot.transform.SetParent(transform, false);
        float length = SegmentCount * SegmentLength * 2f;

        var floor = collisionRoot.AddComponent<BoxCollider>();
        floor.center = new Vector3((LeftWallX + WalkwayEdgeX) * 0.5f, -0.14f, 0f);
        floor.size = new Vector3(WalkwayEdgeX - LeftWallX, 0.28f, length);

        var leftWallGO = new GameObject("Left wall collision");
        leftWallGO.transform.SetParent(collisionRoot.transform, false);
        var leftWall = leftWallGO.AddComponent<BoxCollider>();
        leftWall.center = new Vector3(LeftWallX - 0.10f, CeilingY * 0.5f, 0f);
        leftWall.size = new Vector3(0.20f, CeilingY, length);

        var rightWallGO = new GameObject("Far wall collision");
        rightWallGO.transform.SetParent(collisionRoot.transform, false);
        var rightWall = rightWallGO.AddComponent<BoxCollider>();
        rightWall.center = new Vector3(RightWallX + 0.10f, CeilingY * 0.5f, 0f);
        rightWall.size = new Vector3(0.20f, CeilingY, length);
    }

    Mesh BuildArchitectureMesh()
    {
        const float z0 = -SegmentLength * 0.5f;
        const float z1 = SegmentLength * 0.5f;
        var mesh = new MeshBuilder("Room architecture");

        // Dinding kiri menghadap jalur (+X).
        mesh.AddQuad(
            new Vector3(LeftWallX, 0f, z0),
            new Vector3(LeftWallX, CeilingY, z0),
            new Vector3(LeftWallX, 0f, z1),
            new Vector3(LeftWallX, CeilingY, z1),
            new Vector2(z0 * 0.22f, 0f), new Vector2(z0 * 0.22f, CeilingY * 0.22f),
            new Vector2(z1 * 0.22f, 0f), new Vector2(z1 * 0.22f, CeilingY * 0.22f));

        // Dinding jauh menghadap ke dalam (-X); membingkai keluasan air.
        mesh.AddQuad(
            new Vector3(RightWallX, 0f, z0),
            new Vector3(RightWallX, 0f, z1),
            new Vector3(RightWallX, CeilingY, z0),
            new Vector3(RightWallX, CeilingY, z1),
            new Vector2(z0 * 0.22f, 0f), new Vector2(z1 * 0.22f, 0f),
            new Vector2(z0 * 0.22f, CeilingY * 0.22f), new Vector2(z1 * 0.22f, CeilingY * 0.22f));

        // Plafon dilihat dari sisi bawah (normal menghadap ke bawah).
        mesh.AddQuad(
            new Vector3(LeftWallX, CeilingY, z0),
            new Vector3(RightWallX, CeilingY, z0),
            new Vector3(LeftWallX, CeilingY, z1),
            new Vector3(RightWallX, CeilingY, z1),
            new Vector2(LeftWallX * 0.16f, z0 * 0.16f),
            new Vector2(RightWallX * 0.16f, z0 * 0.16f),
            new Vector2(LeftWallX * 0.16f, z1 * 0.16f),
            new Vector2(RightWallX * 0.16f, z1 * 0.16f));

        return mesh.Build();
    }

    Mesh BuildFloorMesh()
    {
        const float z0 = -SegmentLength * 0.5f;
        const float z1 = SegmentLength * 0.5f;
        var mesh = new MeshBuilder("Honed concrete walkway");
        mesh.AddQuad(
            new Vector3(LeftWallX, 0f, z0),
            new Vector3(LeftWallX, 0f, z1),
            new Vector3(WalkwayEdgeX, 0f, z0),
            new Vector3(WalkwayEdgeX, 0f, z1),
            new Vector2(LeftWallX * 0.24f, z0 * 0.24f),
            new Vector2(LeftWallX * 0.24f, z1 * 0.24f),
            new Vector2(WalkwayEdgeX * 0.24f, z0 * 0.24f),
            new Vector2(WalkwayEdgeX * 0.24f, z1 * 0.24f));
        return mesh.Build();
    }

    Mesh BuildDetailMesh()
    {
        const float z0 = -SegmentLength * 0.5f;
        const float z1 = SegmentLength * 0.5f;
        var mesh = new MeshBuilder("Room details");

        // Ambang rendah di tepi air; jalur tetap terbuka tanpa pagar yang mengganggu pandangan.
        mesh.AddBox(new Vector3(0.28f, 0f, z0), new Vector3(WaterStartX, 0.23f, z1));

        // Lis bawah dan celah panel yang halus — skala manusia, tanpa dekorasi ramai.
        mesh.AddBox(new Vector3(LeftWallX + 0.035f, 0.08f, z0),
            new Vector3(LeftWallX + 0.14f, 0.24f, z1));
        mesh.AddBox(new Vector3(RightWallX - 0.14f, 0.08f, z0),
            new Vector3(RightWallX - 0.035f, 0.24f, z1));
        mesh.AddBox(new Vector3(LeftWallX + 0.04f, CeilingY - 0.24f, z0),
            new Vector3(LeftWallX + 0.12f, CeilingY - 0.17f, z1));
        mesh.AddBox(new Vector3(RightWallX - 0.12f, CeilingY - 0.24f, z0),
            new Vector3(RightWallX - 0.04f, CeilingY - 0.17f, z1));

        for (int i = -1; i <= 2; i++)
        {
            float seamZ = i * 6f;
            mesh.AddBox(new Vector3(LeftWallX + 0.012f, 0.32f, seamZ - 0.012f),
                new Vector3(LeftWallX + 0.026f, CeilingY - 0.33f, seamZ + 0.012f));
            mesh.AddBox(new Vector3(RightWallX - 0.026f, 0.32f, seamZ - 0.012f),
                new Vector3(RightWallX - 0.012f, CeilingY - 0.33f, seamZ + 0.012f));
        }

        // Sambungan slab melintang tiap enam meter di sepanjang walkway.
        for (int i = -1; i <= 2; i++)
        {
            float jointZ = i * 6f;
            mesh.AddBox(new Vector3(LeftWallX + 0.12f, 0.001f, jointZ - 0.012f),
                new Vector3(WaterStartX - 0.36f, 0.004f, jointZ + 0.012f));
        }

        return mesh.Build();
    }

    Mesh BuildEdgeMesh()
    {
        const float z0 = -SegmentLength * 0.5f;
        const float z1 = SegmentLength * 0.5f;
        var mesh = new MeshBuilder("Water drop edge");
        mesh.AddBox(new Vector3(WaterStartX - 0.075f, WaterY - ShallowWaterDepth, z0),
            new Vector3(WaterStartX + 0.01f, 0.015f, z1));
        mesh.AddBox(new Vector3(0.14f, 0.003f, z0), new Vector3(0.19f, 0.009f, z1));

        // Submerged far wall closes the basin below the waterline.
        mesh.AddBox(new Vector3(RightWallX - 0.12f, WaterY - DeepWaterDepth, z0),
            new Vector3(RightWallX, WaterY + 0.015f, z1));
        return mesh.Build();
    }

    Mesh BuildFixtureMesh()
    {
        var mesh = new MeshBuilder("Diffused ceiling panels");
        float[] rows = { -2.15f, 8.5f, 20f, 31.5f };
        for (int row = 0; row < rows.Length; row++)
        {
            for (int i = -1; i <= 1; i++)
            {
                float centerZ = i * 8f;
                Vector3 min = new Vector3(rows[row] - 0.92f, CeilingY - 0.085f, centerZ - 1.65f);
                Vector3 max = new Vector3(rows[row] + 0.92f, CeilingY - 0.025f, centerZ + 1.65f);
                mesh.AddBox(min, max);
            }
        }
        return mesh.Build();
    }

    Mesh BuildWaterMesh()
    {
        const int XSteps = 30;
        const int ZSteps = 24;
        const float z0 = -SegmentLength * 0.5f;
        const float z1 = SegmentLength * 0.5f;
        var vertices = new List<Vector3>((XSteps + 1) * (ZSteps + 1));
        var uvs = new List<Vector2>(vertices.Capacity);
        var normals = new List<Vector3>(vertices.Capacity);
        var triangles = new List<int>(XSteps * ZSteps * 6);

        for (int z = 0; z <= ZSteps; z++)
        {
            float fz = (float)z / ZSteps;
            float pz = Mathf.Lerp(z0, z1, fz);
            for (int x = 0; x <= XSteps; x++)
            {
                float fx = (float)x / XSteps;
                float px = Mathf.Lerp(WaterStartX, RightWallX, fx);
                vertices.Add(new Vector3(px, WaterY, pz));
                uvs.Add(new Vector2(px, pz));
                normals.Add(Vector3.up);
            }
        }

        int stride = XSteps + 1;
        for (int z = 0; z < ZSteps; z++)
        {
            for (int x = 0; x < XSteps; x++)
            {
                int a = z * stride + x;
                int b = a + 1;
                int c = a + stride;
                int d = c + 1;
                triangles.Add(a); triangles.Add(c); triangles.Add(b);
                triangles.Add(b); triangles.Add(c); triangles.Add(d);
            }
        }

        var mesh = new Mesh();
        mesh.name = "Deep water surface";
        mesh.indexFormat = IndexFormat.UInt32;
        mesh.SetVertices(vertices);
        mesh.SetUVs(0, uvs);
        mesh.SetNormals(normals);
        mesh.SetTriangles(triangles, 0);

        var tangents = new Vector4[vertices.Count];
        for (int i = 0; i < tangents.Length; i++) tangents[i] = new Vector4(1f, 0f, 0f, -1f);
        mesh.tangents = tangents;
        mesh.RecalculateBounds();
        var bounds = mesh.bounds;
        bounds.Expand(new Vector3(0f, 0.06f, 0f));
        mesh.bounds = bounds;
        return mesh;
    }

    Mesh BuildWaterBedMesh()
    {
        const int XSteps = 36;
        const int ZSteps = 24;
        const float z0 = -SegmentLength * 0.5f;
        const float z1 = SegmentLength * 0.5f;
        var vertices = new List<Vector3>((XSteps + 1) * (ZSteps + 1));
        var triangles = new List<int>(XSteps * ZSteps * 6);

        for (int z = 0; z <= ZSteps; z++)
        {
            float pz = Mathf.Lerp(z0, z1, (float)z / ZSteps);
            for (int x = 0; x <= XSteps; x++)
            {
                float across = (float)x / XSteps;
                float px = Mathf.Lerp(WaterStartX, RightWallX, across);
                float slope = Mathf.SmoothStep(0f, 1f, across);
                float bedY = WaterY - Mathf.Lerp(ShallowWaterDepth, DeepWaterDepth, slope);
                vertices.Add(new Vector3(px, bedY, pz));
            }
        }

        int stride = XSteps + 1;
        for (int z = 0; z < ZSteps; z++)
        {
            for (int x = 0; x < XSteps; x++)
            {
                int a = z * stride + x;
                int b = a + 1;
                int c = a + stride;
                int d = c + 1;
                triangles.Add(a); triangles.Add(c); triangles.Add(b);
                triangles.Add(b); triangles.Add(c); triangles.Add(d);
            }
        }

        var mesh = new Mesh();
        mesh.name = "Sloped submerged stone basin";
        mesh.indexFormat = IndexFormat.UInt32;
        mesh.SetVertices(vertices);
        mesh.SetTriangles(triangles, 0);
        mesh.RecalculateNormals();
        mesh.RecalculateBounds();
        return mesh;
    }

    void OnDestroy()
    {
        DestroyRuntimeObject(architectureMesh);
        DestroyRuntimeObject(floorMesh);
        DestroyRuntimeObject(detailMesh);
        DestroyRuntimeObject(edgeMesh);
        DestroyRuntimeObject(fixtureMesh);
        DestroyRuntimeObject(waterMesh);
        DestroyRuntimeObject(waterBedMesh);
        DestroyRuntimeObject(wallMaterial);
        DestroyRuntimeObject(floorMaterial);
        DestroyRuntimeObject(trimMaterial);
        DestroyRuntimeObject(edgeMaterial);
        DestroyRuntimeObject(lightMaterial);
        DestroyRuntimeObject(waterMaterial);
        DestroyRuntimeObject(waterBedMaterial);
    }

    static void DestroyRuntimeObject(UnityEngine.Object value)
    {
        if (value == null) return;
        if (Application.isPlaying) UnityEngine.Object.Destroy(value);
        else UnityEngine.Object.DestroyImmediate(value);
    }

    void LateUpdate()
    {
        if (player == null || segments.Count == 0) return;

        while (player.transform.position.z > SegmentLength * 0.5f)
            RecycleForward();
        while (player.transform.position.z < -SegmentLength * 0.5f)
            RecycleBackward();
    }

    void RecycleForward()
    {
        player.RebaseZ(-SegmentLength);
        for (int i = 0; i < segments.Count; i++)
        {
            Vector3 p = segments[i].position;
            p.z -= SegmentLength;
            segments[i].position = p;
        }

        float nearest = float.MaxValue;
        float farthest = float.MinValue;
        Transform oldest = null;
        for (int i = 0; i < segments.Count; i++)
        {
            float z = segments[i].position.z;
            if (z < nearest) { nearest = z; oldest = segments[i]; }
            if (z > farthest) farthest = z;
        }
        Vector3 recycled = oldest.position;
        recycled.z = farthest + SegmentLength;
        oldest.position = recycled;
        WrapCount++;
    }

    void RecycleBackward()
    {
        player.RebaseZ(SegmentLength);
        for (int i = 0; i < segments.Count; i++)
        {
            Vector3 p = segments[i].position;
            p.z += SegmentLength;
            segments[i].position = p;
        }

        float nearest = float.MaxValue;
        float farthest = float.MinValue;
        Transform oldest = null;
        for (int i = 0; i < segments.Count; i++)
        {
            float z = segments[i].position.z;
            if (z < nearest) nearest = z;
            if (z > farthest) { farthest = z; oldest = segments[i]; }
        }
        Vector3 recycled = oldest.position;
        recycled.z = nearest - SegmentLength;
        oldest.position = recycled;
        WrapCount++;
    }

    sealed class MeshBuilder
    {
        readonly Mesh mesh;
        readonly List<Vector3> vertices = new List<Vector3>();
        readonly List<Vector2> uvs = new List<Vector2>();
        readonly List<int> triangles = new List<int>();

        public MeshBuilder(string name) { mesh = new Mesh(); mesh.name = name; }

        public void AddQuad(Vector3 p0, Vector3 p1, Vector3 p2, Vector3 p3,
            Vector2 uv0, Vector2 uv1, Vector2 uv2, Vector2 uv3)
        {
            int start = vertices.Count;
            vertices.Add(p0); vertices.Add(p1); vertices.Add(p2); vertices.Add(p3);
            uvs.Add(uv0); uvs.Add(uv1); uvs.Add(uv2); uvs.Add(uv3);
            triangles.Add(start); triangles.Add(start + 1); triangles.Add(start + 2);
            triangles.Add(start + 2); triangles.Add(start + 1); triangles.Add(start + 3);
        }

        public void AddBox(Vector3 min, Vector3 max)
        {
            // Top (+Y)
            AddQuad(new Vector3(min.x, max.y, min.z), new Vector3(min.x, max.y, max.z),
                new Vector3(max.x, max.y, min.z), new Vector3(max.x, max.y, max.z),
                Vector2.zero, Vector2.up, Vector2.right, Vector2.one);
            // Bottom (-Y)
            AddQuad(new Vector3(min.x, min.y, min.z), new Vector3(max.x, min.y, min.z),
                new Vector3(min.x, min.y, max.z), new Vector3(max.x, min.y, max.z),
                Vector2.zero, Vector2.right, Vector2.up, Vector2.one);
            // Left (-X)
            AddQuad(new Vector3(min.x, min.y, min.z), new Vector3(min.x, min.y, max.z),
                new Vector3(min.x, max.y, min.z), new Vector3(min.x, max.y, max.z),
                Vector2.zero, Vector2.up, Vector2.right, Vector2.one);
            // Right (+X)
            AddQuad(new Vector3(max.x, min.y, min.z), new Vector3(max.x, max.y, min.z),
                new Vector3(max.x, min.y, max.z), new Vector3(max.x, max.y, max.z),
                Vector2.zero, Vector2.up, Vector2.right, Vector2.one);
            // Back (-Z)
            AddQuad(new Vector3(min.x, min.y, min.z), new Vector3(min.x, max.y, min.z),
                new Vector3(max.x, min.y, min.z), new Vector3(max.x, max.y, min.z),
                Vector2.zero, Vector2.up, Vector2.right, Vector2.one);
            // Front (+Z)
            AddQuad(new Vector3(min.x, min.y, max.z), new Vector3(max.x, min.y, max.z),
                new Vector3(min.x, max.y, max.z), new Vector3(max.x, max.y, max.z),
                Vector2.zero, Vector2.right, Vector2.up, Vector2.one);
        }

        public Mesh Build()
        {
            mesh.indexFormat = IndexFormat.UInt32;
            mesh.SetVertices(vertices);
            mesh.SetUVs(0, uvs);
            mesh.SetTriangles(triangles, 0);
            mesh.RecalculateNormals();
            mesh.RecalculateBounds();
            return mesh;
        }
    }
}
