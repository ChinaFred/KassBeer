package fr.kassbeer.kass_beer

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Canal `fr.kassbeer/prefs` (ADR-009) : préférence de thème gardée sur l'appareil, dans
 * `SharedPreferences`. Noms identiques dans `app/lib/core/preferences/preferences_appareil.dart`
 * (P17).
 *
 * La lecture et l'écriture tournent sur un seul thread de fond ; le résultat est rendu sur le
 * thread principal. Un seul appel à la fois (P17) : un appel reçu pendant qu'un autre est en cours
 * rend `BUSY`. Le drapeau `enCours` est posé et levé sur le thread principal. Le Dart n'envoie pas
 * de second appel avant la fin du premier et garde le dernier choix pour la suite
 * (`PreferencesAppareilPlateforme.ecrireTheme`).
 */
class PreferencesAppareil(context: Context) : MethodChannel.MethodCallHandler {
    companion object {
        const val CANAL = "fr.kassbeer/prefs"
        const val METHODE_LIRE_THEME = "getTheme"
        const val METHODE_ECRIRE_THEME = "setTheme"
        const val ARGUMENT_VALEUR = "value"
        const val FICHIER = "kassbeer_prefs"
        const val CLE_THEME = "theme_mode"
        val VALEURS_THEME = setOf("light", "dark", "system")
    }

    private val appContext = context.applicationContext
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private val principal = Handler(Looper.getMainLooper())

    /** Un appel est en cours. Lu et écrit sur le thread principal seul. */
    private var enCours = false

    fun brancher(messenger: BinaryMessenger) {
        MethodChannel(messenger, CANAL).setMethodCallHandler(this)
    }

    fun fermer() {
        executor.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            METHODE_LIRE_THEME -> enFond(result) {
                prefs().getString(CLE_THEME, null)
            }
            METHODE_ECRIRE_THEME -> {
                val valeur = call.argument<String>(ARGUMENT_VALEUR)
                if (valeur == null || valeur !in VALEURS_THEME) {
                    result.error("INVALID_THEME", "valeur de thème refusée", null)
                    return
                }
                enFond(result) {
                    prefs().edit().putString(CLE_THEME, valeur).apply()
                    null
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun prefs() = appContext.getSharedPreferences(FICHIER, Context.MODE_PRIVATE)

    /** Appelé sur le thread principal, par `onMethodCall`. */
    private fun enFond(result: MethodChannel.Result, travail: () -> String?) {
        if (enCours) {
            result.error("BUSY", "un appel de préférence est déjà en cours", null)
            return
        }
        enCours = true
        try {
            executor.execute {
                try {
                    val valeur = travail()
                    principal.post {
                        enCours = false
                        result.success(valeur)
                    }
                } catch (e: Exception) {
                    principal.post {
                        enCours = false
                        result.error("PREFS_FAILED", e.javaClass.simpleName, null)
                    }
                }
            }
        } catch (e: Exception) {
            // Exécuteur fermé (activité détruite) : rien n'est parti en fond.
            enCours = false
            result.error("PREFS_FAILED", e.javaClass.simpleName, null)
        }
    }
}
