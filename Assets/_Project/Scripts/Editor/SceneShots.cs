// ============================================================
// SceneShots.cs
//
// Screenshot in-game TANPA PC dan tanpa perangkat: diambil di dalam
// build CI, tepat sebelum BuildPlayer, lalu diunggah sebagai artifact
// "screenshots" yang bisa dibuka dari halaman run lewat browser HP.
//
// KENAPA DI OnPreprocessBuild
// ---------------------------
// Tidak ada jalur lain yang melihat scene lengkap (karakter VRM sudah
// diimpor, terrain sudah bisa dipaksa streaming, rumput sudah bisa
// dipaksa populate) sebelum dikemas. Di batchmode tidak ada jendela
// game, jadi tangkapannya manual: kamera dirender ke RenderTexture,
// dibaca pikselnya, disimpan PNG.
//
// KENAPA DIBUNGKUS try/catch YANG MENELAN SEMUA EXCEPTION
// -------------------------------------------------------
// Screenshot adalah mata kita, bukan alasan build boleh gagal. Kalau
// GL di runner bermasalah, build APK tetap harus jalan; cukup satu
// baris PERINGATAN di log.
// ============================================================
using System;
using System.Collections.Generic;
using System.IO;
using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;
using RPG.Core;

namespace RPG.Editor
{
    public static class SceneShots
    {
        public const string Folder = "shots";

        /* Tiga suasana yang paling menjelaskan keadaan dunia: siang
           (pencahayaan netral + jarak pandang), senja (uji warna langit
           dan kabut), malam (uji ambient dan matahari redup). */
        static readonly float[] Jam   = { 12f, 17.4f, 21.5f };
        static readonly string[] Nama = { "siang", "senja", "malam" };

        public static void Capture(List<string> log)
        {
            try
            {
                var cam = Camera.main;
                if (cam == null)
                {
                    log.Add("PERINGATAN: screenshot dilewati -- MainCamera tidak ada.");
                    return;
                }

                var streamer = UnityEngine.Object.FindFirstObjectByType<RPG.Runtime.TerrainChunkStreamer>();
                var grass    = UnityEngine.Object.FindFirstObjectByType<RPG.Runtime.GrassField>();
                var cycle    = UnityEngine.Object.FindFirstObjectByType<RPG.Runtime.DayNightCycle>();
                var target   = grass != null && grass.Target != null ? grass.Target
                             : streamer != null ? streamer.Target : null;

                Directory.CreateDirectory(Folder);
                var jadi = 0;

                /* Karakter di-pose idle prosedural LEWAT JALUR RUNTIME YANG
                   SAMA (Locomotion -> RigMapping -> ApplyPose), supaya
                   screenshot mewakili tampilan in-game — bukan bind pose
                   T-pose yang membuat karakter terlihat seperti salib. */
                var rig = UnityEngine.Object.FindFirstObjectByType<RPG.Runtime.CharacterRig>();
                if (rig != null)
                {
                    if (!rig.IsBound) rig.Bind();
                    var idle = Locomotion.SamplePose(
                        new Locomotion.PoseInput(0, 1.0, 0, 0, 0, false, false, null));
                    rig.ApplyPose(RigMapping.Resolve(idle));
                }

                for (var i = 0; i < Jam.Length; i++)
                {
                    if (cycle != null) cycle.SetHour(Jam[i], false);

                    /* Dunia harus sudah ADA sebelum kamera merekam: di
                       batchmode tidak ada loop Update yang men-stream
                       terrain atau menabur rumput. */
                    if (streamer != null) streamer.EditorStreamNow(120);
                    if (grass != null) { grass.PopulateNow(); }

                    ComposeCamera(cam, target);

                    /* Rumput di-bake jadi satu mesh world-space supaya PASTI
                       ikut render manual — kebal terhadap quirks URP
                       (CommandBuffer kamera bisa diam-diam diabaikan). */
                    GameObject baked = null;
                    if (grass != null)
                    {
                        var msh = new Mesh { name = "ShotGrassBake" };
                        var nInst = grass.BakeInto(msh);
                        Debug.Log($"SceneShots: rumput dibake {nInst} instance untuk {Nama[i]} | state: {grass.InitState} | mat={grass.GrassMaterial != null}");
                        if (nInst > 0)
                        {
                            baked = new GameObject("ShotGrass");
                            baked.AddComponent<MeshFilter>().sharedMesh = msh;
                            var mr = baked.AddComponent<MeshRenderer>();
                            mr.sharedMaterial = grass.GrassMaterial;
                            mr.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
                            mr.receiveShadows = false;
                        }
                    }
                    try
                    {
                        var path = Path.Combine(Folder, $"ingame-{Nama[i]}.png");
                        if (RenderToPng(cam, path, 1280, 720)) jadi++;
                    }
                    finally
                    {
                        if (baked != null) UnityEngine.Object.DestroyImmediate(baked);
                    }
                }

                /* Kembalikan tulang ke bind pose supaya scene terbuka sama
                   seperti sebelum screenshot; runtime me-bind ulang sendiri. */
                if (rig != null) rig.ResetToBind();

                /* Kembalikan realtime supaya build player (dan game-nya
                   nanti) mulai dengan jam berjalan, bukan jam beku. */
                cycle?.SetHour(cycle.StartHour, true);

                log.Add(jadi > 0
                    ? $"Screenshot in-game: {jadi} file di {Folder}/ (siang, senja, malam)."
                    : "PERINGATAN: screenshot tidak menghasilkan file.");
            }
            catch (Exception e)
            {
                log.Add($"PERINGATAN: screenshot gagal ({e.GetType().Name}: {e.Message}). Build dilanjutkan.");
            }
        }

        /* Framing SAMA dengan CameraRig in-game (Genshin, ~3 m di
           belakang bahu). Dulu offset (-4.2, 2.6, -6.4) = 8 m — karakter
           sebesar semut, tidak mewakili permainan. */
        static void ComposeCamera(Camera cam, Transform target)
        {
            if (target == null || cam == null) return;
            RPG.Runtime.CameraRig.PlaceBehind(
                cam.transform, target.position,
                yawDeg: 12f,
                pitchDeg: (float)CameraFraming.DefaultPitchDeg,
                dist: (float)CameraFraming.DefaultMeters,
                focusHeight: (float)CameraFraming.DefaultFocusHeight,
                shoulder: (float)CameraFraming.DefaultShoulder);
            cam.fieldOfView = 50f;
            RPG.Runtime.WorldLook.PrepareCamera(cam);
        }

        static bool RenderToPng(Camera cam, string path, int w, int h)
        {
            var rt = RenderTexture.GetTemporary(w, h, 24, RenderTextureFormat.ARGB32);
            var prevTarget = cam.targetTexture;
            var prevActive = RenderTexture.active;
            try
            {
                cam.targetTexture = rt;
                cam.Render();
                RenderTexture.active = rt;

                var tex = new Texture2D(w, h, TextureFormat.RGB24, false);
                tex.ReadPixels(new Rect(0, 0, w, h), 0, 0);
                tex.Apply();

                File.WriteAllBytes(path, tex.EncodeToPNG());
                UnityEngine.Object.DestroyImmediate(tex);
                return true;
            }
            finally
            {
                cam.targetTexture = prevTarget;
                RenderTexture.active = prevActive;
                RenderTexture.ReleaseTemporary(rt);
            }
        }
    }
}
