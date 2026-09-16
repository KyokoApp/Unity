using UnityEngine;
using UnityEngine.UI;
using RPG.Core;

namespace RPG.Runtime
{
    /* ============================================================
       GENSHIN HUD — antarmuka ala Genshin Impact, dibangun dari kode.

       Isi: potret party + HP (kiri atas), kompas arah (tengah atas),
       pelacak region (bawah kompas), minimap placeholder + fps
       (kanan atas), stamina (bawah tengah), klaster aksi ATK/E/Q/
       JUMP/DASH (kanan bawah), stik virtual (kiri bawah), panel
       PENGATURAN lengkap (tengah, via tombol menu).

       Dibangun dari kode (bukan prefab) karena scene dibangun ulang
       builder setiap build — lihat UiKit untuk alasannya.
       Semua teks ASCII (tanpa ikon unicode) supaya tidak jadi kotak
       tofu di font bawaan. Ganti font + sprite di UiKit kalau mau
       ikon beneran (lihat TAHAP-5.md).
       ============================================================ */
    [DisallowMultipleComponent]
    public class GenshinHud : MonoBehaviour
    {
        public static GenshinHud Instance { get; private set; }
        public Canvas Canvas => _canvas;

        const float SkillCdMax = 6f;
        const float BurstCdMax = 15f;

        Canvas _canvas;
        CanvasGroup _group;
        CharacterMotor _motor;
        CameraRig _cam;

        // Kompas: 8 arah (yaw kiblat: U=180 E=90 S=0 B=-90 — cocokkan
        // dengan CameraRelative: yaw 0 = menghadap +Z = "selatan" peta).
        static readonly string[] DirName = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" };
        static readonly float[] DirYaw =
            { 180f, 135f, 90f, 45f, 0f, -45f, -90f, -135f };
        Text[] _dirLabels;
        RectTransform[] _dirRects;

        Text _regionName;
        Text _regionSub;
        string _regionId = "";
        Text _fpsText;
        float _fpsAcc;
        int _fpsN;
        float _fpsShown;

        RectTransform _stamFill;
        CanvasGroup _stamGroup;

        HudButton _attack;
        HudButton _skill;
        HudButton _burst;
        HudButton _jump;
        HudButton _dash;
        Image _burstRing;

        float _skillCd;
        float _burstCd;
        float _energy = 60f;

        RectTransform _nMark;
        Vector2 _mapCenterLocal;

        GameObject _settingsPanel;
        Text _vQuality, _vFps, _vSens, _vDist, _vShadow, _vBloom, _vSound, _vBtn;

        VirtualJoystick _stick;

        /* Satu tombol aksi bundar + overlay cooldown radial. */
        class HudButton
        {
            public RectTransform Root;
            public Image CdOverlay;
            public Text CdText;
        }

        // ============================================================ bangun
        public static GenshinHud Create()
        {
            if (Instance != null) return Instance;
            var go = new GameObject("GenshinHUD");
            var hud = go.AddComponent<GenshinHud>();
            hud.Build();
            return hud;
        }

        public static void SetVisible(bool v)
        {
            if (Instance != null) Instance.SetVisibleNow(v);
        }

        void Awake()
        {
            Instance = this;
            _motor = FindFirstObjectByType<CharacterMotor>();
            _cam = FindFirstObjectByType<CameraRig>();
        }

        void OnDestroy()
        {
            if (Instance == this) Instance = null;
        }

        void SetVisibleNow(bool v)
        {
            if (_group != null)
            {
                _group.alpha = v ? 1f : 0f;
                _group.interactable = v;
                _group.blocksRaycasts = v;
            }
            if (_canvas != null) _canvas.enabled = v;
        }

        void Build()
        {
            Instance = this;
            _canvas = UiKit.CreateCanvas("GenshinCanvas", 10);
            _canvas.transform.SetParent(transform, false);
            _group = _canvas.GetComponent<CanvasGroup>();
            var root = _canvas.transform;

            BuildParty(root);
            BuildCompass(root);
            BuildRegionTracker(root);
            BuildMinimap(root);
            BuildStamina(root);
            BuildActions(root);
            BuildStick(root);
            BuildSettings(root);

            _motor = FindFirstObjectByType<CharacterMotor>();
            _cam = FindFirstObjectByType<CameraRig>();
        }

        void BuildParty(Transform root)
        {
            // Tombol menu (pojok kiri atas).
            var menu = UiKit.Rect("MenuBtn", root,
                new Vector2(0f, 1f), new Vector2(0f, 1f), new Vector2(0.5f, 0.5f),
                new Vector2(62f, -62f), new Vector2(76f, 76f));
            UiKit.Image(menu, UiKit.Circle, UiKit.PanelSoft);
            UiKit.Button(menu, ToggleSettings);
            var ml = UiKit.Rect("T", menu, Vector2.zero, Vector2.one,
                new Vector2(0.5f, 0.5f), Vector2.zero, Vector2.zero);
            UiKit.Label(ml, "=", 44, UiKit.Cream, TextAnchor.MiddleCenter, true);

            // 4 potret party + bar HP.
            for (var i = 0; i < 4; i++)
            {
                var active = i == 0;
                var px = 150f + i * 100f;
                var p = UiKit.Rect("Portrait" + i, root,
                    new Vector2(0f, 1f), new Vector2(0f, 1f), new Vector2(0.5f, 0.5f),
                    new Vector2(px, -62f), new Vector2(84f, 84f));
                UiKit.Image(p, UiKit.Circle,
                    active ? UiKit.Teal : new Color(0.3f, 0.34f, 0.42f, 0.9f));
                var ring = UiKit.Rect("Ring", p, Vector2.zero, Vector2.one,
                    new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(92f, 92f));
                UiKit.Image(ring, UiKit.Ring, active ? UiKit.Gold : UiKit.Dim);
                var num = UiKit.Rect("Num", p, Vector2.zero, Vector2.one,
                    new Vector2(0.5f, 0.5f), Vector2.zero, Vector2.zero);
                UiKit.Label(num, (i + 1).ToString(), 34, UiKit.Cream,
                    TextAnchor.MiddleCenter, true);

                var hp = UiKit.Bar(root, "Hp" + i,
                    new Vector2(0f, 1f), new Vector2(0f, 1f), new Vector2(0.5f, 0.5f),
                    new Vector2(px, -116f), new Vector2(84f, 10f),
                    new Color(0f, 0f, 0f, 0.55f), UiKit.HpGreen);
                UiKit.SetBar(hp, 1f);
            }
        }

        void BuildCompass(Transform root)
        {
            var strip = UiKit.Rect("Compass", root,
                new Vector2(0.5f, 1f), new Vector2(0.5f, 1f), new Vector2(0.5f, 0.5f),
                new Vector2(0f, -40f), new Vector2(560f, 52f));
            UiKit.Image(strip, UiKit.Round, UiKit.Panel);
            _dirLabels = new Text[DirName.Length];
            _dirRects = new RectTransform[DirName.Length];
            for (var i = 0; i < DirName.Length; i++)
            {
                var t = UiKit.Rect("D" + i, strip,
                    new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f),
                    new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(60f, 52f));
                _dirRects[i] = t;
                _dirLabels[i] = UiKit.Label(t, DirName[i], 24, UiKit.Cream);
            }
            var caret = UiKit.Rect("Caret", strip,
                new Vector2(0.5f, 0f), new Vector2(0.5f, 0f), new Vector2(0.5f, 0.5f),
                new Vector2(0f, -2f), new Vector2(40f, 26f));
            UiKit.Label(caret, "v", 22, UiKit.Gold, TextAnchor.MiddleCenter, true);
        }

        void BuildRegionTracker(Transform root)
        {
            var panel = UiKit.Rect("Quest", root,
                new Vector2(0.5f, 1f), new Vector2(0.5f, 1f), new Vector2(0.5f, 0.5f),
                new Vector2(0f, -112f), new Vector2(520f, 80f));
            UiKit.Image(panel, UiKit.Round, UiKit.Panel);
            var n = UiKit.Rect("Name", panel,
                new Vector2(0f, 1f), new Vector2(1f, 1f), new Vector2(0.5f, 1f),
                new Vector2(0f, -8f), new Vector2(500f, 38f));
            _regionName = UiKit.Label(n, "...", 28, UiKit.Cream,
                TextAnchor.MiddleCenter, true);
            var s = UiKit.Rect("Sub", panel,
                new Vector2(0f, 1f), new Vector2(1f, 1f), new Vector2(0.5f, 1f),
                new Vector2(0f, -46f), new Vector2(500f, 30f));
            _regionSub = UiKit.Label(s, "", 21, UiKit.Dim);
        }

        void BuildMinimap(Transform root)
        {
            var map = UiKit.Rect("Minimap", root,
                new Vector2(1f, 1f), new Vector2(1f, 1f), new Vector2(0.5f, 0.5f),
                new Vector2(-130f, -130f), new Vector2(190f, 190f));
            UiKit.Image(map, UiKit.Circle, UiKit.Panel);
            var ring = UiKit.Rect("Ring", map, Vector2.zero, Vector2.one,
                new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(198f, 198f));
            UiKit.Image(ring, UiKit.Ring, UiKit.Gold);
            var t = UiKit.Rect("T", map, Vector2.zero, Vector2.one,
                new Vector2(0.5f, 0.5f), Vector2.zero, Vector2.zero);
            UiKit.Label(t, "MAP", 30, UiKit.Dim, TextAnchor.MiddleCenter, true);
            var nm = UiKit.Rect("N", map,
                new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f),
                new Vector2(0.5f, 0.5f), new Vector2(0f, 78f), new Vector2(30f, 30f));
            UiKit.Label(nm, "N", 24, UiKit.Gold, TextAnchor.MiddleCenter, true);
            _nMark = nm;

            var fps = UiKit.Rect("Fps", root,
                new Vector2(1f, 1f), new Vector2(1f, 1f), new Vector2(0.5f, 0.5f),
                new Vector2(-130f, -248f), new Vector2(190f, 30f));
            _fpsText = UiKit.Label(fps, "", 22, UiKit.Dim);
        }

        void BuildStamina(Transform root)
        {
            var holder = UiKit.Rect("Stamina", root,
                new Vector2(0.5f, 0f), new Vector2(0.5f, 0f), new Vector2(0.5f, 0.5f),
                new Vector2(0f, 120f), new Vector2(440f, 18f));
            _stamGroup = holder.gameObject.AddComponent<CanvasGroup>();
            UiKit.Image(holder, UiKit.Round, new Color(0f, 0f, 0f, 0.55f));
            _stamFill = UiKit.Rect("Fill", holder,
                Vector2.zero, Vector2.one, new Vector2(0f, 0.5f),
                Vector2.zero, Vector2.zero);
            UiKit.Image(_stamFill, UiKit.Round, UiKit.Stamina);
            _stamGroup.alpha = 0f;
        }

        HudButton MakeAction(Transform root, string name, Vector2 pos, float size,
                             string label, int fontSize, System.Action onClick)
        {
            var b = new HudButton();
            b.Root = UiKit.Rect(name, root,
                new Vector2(1f, 0f), new Vector2(1f, 0f), new Vector2(0.5f, 0.5f),
                pos, new Vector2(size, size));
            UiKit.Image(b.Root, UiKit.Circle, new Color(1f, 1f, 1f, 0.30f));
            UiKit.Button(b.Root, onClick);
            var t = UiKit.Rect("T", b.Root, Vector2.zero, Vector2.one,
                new Vector2(0.5f, 0.5f), Vector2.zero, Vector2.zero);
            UiKit.Label(t, label, fontSize, UiKit.Ink, TextAnchor.MiddleCenter, true);
            var cd = UiKit.Rect("Cd", b.Root, Vector2.zero, Vector2.one,
                new Vector2(0.5f, 0.5f), Vector2.zero, Vector2.zero);
            var img = UiKit.Image(cd, UiKit.Circle, UiKit.Cooldown);
            img.type = Image.Type.Filled;
            img.fillMethod = Image.FillMethod.Radial360;
            img.fillAmount = 0f;
            b.CdOverlay = img;
            var ct = UiKit.Rect("CdT", b.Root, Vector2.zero, Vector2.one,
                new Vector2(0.5f, 0.5f), Vector2.zero, Vector2.zero);
            b.CdText = UiKit.Label(ct, "", 34, UiKit.Cream, TextAnchor.MiddleCenter, true);
            return b;
        }

        void BuildActions(Transform root)
        {
            _attack = MakeAction(root, "BtnAttack", new Vector2(-170f, 200f), 210f,
                "ATK", 44, () => { HudInput.AttackPressed = true; });
            _skill = MakeAction(root, "BtnSkill", new Vector2(-350f, 270f), 150f,
                "E", 52, FireSkill);
            _burst = MakeAction(root, "BtnBurst", new Vector2(-330f, 445f), 165f,
                "Q", 56, FireBurst);
            _jump = MakeAction(root, "BtnJump", new Vector2(-545f, 180f), 135f,
                "JMP", 34, () => { HudInput.JumpPressed = true; });
            _dash = MakeAction(root, "BtnDash", new Vector2(-705f, 160f), 135f,
                "DSH", 34, () => { HudInput.DashPressed = true; });

            // Cincin energi ultimate di tombol Q.
            var ring = UiKit.Rect("Energy", _burst.Root,
                Vector2.zero, Vector2.one, new Vector2(0.5f, 0.5f),
                Vector2.zero, new Vector2(180f, 180f));
            _burstRing = UiKit.Image(ring, UiKit.Ring, UiKit.Gold);
            _burstRing.type = Image.Type.Filled;
            _burstRing.fillMethod = Image.FillMethod.Radial360;
            _burstRing.fillAmount = _energy / 100f;
        }

        void BuildStick(Transform root)
        {
            var zone = UiKit.Rect("StickZone", root,
                Vector2.zero, new Vector2(0.45f, 0.72f), new Vector2(0f, 0f),
                Vector2.zero, Vector2.zero);
            UiKit.Image(zone, null, new Color(0f, 0f, 0f, 0f), true);
            var baseRt = UiKit.Rect("Base", zone,
                new Vector2(0f, 0f), new Vector2(0f, 0f), new Vector2(0.5f, 0.5f),
                Vector2.zero, new Vector2(280f, 280f));
            UiKit.Image(baseRt, UiKit.Circle, new Color(1f, 1f, 1f, 0.18f));
            var knob = UiKit.Rect("Knob", baseRt,
                new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f),
                new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(120f, 120f));
            UiKit.Image(knob, UiKit.Circle, new Color(1f, 1f, 1f, 0.45f));

            _stick = zone.gameObject.AddComponent<VirtualJoystick>();
            _stick.Zone = zone;
            _stick.Base = baseRt;
            _stick.Knob = knob;
            _stick.Scaler = _canvas.GetComponent<CanvasScaler>();
        }

        // ============================================================ pengaturan
        void BuildSettings(Transform root)
        {
            var panel = UiKit.Rect("Settings", root,
                new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f),
                Vector2.zero, new Vector2(920f, 680f));
            UiKit.Image(panel, UiKit.Round, new Color(0.07f, 0.09f, 0.15f, 0.96f));
            _settingsPanel = panel.gameObject;

            var title = UiKit.Rect("Title", panel,
                new Vector2(0f, 1f), new Vector2(1f, 1f), new Vector2(0.5f, 1f),
                new Vector2(0f, -34f), new Vector2(800f, 50f));
            UiKit.Label(title, "PENGATURAN", 36, UiKit.Gold, TextAnchor.MiddleCenter, true);

            var y = -110f;
            Row(panel, "Kualitas", ref y, out _vQuality,
                () => CycleQuality(-1), () => CycleQuality(1));
            Row(panel, "FPS", ref y, out _vFps,
                () => CycleFps(-1), () => CycleFps(1));
            Row(panel, "Sensitivitas", ref y, out _vSens,
                () => StepSens(-0.2), () => StepSens(0.2));
            Row(panel, "Jarak Kamera", ref y, out _vDist,
                () => StepDist(-0.5), () => StepDist(0.5));
            Row(panel, "Bayangan", ref y, out _vShadow, ToggleShadows, ToggleShadows);
            Row(panel, "Bloom", ref y, out _vBloom,
                () => CycleBloom(-1), () => CycleBloom(1));
            Row(panel, "Suara", ref y, out _vSound, ToggleSound, ToggleSound);
            Row(panel, "Skala Tombol", ref y, out _vBtn,
                () => StepBtn(-0.1), () => StepBtn(0.1));

            var close = UiKit.Rect("Close", panel,
                new Vector2(0.5f, 0f), new Vector2(0.5f, 0f), new Vector2(0.5f, 0.5f),
                new Vector2(0f, 56f), new Vector2(260f, 60f));
            UiKit.Image(close, UiKit.Round, UiKit.Gold);
            UiKit.Button(close, ToggleSettings);
            var ct = UiKit.Rect("T", close, Vector2.zero, Vector2.one,
                new Vector2(0.5f, 0.5f), Vector2.zero, Vector2.zero);
            UiKit.Label(ct, "TUTUP", 30, UiKit.Ink, TextAnchor.MiddleCenter, true);

            _settingsPanel.SetActive(false);
        }

        void Row(Transform panel, string label, ref float y, out Text value,
                 System.Action left, System.Action right)
        {
            var row = UiKit.Rect("Row" + label, panel,
                new Vector2(0f, 1f), new Vector2(1f, 1f), new Vector2(0.5f, 1f),
                new Vector2(0f, y), new Vector2(840f, 56f));
            y -= 62f;
            var l = UiKit.Rect("L", row,
                new Vector2(0f, 0.5f), new Vector2(0f, 0.5f), new Vector2(0f, 0.5f),
                new Vector2(20f, 0f), new Vector2(340f, 56f));
            UiKit.Label(l, label, 28, UiKit.Cream, TextAnchor.MiddleLeft);

            var bl = UiKit.Rect("BL", row,
                new Vector2(1f, 0.5f), new Vector2(1f, 0.5f), new Vector2(0.5f, 0.5f),
                new Vector2(-300f, 0f), new Vector2(64f, 52f));
            UiKit.Image(bl, UiKit.Round, UiKit.PanelSoft);
            UiKit.Button(bl, left);
            var blt = UiKit.Rect("T", bl, Vector2.zero, Vector2.one,
                new Vector2(0.5f, 0.5f), Vector2.zero, Vector2.zero);
            UiKit.Label(blt, "<", 32, UiKit.Cream);

            var vv = UiKit.Rect("V", row,
                new Vector2(1f, 0.5f), new Vector2(1f, 0.5f), new Vector2(0.5f, 0.5f),
                new Vector2(-160f, 0f), new Vector2(210f, 52f));
            value = UiKit.Label(vv, "", 28, UiKit.Gold);

            var br = UiKit.Rect("BR", row,
                new Vector2(1f, 0.5f), new Vector2(1f, 0.5f), new Vector2(0.5f, 0.5f),
                new Vector2(-40f, 0f), new Vector2(64f, 52f));
            UiKit.Image(br, UiKit.Round, UiKit.PanelSoft);
            UiKit.Button(br, right);
            var brt = UiKit.Rect("T", br, Vector2.zero, Vector2.one,
                new Vector2(0.5f, 0.5f), Vector2.zero, Vector2.zero);
            UiKit.Label(brt, ">", 32, UiKit.Cream);
        }

        void ToggleSettings()
        {
            if (_settingsPanel == null) return;
            var v = !_settingsPanel.activeSelf;
            _settingsPanel.SetActive(v);
            if (v) RefreshSettingsTexts();
        }

        void RefreshSettingsTexts()
        {
            var s = SettingsStore.Load();
            _vQuality.text = QualityPresets.PresetLabel.TryGetValue(s.Quality, out var ql)
                ? ql : s.Quality;
            _vFps.text = s.Fps.ToString();
            _vSens.text = s.Sensitivity.ToString("F1");
            _vDist.text = CameraFraming.MetersFromSettings(s.CameraDistance).ToString("F1") + " m";
            _vShadow.text = s.Shadows ? "ON" : "OFF";
            _vBloom.text = QualityPresets.LevelLabel[
                Mathf.Clamp(s.Gfx.Bloom, 0, 3)];
            _vSound.text = s.Sound ? "ON" : "OFF";
            _vBtn.text = s.ButtonScale.ToString("F2");
        }

        void Apply(GameSettings s)
        {
            SettingsStore.Save(s);
            QualityApplier.RefreshAll();
            RefreshSettingsTexts();
        }

        void CycleQuality(int dir)
        {
            var s = SettingsStore.Load();
            var ids = QualityPresets.PresetIds;
            var i = System.Array.IndexOf(ids, s.Quality);
            if (i < 0) i = 1;
            i = (i + dir + ids.Length) % ids.Length;
            Apply(QualityPresets.ApplyPreset(s, ids[i]));
        }

        void CycleFps(int dir)
        {
            var s = SettingsStore.Load();
            var choices = QualityPresets.FpsChoices;
            var i = System.Array.IndexOf(choices, s.Fps);
            if (i < 0) i = 2;
            i = (i + dir + choices.Length) % choices.Length;
            s.Fps = choices[i];
            Apply(s);
        }

        void StepSens(double d)
        {
            var s = SettingsStore.Load();
            Apply(SettingsStore.WithSensitivity(s, s.Sensitivity + d));
        }

        void StepDist(double d)
        {
            var s = SettingsStore.Load();
            Apply(SettingsStore.WithCameraDistance(s, s.CameraDistance + d));
        }

        void ToggleShadows()
        {
            var s = SettingsStore.Load();
            s.Shadows = !s.Shadows;
            Apply(s);
        }

        void CycleBloom(int dir)
        {
            var s = SettingsStore.Load();
            var v = (s.Gfx.Bloom + dir + 4) % 4;
            Apply(QualityPresets.SetGfx(s, "bloom", v));
        }

        void ToggleSound()
        {
            var s = SettingsStore.Load();
            s.Sound = !s.Sound;
            Apply(s);
        }

        void StepBtn(double d)
        {
            var s = SettingsStore.Load();
            s.ButtonScale = Mathf.Clamp((float)(s.ButtonScale + d), 0.75f, 1.4f);
            Apply(s);
        }

        // ============================================================ skill
        void FireSkill()
        {
            if (_skillCd > 0f || _motor == null) return;
            _skillCd = SkillCdMax;
            _energy = Mathf.Min(100f, _energy + 10f);
            AnimeVFX.Skill(_motor.transform.position + Vector3.up);
            if (_cam != null) _cam.AddShake(0.35f);
        }

        void FireBurst()
        {
            if (_burstCd > 0f || _energy < 100f || _motor == null) return;
            _burstCd = BurstCdMax;
            _energy = 0f;
            AnimeVFX.Ult(_motor.transform.position + Vector3.up);
            if (_cam != null) _cam.AddShake(0.7f);
        }

        // ============================================================ update
        void Update()
        {
            if (_motor == null) _motor = FindFirstObjectByType<CharacterMotor>();
            if (_cam == null) _cam = FindFirstObjectByType<CameraRig>();
            var dt = Time.deltaTime;

            // Kompas + penanda utara minimap.
            if (_cam != null)
            {
                var yaw = _cam.Yaw;
                for (var i = 0; i < _dirLabels.Length; i++)
                {
                    var d = Mathf.DeltaAngle(yaw, DirYaw[i]);
                    var t = _dirLabels[i];
                    _dirRects[i].anchoredPosition = new Vector2(d * 4.2f, 0f);
                    var a = Mathf.Clamp01(1f - Mathf.Abs(d) / 62f);
                    t.color = new Color(1f, 1f, 1f, a);
                }
                if (_nMark != null)
                {
                    var nd = (yaw - 180f) * Mathf.Deg2Rad;
                    _nMark.anchoredPosition =
                        new Vector2(Mathf.Sin(nd) * 74f, Mathf.Cos(nd) * 74f);
                }
            }

            // Pelacak region (teks hanya ditulis saat region berubah).
            if (_motor != null)
            {
                var p = _motor.transform.position;
                var region = WorldData.RegionAt(p.x, p.z);
                if (region.Id != _regionId)
                {
                    _regionId = region.Id;
                    _regionName.text = region.Name;
                    _regionSub.text = region.Subtitle;
                }
                // Stamina.
                var st = _motor.Stamina01;
                UiKit.SetBar(_stamFill, st);
                var showStam = st < 0.999f;
                _stamGroup.alpha += ((showStam ? 1f : 0f) - _stamGroup.alpha) *
                    Mathf.Min(1f, dt * 8f);
            }

            // Cooldown skill/burst + energi.
            _skillCd = Mathf.Max(0f, _skillCd - dt);
            _burstCd = Mathf.Max(0f, _burstCd - dt);
            _energy = Mathf.Min(100f, _energy + 5f * dt);
            SetCd(_skill, _skillCd / SkillCdMax, _skillCd);
            if (_burstCd > 0f) SetCd(_burst, _burstCd / BurstCdMax, _burstCd);
            else if (_energy < 100f) SetCd(_burst, 1f - _energy / 100f, -1f);
            else SetCd(_burst, 0f, 0f);
            if (_burstRing != null) _burstRing.fillAmount = _energy / 100f;

            // FPS (teks diupdate 2x/detik, bukan tiap frame).
            _fpsAcc += dt;
            _fpsN++;
            if (_fpsAcc >= 0.5f)
            {
                _fpsShown = _fpsN / _fpsAcc;
                _fpsAcc = 0f;
                _fpsN = 0;
                if (_fpsText != null) _fpsText.text = $"{_fpsShown:F0} fps";
            }
        }

        static void SetCd(HudButton b, float frac, float seconds)
        {
            if (b == null || b.CdOverlay == null) return;
            b.CdOverlay.fillAmount = Mathf.Clamp01(frac);
            b.CdText.text = seconds > 0f ? Mathf.CeilToInt(seconds).ToString() : "";
        }
    }
}
