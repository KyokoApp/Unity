using System.Collections.Generic;
using UnityEngine;

/// <summary>
/// Lapangan rumput berlapis (port redesign grass_field.gd Godot): per tile 12 m
/// dibaked jadi SATU mesh (helai = 4 segitiga tipis + quad penutup tanah),
/// 3x3 tile dekat rapat + cincin luar lebih jarang, maksimal 1 tile dibangun
/// per frame agar tidak ada spike CPU di mobile. Deterministik per tile.
/// </summary>
public class GrassField : MonoBehaviour
{
    public Transform player;

    const float TileSize = 12f;
    const int Radius = 2;
    const int NearGrid = 32;    // Godot 40 — diturunkan sedikit untuk mobile
    const int FarGrid = 16;
    const float BladeWidth = 0.085f;
    const float BladeHeight = 0.55f;
    const float CoverHalf = 0.25f;

    readonly Dictionary<long, GameObject> tiles = new Dictionary<long, GameObject>();
    readonly Queue<long> pending = new Queue<long>();
    readonly Dictionary<long, int> tileGrids = new Dictionary<long, int>();
    Vector2i center = new Vector2i(99999, 99999);
    Material mat;

    struct Vector2i
    {
        public int x, z;
        public Vector2i(int x, int z) { this.x = x; this.z = z; }
    }

    void Awake()
    {
        var shader = Resources.Load<Shader>("Shaders/GrassBlade");
        if (shader == null) shader = Shader.Find("UAL2/GrassBlade");
        mat = new Material(shader);
    }

    void Update()
    {
        if (player == null || IslandTerrain.I == null) return;
        mat.SetVector("_PlayerPos", new Vector4(player.position.x, player.position.y - 0.9f, player.position.z, 0f));

        var c = new Vector2i(Mathf.FloorToInt(player.position.x / TileSize),
                             Mathf.FloorToInt(player.position.z / TileSize));
        if (c.x != center.x || c.z != center.z) Recenter(c);

        if (pending.Count > 0) BuildTile(DequeuePriority());
    }

    long DequeuePriority()
    {
        // prioritas: tile terdekat dulu
        long best = 0; float bestD = float.MaxValue;
        var arr = pending.ToArray();
        for (int i = 0; i < arr.Length; i++)
        {
            int x = (int)(arr[i] >> 32), z = (int)(arr[i] & 0xFFFFFFFF);
            float d = (x - center.x) * (x - center.x) + (z - center.z) * (z - center.z);
            if (d < bestD) { bestD = d; best = arr[i]; }
        }
        var list = new List<long>(pending);
        list.Remove(best);
        pending.Clear();
        for (int i = 0; i < list.Count; i++) pending.Enqueue(list[i]);
        return best;
    }

    static long Key(int x, int z) { return ((long)x << 32) | (uint)z; }

    void Recenter(Vector2i c)
    {
        center = c;
        pending.Clear();
        var dead = new List<long>();
        foreach (var kv in tiles)
        {
            int x = (int)(kv.Key >> 32), z = (int)(kv.Key & 0xFFFFFFFF);
            if (Mathf.Abs(x - c.x) > Radius || Mathf.Abs(z - c.z) > Radius) dead.Add(kv.Key);
        }
        for (int i = 0; i < dead.Count; i++)
        {
            if (tiles.TryGetValue(dead[i], out var go)) Destroy(go);
            tiles.Remove(dead[i]);
            tileGrids.Remove(dead[i]);
        }
        for (int z = c.z - Radius; z <= c.z + Radius; z++)
            for (int x = c.x - Radius; x <= c.x + Radius; x++)
            {
                long k = Key(x, z);
                if (!tiles.ContainsKey(k) || tileGrids[k] != GridFor(x, z, c)) pending.Enqueue(k);
            }
    }

    int GridFor(int x, int z, Vector2i c)
    {
        return Mathf.Max(Mathf.Abs(x - c.x), Mathf.Abs(z - c.z)) <= 1 ? NearGrid : FarGrid;
    }

    bool CanGrow(float x, float z)
    {
        var it = IslandTerrain.I;
        if (IslandTerrain.ArenaDistance(x, z) < 2f || Mathf.Abs(x) > 495f || Mathf.Abs(z) > 495f) return false;
        // penipisan deterministik via tuning live (grassDensity)
        uint hash = (uint)(Mathf.RoundToInt(x * 4f) * 73856093 ^ Mathf.RoundToInt(z * 4f) * 19349663);
        if ((hash % 1000) / 1000f > WorldTuning.GrassDensity) return false;
        float height = it.SurfaceHeight(x, z);
        if (height < 5.4f || IslandTerrain.WaterCovers(x, z, 1.5f)) return false;
        if (Mathf.Abs(z) < 340f && IslandTerrain.RoadDistance(x, z) < 15f) return false;
        float gx = it.SurfaceHeight(x + 1f, z) - it.SurfaceHeight(x - 1f, z);
        float gz = it.SurfaceHeight(x, z + 1f) - it.SurfaceHeight(x, z - 1f);
        if (new Vector2(gx, gz).magnitude * 0.5f > 0.45f) return false;
        for (int i = 0; i < it.RockClearances.Count; i++)
        {
            var r = it.RockClearances[i];
            if (new Vector2(x - r.x, z - r.z).magnitude < r.y + 0.7f) return false;
        }
        return true;
    }

    void BuildTile(long key)
    {
        int kx = (int)(key >> 32), kz = (int)(key & 0xFFFFFFFF);
        int grid = GridFor(kx, kz, center);
        var rng = new System.Random(unchecked(kx * 73856093 ^ kz * 19349663) + 8421);

        var verts = new List<Vector3>();
        var norms = new List<Vector3>();
        var cols = new List<Color>();
        var tris = new List<int>();
        var origin = new Vector3(kx * TileSize, 0f, kz * TileSize);

        float cell = TileSize / NearGrid;   // far = subset grid dekat (akar tidak pindah saat LOD)
        for (int gz = 0; gz < NearGrid; gz++)
        {
            for (int gx = 0; gx < NearGrid; gx++)
            {
                if (grid == FarGrid && (gx % 2 != 0 || gz % 2 != 0)) continue;
                float lx = (gx + (float)(rng.NextDouble() * 0.5 + 0.25)) * cell;
                float lz = (gz + (float)(rng.NextDouble() * 0.5 + 0.25)) * cell;
                float wx = origin.x + lx, wz = origin.z + lz;
                if (!CanGrow(wx, wz)) continue;

                float h = IslandTerrain.I.SurfaceHeight(wx, wz) - 0.03f;
                float angle = (float)rng.NextDouble() * Mathf.PI * 2f;
                float scale = 0.9f + (float)rng.NextDouble() * 0.25f;
                float rand = (float)rng.NextDouble();

                // kemiringan mengikuti permukaan (tidak melayang di lereng)
                float dx = IslandTerrain.I.SurfaceHeight(wx + 0.5f, wz) - IslandTerrain.I.SurfaceHeight(wx - 0.5f, wz);
                float dz = IslandTerrain.I.SurfaceHeight(wx, wz + 0.5f) - IslandTerrain.I.SurfaceHeight(wx, wz - 0.5f);
                var tilt = Quaternion.FromToRotation(Vector3.up, new Vector3(-dx, 1f, -dz).normalized);
                var rot = Quaternion.Euler(0f, angle * Mathf.Rad2Deg, 0f);

                AddClump(verts, norms, cols, tris, tilt * rot, scale, rand,
                         origin + new Vector3(lx, h, lz) - origin);
            }
        }

        if (verts.Count == 0)
        {
            if (tiles.TryGetValue(key, out var emptyTile) && emptyTile != null) Destroy(emptyTile);
            tiles[key] = null;
            tileGrids[key] = grid;
            return;
        }

        var mesh = new Mesh();
        mesh.name = "GrassTile";
        mesh.indexFormat = UnityEngine.Rendering.IndexFormat.UInt32;
        mesh.SetVertices(verts);
        mesh.SetNormals(norms);
        mesh.SetColors(cols);
        mesh.SetTriangles(tris, 0);
        mesh.RecalculateBounds();

        var go = new GameObject("Grass_" + kx + "_" + kz);
        go.transform.SetParent(transform, false);
        go.transform.localPosition = origin;
        var mf = go.AddComponent<MeshFilter>();
        mf.sharedMesh = mesh;
        var mr = go.AddComponent<MeshRenderer>();
        mr.sharedMaterial = mat;
        mr.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
        mr.receiveShadows = false;

        if (tiles.TryGetValue(key, out var old) && old != null) Destroy(old);
        tiles[key] = go;
        tileGrids[key] = grid;
    }

    void AddClump(List<Vector3> verts, List<Vector3> norms, List<Color> cols, List<int> tris,
                  Quaternion rot, float scale, float rand, Vector3 local)
    {
        // 4 helai segitiga + quad penutup (persis topologi Godot, dibaked lokal tile)
        for (int blade = 0; blade < 4; blade++)
        {
            float a = blade * Mathf.PI * 2f / 4f;
            var offset = Quaternion.Euler(0f, a * Mathf.Rad2Deg, 0f) * new Vector3(0.13f, 0f, 0f);
            float hgt = BladeHeight * (blade % 2 == 0 ? 0.8f : 1f);
            Vector3[] pts =
            {
                new Vector3(-BladeWidth / 2f, 0f, 0f),
                new Vector3(BladeWidth / 2f, 0f, 0f),
                new Vector3(0.025f, hgt, 0.09f)
            };
            int b = verts.Count;
            for (int i = 0; i < 3; i++)
            {
                var p = Quaternion.Euler(0f, a * Mathf.Rad2Deg, 0f) * pts[i] + offset;
                verts.Add(local + rot * (p * scale));
                norms.Add(rot * Vector3.up);
                cols.Add(new Color(Mathf.Clamp01(pts[i].y / BladeHeight), 0f, rand, 1f));
            }
            tris.Add(b); tris.Add(b + 1); tris.Add(b + 2);
        }
        int cb = verts.Count;
        Vector2[] corners = { new Vector2(-1, -1), new Vector2(1, -1), new Vector2(-1, 1), new Vector2(1, 1) };
        for (int i = 0; i < 4; i++)
        {
            var p = new Vector3(corners[i].x * CoverHalf, 0.08f, corners[i].y * CoverHalf);
            verts.Add(local + rot * (p * scale));
            norms.Add(rot * Vector3.up);
            cols.Add(new Color(0.2f, 1f, rand, 1f));
        }
        tris.Add(cb); tris.Add(cb + 1); tris.Add(cb + 2);
        tris.Add(cb + 1); tris.Add(cb + 3); tris.Add(cb + 2);
    }
}
