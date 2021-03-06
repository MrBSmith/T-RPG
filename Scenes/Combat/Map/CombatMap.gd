tool
extends Map
class_name CombatMap

onready var layer_0_node = $Layer
onready var area_node = $Interactives/Areas
onready var pathfinding = $Pathfinding

var layer_array : Array

var cell_path : PoolVector3Array = []

var walkable_cells : PoolVector3Array = []
var obstacles : Array = [] setget set_obstacles, get_obstacles

var is_ready : bool = false

signal map_generation_finished

#### ACCESSORS ####

func set_obstacles(array: Array):
	if array != obstacles:
		obstacles = array
		walkable_cells = pathfinding.set_walkable_cells(grounds)
		pathfinding.connect_walkable_cells(walkable_cells, owner.active_actor)

func get_obstacles() -> Array:
	return obstacles


#### BUILT-IN FUNCTIONS ####

func _ready():
	if Engine.editor_hint:
		return
	
	# Store every layers in the layer_ground_array
	for child in get_children():
		if child is MapLayer:
			layer_array.append(child)
	
	# Hide every nodes that the engine should be rendering (except ground0)
	hide_all_rendered_nodes(self)
	
	init_object_grid_pos()
	
	# Store all the passable cells into the array grounds
	grounds = fetch_ground()
	
	yield(owner, "ready")
	
	var _err = Events.connect("iso_object_cell_changed", self, "on_iso_object_cell_changed")
	_err = Events.connect("cursor_world_pos_changed", self, "on_cursor_world_pos_changed")
	_err = Events.connect("iso_object_removed", self, "_on_iso_object_removed")
	
	# Store all the passable cells into the array walkable_cells_list, 
	# by checking all the cells in the map to see if they are not an obstacle
	walkable_cells = pathfinding.set_walkable_cells(grounds)
	
	# Create the connections between all the walkable cells
	pathfinding.connect_walkable_cells(walkable_cells, owner.active_actor)
	
	for obj in get_tree().get_nodes_in_group("IsoObject"):
		obj.set_current_cell(get_pos_highest_cell(obj.position))
	
	is_ready = true
	
	emit_signal("map_generation_finished")


#### LOGIC ####

# Give every actor, his default grid pos
func init_object_grid_pos():
	yield(owner, "ready")
	
	for object in get_tree().get_nodes_in_group("IsoObject"):
		object.set_current_cell(get_pos_highest_cell(object.position))


# Recursivly search for the deepest node of every branch
# If the deepest node is a Sprite, an AnimatedSprite or a TileMap: hide it
# Exeception with the ground0 (Bescause its rendered by the engine) 
func hide_all_rendered_nodes(node: Node):
	if node is CanvasItem and not node is Control:
		node.set_visible(false) 
	else:
		for child in node.get_children():
			hide_all_rendered_nodes(child)


func generate_movement_arrow(path: PoolVector3Array):
	$Interactives/MovementArrow.generate_movement_arrow(path)

func clear_movement_arrow():
	$Interactives/MovementArrow.clear()

# Return an array of cells at the given world position 
# (ie cells that would be displayed at the same position in the screen)
func get_cell_stack_at_pos(world_pos: Vector2) -> PoolVector3Array:
	var cell_stack : PoolVector3Array = []
	var highest_cell = get_pos_highest_cell(world_pos)
	if highest_cell != Vector3.INF:
		cell_stack.append(highest_cell)
	
	for z in range(highest_cell.z - 1, -1, -1):
		var world_pos_adapted = Vector2(world_pos.x, world_pos.y + 16 * z)
		var cell_2D = layer_array[z].world_to_map(world_pos_adapted)
		var cell_3D = Vector3(cell_2D.x, cell_2D.y, z)
		if is_position_valid(cell_3D):
			cell_stack.append(cell_3D)
	
	return cell_stack


# Get the highest cell of every cells in the 2D plan,
# Returns a 3 dimentional coordinates array of cells
func fetch_ground() -> PoolVector3Array:
	var feed_array : PoolVector3Array = []
	for i in range(layer_array.size() - 1, -1, -1):
		for cell in layer_array[i].get_used_cells():
			if find_2D_cell(Vector2(cell.x, cell.y), feed_array) == Vector3.INF:
				feed_array.append(Vector3(cell.x, cell.y, i))
		
	# Handle bridges
	for i in range(layer_array.size()):
		for child in layer_array[i].get_children():
			var tileset = child.get_tileset()
			for cell in child.get_used_cells():
				var tile_id = child.get_cellv(cell)
				var tile_name = tileset.tile_get_name(tile_id)
				if "Bridge" in tile_name:
					var cell_3D = Vector3(cell.x, cell.y, i)
					if "Left" in tile_name:
						feed_array.append(cell_3D)
						feed_array.append(cell_3D + Vector3(1, 0, 0))
					elif "Right" in tile_name:
						feed_array.append(cell_3D)
						feed_array.append(cell_3D + Vector3(0, 1, 0))
	
	return feed_array


# Take an array of 2D cells and convert it to 3D cells using the height map
# Each cell returned in the array is the highest at the given 2D position
func array2D_to_grid_cells(line2D: Array) -> PoolVector3Array:
	var cell_array : PoolVector3Array = []
	for point in line2D:
		var cell = find_2D_cell_in_grounds(point)
		if cell != Vector3.INF:
			cell_array.append(cell)
	
	return cell_array


# Return the cell in the ground 0 grid pointed by the given position
func world_to_ground_z(pos : Vector2, z : int = 0):
	pos.y -= z * 16
	return layer_array[z].world_to_map(pos)


# Return the layer at the given height
func get_layer(height: int) -> MapLayer:
	return layer_array[height].get_parent()


# Return the id of the layer at the given height
func get_layer_id(height: int) -> int:
	return get_layer(height).get_index()


# Return the highest layer where the given cell is used
# If the given cell is nowhere: return -1
func get_cell_highest_layer(cell : Vector2) -> int:
	for i in range(layer_array.size() - 1, -1, -1):
		if cell in layer_array[i].get_used_cells():
			return i
	return -1


# Return the highest cell in the grid at the given world position
# Can optionaly find it, starting from a given layer (To ignore higher layers)
func get_pos_highest_cell(pos: Vector2, max_layer: int = 0) -> Vector3:
	var ground_0_cell_2D = layer_0_node.world_to_map(pos)
	
	var nb_grounds = layer_array.size()
	if max_layer == 0 or max_layer > nb_grounds:
		max_layer = nb_grounds
		
	for i in range(max_layer - 1, -1, -1):
		var current_cell_2D = ground_0_cell_2D + Vector2(i, i)
		var current_cell_3D = Vector3(current_cell_2D.x, current_cell_2D.y, i)
		if current_cell_3D in grounds:
			return current_cell_3D
	return Vector3.INF


# Return true if the given cell is outside the map bounds
func is_outside_map_bounds(cell: Vector3):
	return !(cell in grounds)


# Draw the movement of the given character
func draw_movement_area():
	var mov = owner.active_actor.get_current_movements()
	var current_cell = owner.active_actor.get_current_cell()
	var reachable_cells = pathfinding.find_reachable_cells(current_cell, mov)
	area_node.draw_area(reachable_cells, "move")


# Take a cell and return its world position
func cell_to_world(cell: Vector3) -> Vector2:
	var pos = layer_0_node.map_to_world(Vector2(cell.x, cell.y))
	pos.y -= cell.z * 16 - 8
	return pos


# Take an array of cells, and return an array of corresponding world positions
func cell_array_to_world(cell_array: PoolVector3Array) -> PoolVector2Array:
	var pos_array : PoolVector2Array = []
	for cell in cell_array:
		var new_pos = cell_to_world(cell)
		if !new_pos in pos_array:
			pos_array.append(new_pos)
	
	return pos_array


# Return true if the given cell is occupied by an obstacle
func is_cell_in_obstacle(cell: Vector3) -> bool:
	for obst in obstacles:
		if cell == obst.get_current_cell():
			return true
	return false


# Check if a position is valid, return true if it is, false if it is not
func is_position_valid(cell: Vector3) -> bool:
	var no_obstacle : bool = !is_cell_in_obstacle(cell)
	var inside_boundes : bool = !is_outside_map_bounds(cell)
	var is_walkable : bool = cell in walkable_cells
	
	return no_obstacle && inside_boundes && is_walkable 


# Return the actor or obstacle placed on the given cell
# Return null if the cell is empty
func get_object_on_cell(cell: Vector3) -> IsoObject:
	var objects_array = get_tree().get_nodes_in_group("Allies")
	objects_array += get_tree().get_nodes_in_group("Enemies")
	objects_array += $Interactives/Obstacles.get_children()
	
	for object in objects_array:
		if object.get_current_cell() == cell:
			return object
	
	return null


# Get every cells in the given range
func get_cells_in_range(origin: Vector3, ran: int) -> PoolVector3Array:
	var cells_in_range : PoolVector3Array = [origin]
	var treated_cells = PoolVector3Array()
	for _i in range(ran):
		for cell in cells_in_range:
			# Discard already treated cells
			if cell in treated_cells:
				continue
			
			var relatives = get_existing_adjacent_cells(cell)
			for rel in relatives:
				if not rel in cells_in_range:
					cells_in_range.append(rel)
			
			# Add the current cell to treate cells
			treated_cells.append(cell)
	
	return cells_in_range


# Get the reachable cells in the given range. Returns a PoolVector3Array of visible & reachable cells
func get_reachable_cells(origin: Vector3, h: int, ran: int, include_self_cell: bool = false) -> PoolVector3Array:
	var ranged_cells = get_cells_in_range(origin, ran)
	var reachable_cells := PoolVector3Array()
	
	if include_self_cell:
		reachable_cells.append(origin)
	
	for i in range(ranged_cells.size()):
		var cell = ranged_cells[-i - 1]
		
		if cell in reachable_cells: continue
		
		var line = IsoRaycast.get_line(self, origin, cell)
		
		var valid_cells = IsoRaycast.get_line_of_sight(self, h, line)
		for c in valid_cells:
			if not c in reachable_cells:
				reachable_cells.append(c)
	
	return reachable_cells


# Update the view field of the given actor by fetchin every cells he can se and feed him
func update_view_field(actor: Actor):
	var view_range = actor.get_view_range()
	var actor_cell = actor.get_current_cell()
	var actor_height = actor.get_height()
	
	var visible_cells = Array(get_reachable_cells(actor_cell, actor_height, view_range, true))
	var barely_visible_cells = Array(IsoLib.get_cells_at_xy_dist(actor_cell, view_range, visible_cells))
	
	for cell in visible_cells:
		if cell in barely_visible_cells:
			visible_cells.erase(cell)
	
	actor.set_view_field([
		visible_cells,
		barely_visible_cells])


# Return true if at least one target is reachable by the active actor
func has_target_reachable(actor: Actor) -> bool:
	var actor_cell = actor.get_current_cell()
	var actor_height = actor.get_height()
	var actor_range = actor.get_current_range()
	var reachables = get_reachable_cells(actor_cell, actor_height, actor_range)
	
	for cell in reachables:
		var obj = get_object_on_cell(cell)
		if obj == null:
			continue
		
		if obj.is_in_group("Enemies") or obj is Obstacle:
			return true
	return false


# Return the number of targets reachable by the active actor 
func count_reachable_enemies(active_cell: Vector3 = owner.active_actor.get_current_cell()) -> int:
	var actor_range = owner.active_actor.get_current_range()
	var reachables = get_cells_in_range(active_cell, actor_range)
	var count : int = 0
	
	for cell in reachables:
		var obj = get_object_on_cell(cell)
		
		if obj == null:
			continue
		
		if obj is Actor:
			if obj.is_in_group("Enemies"):
				count += 1
	return count


func on_iso_object_cell_changed(iso_object: IsoObject):
	if iso_object is Ally:
		update_view_field(iso_object)

func _on_iso_object_removed(iso_object: IsoObject):
	if !iso_object.is_passable():
		obstacles.erase(iso_object)
