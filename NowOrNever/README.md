# Now or Never — app nativa para iPhone

App de entrenamiento, nutrición, pasos y progreso físico escrita en **Swift + SwiftUI**, con persistencia local en **SwiftData**, lectura de pasos con **HealthKit**, recordatorios con **UserNotifications** y apertura/integración de **Strava**.

- iOS **17.0** o posterior · solo iPhone · orientación vertical · tema oscuro (negro/carbón + verde lima).
- Sin dependencias externas (ningún paquete SPM ni CocoaPods).
- Todos los datos se guardan **solo en el iPhone**.

<p>
<img src="docs/screenshots/home.jpg" width="200"> <img src="docs/screenshots/training.jpg" width="200"> <img src="docs/screenshots/session-tue-push-a.jpg" width="200"> <img src="docs/screenshots/nutrition.jpg" width="200">
</p>

*Capturas reales del simulador (iOS 18.5) generadas por el CI. Más en `docs/screenshots/`.*

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

> Pruebas unitarias: en Xcode, ⌘U (con un simulador de iPhone seleccionado).

---

## 2. Funciones implementadas

### Inicio
- Peso más reciente y diferencia respecto al primer peso registrado.
- Objetivo de kcal y barras de proteínas, carbohidratos y grasas (consumido según las comidas marcadas / objetivo).
- Pasos del día (de Apple Salud; si no hay datos se muestra «—», nunca un número inventado).
- Entrenamiento(s) programado(s) para hoy con su estado.
- Comidas completadas (x/4).
- **Cumplimiento diario**: media de los componentes disponibles → comidas (x/4), sesiones del día completadas (se omite el viernes de descanso) y pasos/objetivo (máx. 100 %; se omite si Salud no da datos). El desglose se muestra en pantalla.
- Accesos rápidos: registrar peso, ver pasos, iniciar carrera (abre Strava) y ver rutina.

### Entrenamientos
- Rutina semanal **exacta** de la especificación (`Models/Routine.swift`), con identificadores estables. Las pruebas `RoutineTests` comprueban ejercicios, orden, series y rangos.
- **Sábado con dos sesiones separadas** (Carrera y Pecho y espalda), cada una con su propio estado.
- Viernes: descanso con indicaciones de recuperación, sin fuerza.
- Por sesión de fuerza: marcar cada ejercicio, marcar cada serie, registrar kg y repeticiones, ver la **sesión anterior** con datos, % de ejercicios completados y botón de **sesión completa**.
- Nada se marca automáticamente al abrir un ejercicio.
- **Cumplimiento semanal** (sesiones completadas / 7 sesiones entrenables).
- Registros por semana (lunes–domingo): cada semana nueva empieza con casillas vacías y **el historial anterior se conserva** (pantalla *Historial de semanas anteriores*).
- Sesiones de carrera: botón para abrir Strava, instrucciones y marcado de completada.

### Nutrición
- Objetivos editables en Ajustes (iniciales **provisionales**: 2.300 kcal, 180 g P, 250 g C, 65 g G).
- Desayuno, comida, merienda y cena, con casilla para marcar cada comida en el día elegido (puedes navegar a días anteriores).
- **9 modelos de menú** seleccionables por día, más un menú predeterminado.
- Cada ingrediente muestra nombre, gramos, cómo pesarlo (en crudo, en seco, escurrido, cocido y escurrido, parte comestible, peso real), ≈ kcal y macros.
- Subtotales por comida y **total diario calculados automáticamente** (no hay ningún total escrito a mano).
- Al cambiar los gramos de un ingrediente se recalculan ingrediente, comida y día. Si esa comida ya estaba marcada en el día visible, su registro se actualiza.
- Añadir/quitar ingredientes, renombrar menús.
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
- Primer peso, más reciente, diferencia total, variación **semanal** y **mensual** (solo si hay registros suficientemente antiguos), gráfica de evolución e historial (mantener pulsado para eliminar).
- Aviso de que la fluctuación diaria no es pérdida/ganancia de grasa confirmada.
- **Fotos mensuales** (frente, lateral, espalda): selector de fotos del sistema, indicador de vistas que faltan, guardado por mes/año, una foto por vista y mes (sin duplicados), reemplazo con confirmación, meses anteriores, **comparación de dos meses** (lado a lado o superpuesta con deslizador), eliminación de una foto o de todo el historial.

### Ajustes y recordatorios
- Objetivos de kcal, macros y pasos.
- **Creatina**: activar/desactivar, elegir hora, notificación de prueba. Usa un identificador fijo, así que cambiar la hora **sustituye** el recordatorio (no lo duplica). La app solo dice «programada» cuando iOS acepta la solicitud sin error.
- **Fotos**: recordatorio mensual el día de tu fecha de inicio (22) a las 20:00 (hora configurable).
- Estado del permiso de notificaciones y número de notificaciones programadas.
- Configuración de Strava, fecha de inicio y peso inicial.

---

## 3. Datos y privacidad

| Dato | Dónde se guarda |
|---|---|
| Pesos, cintura, entrenamientos (series, kg, reps, estados), menús, catálogo, comidas marcadas, ajustes, carreras importadas | Base de datos **SwiftData** local (`Application Support`), sin iCloud |
| Fotos de progreso | Archivos JPEG en `Application Support/ProgressPhotos` con protección de datos completa de iOS |
| Tokens OAuth de Strava | **Llavero** de iOS (solo este dispositivo) |
| Client ID de Strava y URL del backend | Ajustes locales (no son secretos) |

- La app **no tiene servidores ni cuentas propias** y no sube fotos a ningún sitio.
- Las copias de seguridad del iPhone (iCloud/Finder) incluyen los datos de las apps, como en cualquier app.
- No hay contraseñas, tokens ni claves privadas en el código fuente.

Permisos que pide la app:
- **Apple Salud** (lectura de pasos) — capacidad HealthKit + `NSHealthShareUsageDescription`.
- **Notificaciones** (creatina, fotos, prueba).
- **Fotos**: se usa `PhotosPicker`, que **no** necesita permiso de acceso a la fototeca (solo recibe las fotos que eliges).

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
├── NowOrNeverTests/             Pruebas unitarias (XCTest)
├── docs/strava-backend/         Backend de ejemplo para OAuth
└── tools/                       Scripts que generan SeedCatalog.json y el .xcodeproj
```

Las 6 secciones usan una barra de pestañas propia, porque la `TabView` del sistema agrupa la sexta pestaña en «Más» en iPhone.

---

## 7. Comprobaciones realizadas

Ver [`CHECKS.md`](CHECKS.md): compilación real con Xcode 16.4 (BUILD SUCCEEDED, sin avisos del compilador), 35 pruebas unitarias en verde en el simulador, capturas de pantalla, y lo que **no** se ha podido probar (iPhone físico, Strava real, notificaciones).
