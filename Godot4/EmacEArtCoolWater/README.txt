EmacEArt Cool Water - stylized toon water shader for Godot 4
============================================================

Stylized toon water for games: lakes, ponds, pools, roadside puddles. It goes
on an ordinary plane placed over a dip in the terrain.

Everything you see on the surface - colour bands, shore glow, foam, light
patterns on the bottom - comes from one number: the vertical distance between
the surface and the ground below it. The water needs no textures or masks of
its own.


REQUIREMENTS
  Godot 4.7 or newer.
  Renderer: Forward+ or Mobile.
  The Compatibility renderer is NOT supported. Godot stores scene depth in a
  different format there, and this shader is built on reading the depth buffer.


RUN THE DEMO
  Open Scenes/WaterDemo.tscn and press F6, or press F5 for the main scene.
  The scene is finished the moment it opens. The terrain is a saved mesh, so it
  looks the same in the editor as it does when the game runs.


NAVIGATION
  LMB + drag ....... orbit the camera
  RMB + drag ....... pan the target
  Mouse wheel ...... zoom
  1 / 2 / 3 ........ camera presets: overview / beach / pools
  Space ............ freeze time (waves, foam, caustics)
  H ................ hide or show the slider panel and help overlay


SLIDER PANEL
  Appears on the left when the scene runs. Pick a surface at the top, drag the
  sliders, the water reacts instantly. Panel settings live only until you close
  the game - the .tres material files on disk are never written to.


USING THE SHADER IN YOUR OWN SCENE
  1. Add a MeshInstance3D with a subdivided plane (vertex waves need vertices
     to act on).
  2. Assign one of the materials from Materials/ as Material Override.
  3. Place the plane over a dip in the terrain. There has to be geometry
     underneath - over empty space there is nothing to measure and the water
     goes flat.


INCLUDED MATERIALS
  EA_Water_Tropical .... turquoise shore water
  EA_Water_DeepBlue .... cool pool blue
  EA_Water_Lagoon ...... green pond


DOCUMENTATION
  Documentation/EmacEArt_CoolWater_QuickStart_EN.pdf
      Four pages: requirements, controls, the six parameter groups, and how to
      put the water into a scene of your own.

  Documentation/EmacEArt_CoolWater_Documentation_EN.pdf
      Twenty pages: all 27 parameters with their range and default, the three
      vertex colour control channels, the three materials side by side, and a
      list of things better left alone in the project.


JOIN US ON DISCORD
  This pack keeps growing, and the next versions come out of what the people
  using it report back. Show how the water looks in your own scene, ask about
  settings, report a fault or request a parameter that is missing.

  https://discord.com/invite/ctXaf5Ftqw


(c) EmacEArt
