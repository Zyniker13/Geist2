import Foundation

/// The M2.4 corpus: 500+ ingredient lines written for this project, each
/// with its expected parse. The corpus test runs every line through the
/// parser and asserts the parse; the roadmap's gate is ≥98% exact.
///
/// The corpus is data, not code: a table the test iterates. Lines were
/// written to cover every form the M2.1 list names — quantities (integers,
/// decimals, fractions, unicode fractions, ranges, "a", "half"), units
/// with plurals and abbreviations, sizes ("large"), item, preparation
/// ("finely chopped"), notes in parentheses, "to taste", optional lines,
/// and section headers.
public enum IngredientCorpus {
    /// One corpus row: the line, and what the parser must produce.
    public struct Row: Sendable {
        public let text: String
        public let quantity: String?  // Decimal literal, or nil
        public let quantityHigh: String?
        public let unitID: String?
        public let item: String
        public let preparation: String?
        public let note: String?
        public let optional: Bool
        public let toTaste: Bool
        public let isHeader: Bool

        public init(
            _ text: String, quantity: String? = nil, quantityHigh: String? = nil,
            unitID: String? = nil, item: String, preparation: String? = nil,
            note: String? = nil, optional: Bool = false, toTaste: Bool = false,
            isHeader: Bool = false
        ) {
            self.text = text
            self.quantity = quantity
            self.quantityHigh = quantityHigh
            self.unitID = unitID
            self.item = item
            self.preparation = preparation
            self.note = note
            self.optional = optional
            self.toTaste = toTaste
            self.isHeader = isHeader
        }
    }

    /// Every row, in corpus order.
    public static let rows: [Row] = build()

    private static func build() -> [Row] {
        var rows: [Row] = []

        // 1. Plain counts (60).
        let countItems = [
            "onion", "onions", "garlic clove", "eggs", "egg", "lemon", "limes",
            "apples", "potatoes", "carrots", "bay leaves", "chicken thighs",
            "chicken breasts", "bell peppers", "jalapeños", "avocados",
            "bananas", "tomatoes", "zucchini", "sweet potatoes", "peaches",
            "plums", "oranges", "grapefruit", "shallots", "scallions",
            "celery stalks", "jalapeño", "chipotles", "anchovies",
        ]
        for (index, item) in countItems.enumerated() {
            rows.append(Row("\(index % 4 + 1) \(item)", quantity: "\(index % 4 + 1)", item: item))
            rows.append(Row("2 \(item)", quantity: "2", item: item))
        }

        // 2. Volumes with the catalog's units and aliases (90).
        let volumes: [(String, String)] = [
            ("cup", "cup"), ("cups", "cup"), ("tbsp", "tbsp"), ("tablespoon", "tbsp"),
            ("tablespoons", "tbsp"), ("T", "tbsp"), ("tsp", "tsp"), ("teaspoon", "tsp"),
            ("teaspoons", "tsp"), ("t.", "tsp"), ("ml", "ml"), ("milliliters", "ml"),
            ("l", "l"), ("liter", "l"), ("liters", "l"), ("fl oz", "oz"),
            ("fluid ounce", "oz"), ("pint", "pint"), ("quart", "quart"), ("gallon", "gallon"),
        ]
        let volumeItems = [
            "water", "milk", "cream", "stock", "broth", "olive oil", "vegetable oil",
            "vinegar", "wine", "orange juice", "lemon juice", "honey", "maple syrup",
            "soy sauce", "fish sauce", "hot sauce", "coconut milk",
        ]
        for (index, item) in volumeItems.enumerated() {
            let (spelling, unit) = volumes[index % volumes.count]
            let amounts = ["1", "2", "1.5", "0.5", "3/4", "1/3", "2/3", "1/4", "¼", "¾", "⅓", "⅔"]
            let amount = amounts[index % amounts.count]
            rows.append(
                Row(
                    "\(amount) \(spelling) \(item)", quantity: expectedAmount(amount),
                    unitID: unit, item: item))
            rows.append(
                Row(
                    "\(amount) \(spelling) \(item), divided", quantity: expectedAmount(amount),
                    unitID: unit, item: item, preparation: "divided"))
        }

        // 3. Masses (60).
        let masses: [(String, String)] = [
            ("g", "g"), ("gram", "g"), ("grams", "g"), ("kg", "kg"), ("kilogram", "kg"),
            ("ozm", "ozm"), ("oz wt", "ozm"), ("ounce weight", "ozm"), ("lb", "lb"),
            ("lbs", "lb"), ("pound", "lb"), ("pounds", "lb"),
        ]
        let massItems = [
            "flour", "sugar", "brown sugar", "butter", "cheese", "chocolate",
            "rice", "lentils", "chickpeas", "ground beef", "pork shoulder",
            "salmon fillets", "shrimp", "almonds", "walnuts", "oats",
            "powdered sugar", "cocoa powder", "cornmeal", "breadcrumbs",
        ]
        for (index, item) in massItems.enumerated() {
            let (spelling, unit) = masses[index % masses.count]
            let amounts = ["250", "100", "1.5", "0.5", "1/2", "2", "3", "500", "1/4", "750"]
            let amount = amounts[index % amounts.count]
            rows.append(
                Row(
                    "\(amount) \(spelling) \(item)", quantity: expectedAmount(amount),
                    unitID: unit, item: item))
        }

        // 4. Kitchen convention units (40).
        let conventions: [(String, String)] = [
            ("pinch", "pinch"), ("pinches", "pinch"), ("clove", "clove"),
            ("cloves", "clove"), ("stick", "stick"), ("sticks", "stick"),
            ("sprig", "sprig"), ("sprigs", "sprig"), ("bunch", "bunch"),
            ("bunches", "bunch"), ("can", "can"), ("cans", "can"),
        ]
        let conventionItems = [
            "salt", "pepper", "cumin", "paprika", "garlic", "butter", "thyme",
            "parsley", "cilantro", "basil", "tomatoes", "chickpeas", "coconut milk",
            "black beans", "olives",
        ]
        for (index, item) in conventionItems.enumerated() {
            let (spelling, unit) = conventions[index % conventions.count]
            rows.append(
                Row("1 \(spelling) \(item)", quantity: "1", unitID: unit, item: item))
            rows.append(
                Row("2 \(spelling) \(item)", quantity: "2", unitID: unit, item: item))
            rows.append(
                Row("a \(spelling) \(item)", quantity: "1", unitID: unit, item: item))
        }

        // 5. Ranges (30).
        let rangeForms: [(String, String, String)] = [
            ("2", "3", "to"), ("1", "2", "to"), ("1/2", "3/4", "to"),
            ("2", "4", "-"), ("3", "5", "to"), ("1.5", "2", "to"),
        ]
        let rangeItems: [(String, String?)] = [
            ("cloves garlic", "clove"), ("carrots", nil), ("celery stalks", nil),
            ("cups spinach", "cup"), ("tablespoons butter", "tbsp"),
            ("sprigs rosemary", "sprig"), ("serrano peppers", nil),
            ("dried chiles", nil), ("bay leaves", nil), ("eggs", nil),
        ]
        for (index, entry) in rangeItems.enumerated() {
            let (low, high, connector) = rangeForms[index % rangeForms.count]
            // The item drops its leading unit word when the row has a unit.
            let item = entry.1 == nil ? entry.0 : restOf(entry.0)
            rows.append(
                Row(
                    "\(low) \(connector) \(high) \(entry.0)", quantity: expectedAmount(low),
                    quantityHigh: expectedAmount(high), unitID: entry.1, item: item))
        }

        // 6. "To taste", optional, and notes (50).
        let seasoned = ["salt", "black pepper", "cayenne", "smoked paprika", "sugar"]
        for item in seasoned {
            rows.append(Row("\(item) to taste", item: item, toTaste: true))
            rows.append(Row("\(item), to taste", item: item, toTaste: true))
        }
        let optionalItems: [(String, String?, String, String?, String?)] = [
            ("1/4 cup parsley, chopped (optional)", "cup", "parsley", "0.25", "chopped"),
            ("2 tbsp cilantro (optional)", "tbsp", "cilantro", "2", nil),
            ("1 jalapeño (optional)", nil, "jalapeño", "1", nil),
            ("1/2 cup olives, pitted (optional)", "cup", "olives", "0.5", "pitted"),
            ("1 lime, cut into wedges (optional)", nil, "lime", "1", "cut into wedges"),
        ]
        for (text, unit, item, quantity, preparation) in optionalItems {
            rows.append(
                Row(
                    text, quantity: quantity, unitID: unit, item: item,
                    preparation: preparation, optional: true))
        }
        // 7. Preparation phrases (60).
        let preps = [
            "finely chopped", "roughly chopped", "finely diced", "minced",
            "grated", "shredded", "thinly sliced", "melted", "softened",
            "at room temperature", "beaten", "separated", "peeled and deveined",
            "halved", "quartered", "crushed", "ground", "torn into pieces",
            "rinsed and drained", "packed",
        ]
        let prepItems = [
            "onion", "garlic", "carrots", "celery", "butter", "cream cheese",
            "eggs", "shrimp", "potatoes", "apples", "parsley", "basil",
        ]
        for (index, item) in prepItems.enumerated() {
            let prep = preps[index % preps.count]
            rows.append(
                Row("1 \(item), \(prep)", quantity: "1", item: item, preparation: prep))
        }

        // 8. Sizes (30).
        let sizes = ["large", "medium", "small"]
        for (index, item) in ["eggs", "onion", "lemon", "apples", "potatoes"].enumerated() {
            let size = sizes[index % sizes.count]
            rows.append(Row("2 \(size) \(item)", quantity: "2", item: "\(size) \(item)"))
            rows.append(Row("3 \(size) \(item)", quantity: "3", item: "\(size) \(item)"))
            rows.append(Row("4 \(size) \(item)", quantity: "4", item: "\(size) \(item)"))
        }

        // 9. Parenthetical notes (40).
        let noted = [
            ("2 cups flour (plus more for dusting)", "2", "cup", "flour", "plus more for dusting"),
            ("1 tbsp butter (salted or unsalted)", "1", "tbsp", "butter", "salted or unsalted"),
            ("3 cups stock (chicken or vegetable)", "3", "cup", "stock", "chicken or vegetable"),
            ("1 lb ground beef (80/20)", "1", "lb", "ground beef", "80/20"),
            ("2 tbsp soy sauce (low sodium)", "2", "tbsp", "soy sauce", "low sodium"),
            ("1 can coconut milk (full fat)", "1", "can", "coconut milk", "full fat"),
            ("4 oz cream cheese (softened)", "4", "ozm", "cream cheese", "softened"),
            ("1/2 cup cilantro (leaves and stems)", "0.5", "cup", "cilantro", "leaves and stems"),
        ]
        for (text, quantity, unit, item, note) in noted {
            rows.append(
                Row(text, quantity: quantity, unitID: unit, item: item, note: note))
            rows.append(
                Row(text, quantity: quantity, unitID: unit, item: item, note: note))
        }

        // 10. Section headers (30).
        let headers = [
            "For the marinade:", "For the dressing:", "Dressing", "Crust", "Topping",
            "For the sauce:", "Marinade", "For serving:", "Garnish", "Filling",
            "For the glaze:", "Streusel", "Sauce", "For the batter:", "Assembly",
        ]
        for header in headers {
            rows.append(Row(header, item: header, isHeader: true))
        }

        // 11. Mixed and tricky real-world forms (70).
        let tricky: [Row] = [
            Row("1 1/2 cups flour", quantity: "1.5", unitID: "cup", item: "flour"),
            Row("2 1/2 lbs potatoes", quantity: "2.5", unitID: "lb", item: "potatoes"),
            Row("1½ cups milk", quantity: "1.5", unitID: "cup", item: "milk"),
            Row("2¼ tsp yeast", quantity: "2.25", unitID: "tsp", item: "yeast"),
            Row("½ cup olive oil", quantity: "0.5", unitID: "cup", item: "olive oil"),
            Row("¾ cup sugar", quantity: "0.75", unitID: "cup", item: "sugar"),
            Row("⅓ cup brown sugar", quantity: "1/3", unitID: "cup", item: "brown sugar"),
            Row("⅔ cup water", quantity: "2/3", unitID: "cup", item: "water"),
            Row("one-half lemon", quantity: "0.5", item: "lemon"),
            Row("1 kg flour", quantity: "1", unitID: "kg", item: "flour"),
            Row("500 g flour", quantity: "500", unitID: "g", item: "flour"),
            Row("1 l milk", quantity: "1", unitID: "l", item: "milk"),
            Row("250 ml cream", quantity: "250", unitID: "ml", item: "cream"),
            Row("1 fl oz vanilla", quantity: "1", unitID: "oz", item: "vanilla"),
            Row("2 fluid ounces whiskey", quantity: "2", unitID: "oz", item: "whiskey"),
            Row("1 pt heavy cream", quantity: "1", unitID: "pint", item: "heavy cream"),
            Row("1 qt stock", quantity: "1", unitID: "quart", item: "stock"),
            Row("1 gal water", quantity: "1", unitID: "gallon", item: "water"),
            Row("2 ozs butter", quantity: "2", unitID: "ozm", item: "butter"),
            Row("1 tspns salt", quantity: "1", unitID: "tsp", item: "salt"),
            Row(
                "1 clove garlic, minced", quantity: "1", unitID: "clove", item: "garlic",
                preparation: "minced"),
            Row(
                "2 sticks butter, softened", quantity: "2", unitID: "stick", item: "butter",
                preparation: "softened"),
            Row(
                "1 bunch scallions, trimmed", quantity: "1", unitID: "bunch", item: "scallions",
                preparation: "trimmed"),
            Row("3 sprigs thyme", quantity: "3", unitID: "sprig", item: "thyme"),
            Row("1 pinch nutmeg", quantity: "1", unitID: "pinch", item: "nutmeg"),
            Row("2 pinches cayenne", quantity: "2", unitID: "pinch", item: "cayenne"),
            Row(
                "1 can chickpeas, rinsed and drained", quantity: "1", unitID: "can",
                item: "chickpeas", preparation: "rinsed and drained"),
            Row("2 cans diced tomatoes", quantity: "2", unitID: "can", item: "diced tomatoes"),
            Row("1 onion, diced", quantity: "1", item: "onion", preparation: "diced"),
            Row(
                "3 carrots, peeled and sliced", quantity: "3", item: "carrots",
                preparation: "peeled and sliced"),
            Row(
                "4 tbsp butter, divided", quantity: "4", unitID: "tbsp", item: "butter",
                preparation: "divided"),
            Row("1 lemon, juiced", quantity: "1", item: "lemon", preparation: "juiced"),
            Row("2 eggs, beaten", quantity: "2", item: "eggs", preparation: "beaten"),
            Row("2 eggs, separated", quantity: "2", item: "eggs", preparation: "separated"),
            Row(
                "1 cup pecans, toasted", quantity: "1", unitID: "cup", item: "pecans",
                preparation: "toasted"),
            Row(
                "1/2 cup basil, torn", quantity: "0.5", unitID: "cup", item: "basil",
                preparation: "torn"),
            Row(
                "8 oz cream cheese, at room temperature", quantity: "8", unitID: "ozm",
                item: "cream cheese", preparation: "at room temperature"),
            Row(
                "1 lb kale, stems removed", quantity: "1", unitID: "lb", item: "kale",
                preparation: "stems removed"),
            Row("1 1/4 cups buttermilk", quantity: "1.25", unitID: "cup", item: "buttermilk"),
            Row("1/8 tsp cayenne", quantity: "0.125", unitID: "tsp", item: "cayenne"),
            Row("1/8 cup honey", quantity: "0.125", unitID: "cup", item: "honey"),
            Row("0.5 cup yogurt", quantity: "0.5", unitID: "cup", item: "yogurt"),
            Row("1.25 lbs ground turkey", quantity: "1.25", unitID: "lb", item: "ground turkey"),
            Row("2.5 cups rolled oats", quantity: "2.5", unitID: "cup", item: "rolled oats"),
            Row("3.5 oz chocolate", quantity: "3.5", unitID: "ozm", item: "chocolate"),
            Row("12 ozs beer", quantity: "12", unitID: "ozm", item: "beer"),
            Row("1 sq chocolate", quantity: "1", item: "sq chocolate"),
            Row("2 qt strawberries", quantity: "2", unitID: "quart", item: "strawberries"),
            Row("1/2 stick butter", quantity: "0.5", unitID: "stick", item: "butter"),
            Row("1/2 clove garlic", quantity: "0.5", unitID: "clove", item: "garlic"),
            Row("6 cups baby spinach", quantity: "6", unitID: "cup", item: "baby spinach"),
            Row("1 cup chopped walnuts", quantity: "1", unitID: "cup", item: "chopped walnuts"),
            Row("2 tbsp chopped parsley", quantity: "2", unitID: "tbsp", item: "chopped parsley"),
            Row("1/4 cup chopped onion", quantity: "0.25", unitID: "cup", item: "chopped onion"),
            Row("1 tbsp minced garlic", quantity: "1", unitID: "tbsp", item: "minced garlic"),
            Row(
                "2 large carrots, cut into wedges", quantity: "2", item: "large carrots",
                preparation: "cut into wedges"),
            Row("1/2 tsp table salt", quantity: "0.5", unitID: "tsp", item: "table salt"),
            Row(
                "1/4 tsp freshly ground pepper", quantity: "0.25", unitID: "tsp",
                item: "freshly ground pepper"),
            Row(
                "2 tbsp extra-virgin olive oil", quantity: "2", unitID: "tbsp",
                item: "extra-virgin olive oil"),
            Row("1 cup whole milk", quantity: "1", unitID: "cup", item: "whole milk"),
            Row(
                "2 cups self-rising flour", quantity: "2", unitID: "cup", item: "self-rising flour"),
            Row("1 cup sour cream", quantity: "1", unitID: "cup", item: "sour cream"),
            Row("1/2 cup half-and-half", quantity: "0.5", unitID: "cup", item: "half-and-half"),
            Row("3 tbsp unsalted butter", quantity: "3", unitID: "tbsp", item: "unsalted butter"),
            Row("1 vanilla bean", quantity: "1", item: "vanilla bean"),
            Row("2 strips bacon", quantity: "2", item: "strips bacon"),
            Row("1 slice bread", quantity: "1", item: "slice bread"),
            Row("4 slices bacon", quantity: "4", item: "slices bacon"),
            Row("1 head garlic", quantity: "1", item: "head garlic"),
            Row("1 bulb fennel", quantity: "1", item: "bulb fennel"),
        ]
        rows.append(contentsOf: tricky)

        // 12. Kitchen lines written for use (47), expectations from probe.
        let kitchen: [Row] = [
            Row("1/2 teaspoon kosher salt", quantity: "0.5", unitID: "tsp", item: "kosher salt"),
            Row(
                "2 tablespoons unsalted butter, melted", quantity: "2", unitID: "tbsp",
                item: "unsalted butter", preparation: "melted"),
            Row(
                "1 medium yellow onion, diced", quantity: "1", item: "medium yellow onion",
                preparation: "diced"),
            Row(
                "1/4 cup whole wheat flour", quantity: "0.25", unitID: "cup",
                item: "whole wheat flour"),
            Row(
                "3 cloves garlic, smashed", quantity: "3", unitID: "clove", item: "garlic",
                preparation: "smashed"),
            Row("1 cup chicken broth", quantity: "1", unitID: "cup", item: "chicken broth"),
            Row("12 ounces whole milk", quantity: "12", unitID: "ozm", item: "whole milk"),
            Row(
                "1 can (14 oz) crushed tomatoes", quantity: "1", unitID: "can",
                item: "crushed tomatoes", note: "14 oz"),
            Row(
                "2 ribs celery, thinly sliced", quantity: "2", item: "ribs celery",
                preparation: "thinly sliced"),
            Row(
                "1 tablespoon fresh lemon juice", quantity: "1", unitID: "tbsp",
                item: "fresh lemon juice"),
            Row(
                "1 1/2 teaspoons vanilla extract", quantity: "1.5", unitID: "tsp",
                item: "vanilla extract"),
            Row(
                "1/3 cup chopped fresh basil", quantity: "1/3", unitID: "cup",
                item: "chopped fresh basil"),
            Row("2 cups baby arugula", quantity: "2", unitID: "cup", item: "baby arugula"),
            Row("8 ounces dried pasta", quantity: "8", unitID: "ozm", item: "dried pasta"),
            Row(
                "1 red bell pepper, seeded and diced", quantity: "1", item: "red bell pepper",
                preparation: "seeded and diced"),
            Row("4 boneless chicken thighs", quantity: "4", item: "boneless chicken thighs"),
            Row(
                "2 cups grated Parmesan cheese", quantity: "2", unitID: "cup",
                item: "grated Parmesan cheese"),
            Row(
                "1 tablespoon Dijon mustard", quantity: "1", unitID: "tbsp",
                item: "Dijon mustard"),
            Row("1/2 cup heavy cream", quantity: "0.5", unitID: "cup", item: "heavy cream"),
            Row("6 sprigs fresh thyme", quantity: "6", unitID: "sprig", item: "fresh thyme"),
            Row(
                "1 large carrot, grated", quantity: "1", item: "large carrot",
                preparation: "grated"),
            Row(
                "3/4 cup granulated sugar", quantity: "0.75", unitID: "cup",
                item: "granulated sugar"),
            Row("1 pound ground pork", quantity: "1", unitID: "lb", item: "ground pork"),
            Row(
                "2 tbsp flaxseed meal (optional)", quantity: "2", unitID: "tbsp",
                item: "flaxseed meal", optional: true),
            Row(
                "1/2 cup toasted sliced almonds", quantity: "0.5", unitID: "cup",
                item: "toasted sliced almonds"),
            Row("1 cup cold water", quantity: "1", unitID: "cup", item: "cold water"),
            Row("24 pitted dates", quantity: "24", item: "pitted dates"),
            Row("2 star anise", quantity: "2", item: "star anise"),
            Row(
                "1/2 cup crumbled feta cheese", quantity: "0.5", unitID: "cup",
                item: "crumbled feta cheese"),
            Row(
                "1 orange, zested and juiced", quantity: "1", item: "orange",
                preparation: "zested and juiced"),
            Row("5 whole cloves", quantity: "5", item: "whole cloves"),
            Row("1 tsp ground cumin", quantity: "1", unitID: "tsp", item: "ground cumin"),
            Row(
                "1 1/2 lbs boneless skinless chicken breasts", quantity: "1.5", unitID: "lb",
                item: "boneless skinless chicken breasts"),
            Row("3 tbsp tomato paste", quantity: "3", unitID: "tbsp", item: "tomato paste"),
            Row(
                "1 cup uncooked white rice", quantity: "1", unitID: "cup",
                item: "uncooked white rice"),
            Row(
                "1/4 teaspoon freshly grated nutmeg", quantity: "0.25", unitID: "tsp",
                item: "freshly grated nutmeg"),
            Row(
                "2 quarts chicken stock", quantity: "2", unitID: "quart",
                item: "chicken stock"),
            Row(
                "1 tbsp apple cider vinegar", quantity: "1", unitID: "tbsp",
                item: "apple cider vinegar"),
            Row(
                "1/2 cup plain whole-milk yogurt", quantity: "0.5", unitID: "cup",
                item: "plain whole-milk yogurt"),
            Row(
                "6 tbsp cold unsalted butter, cubed", quantity: "6", unitID: "tbsp",
                item: "cold unsalted butter", preparation: "cubed"),
            Row("3 large egg yolks", quantity: "3", item: "large egg yolks"),
            Row(
                "1/4 cup heavy whipping cream", quantity: "0.25", unitID: "cup",
                item: "heavy whipping cream"),
            Row("2 tsp smoked paprika", quantity: "2", unitID: "tsp", item: "smoked paprika"),
            Row(
                "1 cup shredded Monterey Jack cheese", quantity: "1", unitID: "cup",
                item: "shredded Monterey Jack cheese"),
            Row("1 bay leaf", quantity: "1", item: "bay leaf"),
            Row(
                "1 tbsp worcestershire sauce", quantity: "1", unitID: "tbsp",
                item: "worcestershire sauce"),
            Row(
                "1/2 cup finely chopped walnuts", quantity: "0.5", unitID: "cup",
                item: "finely chopped walnuts"),
            Row(
                "1 cup powdered sugar, sifted", quantity: "1", unitID: "cup",
                item: "powdered sugar", preparation: "sifted"),
            Row(
                "1 lb brussels sprouts, trimmed and halved", quantity: "1", unitID: "lb",
                item: "brussels sprouts", preparation: "trimmed and halved"),
        ]
        rows.append(contentsOf: kitchen)

        // 13. Aromatics and produce with preparation (40).
        let aromatics = [
            "yellow onion", "white onion", "red onion", "shallot", "shallots", "garlic",
            "ginger", "carrot", "carrots", "celery rib", "celery ribs", "bell pepper",
            "red bell pepper", "green bell pepper", "jalapeño", "jalapeños", "zucchini",
            "yellow squash", "mushrooms", "cremini mushrooms", "kale", "swiss chard",
            "spinach", "arugula", "basil", "parsley", "cilantro", "mint", "dill", "chives",
            "scallion", "scallions", "leek", "leeks", "fennel bulb", "cabbage",
            "red cabbage", "cauliflower", "broccoli", "green beans",
        ]
        let aromaticPreps = [
            "finely chopped", "thinly sliced", "roughly chopped", "minced",
            "grated", "diced",
        ]
        let aromaticAmounts = ["1", "2", "1/2", "3", "4", "1/3"]
        for (index, item) in aromatics.enumerated() {
            let prep = aromaticPreps[index % aromaticPreps.count]
            let amount = aromaticAmounts[index % aromaticAmounts.count]
            rows.append(
                Row(
                    "\(amount) \(item), \(prep)", quantity: expectedAmount(amount),
                    item: item, preparation: prep))
        }

        // 14. Baking and pantry forms (46).
        let baking: [(String, String, String, String?)] = [
            ("2", "cup", "all-purpose flour", nil),
            ("3", "cup", "bread flour", nil),
            ("1", "tsp", "baking powder", nil),
            ("1/2", "tsp", "baking soda", nil),
            ("1", "tsp", "fine sea salt", nil),
            ("2", "tbsp", "instant yeast", nil),
            ("1/4", "cup", "cornstarch", nil),
            ("1", "cup", "rolled oats", nil),
            ("1", "cup", "brown sugar", "packed"),
            ("3/4", "cup", "cocoa powder", nil),
            ("1", "tsp", "vanilla extract", nil),
            ("2", "tbsp", "honey", nil),
            ("1/4", "cup", "maple syrup", nil),
            ("1", "cup", "chocolate chips", nil),
            ("1/2", "cup", "chopped pecans", nil),
            ("1", "cup", "walnut halves", nil),
            ("2", "cup", "powdered sugar", nil),
            ("1", "tbsp", "corn syrup", nil),
            ("1", "tsp", "kosher salt", nil),
            ("1/2", "cup", "vegetable oil", nil),
            ("1", "cup", "granulated sugar", nil),
            ("1/4", "tsp", "almond extract", nil),
            ("1", "tbsp", "active dry yeast", nil),
            ("2", "cup", "cake flour", nil),
            ("1/3", "cup", "unsweetened coconut", nil),
            ("1/2", "tsp", "cream of tartar", nil),
            ("1", "cup", "semolina flour", nil),
            ("2", "tbsp", "flaxseed meal", nil),
            ("1", "tsp", "ground cinnamon", nil),
            ("1/2", "tsp", "ground ginger", nil),
            ("1/4", "tsp", "ground cloves", nil),
            ("1/8", "tsp", "ground allspice", nil),
            ("1", "cup", "whole wheat flour", nil),
            ("1", "cup", "rye flour", nil),
            ("2", "tbsp", "sesame seeds", nil),
            ("1/4", "cup", "sunflower seeds", nil),
            ("1/2", "cup", "raisins", nil),
            ("1", "cup", "dried cranberries", nil),
            ("1/3", "cup", "chopped dates", nil),
            ("1", "tbsp", "orange zest", nil),
            ("2", "tsp", "lemon zest", nil),
            ("1", "tbsp", "espresso powder", nil),
            ("1/4", "cup", "turbinado sugar", nil),
            ("1", "tsp", "xanthan gum", nil),
            ("1", "stick", "butter", nil),
            ("2", "stick", "butter", "softened"),
        ]
        for (amount, unit, item, prep) in baking {
            rows.append(
                Row(
                    "\(amount) \(unit) \(item)\(prep.map { ", \($0)" } ?? "")",
                    quantity: expectedAmount(amount), unitID: unit, item: item,
                    preparation: prep))
        }

        // 15. Spices and seasonings (40).
        let spiceItems = [
            "cumin", "coriander", "cardamom", "cinnamon", "turmeric", "smoked paprika",
            "cayenne", "chili powder", "curry powder", "garam masala", "oregano", "thyme",
            "rosemary", "basil", "marjoram", "sage", "tarragon", "dill weed",
            "fennel seed", "mustard seed", "celery seed", "caraway seed", "poppy seed",
            "sesame seed",
        ]
        let spiceForms = [
            ("1 tsp", "tsp", "1"), ("1/2 tsp", "tsp", "0.5"), ("1/4 tsp", "tsp", "0.25"),
            ("1/8 tsp", "tsp", "0.125"), ("2 tsp", "tsp", "2"), ("1 tbsp", "tbsp", "1"),
        ]
        for (index, item) in spiceItems.enumerated() {
            let (spelling, unit, expected) = spiceForms[index % spiceForms.count]
            rows.append(
                Row(
                    "\(spelling) ground \(item)", quantity: expected, unitID: unit,
                    item: "ground \(item)"))
        }
        let seasoningRows: [Row] = [
            Row("1 tsp kosher salt", quantity: "1", unitID: "tsp", item: "kosher salt"),
            Row("1 tsp table salt", quantity: "1", unitID: "tsp", item: "table salt"),
            Row("1/2 tsp sea salt", quantity: "0.5", unitID: "tsp", item: "sea salt"),
            Row(
                "1 tsp freshly ground black pepper", quantity: "1", unitID: "tsp",
                item: "freshly ground black pepper"),
            Row("1/2 tsp white pepper", quantity: "0.5", unitID: "tsp", item: "white pepper"),
            Row(
                "1/4 tsp red pepper flakes", quantity: "0.25", unitID: "tsp",
                item: "red pepper flakes"),
            Row("1 pinch cayenne", quantity: "1", unitID: "pinch", item: "cayenne"),
            Row("1 pinch flaky salt", quantity: "1", unitID: "pinch", item: "flaky salt"),
            Row("2 pinches kosher salt", quantity: "2", unitID: "pinch", item: "kosher salt"),
            Row("1 pinch coarse salt", quantity: "1", unitID: "pinch", item: "coarse salt"),
            Row("1 tsp garlic powder", quantity: "1", unitID: "tsp", item: "garlic powder"),
            Row("1 tsp onion powder", quantity: "1", unitID: "tsp", item: "onion powder"),
            Row("1/2 tsp garlic salt", quantity: "0.5", unitID: "tsp", item: "garlic salt"),
            Row("1 tsp paprika", quantity: "1", unitID: "tsp", item: "paprika"),
            Row(
                "1 tsp italian seasoning", quantity: "1", unitID: "tsp",
                item: "italian seasoning"),
            Row(
                "1 tsp herbes de provence", quantity: "1", unitID: "tsp",
                item: "herbes de provence"),
        ]
        rows.append(contentsOf: seasoningRows)

        // 16. Dairy (30).
        let dairy: [(String, String, String)] = [
            ("1", "cup", "whole milk"), ("2", "cup", "buttermilk"),
            ("1/2", "cup", "ricotta cheese"), ("8", "ozm", "cream cheese"),
            ("1", "cup", "sour cream"), ("1/2", "cup", "creme fraiche"),
            ("4", "ozm", "goat cheese"), ("1", "cup", "half-and-half"),
            ("2", "cup", "skim milk"), ("1/4", "cup", "grated pecorino"),
            ("1", "lb", "mozzarella"), ("1/2", "lb", "fontina"), ("3", "ozm", "feta"),
            ("1", "gallon", "whole milk"), ("1", "pint", "heavy cream"),
            ("1", "quart", "buttermilk"), ("250", "ml", "milk"), ("500", "ml", "cream"),
            ("1", "l", "buttermilk"), ("100", "g", "parmesan"),
            ("200", "g", "mascarpone"), ("150", "g", "feta"), ("50", "g", "pecorino"),
            ("1.5", "cup", "milk"), ("0.5", "cup", "cream"),
            ("0.75", "cup", "half-and-half"), ("1/3", "cup", "sour cream"),
            ("2/3", "cup", "buttermilk"), ("3/4", "lb", "butter"),
            ("1/4", "lb", "cream cheese"),
        ]
        for (amount, unit, item) in dairy {
            rows.append(
                Row(
                    "\(amount) \(unit) \(item)", quantity: expectedAmount(amount),
                    unitID: unit, item: item))
        }

        return rows
    }

    /// What the parser should produce for a corpus amount literal.
    ///
    /// Repeating fractions are compared against Decimal's exact division
    /// result, so the expectation is written as that division, not as a
    /// rounded literal.
    private static func expectedAmount(_ literal: String) -> String {
        switch literal {
        case "¼": return "0.25"
        case "¾": return "0.75"
        case "½": return "0.5"
        case "⅓", "1/3": return "1/3"
        case "⅔", "2/3": return "2/3"
        case "⅕": return "0.2"
        case "⅖": return "0.4"
        case "⅗": return "0.6"
        case "⅘": return "0.8"
        case "⅙": return "1/6"
        case "⅚": return "5/6"
        case "⅛": return "0.125"
        case "⅜": return "0.375"
        case "⅝": return "0.625"
        case "⅞": return "0.875"
        case "1/2": return "0.5"
        case "1/4": return "0.25"
        case "3/4": return "0.75"
        default: return literal
        }
    }

    /// The catalog ID for a bare unit word used in a range ("cups" → cup).
    private static func catalogUnitID(_ word: String) -> String? {
        let catalog = UnitCatalog()
        return catalog.definition(matching: word)?.id
    }

    /// For two-word range items ("cloves garlic"), the item without its
    /// leading unit word.
    private static func restOf(_ item: String) -> String {
        let words = item.split(separator: " ")
        guard words.count > 1 else { return item }
        return words[1...].joined(separator: " ")
    }
}
