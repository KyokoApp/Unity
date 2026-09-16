using System;
using System.Collections;
using UnityEngine;
using RPG.Core;

namespace RPG.Runtime
{
    /* ============================================================
       WORLD BOOT — masuk dunia tanpa macet.

       Urutan: loading tampil (1 frame) -> stream SEBAGIAN chunk
       dengan anggaran waktu per frame -> MASUK. Rumput, sisa
       chunk, HUD yang gagal: semuanya opsional.

       Pengerasan Tahap 5d (masih macet setelah 5c):
       - Tidak menunggu Progress01 == 1 (25–49 chunk). Satu chunk
         dekat + 0,55 dtk splash = masuk. Lihat BootPolicy.
       - Streaming beranggaran waktu (bukan N chunk tanpa yield),
         jadi main thread tidak membeku dan failsafe bisa jalan.
       - Rumput TIDAK di-populate di sini (LateUpdate-nya sendiri
         yang menabur setelah masuk).
       - HUD dibangun di coroutine, bukan Awake: hang di HUD tidak
         mencegah Start() / failsafe overlay.
       - EnterWorld idempoten; LoadingScreen failsafe memanggil
         WorldBoot.ForceEnter dari timeout overlay yang independen.
       ============================================================ */
    [DisallowMultipleComponent]
    [DefaultExecutionOrder(-200)]
    public class WorldBoot : MonoBehaviour
    {
        public static WorldBoot Instance { get; private set; }

        [Header("Kecepatan boot")]
        [Tooltip("Anggaran milidetik membangun chunk per frame saat loading.")]
        [Range(2f, 16f)] public float StreamBudgetMs = 8f;

        TerrainChunkStreamer _streamer;
        CharacterMotor _motor;
        CameraRig _camRig;
        float _elapsed;
        bool _entered;

        public bool Done => _entered;

        void Awake()
        {
            Instance = this;
            _streamer = FindFirstObjectByType<TerrainChunkStreamer>();
            _motor = FindFirstObjectByType<CharacterMotor>();
            _camRig = FindFirstObjectByType<CameraRig>();

            try { LoadingScreen.Show(); }
            catch (Exception e)
            {
                BootLog.Add("[FATAL-sub] loading: " + e.GetType().Name + ": " + e.Message);
            }
            if (_motor != null) _motor.enabled = false;
            if (_camRig != null) _camRig.enabled = false;
        }

        void OnDestroy()
        {
            if (Instance == this) Instance = null;
        }

        void Start()
        {
            StartCoroutine(Boot());
        }

        IEnumerator Boot()
        {
            yield return null;

            var wallStart = Time.realtimeSinceStartup;
            BootLog.Add("boot mulai.");
            var streamerDead = false;

            try
            {
                try
                {
                    GenshinHud.Create();
                    GenshinHud.SetVisible(false);
                }
                catch (Exception e)
                {
                    BootLog.Add("[FATAL-sub] HUD: " + e.GetType().Name + ": " + e.Message);
                }

                while (!_entered)
                {
                    _elapsed = Time.realtimeSinceStartup - wallStart;

                    var chunks = 0;
                    string status = "menyiapkan";
                    if (_streamer != null && !streamerDead)
                    {
                        try
                        {
                            chunks = _streamer.StreamBudgeted(StreamBudgetMs);
                            status = chunks > 0
                                ? $"memuat dunia ({chunks} chunk)"
                                : "memuat dunia";
                        }
                        catch (Exception e)
                        {
                            streamerDead = true;
                            BootLog.Add("[FATAL-sub] streamer: " + e.GetType().Name + ": " + e.Message);
                        }
                    }

                    var prog = _streamer != null && !streamerDead
                        ? Mathf.Clamp01(0.15f + _streamer.Progress01 * 0.75f)
                        : Mathf.Clamp01((float)(_elapsed / BootPolicy.SoftEnterSec));
                    try { LoadingScreen.SetProgress(prog, status); }
                    catch { /* overlay rusak: tetap masuk */ }
                    if (BootLog.HasErrors)
                    {
                        try { LoadingScreen.ShowError(BootLog.Tail()); }
                        catch { }
                    }

                    var gone = _streamer == null || streamerDead;
                    if (BootPolicy.ShouldEnter(_elapsed, chunks, gone) || LoadingScreen.WantSkip)
                        break;

                    yield return null;
                }
            }
            catch (Exception e)
            {
                BootLog.Add("[FATAL] boot: " + e.GetType().Name + ": " + e.Message);
            }
            finally
            {
                EnterWorld();
            }
        }

        /* Idempoten. Dipanggil dari coroutine, finally, dan
           LoadingScreen failsafe (kalau coroutine tidak jalan). */
        public void EnterWorld()
        {
            if (_entered) return;
            _entered = true;
            try { LoadingScreen.HideImmediate(); } catch { }
            try
            {
                if (GenshinHud.Instance == null) GenshinHud.Create();
                GenshinHud.SetVisible(true);
            }
            catch (Exception e)
            {
                BootLog.Add("[FATAL-sub] HUD masuk: " + e.GetType().Name + ": " + e.Message);
            }
            try { if (_motor != null) _motor.enabled = true; } catch { }
            try
            {
                if (_camRig != null)
                {
                    _camRig.enabled = true;
                    _camRig.SnapNow();
                }
            }
            catch { }
            BootLog.Add($"boot selesai dalam {_elapsed:F2} detik.");
            Debug.Log($"[WorldBoot] dunia siap dalam {_elapsed:F2} detik.");
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
        }
    }
}
