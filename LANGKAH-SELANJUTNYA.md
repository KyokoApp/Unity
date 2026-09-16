# Langkah Selanjutnya (handoff sesi 2026-09-16, Tahap 5e)

> Sesi ini = `arena/01a0aa20-unity`. Jangan pindah branch. Jangan mulai
> Tahap 6 sebelum HP menampilkan dunia berwarna + HUD bersih.

## 1. Posisi sekarang

- Branch: `arena/01a0aa20-unity` (dari 5c `arena/01a0a964-unity`)
- **5d** (`v0.3.2-tahap5d`): boot tidak macet + kamera ~3,2 m. APK
  `35095655337` sukses, tapi screenshot HP masih hitam + UI menumpuk
  (sebagian shot masih 5c: "menabur rumput 92%").
- **5e** (komit ini): dunia tidak hitam, rumput tidak melempar, HUD
  tidak menumpuk chrome debug.

## 2. Yang harus dilakukan setelah push

1. Push branch, tag `v0.3.3-tahap5e` → workflow Android APK.
2. `gh run list -R KyokoApp/Unity --limit 5` — tunggu verify + APK.
3. Install APK dari Release. Harus:
   - Loading hilang ≤ ~2 detik / setelah ketuk, **tanpa kotak merah**.
   - Dunia **berwarna** (tanah + langit), bukan hitam + HUD.
   - Kamera di belakang bahu, karakter besar di sepertiga bawah.
   - HUD Genshin saja: tanpa teks DIAG / tombol Pagi/Siang / stik IMGUI
     "LARI/LOMPAT" menumpuk. F1 = PerfHud, F2 = tombol suasana.
4. **Baru setelah itu** Tahap 6 (`RENCANA-TAHAP-6.md`).

## 3. Konsolidasi branch

- PR #3 (`arena/01a0aa20-unity` → `main`) berisi 5d+5e. Jangan merge
  ke `main` dari sesi Arena ini.
- Jangan squash 5e ke 5c.

## 4. File kunci 5e

| File | Isi |
|---|---|
| `Assets/_Project/Scripts/Core/WorldLookPolicy.cs` | Lantai cahaya + log noisy + solid sky HP |
| `Assets/_Project/Scripts/Runtime/WorldLook.cs` | Kamera URP, langit HP, hide chrome, instancing |
| `Assets/_Project/Shaders/AureliaLitFill.hlsl` | Fill + min shadow (angka = policy) |
| `Assets/_Project/Shaders/AureliaTerrain.shader` | Tidak pernah output hitam |
| `Assets/_Project/Shaders/AureliaSky.shader` | Tanpa LightMode SRPDefaultUnlit |
| `Assets/_Project/Scripts/Runtime/GrassField.cs` | enableInstancing + skip saat loading |
| `Assets/_Project/Scripts/Runtime/TouchJoystick.cs` | Mundur kalau GenshinHud ada |
| `Assets/_Project/Scripts/Runtime/PerfHud.cs` | Default `Visible = false` |
