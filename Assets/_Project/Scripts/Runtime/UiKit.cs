using System;
using UnityEngine;
using UnityEngine.UI;

namespace RPG.Runtime
{
    /* ============================================================
       UI KIT — pembangun UI kode untuk HUD Genshin.

       Kenapa UI dibangun dari KODE, bukan prefab/drag-drop:
       scene game ini DIBANGUN ULANG oleh Stage2SceneBuilder setiap
       build (lihat AureliaBuildPreprocessor) — prefab manual yang
       ditaruh di scene akan HILANG saat scene dibangun ulang.
       Dengan kode, HUD selalu ada dan identik di semua build.

       Semua gambar (lingkaran, cincin, panel) dibuat prosedural
       saat runtime — tanpa aset gambar, tanpa font kustom:
       - Sprite: Texture2D 128px + Sprite.Create (putih, diwarnai
         lewat Image.color)
       - Font: font bawaan Unity (LegacyRuntime/Arial). Ganti di
         UiFont.Font kalau nanti punya font OFL (mis. Nunito).
       ============================================================ */
    public static class UiKit
    {
        // ---- palet Genshin-ish ----
        public static readonly Color Panel      = new Color(0.06f, 0.09f, 0.16f, 0.78f);
        public static readonly Color PanelSoft  = new Color(1f, 1f, 1f, 0.14f);
        public static readonly Color Gold       = new Color(0.84f, 0.70f, 0.42f, 1f);
        public static readonly Color Cream      = new Color(0.96f, 0.95f, 0.91f, 1f);
        public static readonly Color Ink        = new Color(0.17f, 0.16f, 0.19f, 1f);
        public static readonly Color Teal       = new Color(0.45f, 0.77f, 0.71f, 1f);
        public static readonly Color HpGreen    = new Color(0.49f, 0.78f, 0.43f, 1f);
        public static readonly Color Stamina    = new Color(0.95f, 0.82f, 0.35f, 1f);
        public static readonly Color Dim        = new Color(1f, 1f, 1f, 0.45f);
        public static readonly Color Cooldown   = new Color(0.02f, 0.03f, 0.05f, 0.72f);

        public const float RefW = 1920f;
        public const float RefH = 1080f;

        // ---- sprite prosedural (dibuat sekali, dipakai semua UI) ----
        static Sprite _circle;
        static Sprite _ring;
        static Sprite _round;

        public static Sprite Circle
        {
            get
            {
                if (_circle == null) _circle = BuildSprite(128, (x, y) =>
                {
                    var d = Mathf.Sqrt((x - 0.5f) * (x - 0.5f) + (y - 0.5f) * (y - 0.5f)) * 2f;
                    return Mathf.Clamp01((1f - d) * 8f);
                });
                return _circle;
            }
        }

        public static Sprite Ring
        {
            get
            {
                if (_ring == null) _ring = BuildSprite(128, (x, y) =>
                {
                    var d = Mathf.Sqrt((x - 0.5f) * (x - 0.5f) + (y - 0.5f) * (y - 0.5f)) * 2f;
                    var band = 1f - Mathf.Abs(d - 0.82f) / 0.10f;
                    return Mathf.Clamp01(band);
                });
                return _ring;
            }
        }

        public static Sprite Round
        {
            get
            {
                if (_round == null) _round = BuildSprite(128, (x, y) =>
                {
                    const float r = 0.18f;
                    var dx = Math.Max(Math.Abs(x - 0.5f) - (0.5f - r), 0f);
                    var dy = Math.Max(Math.Abs(y - 0.5f) - (0.5f - r), 0f);
                    var d = Mathf.Sqrt(dx * dx + dy * dy);
                    return Mathf.Clamp01((r - d) * 12f + 0.5f);
                });
                return _round;
            }
        }

        delegate float AlphaFn(float x, float y);

        static Sprite BuildSprite(int size, AlphaFn fn)
        {
            var tex = new Texture2D(size, size, TextureFormat.RGBA32, false);
            tex.wrapMode = TextureWrapMode.Clamp;
            tex.filterMode = FilterMode.Bilinear;
            var px = new Color32[size * size];
            for (var y = 0; y < size; y++)
            for (var x = 0; x < size; x++)
            {
                byte a = (byte)(255f * Mathf.Clamp01(
                    fn((x + 0.5f) / size, (y + 0.5f) / size)));
                px[y * size + x] = new Color32(255, 255, 255, a);
            }
            tex.SetPixels32(px);
            tex.Apply(false, false);
            return Sprite.Create(tex, new Rect(0f, 0f, size, size), new Vector2(0.5f, 0.5f));
        }

        // ---- font ----
        static Font _font;
        static bool _fontTried;

        public static Font Font
        {
            get
            {
                if (_font == null && !_fontTried)
                {
                    _fontTried = true;
                    // Unity 6: LegacyRuntime.ttf. Unity lama: Arial.ttf.
                    _font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
                    if (_font == null)
                        _font = Resources.GetBuiltinResource<Font>("Arial.ttf");
                    if (_font == null)
                        Debug.LogWarning("[UiKit] font bawaan tidak ketemu — teks HUD kosong. " +
                                         "Taruh font .ttf di project dan isi UiKit.Font.");
                }
                return _font;
            }
        }

        // ---- konstruktor ----
        public static Canvas CreateCanvas(string name, int sortingOrder)
        {
            var go = new GameObject(name);
            var canvas = go.AddComponent<Canvas>();
            canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            canvas.sortingOrder = sortingOrder;
            var scaler = go.AddComponent<CanvasScaler>();
            scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            scaler.referenceResolution = new Vector2(RefW, RefH);
            scaler.matchWidthOrHeight = 1f;   // skala ikut TINGGI (konsisten di semua HP)
            go.AddComponent<GraphicRaycaster>();
            go.AddComponent<CanvasGroup>();
            return canvas;
        }

        /* RectTransform dari nol. anchorMin/Max 0..1, anchoredPos & size
           dalam piksel referensi (1920x1080). */
        public static RectTransform Rect(string name, Transform parent,
            Vector2 anchorMin, Vector2 anchorMax, Vector2 pivot,
            Vector2 anchoredPos, Vector2 size)
        {
            var go = new GameObject(name);
            go.transform.SetParent(parent, false);
            var rt = go.AddComponent<RectTransform>();
            rt.anchorMin = anchorMin;
            rt.anchorMax = anchorMax;
            rt.pivot = pivot;
            rt.anchoredPosition = anchoredPos;
            rt.sizeDelta = size;
            return rt;
        }

        public static Image Image(RectTransform rt, Sprite sprite, Color color,
                                  bool raycast = false)
        {
            var img = rt.gameObject.AddComponent<Image>();
            img.sprite = sprite;
            img.color = color;
            img.raycastTarget = raycast;
            return img;
        }

        public static Button Button(RectTransform rt, Action onClick)
        {
            var btn = rt.gameObject.AddComponent<Button>();
            var img = rt.gameObject.GetComponent<Image>();
            if (img != null) img.raycastTarget = true;
            if (onClick != null) btn.onClick.AddListener(() => onClick());
            return btn;
        }

        public static Text Label(RectTransform rt, string text, int size, Color color,
                                 TextAnchor align = TextAnchor.MiddleCenter, bool bold = false)
        {
            var t = rt.gameObject.AddComponent<Text>();
            t.font = Font;
            t.text = text;
            t.fontSize = size;
            t.color = color;
            t.alignment = align;
            t.fontStyle = bold ? FontStyle.Bold : FontStyle.Normal;
            t.horizontalOverflow = HorizontalWrapMode.Overflow;
            t.raycastTarget = false;
            return t;
        }

        /* Bar horizontal: latar + isi yang lebarnya = fraksi (0..1) lewat
           anchorMax.x. Mengembalikan RectTransform ISI (untuk diupdate). */
        public static RectTransform Bar(Transform parent, string name,
            Vector2 anchorMin, Vector2 anchorMax, Vector2 pivot,
            Vector2 anchoredPos, Vector2 size, Color bg, Color fg)
        {
            var root = Rect(name, parent, anchorMin, anchorMax, pivot, anchoredPos, size);
            Image(root, Round, bg);
            var fill = Rect("Fill", root,
                new Vector2(0f, 0f), new Vector2(1f, 1f), new Vector2(0f, 0.5f),
                Vector2.zero, Vector2.zero);
            Image(fill, Round, fg);
            return fill;
        }

        public static void SetBar(RectTransform fill, float frac)
        {
            fill.anchorMax = new Vector2(Mathf.Clamp01(frac), 1f);
        }

        public static Color Hex(string hex, float alpha = 1f)
        {
            hex = hex.TrimStart('#');
            var r = Convert.ToInt32(hex.Substring(0, 2), 16) / 255f;
            var g = Convert.ToInt32(hex.Substring(2, 2), 16) / 255f;
            var b = Convert.ToInt32(hex.Substring(4, 2), 16) / 255f;
            return new Color(r, g, b, alpha);
        }
    }
}
