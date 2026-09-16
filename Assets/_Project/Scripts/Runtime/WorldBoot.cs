using System;
using System.Collections;
using UnityEngine;

namespace RPG.Runtime
{
    /* ============================================================
       WORLD BOOT — urutan masuk dunia ala Genshin:

         loading tampil -> chunk awal di-stream (sinkron, beberapa
         frame, dengan progress bar) -> rumput ditabur -> fade out
         -> input dinyalakan.

       Kenapa sinkron, bukan thread latar: thread streamer tetap
       jalan untuk chunk BERIKUTNYA, tapi 25 chunk PERTAMA harus ada
       sebelum pemain melihat apa pun. Membangunnya sinkron 3-4 per
       frame = ~8 frame (~0,2 detik) dengan loading menutupinya.

       Pengerasan Tahap 5c (kasus "macet di loading" di HP):
       - tiap subsistem (loading, HUD, streamer, rumput) dibungkus
         try/catch sendiri. Subsistem yang melempar DINONAKTIFKAN dan
         boot LANJUT tanpa dia — main tanpa HUD/rumput/terrain jauh
         lebih baik daripada macet selamanya. TouchJoystick IMGUI
         tetap jalan sebagai stik cadangan kalau HUD mati.
       - error apa pun (termasuk dari thread latar, via BootLog)
         ditampilkan di kotak merah loading screen — tidak ada lagi
         kegagalan diam-diam yang tidak bisa didiagnosis tanpa PC.
       - failsafe jam dinding: setelah WallLimit detik, paksa masuk
         game apa pun yang terjadi.
       ============================================================ */
    [DisallowMultipleComponent]
    public class WorldBoot : MonoBehaviour
    {
        [Header("Kecepatan boot")]
        [Tooltip("Chunk dibangun per frame saat loading.")]
        [Range(1, 12)] public int BuildsPerFrame = 4;
        [Tooltip("Loading minimal tampil selama ini (detik) supaya tidak berkedip.")]
        public float MinShowTime = 0.9f;
        [Tooltip("Batas dinding mutlak: setelah sekian detik TETAP paksa masuk game.")]
        public float WallLimit = 25f;

        TerrainChunkStreamer _streamer;
        GrassField _grass;
        CharacterMotor _motor;
        CameraRig _camRig;
        float _elapsed;
        bool _done;

        void Awake()
        {
            _streamer = FindFirstObjectByType<TerrainChunkStreamer>();
            _grass = FindFirstObjectByType<GrassField>();
            _motor = FindFirstObjectByType<CharacterMotor>();
            _camRig = FindFirstObjectByType<CameraRig>();

            /* TIDAK ADA yang boleh menggagalkan boot di sini (lihat
               komentar kelas): HUD dibangun di sini (runtime), bukan
               oleh builder — sprite prosedural UiKit tidak selamat
               kalau scene disimpan. */
            try { LoadingScreen.Show(); }
            catch (Exception e)
            {
                BootLog.Add("[FATAL-sub] loading: " + e.GetType().Name + ": " + e.Message);
            }
            try
            {
                GenshinHud.Create();
                GenshinHud.SetVisible(false);
            }
            catch (Exception e)
            {
                BootLog.Add("[FATAL-sub] HUD: " + e.GetType().Name + ": " + e.Message);
            }
            if (_motor != null) _motor.enabled = false;
            if (_camRig != null) _camRig.enabled = false;
        }

        void Start()
        {
            StartCoroutine(Boot());
        }

        IEnumerator Boot()
        {
            // Biarkan satu frame ter-render (loading terlihat) dulu.
            yield return null;

            var wallStart = Time.realtimeSinceStartup;
            BootLog.Add("boot mulai.");
            var guard = 0;
            var streamerDead = false;
            var grassDead = false;

            while (true)
            {
                _elapsed += Time.unscaledDeltaTime;

                var prog = 1f;
                string status = "menyiapkan";
                if (_streamer != null && !streamerDead)
                {
                    try
                    {
                        _streamer.EditorStreamNow(BuildsPerFrame);
                        prog = _streamer.Progress01 * 0.92f;
                        status = $"memuat dunia ({_streamer.ActiveChunks} chunk)";
                    }
                    catch (Exception e)
                    {
                        streamerDead = true;
                        BootLog.Add("[FATAL-sub] streamer: " + e.GetType().Name + ": " + e.Message);
                    }
                }
                if (_grass != null && !grassDead)
                {
                    try
                    {
                        _grass.PopulateNow();
                        prog = Mathf.Max(prog, 0.92f);
                        status = "menabur rumput";
                    }
                    catch (Exception e)
                    {
                        grassDead = true;
                        BootLog.Add("[FATAL-sub] rumput: " + e.GetType().Name + ": " + e.Message);
                    }
                }
                if ((_streamer == null || streamerDead) && (_grass == null || grassDead))
                    prog = 1f;

                LoadingScreen.SetProgress(Mathf.Clamp01(prog), status);
                /* Kalau ada error dari subsistem mana pun (termasuk thread
                   latar), tampilkan di kotak merah — jangan macet diam-diam. */
                if (BootLog.HasErrors) LoadingScreen.ShowError(BootLog.Tail());

                var streamed = (_streamer == null || streamerDead) ||
                    (_streamer.QueuedChunks == 0 && _streamer.Progress01 > 0.999f);
                if (streamed && _elapsed >= MinShowTime) break;

                // Jaring pengaman jam dinding: jangan loading selamanya.
                if (Time.realtimeSinceStartup - wallStart > WallLimit)
                {
                    BootLog.Add($"[WorldBoot] FAILSAFE {WallLimit}s — paksa masuk " +
                        $"(streamerDead={streamerDead} grassDead={grassDead}).");
                    break;
                }
                // Jaring pengaman kedua: jangan loading selamanya (mis. target null).
                if (++guard > 900)
                {
                    Debug.LogWarning("[WorldBoot] guard 900 frame tercapai — lanjut paksa.");
                    break;
                }
                yield return null;
            }

            LoadingScreen.SetProgress(1f, "siap");
            LoadingScreen.Hide();
            GenshinHud.SetVisible(true);
            if (_motor != null) _motor.enabled = true;
            if (_camRig != null) _camRig.enabled = true;
            _done = true;
            BootLog.Add($"boot selesai dalam {_elapsed:F2} detik.");
            Debug.Log($"[WorldBoot] dunia siap dalam {_elapsed:F2} detik.");
        }

        public bool Done => _done;
    }
}
