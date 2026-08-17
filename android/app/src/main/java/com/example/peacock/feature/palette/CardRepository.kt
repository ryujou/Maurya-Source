package com.example.peacock.feature.palette

import android.content.Context
import org.json.JSONObject

object CardRepository {
    fun loadCardImageUrls(context: Context): List<String> {
        return try {
            context.assets.open("card.json").bufferedReader().use { reader ->
                val json = JSONObject(reader.readText())
                val array = json.optJSONArray("cards") ?: return emptyList()
                List(array.length()) { index ->
                    array.optString(index, "").takeIf { it.isNotBlank() } ?: ""
                }.filter { it.isNotBlank() }
            }
        } catch (_: Exception) {
            emptyList()
        }
    }
}
