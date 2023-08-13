extends Node3D

# Temporary control code so the avatar can move around a bit

func _process(delta):
	
	var input_screenspace = Vector2(
		int(Input.is_action_pressed("ui_right")) - int(Input.is_action_pressed("ui_left")),
		int(Input.is_action_pressed("ui_up")) - int(Input.is_action_pressed("ui_down"))
	).normalized()
	
	var input_motion = (global_transform.basis.x * input_screenspace.x + global_transform.basis.z * -input_screenspace.y).normalized()
	
	global_position += input_motion * delta * 3.0
