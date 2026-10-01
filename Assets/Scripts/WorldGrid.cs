using UnityEngine;

/// <summary>
/// World datar dengan garis grid kotak-kotak tanpa batas.
/// Pola grid dihitung shader dari koordinat dunia, lalu plane visual
/// selalu mengikuti player sehingga lantai terlihat tak berujung.
/// </summary>
public class WorldGrid : MonoBehaviour
{
    public Transform target;

    public static WorldGrid Create()
    {
        var root = new GameObject("World");
        var wg = root.AddComponent<WorldGrid>();

        // Collider lantai besar yang ikut bergerak bersama player.
        var col = root.AddComponent<BoxCollider>();
        col.size = new Vector3(4000f, 2f, 4000f);
        col.center = new Vector3(0f, -1f, 0f);

        // Plane visual dengan shader grid tanpa batas.
        var plane = GameObject.CreatePrimitive(PrimitiveType.Plane);
        plane.name = "GridPlane";
        Object.Destroy(plane.GetComponent<Collider>());
        plane.transform.SetParent(root.transform, false);
        plane.transform.localPosition = Vector3.zero;
        plane.transform.localScale = new Vector3(80f, 1f, 80f); // 800 x 800 meter

        var shader = Resources.Load<Shader>("Shaders/InfiniteGrid");
        if (shader == null) shader = Shader.Find("UAL2/InfiniteGrid");
        var mat = new Material(shader);
        var mr = plane.GetComponent<MeshRenderer>();
        mr.sharedMaterial = mat;
        mr.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
        mr.receiveShadows = true;

        return wg;
    }

    void LateUpdate()
    {
        if (target == null) return;
        // Cukup ikuti player; pola grid dihitung dari world-space jadi tidak pernah bergeser.
        transform.position = new Vector3(target.position.x, 0f, target.position.z);
    }
}
