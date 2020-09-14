extends StateBase

class_name CombatStateBase

var active_actor : Actor setget set_active_actor

var map_node : CombatMap setget set_map_node
var cursor_node : IsoObject setget set_cursor_node
var area_node : AreaContainer setget set_area_node
var HUD_node : CanvasLayer setget set_HUD_node

signal turn_finished

#### ACCESSORS ####

func set_active_actor(value : Actor):
	active_actor = value

func set_map_node(value: CombatMap):
	map_node = value

func set_cursor_node(value: IsoObject):
	cursor_node = value

func set_area_node(value : AreaContainer):
	area_node = value

func set_HUD_node(value: CanvasLayer):
	HUD_node = value

#### BUILT-IN FUCNTIONS ####

func _ready():
	var _err = connect("turn_finished", owner, "on_active_actor_turn_finished")

# Undo option
func _input(event):
	if event.is_action_pressed("ui_cancel"):
		get_parent().set_state("Overlook")


#### LOGIC ####

func enter_state():
	HUD_node.set_every_action_disabled()

func exit_state():
	area_node.clear()

func turn_finish():
	emit_signal("turn_finished")
