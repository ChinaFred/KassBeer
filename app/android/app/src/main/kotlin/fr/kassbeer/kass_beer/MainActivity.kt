package fr.kassbeer.kass_beer

import android.content.Context
import android.media.AudioAttributes
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var ringtone: Ringtone? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
