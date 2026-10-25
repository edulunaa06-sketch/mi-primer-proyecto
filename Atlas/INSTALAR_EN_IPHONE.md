# Instalar ATLAS en tu iPhone sin pagar los 99 € al año

Lo primero, claro y sin rodeos:

> **El `.ipa` que genera el CI no se puede instalar tal cual.** Va firmado «ad hoc», que sirve
> para comprobar que el paquete está bien montado, pero Apple no lo deja arrancar en un iPhone.
> Para instalarlo hay que **volver a firmarlo con tu propio Apple ID**, y eso lo hace una
> herramienta en tu ordenador o en el propio móvil. Es gratis, pero tiene condiciones.

## Antes de nada: haz una copia de seguridad

Si ya tienes ATLAS en el iPhone, **exporta tus datos antes de instalar la versión nueva**:
Ajustes → Copia de seguridad → Exportar, y guárdala en Archivos o en iCloud Drive.

Por qué: esta versión añade tablas y campos a la base de datos (series, récords, recuperación,
suplementos). La actualización está pensada para hacerse sola y no borrar nada, pero si algo
fuera mal al abrirla, ATLAS te lo dirá en una pantalla en vez de perder datos en silencio, y con
esa copia lo recuperas todo. Es un minuto y te ahorra un disgusto.

Las cinco cosas que la gente mezcla y conviene separar:

| Paso | Qué es | ¿Hecho? |
|---|---|---|
| Desarrollo | Escribir el código | Sí, está en este repositorio |
| Compilación | Convertir el código en una app | Sí, en el runner macOS del CI |
| Generación del IPA | Empaquetar la app en un `.ipa` | Sí, artefacto `Atlas-ipa` |
| **Firma** | Autorizar la app para TU iPhone con tu Apple ID | **No: esto lo haces tú** |
| Instalación | Pasarla al teléfono | Tú, con Sideloadly o SideStore |

## Lo que Apple impone con un Apple ID gratis

Esto no depende de la app ni de la herramienta: es la política de Apple para una cuenta gratuita
(«personal team»).

- **La firma caduca a los 7 días.** Al octavo, la app deja de abrirse hasta que la vuelvas a firmar.
  No pierdes los datos: siguen en el iPhone mientras no borres la app.
- **Unas 3 apps firmadas a la vez** por dispositivo.
- Hay que **confiar** en el certificado la primera vez, y tener el **Modo desarrollador** activado.

Con la cuenta de pago de Apple (99 €/año) la firma dura **un año** y desaparece el límite de apps.
Es la única forma de quitarse la renovación semanal; el resto son maneras de hacerla más cómoda.

> **AltStore PAL no es un atajo para esto.** Es la tienda alternativa que existe en la UE y para
> los usuarios es gratis, pero para *distribuir* una app en ella hacen falta notarización y cuenta
> de desarrollador de pago. No sirve para instalar tu propia app autofirmada.

## Opción A — Sideloadly (la más sencilla)

Necesitas un ordenador (Windows o Mac) una vez por semana.

1. Descarga el artefacto **`Atlas-ipa`** del último build verde del CI:
   `Actions` → «iOS build (ATLAS)` → el último run en verde → `Atlas-ipa`.
   Dentro del zip está `Atlas.ipa`.
   (También queda una copia en el repositorio, en `Atlas/dist/Atlas.ipa`.)
2. Instala **Sideloadly** (sideloadly.io) y, en Windows, **iTunes** de la web de Apple
   (no la versión de la Microsoft Store).
3. Conecta el iPhone por cable y acepta «Confiar en este ordenador».
4. Abre Sideloadly, arrastra `Atlas.ipa`, escribe tu Apple ID y pulsa **Start**.
   - Si tienes verificación en dos pasos, te pedirá una contraseña específica de app:
     la creas en `account.apple.com` → Seguridad → Contraseñas específicas de app.
   - Deja el *Bundle ID* como está si quieres conservar los datos que ya tengas.
5. En el iPhone: **Ajustes → General → VPN y gestión de dispositivos** → tu Apple ID → **Confiar**.
6. Primera vez: **Ajustes → Privacidad y seguridad → Modo desarrollador** → activar y reiniciar.
7. Cada 7 días, repite el paso 4. No borres la app: así no pierdes el historial.

## Opción B — SideStore (renovar sin ordenador)

Misma caducidad de 7 días, pero la renovación la hace el propio iPhone, sin tener que enchufarlo.

1. Configuración inicial desde un ordenador (una sola vez): generar el archivo de emparejamiento
   e instalar SideStore siguiendo la guía oficial de **sidestore.io**.
2. SideStore necesita una pequeña VPN local en el dispositivo para poder refirmar desde dentro.
3. A partir de ahí, se renueva desde el móvil, y puede hacerlo solo mientras la configuración siga válida.

Es más cómodo a medio plazo y más frágil a corto: el emparejamiento se rompe a veces y una
actualización de iOS puede obligar a repetir la configuración. Si quieres lo más simple y
predecible, quédate en la opción A.

## Opción C — Compilarla tú en un Mac con Xcode

Si tienes acceso a un Mac, es la vía más limpia: Xcode firma con tu Apple ID y la instala directo.

```sh
git clone https://github.com/edulunaa06-sketch/mi-primer-proyecto
cd mi-primer-proyecto/Atlas
python3 tools/gen_xcodeproj.py       # genera Atlas.xcodeproj
open Atlas.xcodeproj
```

En Xcode: selecciona el *target* **Atlas** → `Signing & Capabilities` → marca
**Automatically manage signing** y elige tu Apple ID en *Team*. Conecta el iPhone, selecciónalo
arriba y pulsa ▶. Sigue caducando a los 7 días con cuenta gratuita, pero renovar es pulsar ▶.

## Si la app no abre

| Síntoma | Causa y arreglo |
|---|---|
| «No se puede verificar la app» | Falta confiar en el certificado: Ajustes → General → VPN y gestión de dispositivos |
| Se abre y se cierra al instante | Modo desarrollador desactivado, o la firma ha caducado: vuelve a firmar |
| «Unable to install» en Sideloadly | Ya tienes 3 apps firmadas con ese Apple ID: borra alguna |
| Dejó de abrir a los 7 días | Es lo esperado con cuenta gratuita: refírmala |
| Pide la contraseña y la rechaza | Con 2FA hace falta una contraseña específica de app |

## Lo que todavía no puedo hacer por ti, y por qué

Este entorno es un contenedor **Linux**. Compilar y firmar una app de iOS exige el toolchain de
Apple (Xcode), que solo existe en macOS. Por eso:

- El código, el proyecto y las pruebas se preparan y se verifican aquí.
- La compilación y el empaquetado del IPA se hacen en un runner **macOS** de GitHub Actions.
- **La firma para tu teléfono no se puede hacer en ningún servidor**: necesita tu Apple ID y,
  con cuenta gratuita, un certificado ligado a tu dispositivo. Eso lo tienes que hacer tú.

No hay forma de saltarse esto sin inventarse certificados, y eso no se hace.
