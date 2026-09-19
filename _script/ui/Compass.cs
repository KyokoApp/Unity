////////////////////////////////////////////////////////////////////////////////////////////
/// This script is part of the project "Infinite Runner", a procedural generation project
/// By Adrien Pierret
/// 
/// Compass: The compass shown at the top. 
/// ///////////////////////////////////////////////////////////////////////////////////////

using Godot;
using System;

public partial class Compass : Control
{
    [Export] public Label Angle;
    [Export] public PanelContainer CompassContainer;

    public float CurrentAngle = 0;

    public enum LocationToPoint { Forward, Zero }

    public override void _Process(double delta)
    {
        UpdateCompass(delta);
    }

    private float currentSmoothedAngle = 0f;
    private float velocity = 0f; // Helps simulate damping effect
    private const float damping = 10f; // Controls how quickly it settles
    private const float stiffness = 20f; // Controls how much the needle flips back and forth

    public void UpdateCompass(double delta)
    {
        // Karakter bisa belum terdaftar saat boot (world.tscn dimuat terpisah)
        MainCharacter ch = GameManager.Instance != null ? GameManager.Instance.GetMainCharacter() : null;
        if (ch == null) { return; }
        float targetAngle = GetCompassHeading(ch);

        // Simulating flip-flop effect with a damped spring formula
        float angleDifference = Mathf.PosMod(targetAngle - currentSmoothedAngle + 180f, 360f) - 180f; // Shortest rotation direction

        velocity += angleDifference * (float)delta * stiffness;
        velocity *= Mathf.Exp(-damping * (float)delta); // Exponential decay for damping effect
        currentSmoothedAngle += velocity * (float)delta;

        currentSmoothedAngle = Mathf.PosMod(currentSmoothedAngle, 360f);

        updateAngleText(); // langsung (CallDeferred tiap frame sebelumnya)
    }

    private int _lastAngleText = -1;
    private float _lastNeedleRotation = -999f;

    void updateAngleText()
    {
        float invertedAngle = Mathf.PosMod(360f - currentSmoothedAngle, 360f);
        int rounded = (int)Mathf.Round(invertedAngle);
        // SetText hanya saat angka berubah (re-layout label setiap frame = boros).
        if (rounded != _lastAngleText)
        {
            _lastAngleText = rounded;
            Angle.Text = rounded.ToString("000");
        }
        if (Mathf.Abs(currentSmoothedAngle - _lastNeedleRotation) > 0.05f)
        {
            _lastNeedleRotation = currentSmoothedAngle;
            CompassContainer.RotationDegrees = currentSmoothedAngle;
        }
    }

    public static float GetCompassHeading(Node3D node)
    {
        if (node == null) { return 0f; }
        Vector3 forward = node.GlobalTransform.Basis.Z;

        float angle = Mathf.RadToDeg(Mathf.Atan2(forward.X, forward.Z));
        return Mathf.PosMod(angle + 360f, 360f); // Ensures angle is between 0-360
    }
}
