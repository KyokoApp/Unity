namespace RPG.Runtime
{
    /* ============================================================
       LOADING SCREEN — DIMATIKAN.

       Overlay krem menahan pemain dan di HP sering tidak pernah
       Hide (coroutine macet / exception rumput). User minta hapus
       saja: masuk dunia langsung. API tetap ada supaya pemanggil
       lama kompilasi, tapi tidak pernah membuat canvas.
       ============================================================ */
    public static class LoadingScreen
    {
        public static bool IsShown => false;
        public static bool WantSkip => false;

        public static void Show() { }
        public static void SetProgress(float frac, string status) { }
        public static void Hide() { }
        public static void HideImmediate() { }
        public static void ShowError(string text) { }
    }
}
