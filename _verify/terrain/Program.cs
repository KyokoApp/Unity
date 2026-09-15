using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using RPG.Core;

class P
{
    /* Persentil dari sampel terurut. Dipakai supaya angka di TAHAP-3.md
       bisa direproduksi, bukan dikutip dari ingatan. */
    static double Pct(List<double> sorted, double p)
    {
        if (sorted.Count == 0) return double.NaN;
        var i = (sorted.Count - 1) * p;
        var lo = (int)Math.Floor(i); var hi = Math.Min(lo + 1, sorted.Count - 1);
        return sorted[lo] + (sorted[hi] - sorted[lo]) * (i - lo);
    }

    static void Main()
    {
        // ============================================================
        // 0. SURVEI DUNIA — sumber semua ambang di TerrainSurface.cs.
        //    Grid 301x301 = 90.601 sampel tiap 10 m, mencakup seluruh
        //    WorldSize 3.000 m.
        // ============================================================
        Console.WriteLine("=== SURVEI DUNIA (grid 301x301, langkah 10 m) ===");
        var hs = new List<double>(); var gs = new List<double>();
        int below = 0, total = 0;
        for (var i = 0; i <= 300; i++)
        for (var j = 0; j <= 300; j++)
        {
            var x = -1500.0 + i * 10; var z = -1500.0 + j * 10;
            var h = WorldData.TerrainH(x, z);
            hs.Add(h); total++;
            if (h < WorldData.WaterLevel) below++;
            gs.Add(TerrainSurface.GradientAt(x, z));
        }
        hs.Sort(); gs.Sort();
        Console.WriteLine($"  tinggi  : min {hs[0]:F1}  maks {hs[hs.Count-1]:F1}  rata2 {hs.Average():F1} m");
        Console.WriteLine($"  persentil tinggi: p1={Pct(hs,.01):F1} p5={Pct(hs,.05):F1} p25={Pct(hs,.25):F1} " +
                          $"p50={Pct(hs,.50):F1} p75={Pct(hs,.75):F1} p95={Pct(hs,.95):F1} p99={Pct(hs,.99):F1}");
        Console.WriteLine($"  di bawah air: {100.0*below/total:F2}% dari {total:N0} sampel");
        Console.WriteLine($"  persentil |gradien|: p50={Pct(gs,.50):F3} p75={Pct(gs,.75):F3} p90={Pct(gs,.90):F3} " +
                          $"({Math.Atan(Pct(gs,.90))*180/Math.PI:F1} deg) p95={Pct(gs,.95):F3} " +
                          $"({Math.Atan(Pct(gs,.95))*180/Math.PI:F1} deg) p99={Pct(gs,.99):F3} " +
                          $"({Math.Atan(Pct(gs,.99))*180/Math.PI:F1} deg) maks={gs[gs.Count-1]:F3}");
        Console.WriteLine($"  -> TerrainSurface.RockStart=0.35 ({Math.Atan(0.35)*180/Math.PI:F0} deg, antara p75 dan p90)");
        Console.WriteLine($"  -> TerrainSurface.RockFull =0.95 (= p95 terukur)");

        Console.WriteLine("\n=== TINGGI PER REGION (sampel radius 400 m di sekitar pusat region) ===");
        foreach (var r in WorldData.Regions)
        {
            double lo = 1e9, hi = -1e9;
            for (var a = 0; a < 360; a += 3)
            for (var rad = 0; rad <= 400; rad += 20)
            {
                var x = r.X + rad * Math.Cos(a * Math.PI / 180);
                var z = r.Z + rad * Math.Sin(a * Math.PI / 180);
                if (Math.Abs(x) > 1500 || Math.Abs(z) > 1500) continue;
                var h = WorldData.TerrainH(x, z);
                if (h < lo) lo = h; if (h > hi) hi = h;
            }
            Console.WriteLine($"  {r.Id,-10} ({r.X,5},{r.Z,5})  {lo,6:F1} .. {hi,6:F1} m");
        }
        Console.WriteLine($"  -> TerrainSurface.SnowStart=150 m: di antara p95 ({Pct(hs,.95):F0}) dan p99 ({Pct(hs,.99):F0})");

        Console.WriteLine("\n=== RENCANA CHUNK (WorldData.ChunkPlan) ===");
        foreach (var rad in new[]{1,2,3})
        {
            var plan = WorldData.ChunkPlan(0, 0, rad);
            var span = (2 * rad + 1) * WorldData.ChunkSize;
            Console.WriteLine($"  radius {rad}: {plan.Count,2} chunk, jangkauan {span:F0} m, " +
                              $"{plan.Count(c => c.Near)} di antaranya Near (radius<=1)");
        }
        // berapa chunk yang benar-benar ada di dunia -- batas ChunkPlan memakai
        // tx*ChunkSize < WorldSize/2, jadi rentangnya TIDAK simetris
        int minI = int.MaxValue, maxI = int.MinValue, valid = 0;
        for (var t = -20; t <= 20; t++)
        {
            if (t * WorldData.ChunkSize >= WorldData.WorldSize / 2 ||
                (t + 1) * WorldData.ChunkSize <= -WorldData.WorldSize / 2) continue;
            valid++; if (t < minI) minI = t; if (t > maxI) maxI = t;
        }
        Console.WriteLine($"  indeks chunk valid: [{minI}..{maxI}] = {valid} nilai per sumbu -> {valid*valid} chunk total");
        Console.WriteLine($"  (asimetris: chunk {minI} berakhir di {minI*WorldData.ChunkSize+WorldData.ChunkSize} > -1500, " +
                          $"sedangkan chunk {maxI+1} mulai di {(maxI+1)*WorldData.ChunkSize} >= 1500)");

        // --- 1. chunk mana yang punya salju / air / batu, untuk bahan tes ---
        Console.WriteLine("\n=== KOMPOSISI CHUNK (quads=32) ===");
        Console.WriteLine("chunk            minH    maxH   air%   batu%  salju% jalan%");
        foreach (var (cx,cz) in new[]{(0,0),(0,-6),(-3,-3),(3,3),(-4,4),(0,-5),(2,-5)})
        {
            var m = TerrainMesh.Build(cx, cz);
            if (m == null) { Console.WriteLine($"({cx},{cz}) di luar dunia"); continue; }
            double minH=1e9, maxH=-1e9; int water=0,rock=0,snow=0,road=0;
            var n = m.Quads+1;
            for (var v=0; v<m.VertexCount; v++)
            {
                var y = m.Vertices[v*3+1]; var x = m.Vertices[v*3+0]; var z = m.Vertices[v*3+2];
                if (y<minH) minH=y; if (y>maxH) maxH=y;
                if (y < WorldData.WaterLevel) water++;
                var g = TerrainSurface.GradientAt(x,z);
                if (TerrainSurface.RockAmount(g) > .5) rock++;
                if (TerrainSurface.SnowAmount(y,g) > .5) snow++;
                if (TerrainSurface.RoadAmount(x,z) > .5) road++;
            }
            var t = m.VertexCount/100.0;
            Console.WriteLine($"({cx,3},{cz,3})  {minH,7:F1} {maxH,7:F1}  {water/t,5:F1}  {rock/t,5:F1}  {snow/t,5:F1}  {road/t,5:F1}");
        }

        // --- 2. kecepatan build ---
        Console.WriteLine("\n=== WAKTU BUILD ===");
        foreach (var q in new[]{16,32,64})
        {
            var sw = Stopwatch.StartNew();
            var plan = WorldData.ChunkPlan(0,0,2);
            var built = 0; long verts = 0, tris = 0;
            foreach (var c in plan) { var m = TerrainMesh.Build(c.Cx,c.Cz,q); if (m!=null){built++;verts+=m.VertexCount;tris+=m.TriangleCount;} }
            sw.Stop();
            Console.WriteLine($"  quads={q,3}: {built} chunk, {verts:N0} verteks, {tris:N0} segitiga, {sw.Elapsed.TotalMilliseconds,8:F1} ms total  ({sw.Elapsed.TotalMilliseconds/built:F2} ms/chunk)");
        }

        // --- 3. retakan antar chunk: harus NOL bit ---
        Console.WriteLine("\n=== UJI RETAKAN (harus 0 selisih bit) ===");
        int worst = 0; double worstDiff = 0;
        for (var q=8; q<=32; q*=2)
        {
            var A = TerrainMesh.Build(0,0,q); var B = TerrainMesh.Build(1,0,q); var C = TerrainMesh.Build(0,1,q);
            var n = q+1; double diff=0; int bad=0;
            for (var j=0;j<n;j++)   // tepi timur A vs tepi barat B
            {
                var va=(j*n+q)*3; var vb=(j*n+0)*3;
                for (var k=0;k<3;k++){ var d=Math.Abs(A.Vertices[va+k]-B.Vertices[vb+k]); if(d>0){bad++;} if(d>diff)diff=d; }
            }
            for (var i=0;i<n;i++)   // tepi selatan A vs tepi utara C
            {
                var va=(q*n+i)*3; var vb=(0*n+i)*3;
                for (var k=0;k<3;k++){ var d=Math.Abs(A.Vertices[va+k]-C.Vertices[vb+k]); if(d>0){bad++;} if(d>diff)diff=d; }
            }
            Console.WriteLine($"  quads={q,3}: komponen beda = {bad}, selisih maks = {diff}");
            if (bad>worst) worst=bad; if (diff>worstDiff) worstDiff=diff;
        }
        Console.WriteLine(worst==0 ? "  -> TIDAK ADA RETAKAN (bit-identik)" : $"  -> RETAK! {worst} komponen beda");

        // --- 4. validasi winding: normal segitiga harus +Y ---
        Console.WriteLine("\n=== WINDING (cross(v1-v0,v2-v0).y harus > 0) ===");
        var m2 = TerrainMesh.Build(0,0,16);
        int neg=0; double minY=1e9;
        for (var t=0;t<m2.Triangles.Length;t+=3)
        {
            var a=m2.Triangles[t]*3; var b=m2.Triangles[t+1]*3; var c=m2.Triangles[t+2]*3;
            double ux=m2.Vertices[b]-m2.Vertices[a], uy=m2.Vertices[b+1]-m2.Vertices[a+1], uz=m2.Vertices[b+2]-m2.Vertices[a+2];
            double vx=m2.Vertices[c]-m2.Vertices[a], vy=m2.Vertices[c+1]-m2.Vertices[a+1], vz=m2.Vertices[c+2]-m2.Vertices[a+2];
            var ny = uz*vx - ux*vz;
            if (ny<=0) neg++;
            var l=Math.Sqrt((uy*vz-uz*vy)*(uy*vz-uz*vy)+ny*ny+(ux*vy-uy*vx)*(ux*vy-uy*vx));
            if (l>0 && ny/l<minY) minY=ny/l;
        }
        Console.WriteLine($"  segitiga menghadap bawah: {neg} dari {m2.TriangleCount}   min(normalized ny) = {minY:F6}");

        // --- 5. RoadInfo di titik referensi untuk tes ---
        Console.WriteLine("\n=== TITIK REFERENSI UNTUK TES ===");
        foreach (var (x,z) in new[]{(0.0,0.0),(750.0,750.0),(-807.0,-808.0),(400.0,0.0)})
        {
            var ri = WorldData.RoadInfo(x,z);
            Console.WriteLine($"  ({x},{z}) h={WorldData.TerrainH(x,z):F2} edge={ri.Edge:F2} halfWidth={ri.HalfWidth} roadAmount={TerrainSurface.RoadAmount(x,z):F4}");
        }
    }
}
