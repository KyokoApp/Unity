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
        GameBootstrap.SkipUpdater = true;   // jangan sentuh jaringan saat tes
        bootGO = new GameObject("Boot");
        bootGO.AddComponent<GameBootstrap>();
        yield return null;
        player = Object.FindObjectOfType<PlayerController>();
        Assert.IsNotNull(player, "PlayerController tidak ditemukan setelah bootstrap");
        panim = player.GetComponent<PlayerAnimator>();
        yield return new WaitForSeconds(1.0f);   // tile rumput/hutan pertama
        Shot("00_plaza_spawn");
    }

    [UnityTearDown]
    public IEnumerator TearDown()
    {
        Object.Destroy(bootGO);
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
}
