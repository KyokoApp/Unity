using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;
using RPG.Core;

namespace RPG.Runtime
{
    /* ============================================================
       VIRTUAL JOYSTICK — stik uGUI untuk HUD Genshin.

       Stik "mengambang" ala Genshin mobile: alas muncul di titik
       jari menyentuh zona kiri, kenop mengikuti seret. Matematika
       sumbu SAMA dengan TouchJoystick (Locomotion.JoystickAxis —
       deadzone 0,14), jadi rasa geraknya identik, yang beda hanya
       tampilannya.

       Dibangun oleh GenshinHud; CharacterMotor otomatis memakai
       komponen ini kalau aktif, kalau tidak fallback ke
       TouchJoystick IMGUI.
       ============================================================ */
    [DisallowMultipleComponent]
    public class VirtualJoystick : MonoBehaviour,
        IPointerDownHandler, IDragHandler, IPointerUpHandler
    {
        [Header("Rujukan (diisi GenshinHud)")]
        public RectTransform Zone;
        public RectTransform Base;
        public RectTransform Knob;
        public CanvasScaler Scaler;

        [Header("Bentuk")]
        [Tooltip("Radius stik dalam piksel referensi (1920x1080).")]
        public float RadiusRef = 130f;

        public Locomotion.Axis Axis { get; private set; }
        public bool IsActive { get; private set; }

        int _pointerId = int.MinValue;
        Vector2 _origin;
        float _scale = 1f;

        void Awake()
        {
            if (Scaler != null && Scaler.scaleFactor > 0f) _scale = Scaler.scaleFactor;
            Axis = new Locomotion.Axis(0, 0);
            SetBaseVisible(false);
        }

        public void OnPointerDown(PointerEventData e)
        {
            if (IsActive) return;
            _pointerId = e.pointerId;
            _origin = e.position;
            IsActive = true;
            Axis = new Locomotion.Axis(0, 0);
            if (Scaler != null && Scaler.scaleFactor > 0f) _scale = Scaler.scaleFactor;
            // Alas muncul di titik sentuh (koordinat kanvas).
            if (Base != null && Zone != null)
            {
                Vector2 local;
                if (RectTransformUtility.ScreenPointToLocalPointInRectangle(
                        Zone, e.position, null, out local))
                    Base.anchoredPosition = local;
            }
            if (Knob != null) Knob.anchoredPosition = Vector2.zero;
            SetBaseVisible(true);
        }

        public void OnDrag(PointerEventData e)
        {
            if (!IsActive || e.pointerId != _pointerId) return;
            var delta = (e.position - _origin) / _scale;
            Axis = Locomotion.JoystickAxis(delta.x, delta.y, RadiusRef);
            if (Knob != null)
                Knob.anchoredPosition =
                    new Vector2((float)Axis.X, (float)Axis.Y) * RadiusRef;
        }

        public void OnPointerUp(PointerEventData e)
        {
            if (e.pointerId != _pointerId) return;
            _pointerId = int.MinValue;
            IsActive = false;
            Axis = new Locomotion.Axis(0, 0);
            SetBaseVisible(false);
        }

        void OnDisable()
        {
            _pointerId = int.MinValue;
            IsActive = false;
            Axis = new Locomotion.Axis(0, 0);
        }

        void SetBaseVisible(bool v)
        {
            if (Base != null) Base.gameObject.SetActive(v);
        }
    }
}
