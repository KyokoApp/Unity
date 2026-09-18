

////////////////////////////////////////////////////////////////////////////////////////////
/// This script is part of the project "Infinite Runner", a procedural generation project
/// 
/// TerrainChunk: This script contains all the information relevant to each terrain chunk.
/// This includes heightmap, LODs, and all objects contains in the given chunk
/// ///////////////////////////////////////////////////////////////////////////////////////

using Godot;
using Bouncerock;
using System.Collections.Generic;
using Bouncerock.UI;
using System.Threading;
using System.Threading.Tasks;
using System.Security.Cryptography.X509Certificates;
using System;

namespace Bouncerock.Terrain
{
	public class TerrainChunk
	{

		//const float colliderGenerationDistanceThreshold = 5;
		//public event System.Action<TerrainChunk, bool> onVisibilityChanged;
		public Vector2 GridPosition;



		MeshInstance3D meshObject;
		public Vector2 sampleCentre;
		//Rect2 bounds;

		public Aabb Bounds;

		//LODInfo[] detailLevels;
		LODMesh[] lodMeshes;
		//int colliderLODIndex;

		public Map _map;
		bool heightMapReceived;
		public int previousLODIndex = -1;
		public int currentLODIndex = -1;
		bool hasSetCollider;

		bool hasSetMaterial = false;

		bool hasSetWater = false;
		bool hasSetDecor = false;

		bool isHidden = false;

		public bool loading = false;
		//float maxViewDst;

		//HeightMapSettings heightMapSettings;
		//Vector3 viewer;

		StaticBody3D staticBody;
		CollisionShape3D collisionShape;

		public float timer = 0;

		//public List<MeshInstance3D> DecorHelpers = new List<MeshInstance3D>();

		public bool itemsLoaded = false;
		//public List<List<WorldItem>> worldItems = new List<List<WorldItem>>();

		public SeaWater Water;

		WorldSpaceUI helper;

		public TerrainChunk(Vector2 coord, HeightMapSettings heightMapSettings, LODInfo[] detailLevels, int currentLODIndex, Node parent)
		{
			GridPosition = coord;
			//this.detailLevels = detailLevels;
			this.currentLODIndex = currentLODIndex;
			//this.heightMapSettings = heightMapSettings;
			//GD.Print("Created : " + coord + ". At location: " + coord * TerrainMeshSettings.meshWorldSize);
			sampleCentre = coord * TerrainMeshSettings.meshWorldSize / TerrainMeshSettings.meshScale;
			Vector2 position = coord * TerrainMeshSettings.meshWorldSize;

			meshObject = new MeshInstance3D();
			meshObject.Name = "Chunk[x:" + coord.X + ",y:" + coord.Y + "]";
			//parent.AddChild(meshObject);
			parent.CallDeferred("add_child", meshObject);

			meshObject.Position = new Vector3(position.X, 0, position.Y);
			Bounds = new Aabb(position.X - (meshObject.Scale.X / 2), 0, position.Y - (meshObject.Scale.Y / 2), Vector3.One * TerrainMeshSettings.meshWorldSize);
			if (TerrainManager.Instance.ShowHelpers)
			{
				MeshInstance3D line = LineDrawer.DrawLine3D(meshObject.Position, meshObject.Position + Vector3.Up * 500, Colors.Black);
				meshObject.Name = "LineHelper";
				meshObject.CallDeferred("add_child", line);
			}
			lodMeshes = new LODMesh[detailLevels.Length];

			for (int i = 0; i < detailLevels.Length; i++)
			{
				lodMeshes[i] = new LODMesh(detailLevels[i].LodLevel);
				lodMeshes[i].updateCallback += OnLODMeshReceived;
				lodMeshes[i].updateCallback += UpdateCollisionMesh;
				lodMeshes[i].updateCallback += SetMaterial;
				lodMeshes[i].updateCallback += UpdateHelpers;
			}
			//DebugUI.Instance.AddChunkData(GridPosition.ToString(), GridPosition + $"[{GridPosition}] - New chunk. ");

		}

		void UpdateDebugData()
		{
			return;
			string loadingTxt = loading?"":"(loading...)";
			string itemsLoad = "";
			if (itemsLoaded)
			{
				itemsLoad = $"Items: {_map.GetTerrainElements().Count}";
			}
			DebugUI.Instance.AddChunkData(GridPosition.ToString(), $"{GridPosition} {loadingTxt} LOD: {currentLODIndex}. Material: {hasSetMaterial}. Water: {hasSetWater}. {itemsLoad}");
		}

		/*void CreateBoundGizmo()
		{
			Color semitransparent = new Color(1,1,1,0.5f);
			MeshInstance3D GizmoHelper = LineDrawer.DrawAABB(Vector3.Zero, Bounds.Size, semitransparent);
			GizmoHelper.Name = "Gizmo Helper";
			meshObject.AddChild(GizmoHelper);
		}*/

		public Vector2 CoordToUnit()
		{
			return GridPosition / TerrainMeshSettings.chunkMeshSize;
		}

		public MeshInstance3D GetMesh()
		{
			return meshObject;
		}

		public async Task Load()
		{
			//Do I have a local save?
			UpdateDebugData();
			loading = true;
			if (TerrainManager.Instance.SaveTerrainToLocalDisk)
			{
				if (MapGenerator.MapExists("Chunk[x" + GridPosition.X + ",y" + GridPosition.Y + "].isl"))
				{
					Map savedMap = await MapGenerator.LoadMapFromUnibyteAsync("Chunk[x" + GridPosition.X + ",y" + GridPosition.Y + "]");
					await OnHeightMapReceived(savedMap);
					UpdateDebugData();
					//ThreadedDataRequester.RequestData(() => MapGenerator.LoadMapFromUnibyte("Chunk[x" + GridPosition.X + ",y" + GridPosition.Y+"]"), OnHeightMapReceived);
					loading = false;
					return;
				}
			}
			Map generatedMap = await MapGenerator.GenerateMapAsync(sampleCentre);
			if (loading)
			{
				_=OnHeightMapReceived(generatedMap);//calling the function 
			}
			loading = false;
			//GD.Print("Done loading " + GridPosition);
			UpdateDebugData();
			//GD.Print("Map " +GridPosition+ "generated, with " + generatedMap.GetTerrainElements().Count + " map elements");
			//GD.Print("has heightmap " + generatedMap.heightMap==null);
			//ThreadedDataRequester.RequestData(() => MapGenerator.GenerateMap (sampleCentre), OnHeightMapReceived);
		}

		//returns the height on the grid at given location. Location is express as local 

		/// <summary>
		/// Height at a chunk-local grid position, or TerrainMeshSettings.InvalidHeight when the
		/// position falls outside the heightmap.
		///
		/// Previously this relied on catching IndexOutOfRangeException. Using an exception for
		/// normal out-of-bounds lookups costs a lot on a phone (this is called for every entity
		/// every frame), and its sibling GetInclinationAtChunkMapLocation had no such guard at
		/// all, so it could throw.
		/// </summary>
		public float GetHeightAtChunkMapLocation(Vector2 location)
		{
			int x = Mathf.RoundToInt(location.X);
			int y = Mathf.RoundToInt(location.Y);

			if (_map?.heightMap == null) return TerrainMeshSettings.InvalidHeight;
			if (x < 0 || y < 0 || x >= _map.heightMap.GetLength(0) || y >= _map.heightMap.GetLength(1))
			{
				return TerrainMeshSettings.InvalidHeight;
			}

			return _map.heightMap[x, y];
		}

		/// <summary>
		/// Slope in degrees at a chunk-local grid position, or InvalidHeight when the sample
		/// (which reaches one cell up and to the right) would leave the heightmap.
		/// </summary>
		public float GetInclinationAtChunkMapLocation(Vector2 location)
		{
			int x = Mathf.CeilToInt(location.X);
			int y = Mathf.CeilToInt(location.Y);

			if (_map?.heightMap == null) return TerrainMeshSettings.InvalidHeight;

			int w = _map.heightMap.GetLength(0);
			int h = _map.heightMap.GetLength(1);

			// This sampler reads (x+1, y+1), so it needs one cell of headroom on both axes.
			if (x < 0 || y < 0 || x + 1 >= w || y + 1 >= h)
			{
				return TerrainMeshSettings.InvalidHeight;
			}

			float height = _map.heightMap[x, y];

			Vector3 v1 = new Vector3(x, height, y);
			Vector3 v2 = new Vector3(x, _map.heightMap[x, y + 1], y + 1);
			Vector3 v3 = new Vector3(x + 1, _map.heightMap[x + 1, y + 1], y + 1);

			Vector3 add = v2 - v1;
			Vector3 cross = add.Cross(v3 - v1);
			if (cross.LengthSquared() < 0.000001f) return 0f; // degenerate sample, treat as flat

			Vector3 normal = cross.Normalized();

			// Compute the angle between the normal and the world up vector
			float inclination = Mathf.Acos(Mathf.Clamp(normal.Dot(Vector3.Up), -1f, 1f)) * 57.29578f;

			return inclination;
		}

		public float[,] GetHeightmap()
		{
			if (_map.heightMap != null) { return _map.heightMap; }
			return null;
		}
		/*public List<WorldItem> GetItems()
		{
			if (_map.DecorElements != null) { return _map.DecorElements; }
			return null;
		}*/



		async Task OnHeightMapReceived(Map heightMapObject)
		{
			_map = heightMapObject;
			if (_map.Origin == Map.Origins.Generated && TerrainManager.Instance.SaveTerrainToLocalDisk)
			{
				_map.SaveUnibyte("Chunk[x" + GridPosition.X + ",y" + GridPosition.Y + "]");
				_map.SaveMapDetails("Chunk[x" + GridPosition.X + ",y" + GridPosition.Y + "]");
			}
			
			heightMapReceived = true;
			try
			{
				if (loading)
				{
					await OnLODChanged();
					UpdateDebugData();
				}
			}
			catch(Exception ex)
			{
				GD.Print("LOD Change failed: " +ex.StackTrace);
			}
			await Task.Yield(); 
			try
			{
				if (!itemsLoaded)
				{
					LoadTerrainElements();
					//UpdateDebugData();
				}
			}
			catch(Exception ex)
			{
				GD.Print("Terrain elements load failed: " +ex.StackTrace);
			}
			try
			{
				if (!hasSetWater)
				{
					LoadWater(_map.heightMap);
					//UpdateDebugData();
				}
			}
			catch(Exception ex)
			{
				GD.Print("Water load failed: " +ex.StackTrace);
			}
		}

		async Task LoadWater(float[,] heightMap)
		{
			if (AllAboveThreshold(heightMap, 0)) {hasSetWater = true; return; }
			Node3D parentNode = new Node3D();
			parentNode.Name = "Water";
			meshObject.CallDeferred("add_child", parentNode);
			SeaWater water = TerrainDetailsManager.Instance.Water.Duplicate() as SeaWater;
			parentNode.CallDeferred("add_child", water);
			water.Scale = Vector3.One * (TerrainMeshSettings.chunkMeshSize + 2f);
			await water.SetTerrainElevation("Chunk[x" + GridPosition.X + ",y" + GridPosition.Y + "]", heightMap);
			hasSetWater = true;
			//water.Position = 
		}


		bool AllAboveThreshold(float[,] heightMap, float threshold)
		{
			int width = heightMap.GetLength(0);
			int height = heightMap.GetLength(1);

			for (int x = 0; x < width; x++)
			{
				for (int y = 0; y < height; y++)
				{
					if (heightMap[x, y] < threshold)
						return false; // found a value under threshold
				}
			}

			return true; // no value was under threshold
		}






		//This function is run when the map is done loading, here, we should assess if objects' nodes should be spawned. 
		// If any LOD logic is to be implemented, here's where it should happen
		async Task LoadTerrainElements()
		{
			
			if (itemsLoaded) { return; }if (meshObject==null) { return; }
			itemsLoaded = true;
			//await Task.Yield(); 
			//GD.Print("Loading terrain elements, with " + heightMap.DecorElements.Count + " elements");
			Node3D parentNode = new Node3D();
			parentNode.Name = "DecorObjects";

			meshObject.AddChild(parentNode);
			//meshObject.CallDeferred("add_child", parentNode);
			int i = 0;

			List<WorldItem> itms = new List<WorldItem>(_map.GetTerrainElements());
			//GD.Print("[Item Action] Loading Items from Chunk. " + itms.Count);
			//GD.Print("[Step 2] Chunk " + sampleCentre +" pulled " + _map.GetTerrainElements().Count+  " elements");
			foreach (WorldItem itm in itms)
			{
				//List<WorldItem> items = new List<WorldItem>();
				 if (itm == null) continue;
				Vector2 inGridLocation = new Vector2(25 - itm.GridLocation.X, 25 - itm.GridLocation.Y);
				//GD.Print("inGridLocation " + inGridLocation);
				Vector3 location = new Vector3(-1 * inGridLocation.X, GetHeightAtChunkMapLocation(itm.GridLocation), inGridLocation.Y);

				itm.GridLocation = inGridLocation;
				WorldItemModel item = await TerrainManager.Instance.DetailsManager.SpawnAndInitialize(itm);
				itm.Model = item;
				if (item == null) {GD.Print("Error null item "+itm.GridLocation);continue;}
				//GD.Print("In grid "+itm.GridLocation);
				//parentNode.CallDeferred("add_child", item);
				parentNode.AddChild(item);
				item.Position = location;
				
				item.Scale = itm.Scale;
                item.RotateX(itm.Rotation.X);
                item.RotateY(itm.Rotation.Y + itm.settings.Levitation);
                item.RotateZ(itm.Rotation.Z);
				//await SetMeshParameters(itm);

				itm.Initialize(currentLODIndex);

				i++;
				//worldItems.Add(items);
			}
			
		}

		async Task SetMeshParameters(WorldItem item)
		{
			Vector2 inGridLocation = new Vector2(25 - item.GridLocation.X, 25 - item.GridLocation.Y);
				//GD.Print("inGridLocation " + inGridLocation);
				Vector3 location = new Vector3(-1 * inGridLocation.X, GetHeightAtChunkMapLocation(item.GridLocation), inGridLocation.Y);
			item.Model.Position = location;
				
				item.Model.Scale = item.Scale;//Vector3.One * TerrainManager.Instance.TerrainDetailsRandom.RandfRange(objectToSpawn.MinSize, objectToSpawn.MaxSize);
                // CallDeferred("add_sibling",node);
                item.Model.RotateX(item.Rotation.X);
                item.Model.RotateY(item.Rotation.Y + item.settings.Levitation);
                item.Model.RotateZ(item.Rotation.Z);
		} 

		Vector2 viewerPosition
		{
			get
			{
				if (GameManager.Instance.MainCamera == null) { return Vector2.Zero; }
				return new Vector2(GameManager.Instance.MainCamera.GlobalPosition.X, GameManager.Instance.MainCamera.GlobalPosition.Z);
			}
		}

		Vector3 viewerPosition3
		{
			get
			{
				if (GameManager.Instance.MainCamera == null) { return Vector3.Zero; }
				return new Vector3(GameManager.Instance.MainCamera.GlobalPosition.X, 0, GameManager.Instance.MainCamera.GlobalPosition.Z);
			}
		}

		public void OnLODMeshReceived()
		{
			//GD.Print(GridPosition + " - Received mesh for LOD " + currentLODIndex);
			LODMesh lodMesh = lodMeshes[currentLODIndex];
			if (lodMesh.hasMesh)
			{
				previousLODIndex = currentLODIndex;
				if (meshObject == null || !meshObject.IsInsideTree() || lodMesh.mesh == null) {GD.Print("Issue: LOD nonexistent");return;}

				meshObject.Mesh = lodMesh.mesh;
			}
			UpdateDebugData();
		}

		//The index of our LOD has changed, we need to change the terrain mesh and do other stuff if need is
		public async Task OnLODChanged()
		{
			if (!heightMapReceived)
			{
				GD.Print("LOD Changed, but did not receive heightmap");
			}
			if (heightMapReceived)
			{
				if (currentLODIndex != previousLODIndex)
				{
					//GD.Print(GridPosition + " - Lod changed: from " + previousLODIndex + " to " + currentLODIndex);
					LODMesh lodMesh = lodMeshes[currentLODIndex];
					if (lodMesh.hasMesh)
					{
						previousLODIndex = currentLODIndex;
						meshObject.Mesh = lodMesh.mesh;
					}
					else if (!lodMesh.hasRequestedMesh)
					{
						previousLODIndex = currentLODIndex;
						await lodMesh.RequestMesh(_map);
					}
				}
				UpdateCollisionMesh();
			}
			List<WorldItem> itms = new List<WorldItem>(_map.GetTerrainElements());
			foreach (WorldItem itm in itms)
			{
				itm.OnChangedLOD(currentLODIndex);
			}
			UpdateDebugData();
			//if (currentLODIndex == 0){GD.Print("Current LOD 0 is " + GridPosition);}
		}

		public void UpdateHelpers()
		{
			/*string text = meshObject.Name + " -  LOD: " + currentLODIndex + "\nCenter: " + sampleCentre + " " + IsVisible();
			
			if (helper == null)
			{
				helper = Debug.SetTextHelper(text, Vector3.Zero, meshObject);
				helper.MaxViewDistance = 200;
			}
			if (helper != null)
			{
				helper.SetText(text);
			}*/
		}

		public void Destroy()
		{
			
			DebugUI.Instance.RemoveChunkData(GridPosition.ToString());

			if (meshObject != null && meshObject.IsInsideTree())
				meshObject.QueueFree();
		}

		public void SetChunkPendingDestruction()
		{
			isHidden = true;
			meshObject.Visible = false;

		}

		public void ReinstateChunk()
		{
			isHidden = false;
			//state = ChunkState.MeshReady;
			OnLODChanged ();
			meshObject.Visible = true;

		}

		public void UpdateCollisionMesh()
		{
			//if (TerrainManager.Instance.detailLevels[currentLODIndex].HasCollider) {return;}
			if (TerrainManager.Instance.detailLevels[currentLODIndex].HasCollider)
			{
				if (hasSetCollider)
				{
					collisionShape.Disabled = false;
					collisionShape.Visible = true;
				}
				if (!hasSetCollider)
				{

					if (lodMeshes[currentLODIndex].hasMesh)
					{


						staticBody = new StaticBody3D();
						staticBody.Name = "Collision - " + meshObject.Name;
						meshObject.CallDeferred("add_child", staticBody);
						collisionShape = new CollisionShape3D();
						staticBody.CallDeferred("add_child", collisionShape);

						collisionShape.Shape = meshObject.Mesh.CreateTrimeshShape();

						hasSetCollider = true;
					}
				}

			}
			if (!TerrainManager.Instance.detailLevels[currentLODIndex].HasCollider && hasSetCollider && collisionShape != null)
			{

				collisionShape.Visible = false;
				collisionShape.Disabled = true;
			}
		}





		void SetMaterial()
		{
			if (!hasSetMaterial)
			{
				//Material mat = GD.Load<Material>("_material/test_standard_material_3d.tres");
				if (meshObject.Mesh.GetSurfaceCount() == 0)
       			{
					GD.Print("Error: no surface to set material");
					return;
				}
				Material mat = TerrainManager.Instance.TerrainMaterial;
				if (TerrainManager.Instance.UseDebugMaterial)
				{
					mat = TerrainManager.Instance.DebugTerrainMaterial;
				}
				//Material mat = GD.Load<Material>("_material/testmat.tres");
				meshObject.SetSurfaceOverrideMaterial(0, mat);
				hasSetMaterial = true;
			}
		}

		public void SetVisible(bool visible)
		{
			meshObject.Visible = visible;
		}

		public bool IsVisible()
		{
			return meshObject.Visible;
		}

	}

	class LODMesh
	{

		public Mesh mesh;
		public bool hasRequestedMesh;
		public bool hasMesh;
		int lod;
		public event System.Action updateCallback;

		public LODMesh(int lod)
		{
			this.lod = lod;
		}


		async Task OnMeshDataReceived(MeshData meshDataObject)
		{
			//GD.Print("Mesh received");
			mesh = await ((MeshData)meshDataObject).CreateMesh();

			hasMesh = true;
			updateCallback();
		}



		public async Task RequestMesh(Map heightMap)
		{
			//GD.Print("Requesting Mesh");
			hasRequestedMesh = true;
			MeshData mesh = await MeshGenerator.GenerateTerrainMeshAsync(heightMap, lod);
			await OnMeshDataReceived(mesh);
			//ThreadedDataRequester.RequestData (() => MeshGenerator.GenerateTerrainMesh (heightMap, lod), OnMeshDataReceived);
		}

	}
}