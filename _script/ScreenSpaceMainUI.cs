using Godot;
using System;

public partial class ScreenSpaceMainUI : Control
{
	// Called when the node enters the scene tree for the first time.

	[Export]
	public Label Distance;
	[Export]
	public ProgressBar ActionBar;

	[Export]
	public ProgressBar MojoBar;

	[Export]
	public Label Score;

	[Export]
	public Label Multiplier;

	[Export]
	public Label Record;
	[Export]
	public Label TimeOfDay;

	public override void _Ready()
	{

	}

	void UpdateTime()

	{
		updateTimeOfDay();
	}




	// HUD di-update 5x/detik (bukan tiap frame) dan SetText hanya saat nilai
	// berubah — SetText tiap frame memicu layout ulang label + alokasi string
	// terus-menerus (sampah GC setiap frame di mobile).
	private double _uiAccum = 0.0;
	private const double UiUpdateInterval = 0.2;

	private string _lastDistanceText = "";
	private string _lastScoreText = "";
	private string _lastMultText = "";
	private string _lastRecordText = "";
	private string _lastTimeText = "";

	public override void _Process(double delta)
	{
		_uiAccum += delta;
		if (_uiAccum < UiUpdateInterval) return;
		_uiAccum = 0.0;

		UpdateTime();
		UpdateDistance();
		UpdateActionBar();
		UpdateRecord();
	}

	void UpdateDistance()

	{
		updateDistance();
	}

	void UpdateActionBar()

	{
		updateActionBar();
	}

	void updateActionBar()
	{
		ActionBar.Value = GameManager.Instance.GetMainCharacterAction();
		MojoBar.Value = GameManager.Instance.GetMainCharacterMojo();

		string score = GameManager.Instance.GetMainCharacterScore().ToString();
		if (score != _lastScoreText) { Score.Text = score; _lastScoreText = score; }

		float multiplier = GameManager.Instance.StartingPoint.DistanceTo(GameManager.Instance.GetMainCharacterPosition());
			multiplier = Mathf.Clamp(multiplier/100,1,100);
			multiplier = Mathf.FloorToInt(multiplier);
		string mult = "x" + multiplier;
		if (mult != _lastMultText) { Multiplier.Text = mult; _lastMultText = mult; }
	}

	void UpdateRecord()

	{
		updateRecord();
	}

	void updateRecord()
	{
		float curdist = GameManager.Instance.StartingPoint.DistanceTo(GameManager.Instance.GetMainCharacterPosition());
		if (GameManager.Instance.Record < curdist)
		{
			string rec = curdist.ToString();
			if (rec != _lastRecordText) { Record.Text = rec; _lastRecordText = rec; }
			GameManager.Instance.Record = curdist;
		}
	}

	void updateDistance()
	{
		string dist = Mathf.FloorToInt(GameManager.Instance.StartingPoint.DistanceTo(GameManager.Instance.GetMainCharacterPosition())).ToString();
		if (dist != _lastDistanceText) { Distance.Text = dist; _lastDistanceText = dist; }
	}

	void updateTimeOfDay()
	{
		string timeText = EnvironmentManager.Instance.GetTime();
		if (timeText != _lastTimeText) { TimeOfDay.Text = timeText; _lastTimeText = timeText; }
	}
}
