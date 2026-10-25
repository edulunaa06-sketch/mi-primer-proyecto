# ATLAS · Arquitectura

App iOS nativa en Swift y SwiftUI, con SwiftData para guardar los datos en el propio iPhone.
Sin servidor, sin cuenta y sin suscripción: todo funciona en el dispositivo.

- **Plataforma:** iOS 17 o superior (`IPHONEOS_DEPLOYMENT_TARGET = 17.0`).
- **Lenguaje:** Swift 5 (`SWIFT_VERSION = 5.0`), SwiftUI + SwiftData + Charts.
- **Proyecto Xcode:** se genera con `tools/gen_xcodeproj.py`. Usa grupos sincronizados con el
  sistema de archivos (`PBXFileSystemSynchronizedRootGroup`, `objectVersion = 77`), así que
  **un archivo `.swift` nuevo dentro de `Atlas/` o `AtlasTests/` entra solo**, sin tocar el proyecto.
- **Dependencias externas:** ninguna. No hay CocoaPods, Carthage ni paquetes de Swift.

## Cómo está separado

```
Atlas/
├─ Atlas/
│  ├─ App/              Punto de entrada, navegación raíz y traducción de la paleta
│  ├─ DesignSystem/     Lenguaje visual (DS), logotipo y componentes de marca
│  ├─ Models/           LÓGICA PURA: solo Foundation, sin interfaz ni base de datos
│  ├─ Data/             SwiftData: consultas y operaciones sobre el almacén
│  ├─ Services/         Lo que habla con el exterior (IA, Strava, avisos, fotos, pasos)
│  ├─ Views/            Pantallas, por módulo
│  └─ Resources/        Catálogo de alimentos y menús de ejemplo (JSON)
├─ AtlasTests/          Pruebas (lógica + persistencia en SwiftData)
├─ AtlasUITests/        Recorridos de usuario en el simulador
├─ Config/              Info.plist, entitlements y configuración de firma
└─ tools/               Generador del proyecto Xcode
```

La regla que sostiene todo lo demás: **en `Models/` no se importa SwiftUI ni SwiftData.**
Son funciones puras sobre valores. Eso tiene dos consecuencias prácticas:

1. Se pueden probar sin simulador. De hecho se compilan y ejecutan en Linux con el toolchain
   de Swift (ver «Pruebas»), lo que da una vuelta de corrección en segundos en lugar de minutos.
2. Las pantallas no calculan nada. Reciben números ya calculados y los pintan.

## Módulos

### Entrenamiento de fuerza

| Archivo | Qué resuelve |
|---|---|
| `Models/Strength.swift` | `LoggedSet` (peso, reps, RIR, RPE, descanso, tipo de serie), `OneRepMax` (Epley, Brzycki, Lombardi), `ExerciseSessionSummary`, `StrengthTrend`, `PersonalRecords`, `PlateMath`, `SessionClock` |
| `Models/MuscleGroup.swift` | 18 grupos musculares, 22 patrones de movimiento, 10 materiales y `VolumeReference` |
| `Models/ExerciseCatalog.swift` | 57 fichas de ejercicio: músculos, patrón, material, ejecución, errores, seguridad, variantes y `difference` |
| `Models/VolumeAnalytics.swift` | Series directas e indirectas, tonelaje, frecuencia, programado frente a realizado y avisos |
| `Models/ProgressionEngine.swift` | Progresión doble con RIR, estancamiento, descarga y series planificadas |
| `Models/TrainingModels.swift` | SwiftData: `SetLog`, `PersonalRecordEntry`, `RecoveryLogEntry`, `SupplementEntry`, `SupplementIntake`, `TrainingWeek` |
| `Data/StrengthStore.swift` | Puente entre la base de datos y los cálculos: series de la sesión, historial, récords, descarga, informes |

### Nutrición

`Models/NutritionMath.swift`, `EnergyCalculator.swift` (Mifflin-St Jeor), `MealPlanner.swift`,
`FoodSearch.swift`, `Data/SeedCatalog.swift` y las pantallas de `Views/Nutrition/`.
Los totales **siempre** se suman desde los ingredientes; nunca se guarda un total escrito a mano.

### Cuerpo, recuperación y suplementos

`Models/Compliance.swift` (`WeightStats`), `Tracking.swift` (medias, resúmenes, medallas),
`Recovery.swift` (sueño, fatiga, estrés, prudencia) y `Supplements.swift` (evidencia, duplicados,
coste). Pantallas en `Views/Progress/` y `Views/Settings/`.

### Informes

`Models/Reports.swift` construye un `PeriodReport` a partir de un `ReportInput` ya filtrado.
Cada sección sabe si tiene datos suficientes (`hasEnoughData`) y el informe devuelve dos listas:
`highlights` (lo que ha pasado) y `caveats` (qué falta para que sea fiable).

### Inteligencia artificial

`Services/ClaudeService.swift` y `Models/ClaudeAPI.swift`. La clave se guarda en el Llavero
(`Services/KeychainStore.swift`), **nunca en el código**. Sin clave, la app funciona entera: la IA
es un extra, no un requisito. No se simulan respuestas de IA: si no hay clave, se dice.

## Datos

SwiftData con un único almacén local (`ModelConfiguration("Atlas", cloudKitDatabase: .none)`).
El esquema está declarado en `App/AtlasApp.swift` y es la lista que usan también las pruebas.

Entidades principales y su relación con el modelo que pedía el encargo:

| Encargo | En ATLAS |
|---|---|
| User / UserProfile / UserGoal | `UserSettings` (perfil, objetivos, avisos) |
| WorkoutRoutine / RoutineDay | `WeeklyRoutine` (plantilla) + `RoutineExercise` + `SessionTitle` |
| Exercise / ExerciseVariant | `ExerciseCatalog` (biblioteca) |
| WorkoutSession / WorkoutExercise / ExerciseSet | `WorkoutSessionLog` → `ExerciseLog` → `SetLog` |
| PersonalRecord | `PersonalRecordEntry` |
| Food / Meal / MealItem / Recipe | `FoodItem`, `MealRecord`, `CustomMealItem`, `MenuPlan` → `MealTemplate` → `MealItem` |
| NutritionTarget / DailyNutritionLog | `UserSettings` + `MealRecord` por día |
| BodyMeasurement / ProgressPhoto | `WeightEntry` (peso y cintura), `ProgressPhoto` |
| RecoveryLog / ActivityLog | `RecoveryLogEntry`, `DailySteps`, `WaterLog`, `StravaActivityRecord` |
| Supplement | `SupplementEntry` + `SupplementIntake` |
| Achievement / UserAchievement | `Medals` (calculadas) + marcas vistas en `UserDefaults` |

### Reglas de integridad

- Claves únicas donde el duplicado sería un error: `WorkoutSessionLog.key` (semana + sesión),
  `RecoveryLogEntry.dayKey`, `ProgressPhoto.key` (mes + vista), `DailySteps.dayKey`,
  `PersonalRecordEntry.key` (ejercicio + tipo), `SupplementIntake.key` (día + suplemento).
- Borrado en cascada de arriba abajo: sesión → ejercicios → series; menú → comidas → ingredientes.
- `MealItem.food` se anula en lugar de borrarse, para no perder una comida al borrar un alimento.
- **Toda propiedad nueva lleva valor por defecto.** Es lo que permite añadir campos sin romper
  la base de datos de un iPhone que ya tiene la app instalada.
- El historial no se reescribe: `ExerciseLog` guarda una copia del nombre y la prescripción de
  esa semana, así que editar la rutina hoy no cambia lo que pone en el historial de hace un mes.

### Copia de seguridad

`Models/BackupModels.swift` (formato) y `Data/BackupService.swift` (exportar e importar).
Un JSON con todo, fotos incluidas en base64. **Formato actual: 2.** Los campos añadidos en el 2
son opcionales, así que una copia del formato 1 se sigue importando; una copia del 2 en una app
vieja se rechaza con un mensaje claro en vez de importarse a medias.

No incluye la clave de la IA ni los tokens de Strava: viven en el Llavero y no salen de ahí.

## Pruebas

Tres niveles, y los tres se ejecutan de verdad:

1. **Lógica (235 pruebas).** Solo Foundation. Se ejecutan en el simulador con el resto, y además
   en Linux con el toolchain de Swift, que es lo que se usa durante el desarrollo:

   ```sh
   # Copia a un paquete SwiftPM los archivos que solo dependen de Foundation y los ejecuta.
   swift test
   ```

2. **Persistencia (SwiftData en memoria).** `PersistenceTests`, `BackupPersistenceTests` y
   `StrengthPersistenceTests`. Comprueban que lo guardado se vuelve a leer igual, que el historial
   no se pisa y que la copia de seguridad va y vuelve sin perder nada.

3. **Interfaz (`AtlasUITests`).** Recorridos completos en el simulador: perfil → objetivos,
   editar la rutina y apuntar una serie, marcar comidas, elegir el día paso a paso.

## Integración continua y el IPA

`.github/workflows/atlas-build.yml`, en un runner `macos-15`:

1. Compila para dispositivo sin firma (`CODE_SIGNING_ALLOWED=NO`).
2. Compila en Release, firma **ad hoc** (`codesign --sign -`) y empaqueta `Payload/Atlas.app`
   en `Atlas.ipa`, que se sube como artefacto `Atlas-ipa`.
3. Ejecuta las pruebas en el simulador y exige `TEST SUCCEEDED`.
4. Hace capturas de cada pantalla y las sube como `atlas-screenshots`.

La firma ad hoc sirve para comprobar que el paquete está bien formado, **pero no permite instalar
en un iPhone**. Para eso hay que volver a firmar con un Apple ID: ver `INSTALAR_EN_IPHONE.md`.

## Seguridad y privacidad

- Los datos no salen del iPhone salvo que el usuario exporte una copia a propósito.
- Secretos en el Llavero, nunca en el código ni en la copia de seguridad.
- El `client_secret` de Strava no va en la app: por eso la configuración pide un backend propio.
- Las fotos de progreso se guardan con `.completeFileProtection` en el contenedor de la app.
- Entradas validadas antes de guardar (pesos y gramos no negativos, rangos de repeticiones que
  no se pueden invertir, escalas de 1 a 5 que descartan lo que esté fuera).
- La app no diagnostica. Donde aparece una molestia, un síntoma o un suplemento con riesgos,
  remite a un profesional sanitario y lo dice por escrito.
