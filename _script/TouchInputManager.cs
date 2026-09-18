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

    [Export] public float JoystickRadius = 65f;
    [Export] public float JoystickDeadzone = 10f;
    [Export] public float DragThreshold = 20f;
    [Export] public float RunThreshold = 55f; // Distance from center to trigger sprinting

    public Vector2 CameraRotationAxis { get; private set; } = Vector2.Zero;
    private Dictionary<string, bool> activeActions = new Dictionary<string, bool>();

    private Vector2 lastCameraTouchPos = Vector2.Zero;

    // Analog directional input vector (-1 to 1)
    public Vector2 MoveVector { get; private set; } = Vector2.Zero;

    public override void _Ready()
    {
        // Draw on canvas layer above game
        ZIndex = 100;
        Visible = true;
        GameSettings.EnsureLoaded();
        JoystickRadius *= GameSettings.JoystickScale;
        QueueRedraw();
    }

    // Info untuk debug overlay: sentuhan aktif & vektor gerak terakhir.
    public static int LiveTouchCount { get; private set; }

    // Diagnosa: total event sentuh mentah yang SEMPAT sampai ke node ini.
    public static long RawTouchEvents { get; private set; }
    public static TouchInputManager ActiveInstance { get; private set; }

    public bool IsJoystickActive => isJoystickActive;

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
        RawTouchEvents++;
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

    public override void _EnterTree()
    {
        ActiveInstance = this;
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
        LiveTouchCount = activeTouches.Count;
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
        LiveTouchCount = activeTouches.Count;
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

            // Pure smooth continuous analog vector without conflicting 4-way D-Pad simulation
        }
        else if (index == cameraTouchIndex)
        {
            Vector2 delta = position - lastCameraTouchPos;
            // Sensitivitas & inversi kamera dari menu Setting (user://game_settings.cfg)
            float cameraSensitivity = 0.05f * GameSettings.CameraSensitivity;
            float dirX = GameSettings.InvertCameraX ? 1f : -1f;
            float dirY = GameSettings.InvertCameraY ? 1f : -1f;
            CameraRotationAxis = new Vector2(dirX * delta.X * cameraSensitivity, dirY * delta.Y * cameraSensitivity);
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
