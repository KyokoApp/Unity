# Harness: kompilasi skrip Unity di luar Unity

Sandbox tempat project ini dibuat **tidak punya Unity**. Itu berarti skrip yang
menyentuh `UnityEngine` tidak bisa dikompilasi di sana — padahal justru di situ
salah ketik paling mudah terjadi.

Harness ini menutup celah itu sebagian: `Stubs.cs`, `Attrs.cs`, dan
`EditorStubs.cs` berisi tiruan tipe-tipe Unity (`MonoBehaviour`, `Vector3`,
`AssetDatabase`, `UniversalRenderPipelineAsset`, …), lalu `UnityStubCheck.csproj`
mengkompilasi **file C# yang benar-benar dikirim ke Unity** melawan tiruan itu.

`UniVrmStubs.cs` agak lain: ia meniru API **paket** UniVRM/UniGLTF v0.131.2 yang
dipakai `VrmPrefabBuilder.cs`. Tanda tangannya disalin dari sumber UniVRM pada
tag yang sama dengan yang dikunci `Packages/manifest.json` — bukan dikarang.
Kalau versi UniVRM berubah, file itu harus diperiksa ulang; stub yang menyimpang
dari API asli membuat harness hijau sementara Unity merah.

## Menjalankan

```
export DOTNET_ROOT=/path/ke/dotnet; export PATH=$DOTNET_ROOT:$PATH
cd _verify/unitystub && dotnet build
```

Harus `Build succeeded` dengan **0 error, 0 warning**.

## Apa yang IA buktikan

- Tidak ada salah ketik nama metode/properti **buatan kita sendiri**
- Tidak ada `using` yang hilang
- Tidak ada ketidakcocokan tipe di dalam kode kita (mis. `float` vs `int`,
  `Vector2` vs `Vector3`)
- Tidak ada anggota yang dipakai pada tipe yang salah

Harness ini pernah menangkap bug nyata: `GetComponentsInChildren<T>()`
mengembalikan **array**, tapi kodenya memakai `.Count` (milik `List`). Di Unity
asli itu error kompilasi. Sekarang sudah `.Length`.

## Apa yang TIDAK ia buktikan

- **Bahwa API Unity asli punya anggota yang saya stub.** Stub ditulis tangan;
  kalau saya mengarang metode yang tidak ada di Unity, harness tetap hijau.
  Karena itu API yang berisiko diverifikasi terpisah ke dokumentasi resmi:
  - `GraphicsSettings.defaultRenderPipeline` & `QualitySettings.renderPipeline`
    → dikonfirmasi di docs.unity3d.com (contoh resmi memakai persis pola ini)
  - `Object.FindFirstObjectByType<T>()` → dikonfirmasi ada di Unity 6
    (`FindObjectOfType` sudah obsolete, dan project ini menargetkan 0 warning)
  - `UniversalRenderPipelineAsset.Create(ScriptableRendererData)` → **belum
    dikonfirmasi ke dokumentasi**. Kalau baris itu error di Unity-mu, ganti
    `EnsureUrpAsset()` dengan membuat URP asset lewat menu
    *Assets → Create → Rendering → URP Asset (with Universal Renderer)*,
    lalu pasang manual di Graphics + Quality settings.
- Perilaku runtime. Harness ini cuma kompilasi, tidak menjalankan apa pun.

Yang benar-benar menjalankan kode adalah `_verify/nunit/` (untuk `RPG.Core`)
dan Test Runner di dalam Unity (untuk semuanya).
