@tool
extends EditorPlugin

var known_scripts: Dictionary = {}
var _is_updating: bool = false

# Add any other folders you want to ignore to this list
const IGNORED_FOLDERS: Array[String] = [
	"res://addons",
	"res://demo",
	"res://config",
    "res://assets"
]

func _enter_tree() -> void:
	var efs = get_editor_interface().get_resource_filesystem()
	efs.filesystem_changed.connect(_on_filesystem_changed)
	call_deferred("_initialize_cache")

func _exit_tree() -> void:
	var efs = get_editor_interface().get_resource_filesystem()
	if efs.filesystem_changed.is_connected(_on_filesystem_changed):
		efs.filesystem_changed.disconnect(_on_filesystem_changed)

func _initialize_cache() -> void:
	var efs = get_editor_interface().get_resource_filesystem()
	var root_dir = efs.get_filesystem()
	if root_dir:
		known_scripts.clear()
		_collect_current_scripts(root_dir, known_scripts)

func _on_filesystem_changed() -> void:
	if _is_updating:
		return

	var efs = get_editor_interface().get_resource_filesystem()
	var root_dir = efs.get_filesystem()
	
	if not root_dir:
		return

	var current_scripts = {}
	_collect_current_scripts(root_dir, current_scripts)

	var added = []
	var removed = []

	for path in current_scripts:
		if not known_scripts.has(path):
			added.append(path)

	for path in known_scripts:
		if not current_scripts.has(path):
			removed.append(path)

	if added.size() > 0 or removed.size() > 0:
		_is_updating = true
		call_deferred("_process_changes", added, removed, current_scripts)
	else:
		known_scripts = current_scripts
func _process_changes(added: Array, removed: Array, current_scripts: Dictionary) -> void:
	var files_modified = []

	for a_path in added:
		var handled = false
		var new_name: String = current_scripts[a_path]
		
		for r_path in removed:
			var old_name: String = known_scripts[r_path]
			if _modify_file_on_disk(a_path, new_name, old_name):
				files_modified.append(a_path)
				handled = true
				break
		
		if not handled:
			if _modify_file_on_disk(a_path, new_name, ""):
				files_modified.append(a_path)

	known_scripts = current_scripts
	
	if files_modified.size() > 0:
		var efs = get_editor_interface().get_resource_filesystem()
		for path in files_modified:
			efs.call_deferred("update_file", path)
			
	await get_tree().create_timer(0.2).timeout
	_is_updating = false

func _collect_current_scripts(dir: EditorFileSystemDirectory, dict: Dictionary) -> void:
	if not dir:
		return
		
	var dir_path = dir.get_path()
	
	# Stop the scanner from traversing into excluded folders or their subfolders
	for ignored in IGNORED_FOLDERS:
		if dir_path == ignored or dir_path.begins_with(ignored + "/"):
			return
		
	for i in range(dir.get_file_count()):
		var path = dir.get_file_path(i)
		if path.get_extension() == "gd":
			# Extra string check just to be absolutely sure
			var is_ignored = false
			for ignored in IGNORED_FOLDERS:
				if path.begins_with(ignored + "/"):
					is_ignored = true
					break
			
			if not is_ignored:
				dict[path] = path.get_file().get_basename()
			
	for i in range(dir.get_subdir_count()):
		_collect_current_scripts(dir.get_subdir(i), dict)

func _modify_file_on_disk(path: String, new_name: String, old_name: String) -> bool:
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return false
		
	var content = file.get_as_text()
	file.close()

	var header = "#" + new_name
	var old_header = "#" + old_name if old_name != "" else ""
	
	var modified_content = ""
	var changed = false

	if old_header != "":
		if content.begins_with(old_header + "\n") or content == old_header:
			var remainder = content.substr(old_header.length())
			if remainder.begins_with("\n"):
				remainder = remainder.substr(1)
			modified_content = header + "\n" + remainder
			changed = true
	else:
		if not content.begins_with(header + "\n") and content != header:
			modified_content = header + "\n" + content
			changed = true

	if changed:
		file = FileAccess.open(path, FileAccess.WRITE)
		if file:
			file.store_string(modified_content)
			file.close()
			return true
			
	return false
