//
//  GlobeEphemeris.swift
//  norlysWidget
//
//  Where the sun and the moon stand over the globe, as the website's map/features/ephemeris.ts
//  computes it: the sub-solar point from solar-calculator, the sub-lunar point and the moon's lit
//  fraction from suncalc's low precision ephemeris.
//

import Foundation

enum GlobeEphemeris {
    private static let rad = Double.pi / 180
    private static let j1970 = 2440588.0
    private static let j2000 = 2451545.0
    /// Obliquity of the Earth, as suncalc rounds it.
    private static let e = rad * 23.4397
    private static let dayMs = 864e5

    /// Milliseconds since 1970, as a JavaScript `Date` holds them.
    private static func milliseconds(_ date: Date) -> Double {
        (date.timeIntervalSince1970 * 1000).rounded(.down)
    }

    /// Days since the J2000 epoch.
    private static func toDays(_ date: Date) -> Double {
        milliseconds(date) / dayMs - 0.5 + j1970 - j2000
    }

    /// Brings a longitude back into [-180, 180), with JavaScript's remainder.
    private static func wrapLongitude(_ longitude: Double) -> Double {
        fmod(fmod(longitude, 360) + 540, 360) - 180
    }

    // MARK: solar-calculator

    /// J2000.0 centuries.
    private static func century(_ date: Date) -> Double {
        (milliseconds(date) - 946_728_000_000) / 315_576e7
    }

    private static func meanLongitude(_ t: Double) -> Double {
        let l = fmod(280.46646 + t * (36000.76983 + t * 0.0003032), 360)
        return l < 0 ? l + 360 : l
    }

    private static func meanAnomaly(_ t: Double) -> Double {
        357.52911 + t * (35999.05029 - 0.0001537 * t)
    }

    private static func obliquityOfEcliptic(_ t: Double) -> Double {
        let e0 = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60
        let omega = 125.04 - 1934.136 * t
        return e0 + 0.00256 * cos(omega * rad)
    }

    private static func orbitEccentricity(_ t: Double) -> Double {
        0.016708634 - t * (0.000042037 + 0.0000001267 * t)
    }

    private static func equationOfCenter(_ t: Double) -> Double {
        let m = meanAnomaly(t) * rad
        return sin(m) * (1.914602 - t * (0.004817 + 0.000014 * t))
            + sin(m * 2) * (0.019993 - 0.000101 * t)
            + sin(m * 3) * 0.000289
    }

    private static func apparentLongitude(_ t: Double) -> Double {
        meanLongitude(t) + equationOfCenter(t) - 0.00569 - 0.00478 * sin((125.04 - 1934.136 * t) * rad)
    }

    private static func declination(_ t: Double) -> Double {
        asin(sin(obliquityOfEcliptic(t) * rad) * sin(apparentLongitude(t) * rad)) / rad
    }

    /// In minutes.
    private static func equationOfTime(_ t: Double) -> Double {
        let epsilon = obliquityOfEcliptic(t)
        let l0 = meanLongitude(t)
        let e = orbitEccentricity(t)
        let m = meanAnomaly(t)
        let y = pow(tan(epsilon * rad / 2), 2)
        let sin2l0 = sin(2 * l0 * rad)
        let sinm = sin(m * rad)
        let cos2l0 = cos(2 * l0 * rad)
        let sin4l0 = sin(4 * l0 * rad)
        let sin2m = sin(2 * m * rad)
        let time = y * sin2l0 - 2 * e * sinm + 4 * e * y * sinm * cos2l0 - 0.5 * y * y * sin4l0 - 1.25 * e * e * sin2m
        return time / rad * 4
    }

    // MARK: Points

    /// Where the sun is at zenith, the centre of the hemisphere seeing daylight. Every circle centred
    /// on it is a line of constant solar elevation.
    static func subSolarPoint(_ date: Date) -> GeoPoint {
        let ms = milliseconds(date)
        let day = (ms / dayMs).rounded(.down) * dayMs
        let t = century(date)
        let longitude = (day - ms) / dayMs * 360 - 180
        return GeoPoint(lon: wrapLongitude(longitude - equationOfTime(t) / 4), lat: declination(t))
    }

    /// The centre of the hemisphere in night.
    static func antiSolarPoint(_ date: Date) -> GeoPoint {
        let sun = subSolarPoint(date)
        return GeoPoint(lon: wrapLongitude(sun.lon + 180), lat: -sun.lat)
    }

    /// Where the moon is at zenith, the centre of the hemisphere seeing it.
    static func subLunarPoint(_ date: Date) -> GeoPoint {
        let d = toDays(date)
        let l0 = rad * (218.316 + 13.176396 * d)
        let m = rad * (134.963 + 13.064993 * d)
        let f = rad * (93.272 + 13.229350 * d)
        let l = l0 + rad * 6.289 * sin(m)
        let b = rad * 5.128 * sin(f)
        let ra = atan2(sin(l) * cos(e) - tan(b) * sin(e), cos(l))
        let dec = asin(sin(b) * cos(e) + cos(b) * sin(e) * sin(l))
        let siderealTime = rad * (280.16 + 360.9856235 * d)
        return GeoPoint(lon: wrapLongitude((ra - siderealTime) / rad), lat: dec / rad)
    }

    // MARK: suncalc

    private static func rightAscension(_ l: Double, _ b: Double) -> Double {
        atan2(sin(l) * cos(e) - tan(b) * sin(e), cos(l))
    }

    private static func declination(_ l: Double, _ b: Double) -> Double {
        asin(sin(b) * cos(e) + cos(b) * sin(e) * sin(l))
    }

    /// suncalc's `getMoonIllumination(date).fraction`: the lit part of the moon, from 0 to 1.
    static func moonIllumination(_ date: Date) -> Double {
        let d = toDays(date)

        let sunM = rad * (357.5291 + 0.98560028 * d)
        let center = rad * (1.9148 * sin(sunM) + 0.02 * sin(2 * sunM) + 0.0003 * sin(3 * sunM))
        let sunL = sunM + center + rad * 102.9372 + .pi
        let sunDec = declination(sunL, 0), sunRa = rightAscension(sunL, 0)

        let moonL = rad * (218.316 + 13.176396 * d)
        let moonM = rad * (134.963 + 13.064993 * d)
        let moonF = rad * (93.272 + 13.229350 * d)
        let l = moonL + rad * 6.289 * sin(moonM)
        let b = rad * 5.128 * sin(moonF)
        let moonDist = 385001 - 20905 * cos(moonM)
        let moonDec = declination(l, b), moonRa = rightAscension(l, b)

        let sdist = 149598000.0
        let phi = acos(sin(sunDec) * sin(moonDec) + cos(sunDec) * cos(moonDec) * cos(sunRa - moonRa))
        let inc = atan2(sdist * sin(phi), moonDist - sdist * cos(phi))
        return (1 + cos(inc)) / 2
    }
}
