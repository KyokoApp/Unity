namespace RPG.Runtime
{
    /* ============================================================
       HUD INPUT — jembatan tombol HUD -> CharacterMotor.

       Tombol uGUI hanya menyetel flag; motor membaca semuanya di
       Update lalu memanggil ResetFrame(). Pola ini (bukan event
       langsung) supaya tidak ada input yang hilang atau dobel
       walau urutan Update berubah-ubah.
       ============================================================ */
    public static class HudInput
    {
        public static bool AttackPressed;
        public static bool JumpPressed;
        public static bool DashPressed;
        public static bool SkillPressed;
        public static bool BurstPressed;

        public static void ResetFrame()
        {
            AttackPressed = false;
            JumpPressed = false;
            DashPressed = false;
            SkillPressed = false;
            BurstPressed = false;
        }
    }
}
