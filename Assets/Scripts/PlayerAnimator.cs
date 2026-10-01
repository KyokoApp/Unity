using UnityEngine;
using UnityEngine.Animations;
using UnityEngine.Playables;

/// <summary>
/// Pemutar animasi berbasis PlayableGraph: crossfade 2 slot, loop manual,
/// hold pose non-loop, dan Foot IK opsional untuk clip ground locomotion.
/// Bisa di-rebind ke Animator lain (ganti model mannequin).
/// </summary>
public class PlayerAnimator : MonoBehaviour
{
    PlayableGraph graph;
    AnimationMixerPlayable mixer;
    bool hasGraph;

    readonly AnimationClipPlayable[] slot = new AnimationClipPlayable[2];
    readonly AnimationClip[] slotClip = new AnimationClip[2];
    readonly bool[] slotLoop = new bool[2];
    readonly bool[] slotFootIK = new bool[2];

    int cur = -1;
    float fadeT = 1f;
    float fadeDur = 0.15f;

    public AnimationClip CurrentClip { get { return cur >= 0 ? slotClip[cur] : null; } }
    public bool CurrentApplyFootIK { get { return cur >= 0 && slotFootIK[cur]; } }
    public float CurrentPlaybackSpeed
    {
        get { return cur >= 0 && slot[cur].IsValid() ? (float)slot[cur].GetSpeed() : 0f; }
    }

    public void Bind(Animator animator)
    {
        DestroyGraph();
        graph = PlayableGraph.Create("UAL2Graph");
        graph.SetTimeUpdateMode(DirectorUpdateMode.GameTime);
        mixer = AnimationMixerPlayable.Create(graph, 2);
        var output = AnimationPlayableOutput.Create(graph, "Anim", animator);
        output.SetSourcePlayable(mixer);
        graph.Play();
        hasGraph = true;
        cur = -1;
        fadeT = 1f;
    }

    public void Play(AnimationClip clip, bool loop, float speed = 1f, float fade = 0.15f, bool applyFootIK = false)
    {
        if (!hasGraph || clip == null) return;

        // Clip loop yang sama sedang jalan: cukup update kecepatan dan mode IK.
        // (Clip non-loop yang sama tetap di-restart dari awal.)
        if (cur >= 0 && slotClip[cur] == clip && slotLoop[cur] == loop && loop && slot[cur].IsValid())
        {
            slot[cur].SetSpeed(speed);
            slot[cur].SetApplyFootIK(applyFootIK);
            slotFootIK[cur] = applyFootIK;
            return;
        }

        int next = cur == 0 ? 1 : 0;
        if (slot[next].IsValid())
        {
            graph.Disconnect(mixer, next);
            graph.DestroyPlayable(slot[next]);
        }

        var p = AnimationClipPlayable.Create(graph, clip);
        p.SetApplyFootIK(applyFootIK);
        p.SetApplyPlayableIK(false);
        p.SetTime(0);
        p.SetSpeed(speed);
        p.SetDuration(double.MaxValue); // loop/hold diatur manual di Update

        mixer.ConnectInput(next, p, 0);

        slot[next] = p;
        slotClip[next] = clip;
        slotLoop[next] = loop;
        slotFootIK[next] = applyFootIK;

        if (cur < 0 || fade <= 0f)
        {
            mixer.SetInputWeight(next, 1f);
            if (cur >= 0) mixer.SetInputWeight(cur, 0f);
            fadeT = 1f;
        }
        else
        {
            fadeDur = fade;
            fadeT = 0f;
            mixer.SetInputWeight(next, 0f);
        }
        cur = next;
    }

    public void SetSpeed(float s)
    {
        if (cur >= 0 && slot[cur].IsValid()) slot[cur].SetSpeed(s);
    }

    public float NormalizedTime
    {
        get
        {
            if (cur < 0 || !slot[cur].IsValid()) return 1f;
            var c = slotClip[cur];
            if (c == null || c.length <= 0f) return 1f;
            return (float)(slot[cur].GetTime() / c.length);
        }
    }

    public bool IsDone(float margin = 0.03f)
    {
        if (cur < 0 || slotLoop[cur]) return false;
        return NormalizedTime >= 1f - margin;
    }

    void Update()
    {
        if (!hasGraph) return;

        // Crossfade antar slot.
        if (fadeT < 1f && cur >= 0 && slot[cur].IsValid())
        {
            fadeT = Mathf.MoveTowards(fadeT, 1f, Time.deltaTime / Mathf.Max(0.01f, fadeDur));
            float w = Mathf.SmoothStep(0f, 1f, fadeT);
            mixer.SetInputWeight(cur, w);
            int other = 1 - cur;
            if (slot[other].IsValid())
            {
                mixer.SetInputWeight(other, 1f - w);
                // Setelah fade selesai, slot lama cukup di-pause (dibuang saat slot dipakai ulang).
                if (fadeT >= 1f) slot[other].Pause();
            }
        }

        // Loop manual / tahan pose terakhir.
        for (int i = 0; i < 2; i++)
        {
            if (!slot[i].IsValid() || slotClip[i] == null) continue;
            double t = slot[i].GetTime();
            float len = slotClip[i].length;
            if (len <= 0f) continue;

            if (slotLoop[i])
            {
                if (t >= len) slot[i].SetTime(t % len);
            }
            else if (t > len)
            {
                slot[i].SetTime(len);
                slot[i].SetSpeed(0);
            }
        }
    }

    void OnDestroy()
    {
        DestroyGraph();
    }

    void DestroyGraph()
    {
        if (hasGraph && graph.IsValid()) graph.Destroy();
        hasGraph = false;
        for (int i = 0; i < 2; i++)
        {
            slot[i] = default(AnimationClipPlayable);
            slotClip[i] = null;
            slotLoop[i] = false;
            slotFootIK[i] = false;
        }
        cur = -1;
    }
}
