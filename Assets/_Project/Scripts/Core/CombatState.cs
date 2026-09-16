using System;

namespace RPG.Core
{
    /* ============================================================
       COMBAT STATE — logika tempur & stamina, MURNI (tanpa Unity).

       Alasan ditaruh di Core: aturan kombo ("serangan ke-2 dalam
       0,9 detik = kombo 1") dan stamina ("regen setelah 1 detik
       tidak dipakai") adalah ATURAN MAIN, bukan presentasi. Di sini
       ia bisa dites headless; CharacterMotor tinggal memanggilnya.

       Semua waktu dalam DETIK, stamina 0..1.
       ============================================================ */
    public sealed class CombatState
    {
        public double Stamina = 1.0;

        /* >= 0 = sedang menyerang (detik sejak tebasan mulai).
           -1 = idle. */
        public double AttackT = -1.0;
        public int Combo;                       // 0..2, arah tebasan
        public double AttackDur = 0.55;         // lama satu tebasan
        public double ComboWindow = 0.9;        // jeda maks antar tebasan
        public double StaminaRegen = 0.3;       // per detik
        public double RegenDelay = 1.0;         // jeda sebelum regen jalan

        double _lastEnd = -100.0;
        double _sinceUse = 100.0;

        public bool IsAttacking => AttackT >= 0.0;

        public double Attack01 =>
            AttackT < 0.0 ? 0.0 : Math.Min(1.0, AttackT / Math.Max(1e-6, AttackDur));

        /* now = waktu game (detik). Gagal kalau masih mid-swing. */
        public bool TryAttack(double now)
        {
            if (AttackT >= 0.0) return false;
            Combo = (now - _lastEnd < ComboWindow) ? (Combo + 1) % 3 : 0;
            AttackT = 0.0;
            return true;
        }

        /* now = waktu game. staminaDrain = stamina/detik (0 = regen). */
        public void Update(double dt, double now, double staminaDrain)
        {
            if (AttackT >= 0.0)
            {
                AttackT += dt;
                if (AttackT >= AttackDur) { AttackT = -1.0; _lastEnd = now; }
            }

            if (staminaDrain > 0.0)
            {
                Stamina = Math.Max(0.0, Stamina - staminaDrain * dt);
                _sinceUse = 0.0;
            }
            else
            {
                _sinceUse += dt;
                if (_sinceUse > RegenDelay)
                    Stamina = Math.Min(1.0, Stamina + StaminaRegen * dt);
            }
        }

        /* Dash/skill: gagal kalau stamina kurang (tidak jadi negatif). */
        public bool SpendStamina(double amount)
        {
            if (Stamina < amount) return false;
            Stamina -= amount;
            _sinceUse = 0.0;
            return true;
        }

        public void Reset()
        {
            Stamina = 1.0; AttackT = -1.0; Combo = 0;
            _lastEnd = -100.0; _sinceUse = 100.0;
        }
    }
}
