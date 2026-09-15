using System;

namespace RPG.Core
{
    /* ============================================================
       TERRAIN MESH — pembuat grid chunk dari WorldData.TerrainH().

       PURE: keluarannya array float/int polos, bukan UnityEngine.Mesh,
       jadi bisa dibuat dan dites tanpa Unity (RPG.Core tetap
       noEngineReferences: true). Konversi ke Mesh terjadi di
       RPG.Runtime/TerrainChunkStreamer.cs.

       DUA sifat yang wajib dijaga, dan keduanya ada tesnya:

       1. TIDAK ADA RETAKAN antar chunk.
          Chunk (cx,cz) verteks i=quads berada di x = (cx+1)*ChunkSize,
          persis sama dengan chunk (cx+1,cz) verteks i=0. Karena
          TerrainH() fungsi murni dari (x,z), kedua masukan itu IDENTIK
          bit-per-bit, jadi tingginya identik juga. Ini bukan kebetulan
          yang perlu dijaga — ini konsekuensi dari tidak adanya state.
          Konsekuensinya: resolusi seragam di semua chunk. LOD akan
          menimbulkan retakan dan baru dikerjakan di Tahap 7 bersama
          tier kualitas (lihat TAHAP-3.md).

       2. NORMAL TIDAK BOLEH BERJAHIT.
          Normal dihitung dari selisih terhingga TerrainH, BUKAN dari
          cross-product segitiga di mesh. Kalau dari mesh, verteks di
          perbatasan chunk tidak punya tetangga lintas chunk sehingga
          normalnya beda -> terlihat garis terang/gelap tiap 256 m.
          Dari TerrainH, normalnya fungsi kontinu di seluruh dunia.

       Urutan segitiga: Unity memakai winding SEARAH JARUM JAM untuk
       muka depan, dan RecalculateNormals memakai cross(v1-v0, v2-v0).
       Untuk tanah yang normalnya harus +Y, urutannya (A, C, B) lalu
       (C, D, B) dengan A=(i,j) B=(i+1,j) C=(i,j+1) D=(i+1,j+1).
       Tes Winding_MenghasilkanNormalKeAtas mengunci ini.
       ============================================================ */
    public sealed class ChunkMesh
    {
        public int Cx, Cz;
        public int Quads;
        public double OriginX, OriginZ;      // sudut kiri-atas chunk dalam meter dunia
        public double Step;                  // jarak antar verteks

        public float[] Vertices;             // 3 per verteks  (x, y, z)
        public float[] Normals;              // 3 per verteks
        public float[] Colors;               // 4 per verteks  (r, g, b, a)
        public float[] UVs;                  // 2 per verteks  (0..1 di dalam chunk)
        public int[]   Triangles;

        public int VertexCount => (Quads + 1) * (Quads + 1);
        public int TriangleCount => Quads * Quads * 2;
    }

    public static class TerrainMesh
    {
        /* 32 quad = 8 m per segitiga pada ChunkSize 256 m.

           Cukup halus? Ya, dan ada angkanya: komponen berfrekuensi tertinggi
           di TerrainH adalah `12*sin(x*.012)*cos(z*.01)` dengan panjang
           gelombang 2*pi/0.012 = 524 m. Sampling 8 m berarti ~65 sampel per
           gelombang — jauh di atas Nyquist. Menurunkan ke 16 quad (16 m)
           masih 32 sampel per gelombang dan memangkas verteks 4x; itu
           kandidat tier "low" di Tahap 7. */
        public const int DefaultQuads = 32;

        /* Batas atas yang aman. 64 quad = 4 m, 4.225 verteks per chunk. */
        public const int MaxQuads = 64;

        public static bool ChunkInWorld(int cx, int cz)
        {
            var s = WorldData.ChunkSize;
            return !(cx * s >= WorldData.WorldSize / 2 || (cx + 1) * s <= -WorldData.WorldSize / 2 ||
                     cz * s >= WorldData.WorldSize / 2 || (cz + 1) * s <= -WorldData.WorldSize / 2);
        }

        public static int ChunkIndex(double worldCoord)
            => (int)Math.Floor(worldCoord / WorldData.ChunkSize);

        /* Bangun satu chunk. Mengembalikan null kalau chunk di luar dunia —
           pemanggil tidak perlu mengecek batas sendiri. */
        public static ChunkMesh Build(int cx, int cz, int quads = DefaultQuads)
        {
            if (quads < 1 || quads > MaxQuads)
                throw new ArgumentOutOfRangeException(nameof(quads),
                    $"quads harus 1..{MaxQuads}, dapat {quads}");
            if (!ChunkInWorld(cx, cz)) return null;

            var size = WorldData.ChunkSize;
            var step = size / quads;
            var ox = cx * size;
            var oz = cz * size;
            var n = quads + 1;

            var m = new ChunkMesh
            {
                Cx = cx, Cz = cz, Quads = quads,
                OriginX = ox, OriginZ = oz, Step = step,
                Vertices  = new float[n * n * 3],
                Normals   = new float[n * n * 3],
                Colors    = new float[n * n * 4],
                UVs       = new float[n * n * 2],
                Triangles = new int[quads * quads * 6],
            };

            var e = TerrainSurface.GradientEpsilon;

            for (var j = 0; j < n; j++)
            for (var i = 0; i < n; i++)
            {
                var x = ox + i * step;
                var z = oz + j * step;
                var h = WorldData.TerrainH(x, z);

                /* Gradien lewat selisih terhingga pusat, epsilon sama dengan
                   yang dipakai mengukur ambang di TerrainSurface. Sengaja
                   TIDAK diambil dari grid mesh: grid 8 m melembutkan transisi
                   `Smooth(30,65,...)` di tepi sungai dan menggeser fraksi
                   batu dari yang sudah diukur. */
                var dx = (WorldData.TerrainH(x + e, z) - WorldData.TerrainH(x - e, z)) / (2 * e);
                var dz = (WorldData.TerrainH(x, z + e) - WorldData.TerrainH(x, z - e)) / (2 * e);
                var grad = Math.Sqrt(dx * dx + dz * dz);

                var vi = (j * n + i);

                m.Vertices[vi * 3 + 0] = (float)x;
                m.Vertices[vi * 3 + 1] = (float)h;
                m.Vertices[vi * 3 + 2] = (float)z;

                // normal permukaan y = h(x,z)  ->  normalize(-dh/dx, 1, -dh/dz)
                var nx = -dx; var ny = 1.0; var nz = -dz;
                var inv = 1.0 / Math.Sqrt(nx * nx + ny * ny + nz * nz);
                m.Normals[vi * 3 + 0] = (float)(nx * inv);
                m.Normals[vi * 3 + 1] = (float)(ny * inv);
                m.Normals[vi * 3 + 2] = (float)(nz * inv);

                var c = TerrainSurface.ColorAt(x, z, h, grad, WorldData.TerrainColor(x, z));
                m.Colors[vi * 4 + 0] = (float)c[0];
                m.Colors[vi * 4 + 1] = (float)c[1];
                m.Colors[vi * 4 + 2] = (float)c[2];
                m.Colors[vi * 4 + 3] = 1f;

                m.UVs[vi * 2 + 0] = (float)i / quads;
                m.UVs[vi * 2 + 1] = (float)j / quads;
            }

            var t = 0;
            for (var j = 0; j < quads; j++)
            for (var i = 0; i < quads; i++)
            {
                var a = j * n + i;
                var b = j * n + (i + 1);
                var c = (j + 1) * n + i;
                var d = (j + 1) * n + (i + 1);

                m.Triangles[t++] = a; m.Triangles[t++] = c; m.Triangles[t++] = b;
                m.Triangles[t++] = c; m.Triangles[t++] = d; m.Triangles[t++] = b;
            }

            return m;
        }

        /* Tinggi persis di sebuah titik dunia — dipakai CharacterMotor supaya
           karakter menempel ke permukaan yang sama dengan mesh-nya, bukan ke
           aproksimasi. Karena mesh di-sample dari fungsi yang sama, selisihnya
           hanya sebatas faceting 8 m, yang pada terrain sepanjang 524 m ini
           tidak terlihat. */
        public static double HeightAt(double x, double z) => WorldData.TerrainH(x, z);
    }
}
