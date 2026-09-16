using System;
using UnityEngine;
using RPG.Core;

namespace RPG.Runtime
{
    /* ============================================================
       CHARACTER MOTOR — menggerakkan karakter di dunia dan
       menghasilkan pose.

       Angka kecepatan TIDAK dikarang. Dari DESAIN.md §1, diukur dari
       game aslinya (index.html:1317): jalan 6,5 m/s, lari 13,5 m/s.

       Tinggi tanah diambil dari WorldData.TerrainH(), satu-satunya
       sumber kebenaran terrain.

       Perbaikan Tahap 5 (sebelumnya bug nyata):
       [1] Camera selalu null — builder membuat karakter SEBELUM
           kamera, jadi gerak "relatif kamera" diam-diam memakai yaw
           karakter sendiri. Sekarang dicari ulang di Awake.
       [2] Kecepatan diset langsung (wish*speed) = gerak kaku,
           pose patah saat start/stop. Sekarang akselerasi/
           deselerasi + Move/Run yang di-damp.
       [3] Lompat tanpa coyote-time & jump-buffer = sering gagal di
           tepi tebing. Sekarang ada keduanya.
       [4] Attack/combo/dash tidak pernah terpicu (input attack null
           permanen). Sekarang: klik kiri / tombol HUD = tebasan
           kombo 3x, dashpakai stamina, sprint menguras stamina.
       ============================================================ */
    [RequireComponent(typeof(CharacterRig))]
    [DisallowMultipleComponent]
    public class CharacterMotor : MonoBehaviour
    {
        [Header("Kecepatan (m/s) — dari game asli, lihat komentar di atas")]
        public float WalkSpeed = 6.5f;
        public float RunSpeed  = 13.5f;

        [Header("Kehalusan gerak")]
        [Tooltip("Akselerasi menuju kecepatan target (m/s^2).")]
        public float Acceleration = 26f;
        [Tooltip("Deselerasi saat melepas input (m/s^2).")]
        public float Deceleration = 34f;

        [Header("Lompat & gravitasi")]
        public float Gravity     = 22f;
        public float JumpSpeed   = 7.0f;
        [Tooltip("Jarak root karakter di atas tanah. VRM biasanya punya origin di telapak kaki, jadi 0.")]
        public float GroundOffset = 0f;
        [Tooltip("Masih bisa lompat sekian detik setelah meninggalkan tanah.")]
        public float CoyoteTime = 0.12f;
        [Tooltip("Menekan lompat sedikit sebelum mendarat tetap dihitung.")]
        public float JumpBuffer = 0.15f;

        [Header("Dash & stamina")]
        public float DashSpeed = 20f;
        public float DashTime = 0.18f;
        public float DashStaminaCost = 0.25f;
        [Tooltip("Stamina/detik saat sprint.")]
        public float SprintDrain = 0.15f;

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
        public VirtualJoystick Stick;
        public CharacterRig Rig;

        /* ---- keadaan yang dibaca komponen lain ---- */
        public Vector3 Velocity { get; private set; }
        public float Speed => new Vector2(Velocity.x, Velocity.z).magnitude;
        public bool Grounded { get; private set; } = true;
        public float Phase { get; private set; }
        public double Move01 { get; private set; }
        public double Run01 { get; private set; }
        public float Stamina01 => (float)_combat.Stamina;
        public bool IsDashing => _dashT > 0f;
        public bool IsAttacking => _combat.IsAttacking;
        public CombatState Combat => _combat;

        public event Action Landed;
        public event Action<int> AttackStarted;

        readonly CombatState _combat = new CombatState();
        float _vy;
        float _yaw;
        float _prevYaw;
        double _clock;
        Vector3 _velSm;
        float _coyote;
        float _jumpBuf;
        float _fallSpeed;
        float _dashT;
        Vector3 _dashDir = Vector3.forward;
        double _moveSm;
        double _runSm;

        void Reset()
        {
            Rig = GetComponent<CharacterRig>();
            Camera = FindFirstObjectByType<CameraRig>();
            Joystick = FindFirstObjectByType<TouchJoystick>();
            Stick = FindFirstObjectByType<VirtualJoystick>();
        }

        void Awake()
        {
            if (Rig == null) Rig = GetComponent<CharacterRig>();
            if (Camera == null) Camera = FindFirstObjectByType<CameraRig>();
            if (Joystick == null) Joystick = FindFirstObjectByType<TouchJoystick>();
            if (Stick == null) Stick = FindFirstObjectByType<VirtualJoystick>();
            SnapToGround();
            _yaw = transform.eulerAngles.y;
            _prevYaw = _yaw;
        }

        void OnDisable() { HudInput.ResetFrame(); }

        void Update()
        {
            var dt = Time.deltaTime;
            if (dt <= 0f) return;
            _clock += dt;

            // ---- 1. masukan -------------------------------------------------
            ReadInput(out var ix, out var iz, out var runBtn, out var wantJump,
                      out var wantAttack, out var wantDash, out var analog);

            // ---- 2. arah relatif kamera -------------------------------------
            var camYaw = Camera != null ? Camera.Yaw : transform.eulerAngles.y;
            var wish = CameraRelative(ix, iz, camYaw);
            var mag = Mathf.Clamp01(wish.magnitude);
            if (wish.magnitude > 1f) wish = wish.normalized;

            // Stik analog didorong penuh = sprint otomatis (ala Genshin —
            // tidak perlu tombol lari terpisah). Keyboard tidak ikut
            // (magnitudo keyboard selalu 0/1).
            var wantRun = runBtn || (analog && mag > 0.92f);
            var canSprint = _combat.Stamina > 0.02;
            var sprinting = wantRun && canSprint && mag > 0.1f && !_combat.IsAttacking;

            _combat.Update(dt, _clock, sprinting && Grounded ? SprintDrain : 0.0);

            // ---- 3. dash ------------------------------------------------------
            if (wantDash && !IsDashing && _combat.SpendStamina(DashStaminaCost))
            {
                _dashT = DashTime;
                _dashDir = mag > 0.1f ? wish.normalized
                    : new Vector3(Mathf.Sin(_yaw * Mathf.Deg2Rad), 0f,
                                  Mathf.Cos(_yaw * Mathf.Deg2Rad));
                _yaw = Mathf.Atan2(_dashDir.x, _dashDir.z) * Mathf.Rad2Deg;
                transform.rotation = Quaternion.Euler(0f, _yaw, 0f);
                AnimeVFX.Dash(transform.position + Vector3.up * 0.6f);
                if (Camera != null) Camera.AddShake(0.25f);
            }
            if (_dashT > 0f) _dashT -= dt;

            // ---- 4. serangan --------------------------------------------------
            if (wantAttack && !IsDashing && _combat.TryAttack(_clock))
            {
                AttackStarted?.Invoke(_combat.Combo);
                // Menyerang sambil diam = menghadap arah kamera.
                var faceYaw = mag > 0.05f
                    ? Mathf.Atan2(wish.x, wish.z) * Mathf.Rad2Deg : camYaw;
                _yaw = faceYaw;
                transform.rotation = Quaternion.Euler(0f, _yaw, 0f);
                var fwd = new Vector3(Mathf.Sin(_yaw * Mathf.Deg2Rad), 0f,
                                      Mathf.Cos(_yaw * Mathf.Deg2Rad));
                AnimeVFX.Slash(transform.position + Vector3.up * 1.1f + fwd * 0.9f,
                               _combat.Combo);
                if (Camera != null) Camera.AddShake(0.12f);
            }

            // ---- 5. kecepatan target + penghalusan -----------------------------
            var speedMul = _combat.IsAttacking ? 0.25f : 1f;
            var target = wantRun && canSprint ? RunSpeed : WalkSpeed;
            var want = wish * (target * Mathf.Min(1f, mag)) * speedMul;
            if (IsDashing) want = _dashDir * DashSpeed;

            var rate = want.magnitude > _velSm.magnitude ? Acceleration : Deceleration;
            _velSm = Vector3.MoveTowards(_velSm, want, rate * dt);
            Velocity = new Vector3(_velSm.x, 0f, _velSm.z);

            // ---- 6. integrasi horizontal + batas dunia --------------------------
            var p = transform.position;
            p.x += _velSm.x * dt;
            p.z += _velSm.z * dt;
            var limit = (float)WorldData.WorldLimit;
            p.x = Mathf.Clamp(p.x, -limit, limit);
            p.z = Mathf.Clamp(p.z, -limit, limit);

            // ---- 7. vertikal: coyote, buffer, tempel tanah -----------------------
            if (Grounded) _coyote = CoyoteTime; else _coyote -= dt;
            if (wantJump) _jumpBuf = JumpBuffer; else _jumpBuf -= dt;
            if (_jumpBuf > 0f && _coyote > 0f)
            {
                _vy = JumpSpeed; Grounded = false;
                _coyote = 0f; _jumpBuf = 0f;
            }
            _vy -= Gravity * dt;
            p.y += _vy * dt;
            _fallSpeed = _vy;

            var ground = GroundHeight(p.x, p.z) + GroundOffset;
            if (p.y <= ground)
            {
                if (!Grounded) OnTouchdown(_fallSpeed);
                p.y = ground;
                _vy = 0f;
                Grounded = true;
            }
            else Grounded = false;

            transform.position = p;

            // ---- 8. hadap arah jalan --------------------------------------------
            var turnRate = _combat.IsAttacking ? TurnRate * 0.3f : TurnRate;
            if (mag > 0.05f)
            {
                var wantYaw = Mathf.Atan2(wish.x, wish.z) * Mathf.Rad2Deg;
                _yaw = DampAngle(_yaw, wantYaw, turnRate, dt);
                transform.rotation = Quaternion.Euler(0f, _yaw, 0f);
            }
            else if (_combat.IsAttacking)
            {
                _yaw = DampAngle(_yaw, camYaw, turnRate, dt);
                transform.rotation = Quaternion.Euler(0f, _yaw, 0f);
            }

            // Lean badan saat berputar tajam (dibaca CharacterRig).
            if (Rig != null && dt > 0f)
            {
                var yawRate = Mathf.DeltaAngle(_prevYaw, _yaw) / dt;
                Rig.SetLean(Mathf.Clamp(yawRate / 220f, -1f, 1f));
            }
            _prevYaw = _yaw;

            // ---- 9. irama langkah + blend gerak yang dihaluskan -------------------
            var sp = Speed;
            if (Grounded && sp > 0.3f)
                Phase += dt * (CadenceBase + CadencePerSpeed * sp);

            var moveT = Math.Min(1.0, sp / Math.Max(0.001, WalkSpeed));
            var runT = Math.Max(0.0, Math.Min(1.0,
                       (sp - WalkSpeed) / Math.Max(0.001, RunSpeed - WalkSpeed)));
            _moveSm = Locomotion.Damp(_moveSm, moveT, 8.0, dt);
            _runSm = Locomotion.Damp(_runSm, runT, 8.0, dt);
            Move01 = _moveSm;
            Run01 = _runSm;

            HudInput.ResetFrame();
        }

        void OnTouchdown(float fallSpeed)
        {
            Landed?.Invoke();
            if (fallSpeed < -7f && Rig != null)
                Rig.PulseCrouch(Mathf.Clamp((-fallSpeed - 7f) / 8f, 0.25f, 1f));
            if (fallSpeed < -9f)
            {
                AnimeVFX.Land(transform.position + Vector3.up * 0.15f);
                if (Camera != null) Camera.AddShake(0.3f);
            }
        }

        /* LateUpdate, bukan Update: posisi sudah final, dan VRMSpringBone juga
           jalan di LateUpdate sehingga rok/rambut membaca tulang yang sudah
           di-pose pada frame yang sama. */
        void LateUpdate()
        {
            if (Rig == null || !Rig.IsBound || !Rig.ProceduralEnabled) return;

            double? attack = _combat.IsAttacking ? (double?)_combat.Attack01 : null;
            var input = new Locomotion.PoseInput(
                Phase,
                _clock,
                Move01,
                Run01,
                IsDashing ? 1.0 : 0.0,
                !Grounded,
                !Grounded && _vy < 0f,
                attack,
                _combat.Combo);

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

        void ReadInput(out float ix, out float iz, out bool runBtn, out bool jump,
                       out bool attack, out bool dash, out bool analog)
        {
            ix = Input.GetAxisRaw("Horizontal");
            iz = Input.GetAxisRaw("Vertical");
            analog = false;

            if (Joystick != null && Joystick.IsActive)
            {
                var a = Joystick.Axis;
                ix = (float)a.X;
                iz = (float)a.Y;
                analog = true;
            }
            // Stik uGUI (HUD Genshin) dibangun WorldBoot SETELAH Awake motor,
            // jadi dicari malas di sini. Tanpa ini stik yang terlihat di HUD
            // tidak menggerakkan karakter.
            if (Stick == null) Stick = FindFirstObjectByType<VirtualJoystick>();
            if (Camera == null) Camera = FindFirstObjectByType<CameraRig>();
            if (Stick != null && Stick.IsActive)
            {
                var a = Stick.Axis;
                ix = (float)a.X;
                iz = (float)a.Y;
                analog = true;
            }

            runBtn = Input.GetKey(KeyCode.LeftShift) || Input.GetKey(KeyCode.RightShift)
                     || (Joystick != null && Joystick.RunHeld);
            jump = Input.GetKeyDown(KeyCode.Space)
                   || (Joystick != null && Joystick.JumpPressed)
                   || HudInput.JumpPressed;
            // Klik kiri = serang, TAPI bukan saat klik tombol HUD.
            attack = (Input.GetMouseButtonDown(0) && !PointerOverUi())
                     || HudInput.AttackPressed;
            dash = Input.GetKeyDown(KeyCode.LeftControl) || HudInput.DashPressed;
        }

        static bool PointerOverUi() =>
            UnityEngine.EventSystems.EventSystem.current != null &&
            UnityEngine.EventSystems.EventSystem.current.IsPointerOverGameObject();

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
