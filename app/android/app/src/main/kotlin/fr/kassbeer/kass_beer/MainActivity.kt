package fr.kassbeer.kass_beer

import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var ringtone: Ringtone? = null

    // Canal des fichiers (ADR-007), branché avec le moteur.
    private var fichiers: EchangeFichiers? = null

    // Canal de la préférence de thème (ADR-009), branché avec le moteur.
    private var preferences: PreferencesAppareil? = null

    // Canal des mises à jour de l'APK (ADR-012), branché avec le moteur.
    private var misesAJour: MisesAJour? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Lancement neuf : le fichier exporté et l'APK téléchargé au lancement
        // précédent sont effacés.
        if (savedInstanceState == null) {
            fichiers?.viderExports()
            misesAJour?.viderMisesAJour()
        }
    }

    override fun onDestroy() {
        fichiers?.fermer()
        preferences?.fermer()
        misesAJour?.fermer()
        super.onDestroy()
    }

    // Retour du sélecteur du système (ACTION_OPEN_DOCUMENT, ACTION_CREATE_DOCUMENT) ; les
    // autres requêtes vont aux greffons, par FlutterActivity.
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (fichiers?.onActivityResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Canal des fichiers : mêmes noms que app/lib/core/fichiers/echange_fichiers.dart
        // (P17).
        fichiers = EchangeFichiers(this).also {
            it.brancher(flutterEngine.dartExecutor.binaryMessenger)
        }
        // Canal de la préférence de thème : mêmes noms que
        // app/lib/core/preferences/preferences_appareil.dart (P17).
        preferences = PreferencesAppareil(this).also {
            it.brancher(flutterEngine.dartExecutor.binaryMessenger)
        }
        // Canal des mises à jour de l'APK : mêmes noms que
        // app/lib/core/services/app_installer.dart (P17).
        misesAJour = MisesAJour(this).also {
            it.brancher(flutterEngine.dartExecutor.binaryMessenger)
        }
        // Canal de l'alerte de fin de minuteur : mêmes noms que
        // app/lib/features/brew_day/data/alerte_minuteur.dart (P17).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fr.kassbeer/alert")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "beep" -> {
                            beep()
                            result.success(null)
                        }
                        "vibrate" -> {
                            vibrate()
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("ALERT_FAILED", e.message, null)
                }
            }
    }

    /** Son de notification du système, sur le canal de l'alarme : il sonne en mode silencieux. */
    private fun beep() {
        val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        val tone = RingtoneManager.getRingtone(applicationContext, uri)
            ?: throw IllegalStateException("son de notification indisponible")
        tone.audioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        ringtone?.stop()
        ringtone = tone
        tone.play()
    }

    /** Vibration d'environ une seconde. */
    private fun vibrate() {
        val vibrator: Vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(VibrationEffect.createOneShot(1000L, VibrationEffect.DEFAULT_AMPLITUDE))
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(1000L)
        }
    }
}
