import XCTest
@testable import Atlas

/// Los ejercicios que se crea el usuario: que el nombre se valide, que entren en el catálogo
/// y, lo importante, que sus series cuenten en el músculo que él ha elegido.
final class CustomExerciseTests: XCTestCase {

    override func tearDown() {
        ExerciseCatalog.clearCustom()
        super.tearDown()
    }

    // MARK: Validación del nombre

    func testNameCannotBeEmpty() {
        XCTAssertEqual(CustomExerciseRules.validate(name: "   ", mine: [], libraryLookup: { _ in false }), .empty)
    }

    func testNameCannotBeTooLong() {
        let long = String(repeating: "a", count: CustomExerciseRules.maxNameLength + 1)
        XCTAssertEqual(CustomExerciseRules.validate(name: long, mine: [], libraryLookup: { _ in false }), .tooLong)
    }

    func testNameThatIsAlreadyInTheLibraryIsRejected() {
        let problem = CustomExerciseRules.validate(name: "Press de banca con barra", mine: [])
        XCTAssertEqual(problem, .alreadyInLibrary("Press de banca con barra"))
    }

    func testNameThatYouAlreadyUsedIsRejectedEvenWithDifferentAccents() {
        let mine = [(id: "mio-1", name: "Jalón enfatizando espalda alta")]
        let problem = CustomExerciseRules.validate(name: "  jalon enfatizando espalda alta ", mine: mine,
                                                   libraryLookup: { _ in false })
        XCTAssertEqual(problem, .alreadyYours("Jalón enfatizando espalda alta"))
    }

    func testEditingAnExerciseDoesNotClashWithItself() {
        let mine = [(id: "mio-1", name: "Mi remo raro")]
        XCTAssertNil(CustomExerciseRules.validate(name: "Mi remo raro", mine: mine, editingID: "mio-1",
                                                  libraryLookup: { _ in false }))
    }

    func testAGoodNameIsAccepted() {
        XCTAssertNil(CustomExerciseRules.validate(name: "Jalón al pecho enfatizando espalda alta",
                                                  mine: [], libraryLookup: { _ in false }))
    }

    // MARK: La ficha

    func testTheInfoKeepsWhatTheUserChoseAndNeverDuplicatesThePrimaryMuscle() {
        let info = CustomExerciseRules.info(id: "mio-1", name: "  Jalón espalda alta  ", primary: .upperBack,
                                            secondary: [.lats, .upperBack, .biceps], pattern: .verticalPull,
                                            equipment: .cable, unilateral: false, sets: 4, repMin: 8, repMax: 12,
                                            note: "Agarre ancho", aliases: [])
        XCTAssertEqual(info.name, "Jalón espalda alta")
        XCTAssertEqual(info.primary, .upperBack)
        XCTAssertEqual(info.secondary, [.lats, .biceps])
        XCTAssertTrue(info.isCustom)
        XCTAssertEqual(info.execution, ["Agarre ancho"])
        XCTAssertEqual(info.defaultSets, 4)
    }

    func testRepRangeIsFixedWhenItComesBackwards() {
        let info = CustomExerciseRules.info(id: "mio-2", name: "Raro", primary: .chest, secondary: [],
                                            pattern: .horizontalPush, equipment: .machine, unilateral: false,
                                            sets: 0, repMin: 12, repMax: 5, note: "", aliases: [])
        XCTAssertEqual(info.defaultSets, 1)
        XCTAssertEqual(info.defaultRepMin, 12)
        XCTAssertEqual(info.defaultRepMax, 12)
    }

    func testSuggestedPatternCoversEveryMuscle() {
        for group in MuscleGroup.allCases {
            XCTAssertNotNil(CustomExerciseRules.suggestedPattern(for: group))
        }
        XCTAssertEqual(CustomExerciseRules.suggestedPattern(for: .lats), .verticalPull)
        XCTAssertEqual(CustomExerciseRules.suggestedPattern(for: .calves), .calfRaise)
    }

    // MARK: Dentro del catálogo

    private func register(name: String, primary: MuscleGroup, secondary: [MuscleGroup] = [],
                          aliases: [String] = []) -> ExerciseInfo {
        let info = CustomExerciseRules.info(id: "mio-test", name: name, primary: primary, secondary: secondary,
                                            pattern: .verticalPull, equipment: .cable, unilateral: false,
                                            sets: 3, repMin: 8, repMax: 12, note: "", aliases: aliases)
        ExerciseCatalog.useCustom([info])
        return info
    }

    func testACustomExerciseIsFoundByIdAndByName() {
        _ = register(name: "Jalón enfatizando espalda alta", primary: .upperBack)
        XCTAssertEqual(ExerciseCatalog.info(id: "mio-test")?.primary, .upperBack)
        // Lo apuntado con otro identificador pero el mismo nombre también lo encuentra.
        XCTAssertEqual(ExerciseCatalog.info(id: "custom-abc", name: "jalon enfatizando espalda alta")?.primary, .upperBack)
    }

    func testAnOldNameKeepsWorkingAfterRenaming() {
        _ = register(name: "Jalón espalda alta v2", primary: .upperBack, aliases: ["Jalón espalda alta"])
        XCTAssertEqual(ExerciseCatalog.info(id: "otro", name: "Jalón espalda alta")?.name, "Jalón espalda alta v2")
    }

    func testTheLibraryNeverLosesItsOwnExercises() {
        _ = register(name: "Mi ejercicio", primary: .chest)
        XCTAssertNotNil(ExerciseCatalog.info(named: "Press de banca con barra"))
        XCTAssertEqual(ExerciseCatalog.everything.count, ExerciseCatalog.all.count + 1)
    }

    func testSearchAndAlternativesIncludeYourExercises() {
        _ = register(name: "Jalón enfatizando espalda alta", primary: .upperBack)
        XCTAssertTrue(ExerciseCatalog.search("jalon enfatizando").contains { $0.isCustom })
        XCTAssertTrue(ExerciseCatalog.byMuscle(.upperBack).contains { $0.isCustom })
    }

    // MARK: Lo que de verdad pedía el usuario: que cuente en el músculo

    func testSetsOfACustomExerciseCountForItsMuscle() {
        _ = register(name: "Jalón enfatizando espalda alta", primary: .upperBack, secondary: [.biceps])
        let work = [VolumeAnalytics.ExerciseWork(exerciseID: "custom-xyz",
                                                 name: "Jalón enfatizando espalda alta",
                                                 date: Date(), workSets: 4, volumeKg: 1200)]
        let result = VolumeAnalytics.byMuscle(work)
        XCTAssertTrue(result.unclassified.isEmpty, "El ejercicio del usuario ya no debería quedar sin clasificar")
        XCTAssertEqual(result.muscles.first { $0.group == .upperBack }?.directSets, 4)
        XCTAssertEqual(result.muscles.first { $0.group == .biceps }?.totalSets, 2)
    }

    func testWithoutCreatingItTheSetsStayUnclassified() {
        ExerciseCatalog.clearCustom()
        let work = [VolumeAnalytics.ExerciseWork(exerciseID: "custom-xyz",
                                                 name: "Jalón enfatizando espalda alta",
                                                 date: Date(), workSets: 4, volumeKg: 1200)]
        let result = VolumeAnalytics.byMuscle(work)
        XCTAssertEqual(result.unclassified.count, 1)
        XCTAssertTrue(result.muscles.isEmpty)
    }
}
