using UnityEngine;
using UnityEngine.UI;

namespace RPG.Runtime
{
    /* ============================================================
       LOADING SCREEN — ala Genshin: layar terang + spinner + tips,
       tampil SEBELUM dunia dirender, hilang setelah chunk awal
       selesai di-stream (lihat WorldBoot).

       Kenapa perlu: 25 chunk pertama + rumput + material toon butuh
       ~1-3 detik. Tanpa loading, pemain melihat dunia "tumbuh" dan
       mengira game rusak. Dengan loading, itu jadi pengalaman.
       ============================================================ */
    [DisallowMultipleComponent]
    public class LoadingScreen : MonoBehaviour
    {
        public static LoadingScreen Instance { get; private set; }
        public static bool IsShown => Instance != null && Instance._shown;

        static readonly string[] Tips =
        {
            "Tips: dorong stik penuh untuk sprint otomatis.",
            "Tips: klik kiri / tombol ATK untuk kombo 3x tebasan.",
            "Tips: tombol E = skill elemental, Q = ultimate.",
            "Tips: dash (Ctrl / tombol DSH) memakai 25% stamina.",
            "Tips: stamina terisi lagi setelah 1 detik tidak dipakai.",
            "Tips: putar kamera dengan menyeret sisi kanan layar.",
            "Tips: kualitas grafis bisa diubah di menu (pojok kiri atas).",
        };

        Canvas _canvas;
        CanvasGroup _group;
        RectTransform _barFill;
        Text _barLabel;
        Text _tipsLabel;
        RectTransform _spinner;
        bool _shown;
        float _tipT;
        int _tipIdx;
        float _progress;
        string _status = "";

        public static LoadingScreen Create()
        {
            if (Instance != null) return Instance;
            var go = new GameObject("LoadingScreen");
            var ls = go.AddComponent<LoadingScreen>();
            ls.Build();
            return ls;
        }

        void Awake()
        {
            Instance = this;
        }

        void OnDestroy()
        {
            if (Instance == this) Instance = null;
        }

        void Build()
        {
            Instance = this;
            _canvas = UiKit.CreateCanvas("LoadingScreenCanvas", 100);
            _canvas.transform.SetParent(transform, false);
            _group = _canvas.GetComponent<CanvasGroup>();

            // Latar krem terang (khas loading Genshin).
            var bg = UiKit.Rect("Bg", _canvas.transform,
                Vector2.zero, Vector2.one, new Vector2(0.5f, 0.5f),
                Vector2.zero, Vector2.zero);
            UiKit.Image(bg, null, new Color(0.93f, 0.91f, 0.87f, 1f));

            // Spinner cincin emas.
            _spinner = UiKit.Rect("Spinner", _canvas.transform,
                new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f),
                new Vector2(0f, 60f), new Vector2(150f, 150f));
            UiKit.Image(_spinner, UiKit.Ring, UiKit.Gold);

            var title = UiKit.Rect("Title", _canvas.transform,
                new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f),
                new Vector2(0f, -90f), new Vector2(800f, 90f));
            UiKit.Label(title, "A U R E L I A", 64, UiKit.Ink, TextAnchor.MiddleCenter, true);

            var sub = UiKit.Rect("Sub", _canvas.transform,
                new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f),
                new Vector2(0f, -160f), new Vector2(800f, 40f));
            UiKit.Label(sub, "menyiapkan dunia ...", 30, new Color(0.4f, 0.38f, 0.35f, 1f));

            // Bar kemajuan bawah.
            var barBg = UiKit.Rect("BarBg", _canvas.transform,
                new Vector2(0.5f, 0f), new Vector2(0.5f, 0f), new Vector2(0.5f, 0.5f),
                new Vector2(0f, 150f), new Vector2(640f, 14f));
            UiKit.Image(barBg, UiKit.Round, new Color(0.75f, 0.73f, 0.68f, 1f));
            _barFill = UiKit.Rect("BarFill", barBg,
                Vector2.zero, Vector2.one, new Vector2(0f, 0.5f),
                Vector2.zero, Vector2.zero);
            UiKit.Image(_barFill, UiKit.Round, UiKit.Gold);

            var bl = UiKit.Rect("BarLabel", _canvas.transform,
                new Vector2(0.5f, 0f), new Vector2(0.5f, 0f), new Vector2(0.5f, 0.5f),
                new Vector2(0f, 110f), new Vector2(800f, 36f));
            _barLabel = UiKit.Label(bl, "", 26, new Color(0.4f, 0.38f, 0.35f, 1f));

            var tip = UiKit.Rect("Tips", _canvas.transform,
                new Vector2(0.5f, 0f), new Vector2(0.5f, 0f), new Vector2(0.5f, 0.5f),
                new Vector2(0f, 60f), new Vector2(1200f, 36f));
            _tipsLabel = UiKit.Label(tip, Tips[0], 26, new Color(0.4f, 0.38f, 0.35f, 1f));

            SetVisibleImmediate(false);
        }

        void Update()
        {
            if (_spinner != null && _shown)
                _spinner.localRotation = Quaternion.Euler(0f, 0f,
                    -Time.unscaledTime * 160f % 360f);

            // Fadeopacity menuju target.
            var target = _shown ? 1f : 0f;
            if (_group != null && Mathf.Abs(_group.alpha - target) > 0.001f)
            {
                var d = Time.unscaledDeltaTime * 2.5f;
                _group.alpha = Mathf.Clamp(_group.alpha + Mathf.Sign(target - _group.alpha) * d,
                                           0f, 1f);
                if (_group.alpha <= 0f && !_shown && _canvas != null)
                    _canvas.enabled = false;   // mati total: hemat fill-rate
            }

            if (_shown)
            {
                _tipT += Time.unscaledDeltaTime;
                if (_tipT > 4f)
                {
                    _tipT = 0f;
                    _tipIdx = (_tipIdx + 1) % Tips.Length;
                    if (_tipsLabel != null) _tipsLabel.text = Tips[_tipIdx];
                }
            }
        }

        void RefreshBar()
        {
            if (_barFill != null)
                _barFill.anchorMax = new Vector2(Mathf.Clamp01(_progress), 1f);
            if (_barLabel != null)
                _barLabel.text = $"{_status}  {Mathf.RoundToInt(_progress * 100f)}%";
        }

        void SetVisibleImmediate(bool v)
        {
            _shown = v;
            if (_group != null)
            {
                _group.alpha = v ? 1f : 0f;
                _group.interactable = v;
                _group.blocksRaycasts = v;
            }
            if (_canvas != null) _canvas.enabled = v;
        }

        // ---- API statis ----
        public static void Show()
        {
            var ls = Instance ?? Create();
            ls._progress = 0f;
            ls._status = "memuat";
            ls._tipT = 0f;
            ls._shown = true;
            if (ls._group != null)
            {
                ls._group.alpha = 1f;
                ls._group.interactable = true;
                ls._group.blocksRaycasts = true;
            }
            if (ls._canvas != null) ls._canvas.enabled = true;
            ls.RefreshBar();
        }

        public static void SetProgress(float frac, string status)
        {
            if (Instance == null) return;
            Instance._progress = frac;
            Instance._status = status ?? "";
            Instance.RefreshBar();
        }

        public static void Hide()
        {
            if (Instance == null) return;
            Instance._shown = false;   // fade-out dikerjakan Update
            if (Instance._group != null)
            {
                Instance._group.interactable = false;
                Instance._group.blocksRaycasts = false;
            }
        }
    }
}
