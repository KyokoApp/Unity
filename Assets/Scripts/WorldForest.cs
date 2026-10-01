using System.Collections.Generic;
using UnityEngine;

/// <summary>
/// Hutan & detail nature deterministik per tile 40 m (port redesign
/// world/nature_field.gd Godot): 7x7 tile aktif, 6 percobaan pohon + 12 detail
/// per tile, "grove" sinusoidal supaya padang terbuka berselang-seling dengan
/// rumpun rapat (bukan grid teratur), maksimal 1 tile dibangun per frame.
/// Prefab = konversi glTF Kenney (CC0) oleh ImportWorld saat build CI.
/// </summary>
public class WorldForest : MonoBehaviour
{
    public Transform target;

    const float Tile = 40f;
    const int Radius = 3;
    const int TreeAttempts = 6;
    const int DetailAttempts = 12;

    readonly List<GameObject> trees = new List<GameObject>();
    readonly List<GameObject> bushes = new List<GameObject>();
    readonly List<GameObject> covers = new List<GameObject>();
    readonly List<GameObject> pebbles = new List<GameObject>();

    readonly Dictionary<long, GameObject> tiles = new Dictionary<long, GameObject>();
    readonly Dictionary<long, int> tileCounts = new Dictionary<long, int>();
    readonly Queue<long> pending = new Queue<long>();
    Vector2Int center = new Vector2Int(99999, 99999);
    int instanceCount;
    const int MaxInstances = 340;   // pagu draw call mobile

    public void LoadAssets()
    {
        var prefabs = Resources.LoadAll<GameObject>("WorldGen/Prefabs");
        foreach (var p in prefabs)
        {
            if (p == null) continue;
            string n = p.name;
            if (n.Contains("Tree") || n.Contains("Pine")) trees.Add(p);
            else if (n.Contains("Bush")) bushes.Add(p);
            else if (n.Contains("Pebble") || n.Contains("RockPath")) pebbles.Add(p);
            else covers.Add(p);   // Fern, Flower
        }
        Debug.Log("[WorldForest] prefab: trees=" + trees.Count + " bushes=" + bushes.Count
                  + " covers=" + covers.Count + " pebbles=" + pebbles.Count);
    }

    void Update()
    {
        if (target == null || IslandTerrain.I == null) return;
        var c = new Vector2Int(Mathf.FloorToInt(target.position.x / Tile),
                               Mathf.FloorToInt(target.position.z / Tile));
        if (c != center) Recenter(c);
        if (pending.Count > 0) BuildTile(pending.Dequeue());
    }

    static long Key(int x, int z) { return ((long)x << 32) | (uint)z; }

    void Recenter(Vector2Int c)
    {
        center = c;
        pending.Clear();
        var dead = new List<long>();
        foreach (var kv in tiles)
        {
            int x = (int)(kv.Key >> 32), z = (int)(kv.Key & 0xFFFFFFFF);
            if (Mathf.Max(Mathf.Abs(x - c.x), Mathf.Abs(z - c.y)) > Radius) dead.Add(kv.Key);
        }
        for (int i = 0; i < dead.Count; i++)
        {
            if (tiles.TryGetValue(dead[i], out var go) && go != null) Destroy(go);
            if (tileCounts.TryGetValue(dead[i], out int cn)) instanceCount -= cn;
            tiles.Remove(dead[i]);
            tileCounts.Remove(dead[i]);
        }
        var order = new List<long>();
        for (int z = c.y - Radius; z <= c.y + Radius; z++)
            for (int x = c.x - Radius; x <= c.x + Radius; x++)
                if (!tiles.ContainsKey(Key(x, z))) order.Add(Key(x, z));
        order.Sort((a, b) => Dist(a, c).CompareTo(Dist(b, c)));
        for (int i = 0; i < order.Count; i++) pending.Enqueue(order[i]);
    }

    static float Dist(long key, Vector2Int c)
    {
        int x = (int)(key >> 32), z = (int)(key & 0xFFFFFFFF);
        return (x - c.x) * (x - c.x) + (z - c.y) * (z - c.y);
    }

    bool CanPlace(float x, float z, bool tree)
    {
        var it = IslandTerrain.I;
        if (IslandTerrain.ArenaDistance(x, z) < 5f || new Vector2(x, z).magnitude > 405f) return false;
        float h = it.SurfaceHeight(x, z);
        if (h < 5.5f || IslandTerrain.WaterCovers(x, z, 3f)) return false;
        if (Mathf.Abs(z) < 345f && IslandTerrain.RoadDistance(x, z) < (tree ? 17f : 14f)) return false;
        float gx = it.SurfaceHeight(x + 1f, z) - it.SurfaceHeight(x - 1f, z);
        float gz = it.SurfaceHeight(x, z + 1f) - it.SurfaceHeight(x, z - 1f);
        if (new Vector2(gx, gz).magnitude * 0.5f > 0.40f) return false;
        for (int i = 0; i < it.RockClearances.Count; i++)
        {
            var r = it.RockClearances[i];
            if (new Vector2(x - r.x, z - r.z).magnitude < r.y + 2f) return false;
        }
        return true;
    }

    void BuildTile(long key)
    {
        int kx = (int)(key >> 32), kz = (int)(key & 0xFFFFFFFF);
        var root = new GameObject("Nature_" + kx + "_" + kz);
        root.transform.SetParent(transform, false);
        root.transform.localPosition = new Vector3(kx * Tile, 0f, kz * Tile);

        var rng = new System.Random(unchecked(kx * 73856093 ^ kz * 19349663) + 71037);
        var placed = new List<Vector2>();
        var placedTree = new List<Vector2>();

        for (int i = 0; i < TreeAttempts + DetailAttempts; i++)
        {
            if (instanceCount >= MaxInstances) break;
            bool tree = i < TreeAttempts;
            float px = kx * Tile + (float)(rng.NextDouble() * (Tile - 8) + 4);
            float pz = kz * Tile + (float)(rng.NextDouble() * (Tile - 8) + 4);

            // padang terbuka berselang-seling dengan rumpun rapat (densitas live)
            float grove = Mathf.Sin(px * 0.027f) * Mathf.Cos(pz * 0.033f);
            float accept = Mathf.Clamp01((0.58f + grove * 0.25f) * WorldTuning.TreeDensity);
            if (tree && rng.NextDouble() > accept) continue;
            if (!CanPlace(px, pz, tree)) continue;

            var pt = new Vector2(px, pz);
            float minGap = tree ? 6f : 1.5f;
            var others = tree ? placedTree : placed;
            bool tooClose = false;
            for (int j = 0; j < others.Count; j++)
                if ((others[j] - pt).sqrMagnitude < minGap * minGap) { tooClose = true; break; }
            if (tooClose) continue;

            GameObject prefab;
            if (tree) prefab = Pick(trees, rng);
            else
            {
                double r = rng.NextDouble();
                if (r < 0.35 && bushes.Count > 0) prefab = Pick(bushes, rng);
                else if (r < 0.90 && covers.Count > 0) prefab = Pick(covers, rng);
                else if (pebbles.Count > 0) prefab = Pick(pebbles, rng);
                else prefab = Pick(bushes, rng);
                if (prefab == null) prefab = Pick(covers, rng);
            }
            if (prefab == null) continue;

            float y = IslandTerrain.I.SurfaceHeight(px, pz) - 0.05f;
            var go = Instantiate(prefab, root.transform);
            go.transform.localPosition = new Vector3(px - kx * Tile, y, pz - kz * Tile);
            go.transform.localRotation = Quaternion.Euler(0f, (float)rng.NextDouble() * 360f, 0f);
            float s = tree ? 0.9f + (float)rng.NextDouble() * 0.4f
                           : 0.85f + (float)rng.NextDouble() * 0.4f;
            go.transform.localScale = Vector3.one * s;

            placed.Add(pt);
            if (tree) placedTree.Add(pt);
            instanceCount++;
        }

        tiles[key] = root;
        tileCounts[key] = placed.Count;
    }

    static GameObject Pick(List<GameObject> list, System.Random rng)
    {
        return list.Count > 0 ? list[rng.Next(list.Count)] : null;
    }
}
