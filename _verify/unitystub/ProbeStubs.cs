// ============================================================
//  Stub untuk API yang dipakai PROBE RENDER di PerfHud.
//  Aturan yang sama seperti berkas stub lain: hanya API Unity yang
//  memang ada, ditiru tandatangannya, TANPA perilaku. Yang diuji di sini
//  adalah kode pemakainya (nullable, enum, urutan), bukan Unity.
// ============================================================
namespace UnityEngine
{
    // Object.FindObjectsByType<T>(FindObjectsSortMode) -- pengganti
    // FindObjectsOfType di Unity 2021.3+; sensus renderer probe memakainya.
    public enum FindObjectsSortMode { None = 0, InstanceID = 1 }

    // Nilai enum disalin dari UnityEngine.SystemInfo.graphicsDeviceType.
    public enum GraphicsDeviceType
    {
        Unknown = 0, Null = 1, Direct3D9 = 4, Direct3D11 = 2, Direct3D12 = 12,
        OpenGLES2 = 8, OpenGLES3 = 11, Metal = 16, OpenGLCore = 17, Vulkan = 21
    }

    public static class SystemInfo
    {
        public static GraphicsDeviceType graphicsDeviceType => GraphicsDeviceType.Unknown;
        public static string graphicsDeviceName => "";
        public static int graphicsShaderLevel => 0;
        public static bool supportsParallelPSOCreation => true;
    }
}
