using UnityEngine;
using UnityEngine.UI;
using RPG.Core;

namespace RPG.Runtime
{
    /* ============================================================
       LOADING SCREEN — ala Genshin: layar terang + spinner + tips.

       Tahap 5d: overlay punya nyawa SENDIRI. Kalau WorldBoot tidak
       Start() atau coroutine membeku, Update di sini tetap jalan
       (kecuali main thread benar-benar hang — itu dicegah anggaran
       waktu di streamer) dan setelah OverlayFailsafeSec memaksa
       masuk. HideImmediate mematikan canvas, bukan cuma fade yang
       bergantung Update.
       ============================================================ */
    [DisallowMultipleComponent]
    public class LoadingScreen : MonoBehaviour
    {
        public static LoadingScreen Instance { get; private set; }
        public static bool IsShown => Instance != null && Instance._shown;
        public static bool WantSkip { get; private set; }

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
        Text _errorText;
        Text _skipHint;
        RectTransform _spinner;
        bool _shown;
        float _tipT;
        int _tipIdx;
        float _progress;
        string _status = "";
        float _shownAt;
        bool _failsafeFired;

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

            var bg = UiKit.Rect("Bg", _canvas.transform,
                Vector2.zero, Vector2.one, new Vector2(0.5f, 0.5f),
                Vector2.zero, Vector2.zero);
            UiKit.Image(bg, null, new Color(0.93f, 0.91f, 0.87f, 1f), true);

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

            var skip = UiKit.Rect("Skip", _canvas.transform,
                new Vector2(0.5f, 0f), new Vector2(0.5f, 0f), new Vector2(0.5f, 0.5f),
                new Vector2(0f, 24f), new Vector2(900f, 32f));
            _skipHint = UiKit.Label(skip, "", 22, new Color(0.45f, 0.42f, 0.38f, 1f));

            SetVisibleImmediate(false);
        }

        void Update()
        {
            if (_spinner != null && _shown)
                _spinner.localRotation = Quaternion.Euler(0f, 0f,
                    -Time.unscaledTime * 160f % 360f);

            var target = _shown ? 1f : 0f;
            if (_group != null && Mathf.Abs(_group.alpha - target) > 0.001f)
            {
                var d = Time.unscaledDeltaTime * 4f;
                _group.alpha = Mathf.Clamp(_group.alpha + Mathf.Sign(target - _group.alpha) * d,
                                           0f, 1f);
                if (_group.alpha <= 0f && !_shown && _canvas != null)
                    _canvas.enabled = false;
            }

            if (!_shown) return;

            _tipT += Time.unscaledDeltaTime;
            if (_tipT > 4f)
            {
                _tipT = 0f;
                _tipIdx = (_tipIdx + 1) % Tips.Length;
                if (_tipsLabel != null) _tipsLabel.text = Tips[_tipIdx];
            }

            var shownFor = Time.realtimeSinceStartup - _shownAt;
            if (_skipHint != null)
                _skipHint.text = shownFor > 0.7f ? "ketuk untuk masuk" : "";

            if (shownFor > 0.4f && Tapped())
                WantSkip = true;

            if (!_failsafeFired && shownFor >= BootPolicy.OverlayFailsafeSec)
            {
                _failsafeFired = true;
                BootLog.Add("[LoadingScreen] FAILSAFE overlay — paksa masuk.");
                HideImmediate();
                WorldBoot.ForceEnter();
            }
        }

        static bool Tapped()
        {
            if (Input.GetMouseButtonDown(0) || Input.GetMouseButtonDown(1)) return true;
            for (var i = 0; i < Input.touchCount; i++)
                if (Input.GetTouch(i).phase == TouchPhase.Began) return true;
            return false;
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

        void EnsureErrorBox()
        {
            if (_errorText != null || _canvas == null) return;
            var panel = UiKit.Rect("ErrorBox", _canvas.transform,
                new Vector2(0.5f, 1f), new Vector2(0.5f, 1f), new Vector2(0.5f, 1f),
                new Vector2(0f, -16f), new Vector2(1400f, 250f));
            UiKit.Image(panel, UiKit.Round, new Color(0.45f, 0.08f, 0.08f, 0.93f));
            var t = UiKit.Rect("T", panel, Vector2.zero, Vector2.one,
                new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(-28f, -28f));
            _errorText = UiKit.Label(t, "", 22, Color.white, TextAnchor.UpperLeft);
        }

        public static void Show()
        {
            var ls = Instance ?? Create();
            ls._progress = 0f;
            ls._status = "memuat";
            ls._tipT = 0f;
            ls._shownAt = Time.realtimeSinceStartup;
            ls._failsafeFired = false;
            WantSkip = false;
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
            Instance._shown = false;
            if (Instance._group != null)
            {
                Instance._group.interactable = false;
                Instance._group.blocksRaycasts = false;
            }
        }

        /* Matikan overlay SEKARANG. Dipakai EnterWorld: fade yang
           menunggu Update tidak boleh jadi alasan overlay nempel. */
        public static void HideImmediate()
        {
            Hide();
            if (Instance == null) return;
            if (Instance._group != null) Instance._group.alpha = 0f;
            if (Instance._canvas != null) Instance._canvas.enabled = false;
        }

        public static void ShowError(string text)
        {
            try
            {
                var ls = Instance ?? Create();
                ls.EnsureErrorBox();
                if (ls._errorText != null) ls._errorText.text = text ?? "";
            }
            catch { }
        }
    }
}
