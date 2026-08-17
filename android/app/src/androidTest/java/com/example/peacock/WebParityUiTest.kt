package com.example.peacock

import android.Manifest
import android.graphics.Bitmap
import android.os.SystemClock
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertIsNotDisplayed
import androidx.compose.ui.test.assertTextContains
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performScrollToIndex
import androidx.compose.ui.test.performTextClearance
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTextReplacement
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeLeft
import androidx.compose.ui.unit.dp
import com.example.peacock.ui.MainActivity
import androidx.test.rule.GrantPermissionRule
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.espresso.Espresso.onView
import androidx.test.espresso.UiController
import androidx.test.espresso.ViewAction
import androidx.test.espresso.matcher.ViewMatchers.isAssignableFrom
import org.hamcrest.Matcher
import org.junit.Rule
import org.junit.rules.RuleChain
import org.junit.rules.TestRule
import android.content.pm.ActivityInfo
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class WebParityUiTest {
    private val permissionRule = GrantPermissionRule.grant(
        Manifest.permission.BLUETOOTH_SCAN,
        Manifest.permission.BLUETOOTH_CONNECT,
    )
    private val composeRule = createAndroidComposeRule<MainActivity>()

    @get:Rule
    val rules: TestRule = RuleChain.outerRule(permissionRule).around(composeRule)

    @Test
    fun temporaryShareLabelFollowsSelectedLanguage() {
        selectLanguage("ZH_CN", "开始扫描")
        composeRule.onNodeWithText("临时分享").assertIsDisplayed()
        assertTrue(composeRule.onAllNodes(hasText("一時共有")).fetchSemanticsNodes().isEmpty())

        selectLanguage("JA_JP", "スキャン開始")
        composeRule.onNodeWithText("一時共有").assertIsDisplayed()
        assertTrue(composeRule.onAllNodes(hasText("临时分享")).fetchSemanticsNodes().isEmpty())
    }

    @Test
    fun multilingualDemo_coversAllWebPagesAndControls() {
        selectLanguage("ZH_CN", "开始扫描")
        selectLanguage("JA_JP", "スキャン開始")

        composeRule.onNodeWithTag("debug-toggle").performClick()
        composeRule.onNodeWithTag("open-demo").performClick()

        composeRule.onNodeWithTag("detail-tab-console").assertIsDisplayed()
        composeRule.onNodeWithTag("detail-tab-palette").assertIsDisplayed()
        composeRule.onNodeWithTag("detail-tab-help").assertIsDisplayed()
        composeRule.onNodeWithTag("console-page").assertIsDisplayed()

        composeRule.onNodeWithTag("scene-card").performScrollTo().assertIsDisplayed()
        composeRule.onNodeWithTag("scene-mode-4").performClick()
        composeRule.onNodeWithTag("scene-speed").performTouchInput { swipeLeft() }
        composeRule.onNodeWithTag("apply-scene").performClick()

        composeRule.onNodeWithTag("global-light-card").performScrollTo().assertIsDisplayed()
        composeRule.onNodeWithTag("global-brightness").performTouchInput { swipeLeft() }
        composeRule.onNodeWithTag("apply-global").performClick()

        composeRule.onNodeWithTag("all-groups-card").performScrollTo().assertIsDisplayed()
        composeRule.onNodeWithTag("all-groups-mode-3").performClick()
        composeRule.onNodeWithTag("all-groups-strobe-speed").performTouchInput { swipeLeft() }
        composeRule.onNodeWithTag("all-groups-apply").performClick()

        composeRule.onNodeWithTag("advanced-toggle").performScrollTo().performClick()
        composeRule.onNodeWithTag("group-card-7").performScrollTo().assertIsDisplayed()
        composeRule.onNodeWithTag("group-7-mode-3").performClick()
        composeRule.onNodeWithTag("group-7-apply").performClick()

        composeRule.onNodeWithTag("detail-tab-palette").performClick()
        composeRule.onNodeWithTag("palette-page").assertIsDisplayed()
        composeRule.onNodeWithText("THE IDOLM@STER").performScrollTo().performClick()
        composeRule.onNodeWithTag("palette-page").performScrollToIndex(1)
        composeRule.onNodeWithTag("project-logo-imas_765as").performScrollTo().assertIsDisplayed()

        composeRule.onNodeWithTag("palette-page").performScrollToIndex(0)
        composeRule.onNodeWithText("VOCALOID / バーチャルシンガー").performScrollTo().performClick()
        composeRule.waitForIdle()
        composeRule.onNodeWithTag("palette-page").performScrollToIndex(1)
        composeRule.onNodeWithTag("palette-group-vocaloid_zh").performScrollTo().performClick()
        composeRule.waitForIdle()
        composeRule.onNodeWithTag("palette-page").performScrollToIndex(3)
        composeRule.onNodeWithTag("palette-character-vocaloid_luo_tianyi").assertIsDisplayed()
        saveScreenshot("vocaloid-${composeRule.activity.resources.configuration.fontScale}")

        composeRule.onNodeWithTag("detail-tab-help").performClick()
        composeRule.onNodeWithTag("help-page").assertIsDisplayed()
        composeRule.onNodeWithTag("ota-update-card").assertIsDisplayed()
        saveScreenshot("ota-update-${composeRule.activity.resources.configuration.fontScale}")
        composeRule.onNodeWithTag("help-page").performScrollToIndex(7)
        composeRule.onNodeWithTag("help-section-6").assertIsDisplayed()
        composeRule.onNodeWithTag("help-script-example").performScrollTo().assertIsDisplayed()
        composeRule.onNodeWithTag("ota-update-card").assertIsNotDisplayed()
        saveScreenshot("effect-guide-${composeRule.activity.resources.configuration.fontScale}")
        composeRule.onNodeWithTag("detail-back").performClick()
        composeRule.onNodeWithTag("open-demo").assertIsDisplayed()
    }

    @Test
    fun rotationAndBack_keepTheAppUsable() {
        composeRule.activityRule.scenario.onActivity {
            it.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
        }
        composeRule.waitForIdle()
        composeRule.onNodeWithTag("debug-toggle").assertIsDisplayed()

        composeRule.activityRule.scenario.onActivity {
            it.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        }
        composeRule.waitForIdle()
        composeRule.onNodeWithTag("debug-toggle").assertIsDisplayed()
    }

    @Test
    fun customPalette_opensRuntimeFifthCategoryAndEditor() {
        composeRule.onNodeWithTag("debug-toggle").performClick()
        composeRule.onNodeWithTag("open-demo").performClick()
        composeRule.onNodeWithTag("detail-tab-palette").performClick()
        composeRule.onNodeWithTag("palette-franchise-custom").performScrollTo().performClick()
        composeRule.onNodeWithTag("custom-palette-add").performScrollTo().performClick()
        composeRule.onNodeWithTag("custom-palette-editor").assertIsDisplayed()
        saveScreenshot("custom-palette-dialog-${composeRule.activity.resources.configuration.fontScale}")
    }

    @Test
    fun effectProgramming_opensBlockAndOfflineScriptEditors() {
        composeRule.onNodeWithTag("debug-toggle").performClick()
        composeRule.onNodeWithTag("open-demo").performClick()
        composeRule.onNodeWithTag("detail-tab-effects").performClick()
        composeRule.onNodeWithTag("effects-page").assertIsDisplayed()
        composeRule.onNodeWithTag("effect-new-script").performScrollTo().performClick()
        composeRule.onNodeWithTag("effect-name-dialog").assertIsDisplayed()
        composeRule.onNodeWithTag("effect-name-zh").performTextInput("代码显示测试")
        composeRule.onNodeWithTag("effect-name-ja").performTextInput("コード表示テスト")
        saveScreenshot("effect-name-dialog-${composeRule.activity.resources.configuration.fontScale}")
        composeRule.onNodeWithTag("effect-name-create-confirm").performClick()
        composeRule.onNodeWithTag("effect-script-editor").assertIsDisplayed()
        composeRule.onNodeWithTag("effect-script-native-editor").assertIsDisplayed()
        composeRule.onNodeWithTag("effect-script-source")
            .assertTextContains("effect", substring = true)
        composeRule.onNodeWithTag("effect-editor-preview")
            .assertIsDisplayed()
            .assertHeightIsAtLeast(48.dp)
        composeRule.onNodeWithTag("effect-editor-play")
            .assertIsDisplayed()
            .assertHeightIsAtLeast(48.dp)
        val displayHeight = composeRule.activity.resources.displayMetrics.heightPixels.toFloat()
        val previewBounds = composeRule.onNodeWithTag("effect-editor-preview")
            .fetchSemanticsNode().boundsInWindow
        val playBounds = composeRule.onNodeWithTag("effect-editor-play")
            .fetchSemanticsNode().boundsInWindow
        check(previewBounds.bottom <= displayHeight + 1f) {
            "Preview button extends below the physical display: $previewBounds / $displayHeight"
        }
        check(playBounds.bottom <= displayHeight + 1f) {
            "Play button extends below the physical display: $playBounds / $displayHeight"
        }
        composeRule.onNode(hasTestTag("effect-script-source") and hasSetTextAction())
            .assertIsDisplayed()
        Thread.sleep(600)
        saveScreenshot("effect-script-${composeRule.activity.resources.configuration.fontScale}")
        composeRule.onNodeWithTag("effect-editor-save").performClick()
        composeRule.onNodeWithTag("effect-editor-close").performClick()
        composeRule.onNodeWithTag("effect-rename-代码显示测试").performScrollTo().performClick()
        composeRule.onNodeWithTag("effect-name-dialog").assertIsDisplayed()
        composeRule.onNodeWithTag("effect-name-zh").performTextClearance()
        composeRule.onNodeWithTag("effect-name-zh").performTextInput("代码显示测试-已重命名")
        composeRule.onNodeWithTag("effect-name-rename-confirm").performClick()
        composeRule.waitUntil(timeoutMillis = 5_000) {
            composeRule.onAllNodes(
                hasText("代码显示测试-已重命名") or hasText("コード表示テスト"),
            )
                .fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onAllNodes(hasText("复制为代码") or hasText("コード化"))[0]
            .performScrollTo()
            .performClick()
        composeRule.onNodeWithTag("effect-script-editor").assertIsDisplayed()
        composeRule.onNodeWithTag("effect-script-source")
            .assertTextContains("effect", substring = true)
    }

    @Test
    fun longScriptError_isSingleLanguageAndKeepsBottomActionsVisible() {
        composeRule.onNodeWithTag("debug-toggle").performClick()
        composeRule.onNodeWithTag("open-demo").performClick()
        composeRule.onNodeWithTag("detail-tab-effects").performClick()
        composeRule.onNodeWithTag("effect-new-script").performScrollTo().performClick()
        composeRule.onNodeWithTag("effect-name-zh").performTextInput("长代码错误测试")
        composeRule.onNodeWithTag("effect-name-ja").performTextInput("長いコードのテスト")
        composeRule.onNodeWithTag("effect-name-create-confirm").performClick()

        composeRule.onNode(hasTestTag("effect-script-source") and hasSetTextAction())
            .performTextReplacement(
                """
                effect "长代码错误测试" {
                    let arm: number = 0;
                    group;
                }
                """.trimIndent(),
            )
        composeRule.onNodeWithTag("effect-editor-preview").performClick()
        composeRule.onNodeWithTag("effect-editor-error").assertIsDisplayed()
        composeRule.onNodeWithText(
            "group后需要",
            substring = true,
            useUnmergedTree = true,
        ).assertIsDisplayed()
        assertTrue(
            composeRule.onAllNodes(hasText("groupの後に", substring = true))
                .fetchSemanticsNodes()
                .isEmpty(),
        )

        val displayHeight = composeRule.activity.resources.displayMetrics.heightPixels.toFloat()
        listOf("effect-editor-preview", "effect-editor-play").forEach { tag ->
            val bounds = composeRule.onNodeWithTag(tag)
                .assertIsDisplayed()
                .assertHeightIsAtLeast(48.dp)
                .fetchSemanticsNode()
                .boundsInWindow
            check(bounds.bottom <= displayHeight + 1f) {
                "$tag extends below the physical display: $bounds / $displayHeight"
            }
        }
        saveScreenshot("effect-script-single-language-error")
    }

    @Test
    fun effectBlockEditor_bottomControlsStayInsidePhysicalDisplay() {
        composeRule.onNodeWithTag("debug-toggle").performClick()
        composeRule.onNodeWithTag("open-demo").performClick()
        composeRule.onNodeWithTag("detail-tab-effects").performClick()
        composeRule.onNodeWithTag("effect-edit-红→绿→蓝").performScrollTo().performClick()
        composeRule.onNodeWithTag("effect-block-editor").assertIsDisplayed()
        val webView = captureWebView()
        composeRule.waitUntil(timeoutMillis = 5_000) {
            evaluateBoolean(
                webView,
                "(window.MauryaEditor?.save() || '').includes('maurya_start')",
            )
        }

        val metrics = composeRule.activity.resources.displayMetrics
        val displayWidth = metrics.widthPixels
        val displayHeight = metrics.heightPixels.toFloat()
        saveScreenshot("effect-block-before-bounds-${displayWidth}x${displayHeight.toInt()}")
        listOf("effect-editor-preview", "effect-editor-play").forEach { tag ->
            val node = composeRule.onNodeWithTag(tag)
                .assertIsDisplayed()
                .assertHeightIsAtLeast(48.dp)
            val bounds = node.fetchSemanticsNode().boundsInWindow
            check(bounds.top >= 0f) {
                "$tag starts above the physical display: $bounds / $displayHeight"
            }
            check(bounds.bottom <= displayHeight + 1f) {
                "$tag extends below the physical display: $bounds / $displayHeight"
            }
        }
        saveScreenshot("effect-block-bottom-${displayWidth}x${displayHeight.toInt()}")
    }

    @Test
    fun effectBlockEditor_realAndroidWebViewTapOpensColourPanel() {
        composeRule.onNodeWithTag("debug-toggle").performClick()
        composeRule.onNodeWithTag("open-demo").performClick()
        composeRule.onNodeWithTag("detail-tab-effects").performClick()
        composeRule.onNodeWithTag("effect-edit-红→绿→蓝").performScrollTo().performClick()
        composeRule.onNodeWithTag("effect-block-editor").assertIsDisplayed()
        composeRule.onNodeWithTag("effect-editor-preview")
            .assertIsDisplayed()
            .assertHeightIsAtLeast(48.dp)
        composeRule.onNodeWithTag("effect-editor-play")
            .assertIsDisplayed()
            .assertHeightIsAtLeast(48.dp)

        val webView = captureWebView()
        composeRule.waitUntil(timeoutMillis = 5_000) {
            evaluateBoolean(
                webView,
                "(window.MauryaEditor?.save() || '').includes('maurya_start')",
            )
        }
        val target = evaluateArray(
            webView,
            """
            (() => {
              const field = [...document.querySelectorAll('.blocklyEditableField')]
                .find(node => !node.querySelector('text') && node.querySelector('rect'));
              if (!field) return [];
              const rect = field.getBoundingClientRect();
              return [rect.left + rect.width / 2, rect.top + rect.height / 2, window.innerWidth];
            })()
            """.trimIndent(),
        )
        check(target.length() == 3) { "No rendered Blockly colour field found" }
        tapWebViewAtCssPoint(webView, target)
        composeRule.waitUntil(timeoutMillis = 5_000) {
            !evaluateBoolean(webView, "document.getElementById('field-editor').hidden")
        }
        assertFalse(
            "Colour editor remained hidden after a real Android WebView tap",
            evaluateBoolean(webView, "document.getElementById('field-editor').hidden"),
        )
        val panelBounds = evaluateArray(
            webView,
            """
            (() => {
              const panel = document.querySelector('#field-editor .field-editor__panel');
              const rect = panel.getBoundingClientRect();
              return [rect.top, rect.bottom, window.innerHeight, rect.width];
            })()
            """.trimIndent(),
        )
        check(panelBounds.getDouble(0) >= 0.0) { "Colour editor top is clipped: $panelBounds" }
        check(panelBounds.getDouble(1) <= panelBounds.getDouble(2) + 1.0) {
            "Colour editor bottom is clipped: $panelBounds"
        }
        check(panelBounds.getDouble(3) > 0.0) { "Colour editor did not render" }
        SystemClock.sleep(500)
        saveScreenshot("effect-block-colour-open-${composeRule.activity.resources.configuration.fontScale}")
        SystemClock.sleep(600)
        val orangePreset = evaluateArray(
            webView,
            """
            (() => {
              const node = document.querySelector('.colour-preset[aria-label="#FF9500"]');
              const rect = node.getBoundingClientRect();
              return [rect.left + rect.width / 2, rect.top + rect.height / 2, window.innerWidth];
            })()
            """.trimIndent(),
        )
        tapWebViewAtCssPoint(webView, orangePreset)
        composeRule.waitUntil(timeoutMillis = 5_000) {
            evaluateBoolean(webView, "document.getElementById('field-colour-hex').value === '#FF9500'")
        }
        val applyButton = evaluateArray(
            webView,
            """
            (() => {
              const node = document.getElementById('field-editor-confirm');
              const rect = node.getBoundingClientRect();
              return [rect.left + rect.width / 2, rect.top + rect.height / 2, window.innerWidth];
            })()
            """.trimIndent(),
        )
        tapWebViewAtCssPoint(webView, applyButton)
        composeRule.waitUntil(timeoutMillis = 5_000) {
            evaluateBoolean(webView, "document.getElementById('field-editor').hidden")
        }
        assertTrue(
            "Selecting a preset and applying did not update the Blockly field",
            evaluateBoolean(webView, "window.MauryaEditor.save().toLowerCase().includes('#ff9500')"),
        )

        evaluateBoolean(
            webView,
            """
            (() => {
              document.getElementById('control-zoom-in').click();
              document.getElementById('control-zoom-in').click();
              return true;
            })()
            """.trimIndent(),
        )
        val pan = evaluateArray(
            webView,
            """
            (() => {
              const background = document.querySelector('.blocklyMainBackground');
              const canvas = document.querySelector('.blocklyBlockCanvas');
              const rect = background.getBoundingClientRect();
              return [
                rect.left + rect.width * .65,
                rect.top + rect.height * .78,
                rect.left + rect.width * .45,
                rect.top + rect.height * .68,
                window.innerWidth,
                canvas.getAttribute('transform') || ''
              ];
            })()
            """.trimIndent(),
        )
        swipeWebViewAtCssPoints(webView, pan)
        composeRule.waitUntil(timeoutMillis = 5_000) {
            val before = JSONObject.quote(pan.getString(5))
            evaluateBoolean(
                webView,
                "(document.querySelector('.blocklyBlockCanvas').getAttribute('transform') || '') !== $before",
            )
        }
        assertTrue(
            "Dragging empty Blockly workspace did not pan the canvas",
            evaluateBoolean(
                webView,
                "(document.querySelector('.blocklyBlockCanvas').getAttribute('transform') || '') !== " +
                    JSONObject.quote(pan.getString(5)),
            ),
        )
        composeRule.onNodeWithTag("effect-editor-preview").assertIsDisplayed()
        composeRule.onNodeWithTag("effect-editor-play").assertIsDisplayed()
        SystemClock.sleep(500)
        saveScreenshot("effect-block-colour-applied-${composeRule.activity.resources.configuration.fontScale}")
    }

    private fun selectLanguage(language: String, expectedScanLabel: String) {
        composeRule.onNodeWithTag("debug-toggle").performClick()
        composeRule.onNodeWithTag("language-selector").performClick()
        composeRule.onNodeWithTag("language-$language").performClick()
        composeRule.waitUntil(timeoutMillis = 10_000) {
            composeRule.onAllNodes(hasText(expectedScanLabel)).fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithText(expectedScanLabel).assertIsDisplayed()
    }

    private fun saveScreenshot(name: String) {
        val directory = File(composeRule.activity.getExternalFilesDir(null), "screenshots").apply { mkdirs() }
        val screenshot = File(directory, "$name.png")
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        FileOutputStream(screenshot).use { output ->
            automation.takeScreenshot().compress(Bitmap.CompressFormat.PNG, 100, output)
        }
        automation.executeShellCommand("cp ${screenshot.absolutePath} /sdcard/Download/Maurya-$name.png")
            .close()
    }

    private fun captureWebView(): WebView {
        var captured: WebView? = null
        onView(isAssignableFrom(WebView::class.java)).perform(
            object : ViewAction {
                override fun getConstraints(): Matcher<View> =
                    isAssignableFrom(WebView::class.java)

                override fun getDescription(): String = "capture Blockly WebView across dialog roots"

                override fun perform(uiController: UiController, view: View) {
                    captured = view as WebView
                    uiController.loopMainThreadUntilIdle()
                }
            }
        )
        assertNotNull("Blockly WebView not found", captured)
        return captured!!
    }

    private fun tapWebViewAtCssPoint(webView: WebView, point: JSONArray) {
        val scale = webView.width.toFloat() / point.getDouble(2).toFloat()
        val x = point.getDouble(0).toFloat() * scale
        val y = point.getDouble(1).toFloat() * scale
        composeRule.runOnUiThread {
            val now = SystemClock.uptimeMillis()
            webView.dispatchTouchEvent(
                MotionEvent.obtain(now, now, MotionEvent.ACTION_DOWN, x, y, 0),
            )
            webView.dispatchTouchEvent(
                MotionEvent.obtain(now, now + 80, MotionEvent.ACTION_UP, x, y, 0),
            )
        }
    }

    private fun swipeWebViewAtCssPoints(webView: WebView, points: JSONArray) {
        val scale = webView.width.toFloat() / points.getDouble(4).toFloat()
        val startX = points.getDouble(0).toFloat() * scale
        val startY = points.getDouble(1).toFloat() * scale
        val endX = points.getDouble(2).toFloat() * scale
        val endY = points.getDouble(3).toFloat() * scale
        composeRule.runOnUiThread {
            val start = SystemClock.uptimeMillis()
            webView.dispatchTouchEvent(
                MotionEvent.obtain(start, start, MotionEvent.ACTION_DOWN, startX, startY, 0),
            )
            for (step in 1..6) {
                val fraction = step / 6f
                webView.dispatchTouchEvent(
                    MotionEvent.obtain(
                        start,
                        start + step * 24L,
                        MotionEvent.ACTION_MOVE,
                        startX + (endX - startX) * fraction,
                        startY + (endY - startY) * fraction,
                        0,
                    ),
                )
            }
            webView.dispatchTouchEvent(
                MotionEvent.obtain(start, start + 180L, MotionEvent.ACTION_UP, endX, endY, 0),
            )
        }
    }

    private fun evaluateArray(webView: WebView, script: String): JSONArray {
        val latch = CountDownLatch(1)
        var value = "[]"
        composeRule.activity.runOnUiThread {
            webView.evaluateJavascript(script) {
                value = it
                latch.countDown()
            }
        }
        check(latch.await(5, TimeUnit.SECONDS)) { "WebView JavaScript evaluation timed out" }
        return JSONArray(value)
    }

    private fun evaluateBoolean(webView: WebView, script: String): Boolean {
        val latch = CountDownLatch(1)
        var value = true
        composeRule.activity.runOnUiThread {
            webView.evaluateJavascript(script) {
                value = it == "true"
                latch.countDown()
            }
        }
        check(latch.await(5, TimeUnit.SECONDS)) { "WebView JavaScript evaluation timed out" }
        return value
    }

}
