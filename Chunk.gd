extends Node3D

## A Chunk.
##
## The chunk loader expects this code to offer the 
## load_chunk and unload_chunk functions.




## Load this chunk: invoked by the chunk loader upon instantiation.
## Parameter chunk_pos_ is the position of this chunk, in chunk-space, and should be
## the only thing we need to know to generate a chunk.
func load_chunk(chunk_pos_ : Vector2i):
	
	# Here's where we put the code that generates the chunk:
	# Working out border agreement, subdividing interior into rooms,
	# mesh addition, mesh modification, setting shader parameters, etc. etc.
	
	# Temporary demo: sets the material of the child plane
	# based on position
	if (chunk_pos_.x + chunk_pos_.y) % 2:
		$MeshInstance3D.set_surface_override_material(0, load("res://temp_chunk_material_2.tres"))



## Unload this chunk: invoked by the chunk loader to cause deletion.
func unload_chunk():
	
	# Godot's way of deleting nodes in the scene tree
	queue_free()
