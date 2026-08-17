package com.example.peacock.protocol

object RegisterMap {
    const val DEVICE_ADDR_DEFAULT = 0x01

    const val SCENE_MODE = 0x0000
    const val SCENE_PARAM = 0x0001
    const val LED_GLOBAL_BRI = 0x0002
    const val LED_GAIN_R = 0x0003
    const val LED_GAIN_G = 0x0004
    const val LED_GAIN_B = 0x0005

    const val CFG_SAVE_STATE = 0x000A
    const val DEVICE_ADDR = 0x000B
    const val UART_RX_COUNT = 0x000C
    const val UART_RX_OVERFLOW = 0x000D
    const val UART_TX_DROP = 0x000E
    const val UART_PARSE_ERROR = 0x000F
    const val TEMP_C_X100 = 0x0010
    const val VDDA_MV = 0x0011

    const val GROUP_BASE = 0x0020
    const val GROUP_STRIDE = 0x0005
    const val GROUP_COUNT = 7
    const val GROUP_REG_COUNT = GROUP_COUNT * GROUP_STRIDE
    const val CONFIG_REG_COUNT = 22
    const val MAX_BULK_REG_COUNT = 64

    const val DIAG_CLEAR_KEY = 0xA55A
}
