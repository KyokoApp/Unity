////////////////////////////////////////////////////////////////////////////////////////////
/// This script is part of the project "Infinite Runner", a procedural generation project
/// By Adrien Pierret
///
/// TouchInputManager: Mobile dynamic analog joystick & camera touch controls.
/// Anime / Mobile Action RPG style floating analog joystick (Genshin-like).
///
/// Design notes:
///  - The joystick is a pure analog source. It never simulates ui_left/ui_right/... D-Pad
///    actions, because those are digital and would throw away the stick magnitude.
///    Consumers read `MoveVector` (a Vector2 whose length goes 0..1) instead.
///  - The camera delta is a *consumed* value. Whoever reads it must call
///    ConsumeCameraDelta(), otherwise the camera keeps spinning after the finger stops
///    moving (this used to be a bug here).
///////////////////////////////////////////////////////////////////////////////////////////

using Godot;
using System.Collections.Generic;

public partial class TouchInputManager : Node2D
{
	private int movementTouchIndex = -1;
	private int cameraTouchIndex = -1;

	// Joystick visual & control parameters
	private Vector2 joystickCenter = Vector2.Zero;
	private Vector2 joystickCurrentPos = Vector2.Zero;
	private bool isJoystickActive = false;

	[Export] public float JoystickRadius = 65f;
	[Export] public float JoystickDeadzone = 10f;
	[Export] public float RunThreshold = 0.75f; // Stick magnitude (0..1) at which we start sprinting.

	/// <summary>
	/// Smoothing applied to the stick vector, in "response per second".
	/// Higher = snappier, lower = floatier. 18 feels close to Genshin on a phone.
	/// </summary>
	[Export] public float StickSmoothing = 18f;

	[Export] public float CameraSensitivity = 0.05f;

	/// <summary>Raw camera delta accumulated since the last ConsumeCameraDelta() call.</summary>
	private Vector2 pendingCameraDelta = Vector2.Zero;

	/// <summary>Un-smoothed stick target; MoveVector eases towards this every frame.</summary>
	private Vector2 _targetMoveVector = Vector2.Zero;

	/// <summary>Screen position of the previous camera-touch event.</summary>
	private Vector2 _lastCameraTouchPos = Vector2.Zero;

	/// <summary>
	/// Smoothed analog movement vector. X = strafe (-1 left .. 1 right),
	/// Y = forward/back (-1 forward .. 1 backward, screen-space). Length is 0..1.
	/// </summary>
	public Vector2 MoveVector { get; private set; } = Vector2.Zero;

	/// <summary>True while the stick is pushed past RunThreshold.</summary>
	public bool WantsRun { get; private set; } = false;

	public override void _Ready()
	{
		// Draw on canvas layer above game
		ZIndex = 100;
		Visible = true;
		QueueRedraw();
	}

	public override void _Process(double delta)
	{
		// Frame-rate independent exponential smoothing towards the target stick vector.
		// Using 1 - exp(-k * dt) instead of a bare lerp factor keeps the feel identical
		// whether the device runs at 30, 60 or 120 fps.
		float t = 1f - Mathf.Exp(-StickSmoothing * (float)delta);
		MoveVector = MoveVector.Lerp(_targetMoveVector, t);

		// Snap to exactly zero so idle characters never drift.
		if (MoveVector.LengthSquared() < 0.0001f)
		{
			MoveVector = Vector2.Zero;
		}

		// Sprint is derived from how far the stick is pushed, not from raw pixel distance,
		// so it behaves the same on every screen density.
		WantsRun = MoveVector.Length() >= RunThreshold;
		Input.ActionRelease("run");
		if (WantsRun)
		{
			Input.ActionPress("run");
		}
	}

	/// <summary>
	/// Returns the camera drag accumulated since the last call and resets it.
	/// Call this exactly once per frame from the camera consumer.
	/// </summary>
	public Vector2 ConsumeCameraDelta()
	{
		Vector2 d = pendingCameraDelta;
		pendingCameraDelta = Vector2.Zero;
		return d;
	}

	public override void _Draw()
	{
		// Only appear when actively touched on the screen
		if (!isJoystickActive) return;

		Vector2 center = joystickCenter;
		Vector2 knob = joystickCurrentPos;

		// Modern Anime RPG translucent aesthetic (white translucent rings and glowing thumb knob)
		Color ringColor = new Color(1f, 1f, 1f, 0.25f);
		Color ringBorderColor = new Color(1f, 1f, 1f, 0.65f);
		Color innerRingColor = new Color(1f, 1f, 1f, 0.30f);
		Color knobFill = new Color(1f, 1f, 1f, 0.75f);
		Color knobBorder = new Color(1f, 1f, 1f, 0.95f);

		// Outer base background circle
		DrawCircle(center, JoystickRadius, ringColor);
		// Outer ring border
		DrawArc(center, JoystickRadius, 0, Mathf.Tau, 48, ringBorderColor, 2f, true);

		// Decorative middle guideline circle
		DrawArc(center, JoystickRadius * 0.5f, 0, Mathf.Tau, 32, innerRingColor, 1.2f, true);

		// Run threshold ring, so the player can see where sprint kicks in
		DrawArc(center, JoystickRadius * RunThreshold, 0, Mathf.Tau, 32,
			new Color(1f, 1f, 1f, WantsRun ? 0.55f : 0.18f), 1.5f, true);

		// Line connecting center to knob
		if (knob.DistanceTo(center) > 4f)
		{
			DrawLine(center, knob, new Color(1f, 1f, 1f, 0.35f), 2f, true);
		}

		// Joystick knob (draggable thumb)
		float knobRadius = JoystickRadius * 0.38f;
		DrawCircle(knob, knobRadius, knobFill);
		DrawArc(knob, knobRadius, 0, Mathf.Tau, 32, knobBorder, 2f, true);
	}

	public override void _Input(InputEvent @event)
	{
		if (@event is InputEventScreenTouch touchEvent)
		{
			if (touchEvent.Pressed)
			{
				OnTouchStart(touchEvent.Position, touchEvent.Index);
			}
			else
			{
				OnTouchEnd(touchEvent.Index);
			}
		}
		else if (@event is InputEventScreenDrag dragEvent)
		{
			OnTouchDrag(dragEvent.Position, dragEvent.Index);
		}
	}

	private void OnTouchStart(Vector2 position, int index)
	{
		float screenWidth = GetViewport().GetVisibleRect().Size.X;

		// Left 50% screen width: Dynamic Floating Analog Joystick
		if (position.X < screenWidth * 0.5f)
		{
			if (movementTouchIndex == -1)
			{
				movementTouchIndex = index;
				joystickCenter = position;
				joystickCurrentPos = position;
				isJoystickActive = true;
				QueueRedraw();
			}
		}
		else // Right 50% screen: Camera Rotation
		{
			if (cameraTouchIndex == -1)
			{
				cameraTouchIndex = index;
				// Seed with the touch position so the first drag event produces a real delta
				// instead of a jump from (0,0).
				_lastCameraTouchPos = position;
				pendingCameraDelta = Vector2.Zero;
			}
		}
	}

	private void OnTouchEnd(int index)
	{
		if (index == movementTouchIndex)
		{
			movementTouchIndex = -1;
			isJoystickActive = false;
			_targetMoveVector = Vector2.Zero;
			QueueRedraw();
		}

		if (index == cameraTouchIndex)
		{
			pendingCameraDelta = Vector2.Zero;
			cameraTouchIndex = -1;
		}
	}

	private void OnTouchDrag(Vector2 position, int index)
	{
		if (index == movementTouchIndex && isJoystickActive)
		{
			Vector2 offset = position - joystickCenter;
			float dist = offset.Length();

			// Clamp knob within JoystickRadius
			if (dist > JoystickRadius)
			{
				joystickCurrentPos = joystickCenter + offset.Normalized() * JoystickRadius;
			}
			else
			{
				joystickCurrentPos = position;
			}

			QueueRedraw();

			if (dist < JoystickDeadzone)
			{
				_targetMoveVector = Vector2.Zero;
				return;
			}

			// Normalised direction * analog magnitude (0..1). Keeping the magnitude is what
			// makes a gentle push walk and a full push run, instead of snapping to full speed.
			Vector2 dir = offset.Normalized();
			float magnitude = Mathf.Clamp((dist - JoystickDeadzone) / Mathf.Max(1f, JoystickRadius - JoystickDeadzone), 0f, 1f);
			_targetMoveVector = dir * magnitude;
		}
		else if (index == cameraTouchIndex)
		{
			Vector2 delta = position - _lastCameraTouchPos;
			_lastCameraTouchPos = position;
			// Accumulate instead of overwrite: several drag events can arrive between two
			// rendered frames, and overwriting would drop input.
			pendingCameraDelta += new Vector2(-delta.X * CameraSensitivity, -delta.Y * CameraSensitivity);
			QueueRedraw();
		}
	}

}
