using UnityEngine;

/// <summary>
/// Pedang prosedural (tanpa aset eksternal): 3 kubus (bilah/gard/gagang)
/// ditempel mengikuti tulang tangan kanan model; orientasi dikunci ke arah
/// hadap karakter supaya ayunan combo Sword_Regular_A/B/C terbaca wajar
/// tanpa perlu menebak sumbu tulang tangan.
/// </summary>
public class SwordProp : MonoBehaviour
{
    GameObject root;
    Animator animator;
    bool visible;

    public void Attach(Animator a)
    {
        animator = a;
        if (root == null) Build();
        root.SetActive(false);
    }

    void Build()
    {
        root = new GameObject("Sword");
        root.transform.SetParent(transform, false);

        var steel = new Material(Shader.Find("Standard"));
        steel.SetColor("_Color", new Color(0.75f, 0.78f, 0.82f));
        steel.SetFloat("_Metallic", 1f);
        steel.SetFloat("_Glossiness", 0.8f);

        var dark = new Material(Shader.Find("Standard"));
        dark.SetColor("_Color", new Color(0.25f, 0.16f, 0.10f));
        dark.SetFloat("_Glossiness", 0.3f);

        MakePart("Blade", new Vector3(0.045f, 0.012f, 0.85f), new Vector3(0f, 0f, 0.45f), steel);
        MakePart("Guard", new Vector3(0.16f, 0.035f, 0.035f), new Vector3(0f, 0f, 0.02f), dark);
        MakePart("Grip", new Vector3(0.032f, 0.032f, 0.16f), new Vector3(0f, 0f, -0.09f), dark);
    }

    void MakePart(string n, Vector3 scale, Vector3 pos, Material m)
    {
        var go = GameObject.CreatePrimitive(PrimitiveType.Cube);
        go.name = n;
        Object.Destroy(go.GetComponent<Collider>());
        go.transform.SetParent(root.transform, false);
        go.transform.localPosition = pos;
        go.transform.localScale = scale;
        go.GetComponent<MeshRenderer>().sharedMaterial = m;
    }

    public void SetVisible(bool v)
    {
        visible = v;
        if (root != null) root.SetActive(v);
    }

    void LateUpdate()
    {
        if (!visible || root == null || animator == null) return;
        var hand = animator.GetBoneTransform(HumanBodyBones.RightHand);
        if (hand == null) return;
        var fwd = transform.forward;
        root.position = hand.position + fwd * 0.09f;
        root.rotation = Quaternion.LookRotation(fwd, Vector3.up) * Quaternion.Euler(6f, 0f, 0f);
    }
}
