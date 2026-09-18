////////////////////////////////////////////////////////////////////////////////////////////
/// This script is part of the project "Infinite Runner", a procedural generation project
/// By Adrien Pierret
/// 
/// TouchInputManager: Mobile dynamic analog joystick & camera touch controls.
/// Anime / Mobile Action RPG style floating analog joystick.
///////////////////////////////////////////////////////////////////////////////////////////

using Godot;
using System.Collections.Generic;

public partial class TouchInputManager : Node2D
{
    private Dictionary<int, Vector2> activeTouches = new Dictionary<int, Vector2>();
    private int movementTouchIndex = -1;
    private int cameraTouchIndex = -1;

    // Joystick visual & control parameters
    private Vector2 joystickCenter = Vector2.Zero;
    private Vector2 joystickCurrentPos = Vector2.Zero;
    private bool isJoystickActive = false;

    [Export] public float JoystickRadius = 120f;
    [Export] public float JoystickDeadzone = 12f;
    [Export] public float DragThreshold = 20f;
    [Export] public float RunThreshold = 85f; // Distance from center to trigger sprinting

    public Vector2 CameraRotationAxis { get; private set; } = Vector2.Zero;
    private Dictionary<string, bool> activeActions = new Dictionary<string, bool>();

    private Vector2 lastCameraTouchPos = Vector2.Zero;

    // Analog directional input vector (-1 to 1)
    public Vector2 MoveVector { get; private set; } = Vector2.Zero;

    public override void _Ready()
    {
        // Draw on canvas layer above game
        ZIndex = 100;
        QueueRedraw();

        bool isMobile = OS.HasFeature("mobile") || OS.HasFeature("android") || DisplayServer.IsTouchscreenAvailable();
        #if GODOT_ANDROID
        isMobile = true;
        #endif
        Visible = isMobile;
    }

    public override void _Process(double delta)
    {
        // Maintain active actions
        foreach (var action in activeActions)
        {
            if (action.Value)
                Input.ActionPress(action.Key);
            else
                Input.ActionRelease(action.Key);
        }
    }

    public override void _Draw()
    {
        if (!isJoystickActive) return;

        // Modern Anime RPG translucent aesthetic (white translucent rings and glowing thumb knob)
        Color ringColor = new Color(1f, 1f, 1f, 0.22f);
        Color ringBorderColor = new Color(1f, 1f, 1f, 0.55f);
        Color innerRingColor = new Color(1f, 1f, 1f, 0.25f);
        Color knobFill = new Color(1f, 1f, 1f, 0.65f);
        Color knobBorder = new Color(1f, 1f, 1f, 0.95f);

        // Outer base background circle
        DrawCircle(joystickCenter, JoystickRadius, ringColor);
        // Outer ring border
        DrawArc(joystickCenter, JoystickRadius, 0, Mathf.Tau, 64, ringBorderColor, 2.5f, true);

        // Decorative middle guideline circle
        DrawArc(joystickCenter, JoystickRadius * 0.5f, 0, Mathf.Tau, 48, innerRingColor, 1.2f, true);

        // Line connecting center to knob
        if (joystickCurrentPos.DistanceTo(joystickCenter) > 4f)
        {
            DrawLine(joystickCenter, joystickCurrentPos, new Color(1f, 1f, 1f, 0.35f), 2f, true);
        }

        // Joystick knob (draggable thumb)
        float knobRadius = JoystickRadius * 0.35f;
        DrawCircle(joystickCurrentPos, knobRadius, knobFill);
        DrawArc(joystickCurrentPos, knobRadius, 0, Mathf.Tau, 48, knobBorder, 2.5f, true);
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
                lastCameraTouchPos = position;
            }
        }

        activeTouches[index] = position;
    }

    private void OnTouchEnd(int index)
    {
        if (index == movementTouchIndex)
        {
            StopMovement();
            Input.ActionRelease("run");
            movementTouchIndex = -1;
            isJoystickActive = false;
            MoveVector = Vector2.Zero;
            QueueRedraw();
        }

        if (index == cameraTouchIndex)
        {
            CameraRotationAxis = Vector2.Zero;
            cameraTouchIndex = -1;
        }

        activeTouches.Remove(index);
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
                StopMovement();
                Input.ActionRelease("run");
                MoveVector = Vector2.Zero;
                return;
            }

            Vector2 dir = offset.Normalized();
            MoveVector = dir * Mathf.Clamp((dist - JoystickDeadzone) / (JoystickRadius - JoystickDeadzone), 0f, 1f);

            // Sprinting check
            if (dist >= RunThreshold)
            {
                Input.ActionPress("run");
            }
            else
            {
                Input.ActionRelease("run");
            }

            // Map continuous direction to standard 4-way UI actions
            UpdateDirectionalActions(dir);
        }
        else if (index == cameraTouchIndex)
        {
            Vector2 delta = position - lastCameraTouchPos;
            float cameraSensitivity = 0.05f;
            CameraRotationAxis = new Vector2(-delta.X * cameraSensitivity, -delta.Y * cameraSensitivity);
            lastCameraTouchPos = position;
        }
    }

    private void UpdateDirectionalActions(Vector2 dir)
    {
        // Smooth analog mapping: threshold 0.35 allows diagonal movement
        float threshold = 0.35f;

        if (dir.X > threshold)
        {
            StartAction("ui_right");
            StopAction("ui_left");
        }
        else if (dir.X < -threshold)
        {
            StartAction("ui_left");
            StopAction("ui_right");
        }
        else
        {
            StopAction("ui_right");
            StopAction("ui_left");
        }

        if (dir.Y > threshold)
        {
            StartAction("ui_down");
            StopAction("ui_up");
        }
        else if (dir.Y < -threshold)
        {
            StartAction("ui_up");
            StopAction("ui_down");
        }
        else
        {
            StopAction("ui_down");
            StopAction("ui_up");
        }
    }

    private void StopMovement()
    {
        StopAction("ui_up");
        StopAction("ui_down");
        StopAction("ui_left");
        StopAction("ui_right");
    }

    public void StartAction(string actionName)
    {
        activeActions[actionName] = true;
    }

    public void StopAction(string actionName)
    {
        activeActions[actionName] = false;
    }
}
