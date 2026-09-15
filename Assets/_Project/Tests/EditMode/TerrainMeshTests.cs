using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Threading.Tasks;
using NUnit.Framework;
using RPG.Core;

namespace RPG.Tests
{
    /* ============================================================
       Tes TerrainMesh & TerrainSurface (Tahap 3).

       Angka-angka harapan di sini BUKAN karangan. Semuanya diukur
       dengan _verify/terrain (yang menjalankan WorldData.cs asli),
       lalu ditulis ke sini supaya terkunci. Kalau ada yang berubah,
       cari tahu kenapa — jangan perbarui angkanya diam-diam.

       Dua sifat yang paling penting dijaga:
         - Tidak ada retakan antar chunk (bit-identik di perbatasan)
         - Winding segitiga menghasilkan normal +Y (muka depan Unity)
       ============================================================ */
    [TestFixture]
    public class TerrainMeshTests
    {
        // ------------------------------------------------ batas dunia
        [Test]
        public void ChunkInWorld_SesuaiDenganFilterChunkPlan()
        {
            /* ChunkPlan sudah diuji paritas terhadap JS. Filter batas di
               TerrainMesh harus sama persis, kalau tidak streamer akan
               meminta chunk yang ChunkPlan tidak pernah berikan (atau
               sebaliknya) dan retakan muncul di tepi dunia. */
            var plan = new HashSet<(int, int)>();
            for (var cx = -8; cx <= 8; cx++)
            for (var cz = -8; cz <= 8; cz++)
                if (WorldData.ChunkPlan(cx * 256 + 128, cz * 256 + 128, 0).Count > 0)
                    plan.Add((cx, cz));

            var mismatch = 0;
            for (var cx = -8; cx <= 8; cx++)
            for (var cz = -8; cz <= 8; cz++)
            {
                var inPlan = plan.Contains((cx, cz));
                if (inPlan != TerrainMesh.ChunkInWorld(cx, cz)) mismatch++;
            }
            Assert.AreEqual(0, mismatch, "TerrainMesh.ChunkInWorld tidak cocok dengan filter ChunkPlan");
            Assert.AreEqual(144, plan.Count,
                "cx valid = [-6..5] (12 nilai) karena chunk -6 berakhir di -1280 > -1500 dan chunk 5 mulai di 1280 < 1500 -> 12x12 = 144");
        }

        [Test]
        public void Build_MengembalikanNullDiLuarDunia()
        {
            Assert.IsNull(TerrainMesh.Build(6, 0), "chunk 6 mulai di x=1536 > WorldSize/2");
            Assert.IsNull(TerrainMesh.Build(-7, 0), "chunk -7 berakhir di x=-1536 < -WorldSize/2");
            Assert.IsNotNull(TerrainMesh.Build(5, 5));
        }

        [Test]
        public void Build_MenolakQuadsDiLuarBatas()
        {
            Assert.Throws<ArgumentOutOfRangeException>(() => TerrainMesh.Build(0, 0, 0));
            Assert.Throws<ArgumentOutOfRangeException>(() => TerrainMesh.Build(0, 0, TerrainMesh.MaxQuads + 1));
        }

        // ------------------------------------------------ struktur
        [Test]
        public void Build_UkuranArrayKonsisten()
        {
            const int q = 16;
            var m = TerrainMesh.Build(0, 0, q);
            var n = q + 1;
            Assert.AreEqual(n * n, m.VertexCount);
            Assert.AreEqual(q * q * 2, m.TriangleCount);
            Assert.AreEqual(n * n * 3, m.Vertices.Length);
            Assert.AreEqual(n * n * 3, m.Normals.Length);
            Assert.AreEqual(n * n * 4, m.Colors.Length);
            Assert.AreEqual(n * n * 2, m.UVs.Length);
            Assert.AreEqual(q * q * 6, m.Triangles.Length);
            Assert.AreEqual(q * q * 6, m.Triangles.Length);
            Assert.AreEqual(WorldData.ChunkSize / q, m.Step, 1e-12);
            Assert.AreEqual(0, m.Cx); Assert.AreEqual(0, m.Cz);
        }

        [Test]
        public void Build_IsiVerteksCocokDenganWorldData()
        {
            const int q = 8;
            var cx = 2; var cz = -3;
            var m = TerrainMesh.Build(cx, cz, q);
            var step = WorldData.ChunkSize / q;
            for (var j = 0; j <= q; j++)
            for (var i = 0; i <= q; i++)
            {
                var v = (j * (q + 1) + i) * 3;
                var x = cx * WorldData.ChunkSize + i * step;
                var z = cz * WorldData.ChunkSize + j * step;
                Assert.AreEqual((float)x, m.Vertices[v + 0], 1e-4f, $"x di i={i}");
                Assert.AreEqual((float)z, m.Vertices[v + 2], 1e-4f, $"z di j={j}");
                Assert.AreEqual((float)WorldData.TerrainH(x, z), m.Vertices[v + 1], 1e-4f,
                                $"tinggi harus persis TerrainH({x},{z})");
            }
        }

        [Test]
        public void Build_IndeksDalamRentangDanTanpaSegitigaDegenerate()
        {
            var m = TerrainMesh.Build(1, 1, TerrainMesh.DefaultQuads);
            for (var t = 0; t < m.Triangles.Length; t += 3)
            {
                var a = m.Triangles[t]; var b = m.Triangles[t + 1]; var c = m.Triangles[t + 2];
                Assert.IsTrue(a >= 0 && a < m.VertexCount, $"indeks {a} di luar rentang");
                Assert.IsTrue(b >= 0 && b < m.VertexCount);
                Assert.IsTrue(c >= 0 && c < m.VertexCount);
                Assert.IsFalse(a == b || b == c || a == c, "segitiga degenerate");
            }
        }

        [Test]
        public void Build_UVdanWarnaDalamRentang()
        {
            var m = TerrainMesh.Build(-2, 4, 12);
            for (var i = 0; i < m.UVs.Length; i++)
                Assert.IsTrue(m.UVs[i] >= 0f && m.UVs[i] <= 1f, $"UV[{i}] = {m.UVs[i]}");
            for (var i = 0; i < m.Colors.Length; i++)
                Assert.IsTrue(m.Colors[i] >= 0f && m.Colors[i] <= 1f, $"Color[{i}] = {m.Colors[i]}");
            for (var v = 0; v < m.VertexCount; v++)
                Assert.AreEqual(1f, m.Colors[v * 4 + 3], "alpha harus 1 (terrain opaque)");
        }

        [Test]
        public void Build_NormalSatuanDanMenghadapAtas()
        {
            var m = TerrainMesh.Build(2, -5, TerrainMesh.DefaultQuads);
            for (var v = 0; v < m.VertexCount; v++)
            {
                var x = m.Normals[v * 3]; var y = m.Normals[v * 3 + 1]; var z = m.Normals[v * 3 + 2];
                var len = Math.Sqrt((double)x * x + (double)y * y + (double)z * z);
                Assert.AreEqual(1.0, len, 1e-4, $"normal verteks {v} tidak satuan ({len})");
                Assert.Greater(y, 0f, $"normal verteks {v} menghadap bawah");
            }
        }

        // ------------------------------------------------ SIFAT KRITIS 1
        [Test]
        public void PerbatasanChunk_BitIdentik_TidakAdaRetakan()
        {
            /* Ini tes paling penting di Tahap 3. Kalau gagal, dunia terlihat
               pecah tiap 256 m. Dicek pada beberapa resolusi dan beberapa
               pasangan chunk, termasuk yang menyeberangi x=0 dan z=0. */
            var pairs = new (int, int, int)[]
            {
                (0, 0, 8), (0, 0, 16), (0, 0, 32),
                (-1, 0, 16), (0, -1, 16), (-1, -1, 32), (3, 4, 8), (-6, 2, 16),
            };

            foreach (var (cx, cz, q) in pairs)
            {
                var a = TerrainMesh.Build(cx, cz, q);
                var east = TerrainMesh.Build(cx + 1, cz, q);
                var south = TerrainMesh.Build(cx, cz + 1, q);
                Assert.IsNotNull(a); Assert.IsNotNull(east); Assert.IsNotNull(south);

                var n = q + 1;
                for (var j = 0; j < n; j++)
                {
                    // tepi TIMUR a (i=q) vs tepi BARAT east (i=0)
                    var va = (j * n + q) * 3;
                    var vb = (j * n + 0) * 3;
                    for (var k = 0; k < 3; k++)
                        Assert.AreEqual(a.Vertices[va + k], east.Vertices[vb + k],
                            $"retak tepi timur chunk({cx},{cz}) q={q} j={j} komponen {k}");
                }
                for (var i = 0; i < n; i++)
                {
                    // tepi SELATAN a (j=q) vs tepi UTARA south (j=0)
                    var va = (q * n + i) * 3;
                    var vb = (0 * n + i) * 3;
                    for (var k = 0; k < 3; k++)
                        Assert.AreEqual(a.Vertices[va + k], south.Vertices[vb + k],
                            $"retak tepi selatan chunk({cx},{cz}) q={q} i={i} komponen {k}");
                }
            }
        }

        [Test]
        public void NormalLintasChunk_JugaIdentik()
        {
            /* Verteks sama tapi normal beda = jahitan terang/gelap tiap chunk.
               Karena normal dihitung dari TerrainH (bukan dari mesh), keduanya
               harus identik juga. */
            const int q = 16;
            var a = TerrainMesh.Build(0, 0, q);
            var b = TerrainMesh.Build(1, 0, q);
            var n = q + 1;
            for (var j = 0; j < n; j++)
            for (var k = 0; k < 3; k++)
                Assert.AreEqual(a.Normals[(j * n + q) * 3 + k], b.Normals[(j * n) * 3 + k],
                                $"normal tepi tidak cocok di j={j} komponen {k}");
        }

        // ------------------------------------------------ SIFAT KRITIS 2
        [Test]
        public void Winding_MenghasilkanNormalKeAtas()
        {
            /* Unity: muka depan = winding searah jarum jam, dan
               Mesh.RecalculateNormals memakai cross(v1-v0, v2-v0).
               Untuk tanah, komponen Y hasil cross harus POSITIF.
               Terukur di _verify/terrain: 0 dari 512 segitiga menghadap
               bawah, min(normalized ny) = 0,896. */
            var m = TerrainMesh.Build(0, 0, 16);
            var down = 0;
            var minNy = double.MaxValue;
            for (var t = 0; t < m.Triangles.Length; t += 3)
            {
                var a = m.Triangles[t] * 3; var b = m.Triangles[t + 1] * 3; var c = m.Triangles[t + 2] * 3;
                double ux = m.Vertices[b] - m.Vertices[a], uy = m.Vertices[b + 1] - m.Vertices[a + 1], uz = m.Vertices[b + 2] - m.Vertices[a + 2];
                double vx = m.Vertices[c] - m.Vertices[a], vy = m.Vertices[c + 1] - m.Vertices[a + 1], vz = m.Vertices[c + 2] - m.Vertices[a + 2];
                var nx = uy * vz - uz * vy;
                var ny = uz * vx - ux * vz;
                var nz = ux * vy - uy * vx;
                if (ny <= 0) down++;
                var len = Math.Sqrt(nx * nx + ny * ny + nz * nz);
                if (len > 0 && ny / len < minNy) minNy = ny / len;
            }
            Assert.AreEqual(0, down, "ada segitiga yang menghadap bawah — winding terbalik");
            Assert.AreEqual(0.896079, minNy, 1e-4, "min normal.y berubah dari hasil pengukuran");
        }

        [Test]
        public void Build_Deterministik()
        {
            var a = TerrainMesh.Build(1, -2, 12);
            var b = TerrainMesh.Build(1, -2, 12);
            CollectionAssert.AreEqual(a.Vertices, b.Vertices);
            CollectionAssert.AreEqual(a.Normals, b.Normals);
            CollectionAssert.AreEqual(a.Colors, b.Colors);
            CollectionAssert.AreEqual(a.Triangles, b.Triangles);
        }

        // ------------------------------------------------ isi dunia terukur
        [Test]
        public void ChunkSpawn_MemuatJalan()
        {
            /* Terukur: chunk (0,0) = 25,1% verteks ber-roadAmount > 0,5.
               Penting karena karakter mulai di (0,0) — kalau jalan tidak
               terlihat di spawn, pemain tidak tahu ada sistem jalan. */
            var m = TerrainMesh.Build(0, 0, TerrainMesh.DefaultQuads);
            var road = 0;
            for (var v = 0; v < m.VertexCount; v++)
                if (TerrainSurface.RoadAmount(m.Vertices[v * 3], m.Vertices[v * 3 + 2]) > 0.5) road++;
            var pct = road * 100.0 / m.VertexCount;
            Assert.AreEqual(25.1, pct, 1.0, $"fraksi jalan di chunk spawn = {pct:F1}% (terukur 25,1%)");
        }

        [Test]
        public void ChunkUtara_MemuatSaljuDanBatu()
        {
            /* Terukur: chunk (2,-5) maxH = 217,5 m, batu 27,0%, salju 27,7%.
               Ini satu-satunya bukti bahwa ramp pegunungan utara bekerja
               setelah diskala ke dunia 3 km — kekhawatiran yang ditulis
               eksplisit di DESAIN.md §1 ("puncak anjlok dari +282 m ke ~+40 m"). */
            var m = TerrainMesh.Build(2, -5, TerrainMesh.DefaultQuads);
            double maxH = double.MinValue;
            int rock = 0, snow = 0;
            for (var v = 0; v < m.VertexCount; v++)
            {
                var x = m.Vertices[v * 3]; var y = m.Vertices[v * 3 + 1]; var z = m.Vertices[v * 3 + 2];
                if (y > maxH) maxH = y;
                var g = TerrainSurface.GradientAt(x, z);
                if (TerrainSurface.RockAmount(g) > 0.5) rock++;
                if (TerrainSurface.SnowAmount(y, g) > 0.5) snow++;
            }
            Assert.AreEqual(217.5, maxH, 1.0, "puncak utara harus tetap ~217 m, bukan anjlok ke ~40 m");
            Assert.AreEqual(27.0, rock * 100.0 / m.VertexCount, 1.5, "fraksi batu");
            Assert.AreEqual(27.7, snow * 100.0 / m.VertexCount, 1.5, "fraksi salju");
        }

        [Test]
        public void ChunkDanau_MemuatAir()
        {
            /* Terukur: chunk (-4,4) = 32,2% verteks di bawah permukaan air,
               minH = -5,0 (dasar danau memang datar di -5 karena rumus
               `h*(1-wet) - 5*wet` di TerrainH). */
            var m = TerrainMesh.Build(-4, 4, TerrainMesh.DefaultQuads);
            int water = 0; double minH = double.MaxValue;
            for (var v = 0; v < m.VertexCount; v++)
            {
                var y = m.Vertices[v * 3 + 1];
                if (y < WorldData.WaterLevel) water++;
                if (y < minH) minH = y;
            }
            Assert.AreEqual(32.2, water * 100.0 / m.VertexCount, 1.5, "fraksi air di chunk danau");
            Assert.AreEqual(-5.0, minH, 0.5, "dasar air");
        }

        // ------------------------------------------------ TerrainSurface
        [Test]
        public void RoadAmount_SatuDiTengahJalan_NolDiLuar()
        {
            /* Terukur di _verify/terrain:
                 (0,0)      h=28,00  edge=-8,00  halfWidth=8  roadAmount=1,0000
                 (750,750)  h=47,89  edge=50,06  halfWidth=4  roadAmount=0,0000
                 (-807,-808) h=21,37 edge=-3,96  halfWidth=4  roadAmount=1,0000
                 (400,0)    h=6,96   edge=29,10  halfWidth=8  roadAmount=0,0000   */
            Assert.AreEqual(1.0, TerrainSurface.RoadAmount(0, 0), 1e-9);
            Assert.AreEqual(0.0, TerrainSurface.RoadAmount(750, 750), 1e-9);
            Assert.AreEqual(1.0, TerrainSurface.RoadAmount(-807, -808), 1e-9);
            Assert.AreEqual(0.0, TerrainSurface.RoadAmount(400, 0), 1e-9);
        }

        [Test]
        public void RockAmount_MonotonNaik()
        {
            Assert.AreEqual(0.0, TerrainSurface.RockAmount(0.0), 1e-12);
            Assert.AreEqual(0.0, TerrainSurface.RockAmount(TerrainSurface.RockStart), 1e-12);
            Assert.AreEqual(1.0, TerrainSurface.RockAmount(TerrainSurface.RockFull), 1e-12);
            Assert.AreEqual(1.0, TerrainSurface.RockAmount(10.0), 1e-12);
            Assert.Less(TerrainSurface.RockAmount(0.4), TerrainSurface.RockAmount(0.7));
            Assert.AreEqual(0.5, TerrainSurface.RockAmount((TerrainSurface.RockStart + TerrainSurface.RockFull) / 2), 1e-12,
                            "smoothstep harus tepat 0,5 di tengah");
        }

        [Test]
        public void SnowAmount_ButuhTinggiDanLerengLandai()
        {
            Assert.AreEqual(0.0, TerrainSurface.SnowAmount(100, 0.1), 1e-12, "terlalu rendah");
            Assert.AreEqual(1.0, TerrainSurface.SnowAmount(250, 0.1), 1e-12, "tinggi & landai");
            Assert.AreEqual(0.0, TerrainSurface.SnowAmount(250, 2.0), 1e-6, "tinggi tapi terjal -> salju tidak menempel");
            Assert.Less(TerrainSurface.SnowAmount(250, 0.9), TerrainSurface.SnowAmount(250, 0.2));
        }

        [Test]
        public void ColorAt_SelaluDalamRentang()
        {
            /* Sapuan seluruh dunia pada kisi kasar — mencakup danau, puncak
               bersalju, tebing berbatu, dan jalan. Tidak boleh ada NaN atau
               nilai di luar 0..1, karena itu akan muncul sebagai flicker
               magenta/hitam di layar. */
            var rng = WorldData.RandomForChunk(3, -7);
            for (var k = 0; k < 4000; k++)
            {
                var x = -1450 + 2900 * rng();
                var z = -1450 + 2900 * rng();
                var c = TerrainSurface.ColorAt(x, z);
                for (var i = 0; i < 3; i++)
                {
                    Assert.IsFalse(double.IsNaN(c[i]), $"NaN di ({x},{z})");
                    Assert.IsTrue(c[i] >= 0 && c[i] <= 1, $"warna[{i}]={c[i]} di ({x:F0},{z:F0})");
                }
            }
        }

        [Test]
        public void ColorAt_JalanBedaDariSekitarnya()
        {
            /* Warna jalan harus benar-benar terlihat, bukan menyatu dengan rumput.

               CATATAN dari tes ini: pembandingnya TIDAK boleh (60, 0). Titik itu
               masih di badan jalan — RoadInfo(60,0) memilih lajur z (Edge=-2,01)
               karena jalan lajur-0 juga membentang sepanjang z~0 dengan
               RoadZ(60,0)=60*sin(60/600)=5,99 dan half-width 8 m. Jadi yang
               dibandingkan di sini adalah dua titik yang roadAmount-nya sudah
               diukur di _verify/terrain: 1,0000 dan 0,0000. */
            Assert.AreEqual(1.0, TerrainSurface.RoadAmount(0, 0), 1e-9, "prekondisi: (0,0) di jalan");
            Assert.AreEqual(0.0, TerrainSurface.RoadAmount(400, 0), 1e-9, "prekondisi: (400,0) di luar jalan");
            var on = TerrainSurface.ColorAt(0, 0);
            var off = TerrainSurface.ColorAt(400, 0);
            var d = Math.Abs(on[0] - off[0]) + Math.Abs(on[1] - off[1]) + Math.Abs(on[2] - off[2]);
            Assert.Greater(d, 0.05, $"jalan tidak cukup kontras (delta={d:F4})");
        }

        [Test]
        public void GradientAt_NolDiTanahDatar()
        {
            /* Titik referensi terukur: (0,0) ada di badan jalan, dan TerrainH
               meratakan jalan sepenuhnya (`road = 1 - Smooth(4,42,Edge)` = 1
               saat Edge <= 4, di sini Edge = -8). Jadi gradiennya harus kecil. */
            Assert.Less(TerrainSurface.GradientAt(0, 0), 0.05,
                        "jalan harus datar — TerrainH sudah meratakannya");
        }

        // ============================================================
        // THREAD SAFETY
        //
        // TerrainChunkStreamer membangun chunk di thread latar. Seluruh
        // desain itu bertumpu pada dua klaim tentang RPG.Core:
        //   (a) Build() tidak menyentuh UnityEngine  -> dijaga COMPILER
        //       lewat noEngineReferences: true di RPG.Core.asmdef
        //   (b) RPG.Core tidak punya state statis mutable -> dijaga DI SINI
        //
        // Kalau (b) dilanggar, gejalanya bukan crash: hasilnya hanya kadang
        // beda, di satu perangkat, sekali sehari. Jadi dikunci sebagai tes.
        // ============================================================

        [Test]
        public void Core_TidakPunyaFieldStatisMutable()
        {
            /* Klaim (b) diperiksa lewat refleksi atas assembly yang BENAR-BENAR
               dikirim ke Unity, bukan salinan. Setiap field statis harus const
               (IsLiteral) atau readonly (IsInitOnly).

               Tipe buatan compiler dilewati: lambda yang di-cache menghasilkan
               field delegasi statis yang ditulis sekali dan idempoten. Itu
               bukan state dunia. */
            var asm = typeof(WorldData).Assembly;
            var pelanggaran = new List<string>();
            foreach (var t in asm.GetTypes())
            {
                if (t.IsDefined(typeof(System.Runtime.CompilerServices.CompilerGeneratedAttribute), false)) continue;
                if (t.Name.StartsWith("<>")) continue;
                foreach (var f in t.GetFields(BindingFlags.Static | BindingFlags.Public |
                                              BindingFlags.NonPublic | BindingFlags.FlattenHierarchy))
                {
                    if (f.Name.StartsWith("<>")) continue;
                    if (f.IsLiteral || f.IsInitOnly) continue;
                    pelanggaran.Add($"{t.FullName}.{f.Name}");
                }
            }
            Assert.IsEmpty(pelanggaran,
                "RPG.Core punya field statis mutable -- membangun chunk di thread latar jadi tidak aman: " +
                string.Join(", ", pelanggaran));
        }

        [Test]
        public void Build_Deterministik_DipanggilBerulangKali()
        {
            var a = TerrainMesh.Build(2, -3, 16);
            var b = TerrainMesh.Build(2, -3, 16);
            Assert.IsNotNull(a);
            CollectionAssert.AreEqual(a.Vertices, b.Vertices, "verteks beda antar pemanggilan");
            CollectionAssert.AreEqual(a.Normals,  b.Normals,  "normal beda antar pemanggilan");
            CollectionAssert.AreEqual(a.Colors,   b.Colors,   "warna beda antar pemanggilan");
            CollectionAssert.AreEqual(a.UVs,      b.UVs,      "UV beda antar pemanggilan");
            CollectionAssert.AreEqual(a.Triangles,b.Triangles,"indeks beda antar pemanggilan");
        }

        [Test]
        public void Build_AmanDiThreadBareng_HasilIdentikDenganSekuensial()
        {
            /* 25 chunk dari rencana radius 2 -- beban yang sama persis dengan
               yang dikirim streamer saat pertama kali masuk dunia. */
            var plan = WorldData.ChunkPlan(0, 0, 2)
                            .Where(c => TerrainMesh.ChunkInWorld(c.Cx, c.Cz))
                            .Select(c => (c.Cx, c.Cz)).ToList();
            Assert.AreEqual(25, plan.Count, "prekondisi: radius 2 = 25 chunk");

            const int Q = 16;
            var baseline = new ChunkMesh[plan.Count];
            for (var i = 0; i < plan.Count; i++)
                baseline[i] = TerrainMesh.Build(plan[i].Cx, plan[i].Cz, Q);

            /* Paralelisme 8 -- lebih banyak dari jumlah core HP mana pun yang
               realistis, supaya race lebih mungkin muncul kalau memang ada. */
            var bareng = new ChunkMesh[plan.Count];
            Parallel.For(0, plan.Count, new ParallelOptions { MaxDegreeOfParallelism = 8 }, i =>
            {
                bareng[i] = TerrainMesh.Build(plan[i].Cx, plan[i].Cz, Q);
            });

            for (var i = 0; i < plan.Count; i++)
            {
                var tag = $"chunk ({plan[i].Cx},{plan[i].Cz})";
                Assert.IsNotNull(bareng[i], tag + ": hasil null");
                /* Bukan AreEqual dengan toleransi: harus BIT identik. Kalau ada
                   race, selisihnya kecil dan jarang -- persis jenis bug yang
                   lolos dari perbandingan bertoleransi. */
                CollectionAssert.AreEqual(baseline[i].Vertices,  bareng[i].Vertices,  tag + ": verteks");
                CollectionAssert.AreEqual(baseline[i].Normals,   bareng[i].Normals,   tag + ": normal");
                CollectionAssert.AreEqual(baseline[i].Colors,    bareng[i].Colors,    tag + ": warna");
                CollectionAssert.AreEqual(baseline[i].UVs,       bareng[i].UVs,       tag + ": UV");
                CollectionAssert.AreEqual(baseline[i].Triangles, bareng[i].Triangles, tag + ": indeks");
            }
        }

        [Test]
        public void Build_AmanDiThreadBareng_TanpaCampurTanganAntarChunk()
        {
            /* Versi lebih agresif: semua thread membangun chunk YANG SAMA
               berulang kali. Kalau ada cache statis yang ditulis bersama,
               ini yang paling mungkin memancingnya. */
            var hasil = new ChunkMesh[64];
            Parallel.For(0, 64, new ParallelOptions { MaxDegreeOfParallelism = 8 }, i =>
            {
                hasil[i] = TerrainMesh.Build(1, 1, 16);
            });
            for (var i = 1; i < hasil.Length; i++)
                CollectionAssert.AreEqual(hasil[0].Vertices, hasil[i].Vertices,
                    $"hasil ke-{i} beda dari yang pertama");
        }
    }
}
