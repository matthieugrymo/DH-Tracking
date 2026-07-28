# Spécification — App Connect IQ « DH Tracker »

## 1. Objectif

Développer une **Device App Connect IQ** pour Garmin **Fenix 7 / 7S / 7X** (séries standard et Pro) qui enregistre une journée de VTT de descente en **lift-served** (remontées mécaniques) selon le **modèle du profil Ski alpin de Garmin** : découpage automatique en descentes (« runs »), et statistiques par run.

**Révisé.** Le comportement par défaut reproduit le **modèle ski** : le chrono et le dénivelé positif excluent les remontées. C'est le point important — compter le D+ des remontées polluerait le cumul de dénivelé VTT, exactement ce que le profil Ski alpin évite.

Ce défaut n'est pas une approximation du profil natif, c'en est le comportement exact. Le profil Ski alpin de Garmin met son chrono en pause dès que la descente cesse, le laisse en pause pendant toute la remontée, et sa trace relie le bas d'une descente au haut de la suivante par une ligne droite — il ne suit pas le câble (manuels Garmin « Viewing Your Ski Runs » et « Going Downhill Skiing or Snowboarding »). Une app Connect IQ peut donc le cloner tel quel, et c'est ce que fait `RECORDING_DESCENT_ONLY`.

Connect IQ n'offre qu'un seul levier : le chrono tourne, ou pas. `Activity.Info.totalAscent` est en lecture seule et une `Session` n'expose que start/stop/addLap/save/discard. La montre accumule le temps **et** le dénivelé exactement pendant que le chrono tourne, et une session arrêtée n'écrit aucun point. Trois conséquences n'en font donc qu'une : temps d'activité hors remontées, D+ hors remontées, et trou dans la trace GPS. Elles sont indissociables — mais c'est sans conséquence ici, puisque le modèle ski veut précisément les trois ensemble.

La trace montre donc chaque descente reliée par une ligne droite, comme sur une activité Ski alpin. Comme un câble est rectiligne entre pylônes (§4.1), ce raccord suit à peu près le tracé de la remontée. Le réglage « Enregistrement › Journée complète » permet l'inverse : trace continue, mais D+ et temps d'activité incluant les remontées.

Seul écart résiduel avec le natif : la **latence de détection** (§4.3), le firmware basculant plus tôt qu'une boucle à 1 Hz.

Aucune interaction utilisateur entre le START du matin et le STOP du soir.

## 2. Contexte technique

- **Cible** : Garmin Fenix 7 Pro Solar (`fenix7pro` ; prévoir aussi `fenix7`, `fenix7s`, `fenix7x`).
- **Langage** : Monkey C, `minApiLevel 3.2.0`.
- **Type d'app** : `watch-app` (Device App). Un Data Field ne peut pas piloter le chrono — non négociable.
- **Capteurs** : altimètre barométrique (~1 m), GPS multi-bande, accéléromètre, FC poignet.
- **Toolchain** : Connect IQ SDK Manager, extension Monkey C pour VS Code, simulateur CIQ. Livraison par sideload (`.prg` dans `GARMIN/APPS/`).

## 3. Modèle de données — calqué sur le ski alpin

C'est le cœur de la spec. Garmin, en ski alpin, produit **un lap par descente** et agrège au niveau session. On reproduit exactement ce modèle.

### 3.1 Par descente (= 1 lap FIT)

| Métrique | Calcul |
|---|---|
| Numéro de descente | incrément |
| Dénivelé négatif (m) | altitude au départ du run − altitude en fin de run |
| Distance de la descente (m) | distance parcourue pendant l'état DESCENT |
| Temps de descente | durée de l'état DESCENT |
| Vitesse max (km/h) | max sur le run |
| Vitesse moyenne (km/h) | distance / temps du run |
| Vitesse verticale (m/h) | dénivelé négatif / temps du run × 3600 |
| Pente moyenne (%) | dénivelé / distance horizontale |
| FC moyenne / max | sur le run |

### 3.2 Par session (agrégats journée)

| Métrique | Calcul |
|---|---|
| **Nombre de descentes** | compteur de laps |
| **Dénivelé négatif total** | somme des dénivelés de run |
| Distance totale descendue | somme des distances de run |
| Temps de descente total | = temps d'activité (chrono) |
| Vitesse max de la journée | max global |
| Meilleure descente | run au plus grand dénivelé |
| Temps de remontée total | calculé, stocké en champ dev |
| Ratio descente / journée | temps descente / temps écoulé total |

### 3.3 Champs développeur FIT

Enregistrer via `FitContributor.createField` les métriques que Garmin n'expose pas nativement pour le cyclisme, afin qu'elles remontent dans Garmin Connect :
- `run_count` (session, `DATA_TYPE_UINT16`)
- `total_vertical_drop` (session, float, mètres)
- `run_vertical_drop` (lap, float, mètres)
- `lift_time` (session, uint32, secondes)

## 4. Algorithme de détection — spécifique remontées mécaniques

Le contexte est **lift-served uniquement** : télésièges, télécabines, téléskis. C'est un cas bien plus facile qu'une navette routière, parce que la signature d'une remontée mécanique est très caractéristique.

### 4.1 Signature d'une remontée mécanique

1. **Gain d'altitude régulier et monotone** — 2 à 5 m/s de vitesse verticale, quasiment sans variation.
2. **Vitesse horizontale constante** — typiquement 8–20 km/h, écart-type très faible (le câble ne varie pas).
3. **Trace GPS rectiligne** — le câble suit une ligne droite entre pylônes.
4. **Vibration quasi nulle** — assis sur un siège suspendu. C'est le discriminant le plus fort face au VTT de descente, où l'accéléromètre est saturé en permanence.

### 4.2 Entrées

Échantillonnage 1 Hz de `Activity.getActivityInfo()` : `altitude`, `currentSpeed`, `currentHeading`, timestamp.
Accéléromètre via `Sensor.registerSensorDataListener` à 25 Hz → calculer l'**écart-type de la magnitude** sur fenêtres glissantes de 1 s (`accelVariance`).
Ring buffer de 60 s sur toutes ces séries.

### 4.3 Machine à états

Trois états : `IDLE` (bas de piste, file d'attente), `LIFT` (remontée, chrono en pause), `DESCENT` (chrono actif). État initial : `IDLE`.

**→ DESCENT** (démarrer le chrono, ouvrir un lap) si :
- perte d'altitude ≥ **8 m sur 6 s**, ET
- vitesse ≥ **5 km/h**, ET
- `accelVariance` ≥ `ACCEL_ROUGH_THRESHOLD` (à calibrer terrain, ~2× le bruit au repos)

**→ LIFT** (pause chrono, clôturer le lap) si :
- gain d'altitude ≥ **10 m sur 20 s**, ET
- montée **monotone** : ≥ 80 % des échantillons de la fenêtre en hausse, ET
- `accelVariance` < `ACCEL_SMOOTH_THRESHOLD`

La condition de monotonie + vibration faible est ce qui rend la détection fiable : une remontée en pédalant sur une liaison produit du bruit accéléromètre et un profil d'altitude irrégulier, donc ne déclenchera pas.

**→ IDLE** depuis DESCENT si vitesse < 3 km/h et altitude stable pendant ≥ **90 s** (arrivée en bas, file d'attente). Les arrêts courts en piste ne coupent PAS le chrono.

### 4.4 Robustesse

- **Hystérésis** : état verrouillé 10 s après chaque transition.
- **Filtrage baro** : moyenne mobile 3 s sur l'altitude brute avant tout calcul.
- **Téléski / tire-fesses** : cas limite — vibration modérée, vitesse plus faible. Si la détection le rate, la condition de monotonie d'altitude doit primer : prévoir un mode où `accelVariance` n'est qu'un facteur de confiance secondaire, pas une condition bloquante (voir §7, réglage « Type de remontée »).
- **Perte GPS sous couvert** : la détection repose sur le baro. Traiter `currentSpeed == null` comme condition non satisfaite, sans crash ni changement d'état.
- **Tous les seuils dans un unique `Config.mc`.**

## 5. Interface — écrans style ski

Fond noir, gros caractères, lisible en plein soleil (MIP 260×260). Deux écrans, bascule par UP/DOWN.

**Écran 1 — descente en cours**
- Bandeau d'état : « DESCENTE N°7 » (inversé) / « REMONTÉE — pause » (gris)
- Chrono de la descente en cours (gros)
- Vitesse instantanée
- Dénivelé négatif de la descente en cours

**Écran 2 — journée**
- Nombre de descentes
- Dénivelé négatif total
- Temps de descente cumulé
- Vitesse max du jour
- Indicateur GPS + batterie

**Résumé de fin de descente** : à chaque passage DESCENT → LIFT, afficher 5 s un encart avec dénivelé, temps, vitesse max du run qui vient de se terminer — exactement le comportement du profil ski.

Vibrations : 1 pulse au départ de descente, 2 pulses au passage en pause.

## 6. Boutons

- **START** : démarre la session (1er appui) ; ensuite forçage manuel de transition en secours si la détection se trompe.
- **UP / DOWN** : bascule entre les deux écrans.
- **BACK/LAP** : inactif pendant l'activité (gants).
- **STOP** : menu de fin — Enregistrer / Reprendre / Supprimer.

## 7. Réglages (`Application.Storage`)

| Réglage | Valeurs | Défaut |
|---|---|---|
| Type de remontée | Télésiège/cabine (accel bloquant) / Téléski (accel secondaire) / Mixte | Télésiège |
| Sensibilité détection | Basse / Normale / Haute (seuils ×1.5 / ×1 / ×0.7) | Normale |
| Résumé de fin de descente | on/off | on |
| Vibrations | on/off | on |
| GPS | SatIQ / Multi-bande | SatIQ |

## 8. Session d'enregistrement

```monkeyc
session = ActivityRecording.createSession({
    :name => "DH",
    :sport => Activity.SPORT_CYCLING,
    :subSport => Activity.SUB_SPORT_DOWNHILL
});
```

- `session.start()` à chaque entrée en DESCENT (défaut, mode « descentes seules ») ; au premier appui START en mode « journée complète »
- `session.addLap()` à chaque sortie de DESCENT (un lap = un run, comme le ski) — **activé par défaut**, ce n'est pas optionnel ici puisque c'est le support des métriques par descente. En mode « journée complète » un lap est aussi fermé à chaque *entrée* en DESCENT, de sorte que les laps alternent remontée / descente et que chaque descente ait son propre split
- `session.stop()` à chaque sortie de DESCENT (défaut : c'est ce qui garde le temps et le D+ hors remontées ; ne clôture pas). En mode « journée complète » l'enregistrement ne s'arrête jamais avant le STOP final
- `session.save()` uniquement en fin de journée

## 9. Structure du projet

```
dh-tracker/
├── manifest.xml            # watch-app, produits fenix7*, permissions Fit/Sensor/Positioning
├── monkey.jungle
├── resources/
│   ├── strings/strings.xml # FR par défaut, EN fallback
│   ├── drawables/
│   └── settings/
└── source/
    ├── DhTrackerApp.mc     # AppBase, cycle de vie
    ├── DhTrackerView.mc    # écrans 1 & 2, encart résumé de run
    ├── DhTrackerDelegate.mc# boutons
    ├── LiftDetector.mc     # machine à états IDLE/LIFT/DESCENT — logique pure, testable
    ├── RunStats.mc         # accumulateurs par run + agrégats session
    ├── Config.mc           # toutes les constantes de seuils
    └── SessionManager.mc   # wrapper ActivityRecording + FitContributor
```

**Contrainte d'architecture** : `LiftDetector` et `RunStats` ne dépendent d'aucune API montre. Ils reçoivent `(altitude, speed, heading, accelVariance, timestamp)` et émettent `onRunStart` / `onRunEnd(stats)`. C'est ce qui les rend testables hors simulateur.

## 10. Tests

1. **Unitaires du détecteur** : séquences synthétiques — descente franche, télésiège (montée linéaire + accel plat), téléski, replat en cours de piste, file d'attente en bas, bruit baro, `speed == null`. Vérifier transitions et absence de faux positifs.
2. **Simulateur CIQ** : rejouer un FIT réel de journée DH (Simulation > Activity Data).
3. **Terrain** : première sortie avec l'app en parallèle du profil VTT natif, comparer, ajuster `Config.mc`.

## 11. Critères d'acceptation

- [ ] L'activité apparaît dans Garmin Connect en Cyclisme/VTT descente, un lap par descente.
- [ ] **Le dénivelé positif de l'activité reste proche de zéro** : le D+ des remontées ne doit pas polluer le cumul VTT. C'est le critère qui a motivé la révision du §1.
- [ ] L'activité remonte sur Strava via la synchro Garmin. Vérifier au passage que Strava ne recalcule pas un D+ à partir du saut d'altitude entre deux descentes.
- [ ] Le nombre de descentes détectées est exact sur une journée test (tolérance : 0 manquée, ≤ 1 faux départ).
- [ ] Le temps d'activité exclut les remontées (écart < 5 % vs pointage manuel).
- [ ] Dénivelé négatif total cohérent à ± 3 % avec le dénivelé annoncé de la station × nombre de descentes.
- [ ] Aucun appui entre le START initial et le STOP final.
- [ ] Consommation comparable à un profil VTT natif en SatIQ (boucle principale à 1 Hz max ; l'accéléromètre est le poste à surveiller — si l'autonomie chute, réduire à 10 Hz).
- [ ] Pas de crash sur perte GPS ni sur `altitude == null` au démarrage.

## 12. Hors périmètre (v1)

- Publication sur le Connect IQ Store.
- Métriques Grit/Flow/sauts (API non exposée aux apps tierces).
- Cartographie / nom des pistes.
- Montres AMOLED (Epix, Fenix 8) — ne pas coder en dur les dimensions d'écran, mais pas de test requis.

## 13. Ressources

- SDK & doc : https://developer.garmin.com/connect-iq/
- `Toybox.ActivityRecording`, `Toybox.Activity`, `Toybox.Sensor`, `Toybox.FitContributor`, `Toybox.Attention`, `Toybox.Application.Storage`
- Sideload : montre en USB → copier `bin/dh-tracker.prg` dans `GARMIN/APPS/`
