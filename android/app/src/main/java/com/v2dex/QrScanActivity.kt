package com.v2dex

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Bundle
import android.provider.MediaStore
import android.view.Gravity
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.camera.core.CameraSelector
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import java.util.concurrent.Executors

class QrScanActivity : ComponentActivity() {
  private val cameraExecutor = Executors.newSingleThreadExecutor()
  private var completed = false

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)

    if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
      ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.CAMERA), CAMERA_PERMISSION_REQUEST)
      return
    }

    startCamera()
  }

  override fun onRequestPermissionsResult(
      requestCode: Int,
      permissions: Array<String>,
      grantResults: IntArray
  ) {
    super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    if (requestCode == CAMERA_PERMISSION_REQUEST && grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
      startCamera()
    } else {
      setResult(RESULT_CANCELED)
      finish()
    }
  }

  override fun onDestroy() {
    cameraExecutor.shutdown()
    super.onDestroy()
  }

  private fun startCamera() {
    val previewView = PreviewView(this).apply {
      scaleType = PreviewView.ScaleType.FILL_CENTER
    }
    val hint =
        TextView(this).apply {
          text = "Scan QR"
          setTextColor(0xffffffff.toInt())
          textSize = 18f
          gravity = Gravity.CENTER
          background = roundedBackground(0x66000000, 18)
          setPadding(dp(24), dp(14), dp(24), dp(14))
        }
    val galleryButton =
        ImageView(this).apply {
          contentDescription = "Choose QR image"
          setImageResource(R.drawable.gallery_white)
          scaleType = ImageView.ScaleType.CENTER_INSIDE
          background = roundedBackground(0x99000000.toInt(), 22)
          setPadding(dp(18), dp(10), dp(18), dp(12))
          setOnClickListener {
            val intent =
                Intent(Intent.ACTION_PICK, MediaStore.Images.Media.EXTERNAL_CONTENT_URI).apply {
                  type = "image/*"
                }
            startActivityForResult(intent, QR_IMAGE_REQUEST_CODE)
          }
        }
    val root = FrameLayout(this)
    root.addView(previewView, FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT)
    root.addView(
        hint,
        FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT)
            .apply {
              gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
              topMargin = dp(72)
            })
    root.addView(
        galleryButton,
        FrameLayout.LayoutParams(dp(76), dp(76))
            .apply {
              gravity = Gravity.BOTTOM or Gravity.START
              leftMargin = dp(36)
              bottomMargin = dp(48)
            })
    applyCameraSafeInsets(root, hint, galleryButton)
    setContentView(root)
    root.post { ViewCompat.requestApplyInsets(root) }

    val cameraProviderFuture = ProcessCameraProvider.getInstance(this)
    cameraProviderFuture.addListener(
        {
          val cameraProvider = cameraProviderFuture.get()
          val preview = Preview.Builder().build().also {
            it.setSurfaceProvider(previewView.surfaceProvider)
          }
          val analyzer =
              ImageAnalysis.Builder()
                  .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                  .build()
                  .also {
                    it.setAnalyzer(cameraExecutor) { imageProxy -> scanImage(imageProxy) }
                  }

          cameraProvider.unbindAll()
          cameraProvider.bindToLifecycle(this, CameraSelector.DEFAULT_BACK_CAMERA, preview, analyzer)
        },
        ContextCompat.getMainExecutor(this))
  }

  private fun applyCameraSafeInsets(root: FrameLayout, hint: TextView, galleryButton: ImageView) {
    val baseTopMargin = dp(72)
    val baseBottomMargin = dp(48)

    ViewCompat.setOnApplyWindowInsetsListener(root) { _, insets ->
      val systemBars = insets.getInsets(WindowInsetsCompat.Type.systemBars())

      (hint.layoutParams as FrameLayout.LayoutParams).apply {
        topMargin = systemBars.top + baseTopMargin
        hint.layoutParams = this
      }

      (galleryButton.layoutParams as FrameLayout.LayoutParams).apply {
        bottomMargin = systemBars.bottom + baseBottomMargin
        galleryButton.layoutParams = this
      }

      insets
    }
  }

  private fun roundedBackground(color: Int, radiusDp: Int): GradientDrawable =
      GradientDrawable().apply {
        setColor(color)
        cornerRadius = dp(radiusDp).toFloat()
      }

  private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

  override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
    super.onActivityResult(requestCode, resultCode, data)
    if (requestCode == QR_IMAGE_REQUEST_CODE) {
      val uri = data?.data
      if (resultCode == RESULT_OK && uri != null) {
        decodeQrFromImage(uri)
      }
    }
  }

  @OptIn(ExperimentalGetImage::class)
  private fun scanImage(imageProxy: ImageProxy) {
    val mediaImage = imageProxy.image
    if (mediaImage == null || completed) {
      imageProxy.close()
      return
    }

    val image = InputImage.fromMediaImage(mediaImage, imageProxy.imageInfo.rotationDegrees)
    BarcodeScanning.getClient()
        .process(image)
        .addOnSuccessListener { barcodes ->
          val value =
              barcodes.firstOrNull { it.valueType == Barcode.TYPE_URL || !it.rawValue.isNullOrBlank() }?.rawValue
          if (!value.isNullOrBlank()) {
            complete(value)
          }
        }
        .addOnCompleteListener {
          imageProxy.close()
        }
  }

  private fun decodeQrFromImage(uri: Uri) {
    if (completed) {
      return
    }

    val image = InputImage.fromFilePath(this, uri)
    BarcodeScanning.getClient()
        .process(image)
        .addOnSuccessListener { barcodes ->
          val value = barcodes.firstOrNull { !it.rawValue.isNullOrBlank() }?.rawValue
          if (!value.isNullOrBlank()) {
            complete(value)
          }
        }
  }

  private fun complete(value: String) {
    if (completed) {
      return
    }

    completed = true
    setResult(RESULT_OK, Intent().putExtra(EXTRA_QR_VALUE, value))
    finish()
  }

  companion object {
    const val EXTRA_QR_VALUE = "qrValue"
    private const val CAMERA_PERMISSION_REQUEST = 8101
    private const val QR_IMAGE_REQUEST_CODE = 8102
  }
}
