# Traspaso de trabajo: app ATLAS (iOS)

## Quién es el usuario y cómo trabajar con él
- Responde SIEMPRE en español. No es técnico; explica las cosas de forma sencilla.
- Sé honesto: nada de datos inventados y no digas que algo funciona sin haberlo comprobado.
- Ningún secreto en el código.
- Quiere un IPA instalable con Sideloadly, y solo cuando todo esté probado y verificado.

## Estado de la app (decidido por el usuario)
- La app ATLAS vuelve al estado anterior a las «mejoras expertas» (contenido del commit 722cb43).
  Están CANCELADOS: Health, widgets, planes de carrera, rediseño y funciones expertas. No los añadas.
- La rutina semanal (`Atlas/Atlas/Core/Routine.swift`) es idéntica a la de Now or Never
  (`NowOrNever/NowOrNever/Models/Routine.swift`): L carrera suave, M Push A, X Pull A,
  J Piernas y abdominales, V descanso, S carrera + pecho y espalda, D hombros y brazos.
- El usuario puede añadir ejercicios: Entrenar › sesión › Editar › «Añadir ejercicio».
  El lunes es de carrera; para meter fuerza ese día se usa «Nueva rutina» con el día Lunes.

## Proyecto
- Rama: `now-or-never-ios`. Código en `Atlas/`. El proyecto Xcode se genera con `Atlas/tools/gen_xcodeproj.py`.
- CI: `.github/workflows/atlas-build.yml` (macos-15). Compila, crea el IPA (artefacto «Atlas-ipa»),
  pasa las pruebas en simulador y sube capturas y grabaciones (artefacto «atlas-screenshots»).
- Consultar el CI con curl a través del proxy (no hay gh):
  - `https://api.github.com/repos/edulunaa06-sketch/mi-primer-proyecto/actions/workflows/atlas-build.yml/runs?per_page=1`
  - `.../actions/runs/<id>/jobs`, `.../actions/jobs/<id>/logs`
  - `.../actions/runs/<id>/artifacts`, `.../actions/artifacts/<id>/zip`
- Si falla una prueba de interfaz: en el zip de «atlas-screenshots», `tests/manifest.json` dice qué archivos
  son de cada prueba (jerarquía de la interfaz en .txt, grabación en .mp4).
- Los commits terminan con:
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01WuB6s2FpvGD1hSxzu35gDP`

## Por dónde iba
- Último commit de código: ab30352. La prueba test4 (entreno en vivo) ahora baja hasta el final antes de
  pulsar «Terminar entreno»; antes la barra del descanso tapaba el botón. En la app ya se arregló en b87a3f1
  (barra superpuesta y 170 de margen inferior).
- En el CI anterior pasaban las 20 pruebas lógicas y las pruebas de interfaz 1, 2, 3, 5 y 6. Solo fallaba test4.
- El CI de ab30352 es el run 40125238490 (estaba en curso).

## Qué hacer ahora
1. Mira el resultado del último run de atlas-build.yml (el de ab30352 o uno posterior).
2. Si está en VERDE:
   - Descarga el artefacto «Atlas-ipa» y comprueba que dentro hay `Payload/Atlas.app` con el ejecutable
     y el Info.plist.
   - Cópialo a `Atlas/dist/Atlas.ipa`, añádelo con `git add -f` y haz commit con `[skip ci]` en el mensaje.
     Haz push.
   - Entrégaselo al usuario (SendUserFile) y explícale en español cómo instalarlo con Sideloadly
     (Apple ID gratis; hay que reinstalar cada 7 días; activar el Modo desarrollador y confiar en el perfil
     en Ajustes › General › VPN y gestión de dispositivos).
   - Recuérdale que Strava se conecta en Perfil › Strava, con la guía paso a paso que trae la app.
3. Si está en ROJO: diagnostica con el log y los artefactos, arréglalo, prueba, haz push y repite hasta
   que esté en verde. Solo entonces entrega el IPA.
