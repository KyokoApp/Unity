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
        // FIX 2026-09-15: URP asset lama bikin layar hitam + jejak (trails) di Android:
        //   - UniversalRendererData dibuat via CreateInstance tanpa postProcessData
        //     (URP 17 wajib ada PostProcessData, kalau null renderer gagal clear)
        //   - QualitySettings.renderPipeline cuma diset untuk quality level aktif,
        //     level lain null -> fallback Built-in -> shader URP magenta/hitam
        //   - GlobalSettings tidak ada -> resource URP tidak ke-load
        //   - Camera clearFlags Skybox tanpa skybox -> tidak clear
        // Perbaikan: buat asset dengan postProcessData dari package, set SEMUA quality level.
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
            PostProcessData postProcessData = null;
            var ppPaths = new[] {
                "Packages/com.unity.render-pipelines.universal/Runtime/Data/PostProcessData.asset",
                "Packages/com.unity.render-pipelines.universal/Runtime/Data/PostProcessData.asset",
                "Packages/com.unity.render-pipelines.universal/Runtime/Data/PostProcessData.asset"
            };
            foreach (var p in ppPaths)
            {
                postProcessData = AssetDatabase.LoadAssetAtPath<PostProcessData>(p);
                if (postProcessData != null) break;
            }
            if (postProcessData == null)
            {
                var guids = AssetDatabase.FindAssets("t:PostProcessData");
                if (guids.Length > 0)
                {
                    var path = AssetDatabase.GUIDToAssetPath(guids[0]);
                    postProcessData = AssetDatabase.LoadAssetAtPath<PostProcessData>(path);
                }
            }

            if (renderer == null)
            {
                renderer = ScriptableObject.CreateInstance<UniversalRendererData>();
                if (postProcessData != null) renderer.postProcessData = postProcessData;
                AssetDatabase.CreateAsset(renderer, rendererPath);
                Debug.Log($"[Aurelia] RendererData dibuat: {rendererPath} postProcessData={(postProcessData!=null?"ada":"NULL")}");
            }
            else if (renderer.postProcessData == null && postProcessData != null)
            {
                renderer.postProcessData = postProcessData;
                EditorUtility.SetDirty(renderer);
                Debug.Log("[Aurelia] RendererData diperbaiki: postProcessData dipasang dari package");
            }

            // --- 2. URP Asset ---
            var urpPath = $"{RenderFolder}/AureliaURP.asset";
            var urp = AssetDatabase.LoadAssetAtPath<UniversalRenderPipelineAsset>(urpPath);

            if (urp == null)
            {
                urp = UniversalRenderPipelineAsset.Create(renderer);
                AssetDatabase.CreateAsset(urp, urpPath);
                Debug.Log($"[Aurelia] URP Asset dibuat: {urpPath}");
            }
            else
            {
                var so = new SerializedObject(urp);
                var rendererList = so.FindProperty("m_RendererDataList");
                if (rendererList != null && rendererList.arraySize > 0)
                {
                    rendererList.GetArrayElementAtIndex(0).objectReferenceValue = renderer;
                    so.ApplyModifiedPropertiesWithoutUndo();
                }
            }

            // --- 3. GlobalSettings (URP 17 wajib) ---
            try
            {
                var global = GraphicsSettings.GetSettingsForRenderPipeline<UniversalRenderPipeline>() as UniversalRenderPipelineGlobalSettings;
                if (global == null)
                {
                    var guids = AssetDatabase.FindAssets("t:UniversalRenderPipelineGlobalSettings");
                    if (guids.Length > 0)
                    {
                        var path = AssetDatabase.GUIDToAssetPath(guids[0]);
                        global = AssetDatabase.LoadAssetAtPath<UniversalRenderPipelineGlobalSettings>(path);
                    }
                }
                if (global == null)
                {
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
                if (global != null) EditorUtility.SetDirty(global);
            }
            catch (System.Exception e)
            {
                Debug.LogWarning($"[Aurelia] GlobalSettings ensure gagal: {e.Message}");
            }

            // --- 4. Pasang ke GraphicsSettings & SEMUA Quality Level ---
            GraphicsSettings.defaultRenderPipeline = urp;

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
                QualitySettings.renderPipeline = urp;
                Debug.LogWarning($"[Aurelia] Set all quality levels gagal, fallback: {e.Message}");
            }

            EditorUtility.SetDirty(urp);
            if (renderer != null) EditorUtility.SetDirty(renderer);
            AssetDatabase.SaveAssets();

            var hasGlobal = GraphicsSettings.GetSettingsForRenderPipeline<UniversalRenderPipeline>() != null ? "ada" : "akan dibuat validator";
            Debug.Log("[Aurelia] URP asset siap:\n  " + urpPath + "\n  " + rendererPath + "\n  GlobalSettings: " + hasGlobal + "\nCatatan: cel-shading aktif via shader Aurelia/*Cel");
        }

        // ============================================================ 2
        [MenuItem("Tools/Aurelia/2. Bangun scene Tahap 2 (karakter saja)")]
        public static void BuildStage2Scene() => BuildScene(ScenePath, false);

        [MenuItem("Tools/Aurelia/4. Bangun scene Tahap 3 (dunia terlihat)")]
        public static void BuildStage3Scene() => BuildScene(Scene3Path, true);

        public static string BuildForBuildPlayer(List<string> log)
            => BuildScene(Scene3Path, true, log);

        static string BuildScene(string scenePath, bool withTerrain, List<string> externalLog = null)
        {
            var notes = externalLog ?? new List<string>();

            if (GraphicsSettings.defaultRenderPipeline == null)
            {
                EnsureUrpAsset();
                if (GraphicsSettings.defaultRenderPipeline == null)
                    notes.Add("URP asset gagal dibuat - layar mungkin magenta. Buat manual: Assets > Create > Rendering > URP Asset");
            }

            var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);

            // ---- cahaya -------------------------------------------------
            var lightGo = new GameObject("Directional Light");
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
                ground.name = "Ground (sementara - diganti Tahap 3)";
                ground.transform.position = new Vector3(0f, groundY, 0f);
                ground.transform.localScale = new Vector3(12f, 1f, 12f);
                var groundMat = LoadOrCreateMaterial("AureliaGroundDebug", new Color(0.42f, 0.56f, 0.28f), notes);
                ground.GetComponent<MeshRenderer>().sharedMaterial = groundMat;
            }

            // ---- karakter -----------------------------------------------
            var charGo = PlaceCharacter(groundY, notes);

            // ---- kamera ---------------------------------------------------
            var camGo = new GameObject("Main Camera");
            var cam = camGo.AddComponent<Camera>();
            cam.clearFlags = CameraClearFlags.SolidColor;
            cam.backgroundColor = new Color(0.62f, 0.70f, 0.78f, 1f);
            cam.nearClipPlane = 0.05f;
            cam.farClipPlane = 1200f;
            camGo.AddComponent<AudioListener>();
            var rig = camGo.AddComponent<CameraRig>();
            if (charGo != null) rig.Target = charGo.transform;
            camGo.transform.position = new Vector3(SpawnX, groundY + 2.5f, SpawnZ - 6f);
            camGo.tag = "MainCamera";

            var camData = camGo.GetComponent<UniversalAdditionalCameraData>();
            if (camData == null) camData = camGo.AddComponent<UniversalAdditionalCameraData>();
            try
            {
                var so = new SerializedObject(camData);
                var renderType = so.FindProperty("m_CameraType");
                if (renderType != null) renderType.intValue = 0;
                var clearDepth = so.FindProperty("m_ClearDepth");
                if (clearDepth != null) clearDepth.boolValue = true;
                var renderPost = so.FindProperty("m_RenderPostProcessing");
                if (renderPost != null) renderPost.boolValue = true;
                var antialiasing = so.FindProperty("m_Antialiasing");
                if (antialiasing != null) antialiasing.intValue = 1;
                so.ApplyModifiedPropertiesWithoutUndo();
            }
            catch { }

            // ---- EventSystem ----------
            if (Object.FindFirstObjectByType<UnityEngine.EventSystems.EventSystem>() == null)
            {
                var es = new GameObject("EventSystem");
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
                var cycleGo = new GameObject("DayNightCycle");
                cycle = cycleGo.AddComponent<DayNightCycle>();
                cycle.Sun = light;

                var grassGo = new GameObject("GrassField");
                grass = grassGo.AddComponent<GrassField>();
                grass.Target = charGo != null ? charGo.transform : null;
                grass.GrassMaterial = LoadOrCreateGrassMaterial(notes);
                notes.Add("Rumput + siklus siang/malam terpasang.");
            }

            // ---- GfxApplier + SettingsPanel ----
            var gfxGo = new GameObject("GfxApplier");
            var applier = gfxGo.AddComponent<GfxApplier>();
            applier.Streamer = streamer;
            applier.Grass = grass;
            applier.Sun = light;
            applier.MainCamera = cam;

            var settingsGo = new GameObject("SettingsPanel");
            var panel = settingsGo.AddComponent<SettingsPanel>();
            panel.Applier = applier;
            panel.Streamer = streamer;
            panel.Grass = grass;
            notes.Add("SettingsPanel + GfxApplier terpasang (cel-shading + setting grafik).");

            var hudGo = new GameObject("PerfHud");
            var hud = hudGo.AddComponent<PerfHud>();
            hud.Streamer = streamer;
            hud.Water = water;
            hud.Grass = grass;
            hud.Cycle = cycle;
            hud.Visible = withTerrain;
            notes.Add("PerfHud terpasang.");

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
                notes.Add($"Scene gagal disimpan ke {scenePath}.");

            var sb = new System.Text.StringBuilder();
            sb.AppendLine($"=== SCENE {(withTerrain ? "TAHAP 3" : "TAHAP 2")} DIBANGUN ===");
            sb.AppendLine($"  tersimpan di : {scenePath}");
            sb.AppendLine(withTerrain
                ? $"  tanah        : terrain streaming, spawn y={groundY:F2}"
                : $"  tanah        : bidang datar 120x120 m di y={groundY:F2}");
            sb.AppendLine($"  karakter     : {(charGo == null ? "TIDAK ADA" : charGo.name)}");
            sb.AppendLine();
            sb.AppendLine("Kontrol:");
            sb.AppendLine("  WASD / panah        jalan        (Shift = lari)");
            sb.AppendLine("  Spasi               lompat");
            sb.AppendLine("  seret mouse / jari  putar kamera");
            sb.AppendLine("  HP: stik virtual di kiri-bawah");
            sb.AppendLine("  Setting: tombol kiri-atas");
            if (notes.Count > 0)
            {
                sb.AppendLine();
                sb.AppendLine("CATATAN:");
                foreach (var n in notes) sb.AppendLine("  - " + n);
            }
            Debug.Log(sb.ToString());
            if (!Application.isBatchMode)
            {
                Selection.activeGameObject = charGo ?? camGo;
                SceneView.FrameLastActiveSceneView();
            }
            AssetDatabase.Refresh();
            return scenePath;
        }

        static void AddTerrainAndWater(GameObject charGo, List<string> notes,
                                       out TerrainChunkStreamer streamer, out WaterPlane water)
        {
            var terrainMat = LoadOrCreateShaderMaterial("AureliaTerrain", "Aurelia/Terrain", notes);
            var terrainCel = Shader.Find("Aurelia/TerrainCel");
            if (terrainCel != null && terrainMat != null && terrainMat.shader.name != "Aurelia/TerrainCel")
            {
                notes.Add("Shader cel terrain tersedia: Aurelia/TerrainCel");
            }
            var waterMat   = LoadOrCreateShaderMaterial("AureliaWater",   "Aurelia/Water",   notes);

            var terrainGo = new GameObject("Terrain");
            streamer = terrainGo.AddComponent<TerrainChunkStreamer>();
            streamer.TerrainMaterial = terrainMat;
            streamer.Target = charGo != null ? charGo.transform : null;
            streamer.StreamRadius = 2;
            streamer.QuadsPerChunk = TerrainMesh.DefaultQuads;
            streamer.MaxBuildsPerFrame = 1;

            var waterGo = new GameObject("Water");
            water = waterGo.AddComponent<WaterPlane>();
            water.WaterMaterial = waterMat;
            water.Target = charGo != null ? charGo.transform : null;
            water.Size = 1400f;

            notes.Add("Terrain: 25 chunk streaming.");
            notes.Add("Air: satu quad 1400 m di y = WaterLevel.");
        }

        static Material LoadOrCreateShaderMaterial(string assetName, string shaderName, List<string> notes)
        {
            if (!AssetDatabase.IsValidFolder(ShaderFolder))
            {
                notes.Add($"Folder {ShaderFolder} tidak ada");
                return null;
            }
            var path = $"{ShaderFolder}/{assetName}.mat";
            var existing = AssetDatabase.LoadAssetAtPath<Material>(path);
            if (existing != null) return existing;

            var shader = Shader.Find(shaderName);
            if (shader == null)
            {
                notes.Add($"Shader '{shaderName}' tidak ditemukan.");
                return null;
            }
            var m = new Material(shader) { name = assetName };
            AssetDatabase.CreateAsset(m, path);
            AssetDatabase.SaveAssets();
            return m;
        }

        static Material LoadOrCreateGrassMaterial(List<string> notes)
        {
            if (!AssetDatabase.IsValidFolder(RenderFolder))
            {
                AssetDatabase.CreateFolder("Assets/_Project", "Rendering");
            }
            var path = $"{RenderFolder}/AureliaGrass.mat";
            var existing = AssetDatabase.LoadAssetAtPath<Material>(path);
            if (existing != null) return existing;

            var shader = Shader.Find("Aurelia/GrassCel");
            if (shader == null) shader = Shader.Find("Aurelia/Grass");
            if (shader == null)
            {
                notes.Add("Shader Aurelia/Grass tidak ketemu");
                return null;
            }
            var mat = new Material(shader);
            mat.name = "AureliaGrass";
            AssetDatabase.CreateAsset(mat, path);
            AssetDatabase.SaveAssets();
            return mat;
        }

        static GameObject PlaceCharacter(float groundY, List<string> notes)
        {
            var prefab = FindCharacterPrefab();
            GameObject instance;

            if (prefab != null)
            {
                instance = (GameObject)PrefabUtility.InstantiatePrefab(prefab);
                instance.name = "Character";
                notes.Add($"Prefab karakter dipakai: {AssetDatabase.GetAssetPath(prefab)}");
            }
            else
            {
                instance = GameObject.CreatePrimitive(PrimitiveType.Capsule);
                instance.name = "Character (PLACEHOLDER)";
                Object.DestroyImmediate(instance.GetComponent<Collider>());
                notes.Add("Prefab VRM belum ditemukan, pakai capsule.");
            }

            instance.transform.position = new Vector3(SpawnX, groundY, SpawnZ);
            instance.transform.rotation = Quaternion.identity;

            var rig = instance.AddComponent<CharacterRig>();
            rig.CharacterRoot = instance.transform;
            var motor = instance.AddComponent<CharacterMotor>();
            motor.Rig = rig;
            motor.Camera = Object.FindFirstObjectByType<CameraRig>();
            motor.Joystick = instance.AddComponent<TouchJoystick>();

            if (prefab != null) rig.Bind();

            return instance;
        }

        static GameObject FindCharacterPrefab()
        {
            if (!AssetDatabase.IsValidFolder(CharFolder)) return null;
            return AssetDatabase.FindAssets("t:Prefab", new[] { CharFolder })
                                .Select(AssetDatabase.GUIDToAssetPath)
                                .Select(AssetDatabase.LoadAssetAtPath<GameObject>)
                                .FirstOrDefault(p => p != null &&
                                          p.GetComponentInChildren<Animator>() != null);
        }

        static Material LoadOrCreateMaterial(string name, Color color, List<string> notes)
        {
            if (!AssetDatabase.IsValidFolder(RenderFolder))
                AssetDatabase.CreateFolder("Assets/_Project", "Rendering");
            var path = $"{RenderFolder}/{name}.mat";
            var existing = AssetDatabase.LoadAssetAtPath<Material>(path);
            if (existing != null) return existing;

            var shader = Shader.Find("Universal Render Pipeline/Lit");
            if (shader == null)
            {
                shader = Shader.Find("Standard");
                notes.Add("Shader URP/Lit tidak ditemukan, pakai Standard.");
            }
            var m = new Material(shader) { name = name };
            if (m.HasProperty("_BaseColor")) m.SetColor("_BaseColor", color);
            else if (m.HasProperty("_Color")) m.SetColor("_Color", color);
            AssetDatabase.CreateAsset(m, path);
            AssetDatabase.SaveAssets();
            return m;
        }

        const float TestAngleDeg = 30f;

        [MenuItem("Tools/Aurelia/5. Laporkan stat terrain & air (Play Mode)")]
        public static void ReportTerrainStats()
        {
            if (!Application.isPlaying)
            {
                EditorUtility.DisplayDialog("Tahap 3", "Tekan Play dulu.", "OK");
                return;
            }
            var streamer = Object.FindFirstObjectByType<TerrainChunkStreamer>();
            var water    = Object.FindFirstObjectByType<WaterPlane>();
            var rig      = Object.FindFirstObjectByType<CharacterRig>();
            var motor    = Object.FindFirstObjectByType<CharacterMotor>();
            var sb = new System.Text.StringBuilder();
            sb.AppendLine("=== STAT TAHAP 3 (Play Mode) ===");

            var p = motor != null ? motor.transform.position
                                  : (rig != null ? rig.transform.position : Vector3.zero);
            sb.AppendLine($"Posisi karakter : {p:F2}");
            sb.AppendLine($"TerrainH(x,z)   : {WorldData.TerrainH(p.x, p.z):F2}");
            sb.AppendLine($"Di bawah air    : {WorldData.WaterLevel - p.y:F2} m");

            double g  = TerrainSurface.GradientAt(p.x, p.z);
            double rk = TerrainSurface.RockAmount(g);
            double sn = TerrainSurface.SnowAmount(WorldData.TerrainH(p.x, p.z), g);
            double rd = TerrainSurface.RoadAmount(p.x, p.z);
            var    c  = TerrainSurface.ColorAt(p.x, p.z);
            sb.AppendLine($"Gradien         : {g:F3}");
            sb.AppendLine($"batu/salju/jalan: {rk:P0} / {sn:P0} / {rd:P0}");
            sb.AppendLine($"warna permukaan : ({c[0]:F2}, {c[1]:F2}, {c[2]:F2})");

            if (streamer == null) sb.AppendLine("TerrainChunkStreamer: TIDAK ADA");
            else
            {
                sb.AppendLine($"Chunk aktif     : {streamer.ActiveChunks}");
                sb.AppendLine($"Chunk antre     : {streamer.QueuedChunks}");
                sb.AppendLine($"Mesh di pool    : {streamer.PooledMeshes}");
                sb.AppendLine($"Build terakhir  : {streamer.LastBuildMs:F2} ms");
                sb.AppendLine($"Total           : {streamer.TotalVertices:N0} verteks, {streamer.TotalTriangles:N0} segitiga");
            }

            if (water == null) sb.AppendLine("WaterPlane: TIDAK ADA");
            else sb.AppendLine($"Air           : y={water.transform.position.y:F2}, ukuran={water.Size:F0} m");

            Debug.Log(sb.ToString());
            EditorUtility.DisplayDialog("Tahap 3", sb.ToString(), "OK");
        }

        [MenuItem("Tools/Aurelia/6. Pasang Perf HUD di scene aktif")]
        public static void AddPerfHud()
        {
            if (Object.FindFirstObjectByType<PerfHud>() != null)
            {
                EditorUtility.DisplayDialog("Tahap 3", "PerfHud sudah ada.", "OK");
                return;
            }
            var go = new GameObject("PerfHud");
            var hud = go.AddComponent<PerfHud>();
            hud.Streamer = Object.FindFirstObjectByType<TerrainChunkStreamer>();
            hud.Water = Object.FindFirstObjectByType<WaterPlane>();
            Undo.RegisterCreatedObjectUndo(go, "Pasang Perf HUD");
            var scene = UnityEngine.SceneManagement.SceneManager.GetActiveScene();
            EditorSceneManager.MarkSceneDirty(scene);
            Debug.Log($"PerfHud dipasang di scene '{scene.name}'.");
        }

        [MenuItem("Tools/Aurelia/3. Uji pose karakter/Reset ke bind pose")]
        public static void PoseReset() => WithRig(r => { r.Bind(); r.ResetToBind(); });

        [MenuItem("Tools/Aurelia/3. Uji pose karakter/Paha +30 (X)")]
        public static void PoseThighX() => WithRig(r => Apply(r,
            (Joint.LeftUpperLeg, new Vector3(TestAngleDeg, 0, 0)),
            (Joint.RightUpperLeg, new Vector3(TestAngleDeg, 0, 0))));

        [MenuItem("Tools/Aurelia/3. Uji pose karakter/Paha +30 (Y)")]
        public static void PoseThighY() => WithRig(r => Apply(r,
            (Joint.LeftUpperLeg, new Vector3(0, TestAngleDeg, 0)),
            (Joint.RightUpperLeg, new Vector3(0, TestAngleDeg, 0))));

        [MenuItem("Tools/Aurelia/3. Uji pose karakter/Paha +30 (Z)")]
        public static void PoseThighZ() => WithRig(r => Apply(r,
            (Joint.LeftUpperLeg, new Vector3(0, 0, TestAngleDeg)),
            (Joint.RightUpperLeg, new Vector3(0, 0, TestAngleDeg))));

        [MenuItem("Tools/Aurelia/3. Uji pose karakter/Lengan atas +30 (X)")]
        public static void PoseArmX() => WithRig(r => Apply(r,
            (Joint.LeftUpperArm, new Vector3(TestAngleDeg, 0, 0)),
            (Joint.RightUpperArm, new Vector3(TestAngleDeg, 0, 0))));

        [MenuItem("Tools/Aurelia/3. Uji pose karakter/Lengan atas +30 (Z)")]
        public static void PoseArmZ() => WithRig(r => Apply(r,
            (Joint.LeftUpperArm, new Vector3(0, 0, TestAngleDeg)),
            (Joint.RightUpperArm, new Vector3(0, 0, TestAngleDeg))));

        [MenuItem("Tools/Aurelia/3. Uji pose karakter/Tulang belakang +20 (X)")]
        public static void PoseSpine() => WithRig(r => Apply(r,
            (Joint.Spine, new Vector3(20f, 0, 0)),
            (Joint.Chest, new Vector3(10f, 0, 0))));

        [MenuItem("Tools/Aurelia/3. Uji pose karakter/Lutut +45 (X)")]
        public static void PoseKnee() => WithRig(r => Apply(r,
            (Joint.LeftLowerLeg, new Vector3(45f, 0, 0)),
            (Joint.RightLowerLeg, new Vector3(45f, 0, 0))));

        [MenuItem("Tools/Aurelia/3. Uji pose karakter/Laporkan tulang yang terikat")]
        public static void ReportBones()
        {
            var rig = FindRig();
            if (rig == null) { Debug.LogWarning("[Aurelia] tidak ada CharacterRig di scene."); return; }
            if (!rig.IsBound) rig.Bind();
            Debug.Log(rig.LastBindReport + "\nJalankan Play lalu lihat Console.");
        }

        static void WithRig(System.Action<CharacterRig> action)
        {
            var rig = FindRig();
            if (rig == null)
            {
                Debug.LogWarning("[Aurelia] tidak ada CharacterRig di scene.");
                return;
            }
            if (!rig.IsBound) rig.Bind();
            action(rig);
            SceneView.RepaintAll();
        }

        static void Apply(CharacterRig rig, params (Joint joint, Vector3 eulerDeg)[] items)
        {
            rig.ResetToBind();
            var pose = new Dictionary<Joint, Locomotion.Vec3>();
            foreach (var (joint, e) in items)
                pose[joint] = new Locomotion.Vec3(e.x * Mathf.Deg2Rad,
                                                  e.y * Mathf.Deg2Rad,
                                                  e.z * Mathf.Deg2Rad);
            rig.ApplyPoseRaw(pose);
        }

        static CharacterRig FindRig()
        {
            var sel = Selection.activeGameObject;
            if (sel != null)
            {
                var r = sel.GetComponentInChildren<CharacterRig>();
                if (r != null) return r;
            }
            return Object.FindFirstObjectByType<CharacterRig>();
        }
    }
}
