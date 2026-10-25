# ATLAS · Estado real de cada módulo

Qué funciona, qué funciona a medias y qué no está. Sin adornos: si algo no se ha podido
comprobar, aquí pone que no se ha comprobado.

Leyenda: **Hecho** = implementado y con pruebas que lo ejercitan · **Parcial** = funciona pero
le falta parte de lo pedido · **No está** = no implementado, con el motivo.

## Entrenamiento

| Pedido | Estado | Detalle |
|---|---|---|
| Crear, editar, duplicar y archivar rutinas | **Parcial** | Crear desde cero, editar, reordenar, sustituir y restaurar: hecho. Duplicar una rutina entera y archivarla: no está. |
| Organizar por días y grupos musculares | **Hecho** | Siete días, dos sesiones el mismo día, nombres editables. |
| Series, repeticiones, cargas y descansos | **Hecho** | Series y rango en la rutina; kilos, repeticiones y descanso por serie en la sesión. |
| Objetivos de RIR o RPE | **Parcial** | RIR se apunta por serie y lo usa la progresión. El RPE está en el modelo y se deriva del RIR, pero no hay campo para escribirlo. |
| Notas | **Hecho** | Por ejercicio dentro de la sesión. |
| Superseries y bloques | **No está** | El modelo no agrupa ejercicios. |
| Rutinas favoritas | **No está** | |
| Historial de cada rutina | **Hecho** | Por semana, y por ejercicio en su ficha. |
| Registro de peso, repeticiones, RIR, series | **Hecho** | Con tipo de serie: calentamiento, efectiva, drop y back-off. |
| Series de calentamiento vs efectivas | **Hecho** | El calentamiento no suma volumen. |
| Molestias | **Hecho** | Por ejercicio; bloquean la subida de peso. |
| Duración de la sesión | **Hecho** | Cronómetro con pausa que sobrevive a cerrar la app. |
| Pausar, reanudar y guardar aunque se cierre | **Hecho** | Probado en `StrengthPersistenceTests`. |
| Ver la última sesión comparable mientras entrenas | **Hecho** | «La vez anterior» en cada ejercicio. |
| Récords personales | **Hecho** | Peso máximo, 1RM estimado y volumen de sesión; distingue primera marca de récord batido. |
| Sobrecarga progresiva y recomendaciones | **Hecho** | Progresión doble con RIR, siempre con el motivo escrito. |
| Detección de estancamientos | **Hecho** | Tres sesiones seguidas sin mejorar, nunca con una. |
| Estimaciones de 1RM | **Hecho** | Epley, Brzycki y Lombardi, con nivel de fiabilidad. |
| Volumen semanal y por grupo muscular | **Hecho** | Directo e indirecto, con referencia y avisos. |
| Frecuencia por grupo muscular | **Hecho** | Días distintos, no sesiones. |
| Programado frente a realizado | **Hecho** | |
| Semanas de descarga | **Parcial** | Se sugiere con señales reales y se puede marcar la semana a mano; no hay planificación automática. |
| Planificación por bloques | **No está** | |
| Biblioteca de ejercicios con variantes | **Hecho** | 57 fichas con músculos, patrón, material, ejecución, errores, seguridad y alternativas. |
| Comparar barras, mancuernas, poleas y máquinas | **Hecho** | El comparador explica qué cambia; nunca dice que dos sean idénticos. |
| Vídeos de los ejercicios | **No está** | A propósito: no se inventan enlaces y no hay una fuente de vídeo con licencia. |

## Nutrición

| Pedido | Estado | Detalle |
|---|---|---|
| Objetivos de kcal y macros | **Hecho** | Mifflin-St Jeor, automáticos o a mano. |
| Fibra, agua y micronutrientes | **Parcial** | Agua sí. Fibra y micronutrientes: en el modelo del catálogo, no como objetivo diario. |
| Objetivos distintos en día de entreno y descanso | **No está** | |
| Déficit, mantenimiento, superávit, recomposición | **Hecho** | Como objetivo del perfil. |
| Búsqueda de alimentos, cantidades, marcas, propios | **Hecho** | |
| Escáner de códigos de barras | **No está** | Haría falta una base de datos de productos; no se añade una integración que no se pueda verificar aquí. |
| Registro por foto | **Hecho** | Con IA, si hay clave. |
| Registro por voz | **No está** | |
| Comidas frecuentes y duplicar comidas | **Parcial** | Las ideas y los menús hacen de plantillas; duplicar un día entero, no. |
| Recetas: crear, ingredientes, duplicar, favoritas | **Parcial** | Crear, ingredientes, cantidades, duplicar y borrar: hecho. Favoritas: no. |
| Peso final cocinado y valores por ración | **Hecho** | Y el rendimiento al cocinar, explicado. |
| Pesos crudo, cocinado y comestible | **Hecho** | Siete bases de peso distintas. |
| Suplementos | **Hecho** | Ver abajo. |
| Planificador de menús y lista de la compra | **Parcial** | Planificador del día con reajuste automático: hecho. Lista de la compra, menús semanales, presupuesto y precios de supermercado: no están. |

## Cuerpo, recuperación y progreso

| Pedido | Estado | Detalle |
|---|---|---|
| Peso, medidas, fotos, objetivos | **Parcial** | Peso y cintura sí; fotos mensuales con comparador sí. Más medidas corporales: no. |
| Porcentaje de grasa estimado | **No está** | A propósito: no se estima sin un método fiable, y una foto no lo mide. |
| Medias semanales y evolución mensual | **Hecho** | |
| Comparación de periodos | **Hecho** | En los informes. |
| Gráficas interactivas | **Hecho** | Peso, volumen por músculo y 1RM por ejercicio. |
| Informes semanales, mensuales y anuales | **Hecho** | Cuatro periodos, con lo que falta para que sean fiables. |
| Sueño, fatiga, energía, estrés, agujetas, molestias | **Hecho** | |
| Pasos y actividad | **Hecho** | Sensor del iPhone; carreras desde Strava. |
| Frecuencia cardíaca | **No está** | Haría falta HealthKit (ver abajo). |
| Relacionar recuperación y rendimiento | **Hecho** | Correlación con aviso explícito de que no es causa. |

## Suplementación, gamificación e IA

| Pedido | Estado | Detalle |
|---|---|---|
| Registro, dosis, horarios, coste mensual | **Hecho** | |
| Comparación y evidencia | **Hecho** | 18 suplementos con nivel de evidencia, incluidos los que no la tienen. |
| Duplicidades e interacciones | **Parcial** | Duplicados por principio activo y exceso de cafeína: hecho. Interacciones con medicamentos: no, y se remite a un profesional. |
| Rachas, retos, logros, medallas, récords | **Parcial** | Rachas, medallas, récords y celebraciones: hecho. Retos y objetivos semanales propios: no. |
| Servicio de IA con proveedor real | **Hecho** | API de Claude con salida estructurada. Sin clave, la app lo dice y no simula nada. |
| Herramientas tipadas sobre los datos | **Parcial** | El contexto que ve la IA es tipado, se enseña antes de enviarlo y es **solo lectura**. No hay un bucle de herramientas en el que la IA pida datos por su cuenta. |
| Propuestas de rutina y menús | **Parcial** | Llegan como propuesta de texto; aplicarlas con un toque no está, y es deliberado: la IA no cambia nada sola. |

## Integraciones

| Integración | Estado |
|---|---|
| Strava | **Hecho y probado** por sesiones anteriores. Necesita que el usuario cree su app en Strava y un backend propio para el secreto, con guía paso a paso dentro de la app. |
| API de Claude | **Implementada.** Las peticiones y el formato están probados sin red; **no se ha comprobado una llamada real desde aquí**, porque haría falta una clave del usuario. |
| Apple Health / HealthKit | **No está.** Añadirlo exige un entitlement nuevo, y eso puede complicar la instalación con un Apple ID gratuito, que es justo lo que se necesita para poder usar la app. Se deja fuera a propósito. |
| Bases de datos nutricionales externas | **No está.** No se añade una integración que no se pueda probar aquí. |
| Precios de supermercados | **No está.** No hay fuente fiable y gratuita. |
| Exportar e importar datos | **Hecho y probado.** JSON con todo, fotos incluidas. |

## Pruebas

- **254 pruebas de lógica**, ejecutadas con el toolchain de Swift para Linux en cada cambio.
- **Pruebas de persistencia** con SwiftData en memoria, en el simulador: series, historial,
  cronómetro, récords, recuperación, suplementos, recetas y copia de seguridad.
- **14 recorridos de interfaz** en el simulador, incluido uno con ocho meses de datos que mide
  si alguna pantalla se congela.

## Limitaciones conocidas

1. **El IPA del CI no se instala tal cual**: va firmado ad hoc. Hay que refirmarlo con tu Apple
   ID (`INSTALAR_EN_IPHONE.md`). Con cuenta gratuita caduca a los 7 días. Esto lo impone Apple.
2. **La migración de la base de datos** al abrir la versión nueva con datos antiguos no se ha
   podido probar con una base real anterior. Está pensada para hacerse sola (todos los campos
   nuevos tienen valor por defecto) y, si fallara, la app lo dice en una pantalla en vez de
   borrar nada. Por eso conviene exportar la copia antes de actualizar.
3. **La llamada real a la IA no se ha probado** desde este entorno: requiere una clave.
4. **El identificador del paquete es `com.example.atlas`.** Funciona para instalar, pero es un
   dominio de ejemplo. Cambiarlo haría que el iPhone lo tratara como una app distinta y
   perderías los datos de la instalada, así que se deja como está.
5. **El nombre «Atlas» está muy usado** en Salud y Fitness de la App Store. Para uso personal da
   igual; para publicar habría que cambiarlo. No se ha comprobado en registros de marcas.
