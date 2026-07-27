# DH Tracker

Application Connect IQ (Device App) pour Garmin **fēnix 7 / 7 Pro** qui
enregistre une journée de VTT de descente en lift-served sur le modèle du profil
**Ski alpin** de Garmin : découpage automatique en descentes, chrono actif
uniquement en descente, remontées mécaniques exclues du temps d'activité,
statistiques par run.

Aucun appui entre le START du matin et le STOP du soir.

Spécification complète : [spec-dh-tracker-connectiq.md](spec-dh-tracker-connectiq.md).

## Fonctionnement

Une machine à états à 1 Hz classe chaque seconde en `IDLE` (bas de piste, file
d'attente), `LIFT` (remontée, chrono en pause) ou `DESCENT` (chrono actif) à
partir de l'altimètre barométrique, de la vitesse GPS et de l'écart-type de
l'accéléromètre échantillonné à 25 Hz. Chaque descente produit un lap FIT.

| Écran | Contenu |
|---|---|
| 1 — descente | bandeau d'état, chrono du run, vitesse, dénivelé du run |
| 2 — journée | descentes, dénivelé total, temps de descente, V. max, GPS, batterie |

À la fin de chaque descente, un encart affiche 5 s le dénivelé, le temps et la
vitesse max du run.

| Bouton | Action |
|---|---|
| START | 1er appui : démarre la journée. Ensuite : force la transition que la détection a manquée |
| UP / DOWN | bascule entre les deux écrans |
| BACK/LAP | inactif (gants) |
| MENU (appui long UP) | menu de fin : Enregistrer / Reprendre / Supprimer |

> Le fēnix 7 partage un seul bouton physique entre START et STOP et Connect IQ
> ne remonte pas d'appui long dessus (`PRESS_TYPE_LONG` n'existe pas dans
> l'API). C'est donc MENU qui porte le rôle STOP décrit dans la spec §6.

## Réglages

Éditables depuis Garmin Connect Mobile / Garmin Express une fois l'app installée.

| Réglage | Valeurs | Défaut |
|---|---|---|
| Type de remontée | Télésiège/cabine · Téléski · Mixte | Télésiège |
| Sensibilité détection | Basse (×1.5) · Normale (×1) · Haute (×0.7) | Normale |
| Résumé de fin de descente | on/off | on |
| Vibrations | on/off | on |
| GPS | SatIQ · Multi-bande | SatIQ |

## Champs développeur FIT

Remontent dans Garmin Connect en plus des métriques natives :

| Champ | Portée | Type |
|---|---|---|
| `run_count` | session | uint16 |
| `total_vertical_drop` | session | float (m) |
| `run_vertical_drop` | lap | float (m) |
| `lift_time` | session | uint32 (s) |

## Build

Prérequis : le **Connect IQ SDK** (SDK Manager depuis
<https://developer.garmin.com/connect-iq/sdk/>), avec les devices `fenix7`,
`fenix7s`, `fenix7x`, `fenix7pro`, `fenix7spro`, `fenix7xpro` installés depuis
l'onglet *Devices*. Le SDK Manager demande un compte Garmin — il télécharge les
définitions de devices **et le pack de polices** dont le simulateur a besoin.

```bash
./build.sh                  # release, les 6 produits -> bin/
./build.sh fenix7pro        # un seul produit
./build.sh --test           # build avec les tests unitaires
./build.sh --run fenix7pro  # build + push dans le simulateur
```

Le script génère une clé développeur (`developer_key.der`) au premier lancement
si elle n'existe pas. Elle est ignorée par git — ne la committez pas.

Pour utiliser un SDK hors du chemin standard : `SDK_HOME=/chemin/vers/sdk ./build.sh`.

## Tests

48 tests unitaires couvrent les scénarios de la spec §10.1 (descente franche,
télésiège, téléski, replat, file d'attente, bruit baro, `speed == null`,
`altitude == null`, hystérésis) ainsi que les accumulateurs et le wrapper
`ActivityRecording`.

```bash
./build.sh --test
"$SDK_HOME/bin/connectiq" &                                  # lance le simulateur
"$SDK_HOME/bin/monkeydo" bin/dh-tracker-test.prg fenix7pro -t
```

## Sideload

1. Brancher la montre en USB (mode MTP).
2. Copier le `.prg` du produit correspondant dans `GARMIN/APPS/` de la montre :

```bash
cp bin/dh-tracker-fenix7pro.prg "/Volumes/GARMIN/GARMIN/APPS/dh-tracker.prg"
```

3. Copier aussi `bin/dh-tracker-settings.json` dans `GARMIN/APPS/SETTINGS/`
   si vous voulez les réglages par défaut sur la montre.
4. Éjecter, puis lancer *DH Tracker* depuis la liste d'activités.

## Structure

```
source/
├── Config.mc            # tous les seuils + réglages (spec §4.4)
├── LiftDetector.mc      # machine à états IDLE/LIFT/DESCENT — logique pure
├── RunStats.mc          # accumulateurs par run + agrégats journée — logique pure
├── SessionManager.mc    # ActivityRecording + champs dev FIT
├── DhTrackerApp.mc      # cycle de vie, boucle 1 Hz, accéléromètre, GPS
├── DhTrackerView.mc     # écrans 1 & 2 + encart résumé
├── DhTrackerDelegate.mc # boutons + menu de fin
└── *Test.mc             # tests, exclus du build release par l'annotation (:test)
```

`LiftDetector` et `RunStats` ne dépendent d'aucune API montre : ils reçoivent
`(altitude, speed, heading, accelVariance, timestamp)` et émettent
`onRunStart` / `onRunEnd`. C'est ce qui les rend testables hors simulateur.

## Calibration terrain

Les seuils sont tous dans [source/Config.mc](source/Config.mc). Les deux à
ajuster après la première sortie :

- `ACCEL_ROUGH_MG` / `ACCEL_SMOOTH_MG` — écart-type de la magnitude
  accélérométrique en milli-g. Viser ~2× le bruit au repos pour `ROUGH`.
- `LIFT_WINDOW_SEC` — la détection de remontée arrive environ une fenêtre après
  l'embarquement. Raccourcir la fenêtre réduit le temps de remontée compté comme
  temps d'activité, au prix de plus de faux positifs sur les replats montants.
