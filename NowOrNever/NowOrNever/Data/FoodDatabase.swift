import Foundation

// MARK: - Alimento

/// Un alimento con sus valores por 100 g.
struct Food: Hashable {
    let name: String
    let kcal: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    /// Peso de una unidad (un huevo, un plátano...), si tiene sentido contarlo así.
    let unitGrams: Double?
    let unitSingular: String?
    let unitPlural: String?

    init(_ name: String,
         kcal: Double,
         protein: Double,
         carbs: Double,
         fat: Double,
         unitGrams: Double? = nil,
         unitSingular: String? = nil,
         unitPlural: String? = nil) {
        self.name = name
        self.kcal = kcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.unitGrams = unitGrams
        self.unitSingular = unitSingular
        self.unitPlural = unitPlural
    }
}

// MARK: - Ingrediente

/// Un alimento con los gramos que lleva el plato.
struct Ingredient: Hashable, Identifiable {
    let food: Food
    let grams: Double

    var id: String { food.name }

    init(_ food: Food, _ grams: Double) {
        self.food = food
        self.grams = grams
    }

    var totals: MacroTotals {
        let k = grams / 100
        return MacroTotals(calories: food.kcal * k,
                           protein: food.protein * k,
                           carbs: food.carbs * k,
                           fat: food.fat * k)
    }

    /// Ajusta los gramos y los redondea a algo que se pueda pesar.
    func scaled(by factor: Double) -> Ingredient {
        if let unit = food.unitGrams, unit > 0 {
            let units = max(1, (grams * factor / unit).rounded())
            return Ingredient(food, units * unit)
        }
        let raw = grams * factor
        let step: Double = raw < 20 ? 1 : 5
        let rounded = max(step, (raw / step).rounded() * step)
        return Ingredient(food, rounded)
    }

    /// "150 g de pechuga de pollo" o "2 huevos (110 g)".
    var line: String {
        if let unit = food.unitGrams, unit > 0 {
            let units = Int((grams / unit).rounded())
            let label = units == 1 ? (food.unitSingular ?? food.name) : (food.unitPlural ?? food.name)
            return "\(units) \(label) (\(Formatters.grams(grams)) g)"
        }
        return "\(Formatters.grams(grams)) g de \(food.name)"
    }
}

// MARK: - Receta

/// Un plato de la base de comidas.
struct Recipe: Identifiable, Hashable {
    let id: String
    let name: String
    let type: MealType
    /// Si se prepara en un minuto y se puede llevar encima.
    let quick: Bool
    let ingredients: [Ingredient]

    init(id: String, name: String, type: MealType, quick: Bool = false, ingredients: [Ingredient]) {
        self.id = id
        self.name = name
        self.type = type
        self.quick = quick
        self.ingredients = ingredients
    }

    var baseTotals: MacroTotals {
        ingredients.reduce(into: MacroTotals.zero) { $0 += $1.totals }
    }

    /// Ajusta el plato a unas calorías objetivo, sin pasarse de lo razonable.
    func scaled(toCalories target: Double) -> ScaledRecipe {
        let base = baseTotals.calories
        guard base > 0 else { return ScaledRecipe(recipe: self, ingredients: ingredients) }
        let factor = min(1.6, max(0.6, target / base))
        return ScaledRecipe(recipe: self, ingredients: ingredients.map { $0.scaled(by: factor) })
    }
}

/// Una receta con los gramos ya ajustados al objetivo del día.
struct ScaledRecipe: Identifiable {
    let recipe: Recipe
    let ingredients: [Ingredient]

    var id: String { recipe.id }
    var name: String { recipe.name }
    var type: MealType { recipe.type }

    var totals: MacroTotals {
        ingredients.reduce(into: MacroTotals.zero) { $0 += $1.totals }
    }

    var ingredientLines: [String] { ingredients.map(\.line) }

    /// Modelo de SwiftData listo para guardar.
    func makePlannedMeal() -> PlannedMeal {
        let t = totals
        return PlannedMeal(type: recipe.type,
                           recipeID: recipe.id,
                           name: recipe.name,
                           ingredientLines: ingredientLines,
                           calories: t.calories.rounded(),
                           protein: t.protein.rounded(),
                           carbs: t.carbs.rounded(),
                           fat: t.fat.rounded())
    }
}

// MARK: - Catálogo de alimentos (valores por 100 g)

enum Foods {
    // Cereales y panes
    static let pan = Food("pan de barra", kcal: 265, protein: 9, carbs: 49, fat: 1.5)
    static let panIntegral = Food("pan integral", kcal: 247, protein: 10, carbs: 41, fat: 3.5)
    static let panMolde = Food("pan de molde integral", kcal: 250, protein: 10, carbs: 41, fat: 4,
                               unitGrams: 30, unitSingular: "rebanada de pan de molde integral",
                               unitPlural: "rebanadas de pan de molde integral")
    static let avena = Food("copos de avena", kcal: 380, protein: 13, carbs: 60, fat: 7)
    static let arroz = Food("arroz blanco (en crudo)", kcal: 350, protein: 7, carbs: 78, fat: 1)
    static let pasta = Food("pasta (en crudo)", kcal: 371, protein: 13, carbs: 75, fat: 1.5)
    static let quinoa = Food("quinoa (en crudo)", kcal: 368, protein: 14, carbs: 64, fat: 6)
    static let cuscus = Food("cuscús (en crudo)", kcal: 376, protein: 13, carbs: 77, fat: 0.6)
    static let tortitasLegumbres = Food("tortitas de legumbres", kcal: 360, protein: 19, carbs: 58, fat: 3)
    static let tortitasArroz = Food("tortitas de arroz", kcal: 387, protein: 8, carbs: 81, fat: 3,
                                    unitGrams: 8, unitSingular: "tortita de arroz", unitPlural: "tortitas de arroz")
    static let wrap = Food("tortilla de trigo", kcal: 300, protein: 8, carbs: 48, fat: 8)

    // Carnes y pescados
    static let pollo = Food("pechuga de pollo", kcal: 165, protein: 31, carbs: 0, fat: 3.6)
    static let pavoFilete = Food("pechuga de pavo", kcal: 104, protein: 22, carbs: 1, fat: 1.5)
    static let ternera = Food("filete de ternera", kcal: 160, protein: 26, carbs: 0, fat: 6)
    static let carnePicada = Food("carne picada de ternera 5 %", kcal: 137, protein: 21, carbs: 0, fat: 5)
    static let lomo = Food("lomo de cerdo", kcal: 143, protein: 22, carbs: 0, fat: 6)
    static let jamonSerrano = Food("jamón serrano", kcal: 240, protein: 31, carbs: 0.5, fat: 13)
    static let jamonYork = Food("jamón de york", kcal: 110, protein: 18, carbs: 1.5, fat: 3)
    static let fiambrePavo = Food("fiambre de pavo", kcal: 95, protein: 17, carbs: 1.5, fat: 2.5)
    static let atun = Food("atún en lata al natural", kcal: 116, protein: 26, carbs: 0, fat: 1)
    static let salmon = Food("salmón", kcal: 208, protein: 20, carbs: 0, fat: 13)
    static let merluza = Food("merluza", kcal: 90, protein: 18, carbs: 0, fat: 2)
    static let gambas = Food("gambas peladas", kcal: 99, protein: 24, carbs: 0.2, fat: 0.3)

    // Huevos y lácteos
    static let huevo = Food("huevo", kcal: 143, protein: 13, carbs: 1.1, fat: 9.5,
                            unitGrams: 55, unitSingular: "huevo", unitPlural: "huevos")
    static let clara = Food("clara de huevo", kcal: 52, protein: 11, carbs: 0.7, fat: 0.2)
    static let yogurGriego = Food("yogur griego natural 0 %", kcal: 59, protein: 10, carbs: 3.6, fat: 0.4,
                                  unitGrams: 125, unitSingular: "yogur griego natural 0 %",
                                  unitPlural: "yogures griegos naturales 0 %")
    static let yogurNatural = Food("yogur natural", kcal: 61, protein: 3.5, carbs: 4.7, fat: 3.3,
                                   unitGrams: 125, unitSingular: "yogur natural", unitPlural: "yogures naturales")
    static let quesoBatido = Food("queso fresco batido 0 %", kcal: 47, protein: 8, carbs: 4, fat: 0.2)
    static let quesoFresco = Food("queso fresco", kcal: 98, protein: 11, carbs: 3, fat: 4.5)
    static let quesoCurado = Food("queso curado", kcal: 390, protein: 25, carbs: 1, fat: 32)
    static let leche = Food("leche semidesnatada", kcal: 46, protein: 3.3, carbs: 4.8, fat: 1.6)
    static let proteina = Food("proteína en polvo", kcal: 380, protein: 78, carbs: 8, fat: 5)

    // Legumbres
    static let lentejas = Food("lentejas (en crudo)", kcal: 336, protein: 24, carbs: 49, fat: 1.5)
    static let garbanzos = Food("garbanzos cocidos", kcal: 139, protein: 8, carbs: 20, fat: 2.6)
    static let alubias = Food("alubias blancas cocidas", kcal: 130, protein: 8, carbs: 18, fat: 0.6)

    // Verduras y frutas
    static let brocoli = Food("brócoli", kcal: 34, protein: 2.8, carbs: 7, fat: 0.4)
    static let ensalada = Food("ensalada mixta", kcal: 20, protein: 1.2, carbs: 3, fat: 0.2)
    static let tomate = Food("tomate", kcal: 18, protein: 0.9, carbs: 3.9, fat: 0.2)
    static let tomateTriturado = Food("tomate triturado", kcal: 30, protein: 1.3, carbs: 5.5, fat: 0.3)
    static let cebolla = Food("cebolla", kcal: 40, protein: 1.1, carbs: 9, fat: 0.1)
    static let pimiento = Food("pimiento", kcal: 26, protein: 1, carbs: 6, fat: 0.3)
    static let calabacin = Food("calabacín", kcal: 17, protein: 1.2, carbs: 3.1, fat: 0.3)
    static let berenjena = Food("berenjena", kcal: 25, protein: 1, carbs: 6, fat: 0.2)
    static let champinones = Food("champiñones", kcal: 22, protein: 3.1, carbs: 3.3, fat: 0.3)
    static let judiasVerdes = Food("judías verdes", kcal: 31, protein: 1.8, carbs: 7, fat: 0.2)
    static let zanahoria = Food("zanahoria", kcal: 41, protein: 0.9, carbs: 10, fat: 0.2)
    static let espinacas = Food("espinacas", kcal: 23, protein: 2.9, carbs: 3.6, fat: 0.4)
    static let patata = Food("patata", kcal: 77, protein: 2, carbs: 17, fat: 0.1)
    static let boniato = Food("boniato", kcal: 86, protein: 1.6, carbs: 20, fat: 0.1)
    static let maiz = Food("maíz dulce", kcal: 86, protein: 3.2, carbs: 19, fat: 1.2)
    static let platano = Food("plátano", kcal: 89, protein: 1.1, carbs: 23, fat: 0.3,
                              unitGrams: 120, unitSingular: "plátano", unitPlural: "plátanos")
    static let manzana = Food("manzana", kcal: 52, protein: 0.3, carbs: 14, fat: 0.2,
                              unitGrams: 180, unitSingular: "manzana", unitPlural: "manzanas")
    static let naranja = Food("naranja", kcal: 47, protein: 0.9, carbs: 12, fat: 0.1,
                              unitGrams: 180, unitSingular: "naranja", unitPlural: "naranjas")
    static let fresas = Food("fresas", kcal: 32, protein: 0.7, carbs: 7.7, fat: 0.3)
    static let arandanos = Food("arándanos", kcal: 57, protein: 0.7, carbs: 14, fat: 0.3)
    static let aguacate = Food("aguacate", kcal: 160, protein: 2, carbs: 9, fat: 15)

    // Grasas y extras
    static let aceite = Food("aceite de oliva", kcal: 884, protein: 0, carbs: 0, fat: 100)
    static let almendras = Food("almendras", kcal: 579, protein: 21, carbs: 22, fat: 50)
    static let nueces = Food("nueces", kcal: 654, protein: 15, carbs: 14, fat: 65)
    static let cremaCacahuete = Food("crema de cacahuete", kcal: 588, protein: 25, carbs: 20, fat: 50)
    static let miel = Food("miel", kcal: 304, protein: 0.3, carbs: 82, fat: 0)
    static let cacao = Food("cacao en polvo desgrasado", kcal: 330, protein: 22, carbs: 16, fat: 11)
    static let chocolateNegro = Food("chocolate negro 85 %", kcal: 600, protein: 10, carbs: 22, fat: 50)
    static let lecheCoco = Food("leche de coco light", kcal: 73, protein: 0.7, carbs: 3, fat: 6.5)
}

// MARK: - Base de comidas

/// Todas las recetas de la app, en comida española normal.
enum FoodDatabase {

    static let recipes: [Recipe] = breakfasts + lunches + snacks + dinners

    static func recipes(for type: MealType) -> [Recipe] {
        switch type {
        case .breakfast: return breakfasts
        case .lunch: return lunches
        case .snack: return snacks
        case .dinner: return dinners
        }
    }

    static func recipe(id: String) -> Recipe? {
        recipes.first { $0.id == id }
    }

    // MARK: Desayunos

    static let breakfasts: [Recipe] = [
        Recipe(id: "des-pan-serrano", name: "Pan con jamón serrano", type: .breakfast, quick: true,
               ingredients: [Ingredient(Foods.pan, 90),
                             Ingredient(Foods.jamonSerrano, 60),
                             Ingredient(Foods.tomate, 60),
                             Ingredient(Foods.aceite, 8)]),

        Recipe(id: "des-tortitas-york", name: "Tortitas de legumbres con jamón de york", type: .breakfast, quick: true,
               ingredients: [Ingredient(Foods.tortitasLegumbres, 45),
                             Ingredient(Foods.jamonYork, 100),
                             Ingredient(Foods.quesoFresco, 40),
                             Ingredient(Foods.tomate, 60)]),

        Recipe(id: "des-tostadas-pavo", name: "Tostadas con pavo y queso fresco", type: .breakfast, quick: true,
               ingredients: [Ingredient(Foods.panMolde, 60),
                             Ingredient(Foods.fiambrePavo, 90),
                             Ingredient(Foods.quesoFresco, 50),
                             Ingredient(Foods.tomate, 60)]),

        Recipe(id: "des-yogur-avena", name: "Yogur griego con avena y plátano", type: .breakfast, quick: true,
               ingredients: [Ingredient(Foods.yogurGriego, 250),
                             Ingredient(Foods.avena, 50),
                             Ingredient(Foods.platano, 120),
                             Ingredient(Foods.miel, 10)]),

        Recipe(id: "des-bocadillo-atun", name: "Bocadillo de atún", type: .breakfast, quick: true,
               ingredients: [Ingredient(Foods.pan, 90),
                             Ingredient(Foods.atun, 110),
                             Ingredient(Foods.tomate, 60),
                             Ingredient(Foods.aceite, 6)]),

        Recipe(id: "des-tostada-aguacate-huevo", name: "Tostada de aguacate con huevo", type: .breakfast, quick: true,
               ingredients: [Ingredient(Foods.panIntegral, 80),
                             Ingredient(Foods.aguacate, 60),
                             Ingredient(Foods.huevo, 110),
                             Ingredient(Foods.tomate, 50)]),

        Recipe(id: "des-batido-avena", name: "Batido de avena, plátano y proteína", type: .breakfast, quick: true,
               ingredients: [Ingredient(Foods.leche, 300),
                             Ingredient(Foods.avena, 50),
                             Ingredient(Foods.platano, 120),
                             Ingredient(Foods.proteina, 30)]),

        Recipe(id: "des-tortitas-arroz-cacahuete", name: "Tortitas de arroz con crema de cacahuete", type: .breakfast, quick: true,
               ingredients: [Ingredient(Foods.tortitasArroz, 32),
                             Ingredient(Foods.cremaCacahuete, 25),
                             Ingredient(Foods.platano, 120),
                             Ingredient(Foods.yogurGriego, 125)]),

        Recipe(id: "des-bocadillo-tortilla", name: "Bocadillo de tortilla francesa", type: .breakfast,
               ingredients: [Ingredient(Foods.pan, 90),
                             Ingredient(Foods.huevo, 110),
                             Ingredient(Foods.clara, 60),
                             Ingredient(Foods.aceite, 6)]),

        Recipe(id: "des-porridge", name: "Avena cocida con leche y manzana", type: .breakfast,
               ingredients: [Ingredient(Foods.avena, 60),
                             Ingredient(Foods.leche, 250),
                             Ingredient(Foods.manzana, 180),
                             Ingredient(Foods.almendras, 15)]),

        Recipe(id: "des-revuelto", name: "Huevos revueltos con pan", type: .breakfast,
               ingredients: [Ingredient(Foods.huevo, 110),
                             Ingredient(Foods.clara, 80),
                             Ingredient(Foods.pan, 70),
                             Ingredient(Foods.aceite, 6)]),

        Recipe(id: "des-queso-batido-fruta", name: "Queso batido con fresas y nueces", type: .breakfast, quick: true,
               ingredients: [Ingredient(Foods.quesoBatido, 300),
                             Ingredient(Foods.fresas, 150),
                             Ingredient(Foods.nueces, 20),
                             Ingredient(Foods.avena, 40)]),

        Recipe(id: "des-tostadas-serrano-queso", name: "Tostadas con serrano y queso curado", type: .breakfast, quick: true,
               ingredients: [Ingredient(Foods.panMolde, 60),
                             Ingredient(Foods.jamonSerrano, 50),
                             Ingredient(Foods.quesoCurado, 25),
                             Ingredient(Foods.naranja, 180)]),

        Recipe(id: "des-wrap-pavo", name: "Wrap de pavo y queso fresco", type: .breakfast, quick: true,
               ingredients: [Ingredient(Foods.wrap, 60),
                             Ingredient(Foods.fiambrePavo, 90),
                             Ingredient(Foods.quesoFresco, 50),
                             Ingredient(Foods.ensalada, 50)])
    ]

    // MARK: Almuerzos

    static let lunches: [Recipe] = [
        Recipe(id: "alm-pollo-arroz", name: "Pollo con arroz y brócoli", type: .lunch,
               ingredients: [Ingredient(Foods.pollo, 180),
                             Ingredient(Foods.arroz, 90),
                             Ingredient(Foods.brocoli, 150),
                             Ingredient(Foods.aceite, 10)]),

        Recipe(id: "alm-lentejas", name: "Lentejas con verduras y pollo", type: .lunch,
               ingredients: [Ingredient(Foods.lentejas, 90),
                             Ingredient(Foods.pollo, 120),
                             Ingredient(Foods.zanahoria, 80),
                             Ingredient(Foods.cebolla, 60),
                             Ingredient(Foods.aceite, 10)]),

        Recipe(id: "alm-pasta-bolonesa", name: "Pasta boloñesa con carne picada", type: .lunch,
               ingredients: [Ingredient(Foods.pasta, 100),
                             Ingredient(Foods.carnePicada, 150),
                             Ingredient(Foods.tomateTriturado, 150),
                             Ingredient(Foods.cebolla, 50),
                             Ingredient(Foods.aceite, 10)]),

        Recipe(id: "alm-ternera-wok", name: "Wok de ternera con verduras y arroz", type: .lunch,
               ingredients: [Ingredient(Foods.ternera, 170),
                             Ingredient(Foods.arroz, 80),
                             Ingredient(Foods.pimiento, 100),
                             Ingredient(Foods.cebolla, 60),
                             Ingredient(Foods.aceite, 10)]),

        Recipe(id: "alm-pollo-curry", name: "Pollo al curry con arroz", type: .lunch,
               ingredients: [Ingredient(Foods.pollo, 180),
                             Ingredient(Foods.arroz, 85),
                             Ingredient(Foods.lecheCoco, 100),
                             Ingredient(Foods.pimiento, 80),
                             Ingredient(Foods.aceite, 8)]),

        Recipe(id: "alm-atun-patata", name: "Atún con patata y ensalada", type: .lunch,
               ingredients: [Ingredient(Foods.atun, 160),
                             Ingredient(Foods.patata, 300),
                             Ingredient(Foods.ensalada, 120),
                             Ingredient(Foods.aceite, 12)]),

        Recipe(id: "alm-merluza-patata", name: "Merluza al horno con patata", type: .lunch,
               ingredients: [Ingredient(Foods.merluza, 200),
                             Ingredient(Foods.patata, 280),
                             Ingredient(Foods.cebolla, 60),
                             Ingredient(Foods.aceite, 12)]),

        Recipe(id: "alm-garbanzos-espinacas", name: "Garbanzos con espinacas y huevo", type: .lunch,
               ingredients: [Ingredient(Foods.garbanzos, 250),
                             Ingredient(Foods.espinacas, 150),
                             Ingredient(Foods.huevo, 110),
                             Ingredient(Foods.aceite, 12)]),

        Recipe(id: "alm-lomo-boniato", name: "Lomo de cerdo con boniato asado", type: .lunch,
               ingredients: [Ingredient(Foods.lomo, 180),
                             Ingredient(Foods.boniato, 250),
                             Ingredient(Foods.judiasVerdes, 150),
                             Ingredient(Foods.aceite, 10)]),

        Recipe(id: "alm-arroz-pollo-verduras", name: "Arroz salteado con pollo y verduras", type: .lunch,
               ingredients: [Ingredient(Foods.arroz, 95),
                             Ingredient(Foods.pollo, 150),
                             Ingredient(Foods.calabacin, 120),
                             Ingredient(Foods.zanahoria, 80),
                             Ingredient(Foods.aceite, 10)]),

        Recipe(id: "alm-pavo-quinoa", name: "Pavo con quinoa y verduras", type: .lunch,
               ingredients: [Ingredient(Foods.pavoFilete, 200),
                             Ingredient(Foods.quinoa, 80),
                             Ingredient(Foods.pimiento, 100),
                             Ingredient(Foods.espinacas, 80),
                             Ingredient(Foods.aceite, 10)]),

        Recipe(id: "alm-alubias-pollo", name: "Alubias blancas con pollo y verduras", type: .lunch,
               ingredients: [Ingredient(Foods.alubias, 250),
                             Ingredient(Foods.pollo, 140),
                             Ingredient(Foods.tomateTriturado, 120),
                             Ingredient(Foods.cebolla, 60),
                             Ingredient(Foods.aceite, 10)]),

        Recipe(id: "alm-pasta-atun", name: "Pasta con atún y tomate", type: .lunch,
               ingredients: [Ingredient(Foods.pasta, 100),
                             Ingredient(Foods.atun, 140),
                             Ingredient(Foods.tomateTriturado, 150),
                             Ingredient(Foods.aceite, 10)]),

        Recipe(id: "alm-salmon-cuscus", name: "Salmón con cuscús y verduras", type: .lunch,
               ingredients: [Ingredient(Foods.salmon, 160),
                             Ingredient(Foods.cuscus, 70),
                             Ingredient(Foods.calabacin, 120),
                             Ingredient(Foods.aceite, 8)]),

        Recipe(id: "alm-ternera-patata", name: "Filete de ternera con patatas y ensalada", type: .lunch,
               ingredients: [Ingredient(Foods.ternera, 180),
                             Ingredient(Foods.patata, 250),
                             Ingredient(Foods.ensalada, 120),
                             Ingredient(Foods.aceite, 12)]),

        Recipe(id: "alm-pollo-pasta-pesto", name: "Pasta con pollo y verduras salteadas", type: .lunch,
               ingredients: [Ingredient(Foods.pasta, 95),
                             Ingredient(Foods.pollo, 160),
                             Ingredient(Foods.champinones, 120),
                             Ingredient(Foods.cebolla, 50),
                             Ingredient(Foods.aceite, 12)])
    ]

    // MARK: Meriendas

    static let snacks: [Recipe] = [
        Recipe(id: "mer-batido-proteina", name: "Batido de proteína con plátano", type: .snack, quick: true,
               ingredients: [Ingredient(Foods.proteina, 30),
                             Ingredient(Foods.leche, 250),
                             Ingredient(Foods.platano, 120)]),

        Recipe(id: "mer-yogur-nueces", name: "Yogur griego con nueces y miel", type: .snack, quick: true,
               ingredients: [Ingredient(Foods.yogurGriego, 250),
                             Ingredient(Foods.nueces, 20),
                             Ingredient(Foods.miel, 10)]),

        Recipe(id: "mer-tortitas-cacahuete", name: "Tortitas de arroz con crema de cacahuete", type: .snack, quick: true,
               ingredients: [Ingredient(Foods.tortitasArroz, 24),
                             Ingredient(Foods.cremaCacahuete, 25)]),

        Recipe(id: "mer-fruta-almendras", name: "Manzana con almendras", type: .snack, quick: true,
               ingredients: [Ingredient(Foods.manzana, 180),
                             Ingredient(Foods.almendras, 25)]),

        Recipe(id: "mer-pan-pavo", name: "Pan con fiambre de pavo", type: .snack, quick: true,
               ingredients: [Ingredient(Foods.pan, 60),
                             Ingredient(Foods.fiambrePavo, 70),
                             Ingredient(Foods.tomate, 50)]),

        Recipe(id: "mer-queso-batido-arandanos", name: "Queso batido con arándanos", type: .snack, quick: true,
               ingredients: [Ingredient(Foods.quesoBatido, 250),
                             Ingredient(Foods.arandanos, 100),
                             Ingredient(Foods.avena, 20)]),

        Recipe(id: "mer-platano-cacahuete", name: "Plátano con crema de cacahuete", type: .snack, quick: true,
               ingredients: [Ingredient(Foods.platano, 120),
                             Ingredient(Foods.cremaCacahuete, 20)]),

        Recipe(id: "mer-naranja-chocolate", name: "Naranja con chocolate negro", type: .snack, quick: true,
               ingredients: [Ingredient(Foods.naranja, 180),
                             Ingredient(Foods.chocolateNegro, 20),
                             Ingredient(Foods.almendras, 15)]),

        Recipe(id: "mer-yogur-fresas", name: "Yogur natural con fresas y avena", type: .snack, quick: true,
               ingredients: [Ingredient(Foods.yogurNatural, 250),
                             Ingredient(Foods.fresas, 150),
                             Ingredient(Foods.avena, 25)]),

        Recipe(id: "mer-tostada-atun", name: "Tostada de atún", type: .snack, quick: true,
               ingredients: [Ingredient(Foods.panMolde, 60),
                             Ingredient(Foods.atun, 80),
                             Ingredient(Foods.tomate, 50)]),

        Recipe(id: "mer-batido-cacao", name: "Batido de cacao y avena", type: .snack, quick: true,
               ingredients: [Ingredient(Foods.leche, 250),
                             Ingredient(Foods.cacao, 10),
                             Ingredient(Foods.avena, 30),
                             Ingredient(Foods.proteina, 20)])
    ]

    // MARK: Cenas

    static let dinners: [Recipe] = [
        Recipe(id: "cen-tortilla-ensalada", name: "Tortilla francesa con ensalada", type: .dinner, quick: true,
               ingredients: [Ingredient(Foods.huevo, 165),
                             Ingredient(Foods.clara, 60),
                             Ingredient(Foods.ensalada, 150),
                             Ingredient(Foods.pan, 50),
                             Ingredient(Foods.aceite, 8)]),

        Recipe(id: "cen-salmon-horno", name: "Salmón al horno con verduras", type: .dinner,
               ingredients: [Ingredient(Foods.salmon, 170),
                             Ingredient(Foods.calabacin, 150),
                             Ingredient(Foods.pimiento, 100),
                             Ingredient(Foods.patata, 150),
                             Ingredient(Foods.aceite, 10)]),

        Recipe(id: "cen-pollo-plancha", name: "Pollo a la plancha con ensalada y pan", type: .dinner, quick: true,
               ingredients: [Ingredient(Foods.pollo, 180),
                             Ingredient(Foods.ensalada, 150),
                             Ingredient(Foods.pan, 60),
                             Ingredient(Foods.aceite, 10)]),

        Recipe(id: "cen-merluza-verduras", name: "Merluza con judías verdes y patata", type: .dinner,
               ingredients: [Ingredient(Foods.merluza, 200),
                             Ingredient(Foods.judiasVerdes, 200),
                             Ingredient(Foods.patata, 180),
                             Ingredient(Foods.aceite, 10)]),

        Recipe(id: "cen-revuelto-gambas", name: "Revuelto de gambas y champiñones", type: .dinner,
               ingredients: [Ingredient(Foods.huevo, 110),
                             Ingredient(Foods.gambas, 120),
                             Ingredient(Foods.champinones, 150),
                             Ingredient(Foods.pan, 60),
                             Ingredient(Foods.aceite, 10)]),

        Recipe(id: "cen-pavo-verduras", name: "Pavo a la plancha con verduras al horno", type: .dinner,
               ingredients: [Ingredient(Foods.pavoFilete, 200),
                             Ingredient(Foods.berenjena, 150),
                             Ingredient(Foods.calabacin, 120),
                             Ingredient(Foods.aceite, 12)]),

        Recipe(id: "cen-ensalada-atun", name: "Ensalada completa de atún y huevo", type: .dinner, quick: true,
               ingredients: [Ingredient(Foods.ensalada, 180),
                             Ingredient(Foods.atun, 120),
                             Ingredient(Foods.huevo, 110),
                             Ingredient(Foods.maiz, 60),
                             Ingredient(Foods.aceite, 10)]),

        Recipe(id: "cen-crema-verduras-pollo", name: "Crema de verduras con pollo a la plancha", type: .dinner,
               ingredients: [Ingredient(Foods.calabacin, 200),
                             Ingredient(Foods.zanahoria, 100),
                             Ingredient(Foods.patata, 120),
                             Ingredient(Foods.pollo, 160),
                             Ingredient(Foods.aceite, 10)]),

        Recipe(id: "cen-wrap-pollo", name: "Wrap de pollo con ensalada", type: .dinner, quick: true,
               ingredients: [Ingredient(Foods.wrap, 60),
                             Ingredient(Foods.pollo, 150),
                             Ingredient(Foods.ensalada, 100),
                             Ingredient(Foods.quesoFresco, 40)]),

        Recipe(id: "cen-ternera-verduras", name: "Ternera salteada con verduras", type: .dinner,
               ingredients: [Ingredient(Foods.ternera, 170),
                             Ingredient(Foods.pimiento, 120),
                             Ingredient(Foods.cebolla, 70),
                             Ingredient(Foods.champinones, 100),
                             Ingredient(Foods.aceite, 10)]),

        Recipe(id: "cen-lomo-ensalada", name: "Lomo a la plancha con ensalada y patata", type: .dinner,
               ingredients: [Ingredient(Foods.lomo, 170),
                             Ingredient(Foods.patata, 180),
                             Ingredient(Foods.ensalada, 150),
                             Ingredient(Foods.aceite, 10)]),

        Recipe(id: "cen-tortilla-patata-atun", name: "Tortilla de patata con atún", type: .dinner,
               ingredients: [Ingredient(Foods.huevo, 110),
                             Ingredient(Foods.patata, 200),
                             Ingredient(Foods.atun, 100),
                             Ingredient(Foods.aceite, 12)]),

        Recipe(id: "cen-pollo-boniato", name: "Pollo al horno con boniato", type: .dinner,
               ingredients: [Ingredient(Foods.pollo, 170),
                             Ingredient(Foods.boniato, 200),
                             Ingredient(Foods.brocoli, 150),
                             Ingredient(Foods.aceite, 10)]),

        Recipe(id: "cen-sandwich-york", name: "Sándwich de york y queso con ensalada", type: .dinner, quick: true,
               ingredients: [Ingredient(Foods.panMolde, 90),
                             Ingredient(Foods.jamonYork, 100),
                             Ingredient(Foods.quesoFresco, 50),
                             Ingredient(Foods.ensalada, 100)])
    ]
}
