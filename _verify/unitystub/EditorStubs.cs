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
        public static string[] FindAssets(string f,string[] folders)=>new string[0]; public static string[] FindAssets(string f)=>new string[0];
        public static string GUIDToAssetPath(string g)=>null;
        public static string AssetPathToGUID(string p)=>null;
        public static T LoadAssetAtPath<T>(string p) where T:Object => default;
        public static Object[] LoadAllAssetsAtPath(string p)=>null; public static void ImportAsset(string p){}
        public static void ImportAsset(string p, ImportAssetOptions o){} public static void StartAssetEditing(){} public static void StopAssetEditing(){}
        public static string GetAssetPath(Object o)=>null;
        public static void Refresh(){} public static void Refresh(ImportAssetOptions o){}
        public static bool DeleteAsset(string p)=>true; public static string MoveAsset(string a,string b)=>null;
        public static string GenerateUniqueAssetPath(string p)=>p;
        public static void SaveAssetIfDirty(Object o){} }
    [Flags] public enum ImportAssetOptions { Default=0, ForceUpdate=1 }
    public static class EditorUtility { public static void SetDirty(Object o){}
        public static bool DisplayDialog(string t,string m,string ok)=>true;
        public static bool DisplayDialog(string t,string m,string ok,string cancel)=>true;
        public static void CopySerializedManagedFieldsOnly(Object src,Object dst){}
        public static int EntityIdToObject(int id)=>0;
        public static Object InstanceIDToObject(int id)=>null;
    }
    public static class Selection { public static GameObject activeGameObject; }
    public class SceneView { public static void FrameLastActiveSceneView(){} public static void RepaintAll(){} }
    public static class PrefabUtility {
        public static Object InstantiatePrefab(Object o)=>null;
        public static GameObject SaveAsPrefabAsset(GameObject go,string path)=>null;
    }
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
    public static class EditorApplication {
        // EditorApplication.quitting -- dipakai AureliaCILogTap untuk menutup berkas log.
        public static event Action quitting; }
    public enum BuildTarget { NoTarget = -2, Android = 13, StandaloneWindows64 = 19 }
    public static class EditorUserBuildSettings {
        public static BuildTarget activeBuildTarget => BuildTarget.NoTarget;
        public static bool buildAppBundle;
        public static bool exportAsGoogleAndroidProject; }
    public static class EditorGraphicsSettings {
        public static void SetRenderPipelineGlobalSettingsAsset(UnityEngine.Rendering.RenderPipelineGlobalSettings s){}
    }
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
    public class SerializedObject {
        public SerializedObject(UnityEngine.Object o){}
        public SerializedProperty FindProperty(string n)=>new SerializedProperty();
        public bool ApplyModifiedPropertiesWithoutUndo()=>true;
        public bool ApplyModifiedProperties()=>true;
    }
    public class SerializedProperty {
        public int intValue; public float floatValue; public bool boolValue;
        public Object objectReferenceValue;
        public int arraySize;
        public SerializedProperty GetArrayElementAtIndex(int i)=>new SerializedProperty();
    }
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
namespace UnityEditor.Rendering { public static class EditorGraphicsSettings { public static void PopulateRenderPipelineGraphicsSettings(UnityEngine.Rendering.RenderPipelineGlobalSettings s){} } }

namespace UnityEditor
{
    // PlayerSettings.Android adalah satu-satunya jalan memasang konfigurasi
    // signing APK. Di Unity nyata properti ini getter/setter yang menyimpan ke
    // EditorPrefs per proyek; di sini cukup properti statis — yang mau dicek
    // adalah kode pemakainya (nullable + urutan tulis), bukan perilakunya.
    public sealed class PlayerSettings
    {
        public static class Android
        {
            public static bool useCustomKeystore { get; set; }
            public static string keystoreName { get; set; }
            public static string keystorePass { get; set; }
            public static string keyaliasName { get; set; }
            public static string keyaliasPass { get; set; }
        }
    }
}
