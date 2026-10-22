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

## 3. Que las cuentas funcionen al momento (recomendado)
En **Authentication › Sign In / Providers › Email**, desactiva **Confirm email** y guarda.

Si lo dejas activado, al crear la cuenta te llegará un correo: abre el enlace y después inicia sesión en la app. Aunque el enlace acabe en una página que no carga, la cuenta queda confirmada.

## 4. Copiar los dos datos para la app
En **Project Settings › API Keys** (o en el botón **Connect** de arriba):
- **Project URL**: `https://xxxxxxxx.supabase.co`
- **Publishable key** (`sb_publishable_…`) o, en proyectos antiguos, la **anon public key**.

> ⚠️ Nunca uses la **secret** ni la **service_role**: la app las rechaza. La clave pública se puede compartir sin problema, porque las reglas del paso 2 deciden quién ve qué.

## 5. En la app (cada persona en su iPhone)
1. Pestaña **Amigos** → pega la URL y la clave → **Guardar**.
2. **Crear cuenta**: correo, contraseña, @usuario (por ejemplo `edu`) y tu nombre.
3. Tu pareja hace lo mismo en su iPhone, con la **misma URL y la misma clave**. Pásaselas por WhatsApp.
4. Uno escribe el @usuario del otro y pulsa **Seguir**. Al otro le aparece la solicitud: con **Aceptar y seguir** os seguís los dos.
5. Toca su nombre en **Sigues a** para ver sus últimos 14 días: entrenos hechos (✓) o sin hacer (✗), mejores series, comidas, kcal y pasos. Arriba verás el resumen de la semana, con los días en que no ha entrenado.

## Qué se comparte y cuándo
- **Qué**: un resumen por día con las sesiones programadas (hechas o no) y sus mejores series, las 4 comidas (marcadas o no) con sus kcal, las kcal y la proteína registradas y los pasos.
- **Qué no**: fotos, peso corporal, cintura ni otros datos de Salud.
- **Cuándo**: al abrir la app, al salir de ella y al entrar en *Amigos*. Se suben los últimos 7 días, contados desde que empezaste a usar la app.
- **Quién lo ve**: solo las personas cuya solicitud aceptas. Puedes quitar a un seguidor o desactivar *Compartir* cuando quieras.
- **Dónde**: tus datos completos siguen **solo en tu iPhone**. Si borras la app, el resumen compartido se queda en el servidor hasta que lo borres desde Supabase.

## Límites del plan gratuito
Si nadie usa el proyecto durante una semana, Supabase lo pausa. Entra en supabase.com y pulsa **Restore**; los datos no se pierden.
