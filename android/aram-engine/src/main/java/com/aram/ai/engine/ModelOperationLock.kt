package com.aram.ai.engine

import kotlinx.coroutines.sync.Mutex

/**
 * Shared synchronization lock for model lifecycle and file operations.
 */
object ModelOperationLock {
    val mutex = Mutex()
}
