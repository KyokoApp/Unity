using System;
using System.Collections.Generic;
using System.IO;
using UnityEngine;
using RPG.Core;

namespace RPG.Runtime
{
    /* ============================================================
       BOOT LOG — perekam error sejak SEBELUM scene dimuat.

       Masalah yang diselesaikan: kalau game macet di HP, tidak ada
       logcat dan tidak ada console — penyebabnya tidak terlihat.
       Kelas ini menangkap semua Error/Exception/Warning Unity,
       menampilkannya di loading screen (kotak merah, didorong oleh
       WorldBoot), dan menulis salinan ke file:
         Application.persistentDataPath/aurelia-boot.log

       Thread-safe: TerrainChunkStreamer mencatat error dari thread
       latar, jadi semua akses dikunci dan handler TIDAK menyentuh
       API Unity (ilegal di luar main thread).
       ============================================================ */
    public static class BootLog
    {
        const int MaxLines = 40;

        static readonly List<string> _lines = new List<string>();
        static readonly object _gate = new object();
        static string _file;
        static bool _installed;
        static int _errorCount;

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.BeforeSceneLoad)]
        static void Install()
        {
            if (_installed) return;
            _installed = true;
            try
            {
                _file = Path.Combine(Application.persistentDataPath, "aurelia-boot.log");
                File.WriteAllText(_file,
                    $"=== boot {DateTime.Now:yyyy-MM-dd HH:mm:ss} ({Application.platform}) ===\n");
            }
            catch { _file = null; }
            Application.logMessageReceivedThreaded += OnLog;
            Add("BootLog aktif.");
        }

        static void OnLog(string msg, string stack, LogType type)
        {
            if (type != LogType.Error && type != LogType.Exception && type != LogType.Warning)
                return;
            /* Instancing tanpa flag material: spam tiap frame, bukan
               alasan kotak merah di loading. */
            if (WorldLookPolicy.IsNoisyLog(msg))
            {
                Add("[noise] " + msg);
                return;
            }
            var line = $"[{type}] {msg}";
            if ((type == LogType.Error || type == LogType.Exception) && !string.IsNullOrEmpty(stack))
            {
                var nl = stack.IndexOf('\n');
                line += "\n  @" + (nl >= 0 ? stack.Substring(0, nl) : stack);
            }
            Add(line);
        }

        public static void Add(string line)
        {
            if (string.IsNullOrEmpty(line)) return;
            lock (_gate)
            {
                _lines.Add(line);
                if (line.StartsWith("[Error]", StringComparison.Ordinal) ||
                    line.StartsWith("[Exception]", StringComparison.Ordinal) ||
                    line.IndexOf("FATAL", StringComparison.Ordinal) >= 0)
                    _errorCount++;
                while (_lines.Count > MaxLines) _lines.RemoveAt(0);
                if (_file != null)
                {
                    try { File.AppendAllText(_file, line + "\n"); }
                    catch { _file = null; }
                }
            }
        }

        public static bool HasErrors
        {
            get { lock (_gate) return _errorCount > 0; }
        }

        public static string Tail(int n = 10)
        {
            lock (_gate)
            {
                var from = Math.Max(0, _lines.Count - n);
                var shown = new List<string>();
                for (var i = from; i < _lines.Count; i++) shown.Add(_lines[i]);
                return string.Join("\n", shown);
            }
        }
    }
}
