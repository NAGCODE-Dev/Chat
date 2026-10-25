package com.example.chat_app

import android.app.role.RoleManager
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.view.KeyEvent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var player: MediaPlayer? = null
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "chat/screen",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "keepAwake" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    if (enabled) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "chat/audio",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "play" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.error("invalid_path", "Caminho de áudio inválido.", null)
                    } else {
                        play(path, result)
                    }
                }
                "stop" -> {
                    stopPlayback()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "chat/device",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isAssistantRoleHeld" -> result.success(isAssistantRoleHeld())
                "requestAssistantRole" -> requestAssistantRole(result)
                "hasNotificationAccess" -> result.success(hasNotificationAccess())
                "openNotificationSettings" -> {
                    startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                    result.success(null)
                }
                "openBatterySettings" -> {
                    startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                    result.success(null)
                }
                "openAutostartSettings" -> {
                    openAutostartSettings()
                    result.success(null)
                }
                "openAppSettings" -> {
                    startActivity(
                        Intent(
                            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.parse("package:$packageName"),
                        ),
                    )
                    result.success(null)
                }
                "recentNotifications" -> result.success(ChatNotificationListener.recent())
                "openApp" -> result.success(
                    openApp(call.argument<String>("target").orEmpty()),
                )
                "playMusic" -> result.success(
                    playMusic(call.argument<String>("target").orEmpty()),
                )
                "mediaControl" -> result.success(
                    mediaControl(call.argument<String>("target").orEmpty()),
                )
                "openUrl" -> result.success(
                    openUrl(call.argument<String>("target").orEmpty()),
                )
                else -> result.notImplemented()
            }
        }
    }

    private fun openAutostartSettings() {
        val candidates = listOf(
            Intent().setClassName(
                "com.miui.securitycenter",
                "com.miui.permcenter.autostart.AutoStartManagementActivity",
            ),
            Intent("miui.intent.action.OP_AUTO_START").addCategory(Intent.CATEGORY_DEFAULT),
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:$packageName"),
            ),
        )
        for (intent in candidates) {
            try {
                startActivity(intent)
                return
            } catch (_: Exception) {
                // Tenta a próxima opção; o aparelho pode não ter a tela da MIUI.
            }
        }
    }

    // --- assistente padrão ---

    private fun isAssistantRoleHeld(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
        val roleManager = getSystemService(RoleManager::class.java)
        return roleManager.isRoleAvailable(RoleManager.ROLE_ASSISTANT) &&
            roleManager.isRoleHeld(RoleManager.ROLE_ASSISTANT)
    }

    private fun requestAssistantRole(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.error(
                "unsupported",
                "Esta versão do Android não permite escolher o assistente padrão.",
                null,
            )
            return
        }
        val roleManager = getSystemService(RoleManager::class.java)
        if (!roleManager.isRoleAvailable(RoleManager.ROLE_ASSISTANT)) {
            result.error(
                "unavailable",
                "O aparelho não oferece o papel de assistente.",
                null,
            )
            return
        }
        if (roleManager.isRoleHeld(RoleManager.ROLE_ASSISTANT)) {
            result.success(true)
            return
        }
        startActivity(roleManager.createRequestRoleIntent(RoleManager.ROLE_ASSISTANT))
        result.success(false)
    }

    // --- notificações ---

    private fun hasNotificationAccess(): Boolean {
        val enabled = Settings.Secure.getString(
            contentResolver,
            "enabled_notification_listeners",
        ) ?: return false
        return enabled.split(":").any { it.startsWith(packageName) }
    }

    // --- aplicativos e mídia ---

    private fun openApp(target: String): String {
        if (target.isBlank()) return "Nome do aplicativo vazio."
        val pm = packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val activities = pm.queryIntentActivities(intent, 0)
        val wanted = normalize(target)
        val match = activities.firstOrNull {
            normalize(it.loadLabel(pm).toString()) == wanted
        } ?: activities.firstOrNull {
            normalize(it.loadLabel(pm).toString()).contains(wanted)
        } ?: activities.firstOrNull {
            it.activityInfo.packageName.equals(target, ignoreCase = true)
        }
        if (match == null) return "Aplicativo '$target' não encontrado."
        val launch = Intent(Intent.ACTION_MAIN)
            .addCategory(Intent.CATEGORY_LAUNCHER)
            .setClassName(match.activityInfo.packageName, match.activityInfo.name)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            startActivity(launch)
            "Abrindo ${match.loadLabel(pm)}."
        } catch (error: Exception) {
            "Não foi possível abrir ${match.loadLabel(pm)}: ${error.message}"
        }
    }

    private fun playMusic(target: String): String {
        val query = target.trim()
        if (query.isEmpty() || query.equals("play", true) || query.equals("tocar", true)) {
            return mediaControl("play_pause")
        }
        if (query.equals("pause", true) || query.equals("pausar", true)) {
            return mediaControl("pause")
        }
        val encoded = Uri.encode(query)
        val candidates = listOf(
            Triple("com.spotify.music", "spotify:search:$encoded", "Spotify"),
            Triple(
                "com.google.android.apps.youtube.music",
                "https://music.youtube.com/search?q=$encoded",
                "YouTube Music",
            ),
            Triple(
                "com.google.android.youtube",
                "https://www.youtube.com/results?search_query=$encoded",
                "YouTube",
            ),
        )
        for ((packageName, uri, label) in candidates) {
            if (!isPackageInstalled(packageName)) continue
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(uri))
                .setPackage(packageName)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                startActivity(intent)
                return "Abrindo $label com a busca por '$query'."
            } catch (_: Exception) {
                // Tenta o próximo aplicativo.
            }
        }
        val fallback = Intent(
            Intent.ACTION_VIEW,
            Uri.parse("https://www.youtube.com/results?search_query=$encoded"),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            startActivity(fallback)
            "Abrindo a busca por '$query' no navegador."
        } catch (_: Exception) {
            "Não encontrei um aplicativo de música para tocar '$query'."
        }
    }

    private fun mediaControl(target: String): String {
        val keyCode = when (target.lowercase()) {
            "next", "proxima", "próxima" -> KeyEvent.KEYCODE_MEDIA_NEXT
            "previous", "anterior", "voltar" -> KeyEvent.KEYCODE_MEDIA_PREVIOUS
            "stop", "parar" -> KeyEvent.KEYCODE_MEDIA_STOP
            "pause", "pausar" -> KeyEvent.KEYCODE_MEDIA_PAUSE
            "play", "tocar" -> KeyEvent.KEYCODE_MEDIA_PLAY
            else -> KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
        }
        val audio = getSystemService(AUDIO_SERVICE) as AudioManager
        audio.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
        audio.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_UP, keyCode))
        return "Mídia: ${target.ifBlank { "play/pause" }}."
    }

    private fun openUrl(target: String): String {
        val uri = Uri.parse(target)
        if (uri.scheme != "http" && uri.scheme != "https") {
            return "URL inválida."
        }
        return try {
            startActivity(
                Intent(Intent.ACTION_VIEW, uri)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            "Abrindo o link no navegador."
        } catch (error: Exception) {
            "Não foi possível abrir o link: ${error.message}"
        }
    }

    private fun isPackageInstalled(packageName: String): Boolean = try {
        packageManager.getPackageInfo(packageName, 0)
        true
    } catch (_: Exception) {
        false
    }

    private fun normalize(value: String): String {
        val builder = StringBuilder()
        for (character in value.lowercase()) {
            val mapped = when (character) {
                'á', 'à', 'â', 'ã', 'ä' -> 'a'
                'é', 'è', 'ê', 'ë' -> 'e'
                'í', 'ì', 'î', 'ï' -> 'i'
                'ó', 'ò', 'ô', 'õ', 'ö' -> 'o'
                'ú', 'ù', 'û', 'ü' -> 'u'
                'ç' -> 'c'
                'ñ' -> 'n'
                else -> character
            }
            if (mapped.isLetterOrDigit()) builder.append(mapped)
        }
        return builder.toString()
    }

    // --- reprodução de áudio do TTS ---

    private fun play(path: String, result: MethodChannel.Result) {
        // Interrompe uma reprodução anterior antes de iniciar a nova.
        stopPlayback(completePending = true)
        val mediaPlayer = MediaPlayer()
        player = mediaPlayer
        pendingResult = result
        try {
            mediaPlayer.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ASSISTANT)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build(),
            )
            mediaPlayer.setDataSource(path)
            mediaPlayer.setOnCompletionListener { finishPlayback(null) }
            mediaPlayer.setOnErrorListener { _, what, extra ->
                finishPlayback("Falha ao reproduzir áudio ($what/$extra).")
                true
            }
            mediaPlayer.prepare()
            mediaPlayer.start()
        } catch (error: Exception) {
            finishPlayback(error.message ?: "Falha ao reproduzir áudio.")
        }
    }

    private fun stopPlayback(completePending: Boolean = true) {
        val current = player
        player = null
        try {
            current?.stop()
        } catch (_: IllegalStateException) {
            // O player pode ainda não ter sido preparado.
        }
        current?.release()
        if (completePending) {
            val pending = pendingResult
            pendingResult = null
            pending?.success(null)
        }
    }

    private fun finishPlayback(error: String?) {
        val pending = pendingResult
        pendingResult = null
        val current = player
        player = null
        try {
            current?.release()
        } catch (_: Exception) {
            // Liberação best-effort.
        }
        if (error == null) {
            pending?.success(null)
        } else {
            pending?.error("playback_error", error, null)
        }
    }

    override fun onDestroy() {
        stopPlayback()
        super.onDestroy()
    }
}
