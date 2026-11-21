package com.example.alert_app

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import kotlin.math.abs

/** A touchable system window used when an alert fires over another app. */
object AlarmHudOverlay {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var windowManager: WindowManager? = null
    private var overlayView: View? = null
    @Volatile private var isDismissed = false

    fun show(
        context: Context,
        title: String,
        message: String,
        symbol: String,
        triggerPrice: Double,
        onDismiss: () -> Unit
    ) {
        val appContext = context.applicationContext
        mainHandler.post {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
                !Settings.canDrawOverlays(appContext)
            ) return@post

            isDismissed = false
            removeView()
            val manager = appContext.getSystemService(Context.WINDOW_SERVICE) as WindowManager
            val view = createView(appContext, title, message, symbol, triggerPrice, onDismiss)
            val windowType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            }
            val params = WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                windowType,
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_DIM_BEHIND,
                PixelFormat.TRANSLUCENT
            ).apply {
                gravity = Gravity.CENTER
                dimAmount = 0.58f
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    layoutInDisplayCutoutMode =
                        WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
                }
            }

            try {
                manager.addView(view, params)
                windowManager = manager
                overlayView = view
            } catch (_: Throwable) {
                // The Android full-screen notification remains available if the
                // user has revoked overlay access or the OS refuses this window.
            }
        }
    }

    fun dismiss() {
        mainHandler.post { removeView() }
    }

    private fun createView(
        context: Context,
        title: String,
        message: String,
        symbol: String,
        triggerPrice: Double,
        onDismiss: () -> Unit
    ): View {
        val root = FrameLayout(context).apply {
            setBackgroundColor(Color.argb(208, 0, 0, 0))
            isClickable = true
        }
        val card = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(context, 24), dp(context, 28), dp(context, 24), dp(context, 24))
            background = GradientDrawable().apply {
                setColor(Color.rgb(24, 24, 28))
                cornerRadius = dp(context, 26).toFloat()
                setStroke(dp(context, 1), Color.rgb(77, 77, 85))
            }
            elevation = dp(context, 18).toFloat()
        }
        val label = text(context, "TENX  •  PRICE ALERT", 12, Color.rgb(10, 132, 255), true)
        val heading = text(context, title, 20, Color.WHITE, true).apply {
            gravity = Gravity.CENTER
        }
        val instrument = text(context, symbol.ifBlank { "MARKET ALERT" }, 15, Color.LTGRAY, true)
        val price = if (triggerPrice > 0.0) {
            text(context, triggerPrice.toString(), 34, Color.WHITE, true, Typeface.MONOSPACE)
        } else null
        val details = text(context, message, 15, Color.LTGRAY, false).apply {
            gravity = Gravity.CENTER
        }
        val swipe = text(context, "Swipe horizontally to dismiss or tap button below", 13, Color.rgb(180, 180, 190), false).apply {
            gravity = Gravity.CENTER
            setPadding(0, dp(context, 8), 0, dp(context, 8))
        }
        val dismissButton = TextView(context).apply {
            text = "STOP ALARM  ·  DISMISS"
            textSize = 15f
            setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setPadding(dp(context, 14), dp(context, 15), dp(context, 14), dp(context, 15))
            background = GradientDrawable().apply {
                setColor(Color.rgb(220, 53, 69))
                cornerRadius = dp(context, 14).toFloat()
            }
            setOnClickListener { dismissAndNotify(onDismiss) }
        }

        card.addView(label, verticalParams(context, 0))
        card.addView(heading, verticalParams(context, 12))
        card.addView(instrument, verticalParams(context, 8))
        if (price != null) card.addView(price, verticalParams(context, 8))
        card.addView(details, verticalParams(context, 8))
        card.addView(swipe, verticalParams(context, 18))
        card.addView(dismissButton, verticalParams(context, 8))

        val cardParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.WRAP_CONTENT,
            Gravity.CENTER
        ).apply {
            leftMargin = dp(context, 22)
            rightMargin = dp(context, 22)
        }
        root.addView(card, cardParams)

        // Setup smooth, crash-safe swipe dismissal
        val swipeThreshold = dp(context, 75).toFloat()
        var downX = 0f
        var downY = 0f
        var isDragging = false
        val buttonRect = Rect()

        card.setOnTouchListener { v, event ->
            // Let the dismiss button process its own clicks directly
            dismissButton.getGlobalVisibleRect(buttonRect)
            if (buttonRect.contains(event.rawX.toInt(), event.rawY.toInt())) {
                if (!isDragging) {
                    return@setOnTouchListener false
                }
            }

            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downX = event.rawX
                    downY = event.rawY
                    isDragging = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - downX
                    val dy = event.rawY - downY
                    if (!isDragging && abs(dx) > dp(context, 10) && abs(dx) > abs(dy)) {
                        isDragging = true
                    }
                    if (isDragging) {
                        v.translationX = dx
                        val progress = (abs(dx) / (v.width.toFloat().coerceAtLeast(1f))).coerceIn(0f, 1f)
                        v.alpha = (1f - (progress * 0.7f)).coerceIn(0.2f, 1f)
                        root.alpha = (1f - (progress * 0.4f)).coerceIn(0.3f, 1f)
                        true
                    } else {
                        false
                    }
                }
                MotionEvent.ACTION_UP -> {
                    if (isDragging) {
                        val dx = event.rawX - downX
                        if (abs(dx) >= swipeThreshold) {
                            // Fling off-screen smoothly, then safely dismiss
                            val targetX = if (dx > 0) v.width.toFloat() * 1.5f else -v.width.toFloat() * 1.5f
                            v.animate()
                                .translationX(targetX)
                                .alpha(0f)
                                .setDuration(180)
                                .setListener(object : AnimatorListenerAdapter() {
                                    override fun onAnimationEnd(animation: Animator) {
                                        dismissAndNotify(onDismiss)
                                    }
                                })
                                .start()
                        } else {
                            // Snap back with smooth spring
                            v.animate().translationX(0f).alpha(1f).setDuration(200).start()
                            root.animate().alpha(1f).setDuration(200).start()
                        }
                        isDragging = false
                        true
                    } else {
                        false
                    }
                }
                MotionEvent.ACTION_CANCEL -> {
                    v.animate().translationX(0f).alpha(1f).setDuration(200).start()
                    root.animate().alpha(1f).setDuration(200).start()
                    isDragging = false
                    false
                }
                else -> false
            }
        }

        return root
    }

    private fun dismissAndNotify(onDismiss: () -> Unit) {
        mainHandler.post {
            if (isDismissed) return@post
            isDismissed = true
            try {
                onDismiss()
            } catch (_: Throwable) {}
            removeView()
        }
    }

    private fun removeView() {
        val view = overlayView ?: return
        overlayView = null
        val manager = windowManager
        windowManager = null
        try {
            manager?.removeView(view)
        } catch (_: Throwable) {}
    }

    private fun text(
        context: Context,
        value: String,
        size: Int,
        color: Int,
        bold: Boolean,
        family: Typeface? = null
    ) = TextView(context).apply {
        text = value
        textSize = size.toFloat()
        setTextColor(color)
        if (family != null) typeface = family else if (bold) typeface = Typeface.DEFAULT_BOLD
        gravity = Gravity.CENTER
    }

    private fun verticalParams(context: Context, topMarginDp: Int) =
        LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply { topMargin = dp(context, topMarginDp) }

    private fun dp(context: Context, value: Int): Int =
        (value * context.resources.displayMetrics.density).toInt()
}
