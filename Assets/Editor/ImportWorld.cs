using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;
using UnityEditor;
using UnityEngine;

/// <summary>
/// Konverter world assets Godot (glTF 2.0 terpisah: .gltf + .bin + .png) menjadi
/// asset Unity (Mesh + Material + Prefab) SAAT BUILD CI — Unity 2022 tidak bisa
/// impor glTF secara native. Dipanggil CiBuild.BuildAll (lihat juga
/// ExtractLocomotion untuk pola yang sama).
///
/// Sumber: Assets/WorldSrc/ (model nature dari repo KyokoApp/Godot branch
/// arena/01a0f421-godot — Kenney Nature Kit, CC0).
/// Hasil : Assets/WorldGen/ (Meshes/, Materials/, Prefabs/) — di-gitignore,
///         dibangkitkan ulang tiap build.
///
/// Konversi koordinat: glTF = right-handed Y-up, Unity = left-handed Y-up
/// → negasi Z pada posisi & normal, urutan winding dibalik, V texture dibalik.
/// </summary>
public static class ImportWorld
{
    const string SrcDir = "Assets/WorldSrc";
    const string OutDir = "Assets/Resources/WorldGen";   // wajib di bawah Resources/ agar bisa di-LoadAll runtime

    // Model yang dapat collider (pohon/batu/bush bisa ditabrak; rerumputan tidak).
    static bool NeedsCollider(string name)
    {
        return name.IndexOf("Tree", StringComparison.Ordinal) >= 0
            || name.IndexOf("Pine", StringComparison.Ordinal) >= 0
            || name.IndexOf("Rock", StringComparison.Ordinal) >= 0
            || name.IndexOf("Bush", StringComparison.Ordinal) >= 0;
    }

    [MenuItem("Assets/Impor World Nature (Kenney CC0)")]
    public static void Run()
    {
        if (!Directory.Exists(SrcDir))
        {
            Debug.LogWarning("[ImportWorld] " + SrcDir + " tidak ada — world nature dilewati.");
            return;
        }

        Directory.CreateDirectory(OutDir + "/Meshes");
        Directory.CreateDirectory(OutDir + "/Materials");
        Directory.CreateDirectory(OutDir + "/Prefabs");

        var gltfs = Directory.GetFiles(SrcDir, "*.gltf");
        int done = 0;
        foreach (var gltfPath in gltfs)
        {
            try
            {
                if (ConvertOne(gltfPath)) done++;
            }
            catch (Exception e)
            {
                Debug.LogError("[ImportWorld] Gagal konversi " + gltfPath + ": " + e);
            }
        }
        // tekstur scatter meadow (mask grayscale dari repo Godot) untuk corak
        // shader terrain — harus di bawah Resources agar bisa di-load runtime.
        string texDir = OutDir + "/Textures";
        Directory.CreateDirectory(texDir);
        string meadowSrc = SrcDir + "/meadow_cover.png";
        string meadowDst = texDir + "/meadow_cover.png";
        if (File.Exists(meadowSrc))
        {
            File.Copy(meadowSrc, meadowDst, true);
            AssetDatabase.ImportAsset(meadowDst);
            var ti = AssetDatabase.LoadAssetAtPath<TextureImporter>(meadowDst);
            if (ti != null)
            {
                ti.wrapMode = TextureWrapMode.Repeat;
                ti.filterMode = FilterMode.Bilinear;
                ti.mipmapEnabled = true;
                ti.maxTextureSize = 256;
                ti.SaveAndReimport();
            }
        }

        AssetDatabase.SaveAssets();
        AssetDatabase.Refresh();
        Debug.Log("[ImportWorld] " + done + "/" + gltfs.Length + " model nature siap di " + OutDir + "/Prefabs");
    }

    // ================= SATU FILE glTF =================

    static byte[] bin;
    static List<object> bufferViews;
    static List<object> accessors;

    static bool ConvertOne(string gltfPath)
    {
        string name = Path.GetFileNameWithoutExtension(gltfPath);
        string binPath = Path.ChangeExtension(gltfPath, ".bin");
        if (!File.Exists(binPath)) { Debug.LogError("[ImportWorld] .bin tidak ada: " + binPath); return false; }

        var root = MiniJson.Parse(File.ReadAllText(gltfPath)) as Dictionary<string, object>;
        bin = File.ReadAllBytes(binPath);
        bufferViews = root.ContainsKey("bufferViews") ? MiniJson.List(root["bufferViews"]) : new List<object>();
        accessors = MiniJson.List(root["accessors"]);
        var meshes = MiniJson.List(root["meshes"]);
        var materials = root.ContainsKey("materials") ? MiniJson.List(root["materials"]) : new List<object>();
        var textures = root.ContainsKey("textures") ? MiniJson.List(root["textures"]) : new List<object>();
        var images = root.ContainsKey("images") ? MiniJson.List(root["images"]) : new List<object>();
        if (meshes.Count == 0) return false;

        // ---- materials ----
        var matAssets = new List<Material>();
        for (int mi = 0; mi < materials.Count; mi++)
            matAssets.Add(BuildMaterial(MiniJson.Dict(materials[mi]), textures, images, name + "_m" + mi));

        // ---- mesh (gabungkan primitives jadi submesh) ----
        var mesh = new Mesh();
        mesh.name = name;
        mesh.indexFormat = UnityEngine.Rendering.IndexFormat.UInt32;

        var verts = new List<Vector3>();
        var norms = new List<Vector3>();
        var uvs = new List<Vector2>();
        var cols = new List<Color>();
        var subTris = new List<List<int>>();

        var prims = MiniJson.List(MiniJson.Dict(meshes[0])["primitives"]);
        bool anyColor = false;
        for (int pi = 0; pi < prims.Count; pi++)
            if (MiniJson.Dict(MiniJson.Dict(prims[pi])["attributes"]).ContainsKey("COLOR_0")) { anyColor = true; break; }

        for (int pi = 0; pi < prims.Count; pi++)
        {
            var prim = MiniJson.Dict(prims[pi]);
            var attrs = MiniJson.Dict(prim["attributes"]);
            int offset = verts.Count;

            int count, comps;
            var pos = (float[])ReadAccessor((int)MiniJson.Num(attrs["POSITION"]), out count, out comps);
            var nrm = attrs.ContainsKey("NORMAL") ? (float[])ReadAccessor((int)MiniJson.Num(attrs["NORMAL"]), out count, out comps) : null;
            var uv = attrs.ContainsKey("TEXCOORD_0") ? (float[])ReadAccessor((int)MiniJson.Num(attrs["TEXCOORD_0"]), out count, out comps) : null;
            float[] col = attrs.ContainsKey("COLOR_0") ? (float[])ReadAccessor((int)MiniJson.Num(attrs["COLOR_0"]), out count, out comps) : null;

            for (int v = 0; v < count; v++)
            {
                // glTF RH Y-up → Unity LH Y-up: negasi Z
                verts.Add(new Vector3(pos[v * 3], pos[v * 3 + 1], -pos[v * 3 + 2]));
                norms.Add(nrm != null
                    ? new Vector3(nrm[v * 3], nrm[v * 3 + 1], -nrm[v * 3 + 2])
                    : Vector3.up);
                uvs.Add(uv != null
                    ? new Vector2(uv[v * 2], 1f - uv[v * 2 + 1])   // flip V
                    : Vector2.zero);
                if (col != null)
                {
                    cols.Add(col.Length >= (v + 1) * 4
                        ? new Color(col[v * 4], col[v * 4 + 1], col[v * 4 + 2], col[v * 4 + 3])
                        : Color.white);
                }
                else if (anyColor) cols.Add(Color.white);   // jaga align per-vertex
            }

            var idx = (int[])ReadIndices((int)MiniJson.Num(prim["indices"]), out count);
            var tris = new List<int>(idx.Length);
            for (int t = 0; t + 2 < idx.Length; t += 3)
            {
                // winding dibalik karena mirror Z
                tris.Add(offset + idx[t + 2]);
                tris.Add(offset + idx[t + 1]);
                tris.Add(offset + idx[t]);
            }
            subTris.Add(tris);
        }

        if (anyColor && cols.Count != verts.Count)
        {
            while (cols.Count < verts.Count) cols.Add(Color.white);
        }

        mesh.SetVertices(verts);
        mesh.SetNormals(norms);
        mesh.SetUVs(0, uvs);
        if (anyColor) mesh.SetColors(cols);
        mesh.subMeshCount = subTris.Count;
        for (int s = 0; s < subTris.Count; s++)
            mesh.SetTriangles(subTris[s], s);
        mesh.RecalculateBounds();
        mesh.RecalculateTangents();

        string meshPath = OutDir + "/Meshes/" + name + ".asset";
        DeleteIfExists(meshPath);
        AssetDatabase.CreateAsset(mesh, meshPath);

        // ---- prefab ----
        var go = new GameObject(name);
        var mf = go.AddComponent<MeshFilter>();
        mf.sharedMesh = mesh;
        var mr = go.AddComponent<MeshRenderer>();
        var mats = new Material[subTris.Count];
        for (int s = 0; s < subTris.Count; s++)
        {
            var prim = MiniJson.Dict(prims[s]);
            int matIdx = prim.ContainsKey("material") ? (int)MiniJson.Num(prim["material"]) : -1;
            mats[s] = matIdx >= 0 && matIdx < matAssets.Count ? matAssets[matIdx] : null;
        }
        mr.sharedMaterials = mats;
        if (NeedsCollider(name))
        {
            var mc = go.AddComponent<MeshCollider>();
            mc.sharedMesh = mesh;
        }

        string prefabPath = OutDir + "/Prefabs/" + name + ".prefab";
        DeleteIfExists(prefabPath);
        PrefabUtility.SaveAsPrefabAsset(go, prefabPath);
        UnityEngine.Object.DestroyImmediate(go);
        return true;
    }

    // ================= MATERIAL =================

    static Material BuildMaterial(Dictionary<string, object> m, List<object> textures, List<object> images, string fallbackName)
    {
        string matName = m.ContainsKey("name") ? (string)m["name"] : fallbackName;
        string safe = Sanitize(matName);
        string path = OutDir + "/Materials/" + safe + ".mat";
        var existing = AssetDatabase.LoadAssetAtPath<Material>(path);
        if (existing != null) return existing;   // texture atlas dibagi antar model

        var mat = new Material(Shader.Find("Standard"));
        mat.name = safe;
        mat.SetFloat("_Metallic", 0f);
        mat.SetFloat("_Glossiness", 0.05f);

        string alphaMode = m.ContainsKey("alphaMode") ? (string)m["alphaMode"] : "OPAQUE";
        bool doubleSided = m.ContainsKey("doubleSided") && (bool)m["doubleSided"];
        mat.SetFloat("_Cull", doubleSided ? 0f : 2f);
        if (alphaMode == "MASK")
        {
            mat.SetFloat("_Mode", 1f);   // Cutout
            mat.EnableKeyword("_ALPHATEST_ON");          // WAJIB: tanpa ini Standard tetap varian Opaque
            mat.DisableKeyword("_ALPHABLEND_ON");        // -> background transparan (RGB hitam) ikut tergambar
            mat.DisableKeyword("_ALPHAPREMULTIPLY_ON");
            mat.SetOverrideTag("RenderType", "TransparentCutout");
            float cutoff = m.ContainsKey("alphaCutoff") ? (float)MiniJson.Num(m["alphaCutoff"]) : 0.5f;
            mat.SetFloat("_Cutoff", cutoff);
        }
        else if (alphaMode == "BLEND")
        {
            mat.SetFloat("_Mode", 2f);   // Fade
            mat.EnableKeyword("_ALPHABLEND_ON");
            mat.DisableKeyword("_ALPHATEST_ON");
            mat.SetOverrideTag("RenderType", "Transparent");
        }
        else
        {
            mat.SetOverrideTag("RenderType", "Opaque");
        }

        if (m.ContainsKey("pbrMetallicRoughness"))
        {
            var pbr = MiniJson.Dict(m["pbrMetallicRoughness"]);
            if (pbr.ContainsKey("baseColorTexture"))
            {
                var tex = ResolveTexture(MiniJson.Dict(pbr["baseColorTexture"]), textures, images, false);
                if (tex != null) mat.SetTexture("_MainTex", tex);
            }
        }
        if (m.ContainsKey("normalTexture"))
        {
            var tex = ResolveTexture(MiniJson.Dict(m["normalTexture"]), textures, images, true);
            if (tex != null)
            {
                mat.SetTexture("_BumpMap", tex);
                mat.EnableKeyword("_NORMALMAP");
            }
        }

        AssetDatabase.CreateAsset(mat, path);
        return mat;
    }

    static Texture2D ResolveTexture(Dictionary<string, object> texRef, List<object> textures, List<object> images, bool isNormal)
    {
        int ti = (int)MiniJson.Num(texRef["index"]);
        if (ti < 0 || ti >= textures.Count) return null;
        var tex = MiniJson.Dict(textures[ti]);
        int si = (int)MiniJson.Num(tex["source"]);
        if (si < 0 || si >= images.Count) return null;
        var img = MiniJson.Dict(images[si]);
        string uri = (string)img["uri"];
        string path = SrcDir + "/" + uri;

        if (AssetDatabase.LoadAssetAtPath<Texture2D>(path) == null)
            AssetDatabase.ImportAsset(path, ImportAssetOptions.ForceUpdate);

        var importer = AssetImporter.GetAtPath(path) as TextureImporter;
        if (importer != null)
        {
            bool changed = false;
            var wantType = isNormal ? TextureImporterType.NormalMap : TextureImporterType.Default;
            if (importer.textureType != wantType) { importer.textureType = wantType; changed = true; }
            if (importer.mipmapEnabled == false) { importer.mipmapEnabled = true; changed = true; }
            if (changed) importer.SaveAndReimport();
        }
        return AssetDatabase.LoadAssetAtPath<Texture2D>(path);
    }

    // ================= ACCESSOR =================

    static Array ReadAccessor(int ai, out int count, out int comps)
    {
        var a = MiniJson.Dict(accessors[ai]);
        var bv = MiniJson.Dict(bufferViews[(int)MiniJson.Num(a["bufferView"])]);
        int bo = bv.ContainsKey("byteOffset") ? (int)MiniJson.Num(bv["byteOffset"]) : 0;
        int ao = a.ContainsKey("byteOffset") ? (int)MiniJson.Num(a["byteOffset"]) : 0;
        int ct = (int)MiniJson.Num(a["componentType"]);
        count = (int)MiniJson.Num(a["count"]);
        string type = (string)a["type"];
        comps = type == "SCALAR" ? 1 : type == "VEC2" ? 2 : type == "VEC3" ? 3 : 4;
        int off = bo + ao;

        if (ct == 5126) { var r = new float[count * comps]; Buffer.BlockCopy(bin, off, r, 0, r.Length * 4); return r; }
        throw new Exception("ReadAccessor float: componentType tak didukung " + ct);
    }

    static Array ReadIndices(int ai, out int count)
    {
        var a = MiniJson.Dict(accessors[ai]);
        var bv = MiniJson.Dict(bufferViews[(int)MiniJson.Num(a["bufferView"])]);
        int bo = bv.ContainsKey("byteOffset") ? (int)MiniJson.Num(bv["byteOffset"]) : 0;
        int ao = a.ContainsKey("byteOffset") ? (int)MiniJson.Num(a["byteOffset"]) : 0;
        int ct = (int)MiniJson.Num(a["componentType"]);
        count = (int)MiniJson.Num(a["count"]);
        int off = bo + ao;

        if (ct == 5123) { var u = new ushort[count]; Buffer.BlockCopy(bin, off, u, 0, count * 2); var r = new int[count]; for (int i = 0; i < count; i++) r[i] = u[i]; return r; }
        if (ct == 5125) { var u = new uint[count]; Buffer.BlockCopy(bin, off, u, 0, count * 4); var r = new int[count]; for (int i = 0; i < count; i++) r[i] = (int)u[i]; return r; }
        if (ct == 5121) { var r = new int[count]; for (int i = 0; i < count; i++) r[i] = bin[off + i]; return r; }
        throw new Exception("ReadIndices: componentType tak didukung " + ct);
    }

    static void DeleteIfExists(string path)
    {
        if (AssetDatabase.LoadAssetAtPath<UnityEngine.Object>(path) != null)
            AssetDatabase.DeleteAsset(path);
    }

    static string Sanitize(string s)
    {
        var sb = new StringBuilder();
        foreach (char c in s)
            sb.Append(char.IsLetterOrDigit(c) || c == '_' ? c : '_');
        return sb.ToString();
    }
}

// ================= MINI JSON PARSER =================
// glTF memakai dictionary dinamis (attributes dll.) yang tidak didukung
// JsonUtility — parser kecil deterministik tanpa dependensi eksternal.
public static class MiniJson
{
    public static object Parse(string s) { int i = 0; return ParseValue(s, ref i); }

    public static Dictionary<string, object> Dict(object o) { return (Dictionary<string, object>)o; }
    public static List<object> List(object o) { return (List<object>)o; }
    public static double Num(object o) { return Convert.ToDouble(o, CultureInfo.InvariantCulture); }

    static void SkipWs(string s, ref int i) { while (i < s.Length && char.IsWhiteSpace(s[i])) i++; }

    static object ParseValue(string s, ref int i)
    {
        SkipWs(s, ref i);
        char c = s[i];
        if (c == '{') return ParseObject(s, ref i);
        if (c == '[') return ParseArray(s, ref i);
        if (c == '"') return ParseString(s, ref i);
        if (c == 't') { i += 4; return true; }
        if (c == 'f') { i += 5; return false; }
        if (c == 'n') { i += 4; return null; }
        return ParseNumber(s, ref i);
    }

    static Dictionary<string, object> ParseObject(string s, ref int i)
    {
        var d = new Dictionary<string, object>();
        i++;
        SkipWs(s, ref i);
        if (s[i] == '}') { i++; return d; }
        while (true)
        {
            SkipWs(s, ref i);
            string k = ParseString(s, ref i);
            SkipWs(s, ref i);
            i++; // ':'
            d[k] = ParseValue(s, ref i);
            SkipWs(s, ref i);
            if (s[i] == ',') { i++; continue; }
            i++; // '}'
            return d;
        }
    }

    static List<object> ParseArray(string s, ref int i)
    {
        var l = new List<object>();
        i++;
        SkipWs(s, ref i);
        if (s[i] == ']') { i++; return l; }
        while (true)
        {
            l.Add(ParseValue(s, ref i));
            SkipWs(s, ref i);
            if (s[i] == ',') { i++; continue; }
            i++; // ']'
            return l;
        }
    }

    static string ParseString(string s, ref int i)
    {
        i++; // '"'
        var sb = new StringBuilder();
        while (s[i] != '"')
        {
            char c = s[i++];
            if (c == '\\')
            {
                char e = s[i++];
                switch (e)
                {
                    case 'n': sb.Append('\n'); break;
                    case 't': sb.Append('\t'); break;
                    case 'r': sb.Append('\r'); break;
                    case 'b': sb.Append('\b'); break;
                    case 'f': sb.Append('\f'); break;
                    case 'u': sb.Append((char)Convert.ToInt32(s.Substring(i, 4), 16)); i += 4; break;
                    default: sb.Append(e); break;
                }
            }
            else sb.Append(c);
        }
        i++;
        return sb.ToString();
    }

    static object ParseNumber(string s, ref int i)
    {
        int st = i;
        while (i < s.Length && "+-0123456789.eE".IndexOf(s[i]) >= 0) i++;
        return double.Parse(s.Substring(st, i - st), CultureInfo.InvariantCulture);
    }
}
