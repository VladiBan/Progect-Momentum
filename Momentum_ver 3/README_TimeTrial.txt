MOMENTUM - TIME TRIAL BUILD

OPENING THE PROJECT
1. Extract this entire folder.
2. Open project.godot in Godot 4.7 (the version listed in the original project settings).
3. Press F6 to run the current scene, or F5 to run the project. The startup scene is Level/TimeTrial.tscn.

CONTROLS
WASD  Move
Mouse Look around
Space  Jump (briefly tap for a shorter jump)
Left Shift  Slide (also buffered shortly before landing)
Escape  Release mouse
Left click  Capture mouse again
R  Restart the time trial

LEVEL
The time trial has a slide tunnel, stepped jump platforms, a wall-run bridge, a checkpoint, a finish gate, a race timer, and a speedometer. Falling respawns you at the latest checkpoint. The best time lasts for the current run of the game.

NOTES
The slide camera dip is controlled by Player/Player.gd and moves CameraPivot. The old AnimationPlayer camera-position track has been removed to prevent two systems from moving the camera at once.

This package has been checked for file and scene-path consistency, but it has not been launched in the Godot editor in this environment. If Godot reports an error, fix the first error in the debugger before checking later messages.
