import Toybox.Lang;
import Toybox.Application;
import Toybox.Activity;
import Toybox.Attention;
import Toybox.Math;
import Toybox.Position;
import Toybox.Sensor;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

//! Application entry point and orchestrator (spec §9).
//!
//! Owns the 1 Hz sampling loop, the 25 Hz accelerometer listener, the detector,
//! the statistics and the recording session, and wires the detector's run
//! events to laps, vibrations and the on-screen summary.
class DhTrackerApp extends Application.AppBase {

    public var detector as LiftDetector or Null = null;
    public var stats as SessionStats or Null = null;
    public var sessionManager as SessionManager;

    //! True once the user has pressed START — nothing is recorded before that.
    public var armed as Boolean = false;
    //! True once the day has been saved or discarded.
    public var finished as Boolean = false;

    //! Latest sampled values, exposed for the view.
    public var currentSpeedMps as Float or Null = null;
    public var gpsQuality as Number or Null = null;

    private var _thresholds as Config.Thresholds;
    private var _timer as Timer.Timer or Null = null;
    private var _view as DhTrackerView or Null = null;

    private var _accelVarianceMg as Float or Null = null;
    private var _accelUpdatedMs as Number or Null = null;
    private var _accelRegistered as Boolean = false;
    private var _positionEnabled as Boolean = false;

    private var _lastTickMs as Number or Null = null;

    function initialize() {
        AppBase.initialize();
        _thresholds = Config.loadThresholds();
        sessionManager = new SessionManager();
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        var view = new DhTrackerView();
        _view = view;
        return [view, new DhTrackerDelegate(view)];
    }

    function onStart(state as Dictionary?) as Void {
        var timer = new Timer.Timer();
        timer.start(method(:onTick), Config.SAMPLE_PERIOD_MS, true);
        _timer = timer;
    }

    function onStop(state as Dictionary?) as Void {
        var timer = _timer;
        if (timer != null) {
            timer.stop();
            _timer = null;
        }
        _stopSensors();
        // The app is going away with a day in progress: save rather than lose
        // it. `save()` is a no-op once the user has already saved or discarded.
        if (armed && !finished) {
            saveDay();
        }
    }

    //! Re-read the settings when they are changed from Garmin Connect Mobile.
    //! Thresholds are swapped in place so an in-progress day is not disturbed.
    function onSettingsChanged() as Void {
        _thresholds = Config.loadThresholds();
        var detectorRef = detector;
        if (detectorRef != null) {
            detectorRef.setThresholds(_thresholds);
        }
    }

    // ------------------------------------------------------------------
    // Session lifecycle
    // ------------------------------------------------------------------

    //! First START press (spec §6): open the recording session and start
    //! sampling. The activity timer itself only starts on the first DESCENT.
    function startDay() as Void {
        if (armed) {
            return;
        }
        var now = System.getTimer();
        stats = new SessionStats(now);
        detector = new LiftDetector(_thresholds, method(:onRunStart), method(:onRunEnd));
        _lastTickMs = now;
        armed = true;
        finished = false;

        sessionManager.open();
        _startSensors();
    }

    function saveDay() as Boolean {
        var saved = sessionManager.save();
        finished = true;
        armed = false;
        _stopSensors();
        return saved;
    }

    function discardDay() as Boolean {
        var discarded = sessionManager.discard();
        finished = true;
        armed = false;
        _stopSensors();
        return discarded;
    }

    //! Manual override (spec §6): START outside the first press forces the
    //! transition the detector missed — into a run, or out of it.
    function forceTransition() as Void {
        var detectorRef = detector;
        if (detectorRef == null) {
            return;
        }
        var now = System.getTimer();
        if (detectorRef.state == Config.STATE_DESCENT) {
            detectorRef.forceState(Config.STATE_LIFT, now);
        } else {
            detectorRef.forceState(Config.STATE_DESCENT, now);
        }
        WatchUi.requestUpdate();
    }

    // ------------------------------------------------------------------
    // Sampling
    // ------------------------------------------------------------------

    //! 1 Hz main loop (spec §11: never faster than 1 Hz).
    function onTick() as Void {
        var now = System.getTimer();
        var info = Activity.getActivityInfo();

        var altitude = null;
        var speed = null;
        var heading = null;
        var distance = null;
        var heartRate = null;
        if (info != null) {
            altitude = info.altitude;
            speed = info.currentSpeed;
            heading = info.currentHeading;
            distance = info.elapsedDistance;
            heartRate = info.currentHeartRate;
            gpsQuality = info.currentLocationAccuracy;
        }
        currentSpeedMps = speed;

        var detectorRef = detector;
        var statsRef = stats;
        if (armed && detectorRef != null && statsRef != null) {
            var previousState = detectorRef.state;

            var last = _lastTickMs;
            if (last != null) {
                statsRef.addStateTime(previousState, now - last);
            }
            _lastTickMs = now;

            detectorRef.update(altitude, speed, heading, _freshAccelVariance(now), now);

            if (detectorRef.state == Config.STATE_DESCENT) {
                statsRef.updateRun(detectorRef.altitude(), speed, distance, heartRate, now);
            }
        }

        WatchUi.requestUpdate();
    }

    //! The accelerometer is the strongest discriminator (spec §4.1), but a
    //! stale reading is worse than none: hand the detector null so it degrades
    //! to altitude and speed instead of trusting old data.
    private function _freshAccelVariance(nowMs as Number) as Float or Null {
        var updated = _accelUpdatedMs;
        if (updated == null || nowMs - updated > Config.ACCEL_STALE_MS) {
            return null;
        }
        return _accelVarianceMg;
    }

    //! 25 Hz accelerometer callback: reduce one second of samples to the
    //! standard deviation of the magnitude (spec §4.2).
    function onAccelData(data as Sensor.SensorData) as Void {
        var accel = data.accelerometerData;
        if (accel == null) {
            return;
        }
        var xs = accel.x;
        var ys = accel.y;
        var zs = accel.z;
        if (xs == null || ys == null || zs == null) {
            return;
        }
        var count = xs.size();
        if (count > ys.size()) { count = ys.size(); }
        if (count > zs.size()) { count = zs.size(); }
        if (count < 2) {
            return;
        }

        var sum = 0.0;
        var sumSquares = 0.0;
        for (var i = 0; i < count; i++) {
            var x = xs[i].toFloat();
            var y = ys[i].toFloat();
            var z = zs[i].toFloat();
            var magnitude = Math.sqrt(x * x + y * y + z * z).toFloat();
            sum += magnitude;
            sumSquares += magnitude * magnitude;
        }
        var mean = sum / count;
        var variance = sumSquares / count - mean * mean;
        if (variance < 0.0) {
            variance = 0.0; // floating point slack around a constant signal
        }
        _accelVarianceMg = Math.sqrt(variance).toFloat();
        _accelUpdatedMs = System.getTimer();
    }

    private function _startSensors() as Void {
        if (!_positionEnabled) {
            try {
                Position.enableLocationEvents({
                    :acquisitionType => Position.LOCATION_CONTINUOUS,
                    :configuration => _gnssConfiguration()
                }, method(:onPosition));
                _positionEnabled = true;
            } catch (ex) {
                // Older firmware rejects :configuration — retry without it.
                try {
                    Position.enableLocationEvents(Position.LOCATION_CONTINUOUS,
                                                  method(:onPosition));
                    _positionEnabled = true;
                } catch (ex2) {
                    _positionEnabled = false;
                }
            }
        }

        if (!_accelRegistered) {
            try {
                Sensor.registerSensorDataListener(method(:onAccelData), {
                    :period => Config.ACCEL_PERIOD_SEC,
                    :accelerometer => {
                        :enabled => true,
                        :sampleRate => Config.ACCEL_SAMPLE_RATE
                    }
                });
                _accelRegistered = true;
            } catch (ex) {
                // No accelerometer stream: the detector falls back to
                // barometer plus speed (spec §4.4).
                _accelRegistered = false;
            }
        }
    }

    private function _stopSensors() as Void {
        if (_accelRegistered) {
            try {
                Sensor.unregisterSensorDataListener();
            } catch (ex) {
                // Nothing useful to do if unregistering fails.
            }
            _accelRegistered = false;
        }
        if (_positionEnabled) {
            try {
                Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPosition));
            } catch (ex) {
                // Nothing useful to do if disabling fails.
            }
            _positionEnabled = false;
        }
    }

    private function _gnssConfiguration() as Position.Configuration {
        if (Config.gpsMode() == Config.GPS_MULTI_BAND) {
            return Position.CONFIGURATION_GPS_GLONASS_GALILEO_BEIDOU_L1_L5;
        }
        return Position.CONFIGURATION_SAT_IQ;
    }

    //! Position fixes are consumed through `Activity.getActivityInfo()` in
    //! `onTick`; this callback only exists because the API requires one.
    function onPosition(info as Position.Info) as Void {
    }

    // ------------------------------------------------------------------
    // LiftDetector listener (spec §9)
    // ------------------------------------------------------------------

    //! Entering DESCENT: resume the timer and open a run (spec §8).
    function onRunStart(timeMs as Number) as Void {
        var statsRef = stats;
        var detectorRef = detector;
        if (statsRef == null || detectorRef == null) {
            return;
        }
        // Look back over the detection window: by the time 8 m have been lost
        // the rider is already well past the top of the run.
        var topAltitude = detectorRef.altitudeBefore(Config.DESCENT_WINDOW_SEC);
        if (topAltitude == null) {
            topAltitude = detectorRef.altitude();
        }
        statsRef.startRun(timeMs, topAltitude);
        sessionManager.startTimer();
        _vibrate(1);
    }

    //! Leaving DESCENT: close the run, write the lap and its developer field,
    //! then pause the timer (spec §8). The lap field has to be set before
    //! `addLap` so the value lands on the lap being closed.
    function onRunEnd(timeMs as Number) as Void {
        var statsRef = stats;
        if (statsRef == null) {
            return;
        }
        var run = statsRef.endRun(timeMs);
        if (run != null) {
            sessionManager.setRunDrop(run.dropM());
            sessionManager.addLap();
            sessionManager.setSessionTotals(statsRef.runCount, statsRef.totalDropM,
                                            statsRef.liftMs / 1000);
            var view = _view;
            if (view != null && Config.runSummaryEnabled()) {
                view.showRunSummary(run, System.getTimer());
            }
        }
        sessionManager.stopTimer();
        _vibrate(2);
    }

    //! Spec §5: 1 pulse on run start, 2 pulses on pause.
    private function _vibrate(pulses as Number) as Void {
        if (!Config.vibrationEnabled() || !(Attention has :vibrate)) {
            return;
        }
        if (!System.getDeviceSettings().vibrateOn) {
            return;
        }
        var profile = new Array<Attention.VibeProfile>[pulses * 2 - 1];
        for (var i = 0; i < profile.size(); i++) {
            // Alternate 300 ms buzz / 150 ms gap.
            profile[i] = i % 2 == 0
                ? new Attention.VibeProfile(75, 300)
                : new Attention.VibeProfile(0, 150);
        }
        try {
            Attention.vibrate(profile);
        } catch (ex) {
            // Vibration is cosmetic; never let it break the loop.
        }
    }
}

//! Convenience accessor for the view and the delegate.
function getApp() as DhTrackerApp {
    return Application.getApp() as DhTrackerApp;
}
