## Building Sandbox tutorial card content: a title plus the ordered heading
## lines the card teaches. SandboxTutorialCardPanel renders exactly these
## rows, so adding or editing a topic is a data-only change.
class_name SandboxTutorialCard
extends Resource

@export var title: String = "Building Sandbox"
## Row heading -> one-line detail. Dictionary insertion order is the card's
## display order and is preserved through .tres round-trips.
@export var lines: Dictionary = {}

func validate() -> Array[String]:
	var errors: Array[String] = []
	if title.strip_edges() == "":
		errors.append("tutorial card title is empty")
	for heading in lines:
		var detail: Variant = lines[heading]
		if typeof(detail) != TYPE_STRING or str(detail).strip_edges() == "":
			errors.append("tutorial line '%s' needs a non-empty string detail" % str(heading))
	return errors
