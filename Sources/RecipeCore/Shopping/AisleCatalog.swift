import Foundation

/// Maps an ingredient name to the store aisle it sits in.
///
/// A small original table, not a general-purpose one: it covers the
/// items that show up in everyday cooking and falls back to "Other".
/// The pantry (M7) will refine matching through the taxonomy; the
/// list builder only needs a label to group lines under.
public enum AisleCatalog {

    /// The aisle labels, in display order.
    public static let aisles = [
        "Produce",
        "Meat",
        "Seafood",
        "Dairy & Eggs",
        "Bakery",
        "Dry goods",
        "Canned & Jarred",
        "Spices & Baking",
        "Beverages",
        "Frozen",
        "Other",
    ]

    /// Substring fragments (lowercase) that put an item in an aisle,
    /// checked in order within each aisle's block. First match wins.
    private static let fragments: [(aisle: String, fragments: [String])] = [
        (
            "Produce",
            [
                "onion", "garlic", "carrot", "celery", "tomato", "potato",
                "pepper", "bell", "chile", "chili", "lettuce", "spinach",
                "kale", "cabbage", "broccoli", "cauliflower", "zucchini",
                "cucumber", "mushroom", "leek", "scallion", "shallot",
                "ginger", "herb", "parsley", "cilantro", "basil", "thyme",
                "rosemary", "mint", "dill", "sage", "oregano", "bay leaf",
                "lime", "lemon", "orange", "apple", "banana", "berry",
                "berries", "grape", "avocado", "melon", "peach", "pear",
                "pineapple", "mango", "salad", "greens", "squash",
                "asparagus", "green bean", "pea", "corn", "radish",
                "beet", "turnip", "parsnip", "fennel", "artichoke",
            ]
        ),
        (
            "Meat",
            [
                "chicken", "beef", "pork", "bacon", "ham", "sausage",
                "turkey", "lamb", "steak", "ground", "ribs", "prosciutto",
                "pancetta", "brisket", "veal", "duck", "wings",
            ]
        ),
        (
            "Seafood",
            [
                "fish", "salmon", "tuna", "cod", "shrimp", "prawn",
                "crab", "lobster", "clam", "mussel", "scallop", "oyster",
                "anchovy", "sardine", "squid", "octopus", "trout",
            ]
        ),
        (
            "Dairy & Eggs",
            [
                "milk", "cream", "butter", "cheese", "cheddar", "parmesan",
                "mozzarella", "feta", "goat cheese", "ricotta", "yogurt",
                "yoghurt", "sour cream", "crème fraîche", "creme fraiche",
                "egg", "mayonnaise", "mayo", "half-and-half", "halves and",
                "buttermilk", "mascarpone", "ghee",
            ]
        ),
        (
            "Bakery",
            [
                "bread", "baguette", "bun", "roll", "tortilla", "pita",
                "croissant", "bagel", "crouton", "cracker", "naan",
            ]
        ),
        (
            "Dry goods",
            [
                "flour", "rice", "pasta", "noodle", "spaghetti", "penne",
                "macaroni", "oat", "quinoa", "barley", "couscous",
                "lentil", "bean", "chickpea", "split pea", "sugar",
                "breadcrumb", "polenta", "grits", "tortilla chip",
                "wrap", "cous", "bulgur", "farro", "semolina",
            ]
        ),
        (
            "Canned & Jarred",
            [
                "canned", "can of", "jar", "tomato paste", "tomato sauce",
                "crushed tomato", "diced tomato", "coconut milk",
                "broth", "stock", "olive", "pickle", "caper", "salsa",
                "chutney", "honey", "syrup", "vinegar", "oil", "soy sauce",
                "fish sauce", "sesame oil", "hot sauce", "mustard",
                "ketchup", "worcestershire", "sriracha", "miso", "tahini",
                "peanut butter", "nutella", "jam", "preserve", "harissa",
                "chipotle", "artichoke heart", "water chestnut",
            ]
        ),
        (
            "Spices & Baking",
            [
                // "pepper" only reaches here when produce missed it.
                "salt", "pepper", "cumin",
                "paprika", "coriander", "turmeric", "cinnamon", "nutmeg",
                "clove", "cardamom", "chili powder", "cayenne", "curry",
                "oregano", "thyme", "bay", "allspice", "ginger powder",
                "baking powder", "baking soda", "yeast", "vanilla",
                "extract", "cocoa", "chocolate", "sprinkle", "powdered sugar",
                "brown sugar", "cornstarch", "corn starch", "baking",
                "spice", "seasoning", "peppercorn", "cinnamon stick",
                "nutritional yeast",
            ]
        ),
        (
            "Beverages",
            [
                // "broth" and "stock" live in Canned & Jarred above.
                "water", "juice", "wine", "beer", "cider", "soda",
                "cola", "coffee", "espresso", "tea", "seltzer", "tonic",
                "sparkling", "lemonade",
                "milk substitute", "almond milk", "oat milk", "soy milk",
            ]
        ),
        (
            "Frozen",
            [
                "frozen", "ice cream", "popsicle", "edamame",
            ]
        ),
    ]

    /// The fallback label for items that match nothing.
    public static let fallback = "Other"

    /// The aisle for an ingredient name. Case-insensitive; the first
    /// fragment match in the table's order wins, so "olive oil" lands
    /// in Canned & Jarred before "olive" could suggest Produce.
    public static func aisle(for item: String) -> String {
        let lowered = item.lowercased()
        // Frozen goes first: "frozen peas" is frozen, not produce.
        if lowered.contains("frozen") { return "Frozen" }
        for (aisle, fragments_) in fragments {
            for fragment in fragments_ where lowered.contains(fragment) {
                return aisle
            }
        }
        return fallback
    }
}
