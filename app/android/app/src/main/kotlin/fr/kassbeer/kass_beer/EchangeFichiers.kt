package fr.kassbeer.kass_beer

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * FileProvider du projet (la documentation déconseille la classe nue). Il n'expose que
 * cacheDir/exports/ (res/xml/exports_paths.xml), n'est pas exporté, et n'accorde qu'une
 * lecture temporaire de l'URI partagée.
 */
class ExportsFileProvider : FileProvider()

/**
 * Canal fr.kassbeer/files (ADR-007) : mêmes noms de canal, de méthodes et de codes que
 * app/lib/core/fichiers/echange_fichiers.dart (P17).
 *
 * - pickDocument(maxBytes, mimeTypes?) : ACTION_OPEN_DOCUMENT, sans filtre de type, ou
 *   limité à mimeTypes (EXTRA_MIME_TYPES ; type générique des images quand tous en sont) ;
 *   taille contrôlée avant l'ouverture du flux, lecture bornée à maxBytes + 1 octets ; rend
 *   {name, bytes}, ou null sur une annulation.
 * - shareFile(name, mimeType, bytes) : écrit le fichier dans cacheDir/exports/, puis
 *   ACTION_SEND par la feuille de partage du système.
 * - saveDocument(name, mimeType, bytes) : ACTION_CREATE_DOCUMENT ; rend true si le fichier
 *   est écrit, false sur une annulation.
 *
 * Aucune borne de taille ici : elle vient du Dart. Aucune permission de stockage. Lecture et
 * écriture hors du thread principal, résultat rendu sur le thread principal. Aucun message
 * d'erreur ne contient le nom ni le contenu d'un fichier (P13).
 */
class EchangeFichiers(private val activity: Activity) : MethodChannel.MethodCallHandler {
    companion object {
        const val CANAL = "fr.kassbeer/files"

        /** Codes de requête propres au projet, déclarés une seule fois. */
        const val REQUETE_CHOIX = 0x4B42
        const val REQUETE_ENREGISTREMENT = 0x4B43

        private const val DOSSIER_EXPORTS = "exports"
        private const val NOM_MAX = 120
        private const val TAMPON = 64 * 1024

        /** Même motif et même nombre maximal que kMotifTypeMime et kTypesMax du Dart. */
        private val MOTIF_TYPE_MIME = Regex("^[a-z]{1,20}/[a-z0-9.+*-]{1,60}$")
        private const val TYPES_MAX = 10
    }

    private class Choix(val result: MethodChannel.Result, val maxBytes: Long)

    private class Enregistrement(val result: MethodChannel.Result, val bytes: ByteArray)

    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private val principal = Handler(Looper.getMainLooper())
    private var choixEnCours: Choix? = null
    private var enregistrementEnCours: Enregistrement? = null

    /** Partage en cours, de l'appel à l'ouverture de la feuille ; lu et écrit sur le fil principal. */
    private var partageEnCours = false

    fun brancher(messenger: BinaryMessenger) {
        MethodChannel(messenger, CANAL).setMethodCallHandler(this)
    }

    /** Vide cacheDir/exports/ : le fichier partagé porte le nom de l'auteur de la recette. */
    fun viderExports() {
        val dossier = File(activity.cacheDir, DOSSIER_EXPORTS)
        executor.execute { dossier.listFiles()?.forEach { it.delete() } }
    }

    fun fermer() {
        executor.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickDocument" -> choisir(call, result)
            "shareFile" -> partager(call, result)
            "saveDocument" -> enregistrer(call, result)
            else -> result.notImplemented()
        }
    }

    private fun occupe() =
        choixEnCours != null || enregistrementEnCours != null || partageEnCours

    private fun rendre(action: () -> Unit) {
        principal.post(action)
    }

    private fun choisir(call: MethodCall, result: MethodChannel.Result) {
        val maxBytes = call.argument<Number>("maxBytes")?.toLong()
        if (maxBytes == null || maxBytes <= 0) {
            result.error("INVALID_ARGUMENT", "borne absente", null)
            return
        }
        val brut = call.argument<List<Any?>>("mimeTypes")
        val types = brut?.map { it as? String }
        if (types != null &&
            (types.isEmpty() || types.size > TYPES_MAX ||
                types.any { it == null || !MOTIF_TYPE_MIME.matches(it) })
        ) {
            result.error("INVALID_ARGUMENT", "types de fichier refusés", null)
            return
        }
        if (occupe()) {
            result.error("ALREADY_ACTIVE", "choix ou enregistrement en cours", null)
            return
        }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            if (types == null) {
                // Aucun filtre : Drive déclare un .xml en application/octet-stream.
                type = "*/*"
            } else {
                val filtres = types.filterNotNull()
                type = if (filtres.all { it.startsWith("image/") }) "image/*" else "*/*"
                putExtra(Intent.EXTRA_MIME_TYPES, filtres.toTypedArray())
            }
        }
        choixEnCours = Choix(result, maxBytes)
        try {
            activity.startActivityForResult(intent, REQUETE_CHOIX)
        } catch (e: ActivityNotFoundException) {
            choixEnCours = null
            result.error("NO_PICKER", "aucune application de choix", null)
        }
    }

    private fun enregistrer(call: MethodCall, result: MethodChannel.Result) {
        val nom = call.argument<String>("name")
        val mime = call.argument<String>("mimeType")
        val octets = call.argument<ByteArray>("bytes")
        if (nom == null || mime == null || octets == null) {
            result.error("INVALID_ARGUMENT", "argument absent", null)
            return
        }
        if (!nomValide(nom)) {
            result.error("INVALID_NAME", "nom de fichier refusé", null)
            return
        }
        if (occupe()) {
            result.error("ALREADY_ACTIVE", "choix ou enregistrement en cours", null)
            return
        }
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mime
            putExtra(Intent.EXTRA_TITLE, nom)
        }
        enregistrementEnCours = Enregistrement(result, octets)
        try {
            activity.startActivityForResult(intent, REQUETE_ENREGISTREMENT)
        } catch (e: ActivityNotFoundException) {
            enregistrementEnCours = null
            result.error("NO_PICKER", "aucune application d'enregistrement", null)
        }
    }

    /** Retour d'une activité : vrai si la requête est celle de ce canal. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        when (requestCode) {
            REQUETE_CHOIX -> {
                // Le choix reste marqué jusqu'au résultat final de la lecture : un
                // second appel pendant la lecture rend ALREADY_ACTIVE.
                val choix = choixEnCours ?: return true
                val uri = data?.data
                if (resultCode != Activity.RESULT_OK || uri == null) {
                    finirChoix(choix) { choix.result.success(null) }
                } else {
                    executor.execute { lire(uri, choix) }
                }
                return true
            }
            REQUETE_ENREGISTREMENT -> {
                // Même règle jusqu'à la fin de l'écriture.
                val enregistrement = enregistrementEnCours ?: return true
                val uri = data?.data
                if (resultCode != Activity.RESULT_OK || uri == null) {
                    finirEnregistrement(enregistrement) { enregistrement.result.success(false) }
                } else {
                    executor.execute { ecrire(uri, enregistrement) }
                }
                return true
            }
            else -> return false
        }
    }

    /** Lève la marque du choix, puis rend le résultat (fil principal). */
    private fun finirChoix(choix: Choix, rendu: () -> Unit) {
        if (choixEnCours === choix) choixEnCours = null
        rendu()
    }

    /** Lève la marque de l'enregistrement, puis rend le résultat (fil principal). */
    private fun finirEnregistrement(enregistrement: Enregistrement, rendu: () -> Unit) {
        if (enregistrementEnCours === enregistrement) enregistrementEnCours = null
        rendu()
    }

    /** Lit le document choisi, hors du thread principal. */
    private fun lire(uri: Uri, choix: Choix) {
        try {
            val resolver = activity.contentResolver
            var nom = "fichier"
            var taille: Long? = null
            resolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
                null,
                null,
                null,
            )?.use { curseur ->
                if (curseur.moveToFirst()) {
                    val iNom = curseur.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (iNom >= 0 && !curseur.isNull(iNom)) nom = curseur.getString(iNom)
                    val iTaille = curseur.getColumnIndex(OpenableColumns.SIZE)
                    if (iTaille >= 0 && !curseur.isNull(iTaille)) taille = curseur.getLong(iTaille)
                }
            }
            val annoncee = taille
            if (annoncee != null && annoncee > choix.maxBytes) {
                // Refusé sans ouvrir le flux : Drive n'a rien à télécharger.
                rendre { finirChoix(choix) { choix.result.error("TOO_LARGE", "fichier trop gros", annoncee) } }
                return
            }
            val entree = resolver.openInputStream(uri)
                ?: throw IllegalStateException("flux indisponible")
            val sortie = ByteArrayOutputStream()
            val tampon = ByteArray(TAMPON)
            var total = 0L
            entree.use {
                while (total <= choix.maxBytes) {
                    val voulu = minOf(TAMPON.toLong(), choix.maxBytes + 1 - total).toInt()
                    val lus = it.read(tampon, 0, voulu)
                    if (lus < 0) break
                    sortie.write(tampon, 0, lus)
                    total += lus
                }
            }
            if (total > choix.maxBytes) {
                // Taille inconnue du fournisseur : la lecture s'arrête à la borne + 1 octet.
                rendre { finirChoix(choix) { choix.result.error("TOO_LARGE", "fichier trop gros", null) } }
                return
            }
            val octets = sortie.toByteArray()
            val nomLu = nom
            rendre { finirChoix(choix) { choix.result.success(mapOf("name" to nomLu, "bytes" to octets)) } }
        } catch (e: Exception) {
            rendre { finirChoix(choix) { choix.result.error("READ_FAILED", e.javaClass.simpleName, null) } }
        }
    }

    /** Écrit le document créé par ACTION_CREATE_DOCUMENT, hors du thread principal. */
    private fun ecrire(uri: Uri, enregistrement: Enregistrement) {
        try {
            val flux = activity.contentResolver.openOutputStream(uri, "wt")
                ?: throw IllegalStateException("flux indisponible")
            flux.use { it.write(enregistrement.bytes) }
            rendre { finirEnregistrement(enregistrement) { enregistrement.result.success(true) } }
        } catch (e: Exception) {
            rendre { finirEnregistrement(enregistrement) { enregistrement.result.error("WRITE_FAILED", e.javaClass.simpleName, null) } }
        }
    }

    private fun partager(call: MethodCall, result: MethodChannel.Result) {
        val nom = call.argument<String>("name")
        val mime = call.argument<String>("mimeType")
        val octets = call.argument<ByteArray>("bytes")
        if (nom == null || mime == null || octets == null) {
            result.error("INVALID_ARGUMENT", "argument absent", null)
            return
        }
        if (!nomValide(nom)) {
            result.error("INVALID_NAME", "nom de fichier refusé", null)
            return
        }
        if (occupe()) {
            result.error("ALREADY_ACTIVE", "choix, enregistrement ou partage en cours", null)
            return
        }
        partageEnCours = true
        executor.execute {
            try {
                // Dossier et chemin canonique hors du fil principal.
                val fichier = fichierExport(nom)
                if (fichier == null) {
                    rendre { terminerPartage { result.error("INVALID_NAME", "nom de fichier refusé", null) } }
                    return@execute
                }
                // Un seul fichier exporté à la fois.
                fichier.parentFile?.listFiles()?.forEach { it.delete() }
                fichier.writeBytes(octets)
                rendre { terminerPartage { ouvrirPartage(fichier, nom, mime, result) } }
            } catch (e: Exception) {
                rendre { terminerPartage { result.error("WRITE_FAILED", e.javaClass.simpleName, null) } }
            }
        }
    }

    /** Lève la marque du partage en cours, puis rend le résultat (fil principal). */
    private fun terminerPartage(rendu: () -> Unit) {
        partageEnCours = false
        rendu()
    }

    private fun ouvrirPartage(fichier: File, nom: String, mime: String, result: MethodChannel.Result) {
        try {
            val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.exports", fichier)
            val envoi = Intent(Intent.ACTION_SEND).apply {
                type = mime
                putExtra(Intent.EXTRA_STREAM, uri)
                clipData = ClipData.newRawUri(nom, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            activity.startActivity(Intent.createChooser(envoi, null))
            result.success(null)
        } catch (e: ActivityNotFoundException) {
            result.error("NO_PICKER", "aucune application de partage", null)
        } catch (e: Exception) {
            result.error("SHARE_FAILED", e.javaClass.simpleName, null)
        }
    }

    /** Nom vide, de plus de 120 caractères, avec /, \ ou .. : refusé. */
    private fun nomValide(nom: String) =
        nom.isNotBlank() && nom.length <= NOM_MAX &&
            !nom.contains('/') && !nom.contains('\\') && !nom.contains("..")

    /**
     * Fichier [nom] de cacheDir/exports/, ou null si le nom ou son chemin canonique en sort.
     * Appelé hors du fil principal (mkdirs, canonicalFile).
     */
    private fun fichierExport(nom: String): File? {
        if (!nomValide(nom)) return null
        val dossier = File(activity.cacheDir, DOSSIER_EXPORTS)
        if (!dossier.isDirectory && !dossier.mkdirs()) return null
        val fichier = File(dossier, nom).canonicalFile
        return if (fichier.parentFile == dossier.canonicalFile) fichier else null
    }
}
