#ifndef AURELIA_TERRAIN_INPUT_INCLUDED
#define AURELIA_TERRAIN_INPUT_INCLUDED

// ============================================================
// Semua properti material terrain, dideklarasikan SEKALI di sini
// dan di-include oleh SETIAP Pass.
//
// Ini bukan gaya-gayaan. SRP Batcher menuntut dua hal:
//   (1) properti material berada di dalam CBUFFER UnityPerMaterial, dan
//   (2) isi cbuffer itu IDENTIK di semua Pass pada shader yang sama.
// Kalau salah satu tidak dipenuhi, shader ditandai "SRP Batcher: not
// compatible" dan 25 chunk terrain + bayangannya jadi 50 draw call
// terpisah. Di Adreno/Mali itu biaya CPU nyata, bukan teori.
//
// Cek di Unity: klik file shader, Inspector bagian atas tertulis
// "SRP Batcher compatible: Yes/No". Harus Yes.
// ============================================================

CBUFFER_START(UnityPerMaterial)
    float _DetailScale;
    float _DetailStrength;
    float _LargeScale;
    float _LargeStrength;
    float _AmbientBoost;
CBUFFER_END

#endif
