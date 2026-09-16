using System;
using System.Collections.Generic;
using UnityEngine;

namespace RPG.Runtime
{
    /* ============================================================
       ANIME VFX — pool partikel ringan untuk efek sparkle/skill.

       Desain untuk HP kentang: SATU mesh quad + SATU material
       (Aurelia/Sparkle, additive) + SATU draw call instanced untuk
       SEMUA partikel. CPU hanya mengintegrasikan posisi (maks 256)
       dan menulis matriks — tanpa alokasi per frame.

       VFX Graph SENGAJA tidak dipakai: butuh compute shader yang
       tidak ada di sebagian GPU Android. Shuriken ParticleSystem
       juga dilewati: API modulnya besar dan tiap sistem = draw
       call sendiri. Pool ini cukup untuk sparkle, tebasan, dash,
       debu mendarat, skill, dan ultimate.

       Semua API statis null-safe: kalau komponen tidak ada di
       scene, panggilan jadi no-op (game tetap jalan).
       ============================================================ */
    [DisallowMultipleComponent]
    public class AnimeVFX : MonoBehaviour
    {
        public const int Max = 256;

        [Header("Tampilan")]
        [Tooltip("Kosong = dicari otomatis (shader Aurelia/Sparkle).")]
        public Material SparkleMaterial;
        public float GlobalIntensity = 1f;

        struct P
        {
            public Vector3 Pos;
            public Vector3 Vel;
            public float Life;
            public float MaxLife;
            public float Size;
            public float EndSize;
            public Color Col;
            public Color EndCol;
            public float Gravity;
            public float Drag;
            public bool Active;
        }

        public static AnimeVFX Instance { get; private set; }

        readonly P[] _pool = new P[Max];
        int _cursor;
        readonly Matrix4x4[] _mats = new Matrix4x4[Max];
        readonly Vector4[] _cols = new Vector4[Max];
        readonly MaterialPropertyBlock _block = new MaterialPropertyBlock();
        readonly System.Random _rng = new System.Random(12345);
        Mesh _quad;
        Camera _cam;

        Emitter _aura;

        struct Emitter
        {
            public Transform Target;
            public Color Col;
            public float Rate;
            public float Acc;
            public bool On;
        }

        static readonly int InstColorId = Shader.PropertyToID("_InstColor");

        void Awake()
        {
            Instance = this;
            _quad = BuildQuad();
            if (SparkleMaterial == null)
            {
                var sh = Shader.Find("Aurelia/Sparkle");
                if (sh != null) SparkleMaterial = new Material(sh) { name = "AnimeSparkle" };
            }
            WorldLook.EnableInstancing(SparkleMaterial);
            _cam = Camera.main;
        }

        void OnDestroy()
        {
            if (Instance == this) Instance = null;
            ObjectUtil.SafeDestroy(_quad);
        }

        static Mesh BuildQuad()
        {
            var m = new Mesh { name = "SparkleQuad" };
            m.vertices = new[]
            {
                new Vector3(-0.5f, -0.5f, 0f), new Vector3(0.5f, -0.5f, 0f),
                new Vector3(-0.5f, 0.5f, 0f), new Vector3(0.5f, 0.5f, 0f),
            };
            m.uv = new[]
            {
                new Vector2(0f, 0f), new Vector2(1f, 0f),
                new Vector2(0f, 1f), new Vector2(1f, 1f),
            };
            m.triangles = new[] { 0, 2, 1, 2, 3, 1 };
            m.RecalculateBounds();
            var b = m.bounds;
            // Bounds raksasa: matriks instance bergerak, mesh-nya diam di
            // origin — tanpa ini frustum culling membuang gambarnya.
            m.bounds = new Bounds(Vector3.zero, new Vector3(10000f, 10000f, 10000f));
            return m;
        }

        void LateUpdate()
        {
            if (SparkleMaterial == null) return;
            if (_cam == null) _cam = Camera.main;
            if (_cam == null) return;

            var dt = Time.deltaTime;
            if (dt > 0f) Tick(dt);

            // Billboard bola: semua partikel menghadap kamera.
            var rot = _cam.transform.rotation;
            var n = 0;
            for (var i = 0; i < Max; i++)
            {
                if (!_pool[i].Active) continue;
                ref var p = ref _pool[i];
                var t = 1f - p.Life / p.MaxLife;
                var size = p.Size + (p.EndSize - p.Size) * t;
                var fadeIn = Mathf.Clamp01((p.MaxLife - p.Life) / 0.08f);
                var fadeOut = Mathf.Clamp01(p.Life / (p.MaxLife * 0.45f));
                var c = Color.Lerp(p.Col, p.EndCol, t);
                _mats[n] = Matrix4x4.TRS(p.Pos, rot, new Vector3(size, size, size));
                _cols[n] = new Vector4(c.r, c.g, c.b,
                    c.a * fadeIn * fadeOut * GlobalIntensity);
                n++;
            }
            if (n == 0) return;
            WorldLook.EnableInstancing(SparkleMaterial);
            _block.SetVectorArray(InstColorId, _cols);
            try
            {
                Graphics.DrawMeshInstanced(_quad, 0, SparkleMaterial, _mats, n, _block);
            }
            catch (Exception e)
            {
                SparkleMaterial = null; // jangan spam exception tiap frame
                BootLog.Add("[noise] sparkle instancing mati: " + e.GetType().Name + ": " + e.Message);
            }
        }

        void Tick(float dt)
        {
            if (_aura.On && _aura.Target != null)
            {
                _aura.Acc += _aura.Rate * dt;
                var c = _aura.Target.position + Vector3.up * 1f;
                while (_aura.Acc >= 1f)
                {
                    _aura.Acc -= 1f;
                    var a = (float)_rng.NextDouble() * 6.2832f;
                    var r = 0.5f + (float)_rng.NextDouble() * 0.5f;
                    Spawn(c + new Vector3(Mathf.Cos(a) * r, (float)_rng.NextDouble() * 1.2f - 0.4f,
                                          Mathf.Sin(a) * r),
                          new Vector3(-Mathf.Sin(a) * 0.6f, 0.7f, Mathf.Cos(a) * 0.6f),
                          1.1f, 0.16f, 0.05f, _aura.Col, _aura.Col, 0f, 1f);
                }
            }

            for (var i = 0; i < Max; i++)
            {
                if (!_pool[i].Active) continue;
                ref var p = ref _pool[i];
                p.Life -= dt;
                if (p.Life <= 0f) { p.Active = false; continue; }
                p.Vel.y -= p.Gravity * dt;
                p.Vel *= Mathf.Exp(-p.Drag * dt);
                p.Pos += p.Vel * dt;
            }
        }

        void Spawn(Vector3 pos, Vector3 vel, float life, float size, float endSize,
                   Color col, Color endCol, float gravity, float drag)
        {
            ref var p = ref _pool[_cursor];
            _cursor = (_cursor + 1) % Max;
            p.Pos = pos; p.Vel = vel;
            p.Life = life; p.MaxLife = life;
            p.Size = size; p.EndSize = endSize;
            p.Col = col; p.EndCol = endCol;
            p.Gravity = gravity; p.Drag = drag;
            p.Active = true;
        }

        // ============================================================ efek
        public static void Burst(Vector3 pos, Color col, int count, float speed,
                                 float life, float size)
        {
            if (Instance == null) return;
            for (var i = 0; i < count; i++)
            {
                var th = (float)Instance._rng.NextDouble() * 6.2832f;
                var ph = (float)Instance._rng.NextDouble() * 3.1416f - 1.5708f;
                var v = new Vector3(Mathf.Cos(th) * Mathf.Cos(ph),
                                    Mathf.Sin(ph) * 0.8f + 0.5f,
                                    Mathf.Sin(th) * Mathf.Cos(ph))
                        * speed * (0.4f + (float)Instance._rng.NextDouble() * 0.8f);
                Instance.Spawn(pos, v, life * (0.7f + (float)Instance._rng.NextDouble() * 0.6f),
                    size, size * 0.2f, col, col, 2.5f, 1.5f);
            }
        }

        /* Tebasan pedang: kipas sparkle ke arah hadap + inti putih. */
        public static void Slash(Vector3 pos, int combo)
        {
            if (Instance == null) return;
            var cols = new[]
            {
                new Color(0.65f, 0.95f, 0.90f), new Color(0.75f, 0.90f, 1.0f),
                new Color(1.0f, 0.92f, 0.70f),
            };
            var c = cols[combo % cols.Length];
            Burst(pos, Color.white, 4, 1.5f, 0.35f, 0.5f);
            Burst(pos, c, 12, 4.5f, 0.5f, 0.28f);
        }

        public static void Dash(Vector3 pos)
        {
            if (Instance == null) return;
            Burst(pos, new Color(0.7f, 0.95f, 0.9f), 8, 2f, 0.4f, 0.25f);
        }

        public static void Land(Vector3 pos)
        {
            if (Instance == null) return;
            Burst(pos, new Color(0.85f, 0.78f, 0.62f), 10, 2.5f, 0.5f, 0.3f);
        }

        /* Skill elemental (E): ledakan cincin teal + pilar. */
        public static void Skill(Vector3 pos)
        {
            if (Instance == null) return;
            var c = new Color(0.45f, 0.95f, 0.82f);
            Burst(pos, c, 30, 6f, 0.7f, 0.35f);
            Burst(pos + Vector3.up * 0.5f, Color.white, 10, 2f, 0.5f, 0.5f);
            for (var i = 0; i < 12; i++)
                Instance.Spawn(pos + new Vector3(0f, 0.2f, 0f),
                    new Vector3(0f, 5f + i * 0.2f, 0f), 0.8f, 0.3f, 0.05f,
                    c, c, -2f, 1f);
        }

        /* Ultimate (Q): badai sparkle besar. */
        public static void Ult(Vector3 pos)
        {
            if (Instance == null) return;
            var c1 = new Color(0.55f, 1f, 0.88f);
            var c2 = new Color(1f, 0.9f, 0.6f);
            Burst(pos, c1, 60, 8f, 1.0f, 0.4f);
            Burst(pos + Vector3.up, c2, 25, 4f, 1.2f, 0.55f);
            Burst(pos, Color.white, 15, 2f, 0.8f, 0.8f);
        }

        public static void SetAura(Transform target, Color col, float rate = 14f)
        {
            if (Instance == null) return;
            Instance._aura = new Emitter
                { Target = target, Col = col, Rate = rate, Acc = 0f, On = target != null };
        }

        public static void ClearAura()
        {
            if (Instance == null) return;
            Instance._aura.On = false;
        }
    }
}
