package com.lxmusic.lx_music_flutter

import android.service.notification.NotificationListenerService

/**
 * 空实现的 NotificationListenerService�? * 仅用于让 MediaSessionManager.getActiveSessions(componentName) 返回�?app �?MediaSession�? * �?MediaSessionHelper 可以直接更新 metadata（车机蓝牙歌词依赖）�? */
class LxNotificationListener : NotificationListenerService()
