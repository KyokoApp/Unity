using System.Collections;
using System.IO;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;

/// <summary>Smoke tests for the mobile PoolRooms environment, first-person controls, and room recycling.</summary>
public class SimTests
{
    GameObject bootGO;
    FirstPersonRoomController player;
    PoolRoomsEnvironment environment;

    [UnitySetUp]
    public IEnumerator SetUp()
    {
        bootGO = new GameObject("PoolRooms test bootstrap");
        bootGO.AddComponent<GameBootstrap>();
        yield return null;

        player = Object.FindObjectOfType<FirstPersonRoomController>();
        environment = Object.FindObjectOfType<PoolRoomsEnvironment>();
        Assert.IsNotNull(player, "First-person rig was not created by bootstrap");
        Assert.IsNotNull(environment, "PoolRooms environment was not created by bootstrap");
        Assert.IsNotNull(player.ViewCamera, "First-person camera was not found");
        Shot("00_poolrooms_spawn");
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
    public IEnumerator PoolRooms_Has_Connected_Room_Types_And_Clear_Pool()
    {
        Assert.IsTrue(environment.IsBuilt);
        Assert.AreEqual(PoolRoomsEnvironment.SegmentCount, environment.ActiveSegmentCount);
        Assert.GreaterOrEqual(environment.ActivePoolCount, 2,
            "Main pool and atrium rooms should both contain water");

        bool hasLockerRoom = false;
        bool hasShowerRoom = false;
        for (int i = 0; i < environment.transform.childCount; i++)
        {
            string roomName = environment.transform.GetChild(i).name;
            hasLockerRoom |= roomName.Contains("LockerRoom");
            hasShowerRoom |= roomName.Contains("ShowerRoom");
        }
        Assert.IsTrue(hasLockerRoom, "Connected layout should include a locker room");
        Assert.IsTrue(hasShowerRoom, "Connected layout should include a shower room");

        MeshRenderer[] renderers = environment.GetComponentsInChildren<MeshRenderer>(true);
        MeshRenderer waterSurface = null;
        bool hasSubmergedFloor = false;
        bool hasTiledRoomFloor = false;
        for (int i = 0; i < renderers.Length; i++)
        {
            if (renderers[i].gameObject.name == "Pool water surface")
                waterSurface = renderers[i];
            if (renderers[i].gameObject.name == "Submerged tiled pool floor")
                hasSubmergedFloor |= renderers[i].GetComponent<MeshFilter>().sharedMesh.vertexCount > 0;
            if (renderers[i].gameObject.name == "Room floor tiles")
                hasTiledRoomFloor |= renderers[i].GetComponent<MeshFilter>().sharedMesh.vertexCount > 0;
        }
        Assert.IsNotNull(waterSurface, "Transparent pool surface must be created");
        Assert.GreaterOrEqual(waterSurface.sharedMaterial.renderQueue, 3000,
            "Pool surface must use the transparent render queue");
        Assert.IsTrue(hasSubmergedFloor, "Tiled basin floor should be visible through shallow water");
        Assert.IsTrue(hasTiledRoomFloor, "PoolRooms should have a tiled interior floor");

        Assert.IsTrue(player.ViewCamera.transform.IsChildOf(player.transform),
            "Camera must remain attached to the first-person rig");
        Assert.AreEqual(0, player.GetComponentsInChildren<Renderer>(true).Length,
            "No visible avatar/body should be attached to the player");
        Assert.That(player.transform.position.x,
            Is.EqualTo(PoolRoomsEnvironment.SpawnX).Within(0.05f));
        Shot("01_poolrooms_first_person");
        yield return null;
    }

    [UnityTest]
    public IEnumerator Walk_Through_Connected_Rooms_And_Recycle_Modules()
    {
        float travelledBefore = player.DistanceTravelled;
        player.MoveInput = new Vector2(0f, 1f);
        yield return new WaitForSeconds(8f);
        player.MoveInput = Vector2.zero;
        yield return new WaitForSeconds(0.25f);

        Debug.Log("[SIM POOLROOMS] distance="
            + (player.DistanceTravelled - travelledBefore).ToString("F2")
            + " m, recycled=" + environment.WrapCount
            + ", local z=" + player.transform.position.z.ToString("F2"));
        Assert.Greater(player.DistanceTravelled - travelledBefore, 8f,
            "Mobile joystick input should move the player");
        Assert.Greater(environment.WrapCount, 0,
            "Connected room modules should recycle after the player walks through them");
        Assert.That(Mathf.Abs(player.transform.position.z), Is.LessThanOrEqualTo(12.1f),
            "World origin should remain close to the player during long walks");
        Assert.That(player.transform.position.y, Is.InRange(-0.12f, 0.20f),
            "Player should remain on the walkable room floor");
        Shot("02_poolrooms_after_walk");
    }

    [UnityTest]
    public IEnumerator Player_Remains_Inside_The_Pool_Room()
    {
        Vector3 p = player.transform.position;
        p.x = PoolRoomsEnvironment.MaxWalkX - 0.20f;
        p.y = 0.03f;
        player.transform.position = p;
        player.MoveInput = new Vector2(1f, 0f);
        yield return new WaitForSeconds(2.5f);
        player.MoveInput = Vector2.zero;

        Assert.That(player.transform.position.x, Is.InRange(PoolRoomsEnvironment.MinWalkX - 0.02f,
            PoolRoomsEnvironment.MaxWalkX + 0.02f), "Player should stay within room bounds");
        Assert.That(player.transform.position.x,
            Is.EqualTo(PoolRoomsEnvironment.MaxWalkX).Within(0.04f),
            "The room boundary should stop the player before the outer wall");
        Shot("03_poolrooms_bounds");
        yield return null;
    }

    [UnityTest]
    public IEnumerator Swipe_Rotates_FirstPerson_View()
    {
        float startYaw = player.Yaw;
        player.AddLookPixels(new Vector2(Screen.height * 0.45f, -Screen.height * 0.30f));
        yield return null;

        Assert.Greater(player.Yaw, startYaw + 10f, "Horizontal swipe should rotate the camera");
        Assert.That(player.Pitch, Is.InRange(-78f, 78f), "Camera pitch must not flip over");
        Assert.Greater(player.Pitch, 0f, "Upward swipe should raise the view");
        Shot("04_poolrooms_look");
    }
}
