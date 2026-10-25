package com.example.chat_app

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log

/// Guarda em memória as notificações mais recentes para o chat.
///
/// O serviço só recebe eventos depois que a pessoa concede a permissão em
/// Configurações > Notificações > Acesso a notificações. Nada é enviado para
/// fora do aparelho além do resumo incluído no contexto da conversa.
class ChatNotificationListener : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification) {
        Log.d("ChatNotificationListener", "onNotificationPosted: ${sbn.packageName}")
        if (sbn.packageName == packageName) return
        val extras = sbn.notification.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)
            ?.toString()?.trim().orEmpty()
        val text = (
            extras.getCharSequence(Notification.EXTRA_BIG_TEXT)
                ?: extras.getCharSequence(Notification.EXTRA_TEXT)
            )?.toString()?.trim().orEmpty()
        if (title.isEmpty() && text.isEmpty()) return
        val app = try {
            val info = packageManager.getApplicationInfo(sbn.packageName, 0)
            packageManager.getApplicationLabel(info).toString()
        } catch (_: Exception) {
            sbn.packageName
        }
        synchronized(notifications) {
            notifications.removeAll {
                it["package"] == sbn.packageName &&
                    it["title"] == title &&
                    it["text"] == text
            }
            notifications.addFirst(
                mapOf(
                    "app" to app,
                    "package" to sbn.packageName,
                    "title" to title,
                    "text" to text,
                    "time" to sbn.postTime,
                ),
            )
            while (notifications.size > 30) {
                notifications.removeLast()
            }
        }
    }

    companion object {
        private val notifications = ArrayDeque<Map<String, Any>>()

        fun recent(): List<Map<String, Any>> = synchronized(notifications) {
            notifications.toList()
        }
    }
}
