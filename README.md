# AmethystXR Menu

The VR start menu for [Amlib](https://github.com/AirplanegoBrr/Amlib), a VR-enabled fork of Amethyst for Meta Quest. It's a small Godot 4.7 project: a panel in VR with controller pointers, where you pick an account and an instance and press Play.

It isn't a standalone app. Amlib includes this repo as a submodule at `vr_menu/`, exports it with Godot during the build and runs it inside the launcher through Godot's Android library. The launcher side is the `Amethyst` plugin (`VRMenuPlugin` in Amlib), which the menu polls with `getMenuState()` and calls with `signIn()`, `play()` and `openLauncher()`.

## Working on it

- Open the folder in Godot 4.7.
- To build it into the app, set `godot.path` in Amlib's `local.properties` to your Godot 4.7 binary. Gradle runs the export itself.
- On a PC there's no headset, so OpenXR won't start and the scene renders flat without the launcher plugin.
