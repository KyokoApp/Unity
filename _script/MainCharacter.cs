////////////////////////////////////////////////////////////////////////////////////////////
/// This script is part of the project "Infinite Runner", a procedural generation project
/// By Adrien Pierret
/// 
/// GameManager: A manager for the main character, with basic animations, state machine, input manager.
/// ///////////////////////////////////////////////////////////////////////////////////////

using Godot;
using System;
using Bouncerock;
using Bouncerock.Terrain;
using Bouncerock.UI;
using System.Collections.Generic;

public partial class MainCharacter : CharacterBody3D
{
	[Export]
	public string CharacterName = "Bouncerock";

	[ExportGroup("Camera and optics")]
	[Export]
	public MainCharacterCamera PlayerCamera;

	public WorldSpaceUI PopupInfo;

	[Export]
	public float Action = 100;

	[Export]
	public float Mojo = 0;

	[Export]
	public float Points = 0;


	[Export]
	public Node3D CameraPivot;



	[ExportGroup("Player Objects")]

	public PackedScene Cube;

	[Export]
	public AnimationTree Animator;

	[ExportGroup("Powers")]
	[Export] public Node3D PowerJetpack;

	[ExportGroup("Player Attributes")]

	//Vector3 Direction = Vector3.Zero;

	Vector3 CameraRotationAxis = Vector3.Zero;

	List<RigidBody3D> Crates = new List<RigidBody3D>();


	[Export] public MeshInstance3D Faraway;

	float mouse_speed = 0.05f;

	[Export]
	public float WalkingSpeed = 4;
	[Export]
	public float WalkToRunSpeedIncrease = 1;
	[Export]
	public float RunningSpeed = 20;

	public float SpeedMultiplier = 1;

	[Export]
	public Node3D SpotLight;

	[Export]
	public float JumpVelocity = 5;
	public float JumpVelocityMultiplier = 1;
	/*[Export]
	float MaxSpeed = 4;*/
	float speed = 1;

	private float timeOffGround = 0f;

	float velocity = 0;

	public enum CharacterActions { Idle, Jumping, Running, Attacking, Walking, Falling, Gliding, Flying, Sitting }

	public enum CharacterPowers { Crates, RotoPunch, Jetpack }

	public CharacterPowers CurrentPower = CharacterPowers.Crates;

	float upkeepTimer = 0;

	public bool Initialized = false;
	float _initWaitTimer = 0f;

	public bool hasGlided = false;

	private float attackCooldown = 0.5f;
	private float attackTimer = 0f;

	public class CharacterInput
	{
		bool run = false;
		bool jump = false;

		bool attack = false;
		bool fly = false;
		bool sit = false;
		public Vector3 Direction = Vector3.Zero;

		public Vector3 CameraDirection = Vector3.Zero;

		public void SetRun()
		{
			run = true;
			jump = false;
			attack = false;
			fly = false;
			sit = false;
		}
		public void SetSit()
		{
			run = false;
			jump = false;
			attack = false;
			fly = false;
			sit = true;
		}
		public void SetJump()
		{
			run = false;
			jump = true;
			attack = false;
			fly = false;
			sit = false;
		}
		public void SetFly()
		{
			run = false;
			jump = false;
			attack = false;
			fly = true;
			sit = false;
		}
		public void SetAttack()
		{
			run = false;
			jump = false;
			fly = false;
			attack = true;
			sit = false;
		}
		public void EndAttack()
		{
			attack = false;

		}
		public void Reset()
		{
			run = false;
			jump = false;
			attack = false;
			fly = false;
			sit = false;
		}

		public bool IsRunning() { return run; }
		public bool IsJumping() { return jump; }
		public bool IsAttacking() { return attack; }
		public bool IsSitting() { return sit; }

		public bool IsFlying() { return fly; }
	}

	public CharacterInput CurrentInput = new CharacterInput();

	public CharacterActions CurrentAction;


	float cam_rot_x = 0;
	float cam_rot_y = 0;

	[Export] public TouchInputManager touchInputManager;





	// Get the gravity from the project settings to be synced with RigidBody nodes.
	public float gravity = ProjectSettings.GetSetting("physics/3d/default_gravity").AsSingle();

	public override void _Ready()
	{

		Initialization();
	}

	protected virtual void Initialization()
	{
		//Faraway = GetNode("/root/Faraway") as MeshInstance3D;
		GameSettings.EnsureLoaded();
		Input.MouseMode = Input.MouseModeEnum.Captured;
		FloorMaxAngle = Mathf.DegToRad(50);
		GameManager.Instance.SetMainCamera(PlayerCamera);
		GameManager.Instance.SetMainCharacter(this);

		Cube = GD.Load<PackedScene>("res://_scenes/decor/crate.tscn");

		ApplyToonOutline();
		ConfigureModelAnimationLoops();
	}

	// KayKit Knight.glb membawa 76 clip; tanpa konfigurasi ini semua clip
	// default TIDAK loop → Idle/Run berhenti setelah 1 siklus (seolah macet).
	// Loop dipaksa di sini agar tidak tergantung setting .import.
	private void ConfigureModelAnimationLoops()
	{
		var player = GetNodeOrNull<AnimationPlayer>("RobotArmature/PlayerModel/AnimationPlayer");
		var lib = player?.GetAnimationLibrary("");
		if (lib == null) return;

		// Loop panjang: gerak dasar
		foreach (string n in new[] { "Idle", "Jump_Idle", "Running_A", "Running_B", "Sit_Floor_Idle" })
		{
			if (lib.HasAnimation(n)) lib.GetAnimation(n).LoopMode = Animation.LoopModeEnum.Linear;
		}
		// Sekali main: serangan & transisi
		foreach (string n in new[] { "Throw", "Unarmed_Melee_Attack_Kick", "Jump_Full_Long", "Jump_Start", "Jump_Land",
			"Hit_A", "Hit_B", "Death_A", "Death_B", "Cheer", "Interact", "PickUp", "Use_Item", "Dodge_Forward" })
		{
			if (lib.HasAnimation(n)) lib.GetAnimation(n).LoopMode = Animation.LoopModeEnum.None;
		}
	}

	private void ApplyToonOutline()
	{
		Shader outlineShader = GD.Load<Shader>("res://materials/shaders/toon_outline.gdshader");
		if (outlineShader == null) return;

		var outlineMat = new ShaderMaterial();
		outlineMat.Shader = outlineShader;
		outlineMat.SetShaderParameter("outline_color", new Color(0.08f, 0.08f, 0.1f, 1.0f));
		outlineMat.SetShaderParameter("outline_width", 2.2f);

		Node armature = GetNodeOrNull("RobotArmature");
		if (armature != null)
		{
			ApplyOutlineRecursive(armature, outlineMat);
		}
	}

	private void ApplyOutlineRecursive(Node node, Material outlineMat)
	{
		if (node is MeshInstance3D meshInstance)
		{
			meshInstance.MaterialOverlay = outlineMat;
		}

		foreach (Node child in node.GetChildren())
		{
			ApplyOutlineRecursive(child, outlineMat);
		}
	}

	public override void _PhysicsProcess(double delta)
	{
		if (Initialized)
		{
			float deltaFloat = (float)delta;
			UpdateMovement(deltaFloat);
		}
	}




	public override void _Process(double delta)
	{
		if (TerrainManager.Instance == null ||
		    TerrainManager.Instance.CurrentLoadStatus != TerrainManager.LoadStatuses.Initialized)
		{
			return;
		}
		if (!Initialized)
		{
			// Anti-softlock: kalau lookup terrain gagal > 3 detik (mis. spawn
			// di luar chunk / koordinat tak ketemu), paksa inisialisasi di
			// posisi saat ini daripada karakter macet tak bisa digerakkan.
			_initWaitTimer += (float)delta;
			if (_initWaitTimer > 3f)
			{
				float safeY = Position.Y > -50 ? Position.Y : 30f;
				GlobalPosition = new Vector3(Position.X, safeY, Position.Z);
				if (MobManager.Instance != null)
				{
					MobManager.Instance.CallDeferred("ResetSecureZone", GlobalPosition);
				}
				Initialized = true;
				GD.Print("[MainCharacter] Fallback init dipakai setelah 3 detik.");
			}
		}
		if (!Initialized)
		{
			Vector2 position = new Vector2(Position.X, Position.Z);
			float height = TerrainManager.Instance.GetTerrainHeightAtGlobalCoordinate(position);
			Vector2 origin = position;
			int radius = 20;
			int maxAttempts = 500;
			int attempts = 0;
			float step = radius;
			if (height != -201)
			{
				GD.Print("original pos " + position);

				int layer = 1; // how many steps away from origin
				bool found = false;

				while (!found && attempts < maxAttempts)
				{
					// Iterate in a spiral-like pattern: right, down, left, up
					for (int x = -layer; x <= layer; x++)
					{
						for (int y = -layer; y <= layer; y++)
						{
							// Skip positions inside previous layers to avoid double-checking
							if (Mathf.Abs(x) != layer && Mathf.Abs(y) != layer)
							{
								continue;
							}


							Vector2 checkPos = origin + new Vector2(x * step, y * step);
							float testHeight = TerrainManager.Instance.GetTerrainHeightAtGlobalCoordinate(checkPos);

							attempts++;
							//GD.Print("testing position " + checkPos + " after " + attempts + " attempts . new height " + testHeight);
							if (testHeight > 5.0f)
							{
								position = checkPos;
								height = testHeight + 2;
								found = true;
								break;
							}

							if (attempts >= maxAttempts)
							{
								break;
							}
						}
						if (found || attempts >= maxAttempts)
						{
							break;
						}
					}
					layer++; // expand the search radius
				}

				GlobalPosition = new Vector3(position.X, height, position.Y);
				MobManager.Instance.CallDeferred("ResetSecureZone", GlobalPosition);
				GD.Print("final " + GlobalPosition + " after " + attempts + " attempts");
				Initialized = true;
			}
		}
		if (Faraway != null)
		{
			Faraway.Position = new Vector3(Position.X, 0, Position.Z);
		}
		float deltaFloat = (float)delta;
		//GD.Print(RaycastDown.IsColliding());
		UpdateAction(deltaFloat);
		//UpdateMovement(deltaFloat);
		UpdateCamera(deltaFloat);
		UpdateHelpers(deltaFloat);
		//UpdateInput(deltaFloat);
		UpdateAnimations();
		upkeepTimer = upkeepTimer - (float)delta;
		if (upkeepTimer < 0)
		{
			CratesUpkeep();
			upkeepTimer = 1;
		}
	}


	protected void UpdateAction(float deltaFloat)
	{
		if (attackTimer > 0f)
		{
			attackTimer -= deltaFloat;
		}

		CharacterActions previousAction = CurrentAction;
		if (CurrentInput.IsRunning() && CurrentInput.Direction != Vector3.Zero && Action > 0)
		{
			if (IsOnFloor() || timeOffGround < 1f)
			{
				CurrentAction = CharacterActions.Running;
				timeOffGround = 0;
				Action = Mathf.Clamp(Action - (deltaFloat * 10), 0, 100);
				return;
			}

		}
		if (CurrentInput.IsJumping() && !CurrentInput.IsFlying()) { CurrentAction = CharacterActions.Jumping; return; }
		if (!IsOnFloor())
		{
			timeOffGround += deltaFloat;
			if (CurrentInput.IsRunning() && (!hasGlided || CurrentAction == CharacterActions.Gliding)) { hasGlided = true; CurrentAction = CharacterActions.Gliding; return; }
			if (CurrentInput.IsFlying() && Action > 0) { CurrentAction = CharacterActions.Flying; return; }
			CurrentAction = CharacterActions.Falling; return;
		}
		else
		{
			timeOffGround = 0;
			hasGlided = false;
			if (CurrentInput.IsAttacking() && Action > 5)
			{

				LaunchAttack();
				if (previousAction == CharacterActions.Attacking)
				{
					CurrentAction = CharacterActions.Attacking;
				}
				return;
			}
		}

		if (CurrentInput.Direction != Vector3.Zero && IsOnFloor())
		{
			Action = Mathf.Clamp(Action + deltaFloat, 0, 100);
			CurrentAction = CharacterActions.Walking;
			return;
		}
		if ((CurrentInput.IsSitting() || previousAction == CharacterActions.Sitting) && IsOnFloor() && CurrentInput.Direction == Vector3.Zero)
		{
			Action = Mathf.Clamp(Action + deltaFloat * 2, 0, 100);
			CurrentAction = CharacterActions.Sitting;
			return;
		}
		Action = Mathf.Clamp(Action + deltaFloat * 3, 0, 100);
		CurrentAction = CharacterActions.Idle;


	}

	void LaunchAttack()
	{
		if (attackTimer > 0f) { return; }
		attackTimer = attackCooldown;
		if (CurrentPower == CharacterPowers.Crates)
		{
			Action = Mathf.Clamp(Action - 5, 0, 100);
			Animator.Set("parameters/conditions/tossing", true);
			RigidBody3D newCube = Cube.Instantiate() as RigidBody3D;
			GetTree().Root.AddChild(newCube);
			Vector3 forwardDirection = GlobalTransform.Basis.Z;

			Crates.Add(newCube);

			newCube.Position = GlobalTransform.Origin + (forwardDirection * 2) + Vector3.Up;

			Vector3 velocityDirection = (forwardDirection * 2 + Vector3.Up).Normalized();
			newCube.LinearVelocity = velocityDirection * 10;
			CurrentInput.EndAttack();
		}
		if (CurrentPower == CharacterPowers.RotoPunch)
		{
			Animator.Set("parameters/conditions/tossing", true);

			CurrentInput.EndAttack();
		}

	}

	public void CratesUpkeep()
	{
		foreach (RigidBody3D crate in Crates.ToArray()) // Iterate over a copy of the list
		{
			if (Position.DistanceTo(crate.Position) > 200)
			{
				DespawnCrate(crate, 1);
			}
		}
	}

	async void DespawnCrate(RigidBody3D crate, float delay = -1)
	{
		Crates.Remove(crate);
		if (delay > 0)
		{
			await ToSignal(GetTree().CreateTimer(delay), "timeout");
		}
		crate.QueueFree();

	}

	/*public override void _Input(InputEvent keyEvent)
		{
			
			if (keyEvent is InputEventMouseButton _mouseButton)
			{
				switch (_mouseButton.ButtonIndex)
				{
					case MouseButton.Right:
					Input.MouseMode = _mouseButton.Pressed? Input.MouseModeEnum.Captured:Input.MouseModeEnum.Visible;
					break;
				}
				if (_mouseButton.ButtonIndex == MouseButton.Left && _mouseButton.Pressed)
				{
					RigidBody3D newCube = Cube.Instantiate() as RigidBody3D;
					GetTree().Root.AddChild(newCube);
					Vector3 forwardDirection = GlobalTransform.Basis.Z;

					newCube.Position = GlobalTransform.Origin + (forwardDirection*2)+Vector3.Up;

					Vector3 velocityDirection = (forwardDirection*2 + Vector3.Up).Normalized();
        			newCube.LinearVelocity = velocityDirection * 5;

					//newCube.Position = this.Position + Vector3.Back +Vector3.Up;
				//	newCube.Rotation = this.Rotation;
					//newCube.LinearVelocity = (Vector3.Back+Vector3.Up)*10;
				}
			}
			if (keyEvent is InputEventMouseMotion motion)
			{
				cam_rot_x = Mathf.Clamp((cam_rot_x +(-motion.Relative.Y * mouse_speed)), -25,60);
				cam_rot_y += -motion.Relative.X * mouse_speed;
			}
			if (Input.IsActionPressed("action"))
			{
				float height = TerrainManager.Instance.GetTerrainHeightAtGlobalCoordinate(new Vector2(GlobalPosition.X, GlobalPosition.Z));

				float degree = TerrainManager.Instance.GetTerrainInclinationAtGlobalCoordinate(new Vector2(GlobalPosition.X, GlobalPosition.Z));

				Vector3 location = new Vector3(GlobalPosition.X, height, GlobalPosition.Z);
				GD.Print("Degree inclination: " + degree);
				
				
			}

		}*/

	protected void UpdateAnimations()
	{

		Animator.Set("parameters/conditions/falling", false);
		Animator.Set("parameters/conditions/idle", false);
		Animator.Set("parameters/conditions/sprinting", false);
		Animator.Set("parameters/conditions/running", false);
		Animator.Set("parameters/conditions/tossing", false);
		Animator.Set("parameters/conditions/flying", false);
		Animator.Set("parameters/conditions/glide", false);
		Animator.Set("parameters/conditions/sitting", false);
		PowerJetpack.Visible = false;
		if (CurrentAction == CharacterActions.Falling)
		{
			Animator.Set("parameters/conditions/falling", true);
			return;
		}
		if (CurrentAction == CharacterActions.Sitting)
		{
			Animator.Set("parameters/conditions/sitting", true);
			return;
		}
		if (CurrentAction == CharacterActions.Idle)
		{
			Animator.Set("parameters/conditions/idle", true);
			return;
		}
		if (CurrentAction == CharacterActions.Walking)
		{
			Animator.Set("parameters/conditions/running", true);
			return;
		}
		if (CurrentAction == CharacterActions.Running)
		{
			Animator.Set("parameters/conditions/sprinting", true);
			return;
		}
		if (CurrentAction == CharacterActions.Flying)
		{
			Animator.Set("parameters/conditions/flying", true);
			PowerJetpack.Visible = true;
			return;
		}
		if (CurrentAction == CharacterActions.Gliding)
		{
			Animator.Set("parameters/conditions/glide", true);
			return;
		}

	}

	protected void ChangeAnimState()
	{

	}

	protected void UpdateMovement(float deltaFloat)
	{
		Vector3 velocity = Velocity;

		// Handle Jump.
		if (CurrentAction == CharacterActions.Jumping && IsOnFloor())
		{
			velocity.Y = JumpVelocity * JumpVelocityMultiplier;
		}

		// Get the input direction and handle the movement/deceleration.
		Vector2 inputDir = Vector2.Zero;
		if (touchInputManager != null && touchInputManager.MoveVector != Vector2.Zero)
		{
			// Analog stick: X is horizontal (-1 left, 1 right), Y is vertical (-1 up/forward, 1 down/backward)
			inputDir = new Vector2(touchInputManager.MoveVector.X, touchInputManager.MoveVector.Y);
		}
		else
		{
			inputDir = Input.GetVector("ui_left", "ui_right", "ui_up", "ui_down");
		}

		if (inputDir.LengthSquared() > 0.01f)
		{
			// Calculate true forward and right direction from CameraPivot yaw angle
			float camYawRad = Mathf.DegToRad(cam_rot_y);
			Vector3 camForward = new Vector3(-Mathf.Sin(camYawRad), 0, -Mathf.Cos(camYawRad)).Normalized();
			Vector3 camRight = new Vector3(Mathf.Cos(camYawRad), 0, -Mathf.Sin(camYawRad)).Normalized();

			// Analog up (negative Y) moves straight forward in camera view; analog right (positive X) moves right
			Vector3 targetMoveDir = (camRight * inputDir.X + camForward * -inputDir.Y).Normalized();
			CurrentInput.Direction = targetMoveDir;

			// Smoothly rotate character body towards target move direction without infinite feedback loop
			float targetAngle = Mathf.Atan2(targetMoveDir.X, targetMoveDir.Z);
			Rotation = new Vector3(Rotation.X, Mathf.LerpAngle(Rotation.Y, targetAngle, deltaFloat * 12f), Rotation.Z);
		}
		else
		{
			CurrentInput.Direction = Vector3.Zero;
		}
		if (IsOnFloor())
		{
			if (Action > 0)
			{
				speed = CurrentAction == CharacterActions.Running ? RunningSpeed : WalkingSpeed;
				speed = speed * SpeedMultiplier;
			}
		}
		if (!IsOnFloor())
		{
			if (CurrentAction == CharacterActions.Flying)
			{
				Action = Mathf.Clamp(Action - (deltaFloat * 10), 0, 100);
				velocity.Y += 4 * deltaFloat;
				float t = Mathf.MoveToward((float)(speed - WalkingSpeed) / (RunningSpeed - WalkingSpeed), 0, 1);
				speed = Mathf.Lerp(WalkingSpeed, RunningSpeed, t);
			}
			else if (CurrentAction == CharacterActions.Gliding)
			{
				//Action = Mathf.Clamp(Action - (deltaFloat * 10), 0, 100);
				velocity.Y = -1;
				//float t = Mathf.MoveToward((float)(speed - WalkingSpeed) / (RunningSpeed - WalkingSpeed), 0, 1);
				speed = RunningSpeed;
				speed = speed * SpeedMultiplier;
			}
			else
			{
				Action = Mathf.Clamp(Action + (int)deltaFloat, 0, 100);
				velocity.Y -= gravity * deltaFloat;
				//float ratio = (speed - WalkingSpeed) / (RunningSpeed - WalkingSpeed);
				//float newRatio = Mathf.MoveToward(ratio, 0, deltaFloat * 1.5f); // adjust the 1.5f as needed
				//speed = Mathf.Lerp(WalkingSpeed, RunningSpeed, newRatio);
				float t = Mathf.MoveToward((float)(speed - WalkingSpeed) / (RunningSpeed - WalkingSpeed), 0, 1);
				speed = Mathf.Lerp(WalkingSpeed, RunningSpeed, t);

			}

		}
		if (CurrentInput.Direction != Vector3.Zero)
		{
			velocity.X = CurrentInput.Direction.X * speed;
			velocity.Z = CurrentInput.Direction.Z * speed;
		}
		else
		{
			velocity.X = Mathf.MoveToward(Velocity.X, 0, speed);
			velocity.Z = Mathf.MoveToward(Velocity.Z, 0, speed);
		}

		if (Position.Y < -100)
		{
			Position = new Vector3(Position.X, 50, Position.Z);
			Action = 100;
		}

		Velocity = velocity;
		MoveAndSlide();
	}

	protected void UpdateCamera(float deltaFloat)
	{
#if GODOT_ANDROID
		if (touchInputManager != null)
		{
			CameraRotationAxis.X = touchInputManager.CameraRotationAxis.X;
			CameraRotationAxis.Y = touchInputManager.CameraRotationAxis.Y;
		}
#endif
		float targetFov = 75;
		float fovLerpTime = 0.5f; // adjust this value to control the speed of the FOV change

		if (CurrentInput.Direction.Z != 0)
		{
			if (CurrentAction == CharacterActions.Running || CurrentAction == CharacterActions.Gliding)
			{
				targetFov = 100;
			}
			else
			{
				targetFov = 75;
			}
		}
		if (CameraRotationAxis != Vector3.Zero)
		{
			cam_rot_x -= CameraRotationAxis.Y;
			cam_rot_y += Mathf.Clamp(CameraRotationAxis.X, -25, 60);
			// Reset CameraRotationAxis after applying delta so it doesn't spin infinitely!
			CameraRotationAxis = Vector3.Zero;
		}
		PlayerCamera.Fov = Mathf.Lerp(PlayerCamera.Fov, targetFov, fovLerpTime * deltaFloat);

		// Camera pivot rotates horizontally (Y yaw) and vertically (X pitch) independently from character body
		CameraPivot.RotationDegrees = new Vector3(cam_rot_x, cam_rot_y, 0);

		//RotateObjectLocal(Vector3.Right, Mathf.DegToRad(-pitch));
	}

	public void AddAction(int action)
	{
		float remainder = 0;
		if (Action < 100)
		{
			Action = Action + action;
			remainder = Action - 100;
			if (remainder > 0)
			{
				float multiplier = GameManager.Instance.StartingPoint.DistanceTo(GameManager.Instance.GetMainCharacterPosition());
				multiplier = Mathf.Clamp(multiplier / 100, 1, 100);
				multiplier = Mathf.FloorToInt(multiplier);
				Mojo = Mojo + remainder * multiplier;
			}
		}
		else if (Mojo < 100)
		{
			float multiplier = GameManager.Instance.StartingPoint.DistanceTo(GameManager.Instance.GetMainCharacterPosition());
			multiplier = Mathf.Clamp(multiplier / 100, 1, 100);
			multiplier = Mathf.FloorToInt(multiplier);
			Mojo = Mojo + action * multiplier;
		}
		if (Mojo >= 100)
		{
			Points = Points + 1;
			Mojo = 0;
		}
	}

	private float _helpersAccum = 0f;
	private string _lastHelperText = "";

	public void UpdateHelpers(float deltaFloat)
	{
		if (PopupInfo == null)
		{
			string initText = CharacterName + "\n" + TerrainManager.Instance.CameraInChunk();
			PopupInfo = Debug.SetTextHelper(initText, CameraPivot.Position, CameraPivot);
			PopupInfo.MaxViewDistance = 1000;
			_lastHelperText = initText;
#if GODOT_ANDROID
				PopupInfo.SetSize(50); // cukup set sekali (sebelumnya tiap frame)
#endif
		}
		if (PopupInfo != null)
		{
			// Teks (nama + chunk) dihitung ulang hanya 4x/detik & SetText hanya bila
			// berubah; posisi tetap di-track tiap frame agar label mengikuti karakter.
			_helpersAccum += deltaFloat;
			if (_helpersAccum >= 0.25f)
			{
				_helpersAccum = 0f;
				string text = CharacterName + "\n" + TerrainManager.Instance.CameraInChunk();
				if (text != _lastHelperText)
				{
					_lastHelperText = text;
					PopupInfo.SetText(text);
				}
			}
			PopupInfo.Position = CameraPivot.Position + Vector3.Down * 0.7f;
			//GD.Print("Position " + PopupInfo.Position);
		}
		/*string text = "Adrien" + "\n" + TerrainManager.Instance.CameraInChunk();

		if (PopupInfo == null)
		{
			PopupInfo = Debug.SetTextHelper(text, CameraPivot.Position, CameraPivot);
			PopupInfo.MaxViewDistance = 1000;
		}
		if (PopupInfo != null)
		{
			text = "AdrienSetup" + "\n" + Mathf.RadToDeg(GetFloorAngle()) + " Pos: \nX: " + string.Format("{0:0. #}", Position.X) + "\nY: " + string.Format("{0:0. #}", Position.Y) + "\nZ: " + string.Format("{0:0. #}", Position.Z) ;
			//GD.Print(TerrainGenerator.Instance.CameraInChunk());
			PopupInfo.SetText(text);
			//PopupInfo.Position = CameraPivot.Position+ Vector3.Up *0.2f;
		}*/
	}

	public override void _Input(InputEvent keyEvent)
	{
		CurrentInput.Reset();
		if (Input.IsActionPressed("run"))
		{
			CurrentInput.SetRun();
		}
		if (Input.IsActionPressed("jump"))
		{
			CurrentInput.SetJump();
		}
		if (Input.IsActionPressed("fly"))
		{
			CurrentInput.SetFly();
		}
		
		if (Input.IsActionPressed("sit"))
		{
			CurrentInput.SetSit();
		}
#if GODOT_WINDOWS
		if (Input.IsActionJustPressed("torch"))
		{
			SpotLight.Visible = !SpotLight.Visible;
		}
		if (keyEvent is InputEventMouseButton _mouseButton)
		{
			switch (_mouseButton.ButtonIndex)
			{
				case MouseButton.Right:
					Input.MouseMode = _mouseButton.Pressed ? Input.MouseModeEnum.Captured : Input.MouseModeEnum.Visible;
					break;
			}
			if (_mouseButton.ButtonIndex == MouseButton.Left && _mouseButton.Pressed)
			{
				CurrentInput.SetAttack();

				//Toss a crate
				/*Animator.Set("parameters/conditions/tossing", true);
				RigidBody3D newCube = Cube.Instantiate() as RigidBody3D;
				GetTree().Root.AddChild(newCube);
				Crates.Add(newCube);
				Vector3 forwardDirection = GlobalTransform.Basis.Z;

				newCube.Position = GlobalTransform.Origin + (forwardDirection*2)+Vector3.Up;

				Vector3 velocityDirection = (forwardDirection*2 + Vector3.Up).Normalized();
				newCube.LinearVelocity = velocityDirection * 10;*/

			}
		}
#endif
#if GODOT_ANDROID
			if (Input.IsActionPressed("torch"))
			{
				SpotLight.Visible = !SpotLight.Visible;
			}
			if (Input.IsActionPressed("attack"))
			{
				CurrentInput.SetAttack();
					
					//Toss a crate
					Animator.Set("parameters/conditions/tossing", true);
					RigidBody3D newCube = Cube.Instantiate() as RigidBody3D;
					GetTree().Root.AddChild(newCube);
					Vector3 forwardDirection = GlobalTransform.Basis.Z;

					newCube.Position = GlobalTransform.Origin + (forwardDirection*2)+Vector3.Up;

					Vector3 velocityDirection = (forwardDirection*2 + Vector3.Up).Normalized();
        			newCube.LinearVelocity = velocityDirection * 10;
					
    				LaunchAttack();
			}
#endif
#if GODOT_WINDOWS
		if (keyEvent is InputEventJoypadMotion joypadMotionEvent)
		{
			// Get the joystick axis values
			JoyAxis axis = joypadMotionEvent.Axis; // X-axis of the joystick
			if (axis == JoyAxis.RightX || axis == JoyAxis.RightY)//axis goes from -1 to 0
			{
				// Get the joystick axis values
				if (axis == JoyAxis.RightY)
				{
					CameraRotationAxis.Y = joypadMotionEvent.AxisValue;
				}
				if (axis == JoyAxis.RightX)
				{
					CameraRotationAxis.X = joypadMotionEvent.AxisValue;
				}
			}
			//GD.Print(axis + joypadMotionEvent.AxisValue.ToString());
		}

		if (keyEvent is InputEventMouseMotion motion)
		{
			cam_rot_x = Mathf.Clamp((cam_rot_x + (-motion.Relative.Y * mouse_speed)), -25, 60);
			cam_rot_y += -motion.Relative.X * mouse_speed;
		}
#endif
		if (Input.IsActionPressed("run"))
		{
			CurrentInput.SetRun();
			float height = TerrainManager.Instance.GetTerrainHeightAtGlobalCoordinate(new Vector2(GlobalPosition.X, GlobalPosition.Z));

			float degree = TerrainManager.Instance.GetTerrainInclinationAtGlobalCoordinate(new Vector2(GlobalPosition.X, GlobalPosition.Z));

			Vector3 location = new Vector3(GlobalPosition.X, height, GlobalPosition.Z);
			//GD.Print("Degree inclination: " + degree);

		}

	}
}
