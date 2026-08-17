import Foundation

public enum CoreMotionEnvironmentMapper {
    /// Android `TYPE_PRESSURE` is hectopascals; Core Motion reports kPa.
    public static func androidPressure(kilopascals: Double) -> Double {
        kilopascals.isFinite ? kilopascals * 10 : 0
    }

    public static func androidNear(_ isNear: Bool) -> Double { isNear ? 1 : 0 }
}
