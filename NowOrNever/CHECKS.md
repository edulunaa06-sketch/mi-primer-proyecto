# Resultado de las comprobaciones

## Compilación real con Xcode
La app se compila en un Mac real mediante GitHub Actions (`.github/workflows/ios-build.yml`, runner `macos-15`, **Xcode 16.4**), en cada push que toca `NowOrNever/`:

| Paso | Resultado |
|---|---|
| `xcodebuild build` para iPhone físico (`generic/platform=iOS`, sin firma) | ✅ **BUILD SUCCEEDED** — 0 errores, 0 avisos del compilador Swift |
| `xcodebuild test` en simulador iPhone 16 Pro (iOS 18.5) | ✅ **TEST SUCCEEDED** — 35 pruebas, 0 fallos |
| Instalación y arranque en el simulador + capturas de cada pestaña y de dos sesiones | ✅ La app arranca y todas las pantallas se muestran |

Las capturas se guardan como artefacto `screenshots` de cada ejecución en la pestaña **Actions** del repositorio.

Limitaciones de esta verificación (honestas):
- En CI la app se compila **sin firma** (`CODE_SIGNING_ALLOWED=NO`), así que el entitlement de HealthKit no se incrusta y Salud responde «Missing com.apple.developer.healthkit entitlement». Es lo esperado: al instalarla desde Xcode con tu equipo de firma el entitlement sí se aplica. **No se ha probado en un iPhone físico** ni con datos reales de Salud.
- No se ha probado el flujo OAuth completo con una cuenta de Strava real (requiere tus credenciales y backend). Sí están probados el armado de la URL, la validación del callback, los errores y la decodificación de actividades.
- Las notificaciones no se han disparado en CI (requieren permiso interactivo).

## Pruebas unitarias (35)
- **Rutina** (10): ejercicios, orden, series y rangos exactos de Push A, Pull A, Piernas, Sábado sesión 2 y Domingo; sábado con 2 sesiones separadas; viernes sin fuerza; 7 sesiones entrenables; IDs únicos.
- **Fechas** (2): semana lunes–domingo (22/10/2026 → semana del 19/10; el 26/10 empieza semana nueva), lectura de decimales con coma.
- **Nutrición** (9): ejemplos 180 g pollo → 216 kcal, 80 g arroz seco → 288 kcal, 5 g aceite → 44,2 kcal; sumas calculadas; recálculo al cambiar gramos; catálogo válido (9 menús × 4 comidas, sin referencias rotas); total de cada menú = suma de ingredientes; coherencia kcal↔macros (±15 %); criterios de peso (seco/crudo/escurrido/cocido y escurrido/peso real).
- **Cumplimiento y peso** (4): día de descanso sin componente de entrenamiento, pasos sin datos no se inventan, tope del 100 %, variación semanal/mensual.
- **Strava** (7): URL OAuth sin secretos y con Client ID numérico, callback correcto, denegado, `state` distinto, permisos insuficientes, decodificación y filtro de carreras, tokens.
- **Ritmo y duración** (1).
- **Recordatorio de fotos** (2): día 22 → un solo disparador mensual repetitivo a las 20:00; día 31 → 12 avisos con el último día de cada mes.

Además, la lógica pura se compiló y probó también en Linux con Swift 6.1.2 (mismas 35 pruebas en verde) y se pasó `swiftc -parse` a todos los archivos.

## Revisión manual
1. Todos los archivos Swift revisados; nombres de tipos/propiedades coherentes (confirmado por la compilación).
2. Sin símbolos indefinidos (confirmado por la compilación).
3. Modelos SwiftData ↔ vistas coherentes; relaciones con borrado en cascada solo hacia hijos.
4. Sumas nutricionales: siempre calculadas a partir de los ingredientes (`MealTemplate.totals`, `MenuPlan.totals`); no hay totales escritos a mano.
5. Datos vacíos: sin pesajes, sin pasos, sin menús, sin fotos y sin carreras muestran estados vacíos explicativos, nunca cifras inventadas.
6. Permisos denegados: Salud (instrucciones + botón a Ajustes), notificaciones (alerta con botón a Ajustes; el interruptor vuelve a «apagado» si iOS no concede permiso), fotos (no requiere permiso).
7. Strava: botón de apertura independiente de OAuth; enlace `strava://record` no documentado identificado como tal; errores OAuth mapeados a mensajes claros.
8. Estados de interfaz: modelos `@Observable`/SwiftData; consultas `@Query` reactivas.
9. Historial: los registros de entrenamiento se guardan por semana (clave semana+sesión) y nunca se borran al cambiar de semana; las comidas marcadas guardan una copia de sus valores; no hay ningún borrado automático (ni siquiera si falla la base de datos: se muestra un error).
10. Seguridad: sin secretos en el código; tokens en el Llavero; `client_secret` solo en el backend.

## Errores de compilación pendientes
Ninguno en Xcode 16.4.
