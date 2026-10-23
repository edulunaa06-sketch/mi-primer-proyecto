Usa mi Chrome (la extensión Claude in Chrome) para crear el servidor de amigos de mi app «Now or Never» en Supabase. Hazlo todo tú y pídeme ayuda solo si hace falta iniciar sesión o confirmar algo.

1. Abre https://supabase.com y entra en mi cuenta. Si no tengo, crea una con «Continue with GitHub». Si me pide iniciar sesión, espera a que lo haga yo.
2. Crea un proyecto nuevo:
   - Name: now-or-never
   - Database password: genera una segura y enséñamela al final para que la guarde.
   - Region: una de Europa (Frankfurt o Paris).
   - Plan: Free.
   Espera a que el proyecto termine de prepararse.
3. Abre este enlace en otra pestaña y copia TODO el texto:
   https://raw.githubusercontent.com/edulunaa06-sketch/mi-primer-proyecto/now-or-never-ios/NowOrNever/docs/supabase/schema.sql
   En Supabase ve a SQL Editor › New query, pega el texto y pulsa Run. Si avisa de que hay operaciones destructivas, confirma con «Run this query». Tiene que salir «Success». Si sale un error, dime el mensaje exacto.
4. Ve a Authentication › Sign In / Providers y activa «Allow anonymous sign-ins». Guarda los cambios.
5. Ve a Project Settings › API Keys (o al botón Connect) y dame:
   - la Project URL (https://xxxx.supabase.co)
   - la Publishable key (empieza por sb_publishable_; en proyectos antiguos se llama «anon public»).
   NO copies ni me enseñes la «secret» ni la «service_role».

Al terminar, escríbeme en español:
- la Project URL,
- la Publishable key,
- la contraseña de la base de datos (solo para que la guarde),
- y confirma que los pasos 3 y 4 salieron bien.
