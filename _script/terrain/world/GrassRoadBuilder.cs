////////////////////////////////////////////////////////////////////////////////////////////
/// GrassRoadBuilder: dekorasi "padang pedesaan" per-chunk, murni dari kode (tanpa editor).
/// - Rumput: MultiMesh (sekali draw call per chunk), bilah kecil->normal, warna
///   gradasi hijau muda -> hijau gelap yang acak per rumpun. Hanya tumbuh di area
///   hijau (landai & ketinggian sedang), bukan di air/tebing/jalan.
/// - Jalan tanah: pita polygon mengikuti fungsi sinus global (berkelok-kelok
///   konsisten antar chunk), menempel permukaan terrain, tepi pita transparan
///   (gradasi membaur ke rumput) dengan warna cokelat tanah.
////////////////////////////////////////////////////////////////////////////////////////////

using Godot;

namespace Bouncerock.Terrain
{
	public static class GrassRoadBuilder
	{
		// ---- Konstanta ruang chunk (mengikuti mapping dekor di TerrainChunk) ----
		const float HalfSpan = 25f;          // setengah lebar chunk (world unit)
		const float GridMax = 49f;           // indeks heightmap 0..49

		// ---- Rumput ----------------------------------------------------------------
		const int GrassAttempts = 170;       // percobaan titik acak per chunk
		const int GrassMaxInstances = 120;   // batas atas rumpun per chunk (mobile-safe)
		const float GrassMinAltitude = 1.2f; // jangan tumbuh di pantai/air
		const float GrassMaxAltitude = 13f;  // jangan tumbuh di gundukan tinggi
		const float GrassMaxSlope = 1.5f;    // beda tinggi tetangga maksimum

		// ---- Jalan tanah -------------------------------------------------------------
		const float RoadHalfWidth = 0.9f;    // setengah lebar bagian padat (cokelat penuh)
		const float RoadFadeWidth = 0.9f;    // pita gradasi menuju rumput di tiap sisi
		const float RoadStepZ = 2.0f;        // resolusi segmen sepanjang Z
		const float RoadYOffset = 0.07f;     // angkat sedikit agar tak z-fighting
		const float RoadSkipMargin = 3.0f;   // margin deteksi di luar tepi chunk

		static ArrayMesh _bladeMesh;         // mesh bilah rumput (dipakai bersama semua chunk)
		static StandardMaterial3D _grassMaterial;
		static StandardMaterial3D _roadMaterial;

		// Fungsi garis tengah jalan (koordinat dunia): dua sinus frekuensi rendah
		// supaya berkelok pelan & deterministik konsisten antar chunk.
		static float RoadCenterX(float worldZ)
		{
			return 14f * Mathf.Sin(worldZ * 0.011f) + 7f * Mathf.Sin(worldZ * 0.023f + 1.7f);
		}

		public static void BuildForChunk(TerrainChunk chunk, Node3D parent, Vector3 chunkOrigin)
		{
			BuildGrass(chunk, parent, chunkOrigin);
			BuildRoad(chunk, parent, chunkOrigin);
		}

		// -------------------------------------------------------------------
		// RUMPUT
		// -------------------------------------------------------------------
		static void BuildGrass(TerrainChunk chunk, Node3D parent, Vector3 chunkOrigin)
		{
			EnsureGrassResources();

			var rng = new RandomNumberGenerator();
			int gx0 = Mathf.RoundToInt(chunk.GridPosition.X);
			int gz0 = Mathf.RoundToInt(chunk.GridPosition.Y);
			rng.Seed = (ulong)((gx0 * 73856093) ^ (gz0 * 19349663) ^ 0x5eed) & 0x7fffffff;

			var road = new RoadSampler();
			var mm = new MultiMesh
			{
				TransformFormat = MultiMesh.TransformFormatEnum.Transform3D,
				UseColors = true,
				Mesh = _bladeMesh
			};

			int accepted = 0;
			// Array sementara; MultiMesh butuh InstanceCount final, jadi kumpulkan dulu.
			var transforms = new System.Collections.Generic.List<Transform3D>(GrassMaxInstances);
			var colors = new System.Collections.Generic.List<Color>(GrassMaxInstances);

			for (int i = 0; i < GrassAttempts && accepted < GrassMaxInstances; i++)
			{
				float gx = rng.RandfRange(1f, GridMax - 1f);
				float gz = rng.RandfRange(1f, GridMax - 1f);
				float h = chunk.GetHeightAtChunkMapLocation(new Vector2(gx, gz));
				if (h < GrassMinAltitude || h > GrassMaxAltitude) continue;

				// Lereng: tolak titik curam (tebing/bibir gundukan).
				float hx = chunk.GetHeightAtChunkMapLocation(new Vector2(gx + 1f, gz));
				float hz = chunk.GetHeightAtChunkMapLocation(new Vector2(gx, gz + 1f));
				if (Mathf.Abs(hx - h) + Mathf.Abs(hz - h) > GrassMaxSlope) continue;

				// Posisi lokal mengikuti mapping dekor chunk: loc = (g.X-25, h, 25-g.Y)
				Vector3 local = new Vector3(gx - HalfSpan, h, HalfSpan - gz);

				// Jangan tumbuh di atas jalan tanah.
				Vector3 world = chunkOrigin + local;
				if (road.DistanceToCenter(world.Z, out float roadX) && Mathf.Abs(world.X - roadX) < RoadHalfWidth + 0.4f)
					continue;

				// Skala acak: dari rumpun kecil sampai ukuran normal.
				float s = rng.RandfRange(0.45f, 1.0f);
				float yaw = rng.Randf() * Mathf.Tau;
				var basis = new Basis(Vector3.Up, yaw).Scaled(new Vector3(s, s * rng.RandfRange(0.8f, 1.1f), s));
				transforms.Add(new Transform3D(basis, local));

				// Gradasi hue: hijau muda kekuningan <-> hijau standar (random per rumpun,
				// digabung gradasi gelap->terang di vertex warna mesh-nya).
				float t = rng.Randf();
				colors.Add(new Color(
					Mathf.Lerp(0.75f, 1.0f, t),
					1.0f,
					Mathf.Lerp(0.55f, 0.85f, 1f - t)));
				accepted++;
			}

			if (accepted == 0) return;

			mm.InstanceCount = accepted;
			for (int i = 0; i < accepted; i++)
			{
				mm.SetInstanceTransform(i, transforms[i]);
				mm.SetInstanceColor(i, colors[i]);
			}

			var mmi = new MultiMeshInstance3D
			{
				Name = "GrassScatter",
				Multimesh = mm,
				CastShadow = GeometryInstance3D.ShadowCastingSetting.Off,
				MaterialOverride = _grassMaterial
			};
			parent.AddChild(mmi);
		}

		static void EnsureGrassResources()
		{
			if (_bladeMesh != null) return;

			// 3 bilah segitiga pipih bersilang; warna vertex: pangkal gelap -> ujung
			// hijau muda (gradasi vertikal) lalu di-tint per-rumpun oleh warna instans.
			var verts = new Vector3[9];
			var cols = new Color[9];
			Color cDark = new Color(0.10f, 0.26f, 0.07f);
			Color cTip = new Color(0.55f, 0.85f, 0.30f);
			for (int b = 0; b < 3; b++)
			{
				float yaw = Mathf.Pi / 3f * b;
				Vector3 right = new Vector3(Mathf.Cos(yaw), 0, Mathf.Sin(yaw)) * 0.11f;
				float hgt = 0.38f + 0.12f * b;
				verts[b * 3 + 0] = -right;
				verts[b * 3 + 1] = right;
				verts[b * 3 + 2] = new Vector3(0, hgt, 0);
				cols[b * 3 + 0] = cDark;
				cols[b * 3 + 1] = cDark;
				cols[b * 3 + 2] = cTip;
			}

			var arr = new Godot.Collections.Array();
			arr.Resize((int)Mesh.ArrayType.Max);
			arr[(int)Mesh.ArrayType.Vertex] = verts;
			arr[(int)Mesh.ArrayType.Color] = cols;

			_bladeMesh = new ArrayMesh();
			_bladeMesh.AddSurfaceFromArrays(Mesh.PrimitiveType.Triangles, arr);

			_grassMaterial = new StandardMaterial3D
			{
				VertexColorUseAsAlbedo = true,
				CullMode = BaseMaterial3D.CullModeEnum.Disabled,
				Roughness = 1f,
				SpecularMode = BaseMaterial3D.SpecularModeEnum.Disabled
			};

			_roadMaterial = new StandardMaterial3D
			{
				VertexColorUseAsAlbedo = true,
				Transparency = BaseMaterial3D.TransparencyEnum.Alpha,
				CullMode = BaseMaterial3D.CullModeEnum.Disabled,
				Roughness = 1f,
				SpecularMode = BaseMaterial3D.SpecularModeEnum.Disabled
			};
		}

		// -------------------------------------------------------------------
		// JALAN TANAH
		// -------------------------------------------------------------------
		class RoadSampler
		{
			public bool DistanceToCenter(float worldZ, out float roadX)
			{
				roadX = RoadCenterX(worldZ);
				return true;
			}
		}

		static void BuildRoad(TerrainChunk chunk, Node3D parent, Vector3 chunkOrigin)
		{
			EnsureGrassResources();

			float zMin = chunkOrigin.Z - HalfSpan - RoadSkipMargin;
			float zMax = chunkOrigin.Z + HalfSpan + RoadSkipMargin;

			// Cek cepat: apakah jalan melintasi rentang X chunk ini?
			float minDist = float.MaxValue;
			for (float z = zMin; z <= zMax; z += 6f)
				minDist = Mathf.Min(minDist, Mathf.Abs(RoadCenterX(z) - chunkOrigin.X));
			if (minDist > HalfSpan + RoadHalfWidth + RoadFadeWidth + RoadSkipMargin) return;

			// 4 verteks per baris: fadeKiri | padatKiri | padatKanan | fadeKanan
			// (tepi alpha 0 -> gradasi menyatu dengan rumput, tengah cokelat tanah)
			var verts = new System.Collections.Generic.List<Vector3>();
			var cols = new System.Collections.Generic.List<Color>();
			var uvs = new System.Collections.Generic.List<Vector2>();
			var indices = new System.Collections.Generic.List<int>();

			Color cCenter = new Color(0.42f, 0.30f, 0.17f, 1f);   // tanah basah
			Color cFade = new Color(0.38f, 0.33f, 0.18f, 0f);     // gradasi ke hijau
			float lastH = 2f;
			int prevRowStart = -1;

			for (float wz = zMin; wz <= zMax; wz += RoadStepZ)
			{
				float cx = RoadCenterX(wz);
				if (Mathf.Abs(cx - chunkOrigin.X) > HalfSpan + RoadHalfWidth + RoadFadeWidth + 1f)
					continue;

				// Turunan numerik untuk arah tegak lurus jalan.
				float d = (RoadCenterX(wz + 1f) - RoadCenterX(wz - 1f)) * 0.5f;
				var normal = new Vector2(1f, -d).Normalized();

				float hw = RoadHalfWidth + RoadFadeWidth;
				float[] offs = { -hw, -RoadHalfWidth, RoadHalfWidth, hw };
				Color[] vcol = { cFade, cCenter, cCenter, cFade };
				float[] us = { 0f, 0.3f, 0.7f, 1f };

				int baseIdx = verts.Count;
				for (int k = 0; k < 4; k++)
				{
					float wx = cx + normal.X * offs[k];
					float wzz = wz + normal.Y * offs[k];
					lastH = new RoadSamplerHeight(chunk, chunkOrigin, lastH, wx, wzz).Value;
					verts.Add(new Vector3(wx - chunkOrigin.X, lastH + RoadYOffset, wzz - chunkOrigin.Z));
					cols.Add(vcol[k]);
					uvs.Add(new Vector2(us[k], wz * 0.25f));
				}
				if (prevRowStart == baseIdx - 4)
				{
					for (int k = 0; k < 3; k++)
					{
						indices.Add(baseIdx - 4 + k); indices.Add(baseIdx + k); indices.Add(baseIdx - 4 + k + 1);
						indices.Add(baseIdx - 4 + k + 1); indices.Add(baseIdx + k); indices.Add(baseIdx + k + 1);
					}
				}
				prevRowStart = baseIdx;
			}

			if (indices.Count < 6) return;

			var arr = new Godot.Collections.Array();
			arr.Resize((int)Mesh.ArrayType.Max);
			arr[(int)Mesh.ArrayType.Vertex] = verts.ToArray();
			arr[(int)Mesh.ArrayType.Color] = cols.ToArray();
			arr[(int)Mesh.ArrayType.TexUV] = uvs.ToArray();
			arr[(int)Mesh.ArrayType.Index] = indices.ToArray();

			var mesh = new ArrayMesh();
			mesh.AddSurfaceFromArrays(Mesh.PrimitiveType.Triangles, arr);

			var mi = new MeshInstance3D
			{
				Name = "DirtRoad",
				Mesh = mesh,
				CastShadow = GeometryInstance3D.ShadowCastingSetting.Off,
				MaterialOverride = _roadMaterial,
				Transparency = 0.02f // angkat prioritas kedalaman sedikit, anti z-fight pada lereng
			};
			parent.AddChild(mi);
		}

		// Helper ketinggian dengan memori garis sebelumnya (jalan tetap halus
		// mengikuti gelombang padang, tidak mengambang/tenggelam).
		struct RoadSamplerHeight
		{
			public readonly float Value;
			public RoadSamplerHeight(TerrainChunk chunk, Vector3 origin, float fallback, float wx, float wz)
			{
				float localX = wx - origin.X;
				float localZ = wz - origin.Z;
				float gx = Mathf.Clamp(localX + HalfSpan, 0f, GridMax);
				float gz = Mathf.Clamp(HalfSpan - localZ, 0f, GridMax);
				float h = chunk.GetHeightAtChunkMapLocation(new Vector2(gx, gz));
				Value = h < -100f ? fallback : h;
			}
		}
	}
}
