using System;
using System.Collections.Generic;
using System.Linq;
using NUnit.Framework;
using RPG.Core;
using V3 = RPG.Core.Locomotion.Vec3;

namespace RPG.Tests
{
    /* ============================================================
       Tes RigMapping.

       Ini tes DESAIN, bukan tes paritas: tidak ada padanannya di
       repo three.js karena rig sumbernya (Hornet) sudah dibuang.
       Yang dijaga di sini adalah tiga hal:

         1. Tidak ada sendi SamplePose yang diam-diam hilang.
         2. Aritmetika lipat (SHOULDER->ARM, KNUCLE->HAND,
            LOWLEG->twist) persis seperti yang didokumentasikan.
         3. Nama tulang tetap sama dengan yang diukur dari file model.

       Kalau Locomotion.SamplePose menambah sendi baru, tes (1) akan
       merah sampai RigMapping ikut diperbarui. Itu memang tujuannya.
       ============================================================ */
    [TestFixture]
    public class RigMappingTests
    {
        const double Eps = 1e-12;

        static Locomotion.PoseInput Idle() =>
            new Locomotion.PoseInput(0, 0, 0, 0, 0, false, false, null);

        static Locomotion.PoseInput Walk(double phase = 0, double time = 0,
                                         double move = 1, double run = 0, double dash = 0) =>
            new Locomotion.PoseInput(phase, time, move, run, dash, false, false, null);

        // ---------------------------------------------------------- 1
        [Test]
        public void PoseKeys_PersisSamaDenganKeluaranSamplePose()
        {
            /* Dicek pada beberapa keadaan berbeda supaya cabang airborne
               dan attack ikut terwakili (keduanya menimpa kunci, bukan
               menambah kunci baru). */
            var inputs = new[]
            {
                Idle(),
                Walk(1.3, 2.7),
                new Locomotion.PoseInput(.4, 1.1, 1, 1, .5, false, false, null),
                new Locomotion.PoseInput(.4, 1.1, 1, 0, 0, true, false, null),
                new Locomotion.PoseInput(.4, 1.1, 1, 0, 0, true, true, null),
                new Locomotion.PoseInput(.4, 1.1, 1, 0, 0, false, false, .37, 0),
                new Locomotion.PoseInput(.4, 1.1, 1, 0, 0, false, false, .81, 2),
            };

            foreach (var i in inputs)
            {
                var keys = Locomotion.SamplePose(i).Keys.OrderBy(k => k, StringComparer.Ordinal).ToArray();
                var expected = RigMapping.PoseKeys.OrderBy(k => k, StringComparer.Ordinal).ToArray();
                CollectionAssert.AreEqual(expected, keys,
                    "SamplePose menghasilkan kunci yang tidak terdaftar di RigMapping.PoseKeys");
            }
        }

        [Test]
        public void Resolve_MenghasilkanSemuaJointTanpaSisa()
        {
            var r = RigMapping.Resolve(Locomotion.SamplePose(Walk(1.3, 2.7)));
            Assert.AreEqual(RigMapping.AllJoints.Length, r.Count);
            foreach (var j in RigMapping.AllJoints)
                Assert.IsTrue(r.ContainsKey(j), $"slot {j} tidak diisi");
        }

        // ---------------------------------------------------------- 2
        [Test]
        public void IdlePose_HanyaSisaPoseMembawaSenjata()
        {
            /* move=run=dash=0 dan time=0 membuat breath=0, jadi seluruh
               sendi tubuh & kaki harus NOL persis. Yang tersisa hanya
               pose dasar "membawa senjata" yang di-hardcode SamplePose:
                 ARMR.X -= .12 ; FOREARMR.X += .18 ; ARM.Z = sign*.06
                 KNUCLE R=.48 L=.12 ; HAND.Z = sign*.04
               Ditambah lipatan SHOULDER (0 saat idle) dan KNUCLE. */
            var r = RigMapping.Resolve(Locomotion.SamplePose(Idle()));

            void Zero(Joint j)
            {
                Assert.AreEqual(0, r[j].X, Eps, $"{j}.X");
                Assert.AreEqual(0, r[j].Y, Eps, $"{j}.Y");
                Assert.AreEqual(0, r[j].Z, Eps, $"{j}.Z");
            }

            foreach (var j in new[] { Joint.Hips, Joint.Spine, Joint.Chest, Joint.Neck, Joint.Head,
                                      Joint.LeftUpperLeg, Joint.LeftLowerLeg, Joint.LeftFoot, Joint.LeftToes,
                                      Joint.RightUpperLeg, Joint.RightLowerLeg, Joint.RightFoot, Joint.RightToes,
                                      Joint.LeftShinTwistA, Joint.LeftShinTwistB,
                                      Joint.RightShinTwistA, Joint.RightShinTwistB })
                Zero(j);

            // lengan atas: ARM + SHOULDER(0)
            Assert.AreEqual(0,   r[Joint.LeftUpperArm].X,  Eps);
            Assert.AreEqual(0,   r[Joint.LeftUpperArm].Y,  Eps);
            Assert.AreEqual(-.06, r[Joint.LeftUpperArm].Z, Eps);

            Assert.AreEqual(-.12, r[Joint.RightUpperArm].X, Eps);
            Assert.AreEqual(0,    r[Joint.RightUpperArm].Y, Eps);
            Assert.AreEqual(.06,  r[Joint.RightUpperArm].Z, Eps);

            // siku: FOREARM, kanan sudah digeser +.18
            Assert.AreEqual(.12, r[Joint.LeftLowerArm].X,  Eps);
            Assert.AreEqual(.30, r[Joint.RightLowerArm].X, Eps);

            // tangan: HAND + KNUCLE
            Assert.AreEqual(.12, r[Joint.LeftHand].X,  Eps);
            Assert.AreEqual(-.04, r[Joint.LeftHand].Z, Eps);
            Assert.AreEqual(.48, r[Joint.RightHand].X, Eps);
            Assert.AreEqual(.04, r[Joint.RightHand].Z, Eps);
        }

        [Test]
        public void Shoulder_DilipatPenuhKeLenganAtas()
        {
            /* Ambil keadaan jalan di mana SHOULDER tidak nol, lalu hitung
               ulang secara independen dari rumus di Locomotion. */
            const double phase = 1.3, move = 1, run = .6;
            var pose = Locomotion.SamplePose(Walk(phase, 0, move, run));

            foreach (var (side, joint) in new[] { ("L", Joint.LeftUpperArm), ("R", Joint.RightUpperArm) })
            {
                double sign = side == "R" ? 1 : -1;
                double offset = side == "R" ? 0 : Math.PI;
                var swing = Math.Sin(phase + offset);

                var expectArmX = -swing * (.30 + .15 * run) * move;
                var expectArmZ = sign * .06;
                var expectShX  = -swing * .09 * move;
                var expectShZ  = sign * .035 * move;

                // sisi kanan dapat tambahan -.12 dari baris "membawa senjata"
                if (side == "R") { /* sudah termasuk di pose["ARMR"] */ }

                var actual = RigMapping.Resolve(pose)[joint];
                Assert.AreEqual(pose["ARM" + side].X + expectShX * RigMapping.ShoulderWeight,
                                actual.X, 1e-12, $"{joint}.X");
                Assert.AreEqual(pose["ARM" + side].Z + expectShZ * RigMapping.ShoulderWeight,
                                actual.Z, 1e-12, $"{joint}.Z");

                // dan pastikan SHOULDER memang benar-benar bernilai, bukan nol kebetulan
                Assert.AreEqual(expectShX, pose["SHOULDER" + side].X, 1e-12);
                Assert.AreEqual(expectShZ, pose["SHOULDER" + side].Z, 1e-12);
                Assert.AreEqual(expectArmZ, pose["ARM" + side].Z, 1e-12);
            }
        }

        [Test]
        public void Knuckle_DilipatKePergelangan()
        {
            var pose = Locomotion.SamplePose(Walk(.9, .2));
            var r = RigMapping.Resolve(pose);

            Assert.AreEqual(pose["HANDL"].X + .12 * RigMapping.KnuckleWeight, r[Joint.LeftHand].X, Eps);
            Assert.AreEqual(pose["HANDR"].X + .48 * RigMapping.KnuckleWeight, r[Joint.RightHand].X, Eps);
            Assert.AreEqual(pose["HANDL"].Z, r[Joint.LeftHand].Z, Eps);
            Assert.AreEqual(pose["HANDR"].Z, r[Joint.RightHand].Z, Eps);
        }

        [Test]
        public void LowLeg_DibagiRataKeDuaTulangTwistBetis()
        {
            /* LOWLEG hanya tidak nol saat lift>0, yaitu saat kaki terangkat.
               phase = PI/2 membuat sisi L punya swing = sin(PI/2+PI) = -1 -> lift = 1. */
            var pose = Locomotion.SamplePose(Walk(Math.PI / 2, 0, 1, 0));
            var r = RigMapping.Resolve(pose);

            Assert.That(Math.Abs(pose["LOWLEGL"].X), Is.GreaterThan(1e-6),
                        "prekondisi tes: LOWLEGL harus tidak nol");

            Assert.AreEqual(pose["LOWLEGL"].X * RigMapping.ShinTwistSplit,
                            r[Joint.LeftShinTwistA].X, Eps);
            Assert.AreEqual(pose["LOWLEGL"].X * (1 - RigMapping.ShinTwistSplit),
                            r[Joint.LeftShinTwistB].X, Eps);
            Assert.AreEqual(r[Joint.LeftShinTwistA].X + r[Joint.LeftShinTwistB].X,
                            pose["LOWLEGL"].X, Eps, "jumlah keduanya harus mengembalikan LOWLEG utuh");
        }

        [Test]
        public void Walk_KakiKiriDanKananBerlawanan()
        {
            var r = RigMapping.Resolve(Locomotion.SamplePose(Walk(.7, 0, 1, 0)));
            Assert.That(r[Joint.LeftUpperLeg].X * r[Joint.RightUpperLeg].X, Is.LessThan(0),
                        "saat berjalan, satu paha mengayun maju dan satunya mundur");
            Assert.AreEqual(-r[Joint.LeftUpperLeg].X, r[Joint.RightUpperLeg].X, 1e-12);
            Assert.AreEqual(-r[Joint.LeftUpperLeg].Z, r[Joint.RightUpperLeg].Z, 1e-12);
        }

        [Test]
        public void Airborne_MenimpaPoseTanah()
        {
            var air  = RigMapping.Resolve(Locomotion.SamplePose(
                new Locomotion.PoseInput(.7, 1, 1, 0, 0, true, false, null)));
            var fall = RigMapping.Resolve(Locomotion.SamplePose(
                new Locomotion.PoseInput(.7, 1, 1, 0, 0, true, true, null)));

            Assert.AreEqual(.38 + Math.PI * .035, air[Joint.LeftUpperLeg].X, 1e-12);
            Assert.AreEqual(.38,                  air[Joint.RightUpperLeg].X, 1e-12);
            Assert.AreEqual(.68, air[Joint.LeftLowerLeg].X, 1e-12);
            Assert.AreEqual(.26, fall[Joint.LeftLowerLeg].X, 1e-12);
            Assert.AreEqual(-.18, air[Joint.LeftFoot].X, 1e-12);
            Assert.AreEqual(.35,  air[Joint.LeftLowerArm].X, 1e-12);
        }

        [Test]
        public void Attack_MenimpaLenganKanan()
        {
            var pose = Locomotion.SamplePose(new Locomotion.PoseInput(.2, 1, 1, 0, 0, false, false, .35, 0));
            var r = RigMapping.Resolve(pose);
            // lengan kanan = ARM(attack) + SHOULDER(attack)
            Assert.AreEqual(pose["ARMR"].X + pose["SHOULDERR"].X * RigMapping.ShoulderWeight,
                            r[Joint.RightUpperArm].X, Eps);
            Assert.AreEqual(pose["ARMR"].Y + pose["SHOULDERR"].Y * RigMapping.ShoulderWeight,
                            r[Joint.RightUpperArm].Y, Eps);
            Assert.That(Math.Abs(pose["ARMR"].Y), Is.GreaterThan(1e-6),
                        "prekondisi: attack harus memberi komponen Y pada ARMR");
        }

        // ---------------------------------------------------------- 3
        [Test]
        public void NodeName_SamaDenganYangDiukurDariFileModel()
        {
            /* Angka ini diukur langsung dari humanoid.humanBones dan daftar
               tulang non-humanoid di AureliaChar.vrm. Kalau model diganti,
               tes ini HARUS diperbarui secara sadar — jangan dibisukan. */
            var expect = new Dictionary<Joint, string>
            {
                { Joint.Hips,  "DEF-Hips"  }, { Joint.Spine, "DEF-Spine" },
                { Joint.Chest, "DEF-Chest" }, { Joint.Neck,  "DEF-Neck"  },
                { Joint.Head,  "DEF-Head"  },
                { Joint.LeftUpperLeg,  "DEF-Left leg"   }, { Joint.RightUpperLeg,  "DEF-Right leg"   },
                { Joint.LeftLowerLeg,  "DEF-Left knee"  }, { Joint.RightLowerLeg,  "DEF-Right knee"  },
                { Joint.LeftShinTwistA,"DEF-Left knee.001" }, { Joint.RightShinTwistA,"DEF-Right knee.001" },
                { Joint.LeftShinTwistB,"DEF-Left knee.002" }, { Joint.RightShinTwistB,"DEF-Right knee.002" },
                { Joint.LeftFoot,  "DEF-Left ankle"  }, { Joint.RightFoot,  "DEF-Right ankle"  },
                { Joint.LeftToes,  "DEF-Left toe"    }, { Joint.RightToes,  "DEF-Right toe"    },
                { Joint.LeftUpperArm,  "DEF-Left arm"   }, { Joint.RightUpperArm,  "DEF-Right arm"   },
                { Joint.LeftLowerArm,  "DEF-Left elbow" }, { Joint.RightLowerArm,  "DEF-Right elbow" },
                { Joint.LeftHand,  "DEF-Left wrist" }, { Joint.RightHand,  "DEF-Right wrist" },
            };
            Assert.AreEqual(RigMapping.AllJoints.Length, expect.Count);
            foreach (var kv in expect)
                Assert.AreEqual(kv.Value, RigMapping.NodeName[kv.Key], $"NodeName[{kv.Key}]");
        }

        [Test]
        public void HumanoidBone_HanyaMemakaiNamaVRM0xYangSah()
        {
            /* Daftar bone VRM 0.x yang sah (vrm-c/UniVRM, VRM spec 0.0).
               Hanya 19 dari 23 slot yang punya padanan humanoid; 4 tulang
               twist memang tidak ada di spec dan harus dicari by name. */
            var vrm0 = new HashSet<string>(StringComparer.Ordinal)
            {
                "hips","spine","chest","upperChest","neck","head",
                "leftEye","rightEye","jaw",
                "leftUpperLeg","leftLowerLeg","leftFoot","leftToes",
                "rightUpperLeg","rightLowerLeg","rightFoot","rightToes",
                "leftUpperArm","leftLowerArm","leftHand",
                "rightUpperArm","rightLowerArm","rightHand",
                "leftThumbProximal","leftThumbIntermediate","leftThumbDistal",
                "leftIndexProximal","leftIndexIntermediate","leftIndexDistal",
                "leftMiddleProximal","leftMiddleIntermediate","leftMiddleDistal",
                "leftRingProximal","leftRingIntermediate","leftRingDistal",
                "leftLittleProximal","leftLittleIntermediate","leftLittleDistal",
                "rightThumbProximal","rightThumbIntermediate","rightThumbDistal",
                "rightIndexProximal","rightIndexIntermediate","rightIndexDistal",
                "rightMiddleProximal","rightMiddleIntermediate","rightMiddleDistal",
                "rightRingProximal","rightRingIntermediate","rightRingDistal",
                "rightLittleProximal","rightLittleIntermediate","rightLittleDistal",
            };
            int withBone = 0, without = 0;
            foreach (var j in RigMapping.AllJoints)
            {
                var b = RigMapping.HumanoidBone[j];
                if (b == null) { without++; continue; }
                withBone++;
                Assert.IsTrue(vrm0.Contains(b), $"'{b}' bukan nama bone VRM 0.x yang sah");
            }
            Assert.AreEqual(19, withBone, "jumlah slot yang punya padanan humanoid");
            Assert.AreEqual(4,  without, "hanya 4 tulang twist yang tidak ada di spec VRM");
        }

        [Test]
        public void SetiapJointPunyaNamaNodeUntukFallback()
        {
            foreach (var j in RigMapping.AllJoints)
            {
                Assert.IsFalse(string.IsNullOrEmpty(RigMapping.NodeName[j]),
                               $"{j} tidak punya nama node fallback");
                if (RigMapping.HumanoidBone[j] == null)
                    Assert.IsTrue(RigMapping.NodeName[j].Length > 0,
                                  $"{j} tidak punya humanoid bone, jadi NodeName wajib ada");
            }
        }

        [Test]
        public void Resolve_Deterministik()
        {
            var pose = Locomotion.SamplePose(Walk(2.1, .3, .8, .4));
            var a = RigMapping.Resolve(pose);
            var b = RigMapping.Resolve(pose);
            foreach (var j in RigMapping.AllJoints)
            {
                Assert.AreEqual(a[j].X, b[j].X);
                Assert.AreEqual(a[j].Y, b[j].Y);
                Assert.AreEqual(a[j].Z, b[j].Z);
            }
        }

        [Test]
        public void Resolve_TidakMelemparSaatKunciHilang()
        {
            /* RigMapping harus tahan kalau diberi pose parsial — misalnya
               saat debug atau saat SamplePose versi lama dipanggil. */
            var partial = new Dictionary<string, V3> { { "PELVIS", new V3(.1, .2, .3) } };
            var r = RigMapping.Resolve(partial);
            Assert.AreEqual(.1, r[Joint.Hips].X, Eps);
            Assert.AreEqual(RigMapping.AllJoints.Length, r.Count);
        }
    }
}
