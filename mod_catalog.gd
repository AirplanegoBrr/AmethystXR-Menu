extends Node
## Which Minecraft versions can run in VR, and the mods each one gets. Vivecraft's Quest builds
## come from QuestCraft's fork on GitHub; everything else is looked up on Modrinth (Fabric builds
## for each version), then remembered in user://vr_versions.json for a while. The menu installs
## these mods into its instances itself; Amlib leaves instances marked menuMods alone.

signal changed

const CACHE_PATH := "user://vr_versions.json"
const CACHE_SECONDS := 6 * 3600
## Bumped when what's remembered changes shape, so older lists get checked again
const CACHE_FORMAT := 4
const USER_AGENT := "AirplanegoBrr/AmethystXR-Menu"
const MODRINTH := "https://api.modrinth.com/v2/project/%s/version?loaders=%%5B%%22fabric%%22%%5D&include_changelog=false"
const FORK := "https://github.com/QuestCraftPlusPlus/VivecraftMod/releases/download/"
## Vivecraft builds that run on the Quest (OpenXR on Android), newest first. Only the fork has
## these, so new versions are added here by hand once it releases them.
const VIVECRAFT := {
	"1.21.11": FORK + "6.0.1-1.21.11/vivecraft.jar",
	"1.21.10": FORK + "v6.0.1-1.21.10/Vivecraft.jar",
	"1.21.8": FORK + "1.21.8-1.2.5-OpenXR/vivecraft-1.21.8-1.3.4-fabric.jar",
	"1.21.7": FORK + "1.21.7-1.2.5-OpenXR/vivecraft-1.21.7-1.2.5-b5-fabric.jar",
	"1.21.5": FORK + "1.21.5-1.2.5-OpenXR/vivecraft-1.21.5-1.3.4-fabric.jar",
	"1.21.4": FORK + "1.21.4-1.2.1-openxr/vivecraft-1.21.4-1.2.5-fabric.jar",
	"1.21.1": FORK + "1.21.1-1.2.1-openxr/vivecraft-1.21.1-1.2.5-fabric.jar",
	"1.20.6": FORK + "1.20.6-1.2.1-openxr/vivecraft-1.20.6-1.2.5-fabric.jar",
	"1.20.4": FORK + "1.20.4-1.2.1-openxr/vivecraft-1.20.4-1.2.5-fabric.jar",
	"1.20.1": FORK + "1.20.1-1.2.1-openxr/vivecraft-1.20.1-1.2.5-fabric.jar",
	"1.19.4": FORK + "1.19.4-1.2.1-openxr/vivecraft-1.19.4-1.2.5-fabric.jar",
	"1.19.2": FORK + "1.19.2-1.2.1-openxr/vivecraft-1.19.2-1.2.5-fabric.jar",
}
## Modrinth projects. A version is offered only when every required one has a Fabric build for
## it; the others (performance mods, the set Amlib uses for 1.21.11) are added where they exist.
## When a project has no build, the next id in its list is tried.
const MODS := [
	{"slug": "fabric-api", "ids": ["P7dR8mSH"], "required": true},
	{"slug": "sodium", "ids": ["AANobbMI"]},
	{"slug": "lithium", "ids": ["gvQqBUqZ"]},
	{"slug": "ferritecore", "ids": ["uXXizFIs"]},
	{"slug": "immediatelyfast", "ids": ["5ZwdcRci"]},
	{"slug": "moreculling", "ids": ["51shyZVL"]},
	{"slug": "krypton", "ids": ["fQEb0iXm"]},
	{"slug": "modernfix", "ids": ["modernfix", "TjSm1wrD"]},
	{"slug": "badoptimizations", "ids": ["g96Z4WVZ"]},
	{"slug": "zfastnoise", "ids": ["OnlVIpq5"]},
	{"slug": "better-biome-blend", "ids": ["Rs6c7WyL"]},
	{"slug": "entityculling", "ids": ["NNAgCjsB"]},
]
## Which files in an instance's mods folder the menu installed: slug -> file name
const STATE_FILE := ".amethyst-menu-mods.json"

## Minecraft versions with everything they need, newest first
var versions: Array = []
## While checking Modrinth or installing mods
var busy := false
var status := ""
var progress := 0.0
## Size to assume for a download Modrinth doesn't give one for (Vivecraft, from GitHub)
const SIZE_ESTIMATE := 6 * 1024 * 1024
var _download: HTTPRequest # The mod file being downloaded, for progress
var _download_name := ""
var _download_size := 0 # What the total counted for it
var _bytes_done := 0
var _bytes_total := 0
var _mods := {} # version -> Array of {slug, file, url}


## Loads the remembered versions, and checks Modrinth again when they're old
func refresh() -> void:
	var cache = _read_json(CACHE_PATH)
	if cache is Dictionary and cache.get("mods") is Dictionary and cache.get("format") == CACHE_FORMAT:
		_use(cache.mods)
		if Time.get_unix_time_from_system() - float(cache.get("checked", 0)) < CACHE_SECONDS:
			return
	busy = true
	status = "Checking which versions have VR mods…"
	progress = 0.0
	var found := {}
	for version in VIVECRAFT:
		found[version] = [{"slug": "vivecraft", "file": "vivecraft-%s.jar" % version, "url": VIVECRAFT[version]}]
	var complete := true
	for i in MODS.size():
		var mod: Dictionary = MODS[i]
		progress = float(i) / MODS.size()
		var builds := {}
		for id in mod.ids:
			var list = await _get_json(MODRINTH % id)
			if list is Array:
				_pick_builds(list, mod.slug, builds)
			elif mod.get("required", false):
				complete = false
		for version in found.keys():
			if builds.has(version):
				found[version].append(builds[version])
			elif mod.get("required", false):
				found.erase(version)
	if complete:
		complete = await _add_dependencies(found)
	busy = false
	status = ""
	# Offline or Modrinth is down: keep what was remembered
	if not complete:
		changed.emit()
		return
	_write_json(CACHE_PATH, {"format": CACHE_FORMAT, "checked": Time.get_unix_time_from_system(), "mods": found})
	_use(found)


func has_version(version: String) -> bool:
	return _mods.has(version)


## The newest Fabric build of a project for each Vivecraft version, preferring full releases
func _pick_builds(list: Array, slug: String, builds: Dictionary) -> void:
	for releases_only in [true, false]:
		for build in list:
			if releases_only and build.get("version_type") != "release":
				continue
			var files: Array = build.get("files", [])
			if files.is_empty():
				continue
			var file: Dictionary = files[0]
			for candidate in files:
				if candidate.get("primary", false):
					file = candidate
			var requires := []
			for dependency in build.get("dependencies", []):
				if dependency.get("dependency_type") == "required" and dependency.get("project_id") != null:
					requires.append(dependency.project_id)
			for version in build.get("game_versions", []):
				if VIVECRAFT.has(version) and not builds.has(version):
					builds[version] = {"slug": slug, "project": build.get("project_id", ""),
							"requires": requires, "file": file.filename, "url": file.url, "size": int(file.get("size", 0))}


## Adds the mods the chosen builds need (Fast Noise needs zconfig, for example), and their needs
## in turn. A mod whose requirements have no build for a version is left out of that version.
## Returns false when Modrinth couldn't be reached.
func _add_dependencies(found: Dictionary) -> bool:
	var builds_by_project := {} # project id -> {version -> build}
	for version in found.keys():
		var mods: Array = found[version]
		var have := {}
		for mod in mods:
			if mod.get("project", "") != "":
				have[mod.project] = true
		# Mods appended here are checked too, as the loop reaches them
		var i := 0
		while i < mods.size():
			var missing := false
			for project in mods[i].get("requires", []):
				if have.has(project):
					continue
				if not builds_by_project.has(project):
					status = "Checking mod requirements…"
					var list = await _get_json(MODRINTH % project)
					if not list is Array:
						return false
					var builds := {}
					_pick_builds(list, project, builds)
					builds_by_project[project] = builds
				if not builds_by_project[project].has(version):
					missing = true
					break
				mods.append(builds_by_project[project][version])
				have[project] = true
			if missing:
				if mods[i].slug == "fabric-api":
					found.erase(version)
					break
				mods.remove_at(i)
			else:
				i += 1
	return true


func _use(mods: Dictionary) -> void:
	_mods = mods
	versions = VIVECRAFT.keys().filter(func(version: String) -> bool: return mods.has(version))
	changed.emit()


## Marks an instance as the menu's, then installs its mods. Returns an error message, or "".
func setup_instance(game_dir: String, version: String) -> String:
	var path := game_dir.path_join("vr-instance.json")
	var settings = _read_json(path)
	if not settings is Dictionary:
		settings = {}
	if not settings.get("menuMods", false):
		settings.menuMods = true
		_write_json(path, settings)
	return await install_mods(game_dir, version)


## True for instances whose mods the menu installs (made here, not in the 2D launcher)
func is_menu_instance(game_dir: String) -> bool:
	var settings = _read_json(game_dir.path_join("vr-instance.json"))
	return settings is Dictionary and settings.get("menuMods", false)


## Brings the mods folder in line with the version's mod set: downloads what's missing or
## outdated, and removes files the menu installed that aren't wanted anymore
func install_mods(game_dir: String, version: String) -> String:
	if not _mods.has(version):
		return "No VR mods known for Minecraft " + version
	var mods_dir := game_dir.path_join("mods")
	DirAccess.make_dir_recursive_absolute(mods_dir)
	var state_path := mods_dir.path_join(STATE_FILE)
	var state = _read_json(state_path)
	if not state is Dictionary:
		state = {}
	var wanted: Array = _mods[version]
	var slugs := wanted.map(func(mod: Dictionary) -> String: return mod.slug)
	for slug in state.keys():
		if not slugs.has(slug):
			DirAccess.remove_absolute(mods_dir.path_join(state[slug]))
			state.erase(slug)

	var missing := wanted.filter(func(mod: Dictionary) -> bool:
		return state.get(mod.slug) != mod.file or not FileAccess.file_exists(mods_dir.path_join(mod.file)))
	busy = true
	progress = 0.0
	_bytes_done = 0
	_bytes_total = 0
	for mod in missing:
		_bytes_total += _size_of(mod)
	var error := ""
	for mod in missing:
		var target := mods_dir.path_join(mod.file)
		_download_name = mod.file.get_basename()
		_download_size = _size_of(mod)
		status = "Downloading %s…" % _download_name
		# Fabric only loads .jar files, so a half-finished download is never picked up
		var partial := target + ".part"
		var result: Array = await _request(mod.url, partial)
		_bytes_done += _download_size
		if result[0] != HTTPRequest.RESULT_SUCCESS or result[1] != 200:
			DirAccess.remove_absolute(partial)
			error = "Couldn't download %s, check your connection and try again" % mod.slug
			break
		if state.has(mod.slug) and state[mod.slug] != mod.file:
			DirAccess.remove_absolute(mods_dir.path_join(state[mod.slug]))
		DirAccess.rename_absolute(partial, target)
		state[mod.slug] = mod.file
		_write_json(state_path, state)
	busy = false
	status = ""
	return error


func _size_of(mod: Dictionary) -> int:
	return int(mod.get("size", 0)) if int(mod.get("size", 0)) > 0 else SIZE_ESTIMATE


## Follows the download in progress by bytes, across all the files being installed
func _process(_delta: float) -> void:
	if _download == null or _bytes_total <= 0:
		return
	var size := _download.get_body_size()
	if size > 0 and size != _download_size:
		# Now that the server says how big it is, count that instead of the guess
		_bytes_total += size - _download_size
		_download_size = size
	var got := _download.get_downloaded_bytes()
	progress = clampf(float(_bytes_done + got) / _bytes_total, 0.0, 1.0)
	status = "Downloading %s (%.1f / %.1f MB)" % [_download_name, got / 1048576.0, _download_size / 1048576.0]


func _get_json(url: String) -> Variant:
	var result: Array = await _request(url)
	if result[0] != HTTPRequest.RESULT_SUCCESS or result[1] != 200:
		return null
	return JSON.parse_string(result[3].get_string_from_utf8())


## [result, response code, headers, body], like HTTPRequest.request_completed
func _request(url: String, download_to := "") -> Array:
	var http := HTTPRequest.new()
	http.download_file = download_to
	http.timeout = 120.0
	add_child(http)
	var result: Array = [HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray()]
	if download_to != "":
		_download = http
	if http.request(url, ["User-Agent: " + USER_AGENT]) == OK:
		result = await http.request_completed
	if _download == http:
		_download = null
	http.queue_free()
	return result


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _write_json(path: String, data: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
