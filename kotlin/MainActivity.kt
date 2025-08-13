package com.example.mediaconverter

import android.Manifest
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.util.Log
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import coil.compose.rememberAsyncImagePainter
import coil.decode.GifDecoder
import coil.decode.VideoFrameDecoder
import coil.request.ImageRequest
import com.example.mediaconverter.api.MediaConverterApi
import com.example.mediaconverter.ui.theme.MediaConverterTheme
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.database.FirebaseDatabase
import com.google.firebase.database.ServerValue
import kotlinx.coroutines.launch
import java.io.File

class MainActivity : ComponentActivity() {
    companion object {
        private const val TAG = "MediaConverter"
        private const val REQUEST_PERMISSION = 100
        
        // 서버 URL - 에뮬레이터: 10.0.2.2, 실제 기기: Mac IP
        const val SERVER_URL = "http://10.0.2.2:3000" // 에뮬레이터용
        // const val SERVER_URL = "http://192.168.1.7:3000" // 실제 기기용
    }

    private val mediaConverterApi = MediaConverterApi(SERVER_URL)
    private val auth = FirebaseAuth.getInstance()
    private val database = FirebaseDatabase.getInstance()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // 권한 체크
        checkPermissions()
        
        setContent {
            MediaConverterTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    MediaConverterScreen()
                }
            }
        }
    }

    @Composable
    fun MediaConverterScreen() {
        var selectedMediaUri by remember { mutableStateOf<Uri?>(null) }
        var isConverting by remember { mutableStateOf(false) }
        var conversionProgress by remember { mutableStateOf(0f) }
        var errorMessage by remember { mutableStateOf<String?>(null) }
        var convertedUrl by remember { mutableStateOf<String?>(null) }
        var mediaType by remember { mutableStateOf(MediaType.NONE) }
        
        val context = LocalContext.current
        val coroutineScope = rememberCoroutineScope()
        
        // 미디어 선택 런처
        val mediaPickerLauncher = rememberLauncherForActivityResult(
            contract = ActivityResultContracts.GetContent()
        ) { uri: Uri? ->
            uri?.let {
                selectedMediaUri = it
                // 미디어 타입 판별
                val mimeType = contentResolver.getType(it)
                mediaType = when {
                    mimeType?.startsWith("image/gif") == true -> MediaType.GIF
                    mimeType?.startsWith("video/") == true -> MediaType.VIDEO
                    else -> MediaType.NONE
                }
                Log.d(TAG, "Selected media: $it, type: $mediaType")
            }
        }
        
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(16.dp)
                .verticalScroll(rememberScrollState()),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Text(
                text = "Media Converter",
                style = MaterialTheme.typography.headlineLarge
            )
            
            // 미디어 미리보기
            selectedMediaUri?.let { uri ->
                Card(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(200.dp)
                ) {
                    when (mediaType) {
                        MediaType.GIF, MediaType.VIDEO -> {
                            Image(
                                painter = rememberAsyncImagePainter(
                                    ImageRequest.Builder(context)
                                        .data(uri)
                                        .decoderFactory(if (mediaType == MediaType.GIF) GifDecoder.Factory() else VideoFrameDecoder.Factory())
                                        .build()
                                ),
                                contentDescription = "Selected media",
                                modifier = Modifier.fillMaxSize(),
                                contentScale = ContentScale.Fit
                            )
                        }
                        else -> {}
                    }
                }
                
                Text(
                    text = "Type: ${mediaType.name}",
                    style = MaterialTheme.typography.bodyMedium
                )
            }
            
            // 미디어 선택 버튼
            Button(
                onClick = { mediaPickerLauncher.launch("*/*") },
                modifier = Modifier.fillMaxWidth()
            ) {
                Text("Select Media (GIF/Video)")
            }
            
            // 변환 옵션 버튼들
            when (mediaType) {
                MediaType.GIF -> {
                    // GIF → MP4/WebM 변환
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Button(
                            onClick = {
                                coroutineScope.launch {
                                    convertGifToVideo(selectedMediaUri!!, "mp4")
                                }
                            },
                            enabled = !isConverting,
                            modifier = Modifier.weight(1f)
                        ) {
                            Text("To MP4")
                        }
                        
                        Button(
                            onClick = {
                                coroutineScope.launch {
                                    convertGifToVideo(selectedMediaUri!!, "webm")
                                }
                            },
                            enabled = !isConverting,
                            modifier = Modifier.weight(1f)
                        ) {
                            Text("To WebM")
                        }
                    }
                }
                
                MediaType.VIDEO -> {
                    // 비디오 해상도 변환
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Button(
                            onClick = {
                                coroutineScope.launch {
                                    resizeVideo(selectedMediaUri!!, "320p")
                                }
                            },
                            enabled = !isConverting,
                            modifier = Modifier.weight(1f)
                        ) {
                            Text("320p")
                        }
                        
                        Button(
                            onClick = {
                                coroutineScope.launch {
                                    resizeVideo(selectedMediaUri!!, "720p")
                                }
                            },
                            enabled = !isConverting,
                            modifier = Modifier.weight(1f)
                        ) {
                            Text("720p")
                        }
                    }
                    
                    // 비디오 → GIF 변환
                    Button(
                        onClick = {
                            coroutineScope.launch {
                                convertVideoToGif(selectedMediaUri!!)
                            }
                        },
                        enabled = !isConverting,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text("Convert to GIF")
                    }
                }
                
                else -> {}
            }
            
            // 진행 상태
            if (isConverting) {
                CircularProgressIndicator()
                Text("Converting... ${(conversionProgress * 100).toInt()}%")
            }
            
            // 에러 메시지
            errorMessage?.let { error ->
                Card(
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.errorContainer
                    ),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(
                        text = error,
                        modifier = Modifier.padding(16.dp),
                        color = MaterialTheme.colorScheme.onErrorContainer
                    )
                }
            }
            
            // 변환 결과
            convertedUrl?.let { url ->
                Card(
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.primaryContainer
                    ),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Column(
                        modifier = Modifier.padding(16.dp)
                    ) {
                        Text(
                            text = "✅ Conversion Complete!",
                            style = MaterialTheme.typography.titleMedium,
                            color = MaterialTheme.colorScheme.onPrimaryContainer
                        )
                        Text(
                            text = url,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onPrimaryContainer
                        )
                    }
                }
            }
        }
    }
    
    private suspend fun convertGifToVideo(uri: Uri, format: String) {
        isConverting = true
        errorMessage = null
        
        try {
            val file = getFileFromUri(uri)
            val result = mediaConverterApi.convertVideo(file, format) { progress ->
                conversionProgress = progress
            }
            
            result?.let {
                convertedUrl = it.outputUrl
                // Firebase에 업로드
                uploadToFirebase(it.outputUrl, format, it.metadata)
            }
        } catch (e: Exception) {
            errorMessage = "Conversion failed: ${e.message}"
            Log.e(TAG, "Conversion error", e)
        } finally {
            isConverting = false
        }
    }
    
    private suspend fun resizeVideo(uri: Uri, resolution: String) {
        isConverting = true
        errorMessage = null
        
        try {
            val file = getFileFromUri(uri)
            val result = mediaConverterApi.resizeVideo(file, resolution) { progress ->
                conversionProgress = progress
            }
            
            result?.let {
                convertedUrl = it.outputUrl
                uploadToFirebase(it.outputUrl, "mp4-$resolution", it.metadata)
            }
        } catch (e: Exception) {
            errorMessage = "Resize failed: ${e.message}"
            Log.e(TAG, "Resize error", e)
        } finally {
            isConverting = false
        }
    }
    
    private suspend fun convertVideoToGif(uri: Uri) {
        isConverting = true
        errorMessage = null
        
        try {
            val file = getFileFromUri(uri)
            val result = mediaConverterApi.convertToGif(file) { progress ->
                conversionProgress = progress
            }
            
            result?.let {
                convertedUrl = it.outputUrl
                uploadToFirebase(it.outputUrl, "gif", it.metadata)
            }
        } catch (e: Exception) {
            errorMessage = "GIF conversion failed: ${e.message}"
            Log.e(TAG, "GIF conversion error", e)
        } finally {
            isConverting = false
        }
    }
    
    private fun uploadToFirebase(url: String, format: String, metadata: Map<String, Any>?) {
        val userId = auth.currentUser?.uid ?: "anonymous"
        val ref = database.reference.child("converted_media").child(userId).push()
        
        val data = hashMapOf<String, Any>(
            "url" to url,
            "format" to format,
            "timestamp" to ServerValue.TIMESTAMP
        )
        
        metadata?.let { data.putAll(it) }
        
        ref.setValue(data)
            .addOnSuccessListener {
                Log.d(TAG, "Firebase upload success")
                Toast.makeText(this, "Saved to Firebase!", Toast.LENGTH_SHORT).show()
            }
            .addOnFailureListener { e ->
                Log.e(TAG, "Firebase upload failed", e)
            }
    }
    
    private fun getFileFromUri(uri: Uri): File {
        val inputStream = contentResolver.openInputStream(uri)
        val tempFile = File.createTempFile("media", null, cacheDir)
        tempFile.outputStream().use { output ->
            inputStream?.copyTo(output)
        }
        return tempFile
    }
    
    private fun checkPermissions() {
        val permissions = arrayOf(
            Manifest.permission.READ_EXTERNAL_STORAGE,
            Manifest.permission.INTERNET
        )
        
        val permissionsToRequest = permissions.filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }
        
        if (permissionsToRequest.isNotEmpty()) {
            ActivityCompat.requestPermissions(
                this,
                permissionsToRequest.toTypedArray(),
                REQUEST_PERMISSION
            )
        }
    }
    
    enum class MediaType {
        NONE, GIF, VIDEO
    }
}