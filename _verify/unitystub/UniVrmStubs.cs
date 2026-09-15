// ============================================================
// UniVrmStubs.cs
//
// Tiruan tipe UniVRM/UniGLTF yang dipakai VrmPrefabBuilder.cs, supaya
// harness ini tetap bisa mengompilasi Assets/_Project/Scripts/Editor/*.cs
// tanpa Unity dan tanpa paket UniVRM.
//
// PENTING -- SEMUA tanda tangan di file ini DISALIN dari sumber UniVRM
// tag v0.131.2 (versi yang dikunci di Packages/manifest.json), bukan
// dikarang:
//
//   Packages/UniGLTF/Runtime/UniGLTF/IO/UnityPath.cs
//   Packages/UniGLTF/Runtime/UniGLTF/IO/SubAssetKey.cs
//   Packages/UniGLTF/Runtime/UniGLTF/IO/ImporterContext.cs
//   Packages/UniGLTF/Runtime/UniGLTF/IO/ImporterContextExtensions.cs
//   Packages/UniGLTF/Runtime/UniGLTF/IO/ImporterContextSettings.cs
//   Packages/UniGLTF/Runtime/UniGLTF/IO/TextureIO/Import/TextureFactory.cs
//   Packages/UniGLTF/Editor/UniGLTF/ScriptedImporter/TextureExtractor.cs
//   Packages/UniGLTF/Editor/UniGLTF/IO/Texture/Importer/TextureImporterConfigurator.cs
//   Packages/VRM/Runtime/IO/VRMData.cs
//   Packages/VRM/Runtime/IO/VRMImporterContext.cs
//   Packages/VRM/Runtime/IO/VRMException.cs
//   Packages/VRM/Editor/Format/VRMEditorImporterContext.cs
//   Packages/VRM/Editor/Format/vrmAssetPostprocessor.cs
//
// Kalau versi UniVRM dinaikkan, file ini WAJIB diperiksa ulang terhadap
// tag yang baru. Stub yang menyimpang dari API asli lebih berbahaya
// daripada tidak ada stub sama sekali: harness jadi hijau sementara Unity
// merah. Itu sudah pernah terjadi di project ini
// (EditorUtility.GetRuntimeMemorySizeLong -- API karangan, build CI gagal
// dengan CS0117).
//
// Badan metode sengaja kosong: yang diperiksa harness adalah kompilasi
// (nama, tipe, arity), bukan perilaku UniVRM.
// ============================================================
using System;
using System.Collections.Generic;
using UnityEngine;

namespace UniGLTF
{
    public class glTF
    {
        public object extensions;
    }

    public class GltfData : IDisposable
    {
        public glTF GLTF { get; }
        public void Dispose() { }
    }

    public class GlbFileParser
    {
        public GlbFileParser(string path) { }
        public GltfData Parse() => null;
    }

    public struct SubAssetKey
    {
        public SubAssetKey(Texture obj) { }
        public SubAssetKey(Material obj) { }
        public SubAssetKey(Type type, string name) { }
    }

    public enum Axes { X, Y, Z }

    public enum ImportedTexturesAccessibility { Auto }

    public class ImporterContextSettings
    {
        public ImporterContextSettings(
            bool loadAnimation = true,
            Axes invertAxis = Axes.Z,
            ImportedTexturesAccessibility importedTexturesAccessibility = ImportedTexturesAccessibility.Auto) { }
    }

    public struct TextureDescriptor
    {
        public SubAssetKey SubAssetKey;
    }

    public struct TextureDescriptorCollection { }

    public interface ITextureDescriptorGenerator
    {
        TextureDescriptorCollection Get();
    }

    public static class TextureDescriptorCollectionExtensions
    {
        public static IEnumerable<TextureDescriptor> GetEnumerable(this TextureDescriptorCollection self) => null;
    }

    public class TextureFactory
    {
        public IReadOnlyDictionary<SubAssetKey, Texture> ExternalTextures => null;
        public IReadOnlyDictionary<SubAssetKey, Texture> ConvertedTextures => null;
    }

    public class RuntimeGltfInstance
    {
        public GameObject Root => null;
        public void ShowMeshes() { }
        public void EnableUpdateWhenOffscreen() { }
    }

    public interface ITextureDeserializer { }

    public interface IMaterialDescriptorGenerator { }

    public class ImporterContext : IDisposable
    {
        public GltfData Data => null;
        public ITextureDescriptorGenerator TextureDescriptorGenerator { get; protected set; }
        public TextureFactory TextureFactory => null;

        public ImporterContext(GltfData data) { }
        public void Dispose() { }
    }

    public static class ImporterContextExtensions
    {
        public static RuntimeGltfInstance Load(this ImporterContext ctx) => null;
    }

    public static class TextureImporterConfigurator
    {
        public static void Configure(TextureDescriptor texDesc,
                                     IReadOnlyDictionary<SubAssetKey, Texture> externalMap) { }
    }

    public class UnityPath
    {
        public string FullPath => null;
        public string Value => null;
        public string FileNameWithoutExtension => null;
        public bool IsFileExists => false;
        public bool IsUnderWritableFolder => false;
        public bool IsNull => false;
        public UnityPath Parent => null;

        public static UnityPath FromUnityPath(string unityPath) => null;
        public static UnityPath FromFullpath(string fullPath) => null;
        public static UnityPath FromAsset(UnityEngine.Object asset) => null;

        public UnityPath Child(string name) => null;
        public T LoadAsset<T>() where T : UnityEngine.Object => default;
        public void ImportAsset() { }
        public void EnsureFolder() { }
        public void CreateAsset(UnityEngine.Object o) { }
    }
}

namespace VRM
{
    using UniGLTF;

    public class NotVrm0Exception : Exception { }

    public class VRMData
    {
        public GltfData Data => null;
        public VRMData(GltfData data) { }
    }

    public interface IVrm0XSpringBoneRuntime { }

    public class VRMImporterContext : ImporterContext
    {
        // Urutan & nama parameter harus persis: VrmPrefabBuilder memakai
        // named argument (externalObjectMap:, settings:).
        public VRMImporterContext(
            VRMData data,
            IReadOnlyDictionary<SubAssetKey, UnityEngine.Object> externalObjectMap = null,
            ITextureDeserializer textureDeserializer = null,
            IMaterialDescriptorGenerator materialGenerator = null,
            ImporterContextSettings settings = null,
            IVrm0XSpringBoneRuntime springboneRuntime = null) : base(null) { }
    }

    public class VRMEditorImporterContext
    {
        public VRMEditorImporterContext(VRMImporterContext context, UnityPath prefabPath) { }

        public ITextureDescriptorGenerator TextureDescriptorGenerator => null;

        public void ConvertAndExtractImages(Action<IEnumerable<UnityPath>> onTextureReloaded) { }
        public void SaveAsAsset(RuntimeGltfInstance loaded) { }
    }
}
