@tool
extends Resource
class_name AtmoAcousticMaterial
## Three broad frequency groups: below 400Hz, 400–3500Hz, above 3500Hz.
## Coefficients are authorable acoustic approximations, not measured samples.
@export var material_name := "Stone"
@export var absorption_bands := Vector3(0.03, 0.06, 0.10)
@export var transmission_db := Vector3(-20, -32, -48)
@export_range(0.0, 1.0) var scattering := 0.12
@export_range(0.0, 1.0) var roughness := 0.25

static func sample(collider: Object) -> Dictionary:
	var profile: Resource = null
	if is_instance_valid(collider) and collider.has_method("get_acoustic_profile"):
		profile = collider.get_acoustic_profile()
	if profile is AtmoAcousticMaterial:
		# Roughness redistributes an additional 0–25% of the remaining specular
		# energy into the diffuse field. Both early paths and room probes use it.
		var roughness := clampf(profile.roughness, 0.0, 1.0)
		var diffuse_fraction := 1.0-(1.0-clampf(profile.scattering,0.0,.98))*(1.0-roughness*.25)
		return {"absorption": _bounded(profile.absorption_bands, 0.001, 0.99), "transmission_db": _bounded(profile.transmission_db, -90.0, -0.1), "scattering": diffuse_fraction, "roughness": roughness, "label": String(profile.material_name)}
	var label := String(collider.get_meta("material", "stone")) if is_instance_valid(collider) else "stone"
	var alpha := clampf(float(collider.get_meta("absorption", 0.25)), 0.01, 0.98) if is_instance_valid(collider) else 0.25
	return {"absorption": Vector3(alpha * 0.65, alpha, minf(alpha * 1.35, 0.99)), "transmission_db": Vector3(-20,-32,-48), "scattering": 0.15, "roughness": 0.3, "label": label}

static func _bounded(value: Vector3, minimum: float, maximum: float) -> Vector3:
	return Vector3(clampf(value.x,minimum,maximum),clampf(value.y,minimum,maximum),clampf(value.z,minimum,maximum))

static func reflection_energy(material: Dictionary) -> Vector3:
	var absorption: Vector3 = material.absorption
	var transmission: Vector3 = material.transmission_db
	return Vector3(maxf(0.001,1.0-absorption.x-pow(10.0,transmission.x/10.0)),maxf(0.001,1.0-absorption.y-pow(10.0,transmission.y/10.0)),maxf(0.001,1.0-absorption.z-pow(10.0,transmission.z/10.0)))
