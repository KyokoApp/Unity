using System.Collections;
using System.IO;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;

/// <summary>
/// Audit fisika+animasi headless (jalan di CI, job sim-test, tanpa HP):
/// game dibangun sungguhan (GameBootstrap), karakter digerakkan lewat API
/// yang sama dengan tombol UI, lalu DICATAT: selisih y terhadap permukaan
/// pulau (ngambang/tenggelam?), jarak tempuh, dan clip animasi yang aktif.
/// Setiap skenario juga menyimpan screenshot ke build/simshots/ (diunggah
/// sebagai artefak run — bisa dilihat tanpa instal APK).
/// </summary>
public class SimTests
{
    GameObject bootGO;
    PlayerController player;
    PlayerAnimator panim;

    [UnitySetUp]
    public IEnumerator SetUp()
    {
        player = null;
        panim = null;
        GameBootstrap.SkipUpdater = true;   // jangan sentuh jaringan saat tes
        bootGO = new GameObject("Boot");
        bootGO.AddComponent<GameBootstrap>();
        for (int frame = 0; frame < 600 && player == null; frame++)
        {
            yield return null;
            player = Object.FindObjectOfType<PlayerController>();
        }
        Assert.IsNotNull(player, "PlayerController tidak ditemukan setelah bootstrap/loading");
        panim = player.GetComponent<PlayerAnimator>();
        yield return new WaitForSeconds(1.0f);   // tile rumput/hutan pertama
        Shot("00_plaza_spawn");
    }

    [UnityTearDown]
    public IEnumerator TearDown()
    {
        // Sebagian runtime roots dibuat oleh GameBootstrap sebagai objek scene,
        // bukan child Boot. Bersihkan semuanya agar tes berikutnya tidak
        // memakai player/terrain/PlayableGraph dari skenario sebelumnya.
        foreach (var orbit in Object.FindObjectsOfType<OrbitCamera>())
            Object.Destroy(orbit);

        string[] roots = { "Island", "Boulders", "Player", "GrassField", "WorldForest",
                           "GameUI", "ArpgLoadingScreen", "EventSystem" };
        var all = Object.FindObjectsOfType<GameObject>();
        foreach (var go in all)
        {
            if (go == null || go == bootGO || go.transform.parent != null) continue;
            for (int i = 0; i < roots.Length; i++)
                if (go.name == roots[i]) { Object.Destroy(go); break; }
        }
        if (bootGO != null) Object.Destroy(bootGO);
        IslandTerrain.I = null;
        GameBootstrap.SkipUpdater = false;
        yield return null;
    }

    float Dy()
    {
        var p = player.transform.position;
        return p.y - IslandTerrain.I.SurfaceHeight(p.x, p.z);
    }

    string Clip() { return panim != null && panim.CurrentClip != null ? panim.CurrentClip.name : "(null)"; }

    void Shot(string name)
    {
        Directory.CreateDirectory("build/simshots");
        ScreenCapture.CaptureScreenshot("build/simshots/" + name + ".png");
    }

    float FootGroundGap(Transform foot)
    {
        return foot.position.y - IslandTerrain.I.SurfaceHeight(foot.position.x, foot.position.z);
    }

    [UnityTest]
    public IEnumerator Sim_Dunia_200m_Dan_Spawn_Konsisten()
    {
        var terrain = IslandTerrain.I;
        Assert.IsNotNull(terrain, "IslandTerrain tidak dibuat");
        var renderer = terrain.GetComponent<MeshRenderer>();
        Assert.IsNotNull(renderer, "mesh terrain tidak ada");
        Assert.IsNotNull(renderer.sharedMaterial, "material terrain tidak ada");
        Assert.That(renderer.sharedMaterial.GetFloat("_WorldScale"),
                    Is.EqualTo(IslandTerrain.WorldScale).Within(0.0001f), "shader terrain tidak memakai skala dunia");
        Assert.That(renderer.bounds.size.x, Is.EqualTo(IslandTerrain.WorldSize).Within(0.05f), "lebar terrain bukan 200 m");
        Assert.That(renderer.bounds.size.z, Is.EqualTo(IslandTerrain.WorldSize).Within(0.05f), "panjang terrain bukan 200 m");
        Assert.That(Mathf.Abs(terrain.SpawnPoint.x), Is.LessThan(IslandTerrain.WorldHalfSize));
        Assert.That(Mathf.Abs(terrain.SpawnPoint.z), Is.LessThan(IslandTerrain.WorldHalfSize));
        Assert.That(Mathf.Abs(terrain.SpawnPoint.y - terrain.SurfaceHeight(terrain.SpawnPoint.x, terrain.SpawnPoint.z)),
                    Is.LessThan(0.1f), "spawn tidak menapak pada terrain");
        Debug.Log("[SIM] terrain bounds=" + renderer.bounds + ", spawn=" + terrain.SpawnPoint);
        Shot("05_dunia_200m");
        yield return null;
    }

    [UnityTest]
    public IEnumerator Sim_Jalan_Nempel_Di_Permukaan()
    {
        Vector3 start = player.transform.position;
        player.MoveInput = new Vector2(0f, 1f);
        yield return new WaitForSeconds(2.5f);
        player.MoveInput = Vector2.zero;

        float d = Dy();
        float dist = Vector3.Distance(player.transform.position, start);
        Debug.Log($"[SIM] walk: dy={d:F3} m, jarak={dist:F2} m, clip={Clip()}");
        Assert.IsTrue(Mathf.Abs(d) < 0.35f, "player ngambang/tenggelam saat jalan: dy=" + d);
        Assert.IsTrue(dist > 3f, "player tidak bergerak: " + dist);
        Assert.IsTrue(Clip().Contains("Walk") || Clip().Contains("Jog") || Clip().Contains("Sprint"),
            "clip lokomosi salah: " + Clip());
        Shot("01_jalan");
        yield return null;
    }

    [UnityTest]
    public IEnumerator Sim_Lompat_Naik_Lalu_Mendarat()
    {
        float maxDy = 0f;
        string clipUdara = "(null)";
        player.OnJump();
        for (int i = 0; i < 150; i++)
        {
            yield return null;
            float d = Dy();
            if (d > maxDy) { maxDy = d; clipUdara = Clip(); }
        }
        Debug.Log($"[SIM] jump: puncak={maxDy:F2} m, clipUdara={clipUdara}, clipAkhir={Clip()}, dyAkhir={Dy():F3}");
        Assert.IsTrue(maxDy > 1.0f, "lompat tidak naik: " + maxDy);
        Assert.IsTrue(Mathf.Abs(Dy()) < 0.35f, "TIDAK mendarat (ngambang): dy=" + Dy());
        Shot("02_setelah_lompat");
        yield return null;
    }

    [UnityTest]
    public IEnumerator Sim_Slide_Tidak_Melayang()
    {
        Vector3 start = player.transform.position;
        float maxDy = -99f, minDy = 99f;
        player.MoveInput = new Vector2(0f, 1f);
        yield return new WaitForSeconds(0.6f);
        player.MoveInput = Vector2.zero;
        player.OnSlide();
        for (int i = 0; i < 110; i++)
        {
            yield return null;
            float d = Dy();
            maxDy = Mathf.Max(maxDy, d);
            minDy = Mathf.Min(minDy, d);
        }
        float dist = Vector3.Distance(player.transform.position, start);
        Debug.Log($"[SIM] slide: dy=[{minDy:F3},{maxDy:F3}], jarak={dist:F2}, clip={Clip()}");
        Assert.IsTrue(maxDy < 0.6f, "slide melayang: maxDy=" + maxDy);
        Assert.IsTrue(dist > 2.5f, "slide tidak meluncur: " + dist);
        Shot("03_setelah_slide");
        yield return null;
    }

    [UnityTest]
    public IEnumerator Sim_Serang_Pedang_Muncul_Dan_Kembali_Idle()
    {
        var sword = player.GetComponent<SwordProp>();
        Assert.IsNotNull(sword, "SwordProp tidak ada");
        player.OnAttack();
        yield return new WaitForSeconds(0.25f);
        Debug.Log($"[SIM] attack: clip={Clip()}, pedang={sword.Visible}");
        Assert.IsTrue(sword.Visible, "pedang tidak muncul saat combo pedang");
        Assert.IsTrue(Clip().Contains("Sword"), "clip serangan bukan sword: " + Clip());
        Shot("04_serang");
        yield return new WaitForSeconds(1.8f);
        Debug.Log($"[SIM] attack selesai: clip={Clip()}, pedang={sword.Visible}");
        Assert.IsFalse(sword.Visible, "pedang tetap muncul setelah combo selesai");
        yield return null;
    }

    [UnityTest]
    public IEnumerator Sim_Diam_Tidak_Ngangambang()
    {
        yield return new WaitForSeconds(1.2f);
        float d = Dy();
        Debug.Log($"[SIM] idle: dy={d:F3}, clip={Clip()}");
        Assert.IsTrue(Mathf.Abs(d) < 0.3f, "idle ngambang: dy=" + d);
        Assert.IsTrue(Clip().Contains("Idle"), "clip idle salah: " + Clip());
        yield return null;
    }

    [UnityTest]
    public IEnumerator Sim_FootIK_Menjaga_Telapak_Dekat_Tanah()
    {
        var rig = player.GetComponentInChildren<Animator>();
        Assert.IsNotNull(rig, "Animator mannequin tidak ada");
        Assert.IsTrue(rig.isHuman, "Foot IK memerlukan Avatar Humanoid");
        var left = rig.GetBoneTransform(HumanBodyBones.LeftFoot);
        var right = rig.GetBoneTransform(HumanBodyBones.RightFoot);
        Assert.IsNotNull(left, "bone LeftFoot tidak ditemukan");
        Assert.IsNotNull(right, "bone RightFoot tidak ditemukan");

        player.MoveInput = new Vector2(0f, 0.5f);
        int contactFrames = 0;
        float closestGap = float.MaxValue;
        float lowestGap = float.MaxValue;
        for (int i = 0; i < 120; i++)
        {
            if (i == 60) player.MoveInput = new Vector2(0.5f, 0.5f); // uji pijakan saat membelok
            yield return null;
            float leftGap = FootGroundGap(left);
            float rightGap = FootGroundGap(right);
            float plantedGap = Mathf.Min(leftGap, rightGap);
            closestGap = Mathf.Min(closestGap, plantedGap);
            lowestGap = Mathf.Min(lowestGap, Mathf.Min(leftGap, rightGap));
            if (plantedGap >= -0.25f && plantedGap <= 0.35f) contactFrames++;
        }
        player.MoveInput = Vector2.zero;
        Debug.Log($"[SIM] foot IK: kontak={contactFrames}/120, gap-terdekat={closestGap:F3} m, gap-min={lowestGap:F3} m, clip={Clip()}");
        Assert.GreaterOrEqual(contactFrames, 50, "telapak tidak cukup sering dekat permukaan selama berjalan");
        Assert.GreaterOrEqual(lowestGap, -0.35f, "bone kaki menembus terrain terlalu jauh");
        Shot("06_foot_ik");
    }

    [UnityTest]
    public IEnumerator Sim_Rumput_Menghasilkan_Mesh_Yang_Bisa_Dirender()
    {
        var field = Object.FindObjectOfType<GrassField>();
        Assert.IsNotNull(field, "GrassField tidak dibuat oleh bootstrap");

        MeshFilter[] filters = field.GetComponentsInChildren<MeshFilter>();
        float deadline = Time.time + 12f;
        while (Time.time < deadline && (field.PendingTileCount > 0 || !HasGrassGeometry(filters)))
        {
            yield return null;
            filters = field.GetComponentsInChildren<MeshFilter>();
        }
        filters = field.GetComponentsInChildren<MeshFilter>();

        int meshCount = 0, triangleCount = 0, rendererCount = 0;
        foreach (var filter in filters)
        {
            if (filter == null || filter.sharedMesh == null || filter.sharedMesh.vertexCount == 0) continue;
            meshCount++;
            triangleCount += filter.sharedMesh.triangles.Length / 3;
            var renderer = filter.GetComponent<MeshRenderer>();
            if (renderer != null && renderer.enabled && renderer.sharedMaterial != null
                && renderer.sharedMaterial.shader != null
                && renderer.sharedMaterial.shader.name == "UAL2/GrassBlade") rendererCount++;
        }

        Debug.Log($"[SIM] grass: built={field.BuiltTileCount}, pending={field.PendingTileCount}, rendered={field.RenderedTileCount}, mesh={meshCount}, triangles={triangleCount}, renderer-shader={rendererCount}");
        Assert.AreEqual(0, field.PendingTileCount, "seluruh area 200 m belum selesai di-stream");
        Assert.Greater(field.BuiltTileCount, 300, "tile rumput tidak mencakup area pulau 200 m");
        Assert.Greater(meshCount, 0, "tile rumput tidak menghasilkan mesh");
        Assert.Greater(triangleCount, 0, "mesh rumput kosong");
        Assert.Greater(rendererCount, 0, "mesh rumput tidak punya renderer/shader GrassBlade");
        Shot("07_rumput_render");
    }

    [UnityTest]
    public IEnumerator Sim_Lokomosi_Walk_Jog_Sprint_Sesuai_Kecepatan()
    {
        var library = new AnimLibrary();
        var walk = library.Find("UAL1_Walk_Loop") ?? library.Find("Walk_Fwd_Loop");
        var jog = library.Find("UAL1_Jog_Loop");
        var sprint = library.Find("UAL1_Sprint_Loop");
        Assert.IsNotNull(walk, "clip Walk tidak tersedia");

        player.MoveInput = new Vector2(0f, 0.45f);
        yield return new WaitForSeconds(0.7f);
        Debug.Log("[SIM] tier walk clip=" + Clip() + ", ik=" + panim.CurrentApplyFootIK
            + ", rate=" + panim.CurrentPlaybackSpeed.ToString("F2"));
        Assert.AreSame(walk, panim.CurrentClip, "kecepatan rendah harus memilih Walk");
        Assert.IsTrue(panim.CurrentApplyFootIK, "Walk seharusnya tetap memakai Foot IK");

        player.MoveInput = new Vector2(0f, 0.8f);
        yield return new WaitForSeconds(0.7f);
        Debug.Log("[SIM] tier jog clip=" + Clip() + ", ik=" + panim.CurrentApplyFootIK
            + ", rate=" + panim.CurrentPlaybackSpeed.ToString("F2"));
        if (jog != null)
        {
            Assert.AreSame(jog, panim.CurrentClip, "kecepatan menengah harus memilih Jog");
            Assert.IsFalse(panim.CurrentApplyFootIK, "Jog tidak boleh memakai Foot IK agar stride mocap tidak terdistorsi");
            Assert.That(panim.CurrentPlaybackSpeed, Is.EqualTo(1f).Within(0.12f),
                "Jog 4 m/s harus mendekati playback asli 1x");
        }
        else Debug.LogWarning("[SIM] UAL1 Jog belum diekstrak; tahap Jog dilewati.");

        player.SetSprint(true);
        player.MoveInput = Vector2.up;
        yield return new WaitForSeconds(0.7f);
        Debug.Log("[SIM] tier sprint clip=" + Clip() + ", ik=" + panim.CurrentApplyFootIK
            + ", rate=" + panim.CurrentPlaybackSpeed.ToString("F2"));
        if (sprint != null)
        {
            Assert.AreSame(sprint, panim.CurrentClip, "sprint harus memilih Sprint_Loop");
            Assert.IsFalse(panim.CurrentApplyFootIK, "Sprint tidak boleh memakai Foot IK");
            Assert.That(panim.CurrentPlaybackSpeed, Is.EqualTo(1.25f).Within(0.12f),
                "sprint 6.25 m/s harus memutar Sprint_Loop mendekati 1.25x");
        }
        else Debug.LogWarning("[SIM] UAL1 Sprint belum diekstrak; tahap Sprint dilewati.");

        // LARI adalah toggle; mematikannya saat analog tetap penuh harus
        // beralih dari Sprint ke Jog/Walk, bukan tertahan di clip Sprint.
        player.SetSprint(false);
        yield return new WaitForSeconds(0.35f);
        Debug.Log("[SIM] sprint dilepas clip=" + Clip());
        if (sprint != null)
            Assert.AreNotSame(sprint, panim.CurrentClip, "clip Sprint tetap aktif setelah toggle LARI dimatikan");
        if (jog != null)
        {
            Assert.AreSame(jog, panim.CurrentClip, "setelah sprint dilepas, kecepatan normal harus memilih Jog");
            Assert.That(panim.CurrentPlaybackSpeed, Is.EqualTo(1.25f).Within(0.12f),
                "lari normal 5 m/s harus memakai cadence referensi Godot 1.25x");
        }

        player.MoveInput = Vector2.zero;
        yield return new WaitForSeconds(0.7f);
        Shot("08_lokomosi_bertingkat");
    }

    [UnityTest]
    public IEnumerator Sim_Semua_Clip_Library_Bisa_Dimainkan()
    {
        var library = new AnimLibrary();
        Assert.Greater(library.Count, 0, "library animasi kosong");
        int played = 0;
        for (int i = 0; i < library.Keys.Count; i++)
        {
            string key = library.Keys[i];
            var expected = library.Find(key);
            Assert.IsNotNull(expected, "clip hilang dari dictionary: " + key);
            player.PlayLibraryClip(key);
            yield return null;
            Assert.AreSame(expected, panim.CurrentClip, "clip tidak masuk ke PlayableGraph: " + key);
            played++;
        }
        Debug.Log("[SIM] seluruh clip diuji lewat PlayerController.PlayLibraryClip: " + played);
        Shot("09_semua_animasi");
        player.MoveInput = Vector2.zero;
    }

    static bool HasGrassGeometry(MeshFilter[] filters)
    {
        if (filters == null) return false;
        foreach (var filter in filters)
            if (filter != null && filter.sharedMesh != null && filter.sharedMesh.vertexCount > 0) return true;
        return false;
    }
}
