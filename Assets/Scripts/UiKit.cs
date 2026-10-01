using UnityEngine;
using UnityEngine.UI;

/// <summary>Helper UI: sprite prosedural (lingkaran, cincin, rounded rect) + pembuat Text.</summary>
public static class UiKit
{
    static Sprite circle;
    static Sprite ring;
    static Sprite rounded;
    static Font font;

    public static Font Font
    {
        get
        {
            if (font == null) font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
            return font;
        }
    }

    public static Sprite Circle()
    {
        if (circle != null) return circle;
        const int S = 128;
        var tex = NewTex(S);
        float c = (S - 1) * 0.5f, R = S * 0.5f - 2f;
        var px = new Color32[S * S];
        for (int y = 0; y < S; y++)
            for (int x = 0; x < S; x++)
            {
                float d = Mathf.Sqrt((x - c) * (x - c) + (y - c) * (y - c));
                float a = Mathf.Clamp01(R - d + 0.5f);
                px[y * S + x] = new Color32(255, 255, 255, (byte)(a * 255f));
            }
        tex.SetPixels32(px); tex.Apply();
        circle = Sprite.Create(tex, new Rect(0, 0, S, S), new Vector2(0.5f, 0.5f), 100f);
        return circle;
    }

    public static Sprite Ring()
    {
        if (ring != null) return ring;
        const int S = 192;
        var tex = NewTex(S);
        float c = (S - 1) * 0.5f, R = S * 0.5f - 2f, inner = R * 0.82f;
        var px = new Color32[S * S];
        for (int y = 0; y < S; y++)
            for (int x = 0; x < S; x++)
            {
                float d = Mathf.Sqrt((x - c) * (x - c) + (y - c) * (y - c));
                float a = Mathf.Clamp01(R - d + 0.5f) * Mathf.Clamp01(d - inner + 0.5f);
                px[y * S + x] = new Color32(255, 255, 255, (byte)(a * 255f));
            }
        tex.SetPixels32(px); tex.Apply();
        ring = Sprite.Create(tex, new Rect(0, 0, S, S), new Vector2(0.5f, 0.5f), 100f);
        return ring;
    }

    public static Sprite Rounded()
    {
        if (rounded != null) return rounded;
        const int S = 64;
        const float rad = 18f;
        var tex = NewTex(S);
        var px = new Color32[S * S];
        for (int y = 0; y < S; y++)
            for (int x = 0; x < S; x++)
            {
                float dx = Mathf.Max(0f, Mathf.Max(rad - x, x - (S - 1 - rad)));
                float dy = Mathf.Max(0f, Mathf.Max(rad - y, y - (S - 1 - rad)));
                float d = Mathf.Sqrt(dx * dx + dy * dy);
                float a = Mathf.Clamp01(rad - d + 0.5f);
                px[y * S + x] = new Color32(255, 255, 255, (byte)(a * 255f));
            }
        tex.SetPixels32(px); tex.Apply();
        rounded = Sprite.Create(tex, new Rect(0, 0, S, S), new Vector2(0.5f, 0.5f), 100f,
            0, SpriteMeshType.FullRect, new Vector4(24, 24, 24, 24));
        return rounded;
    }

    static Texture2D NewTex(int s)
    {
        var t = new Texture2D(s, s, TextureFormat.RGBA32, false);
        t.wrapMode = TextureWrapMode.Clamp;
        t.filterMode = FilterMode.Bilinear;
        return t;
    }

    // ---------- pembuat elemen ----------

    public static RectTransform NewRect(string name, Transform parent)
    {
        var go = new GameObject(name, typeof(RectTransform));
        var rt = (RectTransform)go.transform;
        rt.SetParent(parent, false);
        return rt;
    }

    public static Image NewImage(string name, Transform parent, Sprite sprite, Color color)
    {
        var rt = NewRect(name, parent);
        var img = rt.gameObject.AddComponent<Image>();
        img.sprite = sprite;
        img.color = color;
        if (sprite == Rounded()) img.type = Image.Type.Sliced;
        return img;
    }

    public static Text NewText(string name, Transform parent, string content, int size, Color color,
        TextAnchor anchor = TextAnchor.MiddleCenter, FontStyle style = FontStyle.Bold)
    {
        var rt = NewRect(name, parent);
        var t = rt.gameObject.AddComponent<Text>();
        t.font = Font;
        t.text = content;
        t.fontSize = size;
        t.color = color;
        t.alignment = anchor;
        t.fontStyle = style;
        t.horizontalOverflow = HorizontalWrapMode.Overflow;
        t.verticalOverflow = VerticalWrapMode.Overflow;
        t.raycastTarget = false;
        var sh = rt.gameObject.AddComponent<Shadow>();
        sh.effectColor = new Color(0f, 0f, 0f, 0.5f);
        sh.effectDistance = new Vector2(1.5f, -1.5f);
        return t;
    }

    public static void Anchor(RectTransform rt, Vector2 anchor, Vector2 pos, Vector2 size)
    {
        rt.anchorMin = anchor;
        rt.anchorMax = anchor;
        rt.pivot = new Vector2(0.5f, 0.5f);
        rt.anchoredPosition = pos;
        rt.sizeDelta = size;
    }

    public static void Stretch(RectTransform rt, Vector2 min, Vector2 max, Vector4 padding)
    {
        rt.anchorMin = min;
        rt.anchorMax = max;
        rt.offsetMin = new Vector2(padding.x, padding.y);
        rt.offsetMax = new Vector2(-padding.z, -padding.w);
    }
}
