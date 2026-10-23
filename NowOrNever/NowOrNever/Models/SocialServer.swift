import Foundation

/// Servidor de amigos que viene dentro de la app. Con él puesto, cada persona solo elige su nombre:
/// no hay que pegar URL ni clave. Es la URL del proyecto de Supabase y su clave PÚBLICA (publishable/anon),
/// que se puede compartir; las reglas de `docs/supabase/schema.sql` deciden quién ve qué.
/// Vacío = la app pide la URL y la clave en la pestaña Amigos.
enum SocialServer {
    static let url = ""
    static let publishableKey = ""

    static var builtIn: SocialAPI.Config? { SocialAPI.Config(url: url, apiKey: publishableKey) }
}
