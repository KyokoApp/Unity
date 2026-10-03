using System.Collections;
using System.IO;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;

/// <summary>Smoke tests PlayMode untuk room baru, kontrol first-person, dan daur ulang lorong.</summary>
public class SimTests
{
    GameObject bootGO;
    FirstPersonRoomController player;
    EndlessRoom room;

    [UnitySetUp]
    public IEnumerator SetUp()
    {
        bootGO = new GameObject("Room test bootstrap");
        bootGO.AddComponent<GameBootstrap>();
        yield return null;

        player = Object.FindObjectOfType<FirstPersonRoomController>();
        room = Object.FindObjectOfType<EndlessRoom>();
        Assert.IsNotNull(player, "First-person rig tidak dibuat oleh bootstrap");
        Assert.IsNotNull(room, "Lorong room tidak dibuat oleh bootstrap");
        Assert.IsNotNull(player.ViewCamera, "Kamera first-person tidak ditemukan");
        Shot("00_room_spawn");
    }

    [UnityTearDown]
    public IEnumerator TearDown()
    {
        if (bootGO != null) Object.Destroy(bootGO);
        yield return null;
    }

    void Shot(string name)
    {
        Directory.CreateDirectory("build/simshots");
        ScreenCapture.CaptureScreenshot("build/simshots/" + name + ".png");
    }

    [UnityTest]
    public IEnumerator Room_TakBerujung_Dan_Tanpa_Model_Karakter()
    {
        Assert.IsTrue(room.IsBuilt);
        Assert.AreEqual(EndlessRoom.SegmentCount, room.ActiveSegmentCount);
        Assert.Greater(room.WaterWidth, 25f, "Air harus terbentang luas di sisi kanan lorong");
        Assert.IsTrue(player.ViewCamera.transform.IsChildOf(player.transform),
            "Kamera harus menjadi kamera first-person pada rig pemain");
        Assert.AreEqual(0, player.GetComponentsInChildren<Renderer>(true).Length,
            "Tidak boleh ada mesh/avatar terlihat pada kamera first-person");
        Assert.That(player.transform.position.x, Is.EqualTo(EndlessRoom.SpawnX).Within(0.05f));
        Shot("01_room_first_person");
        yield return null;
    }

    [UnityTest]
    public IEnumerator Berjalan_Melewati_Modul_Dunia_Tetap_Tersambung()
    {
        float travelledBefore = player.DistanceTravelled;
        player.MoveInput = new Vector2(0f, 1f);
        yield return new WaitForSeconds(8f);
        player.MoveInput = Vector2.zero;
        yield return new WaitForSeconds(0.25f);

        Debug.Log("[SIM ROOM] jarak=" + (player.DistanceTravelled - travelledBefore).ToString("F2")
            + " m, daur ulang=" + room.WrapCount + ", z lokal=" + player.transform.position.z.ToString("F2"));
        Assert.Greater(player.DistanceTravelled - travelledBefore, 8f,
            "Joystick harus membuat pemain berjalan maju");
        Assert.Greater(room.WrapCount, 0, "Modul lorong harus didaur ulang setelah dilewati");
        Assert.That(Mathf.Abs(player.transform.position.z), Is.LessThanOrEqualTo(12.1f),
            "Origin harus tetap dekat kamera agar perjalanan jauh tidak kehilangan presisi");
        Assert.That(player.transform.position.y, Is.InRange(-0.12f, 0.20f),
            "Kamera tidak boleh jatuh menembus lantai walkway");
        Shot("02_room_after_walk");
    }

    [UnityTest]
    public IEnumerator Pemain_Tetap_Di_Jalur_Kiri_Dekat_Tepi_Air()
    {
        player.MoveInput = new Vector2(1f, 0f);
        yield return new WaitForSeconds(2.5f);
        player.MoveInput = Vector2.zero;

        Assert.That(player.transform.position.x, Is.InRange(EndlessRoom.MinWalkX - 0.02f,
            EndlessRoom.MaxWalkX + 0.02f), "Pemain tidak boleh masuk ke permukaan air");
        Assert.That(player.transform.position.x, Is.EqualTo(EndlessRoom.MaxWalkX).Within(0.04f),
            "Pemain harus bisa merapat ke sisi tepi air");
        Shot("03_room_edge_walk");
        yield return null;
    }

    [UnityTest]
    public IEnumerator Swipe_Memutar_Pandangan_Seperti_FirstPerson()
    {
        float startYaw = player.Yaw;
        player.AddLookPixels(new Vector2(Screen.height * 0.45f, -Screen.height * 0.30f));
        yield return null;

        Assert.Greater(player.Yaw, startYaw + 10f, "Swipe horizontal harus memutar kamera");
        Assert.That(player.Pitch, Is.InRange(-78f, 78f), "Pitch kamera harus dibatasi agar tidak terbalik");
        Assert.Greater(player.Pitch, 0f, "Swipe ke atas harus mengangkat pandangan");
        Shot("04_room_look");
    }
}
