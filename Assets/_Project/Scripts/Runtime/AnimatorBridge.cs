using UnityEngine;

namespace RPG.Runtime
{
    /* ============================================================
       ANIMATOR BRIDGE — jalur ALTERNATIF: animasi jadi (Mixamo /
       Quaternius / VRM) sebagai pengganti pose prosedural.

       Cara pakai (lihat TAHAP-5.md §animasi):
         1. Impor klip animasi + buat AnimatorController dengan
            parameter: Speed (float), Move (float), Grounded (bool),
            Dash (float), Attack (trigger), Combo (int).
         2. Pasang controller ke Animator karakter.
         3. Centang komponen ini (default MATI).
       Bridge mengambil alih (CharacterRig.ProceduralEnabled=false)
       dan memetakan state motor -> parameter. Matikan lagi untuk
       kembali ke prosedural. Kalau controller kosong, bridge
       menonaktifkan diri sendiri dengan aman.
       ============================================================ */
    [DisallowMultipleComponent]
    public class AnimatorBridge : MonoBehaviour
    {
        [Header("Rujukan (kosong = cari sendiri)")]
        public Animator Animator;
        public CharacterMotor Motor;
        public CharacterRig Rig;

        bool _attackSent;

        void Reset()
        {
            Animator = GetComponentInChildren<Animator>();
            Motor = GetComponent<CharacterMotor>();
            Rig = GetComponent<CharacterRig>();
        }

        void Awake()
        {
            if (Animator == null) Animator = GetComponentInChildren<Animator>();
            if (Motor == null) Motor = GetComponent<CharacterMotor>();
            if (Rig == null) Rig = GetComponent<CharacterRig>();
        }

        void OnEnable()
        {
            if (Animator == null) Animator = GetComponentInChildren<Animator>();
            if (Rig == null) Rig = GetComponent<CharacterRig>();
            if (Animator == null || Animator.runtimeAnimatorController == null)
            {
                Debug.LogWarning("[AnimatorBridge] tidak ada controller — kembali ke prosedural.");
                enabled = false;
                return;
            }
            if (Rig != null) Rig.ProceduralEnabled = false;
            Animator.enabled = true;
        }

        void OnDisable()
        {
            if (Rig != null) Rig.ProceduralEnabled = true;
        }

        void Update()
        {
            if (Animator == null || Motor == null) return;
            Animator.SetFloat("Speed", Motor.Speed);
            Animator.SetFloat("Move", (float)Motor.Move01);
            Animator.SetBool("Grounded", Motor.Grounded);
            Animator.SetFloat("Dash", Motor.IsDashing ? 1f : 0f);
            if (Motor.IsAttacking && !_attackSent)
            {
                Animator.SetInteger("Combo", Motor.Combat.Combo);
                Animator.SetTrigger("Attack");
                _attackSent = true;
            }
            else if (!Motor.IsAttacking) _attackSent = false;
        }
    }
}
