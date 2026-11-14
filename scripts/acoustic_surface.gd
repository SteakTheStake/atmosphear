@tool
extends StaticBody3D
## A real collision surface and its editable acoustic material.
@export var acoustic_material: AtmoAcousticMaterial

func get_acoustic_profile() -> Resource:
	return acoustic_material
