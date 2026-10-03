using UnityEngine;
using UnityEngine.EventSystems;

/// <summary>Analog stick virtual: zona sentuh tetap di kiri-bawah, knob mengikuti jari.</summary>
public class VirtualJoystick : MonoBehaviour, IPointerDownHandler, IDragHandler, IPointerUpHandler
{
    public RectTransform knob;
    public float radius = 120f;
    public Vector2 Value { get; private set; }
    public bool IsHeld { get; private set; }

    RectTransform rt;

    void Awake() { rt = (RectTransform)transform; }

    public void OnPointerDown(PointerEventData e)
    {
        IsHeld = true;
        Handle(e);
    }
    public void OnDrag(PointerEventData e) { Handle(e); }

    public void OnPointerUp(PointerEventData e)
    {
        IsHeld = false;
        Value = Vector2.zero;
        if (knob != null) knob.anchoredPosition = Vector2.zero;
    }

    void OnDisable()
    {
        IsHeld = false;
        Value = Vector2.zero;
        if (knob != null) knob.anchoredPosition = Vector2.zero;
    }

    void Handle(PointerEventData e)
    {
        Vector2 lp;
        if (!RectTransformUtility.ScreenPointToLocalPointInRectangle(rt, e.position, e.pressEventCamera, out lp))
            return;
        Value = Vector2.ClampMagnitude(lp / radius, 1f);
        if (knob != null) knob.anchoredPosition = Value * radius;
    }
}

/// <summary>Area transparan di sisi kanan layar untuk memutar kamera dengan geser jari.</summary>
public class TouchLookPad : MonoBehaviour, IPointerDownHandler, IDragHandler
{
    public FirstPersonRoomController player;

    public void OnPointerDown(PointerEventData e) { }

    public void OnDrag(PointerEventData e)
    {
        if (player != null) player.AddLookPixels(e.delta);
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
