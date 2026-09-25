@tool
extends EditorExportPlugin
## Adds Amlib to the Android (Gradle) build: its .aar files from bin/ (put there by
## tools/update_amlib.sh), the Maven libraries it uses, and the manifest bits that make this
## a Quest VR app. Amlib's own manifest (activities, permissions, the "Amethyst" plugin) merges in.

const BIN_DIR := "res://addons/amlib/bin"

## Amlib's Maven dependencies (app_pojavlauncher/build.gradle). A plain .aar doesn't carry
## them, so they're listed here; keep in sync when Amlib's change.
const DEPENDENCIES := [
	"javax.annotation:javax.annotation-api:1.3.2",
	"commons-codec:commons-codec:1.15",
	"androidx.preference:preference:1.2.0",
	"androidx.drawerlayout:drawerlayout:1.2.0",
	"androidx.viewpager2:viewpager2:1.1.0-beta01",
	"androidx.annotation:annotation:1.5.0",
	"androidx.constraintlayout:constraintlayout:2.1.4",
	"com.github.duanhong169:checkerboarddrawable:1.0.2",
	"com.github.PojavLauncherTeam:portrait-sdp:ed33e89cbc",
	"com.github.PojavLauncherTeam:portrait-ssp:6c02fd739b",
	"com.github.Mathias-Boulay:ExtendedView:1.0.0",
	"com.github.Mathias-Boulay:android_gamepad_remapper:2.0.3",
	"com.github.Mathias-Boulay:virtual-joystick-android:1.14",
	"org.tukaani:xz:1.8",
	"net.sourceforge.htmlcleaner:htmlcleaner:2.6.1",
	"com.bytedance:bytehook:1.0.10",
	"top.fifthlight.touchcontroller:proxy-client-android:0.0.4",
	"net.java.dev.jna:jna:5.14.0@aar",
]


func _get_name() -> String:
	return "Amlib"


func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform is EditorExportPlatformAndroid


func _get_android_libraries(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
	var libraries := PackedStringArray()
	var dir := DirAccess.open(BIN_DIR)
	if dir == null:
		push_error("Amlib: no %s, run tools/update_amlib.sh first" % BIN_DIR)
		return libraries
	for file in dir.get_files():
		if file.ends_with(".aar"):
			libraries.append("amlib/bin/" + file)
	return libraries


func _get_android_dependencies(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
	return PackedStringArray(DEPENDENCIES)


func _get_android_dependencies_maven_repos(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
	return PackedStringArray(["https://jitpack.io"])


## Horizon OS only launches an app immersively when its main activity has this category.
## (Godot's manifest already gives the activity its launcher entry.)
func _get_android_manifest_activity_element_contents(platform: EditorExportPlatform, debug: bool) -> String:
	return """
		<intent-filter>
			<action android:name="android.intent.action.MAIN" />
			<category android:name="com.oculus.intent.category.VR" />
		</intent-filter>
"""

