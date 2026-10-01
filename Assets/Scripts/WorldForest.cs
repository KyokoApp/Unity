using System.Collections.Generic;
using UnityEngine;

/// <summary>
/// Hutan prosedural di world datar tak-berbatas: prefab nature (hasil konversi
/// glTF Kenney Nature Kit oleh ImportWorld saat build CI) disebar DETERMINISTIK
/// per sel grid — pola tetap sama setiap kali player kembali ke sel yang sama
/// (seed dari koordinat sel), spawn/musnah halus mengikuti posisi player.
///
/// Ringan untuk mobile: maksimal beberapa ratus instance, update tersebar
/// (throttle), hanya instantiate/destroy saat melewati batas sel.
/// </summary>
public class WorldForest : MonoBehaviour
{
    public Transform target;

    const float CellSize = 12f;
    const float SpawnRadius = 70f;
    const float DespawnRadius = 88f;
    const float ClearRadius = 9f;      // area lahir player bersih
    const int MaxInstances = 240;
    const float UpdateInterval = 0.2f;

    // kategori prefab (diisi LoadAssets)
    readonly List<GameObject> trees = new List<GameObject>();
    readonly List<GameObject> bushes = new List<GameObject>();
    readonly List<GameObject> rocks = new List<GameObject>();
    readonly List<GameObject> covers = new List<GameObject>();

    readonly Dictionary<long, List<GameObject>> active = new Dictionary<long, List<GameObject>>();
    float nextUpdate;
    int instanceCount;

    public void LoadAssets()
    {
        var prefabs = Resources.LoadAll<GameObject>("WorldGen/Prefabs");
        foreach (var p in prefabs)
        {
            if (p == null) continue;
            string n = p.name;
            if (n.IndexOf("Tree", System.StringComparison.Ordinal) >= 0 ||
                n.IndexOf("Pine", System.StringComparison.Ordinal) >= 0) trees.Add(p);
            else if (n.IndexOf("Bush", System.StringComparison.Ordinal) >= 0) bushes.Add(p);
            else if (n.IndexOf("Rock", System.StringComparison.Ordinal) >= 0 ||
                     n.IndexOf("Pebble", System.StringComparison.Ordinal) >= 0) rocks.Add(p);
            else covers.Add(p);   // Fern, Flower, dll.
        }
        Debug.Log("[WorldForest] prefab termuat: trees=" + trees.Count + " bushes=" + bushes.Count
                  + " rocks=" + rocks.Count + " covers=" + covers.Count);
    }

    void Update()
    {
        if (target == null) return;
        if (Time.time < nextUpdate) return;
        nextUpdate = Time.time + UpdateInterval;

        Vector3 p = target.position;
        int cx = Mathf.FloorToInt(p.x / CellSize);
        int cz = Mathf.FloorToInt(p.z / CellSize);
        int range = Mathf.CeilToInt(SpawnRadius / CellSize);

        // spawn sel yang terlihat
        for (int x = cx - range; x <= cx + range; x++)
        {
            for (int z = cz - range; z <= cz + range; z++)
            {
                Vector3 center = new Vector3((x + 0.5f) * CellSize, 0f, (z + 0.5f) * CellSize);
                if ((center - p).sqrMagnitude > SpawnRadius * SpawnRadius) continue;
                long key = Key(x, z);
                if (active.ContainsKey(key)) continue;
                SpawnCell(key, x, z);
            }
        }

        // musnahkan yang jauh
        var dead = new List<long>();
        foreach (var kv in active)
        {
            var list = kv.Value;
            if (list.Count == 0) { dead.Add(kv.Key); continue; }
            Vector3 c = list[0].transform.position;
            if ((c - p).sqrMagnitude > DespawnRadius * DespawnRadius)
            {
                for (int i = 0; i < list.Count; i++)
                {
                    if (list[i] != null) { Destroy(list[i]); instanceCount--; }
                }
                dead.Add(kv.Key);
            }
        }
        for (int i = 0; i < dead.Count; i++) active.Remove(dead[i]);
    }

    void SpawnCell(long key, int x, int z)
    {
        var list = new List<GameObject>();
        active[key] = list;

        var rng = new System.Random(unchecked(x * 73856093 ^ z * 19349663));
        Vector3 center = new Vector3((x + 0.5f) * CellSize, 0f, (z + 0.5f) * CellSize);

        // satu objek "utama" per sel + kemungkinan penutup tanah
        float roll = (float)rng.NextDouble();
        GameObject main = null;
        if (roll < 0.34f && trees.Count > 0) main = Pick(trees, rng);
        else if (roll < 0.52f && bushes.Count > 0) main = Pick(bushes, rng);
        else if (roll < 0.70f && rocks.Count > 0) main = Pick(rocks, rng);
        else if (covers.Count > 0 && (float)rng.NextDouble() < 0.75f) main = Pick(covers, rng);

        if (main != null) Place(list, main, center, rng);

        // penutup tanah tambahan (rumput/bunga) biar tidak gersang
        if (covers.Count > 0 && (float)rng.NextDouble() < 0.45f)
            Place(list, Pick(covers, rng), center, rng);

        if (list.Count == 0) return;
    }

    void Place(List<GameObject> list, GameObject prefab, Vector3 center, System.Random rng)
    {
        if (instanceCount >= MaxInstances) return;

        float jx = ((float)rng.NextDouble() - 0.5f) * (CellSize - 2f);
        float jz = ((float)rng.NextDouble() - 0.5f) * (CellSize - 2f);
        Vector3 pos = center + new Vector3(jx, 0f, jz);
        if (pos.magnitude < ClearRadius) return;   // zona lahir player

        var go = Instantiate(prefab, pos, Quaternion.Euler(0f, (float)rng.NextDouble() * 360f, 0f));
        float s = 0.85f + (float)rng.NextDouble() * 0.4f;
        go.transform.localScale = Vector3.one * s;
        go.transform.SetParent(transform);
        list.Add(go);
        instanceCount++;
    }

    static GameObject Pick(List<GameObject> list, System.Random rng)
    {
        return list[rng.Next(list.Count)];
    }

    static long Key(int x, int z)
    {
        return ((long)x << 32) | (uint)z;
    }
}
