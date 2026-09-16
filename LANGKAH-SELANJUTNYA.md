# Langkah Selanjutnya (handoff sesi 2026-09-17, Tahap 5f)

> Sesi ini = `arena/01a0aa20-unity`. Jangan pindah branch. Jangan mulai
> Tahap 6 sebelum HP menampilkan tanah berwarna.

## 1. Posisi

- **5e** (`v0.3.3-tahap5e`) belum cukup: user masih stuck loading +
  black screen.
- **5f**: loading DIHAPUS (langsung dunia). Terrain UNLIT. Fog /
  shadow / bloom / rumput mati. Langit SolidColor dipaksa tiap frame.

## 2. Setelah push

1. Tag `v0.3.4-tahap5f` → APK.
2. Install. Harus: **tidak ada layar krem**, tanah hijau/coklat,
   langit biru, kamera di belakang karakter, HUD Genshin.
3. Baru Tahap 6.

## 3. File kunci 5f

| File | Isi |
|---|---|
| `WorldBoot.cs` | Masuk dunia di Awake, tanpa coroutine |
| `LoadingScreen.cs` | Stub: tidak pernah menggambar |
| `WorldLookDriver.cs` | LateUpdate: fog off, SolidColor, no HDR |
| `AureliaTerrain.shader` | Unlit vertex color |
