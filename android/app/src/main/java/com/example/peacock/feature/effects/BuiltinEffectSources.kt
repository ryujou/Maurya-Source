package com.example.peacock.feature.effects

object BuiltinEffectSources {
    const val NEBULA_PRISM = """effect "星云棱镜" {
    allPixels.color("#000000");
    wait(100ms);
    forever {
        let t: number = time.elapsedMs / 1000;
        for (let i = 1; i <= 42; i += 1) {
            let arm: number = floor((i - 1) / 6);
            let position: number = (i - 1) % 6;
            let phase: number = (i - 1) / 42 + arm / 13 + position / 17;
            let wave: number = sineWave(1700ms, phase);
            let ripple: number = triangleWave(1100ms, phase * 1.7);
            let cloud: number = fbmNoise(t * 0.7 + i * 0.137, 3, 2026);
            let sparkle: number = squareWave(760ms, 0.14, phase * 2.3);
            let hue: number =
                (t * 86 + arm * 47 + position * 23 + wave * 72 + cloud * 58) % 360;
            let saturation: number = clamp(180 + cloud * 75 + ripple * 20, 0, 255);
            let value: number =
                clamp(24 + wave * 122 + ripple * 54 + sparkle * 55, 0, 255);
            pixelAt(i).hsv(hue, saturation, value);
        }
        wait(50ms);
    }
}"""
}
