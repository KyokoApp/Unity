// Stub UnityEditor + URP, untuk memeriksa kompilasi Stage2SceneBuilder.cs &
// VrmCharacterImportSettings.cs di luar Unity. Sama seperti stub lain: ini
// menangkap salah ketik/tipe, BUKAN bukti kecocokan dengan API Unity asli.
using System;
using UnityEngine;
using Object = UnityEngine.Object;
namespace UnityEditor
{
    public static class AssetDatabase {
        public static bool IsValidFolder(string p)=>false; public static string CreateFolder(string p,string n)=>null;
        public static void CreateAsset(Object o,string p){} public static void SaveAssets(){}
        public static string[] FindAssets(string f,string[] folders)=>null; public static string GUIDToAssetPath(string g)=>null;
        public static T LoadAssetAtPath<T>(string p) where T:Object => default;
        public static Object[] LoadAllAssetsAtPath(string p)=>null; public static void ImportAsset(string p){}
        public static void ImportAsset(string p, ImportAssetOptions o){} public static void StartAssetEditing(){} public static void StopAssetEditing(){}
        public static string GetAssetPath(Object o)=>null;
        public static void Refresh(){} public static void Refresh(ImportAssetOptions o){}
        public static bool DeleteAsset(string p)=>true; public static string MoveAsset(string a,string b)=>null; }
    [Flags] public enum ImportAssetOptions { Default=0, ForceUpdate=1 }
    public static class EditorUtility { public static void SetDirty(Object o){}
        public static bool DisplayDialog(string t,string m,string ok)=>true;
        public static bool DisplayDialog(string t,string m,string ok,string cancel)=>true; }
    public static class Selection { public static GameObject activeGameObject; public static Object[] objects; }
    public class SceneView { public static void FrameLastActiveSceneView(){} public static void RepaintAll(){} }
    public static class PrefabUtility { public static Object InstantiatePrefab(Object o)=>null; }
    public class AssetPostprocessor { public string assetPath; public AssetImporter assetImporter=>null; }
    public class AssetImporter : Object {}
    public class TextureImporter : AssetImporter {
        public TextureImporterType textureType; public bool sRGBTexture; public bool mipmapEnabled;
        public bool alphaIsTransparency; public bool streamingMipmaps; public TextureImporterNPOTScale npotScale;
        public FilterMode filterMode; public TextureWrapMode wrapMode;
        public void SetPlatformTextureSettings(TextureImporterPlatformSettings s){} }
    public class TextureImporterPlatformSettings { public string name; public bool overridden; public TextureImporterFormat format;
        public int maxTextureSize; public TextureResizeAlgorithm resizeAlgorithm; }
    public enum TextureImporterType { Default, NormalMap, GUI, Sprite, Cursor, Cookie, Lightmap, SingleChannel }
    public enum TextureImporterNPOTScale { None, ToNearest, ToLarger, ToSmaller }
    public enum TextureResizeAlgorithm { Mitchell, Bilinear }
    public enum TextureImporterFormat { Automatic=-1, RGBA32=4, ASTC_4x4=48, ASTC_6x6=50, ASTC_8x8=52 }
    public static class Undo { public static void RegisterCreatedObjectUndo(Object o,string n){}
        public static void RecordObject(Object o,string n){} public static void SetTransformParent(UnityEngine.Transform t,UnityEngine.Transform p,string n){} }
    public static class EditorApplication {}
}
namespace UnityEditor.Build
{
    public interface IPreprocessBuildWithReport { int callbackOrder { get; }
        void OnPreprocessBuild(UnityEditor.Build.Reporting.BuildReport report); }
    public class BuildFailedException : System.Exception { public BuildFailedException(string m) : base(m) {} }
    namespace Reporting { public class BuildReport {} }
}
namespace UnityEditor
{
    public class EditorBuildSettingsScene {
        public string path; public bool enabled;
        public EditorBuildSettingsScene(){}
        public EditorBuildSettingsScene(string p,bool e){path=p;enabled=e;} }
    public static class EditorBuildSettings {
        public static EditorBuildSettingsScene[] scenes { get; set; } }
    public class SerializedObject { public SerializedObject(UnityEngine.Object o){}
        public SerializedProperty FindProperty(string n)=>null;
        public bool ApplyModifiedPropertiesWithoutUndo()=>true; }
    public class SerializedProperty { public int intValue; public float floatValue; public bool boolValue; }
}
namespace UnityEditor.SceneManagement
{
    public static class EditorSceneManager {
        public static UnityEngine.SceneManagement.Scene NewScene(NewSceneSetup s, NewSceneMode m)=>default;
        public static bool SaveScene(UnityEngine.SceneManagement.Scene sc, string path)=>true;
        public static void MarkSceneDirty(UnityEngine.SceneManagement.Scene sc){} }
    public enum NewSceneSetup { EmptyScene, DefaultGameObjects }
    public enum NewSceneMode { Single, Additive }
}
namespace UnityEngine.SceneManagement
{
    public struct Scene { public string name; public string path; public bool isLoaded; public int buildIndex; }
    public static class SceneManager {
        public static Scene GetActiveScene()=>default;
        public static Scene GetSceneAt(int i)=>default;
        public static int sceneCount=>0;
        public static Scene CreateScene(string n)=>default; }
}
namespace UnityEngine.Rendering
{
    public static class GraphicsSettings { public static RenderPipelineAsset defaultRenderPipeline; }
    public class RenderPipelineAsset : ScriptableObject {}
    public class ScriptableRendererData : ScriptableObject {}
}
namespace UnityEngine.Rendering.Universal
{
    public class UniversalRendererData : UnityEngine.Rendering.ScriptableRendererData {}
    public class UniversalRenderPipelineAsset : UnityEngine.Rendering.RenderPipelineAsset {
        public static UniversalRenderPipelineAsset Create(UnityEngine.Rendering.ScriptableRendererData r)=>null;
        public float renderScale; public float shadowDistance; public int shadowCascadeCount; }
}
namespace UnityEngine { public static class QualitySettings { public static UnityEngine.Rendering.RenderPipelineAsset renderPipeline; } }
