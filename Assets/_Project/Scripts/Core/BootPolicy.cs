namespace RPG.Core
{
    /* ============================================================
       BOOT POLICY — kapan loading WAJIB melepas pemain ke dunia.

       Bug yang diobati: WorldBoot lama menunggu Progress01 > 0,999
       (SEMUA chunk radius 2–3 = 25–49 mesh) plus PopulateNow rumput
       setiap frame. Di HP, satu frame yang membangun 4 chunk tanpa
       yield bisa membekukan main thread — failsafe 25 detik tidak
       pernah jalan karena coroutine tidak sempat kembali.

       Aturan baru (diuji, tanpa Unity):
         1. Minimal splash 0,55 dtk supaya tidak kedip.
         2. Begitu 1 chunk dekat ada, MASUK.
         3. Setelah 1,15 dtk, masuk WALAU 0 chunk (terrain menyusul
            di latar). Lebih baik padang kosong 2 detik daripada
            krem selamanya.
         4. Dinding mutlak 4 dtk.
       ============================================================ */
    public static class BootPolicy
    {
        public const double MinShowSec = 0.55;
        public const double SoftEnterSec = 1.15;
        public const double WallSec = 4.0;
        public const int MinChunksToEnter = 1;

        /* LoadingScreen punya timeout sendiri, sedikit lebih longgar
           dari WallSec, supaya tetap menyelamatkan kalau WorldBoot
           tidak pernah Start(). */
        public const double OverlayFailsafeSec = 4.5;

        public static bool ShouldEnter(double elapsedSec, int activeChunks, bool streamerGone)
        {
            if (elapsedSec >= WallSec) return true;
            if (elapsedSec >= SoftEnterSec) return true;
            if (elapsedSec >= MinShowSec &&
                (activeChunks >= MinChunksToEnter || streamerGone))
                return true;
            return false;
        }
    }
}
