using System;
using UnityEngine;

namespace RPG.Runtime
{
    /* ============================================================
       WORLD BOOT — langsung masuk dunia. TANPA loading screen.

       User 2026-09-17: loading macet terus, dan kalau sudah masuk
       dunia tetap hitam. Overlay loading dihapus. Motor + kamera
       tidak pernah dimatikan. Terrain streaming jalan di Update
       streamer seperti biasa, di belakang HUD.
       ============================================================ */
    [DisallowMultipleComponent]
    [DefaultExecutionOrder(-200)]
    public class WorldBoot : MonoBehaviour
    {
        public static WorldBoot Instance { get; private set; }

        bool _entered;
        public bool Done => _entered;

        void Awake()
        {
            Instance = this;
            if (GetComponent<WorldLookDriver>() == null)
                gameObject.AddComponent<WorldLookDriver>();
            EnterWorld();
        }

        void Start()
        {
            try
            {
                if (GenshinHud.Instance == null) GenshinHud.Create();
                GenshinHud.SetVisible(true);
            }
            catch (Exception e)
            {
                BootLog.Add("[FATAL-sub] HUD: " + e.GetType().Name + ": " + e.Message);
            }
            try { WorldLook.OnEnteredWorld(); } catch { }
        }

        void OnDestroy()
        {
            if (Instance == this) Instance = null;
        }

        public void EnterWorld()
        {
            if (_entered) return;
            _entered = true;
            try { LoadingScreen.HideImmediate(); } catch { }
            try
            {
                var m = FindFirstObjectByType<CharacterMotor>();
                if (m != null) m.enabled = true;
            }
            catch { }
            try
            {
                var c = FindFirstObjectByType<CameraRig>();
                if (c != null)
                {
                    c.enabled = true;
                    c.SnapNow();
                }
            }
            catch { }
            BootLog.Add("boot: langsung masuk dunia, tanpa loading.");
        }

        public static void ForceEnter()
        {
            if (Instance != null)
            {
                Instance.EnterWorld();
                return;
            }
            try { LoadingScreen.HideImmediate(); } catch { }
            try { GenshinHud.SetVisible(true); } catch { }
            try
            {
                var m = FindFirstObjectByType<CharacterMotor>();
                if (m != null) m.enabled = true;
            }
            catch { }
            try
            {
                var c = FindFirstObjectByType<CameraRig>();
                if (c != null) { c.enabled = true; c.SnapNow(); }
            }
            catch { }
            try { WorldLook.OnEnteredWorld(); } catch { }
        }
    }
}
