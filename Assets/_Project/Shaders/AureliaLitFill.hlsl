#ifndef AURELIA_LIT_FILL_INCLUDED
#define AURELIA_LIT_FILL_INCLUDED

// ============================================================
// Lantai pencahayaan HP. Angka HARUS sama dengan
// WorldLookPolicy.cs (MinShadowAtten / FillLight / AmbientFloor
// / KeepVisible). Tanpa ini, SampleSH=0 × shadow=0 = hitam pekat
// di Adreno/Mali (build CI ke-5, screenshot HP 2026-09-16).
// ============================================================

half AureliaMinShadow(half rawAtten)
{
    return max(rawAtten, 0.45);
}

half3 AureliaAmbientOrFloor(half3 sh, half boost)
{
    half3 a = sh * boost;
    half lum = a.r + a.g + a.b;
    return lum < 0.05 ? half3(0.28, 0.30, 0.34) * boost : a;
}

half3 AureliaFill(half3 albedo, half boost)
{
    return albedo * (0.32 * boost);
}

half3 AureliaKeepVisible(half3 lit, half3 albedo)
{
    return max(lit, albedo * 0.40);
}

#endif
