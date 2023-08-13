extends Node

## Loading Manager for chunk data.


# ========== CONTROL VARIABLES ==========
# (these are @exported so you can access them in the "Inspector" pane)

@export_group("Chunk Properties")

## The world is divided horizontally along the X and Z axes (yes, Z axis, ye Blenderite)
## into chunks of this size.
@export var chunk_size := Vector2(2, 2)


## Inner loading radius.
## The engine will load a square region of chunks around the chunk the avatar is
## currently in; said chunk, plus or minus this number of chunks on both axes.
@export var creation_radius = 2


## Outer loading radius.
## Chunks that end up outside this radius will be unloaded. Obviously must be 
## greater than or equal to creation_radius.
@export var survival_radius = 3



@export_group("")

## The target node: a Node3D whose position defines which chunks should
## or shouldn't be loaded. If you change the avatar, reconnect it here.
@export var target : Node3D

## Where we're going to keep the chunks when we make them: a Node3D
## in the Scene Tree under whom the chunks will be put as children.
@export var chunkset : Node3D

## Resource path to the packed scene that contains the chunk scene; it is this scene
## that the chunk loader will instantiate into chunks.
@export var chunk_scene : PackedScene



# ========== INTERNAL STATE ==========

# References to loaded chunks are stored in this dictionary, keyed by the chunks' 
# positions: this allows us to quickly know if a chunk at a given position is loaded,
# by checking if the key exists.
var extant_chunks = {}


# Loading chunks might be expensive, so we want to offload it to another thread
# so it can be run in the background while the main thread handles avatar movement.
# Unfortunately Godot's not so good with threads, so we can only use one. We make
# a Thread object to control it:
var loading_thread : Thread


# Multithreading means we have to have locks to stop the loading thread from stepping
# on the main thread's toes, or vice versa. Since we've only got one other thread, 
# we'll only use one lock for protecting anything that both threads might touch. This
# is a 'mutex' and it's a sort of lock that only one thread can hold at a time (so if a
# thread is holding it, it means that thread has carte blanche to modify variables that
# the other threads have to keep their sticky paws off, until the mutex is unlocked)
var loading_thread_mutex : Mutex


# We'll need an auxiliary variable to tell the loading thread when to shut down,
# and this variable needs to be protected by the mutex above.
var loading_thread_stop : bool = false


# Here's where we communicate the avatar's current position to the loading thread.
# This variable also needs to be protected by the mutex above.
var target_chunk = Vector2.ZERO


# We don't want the loading thread to be running constantly all the time; rather,
# we tell it when we have a new avatar positon to compute loaded chunks for.
# (admittedly we do this every game tick, but that probably still saves cpu power, and
# you could also imagine only updating if the avatar moves)
# For this we use a multithreading construct helpfully called a 'semaphore', which
# is basically a number that both threads can touch. The main thread adds to that number,
# signifying work to be done, while the loading thread subtracts from the number, signifying
# that it's done the work.
var loading_thread_semaphore : Semaphore



## The ready function: invoked by the engine at start, to set things up.
func _ready():
	# Set up the thread locks
	loading_thread_mutex = Mutex.new()
	loading_thread_semaphore = Semaphore.new()
	
	# Initialize the loading thread (it's controlled by a Thread object)
	loading_thread = Thread.new()
	
	# Run the indicated function in the new thread
	loading_thread.start(_loading_thread_function)



## Invoked by the engine at stop, to tear things down
func _exit_tree():
	
	# Tell the loading thread to stop
	loading_thread_mutex.lock()
	loading_thread_stop = true
	loading_thread_mutex.unlock()
	
	# Tell the loading thread to pay attention
	loading_thread_semaphore.post()
	
	# Wait for the loading thread to stop working (joining threads)
	loading_thread.wait_to_finish()



## The process function: invoked by the engine every game tick.
func _process(_delta):
	
	# 1) Obtain the avatar's horizontal position 
	var target_pos := Vector2(target.global_position.x, target.global_position.z)
	
	# 2) Floor divide by the chunk size to get the avatar's current chunk
	var target_chunk_pre := Vector2i(target_pos / chunk_size)
	
	# 3) Tell the loading thread where the avatar is
	loading_thread_mutex.lock()
	target_chunk = target_chunk_pre
	loading_thread_mutex.unlock()
	
	# 4) Tell the loading thread that there's work to be done
	loading_thread_semaphore.post()
	
	# The loading thread'll do the rest.



# The loading thread function: run from the loading thread.
func _loading_thread_function():
	while true:	# Run until we tell it to stop
		
		# Wait until there's work to be done
		# (the thread'll just hang here until the main thread calls post())
		loading_thread_semaphore.wait()
		
		# Lock the mutex so that only the thread can touch the current_pos and loading_thread_stop
		loading_thread_mutex.lock()
		
		# Check to see if we've been told to stop.
		if loading_thread_stop:
			break
		
		# Chunk Loading: Work out which chunk positions are inside the creation radius
		#		and therefore need chunks in them.

	
		for chunk_y in range(target_chunk.y - creation_radius, target_chunk.y + creation_radius + 1):
			for chunk_x in range(target_chunk.x - creation_radius, target_chunk.x + creation_radius + 1):
			
				# Chunk at <chunk_x, chunk_y> needs to be loaded
				var chunk_pos_to_load = Vector2i(chunk_x, chunk_y)
			
				if chunk_pos_to_load not in extant_chunks:
					# Chunk's not already loaded, so we have to load it.
				
					# Instantiate the chunk scene; this makes a new chunk node that we can
					# add to our own scene tree.
					var freshly_loaded_chunk = chunk_scene.instantiate()
				
					# Tell the chunk to load itself (actually putting stuff in the chunk
					# is the chunk's job)
					freshly_loaded_chunk.load_chunk(chunk_pos_to_load)
				
					# Set the chunk's position in the 3D world
					var true_horizontal_position = Vector2(chunk_pos_to_load) * chunk_size
					freshly_loaded_chunk.position = Vector3(true_horizontal_position.x, 0, true_horizontal_position.y)
				
					# Add the chunk to the chunk buffer, keyed by its position
					extant_chunks[chunk_pos_to_load] = freshly_loaded_chunk
					
					# Parent the chunk to the chunk-holding node in the scene tree
					# Because we're doing this from a thread, we have to defer the call:
					chunkset.call_deferred("add_child", freshly_loaded_chunk)
			
			# Otherwise the chunk is already loaded; leave it be.
		
		
		# 4) Chunk Unloading: Work out which existing chunks are outside the survival radius and
		#		therefore need to be unloaded.
		for chunk_pos in extant_chunks:
			# For every existing chunk, iterating by position key
			if ((chunk_pos.x < target_chunk.x - survival_radius) or
				(chunk_pos.x > target_chunk.x + survival_radius) or
				(chunk_pos.y < target_chunk.y - survival_radius) or
				(chunk_pos.y > target_chunk.y + survival_radius)):
				
					# Chunk position is outside survival radius; unload the chunk
					var chunk_to_unload = extant_chunks[chunk_pos]
				
					# Remove chunk coordinates from the extant chunk dictionary, signalling that this
					# chunk no longer is loaded
					extant_chunks.erase(chunk_pos)
				
					# Tell chunk to unload itself
					chunk_to_unload.call_deferred("unload_chunk")
	
		# Unlock the mutex so the main thread can update position and stop controls
		loading_thread_mutex.unlock()
