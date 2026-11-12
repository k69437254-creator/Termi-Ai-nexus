package com.aram.ai.engine

import android.app.DownloadManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.aram.ai.data.AppPrefs
import com.aram.ai.data.ModelFiles

class AramModelDownloadReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != DownloadManager.ACTION_DOWNLOAD_COMPLETE) return
        val id = intent.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1L)
        if (id < 0L || id != AppPrefs.downloadId(context)) return

        val manager = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        val cursor = runCatching { manager.query(DownloadManager.Query().setFilterById(id)) }.getOrNull()
        var successful = false
        var reason = "تعذر إكمال تنزيل النموذج"
        cursor?.use {
            if (it.moveToFirst()) {
                val status = it.getInt(it.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
                val code = it.getInt(it.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON))
                successful = status == DownloadManager.STATUS_SUCCESSFUL
                if (!successful) reason = "فشل تنزيل نموذج Aram AI (رمز DownloadManager: $code)"
            }
        }

        if (successful && ModelFiles.finalizeDownload(context)) {
            AppPrefs.setDownloadId(context, -1L)
            AppPrefs.setEngineState(context, "STOPPED", "اكتمل تنزيل النموذج؛ يجري تجهيز محرك Aram AI عند أول طلب")
            context.startForegroundService(Intent(context, AramEngineService::class.java).setAction(AramEngineService.ACTION_START))
        } else {
            AppPrefs.setEngineState(context, "ERROR", reason)
        }
    }
}
