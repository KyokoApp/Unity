////////////////////////////////////////////////////////////////////////////////////////////
/// This script is part of the project "Infinite Runner", a procedural generation project
/// By Adrien Pierret
///
/// AnimeCharacterRig: drives the VRM anime character with the Universal Animation Library
/// animations.
///
/// Why this exists
/// ---------------
/// The project ships three different skeletons:
///   1. _models/mannequin_f.glb  - Unreal-style names (pelvis, spine_01, upperarm_l ...)
///   2. _models/ual_anims.glb    - the SAME 65 names as (1), carrying 43 animations
///   3. _models/anime_character.glb - VRM, 129 joints named J_Bip_* / J_Sec_*
///
/// (1) and (2) line up 1:1, so UAL animations need no work to drive the mannequin. The anime
/// character shares NO bone names with either, so playing a UAL clip on it requires real
/// retargeting: every track has to be re-pointed at the matching bone, and the differing rest
/// orientations have to be compensated for or the limbs twist.
///
/// Rather than hand-rolling quaternion maths, this uses Godot's own retargeting. Both rigs get
/// a BoneMap onto the shared SkeletonProfileHumanoid, which is exactly the mechanism Godot uses
/// to convert between rigs. This class only rebuilds the track *paths* through that mapping and
/// hands the result to the existing AnimationPlayer, so the state machine in main_character.tscn
/// keeps working untouched.
///
/// Everything here is defensive: if any step fails it logs and leaves the existing rig alone,
/// so the worst case is "the character looks like it did before", never a crash.
///////////////////////////////////////////////////////////////////////////////////////////

using Godot;
using System.Collections.Generic;

public partial class AnimeCharacterRig : Node
{
	[ExportGroup("Toggle")]

	/// <summary>
	/// Turn this off to fall back to the original model. Nothing else in the scene needs
	/// to change, which is the point: the swap should always be reversible.
	/// </summary>
	[Export] public bool Enabled = true;

	[ExportGroup("Sources")]

	[Export] public PackedScene AnimeCharacterScene;
	[Export] public PackedScene UalAnimationsScene;

	[Export] public BoneMap UalBoneMap;
	[Export] public BoneMap AnimeBoneMap;

	[ExportGroup("Targets")]

	/// <summary>Where the anime model gets mounted (usually the existing armature node).</summary>
	[Export] public NodePath MountPoint;

	/// <summary>The AnimationPlayer the state machine already reads from.</summary>
	[Export] public AnimationPlayer TargetPlayer;

	/// <summary>Node to hide once the anime model is up (the old mannequin/robot visual).</summary>
	[Export] public NodePath LegacyModelToHide;

	[ExportGroup("Appearance")]

	[Export] public float ModelScale = 1.0f;
	[Export] public Vector3 ModelOffset = Vector3.Zero;

	/// <summary>
	/// Game animation name -> Universal Animation Library clip name.
	/// Editable in the inspector so clips can be swapped without touching code.
	///
	/// NOTE: UAL2 *Standard* has no clean walk/run/sprint loop. The defaults below are the
	/// closest available clips; replace them if you own the Pro pack or author your own.
	/// </summary>
	[Export] public Godot.Collections.Dictionary AnimationMap = new Godot.Collections.Dictionary
	{
		{ "Idle", "Idle_No_Loop" },
		{ "Run", "Walk_Carry_Loop" },
		{ "Sprint", "Zombie_Walk_Fwd_Loop" },
		{ "Fall", "NinjaJump_Idle_Loop" },
		{ "Fall2", "NinjaJump_Idle_Loop" },
		{ "Jump", "NinjaJump_Start" },
		{ "Jump2", "NinjaJump_Start" },
		{ "Jump3", "NinjaJump_Start" },
		{ "LongJump", "NinjaJump_Start" },
		{ "GroundSlide", "Slide_Loop" },
		{ "Crouch", "Slide_Start" },
		{ "Attack1", "Melee_Hook" },
		{ "Kick", "Sword_Regular_A" },
		{ "Hurt", "Hit_Knockback" },
		{ "WallJump", "ClimbUp_1m" },
		{ "WallSlide", "NinjaJump_Idle_Loop" },
		{ "Dive", "NinjaJump_Start" },
		{ "Emote1", "Yes" },
		{ "Emote2", "Consume" },
		{ "T-pose", "A_TPose" },
	};

	/// <summary>
	/// UAL clips that should loop. glTF carries no loop flag, so Godot imports every clip as
	/// non-looping and the loops have to be declared here.
	/// </summary>
	[Export] public Godot.Collections.Array<string> LoopingClips = new Godot.Collections.Array<string>
	{
		"Idle_No_Loop",
		"Idle_FoldArms_Loop",
		"Idle_Lantern_Loop",
		"Idle_Rail_Loop",
		"Idle_Shield_Loop",
		"Idle_TalkingPhone_Loop",
		"NinjaJump_Idle_Loop",
		"Slide_Loop",
		"Walk_Carry_Loop",
		"Zombie_Walk_Fwd_Loop",
		"Zombie_Idle_Loop",
		"TreeChopping_Loop",
	};

	/// <summary>Set once the swap succeeded. Other systems can check this.</summary>
	public bool IsActive { get; private set; } = false;

	private readonly HashSet<string> _loopSet = new HashSet<string>();

	public override void _Ready()
	{
		if (!Enabled)
		{
			GD.Print("[AnimeCharacterRig] disabled, keeping the original rig.");
			return;
		}

		if (AnimeCharacterScene == null || UalAnimationsScene == null)
		{
			GD.PrintErr("[AnimeCharacterRig] AnimeCharacterScene / UalAnimationsScene are not assigned.");
			return;
		}
		if (UalBoneMap == null || AnimeBoneMap == null)
		{
			GD.PrintErr("[AnimeCharacterRig] both BoneMaps must be assigned for retargeting.");
			return;
		}
		if (TargetPlayer == null)
		{
			GD.PrintErr("[AnimeCharacterRig] TargetPlayer is not assigned.");
			return;
		}

		foreach (string clip in LoopingClips)
		{
			if (!string.IsNullOrEmpty(clip)) _loopSet.Add(clip);
		}

		Node mount = MountPoint.IsEmpty ? GetParent() : GetNodeOrNull(MountPoint);
		if (mount == null)
		{
			GD.PrintErr($"[AnimeCharacterRig] mount point not found: {MountPoint}");
			return;
		}

		// ---- 1. Mount the anime model -------------------------------------------------
		Node modelRoot = AnimeCharacterScene.Instantiate();
		modelRoot.Name = "AnimeCharacterModel";
		mount.AddChild(modelRoot);
		if (modelRoot is Node3D model3D)
		{
			// Node has no Scale/Position; only Node3D does, so these belong inside the check.
			model3D.Scale = Vector3.One * ModelScale;
			model3D.Position = ModelOffset;
		}

		Skeleton3D animeSkeleton = FindFirstSkeleton(modelRoot);
		if (animeSkeleton == null)
		{
			GD.PrintErr("[AnimeCharacterRig] no Skeleton3D inside the anime model.");
			modelRoot.QueueFree();
			return;
		}

		// ---- 2. Teach Godot both rigs via the shared humanoid profile ------------------
		AssignBoneMap(animeSkeleton, AnimeBoneMap, "anime");

		Node animsRoot = UalAnimationsScene.Instantiate();
		AddChild(animsRoot); // kept as a child so the source skeleton stays alive for retargeting
		animsRoot.Name = "_UalAnimationSource";
		if (animsRoot is Node3D anims3D) anims3D.Visible = false;

		Skeleton3D ualSkeleton = FindFirstSkeleton(animsRoot);
		AnimationPlayer ualPlayer = FindFirstAnimationPlayer(animsRoot);
		if (ualSkeleton == null || ualPlayer == null)
		{
			GD.PrintErr($"[AnimeCharacterRig] UAL source incomplete (skeleton={ualSkeleton != null}, player={ualPlayer != null}).");
			animsRoot.QueueFree();
			modelRoot.QueueFree();
			return;
		}
		AssignBoneMap(ualSkeleton, UalBoneMap, "UAL");

		// ---- 3. Rebuild each clip against the anime skeleton ---------------------------
		AnimationLibrary library;
		if (!TargetPlayer.HasAnimationLibrary(""))
		{
			library = new AnimationLibrary();
			TargetPlayer.AddAnimationLibrary("", library);
		}
		else
		{
			library = TargetPlayer.GetAnimationLibrary("");
		}

		int replaced = 0;
		int skipped = 0;

		foreach (var pair in AnimationMap)
		{
			string gameName = pair.Key.AsString();
			string ualName = pair.Value.AsString();

			Animation remapped = BuildRetargetedClip(ualPlayer, ualName, animeSkeleton, ualSkeleton);
			if (remapped == null)
			{
				skipped++;
				continue;
			}

			// Overwrite in place: the state machine references animations by name, so keeping
			// the existing names means main_character.tscn does not have to change.
			if (library.HasAnimation(gameName))
			{
				library.RemoveAnimation(gameName);
			}
			library.AddAnimation(gameName, remapped);
			replaced++;
		}

		// The source skeleton is no longer needed once every track has been rebuilt.
		animsRoot.QueueFree();

		if (replaced == 0)
		{
			GD.PrintErr("[AnimeCharacterRig] no clips could be retargeted; leaving the original rig visible.");
			modelRoot.QueueFree();
			return;
		}

		// ---- 4. Hide the old visual ----------------------------------------------------
		if (!LegacyModelToHide.IsEmpty)
		{
			if (GetNodeOrNull(LegacyModelToHide) is CanvasItem legacyItem)
			{
				legacyItem.Visible = false;
			}
		}

		IsActive = true;
		GD.Print($"[AnimeCharacterRig] active: {replaced} clips retargeted, {skipped} skipped.");
	}

	// ------------------------------------------------------------------

	private static void AssignBoneMap(Skeleton3D skeleton, BoneMap map, string label)
	{
		skeleton.BoneMap = map;
		skeleton.SkeletonProfile = map.Profile;
		GD.Print($"[AnimeCharacterRig] bone map applied to {label} skeleton '{skeleton.Name}' " +
				 $"({skeleton.GetBoneCount()} bones).");
	}

	/// <summary>
	/// Rebuilds one UAL clip so its tracks point at the anime skeleton instead.
	/// Bone names are translated source -> humanoid profile -> target, which is the same
	/// round-trip Godot performs internally, so unmapped bones simply drop out.
	/// </summary>
	private Animation BuildRetargetedClip(AnimationPlayer source, string clipName,
										  Skeleton3D target, Skeleton3D sourceSkeleton)
	{
		if (!source.HasAnimation(clipName))
		{
			GD.Print($"[AnimeCharacterRig] clip '{clipName}' not found in the UAL library.");
			return null;
		}

		Animation src = source.GetAnimation(clipName);
		Animation dst = new Animation
		{
			Length = src.Length,
			Step = src.Step,
			LoopMode = _loopSet.Contains(clipName)
				? Animation.LoopModeEnum.Linear
				: Animation.LoopModeEnum.None,
		};

		// Tracks address the skeleton by node path; find where the source skeleton lives so we
		// can swap that prefix for the target's.
		// NodePath has no implicit conversion to string, so materialise it once here.
		string targetPath = TargetPlayer.GetPathTo(target).ToString();

		int mappedTracks = 0;
		int droppedTracks = 0;

		for (int i = 0; i < src.GetTrackCount(); i++)
		{
			Animation.TrackType type = src.TrackGetType(i);
			if (type != Animation.TrackType.Position3D &&
				type != Animation.TrackType.Rotation3D &&
				type != Animation.TrackType.Scale3D)
			{
				// Blend shapes / method calls / generic value tracks are not portable between
				// two unrelated rigs. Dropping them is the safe behaviour.
				droppedTracks++;
				continue;
			}

			NodePath path = src.TrackGetPath(i);
			if (path.GetSubNameCount() < 1)
			{
				droppedTracks++;
				continue;
			}

			string sourceBone = path.GetSubName(0).ToString();

			string targetBone = TranslateBone(sourceBone);
			if (string.IsNullOrEmpty(targetBone))
			{
				// Leaf bones (thumb_04_leaf_l, ball_leaf_l, ...) and VRM spring bones (J_Sec_*)
				// have no humanoid counterpart. Skipping them is correct, not an error.
				droppedTracks++;
				continue;
			}

			int newTrack = dst.AddTrack(type);
			dst.TrackSetPath(newTrack, new NodePath(targetPath + ":" + targetBone));
			dst.TrackSetInterpolationType(newTrack, src.TrackGetInterpolationType(i));
			dst.TrackSetInterpolationTypeLoopWrap(newTrack, src.TrackGetInterpolationTypeLoopWrap(i));
			dst.TrackSetEnabled(newTrack, src.TrackIsEnabled(i));

			int keyCount = src.TrackGetKeyCount(i);
			for (int k = 0; k < keyCount; k++)
			{
				float time = (float)src.TrackGetKeyTime(i, k);
				Variant value = src.TrackGetKeyValue(i, k);
				float transition = src.TrackGetKeyTransition(i, k);
				dst.TrackInsertKey(newTrack, time, value, transition);
			}

			mappedTracks++;
		}

		if (mappedTracks == 0)
		{
			GD.Print($"[AnimeCharacterRig] clip '{clipName}' produced no usable tracks.");
			return null;
		}

		return dst;
	}

	/// <summary>UAL bone name -> anime (VRM) bone name, via the shared humanoid profile.</summary>
	private string TranslateBone(string sourceBone)
	{
		StringName profileName = UalBoneMap.GetProfileBoneName(sourceBone);
		if (string.IsNullOrEmpty(profileName.ToString())) return null;

		StringName targetBone = AnimeBoneMap.GetSkeletonBoneName(profileName);
		if (string.IsNullOrEmpty(targetBone.ToString())) return null;

		return targetBone.ToString();
	}

	private static Skeleton3D FindFirstSkeleton(Node root)
	{
		if (root is Skeleton3D sk) return sk;
		foreach (Node child in root.GetChildren())
		{
			Skeleton3D found = FindFirstSkeleton(child);
			if (found != null) return found;
		}
		return null;
	}

	private static AnimationPlayer FindFirstAnimationPlayer(Node root)
	{
		if (root is AnimationPlayer ap) return ap;
		foreach (Node child in root.GetChildren())
		{
			AnimationPlayer found = FindFirstAnimationPlayer(child);
			if (found != null) return found;
		}
		return null;
	}
}
