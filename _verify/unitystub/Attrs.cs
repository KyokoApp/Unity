// Stub atribut Unity & UnityEditor untuk pemeriksaan kompilasi di luar engine.
using System;
namespace UnityEngine
{
    [AttributeUsage(AttributeTargets.Field)] public class HeaderAttribute : Attribute { public HeaderAttribute(string h){} }
    [AttributeUsage(AttributeTargets.All)]     public class TooltipAttribute : Attribute { public TooltipAttribute(string t){} }
    [AttributeUsage(AttributeTargets.Field)]   public class RangeAttribute : Attribute { public RangeAttribute(float a,float b){} }
    [AttributeUsage(AttributeTargets.Field)]   public class SpaceAttribute : Attribute { public SpaceAttribute(){} public SpaceAttribute(float h){} }
    [AttributeUsage(AttributeTargets.Field)]   public class SerializeField : Attribute {}
    [AttributeUsage(AttributeTargets.Field)]   public class HideInInspector : Attribute {}
    [AttributeUsage(AttributeTargets.Class)]   public class DisallowMultipleComponent : Attribute {}
    [AttributeUsage(AttributeTargets.Class)]   public class DefaultExecutionOrder : Attribute { public DefaultExecutionOrder(int order){} }
    [AttributeUsage(AttributeTargets.Class)]   public class RequireComponent : Attribute { public RequireComponent(Type t){} }
    [AttributeUsage(AttributeTargets.Class)]   public class ExecuteAlways : Attribute {}
    [AttributeUsage(AttributeTargets.Method)]  public class ContextMenu : Attribute { public ContextMenu(string n){} }
    public enum RuntimeInitializeLoadType { AfterSceneLoad, BeforeSceneLoad, AfterAssembliesLoaded, BeforeSplashScreen, SubsystemRegistration }
    [AttributeUsage(AttributeTargets.Method)] public class RuntimeInitializeOnLoadMethodAttribute : Attribute { public RuntimeInitializeOnLoadMethodAttribute(){} public RuntimeInitializeOnLoadMethodAttribute(RuntimeInitializeLoadType t){} }
}
namespace UnityEditor
{
    [AttributeUsage(AttributeTargets.Method)] public class MenuItem : Attribute { public MenuItem(string p){} public MenuItem(string p,bool v){} public MenuItem(string p,bool v,int pr){} }
    [AttributeUsage(AttributeTargets.Method)] public class InitializeOnLoadMethod : Attribute {}
}
