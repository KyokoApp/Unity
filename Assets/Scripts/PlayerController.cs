using UnityEngine;

/// <summary>
/// Kontrol karakter untuk Android: analog kiri untuk gerak (walk -> run sesuai
/// kemiringan analog), tombol LOMPAT / SERANG (combo pedang) / SLIDE / LARI,
/// plus pemutaran semua animasi UAL2 dari panel ANIMASI.
/// </summary>
public class PlayerController : MonoBehaviour
{
    public Transform cameraTransform;
    public Vector2 MoveInput { get; set; }
    public Transform CameraTarget { get; private set; }

    // ---- tuning (bisa di-update live oleh ContentUpdater tanpa instal ulang) ----
    public static float WalkSpeed = 2.1f;
    public static float RunSpeed = 4.6f;
    public static float SprintMul = 1.35f;
    public static float RotSpeed = 14f;
    public static float Gravity = -30f;
    public static float JumpVel = 9f;

    CharacterController cc;
    PlayerAnimator anim;
    AnimLibrary lib;

    GameObject modelInstance;
    int modelIndex;

    enum State { Loco, Air, Land, Action, Slide }
    State state = State.Loco;

    float vy;
    float speedSm;
    bool sprint;
    Vector3 lastMoveDir = Vector3.forward;

    // aksi / combo
    static readonly string[] Combo = { "Sword_Regular_A", "Sword_Regular_B", "Sword_Regular_C" };
    string actionKey = "";
    bool actionLoop;
    float actionTime;
    int comboStage;
    bool comboQueued;

    // slide
    int slidePhase;
    float slideTimer;
    Vector3 slideDir;

    float landTimer;

    public bool Sprint { get { return sprint; } }
    public string CurrentModelName { get { return modelIndex == 0 ? "UAL2" : "Mannequin F"; } }

    public void Init(AnimLibrary library)
    {
        lib = library;

        cc = gameObject.AddComponent<CharacterController>();
        cc.height = 1.75f;
        cc.center = new Vector3(0f, 0.92f, 0f);
        cc.radius = 0.33f;
        cc.slopeLimit = 50f;
        cc.stepOffset = 0.4f;
        cc.skinWidth = 0.04f;

        anim = gameObject.AddComponent<PlayerAnimator>();

        CameraTarget = new GameObject("CamTarget").transform;
        CameraTarget.SetParent(transform, false);
        CameraTarget.localPosition = new Vector3(0f, 1.45f, 0f);

        SetModel(0);
    }

    // ================= MODEL =================

    public void ToggleModel()
    {
        SetModel(1 - modelIndex);
    }

    void SetModel(int idx)
    {
        modelIndex = idx;
        if (modelInstance != null) Destroy(modelInstance);

        GameObject prefab = idx == 0 ? lib.ModelUAL2 : lib.ModelMannequinF;
        if (prefab == null) { Debug.LogError("[UAL2] Model tidak ditemukan di Resources/UAL2"); return; }

        modelInstance = Instantiate(prefab, transform);
        modelInstance.transform.localPosition = Vector3.zero;
        modelInstance.transform.localRotation = Quaternion.identity;

        var animator = modelInstance.GetComponentInChildren<Animator>();
        if (animator == null) animator = modelInstance.AddComponent<Animator>();
        animator.applyRootMotion = false;
        animator.cullingMode = AnimatorCullingMode.AlwaysAnimate;

        anim.Bind(animator);
        state = State.Loco;
        anim.Play(lib.Get("Idle_FoldArms_Loop"), true, 1f, 0f);
    }

    // ================= INPUT DARI UI =================

    public void SetSprint(bool on) { sprint = on; }

    public void OnJump()
    {
        if (state == State.Air) return;
        vy = JumpVel;
        state = State.Air;
        anim.Play(lib.Get("NinjaJump_Start"), false, 1.25f, 0.08f);
    }

    public void OnAttack()
    {
        if (state == State.Air) return;
        if (state == State.Action && IsComboKey(actionKey))
        {
            comboQueued = true; // lanjut combo A -> B -> C
            return;
        }
        comboStage = 0;
        comboQueued = false;
        StartAction(Combo[0], false, 1.15f);
    }

    public void OnSlide()
    {
        if (state == State.Air || state == State.Slide) return;
        state = State.Slide;
        slidePhase = 0;
        slideDir = lastMoveDir.sqrMagnitude > 0.01f ? lastMoveDir : transform.forward;
        slideDir.y = 0f; slideDir.Normalize();
        transform.rotation = Quaternion.LookRotation(slideDir);
        anim.Play(lib.Get("Slide_Start"), false, 1.2f, 0.08f);
    }

    /// <summary>Dipanggil panel ANIMASI: mainkan clip apa pun dari library.</summary>
    public void PlayLibraryClip(string key)
    {
        if (state == State.Air) return;
        comboQueued = false;
        StartAction(key, AnimLibrary.IsLoop(key), 1f);
    }

    void StartAction(string key, bool loop, float speed)
    {
        var c = lib.Get(key);
        if (c == null) return;
        state = State.Action;
        actionKey = key;
        actionLoop = loop;
        actionTime = 0f;
        anim.Play(c, loop, speed, 0.12f);
    }

    static bool IsComboKey(string key)
    {
        for (int i = 0; i < Combo.Length; i++)
            if (Combo[i] == key) return true;
        return false;
    }

    // ================= UPDATE =================

    void Update()
    {
        float dt = Time.deltaTime;
        if (dt <= 0f) return;

        Vector2 inp = Vector2.ClampMagnitude(MoveInput, 1f);
        float mag = inp.magnitude;
        Vector3 dir = CamRelative(inp);
        if (mag > 0.08f) lastMoveDir = dir;

        switch (state)
        {
            case State.Loco: UpdateLoco(dt, inp, dir, mag); break;
            case State.Air: UpdateAir(dt, dir, mag); break;
            case State.Land: UpdateLand(dt, mag); break;
            case State.Action: UpdateAction(dt, mag); break;
            case State.Slide: UpdateSlide(dt); break;
        }
    }

    void UpdateLoco(float dt, Vector2 inp, Vector3 dir, float mag)
    {
        float targetSpeed = 0f;
        if (mag > 0.08f)
        {
            float t = Mathf.InverseLerp(0.08f, 1f, mag); // analog: miring dikit = jalan, penuh = lari
            targetSpeed = Mathf.Lerp(WalkSpeed * 0.55f, RunSpeed, t);
            if (sprint) targetSpeed *= SprintMul;
            RotateToward(dir, dt);
        }
        speedSm = Mathf.MoveTowards(speedSm, targetSpeed, 20f * dt);

        vy = cc.isGrounded ? -3f : vy + Gravity * dt;
        Vector3 moveDir = mag > 0.08f ? dir : lastMoveDir;
        cc.Move((moveDir * speedSm + Vector3.up * vy) * dt);

        // animasi locomotion
        if (speedSm < 0.25f)
        {
            anim.Play(lib.Get("Idle_FoldArms_Loop"), true, 1f, 0.2f);
        }
        else
        {
            anim.Play(lib.Get("Walk_Carry_Loop"), true, 1f, 0.15f);
            anim.SetSpeed(Mathf.Clamp(speedSm / 2.0f, 0.7f, 2.6f));
        }
    }

    void UpdateAir(float dt, Vector3 dir, float mag)
    {
        vy += Gravity * dt;
        if (mag > 0.08f) RotateToward(dir, dt * 0.6f);
        Vector3 move = dir * (mag * Mathf.Max(speedSm, RunSpeed * 0.75f));
        cc.Move((move + Vector3.up * vy) * dt);

        if (anim.IsDone())
            anim.Play(lib.Get("NinjaJump_Idle_Loop"), true, 1f, 0.12f);

        if (cc.isGrounded && vy <= 0f)
        {
            vy = -3f;
            state = State.Land;
            landTimer = 0.3f;
            anim.Play(lib.Get("NinjaJump_Land"), false, 1.35f, 0.05f);
        }
    }

    void UpdateLand(float dt, float mag)
    {
        landTimer -= dt;
        speedSm = Mathf.MoveTowards(speedSm, 0f, 10f * dt);
        cc.Move((lastMoveDir * speedSm + Vector3.up * -3f) * dt);
        if (landTimer <= 0f || (mag > 0.4f && landTimer < 0.18f))
            state = State.Loco;
    }

    void UpdateAction(float dt, float mag)
    {
        actionTime += dt;
        speedSm = Mathf.MoveTowards(speedSm, 0f, 14f * dt);
        cc.Move((lastMoveDir * speedSm + Vector3.up * -3f) * dt);

        if (!actionLoop && anim.IsDone())
        {
            if (comboQueued && IsComboKey(actionKey) && comboStage < Combo.Length - 1)
            {
                comboStage++;
                comboQueued = false;
                StartAction(Combo[comboStage], false, 1.15f);
            }
            else
            {
                state = State.Loco;
            }
            return;
        }

        // Batalkan aksi dengan analog (loop kapan saja, non-loop setelah 75%).
        if (actionLoop && mag > 0.45f && actionTime > 0.25f) state = State.Loco;
        else if (!actionLoop && mag > 0.6f && anim.NormalizedTime > 0.75f) state = State.Loco;
    }

    void UpdateSlide(float dt)
    {
        float spd;
        switch (slidePhase)
        {
            case 0: // Slide_Start
                spd = 6.5f;
                if (anim.IsDone())
                {
                    slidePhase = 1;
                    slideTimer = 0.35f;
                    anim.Play(lib.Get("Slide_Loop"), true, 1f, 0.08f);
                }
                break;
            case 1: // Slide_Loop
                spd = 5.5f;
                slideTimer -= dt;
                if (slideTimer <= 0f)
                {
                    slidePhase = 2;
                    anim.Play(lib.Get("Slide_Exit"), false, 1.2f, 0.08f);
                }
                break;
            default: // Slide_Exit
                spd = Mathf.Lerp(3f, 0.5f, anim.NormalizedTime);
                if (anim.IsDone())
                {
                    state = State.Loco;
                    speedSm = 1.5f;
                }
                break;
        }
        cc.Move((slideDir * spd + Vector3.up * -3f) * dt);
    }

    // ================= UTIL =================

    Vector3 CamRelative(Vector2 inp)
    {
        if (inp.sqrMagnitude < 0.0001f) return Vector3.zero;
        Vector3 f = cameraTransform != null ? cameraTransform.forward : Vector3.forward;
        Vector3 r = cameraTransform != null ? cameraTransform.right : Vector3.right;
        f.y = 0f; r.y = 0f;
        f.Normalize(); r.Normalize();
        Vector3 d = f * inp.y + r * inp.x;
        return d.sqrMagnitude > 0.0001f ? d.normalized : Vector3.zero;
    }

    void RotateToward(Vector3 dir, float dt)
    {
        if (dir.sqrMagnitude < 0.0001f) return;
        var q = Quaternion.LookRotation(dir, Vector3.up);
        transform.rotation = Quaternion.Slerp(transform.rotation, q, 1f - Mathf.Exp(-RotSpeed * dt));
    }
}
