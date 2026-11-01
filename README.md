# mi-primer-proyecto

En este repositorio conviven tres cosas. Cada una está en su carpeta y no se pisan entre ellas.

## `Atlas/` — Now or Never, la app de iOS (lo que está en desarrollo)

> La carpeta, el proyecto de Xcode y el identificador siguen llamándose `Atlas`: cambiarlos
> haría que el iPhone tratara la app como otra distinta y se perderían los datos ya guardados.

App nativa de entrenamiento, nutrición y progreso. Swift + SwiftUI + SwiftData, sin servidor,
sin cuenta y sin suscripción: los datos viven en el iPhone.

Qué hace:

- **Entrenar.** Rutina editable, sesión en vivo con kilos, repeticiones y RIR por serie,
  cronómetro que sobrevive a cerrar la app, comparación con la sesión anterior, récords,
  1RM estimado y una progresión que explica por qué propone subir, mantener o bajar.
- **Volumen.** Series por grupo muscular (directas e indirectas), frecuencia, programado frente
  a realizado, estancamientos y descarga.
- **Biblioteca.** 57 ejercicios con músculos, patrón, material, ejecución, errores frecuentes,
  seguridad y variantes, con un comparador que explica qué cambia al sustituir uno por otro.
- **Comer.** Objetivos de kcal y macros (Mifflin-St Jeor), catálogo de alimentos, menús e ideas,
  recetas propias con raciones y peso final cocinado, planificador del día y foto del plato con IA.
- **Progreso.** Peso con medias semanales y mensuales, cintura, fotos, pasos, calendario,
  medallas, resumen semanal e informes por periodo con comparación.
- **Recuperación.** Sueño, energía, fatiga, estrés, agujetas y molestias, con avisos prudentes.
- **Suplementos.** Dosis, horarios, coste al mes y qué dice la evidencia de cada uno, incluida
  la que no la tiene.
- **IA opcional.** Con tu clave puedes preguntarle por tus propios datos; se te enseña antes
  exactamente qué se envía. Sin clave, todo lo demás funciona igual.

Documentación: [`Atlas/ARQUITECTURA.md`](Atlas/ARQUITECTURA.md) y, para ponerla en el móvil,
[`Atlas/INSTALAR_EN_IPHONE.md`](Atlas/INSTALAR_EN_IPHONE.md).

El IPA lo compila el CI en un runner macOS (`.github/workflows/atlas-build.yml`) y queda en el
artefacto `Atlas-ipa`, con una copia en `Atlas/dist/Atlas.ipa`. Va firmado **ad hoc**: sirve para
comprobar que el paquete está bien montado, pero **para instalarlo en tu iPhone hay que volver a
firmarlo con tu Apple ID**. Está explicado paso a paso en el documento de instalación.

## `NowOrNever/` — la versión anterior de la app

La app de la que salió Now or Never. Se conserva entera y con su propio CI por si hace falta volver a
mirar algo. No es donde se trabaja.

## Raíz (`index.html`, `app.html`, `sw.js`…) — Kcalia, la web instalable

Contador de calorías que funciona en el navegador y se puede añadir a la pantalla de inicio:

- Calorías de mantenimiento y objetivo según sexo, edad, peso, altura, complexión y actividad.
- Estimación de las calorías de un plato a partir de una foto.
- Anillos diarios de calorías, proteína y creatina, con progreso semanal.
- Dosis de creatina y recordatorio diario.

`app.html` es el código fuente; `index.html` se genera con `./build.sh` y no se edita a mano.

Para usarla: Settings → Pages → `main` / root, y abrir
`https://edulunaa06-sketch.github.io/mi-primer-proyecto/` en el móvil (iPhone: Safari →
Compartir → «Añadir a pantalla de inicio»). La IA se activa en Perfil con una clave de
[Google AI Studio](https://aistudio.google.com/apikey), que se guarda solo en el móvil.
