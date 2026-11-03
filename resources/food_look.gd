class_name FoodLook
extends Resource

## How an ingredient's cut pieces look: the shape the view builds for a
## piece (FoodPieceMesh) and the surface pattern the food shader paints on
## it. Pure appearance - nothing here changes how food cooks. Shared looks
## live in data/looks/ and ingredients point at one; an ingredient without
## a look uses DEFAULT.

## The grain or texture of the flesh, painted by the food shader.
enum Pattern {
	NONE,
	## Fine starch flecks: potato, root.
	SPECKLE,
	## Long muscle fibres along the piece's length: red meat, poultry.
	FIBRE,
	## Fish: flakes in chevrons.
	FLAKE,
	## Threads of white fat through lean.
	MARBLE,
	## Leaf and blade veins.
	VEIN,
	## Open pores: mushrooms, organs, crumb.
	PORE,
	## Growth rings and fibres of woody roots and bones.
	RINGS,
}

## How fully a face that still has its skin rounds over, 0 (square) to 1
## (as round as an egg). Cut faces stay flat whatever this is.
@export_range(0.0, 1.0) var roundness: float = 0.6
## The tiny bevel the knife leaves on a cut edge, in mm.
@export_range(0.1, 3.0) var cut_edge_mm: float = 0.6
## How lumpy the skin is, in mm of hollows.
@export_range(0.0, 5.0) var wobble_mm: float = 0.6
## Size of the lumps, in mm.
@export_range(2.0, 200.0) var wobble_size_mm: float = 18.0

@export var pattern: Pattern = Pattern.SPECKLE
## The colour the pattern pulls the flesh toward (fat, veins, fibre).
@export var pattern_color: Color = Color(1.0, 1.0, 1.0)
@export_range(0.0, 1.0) var pattern_strength: float = 0.15
## Spacing of the pattern, in mm.
@export_range(0.2, 50.0) var pattern_size_mm: float = 2.0

## How much a cooked piece curls as its protein tightens (fillets, skin),
## 0 to 1.
@export_range(0.0, 1.0) var curl_when_cooked: float = 0.0
## How much a browning crust blisters up, 0 to 1.
@export_range(0.0, 1.0) var crust_blister: float = 0.5

static var DEFAULT := FoodLook.new()

static func of(ingredient: Ingredient) -> FoodLook:
	return ingredient.look if ingredient and ingredient.look else DEFAULT
