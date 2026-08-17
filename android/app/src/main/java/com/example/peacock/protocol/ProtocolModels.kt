package com.example.peacock.protocol

sealed interface ProtocolResponse

data class ReadHoldingResponse(val values: List<Int>) : ProtocolResponse

data class WriteAckResponse(
    val function: Int,
    val startRegister: Int,
    val valueOrCount: Int,
) : ProtocolResponse

data class ExceptionResponse(
    val function: Int,
    val code: Int,
    val message: String,
) : ProtocolResponse
