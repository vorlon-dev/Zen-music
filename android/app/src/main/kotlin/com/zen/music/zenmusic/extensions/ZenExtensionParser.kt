package com.zen.music.zenmusic.extensions

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import dalvik.system.DexClassLoader
import dev.brahmkshatriya.echo.common.clients.ExtensionClient
import dev.brahmkshatriya.echo.common.models.ExtensionType
import dev.brahmkshatriya.echo.common.models.ImportType
import dev.brahmkshatriya.echo.common.models.Metadata
import java.io.File

data class ParsedExtension(
    val metadata: Metadata,
    val client: ExtensionClient,
)

/** Parses extension APKs: manifest metadata → Metadata, DEX → client instance. */
class ZenExtensionParser(private val context: Context) {

    fun parse(file: File, importType: ImportType): Result<ParsedExtension> = runCatching {
        val metadata = parseManifest(file, importType)
        val client = loadFrom(metadata)
        ParsedExtension(metadata, client)
    }

    fun parseManifest(file: File, importType: ImportType): Metadata {
        val packageInfo = context.packageManager.getPackageArchiveInfo(
            file.absolutePath, PACKAGE_FLAGS
        ) ?: error("Failed to get package info for ${file.absolutePath}")
        val metaData = packageInfo.applicationInfo?.metaData
            ?: error("No metadata in ${file.absolutePath}")

        val type = packageInfo.reqFeatures
            ?.firstOrNull { it.name?.startsWith(FEATURE) == true }
            ?.let { ExtensionType.entries.first { e -> e.feature == it.name!!.substringAfter(FEATURE) } }
            ?: error("No extension feature declared")

        fun getOrNull(key: String) =
            metaData.getString(key)?.takeIf { it.isNotBlank() }
        fun get(key: String) = getOrNull(key)
            ?: error("$key not found in metadata for ${packageInfo.packageName}")

        return Metadata(
            path = file.absolutePath,
            preservedPackages = getOrNull("preserved_packages")
                .orEmpty().split(",").mapNotNull { it.trim().ifEmpty { null } },
            className = get("class"),
            importType = importType,
            type = type,
            id = get("id"),
            version = get("version"),
            icon = null, // icon_url wiring added with ImageHolder
            name = get("name"),
            description = get("description"),
            author = get("author"),
            authorUrl = getOrNull("author_url"),
            repoUrl = getOrNull("repo_url"),
            updateUrl = getOrNull("update_url"),
            isEnabled = metaData.getBoolean("enabled", true),
        )
    }

    private fun loadFrom(metadata: Metadata): ExtensionClient {
        val optimizedDir = File(context.cacheDir, "dex_opt").apply { mkdirs() }
        val loader = DexClassLoader(
            metadata.path,
            optimizedDir.absolutePath,
            null,
            context.classLoader,
        )
        val clazz = loader.loadClass(metadata.className)
        return clazz.getDeclaredConstructor().newInstance() as ExtensionClient
    }

    companion object {
        @Suppress("DEPRECATION")
        private val PACKAGE_FLAGS = PackageManager.GET_CONFIGURATIONS or
                PackageManager.GET_META_DATA or
                PackageManager.GET_SIGNATURES or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P)
                    PackageManager.GET_SIGNING_CERTIFICATES else 0

        private const val FEATURE = "dev.brahmkshatriya.echo."
    }
}