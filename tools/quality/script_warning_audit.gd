extends SceneTree
## Collects the GDScript compile warnings Godot reports to an attached debugger (which is where the editor's Errors panel gets them; a plain headless run
## prints none). This script is the debugger side: it listens on a local port, launches a second Godot that loads every project script, and writes each
## warning as `file:line | message`.
##
## Usage: godot_console --headless --path . --script res://tools/quality/script_warning_audit.gd -- <godot_executable> <output_file>

const PORT := 6007


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var exe := args[0] if args.size() > 0 else OS.get_executable_path()
	var out_path := args[1] if args.size() > 1 else "user://script_warnings.txt"
	var server := TCPServer.new()
	if server.listen(PORT, "127.0.0.1") != OK:
		push_error("cannot listen on %d" % PORT)
		quit(2)
		return
	var project := ProjectSettings.globalize_path("res://")
	var pid := OS.create_process(exe, ["--headless", "--path", project, "--remote-debug", "tcp://127.0.0.1:%d" % PORT, "--script", "res://tools/scan_script_warnings.gd"])
	var started := Time.get_ticks_msec()
	var peer: StreamPeerTCP = null
	var buffer := PackedByteArray()
	var seen := {}
	var lines: PackedStringArray = []
	var last_data := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 240000:
		if peer == null and server.is_connection_available():
			peer = server.take_connection()
		if peer != null:
			peer.poll()
			var available := peer.get_available_bytes()
			if available > 0:
				buffer.append_array(peer.get_data(available)[1])
				last_data = Time.get_ticks_msec()
			while buffer.size() >= 4:
				var length := buffer.decode_u32(0)
				if buffer.size() < 4 + length:
					break
				var message: Variant = bytes_to_var(buffer.slice(4, 4 + length))
				buffer = buffer.slice(4 + length)
				_handle(message, seen, lines)
			if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED and buffer.size() == 0:
				break
		elif not OS.is_process_running(pid) and Time.get_ticks_msec() - started > 5000:
			break
		OS.delay_msec(5)
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	for line in lines:
		file.store_line(line)
	file.close()
	print("WARNINGS %d -> %s" % [lines.size(), ProjectSettings.globalize_path(out_path)])
	OS.kill(pid)
	quit(0)


func _handle(message: Variant, seen: Dictionary, lines: PackedStringArray) -> void:
	if not (message is Array) or (message as Array).size() < 3:
		return
	var name: String = str((message as Array)[0])
	var data: Variant = (message as Array)[2]
	if name != "error" or not (data is Array):
		return
	var fields: Array = data
	# [hr, min, sec, msec, source_file, source_func, source_line, error, error_descr, warning, callstack...]
	if fields.size() < 10:
		return
	var text := "%s:%s | %s | %s" % [fields[4], fields[6], fields[7], fields[8]]
	if fields[9] == true and not seen.has(text):
		seen[text] = true
		lines.append(text)
