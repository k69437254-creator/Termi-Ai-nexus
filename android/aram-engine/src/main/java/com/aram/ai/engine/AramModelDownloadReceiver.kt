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

        ModelFiles.reconcileCompletedDownload(context)
    }
}
