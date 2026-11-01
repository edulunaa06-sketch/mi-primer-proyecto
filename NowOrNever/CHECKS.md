# Resultado de las comprobaciones

## Compilación real con Xcode
La app se compila y se prueba en un Mac real mediante GitHub Actions (`.github/workflows/ios-build.yml`, runner `macos-15`, **Xcode 16.4**), en cada push que toca `NowOrNever/`:

| Paso | Resultado (última ejecución) |
|---|---|
| `xcodebuild build` para iPhone físico (`generic/platform=iOS`, sin firma) | ✅ **BUILD SUCCEEDED** |
| Pruebas unitarias y de persistencia (simulador iPhone 16 Pro, iOS 18.5) | ✅ **67 pruebas, 0 fallos** |
| Pruebas de interfaz (XCUITest: la app se usa tocando la pantalla) | ✅ **4 pruebas, 0 fallos** |
| Instalación, arranque y capturas de todas las pestañas, el perfil, el editor de rutina y dos sesiones | ✅ |

Las capturas (`screenshots`) y el log de pruebas (`test-log`) se guardan como artefactos de cada ejecución en la pestaña **Actions** del repositorio.

### Qué hacen las pruebas de interfaz (con la app real en el simulador)
1. **Perfil → objetivos**: escribe 85,1 kg, 180 cm, 30 años y Hombre; comprueba la vista previa (2550 kcal), guarda y verifica el mensaje «Objetivos: 2550 kcal · P 170 g…». Después comprueba que el pesaje aparece en Progreso (85,1 kg) y que Inicio muestra «/ 2550 kcal».
2. **Rutina editable + registro**: abre Push A, pulsa *Editar*, añade «Fondos en paralelas», comprueba que aparece en la sesión, registra 60 kg × 8 en la primera serie, la marca, marca el ejercicio («1 de 7 ejercicios») y abre *Ver progresión de cargas*, donde aparece «60 kg × 8».
3. **Comidas**: marca una comida en Nutrición y verifica «1 de 4 comidas completadas».
4. **Elegir comidas paso a paso**: abre el asistente y, en cada paso (desayuno, comida, merienda y cena), comprueba que hay al menos 4 opciones y elige una. Guarda el día, pulsa *Cambiar comida*, elige otra alternativa y comprueba que aparece *Volver al menú*.

Fallos encontrados por estas pruebas y cómo se resolvieron:
- El teclado numérico tapaba los botones del Perfil. Se añadió un botón **Listo** para cerrarlo (también útil en uso real).
- Al añadir el asistente, la prueba de comidas pulsaba un botón que quedaba detrás de la barra de pestañas, o pulsaba mientras la pantalla aún se desplazaba. Era un problema de la prueba, no de la app; se corrigió la prueba.
- En una ejecución el simulador de GitHub no pudo arrancar la app («Timed out while acquiring background assertion»). Era un fallo de la infraestructura; en las siguientes ejecuciones no se repitió.

### Limitaciones de esta verificación
- En CI la app se compila **sin firma** (`CODE_SIGNING_ALLOWED=NO`), así que no lleva el entitlement de HealthKit y Salud responde «Missing com.apple.developer.healthkit entitlement». Es lo esperado: al instalarla desde Xcode con tu equipo de firma el entitlement sí se aplica. **No se ha probado en un iPhone físico ni con pasos reales de Salud.**
- **Strava**: no se ha probado el flujo OAuth con una cuenta real (requiere tus credenciales y un backend). Sí están probados la URL de autorización, la validación del callback, los errores y la lectura de actividades.
- **Notificaciones**: no se han disparado en CI (el permiso es interactivo). Sí está probada la planificación del aviso mensual (día 22 a las 20:00) y, con días 29–31, el ajuste al último día del mes.
- **Fotos**: el selector de fotos no se ha automatizado en CI.

## Pruebas unitarias y de persistencia (57)
- **Rutina predeterminada** (10): ejercicios, orden, series y rangos exactos; sábado con 2 sesiones separadas; viernes sin fuerza.
- **Fechas** (2): semanas de lunes a domingo; lectura de decimales con coma.
- **Nutrición** (9): 180 g de pollo → 216 kcal, 80 g de arroz en seco → 288 kcal, 5 g de aceite → 44,2 kcal; los totales salen de sumar los ingredientes; 9 menús × 4 comidas; criterios de pesaje.
- **Perfil / Mifflin‑St Jeor** (6): hombre y mujer (basal exacto), orden de objetivos (perder < recomposición < ganar), macros que suman las kcal, perfiles no válidos y ajuste de gramos a cantidades pesables.
- **Edición de rutina, lógica** (5): rangos de repeticiones, identidad de sesión, nombres para registros antiguos y resumen de progresión (mejor serie, volumen, 1RM estimado).
- **Planificador de comidas** (8): reparto del objetivo entre comidas, objetivo de la comida siguiente según la anterior, la cena recibe lo que falta, nunca objetivos negativos, ración ajustada al objetivo, orden por encaje de macros, máximo 4 opciones y gramos pesables.
- **Persistencia SwiftData en memoria** (13):
  - La rutina personalizada parte de la predeterminada y no se duplica.
  - Añadir, sustituir, reordenar, cambiar series/reps, eliminar y restaurar.
  - Las semanas nuevas empiezan vacías y la sesión anterior sigue disponible.
  - El historial conserva el nombre de un ejercicio sustituido.
  - Las series se amplían al subir la prescripción.
  - Los objetivos automáticos se recalculan con cada peso nuevo; los manuales no se tocan; con un perfil incompleto no se calcula nada.
  - No se duplica un pesaje idéntico.
  - Los 9 menús se ajustan a 2600 kcal (±4 %).
  - Al editar gramos cambian los totales de la comida y del día.
  - Una comida solo se marca una vez al día.
  - Elegir una comida sustituye a la del menú y su registro guarda la ración elegida. *Volver al menú* deshace la elección.
  - Elegir las 4 comidas en secuencia deja el día dentro del ±8 % de las kcal objetivo y con un encaje de macros superior al 85 %.
- **Cumplimiento y peso** (4), **Strava** (7), **ritmo** (1) y **recordatorio de fotos** (2).

La lógica pura (54 de estas pruebas) también se compila y se ejecuta en Linux con Swift 6.1.2.

## Errores de compilación pendientes
Ninguno en Xcode 16.4.
