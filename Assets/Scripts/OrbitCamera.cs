using UnityEngine;

/// <summary>Kamera orbit third-person; diputar lewat geser jari di sisi kanan layar.</summary>
public class OrbitCamera : MonoBehaviour
{
    public Transform target;
    public float distance = 4.8f;
    public float yaw;
    public float pitch = 16f;

    public void AddLook(Vector2 delta)
    {
        yaw += delta.x * 0.22f;
        pitch = Mathf.Clamp(pitch - delta.y * 0.18f, -8f, 68f);
    }

    public void SnapBehind(Transform player)
    {
        yaw = player.eulerAngles.y;
        ApplyImmediate();
    }

    void LateUpdate()
    {
        if (target == null) return;
        var rot = Quaternion.Euler(pitch, yaw, 0f);
        Vector3 desired = target.position + rot * new Vector3(0f, 0f, -distance);
        if (desired.y < 0.3f) desired.y = 0.3f;

        float k = 1f - Mathf.Exp(-16f * Time.deltaTime);
        transform.position = Vector3.Lerp(transform.position, desired, k);

        Vector3 look = target.position - transform.position;
        if (look.sqrMagnitude > 0.0001f)
            transform.rotation = Quaternion.LookRotation(look.normalized, Vector3.up);
    }

    void ApplyImmediate()
    {
        if (target == null) return;
        var rot = Quaternion.Euler(pitch, yaw, 0f);
        Vector3 desired = target.position + rot * new Vector3(0f, 0f, -distance);
        if (desired.y < 0.3f) desired.y = 0.3f;
        transform.position = desired;
        Vector3 look = target.position - transform.position;
        if (look.sqrMagnitude > 0.0001f)
            transform.rotation = Quaternion.LookRotation(look.normalized, Vector3.up);
    }
}
