# DH Tracker

Application Connect IQ (Device App) pour Garmin **fēnix 7 / 7 Pro** qui
enregistre une journée de VTT de descente en lift-served sur le modèle du profil
**Ski alpin** de Garmin : découpage automatique en descentes, un lap FIT par
descente, statistiques par run.

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
| Enregistrement | Descentes seules · Journée complète | Descentes seules |
| Type de remontée | Télésiège/cabine · Téléski · Mixte | Télésiège |
| Sensibilité détection | Basse (×1.5) · Normale (×1) · Haute (×0.7) | Normale |
| Résumé de fin de descente | on/off | on |
| Vibrations | on/off | on |
| GPS | SatIQ · Multi-bande | SatIQ |

## Enregistrement et synchro Strava

Connect IQ n'offre qu'un seul levier : le chrono tourne, ou pas.
`Activity.Info.totalAscent` est en lecture seule et une session n'expose que
start/stop/addLap/save/discard. La montre accumule le temps **et** le dénivelé
exactement pendant que le chrono tourne, et une session arrêtée n'écrit aucun
point. Trois choses n'en font donc qu'une seule, indissociables :

> temps d'activité hors remontées ⟺ D+ hors remontées ⟺ trou dans la trace GPS

| | Descentes seules (défaut) | Journée complète |
|---|---|---|
| Temps d'activité | temps de descente | journée entière |
| **D+ de l'activité** | **≈ 0, le cumul VTT reste propre** | **inclut tout le D+ des remontées** |
| Trace GPS | descentes reliées en ligne droite | continue |
| Laps | un lap par descente | alternance remontée / descente |

Le défaut reproduit le profil **Ski alpin** : c'est le comportement voulu pour ne
pas polluer le dénivelé positif VTT. Le raccord en ligne droite entre le bas d'une
descente et le haut de la suivante suit à peu près le tracé de la remontée, un
câble étant rectiligne entre pylônes.

Le profil Ski alpin natif de Garmin, lui, garde la trace *et* exclut les
remontées — parce qu'il ne passe pas par cette API. Ce n'est pas reproductible
depuis une app Connect IQ.

La synchro passe par la chaîne habituelle : la montre écrit le FIT dans
`GARMIN/ACTIVITY/`, Garmin Connect Mobile le synchronise, puis Garmin Connect le
pousse vers Strava si la synchro automatique Garmin↔Strava est autorisée. Le fait
que l'app soit sideloadée ne change rien.

Deux points à vérifier à la première sortie :

- **Strava ignore les champs développeur FIT.** Le nombre de descentes et le
  dénivelé négatif total s'affichent dans Garmin Connect (rôle de
  `resources/fitcontributions/`) mais pas sur Strava. Les laps passent bien et
  donnent un split par descente.
- **Le D+ recalculé par Strava.** Garmin Connect lit le `total_ascent` du FIT, qui
  exclut bien les remontées. Strava recalcule plutôt à partir du flux d'altitude,
  où le saut entre le bas d'une descente et le haut de la suivante est un delta
  positif. Selon la façon dont Strava traite les coupures de temps, ce saut peut
  ou non être compté. À contrôler sur la première activité.

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
<https://developer.garmin.com/connect-iq/sdk/>), avec tous les devices `fenix7*`
installés depuis l'onglet *Devices*. Le SDK Manager demande un compte Garmin — il
télécharge les définitions de devices **et le pack de polices** dont le
simulateur a besoin.

### Quel produit pour quelle montre ?

La gamme Pro existe en **deux produits Connect IQ par taille** : les modèles
Sapphire (avec Wi-Fi) et les modèles « Solar Edition » sans Wi-Fi. Vérifiez le
numéro de pièce sur la montre — *Paramètres › Système › À propos* — avant de
sideloader :

| Montre | Numéro de pièce | Produit à builder |
|---|---|---|
| fēnix 7 Pro (Sapphire) | 006-B4375-00 | `fenix7pro` |
| fēnix 7 Pro Solar Edition | 006-B4595-00 | `fenix7pronowifi` |
| fēnix 7S Pro | 006-B4374-00 | `fenix7spro` |
| fēnix 7X Pro (Sapphire) | 006-B4376-00 | `fenix7xpro` |
| fēnix 7X Pro Solar Edition | 006-B4596-00 | `fenix7xpronowifi` |
| fēnix 7 / 7S / 7X (non-Pro) | 006-B390x-00 | `fenix7` / `fenix7s` / `fenix7x` |

Un `.prg` buildé pour le mauvais produit n'apparaîtra pas dans la liste
d'activités de la montre.

```bash
./build.sh                  # release, tous les produits -> bin/
./build.sh fenix7pronowifi  # un seul produit
./build.sh --test           # build avec les tests unitaires
./build.sh --run fenix7pro  # build + push dans le simulateur
```

Le script génère une clé développeur (`developer_key.der`) au premier lancement
si elle n'existe pas. Elle est ignorée par git — ne la committez pas.

Pour utiliser un SDK hors du chemin standard : `SDK_HOME=/chemin/vers/sdk ./build.sh`.

## Tests

50 tests unitaires couvrent les scénarios de la spec §10.1 (descente franche,
télésiège, téléski, replat, file d'attente, bruit baro, `speed == null`,
`altitude == null`, reprise après perte baro, hystérésis), la reprise de distance
GPS sans double comptage, les accumulateurs et le wrapper `ActivityRecording`.

```bash
./build.sh --test
"$SDK_HOME/bin/connectiq" &                                  # lance le simulateur
"$SDK_HOME/bin/monkeydo" bin/dh-tracker-test.prg fenix7pro -t
```

## Sideload

1. Brancher la montre en USB. Elle se monte comme un volume `GARMIN`.
2. Copier le `.prg` **du produit correspondant à votre montre** (voir le tableau
   ci-dessus) dans `GARMIN/APPS/` :

```bash
cp bin/dh-tracker-fenix7pronowifi.prg "/Volumes/GARMIN/GARMIN/APPS/dh-tracker.prg"
```

3. Éjecter le volume, puis lancer *DH Tracker* depuis la liste d'activités.

> **Réglages d'une app sideloadée.** Garmin Connect Mobile ne propose les
> réglages Connect IQ que pour les apps installées depuis le store ; une app
> sideloadée démarre donc sur les valeurs par défaut de
> `resources/settings/settings.xml`. Pour changer un réglage, modifiez la valeur
> par défaut et rebuildez — c'est le chemin le plus fiable. Le
> `bin/dh-tracker-<produit>-settings.json` généré à côté du `.prg` peut aussi
> être copié dans `GARMIN/APPS/SETTINGS/`, mais le support varie selon les
> firmwares.

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
