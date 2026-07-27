import Toybox.Lang;
import Toybox.Graphics;
import Toybox.Position;
import Toybox.System;
import Toybox.WatchUi;

//! The two ski-style screens plus the end-of-run summary card (spec §5).
//!
//! Black background, large glyphs, readable in full sun on a MIP display.
//!
//! The supported products span two screen families — round-240x240 (7S, 7S Pro)
//! and round-260x260 (7, 7X and the Pro/Solar Edition variants) — so no
//! position is hardcoded: every one derives from `dc.getWidth()` /
//! `dc.getHeight()`, which also keeps AMOLED models working (spec §12).
class DhTrackerView extends WatchUi.View {

    public const PAGE_RUN = 0;
    public const PAGE_DAY = 1;
    private const PAGE_COUNT = 2;

    private var _page as Number = PAGE_RUN;
    private var _summaryRun as RunStats or Null = null;
    private var _summaryUntilMs as Number or Null = null;

    function initialize() {
        View.initialize();
    }

    function nextPage() as Void {
        _page = (_page + 1) % PAGE_COUNT;
    }

    function previousPage() as Void {
        _page = (_page + PAGE_COUNT - 1) % PAGE_COUNT;
    }

    //! Show the finished run's stats for 5 s, exactly like the ski profile
    //! (spec §5).
    function showRunSummary(run as RunStats, nowMs as Number) as Void {
        _summaryRun = run;
        _summaryUntilMs = nowMs + Config.RUN_SUMMARY_MS;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        if (_summaryVisible()) {
            _drawRunSummary(dc);
        } else if (_page == PAGE_DAY) {
            _drawDayScreen(dc);
        } else {
            _drawRunScreen(dc);
        }
    }

    private function _summaryVisible() as Boolean {
        var until = _summaryUntilMs;
        if (until == null || _summaryRun == null) {
            return false;
        }
        if (System.getTimer() >= until) {
            _summaryUntilMs = null;
            _summaryRun = null;
            return false;
        }
        return true;
    }

    // ------------------------------------------------------------------
    // Screen 1 — run in progress (spec §5)
    // ------------------------------------------------------------------

    private function _drawRunScreen(dc as Graphics.Dc) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var app = $.getApp();
        var stats = app.stats;
        var detector = app.detector;
        var state = detector == null ? Config.STATE_IDLE : detector.state;

        _drawStatusBand(dc, width, height, app, state);

        var run = stats == null ? null : stats.currentRun;
        var durationMs = run == null ? 0 : run.durationMs();
        var dropM = run == null ? 0.0 : run.dropM();

        _drawBigValue(dc, width, (height * 0.40).toNumber(), formatDuration(durationMs),
                      state == Config.STATE_DESCENT
                          ? Graphics.COLOR_WHITE : Graphics.COLOR_LT_GRAY);

        var speed = app.currentSpeedMps;
        _drawLabelledValue(dc, width, (height * 0.63).toNumber(),
                           WatchUi.loadResource($.Rez.Strings.LabelSpeed) as String,
                           formatSpeed(speed),
                           WatchUi.loadResource($.Rez.Strings.UnitKmh) as String);

        _drawLabelledValue(dc, width, (height * 0.83).toNumber(),
                           WatchUi.loadResource($.Rez.Strings.LabelDrop) as String,
                           formatMeters(dropM),
                           WatchUi.loadResource($.Rez.Strings.UnitMeter) as String);
    }

    //! Inverted band while descending, grey while paused (spec §5).
    private function _drawStatusBand(dc as Graphics.Dc, width as Number,
                                     height as Number, app as DhTrackerApp,
                                     state as Number) as Void {
        var bandHeight = (height * 0.18).toNumber();
        var background = Graphics.COLOR_DK_GRAY;
        var foreground = Graphics.COLOR_LT_GRAY;
        var text;

        if (!app.armed) {
            text = WatchUi.loadResource($.Rez.Strings.StateReady) as String;
        } else if (state == Config.STATE_DESCENT) {
            background = Graphics.COLOR_WHITE;
            foreground = Graphics.COLOR_BLACK;
            var stats = app.stats;
            var number = stats == null ? 0 : stats.runCount;
            text = (WatchUi.loadResource($.Rez.Strings.StateDescent) as String) + number;
        } else if (state == Config.STATE_LIFT) {
            text = WatchUi.loadResource($.Rez.Strings.StateLift) as String;
        } else {
            text = WatchUi.loadResource($.Rez.Strings.StateIdle) as String;
        }

        dc.setColor(background, background);
        dc.fillRectangle(0, 0, width, bandHeight);
        dc.setColor(foreground, background);
        dc.drawText(width / 2, bandHeight / 2, Graphics.FONT_TINY, text,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // ------------------------------------------------------------------
    // Screen 2 — the day (spec §5)
    // ------------------------------------------------------------------

    private function _drawDayScreen(dc as Graphics.Dc) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var app = $.getApp();
        var stats = app.stats;
        var bandHeight = (height * 0.18).toNumber();

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_DK_GRAY);
        dc.fillRectangle(0, 0, width, bandHeight);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_DK_GRAY);
        dc.drawText(width / 2, bandHeight / 2, Graphics.FONT_TINY,
                    WatchUi.loadResource($.Rez.Strings.ScreenDay) as String,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        var runs = stats == null ? 0 : stats.runCount;
        var drop = stats == null ? 0.0 : stats.totalDropM;
        var descentMs = stats == null ? 0 : stats.descentMs();
        var maxSpeed = stats == null ? 0.0 : stats.maxSpeedMps;

        _drawRow(dc, width, (height * 0.29).toNumber(),
                 WatchUi.loadResource($.Rez.Strings.LabelRuns) as String,
                 runs.toString());
        _drawRow(dc, width, (height * 0.43).toNumber(),
                 WatchUi.loadResource($.Rez.Strings.LabelDrop) as String,
                 formatMeters(drop) + " "
                     + (WatchUi.loadResource($.Rez.Strings.UnitMeter) as String));
        _drawRow(dc, width, (height * 0.57).toNumber(),
                 WatchUi.loadResource($.Rez.Strings.LabelTime) as String,
                 formatDuration(descentMs));
        _drawRow(dc, width, (height * 0.71).toNumber(),
                 WatchUi.loadResource($.Rez.Strings.LabelMaxSpeed) as String,
                 formatSpeed(maxSpeed) + " "
                     + (WatchUi.loadResource($.Rez.Strings.UnitKmh) as String));

        _drawStatusFooter(dc, width, height, app);
    }

    //! GPS quality dots on the left, battery percentage on the right.
    private function _drawStatusFooter(dc as Graphics.Dc, width as Number,
                                       height as Number, app as DhTrackerApp) as Void {
        var y = (height * 0.88).toNumber();
        var quality = app.gpsQuality;
        var bars = 0;
        if (quality != null) {
            if (quality == Position.QUALITY_GOOD) {
                bars = 3;
            } else if (quality == Position.QUALITY_USABLE) {
                bars = 2;
            } else if (quality == Position.QUALITY_POOR) {
                bars = 1;
            }
        }

        var radius = 4;
        var spacing = radius * 3;
        var startX = (width * 0.32).toNumber();
        for (var i = 0; i < 3; i++) {
            dc.setColor(i < bars ? Graphics.COLOR_GREEN : Graphics.COLOR_DK_GRAY,
                        Graphics.COLOR_BLACK);
            dc.fillCircle(startX + i * spacing, y, radius);
        }

        var battery = System.getSystemStats().battery;
        dc.setColor(battery < 15.0 ? Graphics.COLOR_RED : Graphics.COLOR_LT_GRAY,
                    Graphics.COLOR_BLACK);
        dc.drawText((width * 0.68).toNumber(), y, Graphics.FONT_XTINY,
                    battery.format("%.0f") + "%",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // ------------------------------------------------------------------
    // End-of-run summary card (spec §5)
    // ------------------------------------------------------------------

    private function _drawRunSummary(dc as Graphics.Dc) as Void {
        var run = _summaryRun;
        if (run == null) {
            return;
        }
        var width = dc.getWidth();
        var height = dc.getHeight();
        var bandHeight = (height * 0.18).toNumber();

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_WHITE);
        dc.fillRectangle(0, 0, width, bandHeight);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
        dc.drawText(width / 2, bandHeight / 2, Graphics.FONT_TINY,
                    (WatchUi.loadResource($.Rez.Strings.StateDescent) as String) + run.index,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        _drawLabelledValue(dc, width, (height * 0.36).toNumber(),
                           WatchUi.loadResource($.Rez.Strings.LabelDrop) as String,
                           formatMeters(run.dropM()),
                           WatchUi.loadResource($.Rez.Strings.UnitMeter) as String);
        _drawLabelledValue(dc, width, (height * 0.58).toNumber(),
                           WatchUi.loadResource($.Rez.Strings.LabelTime) as String,
                           formatDuration(run.durationMs()), "");
        _drawLabelledValue(dc, width, (height * 0.80).toNumber(),
                           WatchUi.loadResource($.Rez.Strings.LabelMaxSpeed) as String,
                           formatSpeed(run.maxSpeedMps),
                           WatchUi.loadResource($.Rez.Strings.UnitKmh) as String);
    }

    // ------------------------------------------------------------------
    // Drawing helpers
    // ------------------------------------------------------------------

    private function _drawBigValue(dc as Graphics.Dc, width as Number, y as Number,
                                  text as String, color as Graphics.ColorType) as Void {
        dc.setColor(color, Graphics.COLOR_BLACK);
        dc.drawText(width / 2, y, Graphics.FONT_NUMBER_HOT, text,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! Small grey label above a large value, optionally suffixed with a unit.
    private function _drawLabelledValue(dc as Graphics.Dc, width as Number, y as Number,
                                        label as String, value as String,
                                        unit as String) as Void {
        var labelHeight = dc.getFontHeight(Graphics.FONT_XTINY);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        dc.drawText(width / 2, y - labelHeight, Graphics.FONT_XTINY, label,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        var text = unit.length() > 0 ? value + " " + unit : value;
        dc.drawText(width / 2, y + labelHeight / 2, Graphics.FONT_NUMBER_MILD, text,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! Label left, value right — used for the day totals.
    private function _drawRow(dc as Graphics.Dc, width as Number, y as Number,
                              label as String, value as String) as Void {
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        dc.drawText((width * 0.14).toNumber(), y, Graphics.FONT_XTINY, label,
                    Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText((width * 0.86).toNumber(), y, Graphics.FONT_SMALL, value,
                    Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}

//! "m:ss" below an hour, "h:mm:ss" above.
function formatDuration(durationMs as Number) as String {
    var totalSeconds = durationMs / 1000;
    if (totalSeconds < 0) {
        totalSeconds = 0;
    }
    var hours = totalSeconds / 3600;
    var minutes = totalSeconds / 60 % 60;
    var seconds = totalSeconds % 60;
    if (hours > 0) {
        return hours.format("%d") + ":" + minutes.format("%02d") + ":"
               + seconds.format("%02d");
    }
    return minutes.format("%d") + ":" + seconds.format("%02d");
}

//! Whole metres, rounded. `Float.format("%d")` truncates instead of rounding,
//! so the explicit "%.0f" matters on values like 215.7 m.
function formatMeters(meters as Float) as String {
    return meters.format("%.0f");
}

//! Metres per second to km/h, one decimal. Null (no GPS fix) shows as "--".
function formatSpeed(speedMps as Float or Null) as String {
    if (speedMps == null) {
        return "--";
    }
    return (speedMps * 3.6).format("%.1f");
}
