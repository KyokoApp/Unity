using System;
using UnityEngine;
using UnityEngine.UI;

/// <summary>
/// Membangun seluruh UI sentuh saat runtime (landscape Android):
///  - Analog virtual di kiri-bawah.
///  - LOMPAT (besar) kanan-bawah, SERANG & SLIDE di sebelahnya, LARI (toggle) di atasnya.
///  - Tombol ANIMASI membuka panel scroll berisi SEMUA clip UAL2.
///  - Tombol GANTI MODEL menukar mannequin UAL2 <-> Mannequin F.
///  - Pad transparan sisi kanan untuk memutar kamera.
/// </summary>
public class GameUI : MonoBehaviour
{
    PlayerController player;
    AnimLibrary lib;
    OrbitCamera cam;

    VirtualJoystick joystick;
    GameObject animPanel;
    PressButton sprintBtn;
    Text modelLabel;
    Text statusText;
    float statusUntil;
    PressButton appUpdateBtn;
    Text appUpdateLabel;
    Action appUpdateAction;
    bool sprintOn;

    static readonly Color BtnDark = new Color(0.07f, 0.08f, 0.11f, 0.55f);
    static readonly Color BtnAccent = new Color(0.22f, 0.52f, 0.95f, 0.75f);
    static readonly Color BtnGreen = new Color(0.22f, 0.75f, 0.40f, 0.85f);
    static readonly Color PanelBg = new Color(0.06f, 0.07f, 0.10f, 0.93f);

    public void Init(PlayerController p, AnimLibrary library, OrbitCamera orbit)
    {
        player = p;
        lib = library;
        cam = orbit;
        Build();
    }

    void Update()
    {
        if (player != null && joystick != null)
            player.MoveInput = joystick.Value;

        if (statusText != null && statusText.enabled && Time.unscaledTime > statusUntil)
            statusText.enabled = false;
    }

    /// <summary>Tampilkan pesan status (update konten, MOTD, dsb) di tengah-atas layar.</summary>
    public void SetStatus(string msg, float seconds)
    {
        if (statusText == null) return;
        statusText.text = msg;
        statusText.enabled = true;
        statusUntil = Time.unscaledTime + seconds;
    }

    public void ShowAppUpdate(string version, Action downloadAndInstall)
    {
        appUpdateAction = downloadAndInstall;
        if (appUpdateBtn == null) return;
        appUpdateLabel.text = "UNDUH & PASANG UPDATE  v" + version;
        appUpdateBtn.gameObject.SetActive(true);
    }

    public void SetAppUpdateProgress(float progress)
    {
        if (appUpdateLabel != null)
            appUpdateLabel.text = "MENGUNDUH UPDATE... " + Mathf.RoundToInt(Mathf.Clamp01(progress) * 100f) + "%";
    }

    public void SetAppUpdateMessage(string message)
    {
        if (appUpdateLabel != null) appUpdateLabel.text = message;
    }

    void BeginAppUpdate()
    {
        if (appUpdateAction != null) appUpdateAction();
    }

    // =====================================================================

    void Build()
    {
        // ---- Canvas ----
        var canvasGO = new GameObject("Canvas", typeof(Canvas), typeof(CanvasScaler), typeof(GraphicRaycaster));
        canvasGO.transform.SetParent(transform, false);
        var canvas = canvasGO.GetComponent<Canvas>();
        canvas.renderMode = RenderMode.ScreenSpaceOverlay;
        var scaler = canvasGO.GetComponent<CanvasScaler>();
        scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
        scaler.referenceResolution = new Vector2(1920, 1080);
        scaler.matchWidthOrHeight = 1f; // patok ke tinggi layar (landscape)

        // ---- Root safe area ----
        var safe = UiKit.NewRect("SafeArea", canvasGO.transform);
        UiKit.Stretch(safe, Vector2.zero, Vector2.one, Vector4.zero);
        safe.gameObject.AddComponent<SafeAreaFitter>();

        // ---- Pad kamera (paling bawah dalam urutan raycast) ----
        var pad = UiKit.NewImage("LookPad", safe, null, new Color(0, 0, 0, 0f));
        UiKit.Stretch((RectTransform)pad.transform, new Vector2(0.38f, 0f), Vector2.one, Vector4.zero);
        pad.raycastTarget = true;
        var look = pad.gameObject.AddComponent<TouchLookPad>();
        look.cam = cam;

        BuildJoystick(safe);
        BuildActionButtons(safe);
        BuildTopBar(safe);
        BuildAnimPanel(safe);

        // ---- Status updater / MOTD (tengah-atas) ----
        statusText = UiKit.NewText("Status", safe, "", 26, new Color(1f, 0.95f, 0.6f, 0.95f));
        UiKit.Anchor((RectTransform)statusText.transform, new Vector2(0.5f, 1f), new Vector2(0, -60), new Vector2(1200, 44));
        statusText.enabled = false;

        // ---- Petunjuk ----
        var hint = UiKit.NewText("Hint", safe,
            "Analog kiri: jalan / lari   •   Geser layar kanan: kamera   •   ANIMASI: semua gerakan UAL2",
            30, new Color(1f, 1f, 1f, 0.85f));
        UiKit.Anchor((RectTransform)hint.transform, new Vector2(0.5f, 0f), new Vector2(0, 70), new Vector2(1600, 60));
        hint.gameObject.AddComponent<FadeOutHint>();
    }

    // =====================================================================

    void BuildJoystick(RectTransform parent)
    {
        // Zona sentuh analog: kiri-bawah, lebih besar dari visual agar mudah dijangkau jempol.
        var zone = UiKit.NewImage("JoystickZone", parent, null, new Color(0, 0, 0, 0f));
        UiKit.Anchor((RectTransform)zone.transform, new Vector2(0f, 0f), new Vector2(330, 310), new Vector2(560, 560));
        zone.raycastTarget = true;

        var baseImg = UiKit.NewImage("Base", zone.transform, UiKit.Ring(), new Color(1f, 1f, 1f, 0.35f));
        UiKit.Anchor((RectTransform)baseImg.transform, new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(330, 330));
        baseImg.raycastTarget = false;

        var baseFill = UiKit.NewImage("BaseFill", zone.transform, UiKit.Circle(), new Color(0.05f, 0.06f, 0.09f, 0.30f));
        UiKit.Anchor((RectTransform)baseFill.transform, new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(310, 310));
        baseFill.raycastTarget = false;

        var knob = UiKit.NewImage("Knob", zone.transform, UiKit.Circle(), new Color(1f, 1f, 1f, 0.75f));
        UiKit.Anchor((RectTransform)knob.transform, new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(140, 140));
        knob.raycastTarget = false;

        joystick = zone.gameObject.AddComponent<VirtualJoystick>();
        joystick.knob = (RectTransform)knob.transform;
        joystick.radius = 120f;
    }

    void BuildActionButtons(RectTransform parent)
    {
        // LOMPAT — tombol terbesar, pas di jempol kanan.
        MakeCircleButton(parent, "LOMPAT", new Vector2(1f, 0f), new Vector2(-250, 260), 240, BtnAccent,
            () => player.OnJump(), null, 40);

        // SERANG — kiri-atas dari LOMPAT.
        MakeCircleButton(parent, "SERANG", new Vector2(1f, 0f), new Vector2(-510, 350), 185, BtnDark,
            () => player.OnAttack(), null, 32);

        // SLIDE — kiri-bawah dari LOMPAT.
        MakeCircleButton(parent, "SLIDE", new Vector2(1f, 0f), new Vector2(-530, 155), 165, BtnDark,
            () => player.OnSlide(), null, 30);

        // LARI — toggle, di atas LOMPAT.
        sprintBtn = MakeCircleButton(parent, "LARI", new Vector2(1f, 0f), new Vector2(-240, 520), 160, BtnDark,
            ToggleSprint, null, 30);
    }

    void ToggleSprint()
    {
        sprintOn = !sprintOn;
        player.SetSprint(sprintOn);
        sprintBtn.SetBaseColor(sprintOn ? BtnGreen : BtnDark);
    }

    void BuildTopBar(RectTransform parent)
    {
        // Judul + kredit (kiri-atas).
        var title = UiKit.NewText("Title", parent, "Arpg", 34, Color.white, TextAnchor.UpperLeft);
        UiKit.Anchor((RectTransform)title.transform, new Vector2(0f, 1f), new Vector2(250, -55), new Vector2(460, 50));
        var credit = UiKit.NewText("Credit", parent, "Animasi: Universal Animation Library 2 — Quaternius (CC0)",
            22, new Color(1f, 1f, 1f, 0.65f), TextAnchor.UpperLeft, FontStyle.Normal);
        UiKit.Anchor((RectTransform)credit.transform, new Vector2(0f, 1f), new Vector2(330, -100), new Vector2(620, 40));

        // Tombol hanya muncul jika release GitHub menyediakan APK versi lebih baru.
        appUpdateBtn = MakeRectButton(parent, "APP_UPDATE", new Vector2(0f, 1f), new Vector2(235, -177), new Vector2(430, 64),
            BtnAccent, BeginAppUpdate, 21);
        appUpdateLabel = appUpdateBtn.GetComponentInChildren<Text>();
        appUpdateLabel.text = "UNDUH & PASANG UPDATE";
        appUpdateBtn.gameObject.SetActive(false);

        // GANTI MODEL (kanan-atas, sebelah kiri tombol ANIMASI).
        var modelBtn = MakeRectButton(parent, "GANTI MODEL", new Vector2(1f, 1f), new Vector2(-480, -75), new Vector2(280, 90),
            BtnDark, () =>
            {
                player.ToggleModel();
                if (modelLabel != null) modelLabel.text = "MODEL: " + player.CurrentModelName.ToUpper();
            }, 28);
        modelLabel = UiKit.NewText("ModelLabel", parent, "MODEL: UAL2", 22, new Color(1f, 1f, 1f, 0.7f));
        UiKit.Anchor((RectTransform)modelLabel.transform, new Vector2(1f, 1f), new Vector2(-480, -140), new Vector2(280, 36));

        // ANIMASI (kanan-atas).
        MakeRectButton(parent, "ANIMASI", new Vector2(1f, 1f), new Vector2(-180, -75), new Vector2(260, 90),
            BtnAccent, ToggleAnimPanel, 30);
    }

    void ToggleAnimPanel()
    {
        if (animPanel != null) animPanel.SetActive(!animPanel.activeSelf);
    }

    void BuildAnimPanel(RectTransform parent)
    {
        var panel = UiKit.NewImage("AnimPanel", parent, UiKit.Rounded(), PanelBg);
        var prt = (RectTransform)panel.transform;
        prt.anchorMin = new Vector2(1f, 0f);
        prt.anchorMax = new Vector2(1f, 1f);
        prt.pivot = new Vector2(1f, 0.5f);
        prt.offsetMin = new Vector2(-680f, 20f);
        prt.offsetMax = new Vector2(-20f, -140f);
        animPanel = panel.gameObject;

        var header = UiKit.NewText("Header", prt, "SEMUA ANIMASI UAL2 (" + lib.Count + ")", 30, Color.white);
        UiKit.Anchor((RectTransform)header.transform, new Vector2(0.5f, 1f), new Vector2(0, -45), new Vector2(600, 50));

        MakeRectButton(prt, "X", new Vector2(1f, 1f), new Vector2(-50, -48), new Vector2(70, 70),
            new Color(0.8f, 0.25f, 0.25f, 0.9f), ToggleAnimPanel, 32);

        // ---- ScrollRect ----
        var viewport = UiKit.NewImage("Viewport", prt, null, new Color(0, 0, 0, 0.01f));
        var vrt = (RectTransform)viewport.transform;
        UiKit.Stretch(vrt, Vector2.zero, Vector2.one, new Vector4(16, 16, 16, 95));
        viewport.gameObject.AddComponent<RectMask2D>();

        var content = UiKit.NewRect("Content", vrt);
        content.anchorMin = new Vector2(0f, 1f);
        content.anchorMax = new Vector2(1f, 1f);
        content.pivot = new Vector2(0.5f, 1f);
        content.offsetMin = Vector2.zero;
        content.offsetMax = Vector2.zero;

        var grid = content.gameObject.AddComponent<GridLayoutGroup>();
        grid.cellSize = new Vector2(302, 76);
        grid.spacing = new Vector2(12, 12);
        grid.padding = new RectOffset(6, 6, 6, 6);
        grid.constraint = GridLayoutGroup.Constraint.FixedColumnCount;
        grid.constraintCount = 2;
        grid.childAlignment = TextAnchor.UpperCenter;

        var fitter = content.gameObject.AddComponent<ContentSizeFitter>();
        fitter.verticalFit = ContentSizeFitter.FitMode.PreferredSize;

        var scroll = animPanel.AddComponent<ScrollRect>();
        scroll.viewport = vrt;
        scroll.content = content;
        scroll.horizontal = false;
        scroll.vertical = true;
        scroll.movementType = ScrollRect.MovementType.Elastic;
        scroll.scrollSensitivity = 30f;
        scroll.decelerationRate = 0.12f;

        // ---- Tombol untuk SETIAP animasi dalam library ----
        foreach (var key in lib.Keys)
        {
            string k = key; // capture
            var img = UiKit.NewImage("Anim_" + k, content, UiKit.Rounded(), new Color(0.16f, 0.19f, 0.26f, 0.95f));
            var btn = img.gameObject.AddComponent<Button>();
            btn.targetGraphic = img;
            btn.onClick.AddListener(() => player.PlayLibraryClip(k));
            var label = UiKit.NewText("Label", img.transform, PrettyName(k), 23,
                AnimLibrary.IsLoop(k) ? new Color(0.65f, 0.85f, 1f) : Color.white,
                TextAnchor.MiddleCenter, FontStyle.Normal);
            UiKit.Stretch((RectTransform)label.transform, Vector2.zero, Vector2.one, new Vector4(4, 4, 4, 4));
        }

        animPanel.SetActive(false);
    }

    static string PrettyName(string key)
    {
        return key.Replace('_', ' ');
    }

    // =====================================================================

    PressButton MakeCircleButton(RectTransform parent, string label, Vector2 anchor, Vector2 pos, float size,
        Color color, System.Action onDown, System.Action onUp, int fontSize)
    {
        var img = UiKit.NewImage("Btn_" + label, parent, UiKit.Circle(), color);
        UiKit.Anchor((RectTransform)img.transform, anchor, pos, new Vector2(size, size));

        var edge = UiKit.NewImage("Edge", img.transform, UiKit.Ring(), new Color(1f, 1f, 1f, 0.5f));
        UiKit.Stretch((RectTransform)edge.transform, Vector2.zero, Vector2.one, Vector4.zero);
        edge.raycastTarget = false;

        var txt = UiKit.NewText("Label", img.transform, label, fontSize, Color.white);
        UiKit.Stretch((RectTransform)txt.transform, Vector2.zero, Vector2.one, Vector4.zero);

        var pb = img.gameObject.AddComponent<PressButton>();
        pb.targetGraphic = img;
        pb.onDown = onDown;
        pb.onUp = onUp;
        return pb;
    }

    PressButton MakeRectButton(RectTransform parent, string label, Vector2 anchor, Vector2 pos, Vector2 size,
        Color color, System.Action onDown, int fontSize)
    {
        var img = UiKit.NewImage("Btn_" + label, parent, UiKit.Rounded(), color);
        UiKit.Anchor((RectTransform)img.transform, anchor, pos, size);

        var txt = UiKit.NewText("Label", img.transform, label, fontSize, Color.white);
        UiKit.Stretch((RectTransform)txt.transform, Vector2.zero, Vector2.one, Vector4.zero);

        var pb = img.gameObject.AddComponent<PressButton>();
        pb.targetGraphic = img;
        pb.onDown = onDown;
        return pb;
    }
}
