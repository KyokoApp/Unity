# Karakter & Animasi Pemain

## Masalah kemarin (T-pose)

`main_character.tscn` menampilkan mesh **mannequin (rig sendiri, 65 bone)**
yang disisipkan di dalam `RobotArmature`, sementara semua animasi menargetkan
**skeleton robot (25 bone)**. Karena mesh mannequin tidak diikat ke skeleton
robot, ia tidak pernah bergerak → T-pose permanen. Jalur "retarget/universal
animation" yang dipaksa di sini memang rawan gagal — dan sekarang tidak lagi
diperlukan.

## Solusi: KayKit Knight (satu file, langsung jalan)

- File: `_models/kaykit/Knight.glb` (±3.5 MB) — **skeleton + mesh + 76 animasi
  dalam satu GLB**, tanpa retarget. Lisensi CC0 (salinan ada di
  `_models/kaykit/LICENSE-CC0-KayKit.txt`, kredit: Kay Lousberg).
- Terrain + UI ukurannya: Knight low-poly chibi ~cocok dengan gaya kartun +
  toon outline yang memang sudah dipasang otomatis oleh
  `MainCharacter.ApplyToonOutline()` (outline rekursif dari `RobotArmature`,
  jadi model baru otomatis ikut ter-outline).
- `_scenes/main_character.tscn`:
  - `RobotArmature/PlayerModel` sekarang me-instance `Knight.glb`
    (robot lama tetap ada sebagai mesh tersembunyi — skeleton-nya tidak
    dianimasikan lagi).
  - `AnimationTree.anim_player` diarahkan ke
    `RobotArmature/PlayerModel/AnimationPlayer` (AnimationPlayer bawaan GLB).
  - Mapping state machine (nama state sama, isi clip diganti):

    | State | Clip lama (robot) | Clip baru (KayKit) |
    |---|---|---|
    | Idle | Idle | `Idle` |
    | Run | Run | `Running_A` |
    | Sprint | Sprint | `Running_B` |
    | Fall | Fall | `Jump_Idle` (loop udara) |
    | Dive (glide) | Dive | `Jump_Idle` |
    | Hurt (dipakai utk `sitting`) | Hurt | `Sit_Floor_Idle` |
    | Kick | Kick | `Unarmed_Melee_Attack_Kick` |
    | Attack1 (dipakai utk `tossing`) | Attack1 | `Throw` |
    | LongJump (orphan) | LongJump | `Jump_Full_Long` |

- `MainCharacter.ConfigureModelAnimationLoops()` memaksa loop-mode non-loop
  clip menjadi loop (Idle/Run/Sprint/Fall/Sit) dan one-shot untuk serangan —
  tidak tergantung setelan import.

## Animasi lain yang tersedia di GLB (untuk dipakai nanti)

`Walking_A/B/C`, `Jump_Start`, `Jump_Land`, `Dodge_*`, `Block*`, `Hit_A/B`,
`Death_A/B` + pose, `Cheer`, `Interact`, `PickUp`, `Use_Item`, `Sword_*`,
`Spellcast_*`, `Sit_Chair_*`, `Lie_*`, `1H/2H_Melee_Attack_*`, `T-Pose` dsb.
— 76 clip total, siap dipetakan ke tombol aksi baru tanpa aset tambahan.

## Model cadangan

- Robot resmi Godot (`_models/3DGodotRobot.glb`) tetap utuh dan DIANJURKAN
  sebagai fallback (mesh-nya tinggal di-unhide di `RobotArmature` bila
  diperlukan).
- Aset mannequin/UAL (`mannequin_f.glb` & `ual_anims.glb`) serta direktori
  `Universal Animation Library 2[Standard]` telah dihapus dari repositori
  karena riwayat T-pose dan untuk menghemat ukuran repo (>80MB).

## Catatan edit cepat

- Ukuran/arah model ada di node `RobotArmature/PlayerModel` (scale 1.7).
  Bila model tampak jalan mundur, putar `rotation_degrees.Y = 180` di node itu.
