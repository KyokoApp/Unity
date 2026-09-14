using System;
using System.Collections.Generic;

namespace RPG.Core
{
    /* ============================================================
       LOCOMOTION — port 1:1 dari game/locomotion.mjs (58 baris).

       Target pose RELATIF terhadap bind pose rig, dalam radian.
       Setiap sendi yang digerakkan diberi target SETIAP frame supaya
       attack tidak bisa meninggalkan anggota badan tersangkut.

       Di Unity, keluaran ini dipakai oleh fase 3: Animator dengan
       Playables, atau langsung menulis localRotation per Transform.
       Kelas ini sengaja tidak menyentuh UnityEngine.
       ============================================================ */
    public static class Locomotion
    {
        public readonly struct Vec3
        {
            public readonly double X, Y, Z;
            public Vec3(double x, double y, double z) { X = x; Y = y; Z = z; }
            public Vec3 WithX(double x) => new Vec3(x, Y, Z);
            public Vec3 WithY(double y) => new Vec3(X, y, Z);
        }

        /* `attack` null = tidak sedang menyerang (JS: attack === null). */
        public readonly struct PoseInput
        {
            public readonly double Phase, Time, Move, Run, Dash;
            public readonly bool Airborne, Falling;
            public readonly double? Attack;
            public readonly int Combo;

            public PoseInput(double phase, double time, double move, double run, double dash,
                             bool airborne, bool falling, double? attack, int combo = 0)
            {
                Phase = phase; Time = time; Move = move; Run = run; Dash = dash;
                Airborne = airborne; Falling = falling; Attack = attack; Combo = combo;
            }
        }

        public static Dictionary<string, Vec3> SamplePose(PoseInput i)
        {
            var pose = new Dictionary<string, Vec3>();
            void Put(string name, double x = 0, double y = 0, double z = 0)
                => pose[name] = new Vec3(x, y, z);

            var breath = Math.Sin(i.Time * 1.8) * .022;

            Put("PELVIS", .10 * i.Run + .36 * i.Dash,
                Math.Sin(i.Phase) * .055 * i.Move, Math.Sin(i.Phase) * .035 * i.Move);
            Put("BELLY", breath - .04 * i.Run, 0, -Math.Sin(i.Phase) * .022 * i.Move);
            Put("CHEST", breath * .6, -Math.Sin(i.Phase) * .13 * i.Move, 0);
            Put("NECK", -.045 * i.Run);
            Put("HEAD", -.025 * i.Run, Math.Sin(i.Time * .55) * .035 * (1 - i.Move));

            /* ['R',0,1] lalu ['L',PI,-1] — urutan harus sama karena
               cabang airborne menimpa nilai yang sudah ditulis. */
            var sides = new (string side, double offset, double sign)[]
            {
                ("R", 0, 1), ("L", Math.PI, -1),
            };

            foreach (var (side, offset, sign) in sides)
            {
                var swing = Math.Sin(i.Phase + offset);
                var lift = Math.Max(0, -swing);

                Put("THIGH" + side, swing * (.40 + .27 * i.Run + .15 * i.Dash) * i.Move, 0, sign * .018 * i.Move);
                Put("KNEE" + side, (.10 + .78 * lift * lift) * i.Move);
                Put("LOWLEG" + side, -.08 * lift * i.Move);
                Put("FOOT" + side, (-swing * .20 - lift * .15) * i.Move);
                Put("TOE" + side, Math.Max(0, swing) * .16 * i.Move);
                Put("SHOULDER" + side, -swing * .09 * i.Move, 0, sign * .035 * i.Move);
                Put("ARM" + side, -swing * (.30 + .15 * i.Run) * i.Move, 0, sign * .06);
                Put("FOREARM" + side, .12 + .35 * i.Run + .10 * lift * i.Move);
                Put("HAND" + side, 0, 0, sign * .04);
                Put("KNUCLE" + side, side == "R" ? .48 : .12);

                if (i.Airborne)
                {
                    Put("THIGH" + side, i.Falling ? .14 : .38 + offset * .035);
                    Put("KNEE" + side, i.Falling ? .26 : .68);
                    Put("FOOT" + side, -.18);
                    Put("TOE" + side, .05);
                    Put("ARM" + side, -.20, 0, sign * .20);
                    Put("FOREARM" + side, .35);
                }
            }

            /* Bawa senjata dengan siku santai, bukan menyapu ke belakang punggung.
               JS memutasinya in-place: pose.ARMR[0] -= .12 */
            pose["ARMR"] = pose["ARMR"].WithX(pose["ARMR"].X - .12);
            pose["FOREARMR"] = pose["FOREARMR"].WithX(pose["FOREARMR"].X + .18);

            if (i.Attack.HasValue)
            {
                var t = Math.Max(0, Math.Min(1, i.Attack.Value));
                static double Smooth01(double x)
                {
                    x = Math.Max(0, Math.Min(1, x));
                    return x * x * (3 - 2 * x);
                }
                var wind = Smooth01(t / .26);
                var cut = Smooth01((t - .26) / .22);
                var recover = Smooth01((t - .60) / .40);
                var arc = (wind - 2 * cut) * (1 - recover);
                var direction = i.Combo % 2 == 0 ? 1 : -1;
                var vertical = i.Combo == 2;

                Put("PELVIS", .07, arc * .32 * direction);
                Put("BELLY", .04, arc * .18 * direction);
                Put("CHEST", .10, arc * .55 * direction);
                Put("SHOULDERR", -.18, arc * .25 * direction, -.12);
                Put("ARMR",
                    vertical ? -1.25 * arc : -.35 - .65 * cut * (1 - recover),
                    arc * .9 * direction, -.22 - arc * .55);
                Put("FOREARMR", .4 + .55 * wind * (1 - cut));
                Put("HANDR", -.12, arc * .22, 0);
                Put("ARML", .10, 0, .18);
                Put("FOREARML", .30);
                Put("THIGHR", -.12 * (1 - recover));
                Put("THIGHL", .16 * (1 - recover));
                Put("KNEER", .18 * (1 - recover));
                Put("KNEEL", .23 * (1 - recover));
            }

            return pose;
        }

        public static double Damp(double current, double target, double rate, double dt)
            => current + (target - current) * (1 - Math.Exp(-rate * dt));

        public readonly struct Axis
        {
            public readonly double X, Y;
            public Axis(double x, double y) { X = x; Y = y; }
        }

        public static Axis JoystickAxis(double x, double y, double radius = 55, double deadzone = .14)
        {
            var length = Math.Sqrt(x * x + y * y) / radius;
            if (length <= deadzone) return new Axis(0, 0);
            var amount = Math.Min(1, (length - deadzone) / (1 - deadzone));
            return new Axis(x / (length * radius) * amount, y / (length * radius) * amount);
        }
    }
}
