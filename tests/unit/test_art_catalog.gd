extends GutTest
## ArtCatalog must degrade to null (not crash) when the art pipeline has not landed.


func test_missing_sprite_returns_null() -> void:
	assert_null(ArtCatalog.texture("__definitely_missing__"))
	assert_false(ArtCatalog.has_sprite("__definitely_missing__"))


func test_path_is_stable() -> void:
	assert_eq(ArtCatalog.sprite_path("item_rocky"), "res://assets/sprites/item_rocky.png")
