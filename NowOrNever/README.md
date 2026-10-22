# Now or Never — app nativa para iPhone

App de entrenamiento, nutrición, pasos y progreso físico escrita en **Swift + SwiftUI**, con persistencia local en **SwiftData**, lectura de pasos con **HealthKit**, recordatorios con **UserNotifications** y apertura/integración de **Strava**.

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
   - En esa misma pestaña debe aparecer la capacidad **HealthKit** (ya está configurada en `Config/NowOrNever.entitlements`). Si Xcode muestra un aviso, pulsa *Try Again* / *Fix*.
   - Haz lo mismo (Team) en el target **NowOrNeverTests** si vas a ejecutar las pruebas.
5. Conecta el iPhone y, en el iPhone, activa **Ajustes › Privacidad y seguridad › Modo desarrollador** (iOS lo pide la primera vez y reinicia el teléfono).
6. Arriba en Xcode elige tu iPhone como destino y pulsa **▶︎ Run** (⌘R).
7. La primera vez el iPhone dirá que el desarrollador no es de confianza: ve a **Ajustes › General › VPN y gestión de dispositivos**, toca tu Apple ID y pulsa **Confiar**.
8. Abre la app. Verás la pantalla inicial para introducir tu peso y fecha de inicio (puedes pulsar *Usar 85,1 kg · 22 oct 2026* o escribir otros valores, o *Omitir*).

> Pruebas: en Xcode, ⌘U con un simulador de iPhone seleccionado (pruebas unitarias + pruebas de interfaz).

### Que parezca una app normal (como WhatsApp o TikTok)
Una vez instalada desde Xcode, Now or Never **ya es una app nativa**: tiene su icono en la pantalla de inicio, se abre a pantalla completa, aparece en la biblioteca de apps, en Spotlight, en Ajustes › Notificaciones y en Salud. No es una web ni un acceso directo. La única diferencia con una app de la App Store es **cómo se instala y cuánto dura la firma**:

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
- **Frase motivadora** (gimnasio y desarrollo personal; 40 frases, nunca la misma dos veces seguidas). Se cierra sola a los 3 s o al tocarla y aparece la interfaz. Vuelve a salir si regresas a la app tras 10 minutos o más fuera.

### Inicio
- **Calorías de hoy** arriba del todo, sin anillos: «Te quedan X kcal» (objetivo − lo comido) y lo que te queda de proteínas, carbohidratos y grasas. Baja a medida que registras comidas; si te pasas, lo indica en naranja. Al tocarla se abre *Comidas*.
- **Tarjeta de pasos de hoy** arriba del todo: número grande, anillo de % del objetivo, cuántos te faltan, ≈ km (zancada media de 0,76 m) y ≈ kcal (0,04 kcal/paso), y de dónde salen los datos. Si Apple Salud no da datos (por ejemplo, porque la instalación por SideStore no incluye el permiso de Salud), usa el **sensor de movimiento del iPhone** (Movimiento y forma física, últimos 7 días). Si aún no has dado permiso, muestra el botón *Conectar Apple Salud*.
- Peso más reciente y diferencia respecto al primer peso registrado.
- Entrenamiento(s) programado(s) para hoy con su estado.
- Comidas completadas (x/4).
- **Cumplimiento diario**: media de los componentes disponibles → comidas (x/4), sesiones del día completadas (se omite el viernes de descanso) y pasos/objetivo (máx. 100 %; se omite si Salud no da datos). El desglose se muestra en pantalla.
- Accesos rápidos: registrar peso, ver pasos, iniciar carrera (abre Strava) y ver rutina.

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
- **Cambiar el nombre de cualquier sesión** (lápiz arriba a la derecha dentro de la sesión, o mantener pulsada en la lista). El historial se conserva y *Nombre original* lo deshace.
- **Sábado con dos sesiones separadas** (Carrera y Pecho y espalda), cada una con su propio estado.
- Viernes: descanso con indicaciones de recuperación, sin fuerza.
- Por sesión de fuerza: marcar cada ejercicio, marcar cada serie, registrar kg y repeticiones, ver la **sesión anterior** con datos, % de ejercicios completados y botón de **sesión completa**.
- Nada se marca automáticamente al abrir un ejercicio.
- **Cumplimiento semanal** (sesiones completadas / 7 sesiones entrenables).
- Registros por semana (lunes–domingo): cada semana nueva empieza con casillas vacías y **el historial anterior se conserva** (pantalla *Historial de semanas anteriores*).
- Sesiones de carrera: botón para abrir Strava, instrucciones y marcado de completada.
- **Rutina editable** (botón *Editar* dentro de cada sesión de fuerza): añadir, eliminar, sustituir y reordenar ejercicios, y cambiar series y rango de repeticiones. Se guarda en el dispositivo y hay un botón para *Restaurar la rutina predeterminada*.
  - Sustituir un ejercicio crea uno nuevo en la misma posición: su progresión empieza de cero y el historial del anterior se conserva.
  - Cada registro semanal guarda una copia del nombre y la prescripción, así que el historial sigue siendo legible aunque cambies la rutina.
- **Progresión de cargas** por ejercicio (*Ver progresión de cargas*): gráfica de la carga máxima por semana, mejor serie, volumen (kg × reps), repeticiones totales y 1RM estimado (Epley, orientativo).

### Nutrición › Comidas (lo que comes de verdad, por foto)
- Cuatro comidas: **Desayuno, Almuerzo, Merienda y Cena**. Al tocar una se abre **directamente la cámara**.
- Haces la foto del plato (o de los ingredientes) y **Claude detecta qué alimentos hay** (pollo, atún, boniato, queso cottage…). Los dudosos aparecen con «(?)».
- Puedes **corregir nombres, quitar alimentos o añadir los que no haya detectado**, y **pones los gramos de cada uno** (lo que marca la báscula).
- *Calcular calorías*: Claude da los valores por 100 g de cada alimento tal y como está (cocinado, crudo…) y la app calcula kcal y macros **con tus gramos**. Ves cada alimento y el **total**, y *Añadir* lo suma a esa comida. Se pueden hacer varias fotos para la misma comida.
- Cada alimento se puede quitar después (✕) y el total se actualiza. También sin foto: *Añadir ingrediente* y escribirlo a mano.
- Las kcal registradas se restan en **Inicio** (lo que te queda).

### Nutrición › Menús (ideas y planificación)
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
- **«Lo que como»** (*Como otra cosa: apuntarla* en cada comida, y *Voy a comer otra cosa* dentro del asistente): apunta lo que realmente comes de tres formas:
  - *Describir (Claude)*: escribes «150 g de macarrones con tomate» y Claude estima los gramos, kcal y macros de cada ingrediente. Revisas el resultado antes de añadirlo.
  - *Catálogo*: buscas el alimento (entiende nombres comunes: «macarrones» encuentra la pasta) y pones los gramos.
  - *Manual*: nombre, gramos y kcal (macros opcionales), por ejemplo copiados de la etiqueta.
  - *Alternativa más saludable*: Claude propone comidas hechas **solo con alimentos del catálogo** que encajan con el objetivo de esa comida; las kcal y macros las calcula la app, no Claude.
- **Reajustar el resto del día a mis macros**: mantiene lo que has apuntado y lo que ya has marcado como comido, y vuelve a elegir las demás comidas para cuadrar el día.
- **Claude (opcional)**: necesita tu propia clave de la API de Anthropic (*Ajustes › Claude*), que se guarda en el Llavero. Cada consulta cuesta unos céntimos en tu cuenta de Anthropic. Sin clave, *Catálogo* y *Manual* funcionan igual.
- **Objetivos a mano**: al escribir las kcal en *Ajustes › Objetivos diarios*, las proteínas, los carbohidratos y las grasas se calculan solos (proteína: 25–35 % de las kcal según tu objetivo, entre 1,6 y 2,4 g/kg de peso; grasa 25 %; el resto carbohidratos). Después puedes retocarlos.
- **Ajustar a tus requerimientos** (*Nutrición › ⋯ › Los 9 menús*): cada menú indica cuánto se desvía de tu objetivo calórico y puedes escalar un menú o los nueve a tus kcal. El ajuste es proporcional (mantiene las proporciones de macros de cada menú) y redondea a cantidades pesables (1 g por debajo de 20 g, 5 g por debajo de 100 g y 10 g a partir de ahí). Las comidas ya marcadas en días anteriores no cambian.
- **Catálogo local editable** de alimentos (valores por 100 g), con indicador ⚠︎ de valor provisional, aviso si kcal y macros no cuadran y opción de crear alimentos.
- Registro diario de comidas consumidas e historial con % de calorías.
- Criterios de peso: arroz, pasta, avena y quinoa **en seco**; carne y pescado **en crudo**; legumbres **cocidas y escurridas**; atún **escurrido**; aceite en **gramos reales**.

> Los valores del catálogo son **aproximados** (referencias generales tipo USDA FoodData Central/BEDCA) y los menús son **ejemplos**. No son un plan calculado clínicamente. Los alimentos que dependen mucho de la marca (whey, yogures, pan, legumbres de bote…) vienen marcados como provisionales. Revísalos con la etiqueta de tus productos en *Nutrición › ⋯ › Catálogo de alimentos*.

### Actividad y pasos (Apple Salud)
- Solicita permiso de **lectura** de pasos (no escribe nada en Salud).
- Pasos de hoy (suma acumulada deduplicada por HealthKit entre iPhone y Apple Watch), objetivo editable (8.000 por defecto) y % de cumplimiento.
- Historial de los últimos 30 días (gráfica + lista), media y días con objetivo.
- Permisos: iOS **no indica** a las apps si se ha denegado la lectura de datos de Salud; en ese caso las consultas simplemente no devuelven datos. La app muestra «Sin datos» y explica cómo revisarlo: *Ajustes › Salud › Acceso a datos y dispositivos › Now or Never*.

### Strava
- Botón **Abrir Strava** en las sesiones de carrera, en Actividad y en Inicio.
- Comprueba si Strava está instalada (`LSApplicationQueriesSchemes` incluye `strava`).
- **Importante**: Strava **no publica** ningún enlace profundo documentado para iniciar una grabación. La app intenta `strava://record` (no documentado) y, si iOS no puede abrirlo, abre la app con `strava://`. En la práctica se abrirá Strava y deberás pulsar **Grabar** tú mismo; la app lo explica en pantalla.
- Si Strava no está instalada, ofrece abrir la App Store o strava.com.
- **Importación de carreras por OAuth 2.0 (API oficial)**: implementada pero **pendiente de configuración** (ver sección 4). Sin configurar, la app lo indica y **no** muestra kilómetros importados.

### Progreso físico
- Registro de peso con fecha/hora y **cintura opcional**; evita duplicar un registro idéntico el mismo día.
- Primer peso, más reciente, diferencia total, diferencia con el **registro anterior** (también en cada fila del historial), variación **semanal** y **mensual** (solo si hay registros suficientemente antiguos), gráfica de evolución e historial (mantener pulsado para eliminar).
- Aviso de que la fluctuación diaria no es pérdida/ganancia de grasa confirmada.
- **Fotos mensuales** (frente, lateral, espalda): **cámara integrada** (delantera o trasera, temporizador de 3 o 10 s para hacerte la de espalda tú solo, y la foto del mismo ángulo del mes anterior superpuesta en transparencia para repetir la postura; revisas la foto antes de guardarla) o selector de fotos del sistema, indicador de vistas que faltan, guardado por mes/año, una foto por vista y mes (sin duplicados), reemplazo con confirmación, meses anteriores, **comparación de dos meses** (lado a lado o superpuesta con deslizador), eliminación de una foto o de todo el historial.

### Amigos (cuentas y seguir a otras personas)
- Cada persona usa la app en **su iPhone con su cuenta** (correo + contraseña + @usuario). Los datos completos siguen en cada móvil.
- **Seguir** a alguien por su @usuario. La otra persona recibe la solicitud y puede *Aceptar y seguir*, *Solo aceptar* o rechazarla.
- En **Sigues a** ves los **últimos 14 días** de cada persona: sesiones programadas **hechas (✓) o sin hacer (✗)** con sus mejores series, sus comidas y kcal, la proteína y los pasos. Arriba aparece el resumen semanal, con los días en que **no ha entrenado**.
- Lo que se comparte se sube al abrir la app, al salir de ella y al entrar en *Amigos*. Lo puedes desactivar en *Compartir* y quitar seguidores cuando quieras.
- Necesita un servidor gratuito de **Supabase**, que se crea una vez (guía en `AMIGOS.md`; esquema y reglas de privacidad en `docs/supabase/schema.sql`).

### Ajustes y recordatorios
- Objetivos de kcal, macros y pasos.
- **Creatina**: activar/desactivar, elegir hora, notificación de prueba. Usa un identificador fijo, así que cambiar la hora **sustituye** el recordatorio (no lo duplica). La app solo dice «programada» cuando iOS acepta la solicitud sin error.
- **Fotos**: recordatorio mensual el **día 22 a las 20:00** (o el día de tu fecha de inicio si la configuras; hora ajustable).
- Estado del permiso de notificaciones y número de notificaciones programadas.
- Configuración de Strava, fecha de inicio y peso inicial.

---

## 3. Datos y privacidad

| Dato | Dónde se guarda |
|---|---|
| Pesos, cintura, entrenamientos (series, kg, reps, estados), menús, catálogo, comidas marcadas, ajustes, carreras importadas | Base de datos **SwiftData** local (`Application Support`), sin iCloud |
| Fotos de progreso | Archivos JPEG en `Application Support/ProgressPhotos` con protección de datos completa de iOS |
| Tokens OAuth de Strava | **Llavero** de iOS (solo este dispositivo) |
| Sesión de Amigos | **Llavero** de iOS. La URL y la clave pública del servidor, en ajustes locales |
| Resumen diario compartido (si usas Amigos) | Tu proyecto de Supabase. Solo lo leen las personas que aceptas (reglas por fila en `docs/supabase/schema.sql`) |
| Clave de la API de Claude (opcional) | **Llavero** de iOS. Se envía a `api.anthropic.com` solo cuando usas Claude: la **foto de la comida** (reducida) y los ingredientes con sus gramos, el texto que describes o, para ideas, tu objetivo y la lista del catálogo. Nunca las fotos de progreso, tu peso ni datos de Salud |
| Client ID de Strava y URL del backend | Ajustes locales (no son secretos) |

- La app **no tiene servidores ni cuentas propias** y no sube fotos a ningún sitio.
- Las copias de seguridad del iPhone (iCloud/Finder) incluyen los datos de las apps, como en cualquier app.
- No hay contraseñas, tokens ni claves privadas en el código fuente.

Permisos que pide la app:
- **Apple Salud** (lectura de pasos) — capacidad HealthKit + `NSHealthShareUsageDescription`.
- **Notificaciones** (creatina, fotos, prueba).
- **Fotos**: se usa `PhotosPicker`, que **no** necesita permiso de acceso a la fototeca (solo recibe las fotos que eliges).
- **Cámara** (fotos de progreso) y **Movimiento y forma física** (pasos cuando Salud no da datos).

---

## 4. Funciones que necesitan configuración externa

### Importar carreras desde Strava (opcional)
El intercambio del código OAuth por tokens requiere el **client_secret**, que no debe estar nunca dentro de una app. Por eso hace falta un pequeño backend.

1. Entra en <https://www.strava.com/settings/api> y crea una aplicación.
   - **Authorization Callback Domain**: `localhost`
   - Anota el **Client ID** y el **Client Secret**.
2. Despliega el backend de ejemplo `docs/strava-backend/worker.js` (Cloudflare Workers, plan gratuito):
   ```bash
   npm install -g wrangler
   cd docs/strava-backend
   wrangler init --yes   # o crea wrangler.toml con main = "worker.js"
   wrangler secret put STRAVA_CLIENT_ID
   wrangler secret put STRAVA_CLIENT_SECRET
   wrangler deploy
   ```
   Obtendrás una URL `https://…workers.dev`. Puedes usar cualquier otro servidor que implemente `POST /strava/token` y `POST /strava/refresh` igual que el ejemplo.
3. En la app: **Ajustes › Strava** → escribe el Client ID y la URL del backend → *Guardar configuración* → *Conectar con Strava* → autoriza (marca la casilla de ver actividades) → *Importar carreras ahora*.

Detalles técnicos:
- Flujo: `ASWebAuthenticationSession` (vía `webAuthenticationSession` de SwiftUI) con `https://www.strava.com/oauth/mobile/authorize`, `redirect_uri = nowornever://localhost/strava`, `scope = read,activity:read_all`, `state` aleatorio validado.
- Se importan las actividades `Run`, `TrailRun` y `VirtualRun`: distancia, tiempo transcurrido, tiempo en movimiento, ritmo medio (calculado con el tiempo en movimiento), fecha y desnivel si existe.
- El token se renueva automáticamente vía backend cuando caduca (Strava los emite con 6 h de validez).
- Errores gestionados: cancelación/denegación, `state` distinto, permisos insuficientes, 401, límite de peticiones (429) y respuestas inválidas del backend.
- *Desconectar* revoca el token en Strava y lo borra del Llavero.
- Strava limita a las apps nuevas a 1 atleta (tú) hasta que solicitas más capacidad; suficiente para uso personal.

### Demo web (sin instalar nada)
`demo/NowOrNever-demo.html` es una versión web de la parte de comidas, rutina, peso y perfil, con el mismo catálogo y el mismo planificador. Guarda los datos en el navegador (y en tu cuenta de Claude si la abres como artefacto) y permite exportar/importar una copia en JSON. Se regenera con `python3 tools/build_demo.py`. No tiene Salud, notificaciones ni fotos.

### Nada más
Salud, notificaciones, fotos y el botón de abrir Strava funcionan sin credenciales.

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
│   ├── Info.plist               URL scheme nowornever, LSApplicationQueriesSchemes, texto de Salud
│   ├── NowOrNever.entitlements  com.apple.developer.healthkit
│   └── Signing.xcconfig         BUNDLE_ID_PREFIX (identificador configurable)
├── NowOrNever/
│   ├── App/                     Punto de entrada, barra de pestañas, tema
│   ├── Models/                  Rutina, cálculos nutricionales, cumplimiento, modelos SwiftData, Strava API
│   ├── Data/                    Catálogo de ejemplo y operaciones de datos
│   ├── Services/                HealthKit, notificaciones, Strava, fotos, Llavero
│   ├── Views/                   Inicio, Entreno, Nutrición, Actividad, Progreso, Ajustes
│   ├── Resources/SeedCatalog.json  Alimentos y 9 menús de ejemplo
│   └── Assets.xcassets          Icono, color de acento, color de arranque
├── NowOrNeverTests/             Pruebas unitarias y de persistencia (XCTest + SwiftData en memoria)
├── NowOrNeverUITests/           Pruebas de interfaz que usan la app como un usuario (XCUITest)
├── docs/strava-backend/         Backend de ejemplo para OAuth
└── tools/                       Scripts que generan SeedCatalog.json y el .xcodeproj
```

Las 6 secciones usan una barra de pestañas propia, porque la `TabView` del sistema agrupa la sexta pestaña en «Más» en iPhone.

---

## 7. Comprobaciones realizadas

Ver [`CHECKS.md`](CHECKS.md): compilación real con Xcode 16.4, 57 pruebas unitarias y de persistencia y 3 pruebas de interfaz en verde en el simulador, capturas de pantalla, y lo que **no** se ha podido probar (iPhone físico, Salud con datos reales, Strava real, notificaciones).
