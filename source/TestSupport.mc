import Toybox.Lang;
import Toybox.Test;

//! Shared fixtures for the unit tests.
//!
//! These are classes rather than global functions on purpose: Run No Evil
//! enumerates every `(:test)` *function* as a test case, so helpers have to be
//! static methods. The `(:test)` annotation on the class still keeps all of it
//! out of the shipped app.

//! Owns a detector and records the run events it emits. The harness has to own
//! the detector because `method(:x)` only binds to `self`.
(:test)
class DetectorHarness {

    public var detector as LiftDetector;
    public var startCount as Number = 0;
    public var endCount as Number = 0;
    public var lastStartMs as Number or Null = null;
    public var lastEndMs as Number or Null = null;

    function initialize(thresholds as Config.Thresholds) {
        detector = new LiftDetector(thresholds, method(:onRunStart), method(:onRunEnd));
    }

    function onRunStart(timeMs as Number) as Void {
        startCount += 1;
        lastStartMs = timeMs;
    }

    function onRunEnd(timeMs as Number) as Void {
        endCount += 1;
        lastEndMs = timeMs;
    }

    //! Feed `seconds` of 1 Hz samples on a linear altitude ramp.
    //! Returns the timestamp the next sample would carry.
    function feedRamp(startMs as Number, seconds as Number, startAltitudeM as Float,
                      altitudeRateMps as Float, speedMps as Float or Null,
                      accelMg as Float or Null) as Number {
        var timeMs = startMs;
        for (var i = 0; i < seconds; i++) {
            detector.update(startAltitudeM + altitudeRateMps * i, speedMps, 0.0,
                            accelMg, timeMs);
            timeMs += 1000;
        }
        return timeMs;
    }

    //! Feed `seconds` of samples oscillating +/- `amplitudeM` around a constant
    //! altitude — barometric noise, which must never trigger anything.
    function feedNoise(startMs as Number, seconds as Number, altitudeM as Float,
                       amplitudeM as Float, speedMps as Float or Null,
                       accelMg as Float or Null) as Number {
        var timeMs = startMs;
        for (var i = 0; i < seconds; i++) {
            var offset = i % 2 == 0 ? amplitudeM : -amplitudeM;
            detector.update(altitudeM + offset, speedMps, 0.0, accelMg, timeMs);
            timeMs += 1000;
        }
        return timeMs;
    }

    //! Feed `seconds` of samples with a null altitude — barometer not ready.
    function feedNullAltitude(startMs as Number, seconds as Number) as Number {
        var timeMs = startMs;
        for (var i = 0; i < seconds; i++) {
            detector.update(null, 3.0, 0.0, 300.0, timeMs);
            timeMs += 1000;
        }
        return timeMs;
    }
}

(:test)
class TestSupport {

    static function makeThresholds(sensitivity as Number,
                                   liftType as Number) as Config.Thresholds {
        var thresholds = new Config.Thresholds();
        thresholds.applySensitivity(sensitivity);
        thresholds.applyLiftType(liftType);
        return thresholds;
    }

    static function makeHarness(liftType as Number) as DetectorHarness {
        return new DetectorHarness(makeThresholds(Config.SENS_NORMAL, liftType));
    }

    static function nearlyEqual(actual as Float, expected as Float,
                                tolerance as Float) as Boolean {
        return (actual - expected).abs() <= tolerance;
    }

    //! Feed a run with a constant descent rate and speed, using the cumulative
    //! distance channel the watch would provide.
    //!
    //! Note the first sample only establishes the cumulative-distance baseline,
    //! exactly as it does on the watch, so `seconds` samples contribute
    //! `seconds - 1` distance steps.
    static function feedRun(run as RunStats, seconds as Number, startAltitudeM as Float,
                            altitudeRateMps as Float, speedMps as Float,
                            heartRate as Number or Null) as Number {
        var timeMs = run.startTimeMs;
        var distanceM = 0.0;
        for (var i = 1; i <= seconds; i++) {
            timeMs += 1000;
            distanceM += speedMps;
            run.update(startAltitudeM + altitudeRateMps * i, speedMps, distanceM,
                       heartRate, timeMs);
        }
        return timeMs;
    }
}
