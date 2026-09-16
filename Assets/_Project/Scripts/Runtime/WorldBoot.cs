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
       ============================================================ */
    [DisallowMultipleComponent]
    public class WorldBoot : MonoBehaviour
    {
        [Header("Kecepatan boot")]
        [Tooltip("Chunk dibangun per frame saat loading.")]
        [Range(1, 12)] public int BuildsPerFrame = 4;
        [Tooltip("Loading minimal tampil selama ini (detik) supaya tidak berkedip.")]
        public float MinShowTime = 0.9f;

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

            LoadingScreen.Show();
            /* HUD dibangun di sini (runtime), bukan oleh builder — sprite
               prosedural UiKit tidak selamat kalau scene disimpan. */
            GenshinHud.Create();
            GenshinHud.SetVisible(false);
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

            var guard = 0;
            while (true)
            {
                _elapsed += Time.unscaledDeltaTime;

                var prog = 1f;
                string status = "menyiapkan";
                if (_streamer != null)
                {
                    _streamer.EditorStreamNow(BuildsPerFrame);
                    prog = _streamer.Progress01 * 0.92f;
                    status = $"memuat dunia ({_streamer.ActiveChunks} chunk)";
                }
                if (_grass != null)
                {
                    _grass.PopulateNow();
                    prog = Mathf.Max(prog, 0.92f);
                    status = "menabur rumput";
                }
                if (_streamer == null && _grass == null)
                    prog = 1f;

                LoadingScreen.SetProgress(Mathf.Clamp01(prog), status);

                var streamed = _streamer == null ||
                    (_streamer.QueuedChunks == 0 && _streamer.Progress01 > 0.999f);
                if (streamed && _elapsed >= MinShowTime) break;

                // Jaring pengaman: jangan loading selamanya (mis. target null).
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
            Debug.Log($"[WorldBoot] dunia siap dalam {_elapsed:F2} detik.");
        }

        public bool Done => _done;
    }
}
