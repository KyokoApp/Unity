using System;
using NUnit.Framework;
using RPG.Core;

namespace RPG.Tests
{
    [TestFixture]
    public class BootAndCameraTests
    {
        const double Tol = 1e-9;

        [Test]
        public void Boot_TidakMasukSebelumMinShow()
        {
            Assert.IsFalse(BootPolicy.ShouldEnter(0.2, 25, false));
            Assert.IsFalse(BootPolicy.ShouldEnter(0.2, 0, true));
        }

        [Test]
        public void Boot_SatuChunkCukupSetelahMinShow()
        {
            Assert.IsTrue(BootPolicy.ShouldEnter(BootPolicy.MinShowSec, 1, false));
            Assert.IsFalse(BootPolicy.ShouldEnter(BootPolicy.MinShowSec, 0, false));
        }

        [Test]
        public void Boot_StreamerMati_MasukSetelahMinShow()
        {
            Assert.IsTrue(BootPolicy.ShouldEnter(BootPolicy.MinShowSec, 0, true));
        }

        [Test]
        public void Boot_SoftEnter_WalauNolChunk()
        {
            Assert.IsTrue(BootPolicy.ShouldEnter(BootPolicy.SoftEnterSec, 0, false));
        }

        [Test]
        public void Boot_DindingMutlak()
        {
            Assert.IsTrue(BootPolicy.ShouldEnter(BootPolicy.WallSec, 0, false));
            Assert.Greater(BootPolicy.OverlayFailsafeSec, BootPolicy.WallSec);
        }

        [Test]
        public void Kamera_DefaultSettings_JadiTigaMeterLebih()
        {
            var m = CameraFraming.MetersFromSettings(CameraFraming.SettingsDefault);
            Assert.AreEqual(CameraFraming.DefaultMeters, m, Tol);
            Assert.Greater(m, 3.0);
            Assert.Less(m, 3.4);
        }

        [Test]
        public void Kamera_UjungZoom_DiRentangGenshin()
        {
            Assert.AreEqual(CameraFraming.MetersMin,
                CameraFraming.MetersFromSettings(3), Tol);
            Assert.AreEqual(CameraFraming.MetersMax,
                CameraFraming.MetersFromSettings(8), Tol);
            Assert.AreEqual(CameraFraming.MetersMin,
                CameraFraming.MetersFromSettings(-99), Tol);
            Assert.AreEqual(CameraFraming.MetersMax,
                CameraFraming.MetersFromSettings(99), Tol);
            Assert.AreEqual(CameraFraming.DefaultMeters,
                CameraFraming.MetersFromSettings(double.NaN), Tol);
        }

        [Test]
        public void Orbit_Yaw0Pitch0_DiBelakangPadaMinusZ()
        {
            CameraFraming.OrbitOffset(0, 0, 1, out var x, out var y, out var z);
            Assert.AreEqual(0.0, x, Tol);
            Assert.AreEqual(0.0, y, Tol);
            Assert.AreEqual(-1.0, z, Tol);
        }

        [Test]
        public void Orbit_PitchPositif_KameraDiAtas()
        {
            CameraFraming.OrbitOffset(0, 90, 2, out var x, out var y, out var z);
            Assert.AreEqual(0.0, x, 1e-9);
            Assert.AreEqual(2.0, y, 1e-9);
            Assert.AreEqual(0.0, z, 1e-9);
        }

        [Test]
        public void Orbit_DefaultGenshin_TigaMeterDiBelakangSedikitAtas()
        {
            CameraFraming.OrbitOffset(0, CameraFraming.DefaultPitchDeg,
                CameraFraming.DefaultMeters, out var x, out var y, out var z);
            Assert.AreEqual(0.0, x, 1e-9);
            Assert.Greater(y, 0.7);
            Assert.Less(y, 1.1);
            Assert.Less(z, -2.8);
            Assert.Greater(z, -3.3);
            var len = Math.Sqrt(x * x + y * y + z * z);
            Assert.AreEqual(CameraFraming.DefaultMeters, len, 1e-9);
        }

        [Test]
        public void Look_LantaiBayanganDanFill_TidakNol()
        {
            Assert.Greater(WorldLookPolicy.MinShadowAtten, 0.3);
            Assert.Less(WorldLookPolicy.MinShadowAtten, 0.7);
            Assert.Greater(WorldLookPolicy.FillLight, 0.2);
            Assert.Greater(WorldLookPolicy.AmbientFloor, 0.2);
            Assert.Greater(WorldLookPolicy.KeepVisible, 0.3);
        }

        [Test]
        public void Look_HP_PakaiLangitWarnaDatar()
        {
            Assert.IsTrue(WorldLookPolicy.UseSolidSky(true));
            Assert.IsFalse(WorldLookPolicy.UseSolidSky(false));
        }

        [Test]
        public void Look_AmbientHitam_Terdeteksi()
        {
            Assert.IsTrue(WorldLookPolicy.AmbientTooDark(0, 0, 0));
            Assert.IsFalse(WorldLookPolicy.AmbientTooDark(0.5, 0.56, 0.64));
        }

        [Test]
        public void Look_InstancingError_BukanFatal()
        {
            Assert.IsTrue(WorldLookPolicy.IsNoisyLog(
                "Material needs to enable instancing for DrawMeshInstanced"));
            Assert.IsTrue(WorldLookPolicy.IsNoisyLog(
                "InvalidOperationException: DrawMeshInstanced"));
            Assert.IsFalse(WorldLookPolicy.IsNoisyLog("NullReferenceException: camera"));
            Assert.IsFalse(WorldLookPolicy.IsNoisyLog(null));
        }
    }
}
