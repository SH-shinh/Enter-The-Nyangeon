# The base of a simulated effect (the JS `create(o)` that returns { update, draw, drawBack }). An effect script
# that keeps state extends this, keeps what the JS closure captured as member variables, and overrides:
#   func create(o: Dictionary) -> void      set up (the body of the JS create)
#   func update(dt: float) -> void          step (the runtime calls it at 120 Hz or finer)
#   func draw(p: Painter) -> void           what goes in front of a character
#   func drawBack(p: Painter) -> void       what goes behind (optional)
# A script may instead export `static func create(o) -> <an object with these methods>` (moves use chain()).
extends RefCounted

const Painter := preload("painter.gd")


func create(_o: Dictionary) -> void:
	pass


func update(_dt: float) -> void:
	pass


func draw(_p: Painter) -> void:
	pass


func drawBack(_p: Painter) -> void:
	pass


## Let go of what this effect holds. Fx.Instance calls it when the instance is freed: a member that points back at the
## effect (an onLand lambda bound to self, kept by its own Particles) is a reference cycle Godot's RefCounted never
## frees on its own. Only object, Callable and untyped members are cleared; shared arrays are left alone.
func dispose() -> void:
	for prop in get_property_list():
		if not (prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var v: Variant = get(prop.name)
		match typeof(v):
			TYPE_OBJECT:
				set(prop.name, null)
			TYPE_CALLABLE:
				set(prop.name, Callable() if prop.type == TYPE_CALLABLE else null)
			TYPE_ARRAY, TYPE_DICTIONARY:
				if prop.type == TYPE_NIL:
					set(prop.name, null)
