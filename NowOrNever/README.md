# Now or Never — app nativa para iPhone

App de entrenamiento, nutrición y progreso físico escrita en **Swift + SwiftUI**, con persistencia local en **SwiftData**, recordatorios con **UserNotifications** y apertura/integración de **Strava**.

- iOS **17.0** o posterior · solo iPhone · orientación vertical · tema oscuro (negro/carbón + verde lima).
- Sin dependencias externas (ningún paquete SPM ni CocoaPods).
- Todos los datos se guardan **solo en el iPhone**.

<p>
<img src="docs/screenshots/meal-builder.jpg" width="200"> <img src="docs/screenshots/profile.jpg" width="200"> <img src="docs/screenshots/routine-editor.jpg" width="200"> <img src="docs/screenshots/session-tue-push-a.jpg" width="200">
</p>

*Capturas reales del simulador (iOS 18.5) generadas por el CI después de que las pruebas de interfaz introdujeran esos datos tocando la app. Más en `docs/screenshots/`.*

---

## 1. Instalación paso a paso (para principiantes)

### Lo que necesitas
1. Un **Mac** con **Xcode 16 o posterior** (gratis en la App Store del Mac). El proyecto usa el formato de Xcode 16; Xcode 15 no lo abre.
2. Tu **iPhone** con iOS 17 o posterior y un cable (o la misma red Wi‑Fi tras el primer emparejamiento).
3. Un **Apple ID**. Basta con la cuenta gratuita; con ella la app caduca a los **7 días** y hay que volver a instalarla desde Xcode. Con el Apple Developer Program (de pago) dura 1 año.

### Pasos
1. Descarga y descomprime `NowOrNever.zip` (o clona el repositorio y entra en la carpeta `NowOrNever/`).
2. Haz doble clic en **`NowOrNever.xcodeproj`**.
3. **Cambia el identificador de la app** (obligatorio, tiene que ser único):
   - En el navegador de archivos de Xcode abre `Config/Signing.xcconfig`.
   - Cambia `BUNDLE_ID_PREFIX = com.example` por algo tuyo, p. ej. `BUNDLE_ID_PREFIX = com.tunombre`.
   - El identificador final será `com.tunombre.nowornever`.
4. **Elige tu equipo de firma**:
   - Xcode › Settings › Accounts › `+` › añade tu Apple ID (si no lo has hecho ya).
   - Selecciona el proyecto azul **NowOrNever** › target **NowOrNever** › pestaña **Signing & Capabilities**.
   - Deja marcado *Automatically manage signing* y elige tu **Team**.
   - Haz lo mismo (Team) en el target **NowOrNeverTests** si vas a ejecutar las pruebas.
5. Conecta el iPhone y, en el iPhone, activa **Ajustes › Privacidad y seguridad › Modo desarrollador** (iOS lo pide la primera vez y reinicia el teléfono).
6. Arriba en Xcode elige tu iPhone como destino y pulsa **▶︎ Run** (⌘R).
7. La primera vez el iPhone dirá que el desarrollador no es de confianza: ve a **Ajustes › General › VPN y gestión de dispositivos**, toca tu Apple ID y pulsa **Confiar**.
8. Abre la app. Verás la pantalla inicial para introducir tu peso y fecha de inicio (puedes pulsar *Usar 85,1 kg · 22 oct 2026* o escribir otros valores, o *Omitir*).

> Pruebas: en Xcode, ⌘U con un simulador de iPhone seleccionado (pruebas unitarias + pruebas de interfaz).

### Que parezca una app normal (como WhatsApp o TikTok)
Una vez instalada desde Xcode, Now or Never **ya es una app nativa**: tiene su icono en la pantalla de inicio, se abre a pantalla completa, aparece en la biblioteca de apps, en Spotlight y en Ajustes › Notificaciones. No es una web ni un acceso directo. La única diferencia con una app de la App Store es **cómo se instala y cuánto dura la firma**:

| Opción | Coste | Duración de la instalación | Qué necesitas |
|---|---|---|---|
| **Xcode + Apple ID gratuito** | 0 € | **7 días**; luego la app no abre hasta reinstalarla desde Xcode (tus datos se conservan si no la borras) | Mac + cable |
| **Apple Developer Program** + instalación desde Xcode | 99 €/año | **1 año** | Mac |
| **Apple Developer Program + TestFlight** (recomendada) | 99 €/año | Cada compilación dura **90 días** y se actualiza desde la app TestFlight, como una app de la tienda | Mac para subirla una vez (Product › Archive › Distribute App › TestFlight) |
| Publicarla en la App Store | 99 €/año | Indefinida | Revisión de Apple |

Pasos con Xcode (resumen; detalle arriba): Mac con Xcode → abrir `NowOrNever.xcodeproj` → cambiar `BUNDLE_ID_PREFIX` → elegir tu Team → conectar el iPhone → activar Modo desarrollador → ▶︎ Run → en el iPhone, *Ajustes › General › VPN y gestión de dispositivos › Confiar*.

Con la cuenta gratuita, para renovarla cada semana basta con conectar el iPhone y volver a pulsar ▶︎ Run (no se pierden los datos). Sin Mac no se puede compilar una app nativa de iOS; existen servicios de Mac en la nube, pero la instalación seguiría necesitando una de las opciones de la tabla.

---

## 2. Funciones implementadas

### Al abrir la app
- **Pantalla de carga** «NOW OR NEVER» sobre negro: entra de golpe (con vibración y una sacudida), aguanta un momento y sale disparada hacia ti con un destello verde. Después aparece la **frase motivadora** (gimnasio y desarrollo personal; 40 frases, nunca la misma dos veces seguidas), que se cierra sola a los 4 s o al tocarla. Tocar durante el logo pasa directamente a la frase. Sin música.
- Si vuelves a la app tras 10 minutos o más fuera sale solo la frase, sin el logo.

### Inicio
- **Calorías de hoy** arriba del todo, sin anillos: «Te quedan X kcal» (objetivo − lo comido) y lo que te queda de proteínas, carbohidratos y grasas. Baja a medida que registras comidas; si te pasas, lo indica en naranja. El botón de debajo abre *Nutrición*.
- Peso más reciente y diferencia respecto al primer peso registrado.
- Entrenamiento(s) programado(s) para hoy con su estado.
- Comidas completadas (x/4).
- **Cumplimiento diario**: media de los componentes disponibles → comidas (x/4), sesiones del día completadas (se omite el viernes de descanso) y pasos (si hay datos). El desglose se muestra en pantalla.
- **Pasos de hoy** con el sensor de movimiento del iPhone (no usa Apple Salud), en vivo mientras la app está abierta: total, lo que falta para tu objetivo, km y kcal aproximados. La primera vez iOS pide el permiso de *Movimiento y forma física*. Cuentan en el cumplimiento diario. La app guarda los pasos de cada día (el iPhone solo guarda 7 días) para el historial.
- **Objetivo de pasos adaptativo y ajustable** (botón «cambiar» en la tarjeta de pasos o Ajustes › Pasos): en automático, cada día se pone en la media de los 7 días anteriores + 5 % (redondeado a 250, entre 3.000 y 20.000; necesita al menos 3 días con datos). Si cambias el número a mano pasa a manual; puedes volver a activar el automático cuando quieras.
- **Racha** de días cumplidos y la marca de hoy (descanso, enfermo…). Tocarla abre el Calendario.

### Calendario (pestaña propia)
- Vista mensual tipo **mapa de calor**: cada día coloreado según lo cumplido (verde más intenso cuanto más cumplido, rojo si no se cumplió). Un día está **cumplido** con el 70 % o más del cumplimiento diario (comidas, entreno del día y pasos).
- **Racha actual** y **mejor racha**. Los días antes de empezar a usar la app no cuentan.
- Al tocar un día: detalle (comidas, entreno, pasos, %) y marca:
  - **Descanso**: no cuenta como fallo ni rompe la racha. **Los viernes son descanso por defecto**; se puede cambiar a «Normal» o «Entrenado».
  - **Entrenado**: entrenaste aunque no tocara (p. ej. adelantar al viernes la carrera o el push/espalda del sábado). Cuenta como día cumplido.
  - **Malo / enfermo**: no rompe la racha; con «Hasta» se marcan varios días seguidos.
  - **Trabajando**: no cuenta como fallo ni rompe la racha.

### Perfil personal y objetivos automáticos (Ajustes › Perfil personal)
- Peso, altura, edad, sexo, nivel de actividad (5 niveles) y objetivo: **perder grasa, ganar músculo o recomposición**.
- El peso del perfil es tu **último pesaje**; si lo cambias, se guarda como pesaje nuevo de hoy (queda en el historial).
- Cálculo con **Mifflin‑St Jeor**: basal = 10×peso + 6,25×altura − 5×edad + 5 (hombre) / −161 (mujer); gasto = basal × factor de actividad (1,2 / 1,375 / 1,55 / 1,725 / 1,9).
- Calorías objetivo: −20 % (perder grasa), +10 % (ganar músculo), −10 % (recomposición), redondeadas a 10 kcal.
- Macros: proteína = 35 % (perder grasa), 30 % (recomposición) o 25 % (ganar músculo) de las kcal, dentro de 1,6–2,4 g/kg de peso; grasa 25 % de las kcal (mín. 0,6 g/kg); carbohidratos, el resto. Así los tres macros cambian cuando cambian las kcal.
- Con **Objetivos automáticos** activado, kcal y macros se recalculan al guardar el perfil y **cada vez que registras un peso nuevo**. Si editas los objetivos a mano en Ajustes, pasan a ser manuales y ya no se sobrescriben.
- Es una estimación orientativa, no una pauta médica.

### Entrenamientos
- Rutina semanal **exacta** de la especificación (`Models/Routine.swift`), con identificadores estables. Las pruebas `RoutineTests` comprueban ejercicios, orden, series y rangos.
- **Rutina predeterminada o desde cero**: al empezar (y en *Entrenos › Opciones de la rutina*) puedes vaciar las sesiones de fuerza para montar tu propia rutina, o volver a la predeterminada. El historial se conserva.
- **Cambiar el nombre de cualquier sesión** (lápiz arriba a la derecha dentro de la sesión, o mantener pulsada en la lista). El historial se conserva y *Nombre original* lo deshace.
- **Sábado con dos sesiones separadas** (Carrera y Pecho y espalda), cada una con su propio estado.
- Viernes: descanso con indicaciones de recuperación, sin fuerza.
- Por sesión de fuerza: marcar cada ejercicio, marcar cada serie, registrar kg y repeticiones, ver la **sesión anterior** con datos, % de ejercicios completados. **La sesión se completa sola** al marcar todos los ejercicios (y un ejercicio se marca solo al terminar todas sus series); si desmarcas uno, deja de estar completada.
- Nada se marca automáticamente al abrir un ejercicio.
- **Cumplimiento semanal** (sesiones completadas / 7 sesiones entrenables).
- Registros por semana (lunes–domingo): cada semana nueva empieza con casillas vacías y **el historial anterior se conserva** (pantalla *Historial de semanas anteriores*).
- Sesiones de carrera: botón para abrir Strava, instrucciones y botón de completada (también en la lista de la semana, «Marcar»).
- **Rutina editable** (botón *Editar* dentro de cada sesión de fuerza): añadir, eliminar, sustituir y reordenar ejercicios, y cambiar series y rango de repeticiones. Se guarda en el dispositivo y hay un botón para *Restaurar la rutina predeterminada*.
  - Sustituir un ejercicio crea uno nuevo en la misma posición: su progresión empieza de cero y el historial del anterior se conserva.
  - Cada registro semanal guarda una copia del nombre y la prescripción, así que el historial sigue siendo legible aunque cambies la rutina.
- **Progresión de cargas** por ejercicio (*Ver progresión de cargas*): gráfica de la carga máxima por semana, mejor serie, volumen (kg × reps), repeticiones totales y 1RM estimado (Epley, orientativo).

### Nutrición (menús)
- **Tus calorías**: en Ajustes › Objetivos diarios, o con el botón *Cambiar* de la tarjeta de calorías de Inicio.
- Objetivos editables en Ajustes (iniciales **provisionales**: 2.300 kcal, 180 g P, 250 g C, 65 g G).
- Desayuno, comida, merienda y cena, con casilla para marcar cada comida en el día elegido (puedes navegar a días anteriores).
- **9 modelos de menú** seleccionables por día, más un menú predeterminado.
- Cada ingrediente muestra nombre, gramos, cómo pesarlo (en crudo, en seco, escurrido, cocido y escurrido, parte comestible, peso real), ≈ kcal y macros.
- Subtotales por comida y **total diario calculados automáticamente** (no hay ningún total escrito a mano).
- Al cambiar los gramos de un ingrediente se recalculan ingrediente, comida y día. Si esa comida ya estaba marcada en el día visible, su registro se actualiza.
- Añadir/quitar ingredientes, renombrar menús.
- **Comidas a elegir (menú abierto)**: en lugar de un menú cerrado puedes escoger cada comida:
  - *Elegir mis comidas paso a paso*: primero 4 opciones de desayuno; después, según los macros del desayuno elegido, 4 opciones de comida; luego merienda y, por último, la cena, que cuadra con lo que te falta del día. Al final ves el resumen del día frente a tus objetivos y lo guardas.
  - *Cambiar* en cada comida del día: propone las alternativas que mejor encajan con las otras tres comidas que ya tienes. *Volver al menú* deshace el cambio.
  - Las opciones son las comidas de ese tipo de los 9 menús. Cada una se propone con una **ración ajustada** (75–135 %) para acercarse a los macros que te quedan, con gramos redondeados a cantidades pesables, y una puntuación «Encaja X %». Reparto orientativo del día: desayuno 25 %, comida 35 %, merienda 15 %, cena 25 %.
  - Las elecciones se guardan por día. Si una comida ya estaba marcada como hecha y la cambias, su registro se actualiza.
- **44 ideas de comida con pesos** (además de las 36 comidas de los 9 menús): por ejemplo *Plato de frutas con yogur* (plátano, fresas, kiwi, piña, yogur griego y nueces, ≈ 445 kcal) o *Pan blanco con jamón serrano y tomate* (≈ 442 kcal). Aparecen como opciones en el asistente y en *Cambiar*, con la ración ajustada a lo que te queda del día. Si eliges un desayuno ligero (un plato de fruta), la comida, la merienda y la cena se proponen con más cantidad para cuadrar el día.
- **«Lo que como»** (*Como otra cosa: apuntarla* en cada comida, y *Voy a comer otra cosa* dentro del asistente): apunta lo que realmente comes de dos formas:
  - *Catálogo*: buscas el alimento (entiende nombres comunes: «macarrones» encuentra la pasta) y pones los gramos.
  - *Manual*: nombre, gramos y kcal (macros opcionales), por ejemplo copiados de la etiqueta.
- **Reajustar el resto del día a mis macros**: mantiene lo que has apuntado y lo que ya has marcado como comido, y vuelve a elegir las demás comidas para cuadrar el día.
- **Objetivos a mano**: al escribir las kcal en *Ajustes › Objetivos diarios*, las proteínas, los carbohidratos y las grasas se calculan solos (proteína: 25–35 % de las kcal según tu objetivo, entre 1,6 y 2,4 g/kg de peso; grasa 25 %; el resto carbohidratos). Después puedes retocarlos.
- **Ajustar a tus requerimientos** (*Nutrición › ⋯ › Los 9 menús*): cada menú indica cuánto se desvía de tu objetivo calórico y puedes escalar un menú o los nueve a tus kcal. El ajuste es proporcional (mantiene las proporciones de macros de cada menú) y redondea a cantidades pesables (1 g por debajo de 20 g, 5 g por debajo de 100 g y 10 g a partir de ahí). Las comidas ya marcadas en días anteriores no cambian.
- **Catálogo local editable** de alimentos (valores por 100 g), con indicador ⚠︎ de valor provisional, aviso si kcal y macros no cuadran y opción de crear alimentos.
- Registro diario de comidas consumidas e historial con % de calorías.
- Criterios de peso: arroz, pasta, avena y quinoa **en seco**; carne y pescado **en crudo**; legumbres **cocidas y escurridas**; atún **escurrido**; aceite en **gramos reales**.

> Los valores del catálogo son **aproximados** (referencias generales tipo USDA FoodData Central/BEDCA) y los menús son **ejemplos**. No son un plan calculado clínicamente. Los alimentos que dependen mucho de la marca (whey, yogures, pan, legumbres de bote…) vienen marcados como provisionales. Revísalos con la etiqueta de tus productos en *Nutrición › ⋯ › Catálogo de alimentos*.

### Strava
- Botón **Abrir Strava** en las sesiones de carrera, en Actividad y en Inicio.
- Comprueba si Strava está instalada (`LSApplicationQueriesSchemes` incluye `strava`).
- **Importante**: Strava **no publica** ningún enlace profundo documentado para iniciar una grabación. La app intenta `strava://record` (no documentado) y, si iOS no puede abrirlo, abre la app con `strava://`. En la práctica se abrirá Strava y deberás pulsar **Grabar** tú mismo; la app lo explica en pantalla.
- Si Strava no está instalada, ofrece abrir la App Store o strava.com.
- **Importación de carreras por OAuth 2.0 (API oficial), sin servidor**: se configura una vez en Ajustes › Strava con la guía de la app (ver sección 4). Después se importan solas al abrir la app. Sin configurar, la app lo indica y **no** inventa kilómetros (puedes apuntar carreras a mano).

### Progreso (pestaña con cuatro secciones: Peso · Semana · Medallas · Fotos)
- **Gráfica de evolución del peso** con periodo 1M / 3M / 6M / 1A / Todo: cada pesaje (puntos), **tendencia de 7 días** (línea verde, quita el ruido del agua) y **media de cada mes** (línea discontinua), con el cambio de la tendencia en el periodo.
- **Media mensual**: lista con la media de cada mes, número de pesajes y diferencia con el mes anterior.
- **Semana**: resumen de lunes a domingo con flechas para ver semanas anteriores: **media de pasos**, **km corridos** (Strava o carreras apuntadas a mano), **cambio de peso** (último pesaje de la semana frente al anterior), **días cumplidos** (y descansos/fallos), el día a día en colores y las sesiones de entreno completadas.
- **Medallas** (bronce, plata y oro) en vez de una lista de récords: carrera más larga (5 / 10 / 21,1 km), mejor ritmo en carreras de 5 km o más (7:00 / 6:00 / 5:00 por km), día con más pasos (10.000 / 15.000 / 20.000), racha más larga (7 / 30 / 100 días), km totales (50 / 200 / 500), sesiones de fuerza (10 / 50 / 150), pesajes (10 / 30 / 100) y meses con las tres fotos (1 / 3 / 6). Cada una muestra la mejor marca, la fecha y lo que falta para el siguiente nivel. Sin datos no se inventa nada. Apple Salud (HealthKit) no se usa porque iOS no deja leerla al instalar con una cuenta de Apple gratuita.
- **Carreras sin Strava**: en una sesión de carrera, «Apuntar carrera a mano» (fecha, km y tiempo; calcula el ritmo). Cuentan para el resumen y las medallas.
- Registro de peso con fecha/hora y **cintura opcional**; evita duplicar un registro idéntico el mismo día.
- Primer peso, más reciente, diferencia total, diferencia con el **registro anterior** (también en cada fila del historial), variación **semanal** y **mensual** (solo si hay registros suficientemente antiguos), gráfica de evolución e historial (mantener pulsado para eliminar).
- Aviso de que la fluctuación diaria no es pérdida/ganancia de grasa confirmada.
- **Fotos mensuales** (frente, lateral, espalda): **cámara integrada** (delantera o trasera, temporizador de 3 o 10 s para hacerte la de espalda tú solo, y la foto del mismo ángulo del mes anterior superpuesta en transparencia para repetir la postura; revisas la foto antes de guardarla) o selector de fotos del sistema, indicador de vistas que faltan, guardado por mes/año, una foto por vista y mes (sin duplicados), reemplazo con confirmación, meses anteriores, **comparación de dos meses** (lado a lado o superpuesta con deslizador), eliminación de una foto o de todo el historial.
- **Antes / después**: deslizador sobre la propia foto (arrastra: a la izquierda «Antes», a la derecha «Después») o lado a lado. Al hacer una foto nueva, la del mes anterior sale encima en transparencia como guía de pose, con la transparencia ajustable.

### Ajustes y recordatorios
- **Diagnóstico de fluidez**: la app apunta cada vez que la pantalla se queda congelada más de 0,7 s, cuánto duró y en qué sección. Se ve en Ajustes; no se envía a ningún sitio.
- Objetivos de kcal y macros.
- **Creatina**: activar/desactivar, elegir hora, notificación de prueba. Usa un identificador fijo, así que cambiar la hora **sustituye** el recordatorio (no lo duplica). La app solo dice «programada» cuando iOS acepta la solicitud sin error.
- **Fotos**: recordatorio mensual el **día 22 a las 20:00** (o el día de tu fecha de inicio si la configuras; hora ajustable).
- Estado del permiso de notificaciones y número de notificaciones programadas.
- Configuración de Strava, fecha de inicio y peso inicial.
- **Avisos inteligentes**: aviso de pasos (solo si vas por debajo de la mitad de tu objetivo) y recordatorio de pesarte (solo si ese día aún no te has pesado). Eliges la hora («desde» = «hasta») o un rango (avisa a una hora dentro del rango). iOS no deja a una app mirar los pasos a cualquier hora: se comprueba al abrir y cerrar la app y cuando iOS la deja actualizarse en segundo plano (eso lo decide iOS), y el aviso dice cuántos pasos llevabas en la última comprobación.
- **Copia de seguridad**: «Exportar» guarda un archivo `.json` (en Archivos, iCloud Drive…) con todos los datos, fotos incluidas. «Importar» lo lee, enseña un resumen y, si confirmas, **reemplaza** todos los datos actuales. No incluye la clave de Claude ni la conexión con Strava.

---

## 3. Datos y privacidad

| Dato | Dónde se guarda |
|---|---|
| Pesos, cintura, entrenamientos (series, kg, reps, estados), menús, catálogo, comidas marcadas, ajustes, carreras importadas | Base de datos **SwiftData** local (`Application Support`), sin iCloud |
| Fotos de progreso | Archivos JPEG en `Application Support/ProgressPhotos` con protección de datos completa de iOS |
| Tokens OAuth de Strava | **Llavero** de iOS (solo este dispositivo) |
| ID de cliente de Strava | Ajustes locales (no es secreto) |
| Secreto de cliente de Strava | **Llavero** de iOS (solo este dispositivo) |

- La app **no tiene servidores ni cuentas propias** y no sube fotos a ningún sitio.
- Las copias de seguridad del iPhone (iCloud/Finder) incluyen los datos de las apps, como en cualquier app.
- No hay contraseñas, tokens ni claves privadas en el código fuente.

Permisos que pide la app:
- **Notificaciones** (creatina, fotos, prueba).
- **Fotos**: se usa `PhotosPicker`, que **no** necesita permiso de acceso a la fototeca (solo recibe las fotos que eliges).
- **Cámara** (fotos de progreso).

---

## 4. Funciones que necesitan configuración externa

### Importar carreras desde Strava (opcional, una sola vez, sin servidor)
La app habla directamente con Strava desde el iPhone; no hace falta ningún servidor ni programar. En la app: **Ajustes › Strava › «Cómo configurarlo»** (guía paso a paso):
1. Entra en <https://www.strava.com/settings/api> con tu cuenta y crea una aplicación (nombre: Now or Never; sitio web: `http://localhost`; **dominio de devolución de llamada: `localhost`**).
2. Copia el **ID de cliente** y el **secreto de cliente**, pégalos en Ajustes › Strava y pulsa **«Guardar y conectar con Strava»** → Autorizar.
3. Las carreras se importan al momento y luego solas cada vez que abres la app (como mucho cada 30 min). También hay «Importar carreras ahora».

El secreto se guarda solo en el **Llavero** de ese iPhone (no en el código ni en la copia de seguridad). Es una app de uso personal: la aplicación de Strava es tuya y solo la usas tú.

### Demo web (sin instalar nada)
`demo/NowOrNever-demo.html` es una versión web de la parte de comidas, rutina, peso y perfil, con el mismo catálogo y el mismo planificador. Guarda los datos en el navegador (y en tu cuenta de Claude si la abres como artefacto) y permite exportar/importar una copia en JSON. Se regenera con `python3 tools/build_demo.py`. No tiene Salud, notificaciones ni fotos.

### Nada más
Las notificaciones, las fotos y el botón de abrir Strava funcionan sin credenciales.

---

## 5. Notas sobre recordatorios

- **Creatina**: `UNCalendarNotificationTrigger` diario repetitivo (hora y minuto).
- **Fotos**: si el día de referencia (el día de tu fecha de inicio, 22) es ≤ 28 se usa un único disparador mensual repetitivo (`day = 22, hour = 20`), que iOS respeta todos los meses. Si fuese 29, 30 o 31, iOS saltaría los meses sin ese día; en ese caso la app programa individualmente los próximos 12 meses usando el último día del mes y los renueva cada vez que se abre.
- iOS permite como máximo 64 notificaciones locales pendientes por app; esta app usa como mucho 14.
- Si el iPhone está en modo Concentración, las notificaciones pueden quedar silenciadas según tu configuración.

---

## 6. Estructura del proyecto

```
NowOrNever/
├── NowOrNever.xcodeproj         Proyecto (formato Xcode 16, carpetas sincronizadas)
├── Config/
│   ├── Info.plist               URL scheme nowornever, LSApplicationQueriesSchemes
│   ├── NowOrNever.entitlements  com.apple.developer.healthkit
│   └── Signing.xcconfig         BUNDLE_ID_PREFIX (identificador configurable)
├── NowOrNever/
│   ├── App/                     Punto de entrada, barra de pestañas, tema
│   ├── Models/                  Rutina, cálculos nutricionales, cumplimiento, modelos SwiftData, Strava API
│   ├── Data/                    Catálogo de ejemplo y operaciones de datos
│   ├── Services/                HealthKit, notificaciones, Strava, fotos, Llavero
│   ├── Views/                   Inicio, Entreno, Nutrición, Progreso, Calendario, Ajustes
│   ├── Resources/SeedCatalog.json  Alimentos y menús de ejemplo
│   └── Assets.xcassets          Icono, color de acento, color de arranque
├── NowOrNeverTests/             Pruebas unitarias y de persistencia (XCTest + SwiftData en memoria)
├── NowOrNeverUITests/           Pruebas de interfaz que usan la app como un usuario (XCUITest)
└── tools/                       Scripts que generan SeedCatalog.json y el .xcodeproj
```

Las 6 secciones usan una barra de pestañas propia, porque la `TabView` del sistema agrupa la sexta pestaña en «Más» en iPhone.

---

## 7. Comprobaciones realizadas

Ver [`CHECKS.md`](CHECKS.md): compilación real con Xcode 16.4, 57 pruebas unitarias y de persistencia y 3 pruebas de interfaz en verde en el simulador, capturas de pantalla, y lo que **no** se ha podido probar (iPhone físico, Salud con datos reales, Strava real, notificaciones).
