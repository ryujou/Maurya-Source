package com.example.peacock.feature.effects

import com.example.peacock.feature.runtime.GroupState
import com.example.peacock.protocol.ModbusCodec

object EffectProtocol {
    const val capabilityVolatileEffect = 0x20
    const val capabilityPixelEffect = 0x40
    private const val begin = 0x20
    private const val frame = 0x21
    private const val heartbeat = 0x22
    private const val end = 0x23
    private const val pixelFrame = 0x24

    fun beginRequest(address: Int) = ModbusCodec.buildVendor(address, byteArrayOf(begin.toByte()))
    fun parseBegin(response: ByteArray): Long {
        val payload = payload(response, begin)
        require(payload.size == 6 && payload[0].toInt() and 255 == 0x30 && payload[1].toInt() and 255 == 4)
        return payload.copyOfRange(2,6).u32()
    }
    fun frameRequest(address:Int, sessionId:Long, sequence:Int, groups:List<GroupState>):ByteArray {
        require(groups.size == EffectGeometry.GROUP_COUNT)
        val body=ArrayList<Byte>(49)
        body += frame.toByte()
        body.addU32(sessionId)
        body += sequence.toByte(); body += (sequence ushr 8).toByte()
        groups.forEach {
            body += it.innerMode.toByte()
            body += it.hue.toByte(); body += (it.hue ushr 8).toByte()
            body += it.sat.toByte(); body += it.value.toByte(); body += it.innerParam.toByte()
        }
        return ModbusCodec.buildVendor(address,body.toByteArray())
    }
    fun pixelFrameRequest(
        address: Int,
        sessionId: Long,
        sequence: Int,
        pixels: List<EffectRgb>,
    ): ByteArray {
        require(pixels.size == EffectGeometry.PIXEL_COUNT)
        val body = ArrayList<Byte>(9 + EffectGeometry.PIXEL_COUNT * 3)
        body += pixelFrame.toByte()
        body.addU32(sessionId)
        body += sequence.toByte()
        body += (sequence ushr 8).toByte()
        body += 1 // RGB888
        body += EffectGeometry.PIXEL_COUNT.toByte()
        pixels.forEach {
            body += it.red.toByte()
            body += it.green.toByte()
            body += it.blue.toByte()
        }
        return ModbusCodec.buildVendor(address, body.toByteArray()).also {
            check(it.size == EffectGeometry.PIXEL_FRAME_BYTES) {
                "pixel frame must be exactly ${EffectGeometry.PIXEL_FRAME_BYTES} bytes"
            }
        }
    }
    fun heartbeatRequest(address:Int,sessionId:Long)=ModbusCodec.buildVendor(address, byteArrayOf(heartbeat.toByte())+u32(sessionId))
    fun endRequest(address:Int,sessionId:Long)=ModbusCodec.buildVendor(address, byteArrayOf(end.toByte())+u32(sessionId))
    fun parseAck(response:ByteArray,command:Int)=payload(response,command)
    fun frameCommand()=frame
    fun pixelFrameCommand()=pixelFrame
    fun heartbeatCommand()=heartbeat
    fun endCommand()=end

    private fun payload(frame:ByteArray,command:Int):ByteArray {
        require(ModbusCodec.validateCrc(frame) && frame.size>=7 && frame[1].toInt() and 255==0x41)
        val raw=frame.copyOfRange(3,frame.size-2)
        require(raw[0].toInt() and 255==command)
        val status=raw[1].toInt() and 255
        if(status!=0) throw EffectCommandRejectedException(command,status)
        return raw.copyOfRange(2,raw.size)
    }
    private fun ByteArray.u32()=foldIndexed(0L){i,v,b->v or ((b.toLong() and 255) shl (i*8))}
    private fun u32(v:Long)=byteArrayOf(v.toByte(),(v ushr 8).toByte(),(v ushr 16).toByte(),(v ushr 24).toByte())
    private fun ArrayList<Byte>.addU32(v:Long){ addAll(u32(v).toList()) }
}

class EffectCommandRejectedException(val command:Int,val status:Int):
    IllegalStateException("设备拒绝临时灯效命令 0x${command.toString(16)}（状态$status）")
