using UnityEngine;

/// <summary>
/// Kamera dan gerak first-person tanpa model/renderer. Input berasal dari
/// joystick sentuh, swipe kamera, atau WASD saat diuji di editor.
/// </summary>
public class FirstPersonRoomController : MonoBehaviour
{
    public const float WalkSpeed = 2.15f;
    public const float EyeHeight = 1.64f;
    const float Gravity = -22f;
    const float MaxFallSpeed = -22f;
    const float LookDegreesPerScreenHeight = 70f;
    const float CameraBobAmount = 0.018f;

    public Vector2 MoveInput { get; set; }
    public Camera ViewCamera { get; private set; }
    public float Yaw { get { return yaw; } }
    public float Pitch { get { return pitch; } }
    public float DistanceTravelled { get; private set; }

    CharacterController characterController;
    Transform cameraTransform;
    float yaw;
    float pitch;
    float verticalSpeed;
    float bobPhase;
    float bobAmount;
    Vector3 planarVelocity;

    /// <summary>Dipanggil bootstrap setelah kamera scene ditemukan/dibuat.</summary>
    public void Initialize(Camera viewCamera, Vector3 spawnPoint, float initialYaw = 9f)
    {
        ViewCamera = viewCamera;
        transform.position = spawnPoint;
        yaw = initialYaw;
        pitch = 2.5f;

        characterController = gameObject.AddComponent<CharacterController>();
        characterController.height = 1.82f;
        characterController.radius = 0.29f;
        characterController.center = new Vector3(0f, 0.91f, 0f);
        characterController.slopeLimit = 48f;
        characterController.stepOffset = 0.18f;
        characterController.skinWidth = 0.035f;
        characterController.minMoveDistance = 0f;

        if (ViewCamera == null) return;
        cameraTransform = ViewCamera.transform;
        cameraTransform.SetParent(transform, false);
        cameraTransform.localPosition = new Vector3(0f, EyeHeight, 0f);
        cameraTransform.localRotation = Quaternion.Euler(pitch, 0f, 0f);
        transform.rotation = Quaternion.Euler(0f, yaw, 0f);
    }

    /// <summary>delta dalam piksel; satu swipe setinggi layar ≈ 70 derajat.</summary>
    public void AddLookPixels(Vector2 delta)
    {
        float sensitivity = LookDegreesPerScreenHeight / Mathf.Max(1, Screen.height);
        yaw += delta.x * sensitivity;
        pitch = Mathf.Clamp(pitch - delta.y * sensitivity, -78f, 78f);
        transform.rotation = Quaternion.Euler(0f, yaw, 0f);
        ApplyCameraPitch();
    }

    /// <summary>
    /// Saat lorong di-recycle, posisi pemain dan seluruh modul digeser dengan
    /// jumlah yang sama agar gerak terasa benar-benar tanpa ujung dan presisi float tetap baik.
    /// </summary>
    public void RebaseZ(float amount)
    {
        bool wasEnabled = characterController != null && characterController.enabled;
        if (wasEnabled) characterController.enabled = false;
        Vector3 p = transform.position;
        p.z += amount;
        transform.position = p;
        if (wasEnabled) characterController.enabled = true;
    }

    void Update()
    {
        if (characterController == null) return;

        float dt = Mathf.Clamp(Time.deltaTime, 0f, 0.08f);
        if (dt <= 0f) return;

        Vector2 input = Vector2.ClampMagnitude(MoveInput, 1f);
        Vector2 keyboard = new Vector2(Input.GetAxisRaw("Horizontal"), Input.GetAxisRaw("Vertical"));
        if (keyboard.sqrMagnitude > input.sqrMagnitude)
            input = Vector2.ClampMagnitude(keyboard, 1f);

        // Drag pada pad UI berfungsi di HP. Klik kanan + mouse juga nyaman untuk Play Mode.
        if (!Application.isMobilePlatform && Input.GetMouseButton(1))
        {
            yaw += Input.GetAxis("Mouse X") * 2.4f;
            pitch = Mathf.Clamp(pitch - Input.GetAxis("Mouse Y") * 2.4f, -78f, 78f);
            transform.rotation = Quaternion.Euler(0f, yaw, 0f);
            ApplyCameraPitch();
        }

        Vector3 wish = transform.forward * input.y + transform.right * input.x;
        wish.y = 0f;
        if (wish.sqrMagnitude > 1f) wish.Normalize();

        float magnitude = input.magnitude;
        float inputSpeed = magnitude < 0.06f
            ? 0f
            : WalkSpeed * Mathf.Lerp(0.35f, 1f, Mathf.InverseLerp(0.06f, 1f, magnitude));
        Vector3 targetVelocity = wish * inputSpeed;
        planarVelocity = Vector3.MoveTowards(planarVelocity, targetVelocity, 7.5f * dt);

        if (characterController.isGrounded && verticalSpeed < 0f)
            verticalSpeed = -1.2f;
        else
            verticalSpeed = Mathf.Max(verticalSpeed + Gravity * dt, MaxFallSpeed);

        Vector3 before = transform.position;
        characterController.Move((planarVelocity + Vector3.up * verticalSpeed) * dt);

        // Lorong hanya dapat dilalui di jalur kiri yang kering. Batas ini tetap
        // membolehkan pemain merapat ke tepi air untuk melihat ke bawah.
        Vector3 p = transform.position;
        p.x = Mathf.Clamp(p.x, EndlessRoom.MinWalkX, EndlessRoom.MaxWalkX);
        if (p.y < -4f)
        {
            p.x = EndlessRoom.SpawnX;
            p.y = 0.03f;
            p.z = 0f;
            verticalSpeed = 0f;
            planarVelocity = Vector3.zero;
        }
        transform.position = p;

        Vector3 travelled = transform.position - before;
        DistanceTravelled += new Vector2(travelled.x, travelled.z).magnitude;

        float moving = planarVelocity.magnitude;
        if (moving > 0.12f)
        {
            bobPhase += dt * Mathf.Lerp(5f, 8f, moving / WalkSpeed);
            bobAmount = Mathf.MoveTowards(bobAmount, 1f, dt * 3f);
        }
        else
        {
            bobAmount = Mathf.MoveTowards(bobAmount, 0f, dt * 2.5f);
        }

        if (cameraTransform != null)
        {
            float bob = Mathf.Sin(bobPhase) * CameraBobAmount * bobAmount;
            float sway = Mathf.Sin(bobPhase * 0.5f) * 0.008f * bobAmount;
            Vector3 targetPosition = new Vector3(sway, EyeHeight + bob, 0f);
            cameraTransform.localPosition = Vector3.Lerp(cameraTransform.localPosition,
                targetPosition, 1f - Mathf.Exp(-12f * dt));
        }
    }

    void ApplyCameraPitch()
    {
        if (cameraTransform != null)
            cameraTransform.localRotation = Quaternion.Euler(pitch, 0f, 0f);
    }
}
