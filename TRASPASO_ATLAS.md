# Traspaso de trabajo: app ATLAS (iOS)

## Quién es el usuario y cómo trabajar con él
- Responde SIEMPRE en español. No es técnico; explica las cosas de forma sencilla.
- Sé honesto: nada de datos inventados y no digas que algo funciona sin haberlo comprobado.
- Ningún secreto en el código.
- Quiere un IPA instalable con Sideloadly, y solo cuando todo esté probado y verificado.

## Estado de la app
- Rama de trabajo: `claude/modest-curie-l89w4f`, con la PR #1 abierta hacia `main`.
  La rama anterior `now-or-never-ios` está incluida entera en esta (avance sin merge).
- Código en `Atlas/`. El proyecto Xcode se genera con `Atlas/tools/gen_xcodeproj.py` y usa
  grupos sincronizados: **un .swift nuevo entra solo**, no hay que regenerar nada.
- Documentación: `Atlas/ARQUITECTURA.md` y `Atlas/INSTALAR_EN_IPHONE.md`.

### Cambio de rumbo importante (25/10/2026)
El usuario pidió por escrito una app de entrenamiento de élite con **registro de kilos,
repeticiones, RIR, RPE, 1RM estimado, volumen por grupo muscular y progresión**. Eso
**revierte a propósito** la decisión anterior de «entreno sin kilos» que figuraba en este
mismo documento. Si vuelve a cambiar de opinión, que lo diga él: no se deshace por iniciativa propia.

Lo que hay ahora, además de lo que ya existía (nutrición, menús, peso, fotos, pasos,
calendario, medallas, copia de seguridad, Strava, IA opcional):
- Sesión de fuerza en vivo: series con kilos, repeticiones y RIR, calentamientos, cronómetro
  con pausa que sobrevive a cerrar la app, comparación con la sesión anterior, récords al
  terminar, nota y molestia por ejercicio.
- Biblioteca de 57 ejercicios con músculos, patrón, material, ejecución, errores, seguridad
  y variantes, con un comparador que explica qué cambia al sustituir uno por otro.
- Volumen por grupo muscular con referencia, frecuencia, programado frente a realizado,
  estancamiento y descarga.
- Recuperación (sueño, energía, fatiga, estrés, agujetas, molestias) e informes por periodo
  con comparación con el anterior.
- Suplementos con dosis, coste al mes, evidencia, duplicados y avisos.

## Pruebas
- 235 pruebas de lógica se ejecutan **en Linux** con el toolchain de Swift. Es la forma rápida
  de trabajar: copia a un paquete SwiftPM los archivos que solo importan Foundation y los corre.
  El script de sincronización está en el directorio temporal de la sesión; se rehace en dos minutos
  (ver «Pruebas» en ARQUITECTURA.md).
- Persistencia e interfaz, en el simulador desde el CI.

## CI
- `.github/workflows/atlas-build.yml` (macos-15): compila para dispositivo, genera el IPA
  (artefacto `Atlas-ipa`), pasa las pruebas en simulador y sube capturas (`atlas-screenshots`).
- Si falla, el artefacto `atlas-test-log` trae `build-device.log` con los errores de compilación.
- Al terminar en verde: copiar el IPA a `Atlas/dist/Atlas.ipa` con `git add -f` y `[skip ci]`
  en el mensaje, entregarlo con SendUserFile y explicar la instalación.

## Por dónde va (25/10/2026, sesión de Opus 5)

- 15 commits nuevos sobre `819e83f`: +10.478 líneas en `Atlas/`, 25 archivos Swift nuevos.
  El código de ATLAS pasa de 15.040 a 25.172 líneas.
- Lo construido está en `Atlas/ESTADO.md`, módulo por módulo y diciendo lo que NO está.
- El CI ya compila todo y genera el IPA. El run 19 (`9fceee7`) es el definitivo: valida los
  tres fallos corregidos del run 15, la prueba nueva de pantallas, los plurales y el
  rendimiento al abrir una sesión.
- Fallos que encontró el CI y están corregidos: `Section(título) { } footer:` no existe en
  SwiftUI; autocompletar peleaba con la casilla manual del ejercicio; renumerar series contaba
  la recién borrada; y dos pruebas mías comparaban structs enteros después de pasar por JSON
  (las fechas van en milisegundos).
- Pendiente al terminar en verde: copiar el IPA a `Atlas/dist/Atlas.ipa` con `git add -f` y
  `[skip ci]`, entregarlo con SendUserFile y recordar que hay que refirmarlo.

## Lo que NO se puede hacer desde aquí
El contenedor es Linux: no hay Xcode. La compilación y el IPA salen del runner macOS del CI.
**La firma para el iPhone del usuario no se puede hacer en ningún servidor**: necesita su Apple ID.
No se inventan certificados ni perfiles.
