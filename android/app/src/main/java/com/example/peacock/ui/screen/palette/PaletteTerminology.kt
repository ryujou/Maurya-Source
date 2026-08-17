package com.example.peacock.ui.screen.palette

import android.content.Context
import com.example.peacock.R

data class PaletteCopy(
    val groupNoun: String,
    val memberNoun: String,
    val groupSearchLabel: String,
    val memberSearchLabel: String,
    val memberListTitleFormat: String,
    val noGroupMessage: String,
    val noMemberMessage: String,
) {
    fun memberListTitle(groupName: String): String {
        return memberListTitleFormat.format(memberNoun, groupName)
    }
}

fun resolvePaletteCopy(context: Context, franchiseId: String): PaletteCopy {
    val groupTermRes = when (franchiseId) {
        "bangdream" -> R.string.palette_term_bangdream_group
        "imas" -> R.string.palette_term_imas_group
        else -> R.string.palette_term_lovelive_group
    }
    val memberTermRes = when (franchiseId) {
        "imas" -> R.string.palette_term_imas_member
        else -> R.string.palette_term_member
    }

    val groupNoun = context.getString(groupTermRes)
    val memberNoun = context.getString(memberTermRes)
    return PaletteCopy(
        groupNoun = groupNoun,
        memberNoun = memberNoun,
        groupSearchLabel = context.getString(R.string.palette_search_format, groupNoun),
        memberSearchLabel = context.getString(R.string.palette_search_format, memberNoun),
        memberListTitleFormat = context.getString(R.string.palette_list_title_format),
        noGroupMessage = context.getString(R.string.palette_no_group_format, groupNoun),
        noMemberMessage = context.getString(R.string.palette_no_member_format, groupNoun, memberNoun),
    )
}
