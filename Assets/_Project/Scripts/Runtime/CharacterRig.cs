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

       Kenapa langsung menulis Transform, bukan pakai Animator/muscle:
       komentar di Locomotion.cs sudah mengantisipasi jalur ini
       ("langsung menulis localRotation per Transform"). Nilai dari
       SamplePose adalah rotasi RELATIF terhadap bind pose, jadi
       bind pose direkam sekali di Awake lalu dikomposisikan:

           localRotation = bindRotation * Quaternion.Euler(rad -> deg)

       Animator pada prefab VRM DIMATIKAN. Alasannya: tanpa
       RuntimeAnimatorController pun, Animator humanoid bisa menulis
       ulang tulang tiap update dan menimpa pose kita. VRMSpringBone
       (rok & rambut) tetap jalan karena ia LateUpdate dan menyentuh
       tulang yang berbeda.

       ----------------------------------------------------------
       PENTING — ORIENTASI SUMBU TULANG
       Model ini diekspor dari Blender, jadi sumbu lokal tulangnya
       adalah hasil rigify, BUKAN sumbu ternormalisasi Unity Humanoid.
       Arah "ayun kaki ke depan" bisa jadi sumbu X, bisa -X, bisa Z.
       Itu tidak bisa dipastikan tanpa membuka Unity.

       Karena itu tiap kelompok sendi punya pengali sumbu yang bisa
       diubah di Inspector (SignLeg, SignArm, dst). Cara memakainya:
       jalankan menu Tools > Aurelia > Uji pose karakter, lihat kaki
       mana yang bergerak ke arah salah, lalu balik tanda yang
       bersangkutan. Rinciannya di TAHAP-2.md bagian "Kalibrasi sumbu".
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

        [Header("Kalibrasi sumbu — balik tanda kalau anggota badan bergerak ke arah salah")]
        [Range(-1f, 1f)] public float SignLegX = 1f, SignLegY = 1f, SignLegZ = 1f;
        [Range(-1f, 1f)] public float SignArmX = 1f, SignArmY = 1f, SignArmZ = -1f;
        [Range(-1f, 1f)] public float SignSpineX = 1f, SignSpineY = 1f, SignSpineZ = 1f;
        [Range(-1f, 1f)] public float SignFootX = 1f;

        [Header("Debug")]
        public bool DrawBindPoseGizmos = false;
        [Tooltip("Kunci karakter di bind pose (untuk memeriksa apakah bind-nya benar).")]
        public bool FreezeAtBindPose = false;

        /* Bind pose DISERIALISASI, bukan cuma disimpan di memori.

           Alasannya konkret: menu "Tools > Aurelia > 3. Uji pose karakter"
           memutar tulang di Edit Mode untuk kalibrasi sumbu. Perubahan yang
           belum di-save itu IKUT terbawa waktu masuk Play Mode, jadi kalau
           bind pose direkam ulang di Awake() ia akan merekam pose uji sebagai
           "pose netral" dan seluruh animasi jadi miring permanen.

           Dengan bind pose tersimpan di scene/prefab, Awake() hanya merekam
           ulang kalau daftarnya kosong atau ada tulang yang hilang. */
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
        Animator _animator;

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

            /* Animator dimatikan supaya tidak menimpa pose kita. */
            if (_animator != null && _animator.enabled) _animator.enabled = false;

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

        /* ----------------------------------------------------------
           Terapkan pose. Dipanggil dari CharacterMotor di LateUpdate
           (setelah karakter bergerak, sebelum SpringBone jalan).
           ---------------------------------------------------------- */
        public void ApplyPose(IReadOnlyDictionary<Joint, Locomotion.Vec3> pose)
        {
            if (FreezeAtBindPose) { ResetToBind(); return; }

            foreach (var kv in _bones)
            {
                if (!pose.TryGetValue(kv.Key, out var v)) continue;
                GetSigns(kv.Key, out var sx, out var sy, out var sz);
                var q = Quaternion.Euler(
                    (float)(v.X * sx * Mathf.Rad2Deg),
                    (float)(v.Y * sy * Mathf.Rad2Deg),
                    (float)(v.Z * sz * Mathf.Rad2Deg));
                kv.Value.localRotation = _bind[kv.Key] * q;
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
