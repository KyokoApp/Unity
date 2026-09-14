# Harness verifikasi paritas

Membandingkan `RPG.Core` (C#) terhadap modul JS ASLI, baris per baris.
Ini yang menjaga port tidak menyimpang diam-diam.

## Butuh repo three.js di sebelahnya

Harness mengimpor modul JS asli, jadi strukturnya harus:

    parent/
      rpg/game/world-data.mjs      <- clone KyokoApp/rpg
      unity-rpg/_verify/           <- folder ini

Kalau tidak, edit path import di `dump-js.mjs`.

## Menjalankan

    export DOTNET_ROOT=/path/ke/dotnet; export PATH=$DOTNET_ROOT:$PATH
    cd _verify
    node dump-js.mjs > js.txt                    # butuh Node 20+
    dotnet run -c Release > cs.txt
    python3 compare.py js.txt cs.txt             # harus bilang SETARA

    cd nunit && dotnet test                      # harus 7/7

Catatan: `world-3km.mjs` dan `world-scatter-3km.mjs` adalah FIXTURE yang
diturunkan secara mekanis dari modul aslinya pada konstanta dunia 3 km
(skrip pembuatnya: 33 dan 1 substitusi ter-assert). Unity memang sengaja
berbeda angka dari versi three.js yang masih live (3 km vs 6 km, tanpa mobil),
jadi perbandingan dilakukan pada konstanta yang sama lewat fixture ini.

## Uji mutasi

Kalau mau memastikan tesnya benar-benar punya gigi, rusak satu angka di
`WorldScatter.cs` (mis. ambang `.22` jadi `.23`) dan pastikan NUnit MERAH.
Kalau tetap hijau, cakupan tesnya kurang.
