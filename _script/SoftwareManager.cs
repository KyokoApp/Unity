/*MIT License

Copyright (c) 2025 Adrien Pierret

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.*/


using System.IO;
using System.Xml.Serialization;
using Godot;

namespace Bouncerock
{
	public partial class SoftwareManager : Node
	{
        public static double Runtime = 0;

		public string SoftwareVersion;
		public enum BuildTypes { REGULAR, DEVELOPER }
		public static BuildTypes Build = BuildTypes.REGULAR;

		//PATHS

		//Folder paths
		protected static string persistentpath = "";
		protected static string documentspath = "";
		protected static string modelspath = "";

		//Formats
		public static string binformat = ".isl";
		public static string publicformat = ".xml";

		//Manifest stores the base user data
		protected static string manifestfile = "/manifest";

		protected static string debugfile = "/debug.logs";
		protected static string preferencesfile = "/settings.xml";

		public static bool Initialized = false;
		//Everything starts from here
		public override void _Ready() 
		{
			GD.Print("Starting Software Manager");
			// Harus dipanggil: tanpa ini persistentpath/documentspath tetap "" dan
			// semua file (manifest, terrain cache, log) ditulis ke path tidak valid.
			SetPersistentPaths();
			Initialized = true;
			//Debug.DebugStartSession();
			GameManager gameManager = GetParent().GetNode<GameManager>("GameManager");
			if (gameManager == null)
			{
				GD.PrintErr("SoftwareManager: GameManager tidak ditemukan - inisialisasi game dilewati.");
				return;
			}
			gameManager.Initialize();
		}

		protected void SetPersistentPaths()
		{
			// GAME KHUSUS ANDROID: tidak ada lagi SpecialFolder (ApplicationData /
			// MyDocuments) — di Android fungsi itu mengembalikan string kosong,
			// sehingga persistentpath jadi "" dan semua file update/manifest tulis ke
			// path yang tidak valid. Semua data sekarang di folder milik aplikasi.
			persistentpath = ProjectSettings.GlobalizePath("user://Bouncerock") + "/";
			documentspath = persistentpath + "Docs/";
			Directory.CreateDirectory(persistentpath);   // System.IO: folder ini juga dibaca FileWriter
		}

		public static string GetManifestPath()
		{
			return persistentpath + manifestfile + binformat;
		}

		public static string GetPersistentPath()
		{
			return persistentpath;
		}

		

		public static string GetDebugFilePath()
		{
			return debugfile;
		}

		public override void _Process(double delta)
		{
			Runtime = Runtime + delta;
		}
    }
    
}