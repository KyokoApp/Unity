/*MIT License

Copyright (c) 2025 Adrien Pierret

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.*/

////////////////////////////////////////////////////////////////////////////////////////////
/// This script is part of the project "Infinite Runner", a procedural generation project
/// By Adrien Pierret
/// 
/// GameManager: This script is originally supposed to centralize and take care of everything related to the software.
/// It is the starting point for everything.
/// ///////////////////////////////////////////////////////////////////////////////////////

using Godot;
using System;
using Bouncerock.Events;

public partial class GameManager : Node
{
    public static GameManager Instance;
	private static Camera3D mainCamera;
	private static MainCharacter mainCharacter;

	// Akses read-only ke karakter aktif (dipakai debug overlay).
	public static MainCharacter CurrentCharacter => mainCharacter;
	
	public bool Initialized = false;
	public static PackedScene World;
	public static Resource UI;

	public float Record = 0;

	public Vector3 StartingPoint = Vector3.Zero;

	public Camera3D MainCamera
	{
		get{return mainCamera;}
	}

    public void Initialize()
	{
		Instance = this;
		Initialized = true;
		GD.Print("GameManager initialized");
		SoftwareInitialized();
		
	}

	public void OnLoseGame()
	{
		GD.Print("Lost");
		//Record = StartingPoint.DistanceTo(GetMainCharacterPosition())>Record?StartingPoint.DistanceTo(GetMainCharacterPosition());
		
		MobManager.Instance.DespawnAllMobs();
		StartingPoint = GetMainCharacterPosition();
		MobManager.Instance.ResetSecureZone(StartingPoint);
	}

	public void SoftwareInitialized()
	{
		LoadWorld();
	}

    public void SetMainCamera(Camera3D newCamera)
	{
		mainCamera = newCamera;
		GD.Print("Main camera changed: "+ mainCamera.Name);
		EvtCameraChanged evtCameraChanged = new EvtCameraChanged(newCamera, mainCamera);
		BouncerockEventManager.TriggerEvent<EvtCameraChanged>(evtCameraChanged);
	}

	public void SetMainCharacter(MainCharacter newCharacter)
	{
		mainCharacter = newCharacter;
		GD.Print("Main character changed: "+ mainCharacter.Name);
		EvtCharacterChanged evtCharacterChanged = new EvtCharacterChanged(newCharacter, mainCharacter);
		BouncerockEventManager.TriggerEvent<EvtCharacterChanged>(evtCharacterChanged);
	}

	// Semua getter di bawah ini aman dipanggil sebelum karakter utama terdaftar:
	// adegan (main.tscn) dan karakter (world.tscn) dimuat terpisah, jadi HUD yang
	// jalan di 1-2 frame pertama dulu-duluan dengan mainCharacter == null.
	public float GetMainCharacterAction()
	{
		return mainCharacter != null && GodotObject.IsInstanceValid(mainCharacter) ? mainCharacter.Action : 0f;
	}
	public float GetMainCharacterMojo()
	{
		return mainCharacter != null && GodotObject.IsInstanceValid(mainCharacter) ? mainCharacter.Mojo : 0f;
	}
	public float GetMainCharacterScore()
	{
		return mainCharacter != null && GodotObject.IsInstanceValid(mainCharacter) ? mainCharacter.Points : 0f;
	}
	/// <summary>Rasio darah 0..1 untuk HUD. 1f saat karakter belum ada (tidak berkedip).</summary>
	public float GetMainCharacterHealthRatio()
	{
		return mainCharacter != null && GodotObject.IsInstanceValid(mainCharacter) ? mainCharacter.HealthRatio : 1f;
	}
	public MainCharacter GetMainCharacter()
	{
		return mainCharacter != null && GodotObject.IsInstanceValid(mainCharacter) ? mainCharacter : null;
	}

	public Vector3 GetMainCharacterPosition()
	{
		return mainCharacter != null && GodotObject.IsInstanceValid(mainCharacter) ? mainCharacter.Position : Vector3.Zero;
	}

	public void LoadWorld()
	{
	GD.Print("Loading world");
		World = ResourceLoader.Load<PackedScene>("res://_scenes/world.tscn");
		Node node = World.Instantiate();
		CallDeferred("add_sibling",node);
		//AddSibling(node);
	}
}