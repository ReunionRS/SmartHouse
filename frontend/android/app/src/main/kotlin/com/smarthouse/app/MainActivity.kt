package com.smarthouse.app

import android.hardware.biometrics.BiometricManager
import android.hardware.biometrics.BiometricPrompt
import android.os.Build
import android.os.CancellationSignal
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "smart_house/biometrics")
            .setMethodCallHandler { call, result ->
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
                    result.success(false)
                    return@setMethodCallHandler
                }
                val manager = getSystemService(BiometricManager::class.java)
                if (call.method == "isAvailable") {
                    result.success(manager.canAuthenticate() == BiometricManager.BIOMETRIC_SUCCESS)
                    return@setMethodCallHandler
                }
                if (call.method == "authenticate") {
                    val reason = call.argument<String>("reason")
                        ?: "Подтвердите вход в Smart House"
                    val prompt = BiometricPrompt.Builder(this)
                        .setTitle("Smart House")
                        .setSubtitle(reason)
                        .setNegativeButton("Отмена", mainExecutor) { _, _ -> }
                        .build()
                    prompt.authenticate(
                        CancellationSignal(),
                        mainExecutor,
                        object : BiometricPrompt.AuthenticationCallback() {
                            override fun onAuthenticationSucceeded(
                                authenticationResult: BiometricPrompt.AuthenticationResult
                            ) {
                                result.success(true)
                            }

                            override fun onAuthenticationError(
                                errorCode: Int,
                                errString: CharSequence
                            ) {
                                result.success(false)
                            }
                        }
                    )
                    return@setMethodCallHandler
                }
                result.notImplemented()
            }
    }
}
