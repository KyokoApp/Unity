using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

/// <summary>
/// Mobile-friendly, standalone pool-room exploration environment. The connected
/// room modules are original runtime geometry inspired by the PoolRooms concept;
/// no Lethal Company runtime, DunGen package, or external model bundle is needed.
/// </summary>
public class PoolRoomsEnvironment : MonoBehaviour
{
    public const float SegmentLength = 24f;
    public const int SegmentCount = 8;
    public const float RoomHalfWidth = 12f;
    public const float CeilingY = 6.8f;
    public const float PoolHalfWidth = 6.2f;
    public const float PoolHalfLength = 8.3f;
    public const float WaterY = -0.18f;
    public const float ShallowDepth = 0.78f;
    public const float DeepDepth = 3.15f;
    public const float SpawnX = -7.6f;
    public const float MinWalkX = -11.2f;
    public const float MaxWalkX = 11.2f;
    const float PortalHalfWidth = 2.45f;
    const float SidePortalCenterX = -9.1f;
    const float SidePortalHalfWidth = 1.9f;
    const float PortalHeight = 4.2f;
    const float WallThickness = 0.24f;

    public int ActiveSegmentCount { get { return segments.Count; } }
    public int ActivePoolCount { get; private set; }
    public int WrapCount { get; private set; }
    public bool IsBuilt { get; private set; }

    readonly List<Transform> segments = new List<Transform>();
    readonly List<Mesh> ownedMeshes = new List<Mesh>();
    FirstPersonRoomController player;

    Material wallTileMaterial;
    Material floorTileMaterial;
    Material poolTileMaterial;
    Material ceilingTileMaterial;
    Material upperWallMaterial;
    Material trimMaterial;
    Material metalMaterial;
    Material lockerMaterial;
    Material woodMaterial;
    Material plantMaterial;
    Material soilMaterial;
    Material accentMaterial;
    Material lightMaterial;
    Material waterMaterial;
    Material waterBedMaterial;

    enum RoomKind
    {
        MainPool,
        LockerRoom,
        ShowerRoom,
        PalmAtrium
    }

    public static PoolRoomsEnvironment Build(Transform parent, FirstPersonRoomController controller)
    {
        var root = new GameObject("PoolRooms | Connected Interior");
        root.transform.SetParent(parent, false);
        var environment = root.AddComponent<PoolRoomsEnvironment>();
        environment.Initialize(controller);
        return environment;
    }

    void Initialize(FirstPersonRoomController controller)
    {
        player = controller;
        CreateMaterials();

        // Four-room cycle keeps every recycled module's next room type aligned.
        int firstRoomIndex = -(SegmentCount / 2) + 1;
        for (int i = 0; i < SegmentCount; i++)
        {
            int roomIndex = firstRoomIndex + i;
            float z = roomIndex * SegmentLength;
            RoomKind kind = (RoomKind)PositiveModulo(roomIndex, 4);
            segments.Add(CreateRoomSegment(i, z, kind));
        }

        IsBuilt = true;
        Debug.Log("[PoolRooms] Mobile interior ready: " + segments.Count
            + " connected rooms; pool rooms: " + ActivePoolCount + ".");
    }

    void CreateMaterials()
    {
        Shader tileShader = Resources.Load<Shader>("Shaders/PoolTile");
        if (tileShader == null) tileShader = Shader.Find("PoolRooms/TileSurface");
        Shader standard = Shader.Find("Standard");
        if (standard == null) standard = tileShader;
        if (tileShader == null) tileShader = standard;

        wallTileMaterial = MakeTile(tileShader, "Pool wall | blue ceramic",
            new Color(0.42f, 0.55f, 0.60f), new Color(0.16f, 0.24f, 0.28f), 0.65f, 0.035f, 0.075f, 0.34f);
        floorTileMaterial = MakeTile(tileShader, "Wet floor | graphite ceramic",
            new Color(0.30f, 0.38f, 0.41f), new Color(0.12f, 0.18f, 0.21f), 0.78f, 0.045f, 0.055f, 0.52f);
        poolTileMaterial = MakeTile(tileShader, "Pool coping | pale blue tile",
            new Color(0.61f, 0.72f, 0.74f), new Color(0.25f, 0.36f, 0.39f), 0.52f, 0.03f, 0.05f, 0.50f);
        ceilingTileMaterial = MakeTile(tileShader, "Ceiling | deep slate tile",
            new Color(0.19f, 0.24f, 0.28f), new Color(0.08f, 0.12f, 0.15f), 1.15f, 0.035f, 0.035f, 0.24f);

        upperWallMaterial = MakeStandard(standard, "Upper wall | cool concrete",
            new Color(0.22f, 0.28f, 0.32f), 0.02f, 0.18f, Color.black);
        trimMaterial = MakeStandard(standard, "Pool trim | porcelain",
            new Color(0.60f, 0.70f, 0.72f), 0.02f, 0.50f, Color.black);
        metalMaterial = MakeStandard(standard, "Brushed pool steel",
            new Color(0.34f, 0.44f, 0.48f), 0.55f, 0.70f, Color.black);
        lockerMaterial = MakeStandard(standard, "Locker enamel | faded blue",
            new Color(0.10f, 0.23f, 0.31f), 0.22f, 0.48f, Color.black);
        woodMaterial = MakeStandard(standard, "Bench | damp dark timber",
            new Color(0.24f, 0.19f, 0.14f), 0.02f, 0.26f, Color.black);
        plantMaterial = MakeStandard(standard, "Palm leaves",
            new Color(0.10f, 0.26f, 0.16f), 0f, 0.26f, Color.black);
        soilMaterial = MakeStandard(standard, "Planter soil",
            new Color(0.12f, 0.095f, 0.065f), 0f, 0.12f, Color.black);
        accentMaterial = MakeStandard(standard, "Pool lane accents",
            new Color(0.28f, 0.58f, 0.68f), 0.18f, 0.65f, Color.black);
        lightMaterial = MakeStandard(standard, "Frosted ceiling diffuser",
            new Color(0.82f, 0.91f, 0.94f), 0f, 0.62f, new Color(0.42f, 0.58f, 0.66f));

        Shader waterShader = Resources.Load<Shader>("Shaders/PoolWater");
        if (waterShader == null) waterShader = Shader.Find("PoolRooms/QuietPoolWater");
        if (waterShader == null) waterShader = standard;
        waterMaterial = new Material(waterShader);
        waterMaterial.name = "Clear shallow-to-deep pool water";
        waterMaterial.renderQueue = (int)RenderQueue.Transparent;
        SetIfPresent(waterMaterial, "_NearColor", new Color(0.17f, 0.37f, 0.43f, 1f));
        SetIfPresent(waterMaterial, "_DeepColor", new Color(0.018f, 0.085f, 0.13f, 1f));
        SetIfPresent(waterMaterial, "_ReflectionColor", new Color(0.48f, 0.68f, 0.74f, 1f));
        SetIfPresent(waterMaterial, "_PoolCenterX", 0f);
        SetIfPresent(waterMaterial, "_PoolHalfWidth", PoolHalfWidth);
        SetIfPresent(waterMaterial, "_ShallowOpacity", 0.20f);
        SetIfPresent(waterMaterial, "_DeepOpacity", 0.78f);

        Shader bedShader = Resources.Load<Shader>("Shaders/UnderwaterBed");
        if (bedShader == null) bedShader = Shader.Find("PoolRooms/SubmergedPoolTile");
        if (bedShader == null) bedShader = tileShader;
        waterBedMaterial = new Material(bedShader);
        waterBedMaterial.name = "Visible tiled pool bed";
        SetIfPresent(waterBedMaterial, "_ShallowColor", new Color(0.35f, 0.47f, 0.51f, 1f));
        SetIfPresent(waterBedMaterial, "_DeepColor", new Color(0.055f, 0.13f, 0.19f, 1f));
        SetIfPresent(waterBedMaterial, "_PoolCenterX", 0f);
        SetIfPresent(waterBedMaterial, "_PoolHalfWidth", PoolHalfWidth);
    }

    static Material MakeTile(Shader shader, string materialName, Color tileColor, Color groutColor,
        float tileSize, float groutWidth, float variation, float smoothness)
    {
        var material = new Material(shader);
        material.name = materialName;
        SetIfPresent(material, "_TileColor", tileColor);
        SetIfPresent(material, "_GroutColor", groutColor);
        SetIfPresent(material, "_TileSize", tileSize);
        SetIfPresent(material, "_GroutWidth", groutWidth);
        SetIfPresent(material, "_Variation", variation);
        SetIfPresent(material, "_Smoothness", smoothness);
        return material;
    }

    static Material MakeStandard(Shader shader, string materialName, Color color,
        float metallic, float smoothness, Color emission)
    {
        var material = new Material(shader);
        material.name = materialName;
        SetIfPresent(material, "_Color", color);
        SetIfPresent(material, "_BaseColor", color);
        SetIfPresent(material, "_Metallic", metallic);
        SetIfPresent(material, "_Glossiness", smoothness);
        SetIfPresent(material, "_Smoothness", smoothness);
        if (emission.maxColorComponent > 0.001f)
        {
            material.EnableKeyword("_EMISSION");
            SetIfPresent(material, "_EmissionColor", emission);
        }
        return material;
    }

    static void SetIfPresent(Material material, string property, Color value)
    {
        if (material != null && material.HasProperty(property)) material.SetColor(property, value);
    }

    static void SetIfPresent(Material material, string property, float value)
    {
        if (material != null && material.HasProperty(property)) material.SetFloat(property, value);
    }

    Transform CreateRoomSegment(int index, float z, RoomKind kind)
    {
        var segment = new GameObject("Pool room " + index.ToString("00") + " | " + kind);
        segment.transform.SetParent(transform, false);
        segment.transform.localPosition = new Vector3(0f, 0f, z);

        var walls = new MeshBuilder("Blue tiled pool walls");
        var upperWalls = new MeshBuilder("Cool concrete upper walls");
        var floors = new MeshBuilder("Wet ceramic room floor");
        var ceiling = new MeshBuilder("Slate pool ceiling");
        var trim = new MeshBuilder("Porcelain coping and door trim");
        var metal = new MeshBuilder("Pool steel fixtures");
        var lockers = new MeshBuilder("Locker bank geometry");
        var wood = new MeshBuilder("Bench and timber furniture");
        var plants = new MeshBuilder("Palm foliage");
        var soil = new MeshBuilder("Planters and soil");
        var accents = new MeshBuilder("Room accent details");
        var diffusers = new MeshBuilder("Frosted ceiling panels");
        Mesh water = null;
        Mesh bed = null;

        bool hasPool = kind == RoomKind.MainPool || kind == RoomKind.PalmAtrium;
        float poolHalfWidth = kind == RoomKind.PalmAtrium ? 3.75f : PoolHalfWidth;
        float poolHalfLength = kind == RoomKind.PalmAtrium ? 5.45f : PoolHalfLength;

        BuildRoomShell(walls, upperWalls, floors, ceiling, trim, kind, hasPool,
            poolHalfWidth, poolHalfLength);
        BuildRoomDetails(kind, trim, metal, lockers, wood, plants, soil, accents,
            poolHalfWidth, poolHalfLength);
        BuildCeilingDetails(ceiling, diffusers);

        AddMeshObject(segment.transform, "Blue ceramic walls", Track(walls.Build("Pool wall tiles")), wallTileMaterial);
        AddMeshObject(segment.transform, "Concrete upper walls", Track(upperWalls.Build("Pool upper walls")), upperWallMaterial);
        AddMeshObject(segment.transform, "Room floor tiles", Track(floors.Build("Pool tile floor")), floorTileMaterial);
        AddMeshObject(segment.transform, "Slate ceiling", Track(ceiling.Build("Pool ceiling")), ceilingTileMaterial);
        AddMeshObject(segment.transform, "Porcelain pool borders", Track(trim.Build("Pool coping")), poolTileMaterial);
        AddMeshObject(segment.transform, "Brushed metal", Track(metal.Build("Pool metal")), metalMaterial);
        AddMeshObject(segment.transform, "Blue lockers", Track(lockers.Build("Pool lockers")), lockerMaterial);
        AddMeshObject(segment.transform, "Wood benches", Track(wood.Build("Pool benches")), woodMaterial);
        AddMeshObject(segment.transform, "Palm leaves", Track(plants.Build("Pool atrium foliage")), plantMaterial);
        AddMeshObject(segment.transform, "Planters", Track(soil.Build("Pool atrium planters")), soilMaterial);
        AddMeshObject(segment.transform, "Blue accents", Track(accents.Build("Pool room accents")), accentMaterial);
        AddMeshObject(segment.transform, "Ceiling light diffusers", Track(diffusers.Build("Pool room lights")), lightMaterial);

        if (hasPool)
        {
            water = Track(BuildWaterSurface(poolHalfWidth, poolHalfLength));
            bed = Track(BuildWaterBed(poolHalfWidth, poolHalfLength));
            GameObject bedObject = AddMeshObject(segment.transform, "Submerged tiled pool floor", bed, waterBedMaterial);
            GameObject waterObject = AddMeshObject(segment.transform, "Pool water surface", water, waterMaterial);
            SetRendererFloat(bedObject, "_PoolHalfWidth", poolHalfWidth);
            SetRendererFloat(waterObject, "_PoolHalfWidth", poolHalfWidth);
            ActivePoolCount++;
        }

        AddRoomColliders(segment.transform, kind, poolHalfWidth, poolHalfLength);
        AddCeilingLights(segment.transform, kind);
        return segment.transform;
    }

    void BuildRoomShell(MeshBuilder walls, MeshBuilder upperWalls, MeshBuilder floors,
        MeshBuilder ceiling, MeshBuilder trim, RoomKind kind, bool hasPool,
        float poolHalfWidth, float poolHalfLength)
    {
        const float lowerTileHeight = 3.35f;
        const float halfLength = SegmentLength * 0.5f;
        float left = -RoomHalfWidth;
        float right = RoomHalfWidth;
        float wallInnerLeft = left + WallThickness;
        float wallInnerRight = right - WallThickness;

        // Two-tone tiled side walls.
        walls.AddBox(new Vector3(left, 0f, -halfLength),
            new Vector3(wallInnerLeft, lowerTileHeight, halfLength));
        walls.AddBox(new Vector3(wallInnerRight, 0f, -halfLength),
            new Vector3(right, lowerTileHeight, halfLength));
        upperWalls.AddBox(new Vector3(left, lowerTileHeight, -halfLength),
            new Vector3(wallInnerLeft, CeilingY, halfLength));
        upperWalls.AddBox(new Vector3(wallInnerRight, lowerTileHeight, -halfLength),
            new Vector3(right, CeilingY, halfLength));

        // Each end wall leaves a generous doorway so the four room types connect seamlessly.
        AddPortalWall(walls, upperWalls, trim, -halfLength, left, right, lowerTileHeight);
        AddPortalWall(walls, upperWalls, trim, halfLength, left, right, lowerTileHeight);

        if (hasPool)
        {
            float walkEdgeX = poolHalfWidth + 0.40f;
            float walkEdgeZ = poolHalfLength + 0.40f;
            AddFloorRegion(floors, left + WallThickness, -walkEdgeX, -halfLength, halfLength);
            AddFloorRegion(floors, walkEdgeX, right - WallThickness, -halfLength, halfLength);
            AddFloorRegion(floors, -walkEdgeX, walkEdgeX, -halfLength, -walkEdgeZ);
            AddFloorRegion(floors, -walkEdgeX, walkEdgeX, walkEdgeZ, halfLength);
        }
        else
        {
            AddFloorRegion(floors, left + WallThickness, right - WallThickness, -halfLength, halfLength);
        }

        // The ceiling is deliberately low and repeated, like a closed indoor aquatic facility.
        ceiling.AddQuad(
            new Vector3(left + WallThickness, CeilingY, -halfLength),
            new Vector3(right - WallThickness, CeilingY, -halfLength),
            new Vector3(left + WallThickness, CeilingY, halfLength),
            new Vector3(right - WallThickness, CeilingY, halfLength),
            new Vector2(left, -halfLength), new Vector2(right, -halfLength),
            new Vector2(left, halfLength), new Vector2(right, halfLength));

        // Long tiled band and narrow porcelain base strip make room boundaries legible.
        trim.AddBox(new Vector3(left + WallThickness, 3.29f, -halfLength),
            new Vector3(left + WallThickness + 0.08f, 3.38f, halfLength));
        trim.AddBox(new Vector3(right - WallThickness - 0.08f, 3.29f, -halfLength),
            new Vector3(right - WallThickness, 3.38f, halfLength));
        trim.AddBox(new Vector3(left + WallThickness, 0.02f, -halfLength),
            new Vector3(left + WallThickness + 0.09f, 0.18f, halfLength));
        trim.AddBox(new Vector3(right - WallThickness - 0.09f, 0.02f, -halfLength),
            new Vector3(right - WallThickness, 0.18f, halfLength));

        // A few exposed ceiling beams break up the flat roof without expensive geometry.
        for (int i = -1; i <= 1; i++)
        {
            float beamZ = i * 8f;
            ceiling.AddBox(new Vector3(left + 0.25f, CeilingY - 0.35f, beamZ - 0.16f),
                new Vector3(right - 0.25f, CeilingY - 0.12f, beamZ + 0.16f));
        }
    }

    void AddPortalWall(MeshBuilder lower, MeshBuilder upper, MeshBuilder trim,
        float z, float left, float right, float lowerHeight)
    {
        float[] openingCenters = { SidePortalCenterX, 0f };
        float[] openingHalfWidths = { SidePortalHalfWidth, PortalHalfWidth };
        float[] openingLefts = new float[openingCenters.Length];
        float[] openingRights = new float[openingCenters.Length];
        for (int i = 0; i < openingCenters.Length; i++)
        {
            openingLefts[i] = openingCenters[i] - openingHalfWidths[i];
            openingRights[i] = openingCenters[i] + openingHalfWidths[i];
        }

        float zMin = z - WallThickness * 0.5f;
        float zMax = z + WallThickness * 0.5f;
        float[] intervalLefts = { left, openingRights[0], openingRights[1] };
        float[] intervalRights = { openingLefts[0], openingLefts[1], right };
        for (int i = 0; i < intervalLefts.Length; i++)
        {
            lower.AddBox(new Vector3(intervalLefts[i], 0f, zMin),
                new Vector3(intervalRights[i], lowerHeight, zMax));
            upper.AddBox(new Vector3(intervalLefts[i], lowerHeight, zMin),
                new Vector3(intervalRights[i], CeilingY, zMax));
        }
        for (int i = 0; i < openingCenters.Length; i++)
            upper.AddBox(new Vector3(openingLefts[i], PortalHeight, zMin),
                new Vector3(openingRights[i], CeilingY, zMax));

        // Subtle double jamb and lintel frames for the side walkway and broad central doorway.
        float frameDepth = WallThickness + 0.04f;
        for (int i = 0; i < openingCenters.Length; i++)
        {
            float openingLeft = openingLefts[i];
            float openingRight = openingRights[i];
            trim.AddBox(new Vector3(openingLeft - 0.12f, 0f, z - frameDepth * 0.5f),
                new Vector3(openingLeft + 0.08f, PortalHeight, z + frameDepth * 0.5f));
            trim.AddBox(new Vector3(openingRight - 0.08f, 0f, z - frameDepth * 0.5f),
                new Vector3(openingRight + 0.12f, PortalHeight, z + frameDepth * 0.5f));
            trim.AddBox(new Vector3(openingLeft - 0.12f, PortalHeight - 0.10f, z - frameDepth * 0.5f),
                new Vector3(openingRight + 0.12f, PortalHeight + 0.12f, z + frameDepth * 0.5f));
        }
    }

    static void AddFloorRegion(MeshBuilder builder, float x0, float x1, float z0, float z1)
    {
        if (x1 <= x0 || z1 <= z0) return;
        builder.AddQuad(
            new Vector3(x0, 0f, z0), new Vector3(x0, 0f, z1),
            new Vector3(x1, 0f, z0), new Vector3(x1, 0f, z1),
            new Vector2(x0, z0), new Vector2(x0, z1),
            new Vector2(x1, z0), new Vector2(x1, z1));
    }

    void BuildRoomDetails(RoomKind kind, MeshBuilder trim, MeshBuilder metal, MeshBuilder lockers,
        MeshBuilder wood, MeshBuilder plants, MeshBuilder soil, MeshBuilder accents,
        float poolHalfWidth, float poolHalfLength)
    {
        if (kind == RoomKind.MainPool)
        {
            AddPoolCoping(trim, poolHalfWidth, poolHalfLength);
            AddPoolColumns(trim, metal);
            AddPoolLadder(metal, poolHalfWidth, poolHalfLength);
            AddPoolBenches(wood, metal, poolHalfWidth, poolHalfLength);
            AddLaneMarkers(accents, poolHalfWidth, poolHalfLength);
        }
        else if (kind == RoomKind.LockerRoom)
        {
            BuildLockerBanks(lockers, metal, wood);
            AddSimpleColumns(trim);
        }
        else if (kind == RoomKind.ShowerRoom)
        {
            BuildShowers(trim, metal, accents);
            BuildWashBasins(trim, metal);
        }
        else
        {
            AddPoolCoping(trim, poolHalfWidth, poolHalfLength);
            AddPalmAtrium(plants, soil, wood, trim, metal, accents, poolHalfWidth, poolHalfLength);
        }
    }

    void AddPoolCoping(MeshBuilder trim, float halfWidth, float halfLength)
    {
        const float outer = 0.40f;
        const float inner = 0.06f;
        const float bottom = -0.02f;
        const float top = 0.31f;
        trim.AddBox(new Vector3(-halfWidth - outer, bottom, -halfLength - outer),
            new Vector3(-halfWidth + inner, top, halfLength + outer));
        trim.AddBox(new Vector3(halfWidth - inner, bottom, -halfLength - outer),
            new Vector3(halfWidth + outer, top, halfLength + outer));
        trim.AddBox(new Vector3(-halfWidth + inner, bottom, -halfLength - outer),
            new Vector3(halfWidth - inner, top, -halfLength + inner));
        trim.AddBox(new Vector3(-halfWidth + inner, bottom, halfLength - inner),
            new Vector3(halfWidth - inner, top, halfLength + outer));
    }

    void AddPoolColumns(MeshBuilder columns, MeshBuilder metal)
    {
        float[] xs = { -9.0f, 9.0f };
        float[] zs = { -8.5f, 0f, 8.5f };
        for (int x = 0; x < xs.Length; x++)
        {
            for (int z = 0; z < zs.Length; z++)
            {
                columns.AddCylinder(xs[x], zs[z], 0.48f, 0f, CeilingY - 0.18f, 12);
                metal.AddBox(new Vector3(xs[x] - 0.53f, 0.15f, zs[z] - 0.53f),
                    new Vector3(xs[x] + 0.53f, 0.31f, zs[z] + 0.53f));
                metal.AddBox(new Vector3(xs[x] - 0.53f, CeilingY - 0.42f, zs[z] - 0.53f),
                    new Vector3(xs[x] + 0.53f, CeilingY - 0.25f, zs[z] + 0.53f));
            }
        }
    }

    void AddPoolLadder(MeshBuilder metal, float halfWidth, float halfLength)
    {
        float x = halfWidth - 0.9f;
        float z = halfLength - 0.68f;
        for (int side = -1; side <= 1; side += 2)
        {
            float railX = x + side * 0.42f;
            metal.AddBox(new Vector3(railX - 0.055f, -0.10f, z - 0.10f),
                new Vector3(railX + 0.055f, 1.12f, z + 0.02f));
            metal.AddBox(new Vector3(railX - 0.055f, 0.87f, z - 0.17f),
                new Vector3(railX + 0.055f, 1.12f, z + 0.18f));
        }
        for (int rung = 0; rung < 4; rung++)
        {
            float y = 0.05f + rung * 0.24f;
            metal.AddBox(new Vector3(x - 0.45f, y, z - 0.10f),
                new Vector3(x + 0.45f, y + 0.07f, z + 0.02f));
        }
    }

    void AddPoolBenches(MeshBuilder wood, MeshBuilder metal, float poolHalfWidth, float poolHalfLength)
    {
        for (int side = -1; side <= 1; side += 2)
        {
            float x = side * (poolHalfWidth + 3.8f);
            float z = -poolHalfLength + 2.2f;
            wood.AddBox(new Vector3(x - 0.40f, 0.54f, z - 1.85f),
                new Vector3(x + 0.40f, 0.70f, z + 1.85f));
            for (int leg = -1; leg <= 1; leg += 2)
                metal.AddBox(new Vector3(x - 0.30f, 0.08f, z + leg * 1.42f - 0.08f),
                    new Vector3(x + 0.30f, 0.55f, z + leg * 1.42f + 0.08f));
        }
    }

    void AddLaneMarkers(MeshBuilder accents, float halfWidth, float halfLength)
    {
        // Thin floating lane ropes echo a public swimming pool without cluttering the surface.
        float[] lanes = { -3.7f, -1.25f, 1.25f, 3.7f };
        for (int lane = 0; lane < lanes.Length; lane++)
        {
            float x = lanes[lane];
            accents.AddBox(new Vector3(x - 0.035f, WaterY + 0.045f, -halfLength + 0.65f),
                new Vector3(x + 0.035f, WaterY + 0.095f, halfLength - 0.65f));
        }
        // A few pool-end markers rest above water as subtle visual guides.
        accents.AddBox(new Vector3(-halfWidth + 0.45f, WaterY + 0.035f, halfLength - 0.70f),
            new Vector3(halfWidth - 0.45f, WaterY + 0.085f, halfLength - 0.48f));
    }

    void BuildLockerBanks(MeshBuilder lockers, MeshBuilder metal, MeshBuilder wood)
    {
        const float firstZ = -8.0f;
        const float spacing = 1.15f;
        const int count = 15;
        for (int side = -1; side <= 1; side += 2)
        {
            for (int i = 0; i < count; i++)
            {
                float z = firstZ + i * spacing;
                float bodyMinX = side < 0 ? -11.42f : 10.72f;
                float bodyMaxX = side < 0 ? -10.72f : 11.42f;
                lockers.AddBox(new Vector3(bodyMinX, 0.10f, z - 0.47f),
                    new Vector3(bodyMaxX, 2.02f, z + 0.47f));

                float faceX = side < 0 ? bodyMaxX + 0.012f : bodyMinX - 0.012f;
                float panelMin = side < 0 ? faceX : faceX - 0.035f;
                float panelMax = side < 0 ? faceX + 0.035f : faceX;
                metal.AddBox(new Vector3(panelMin, 0.15f, z - 0.40f),
                    new Vector3(panelMax, 1.98f, z + 0.40f));

                // Dark vents and a short vertical handle make each locker legible at phone resolution.
                float ventMinX = side < 0 ? panelMax + 0.005f : panelMin - 0.012f;
                float ventMaxX = side < 0 ? panelMax + 0.017f : panelMin - 0.005f;
                for (int vent = 0; vent < 3; vent++)
                {
                    float ventY = 1.64f + vent * 0.075f;
                    metal.AddBox(new Vector3(ventMinX, ventY, z - 0.20f),
                        new Vector3(ventMaxX, ventY + 0.024f, z + 0.20f));
                }
                float handleX = side < 0 ? panelMax + 0.035f : panelMin - 0.035f;
                metal.AddBox(new Vector3(handleX - 0.03f, 0.78f, z + 0.22f),
                    new Vector3(handleX + 0.03f, 1.06f, z + 0.28f));
            }

            float benchX = side * 8.95f;
            wood.AddBox(new Vector3(benchX - 0.40f, 0.48f, -2.25f),
                new Vector3(benchX + 0.40f, 0.66f, 2.25f));
            for (int legZ = -1; legZ <= 1; legZ += 2)
                metal.AddBox(new Vector3(benchX - 0.28f, 0.06f, legZ * 1.72f - 0.09f),
                    new Vector3(benchX + 0.28f, 0.49f, legZ * 1.72f + 0.09f));
        }
    }

    void BuildShowers(MeshBuilder partitions, MeshBuilder metal, MeshBuilder accents)
    {
        // Four tiled cubicles occupy the right side; the middle stays open for exploration.
        const float backX = 10.9f;
        for (int stall = 0; stall < 4; stall++)
        {
            float z = -7.0f + stall * 4.25f;
            partitions.AddBox(new Vector3(6.4f, 0f, z - 1.8f),
                new Vector3(backX, 2.18f, z - 1.68f));
            partitions.AddBox(new Vector3(6.4f, 0f, z + 1.68f),
                new Vector3(backX, 2.18f, z + 1.8f));
            partitions.AddBox(new Vector3(backX - 0.14f, 0f, z - 1.8f),
                new Vector3(backX, 2.18f, z + 1.8f));

            // Shower riser, valve, and a compact spray head.
            metal.AddBox(new Vector3(backX - 0.48f, 1.50f, z - 0.045f),
                new Vector3(backX - 0.40f, 2.20f, z + 0.045f));
            metal.AddBox(new Vector3(backX - 0.68f, 2.12f, z - 0.18f),
                new Vector3(backX - 0.22f, 2.20f, z + 0.18f));
            accents.AddBox(new Vector3(backX - 0.58f, 0.92f, z - 0.11f),
                new Vector3(backX - 0.33f, 1.04f, z + 0.11f));
            // Floor drain.
            metal.AddBox(new Vector3(7.1f, 0.008f, z - 0.18f),
                new Vector3(7.55f, 0.022f, z + 0.18f));
        }
    }

    void BuildWashBasins(MeshBuilder porcelain, MeshBuilder metal)
    {
        // A continuous sink counter and mirrors on the opposite wall.
        porcelain.AddBox(new Vector3(-10.75f, 0.82f, -7.6f),
            new Vector3(-9.05f, 1.02f, 7.6f));
        metal.AddBox(new Vector3(-10.50f, 1.88f, -7.4f),
            new Vector3(-10.38f, 3.00f, 7.4f));
        for (int i = 0; i < 5; i++)
        {
            float z = -6.0f + i * 3.0f;
            porcelain.AddCylinder(-9.78f, z, 0.48f, 0.99f, 1.20f, 12);
            metal.AddBox(new Vector3(-9.85f, 1.17f, z - 0.045f),
                new Vector3(-9.78f, 1.48f, z + 0.045f));
        }
    }

    void AddSimpleColumns(MeshBuilder columns)
    {
        for (int z = -8; z <= 8; z += 8)
        {
            columns.AddCylinder(-8.7f, z, 0.38f, 0f, CeilingY - 0.15f, 10);
            columns.AddCylinder(8.7f, z, 0.38f, 0f, CeilingY - 0.15f, 10);
        }
    }

    void AddPalmAtrium(MeshBuilder plants, MeshBuilder planters, MeshBuilder wood,
        MeshBuilder columns, MeshBuilder metal, MeshBuilder accents, float poolHalfWidth, float poolHalfLength)
    {
        AddSimpleColumns(columns);

        Vector3[] positions =
        {
            new Vector3(-10.0f, 0f, -9.0f), new Vector3(10.0f, 0f, -9.0f),
            new Vector3(-10.0f, 0f, 9.0f), new Vector3(10.0f, 0f, 9.0f)
        };
        for (int i = 0; i < positions.Length; i++)
        {
            Vector3 p = positions[i];
            planters.AddCylinder(p.x, p.z, 1.05f, 0.0f, 0.56f, 16);
            planters.AddCylinder(p.x, p.z, 0.86f, 0.54f, 0.67f, 16);
            AddPalm(wood, plants, p.x, p.z, 5.7f, i * 0.71f);
        }

        for (int side = -1; side <= 1; side += 2)
        {
            float x = side * 6.5f;
            wood.AddBox(new Vector3(x - 0.36f, 0.48f, -2.8f),
                new Vector3(x + 0.36f, 0.66f, 2.8f));
            metal.AddBox(new Vector3(x - 0.26f, 0.05f, -2.3f),
                new Vector3(x + 0.26f, 0.50f, -2.12f));
            metal.AddBox(new Vector3(x - 0.26f, 0.05f, 2.12f),
                new Vector3(x + 0.26f, 0.50f, 2.3f));
        }

        // Small glowing blue strips near the atrium basin.
        accents.AddBox(new Vector3(-poolHalfWidth - 0.02f, 0.34f, -poolHalfLength - 0.04f),
            new Vector3(-poolHalfWidth + 0.03f, 0.40f, poolHalfLength + 0.04f));
        accents.AddBox(new Vector3(poolHalfWidth - 0.03f, 0.34f, -poolHalfLength - 0.04f),
            new Vector3(poolHalfWidth + 0.02f, 0.40f, poolHalfLength + 0.04f));
    }

    static void AddPalm(MeshBuilder trunk, MeshBuilder leaves, float x, float z, float topY, float phase)
    {
        trunk.AddTaperedCylinder(x, z, 0.28f, 0.17f, 0.34f, topY, 9);
        float crownY = topY;
        for (int i = 0; i < 8; i++)
        {
            float angle = phase + i * Mathf.PI * 2f / 8f;
            Vector3 direction = new Vector3(Mathf.Cos(angle), 0f, Mathf.Sin(angle));
            float length = 2.45f + 0.28f * Mathf.Sin(i * 1.7f + phase);
            Vector3 root = new Vector3(x + direction.x * 0.16f, crownY, z + direction.z * 0.16f);
            Vector3 tip = new Vector3(x + direction.x * length, crownY - 0.88f, z + direction.z * length);
            Vector3 side = new Vector3(-direction.z, 0f, direction.x) * 0.24f;
            Vector3 mid = Vector3.Lerp(root, tip, 0.48f) + Vector3.down * 0.18f;
            leaves.AddDoubleQuad(root, mid + side, tip, mid - side);
        }
    }

    void BuildCeilingDetails(MeshBuilder ceiling, MeshBuilder diffusers)
    {
        for (int i = -1; i <= 1; i++)
        {
            float z = i * 7.7f;
            diffusers.AddBox(new Vector3(-1.12f, CeilingY - 0.20f, z - 0.90f),
                new Vector3(1.12f, CeilingY - 0.10f, z + 0.90f));
            ceiling.AddBox(new Vector3(-RoomHalfWidth + 0.20f, CeilingY - 0.46f, z - 0.075f),
                new Vector3(RoomHalfWidth - 0.20f, CeilingY - 0.28f, z + 0.075f));
        }
        for (int side = -1; side <= 1; side += 2)
        {
            ceiling.AddBox(new Vector3(side * 5.2f - 0.08f, CeilingY - 0.30f, -SegmentLength * 0.5f),
                new Vector3(side * 5.2f + 0.08f, CeilingY - 0.14f, SegmentLength * 0.5f));
        }
    }

    Mesh BuildWaterSurface(float halfWidth, float halfLength)
    {
        const int xSteps = 24;
        const int zSteps = 24;
        var vertices = new List<Vector3>((xSteps + 1) * (zSteps + 1));
        var uvs = new List<Vector2>(vertices.Capacity);
        var normals = new List<Vector3>(vertices.Capacity);
        var triangles = new List<int>(xSteps * zSteps * 6);

        for (int z = 0; z <= zSteps; z++)
        {
            float pz = Mathf.Lerp(-halfLength, halfLength, (float)z / zSteps);
            for (int x = 0; x <= xSteps; x++)
            {
                float px = Mathf.Lerp(-halfWidth, halfWidth, (float)x / xSteps);
                vertices.Add(new Vector3(px, WaterY, pz));
                uvs.Add(new Vector2(px, pz));
                normals.Add(Vector3.up);
            }
        }

        int stride = xSteps + 1;
        for (int z = 0; z < zSteps; z++)
        {
            for (int x = 0; x < xSteps; x++)
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
        mesh.name = "Calm tiled pool surface";
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

    Mesh BuildWaterBed(float halfWidth, float halfLength)
    {
        const int xSteps = 28;
        const int zSteps = 24;
        var vertices = new List<Vector3>((xSteps + 1) * (zSteps + 1));
        var triangles = new List<int>(xSteps * zSteps * 6);
        for (int z = 0; z <= zSteps; z++)
        {
            float pz = Mathf.Lerp(-halfLength, halfLength, (float)z / zSteps);
            for (int x = 0; x <= xSteps; x++)
            {
                float px = Mathf.Lerp(-halfWidth, halfWidth, (float)x / xSteps);
                float depth = 1f - Mathf.Clamp01(Mathf.Abs(px) / Mathf.Max(halfWidth, 0.1f));
                depth = Mathf.SmoothStep(0f, 1f, depth);
                float y = WaterY - Mathf.Lerp(ShallowDepth, DeepDepth, depth);
                vertices.Add(new Vector3(px, y, pz));
            }
        }

        int stride = xSteps + 1;
        for (int z = 0; z < zSteps; z++)
        {
            for (int x = 0; x < xSteps; x++)
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
        mesh.name = "Visible sloped pool tiles";
        mesh.SetVertices(vertices);
        mesh.SetTriangles(triangles, 0);
        mesh.RecalculateNormals();
        mesh.RecalculateBounds();
        return mesh;
    }

    void AddRoomColliders(Transform segment, RoomKind kind, float poolHalfWidth, float poolHalfLength)
    {
        const float halfLength = SegmentLength * 0.5f;
        bool hasPool = kind == RoomKind.MainPool || kind == RoomKind.PalmAtrium;
        // Outer walls and portal lintels.
        AddCollider(segment, new Vector3(-RoomHalfWidth + WallThickness * 0.5f, CeilingY * 0.5f, 0f),
            new Vector3(WallThickness, CeilingY, SegmentLength));
        AddCollider(segment, new Vector3(RoomHalfWidth - WallThickness * 0.5f, CeilingY * 0.5f, 0f),
            new Vector3(WallThickness, CeilingY, SegmentLength));
        AddPortalColliders(segment, -halfLength);
        AddPortalColliders(segment, halfLength);

        if (hasPool)
        {
            float outsideX = poolHalfWidth + 0.40f;
            float outsideZ = poolHalfLength + 0.40f;
            float floorLeft = -RoomHalfWidth + WallThickness;
            float floorRight = RoomHalfWidth - WallThickness;
            float sideFloorWidth = -outsideX - floorLeft;
            AddFloorCollider(segment, (floorLeft - outsideX) * 0.5f, sideFloorWidth,
                -halfLength, SegmentLength);
            AddFloorCollider(segment, (outsideX + floorRight) * 0.5f, floorRight - outsideX,
                -halfLength, SegmentLength);
            AddFloorCollider(segment, 0f, outsideX * 2f, -halfLength, halfLength - outsideZ);
            AddFloorCollider(segment, 0f, outsideX * 2f, outsideZ, halfLength - outsideZ);

            // Low tile coping blocks the player at the pool lip while keeping the water open to view.
            AddCollider(segment, new Vector3(-poolHalfWidth - 0.20f, 0.13f, 0f),
                new Vector3(0.40f, 0.38f, poolHalfLength * 2f + 0.80f));
            AddCollider(segment, new Vector3(poolHalfWidth + 0.20f, 0.13f, 0f),
                new Vector3(0.40f, 0.38f, poolHalfLength * 2f + 0.80f));
            AddCollider(segment, new Vector3(0f, 0.13f, -poolHalfLength - 0.20f),
                new Vector3(poolHalfWidth * 2f, 0.38f, 0.40f));
            AddCollider(segment, new Vector3(0f, 0.13f, poolHalfLength + 0.20f),
                new Vector3(poolHalfWidth * 2f, 0.38f, 0.40f));
        }
        else
        {
            AddFloorCollider(segment, 0f, RoomHalfWidth * 2f - WallThickness * 2f, -halfLength, SegmentLength);
        }

        if (kind == RoomKind.MainPool)
        {
            float[] xs = { -9.0f, 9.0f };
            float[] zs = { -8.5f, 0f, 8.5f };
            for (int x = 0; x < xs.Length; x++)
                for (int z = 0; z < zs.Length; z++)
                    AddCollider(segment, new Vector3(xs[x], (CeilingY - 0.18f) * 0.5f, zs[z]),
                        new Vector3(0.96f, CeilingY - 0.18f, 0.96f));
            for (int side = -1; side <= 1; side += 2)
                AddCollider(segment, new Vector3(side * (poolHalfWidth + 3.8f), 0.62f,
                    -poolHalfLength + 2.2f), new Vector3(0.9f, 0.72f, 3.7f));
        }
        else if (kind == RoomKind.LockerRoom)
        {
            AddCollider(segment, new Vector3(-11.07f, 1.06f, 0f), new Vector3(0.72f, 1.96f, 17.2f));
            AddCollider(segment, new Vector3(11.07f, 1.06f, 0f), new Vector3(0.72f, 1.96f, 17.2f));
            for (int side = -1; side <= 1; side += 2)
                AddCollider(segment, new Vector3(side * 8.95f, 0.57f, 0f), new Vector3(0.85f, 0.72f, 4.6f));
        }
        else if (kind == RoomKind.ShowerRoom)
        {
            for (int stall = 0; stall < 4; stall++)
            {
                float z = -7.0f + stall * 4.25f;
                AddCollider(segment, new Vector3(8.65f, 1.09f, z - 1.74f), new Vector3(4.5f, 2.18f, 0.12f));
                AddCollider(segment, new Vector3(8.65f, 1.09f, z + 1.74f), new Vector3(4.5f, 2.18f, 0.12f));
                AddCollider(segment, new Vector3(10.83f, 1.09f, z), new Vector3(0.14f, 2.18f, 3.6f));
            }
            AddCollider(segment, new Vector3(-9.90f, 0.92f, 0f), new Vector3(1.8f, 0.25f, 15.2f));
        }
        else
        {
            float[] xs = { -8.7f, 8.7f };
            float[] zs = { -8f, 0f, 8f };
            for (int x = 0; x < xs.Length; x++)
                for (int z = 0; z < zs.Length; z++)
                    AddCollider(segment, new Vector3(xs[x], (CeilingY - 0.15f) * 0.5f, zs[z]),
                        new Vector3(0.76f, CeilingY - 0.15f, 0.76f));
            float[] palmX = { -10f, 10f };
            float[] palmZ = { -9f, 9f };
            for (int x = 0; x < palmX.Length; x++)
                for (int z = 0; z < palmZ.Length; z++)
                    AddCollider(segment, new Vector3(palmX[x], 0.34f, palmZ[z]), new Vector3(2.1f, 0.68f, 2.1f));
            for (int side = -1; side <= 1; side += 2)
                AddCollider(segment, new Vector3(side * 6.5f, 0.57f, 0f), new Vector3(0.8f, 0.72f, 5.7f));
        }
    }

    void AddPortalColliders(Transform segment, float z)
    {
        float thickness = WallThickness;
        float sidePortalLeft = SidePortalCenterX - SidePortalHalfWidth;
        float sidePortalRight = SidePortalCenterX + SidePortalHalfWidth;
        float centerPortalLeft = -PortalHalfWidth;
        float centerPortalRight = PortalHalfWidth;
        float[] solidLefts = { -RoomHalfWidth, sidePortalRight, centerPortalRight };
        float[] solidRights = { sidePortalLeft, centerPortalLeft, RoomHalfWidth };
        for (int i = 0; i < solidLefts.Length; i++)
        {
            float width = solidRights[i] - solidLefts[i];
            AddCollider(segment, new Vector3((solidLefts[i] + solidRights[i]) * 0.5f,
                CeilingY * 0.5f, z), new Vector3(width, CeilingY, thickness));
        }
        AddCollider(segment, new Vector3(SidePortalCenterX,
            PortalHeight + (CeilingY - PortalHeight) * 0.5f, z),
            new Vector3(SidePortalHalfWidth * 2f, CeilingY - PortalHeight, thickness));
        AddCollider(segment, new Vector3(0f,
            PortalHeight + (CeilingY - PortalHeight) * 0.5f, z),
            new Vector3(PortalHalfWidth * 2f, CeilingY - PortalHeight, thickness));
    }

    void AddFloorCollider(Transform segment, float centerX, float width, float zStart, float length)
    {
        if (width <= 0f || length <= 0f) return;
        AddCollider(segment, new Vector3(centerX, -0.12f, (zStart + length * 0.5f)),
            new Vector3(width, 0.24f, length));
    }

    static void AddCollider(Transform parent, Vector3 center, Vector3 size)
    {
        var colliderObject = new GameObject("Room collision");
        colliderObject.transform.SetParent(parent, false);
        colliderObject.transform.localPosition = center;
        var box = colliderObject.AddComponent<BoxCollider>();
        box.size = size;
    }

    void AddCeilingLights(Transform segment, RoomKind kind)
    {
        float intensity = kind == RoomKind.ShowerRoom ? 0.58f : 0.78f;
        for (int side = -1; side <= 1; side += 2)
        {
            var lightObject = new GameObject("Soft aquatic ceiling bounce");
            lightObject.transform.SetParent(segment, false);
            lightObject.transform.localPosition = new Vector3(side * 4.7f, CeilingY - 0.75f, 0f);
            var light = lightObject.AddComponent<Light>();
            light.type = LightType.Point;
            light.color = kind == RoomKind.PalmAtrium
                ? new Color(0.70f, 0.86f, 0.94f)
                : new Color(0.63f, 0.79f, 0.88f);
            light.intensity = intensity;
            light.range = 13f;
            light.shadows = LightShadows.None;
        }
    }

    GameObject AddMeshObject(Transform parent, string name, Mesh mesh, Material material)
    {
        if (parent == null || mesh == null || material == null) return null;
        var go = new GameObject(name);
        go.transform.SetParent(parent, false);
        var filter = go.AddComponent<MeshFilter>();
        filter.sharedMesh = mesh;
        var renderer = go.AddComponent<MeshRenderer>();
        renderer.sharedMaterial = material;
        renderer.shadowCastingMode = ShadowCastingMode.Off;
        renderer.receiveShadows = true;
        return go;
    }

    static void SetRendererFloat(GameObject gameObject, string property, float value)
    {
        if (gameObject == null) return;
        var renderer = gameObject.GetComponent<MeshRenderer>();
        if (renderer == null || !renderer.sharedMaterial.HasProperty(property)) return;
        var block = new MaterialPropertyBlock();
        renderer.GetPropertyBlock(block);
        block.SetFloat(property, value);
        renderer.SetPropertyBlock(block);
    }

    Mesh Track(Mesh mesh)
    {
        if (mesh != null) ownedMeshes.Add(mesh);
        return mesh;
    }

    void LateUpdate()
    {
        if (player == null || segments.Count == 0) return;
        while (player.transform.position.z > SegmentLength * 0.5f) RecycleForward();
        while (player.transform.position.z < -SegmentLength * 0.5f) RecycleBackward();
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
            if (z < nearest) { nearest = z; oldest = segments[i]; }
            if (z > farthest) farthest = z;
        }
        Vector3 recycled = oldest.position;
        recycled.z = nearest - SegmentLength;
        oldest.position = recycled;
        WrapCount++;
    }

    void OnDestroy()
    {
        for (int i = 0; i < ownedMeshes.Count; i++) DestroyRuntimeObject(ownedMeshes[i]);
        DestroyRuntimeObject(wallTileMaterial);
        DestroyRuntimeObject(floorTileMaterial);
        DestroyRuntimeObject(poolTileMaterial);
        DestroyRuntimeObject(ceilingTileMaterial);
        DestroyRuntimeObject(upperWallMaterial);
        DestroyRuntimeObject(trimMaterial);
        DestroyRuntimeObject(metalMaterial);
        DestroyRuntimeObject(lockerMaterial);
        DestroyRuntimeObject(woodMaterial);
        DestroyRuntimeObject(plantMaterial);
        DestroyRuntimeObject(soilMaterial);
        DestroyRuntimeObject(accentMaterial);
        DestroyRuntimeObject(lightMaterial);
        DestroyRuntimeObject(waterMaterial);
        DestroyRuntimeObject(waterBedMaterial);
    }

    static void DestroyRuntimeObject(Object value)
    {
        if (value == null) return;
        if (Application.isPlaying) Object.Destroy(value);
        else Object.DestroyImmediate(value);
    }

    static int PositiveModulo(int value, int divisor)
    {
        int result = value % divisor;
        return result < 0 ? result + divisor : result;
    }

    sealed class MeshBuilder
    {
        readonly string meshName;
        readonly List<Vector3> vertices = new List<Vector3>();
        readonly List<Vector2> uvs = new List<Vector2>();
        readonly List<int> triangles = new List<int>();

        public MeshBuilder(string name) { meshName = name; }
        public bool HasGeometry { get { return vertices.Count > 0; } }

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
            if (max.x <= min.x || max.y <= min.y || max.z <= min.z) return;
            // Unit-space UVs are measured in metres, so the procedural tile shader keeps a stable scale.
            AddQuad(new Vector3(min.x, max.y, min.z), new Vector3(min.x, max.y, max.z),
                new Vector3(max.x, max.y, min.z), new Vector3(max.x, max.y, max.z),
                new Vector2(min.x, min.z), new Vector2(min.x, max.z),
                new Vector2(max.x, min.z), new Vector2(max.x, max.z));
            AddQuad(new Vector3(min.x, min.y, min.z), new Vector3(max.x, min.y, min.z),
                new Vector3(min.x, min.y, max.z), new Vector3(max.x, min.y, max.z),
                new Vector2(min.x, min.z), new Vector2(max.x, min.z),
                new Vector2(min.x, max.z), new Vector2(max.x, max.z));
            AddQuad(new Vector3(min.x, min.y, min.z), new Vector3(min.x, min.y, max.z),
                new Vector3(min.x, max.y, min.z), new Vector3(min.x, max.y, max.z),
                new Vector2(min.z, min.y), new Vector2(max.z, min.y),
                new Vector2(min.z, max.y), new Vector2(max.z, max.y));
            AddQuad(new Vector3(max.x, min.y, min.z), new Vector3(max.x, max.y, min.z),
                new Vector3(max.x, min.y, max.z), new Vector3(max.x, max.y, max.z),
                new Vector2(min.z, min.y), new Vector2(min.z, max.y),
                new Vector2(max.z, min.y), new Vector2(max.z, max.y));
            AddQuad(new Vector3(min.x, min.y, min.z), new Vector3(min.x, max.y, min.z),
                new Vector3(max.x, min.y, min.z), new Vector3(max.x, max.y, min.z),
                new Vector2(min.x, min.y), new Vector2(min.x, max.y),
                new Vector2(max.x, min.y), new Vector2(max.x, max.y));
            AddQuad(new Vector3(min.x, min.y, max.z), new Vector3(max.x, min.y, max.z),
                new Vector3(min.x, max.y, max.z), new Vector3(max.x, max.y, max.z),
                new Vector2(min.x, min.y), new Vector2(max.x, min.y),
                new Vector2(min.x, max.y), new Vector2(max.x, max.y));
        }

        public void AddCylinder(float x, float z, float radius, float bottomY, float topY, int sides)
        {
            AddTaperedCylinder(x, z, radius, radius, bottomY, topY, sides);
        }

        public void AddTaperedCylinder(float x, float z, float bottomRadius, float topRadius,
            float bottomY, float topY, int sides)
        {
            if (sides < 3 || topY <= bottomY) return;
            Vector3 bottomCenter = new Vector3(x, bottomY, z);
            Vector3 topCenter = new Vector3(x, topY, z);
            for (int i = 0; i < sides; i++)
            {
                float a0 = i * Mathf.PI * 2f / sides;
                float a1 = (i + 1) * Mathf.PI * 2f / sides;
                Vector3 b0 = new Vector3(x + Mathf.Cos(a0) * bottomRadius, bottomY, z + Mathf.Sin(a0) * bottomRadius);
                Vector3 b1 = new Vector3(x + Mathf.Cos(a1) * bottomRadius, bottomY, z + Mathf.Sin(a1) * bottomRadius);
                Vector3 t0 = new Vector3(x + Mathf.Cos(a0) * topRadius, topY, z + Mathf.Sin(a0) * topRadius);
                Vector3 t1 = new Vector3(x + Mathf.Cos(a1) * topRadius, topY, z + Mathf.Sin(a1) * topRadius);
                AddTriangle(b0, t0, b1);
                AddTriangle(b1, t0, t1);
                AddTriangle(topCenter, t1, t0);
                AddTriangle(bottomCenter, b0, b1);
            }
        }

        public void AddDoubleQuad(Vector3 a, Vector3 b, Vector3 c, Vector3 d)
        {
            Vector2 uv0 = Vector2.zero;
            Vector2 uv1 = Vector2.up;
            Vector2 uv2 = Vector2.right;
            Vector2 uv3 = Vector2.one;
            AddQuad(a, b, c, d, uv0, uv1, uv2, uv3);
            AddQuad(c, d, a, b, uv2, uv3, uv0, uv1);
        }

        void AddTriangle(Vector3 a, Vector3 b, Vector3 c)
        {
            int start = vertices.Count;
            vertices.Add(a); vertices.Add(b); vertices.Add(c);
            uvs.Add(new Vector2(a.x, a.z));
            uvs.Add(new Vector2(b.x, b.z));
            uvs.Add(new Vector2(c.x, c.z));
            triangles.Add(start); triangles.Add(start + 1); triangles.Add(start + 2);
        }

        public Mesh Build(string name = null)
        {
            if (vertices.Count == 0) return null;
            var mesh = new Mesh();
            mesh.name = string.IsNullOrEmpty(name) ? meshName : name;
            if (vertices.Count > 65535) mesh.indexFormat = IndexFormat.UInt32;
            mesh.SetVertices(vertices);
            mesh.SetUVs(0, uvs);
            mesh.SetTriangles(triangles, 0);
            mesh.RecalculateNormals();
            mesh.RecalculateBounds();
            return mesh;
        }
    }
}
