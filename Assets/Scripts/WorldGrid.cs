using UnityEngine;

/// <summary>
/// World datar dengan garis grid kotak-kotak tanpa batas.
/// Pola grid dihitung shader dari koordinat dunia, lalu plane visual
/// selalu mengikuti player sehingga lantai terlihat tak berujung.
/// </summary>
public class WorldGrid : MonoBehaviour
{
    public Transform target;

    Transform planeT;   // plane visual (tanpa collider) — ikut player tiap frame

    static Material gridMat;

    /// <summary>Ganti warna grid + fog secara live (dipakai ContentUpdater).</summary>
    public static void ApplyLook(Color baseCol, Color lineCol, Color majorCol, Color? fogCol)
    {
        if (gridMat != null)
        {
            gridMat.SetColor("_BaseColor", baseCol);
            gridMat.SetColor("_LineColor", lineCol);
            gridMat.SetColor("_MajorColor", majorCol);
        }
        if (fogCol.HasValue)
        {
            RenderSettings.fogColor = fogCol.Value;
            var cam = Camera.main;
            if (cam != null) cam.backgroundColor = fogCol.Value;
        }
    }

    public static WorldGrid Create()
    {
        var root = new GameObject("World");
        var wg = root.AddComponent<WorldGrid>();

        // Collider lantai besar yang ikut bergerak bersama player.
        // Cadangan lantai selebar pulau 200 m (puncak tetap y=0), cukup luas
        // untuk map aktif tanpa collider ribuan meter yang tidak diperlukan.
        var col = root.AddComponent<BoxCollider>();
        col.size = new Vector3(IslandTerrain.WorldSize, 20f, IslandTerrain.WorldSize);
        col.center = new Vector3(0f, -10f, 0f);

        // Plane visual dengan shader grid tanpa batas.
        var plane = GameObject.CreatePrimitive(PrimitiveType.Plane);
        plane.name = "GridPlane";
        Object.Destroy(plane.GetComponent<Collider>());
        plane.transform.SetParent(root.transform, false);
        plane.transform.localPosition = Vector3.zero;
        plane.transform.localScale = new Vector3(IslandTerrain.WorldSize / 10f, 1f, IslandTerrain.WorldSize / 10f); // 200 x 200 m

        var shader = Resources.Load<Shader>("Shaders/InfiniteGrid");
        if (shader == null) shader = Shader.Find("UAL2/InfiniteGrid");
        var mat = new Material(shader);
        gridMat = mat;
        var mr = plane.GetComponent<MeshRenderer>();
        mr.sharedMaterial = mat;
        mr.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
        mr.receiveShadows = true;

        wg.planeT = plane.transform;
        return wg;
    }

    // Collider statis yang DIPINDAH tiap frame membuat PhysX glitch (karakter
    // bisa terdorong/grounded flicker → "tembus tanah"). Karena lantai datar
    // sempurna dan pola grid dihitung dari world-space, collider hanya di-snap
    // saat player mendekati tepi area cadangan 200 m.
    const float SnapDistance = IslandTerrain.WorldHalfSize;

    void LateUpdate()
    {
        if (target == null) return;
        Vector3 c = transform.position;
        Vector3 p = target.position;

        // Collider lantai (root): snap kasar tiap 100 m agar PhysX tidak glitch.
        if (Mathf.Abs(p.x - c.x) > SnapDistance || Mathf.Abs(p.z - c.z) > SnapDistance)
        {
            float sx = Mathf.Round(p.x / SnapDistance) * SnapDistance;
            float sz = Mathf.Round(p.z / SnapDistance) * SnapDistance;
            transform.position = new Vector3(sx, 0f, sz);
        }

        // Plane visual (tanpa collider): bebas ikut player tiap frame — grid
        // dihitung dari world-space jadi polanya tidak pernah bergeser.
        if (planeT != null) planeT.position = new Vector3(p.x, 0f, p.z);
    }
}
