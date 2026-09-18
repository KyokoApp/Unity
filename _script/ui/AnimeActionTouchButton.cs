using Godot;
using System;

public partial class AnimeActionTouchButton : Control
{
    [Export] public string ActionName = "";
    [Export] public string LabelText = "ATK";
    [Export] public int FontSize = 28;
    [Export] public float ButtonRadius = 55f;
    [Export] public Color BaseColor = new Color(1f, 1f, 1f, 0.22f);
    [Export] public Color PressedColor = new Color(1f, 1f, 1f, 0.50f);
    [Export] public Color BorderColor = new Color(1f, 1f, 1f, 0.75f);

    private bool isPressed = false;
    private int touchIndex = -1;

    public override void _Ready()
    {
        CustomMinimumSize = new Vector2(ButtonRadius * 2, ButtonRadius * 2);
        MouseFilter = MouseFilterEnum.Pass;
    }

    public override void _Draw()
    {
        Vector2 center = Size * 0.5f;
        float radius = Mathf.Min(center.X, center.Y) - 2f;

        Color fillColor = isPressed ? PressedColor : BaseColor;
        Color outlineColor = isPressed ? Colors.White : BorderColor;

        // Outer glow on press
        if (isPressed)
        {
            DrawArc(center, radius + 4f, 0, Mathf.Tau, 48, new Color(1f, 1f, 1f, 0.35f), 3f, true);
        }

        // Main circular button background
        DrawCircle(center, radius, fillColor);

        // Circular border
        DrawArc(center, radius, 0, Mathf.Tau, 64, outlineColor, 2.5f, true);

        // Inner decorative ring (Anime / Genshin RPG aesthetic)
        DrawArc(center, radius * 0.78f, 0, Mathf.Tau, 48, new Color(outlineColor.R, outlineColor.G, outlineColor.B, 0.3f), 1.2f, true);

        // Text label
        Font defaultFont = ThemeDB.FallbackFont;
        if (defaultFont != null && !string.IsNullOrEmpty(LabelText))
        {
            Vector2 stringSize = defaultFont.GetStringSize(LabelText, HorizontalAlignment.Center, -1, FontSize);
            Vector2 textPos = new Vector2(center.X - stringSize.X * 0.5f, center.Y + stringSize.Y * 0.35f);

            // Shadow
            DrawString(defaultFont, textPos + new Vector2(1, 2), LabelText, HorizontalAlignment.Left, -1, FontSize, new Color(0, 0, 0, 0.6f));
            // Foreground text
            DrawString(defaultFont, textPos, LabelText, HorizontalAlignment.Left, -1, FontSize, Colors.White);
        }
    }

    public override void _Input(InputEvent @event)
    {
        if (@event is InputEventScreenTouch touch)
        {
            Vector2 localPos = ToLocal(touch.Position);
            Vector2 center = Size * 0.5f;
            float dist = localPos.DistanceTo(center);

            if (touch.Pressed)
            {
                if (dist <= ButtonRadius && touchIndex == -1)
                {
                    touchIndex = touch.Index;
                    SetPressed(true);
                    GetViewport().SetInputAsHandled();
                }
            }
            else
            {
                if (touch.Index == touchIndex)
                {
                    touchIndex = -1;
                    SetPressed(false);
                    GetViewport().SetInputAsHandled();
                }
            }
        }
        else if (@event is InputEventScreenDrag drag && drag.Index == touchIndex)
        {
            Vector2 localPos = ToLocal(drag.Position);
            Vector2 center = Size * 0.5f;
            float dist = localPos.DistanceTo(center);

            if (dist > ButtonRadius * 1.6f)
            {
                touchIndex = -1;
                SetPressed(false);
            }
        }
    }

    private void SetPressed(bool pressed)
    {
        if (isPressed == pressed) return;
        isPressed = pressed;
        QueueRedraw();

        if (!string.IsNullOrEmpty(ActionName))
        {
            if (isPressed)
            {
                Input.ActionPress(ActionName);
            }
            else
            {
                Input.ActionRelease(ActionName);
            }
        }
    }
}
