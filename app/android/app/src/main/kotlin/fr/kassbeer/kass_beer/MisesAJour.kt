package fr.kassbeer.kass_beer

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * FileProvider des mises à jour (ADR-012). Il n'expose que cacheDir/updates/
 * (res/xml/updates_paths.xml), n'est pas exporté, et n'accorde qu'une lecture
 * temporaire de l'URI passée à l'installateur. Distinct d'ExportsFileProvider :
 * les deux dossiers ne partagent pas une autorité.
 */
class MisesAJourFileProvider : FileProvider()

/**
 * Canal fr.kassbeer/updates (ADR-012) : mêmes noms de canal, de méthodes et de codes
 * que app/lib/core/services/app_installer.dart (P17).
 *
 * - updatesDir() : crée et rend cacheDir/updates/.
 * - canRequestInstall() : autorisation « installer des applications inconnues ».
 * - openInstallSettings() : ouvre ce réglage pour Kass'Beer.
 * - installApk(expectedBuild) : aucun chemin reçu du Dart ; lit
 *   cacheDir/updates/kass-beer-update.apk hors du thread principal, exige le paquet de
 *   l'application et un versionCode égal à expectedBuild (sinon apk_invalid, fichier
 *   effacé), puis ouvre l'installateur du système.
 *
 * Aucun message d'erreur ne contient de chemin (P13).
 */
class MisesAJour(private val activity: Activity) : MethodChannel.MethodCallHandler {
    companion object {
        const val CANAL = "fr.kassbeer/updates"
        private const val DOSSIER = "updates"
        private const val FICHIER = "kass-beer-update.apk"
        private const val TYPE_APK = "application/vnd.android.package-archive"
    }

    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private val principal = Handler(Looper.getMainLooper())

    /** Installation en cours, de l'appel à l'ouverture de l'installateur ; fil principal. */
    private var installationEnCours = false

    fun brancher(messenger: BinaryMessenger) {
        MethodChannel(messenger, CANAL).setMethodCallHandler(this)
    }

    /** Vide cacheDir/updates/ : un APK installé ou abandonné n'a plus d'usage. */
    fun viderMisesAJour() {
        val dossier = File(activity.cacheDir, DOSSIER)
        executor.execute { dossier.listFiles()?.forEach { it.delete() } }
    }

    fun fermer() {
        executor.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "updatesDir" -> dossier(result)
            "canRequestInstall" -> result.success(peutInstaller())
            "openInstallSettings" -> ouvrirReglages(result)
            "installApk" -> installer(call, result)
            else -> result.notImplemented()
        }
    }

    private fun dossier(result: MethodChannel.Result) {
        executor.execute {
            val dossier = File(activity.cacheDir, DOSSIER)
            val pret = dossier.isDirectory || dossier.mkdirs()
            principal.post {
                if (pret) {
                    result.success(dossier.absolutePath)
                } else {
                    result.error("dir_unavailable", "dossier des mises à jour indisponible", null)
                }
            }
        }
    }

    /** Avant Android 8, l'autorisation était un réglage global : rien à demander. */
    private fun peutInstaller(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return true
        return activity.packageManager.canRequestPackageInstalls()
    }

    private fun ouvrirReglages(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.success(false)
            return
        }
        try {
            activity.startActivity(
                Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:${activity.packageName}"),
                ),
            )
            result.success(true)
        } catch (e: ActivityNotFoundException) {
            result.error("settings_unavailable", "réglage indisponible", null)
        }
    }

    private fun installer(call: MethodCall, result: MethodChannel.Result) {
        val attendu = call.argument<Number>("expectedBuild")?.toLong()
        if (attendu == null || attendu <= 0) {
            result.error("INVALID_ARGUMENT", "build attendu absent", null)
            return
        }
        if (installationEnCours) {
            result.error("ALREADY_ACTIVE", "installation en cours", null)
            return
        }
        installationEnCours = true
        executor.execute {
            try {
                val fichier = File(File(activity.cacheDir, DOSSIER), FICHIER)
                if (!fichier.isFile) {
                    principal.post { terminer { result.error("apk_missing", "fichier absent", null) } }
                    return@execute
                }
                if (!conforme(fichier, attendu)) {
                    fichier.delete()
                    principal.post { terminer { result.error("apk_invalid", "paquet ou versionCode refusés", null) } }
                    return@execute
                }
                principal.post { terminer { ouvrirInstallateur(fichier, result) } }
            } catch (e: Exception) {
                principal.post { terminer { result.error("install_failed", e.javaClass.simpleName, null) } }
            }
        }
    }

    /** Paquet de l'application et versionCode égal au build du manifeste. */
    private fun conforme(fichier: File, attendu: Long): Boolean {
        val lu: PackageInfo? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            activity.packageManager.getPackageArchiveInfo(
                fichier.path,
                PackageManager.PackageInfoFlags.of(0),
            )
        } else {
            @Suppress("DEPRECATION")
            activity.packageManager.getPackageArchiveInfo(fichier.path, 0)
        }
        val info = lu ?: return false
        if (info.packageName != activity.packageName) return false
        val build = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }
        return build == attendu
    }

    /** Lève la marque de l'installation en cours, puis rend le résultat (fil principal). */
    private fun terminer(rendu: () -> Unit) {
        installationEnCours = false
        rendu()
    }

    private fun ouvrirInstallateur(fichier: File, result: MethodChannel.Result) {
        try {
            val uri = FileProvider.getUriForFile(
                activity,
                "${activity.packageName}.updates",
                fichier,
            )
            activity.startActivity(
                Intent(Intent.ACTION_VIEW)
                    .setDataAndType(uri, TYPE_APK)
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),
            )
            result.success(true)
        } catch (e: ActivityNotFoundException) {
            result.error("install_failed", "installateur indisponible", null)
        } catch (e: Exception) {
            result.error("install_failed", e.javaClass.simpleName, null)
        }
    }
}
