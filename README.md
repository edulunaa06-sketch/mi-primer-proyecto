# Kcalia

Contador de calorías con estilo iOS:

- Calcula tus calorías de mantenimiento y tu objetivo de déficit según sexo, edad, peso, altura, complexión y actividad (Mifflin-St Jeor).
- Estima las calorías de un plato a partir de una foto con IA (Claude) y las va sumando.
- Anillos diarios de calorías, proteína y creatina; progreso semanal y déficit acumulado.
- Calcula tu dosis de creatina (mantenimiento o fase de carga), lleva tu racha y crea una alarma diaria en el calendario.

## Archivos

- `app.html`: código fuente de la app (también se publica como artifact en Claude).
- `index.html`: versión instalable generada con `./build.sh`. No la edites a mano.
- `manifest.webmanifest`, `sw.js`, `icons/`: lo necesario para instalarla en el móvil.

## Instalar en el móvil

1. Publica el repositorio con GitHub Pages (Settings → Pages → Deploy from a branch → `main` / root).
2. Abre `https://edulunaa06-sketch.github.io/mi-primer-proyecto/` en el móvil.
3. iPhone: Safari → Compartir → «Añadir a pantalla de inicio». Android: Chrome → ⋮ → «Instalar aplicación».
4. En Perfil, pega tu clave de la API de Anthropic para analizar fotos (se guarda solo en el móvil).
