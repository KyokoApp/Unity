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

		/// <summary>Analog stick deflection, 0..1. Drives walk/run speed blending.</summary>
		public float AnalogMagnitude = 0f;

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
		FloorMaxAngle = Mathf.DegToRad(50);
		GameManager.Instance.SetMainCamera(PlayerCamera);
		GameManager.Instance.SetMainCharacter(this);

		Cube = GD.Load<PackedScene>("res://_scenes/decor/crate.tscn");

		ApplyToonOutline();
	}

	private void ApplyToonOutline()
	{
		Shader outlineShader = GD.Load<Shader>("res://materials/shaders/toon_outline.gdshader");
		if (outlineShader == null) return;

		var outlineMat = new ShaderMaterial();
		outlineMat.Shader = outlineShader;
		outlineMat.SetShaderParameter("outline_color", new Color(0.08f, 0.08f, 0.1f, 1.0f));
		outlineMat.SetShaderParameter("outline_width", 2.2f);

		// Both rigs get the outline. AnimeCharacterRig runs in _Ready() as a child node, so it
		// has already mounted the anime model by the time we get here; RobotArmature is hidden
		// once that succeeds, but walking it costs nothing and keeps the old rig outlined if
		// the swap is switched off in the inspector.
		Node armature = GetNodeOrNull("RobotArmature");
		if (armature != null)
		{
			ApplyOutlineRecursive(armature, outlineMat);
		}

		Node animeMount = GetNodeOrNull("AnimeRigMount");
		if (animeMount != null)
		{
			ApplyOutlineRecursive(animeMount, outlineMat);
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
		if (TerrainManager.Instance.CurrentLoadStatus != TerrainManager.LoadStatuses.Initialized)
		{
			return;
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
			if (!Bouncerock.Terrain.TerrainMeshSettings.IsInvalidHeight(height))
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
		Faraway.Position = new Vector3(Position.X, 0, Position.Z);
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

	// ------------------------------------------------------------------
	// Movement tuning. These were previously hardcoded inside the method,
	// which made the character feel "stiff": any stick deflection past the
	// deadzone instantly snapped the character to full speed.
	// ------------------------------------------------------------------

	/// <summary>Stick magnitude below this is treated as "walk", above it we blend into a run.</summary>
	[Export] public float RunStickThreshold = 0.55f;

	/// <summary>How fast the body turns to face the travel direction (radians/sec response).</summary>
	[Export] public float TurnResponse = 14f;

	/// <summary>Ground acceleration / braking, in units per second squared.</summary>
	[Export] public float GroundAcceleration = 55f;

	/// <summary>How strongly the analog magnitude scales speed between 0 and 1.</summary>
	[Export] public float AnalogSpeedCurve = 1f;

	/// <summary>Vertical camera limits, in degrees. Pitch used to be unclamped on Android.</summary>
	[Export] public float CameraPitchMin = -25f;
	[Export] public float CameraPitchMax = 60f;

	/// <summary>
	/// Builds the world-space movement direction from the analog stick, using the actual
	/// camera basis. Reading CameraPivot.GlobalTransform.Basis (instead of re-deriving the
	/// yaw by hand) means the direction stays correct even if the pivot gets reparented or
	/// its rotation is driven from somewhere else.
	/// </summary>
	private Vector3 AnalogToWorldDirection(Vector2 inputDir)
	{
		Basis camBasis = CameraPivot.GlobalTransform.Basis;

		// Flatten onto the ground plane so looking up/down never tilts the walk direction.
		Vector3 camForward = new Vector3(camBasis.Z.X, 0f, camBasis.Z.Z);
		Vector3 camRight = new Vector3(camBasis.X.X, 0f, camBasis.X.Z);

		if (camForward.LengthSquared() < 0.0001f)
		{
			// Camera pointing straight down: fall back to the character's own facing.
			camForward = new Vector3(-Mathf.Sin(Rotation.Y), 0f, -Mathf.Cos(Rotation.Y));
			camRight = new Vector3(Mathf.Cos(Rotation.Y), 0f, -Mathf.Sin(Rotation.Y));
		}

		camForward = camForward.Normalized();
		camRight = camRight.Normalized();

		// Stick up (negative Y on screen) means "away from the camera" = camForward.
		// Godot's -Z is forward, hence the sign on the forward term.
		return (camRight * inputDir.X - camForward * inputDir.Y).Normalized();
	}

	protected void UpdateMovement(float deltaFloat)
	{
		Vector3 velocity = Velocity;

		// Handle Jump.
		if (CurrentAction == CharacterActions.Jumping && IsOnFloor())
		{
			velocity.Y = JumpVelocity * JumpVelocityMultiplier;
		}

		// ------------------------------------------------------------------
		// Analog input. Touch stick first; keyboard/gamepad axes as fallback.
		// Both produce a Vector2 whose LENGTH carries the analog magnitude.
		// ------------------------------------------------------------------
		Vector2 inputDir = Vector2.Zero;
		if (touchInputManager != null)
		{
			inputDir = touchInputManager.MoveVector;
		}
		if (inputDir.LengthSquared() < 0.0001f)
		{
			inputDir = Input.GetVector("ui_left", "ui_right", "ui_up", "ui_down");
		}

		float stickMagnitude = Mathf.Clamp(inputDir.Length(), 0f, 1f);

		if (stickMagnitude > 0.01f)
		{
			Vector3 targetMoveDir = AnalogToWorldDirection(inputDir);
			CurrentInput.Direction = targetMoveDir;
			CurrentInput.AnalogMagnitude = stickMagnitude;

			// Turn the body towards the travel direction. Exponential smoothing keeps the
			// turn rate identical at 30, 60 or 120 fps (the old deltaFloat * 12f factor did not).
			float targetAngle = Mathf.Atan2(targetMoveDir.X, targetMoveDir.Z);
			float turnT = 1f - Mathf.Exp(-TurnResponse * deltaFloat);
			Rotation = new Vector3(Rotation.X, Mathf.LerpAngle(Rotation.Y, targetAngle, turnT), Rotation.Z);
		}
		else
		{
			CurrentInput.Direction = Vector3.Zero;
			CurrentInput.AnalogMagnitude = 0f;
		}

		// ------------------------------------------------------------------
		// Speed selection. Stick magnitude drives speed continuously:
		//   light push  -> slow walk
		//   past RunStickThreshold -> blends up to RunningSpeed
		// ------------------------------------------------------------------
		float runBlend = Mathf.Clamp((stickMagnitude - RunStickThreshold) / Mathf.Max(0.01f, 1f - RunStickThreshold), 0f, 1f);
		float maxSpeedForStick = Mathf.Lerp(WalkingSpeed, RunningSpeed, Mathf.SmoothStep(0f, 1f, runBlend));

		if (IsOnFloor())
		{
			if (Action > 0)
			{
				// Sprinting only while stamina remains and the state machine agrees.
				bool wantsSprint = CurrentAction == CharacterActions.Running || runBlend > 0f;
				speed = (wantsSprint ? maxSpeedForStick : Mathf.Min(maxSpeedForStick, WalkingSpeed)) * SpeedMultiplier;
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
				velocity.Y = -1;
				speed = RunningSpeed * SpeedMultiplier;
			}
			else
			{
				Action = Mathf.Clamp(Action + deltaFloat, 0, 100);
				velocity.Y -= gravity * deltaFloat;
				float t = Mathf.MoveToward((float)(speed - WalkingSpeed) / (RunningSpeed - WalkingSpeed), 0, 1);
				speed = Mathf.Lerp(WalkingSpeed, RunningSpeed, t);
			}
		}

		// ------------------------------------------------------------------
		// Horizontal velocity. Accelerating towards the target instead of assigning it
		// outright is what removes the last bit of "snapping" from the controls.
		// ------------------------------------------------------------------
		Vector2 targetHorizontal;
		if (CurrentInput.Direction != Vector3.Zero)
		{
			// Analog curve: 1.0 = fully linear, >1 = slower at low stick, snappier near full.
			float analogScale = Mathf.Pow(stickMagnitude, AnalogSpeedCurve);
			targetHorizontal = new Vector2(CurrentInput.Direction.X, CurrentInput.Direction.Z) * (speed * analogScale);
		}
		else
		{
			targetHorizontal = Vector2.Zero;
		}

		float accel = GroundAcceleration * (IsOnFloor() ? 1f : 0.35f);
		float maxStep = accel * deltaFloat;

		velocity.X = Mathf.MoveToward(velocity.X, targetHorizontal.X, maxStep);
		velocity.Z = Mathf.MoveToward(velocity.Z, targetHorizontal.Y, maxStep);

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
		// Consume (not read) the touch delta: TouchInputManager accumulates drag events and
		// zeroes them here, so the camera stops the moment the finger stops.
		Vector2 camDelta = Vector2.Zero;
		if (touchInputManager != null)
		{
			camDelta = touchInputManager.ConsumeCameraDelta();
		}
		CameraRotationAxis.X = camDelta.X;
		CameraRotationAxis.Y = camDelta.Y;

		float targetFov = 75;
		float fovLerpTime = 0.5f; // adjust this value to control the speed of the FOV change

		// Use the full movement magnitude: the old `Direction.Z != 0` test missed strafing
		// entirely, so the FOV never widened when running sideways.
		float moveAmount = CurrentInput.AnalogMagnitude;
		if (moveAmount > 0.01f)
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
			// Pitch is clamped on every platform now; on Android it previously wasn't, so the
			// camera could roll over the character's head.
			cam_rot_x = Mathf.Clamp(cam_rot_x - CameraRotationAxis.Y, CameraPitchMin, CameraPitchMax);
			cam_rot_y += CameraRotationAxis.X;

			// Keep yaw in -180..180 so it never drifts into huge values on a long session.
			if (cam_rot_y > 180f) cam_rot_y -= 360f;
			else if (cam_rot_y < -180f) cam_rot_y += 360f;

			CameraRotationAxis = Vector3.Zero;
		}

		// Frame-rate independent FOV easing.
		float fovT = 1f - Mathf.Exp(-fovLerpTime * 6f * deltaFloat);
		PlayerCamera.Fov = Mathf.Lerp(PlayerCamera.Fov, targetFov, fovT);

		// Camera pivot rotates horizontally (Y yaw) and vertically (X pitch) independently from character body
		CameraPivot.RotationDegrees = new Vector3(cam_rot_x, cam_rot_y, 0);
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

	public void UpdateHelpers(float deltaFloat)
	{
		string text = CharacterName+ "\n" + TerrainManager.Instance.CameraInChunk();
		if (PopupInfo == null)
		{
			PopupInfo = Debug.SetTextHelper(text, CameraPivot.Position, CameraPivot);
			PopupInfo.MaxViewDistance = 1000;
		}
		if (PopupInfo != null)
		{
			text = text;// + "\n" + CurrentAction + " " + TerrainManager.Instance.GetTerrainHeightAtGlobalCoordinate(new Vector2(Position.X, Position.Z)).ToString();
						//Mathf.RadToDeg(GetFloorAngle()) + " Pos: X: " + string.Format("{0:0. #}", Position.X) + " Y: " + string.Format("{0:0. #}", Position.Y) + " Z: " + string.Format("{0:0. #}", Position.Z) ;
						//GD.Print(TerrainGenerator.Instance.CameraInChunk());
			PopupInfo.SetText(text);
#if GODOT_ANDROID
				PopupInfo.SetSize(50);
#endif
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

	/// <summary>
	/// Touch-only input handling. This project ships as an Android build, so the previous
	/// mouse / mouse-motion / gamepad branches have been removed along with their
	/// GODOT_WINDOWS blocks.
	/// </summary>
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

		if (Input.IsActionJustPressed("torch"))
		{
			SpotLight.Visible = !SpotLight.Visible;
		}

		// JustPressed, not IsActionPressed: the old code ran this on *every* input event while
		// the button was held, and it also spawned a crate inline *and* called LaunchAttack()
		// (which spawns another one) — so a single tap produced two crates. LaunchAttack()
		// already owns spawning plus the cooldown, so it is the only caller now.
		if (Input.IsActionJustPressed("attack"))
		{
			CurrentInput.SetAttack();
			LaunchAttack();
		}
	}
}
