using UnityEngine;
using UnityEngine.UI;

/// <summary>UI sentuh minimal untuk HP: joystick berjalan di kiri, swipe-look di kanan.</summary>
public class GameUI : MonoBehaviour
{
    FirstPersonRoomController player;
    VirtualJoystick joystick;
    Text statusText;
    float statusUntil;
    bool joystickWasHeld;

    static readonly Color Ink = new Color(0.79f, 0.88f, 0.92f, 0.88f);
    static readonly Color MutedInk = new Color(0.56f, 0.72f, 0.77f, 0.68f);

    public void Init(FirstPersonRoomController controller)
    {
        player = controller;
        Build();
    }

    void Update()
    {
        if (player != null && joystick != null)
        {
            if (joystick.IsHeld)
            {
                player.MoveInput = joystick.Value;
                joystickWasHeld = true;
            }
            else if (joystickWasHeld)
            {
                player.MoveInput = Vector2.zero;
                joystickWasHeld = false;
            }
        }

        if (statusText != null && statusText.enabled && Time.unscaledTime > statusUntil)
            statusText.enabled = false;
    }

    public void SetStatus(string message, float seconds)
    {
        if (statusText == null) return;
        statusText.text = message;
        statusText.enabled = true;
        statusUntil = Time.unscaledTime + seconds;
    }

    void Build()
    {
        var canvasGO = new GameObject("Canvas", typeof(Canvas), typeof(CanvasScaler), typeof(GraphicRaycaster));
        canvasGO.transform.SetParent(transform, false);
        var canvas = canvasGO.GetComponent<Canvas>();
        canvas.renderMode = RenderMode.ScreenSpaceOverlay;
        canvas.sortingOrder = 10;

        var scaler = canvasGO.GetComponent<CanvasScaler>();
        scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
        scaler.referenceResolution = new Vector2(1920f, 1080f);
        scaler.matchWidthOrHeight = 1f;

        var safe = UiKit.NewRect("SafeArea", canvasGO.transform);
        UiKit.Stretch(safe, Vector2.zero, Vector2.one, Vector4.zero);
        safe.gameObject.AddComponent<SafeAreaFitter>();

        // Pad transparan tetap menangkap sentuhan untuk melihat; joystick yang
        // dibuat setelahnya berada di atas pad dan aman dipakai multi-touch.
        var lookPad = UiKit.NewImage("LookPad", safe, null, new Color(0f, 0f, 0f, 0.001f));
        UiKit.Stretch((RectTransform)lookPad.transform, new Vector2(0.32f, 0f), Vector2.one, Vector4.zero);
        lookPad.raycastTarget = true;
        var look = lookPad.gameObject.AddComponent<TouchLookPad>();
        look.player = player;

        BuildJoystick(safe);
        BuildHud(safe);

        statusText = UiKit.NewText("Status", safe, string.Empty, 24, Ink);
        UiKit.Anchor((RectTransform)statusText.transform, new Vector2(0.5f, 1f),
            new Vector2(0f, -138f), new Vector2(1100f, 44f));
        statusText.enabled = false;
    }

    void BuildJoystick(RectTransform parent)
    {
        var zone = UiKit.NewImage("MoveJoystickZone", parent, null, new Color(0f, 0f, 0f, 0.001f));
        UiKit.Anchor((RectTransform)zone.transform, Vector2.zero, new Vector2(245f, 230f),
            new Vector2(450f, 450f));
        zone.raycastTarget = true;

        var ring = UiKit.NewImage("JoystickRing", zone.transform, UiKit.Ring(),
            new Color(0.44f, 0.68f, 0.74f, 0.42f));
        UiKit.Anchor((RectTransform)ring.transform, new Vector2(0.5f, 0.5f), Vector2.zero,
            new Vector2(258f, 258f));
        ring.raycastTarget = false;

        var baseFill = UiKit.NewImage("JoystickFill", zone.transform, UiKit.Circle(),
            new Color(0.09f, 0.18f, 0.22f, 0.16f));
        UiKit.Anchor((RectTransform)baseFill.transform, new Vector2(0.5f, 0.5f), Vector2.zero,
            new Vector2(238f, 238f));
        baseFill.raycastTarget = false;

        var knob = UiKit.NewImage("JoystickKnob", zone.transform, UiKit.Circle(),
            new Color(0.62f, 0.79f, 0.83f, 0.56f));
        UiKit.Anchor((RectTransform)knob.transform, new Vector2(0.5f, 0.5f), Vector2.zero,
            new Vector2(92f, 92f));
        knob.raycastTarget = false;

        joystick = zone.gameObject.AddComponent<VirtualJoystick>();
        joystick.knob = (RectTransform)knob.transform;
        joystick.radius = 94f;
    }

    void BuildHud(RectTransform parent)
    {
        var title = UiKit.NewText("RoomTitle", parent, "POOLROOMS", 25, Ink, TextAnchor.MiddleLeft);
        UiKit.Anchor((RectTransform)title.transform, new Vector2(0f, 1f),
            new Vector2(142f, -68f), new Vector2(310f, 38f));

        var subtitle = UiKit.NewText("RoomSubtitle", parent, "LIMINAL AQUATIC WING", 16, MutedInk,
            TextAnchor.MiddleLeft, FontStyle.Normal);
        UiKit.Anchor((RectTransform)subtitle.transform, new Vector2(0f, 1f),
            new Vector2(147f, -105f), new Vector2(310f, 30f));

        var rule = UiKit.NewImage("TitleRule", parent, null, new Color(0.22f, 0.30f, 0.32f, 0.30f));
        UiKit.Anchor((RectTransform)rule.transform, new Vector2(0f, 1f),
            new Vector2(156f, -128f), new Vector2(250f, 2f));
        rule.raycastTarget = false;

        var hint = UiKit.NewText("ControlHint", parent,
            "Joystick kiri: jelajahi     •     Geser sisi kanan: lihat sekeliling",
            21, new Color(0.75f, 0.85f, 0.89f, 0.72f), TextAnchor.MiddleCenter, FontStyle.Normal);
        UiKit.Anchor((RectTransform)hint.transform, new Vector2(0.5f, 0f),
            new Vector2(0f, 36f), new Vector2(1120f, 42f));
        hint.gameObject.AddComponent<FadeOutHint>();
    }
}
