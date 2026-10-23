package com.swanlab.audiox64

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var visualizerPlugin: VisualizerPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        visualizerPlugin = VisualizerPlugin(flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onDestroy() {
        visualizerPlugin?.dispose()
        visualizerPlugin = null
        super.onDestroy()
    }
}