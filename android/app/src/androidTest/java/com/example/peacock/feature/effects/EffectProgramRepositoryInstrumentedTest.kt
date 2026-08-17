package com.example.peacock.feature.effects

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class EffectProgramRepositoryInstrumentedTest {
    @Test
    fun existingInstallReceivesNewBundledEffectOnlyOnce() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val file = File(context.filesDir, "effect_programs.json")
        val original = file.takeIf(File::exists)?.readBytes()
        val preferences = context.getSharedPreferences("effect_program_repository", 0)
        val hadVersion = preferences.contains("bundled_examples_version")
        val originalVersion = preferences.getInt("bundled_examples_version", 0)

        try {
            file.delete()
            preferences.edit().remove("bundled_examples_version").commit()
            val initial = EffectProgramRepository(context).load()
            val legacyPrograms = initial.filterNot { it.id == "example-nebula-prism" }
            file.writeText(
                JSONArray().apply { legacyPrograms.forEach { put(EffectProgramTransfer.encode(it)) } }.toString(),
            )
            preferences.edit().remove("bundled_examples_version").commit()

            val upgraded = EffectProgramRepository(context).load()
            assertTrue(upgraded.any { it.id == "example-nebula-prism" })

            EffectProgramRepository(context).delete("example-nebula-prism")
            val afterUserDelete = EffectProgramRepository(context).load()
            assertFalse(afterUserDelete.any { it.id == "example-nebula-prism" })
        } finally {
            if (original == null) file.delete() else file.writeBytes(original)
            preferences.edit().apply {
                if (hadVersion) putInt("bundled_examples_version", originalVersion)
                else remove("bundled_examples_version")
            }.commit()
        }
    }
}
