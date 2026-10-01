# UAL2 Playground (Unity, Android)

Game Unity yang dibangun ulang dari nol:

- **World datar tanpa batas** dengan garis grid kotak-kotak (shader world-space — lantai selalu mengikuti pemain sehingga tidak pernah ada ujungnya).
- **Universal Animation Library 2 [Standard]** dari [Quaternius](https://quaternius.com) dipakai **lengkap (43 animasi)** — sumber: [KyokoApp/Godot](https://github.com/KyokoApp/Godot/tree/main/Universal%20Animation%20Library%202%5BStandard%5D), lisensi CC0.
- **Kontrol sentuh Android** yang diposisikan rapi (safe-area aware):
  - **Analog kiri-bawah** — jalan (miring sedikit) sampai lari (miring penuh), arah relatif kamera.
  - **LOMPAT** (tombol besar kanan-bawah) — NinjaJump Start → Idle Loop → Land.
  - **SERANG** — combo pedang A → B → C (tap beruntun).
  - **SLIDE** — Slide Start → Loop → Exit sambil meluncur.
  - **LARI** (toggle) — sprint.
  - **ANIMASI** (kanan-atas) — panel scroll berisi **semua 43 animasi UAL2**, tap untuk memainkan.
  - **GANTI MODEL** — tukar mannequin UAL2 ↔ Mannequin F (retarget Humanoid).
  - **Geser layar kanan** — memutar kamera orbit.

## Cara buka

1. Install **Unity Hub** + editor **2022.3 LTS** (atau lebih baru) dengan modul **Android Build Support (SDK/NDK/OpenJDK)**.
2. `Add project` → pilih folder repo ini → buka.
3. Import pertama memakan waktu beberapa menit (FBX 24 MB berisi 43 animasi).
4. Buka `Assets/Scenes/Main.unity` lalu tekan **Play** (di editor, analog bisa di-drag pakai mouse).

## Build APK

1. `File ▸ Build Settings ▸ Android ▸ Switch Platform`.
2. `Build` → hasilkan `.apk` → install di HP.
   - Orientasi landscape, IL2CPP, ARMv7 + ARM64, min SDK 23 sudah dikonfigurasi di `ProjectSettings`.

## Struktur

```
Assets/
  Scenes/Main.unity          # scene: kamera, lampu, GameBootstrap
  Scripts/                   # semua logika (world, player, animasi, UI dibangun runtime)
  Resources/UAL2/            # UAL2_Standard.fbx (43 anim) + Mannequin_F.fbx (Humanoid)
  Resources/Shaders/         # shader grid tanpa batas
  UAL2/                      # License (CC0) + README asli dari Quaternius
```

## Kredit

- Animasi & model: **Quaternius — Universal Animation Library 2 [Standard]**, lisensi **CC0 1.0** (public domain). Dukung di [patreon.com/quaternius](https://www.patreon.com/quaternius).
