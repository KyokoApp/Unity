using System;
using UnityEngine;
using RPG.Core;

namespace RPG.Runtime
{
    /* ============================================================
       CHARACTER MOTOR — menggerakkan karakter di dunia dan
       menghasilkan pose.

       Angka kecepatan TIDAK dikarang. Dari DESAIN.md §1, diukur dari
       game aslinya (index.html:1317):

           jalan  6,5 m/s
           lari  13,5 m/s

       Karena mobil sudah dibuang, ini satu-satunya alat tempuh, dan
       seluruh keputusan ukuran dunia 3 km diturunkan dari dua angka
       itu. Mengubahnya di sini berarti mengubah premis desainnya —
       jadi keduanya ditaruh sebagai konstanta bernama, bukan angka
       ajaib di tengah rumus.

       Tinggi tanah diambil dari WorldData.TerrainH(), satu-satunya
       sumber kebenaran terrain. Jangan pernah menulis ketinggian
       sendiri di tempat lain: kalau rumus terrain berubah di Fase 3,
       karakter ini ikut benar dengan sendirinya.
       ============================================================ */
    [RequireComponent(typeof(CharacterRig))]
    [DisallowMultipleComponent]
    public class CharacterMotor : MonoBehaviour
    {
        [Header("Kecepatan (m/s) — dari game asli, lihat komentar di atas")]
        public float WalkSpeed = 6.5f;
        public float RunSpeed  = 13.5f;

        [Header("Lompat & gravitasi")]
        public float Gravity     = 22f;
        public float JumpSpeed   = 7.0f;
        [Tooltip("Jarak root karakter di atas tanah. VRM biasanya punya origin di telapak kaki, jadi 0.")]
        public float GroundOffset = 0f;

        [Header("Irama langkah (rad/s)")]
        [Tooltip("phase += dt * (CadenceBase + CadencePerSpeed * kecepatan). " +
                 "Default menghasilkan ~1,7 langkah/detik saat jalan dan ~2,7 saat lari.")]
        public float CadenceBase     = 5.4f;
        public float CadencePerSpeed = 0.86f;

        [Header("Putaran badan")]
        [Tooltip("Kecepatan karakter berputar menghadap arah jalan (1/detik).")]
        public float TurnRate = 14f;

        [Header("Rujukan")]
        public CameraRig Camera;
        public TouchJoystick Joystick;
        public CharacterRig Rig;

        /* ---- keadaan yang dibaca komponen lain ---- */
        public Vector3 Velocity { get; private set; }
        public float Speed => new Vector2(Velocity.x, Velocity.z).magnitude;
        public bool Grounded { get; private set; } = true;
        public float Phase { get; private set; }
        public double Move01 { get; private set; }
        public double Run01 { get; private set; }

        float _vy;
        float _yaw;
        double _clock;

        void Reset()
        {
            Rig = GetComponent<CharacterRig>();
            Camera = FindFirstObjectByType<CameraRig>();
            Joystick = FindFirstObjectByType<TouchJoystick>();
        }

        void Awake()
        {
            if (Rig == null) Rig = GetComponent<CharacterRig>();
            SnapToGround();
            _yaw = transform.eulerAngles.y;
        }

        void Update()
        {
            var dt = Time.deltaTime;
            _clock += dt;

            // ---- 1. masukan -------------------------------------------------
            ReadInput(out var ix, out var iz, out var wantRun, out var wantJump);

            // ---- 2. arah relatif kamera -------------------------------------
            var camYaw = Camera != null ? Camera.Yaw : transform.eulerAngles.y;
            var wish = CameraRelative(ix, iz, camYaw);
            var mag = wish.magnitude;                       // 0..1 setelah deadzone
            if (mag > 1f) wish /= mag;

            var target = wantRun ? RunSpeed : WalkSpeed;
            var speed  = target * Mathf.Min(1f, mag);
            Velocity   = wish * speed;

            // ---- 3. integrasi horizontal + batas dunia ----------------------
            var p = transform.position;
            p.x += Velocity.x * dt;
            p.z += Velocity.z * dt;
            var limit = (float)WorldData.WorldLimit;
            p.x = Mathf.Clamp(p.x, -limit, limit);
            p.z = Mathf.Clamp(p.z, -limit, limit);

            // ---- 4. vertikal: gravitasi, lompat, tempel tanah ----------------
            if (wantJump && Grounded) { _vy = JumpSpeed; Grounded = false; }
            _vy -= Gravity * dt;
            p.y += _vy * dt;

            var ground = GroundHeight(p.x, p.z) + GroundOffset;
            if (p.y <= ground)
            {
                p.y = ground;
                _vy = 0f;
                Grounded = true;
            }
            else Grounded = false;

            transform.position = p;

            // ---- 5. hadap arah jalan ----------------------------------------
            if (mag > 0.05f)
            {
                var wantYaw = Mathf.Atan2(wish.x, wish.z) * Mathf.Rad2Deg;
                _yaw = DampAngle(_yaw, wantYaw, TurnRate, dt);
                transform.rotation = Quaternion.Euler(0f, _yaw, 0f);
            }

            // ---- 6. irama langkah -------------------------------------------
            var sp = Speed;
            if (Grounded && mag > 0.01f) Phase += dt * (CadenceBase + CadencePerSpeed * sp);

            Move01 = Math.Min(1.0, sp / Math.Max(0.001, WalkSpeed));
            Run01  = Math.Max(0.0, Math.Min(1.0,
                       (sp - WalkSpeed) / Math.Max(0.001, RunSpeed - WalkSpeed)));
        }

        /* LateUpdate, bukan Update: posisi sudah final, dan VRMSpringBone juga
           jalan di LateUpdate sehingga rok/rambut membaca tulang yang sudah
           di-pose pada frame yang sama. */
        void LateUpdate()
        {
            if (Rig == null || !Rig.IsBound) return;

            var input = new Locomotion.PoseInput(
                Phase,
                _clock,
                Move01,
                Run01,
                0,                          // dash: belum ada di Tahap 2
                !Grounded,
                !Grounded && _vy < 0f,
                null,                       // attack: Tahap 5
                0);

            var pose = Locomotion.SamplePose(input);
            var resolved = RigMapping.Resolve(pose);
            Rig.ApplyPose(resolved);
        }

        // ------------------------------------------------------------------
        public float GroundHeight(float x, float z) =>
            (float)WorldData.TerrainH(x, z);

        void SnapToGround()
        {
            var p = transform.position;
            p.y = GroundHeight(p.x, p.z) + GroundOffset;
            transform.position = p;
            _vy = 0f;
            Grounded = true;
        }

        /* Sumbu joystick/keyboard -> arah dunia, diputar menurut yaw kamera.
           Izinkan kamera null supaya komponen ini tetap bisa dites sendirian. */
        public static Vector3 CameraRelative(float ix, float iz, float camYawDeg)
        {
            if (ix == 0f && iz == 0f) return Vector3.zero;
            var rad = camYawDeg * Mathf.Deg2Rad;
            var cos = Mathf.Cos(rad);
            var sin = Mathf.Sin(rad);
            // iz = "maju" pada joystick; di Unity maju adalah +Z relatif kamera
            return new Vector3(ix * cos + iz * sin, 0f, iz * cos - ix * sin).normalized
                   * Mathf.Clamp01(Mathf.Sqrt(ix * ix + iz * iz));
        }

        void ReadInput(out float ix, out float iz, out bool run, out bool jump)
        {
            ix = Input.GetAxisRaw("Horizontal");
            iz = Input.GetAxisRaw("Vertical");

            if (Joystick != null && Joystick.IsActive)
            {
                var a = Joystick.Axis;
                ix = (float)a.X;
                iz = (float)a.Y;
            }

            run  = Input.GetKey(KeyCode.LeftShift) || Input.GetKey(KeyCode.RightShift)
                   || (Joystick != null && Joystick.RunHeld);
            jump = Input.GetKeyDown(KeyCode.Space) || (Joystick != null && Joystick.JumpPressed);
        }

        /* Locomotion.Damp bekerja pada nilai skalar lurus. Untuk sudut harus
           lewat selisih terpendek, kalau tidak karakter berputar 350 derajat
           untuk perubahan 10 derajat. */
        public static float DampAngle(float current, float target, float rate, float dt)
        {
            var delta = Mathf.DeltaAngle(current, target);
            return current + delta * (1f - Mathf.Exp(-rate * dt));
        }

        void OnDrawGizmosSelected()
        {
            Gizmos.color = Color.yellow;
            Gizmos.DrawWireSphere(transform.position, 0.15f);
            Gizmos.color = Color.green;
            Gizmos.DrawLine(transform.position, transform.position + Velocity * 0.25f);
        }
    }
}
