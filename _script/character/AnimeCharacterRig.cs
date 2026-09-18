////////////////////////////////////////////////////////////////////////////////////////////
/// This script is part of the project "Infinite Runner", a procedural generation project
/// By Adrien Pierret
///
/// AnimeCharacterRig: plays the Universal Animation Library clips on the VRM anime character.
///
/// Why this is needed
/// ------------------
/// Three different skeletons live in this project:
///   1. _models/mannequin_f.glb     Unreal-style names (pelvis, spine_01, upperarm_l ...)
///   2. _models/ual_anims.glb       the SAME 65 names, carrying 43 animations
///   3. _models/anime_character.glb VRM, 129 joints named J_Bip_* / J_Sec_*
///
/// (1) and (2) line up 1:1. The anime character shares NO bone names with either, so a clip has
/// to be rebuilt with every track re-pointed at the matching bone.
///
/// Re-pointing the name is not enough. The two rigs also have different rest orientations, so
/// copying a rotation straight across twists the limbs. Each rotation is therefore converted
/// through the bones' global rest poses:
///
///     q_target = R_target_rest^-1 * R_source_rest * q_source
///
/// which makes the target bone reach the same world-space orientation the source bone had.
///
/// Godot does have retargeting built in, but its BoneMap lives on the *importer*, not on the
/// runtime Skeleton3D node (Skeleton3D exposes only animate_physical_bones,
/// modifier_callback_mode_process, motion_scale and show_rest_only). So the mapping is carried
/// here instead. _models/retarget/*.tres hold the same mapping for use in the editor's
/// import dock if you prefer to bake it offline.
///
/// Everything is defensive: any failure logs and leaves the existing rig alone, so the worst
/// case is "looks like it did before", never a crash. Set Enabled=false to opt out entirely.
///////////////////////////////////////////////////////////////////////////////////////////

using Godot;
using System.Collections.Generic;

public partial class AnimeCharacterRig : Node
{
	[ExportGroup("Toggle")]

	/// <summary>
	/// Turn this off to fall back to the original model. Nothing else in the scene has to
	/// change, which is the point: the swap is always reversible.
	/// </summary>
	[Export] public bool Enabled = true;

	[ExportGroup("Sources")]

	[Export] public PackedScene AnimeCharacterScene;
	[Export] public PackedScene UalAnimationsScene;

	[ExportGroup("Targets")]

	/// <summary>Where the anime model gets mounted.</summary>
	[Export] public NodePath MountPoint;

	/// <summary>The AnimationPlayer the existing state machine already reads from.</summary>
	[Export] public AnimationPlayer TargetPlayer;

	/// <summary>Node to hide once the anime model is up (the old mannequin/robot visual).</summary>
	[Export] public NodePath LegacyModelToHide;

	[ExportGroup("Appearance")]

	[Export] public float ModelScale = 1.0f;
	[Export] public Vector3 ModelOffset = Vector3.Zero;

	[ExportGroup("Animation mapping")]

	/// <summary>
	/// Game animation name -> Universal Animation Library clip name. Editable in the inspector
	/// so clips can be swapped without touching code.
	///
	/// NOTE: UAL2 *Standard* has no clean walk/run/sprint loop. The defaults below are the
	/// closest clips available; replace them if you own the Pro pack or author your own.
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
		"Idle_No_Loop", "Idle_FoldArms_Loop", "Idle_Lantern_Loop", "Idle_Rail_Loop",
		"Idle_Shield_Loop", "Idle_TalkingPhone_Loop", "NinjaJump_Idle_Loop", "Slide_Loop",
		"Walk_Carry_Loop", "Zombie_Walk_Fwd_Loop", "Zombie_Idle_Loop", "TreeChopping_Loop",
	};

	/// <summary>Set once the swap succeeded.</summary>
	public bool IsActive { get; private set; } = false;

	/// <summary>
	/// UAL bone name -> anime (VRM) bone name. Generated from
	/// _models/retarget/bonemap_ual_mannequin.tres and bonemap_vrm_anime.tres, both of which
	/// resolve onto SkeletonProfileHumanoid, so the pairing is the same one Godot would use.
	/// Leaf bones (thumb_04_leaf_l, ball_leaf_l) have no humanoid counterpart and are absent;
	/// their tracks are dropped, which is correct.
	/// </summary>
	private static readonly Dictionary<string, string> UalToAnime = new Dictionary<string, string>
	{
		{ "Head", "J_Bip_C_Head" },
		{ "ball_l", "J_Bip_L_ToeBase" },
		{ "ball_r", "J_Bip_R_ToeBase" },
		{ "calf_l", "J_Bip_L_LowerLeg" },
		{ "calf_r", "J_Bip_R_LowerLeg" },
		{ "clavicle_l", "J_Bip_L_Shoulder" },
		{ "clavicle_r", "J_Bip_R_Shoulder" },
		{ "foot_l", "J_Bip_L_Foot" },
		{ "foot_r", "J_Bip_R_Foot" },
		{ "hand_l", "J_Bip_L_Hand" },
		{ "hand_r", "J_Bip_R_Hand" },
		{ "index_01_l", "J_Bip_L_Index1" },
		{ "index_01_r", "J_Bip_R_Index1" },
		{ "index_02_l", "J_Bip_L_Index2" },
		{ "index_02_r", "J_Bip_R_Index2" },
		{ "index_03_l", "J_Bip_L_Index3" },
		{ "index_03_r", "J_Bip_R_Index3" },
		{ "lowerarm_l", "J_Bip_L_LowerArm" },
		{ "lowerarm_r", "J_Bip_R_LowerArm" },
		{ "middle_01_l", "J_Bip_L_Middle1" },
		{ "middle_01_r", "J_Bip_R_Middle1" },
		{ "middle_02_l", "J_Bip_L_Middle2" },
		{ "middle_02_r", "J_Bip_R_Middle2" },
		{ "middle_03_l", "J_Bip_L_Middle3" },
		{ "middle_03_r", "J_Bip_R_Middle3" },
		{ "neck_01", "J_Bip_C_Neck" },
		{ "pelvis", "J_Bip_C_Hips" },
		{ "pinky_01_l", "J_Bip_L_Little1" },
		{ "pinky_01_r", "J_Bip_R_Little1" },
		{ "pinky_02_l", "J_Bip_L_Little2" },
		{ "pinky_02_r", "J_Bip_R_Little2" },
		{ "pinky_03_l", "J_Bip_L_Little3" },
		{ "pinky_03_r", "J_Bip_R_Little3" },
		{ "ring_01_l", "J_Bip_L_Ring1" },
		{ "ring_01_r", "J_Bip_R_Ring1" },
		{ "ring_02_l", "J_Bip_L_Ring2" },
		{ "ring_02_r", "J_Bip_R_Ring2" },
		{ "ring_03_l", "J_Bip_L_Ring3" },
		{ "ring_03_r", "J_Bip_R_Ring3" },
		{ "root", "Root" },
		{ "spine_01", "J_Bip_C_Spine" },
		{ "spine_02", "J_Bip_C_Chest" },
		{ "spine_03", "J_Bip_C_UpperChest" },
		{ "thigh_l", "J_Bip_L_UpperLeg" },
		{ "thigh_r", "J_Bip_R_UpperLeg" },
		{ "thumb_01_l", "J_Bip_L_Thumb1" },
		{ "thumb_01_r", "J_Bip_R_Thumb1" },
		{ "thumb_02_l", "J_Bip_L_Thumb2" },
		{ "thumb_02_r", "J_Bip_R_Thumb2" },
		{ "thumb_03_l", "J_Bip_L_Thumb3" },
		{ "thumb_03_r", "J_Bip_R_Thumb3" },
		{ "upperarm_l", "J_Bip_L_UpperArm" },
		{ "upperarm_r", "J_Bip_R_UpperArm" },	};

	private readonly HashSet<string> _loopSet = new HashSet<string>();

	public override void _Ready()
	{
		if (!Enabled)
		{
			GD.Print("[AnimeCharacterRig] disabled, keeping the original rig.");
			return;
		}

		if (AnimeCharacterScene == null || UalAnimationsScene == null || TargetPlayer == null)
		{
			GD.PrintErr("[AnimeCharacterRig] AnimeCharacterScene, UalAnimationsScene and TargetPlayer must all be assigned.");
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

		// ---- 1. Mount the anime model ------------------------------------------------
		Node modelRoot = AnimeCharacterScene.Instantiate();
		modelRoot.Name = "AnimeCharacterModel";
		mount.AddChild(modelRoot);
		if (modelRoot is Node3D model3D)
		{
			// Node has no Scale/Position; only Node3D does.
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

		// ---- 2. Bring in the UAL clips ------------------------------------------------
		Node animsRoot = UalAnimationsScene.Instantiate();
		animsRoot.Name = "_UalAnimationSource";
		AddChild(animsRoot);

		Skeleton3D ualSkeleton = FindFirstSkeleton(animsRoot);
		AnimationPlayer ualPlayer = FindFirstAnimationPlayer(animsRoot);
		if (ualSkeleton == null || ualPlayer == null)
		{
			GD.PrintErr($"[AnimeCharacterRig] UAL source incomplete (skeleton={ualSkeleton != null}, player={ualPlayer != null}).");
			animsRoot.QueueFree();
			modelRoot.QueueFree();
			return;
		}

		// Proportion correction for the hips translation track.
		float heightRatio = ComputeHeightRatio(ualSkeleton, animeSkeleton);

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

			Animation remapped = BuildRetargetedClip(ualPlayer, ualName, animeSkeleton, ualSkeleton, heightRatio);
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

		// ---- 4. Hide the old visual ---------------------------------------------------
		if (!LegacyModelToHide.IsEmpty)
		{
			if (GetNodeOrNull(LegacyModelToHide) is CanvasItem legacyItem)
			{
				legacyItem.Visible = false;
			}
		}

		IsActive = true;
		GD.Print($"[AnimeCharacterRig] active: {replaced} clips retargeted, {skipped} skipped, height ratio {heightRatio:F3}.");
	}

	// ------------------------------------------------------------------

	/// <summary>
	/// Ratio of the two rigs' hip heights, used to scale the hips translation so a crouch or a
	/// bob lands at the right height on the anime body.
	/// </summary>
	private static float ComputeHeightRatio(Skeleton3D source, Skeleton3D target)
	{
		float s = HipHeight(source, "pelvis");
		float t = HipHeight(target, "J_Bip_C_Hips");
		if (s <= 0.0001f || t <= 0.0001f) return 1f;
		return t / s;
	}

	private static float HipHeight(Skeleton3D sk, string boneName)
	{
		int idx = sk.FindBone(boneName);
		if (idx < 0) return 0f;
		return sk.GetBoneGlobalRest(idx).Origin.Y;
	}

	/// <summary>
	/// Rebuilds one UAL clip so its tracks drive the anime skeleton.
	/// </summary>
	private Animation BuildRetargetedClip(AnimationPlayer source, string clipName,
										  Skeleton3D target, Skeleton3D sourceSkeleton,
										  float heightRatio)
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

		// Tracks address the skeleton by node path; find where the target skeleton lives so the
		// prefix can be swapped. NodePath has no implicit string conversion.
		string targetPath = TargetPlayer.GetPathTo(target).ToString();

		int mappedTracks = 0;
		int droppedTracks = 0;

		for (int i = 0; i < src.GetTrackCount(); i++)
		{
			Animation.TrackType type = src.TrackGetType(i);
			bool isRotation = type == Animation.TrackType.Rotation3D;
			bool isPosition = type == Animation.TrackType.Position3D;
			bool isScale = type == Animation.TrackType.Scale3D;

			if (!isRotation && !isPosition && !isScale)
			{
				// Blend shapes / method calls / generic value tracks are not portable between two
				// unrelated rigs. Dropping them is the safe behaviour.
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
			if (!UalToAnime.TryGetValue(sourceBone, out string targetBone))
			{
				// Leaf bones and VRM spring bones (J_Sec_*) have no counterpart.
				droppedTracks++;
				continue;
			}

			// Position tracks encode the source rig's limb lengths, which mean nothing on a
			// different body. Keep only the hips translation (scaled), drop the rest.
			bool isHips = targetBone == "J_Bip_C_Hips";
			if (isPosition && !isHips)
			{
				droppedTracks++;
				continue;
			}

			int srcBoneIdx = sourceSkeleton.FindBone(sourceBone);
			int dstBoneIdx = target.FindBone(targetBone);
			if (srcBoneIdx < 0 || dstBoneIdx < 0)
			{
				droppedTracks++;
				continue;
			}

			// q_target = R_target_rest^-1 * R_source_rest * q_source
			Basis correction = Basis.Identity;
			if (isRotation)
			{
				Basis srcRest = sourceSkeleton.GetBoneGlobalRest(srcBoneIdx).Basis;
				Basis dstRest = target.GetBoneGlobalRest(dstBoneIdx).Basis;
				correction = dstRest.Inverse() * srcRest;
			}

			int newTrack = dst.AddTrack(type);
			dst.TrackSetPath(newTrack, new NodePath(targetPath + ":" + targetBone));
			dst.TrackSetInterpolationType(newTrack, src.TrackGetInterpolationType(i));
			dst.TrackSetEnabled(newTrack, src.TrackIsEnabled(i));

			int keyCount = src.TrackGetKeyCount(i);
			for (int k = 0; k < keyCount; k++)
			{
				double time = src.TrackGetKeyTime(i, k);
				Variant value = src.TrackGetKeyValue(i, k);
				float transition = src.TrackGetKeyTransition(i, k);

				if (isRotation && value.VariantType == Variant.Type.Quaternion)
				{
					Quaternion q = value.AsQuaternion();
					// Godot C# defines no Basis * Quaternion operator, so convert the
					// correction basis into a quaternion and multiply quaternion-by-quaternion.
					Quaternion corrected = new Quaternion(correction) * q;
					dst.TrackInsertKey(newTrack, time, Variant.From(corrected), transition);
				}
				else if (isPosition && value.VariantType == Variant.Type.Vector3)
				{
					Vector3 v = value.AsVector3();
					dst.TrackInsertKey(newTrack, time, Variant.From(new Vector3(v.X, v.Y * heightRatio, v.Z) * heightRatio), transition);
				}
				else
				{
					dst.TrackInsertKey(newTrack, time, value, transition);
				}
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
