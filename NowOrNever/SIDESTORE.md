# Instalar Now or Never con SideStore (gratis, sin App Store)

## Qué necesitas
- **Un ordenador** con Windows, Mac o Linux y un **cable USB** para el iPhone. Solo hace falta la primera vez; con una tablet no se puede.
- Una **cuenta de Apple** (vale la tuya de siempre y es gratis).
- En el iPhone: iOS 15 o posterior y la app **LocalDevVPN** (gratis en el App Store).
- El archivo **`NowOrNever.ipa`**.

## Paso 1 · Instalar SideStore (una sola vez, con el ordenador)
1. En el ordenador, descarga **iloader** desde la guía oficial: <https://docs.sidestore.io/docs/installation/install>.
2. Conecta el iPhone por USB. Si el iPhone pregunta «¿Confiar en este ordenador?», pulsa **Confiar**.
3. Abre iloader, inicia sesión con tu cuenta de Apple, elige tu iPhone y pulsa **Install SideStore (Stable)**.
4. En el iPhone, ve a **Ajustes › General › VPN y gestión de dispositivos**, toca tu cuenta y pulsa **Confiar**.
5. Ve a **Ajustes › Privacidad y seguridad › Modo de desarrollador** y actívalo. El iPhone se reinicia.
6. Abre **LocalDevVPN** y pulsa **Connect**.
7. Abre **SideStore** e inicia sesión con la misma cuenta de Apple. En **My Apps**, toca el contador «7 DAYS» de SideStore para renovarlo. Si te pregunta por el certificado, pulsa **Yes / Refresh Now**.

## Paso 2 · Instalar Now or Never (desde el propio iPhone)
1. Pasa `NowOrNever.ipa` al iPhone, por ejemplo por AirDrop, iCloud Drive, correo o Drive, y guárdalo en **Archivos**.
2. Con **LocalDevVPN conectado**, abre SideStore › **My Apps** › **+** (arriba a la izquierda).
3. Elige `NowOrNever.ipa`. En un minuto aproximadamente aparece el icono en tu pantalla de inicio, como cualquier otra app.
4. La primera vez que abras la app, acepta los permisos que pide: Salud y Movimiento (pasos), notificaciones (creatina y fotos) y cámara (fotos de comidas y de progreso).

## Paso 3 · Renovar cada semana (2 toques, sin ordenador)
Con una cuenta de Apple gratuita, las apps caducan a los **7 días**.
- Activa LocalDevVPN, abre SideStore › My Apps y pulsa **Refresh All**.
- También puedes hacerlo automático con un atajo: SideStore trae una acción para la app **Atajos** con la que crear una automatización diaria.
- Si se te pasa y caduca, **no pierdes los datos**: renueva la app y vuelve a abrirla.

## Instalarla en el iPhone de tu pareja
Necesita su propio SideStore en su iPhone, con su cuenta de Apple. Repite los pasos 1 y 2 en su móvil; el ordenador solo hace falta la primera vez. Pásale `NowOrNever.ipa` por AirDrop o WhatsApp (como documento).

Al abrir la app por primera vez podrá elegir **Rutina: Predeterminada o Desde cero**. Con *Desde cero*, las sesiones de fuerza empiezan vacías: mantiene pulsada cada sesión para ponerle nombre (por ejemplo «Glúteo») y dentro pulsa *Editar* para añadir sus ejercicios. También puede cambiarlo más tarde en *Entrenos › Opciones de la rutina*.

Después, en *Amigos*, pega la misma URL y clave del servidor (ver `AMIGOS.md`), crea su cuenta y seguíos.

## Actualizar a una versión nueva
En SideStore › My Apps › **+**, elige el `.ipa` nuevo. Se instala encima y **conserva tus datos**, siempre que uses la misma cuenta de Apple.

## Si algo falla
| Problema | Solución |
|---|---|
| «Unable to verify app» / la app no abre | Ajustes › General › VPN y gestión de dispositivos › Confiar. |
| SideStore no instala ni renueva | Comprueba que LocalDevVPN está conectado. Si sigue fallando, el archivo de emparejamiento ha caducado: vuelve a conectarlo al ordenador y genéralo con iloader. |
| «Maximum number of apps» | Con una cuenta gratuita solo puede haber 3 apps instaladas por SideStore (SideStore cuenta como una). Borra otra. |
| Salud no muestra pasos | Algunas capacidades de Apple no se activan con cuentas gratuitas. El resto de la app funciona igual. Con Xcode y tu cuenta sí puedes activarlo. |

## Lo que funciona y lo que está sin probar
- **Comprobado en un Mac de GitHub (simulador):** la app compila, arranca y pasa las pruebas automáticas, también las de pulsar la pantalla.
- **Sin probar en un iPhone físico:** la instalación por SideStore, Salud, las notificaciones, la cámara, Strava y Claude. Si algo de esto falla, dime el mensaje exacto y lo corrijo.
