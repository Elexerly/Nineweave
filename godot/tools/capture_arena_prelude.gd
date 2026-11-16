extends SceneTree
## Offline visual QA. No API, account, or media download is used.
## godot --path godot --resolution 1280x720 --script res://tools/capture_arena_prelude.gd -- /tmp/arena.png
const Overlay = preload("res://characters/hero_video_overlay.gd")
func _initialize(): capture.call_deferred()
func capture():
	if DisplayServer.get_name() == "headless":
		print("ARENA_CAPTURE BLOCKED: graphical display required"); quit(2); return
	var overlay = Overlay.new(); root.add_child(overlay)
	overlay.set_process(false); overlay.visible = true; overlay.size = Vector2(root.size)
	overlay._waiting_for_intros = true; overlay._wait_age = 1.5
	overlay._chrome = Control.new(); overlay.add_child(overlay._chrome)
	overlay._chrome.draw.connect(overlay._draw_chrome)
	overlay._chrome.queue_redraw()
	for i in range(3): await process_frame
	await RenderingServer.frame_post_draw
	var args = OS.get_cmdline_user_args()
	var out = args[0] if args.size() else "user://arena-prelude.png"
	var image = root.get_texture().get_image()
	var success = not image.is_empty() and image.save_png(out) == OK
	print("ARENA_CAPTURE ","PASS" if success else "FAIL"," size=",root.size," out=",out)
	quit(0 if success else 1)
