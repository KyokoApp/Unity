using System;
using System.Collections.Generic;

namespace RPG.Core
{
    /* ============================================================
       RIG MAPPING — memetakan 25 sendi keluaran Locomotion.SamplePose()
       ke tulang karakter VRM yang dipakai project ini.

       Kenapa kelas ini ada dan kenapa PURE (tanpa UnityEngine):
       rig sumber (Hornet, character.glb) sudah dibuang. Yang tersisa
       adalah 25 nama sendi abstrak. Model penggantinya punya tulang
       bernama lain dan — yang lebih penting — TIDAK punya padanan
       untuk 3 pasang sendi itu. Keputusan "melipat ke mana" adalah
       keputusan desain yang harus bisa dites, bukan dikira-kira di
       dalam MonoBehaviour. Jadi keputusannya ditaruh di sini.

       Hasil pengukuran atas model (lihat Assets/Art/Characters/LISENSI.md):
         - 49 bone humanoid VRM lengkap, termasuk seluruh jari
         - TIDAK ada clavicle/bahu  -> SHOULDER tidak punya tujuan
         - ada tulang twist .001/.002 -> LOWLEG punya tujuan
         - ada *FingerPalm_*         -> KNUCLE bisa dilipat ke pergelangan

       Semua angka dalam RADIAN, relatif terhadap bind pose — sama
       seperti keluaran SamplePose(). Kelas ini tidak melakukan
       interpolasi, tidak menyentuh waktu, tidak menyimpan state.
       ============================================================ */

    /* Slot tulang yang benar-benar kita gerakkan. Sengaja TIDAK memakai
       enum HumanBodyBones milik Unity supaya assembly ini tetap murni. */
    public enum Joint
    {
        Hips, Spine, Chest, Neck, Head,

        LeftUpperLeg, LeftLowerLeg, LeftShinTwistA, LeftShinTwistB, LeftFoot, LeftToes,
        RightUpperLeg, RightLowerLeg, RightShinTwistA, RightShinTwistB, RightFoot, RightToes,

        LeftUpperArm, LeftLowerArm, LeftHand,
        RightUpperArm, RightLowerArm, RightHand,
    }

    public static class RigMapping
    {
        /* ----------------------------------------------------------
           Nama node di model. Dua sumber, dipakai berurutan:
             1. HumanoidBone -> lewat Animator.GetBoneTransform() bila
                Avatar humanoid berhasil dibuat UniVRM (paling tahan
                terhadap model yang berganti nama tulang).
             2. NodeName     -> pencarian by name di hierarki, untuk
                model ini dan untuk tulang yang tidak ada di daftar
                humanoid VRM (twist .001/.002, dsb).
           ---------------------------------------------------------- */

        /* Nilai string-nya SAMA dengan field `bone` di VRM humanoid,
           sehingga Runtime bisa memetakannya ke HumanBodyBones tanpa
           perlu referensi UnityEngine di sini. */
        public static readonly IReadOnlyDictionary<Joint, string> HumanoidBone =
            new Dictionary<Joint, string>
        {
            { Joint.Hips,            "hips"            },
            { Joint.Spine,           "spine"           },
            { Joint.Chest,           "chest"           },
            { Joint.Neck,            "neck"            },
            { Joint.Head,            "head"            },

            { Joint.LeftUpperLeg,    "leftUpperLeg"    },
            { Joint.LeftLowerLeg,    "leftLowerLeg"    },
            { Joint.LeftShinTwistA,  null },   // tidak ada di humanoid VRM
            { Joint.LeftShinTwistB,  null },
            { Joint.LeftFoot,        "leftFoot"        },
            { Joint.LeftToes,        "leftToes"        },

            { Joint.RightUpperLeg,   "rightUpperLeg"   },
            { Joint.RightLowerLeg,   "rightLowerLeg"   },
            { Joint.RightShinTwistA, null },
            { Joint.RightShinTwistB, null },
            { Joint.RightFoot,       "rightFoot"       },
            { Joint.RightToes,       "rightToes"       },

            { Joint.LeftUpperArm,    "leftUpperArm"    },
            { Joint.LeftLowerArm,    "leftLowerArm"    },
            { Joint.LeftHand,        "leftHand"        },
            { Joint.RightUpperArm,   "rightUpperArm"   },
            { Joint.RightLowerArm,   "rightLowerArm"   },
            { Joint.RightHand,       "rightHand"       },
        };

        /* Nama node terukur dari file model. Ini fallback kalau Avatar
           humanoid tidak tersedia. Diambil langsung dari VRM
           humanoid.humanBones + daftar tulang non-humanoid. */
        public static readonly IReadOnlyDictionary<Joint, string> NodeName =
            new Dictionary<Joint, string>
        {
            { Joint.Hips,            "DEF-Hips"        },
            { Joint.Spine,           "DEF-Spine"       },
            { Joint.Chest,           "DEF-Chest"       },
            { Joint.Neck,            "DEF-Neck"        },
            { Joint.Head,            "DEF-Head"        },

            { Joint.LeftUpperLeg,    "DEF-Left leg"    },
            { Joint.LeftLowerLeg,    "DEF-Left knee"   },
            { Joint.LeftShinTwistA,  "DEF-Left knee.001" },
            { Joint.LeftShinTwistB,  "DEF-Left knee.002" },
            { Joint.LeftFoot,        "DEF-Left ankle"  },
            { Joint.LeftToes,        "DEF-Left toe"    },

            { Joint.RightUpperLeg,   "DEF-Right leg"   },
            { Joint.RightLowerLeg,   "DEF-Right knee"  },
            { Joint.RightShinTwistA, "DEF-Right knee.001" },
            { Joint.RightShinTwistB, "DEF-Right knee.002" },
            { Joint.RightFoot,       "DEF-Right ankle" },
            { Joint.RightToes,       "DEF-Right toe"   },

            { Joint.LeftUpperArm,    "DEF-Left arm"    },
            { Joint.LeftLowerArm,    "DEF-Left elbow"  },
            { Joint.LeftHand,        "DEF-Left wrist"  },
            { Joint.RightUpperArm,   "DEF-Right arm"   },
            { Joint.RightLowerArm,   "DEF-Right elbow" },
            { Joint.RightHand,       "DEF-Right wrist" },
        };

        /* Berapa bagian dari LOWLEG yang masuk ke masing-masing tulang
           twist betis. 0.5/0.5 membagi putaran merata sehingga kulit
           tidak melintir di satu titik. */
        public const double ShinTwistSplit = 0.5;

        /* KNUCLE bernilai konstan (.48 kanan, .12 kiri) dan tidak punya
           tulang tujuan. Nilainya dilipat ke sumbu X pergelangan.
           Kalau di layar tangan terlihat terpuntir aneh, ini angka
           pertama yang harus dinolkan — lihat TAHAP-2.md. */
        public const double KnuckleWeight = 1.0;

        /* SHOULDER tidak punya clavicle tujuan. Kontribusinya kecil
           (-swing*.09 dan sign*.035) jadi dilipat penuh ke lengan atas. */
        public const double ShoulderWeight = 1.0;

        public static readonly Joint[] AllJoints = (Joint[])Enum.GetValues(typeof(Joint));

        static Locomotion.Vec3 Get(IReadOnlyDictionary<string, Locomotion.Vec3> pose, string key)
            => pose.TryGetValue(key, out var v) ? v : new Locomotion.Vec3();

        static Locomotion.Vec3 Add(Locomotion.Vec3 a, Locomotion.Vec3 b, double wb = 1)
            => new Locomotion.Vec3(a.X + b.X * wb, a.Y + b.Y * wb, a.Z + b.Z * wb);

        /* Slot per sisi, disiapkan sekali. Menghindari Enum.Parse di jalur
           yang dipanggil tiap frame. */
        readonly struct SideSlots
        {
            public readonly Joint UpperLeg, LowerLeg, ShinTwistA, ShinTwistB, Foot, Toes;
            public readonly Joint UpperArm, LowerArm, Hand;
            public SideSlots(Joint ul, Joint ll, Joint ta, Joint tb, Joint ft, Joint to,
                             Joint ua, Joint la, Joint h)
            { UpperLeg = ul; LowerLeg = ll; ShinTwistA = ta; ShinTwistB = tb; Foot = ft; Toes = to;
              UpperArm = ua; LowerArm = la; Hand = h; }
        }

        static readonly SideSlots Left = new SideSlots(
            Joint.LeftUpperLeg, Joint.LeftLowerLeg, Joint.LeftShinTwistA, Joint.LeftShinTwistB,
            Joint.LeftFoot, Joint.LeftToes,
            Joint.LeftUpperArm, Joint.LeftLowerArm, Joint.LeftHand);

        static readonly SideSlots Right = new SideSlots(
            Joint.RightUpperLeg, Joint.RightLowerLeg, Joint.RightShinTwistA, Joint.RightShinTwistB,
            Joint.RightFoot, Joint.RightToes,
            Joint.RightUpperArm, Joint.RightLowerArm, Joint.RightHand);

        /* ==========================================================
           Resolve: 25 sendi abstrak -> 23 slot tulang konkret.

           Tiga aturan lipat:
             ARM    += SHOULDER * ShoulderWeight   (tidak ada clavicle)
             HAND   += KNUCLE   * KnuckleWeight    (tidak ada tulang knuckle)
             LOWLEG ->  ShinTwistA/B dibagi ShinTwistSplit
           ========================================================== */
        public static Dictionary<Joint, Locomotion.Vec3> Resolve(
            IReadOnlyDictionary<string, Locomotion.Vec3> pose)
        {
            var o = new Dictionary<Joint, Locomotion.Vec3>(AllJoints.Length);

            o[Joint.Hips]  = Get(pose, "PELVIS");
            o[Joint.Spine] = Get(pose, "BELLY");
            o[Joint.Chest] = Get(pose, "CHEST");
            o[Joint.Neck]  = Get(pose, "NECK");
            o[Joint.Head]  = Get(pose, "HEAD");

            ApplySide(o, Left,  "L", pose);
            ApplySide(o, Right, "R", pose);

            return o;
        }

        static void ApplySide(Dictionary<Joint, Locomotion.Vec3> o, SideSlots s, string side,
                              IReadOnlyDictionary<string, Locomotion.Vec3> pose)
        {
            var thigh    = Get(pose, "THIGH"    + side);
            var knee     = Get(pose, "KNEE"     + side);
            var lowleg   = Get(pose, "LOWLEG"   + side);
            var foot     = Get(pose, "FOOT"     + side);
            var toe      = Get(pose, "TOE"      + side);
            var shoulder = Get(pose, "SHOULDER" + side);
            var arm      = Get(pose, "ARM"      + side);
            var forearm  = Get(pose, "FOREARM"  + side);
            var hand     = Get(pose, "HAND"     + side);
            var knuckle  = Get(pose, "KNUCLE"   + side);

            o[s.UpperLeg]   = thigh;
            o[s.LowerLeg]   = knee;
            o[s.ShinTwistA] = Scale(lowleg, ShinTwistSplit);
            o[s.ShinTwistB] = Scale(lowleg, 1 - ShinTwistSplit);
            o[s.Foot]       = foot;
            o[s.Toes]       = toe;

            o[s.UpperArm]   = Add(arm, shoulder, ShoulderWeight);
            o[s.LowerArm]   = forearm;
            o[s.Hand]       = Add(hand, knuckle, KnuckleWeight);
        }

        static Locomotion.Vec3 Scale(Locomotion.Vec3 v, double k)
            => new Locomotion.Vec3(v.X * k, v.Y * k, v.Z * k);

        /* Daftar 25 kunci yang dihasilkan SamplePose. Dipakai oleh tes
           untuk memastikan tidak ada kunci yang diam-diam tidak terpakai:
           kalau Locomotion menambah sendi baru, tes akan merah sampai
           Resolve() ikut memperbaruinya. */
        public static readonly string[] PoseKeys =
        {
            "PELVIS", "BELLY", "CHEST", "NECK", "HEAD",
            "THIGHL", "KNEEL", "LOWLEGL", "FOOTL", "TOEL",
            "SHOULDERL", "ARML", "FOREARML", "HANDL", "KNUCLEL",
            "THIGHR", "KNEER", "LOWLEGR", "FOOTR", "TOER",
            "SHOULDERR", "ARMR", "FOREARMR", "HANDR", "KNUCLER",
        };
    }
}
