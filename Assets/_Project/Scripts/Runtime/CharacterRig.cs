using System;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;
using RPG.Core;
using Joint = RPG.Core.Joint;

namespace RPG.Runtime
{
    /* ============================================================
       CHARACTER RIG — menulis localRotation tulang tiap frame dari
       hasil RigMapping.Resolve().

       localRotation = bindRotation * Quaternion.Euler(rad -> deg)

       Animator pada prefab VRM DIMATIKAN selama jalur prosedural
       aktif. Kalau nanti kamu mengimpor animasi jadi (Mixamo /
       Quaternius — lihat TAHAP-5.md), AnimatorBridge akan menyetel
       ProceduralEnabled=false dan Animator kembali mengambil alih.

       Tambahan Tahap 5: pose DIHALUSKAN antar frame (tidak patah
       saat input berubah mendadak), badan LEAN saat berputar, dan
       lutut MENYEKUK sesaat saat mendarat dari lompatan tinggi.
       ============================================================ */
    [DisallowMultipleComponent]
    public class CharacterRig : MonoBehaviour
    {
        [Header("Sumber")]
        [Tooltip("Root karakter (instance prefab VRM). Kosongkan = pakai GameObject ini.")]
        public Transform CharacterRoot;

        [Tooltip("Kalau dicentang, tulang dicari lewat Animator.GetBoneTransform() " +
                 "(pakai Avatar humanoid). Kalau gagal, otomatis turun ke pencarian nama.")]
        public bool PreferAvatarLookup = true;

        [Tooltip("Kalau false, ApplyPose dilewati (untuk jalur Animator/animasi jadi).")]
        public bool ProceduralEnabled = true;

        [Header("Kehalusan")]
        [Tooltip("Laju pose mengejar target (1/detik). Makin besar makin responsif, makin kecil makin lembut.")]
        public float PoseSmoothRate = 14f;
        [Tooltip("Seberapa kuat badan miring saat berputar (0 = mati).")]
        [Range(0f, 1f)] public float LeanStrength = 0.7f;

        [Header("Kalibrasi sumbu — balik tanda kalau anggota badan bergerak ke arah salah")]
        [Range(-1f, 1f)] public float SignLegX = 1f, SignLegY = 1f, SignLegZ = 1f;
        [Range(-1f, 1f)] public float SignArmX = 1f, SignArmY = 1f, SignArmZ = -1f;
        [Range(-1f, 1f)] public float SignSpineX = 1f, SignSpineY = 1f, SignSpineZ = 1f;
        [Range(-1f, 1f)] public float SignFootX = 1f;

        [Header("Debug")]
        public bool DrawBindPoseGizmos = false;
        [Tooltip("Kunci karakter di bind pose (untuk memeriksa apakah bind-nya benar).")]
        public bool FreezeAtBindPose = false;

        /* Bind pose DISERIALISASI ... (alasan: lihat TAHAP-2.md —
           menu uji pose di Edit Mode ikut terbawa ke Play Mode). */
        [System.Serializable]
        public struct BindEntry
        {
            public Joint Joint;
            public Transform Bone;
            public Quaternion LocalRotation;
        }

        [SerializeField] BindEntry[] _serializedBind = new BindEntry[0];

        readonly Dictionary<Joint, Transform> _bones = new Dictionary<Joint, Transform>();
        readonly Dictionary<Joint, Quaternion> _bind = new Dictionary<Joint, Quaternion>();
        readonly Dictionary<Joint, Locomotion.Vec3> _prev = new Dictionary<Joint, Locomotion.Vec3>();
        /* Koreksi lengan-turun per sendi (dihitung di Bind, lihat ComputeArmFix).
           Sendi yang tidak ada di sini = tanpa koreksi (identitas). */
        readonly Dictionary<Joint, Quaternion> _armFix = new Dictionary<Joint, Quaternion>();
        Animator _animator;
        float _lean;
        float _leanTarget;
        float _crouch;

        public bool IsBound => _bones.Count > 0;
        public int BoundCount => _bones.Count;
        public string LastBindReport { get; private set; } = "";

        void Awake()
        {
            if (CharacterRoot == null) CharacterRoot = transform;
            Bind();
        }

        /* Dipanggil ulang kalau prefab karakter diganti saat runtime. */
        public void Bind()
        {
            _bones.Clear();
            _bind.Clear();
            _prev.Clear();
            _armFix.Clear();

            _animator = CharacterRoot.GetComponentInChildren<Animator>();
            var missing = new List<string>();
            var viaAvatar = 0;

            var saved = new Dictionary<Joint, Quaternion>();
            foreach (var e in _serializedBind)
                if (e.Bone != null) saved[e.Joint] = e.LocalRotation;

            foreach (var j in RigMapping.AllJoints)
            {
                Transform t = null;

                if (PreferAvatarLookup && _animator != null && _animator.isHuman &&
                    RigMapping.HumanoidBone.TryGetValue(j, out var hb) && hb != null)
                {
                    t = _animator.GetBoneTransform(HumanBoneFromVrm(hb));
                    if (t != null) viaAvatar++;
                }

                if (t == null && RigMapping.NodeName.TryGetValue(j, out var name))
                    t = FindDeep(CharacterRoot, name);

                if (t == null) { missing.Add(j.ToString()); continue; }

                _bones[j] = t;
                /* Kalau bind pose sudah pernah direkam, pakai itu dan pulihkan
                   tulang ke sana — bukan ke posisi sekarang yang mungkin sudah
                   diputar oleh menu uji pose. */
                if (saved.TryGetValue(j, out var q)) { t.localRotation = q; _bind[j] = q; }
                else _bind[j] = t.localRotation;
            }

            _serializedBind = _bones
                .Select(kv => new BindEntry { Joint = kv.Key, Bone = kv.Value,
                                              LocalRotation = _bind[kv.Key] })
                .ToArray();

            /* Tulang saat ini di bind pose (fresh build = prefab perawan;
               editor = dipulihkan dari _serializedBind di atas). */
            ComputeArmFix();

            /* Animator hanya dimatikan di jalur prosedural. Jalur Animator
               (animasi jadi) membutuhkannya menyala. */
            if (_animator != null) _animator.enabled = !ProceduralEnabled;

            LastBindReport =
                $"[CharacterRig] terikat {_bones.Count}/{RigMapping.AllJoints.Length} tulang " +
                $"({viaAvatar} lewat Avatar humanoid, sisanya lewat nama). " +
                (missing.Count == 0 ? "Lengkap." : $"TIDAK KETEMU: {string.Join(", ", missing)}");

            Debug.Log(LastBindReport);
            if (_bones.Count == 0)
                Debug.LogError("[CharacterRig] tidak ada satu pun tulang yang ketemu. " +
                               "Pastikan CharacterRoot mengarah ke instance prefab VRM.");
        }

        /* Nama bone VRM 0.x -> HumanBodyBones Unity. Sengaja dibuat tabel
           eksplisit, bukan Enum.Parse, supaya salah ketik ketahuan saat kompilasi. */
        static readonly Dictionary<string, HumanBodyBones> HumanMap = new Dictionary<string, HumanBodyBones>
        {
            { "hips",          HumanBodyBones.Hips },
            { "spine",         HumanBodyBones.Spine },
            { "chest",         HumanBodyBones.Chest },
            { "neck",          HumanBodyBones.Neck },
            { "head",          HumanBodyBones.Head },
            { "leftUpperLeg",  HumanBodyBones.LeftUpperLeg },
            { "leftLowerLeg",  HumanBodyBones.LeftLowerLeg },
            { "leftFoot",      HumanBodyBones.LeftFoot },
            { "leftToes",      HumanBodyBones.LeftToes },
            { "rightUpperLeg", HumanBodyBones.RightUpperLeg },
            { "rightLowerLeg", HumanBodyBones.RightLowerLeg },
            { "rightFoot",     HumanBodyBones.RightFoot },
            { "rightToes",     HumanBodyBones.RightToes },
            { "leftUpperArm",  HumanBodyBones.LeftUpperArm },
            { "leftLowerArm",  HumanBodyBones.LeftLowerArm },
            { "leftHand",      HumanBodyBones.LeftHand },
            { "rightUpperArm", HumanBodyBones.RightUpperArm },
            { "rightLowerArm", HumanBodyBones.RightLowerArm },
            { "rightHand",     HumanBodyBones.RightHand },
        };

        static HumanBodyBones HumanBoneFromVrm(string vrmBone) =>
            HumanMap.TryGetValue(vrmBone, out var b) ? b : HumanBodyBones.LastBone;

        /* Koreksi lengan: bind pose VRM = T-pose (lengan horizontal),
           sementara SEMUA pose Locomotion ditulis untuk bind berlengan
           turun (rig JS aslinya). Tanpa koreksi, karakter idle/jalan
           dengan lengan terbuka seperti salib — di screenshot maupun
           in-game.

           Bebas sumbu (tidak menebak axis lokal tulang): arah lengan
           diukur di ruang karakter, lalu diputar ke arah rileks
           (bawah + sedikit keluar + sedikit depan) lewat
           FromToRotation, dan dinyatakan sebagai premultiply
           bone-local. Kalau modelnya memang sudah A-pose, sudutnya
           ~0 dan koreksinya otomatis identitas. */
        void ComputeArmFix()
        {
            _armFix.Clear();
            if (CharacterRoot == null) return;
            FixArm(Joint.LeftUpperArm, Joint.LeftLowerArm);
            FixArm(Joint.RightUpperArm, Joint.RightLowerArm);
        }

        void FixArm(Joint upper, Joint lower)
        {
            if (!_bones.TryGetValue(upper, out var u)) return;
            if (!_bones.TryGetValue(lower, out var e)) return;
            if (u.parent == null) return;
            var span = e.position - u.position;
            if (span.sqrMagnitude < 1e-10f) return;
            var dirChar = CharacterRoot.InverseTransformDirection(span.normalized);
            var wantChar = new Vector3(Mathf.Sign(dirChar.x) * 0.16f, -1f, 0.10f).normalized;
            if (Vector3.Angle(dirChar, wantChar) < 1f) return;
            var qChar = Quaternion.FromToRotation(dirChar, wantChar);
            // char-space -> world -> parent-space, lalu ke bone-local:
            // local' = qParent * bind = bind * (bind^-1 * qParent * bind).
            var rootQ = CharacterRoot.rotation;
            var qWorld = rootQ * qChar * Quaternion.Inverse(rootQ);
            var parentQ = u.parent.rotation;
            var qParent = Quaternion.Inverse(parentQ) * qWorld * parentQ;
            var bindQ = _bind[upper];
            _armFix[upper] = Quaternion.Inverse(bindQ) * qParent * bindQ;
        }

        static Transform FindDeep(Transform root, string name)
        {
            if (root.name == name) return root;
            for (var i = 0; i < root.childCount; i++)
            {
                var hit = FindDeep(root.GetChild(i), name);
                if (hit != null) return hit;
            }
            return null;
        }

        /* Kecepatan putar badan ternormalisasi (-1..1), diisi motor tiap
           frame. Dipakai untuk lean (badan miring saat berputar). */
        public void SetLean(float yawRateNorm) { _leanTarget = yawRateNorm; }

        /* Sekuk lutut sesaat (0..1), dipicu saat mendarat. */
        public void PulseCrouch(float strength)
        {
            _crouch = Mathf.Clamp(_crouch + strength, 0f, 1f);
        }

        /* ----------------------------------------------------------
           Terapkan pose. Dipanggil dari CharacterMotor di LateUpdate
           (setelah karakter bergerak, sebelum SpringBone jalan).
           ---------------------------------------------------------- */
        public void ApplyPose(IReadOnlyDictionary<Joint, Locomotion.Vec3> pose)
        {
            if (!ProceduralEnabled) return;
            if (FreezeAtBindPose) { ResetToBind(); return; }

            var dt = Time.deltaTime;
            /* dt==0 di batchmode (SceneShots): tanpa ini k=0, pose tidak
               pernah tertulis, screenshot tetap T-pose salib. */
            var k = dt <= 1e-5f ? 1f
                : 1f - Mathf.Exp(-PoseSmoothRate * dt);
            _lean += (_leanTarget - _lean) * (1f - Mathf.Exp(-8f * Mathf.Max(0f, dt)));
            _crouch *= Mathf.Exp(-6f * Mathf.Max(0f, dt));
            if (_crouch < 0.001f) _crouch = 0f;

            foreach (var kv in _bones)
            {
                if (!pose.TryGetValue(kv.Key, out var v)) continue;

                // Haluskan: pose mengejar target, bukan teleport.
                if (_prev.TryGetValue(kv.Key, out var p))
                {
                    v = new Locomotion.Vec3(
                        p.X + (v.X - p.X) * k,
                        p.Y + (v.Y - p.Y) * k,
                        p.Z + (v.Z - p.Z) * k);
                }
                _prev[kv.Key] = v;

                // Lean + crouch ditambahkan di ruang abstrak (sebelum tanda
                // kalibrasi), supaya ikut arah sumbu yang benar.
                var ex = 0.0; var ey = 0.0;
                if (kv.Key == Joint.Chest) ey = _lean * 0.30 * LeanStrength;
                else if (kv.Key == Joint.Spine) ey = _lean * 0.18 * LeanStrength;
                else if (kv.Key == Joint.LeftUpperLeg || kv.Key == Joint.RightUpperLeg)
                    ex = _crouch * 0.55;
                else if (kv.Key == Joint.LeftLowerLeg || kv.Key == Joint.RightLowerLeg)
                    ex = _crouch * 0.80;

                GetSigns(kv.Key, out var sx, out var sy, out var sz);
                var q = Quaternion.Euler(
                    (float)((v.X + ex) * sx * Mathf.Rad2Deg),
                    (float)((v.Y + ey) * sy * Mathf.Rad2Deg),
                    (float)(v.Z * sz * Mathf.Rad2Deg));
                if (!_armFix.TryGetValue(kv.Key, out var fix)) fix = Quaternion.identity;
                kv.Value.localRotation = _bind[kv.Key] * fix * q;
            }
        }

        /* Sama seperti ApplyPose tapi TANPA pengali Sign*. Dipakai oleh menu
           "Uji pose karakter" untuk melihat sumbu mentah tulang, sehingga
           kalibrasi tanda tidak mencemari hasil pengamatannya sendiri. */
        public void ApplyPoseRaw(IReadOnlyDictionary<Joint, Locomotion.Vec3> pose)
        {
            foreach (var kv in _bones)
            {
                if (!pose.TryGetValue(kv.Key, out var v)) continue;
                kv.Value.localRotation = _bind[kv.Key] * Quaternion.Euler(
                    (float)(v.X * Mathf.Rad2Deg),
                    (float)(v.Y * Mathf.Rad2Deg),
                    (float)(v.Z * Mathf.Rad2Deg));
            }
        }

        public void ResetToBind()
        {
            foreach (var kv in _bones) kv.Value.localRotation = _bind[kv.Key];
            _prev.Clear();
            _lean = 0f; _leanTarget = 0f; _crouch = 0f;
        }

        void GetSigns(Joint j, out float x, out float y, out float z)
        {
            switch (j)
            {
                case Joint.LeftUpperLeg: case Joint.RightUpperLeg:
                case Joint.LeftLowerLeg: case Joint.RightLowerLeg:
                case Joint.LeftShinTwistA: case Joint.LeftShinTwistB:
                case Joint.RightShinTwistA: case Joint.RightShinTwistB:
                    x = SignLegX; y = SignLegY; z = SignLegZ; break;

                case Joint.LeftUpperArm: case Joint.RightUpperArm:
                case Joint.LeftLowerArm: case Joint.RightLowerArm:
                case Joint.LeftHand:     case Joint.RightHand:
                    x = SignArmX; y = SignArmY; z = SignArmZ; break;

                case Joint.LeftFoot:  case Joint.RightFoot:
                case Joint.LeftToes:  case Joint.RightToes:
                    x = SignFootX; y = 1f; z = 1f; break;

                default:   // Hips, Spine, Chest, Neck, Head
                    x = SignSpineX; y = SignSpineY; z = SignSpineZ; break;
            }
        }

        void OnDrawGizmosSelected()
        {
            if (!DrawBindPoseGizmos) return;
            Gizmos.color = Color.cyan;
            foreach (var kv in _bones)
            {
                var t = kv.Value;
                Gizmos.DrawWireSphere(t.position, 0.02f);
                if (t.parent != null)
                {
                    Gizmos.color = new Color(0f, .6f, 1f, .5f);
                    Gizmos.DrawLine(t.parent.position, t.position);
                    Gizmos.color = Color.cyan;
                }
            }
        }
    }
}
