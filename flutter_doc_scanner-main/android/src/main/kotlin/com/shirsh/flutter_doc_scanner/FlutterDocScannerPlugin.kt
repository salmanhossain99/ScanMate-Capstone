package com.shirsh.flutter_doc_scanner


import android.app.Activity
import android.app.Application
import android.app.Application.ActivityLifecycleCallbacks
import android.content.Intent
import android.content.IntentSender
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Bundle
import android.util.Log
import androidx.activity.result.IntentSenderRequest
import androidx.core.app.ActivityCompat.startIntentSenderForResult
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import com.google.android.gms.common.api.CommonStatusCodes
import com.google.android.gms.tasks.Task
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.FlutterPlugin.FlutterPluginBinding
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.EventChannel.EventSink
import io.flutter.plugin.common.EventChannel.StreamHandler
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry.ActivityResultListener
import java.io.File
import java.io.FileOutputStream
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import android.content.ContentValues

class FlutterDocScannerPlugin : MethodCallHandler, ActivityResultListener,
    FlutterPlugin, ActivityAware {
    private var channel: MethodChannel? = null
    private var pluginBinding: FlutterPluginBinding? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var applicationContext: Application? = null
    private val CHANNEL = "flutter_doc_scanner"
    private var activity: Activity? = null
    private val TAG = FlutterDocScannerPlugin::class.java.simpleName

    private val REQUEST_CODE_SCAN = 213312
    private val REQUEST_CODE_SCAN_URI = 214412
    private val REQUEST_CODE_SCAN_IMAGES = 215512
    private val REQUEST_CODE_SCAN_PDF = 216612
    private lateinit var resultChannel: MethodChannel.Result
    private var lastMethodCall: MethodCall? = null

    override fun onMethodCall(call: MethodCall, result: Result) {
        resultChannel = result
        lastMethodCall = call
        val page = (call.arguments as? Map<*, *>)?.get("page") as? Int ?: 4

        when (call.method) {
            "getPlatformVersion" -> result.success("Android ${android.os.Build.VERSION.RELEASE}")
            "getScanDocuments" -> {
                // On Android, getScanDocumentsUri is the one that returns image paths
                // which is what the dart code expects.
                startDocumentScanUri(page)
            }
            "getScannedDocumentAsImages" -> startDocumentScanImages(page)
            "getScannedDocumentAsPdf" -> startDocumentScanPDF(page)
            "getScanDocumentsUri" -> startDocumentScanUri(page)
            else -> result.notImplemented()
        }
    }

    private fun startDocumentScan(page: Int = 4) {
        val options =
            GmsDocumentScannerOptions.Builder().setGalleryImportAllowed(true).setPageLimit(page)
                .setResultFormats(
                    GmsDocumentScannerOptions.RESULT_FORMAT_JPEG,
                    GmsDocumentScannerOptions.RESULT_FORMAT_PDF
                ).setScannerMode(GmsDocumentScannerOptions.SCANNER_MODE_FULL).build()
        val scanner = GmsDocumentScanning.getClient(options)
        val task: Task<IntentSender>? = activity?.let { scanner.getStartScanIntent(it) }
        task?.addOnSuccessListener { intentSender ->
            val intent = IntentSenderRequest.Builder(intentSender).build().intentSender
            try {

                startIntentSenderForResult(
                    activity!!,
                    intent,
                    REQUEST_CODE_SCAN,
                    null,
                    0,
                    0,
                    0,
                    null
                )
            } catch (e: Exception) {
                resultChannel.error("SCAN_ERROR", "Failed to start scanner", e.toString())
            }
        }?.addOnFailureListener { e ->
            resultChannel.error("SCAN_ERROR", "Failed to get scanner intent", e.toString())
        }
    }

    private fun startDocumentScanImages(page: Int = 4) {
        // Optimize options for speed
        val options = GmsDocumentScannerOptions.Builder()
            .setGalleryImportAllowed(false) // Disable gallery to speed up
            .setPageLimit(1) // Set to 1 page for faster processing
                .setResultFormats(
                GmsDocumentScannerOptions.RESULT_FORMAT_JPEG
            ) // Only JPEG format
            .setScannerMode(GmsDocumentScannerOptions.SCANNER_MODE_FULL)
            .build()
            
        val scanner = GmsDocumentScanning.getClient(options)
        val task: Task<IntentSender>? = activity?.let { scanner.getStartScanIntent(it) }
        task?.addOnSuccessListener { intentSender ->
            val intent = IntentSenderRequest.Builder(intentSender).build().intentSender
            try {
                startIntentSenderForResult(
                    activity!!,
                    intent,
                    REQUEST_CODE_SCAN_IMAGES,
                    null,
                    0,
                    0,
                    0,
                    null
                )
            } catch (e: Exception) {
                resultChannel.error("SCAN_ERROR", "Failed to start scanner for images", e.toString())
            }
        }?.addOnFailureListener { e ->
            resultChannel.error("SCAN_ERROR", "Failed to get scanner intent for images", e.toString())
        }
    }

    private fun startDocumentScanPDF(page: Int = 4) {
        // Performance logging
        val startTime = System.currentTimeMillis()
        Log.d(TAG, "Starting PDF scan with DIRECT PDF generation")
        
        // Get additional parameters if provided
        val maxResolution = (lastMethodCall?.arguments as? Map<*, *>)?.get("maxResolution") as? Int ?: 1800
        val quality = (lastMethodCall?.arguments as? Map<*, *>)?.get("quality") as? Int ?: 95
        
        Log.d(TAG, "PDF params: maxResolution=$maxResolution, quality=$quality")
        
        val options =
            GmsDocumentScannerOptions.Builder()
                .setGalleryImportAllowed(true)
                .setPageLimit(page)
                // Request ONLY PDF format for direct generation with NO intermediate processing
                .setResultFormats(GmsDocumentScannerOptions.RESULT_FORMAT_PDF)
                // Use full scanner mode for best results
                .setScannerMode(GmsDocumentScannerOptions.SCANNER_MODE_FULL)
                .build()
                
        Log.d(TAG, "PDF Scanner config: pageLimit=$page, mode=FULL, formats=PDF ONLY")
        
        val scanner = GmsDocumentScanning.getClient(options)
        val task: Task<IntentSender>? = activity?.let { scanner.getStartScanIntent(it) }
        task?.addOnSuccessListener { intentSender ->
            val intent = IntentSenderRequest.Builder(intentSender).build().intentSender
            try {
                Log.d(TAG, "Starting PDF scanner intent (elapsed: ${System.currentTimeMillis() - startTime}ms)")
                startIntentSenderForResult(
                    activity!!,
                    intent,
                    REQUEST_CODE_SCAN_PDF,
                    null,
                    0,
                    0,
                    0,
                    null
                )
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start PDF scanner: ${e.message}")
                resultChannel.error("SCAN_ERROR", "Failed to start scanner for PDF", e.toString())
            }
        }?.addOnFailureListener { e ->
            Log.e(TAG, "Failed to get PDF scanner intent: ${e.message}")
            resultChannel.error("SCAN_ERROR", "Failed to get scanner intent for PDF", e.toString())
        }
    }

    // Helper methods removed as we now handle file extraction directly in the PDF result handling

    private fun startDocumentScanUri(page: Int = 4) {
        // Performance logging
        val startTime = System.currentTimeMillis()
        Log.d(TAG, "Starting document scan with optimized settings (startTime: $startTime)")
        
        // Use optimized scanner options
        val options =
            GmsDocumentScannerOptions.Builder()
                .setGalleryImportAllowed(true) // Allow gallery import for flexibility
                .setPageLimit(page)
                // Request only JPEG for better performance - skip PDF processing by Google ML Kit
                .setResultFormats(GmsDocumentScannerOptions.RESULT_FORMAT_JPEG)
                // Use FULL scanner mode as FAST is not available in this version
                .setScannerMode(GmsDocumentScannerOptions.SCANNER_MODE_FULL)
                .build()
                
        Log.d(TAG, "Scanner config: pageLimit=$page, mode=FULL, format=JPEG")
        
        val scanner = GmsDocumentScanning.getClient(options)
        val task: Task<IntentSender>? = activity?.let { scanner.getStartScanIntent(it) }
        task?.addOnSuccessListener { intentSender ->
            val intent = IntentSenderRequest.Builder(intentSender).build().intentSender
            try {
                Log.d(TAG, "Starting scanner intent (elapsed: ${System.currentTimeMillis() - startTime}ms)")
                startIntentSenderForResult(
                    activity!!,
                    intent,
                    REQUEST_CODE_SCAN_URI,
                    null,
                    0,
                    0,
                    0,
                    null
                )
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start scanner: ${e.message}")
                resultChannel.error("SCAN_ERROR", "Failed to start scanner for URI", e.toString())
            }
        }?.addOnFailureListener { e ->
            Log.e(TAG, "Failed to get scanner intent: ${e.message}")
            resultChannel.error("SCAN_ERROR", "Failed to get scanner intent for URI", e.toString())
        }
    }


    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        when (requestCode) {
            REQUEST_CODE_SCAN -> {
                if (resultCode == Activity.RESULT_OK) {
                    val scanningResult = GmsDocumentScanningResult.fromActivityResultIntent(data)
                    scanningResult?.getPdf()?.let { pdf ->
                        val pdfUri = pdf.getUri()
                        val pageCount = pdf.getPageCount()
                        resultChannel.success(
                            mapOf(
                                "pdfUri" to pdfUri.toString(),
                                "pageCount" to pageCount,
                            )
                        )
                    } ?: resultChannel.error("SCAN_FAILED", "No PDF result returned", null)
                } else if (resultCode == Activity.RESULT_CANCELED) {
                    resultChannel.success(null)
                } else {
                    resultChannel.error("SCAN_FAILED", "Failed to start scanning", null)
                }
            }
            REQUEST_CODE_SCAN_IMAGES -> {
                if (resultCode == Activity.RESULT_OK) {
                    val scanningResult = GmsDocumentScanningResult.fromActivityResultIntent(data)
                    scanningResult?.getPages()?.let { pages ->
                        resultChannel.success(
                            mapOf(
                                "Uri" to pages.toString(),
                                "Count" to pages.size,
                            )
                        )
                    } ?: resultChannel.error("SCAN_FAILED", "No image results returned", null)
                } else if (resultCode == Activity.RESULT_CANCELED) {
                    resultChannel.success(null)
                }
            }
            REQUEST_CODE_SCAN_PDF -> {
                if (resultCode == Activity.RESULT_OK) {
                    // Performance logging
                    val processingStart = System.currentTimeMillis()
                    Log.d(TAG, "PDF scan completed, directly using ML Kit PDF result")
                    
                    val scanningResult = GmsDocumentScanningResult.fromActivityResultIntent(data)
                    
                    // We only requested PDF format, so we should only get a PDF
                    if (scanningResult?.getPdf() != null) {
                        val pdf = scanningResult.getPdf()!!
                        val pdfUri = pdf.getUri()
                        val pageCount = pdf.getPageCount()
                        
                        // Extract file path from URI with minimal processing - HIGH PRIORITY THREAD
                        Thread(Runnable {
                            // Copy the PDF file directly to cache
                            try {
                                val inputStream = activity?.contentResolver?.openInputStream(pdfUri)
                                if (inputStream == null) {
                                    Log.e(TAG, "Failed to open input stream for PDF")
                                    activity?.runOnUiThread {
                                        resultChannel.error("SCAN_ERROR", "Failed to open PDF file", null)
                                    }
                                    return@Runnable
                                }
                                
                                val fileName = "scan_pdf_direct_${System.currentTimeMillis()}.pdf"
                                val file = File(applicationContext!!.cacheDir, fileName)
                                
                                // Use buffered streams for better performance and reliability
                                val bufferedInput = BufferedInputStream(inputStream)
                                val outputStream = FileOutputStream(file)
                                val bufferedOutput = BufferedOutputStream(outputStream)
                                
                                // Copy using a buffer for better reliability
                                val buffer = ByteArray(8192) // 8KB buffer
                                var bytesRead: Int
                                var totalBytes = 0
                                
                                while (bufferedInput.read(buffer).also { bytesRead = it } != -1) {
                                    bufferedOutput.write(buffer, 0, bytesRead)
                                    totalBytes += bytesRead
                                }
                                
                                // Make sure all data is written
                                bufferedOutput.flush()
                                
                                // Close all streams properly
                                bufferedInput.close()
                                bufferedOutput.close()
                                outputStream.close()
                                inputStream.close()
                                
                                // Set file permissions to ensure it's readable
                                try {
                                    file.setReadable(true, false)
                                    file.setWritable(true)
                                } catch (e: Exception) {
                                    Log.w(TAG, "Failed to set file permissions: ${e.message}")
                                    // Continue anyway as this might not be fatal
                                }
                                
                                // Set MIME type for the ContentResolver to help external apps recognize the file
                                try {
                                    val contentValues = ContentValues().apply {
                                        put("mime_type", "application/pdf")
                                        put("_display_name", fileName)
                                    }
                                    val uri = activity?.contentResolver?.insert(
                                        android.provider.MediaStore.Files.getContentUri("external"),
                                        contentValues
                                    )
                                    
                                    uri?.let {
                                        val outputStream = activity?.contentResolver?.openOutputStream(it)
                                        outputStream?.use { os ->
                                            file.inputStream().use { input ->
                                                input.copyTo(os)
                                            }
                                        }
                                        Log.d(TAG, "Added file to MediaStore: $uri")
                                    }
                                } catch (e: Exception) {
                                    Log.w(TAG, "Failed to update MediaStore: ${e.message}")
                                    // Continue anyway as this is just for better Android integration
                                }
                                
                                // Verify file was created properly
                                if (!file.exists() || file.length() == 0L) {
                                    Log.e(TAG, "PDF file creation failed or file is empty")
                                    activity?.runOnUiThread {
                                        resultChannel.error("SCAN_ERROR", "Failed to create PDF file", null)
                                    }
                                    return@Runnable
                                }
                                
                                val fileSize = file.length() / 1024
                                Log.d(TAG, "Direct ML Kit PDF saved: ${file.path}, size: ${fileSize}KB, bytes: $totalBytes, time: ${System.currentTimeMillis() - processingStart}ms")
                                
                                activity?.runOnUiThread {
                        resultChannel.success(
                            mapOf(
                                            "pdfUri" to file.absolutePath,
                                "pageCount" to pageCount,
                                            "directPdf" to true,
                                            "fileSize" to fileSize
                            )
                        )
                                }
                            } catch (e: Exception) {
                                Log.e(TAG, "Error saving PDF: ${e.message}", e)
                                // Fall back to URI string if file extraction fails
                                activity?.runOnUiThread {
                                    resultChannel.error("SCAN_ERROR", "Failed to process PDF: ${e.message}", e.toString())
                                }
                            }
                        }).apply {
                            priority = Thread.MAX_PRIORITY
                            start()
                        }
                    } else {
                        // This should not happen since we only requested PDF format
                        resultChannel.error("SCAN_FAILED", "ML Kit did not return a PDF as requested", null)
                    }
                } else if (resultCode == Activity.RESULT_CANCELED) {
                    resultChannel.success(null)
                }
            }
            REQUEST_CODE_SCAN_URI -> {
                if (resultCode == Activity.RESULT_OK) {
                    val scanTimeEnd = System.currentTimeMillis()
                    Log.d(TAG, "Scan completed, processing results")
                    
                    val scanningResult = GmsDocumentScanningResult.fromActivityResultIntent(data)
                    scanningResult?.getPages()?.let { pages ->
                        // Performance logging
                        Log.d(TAG, "Got ${pages.size} pages from scanner")
                        
                        // Process images in a more efficient way
                        Thread {
                            val startProcessing = System.currentTimeMillis()
                            Log.d(TAG, "Starting image processing (bg thread)")
                            
                            // Use a more efficient processing method for images
                            val imagePaths = ArrayList<String>(pages.size)
                            
                            for (page in pages) {
                                // Process each page
                                val path = processScanResultFaster(page.imageUri)
                                if (path != null) {
                                    imagePaths.add(path)
                                }
                            }
                            
                            val endProcessing = System.currentTimeMillis()
                            Log.d(TAG, "Processed ${imagePaths.size} images in ${endProcessing - startProcessing}ms")
                            
                            activity?.runOnUiThread {
                                resultChannel.success(imagePaths)
                            }
                        }.start()
                    } ?: resultChannel.error("SCAN_FAILED", "No URI results returned", null)
                } else if (resultCode == Activity.RESULT_CANCELED) {
                    Log.d(TAG, "Scan cancelled by user")
                    resultChannel.success(null)
                }
            }
        }
        return false
    }
    
    /**
     * Process scan result with optimized parameters for faster processing
     */
    private fun processScanResultFaster(uri: Uri): String? {
        val startTime = System.currentTimeMillis()
        
        try {
            // Create a unique filename for the processed image
            val fileName = "scan_${System.currentTimeMillis()}.jpg"
            val file = File(applicationContext!!.cacheDir, fileName)
            
            // Get compression parameters with even more aggressive defaults
            val maxResolution = (lastMethodCall?.arguments as? Map<*, *>)?.get("maxResolution") as? Int ?: 800
            val quality = (lastMethodCall?.arguments as? Map<*, *>)?.get("quality") as? Int ?: 60
            
            Log.d(TAG, "Processing image with maxResolution=$maxResolution, quality=$quality")
            
            // Skip BitmapFactory.Options decoding step for faster processing
            // and directly load with a fixed scale
            val inputStream = activity?.contentResolver?.openInputStream(uri)
            
            // Create options for downsampling
            val options = BitmapFactory.Options().apply {
                inSampleSize = 2  // Fixed downsample by 2x for better performance
                inPreferredConfig = Bitmap.Config.RGB_565  // Use less memory
            }
            
            // Decode bitmap with options
            val bitmap = BitmapFactory.decodeStream(inputStream, null, options)
            inputStream?.close()
            
            if (bitmap != null) {
                // Compress directly to file
                val outputStream = FileOutputStream(file)
                bitmap.compress(Bitmap.CompressFormat.JPEG, quality, outputStream)
                outputStream.close()
                bitmap.recycle()
                
                val endTime = System.currentTimeMillis()
                Log.d(TAG, "Image processed in ${endTime - startTime}ms, path: ${file.path}, size: ${file.length() / 1024}KB")
                
                return file.path
            } else {
                Log.e(TAG, "Failed to decode bitmap from URI: $uri")
                return null
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error processing scan result: ${e.message}")
            return null
        }
    }

    /**
     * Process scan result with high quality parameters for better PDF output
     */
    private fun processHighQualityScanResult(uri: Uri): String? {
        val startTime = System.currentTimeMillis()
        
        try {
            // Create a unique filename for the processed image
            val fileName = "scan_hq_${System.currentTimeMillis()}.jpg"
            val file = File(applicationContext!!.cacheDir, fileName)
            
            // Get compression parameters with high quality defaults
            val maxResolution = (lastMethodCall?.arguments as? Map<*, *>)?.get("maxResolution") as? Int ?: 1800
            val quality = (lastMethodCall?.arguments as? Map<*, *>)?.get("quality") as? Int ?: 95
            
            Log.d(TAG, "Processing high quality image with maxResolution=$maxResolution, quality=$quality")
            
            // Open the input stream
            val inputStream = activity?.contentResolver?.openInputStream(uri)
            
            // Get the image dimensions without loading the full bitmap
            val options = BitmapFactory.Options().apply {
                inJustDecodeBounds = true
            }
            BitmapFactory.decodeStream(inputStream, null, options)
            inputStream?.close()
            
            // Calculate inSampleSize while maintaining high quality
            val imageHeight = options.outHeight
            val imageWidth = options.outWidth
            var inSampleSize = 1
            
            if (imageHeight > maxResolution || imageWidth > maxResolution) {
                val halfHeight = imageHeight / 2
                val halfWidth = imageWidth / 2
                
                // Gradually reduce sample size to maintain quality
                while ((halfHeight / inSampleSize) >= maxResolution && (halfWidth / inSampleSize) >= maxResolution) {
                    inSampleSize *= 2
                }
                
                // Ensure we don't over-downsample
                if (inSampleSize > 1) {
                    inSampleSize /= 2
                }
            }
            
            // Load the image with the calculated sample size
            options.inJustDecodeBounds = false
            options.inSampleSize = inSampleSize
            options.inPreferredConfig = Bitmap.Config.ARGB_8888 // Use full color for high quality
            
            val inputStream2 = activity?.contentResolver?.openInputStream(uri)
            val bitmap = BitmapFactory.decodeStream(inputStream2, null, options)
            inputStream2?.close()
            
            if (bitmap != null) {
                // Compress with high quality
                val outputStream = FileOutputStream(file)
                bitmap.compress(Bitmap.CompressFormat.JPEG, quality, outputStream)
                outputStream.close()
                bitmap.recycle()
                
                val fileSize = file.length() / 1024
                val endTime = System.currentTimeMillis()
                Log.d(TAG, "High quality image processed in ${endTime - startTime}ms, path: ${file.path}, size: ${fileSize}KB")
                
                return file.path
            } else {
                // If decoding failed, try to copy the file directly
                Log.d(TAG, "Bitmap decoding failed, copying file directly")
                val inputStream3 = activity?.contentResolver?.openInputStream(uri)
                val outputStream = FileOutputStream(file)
                inputStream3?.copyTo(outputStream)
                inputStream3?.close()
                outputStream.close()
                
                return file.path
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error processing high quality scan result: ${e.message}")
            return null
        }
    }

    override fun onAttachedToEngine(binding: FlutterPluginBinding) {
        pluginBinding = binding
        applicationContext = binding.applicationContext as Application
    }

    override fun onDetachedFromEngine(binding: FlutterPluginBinding) {
        pluginBinding = null
        channel?.setMethodCallHandler(null)
        channel = null
    }

    override fun onDetachedFromActivityForConfigChanges() {
        onDetachedFromActivity()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addActivityResultListener(this)

        channel = MethodChannel(
            pluginBinding!!.binaryMessenger,
            CHANNEL
        )
        channel?.setMethodCallHandler(this)
    }

    override fun onDetachedFromActivity() {
        activity = null
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
    }

    private fun copyFileToAppDir(uri: Uri): String? {
        return try {
            val inputStream = activity?.contentResolver?.openInputStream(uri)
            val fileName = "scan_${System.currentTimeMillis()}.jpg"
            val file = File(applicationContext!!.cacheDir, fileName)
            val outputStream = FileOutputStream(file)
            
            // Get compression parameters from lastMethodCall instead of call
            val maxResolution = (lastMethodCall?.arguments as? Map<*, *>)?.get("maxResolution") as? Int ?: 1200
            val quality = (lastMethodCall?.arguments as? Map<*, *>)?.get("quality") as? Int ?: 80
            
            // Use BitmapFactory to decode and compress the image
            val options = BitmapFactory.Options().apply {
                inJustDecodeBounds = true
            }
            BitmapFactory.decodeStream(inputStream, null, options)
            inputStream?.close()
            
            // Calculate inSampleSize to resize image to maxResolution
            val imageHeight = options.outHeight
            val imageWidth = options.outWidth
            var inSampleSize = 1
            
            if (imageHeight > maxResolution || imageWidth > maxResolution) {
                val halfHeight = imageHeight / 2
                val halfWidth = imageWidth / 2
                
                while ((halfHeight / inSampleSize) >= maxResolution && 
                       (halfWidth / inSampleSize) >= maxResolution) {
                    inSampleSize *= 2
                }
            }
            
            // Decode with inSampleSize
            options.inJustDecodeBounds = false
            options.inSampleSize = inSampleSize
            
            val inputStream2 = activity?.contentResolver?.openInputStream(uri)
            val bitmap = BitmapFactory.decodeStream(inputStream2, null, options)
            inputStream2?.close()
            
            // Compress and save bitmap
            if (bitmap != null) {
                bitmap.compress(Bitmap.CompressFormat.JPEG, quality, outputStream)
                bitmap.recycle()
            } else {
                // Fallback to direct copy if bitmap processing fails
                val inputStream3 = activity?.contentResolver?.openInputStream(uri)
                inputStream3?.copyTo(outputStream)
                inputStream3?.close()
            }
            
            outputStream.close()
            file.absolutePath
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }
}