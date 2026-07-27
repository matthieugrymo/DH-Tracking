import Toybox.Lang;
import Toybox.Test;

//! Unit tests for the detector, on the synthetic sequences listed in spec §10.1.
//!
//! Everything here is annotated `(:test)` so it is compiled only with
//! `--unit-test` and never ships in the app.
//!
//! Run with:
//!   monkeyc -f monkey.jungle -d fenix7pro -o bin/dh-tracker-test.prg \
//!           -y developer_key.der --unit-test
//!   monkeydo bin/dh-tracker-test.prg fenix7pro -t

// ----------------------------------------------------------------------
// DESCENT
// ----------------------------------------------------------------------

//! Descente franche : -2 m/s, 18 km/h, accéléromètre saturé.
(:test)
function testCleanDescentStartsRun(logger as Logger) as Boolean {
    var harness = TestSupport.makeHarness(Config.LIFT_CHAIRLIFT);
    harness.feedRamp(0, 12, 1000.0, -2.0, 5.0, 300.0);

    logger.debug("state=" + harness.detector.state + " starts=" + harness.startCount);
    return harness.detector.state == Config.STATE_DESCENT
           && harness.startCount == 1
           && harness.endCount == 0;
}

//! A drop steep enough but at walking pace is not a run (spec §4.3, 5 km/h gate).
(:test)
function testDescentNeedsSpeed(logger as Logger) as Boolean {
    var harness = TestSupport.makeHarness(Config.LIFT_CHAIRLIFT);
    harness.feedRamp(0, 12, 1000.0, -2.0, 0.9, 300.0);

    logger.debug("state=" + harness.detector.state);
    return harness.detector.state == Config.STATE_IDLE && harness.startCount == 0;
}

//! A drop with a quiet accelerometer is a lift going down, not a run
//! (spec §4.1: vibration is the strongest discriminator).
(:test)
function testDescentNeedsRoughGround(logger as Logger) as Boolean {
    var harness = TestSupport.makeHarness(Config.LIFT_CHAIRLIFT);
    harness.feedRamp(0, 12, 1000.0, -2.0, 5.0, 15.0);

    logger.debug("state=" + harness.detector.state);
    return harness.detector.state == Config.STATE_IDLE && harness.startCount == 0;
}

// ----------------------------------------------------------------------
// LIFT
// ----------------------------------------------------------------------

//! Télésiège : +2 m/s linéaire, 12 km/h, accéléromètre plat.
(:test)
function testChairliftDetected(logger as Logger) as Boolean {
    var harness = TestSupport.makeHarness(Config.LIFT_CHAIRLIFT);
    harness.feedRamp(0, 25, 1000.0, 2.0, 3.3, 20.0);

    logger.debug("state=" + harness.detector.state);
    return harness.detector.state == Config.STATE_LIFT;
}

//! Téléski : montée plus lente, vibration modérée. En mode « télésiège »
//! l'accéléromètre bloque, donc la remontée n'est pas vue — c'est le cas limite
//! du spec §4.4 qui justifie le réglage.
(:test)
function testTbarMissedInChairliftMode(logger as Logger) as Boolean {
    var harness = TestSupport.makeHarness(Config.LIFT_CHAIRLIFT);
    harness.feedRamp(0, 25, 1000.0, 1.0, 2.2, 90.0);

    logger.debug("state=" + harness.detector.state);
    return harness.detector.state == Config.STATE_IDLE;
}

//! Le même téléski en mode « téléski » : la monotonie d'altitude prime,
//! l'accéléromètre ne bloque plus (spec §4.4).
(:test)
function testTbarDetectedInTbarMode(logger as Logger) as Boolean {
    var harness = TestSupport.makeHarness(Config.LIFT_TBAR);
    harness.feedRamp(0, 25, 1000.0, 1.0, 2.2, 90.0);

    logger.debug("state=" + harness.detector.state);
    return harness.detector.state == Config.STATE_LIFT;
}

//! Une liaison montante en pédalant : altitude irrégulière + accéléromètre
//! bruyant. Ne doit pas être prise pour une remontée mécanique (spec §4.3).
(:test)
function testPedallingClimbIsNotLift(logger as Logger) as Boolean {
    var harness = TestSupport.makeHarness(Config.LIFT_CHAIRLIFT);
    // Net climb, but every other second stalls, so monotonicity stays under 80 %.
    var timeMs = 0;
    var altitude = 1000.0;
    for (var i = 0; i < 30; i++) {
        harness.detector.update(altitude, 2.0, 0.0, 250.0, timeMs);
        altitude += i % 2 == 0 ? 2.0 : -0.5;
        timeMs += 1000;
    }

    logger.debug("state=" + harness.detector.state);
    return harness.detector.state == Config.STATE_IDLE;
}

// ----------------------------------------------------------------------
// DESCENT -> IDLE and mid-run stops
// ----------------------------------------------------------------------

//! Replat en cours de piste : on roule encore, le chrono ne doit pas couper.
(:test)
function testFlatSectionKeepsRunOpen(logger as Logger) as Boolean {
    var harness = TestSupport.makeHarness(Config.LIFT_CHAIRLIFT);
    var timeMs = harness.feedRamp(0, 12, 1000.0, -2.0, 5.0, 300.0);
    harness.feedRamp(timeMs, 40, 978.0, 0.0, 2.0, 250.0);

    logger.debug("state=" + harness.detector.state + " ends=" + harness.endCount);
    return harness.detector.state == Config.STATE_DESCENT && harness.endCount == 0;
}

//! Arrêt court en piste (60 s) : sous le seuil de 90 s, le chrono continue
//! (spec §4.3).
(:test)
function testShortStopKeepsRunOpen(logger as Logger) as Boolean {
    var harness = TestSupport.makeHarness(Config.LIFT_CHAIRLIFT);
    var timeMs = harness.feedRamp(0, 12, 1000.0, -2.0, 5.0, 300.0);
    harness.feedRamp(timeMs, 60, 978.0, 0.0, 0.0, 20.0);

    logger.debug("state=" + harness.detector.state + " ends=" + harness.endCount);
    return harness.detector.state == Config.STATE_DESCENT && harness.endCount == 0;
}

//! File d'attente en bas (100 s à l'arrêt, altitude stable) : passage en IDLE
//! et clôture du run (spec §4.3).
(:test)
function testQueueAtBottomEndsRun(logger as Logger) as Boolean {
    var harness = TestSupport.makeHarness(Config.LIFT_CHAIRLIFT);
    var timeMs = harness.feedRamp(0, 12, 1000.0, -2.0, 5.0, 300.0);
    harness.feedRamp(timeMs, 100, 978.0, 0.0, 0.0, 20.0);

    logger.debug("state=" + harness.detector.state + " ends=" + harness.endCount);
    return harness.detector.state == Config.STATE_IDLE
           && harness.startCount == 1
           && harness.endCount == 1;
}

// ----------------------------------------------------------------------
// Robustness (spec §4.4)
// ----------------------------------------------------------------------

//! Bruit baro seul : aucune transition, quelle que soit la vibration.
(:test)
function testBaroNoiseTriggersNothing(logger as Logger) as Boolean {
    var harness = TestSupport.makeHarness(Config.LIFT_CHAIRLIFT);
    harness.feedNoise(0, 60, 1000.0, 2.0, 5.0, 300.0);

    logger.debug("state=" + harness.detector.state);
    return harness.detector.state == Config.STATE_IDLE
           && harness.startCount == 0
           && harness.endCount == 0;
}

//! Perte GPS : `speed == null` est une condition non satisfaite, sans crash ni
//! changement d'état (spec §4.4).
(:test)
function testNullSpeedBlocksDescentWithoutCrashing(logger as Logger) as Boolean {
    var harness = TestSupport.makeHarness(Config.LIFT_CHAIRLIFT);
    harness.feedRamp(0, 20, 1000.0, -2.0, null, 300.0);

    logger.debug("state=" + harness.detector.state);
    return harness.detector.state == Config.STATE_IDLE && harness.startCount == 0;
}

//! Perte GPS en pleine descente : le run reste ouvert, pas de crash.
(:test)
function testNullSpeedMidRunKeepsRunOpen(logger as Logger) as Boolean {
    var harness = TestSupport.makeHarness(Config.LIFT_CHAIRLIFT);
    var timeMs = harness.feedRamp(0, 12, 1000.0, -2.0, 5.0, 300.0);
    harness.feedRamp(timeMs, 30, 978.0, -2.0, null, 300.0);

    logger.debug("state=" + harness.detector.state + " ends=" + harness.endCount);
    return harness.detector.state == Config.STATE_DESCENT && harness.endCount == 0;
}

//! `altitude == null` au démarrage : pas de crash, pas de transition
//! (critère d'acceptation §11).
(:test)
function testNullAltitudeIsSafe(logger as Logger) as Boolean {
    var harness = TestSupport.makeHarness(Config.LIFT_CHAIRLIFT);
    var timeMs = harness.feedNullAltitude(0, 10);

    var stateAfterNulls = harness.detector.state;
    var altitudeAfterNulls = harness.detector.altitude();

    // The barometer comes online: detection must work from there.
    harness.feedRamp(timeMs, 12, 1000.0, -2.0, 5.0, 300.0);

    logger.debug("state=" + harness.detector.state);
    return stateAfterNulls == Config.STATE_IDLE
           && altitudeAfterNulls == null
           && harness.detector.state == Config.STATE_DESCENT;
}

//! Hystérésis : état verrouillé 10 s après chaque transition (spec §4.4).
(:test)
function testHysteresisLocksStateFor10s(logger as Logger) as Boolean {
    var harness = TestSupport.makeHarness(Config.LIFT_CHAIRLIFT);
    harness.detector.forceState(Config.STATE_DESCENT, 1000);

    var lockedDuring = harness.detector.isLocked(5000);
    var lockedAtEdge = harness.detector.isLocked(10999);
    var freeAfter = harness.detector.isLocked(11001);

    logger.debug("during=" + lockedDuring + " edge=" + lockedAtEdge
                 + " after=" + freeAfter);
    return lockedDuring && lockedAtEdge && !freeAfter;
}

//! Forçage manuel (spec §6) : émet bien les événements de run.
(:test)
function testForceStateEmitsRunEvents(logger as Logger) as Boolean {
    var harness = TestSupport.makeHarness(Config.LIFT_CHAIRLIFT);
    harness.detector.forceState(Config.STATE_DESCENT, 1000);
    harness.detector.forceState(Config.STATE_LIFT, 60000);

    logger.debug("starts=" + harness.startCount + " ends=" + harness.endCount);
    return harness.startCount == 1
           && harness.endCount == 1
           && harness.lastStartMs == 1000
           && harness.lastEndMs == 60000;
}

//! `altitudeBefore` permet de retrouver le haut de la piste : la descente n'est
//! reconnue qu'après 8 m de perte, il faut donc remonter la fenêtre de détection.
(:test)
function testAltitudeBeforeRecoversTopOfRun(logger as Logger) as Boolean {
    var harness = TestSupport.makeHarness(Config.LIFT_CHAIRLIFT);
    // -2 m/s from 1000 m; the run is detected at t = 6 s, at ~990 m smoothed.
    harness.feedRamp(0, 12, 1000.0, -2.0, 5.0, 300.0);

    var now = harness.detector.altitude();
    var top = harness.detector.altitudeBefore(Config.DESCENT_WINDOW_SEC);
    var tooFarBack = harness.detector.altitudeBefore(600);

    logger.debug("now=" + now + " top=" + top + " tooFarBack=" + tooFarBack);
    return now != null && top != null
           && top > now
           && TestSupport.nearlyEqual(top - now, 12.0, 0.01)
           && tooFarBack == null;
}

//! Avant le premier échantillon utilisable, `altitudeBefore` renvoie null.
(:test)
function testAltitudeBeforeIsNullWithoutHistory(logger as Logger) as Boolean {
    var harness = TestSupport.makeHarness(Config.LIFT_CHAIRLIFT);

    logger.debug("before=" + harness.detector.altitudeBefore(6));
    return harness.detector.altitudeBefore(6) == null;
}

//! `reset()` repart d'un état propre sans émettre d'événement.
(:test)
function testResetClearsHistory(logger as Logger) as Boolean {
    var harness = TestSupport.makeHarness(Config.LIFT_CHAIRLIFT);
    harness.feedRamp(0, 12, 1000.0, -2.0, 5.0, 300.0);
    harness.detector.reset();

    logger.debug("state=" + harness.detector.state);
    return harness.detector.state == Config.STATE_IDLE
           && harness.detector.altitude() == null
           && harness.startCount == 1;
}

// ----------------------------------------------------------------------
// Thresholds and settings (spec §7)
// ----------------------------------------------------------------------

//! Sensibilité basse (x1.5) : plus difficile à déclencher dans les deux sens.
(:test)
function testLowSensitivityRaisesThresholds(logger as Logger) as Boolean {
    var thresholds = TestSupport.makeThresholds(Config.SENS_LOW, Config.LIFT_CHAIRLIFT);
    var rough = thresholds.accelRoughMg;
    var smooth = thresholds.accelSmoothMg;
    if (rough == null || smooth == null) {
        logger.error("both accel gates stay enabled in chairlift mode");
        return false;
    }

    logger.debug("drop=" + thresholds.descentDropM + " gain=" + thresholds.liftGainM
                 + " rough=" + rough + " smooth=" + smooth);
    return TestSupport.nearlyEqual(thresholds.descentDropM, 12.0, 0.001)
           && TestSupport.nearlyEqual(thresholds.liftGainM, 15.0, 0.001)
           && TestSupport.nearlyEqual(rough, 180.0, 0.001)
           && TestSupport.nearlyEqual(smooth, 40.0, 0.001);
}

//! Sensibilité haute (x0.7) : plus facile à déclencher dans les deux sens.
(:test)
function testHighSensitivityLowersThresholds(logger as Logger) as Boolean {
    var thresholds = TestSupport.makeThresholds(Config.SENS_HIGH, Config.LIFT_CHAIRLIFT);
    var rough = thresholds.accelRoughMg;
    var smooth = thresholds.accelSmoothMg;
    if (rough == null || smooth == null) {
        logger.error("both accel gates stay enabled in chairlift mode");
        return false;
    }

    logger.debug("drop=" + thresholds.descentDropM + " rough=" + rough
                 + " smooth=" + smooth);
    return TestSupport.nearlyEqual(thresholds.descentDropM, 5.6, 0.001)
           && TestSupport.nearlyEqual(thresholds.liftGainM, 7.0, 0.001)
           && TestSupport.nearlyEqual(rough, 84.0, 0.001)
           && TestSupport.nearlyEqual(smooth, 85.714, 0.01);
}

//! Une sensibilité basse doit rendre la descente plus dure à déclencher :
//! -1.5 m/s (9 m sur 6 s) passe en normale, pas en basse.
(:test)
function testLowSensitivityRejectsShallowDescent(logger as Logger) as Boolean {
    var normal = new DetectorHarness(
        TestSupport.makeThresholds(Config.SENS_NORMAL, Config.LIFT_CHAIRLIFT));
    var low = new DetectorHarness(
        TestSupport.makeThresholds(Config.SENS_LOW, Config.LIFT_CHAIRLIFT));

    normal.feedRamp(0, 12, 1000.0, -1.5, 5.0, 300.0);
    low.feedRamp(0, 12, 1000.0, -1.5, 5.0, 300.0);

    logger.debug("normal=" + normal.detector.state + " low=" + low.detector.state);
    return normal.detector.state == Config.STATE_DESCENT
           && low.detector.state == Config.STATE_IDLE;
}

//! Mode mixte : le seuil accéléromètre est relâché mais reste bloquant.
(:test)
function testMixedModeRelaxesAccelGate(logger as Logger) as Boolean {
    var mixed = TestSupport.makeThresholds(Config.SENS_NORMAL, Config.LIFT_MIXED);
    var smooth = mixed.accelSmoothMg;

    logger.debug("smooth=" + smooth + " ratio=" + mixed.liftMonotonicRatio);
    return smooth != null
           && TestSupport.nearlyEqual(smooth, 120.0, 0.001)
           && TestSupport.nearlyEqual(mixed.liftMonotonicRatio, 0.8, 0.001);
}

//! Mode téléski : plus de plafond accéléromètre, monotonie plus stricte.
(:test)
function testTbarModeDropsAccelGate(logger as Logger) as Boolean {
    var tbar = TestSupport.makeThresholds(Config.SENS_NORMAL, Config.LIFT_TBAR);

    logger.debug("smooth=" + tbar.accelSmoothMg + " ratio=" + tbar.liftMonotonicRatio);
    return tbar.accelSmoothMg == null
           && TestSupport.nearlyEqual(tbar.liftMonotonicRatio, 0.9, 0.001);
}

//! Sans accéléromètre (capteur indisponible), la détection doit dégrader
//! proprement sur baro + vitesse plutôt que de ne plus rien voir (spec §4.4).
(:test)
function testDetectionDegradesWithoutAccelerometer(logger as Logger) as Boolean {
    var harness = TestSupport.makeHarness(Config.LIFT_CHAIRLIFT);
    harness.feedRamp(0, 12, 1000.0, -2.0, 5.0, null);

    logger.debug("state=" + harness.detector.state);
    return harness.detector.state == Config.STATE_DESCENT && harness.startCount == 1;
}

//! Une journée complète : 3 descentes séparées par 2 remontées.
(:test)
function testFullDaySequence(logger as Logger) as Boolean {
    var harness = TestSupport.makeHarness(Config.LIFT_CHAIRLIFT);
    var timeMs = 0;
    var altitude = 2000.0;

    for (var run = 0; run < 3; run++) {
        // 150 s of descent at -2 m/s => 300 m of drop.
        timeMs = harness.feedRamp(timeMs, 150, altitude, -2.0, 8.0, 300.0);
        altitude -= 300.0;
        if (run < 2) {
            // 150 s of chairlift at +2 m/s back to the top.
            timeMs = harness.feedRamp(timeMs, 150, altitude, 2.0, 3.3, 20.0);
            altitude += 300.0;
        }
    }

    logger.debug("starts=" + harness.startCount + " ends=" + harness.endCount
                 + " state=" + harness.detector.state);
    return harness.startCount == 3
           && harness.endCount == 2
           && harness.detector.state == Config.STATE_DESCENT;
}
