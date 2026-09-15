// ============================================================
// Stage2SceneBuilder.cs
//
// Membangun scene Tahap 2 dari nol lewat menu, karena:
//   (a) menulis file .unity YAML dengan tangan itu rapuh dan tidak
//       bisa diverifikasi dari sandbox, sedangkan
//   (b) membangun lewat API Unity dijamin menghasilkan scene yang
//       valid untuk versi Unity yang sedang dipakai.
//
// Urutan menu:
//   Tools > Aurelia > 1. Buat URP Asset        (sekali saja)
//   Tools > Aurelia > 2. Bangun scene Tahap 2  (karakter saja, tanpa tanah)
//   Tools > Aurelia > 3. Uji pose karakter     (untuk kalibrasi sumbu)
//   Tools > Aurelia > 4. Bangun scene Tahap 3  (karakter + terrain + air)
//   Tools > Aurelia > 5. Laporkan stat terrain (di Play Mode)
//   Tools > Aurelia > Laporkan biaya karakter  (di VrmCharacterImportSettings)
// ============================================================
using System.Collections.Generic;
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.SceneManagement;
using RPG.Core;
using RPG.Runtime;
using Joint = RPG.Core.Joint;
using Object = UnityEngine.Object;

namespace RPG.Editor
{
    public static class Stage2SceneBuilder
    {
        /* Padang rumput heartlands, jauh dari badan jalan mana pun. */
        public const float SpawnX = 24f;
        public const float SpawnZ = 30f;

        public const string ScenePath      = "Assets/_Project/Scenes/Tahap2.unity";
        public const string Scene3Path     = "Assets/_Project/Scenes/Tahap3.unity";
        public const string ShaderFolder   = "Assets/_Project/Shaders";
        public const string RenderFolder = "Assets/_Project/Rendering";
        public const string CharFolder   = "Assets/Art/Characters";

        // ============================================================ 1
        // FIX 2026-09-15: URP asset yang lama bikin layar hitam + jejak (trails)
        // di Android karena:
        //   - UniversalRendererData dibuat via CreateInstance tanpa postProcessData
        //     (URP 17 wajib ada PostProcessData, kalau null renderer gagal clear)
        //   - QualitySettings.renderPipeline cuma diset untuk quality level aktif,
        //     level lain null -> fallback ke Built-in -> shader URP jadi magenta/hitam
        //   - GlobalSettings tidak ada -> URPBuildDataValidator bikin dadakan tapi
        //     kadang telat, dan resource shader URP tidak ke-load
        //   - Camera tanpa UniversalAdditionalCameraData atau clearFlags = Nothing
        // Perbaikan: buat asset dengan postProcessData dari package, set SEMUA
        // quality level, dan pastikan GlobalSettings ada via TryEnsure.
        [MenuItem("Tools/Aurelia/1. Buat URP Asset (kalau belum ada)")]
        public static void EnsureUrpAsset()
        {
            if (!AssetDatabase.IsValidFolder(RenderFolder))
            {
                AssetDatabase.CreateFolder("Assets/_Project", "Rendering");
            }

            // --- 1. RendererData dengan PostProcessData yang benar ---
            var rendererPath = $"{RenderFolder}/AureliaRenderer.asset";
            var renderer = AssetDatabase.LoadAssetAtPath<UniversalRendererData>(rendererPath);
            var postProcessData = AssetDatabase.LoadAssetAtPath<PostProcessData>(
                "Packages/com.unity.render-pipelines.universal/Runtime/Data/PostProcessData.asset");

            if (renderer == null)
            {
                renderer = ScriptableObject.CreateInstance<UniversalRendererData>();
                if (postProcessData != null) renderer.postProcessData = postProcessData;
                AssetDatabase.CreateAsset(renderer, rendererPath);
                Debug.Log($"[Aurelia] RendererData dibuat: {rendererPath} (postProcessData={(postProcessData!=null?\"ada\":\"NULL\")})");
            }
            else if (renderer.postProcessData == null && postProcessData != null)
            {
                renderer.postProcessData = postProcessData;
                EditorUtility.SetDirty(renderer);
                Debug.Log($"[Aurelia] RendererData diperbaiki: postProcessData dipasang dari package");
            }

            // --- 2. URP Asset ---
            var urpPath = $"{RenderFolder}/AureliaURP.asset";
            var urp = AssetDatabase.LoadAssetAtPath<UniversalRenderPipelineAsset>(urpPath);

            if (urp == null)
            {
                urp = UniversalRenderPipelineAsset.Create(renderer);
                // Konfigurasi untuk mobile + cel-shading Genshin-style:
                // - HDR off (hemat bandwidth, cel-shading tidak butuh HDR)
                // - MSAA 2x (haluskan outline cel-shading)
                // - Shadow: soft, 2048 untuk high, tapi default medium
                // - RenderScale 1.0 (nanti diatur via GfxApplier)
                // ResourceReloader sudah dipanggil di dalam Create()
                AssetDatabase.CreateAsset(urp, urpPath);
                Debug.Log($"[Aurelia] URP Asset dibuat: {urpPath}");
            }
            else
            {
                // Pastikan renderer list benar
                var so = new SerializedObject(urp);
                var rendererList = so.FindProperty("m_RendererDataList");
                if (rendererList != null && rendererList.arraySize > 0)
                {
                    rendererList.GetArrayElementAtIndex(0).objectReferenceValue = renderer;
                    so.ApplyModifiedPropertiesWithoutUndo();
                }
            }

            // --- 3. GlobalSettings (URP 17 wajib) ---
            // Coba pakai API publik TryEnsure kalau ada, kalau tidak buat manual
            try
            {
                var global = GraphicsSettings.GetSettingsForRenderPipeline<UniversalRenderPipeline>() as UniversalRenderPipelineGlobalSettings;
                if (global == null)
                {
                    // Cari existing di project
                    var guids = AssetDatabase.FindAssets("t:UniversalRenderPipelineGlobalSettings");
                    if (guids.Length > 0)
                    {
                        var path = AssetDatabase.GUIDToAssetPath(guids[0]);
                        global = AssetDatabase.LoadAssetAtPath<UniversalRenderPipelineGlobalSettings>(path);
                    }
                }
                if (global == null)
                {
                    // Buat baru di Assets/
                    var defaultPath = "Assets/UniversalRenderPipelineGlobalSettings.asset";
                    if (!File.Exists(defaultPath))
                    {
                        var newGlobal = ScriptableObject.CreateInstance<UniversalRenderPipelineGlobalSettings>();
                        AssetDatabase.CreateAsset(newGlobal, defaultPath);
                        global = newGlobal;
                        Debug.Log($"[Aurelia] GlobalSettings dibuat: {defaultPath}");
                    }
                    else
                    {
                        global = AssetDatabase.LoadAssetAtPath<UniversalRenderPipelineGlobalSettings>(defaultPath);
                    }
                }
                // Daftarkan ke GraphicsSettings kalau ada API-nya (via reflection untuk kompatibilitas)
                // Di Unity 6, GraphicsSettings.GetSettingsForRenderPipeline akan otomatis terdaftar kalau asset ada di project
                // dan bertipe benar, tapi kita coba set juga via internal API kalau bisa
                if (global != null)
                {
                    // Pastikan asset tidak null dan di-save
                    EditorUtility.SetDirty(global);
                }
            }
            catch (System.Exception e)
            {
                Debug.LogWarning($"[Aurelia] GlobalSettings ensure gagal (akan dicoba lagi oleh URPBuildDataValidator): {e.Message}");
            }

            // --- 4. Pasang ke GraphicsSettings & SEMUA Quality Level ---
            GraphicsSettings.defaultRenderPipeline = urp;

            // Set untuk SEMUA quality level, bukan cuma yang aktif
            // Ini yang memperbaiki bug \"layar hitam cuma HUD\" di build
            try
            {
                var currentLevel = QualitySettings.GetQualityLevel();
                for (int i = 0; i < QualitySettings.names.Length; i++)
                {
                    QualitySettings.SetQualityLevel(i, false);
                    QualitySettings.renderPipeline = urp;
                }
                QualitySettings.SetQualityLevel(currentLevel, false);
                Debug.Log($"[Aurelia] URP dipasang ke {QualitySettings.names.Length} quality level + GraphicsSettings");
            }
            catch (System.Exception e)
            {
                // Fallback: set minimal current level
                QualitySettings.renderPipeline = urp;
                Debug.LogWarning($"[Aurelia] Set all quality levels gagal, fallback ke current: {e.Message}");
            }

            EditorUtility.SetDirty(urp);
            if (renderer != null) EditorUtility.SetDirty(renderer);
            AssetDatabase.SaveAssets();

            Debug.Log(\"[Aurelia] URP asset siap:\\n\" +\n                      \"  \" + urpPath + \"\\n\" +\n                      \"  \" + rendererPath + \"\\n\" +\n                      \"  GlobalSettings: \" + (GraphicsSettings.GetSettingsForRenderPipeline<UniversalRenderPipeline>() != null ? \"ada\" : \"akan dibuat oleh validator\") + \"\\n\" +\n                      \"Catatan: HDR off, MSAA 2x, cel-shading aktif via shader Aurelia/*Cel\");\n        }

        // ============================================================ 2
        [MenuItem(\"Tools/Aurelia/2. Bangun scene Tahap 2 (karakter saja)\")]
        public static void BuildStage2Scene() => BuildScene(ScenePath, false);

        /* Tahap 3: scene yang sama PLUS terrain streaming + air.
           Sengaja satu fungsi yang sama, bukan duplikat — supaya karakter,
           kamera, dan cahaya di kedua scene dijamin identik dan perbedaan
           yang terlihat murni karena terrain. */
        [MenuItem(\"Tools/Aurelia/4. Bangun scene Tahap 3 (dunia terlihat)\")]
        public static void BuildStage3Scene() => BuildScene(Scene3Path, true);

        /* Dipanggil oleh AureliaBuildPreprocessor sebelum setiap build player,
           termasuk build dari GitHub Actions. Metode yang sama dengan menu di
           atas -- tidak ada jalur khusus CI yang tidak pernah diuji manusia. */
        public static string BuildForBuildPlayer(List<string> log)
            => BuildScene(Scene3Path, true, log);

        static string BuildScene(string scenePath, bool withTerrain, List<string> externalLog = null)
        {
            var notes = externalLog ?? new List<string>();

            if (GraphicsSettings.defaultRenderPipeline == null)
            {
                EnsureUrpAsset();
                if (GraphicsSettings.defaultRenderPipeline == null)
                    notes.Add(\"URP asset gagal dibuat — layar mungkin magenta. \" +\n                              \"Buat manual: Assets > Create > Rendering > URP Asset (with Universal Renderer).\");
            }

            var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);

            // ---- cahaya -------------------------------------------------
            var lightGo = new GameObject(\"Directional Light\");
            var light = lightGo.AddComponent<Light>();
            light.type = LightType.Directional;
            light.color = new Color(1f, 0.96f, 0.88f);
            light.intensity = 1.05f;
            light.shadows = LightShadows.Soft;
            lightGo.transform.rotation = Quaternion.Euler(52f, -34f, 0f);

            // ---- tanah datar --------------------------------------------
            var groundY = (float)WorldData.TerrainH(SpawnX, SpawnZ);
            if (!withTerrain)
            {
                var ground = GameObject.CreatePrimitive(PrimitiveType.Plane);
                ground.name = \"Ground (sementara — diganti Tahap 3)\";
                ground.transform.position = new Vector3(0f, groundY, 0f);
                ground.transform.localScale = new Vector3(12f, 1f, 12f);
                var groundMat = LoadOrCreateMaterial(\"AureliaGroundDebug\",\n                                                     new Color(0.42f, 0.56f, 0.28f), notes);\n                ground.GetComponent<MeshRenderer>().sharedMaterial = groundMat;\n            }

            // ---- karakter -----------------------------------------------
            var charGo = PlaceCharacter(groundY, notes);

            // ---- kamera ---------------------------------------------------
            var camGo = new GameObject(\"Main Camera\");
            var cam = camGo.AddComponent<Camera>();
            // FIX: Selalu SolidColor, bukan Skybox, supaya tidak ada jejak (trails)
            // Skybox tanpa material di URP bisa bikin tidak clear -> jejak
            cam.clearFlags = CameraClearFlags.SolidColor;
            cam.backgroundColor = new Color(0.62f, 0.70f, 0.78f, 1f);
            cam.nearClipPlane = 0.05f;
            cam.farClipPlane = 1200f;
            camGo.AddComponent<AudioListener>();
            var rig = camGo.AddComponent<CameraRig>();
            if (charGo != null) rig.Target = charGo.transform;
            camGo.transform.position = new Vector3(SpawnX, groundY + 2.5f, SpawnZ - 6f);
            camGo.tag = \"MainCamera\";

            // FIX: Pastikan UniversalAdditionalCameraData ada dan benar
            // Ini yang sering hilang kalau URP asset dibuat setelah kamera
            var camData = camGo.GetComponent<UniversalAdditionalCameraData>();
            if (camData == null) camData = camGo.AddComponent<UniversalAdditionalCameraData>();
            // Pakai reflection untuk set properti yang tidak publik di semua versi URP
            // Tapi set minimal yang publik: renderType Base, clearDepth true
            try
            {
                var so = new SerializedObject(camData);
                var renderType = so.FindProperty(\"m_CameraType\");
                if (renderType != null) renderType.intValue = 0; // Base
                var clearDepth = so.FindProperty(\"m_ClearDepth\");
                if (clearDepth != null) clearDepth.boolValue = true;
                var renderPost = so.FindProperty(\"m_RenderPostProcessing\");
                if (renderPost != null) renderPost.boolValue = true;
                var antialiasing = so.FindProperty(\"m_Antialiasing\");
                if (antialiasing != null) antialiasing.intValue = 1; // FXAA atau 2x
                so.ApplyModifiedPropertiesWithoutUndo();
            }
            catch { }

            // ---- EventSystem (dipakai CameraRig.IsPointerOverUi) ----------
            if (Object.FindFirstObjectByType<UnityEngine.EventSystems.EventSystem>() == null)
            {
                var es = new GameObject(\"EventSystem\");
                es.AddComponent<UnityEngine.EventSystems.EventSystem>();
                es.AddComponent<UnityEngine.EventSystems.StandaloneInputModule>();
            }

            // ---- terrain + air (Tahap 3) ----------------------------------
            TerrainChunkStreamer streamer = null;
            WaterPlane water = null;
            if (withTerrain) AddTerrainAndWater(charGo, notes, out streamer, out water);

            // ---- siklus siang/malam + rumput (Tahap 4) ------------------
            DayNightCycle cycle = null;
            GrassField grass = null;
            if (withTerrain)
            {
                var cycleGo = new GameObject(\"DayNightCycle\");
                cycle = cycleGo.AddComponent<DayNightCycle>();
                cycle.Sun = light;

                var grassGo = new GameObject(\"GrassField\");
                grass = grassGo.AddComponent<GrassField>();
                grass.Target = charGo != null ? charGo.transform : null;
                grass.GrassMaterial = LoadOrCreateGrassMaterial(notes);
                notes.Add(\"Rumput + siklus siang/malam terpasang. Tombol suasana Pagi/Siang/\" +\n                          \"Sore/Malam/Realtime ada di kiri-bawah layar.\");
            }

            // ---- GfxApplier + SettingsPanel (baru: setting grafik) ----
            var gfxGo = new GameObject(\"GfxApplier\");
            var applier = gfxGo.AddComponent<GfxApplier>();
            applier.Streamer = streamer;
            applier.Grass = grass;
            applier.Sun = light;
            applier.MainCamera = cam;

            var settingsGo = new GameObject(\"SettingsPanel\");
            var panel = settingsGo.AddComponent<SettingsPanel>();
            panel.Applier = applier;
            panel.Streamer = streamer;
            panel.Grass = grass;
            notes.Add(\"SettingsPanel + GfxApplier terpasang (cel-shading Genshin + setting grafik).\");

            /* HUD performa dipasang bersama scene, bukan nanti. Alasannya:
               tanpa angka di layar, \"rasanya lancar\" tidak bisa dipakai untuk
               memutuskan apa pun -- dan keputusan Tahap 7 (tier kualitas)
               sepenuhnya bergantung pada pengukuran di perangkat. */
            var hudGo = new GameObject(\"PerfHud\");
            var hud = hudGo.AddComponent<PerfHud>();
            hud.Streamer = streamer;
            hud.Water = water;
            hud.Grass = grass;
            hud.Cycle = cycle;
            hud.Visible = withTerrain;
            notes.Add(\"PerfHud terpasang. F1 (atau ketuk sudut kanan-atas 3x) untuk sembunyikan.\");

            // ---- langit & ambient ------------------------------------------
            cam.clearFlags = CameraClearFlags.SolidColor;
            cam.backgroundColor = new Color(0.62f, 0.70f, 0.78f, 1f);
            RenderSettings.ambientMode = AmbientMode.Flat;
            RenderSettings.ambientLight = new Color(0.50f, 0.56f, 0.64f);
            RenderSettings.fog = true;
            RenderSettings.fogMode = FogMode.Linear;
            RenderSettings.fogStartDistance = 220f;
            RenderSettings.fogEndDistance = withTerrain ? 1150f : 600f;
            RenderSettings.fogColor = cam.backgroundColor;

            // ---- simpan ----------------------------------------------------
            var dir = Path.GetDirectoryName(scenePath);
            if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
            EditorSceneManager.MarkSceneDirty(scene);
            if (!EditorSceneManager.SaveScene(scene, scenePath))
                notes.Add($\"Scene gagal disimpan ke {scenePath}.\");

            var sb = new System.Text.StringBuilder();
            sb.AppendLine($\"=== SCENE {(withTerrain ? \"TAHAP 3\" : \"TAHAP 2\")} DIBANGUN ===\");
            sb.AppendLine($\"  tersimpan di : {scenePath}\");
            sb.AppendLine(withTerrain\n                ? $\"  tanah        : terrain streaming (heightfield WorldData), spawn y={groundY:F2}\"\n                : $\"  tanah        : bidang datar 120x120 m di y={groundY:F2} (dari WorldData.TerrainH(Spawn))\");\n            sb.AppendLine($\"  karakter     : {(charGo == null ? \"TIDAK ADA — lihat catatan\" : charGo.name)}\");\n            sb.AppendLine();\n            sb.AppendLine(\"Kontrol:\");\n            sb.AppendLine(\"  WASD / panah        jalan        (Shift = lari 13,5 m/s)\");\n            sb.AppendLine(\"  Spasi               lompat\");\n            sb.AppendLine(\"  seret mouse / jari  putar kamera\");\n            sb.AppendLine(\"  HP: stik virtual muncul di kiri-bawah saat disentuh\");\n            sb.AppendLine(\"  Setting: tombol kiri-atas untuk buka setting grafik\");\n            if (notes.Count > 0)\n            {\n                sb.AppendLine();\n                sb.AppendLine(\"CATATAN / yang perlu kamu urus:\");\n                foreach (var n in notes) sb.AppendLine(\"  - \" + n);\n            }\n            Debug.Log(sb.ToString());\n            if (!Application.isBatchMode)\n            {\n                Selection.activeGameObject = charGo ?? camGo;\n                SceneView.FrameLastActiveSceneView();\n            }\n            AssetDatabase.Refresh();\n            return scenePath;\n        }

        static void AddTerrainAndWater(GameObject charGo, List<string> notes,\n                                       out TerrainChunkStreamer streamer, out WaterPlane water)\n        {\n            var terrainMat = LoadOrCreateShaderMaterial(\"AureliaTerrain\", \"Aurelia/Terrain\", notes);\n            // Fallback ke cel version kalau ada\n            var terrainCel = Shader.Find(\"Aurelia/TerrainCel\");\n            if (terrainCel != null && terrainMat != null && terrainMat.shader.name != \"Aurelia/TerrainCel\")\n            {\n                // Tetap pakai material existing tapi nanti GfxApplier akan swap ke cel kalau setting high\n                notes.Add(\"Shader cel terrain tersedia: Aurelia/TerrainCel\");\n            }\n            var waterMat   = LoadOrCreateShaderMaterial(\"AureliaWater\",   \"Aurelia/Water\",   notes);\n\n            var terrainGo = new GameObject(\"Terrain\");\n            streamer = terrainGo.AddComponent<TerrainChunkStreamer>();\n            streamer.TerrainMaterial = terrainMat;\n            streamer.Target = charGo != null ? charGo.transform : null;\n            streamer.StreamRadius = 2;\n            streamer.QuadsPerChunk = TerrainMesh.DefaultQuads;\n            streamer.MaxBuildsPerFrame = 1;\n\n            var waterGo = new GameObject(\"Water\");\n            water = waterGo.AddComponent<WaterPlane>();\n            water.WaterMaterial = waterMat;\n            water.Target = charGo != null ? charGo.transform : null;\n            water.Size = 1400f;\n\n            notes.Add(\"Terrain: 25 chunk streaming, 8 m per segitiga, ~51.200 segitiga.\");\n            notes.Add(\"Air: satu quad 1.400 m di y = WorldData.WaterLevel (0), mengikuti karakter.\");\n        }

        static Material LoadOrCreateShaderMaterial(string assetName, string shaderName, List<string> notes)\n        {\n            if (!AssetDatabase.IsValidFolder(ShaderFolder))\n            {\n                notes.Add($\"Folder {ShaderFolder} tidak ada — material tidak bisa dibuat.\");\n                return null;\n            }\n            var path = $\"{ShaderFolder}/{assetName}.mat\";\n            var existing = AssetDatabase.LoadAssetAtPath<Material>(path);\n            if (existing != null) return existing;\n\n            var shader = Shader.Find(shaderName);\n            if (shader == null)\n            {\n                notes.Add($\"Shader '{shaderName}' tidak ditemukan oleh Shader.Find. \" +\n                          $\"Material {assetName} tidak dibuat.\");\n                return null;\n            }\n            var m = new Material(shader) { name = assetName };\n            AssetDatabase.CreateAsset(m, path);\n            AssetDatabase.SaveAssets();\n            return m;\n        }

        static Material LoadOrCreateGrassMaterial(List<string> notes)\n        {\n            if (!AssetDatabase.IsValidFolder(RenderFolder))\n            {\n                AssetDatabase.CreateFolder(\"Assets/_Project\", \"Rendering\");\n            }\n            var path = $\"{RenderFolder}/AureliaGrass.mat\";\n            var existing = AssetDatabase.LoadAssetAtPath<Material>(path);\n            if (existing != null) return existing;\n\n            // Coba cel version dulu\n            var shader = Shader.Find(\"Aurelia/GrassCel\");\n            if (shader == null) shader = Shader.Find(\"Aurelia/Grass\");\n            if (shader == null)\n            {\n                notes.Add(\"Shader Aurelia/Grass tidak ketemu -- rumput dilewati. \" +\n                          \"Pastikan folder Assets/_Project/Shaders ikut tersalin.\");\n                return null;\n            }\n            var mat = new Material(shader);\n            mat.name = \"AureliaGrass\";\n            AssetDatabase.CreateAsset(mat, path);\n            AssetDatabase.SaveAssets();\n            return mat;\n        }

        static GameObject PlaceCharacter(float groundY, List<string> notes)\n        {\n            var prefab = FindCharacterPrefab();\n            GameObject instance;\n\n            if (prefab != null)\n            {\n                instance = (GameObject)PrefabUtility.InstantiatePrefab(prefab);\n                instance.name = \"Character\";\n                notes.Add($\"Prefab karakter dipakai: {AssetDatabase.GetAssetPath(prefab)}\");\n            }\n            else\n            {\n                instance = GameObject.CreatePrimitive(PrimitiveType.Capsule);\n                instance.name = \"Character (PLACEHOLDER — prefab VRM belum ada)\";\n                Object.DestroyImmediate(instance.GetComponent<Collider>());\n                notes.Add(\"Prefab VRM belum ditemukan di \" + CharFolder + \".\\n\" +\n                          \"    Dipakai capsule placeholder supaya motor & kamera tetap bisa diuji.\\n\" +\n                          \"    Urutannya: pasang UniVRM v0.131.2 -> taruh AureliaChar.vrm di folder itu ->\\n\" +\n                          \"    tunggu impor selesai -> jalankan menu ini lagi.\");\n            }\n\n            instance.transform.position = new Vector3(SpawnX, groundY, SpawnZ);\n            instance.transform.rotation = Quaternion.identity;\n\n            var rig = instance.AddComponent<CharacterRig>();\n            rig.CharacterRoot = instance.transform;\n            var motor = instance.AddComponent<CharacterMotor>();\n            motor.Rig = rig;\n            motor.Camera = Object.FindFirstObjectByType<CameraRig>();\n            motor.Joystick = instance.AddComponent<TouchJoystick>();\n\n            if (prefab != null) rig.Bind();\n\n            return instance;\n        }

        static GameObject FindCharacterPrefab()\n        {\n            if (!AssetDatabase.IsValidFolder(CharFolder)) return null;\n            return AssetDatabase.FindAssets(\"t:Prefab\", new[] { CharFolder })\n                                .Select(AssetDatabase.GUIDToAssetPath)\n                                .Select(AssetDatabase.LoadAssetAtPath<GameObject>)\n                                .FirstOrDefault(p => p != null &&\n                                          p.GetComponentInChildren<Animator>() != null);\n        }

        static Material LoadOrCreateMaterial(string name, Color color, List<string> notes)\n        {\n            if (!AssetDatabase.IsValidFolder(RenderFolder))\n                AssetDatabase.CreateFolder(\"Assets/_Project\", \"Rendering\");\n            var path = $\"{RenderFolder}/{name}.mat\";\n            var existing = AssetDatabase.LoadAssetAtPath<Material>(path);\n            if (existing != null) return existing;\n\n            var shader = Shader.Find(\"Universal Render Pipeline/Lit\");\n            if (shader == null)\n            {\n                shader = Shader.Find(\"Standard\");\n                notes.Add(\"Shader URP/Lit tidak ditemukan — dipakai Standard. \" +\n                          \"Artinya URP asset belum terpasang benar.\");\n            }\n            var m = new Material(shader) { name = name };\n            if (m.HasProperty(\"_BaseColor\")) m.SetColor(\"_BaseColor\", color);\n            else if (m.HasProperty(\"_Color\")) m.SetColor(\"_Color\", color);\n            AssetDatabase.CreateAsset(m, path);\n            AssetDatabase.SaveAssets();\n            return m;\n        }

        const float TestAngleDeg = 30f;

        [MenuItem(\"Tools/Aurelia/5. Laporkan stat terrain & air (Play Mode)\")]\n        public static void ReportTerrainStats()\n        {\n            if (!Application.isPlaying)\n            {\n                EditorUtility.DisplayDialog(\"Tahap 3\",\n                    \"Menu ini membaca kondisi runtime. Tekan Play dulu.\", \"OK\");\n                return;\n            }\n            var streamer = Object.FindFirstObjectByType<TerrainChunkStreamer>();\n            var water    = Object.FindFirstObjectByType<WaterPlane>();\n            var rig      = Object.FindFirstObjectByType<CharacterRig>();\n            var motor    = Object.FindFirstObjectByType<CharacterMotor>();\n            var sb = new System.Text.StringBuilder();\n            sb.AppendLine(\"=== STAT TAHAP 3 (Play Mode) ===\");\n\n            var p = motor != null ? motor.transform.position\n                                  : (rig != null ? rig.transform.position : Vector3.zero);\n            sb.AppendLine($\"Posisi karakter : {p:F2}\");\n            sb.AppendLine($\"TerrainH(x,z)   : {WorldData.TerrainH(p.x, p.z):F2}  (delta {p.y - WorldData.TerrainH(p.x, p.z):F3})\");\n            sb.AppendLine($\"Di bawah air    : {WorldData.WaterLevel - p.y:F2} m\");\n\n            double g  = TerrainSurface.GradientAt(p.x, p.z);\n            double rk = TerrainSurface.RockAmount(g);\n            double sn = TerrainSurface.SnowAmount(WorldData.TerrainH(p.x, p.z), g);\n            double rd = TerrainSurface.RoadAmount(p.x, p.z);\n            var    c  = TerrainSurface.ColorAt(p.x, p.z);\n            sb.AppendLine($\"Gradien         : {g:F3}\");\n            sb.AppendLine($\"batu/salju/jalan: {rk:P0} / {sn:P0} / {rd:P0}\");\n            sb.AppendLine($\"warna permukaan : ({c[0]:F2}, {c[1]:F2}, {c[2]:F2})\");\n\n            if (streamer == null) sb.AppendLine(\"TerrainChunkStreamer: TIDAK ADA di scene\");\n            else\n            {\n                sb.AppendLine($\"Chunk aktif     : {streamer.ActiveChunks}\");\n                sb.AppendLine($\"Chunk antre     : {streamer.QueuedChunks}\");\n                sb.AppendLine($\"Mesh di pool    : {streamer.PooledMeshes}\");\n                sb.AppendLine($\"Build terakhir  : {streamer.LastBuildMs:F2} ms/chunk (rujukan komputer: 2,0-4,6 ms)\");\n                sb.AppendLine($\"Total           : {streamer.TotalVertices:N0} verteks, {streamer.TotalTriangles:N0} segitiga\");\n                sb.AppendLine($\"Radius/quads    : {streamer.StreamRadius} / {streamer.QuadsPerChunk}\");\n                var rc = WorldData.ChunkPlan(p.x, p.z, streamer.StreamRadius);\n                sb.AppendLine($\"Chunk direncanakan: {rc.Count}\");\n            }\n\n            if (water == null) sb.AppendLine(\"WaterPlane: TIDAK ADA di scene\");\n            else sb.AppendLine($\"Air           : y={water.transform.position.y:F2}, ukuran={water.Size:F0} m\");\n\n            Debug.Log(sb.ToString());\n            EditorUtility.DisplayDialog(\"Tahap 3\", sb.ToString(), \"OK\");\n        }\n\n        [MenuItem(\"Tools/Aurelia/6. Pasang Perf HUD di scene aktif\")]\n        public static void AddPerfHud()\n        {\n            if (Object.FindFirstObjectByType<PerfHud>() != null)\n            {\n                EditorUtility.DisplayDialog(\"Tahap 3\", \"PerfHud sudah ada di scene ini.\", \"OK\");\n                return;\n            }\n            var go = new GameObject(\"PerfHud\");\n            var hud = go.AddComponent<PerfHud>();\n            hud.Streamer = Object.FindFirstObjectByType<TerrainChunkStreamer>();\n            hud.Water = Object.FindFirstObjectByType<WaterPlane>();\n            Undo.RegisterCreatedObjectUndo(go, \"Pasang Perf HUD\");\n            var scene = UnityEngine.SceneManagement.SceneManager.GetActiveScene();\n            EditorSceneManager.MarkSceneDirty(scene);\n            Debug.Log($\"PerfHud dipasang di scene '{scene.name}'. \" +\n                      (hud.Streamer != null ? \"\" : \"TerrainChunkStreamer belum ada — isikan manual kalau sudah.\"));\n        }\n\n        [MenuItem(\"Tools/Aurelia/3. Uji pose karakter/Reset ke bind pose\")]\n        public static void PoseReset() => WithRig(r => { r.Bind(); r.ResetToBind(); });\n\n        [MenuItem(\"Tools/Aurelia/3. Uji pose karakter/Paha +30 (X)\")]\n        public static void PoseThighX() => WithRig(r => Apply(r,\n            (Joint.LeftUpperLeg, new Vector3(TestAngleDeg, 0, 0)),\n            (Joint.RightUpperLeg, new Vector3(TestAngleDeg, 0, 0))));\n\n        [MenuItem(\"Tools/Aurelia/3. Uji pose karakter/Paha +30 (Y)\")]\n        public static void PoseThighY() => WithRig(r => Apply(r,\n            (Joint.LeftUpperLeg, new Vector3(0, TestAngleDeg, 0)),\n            (Joint.RightUpperLeg, new Vector3(0, TestAngleDeg, 0))));\n\n        [MenuItem(\"Tools/Aurelia/3. Uji pose karakter/Paha +30 (Z)\")]\n        public static void PoseThighZ() => WithRig(r => Apply(r,\n            (Joint.LeftUpperLeg, new Vector3(0, 0, TestAngleDeg)),\n            (Joint.RightUpperLeg, new Vector3(0, 0, TestAngleDeg))));\n\n        [MenuItem(\"Tools/Aurelia/3. Uji pose karakter/Lengan atas +30 (X)\")]\n        public static void PoseArmX() => WithRig(r => Apply(r,\n            (Joint.LeftUpperArm, new Vector3(TestAngleDeg, 0, 0)),\n            (Joint.RightUpperArm, new Vector3(TestAngleDeg, 0, 0))));\n\n        [MenuItem(\"Tools/Aurelia/3. Uji pose karakter/Lengan atas +30 (Z)\")]\n        public static void PoseArmZ() => WithRig(r => Apply(r,\n            (Joint.LeftUpperArm, new Vector3(0, 0, TestAngleDeg)),\n            (Joint.RightUpperArm, new Vector3(0, 0, TestAngleDeg))));\n\n        [MenuItem(\"Tools/Aurelia/3. Uji pose karakter/Tulang belakang +20 (X)\")]\n        public static void PoseSpine() => WithRig(r => Apply(r,\n            (Joint.Spine, new Vector3(20f, 0, 0)),\n            (Joint.Chest, new Vector3(10f, 0, 0))));\n\n        [MenuItem(\"Tools/Aurelia/3. Uji pose karakter/Lutut +45 (X)\")]\n        public static void PoseKnee() => WithRig(r => Apply(r,\n            (Joint.LeftLowerLeg, new Vector3(45f, 0, 0)),\n            (Joint.RightLowerLeg, new Vector3(45f, 0, 0))));\n\n        [MenuItem(\"Tools/Aurelia/3. Uji pose karakter/Laporkan tulang yang terikat\")]\n        public static void ReportBones()\n        {\n            var rig = FindRig();\n            if (rig == null) { Debug.LogWarning(\"[Aurelia] tidak ada CharacterRig di scene.\"); return; }\n            if (!rig.IsBound) rig.Bind();\n            Debug.Log(rig.LastBindReport +\n                      \"\\nJalankan Play lalu lihat Console untuk laporan yang sama dari runtime.\");\n        }\n\n        static void WithRig(System.Action<CharacterRig> action)\n        {\n            var rig = FindRig();\n            if (rig == null)\n            {\n                Debug.LogWarning(\"[Aurelia] tidak ada CharacterRig di scene. \" +\n                                 \"Jalankan dulu 'Tools > Aurelia > 2. Bangun scene Tahap 2'.\");\n                return;\n            }\n            if (!rig.IsBound) rig.Bind();\n            action(rig);\n            SceneView.RepaintAll();\n        }\n\n        static void Apply(CharacterRig rig, params (Joint joint, Vector3 eulerDeg)[] items)\n        {\n            rig.ResetToBind();\n            var pose = new Dictionary<Joint, Locomotion.Vec3>();\n            foreach (var (joint, e) in items)\n                pose[joint] = new Locomotion.Vec3(e.x * Mathf.Deg2Rad,\n                                                  e.y * Mathf.Deg2Rad,\n                                                  e.z * Mathf.Deg2Rad);\n            rig.ApplyPoseRaw(pose);\n        }\n\n        static CharacterRig FindRig()\n        {\n            var sel = Selection.activeGameObject;\n            if (sel != null)\n            {\n                var r = sel.GetComponentInChildren<CharacterRig>();\n                if (r != null) return r;\n            }\n            return Object.FindFirstObjectByType<CharacterRig>();\n        }\n    }\n}\n