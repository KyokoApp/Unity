using System;

namespace RPG.Core
{
    /* ============================================================
       JS-MATH — pembulatan yang SETIA kepada ECMAScript.

       Ini ada karena uji paritas JS-vs-C# menangkap bug nyata:
       Math.Round bawaan .NET memakai BANKER'S ROUNDING (ToEven),
       sedangkan Math.round di JS membulatkan setengah ke +Infinity.

           Math.round(22.5)   di JS   -> 23
           Math.Round(22.5)   di .NET -> 22   <-- beda!

       Akibatnya nyata, bukan kosmetik: dustCount preset 'balanced'
       jadi 22 alih-alih 23, birdCount 8 alih-alih 9, fogFar 1282
       alih-alih 1283. Jumlah partikel dan jarak pandang bergeser
       diam-diam dari versi three.js.

       Karena itu SEMUA pembulatan yang di-port dari JS wajib lewat
       kelas ini. Jangan panggil Math.Round langsung di RPG.Core.
       ============================================================ */
    public static class JsMath
    {
        /* Definisi ECMAScript: Math.round(x) = floor(x + 0.5).
           NaN tetap NaN; +Inf/-Inf tetap apa adanya. */
        public static double Round(double v)
        {
            if (double.IsNaN(v) || double.IsInfinity(v)) return v;
            return Math.Floor(v + 0.5);
        }

        public static int RoundToInt(double v)
        {
            var r = Round(v);
            /* Jaga-jaga nilai di luar rentang int; tidak terjadi pada
               angka di game ini, tapi cast yang overflow itu undefined. */
            if (r > int.MaxValue) return int.MaxValue;
            if (r < int.MinValue) return int.MinValue;
            return (int)r;
        }
    }
}
