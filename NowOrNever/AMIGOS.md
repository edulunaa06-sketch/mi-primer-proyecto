# Cuentas y amigos: configurar el servidor (una vez, gratis, unos 5 minutos)

Para que tu iPhone y el de tu pareja se vean hace falta un pequeño servidor. Se usa **Supabase**, que es gratis para este uso. Lo crea **una sola persona** y la otra solo pega los mismos dos datos en su app.

## 1. Crear el proyecto
1. Entra en <https://supabase.com> y pulsa **Start your project**. Puedes registrarte con tu correo o con GitHub.
2. Pulsa **New project**:
   - Name: `now-or-never`
   - Database password: inventa una y guárdala (la app no la necesita).
   - Region: **Europe (Frankfurt o Paris)**.
   - Plan: **Free**.
3. Espera 1–2 minutos a que el proyecto esté listo.

## 2. Crear las tablas y las reglas de privacidad
1. En el menú de la izquierda, entra en **SQL Editor** y pulsa **New query**.
2. Abre el archivo `docs/supabase/schema.sql` de este proyecto, copia todo su contenido, pégalo y pulsa **Run**. Debe salir «Success».
   - Crea también dos carpetas privadas de archivos (**avatars** para las fotos de perfil y **progress** para las fotos de progreso) con sus reglas de acceso.
   - Si ya lo ejecutaste con una versión anterior, vuelve a ejecutarlo entero: añade lo nuevo sin borrar nada.

## 3. Entrar solo con un nombre (sin correo ni contraseña)
En **Authentication › Sign In / Providers**, activa **Allow anonymous sign-ins** y pulsa **Save**.

Así cada persona solo escribe su nombre en la app. La cuenta queda guardada en su iPhone; como no tiene correo, no se puede «cerrar sesión» y volver a entrar en otro móvil.

## 4. Copiar los dos datos
En **Project Settings › API Keys** (o en el botón **Connect** de arriba):
- **Project URL**: `https://xxxxxxxx.supabase.co`
- **Publishable key** (`sb_publishable_…`) o, en proyectos antiguos, la **anon public key**.

> ⚠️ Nunca uses la **secret** ni la **service_role**: la app las rechaza. La clave pública se puede compartir sin problema, porque las reglas del paso 2 deciden quién ve qué.

**Lo más fácil:** pásale estos dos datos a Claude para que los meta dentro de la app (`NowOrNever/Models/SocialServer.swift`). Con la siguiente versión, nadie tiene que pegar nada: abren *Amigos*, escriben su nombre y listo.

Si no, cada persona los pega una vez en *Amigos* y pulsa **Guardar**.

## 5. Usarlo
1. Pestaña **Amigos** → escribe tu nombre (el @usuario se rellena solo; puedes cambiarlo) → **Empezar**.
2. En **Buscar amigos**, escribe el nombre o el @usuario de tu pareja o de un amigo y pulsa **Seguir**.
   O pulsa **Buscar en mis contactos**: salen los contactos de tu agenda que usan la app y han puesto su teléfono.
   - Tu teléfono es opcional (al empezar o en *Buscar amigos*). En el servidor solo se guarda un código sacado del número, no el número, y nadie puede ver la lista.
   - Los números no se comprueban por SMS: alguien podría poner un número que no es suyo. Por eso seguir siempre necesita que la otra persona acepte; fíjate en su @usuario.
3. Al otro le aparece la solicitud: con **Aceptar y seguir** os seguís los dos.
4. Toca su nombre en **Sigues a** para ver sus últimos 14 días: entrenos hechos (✓) o sin hacer (✗), mejores series, comidas, kcal y pasos. Arriba verás el resumen de la semana, con los días en que no ha entrenado.

## Tu perfil
En *Amigos*, toca tu nombre (**Ver mi perfil**):
- **Foto de perfil**: toca el círculo y elígela de la galería.
- **Seguidores y seguidos**: el número y la lista.
- **Estadísticas**: tu altura (de *Ajustes › Perfil*) y tu último peso. Interruptor *Mostrar altura y peso a mis seguidores*.
- **Fotos de progreso**: las de *Progreso › Fotos*, agrupadas por fecha (por ejemplo «Viernes, 23 de octubre» con frente, lateral y espalda). Cada vez que haces una, se añade. La primera vez que entras te pregunta si quieres compartirlas. Si lo desactivas, se borran del servidor y en tu iPhone se quedan.

En el perfil de tu pareja (*Sigues a* › su nombre) ves su foto, sus seguidores y seguidos, su altura y peso, y dos pestañas: **Entrenos y comidas** (sus días) y **Fotos** (sus fotos con fecha).

## Qué se comparte y cuándo
- **Qué**: un resumen por día con las sesiones programadas (hechas o no) y sus mejores series, las 4 comidas (marcadas o no) con sus kcal, las kcal y la proteína registradas y los pasos.
- **Además, si lo activas en tu perfil**: tu altura y tu peso, y tus fotos de progreso con su fecha. Tu foto de perfil la ve cualquiera que use el mismo servidor, para que te reconozca al buscarte.
- **Qué no**: cintura, fotos de comidas, ni otros datos de Salud.
- **Cuándo**: al abrir la app, al salir de ella y al entrar en *Amigos*. Se suben los últimos 7 días, contados desde que empezaste a usar la app.
- **Quién lo ve**: solo las personas cuya solicitud aceptas. Puedes quitar a un seguidor o desactivar *Compartir* cuando quieras.
- **Dónde**: tus datos completos siguen **solo en tu iPhone**. Si borras la app, el resumen compartido se queda en el servidor hasta que lo borres desde Supabase.

## Límites del plan gratuito
Si nadie usa el proyecto durante una semana, Supabase lo pausa. Entra en supabase.com y pulsa **Restore**; los datos no se pierden.
