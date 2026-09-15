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
        public const string ScenePath      = "Assets/_Project/Scenes/Tahap2.unity";
        public const string Scene3Path     = "Assets/_Project/Scenes/Tahap3.unity";
        public const string ShaderFolder   = "Assets/_Project/Shaders";
        public const string RenderFolder = "Assets/_Project/Rendering";
        public const string CharFolder   = "Assets/Art/Characters";

        // ============================================================ 1
        [MenuItem("Tools/Aurelia/1. Buat URP Asset (kalau belum ada)")]
        public static void EnsureUrpAsset()
        {
            if (GraphicsSettings.defaultRenderPipeline != null)
            {
                Debug.Log($"[Aurelia] URP asset sudah ada: " +
                          $"{GraphicsSettings.defaultRenderPipeline.name}. Tidak melakukan apa-apa.");
                return;
            }

            if (!AssetDatabase.IsValidFolder(RenderFolder))
            {
                AssetDatabase.CreateFolder("Assets/_Project", "Rendering");
            }

            var renderer = ScriptableObject.CreateInstance<UniversalRendererData>();
            AssetDatabase.CreateAsset(renderer, $"{RenderFolder}/AureliaRenderer.asset");

            var urp = UniversalRenderPipelineAsset.Create(renderer);
            AssetDatabase.CreateAsset(urp, $"{RenderFolder}/AureliaURP.asset");
            AssetDatabase.SaveAssets();

            GraphicsSettings.defaultRenderPipeline = urp;
            QualitySettings.renderPipeline = urp;
            EditorUtility.SetDirty(urp);
            AssetDatabase.SaveAssets();

            Debug.Log("[Aurelia] URP asset dibuat dan dipasang di Graphics + Quality.\n" +
                      "  " + RenderFolder + "/AureliaURP.asset\n" +
                      "  " + RenderFolder + "/AureliaRenderer.asset\n" +
                      "Catatan: bayangan, HDR, dan MSAA masih default. Itu pekerjaan Tahap 7.");
        }

        // ============================================================ 2
        [MenuItem("Tools/Aurelia/2. Bangun scene Tahap 2 (karakter saja)")]
        public static void BuildStage2Scene() => BuildScene(ScenePath, false);

        /* Tahap 3: scene yang sama PLUS terrain streaming + air.
           Sengaja satu fungsi yang sama, bukan duplikat — supaya karakter,
           kamera, dan cahaya di kedua scene dijamin identik dan perbedaan
           yang terlihat murni karena terrain. */
        [MenuItem("Tools/Aurelia/4. Bangun scene Tahap 3 (dunia terlihat)")]
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
                    notes.Add("URP asset gagal dibuat — layar mungkin magenta. " +
                              "Buat manual: Assets > Create > Rendering > URP Asset (with Universal Renderer).");
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
            /* Tahap 2 memang sengaja bidang datar: yang diuji di sini adalah
               "karakter bisa jalan", bukan "dunia terlihat" (itu Tahap 3).
               Tingginya diambil dari WorldData supaya karakter berdiri di
               angka yang benar, bukan di y=0 karangan. */
            var groundY = (float)WorldData.TerrainH(0, 0);
            /* Bidang datar ini alat uji Tahap 2 ("karakter bisa jalan").
               Di scene Tahap 3 ia justru berbahaya: bidang 120x120 m yang
               memotong bukit bisa menutupi terrain asli dari sudut kamera
               tertentu. Jadi hanya dibuat kalau terrain tidak ikut. */
            if (!withTerrain)
            {
                var ground = GameObject.CreatePrimitive(PrimitiveType.Plane);
                ground.name = "Ground (sementara — diganti Tahap 3)";
                ground.transform.position = new Vector3(0f, groundY, 0f);
                ground.transform.localScale = new Vector3(12f, 1f, 12f);   // 120 m x 120 m
                var groundMat = LoadOrCreateMaterial("AureliaGroundDebug",
                                                     new Color(0.42f, 0.56f, 0.28f), notes);
                ground.GetComponent<MeshRenderer>().sharedMaterial = groundMat;
            }

            // ---- karakter -----------------------------------------------
            var charGo = PlaceCharacter(groundY, notes);

            // ---- kamera ---------------------------------------------------
            var camGo = new GameObject("Main Camera");
            var cam = camGo.AddComponent<Camera>();
            cam.clearFlags = CameraClearFlags.Skybox;
            cam.nearClipPlane = 0.05f;
            cam.farClipPlane = 1200f;
            camGo.AddComponent<AudioListener>();
            var rig = camGo.AddComponent<CameraRig>();
            if (charGo != null) rig.Target = charGo.transform;
            camGo.transform.position = new Vector3(0f, groundY + 2.5f, -6f);
            camGo.tag = "MainCamera";

            // ---- EventSystem (dipakai CameraRig.IsPointerOverUi) ----------
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

            /* HUD performa dipasang bersama scene, bukan nanti. Alasannya:
               tanpa angka di layar, "rasanya lancar" tidak bisa dipakai untuk
               memutuskan apa pun -- dan keputusan Tahap 7 (tier kualitas)
               sepenuhnya bergantung pada pengukuran di perangkat. */
            var hudGo = new GameObject("PerfHud");
            var hud = hudGo.AddComponent<PerfHud>();
            hud.Streamer = streamer;
            hud.Water = water;
            hud.Visible = withTerrain;
            notes.Add("PerfHud terpasang. F1 (atau ketuk sudut kanan-atas 3x) untuk sembunyikan.");

            // ---- langit & ambient ------------------------------------------
            /* EmptyScene TIDAK punya material skybox. ambientMode = Skybox
               tanpa skybox membuat ambient HITAM: walau ada matahari, dunia
               terlihat seperti foto malam -- persis gejala build CI ke-5 di
               HP (layar gelap seragam, hanya HUD dan stik yang kelihatan).
               Sampai langit sungguhan dikerjakan, pakai warna datar yang
               sama dengan fog: cakrawala menyatu dengan kabut dan ambient
               tidak pernah nol. */
            cam.clearFlags = CameraClearFlags.SolidColor;
            cam.backgroundColor = new Color(0.62f, 0.70f, 0.78f);
            RenderSettings.ambientMode = AmbientMode.Flat;
            RenderSettings.ambientLight = new Color(0.50f, 0.56f, 0.64f);
            RenderSettings.fog = true;
            RenderSettings.fogMode = FogMode.Linear;
            /* Terukur di _verify/terrain: jangkauan streaming radius 2 = 1.280 m,
               radius 3 = 1.792 m. Fog mulai sebelum tepi chunk terdekat habis
               supaya chunk tidak muncul tiba-tiba di ujung pandang. */
            RenderSettings.fogStartDistance = 220f;
            RenderSettings.fogEndDistance = withTerrain ? 1150f : 600f;
            RenderSettings.fogColor = cam.backgroundColor;

            // ---- simpan ----------------------------------------------------
            /* Pakai scenePath (parameter), bukan ScenePath (konstanta Tahap 2).
               Kebetulan keduanya satu folder jadi selama ini tidak ketahuan. */
            var dir = Path.GetDirectoryName(scenePath);
            if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
            EditorSceneManager.MarkSceneDirty(scene);
            if (!EditorSceneManager.SaveScene(scene, scenePath))
                notes.Add($"Scene gagal disimpan ke {scenePath}.");

            var sb = new System.Text.StringBuilder();
            sb.AppendLine($"=== SCENE {(withTerrain ? "TAHAP 3" : "TAHAP 2")} DIBANGUN ===");
            sb.AppendLine($"  tersimpan di : {scenePath}");
            sb.AppendLine(withTerrain
                ? $"  tanah        : terrain streaming (heightfield WorldData), spawn y={groundY:F2}"
                : $"  tanah        : bidang datar 120x120 m di y={groundY:F2} (dari WorldData.TerrainH(0,0))");
            sb.AppendLine($"  karakter     : {(charGo == null ? "TIDAK ADA — lihat catatan" : charGo.name)}");
            sb.AppendLine();
            sb.AppendLine("Kontrol:");
            sb.AppendLine("  WASD / panah        jalan        (Shift = lari 13,5 m/s)");
            sb.AppendLine("  Spasi               lompat");
            sb.AppendLine("  seret mouse / jari  putar kamera");
            sb.AppendLine("  HP: stik virtual muncul di kiri-bawah saat disentuh");
            if (notes.Count > 0)
            {
                sb.AppendLine();
                sb.AppendLine("CATATAN / yang perlu kamu urus:");
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
            var waterMat   = LoadOrCreateShaderMaterial("AureliaWater",   "Aurelia/Water",   notes);

            var terrainGo = new GameObject("Terrain");
            streamer = terrainGo.AddComponent<TerrainChunkStreamer>();
            streamer.TerrainMaterial = terrainMat;
            streamer.Target = charGo != null ? charGo.transform : null;
            streamer.StreamRadius = 2;
            streamer.QuadsPerChunk = TerrainMesh.DefaultQuads;
            /* Terukur 3,01 ms/chunk pada quads=32. Satu chunk per frame =
               tidak ada hitch; 25 chunk awal termuat dalam ~25 frame. */
            streamer.MaxBuildsPerFrame = 1;

            var waterGo = new GameObject("Water");
            water = waterGo.AddComponent<WaterPlane>();
            water.WaterMaterial = waterMat;
            water.Target = charGo != null ? charGo.transform : null;
            water.Size = 1400f;

            notes.Add("Terrain: 25 chunk streaming, 8 m per segitiga, ~51.200 segitiga.");
            notes.Add("Air: satu quad 1.400 m di y = WorldData.WaterLevel (0), mengikuti karakter.");
            notes.Add("Kalau terrain terlihat magenta: shader Aurelia/Terrain tidak ketemu. " +
                      "Pastikan folder Assets/_Project/Shaders/ ikut tersalin.");
        }

        static Material LoadOrCreateShaderMaterial(string assetName, string shaderName, List<string> notes)
        {
            if (!AssetDatabase.IsValidFolder(ShaderFolder))
            {
                notes.Add($"Folder {ShaderFolder} tidak ada — material tidak bisa dibuat.");
                return null;
            }
            var path = $"{ShaderFolder}/{assetName}.mat";
            var existing = AssetDatabase.LoadAssetAtPath<Material>(path);
            if (existing != null) return existing;

            var shader = Shader.Find(shaderName);
            if (shader == null)
            {
                notes.Add($"Shader '{shaderName}' tidak ditemukan oleh Shader.Find. " +
                          $"Material {assetName} tidak dibuat.");
                return null;
            }
            var m = new Material(shader) { name = assetName };
            AssetDatabase.CreateAsset(m, path);
            AssetDatabase.SaveAssets();
            return m;
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
                instance.name = "Character (PLACEHOLDER — prefab VRM belum ada)";
                Object.DestroyImmediate(instance.GetComponent<Collider>());
                notes.Add("Prefab VRM belum ditemukan di " + CharFolder + ".\n" +
                          "    Dipakai capsule placeholder supaya motor & kamera tetap bisa diuji.\n" +
                          "    Urutannya: pasang UniVRM v0.131.2 -> taruh AureliaChar.vrm di folder itu ->\n" +
                          "    tunggu impor selesai -> jalankan menu ini lagi.");
            }

            instance.transform.position = new Vector3(0f, groundY, 0f);
            /* VRM dijamin menghadap +Z (spec VRM). CharacterMotor memakai
               yaw = atan2(x, z), jadi tanpa putaran tambahan karakter sudah
               menghadap arah yang benar. */
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

        /* Material disimpan sebagai aset di disk. Material "liar" yang cuma
           hidup di dalam scene tidak bisa di-inspect dan hilang tanpa jejak
           kalau scene-nya dibangun ulang. */
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
                notes.Add("Shader URP/Lit tidak ditemukan — dipakai Standard. " +
                          "Artinya URP asset belum terpasang benar.");
            }
            var m = new Material(shader) { name = name };
            if (m.HasProperty("_BaseColor")) m.SetColor("_BaseColor", color);
            else if (m.HasProperty("_Color")) m.SetColor("_Color", color);
            AssetDatabase.CreateAsset(m, path);
            AssetDatabase.SaveAssets();
            return m;
        }

        // ============================================================ 3
        /* Kalibrasi sumbu tulang.

           Masalahnya nyata: model ini diekspor dari Blender (rigify), jadi
           sumbu lokal tiap tulang adalah pilihan rigify, bukan sumbu
           ternormalisasi Unity Humanoid. Tanpa membuka Unity tidak ada cara
           mengetahui apakah "ayun paha ke depan" itu +X atau -X atau +Z.

           Menu di bawah menerapkan satu putaran pada SATU kelompok sendi
           saja. Lihat di Scene view ke arah mana ia bergerak, lalu setel
           Sign* di Inspector CharacterRig sampai arahnya benar.        */

        const float TestAngleDeg = 30f;

        // ============================================================ 5
        /* Dipanggil di Play Mode. Membaca kondisi nyata, bukan asumsi —
           kalau angkanya meleset dari hasil _verify/terrain, berarti ada
           yang beda di perangkat dan itu yang harus diselidiki. */
        [MenuItem("Tools/Aurelia/5. Laporkan stat terrain & air (Play Mode)")]
        public static void ReportTerrainStats()
        {
            if (!Application.isPlaying)
            {
                EditorUtility.DisplayDialog("Tahap 3",
                    "Menu ini membaca kondisi runtime. Tekan Play dulu.", "OK");
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
            sb.AppendLine($"TerrainH(x,z)   : {WorldData.TerrainH(p.x, p.z):F2}  (delta {p.y - WorldData.TerrainH(p.x, p.z):F3})");
            sb.AppendLine($"Di bawah air    : {WorldData.WaterLevel - p.y:F2} m");

            /* Komposisi permukaan — nilai mentah dari TerrainSurface, bukan
               ringkasan bikinan, supaya yang dilaporkan di sini sama persis
               dengan yang diuji oleh TerrainMeshTests. */
            double g  = TerrainSurface.GradientAt(p.x, p.z);
            double rk = TerrainSurface.RockAmount(g);
            double sn = TerrainSurface.SnowAmount(WorldData.TerrainH(p.x, p.z), g);
            double rd = TerrainSurface.RoadAmount(p.x, p.z);
            var    c  = TerrainSurface.ColorAt(p.x, p.z);
            sb.AppendLine($"Gradien         : {g:F3}");
            sb.AppendLine($"batu/salju/jalan: {rk:P0} / {sn:P0} / {rd:P0}");
            sb.AppendLine($"warna permukaan : ({c[0]:F2}, {c[1]:F2}, {c[2]:F2})");

            if (streamer == null) sb.AppendLine("TerrainChunkStreamer: TIDAK ADA di scene");
            else
            {
                sb.AppendLine($"Chunk aktif     : {streamer.ActiveChunks}");
                sb.AppendLine($"Chunk antre     : {streamer.QueuedChunks}");
                sb.AppendLine($"Mesh di pool    : {streamer.PooledMeshes}");
                sb.AppendLine($"Build terakhir  : {streamer.LastBuildMs:F2} ms/chunk (rujukan komputer: 2,0-4,6 ms)");
                sb.AppendLine($"Total           : {streamer.TotalVertices:N0} verteks, {streamer.TotalTriangles:N0} segitiga");
                sb.AppendLine($"Radius/quads    : {streamer.StreamRadius} / {streamer.QuadsPerChunk}");
                var rc = WorldData.ChunkPlan(p.x, p.z, streamer.StreamRadius);
                sb.AppendLine($"Chunk direncanakan: {rc.Count}");
            }

            if (water == null) sb.AppendLine("WaterPlane: TIDAK ADA di scene");
            else sb.AppendLine($"Air           : y={water.transform.position.y:F2}, ukuran={water.Size:F0} m");

            Debug.Log(sb.ToString());
            EditorUtility.DisplayDialog("Tahap 3", sb.ToString(), "OK");
        }

        /* Dipakai kalau scene sudah terlanjur dibuat sebelum PerfHud ada. */
        [MenuItem("Tools/Aurelia/6. Pasang Perf HUD di scene aktif")]
        public static void AddPerfHud()
        {
            if (Object.FindFirstObjectByType<PerfHud>() != null)
            {
                EditorUtility.DisplayDialog("Tahap 3", "PerfHud sudah ada di scene ini.", "OK");
                return;
            }
            var go = new GameObject("PerfHud");
            var hud = go.AddComponent<PerfHud>();
            hud.Streamer = Object.FindFirstObjectByType<TerrainChunkStreamer>();
            hud.Water = Object.FindFirstObjectByType<WaterPlane>();
            Undo.RegisterCreatedObjectUndo(go, "Pasang Perf HUD");
            var scene = UnityEngine.SceneManagement.SceneManager.GetActiveScene();
            EditorSceneManager.MarkSceneDirty(scene);
            Debug.Log($"PerfHud dipasang di scene '{scene.name}'. " +
                      (hud.Streamer != null ? "" : "TerrainChunkStreamer belum ada — isikan manual kalau sudah."));
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
            Debug.Log(rig.LastBindReport +
                      "\nJalankan Play lalu lihat Console untuk laporan yang sama dari runtime.");
        }

        static void WithRig(System.Action<CharacterRig> action)
        {
            var rig = FindRig();
            if (rig == null)
            {
                Debug.LogWarning("[Aurelia] tidak ada CharacterRig di scene. " +
                                 "Jalankan dulu 'Tools > Aurelia > 2. Bangun scene Tahap 2'.");
                return;
            }
            if (!rig.IsBound) rig.Bind();
            action(rig);
            SceneView.RepaintAll();
        }

        static void Apply(CharacterRig rig, params (Joint joint, Vector3 eulerDeg)[] items)
        {
            rig.ResetToBind();
            /* Lewati ApplyPose() dan tulis langsung, supaya pengali Sign* di
               Inspector TIDAK ikut campur — yang sedang diuji di sini justru
               sumbu mentah tulang. */
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
