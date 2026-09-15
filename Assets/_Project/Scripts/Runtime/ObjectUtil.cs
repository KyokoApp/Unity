// ============================================================
// ObjectUtil.cs
//
// Kenapa file ini ada: OnDestroy() TIDAK hanya jalan saat game
// dimainkan. Ia juga jalan ketika Editor menutup komponen --
// termasuk saat build player di batchmode, dan saat komponen
// [ExecuteAlways] (WaterPlane, TerrainChunkStreamer) dimatikan atau
// scene-nya ditutup. Di semua situasi itu Application.isPlaying == false,
// dan Destroy() ilegal: Unity melempar
// "Destroy may not be called from edit mode! Use DestroyImmediate instead."
// yang muncul sebagai error build.
//
// Aturan Unity-nya sendiri: Destroy() menunda penghancuran sampai akhir
// frame (butuh player loop yang sedang jalan), DestroyImmediate()
// menghancurkan sekarang (satu-satunya pilihan saat tidak ada loop).
// ============================================================
using UnityEngine;

namespace RPG.Runtime
{
    static class ObjectUtil
    {
        public static void SafeDestroy(Object obj)
        {
            if (obj == null) return;
            if (Application.isPlaying) Object.Destroy(obj);
            else Object.DestroyImmediate(obj);
        }
    }
}
