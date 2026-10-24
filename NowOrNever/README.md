# Now or Never

App de gimnasio para iPhone, en negro y amarillo. SwiftUI + SwiftData, iOS 17 mínimo,
sin librerías externas y sin servidor: todo se guarda en el móvil.

## Pestañas

- **Inicio**: calorías que quedan hoy en un anillo amarillo, barras de macros en tiempo real,
  entreno que toca hoy, siguiente comida pendiente y último peso.
- **Nutrición**: menú del día (desayuno, almuerzo, merienda y cena) con los gramos de cada
  ingrediente, check por comida, botón «Cambiar» y «Añadir manual».
- **Entreno**: la rutina semanal cargada de fábrica, con registro de series, aviso de
  «Sube peso», temporizador de descanso y kilómetros los días de correr.
- **Progreso**: registro de peso con gráfica de línea (Swift Charts).
- **Perfil**: datos físicos, cálculo Mifflin-St Jeor e interruptor de ajuste manual.

## Estructura

```
NowOrNever/
├── project.yml                  # proyecto de Xcode, generado con XcodeGen
├── Support/Info.plist
└── NowOrNever/
    ├── App/                     # punto de entrada y apariencia global
    ├── Models/                  # modelos de SwiftData
    ├── Views/                   # pantallas y componentes
    ├── ViewModels/              # planificador de menús, servicios y temporizador
    ├── Data/                    # base de comidas, rutina y datos de ejemplo
    ├── Utilities/               # Theme.swift, fechas y formatos
    └── Resources/Assets.xcassets
```

## Conseguir el .ipa

No hace falta Mac. Cada vez que se sube algo a `NowOrNever/`, GitHub Actions compila la app
en un runner de macOS y deja el `.ipa` listo:

1. Pestaña **Actions** del repositorio → workflow **Compilar Now or Never (.ipa)**.
2. Abre la última ejecución (o lánzala a mano con **Run workflow**).
3. Descarga el artifact **NowOrNever-ipa** y descomprímelo: dentro está `NowOrNever.ipa`.
4. Fírmalo e instálalo en el iPhone con Sideloadly.

La app se compila **sin firmar** (`CODE_SIGNING_ALLOWED=NO`), que es justo lo que espera Sideloadly.

## Abrirlo en Xcode (si algún día tienes Mac)

```bash
brew install xcodegen
cd NowOrNever
xcodegen generate
open NowOrNever.xcodeproj
```

El `.xcodeproj` no se guarda en git: se genera siempre desde `project.yml`.
