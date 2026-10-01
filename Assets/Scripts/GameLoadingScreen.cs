using UnityEngine;
using UnityEngine.UI;

/// <summary>Boot splash penuh layar dengan bar kemajuan tipis di bawah.</summary>
public sealed class GameLoadingScreen
{
    GameObject root;
    Image fill;
    Text caption;
    Sprite backgroundSprite;

    GameLoadingScreen() { }

    public static GameLoadingScreen Show()
    {
        var view = new GameLoadingScreen();
        view.Build();
        return view;
    }

    void Build()
    {
        root = new GameObject("ArpgLoadingScreen", typeof(RectTransform), typeof(Canvas), typeof(CanvasScaler), typeof(GraphicRaycaster));
        var canvas = root.GetComponent<Canvas>();
        canvas.renderMode = RenderMode.ScreenSpaceOverlay;
        canvas.sortingOrder = 32000;
        var scaler = root.GetComponent<CanvasScaler>();
        scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
        scaler.referenceResolution = new Vector2(1920f, 1080f);
        scaler.matchWidthOrHeight = 0.5f;

        var bgGo = new GameObject("Background", typeof(RectTransform), typeof(Image));
        bgGo.transform.SetParent(root.transform, false);
        var bgRect = (RectTransform)bgGo.transform;
        bgRect.anchorMin = Vector2.zero;
        bgRect.anchorMax = Vector2.one;
        bgRect.offsetMin = Vector2.zero;
        bgRect.offsetMax = Vector2.zero;
        var bg = bgGo.GetComponent<Image>();
        bg.raycastTarget = false;
        var texture = Resources.Load<Texture2D>("Branding/ArpgLoading");
        if (texture != null)
        {
            backgroundSprite = Sprite.Create(texture, new Rect(0f, 0f, texture.width, texture.height), new Vector2(0.5f, 0.5f), 100f);
            bg.sprite = backgroundSprite;
            bg.type = Image.Type.Simple;
            bg.preserveAspect = false;
        }
        else bg.color = new Color(0.045f, 0.07f, 0.12f, 1f);

        var title = MakeText("Arpg", 46, Color.white, TextAnchor.MiddleLeft);
        Anchor((RectTransform)title.transform, new Vector2(0f, 1f), new Vector2(270f, -65f), new Vector2(500f, 76f));
        title.fontStyle = FontStyle.Bold;
        title.raycastTarget = false;

        var captionGo = MakeText("MEMUAT...", 22, new Color(0.88f, 0.95f, 1f, 0.94f), TextAnchor.MiddleLeft);
        Anchor((RectTransform)captionGo.transform, new Vector2(0.5f, 0f), new Vector2(0f, 56f), new Vector2(1500f, 36f));
        caption = captionGo;

        var trackGo = new GameObject("ProgressTrack", typeof(RectTransform), typeof(Image));
        trackGo.transform.SetParent(root.transform, false);
        var trackRect = (RectTransform)trackGo.transform;
        trackRect.anchorMin = new Vector2(0.08f, 0f);
        trackRect.anchorMax = new Vector2(0.92f, 0f);
        trackRect.pivot = new Vector2(0.5f, 0f);
        trackRect.offsetMin = new Vector2(0f, 24f);
        trackRect.offsetMax = new Vector2(0f, 30f); // tinggi 6 px di resolusi referensi, di bawah teks
        var track = trackGo.GetComponent<Image>();
        track.color = new Color(0.02f, 0.04f, 0.07f, 0.82f);
        track.raycastTarget = false;

        var fillGo = new GameObject("ProgressFill", typeof(RectTransform), typeof(Image));
        fillGo.transform.SetParent(trackGo.transform, false);
        var fillRect = (RectTransform)fillGo.transform;
        fillRect.anchorMin = Vector2.zero;
        fillRect.anchorMax = Vector2.one;
        fillRect.offsetMin = Vector2.zero;
        fillRect.offsetMax = Vector2.zero;
        fill = fillGo.GetComponent<Image>();
        fill.color = new Color(0.48f, 0.88f, 0.96f, 1f);
        fill.type = Image.Type.Filled;
        fill.fillMethod = Image.FillMethod.Horizontal;
        fill.fillOrigin = (int)Image.OriginHorizontal.Left;
        fill.fillAmount = 0f;
        fill.raycastTarget = false;
    }

    Text MakeText(string value, int size, Color color, TextAnchor alignment)
    {
        var go = new GameObject("Text", typeof(RectTransform), typeof(Text), typeof(Shadow));
        go.transform.SetParent(root.transform, false);
        var text = go.GetComponent<Text>();
        text.font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
        text.text = value;
        text.fontSize = size;
        text.color = color;
        text.alignment = alignment;
        text.horizontalOverflow = HorizontalWrapMode.Overflow;
        text.verticalOverflow = VerticalWrapMode.Overflow;
        text.raycastTarget = false;
        var shadow = go.GetComponent<Shadow>();
        shadow.effectColor = new Color(0f, 0f, 0f, 0.65f);
        shadow.effectDistance = new Vector2(2f, -2f);
        return text;
    }

    static void Anchor(RectTransform rt, Vector2 anchor, Vector2 position, Vector2 size)
    {
        rt.anchorMin = anchor;
        rt.anchorMax = anchor;
        rt.pivot = new Vector2(0.5f, 0.5f);
        rt.anchoredPosition = position;
        rt.sizeDelta = size;
    }

    public void SetProgress(float amount, string message)
    {
        if (fill != null) fill.fillAmount = Mathf.Clamp01(amount);
        if (caption != null && !string.IsNullOrEmpty(message)) caption.text = message;
    }

    public void Hide()
    {
        if (root != null) Object.Destroy(root);
        if (backgroundSprite != null) Object.Destroy(backgroundSprite);
        root = null;
        fill = null;
        caption = null;
        backgroundSprite = null;
    }
}
