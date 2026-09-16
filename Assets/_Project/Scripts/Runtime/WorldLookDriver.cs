using UnityEngine;

namespace RPG.Runtime
{
    /* Setiap LateUpdate: paksa kamera + fog + bayangan ke keadaan
       yang PASTI menampilkan dunia di HP. DayNightCycle / QualityApplier
       tidak boleh menimpa ini di frame yang sama (execution order 1000). */
    [DisallowMultipleComponent]
    [DefaultExecutionOrder(1000)]
    public class WorldLookDriver : MonoBehaviour
    {
        void OnEnable() => WorldLook.ForceVisibleFrame();
        void LateUpdate() => WorldLook.ForceVisibleFrame();
    }
}
