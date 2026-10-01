using System;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;

/// <summary>Analog stick virtual: zona sentuh tetap di kiri-bawah, knob mengikuti jari.</summary>
public class VirtualJoystick : MonoBehaviour, IPointerDownHandler, IDragHandler, IPointerUpHandler
{
    const float DeadZone = 0.15f; // samme ambang sentuh seperti joystick di Godot

    public RectTransform knob;
    public float radius = 120f;
    public Vector2 Value { get; private set; }

    RectTransform rt;

    void Awake() { rt = (RectTransform)transform; }

    public void OnPointerDown(PointerEventData e) { Handle(e); }
    public void OnDrag(PointerEventData e) { Handle(e); }

    public void OnPointerUp(PointerEventData e)
    {
        Value = Vector2.zero;
        if (knob != null) knob.anchoredPosition = Vector2.zero;
    }

    void Handle(PointerEventData e)
    {
        Vector2 lp;
        if (!RectTransformUtility.ScreenPointToLocalPointInRectangle(rt, e.position, e.pressEventCamera, out lp))
            return;
        float safeRadius = Mathf.Max(1f, radius);
        Vector2 raw = Vector2.ClampMagnitude(lp / safeRadius, 1f);
        float strength = raw.magnitude;
        Value = strength <= DeadZone
            ? Vector2.zero
            : raw.normalized * ((strength - DeadZone) / (1f - DeadZone));
        // Knob mengikuti posisi jari; hanya nilai input yang dipotong deadzone.
        if (knob != null) knob.anchoredPosition = raw * safeRadius;
    }
}

/// <summary>Tombol aksi: merespons saat jari MENYENTUH (pointer down), bukan saat dilepas.</summary>
public class PressButton : MonoBehaviour, IPointerDownHandler, IPointerUpHandler
{
    public Action onDown;
    public Action onUp;
    public Graphic targetGraphic;

    Color baseColor;
    Vector3 baseScale;
    bool baseSet;

    void Awake()
    {
        baseScale = transform.localScale;
    }

    void EnsureBase()
    {
        if (!baseSet && targetGraphic != null)
        {
            baseColor = targetGraphic.color;
            baseSet = true;
        }
    }

    public void OnPointerDown(PointerEventData e)
    {
        EnsureBase();
        transform.localScale = baseScale * 0.9f;
        if (targetGraphic != null)
            targetGraphic.color = new Color(baseColor.r, baseColor.g, baseColor.b, Mathf.Min(1f, baseColor.a + 0.25f));
        if (onDown != null) onDown();
    }

    public void OnPointerUp(PointerEventData e)
    {
        EnsureBase();
        transform.localScale = baseScale;
        if (targetGraphic != null) targetGraphic.color = baseColor;
        if (onUp != null) onUp();
    }

    /// <summary>Set warna dasar baru (untuk tombol toggle seperti LARI).</summary>
    public void SetBaseColor(Color c)
    {
        baseColor = c;
        baseSet = true;
        if (targetGraphic != null) targetGraphic.color = c;
    }
}

/// <summary>Area transparan di sisi kanan layar untuk memutar kamera dengan geser jari.</summary>
public class TouchLookPad : MonoBehaviour, IPointerDownHandler, IDragHandler
{
    public OrbitCamera cam;

    public void OnPointerDown(PointerEventData e) { }

    public void OnDrag(PointerEventData e)
    {
        if (cam == null) return;
        float scale = 240f / Mathf.Max(1, Screen.height);
        cam.AddLook(e.delta * scale);
    }
}

/// <summary>Menyesuaikan panel UI dengan safe area (notch / punch hole) di Android.</summary>
public class SafeAreaFitter : MonoBehaviour
{
    Rect applied = new Rect(-1, -1, -1, -1);

    void Update()
    {
        Rect sa = Screen.safeArea;
        if (sa == applied) return;
        applied = sa;

        var rt = (RectTransform)transform;
        Vector2 min = sa.position;
        Vector2 max = sa.position + sa.size;
        min.x /= Screen.width; min.y /= Screen.height;
        max.x /= Screen.width; max.y /= Screen.height;
        rt.anchorMin = min;
        rt.anchorMax = max;
        rt.offsetMin = Vector2.zero;
        rt.offsetMax = Vector2.zero;
    }
}

/// <summary>Teks petunjuk yang memudar lalu hilang.</summary>
public class FadeOutHint : MonoBehaviour
{
    public float delay = 6f;
    public float fadeTime = 1.5f;
    CanvasGroup cg;
    float t;

    void Awake() { cg = gameObject.AddComponent<CanvasGroup>(); cg.blocksRaycasts = false; }

    void Update()
    {
        t += Time.deltaTime;
        if (t < delay) return;
        float a = 1f - (t - delay) / fadeTime;
        cg.alpha = Mathf.Clamp01(a);
        if (a <= 0f) gameObject.SetActive(false);
    }
}
