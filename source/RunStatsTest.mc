import Toybox.Lang;
import Toybox.Test;

//! Unit tests for the per-run and per-day accumulators (spec §3.1, §3.2).

//! Dénivelé négatif = altitude au départ - altitude en fin de run (spec §3.1).
(:test)
function testRunDropIsStartMinusEnd(logger as Logger) as Boolean {
    var run = new RunStats(1, 0, 1500.0);
    TestSupport.feedRun(run, 100, 1500.0, -2.0, 10.0, 150);
    run.close(100000);

    logger.debug("drop=" + run.dropM() + " duration=" + run.durationSec());
    return TestSupport.nearlyEqual(run.dropM(), 200.0, 0.01) && run.durationSec() == 100;
}

//! Un run qui ne fait que monter ne retire rien à la journée.
(:test)
function testRunDropIsClampedAtZero(logger as Logger) as Boolean {
    var run = new RunStats(1, 0, 1000.0);
    TestSupport.feedRun(run, 10, 1000.0, 1.0, 5.0, null);
    run.close(10000);

    logger.debug("drop=" + run.dropM());
    return TestSupport.nearlyEqual(run.dropM(), 0.0, 0.001);
}

//! Le dénivelé se mesure jusqu'au point le plus bas, pas jusqu'à l'altitude au
//! moment où la machine à états bascule : la détection de remontée arrive ~20 s
//! après l'embarquement, et le télésiège a déjà grimpé (voir `RunStats.dropM`).
(:test)
function testRunDropIgnoresLiftClimbAfterBottom(logger as Logger) as Boolean {
    var run = new RunStats(1, 0, 1500.0);
    // 200 m of descent down to 1300 m...
    TestSupport.feedRun(run, 100, 1500.0, -2.0, 10.0, null);
    // ...then 20 s of chairlift at +2 m/s before the transition is seen.
    var timeMs = 100000;
    for (var i = 1; i <= 20; i++) {
        timeMs += 1000;
        run.update(1300.0 + 2.0 * i, 3.0, null, null, timeMs);
    }
    run.close(timeMs);

    logger.debug("drop=" + run.dropM() + " lowest=" + run.lowestAltitudeM
                 + " end=" + run.endAltitudeM);
    return TestSupport.nearlyEqual(run.dropM(), 200.0, 0.01)
           && TestSupport.nearlyEqual(run.lowestAltitudeM, 1300.0, 0.01)
           && TestSupport.nearlyEqual(run.endAltitudeM, 1340.0, 0.01);
}

//! Distance, vitesse moyenne et vitesse max sur le run (spec §3.1).
//!
//! Les 101 échantillons couvrent 1010 m de distance cumulée, mais le premier
//! ne sert qu'à poser la référence — comme sur la montre, où la distance à
//! l'instant exact du départ du run n'est pas connue. D'où 1000 m sur 101 s.
(:test)
function testRunSpeedMetrics(logger as Logger) as Boolean {
    var run = new RunStats(1, 0, 1000.0);
    TestSupport.feedRun(run, 100, 1000.0, -1.0, 10.0, null);
    // One faster sample so the max diverges from the average.
    run.update(899.0, 18.0, 1010.0, null, 101000);
    run.close(101000);

    logger.debug("dist=" + run.distanceM + " avg=" + run.avgSpeedMps()
                 + " max=" + run.maxSpeedMps);
    return TestSupport.nearlyEqual(run.distanceM, 1000.0, 0.01)
           && TestSupport.nearlyEqual(run.avgSpeedMps(), 9.901, 0.001)
           && TestSupport.nearlyEqual(run.maxSpeedMps, 18.0, 0.001);
}

//! Vitesse verticale en m/h (spec §3.1) : 200 m en 100 s => 7200 m/h.
(:test)
function testVerticalSpeed(logger as Logger) as Boolean {
    var run = new RunStats(1, 0, 1500.0);
    TestSupport.feedRun(run, 100, 1500.0, -2.0, 10.0, null);
    run.close(100000);

    logger.debug("vspeed=" + run.verticalSpeedMph());
    return TestSupport.nearlyEqual(run.verticalSpeedMph(), 7200.0, 1.0);
}

//! Pente moyenne = dénivelé / distance *horizontale* (spec §3.1).
//! 100 m de dénivelé sur 500 m parcourus => horizontale 489.9 m => 20.4 %.
(:test)
function testAvgSlopeUsesHorizontalDistance(logger as Logger) as Boolean {
    var run = new RunStats(1, 0, 1000.0);
    run.update(1000.0, 10.0, 0.0, null, 1000);    // establishes the distance baseline
    run.update(900.0, 10.0, 500.0, null, 50000);  // 500 m travelled, 100 m of drop
    run.close(50000);

    logger.debug("slope=" + run.avgSlopePct() + " dist=" + run.distanceM);
    return TestSupport.nearlyEqual(run.avgSlopePct(), 20.41, 0.05);
}

//! Une distance nulle ou incohérente ne doit pas produire de division par zéro.
(:test)
function testDegenerateRunHasNoDivisionByZero(logger as Logger) as Boolean {
    var run = new RunStats(1, 5000, 1000.0);

    logger.debug("avg=" + run.avgSpeedMps() + " slope=" + run.avgSlopePct()
                 + " vspeed=" + run.verticalSpeedMph() + " hr=" + run.avgHeartRate());
    return TestSupport.nearlyEqual(run.avgSpeedMps(), 0.0, 0.001)
           && TestSupport.nearlyEqual(run.avgSlopePct(), 0.0, 0.001)
           && TestSupport.nearlyEqual(run.verticalSpeedMph(), 0.0, 0.001)
           && run.avgHeartRate() == 0;
}

//! FC moyenne et max sur le run (spec §3.1). Les zéros sont ignorés.
(:test)
function testHeartRateMetrics(logger as Logger) as Boolean {
    var run = new RunStats(1, 0, 1000.0);
    run.update(998.0, 5.0, 5.0, 120, 1000);
    run.update(996.0, 5.0, 10.0, 160, 2000);
    run.update(994.0, 5.0, 15.0, 0, 3000);
    run.update(992.0, 5.0, 20.0, null, 4000);
    run.close(4000);

    logger.debug("avg=" + run.avgHeartRate() + " max=" + run.maxHeartRate);
    return run.avgHeartRate() == 140 && run.maxHeartRate == 160;
}

//! Sans distance cumulée (GPS perdu), la distance se replie sur l'intégration
//! de la vitesse.
(:test)
function testDistanceFallsBackToSpeedIntegration(logger as Logger) as Boolean {
    var run = new RunStats(1, 0, 1000.0);
    for (var i = 1; i <= 10; i++) {
        run.update(1000.0 - i, 8.0, null, null, i * 1000);
    }
    run.close(10000);

    logger.debug("dist=" + run.distanceM);
    return TestSupport.nearlyEqual(run.distanceM, 80.0, 0.01);
}

//! Une distance cumulée qui régresse (recalage GPS) ne doit pas soustraire.
(:test)
function testCumulativeDistanceNeverDecreases(logger as Logger) as Boolean {
    var run = new RunStats(1, 0, 1000.0);
    run.update(998.0, 5.0, 100.0, null, 1000);
    run.update(996.0, 5.0, 200.0, null, 2000);
    run.update(994.0, 5.0, 150.0, null, 3000);
    run.update(992.0, 5.0, 260.0, null, 4000);
    run.close(4000);

    logger.debug("dist=" + run.distanceM);
    // 200 -> 150 contributes nothing; 150 -> 260 adds 110 on top of the first 100.
    return TestSupport.nearlyEqual(run.distanceM, 210.0, 0.01);
}

// ----------------------------------------------------------------------
// Day aggregates (spec §3.2)
// ----------------------------------------------------------------------

//! Nombre de descentes, dénivelé total, distance totale, meilleure descente.
(:test)
function testSessionAggregates(logger as Logger) as Boolean {
    var stats = new SessionStats(0);

    var first = stats.startRun(0, 2000.0);
    TestSupport.feedRun(first, 100, 2000.0, -2.0, 10.0, null);
    stats.updateRun(1800.0, 10.0, 1000.0, null, 100000);
    stats.endRun(100000);

    var second = stats.startRun(200000, 1900.0);
    TestSupport.feedRun(second, 50, 1900.0, -6.0, 12.0, null);
    stats.updateRun(1600.0, 20.0, 600.0, null, 250000);
    stats.endRun(250000);

    var best = stats.bestRun;
    logger.debug("runs=" + stats.runCount + " drop=" + stats.totalDropM
                 + " descent=" + stats.totalDescentMs
                 + " best=" + (best == null ? -1 : best.index));

    return stats.runCount == 2
           && TestSupport.nearlyEqual(stats.totalDropM, 500.0, 0.5)
           && stats.totalDescentMs == 150000
           && TestSupport.nearlyEqual(stats.maxSpeedMps, 20.0, 0.001)
           && best != null
           && best.index == 2;
}

//! Temps de remontée et temps d'arrêt sont comptés séparément (spec §3.2).
(:test)
function testStateTimeAccounting(logger as Logger) as Boolean {
    var stats = new SessionStats(0);
    stats.addStateTime(Config.STATE_LIFT, 60000);
    stats.addStateTime(Config.STATE_IDLE, 30000);
    stats.addStateTime(Config.STATE_DESCENT, 90000); // ignored: comes from runs
    stats.addStateTime(Config.STATE_LIFT, -5000);    // clock skew, ignored

    logger.debug("lift=" + stats.liftMs + " idle=" + stats.idleMs);
    return stats.liftMs == 60000 && stats.idleMs == 30000;
}

//! Le temps de descente inclut le run en cours.
(:test)
function testDescentMsIncludesRunInProgress(logger as Logger) as Boolean {
    var stats = new SessionStats(0);
    var first = stats.startRun(0, 1000.0);
    TestSupport.feedRun(first, 60, 1000.0, -2.0, 10.0, null);
    stats.endRun(60000);

    var second = stats.startRun(100000, 900.0);
    TestSupport.feedRun(second, 30, 900.0, -2.0, 10.0, null);

    logger.debug("descent=" + stats.descentMs());
    return stats.descentMs() == 90000;
}

//! Ratio descente / journée (spec §3.2).
(:test)
function testDescentRatio(logger as Logger) as Boolean {
    var stats = new SessionStats(0);
    var run = stats.startRun(0, 1000.0);
    TestSupport.feedRun(run, 100, 1000.0, -2.0, 10.0, null);
    stats.endRun(100000);

    logger.debug("ratio=" + stats.descentRatioPct(400000));
    return TestSupport.nearlyEqual(stats.descentRatioPct(400000), 25.0, 0.01)
           && TestSupport.nearlyEqual(stats.descentRatioPct(0), 0.0, 0.001);
}

//! Clôturer sans run ouvert renvoie null au lieu de planter.
(:test)
function testEndRunWithoutOpenRun(logger as Logger) as Boolean {
    var stats = new SessionStats(0);
    var result = stats.endRun(1000);

    logger.debug("result=" + result);
    return result == null && stats.runCount == 0;
}

//! Une altitude nulle au départ d'un run ne doit pas planter (spec §11).
(:test)
function testStartRunWithNullAltitude(logger as Logger) as Boolean {
    var stats = new SessionStats(0);
    var run = stats.startRun(0, null);
    run.update(null, null, null, null, 1000);
    stats.endRun(1000);

    logger.debug("drop=" + run.dropM() + " runs=" + stats.runCount);
    return stats.runCount == 1 && TestSupport.nearlyEqual(run.dropM(), 0.0, 0.001);
}

// ----------------------------------------------------------------------
// Formatting helpers used by the view
// ----------------------------------------------------------------------

(:test)
function testFormatDuration(logger as Logger) as Boolean {
    logger.debug(formatDuration(0) + " " + formatDuration(65000) + " "
                 + formatDuration(3725000) + " " + formatDuration(-1000));
    return formatDuration(0).equals("0:00")
           && formatDuration(65000).equals("1:05")
           && formatDuration(3725000).equals("1:02:05")
           && formatDuration(-1000).equals("0:00");
}

(:test)
function testFormatSpeed(logger as Logger) as Boolean {
    logger.debug(formatSpeed(null) + " " + formatSpeed(10.0));
    return formatSpeed(null).equals("--") && formatSpeed(10.0).equals("36.0");
}

//! Les mètres sont arrondis, pas tronqués — `Float.format("%d")` tronque.
(:test)
function testFormatMeters(logger as Logger) as Boolean {
    logger.debug(formatMeters(215.7) + " " + formatMeters(215.2) + " "
                 + formatMeters(0.0));
    return formatMeters(215.7).equals("216")
           && formatMeters(215.2).equals("215")
           && formatMeters(0.0).equals("0");
}
