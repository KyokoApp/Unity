// Stub UnityEngine SEMATA-MATA untuk memeriksa kompilasi skrip Runtime
// di luar Unity. Ini BUKAN bukti API-nya cocok dengan Unity asli --
// hanya menangkap salah ketik, signature salah, using hilang, dan
// kesalahan tipe. Lihat catatan di TAHAP-2.md.
using System;
using System.Collections.Generic;
namespace UnityEngine
{
    public struct Vector2 { public float x,y; public Vector2(float x,float y){this.x=x;this.y=y;}
        public float magnitude=>0f; public Vector2 normalized=>this; public static Vector2 zero=>default;
        public static Vector2 operator-(Vector2 a,Vector2 b)=>default; public static Vector2 operator+(Vector2 a,Vector2 b)=>default;
        public static Vector2 operator*(Vector2 a,float k)=>default; public static Vector2 operator*(float k,Vector2 a)=>default;
        public static implicit operator Vector3(Vector2 v)=>default; }
    public struct Vector3 { public float x,y,z; public Vector3(float x,float y,float z){this.x=x;this.y=y;this.z=z;}
        public float magnitude=>0f; public Vector3 normalized=>this; public static Vector3 zero=>default; public static Vector3 up=>default;
        public static Vector3 operator*(Vector3 a,float k)=>default; public static Vector3 operator*(float k,Vector3 a)=>default;
        public static Vector3 operator/(Vector3 a,float k)=>default; public static Vector3 operator+(Vector3 a,Vector3 b)=>default;
        public static Vector3 operator-(Vector3 a,Vector3 b)=>default;
        public static implicit operator Vector2(Vector3 v)=>default; }
    public struct Quaternion { public float x,y,z,w; public static Quaternion identity=>default;
        public static Quaternion Euler(float x,float y,float z)=>default; public static Quaternion Euler(Vector3 v)=>default;
        public static Quaternion LookRotation(Vector3 f,Vector3 u)=>default; public static Quaternion Slerp(Quaternion a,Quaternion b,float t)=>default;
        public static Quaternion operator*(Quaternion a,Quaternion b)=>default; }
    public struct Color { public float r,g,b,a; public Color(float r,float g,float b){this.r=r;this.g=g;this.b=b;}
        public Color(float r,float g,float b,float a){this.r=r;this.g=g;this.b=b;this.a=a;}
        public static Color white=>default; public static Color cyan=>default; public static Color yellow=>default; public static Color green=>default; }
    public struct Color32 { public byte r,g,b,a; public Color32(byte r,byte g,byte b,byte a){this.r=r;this.g=g;this.b=b;this.a=a;} }
    public struct Rect { public float x,y,width,height; public Rect(float x,float y,float w,float h){this.x=x;this.y=y;this.width=w;this.height=h;}
        public float xMax=>0f; public float yMax=>0f; public bool Contains(Vector2 p)=>false; }
    public static class Mathf { public const float Rad2Deg=57.29578f; public const float Deg2Rad=0.01745329f;
        public static float Cos(float a)=>0f; public static float Sin(float a)=>0f; public static float Sqrt(float a)=>0f;
        public static float Abs(float a)=>a; public static float Clamp(float v,float a,float b)=>v;
        public static float Clamp01(float v)=>v; public static float Max(float a,float b)=>a; public static float Min(float a,float b)=>a;
        public static float DeltaAngle(float a,float b)=>0f; public static int RoundToInt(float v)=>0; public static float Exp(float v)=>0f;
        public static float Atan2(float y,float x)=>0f;
        public static int Max(int a,int b)=>a; public static int Min(int a,int b)=>a;
        public static float Round(float v)=>v;
        /* Unity punya overload terpisah untuk int dan float. Tanpa yang int,
           Mathf.Clamp(x, 8, 64) di sini mengembalikan float dan menyembunyikan
           perbedaan tipe yang Unity asli tolak. */
        public static int Clamp(int v,int a,int b)=>v; }
    public class Object { public string name; public static void Destroy(Object o){} public static void DestroyImmediate(Object o){}
        public static T FindFirstObjectByType<T>() where T:Object => default; }
    public class Component : Object { public Transform transform=>null; public GameObject gameObject=>null;
        public T GetComponent<T>()=>default; public T GetComponentInChildren<T>()=>default; public T[] GetComponentsInChildren<T>(bool x)=>null; }
    public class Behaviour : Component { public bool enabled; }
    public class Transform : Component { public Vector3 position; public Vector3 localPosition; public Quaternion rotation; public Quaternion localRotation;
        public Vector3 eulerAngles; public Vector3 localScale; public Transform parent=>null; public int childCount=>0;
        public Transform GetChild(int i)=>null;
        public void SetParent(Transform p){} public void SetParent(Transform p,bool worldPositionStays){} }
    public enum PrimitiveType { Sphere, Capsule, Cylinder, Cube, Plane, Quad }
    public class GameObject : Object { public GameObject(){} public GameObject(string n){} public Transform transform=>null;
        public string tag; public int layer; public T AddComponent<T>() where T:Component => default; public T GetComponent<T>()=>default;
        public T GetComponentInChildren<T>()=>default; public T[] GetComponentsInChildren<T>(bool inc)=>null;
        public static GameObject CreatePrimitive(PrimitiveType t)=>null; }
    public class Renderer : Component { public Material sharedMaterial; }
    public class MeshRenderer : Renderer { public bool receiveShadows; public UnityEngine.Rendering.ShadowCastingMode shadowCastingMode; }
    public class SkinnedMeshRenderer : Renderer { public Transform[] bones; public Mesh sharedMesh; }
    public class Mesh : Object { public int vertexCount=>0; public int subMeshCount=>0; public int blendShapeCount=>0;
        public uint GetIndexCount(int s)=>0;
        /* Tipe properti ini harus sama dengan Unity asli, karena harness ini
           justru dipakai untuk menangkap salah tipe (mis. Color32[] masuk ke
           Mesh.colors yang bertipe Color[]). */
        public Vector3[] vertices; public Vector3[] normals; public Color[] colors; public Color32[] colors32;
        public Vector2[] uv; public int[] triangles; public Bounds bounds;
        public UnityEngine.Rendering.IndexFormat indexFormat;
        public void Clear(){} public void Clear(bool keepVertexLayout){}
        public void RecalculateBounds(){} public void RecalculateNormals(){}
        public void UploadMeshData(bool markNoLongerReadable){} public void MarkDynamic(){} }
    public struct Bounds { public Vector3 center; public Vector3 size; public Bounds(Vector3 c,Vector3 s){center=c;size=s;} }
    public class MeshFilter : Component { public Mesh sharedMesh; public Mesh mesh; }
    public struct LayerMask { public int value;
        public static int NameToLayer(string n)=>0; public static int GetMask(params string[] n)=>0; }
    public class Collider : Component {}
    public class AudioListener : Behaviour {}
    public class MonoBehaviour : Behaviour {}
    public class ScriptableObject : Object { public static T CreateInstance<T>() where T:ScriptableObject => default; }
    public static class Debug { public static void Log(object m){} public static void LogError(object m){} public static void LogWarning(object m){} }
    public static class Time { public static float deltaTime=>0f; public static float unscaledDeltaTime=>0f;
        public static float time=>0f; public static float realtimeSinceStartup=>0f; public static int frameCount=>0; public static float timeScale=1f; }
    public enum ScreenOrientation { Portrait, PortraitUpsideDown, LandscapeLeft, LandscapeRight, AutoRotation }
    public static class Screen { public static int width=>0; public static int height=>0; public static ScreenOrientation orientation; }
    public static class Application { public static bool isPlaying=>false; public static bool isBatchMode=>false;
        public static bool isEditor=>false; public static string platform=>null; public static void Quit(){} }
    public static class PlayerPrefs { public static bool HasKey(string k)=>false; public static float GetFloat(string k)=>0f;
        public static int GetInt(string k)=>0; public static string GetString(string k)=>null; public static void SetFloat(string k,float v){}
        public static void SetInt(string k,int v){} public static void SetString(string k,string v){} public static void DeleteKey(string k){}
        public static void Save(){} }
    public static class Input { public static float GetAxisRaw(string n)=>0f; public static bool GetKey(KeyCode c)=>false;
        public static bool GetKeyDown(KeyCode c)=>false; public static bool GetMouseButton(int b)=>false;
        public static bool GetMouseButtonDown(int b)=>false; public static Vector3 mousePosition=>default; public static int touchCount=>0;
        public static Touch GetTouch(int i)=>default; }
    public enum KeyCode { Space, LeftShift, RightShift, F1, F2, Escape }
    public enum TouchPhase { Began, Moved, Stationary, Ended, Canceled }
    public struct Touch { public int fingerId; public Vector2 position; public TouchPhase phase; }
    public class Camera : Behaviour { public CameraClearFlags clearFlags; public float nearClipPlane, farClipPlane, fieldOfView;
        public Color backgroundColor; public static Camera main=>null; }
    public enum CameraClearFlags { Skybox, SolidColor, Depth, Nothing }
    public class Light : Behaviour { public LightType type; public Color color; public float intensity; public LightShadows shadows; }
    public enum LightType { Directional, Point, Spot, Area } public enum LightShadows { None, Hard, Soft }
    public class Animator : Behaviour { public bool isHuman=>false; public Transform GetBoneTransform(HumanBodyBones b)=>null; }
    public enum HumanBodyBones { Hips,Spine,Chest,Neck,Head,LeftUpperLeg,LeftLowerLeg,LeftFoot,LeftToes,
        RightUpperLeg,RightLowerLeg,RightFoot,RightToes,LeftUpperArm,LeftLowerArm,LeftHand,
        RightUpperArm,RightLowerArm,RightHand,LastBone }
    public class Texture : Object { public int width=>0; public int height=>0; }
    public class Texture2D : Texture { public Texture2D(int w,int h,TextureFormat f,bool mip){}
        public TextureWrapMode wrapMode; public void SetPixels32(Color32[] c){} public void Apply(bool a,bool b){} }
    public enum TextureFormat { RGBA32 } public enum TextureWrapMode { Repeat, Clamp } public enum FilterMode { Point, Bilinear, Trilinear }
    public class Material : Object { public Material(Shader s){} public bool HasProperty(string n)=>false; public void SetColor(string n,Color c){} }
    public class Shader : Object { public static Shader Find(string n)=>null; }
    namespace Profiling {
        /* Harus sama dengan Unity asli. Dulu stub menaruh
           GetRuntimeMemorySizeLong di UnityEditor.EditorUtility (tidak ada di
           Unity), dan persis itulah yang membuat build CI pertama gagal. */
        public static class Profiler {
            public static long GetRuntimeMemorySizeLong(Object o)=>0;
            public static long GetTotalAllocatedMemoryLong()=>0;
            public static long GetMonoUsedSizeLong()=>0;
            public static long GetTotalReservedMemoryLong()=>0; } }
    public static class Gizmos { public static Color color; public static void DrawWireSphere(Vector3 c,float r){} public static void DrawLine(Vector3 a,Vector3 b){} }
    public static class RenderSettings { public static UnityEngine.Rendering.AmbientMode ambientMode;
        public static bool fog; public static FogMode fogMode; public static float fogStartDistance, fogEndDistance, fogDensity;
        public static Color fogColor; public static Color ambientLight; }
    public enum FogMode { Linear, Exponential, ExponentialSquared }
    public class GUIStyle { public GUIStyle(){} public GUIStyle(GUIStyle o){} public TextAnchor alignment; public int fontSize; public GUIStyleState normal=new GUIStyleState(); }
    public class GUIStyleState { public Color textColor; }
    public enum TextAnchor { MiddleCenter }
    public static class GUI { public static Color color; public static GUIStyleSkin skin=>new GUIStyleSkin();
        public static void DrawTexture(Rect r,Texture t){} public static void Label(Rect r,string t,GUIStyle s){} }
    public class GUIStyleSkin { public GUIStyle label=>new GUIStyle(); }
    namespace EventSystems { public class EventSystem : Behaviour { public static EventSystem current=>null;
        public bool IsPointerOverGameObject()=>false; public bool IsPointerOverGameObject(int id)=>false; }
        public class StandaloneInputModule : Behaviour {} }
    namespace Rendering {
        public enum AmbientMode { Skybox, Trilight, Flat, Custom }
        public enum ShadowCastingMode { Off, On, TwoSided, ShadowsOnly }
        public enum IndexFormat { UInt16, UInt32 } }
}
namespace UnityEngine { public class SceneViewDummy {} }
