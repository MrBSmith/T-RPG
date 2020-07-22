extends Node
class_name CombatLoop

onready var map_node = $Map
onready var area_node = $Map/Interactives/Areas
onready var cursor_node = $Map/Interactives/Cursor
onready var combat_state_node = $CombatState
onready var HUD_node = $HUD

onready var allies_array : Array = get_tree().get_nodes_in_group("Allies") setget set_future_actors_order
onready var actors_order : Array = get_tree().get_nodes_in_group("Actors") setget set_actors_order

var focused_objects_array : Array = []

var active_actor : Actor setget set_active_actor, get_active_actor
var previous_actor : Actor = null

var future_actors_order : Array
var is_ready : bool = false

signal active_actor_changed

#### ACCESSORS ####

func set_active_actor(value: Actor):
	if value != active_actor:
		focused_objects_array.erase(active_actor)
		if active_actor:
			active_actor.set_passable(false)
		active_actor = value
		active_actor.set_passable(true)
		focused_objects_array.append(active_actor)
		emit_signal("active_actor_changed", active_actor)


func set_actors_order(value: Array):
	actors_order = value.duplicate()

func set_future_actors_order(value: Array):
	future_actors_order = value.duplicate()

func get_active_actor() -> Actor:
	return active_actor

#### BUILT-IN FUNCTION ####

func _ready():
	var _err = connect("active_actor_changed", $DebugPanel, "_on_active_actor_changed")
	_err = cursor_node.connect("cell_changed", $DebugPanel, "_on_cursor_pos_changed")
	_err = cursor_node.connect("max_z_changed", $DebugPanel, "_on_cursor_max_z_changed")
	
	propagate_call("set_map_node", [map_node], true)
	propagate_call("set_active_actor", [actors_order[0]], true)
	propagate_call("set_cursor_node", [cursor_node], true)
	propagate_call("set_area_node", [area_node], true)
	propagate_call("set_HUD_node", [HUD_node], true)
	
	HUD_node.generate_timeline(actors_order)
	focused_objects_array = [cursor_node, active_actor]
	
	# Feed the renderer with the actors and layers and hide it
	var layers_array : Array = []
	for child in map_node.get_children():
		if child is MapLayer:
			layers_array.append(child)
	
	$Renderer.set_layers_array(layers_array)
	on_iso_object_list_changed()
	
	is_ready = true
	
	# First turn trigger
	propagate_call("new_turn", [], true)


#### LOGIC ####

# New turn procedure, set the new active_actor and previous_actor
func new_turn():
	previous_actor = active_actor
	propagate_call("set_active_actor", [actors_order[0]], true)
	on_focus_changed()
	
	HUD_node.update_actions_left(active_actor.get_current_actions())
	
	combat_state_node.set_state("Overlook")
	active_actor.turn_start()


# End of turn procedure, called right before a new turn start
func end_turn():
	# Change the order of the timeline
	set_future_actors_order(actors_order)
	first_become_last(future_actors_order)
	
	HUD_node.move_timeline(actors_order, future_actors_order)


# Put the first actor of the array at the last position
func first_become_last(array : Array) -> void:
	var first = array.pop_front()
	array.append(first)


# Get every unpassable object form the IsoOject group 
func fetch_obstacles(iso_object_array: Array) -> Array:
	var unpassable_objects : Array = []
	for object in iso_object_array:
		if !object.is_passable():
			unpassable_objects.append(object)
	
	return unpassable_objects


#### SIGNALS ####

# Triggered when the active actor finished his turn
func on_active_actor_turn_finished():
	end_turn()


# Triggered when the timeline movement is finished
# Update the order of children nodes in the hierachy of the timeline to match the actor order
func on_timeline_movement_finished():
	set_actors_order(future_actors_order)
	HUD_node.update_timeline_order(actors_order)
	
	# Call the new turn
	propagate_call("new_turn", [], true)


func on_focus_changed():
	$Renderer.set_focus_array([active_actor, cursor_node])


# Update the iso object list of the renderer
# Called each time a iso object is added or removed from the scene
func on_iso_object_list_changed():
	var iso_object_array = get_tree().get_nodes_in_group("IsoObject")
	$Renderer.set_objects_array(iso_object_array)
	$Map.set_obstacles(fetch_obstacles(iso_object_array))


# Update the focus objects by adding a new one
func on_object_focused(focus_obj: IsoObject):
	focused_objects_array.append(focus_obj)
	$Renderer.set_focus_array(focused_objects_array)


# Update the focus objects by erasing an old one
func on_object_unfocused(focus_obj: IsoObject):
	focused_objects_array.erase(focus_obj)


func on_action_spent():
	HUD_node.update_actions_left(active_actor.get_current_actions())


func on_actor_wait():
	combat_state_node.set_state("Wait")
