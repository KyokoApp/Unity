using NUnit.Framework;
using RPG.Core;

namespace RPG.Tests
{
    /* Tes aturan tempur Tahap 5. Semua angka dihitung tangan dari
       CombatState (default: AttackDur 0,55, ComboWindow 0,9,
       StaminaRegen 0,3/detik, RegenDelay 1,0). */
    [TestFixture]
    public class CombatTests
    {
        const double Tol = 1e-9;

        [Test]
        public void Stamina_Terkuras_Saat_Sprint()
        {
            var c = new CombatState();
            c.Update(1.0, 1.0, 0.5);
            Assert.AreEqual(0.5, c.Stamina, Tol);
        }

        [Test]
        public void Stamina_Regen_Tertunda_1_Detik()
        {
            var c = new CombatState();
            c.Update(1.0, 1.0, 0.5);          // 1,0 -> 0,5
            c.Update(0.5, 1.5, 0.0);          // jeda 0,5: belum regen
            Assert.AreEqual(0.5, c.Stamina, Tol);
            c.Update(1.0, 2.5, 0.0);          // jeda 1,5: regen 0,3
            Assert.AreEqual(0.8, c.Stamina, Tol);
        }

        [Test]
        public void Stamina_Tidak_Pernah_Negatif_Atau_Lebih_Dari_1()
        {
            var c = new CombatState();
            c.Update(10.0, 10.0, 1.0);
            Assert.AreEqual(0.0, c.Stamina, Tol);
            c.Update(10.0, 20.0, 0.0);
            Assert.AreEqual(1.0, c.Stamina, Tol);
        }

        [Test]
        public void Spend_Gagal_Kalau_Kurang()
        {
            var c = new CombatState { Stamina = 0.75 };
            Assert.IsTrue(c.SpendStamina(0.25));
            Assert.AreEqual(0.5, c.Stamina, Tol);
            Assert.IsFalse(c.SpendStamina(0.8));
            Assert.AreEqual(0.5, c.Stamina, Tol);
        }

        [Test]
        public void Kombo_Naik_Dalam_Window_Reset_Di_Luar_Window()
        {
            var c = new CombatState();
            Assert.IsTrue(c.TryAttack(0.0));
            Assert.AreEqual(0, c.Combo);
            c.Update(0.6, 0.6, 0.0);          // selesai, lastEnd = 0,6
            Assert.IsFalse(c.IsAttacking);

            Assert.IsTrue(c.TryAttack(1.0));   // 0,4 < 0,9 -> kombo 1
            Assert.AreEqual(1, c.Combo);
            c.Update(0.6, 1.6, 0.0);

            Assert.IsTrue(c.TryAttack(3.0));   // 1,4 > 0,9 -> reset 0
            Assert.AreEqual(0, c.Combo);
        }

        [Test]
        public void Serangan_Baru_Ditolak_Saat_Mid_Swing()
        {
            var c = new CombatState();
            Assert.IsTrue(c.TryAttack(0.0));
            Assert.IsFalse(c.TryAttack(0.1));
            Assert.AreEqual(0, c.Combo);
        }

        [Test]
        public void Attack01_Naik_0_Ke_1_Lalu_Idle()
        {
            var c = new CombatState();
            c.TryAttack(0.0);
            c.Update(0.275, 0.275, 0.0);
            Assert.AreEqual(0.5, c.Attack01, Tol);
            c.Update(0.275, 0.55, 0.0);
            Assert.IsFalse(c.IsAttacking);
            Assert.AreEqual(0.0, c.Attack01, Tol);
        }
    }
}
