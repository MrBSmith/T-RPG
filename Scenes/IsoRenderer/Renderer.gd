extends Node2D

const TILE_SIZE = Vector2(32, 32)

var visible_cells : Array = [[], []] setget set_visible_cells, get_visible_cells
var focus_array : Array = [] setget set_focus_array, get_focus_array

enum type_priority {
	TILE,
	AREA,
	MOVEMENT_ARROW,
	CURSOR,
	OBSTACLE,
	ACTOR
}

#### ACCESSORS ####

func set_focus_array(array: Array): focus_array = array
func get_focus_array() -> Array: return focus_array

func set_visible_cells(value: Array):
	visible_cells = value
	update_tiles_visibility()

func get_visible_cells() -> Array: return visible_cells


#### BUILT-IN ####

func _ready() -> void:
	var _err = Events.connect("iso_object_cell_changed", self, "_on_iso_object_cell_changed")
	_err = Events.connect("iso_object_added", self, "_on_iso_object_added")
	_err = Events.connect("iso_object_removed", self, "_on_iso_object_removed")
	_err = Events.connect("tiles_shake", self, "_on_tiles_shake")


#### LOGIC ####

func init_rendering_queue(layers_array: Array, objects_array: Array):
	for i in range(layers_array.size()):
		for cell in layers_array[i].get_used_cells():
			add_cell_to_queue(cell, layers_array[i], i)
		
		for child in layers_array[i].get_children():
			for cell in child.get_used_cells():
				add_cell_to_queue(cell, child, i)
	
	for obj in objects_array:
		add_iso_obj(obj)


# Add the given cell to te rendering queue
func add_cell_to_queue(cell: Vector2, tilemap: TileMap, height: int) -> void:
	var tileset = tilemap.get_tileset()
	var cell_3D = Vector3(cell.x, cell.y, height)
	
	# Get the tile id and the position of the cell in the autotile
	var tile_id = tilemap.get_cellv(cell)
	var tile_region = tileset.tile_get_region(tile_id)
	var tile_tileset_pos = tile_region.position
	var autotile_coord = tilemap.get_cell_autotile_coord(int(cell.x), int(cell.y))
	
	# Get the texture
	var tile_mode = tileset.tile_get_tile_mode(tile_id)
	var stream_texture = tileset.tile_get_texture(tile_id)
	var atlas_texture = AtlasTexture.new()
	atlas_texture.set_atlas(stream_texture)
	if tile_mode == tileset.SINGLE_TILE:
		atlas_texture.set_region(tile_region)
	else:
		atlas_texture.set_region(Rect2(tile_tileset_pos + (autotile_coord * TILE_SIZE), TILE_SIZE))
	
	# Set the texture to the right position
	var height_offset = Vector2(0, -16) * (height - 1)
	var texture_offset = tileset.tile_get_texture_offset(tile_id)
	var offset = height_offset + texture_offset
	var pos = tilemap.map_to_world(cell)
	
	var render_part = TileRenderPart.new(tilemap, atlas_texture, cell_3D, pos, 0, offset)
	
	add_iso_rendering_part(render_part, tilemap)


# Add the given part in the rendering queue
func add_iso_rendering_part(part: RenderPart, obj: Node):
	if get_child_count() == 0:
		add_part(part, obj)
	else:
		var children = get_children()
		for i in range(children.size()):
			if xyz_sum_compare(part, children[i]):
				add_part(part, obj)
				move_child(part, i)
				break


# Add the given part to the render queue
func add_part(part: RenderPart, obj: Node):
	part.set_name(obj.name)
	add_child(part, true)
	part.set_owner(self)


# Update the tile visibility based on the visibles cells
func update_tiles_visibility():
	for child in get_children():
		if child is TileRenderPart:
			var part_cell = child.get_current_cell()
			if part_cell in visible_cells[IsoObject.VISIBILITY.BARELY_VISIBLE]:
				child.set_visibility(IsoObject.VISIBILITY.BARELY_VISIBLE)
			elif not part_cell in visible_cells[IsoObject.VISIBILITY.VISIBLE]:
				child.set_visibility(IsoObject.VISIBILITY.NOT_VISIBLE)
			else:
				child.set_visibility(IsoObject.VISIBILITY.VISIBLE)


# Place the given obj at the right position in the rendering queue
func add_iso_obj(obj: IsoObject) -> void:
	var parts_array = scatter_iso_object(obj)
	
	for part in parts_array:
		add_iso_rendering_part(part, obj)
	
	return


# Remove the given object from the rendering queue
func remove_iso_obj(obj: IsoObject):
	for child in get_children():
		if child.get_object_ref() == obj:
			child.queue_free()


# Replace the given obj at the right position in the rendering queue
func reorder_iso_obj(obj: IsoObject):
	for part in get_obj_parts(obj):
		reorder_part(part)


# Replace the given part at the right position in the rendering queue
func reorder_part(part: RenderPart):
	var children = get_children()
	var part_obj = part.get_object_ref()
	for i in range(children.size()):
		var child = children[i]
		if child.get_object_ref() == part_obj: continue
		if xyz_sum_compare(part, child):
			var part_id = part.get_index()
			if part_id < i:
				move_child(part, i - 1)
			else:
				move_child(part, i)
			break


# Returns every parts in the render queue that references the given object
func get_obj_parts(obj: IsoObject) -> Array:
	var part_array := Array()
	for child in get_children():
		if child.get_object_ref() == obj:
			part_array.append(child)
	return part_array


# Scatters a texture in the given number of smaller height, then returns it in an array
## ONLY HANDLE VERTICAL SCATTERING - MULTIPLE TILES WIDE OBJECTS ARE NOT SUPPORTED ##
func scatter_iso_object(obj: IsoObject) -> Array:
	var scattered_obj : Array = []
	var sprite_array : Array = []
	
	for child in obj.get_children():
		if child is IsoSprite or child is IsoAnimatedSprite:
			sprite_array.append(child)
	
	var height = obj.get_height()
	var obj_cell = obj.get_current_cell()
	var object_pos = obj.get_global_position()
	
	var obj_modul = obj.get_modulate()
	
	for i in range(height):
		var altitude = height - i
		var part_cell = obj_cell + Vector3(0, 0, altitude)
		
		var part = IsoRenderPart.new(obj, sprite_array, part_cell, object_pos,
									altitude, obj_modul)
		scattered_obj.append(part)
	
	return scattered_obj


# Check if the given object have at least one part of it in the rendering queue
func is_obj_in_rendering_queue(obj: IsoObject):
	for child in get_children():
		if child.get_object_ref() == obj:
			return true
	return false 


# Return the value of the drawing priority of the given object type
func get_type_priority(thing) -> int:
	if thing is Vector3:
		return type_priority.TILE
	elif thing.get_object_ref() is TileArea:
		return type_priority.AREA
	elif thing.get_object_ref() is MovementArrowSegment:
		return type_priority.MOVEMENT_ARROW
	elif thing.get_object_ref() is Cursor:
		return type_priority.CURSOR
	elif thing.get_object_ref() is Obstacle:
		return type_priority.OBSTACLE
	elif thing.get_object_ref() is Actor:
		return type_priority.ACTOR
	
	return -1


# Compare two positions, return true if a must be renderer before b
func xyz_sum_compare(a: RenderPart, b: RenderPart) -> bool:
	var grid_pos_a = a.get_current_cell()
	var grid_pos_b = b.get_current_cell()
	
	var sum_a = grid_pos_a.x + grid_pos_a.y + grid_pos_a.z
	var sum_b = grid_pos_b.x + grid_pos_b.y + grid_pos_b.z

	# First compare the sum x + y + z
	# Then compare y, then x, then z
	# If nothing worked, sort by type
	if sum_a == sum_b:
		if grid_pos_a.y == grid_pos_b.y:
			if grid_pos_a.x == grid_pos_b.x:
				if grid_pos_a.z == grid_pos_b.z:
					return get_type_priority(a) < get_type_priority(b)
				else:
					return grid_pos_a.z < grid_pos_b.z
			else:
				return grid_pos_a.x < grid_pos_b.x
		else:
			return grid_pos_a.y < grid_pos_b.y
	else:
		return sum_a < sum_b


func get_parts_at_2D_pos(pos: Vector2) -> Array:
	var part_array = Array()
	for child in get_children():
		var child_cell = child.get_current_cell()
		if child_cell.x == pos.x && child_cell.y == pos.y:
			part_array.append(child)
	return part_array


func shake(origin: Vector2, magnitude: int, wave: bool = true, duration: float = 1.0):
	for part in get_children():
		var part_cell = part.get_current_cell()
		var dist_to_origin = abs(part_cell.x - origin.x) + abs(part_cell.y - origin.y)
		if dist_to_origin <= magnitude:
			var mag = int(clamp(magnitude - dist_to_origin, 0, magnitude))
			var delay = (duration / 3) * (dist_to_origin / 2)
			part.start_sin_move(mag, delay)


#### SIGNAL RESPONSES ####

func _on_iso_object_cell_changed(obj: IsoObject):
	if !is_obj_in_rendering_queue(obj):
		add_iso_obj(obj)


func _on_iso_object_added(obj: IsoObject):
	add_iso_obj(obj)


func _on_iso_object_removed(obj: IsoObject):
	remove_iso_obj(obj)


func _on_part_cell_changed(part: IsoRenderPart, _cell: Vector3):
	reorder_part(part)


func _on_tiles_shake(origin: Vector2, magnitude: int):
	shake(origin, magnitude)
