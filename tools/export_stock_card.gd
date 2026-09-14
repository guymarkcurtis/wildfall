## Re-exports the stock reference pack, its manifest, and the contact card.
##
## Run:
##   Godot --headless --path <project> --script tools/export_stock_card.gd
##
## Useful whenever PACK_ASSETS changes: the card is regenerated from the
## list, so new sheets appear in their intended card positions immediately.
## The Options panel button does the same work from the running game.
##
## Exit code: 0 = export succeeded.
extends SceneTree

func _initialize() -> void:
	var result := TexturePackManager.export_stock_reference()
	var card_path := str(result.get("card_path", ""))
	if card_path == "":
		print("EXPORT-FAIL no card path")
		quit(1)
		return
	print("EXPORT-DONE card=", card_path)
	quit(0)
