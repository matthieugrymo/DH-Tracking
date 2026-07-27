import Toybox.Lang;
import Toybox.Application;

//! Every tuning constant of the detector lives here — spec §4.4 requires a
//! single place to calibrate after a field session.
//!
//! The module also builds the `Thresholds` object handed to `LiftDetector`.
//! `Thresholds` is plain data with no watch-API dependency so that unit tests
//! can construct one directly (spec §9, architecture constraint).
module Config {

    // ------------------------------------------------------------------
    // Detector states (spec §4.3)
    // ------------------------------------------------------------------
    enum {
        STATE_IDLE    = 0,  // bottom of the slope, lift queue
        STATE_LIFT    = 1,  // riding up, timer paused
        STATE_DESCENT = 2   // riding down, timer running
    }

    // ------------------------------------------------------------------
    // "Type de remontée" setting (spec §7)
    // ------------------------------------------------------------------
    enum {
        LIFT_CHAIRLIFT = 0, // accelVariance is a blocking condition
        LIFT_TBAR      = 1, // accelVariance is only a confidence factor
        LIFT_MIXED     = 2  // accelVariance blocks, but with a relaxed gate
    }

    // ------------------------------------------------------------------
    // "Sensibilité détection" setting (spec §7)
    // ------------------------------------------------------------------
    enum {
        SENS_LOW    = 0,
        SENS_NORMAL = 1,
        SENS_HIGH   = 2
    }

    // ------------------------------------------------------------------
    // "GPS" setting (spec §7)
    // ------------------------------------------------------------------
    enum {
        GPS_SAT_IQ     = 0,
        GPS_MULTI_BAND = 1
    }

    // ------------------------------------------------------------------
    // "Enregistrement" setting.
    //
    // Connect IQ gives exactly one lever here: whether the session timer is
    // running. `Activity.Info.totalAscent` is read-only and a Session exposes
    // only start/stop/addLap/save/discard, so the device accumulates both time
    // *and* ascent precisely while the timer runs — and a stopped session writes
    // no records at all. Three consequences are therefore one and the same
    // switch: activity time excluding lifts, ascent excluding lifts, and a gap
    // in the GPS track. They cannot be separated.
    //
    //   RECORDING_DESCENT_ONLY (default) the session is stopped on every lift.
    //                         This is the alpine ski model: activity time is
    //                         descent time, and the lift climb never lands in
    //                         the MTB ascent total. Cost: no GPS point is
    //                         written during a lift, so the map shows each
    //                         descent joined by a straight line. Since a cable
    //                         runs straight between pylons (§4.1), that
    //                         connector roughly traces the lift anyway.
    //
    //   RECORDING_FULL_DAY    the session runs from START to STOP, so the GPS
    //                         track is continuous. Cost: every metre the lift
    //                         climbs is counted as MTB ascent, and activity time
    //                         covers the whole day. Per-run laps and the
    //                         `lift_time` developer field carry the breakdown.
    // ------------------------------------------------------------------
    enum {
        RECORDING_FULL_DAY     = 0,
        RECORDING_DESCENT_ONLY = 1
    }

    // ------------------------------------------------------------------
    // Sampling (spec §4.2, §11)
    // ------------------------------------------------------------------
    const SAMPLE_PERIOD_MS  = 1000; // main loop runs at 1 Hz, never faster
    const HISTORY_SEC       = 60;   // ring buffer depth
    const ALT_SMOOTH_SEC    = 3;    // moving average on the raw barometer
    const ACCEL_SAMPLE_RATE = 25;   // Hz; drop to 10 if battery life suffers
    const ACCEL_PERIOD_SEC  = 1;    // one accel callback per second
    const ACCEL_STALE_MS    = 4000; // no callback for this long => unavailable
    //! A larger gap invalidates detector windows. Without this guard an altitude
    //! sample from before a sensor outage could satisfy a 6 s / 20 s window.
    const SAMPLE_GAP_RESET_MS = 2500;

    // ------------------------------------------------------------------
    // IDLE/LIFT -> DESCENT (spec §4.3)
    // ------------------------------------------------------------------
    const DESCENT_WINDOW_SEC    = 6;
    const DESCENT_DROP_M        = 8.0;
    const DESCENT_MIN_SPEED_MPS = 1.389; // 5 km/h

    // ------------------------------------------------------------------
    // IDLE/DESCENT -> LIFT (spec §4.3)
    // ------------------------------------------------------------------
    const LIFT_WINDOW_SEC          = 20;
    const LIFT_GAIN_M              = 10.0;
    const LIFT_MONOTONIC_RATIO     = 0.8;
    //! With a surface lift the accelerometer is not a blocking condition
    //! (spec §4.4), so monotonicity has to carry more of the decision.
    const LIFT_MONOTONIC_RATIO_TBAR = 0.9;
    //! Below this many samples in the window the monotonicity ratio is noise.
    const LIFT_MIN_SAMPLES = 8;

    //! Narrow confirmation window. Latency before LIFT is recognised is charged
    //! straight to the activity's ascent total (the device accumulates ascent
    //! while the timer runs), so a faster path pays for itself. A smaller gain is
    //! acceptable because the monotonicity bar is raised to compensate: a steady
    //! 0.75 m/s climb with almost every sample rising and no vibration is not
    //! something a downhill bike does.
    const LIFT_FAST_WINDOW_SEC     = 8;
    const LIFT_FAST_GAIN_M         = 6.0;
    const LIFT_FAST_MONOTONIC_RATIO = 0.9;
    const LIFT_FAST_MIN_SAMPLES    = 6;

    // ------------------------------------------------------------------
    // DESCENT -> IDLE (spec §4.3)
    // ------------------------------------------------------------------
    const IDLE_MAX_SPEED_MPS   = 0.833; // 3 km/h
    const IDLE_ALT_TOLERANCE_M = 3.0;   // "altitude stable"
    const IDLE_HOLD_SEC        = 90;    // short stops on the trail do not count

    // ------------------------------------------------------------------
    // Accelerometer thresholds.
    // Standard deviation of the accel magnitude over 1 s, in milli-g.
    // TO CALIBRATE IN THE FIELD (spec §4.3): ACCEL_ROUGH should sit at roughly
    // twice the resting noise floor measured on the wrist.
    // ------------------------------------------------------------------
    const ACCEL_ROUGH_MG   = 120.0; // above this => rough ground, i.e. riding
    const ACCEL_SMOOTH_MG  = 60.0;  // below this => hanging from a cable
    const ACCEL_MIXED_RELAX = 2.0;  // gate multiplier in LIFT_MIXED mode

    // ------------------------------------------------------------------
    // Robustness (spec §4.4)
    // ------------------------------------------------------------------
    const TRANSITION_LOCK_SEC = 10; // hysteresis: state locked after a change

    // ------------------------------------------------------------------
    // UI (spec §5)
    // ------------------------------------------------------------------
    const RUN_SUMMARY_MS = 5000;

    // ------------------------------------------------------------------
    // Property keys — must match resources/settings/settings.xml
    // ------------------------------------------------------------------
    const PROP_LIFT_TYPE   = "liftType";
    const PROP_SENSITIVITY = "sensitivity";
    const PROP_RUN_SUMMARY = "runSummary";
    const PROP_VIBRATION   = "vibration";
    const PROP_GPS_MODE    = "gpsMode";
    const PROP_RECORDING   = "recordingMode";

    //! Detector thresholds, resolved from the constants above plus the user
    //! settings. Pure data: no watch API is touched, so `LiftDetector` stays
    //! testable outside the simulator.
    class Thresholds {
        public var descentDropM as Float = 0.0;
        public var descentMinSpeedMps as Float = 0.0;
        public var liftGainM as Float = 0.0;
        public var liftMonotonicRatio as Float = 0.0;
        public var liftFastGainM as Float = 0.0;
        public var liftFastMonotonicRatio as Float = 0.0;
        public var idleMaxSpeedMps as Float = 0.0;
        public var idleAltToleranceM as Float = 0.0;

        //! Minimum accel std-dev to accept a DESCENT. Null disables the gate.
        public var accelRoughMg as Float or Null = null;
        //! Maximum accel std-dev to accept a LIFT. Null disables the gate.
        public var accelSmoothMg as Float or Null = null;

        function initialize() {
            descentDropM       = DESCENT_DROP_M;
            descentMinSpeedMps = DESCENT_MIN_SPEED_MPS;
            liftGainM          = LIFT_GAIN_M;
            liftMonotonicRatio = LIFT_MONOTONIC_RATIO;
            liftFastGainM      = LIFT_FAST_GAIN_M;
            liftFastMonotonicRatio = LIFT_FAST_MONOTONIC_RATIO;
            idleMaxSpeedMps    = IDLE_MAX_SPEED_MPS;
            idleAltToleranceM  = IDLE_ALT_TOLERANCE_M;
            accelRoughMg       = ACCEL_ROUGH_MG;
            accelSmoothMg      = ACCEL_SMOOTH_MG;
        }

        //! Spec §7: low ×1.5, normal ×1, high ×0.7.
        //!
        //! The multiplier expresses "how hard is it to trigger a transition",
        //! so it scales the altitude thresholds and the DESCENT accel floor
        //! directly, and the LIFT accel ceiling inversely — otherwise a "low
        //! sensitivity" setting would make LIFT *easier* to trigger.
        //! Speed gates are physical sanity checks and are left alone.
        function applySensitivity(sensitivity as Number) as Void {
            var factor = 1.0;
            if (sensitivity == SENS_LOW) {
                factor = 1.5;
            } else if (sensitivity == SENS_HIGH) {
                factor = 0.7;
            }
            descentDropM = DESCENT_DROP_M * factor;
            liftGainM    = LIFT_GAIN_M * factor;
            liftFastGainM = LIFT_FAST_GAIN_M * factor;
            accelRoughMg = ACCEL_ROUGH_MG * factor;
            accelSmoothMg = ACCEL_SMOOTH_MG / factor;
        }

        //! Spec §7 / §4.4. Must be called after `applySensitivity`, which
        //! resets the accel gates.
        function applyLiftType(liftType as Number) as Void {
            if (liftType == LIFT_TBAR) {
                // Surface lift: moderate vibration and lower speed, so the
                // accelerometer must not veto. Altitude monotonicity leads.
                accelSmoothMg = null;
                liftMonotonicRatio = LIFT_MONOTONIC_RATIO_TBAR;
                liftFastMonotonicRatio = LIFT_MONOTONIC_RATIO_TBAR
                    > LIFT_FAST_MONOTONIC_RATIO
                    ? LIFT_MONOTONIC_RATIO_TBAR : LIFT_FAST_MONOTONIC_RATIO;
            } else if (liftType == LIFT_MIXED) {
                var smooth = accelSmoothMg;
                if (smooth != null) {
                    accelSmoothMg = smooth * ACCEL_MIXED_RELAX;
                }
                liftMonotonicRatio = LIFT_MONOTONIC_RATIO;
            } else {
                liftMonotonicRatio = LIFT_MONOTONIC_RATIO;
            }
        }
    }

    //! Read a property, falling back to `defaultValue` when it is missing or
    //! of the wrong type (happens on a fresh install before settings sync).
    function getNumber(key as String, defaultValue as Number) as Number {
        try {
            var value = Properties.getValue(key);
            if (value instanceof Number) {
                return value;
            }
        } catch (ex) {
            // Properties unavailable — fall through to the default.
        }
        return defaultValue;
    }

    function getBoolean(key as String, defaultValue as Boolean) as Boolean {
        try {
            var value = Properties.getValue(key);
            if (value instanceof Boolean) {
                return value;
            }
        } catch (ex) {
            // Properties unavailable — fall through to the default.
        }
        return defaultValue;
    }

    function liftType() as Number {
        return getNumber(PROP_LIFT_TYPE, LIFT_CHAIRLIFT);
    }

    function sensitivity() as Number {
        return getNumber(PROP_SENSITIVITY, SENS_NORMAL);
    }

    function runSummaryEnabled() as Boolean {
        return getBoolean(PROP_RUN_SUMMARY, true);
    }

    function vibrationEnabled() as Boolean {
        return getBoolean(PROP_VIBRATION, true);
    }

    function gpsMode() as Number {
        return getNumber(PROP_GPS_MODE, GPS_SAT_IQ);
    }

    function recordingMode() as Number {
        return getNumber(PROP_RECORDING, RECORDING_DESCENT_ONLY);
    }

    //! True when the recording has to be stopped during lifts, i.e. when the
    //! activity timer should show descent time only.
    function pauseOnLift() as Boolean {
        return recordingMode() == RECORDING_DESCENT_ONLY;
    }

    //! Build the threshold set matching the current user settings.
    function loadThresholds() as Thresholds {
        var thresholds = new Thresholds();
        thresholds.applySensitivity(sensitivity());
        thresholds.applyLiftType(liftType());
        return thresholds;
    }
}
