package com.example.mediaconverter.api

import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.asRequestBody
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.util.concurrent.TimeUnit

class MediaConverterApi(private val serverUrl: String) {
    companion object {
        private const val TAG = "MediaConverterApi"
    }
    
    private val client = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(300, TimeUnit.SECONDS)
        .writeTimeout(300, TimeUnit.SECONDS)
        .build()
    
    data class ConversionResult(
        val success: Boolean,
        val outputUrl: String?,
        val metadata: Map<String, Any>?
    )
    
    // GIF/비디오를 MP4/WebM으로 변환
    suspend fun convertVideo(
        file: File,
        format: String,
        progressCallback: (Float) -> Unit = {}
    ): ConversionResult? = withContext(Dispatchers.IO) {
        try {
            val requestBody = MultipartBody.Builder()
                .setType(MultipartBody.FORM)
                .addFormDataPart(
                    "video",
                    file.name,
                    file.asRequestBody("image/gif".toMediaType())
                )
                .addFormDataPart("format", format)
                .addFormDataPart("resolution", "640x480")
                .addFormDataPart("fps", "10")
                .build()
            
            val request = Request.Builder()
                .url("$serverUrl/convert/video")
                .post(requestBody)
                .build()
            
            val response = client.newCall(request).execute()
            
            if (response.isSuccessful) {
                val responseBody = response.body?.string()
                val json = JSONObject(responseBody ?: "{}")
                
                return@withContext ConversionResult(
                    success = json.optBoolean("success", false),
                    outputUrl = json.optString("outputUrl")?.let { "$serverUrl$it" },
                    metadata = parseMetadata(json.optJSONObject("metadata"))
                )
            } else {
                Log.e(TAG, "Server error: ${response.code}")
                return@withContext null
            }
        } catch (e: Exception) {
            Log.e(TAG, "Conversion error", e)
            return@withContext null
        }
    }
    
    // 비디오 해상도 변환 (320p, 720p)
    suspend fun resizeVideo(
        file: File,
        resolution: String,
        progressCallback: (Float) -> Unit = {}
    ): ConversionResult? = withContext(Dispatchers.IO) {
        try {
            val requestBody = MultipartBody.Builder()
                .setType(MultipartBody.FORM)
                .addFormDataPart(
                    "video",
                    file.name,
                    file.asRequestBody("video/mp4".toMediaType())
                )
                .addFormDataPart("resolution", resolution)
                .build()
            
            val request = Request.Builder()
                .url("$serverUrl/resize/video")
                .post(requestBody)
                .build()
            
            val response = client.newCall(request).execute()
            
            if (response.isSuccessful) {
                val responseBody = response.body?.string()
                val json = JSONObject(responseBody ?: "{}")
                
                return@withContext ConversionResult(
                    success = json.optBoolean("success", false),
                    outputUrl = json.optString("outputUrl")?.let { "$serverUrl$it" },
                    metadata = parseMetadata(json.optJSONObject("metadata"))
                )
            } else {
                Log.e(TAG, "Resize error: ${response.code}")
                return@withContext null
            }
        } catch (e: Exception) {
            Log.e(TAG, "Resize error", e)
            return@withContext null
        }
    }
    
    // 비디오를 GIF로 변환
    suspend fun convertToGif(
        file: File,
        fps: String = "10",
        scale: String = "320",
        duration: String = "10",
        progressCallback: (Float) -> Unit = {}
    ): ConversionResult? = withContext(Dispatchers.IO) {
        try {
            val requestBody = MultipartBody.Builder()
                .setType(MultipartBody.FORM)
                .addFormDataPart(
                    "video",
                    file.name,
                    file.asRequestBody("video/mp4".toMediaType())
                )
                .addFormDataPart("fps", fps)
                .addFormDataPart("scale", scale)
                .addFormDataPart("duration", duration)
                .build()
            
            val request = Request.Builder()
                .url("$serverUrl/convert/to-gif")
                .post(requestBody)
                .build()
            
            val response = client.newCall(request).execute()
            
            if (response.isSuccessful) {
                val responseBody = response.body?.string()
                val json = JSONObject(responseBody ?: "{}")
                
                return@withContext ConversionResult(
                    success = json.optBoolean("success", false),
                    outputUrl = json.optString("outputUrl")?.let { "$serverUrl$it" },
                    metadata = parseMetadata(json.optJSONObject("metadata"))
                )
            } else {
                Log.e(TAG, "GIF conversion error: ${response.code}")
                return@withContext null
            }
        } catch (e: Exception) {
            Log.e(TAG, "GIF conversion error", e)
            return@withContext null
        }
    }
    
    // 오디오 추출
    suspend fun extractAudio(
        file: File,
        format: String = "mp3",
        progressCallback: (Float) -> Unit = {}
    ): ConversionResult? = withContext(Dispatchers.IO) {
        try {
            val requestBody = MultipartBody.Builder()
                .setType(MultipartBody.FORM)
                .addFormDataPart(
                    "video",
                    file.name,
                    file.asRequestBody("video/mp4".toMediaType())
                )
                .addFormDataPart("format", format)
                .build()
            
            val request = Request.Builder()
                .url("$serverUrl/extract/audio")
                .post(requestBody)
                .build()
            
            val response = client.newCall(request).execute()
            
            if (response.isSuccessful) {
                val responseBody = response.body?.string()
                val json = JSONObject(responseBody ?: "{}")
                
                return@withContext ConversionResult(
                    success = json.optBoolean("success", false),
                    outputUrl = json.optString("outputUrl")?.let { "$serverUrl$it" },
                    metadata = null
                )
            } else {
                Log.e(TAG, "Audio extraction error: ${response.code}")
                return@withContext null
            }
        } catch (e: Exception) {
            Log.e(TAG, "Audio extraction error", e)
            return@withContext null
        }
    }
    
    // 변환된 파일 다운로드
    suspend fun downloadFile(url: String): ByteArray? = withContext(Dispatchers.IO) {
        try {
            val request = Request.Builder()
                .url(url)
                .build()
            
            val response = client.newCall(request).execute()
            
            if (response.isSuccessful) {
                return@withContext response.body?.bytes()
            } else {
                Log.e(TAG, "Download error: ${response.code}")
                return@withContext null
            }
        } catch (e: Exception) {
            Log.e(TAG, "Download error", e)
            return@withContext null
        }
    }
    
    // WebSocket을 통한 실시간 진행률 모니터링
    fun connectWebSocket(onProgress: (Float) -> Unit) {
        val wsUrl = serverUrl.replace("http://", "ws://")
        val request = Request.Builder()
            .url(wsUrl)
            .build()
        
        val webSocket = client.newWebSocket(request, object : WebSocketListener() {
            override fun onMessage(webSocket: WebSocket, text: String) {
                try {
                    val json = JSONObject(text)
                    if (json.optString("type") == "progress") {
                        val progressData = json.optJSONObject("data")
                        val percent = progressData?.optDouble("percent", 0.0) ?: 0.0
                        onProgress((percent / 100).toFloat())
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "WebSocket message error", e)
                }
            }
            
            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                Log.e(TAG, "WebSocket error", t)
            }
        })
    }
    
    private fun parseMetadata(json: JSONObject?): Map<String, Any>? {
        if (json == null) return null
        
        val metadata = mutableMapOf<String, Any>()
        json.keys().forEach { key ->
            metadata[key] = json.opt(key)
        }
        return metadata
    }
}