# DH Tracker — plan d'implémentation

Source : [spec-dh-tracker-connectiq.md](../spec-dh-tracker-connectiq.md)

## Environnement

- [x] SDK Connect IQ 9.2.0 récupéré et vérifié
- [x] Fichiers device fenix7 / 7S / 7X / 7 Pro / 7S Pro / 7X Pro installés
- [x] Clé développeur générée
- Le SDK a été installé **dans le scratchpad de session uniquement**. La machine
  a été remise dans son état d'origine en fin de session (aucun
  `~/Library/Application Support/Garmin` laissé derrière). Voir « Build » dans le
  README pour l'installation permanente via le SDK Manager.

## Implémentation

- [x] `manifest.xml` — watch-app, 8 produits fenix7*, permissions Fit/FitContributor/Sensor/Positioning
- [x] `monkey.jungle`
- [x] `resources/` — strings FR (défaut) + `resources-eng/` EN, icône 40×40, settings
- [x] `Config.mc` — tous les seuils, sensibilité, type de remontée (§4.4)
- [x] `LiftDetector.mc` — machine à états IDLE/LIFT/DESCENT, pure (§4.3)
- [x] `RunStats.mc` — accumulateurs run + agrégats session, purs (§3.1, §3.2)
- [x] `SessionManager.mc` + `resources/fitcontributions/` — ActivityRecording +
      4 champs dev FIT visibles dans Garmin Connect (§3.3, §8)
- [x] `DhTrackerApp.mc` — cycle de vie, boucle 1 Hz, accéléromètre 25 Hz, GPS
- [x] `DhTrackerView.mc` — écrans 1 & 2 + encart résumé de run (§5)
- [x] `DhTrackerDelegate.mc` — boutons + menu de fin (§6)
- [x] Tests unitaires (§10.1) + tests d'intégration `SessionManager`
- [x] `build.sh`, `.gitignore`, README (build / tests / sideload / calibration)

## Vérification

- [x] Compilation `fenix7pro` — typecheck **strict** (`-l 3`), zéro warning
- [x] Compilation des 6 produits d'origine, en release (`-r`), ~20 Ko chacun
- [ ] Compilation des 2 variantes Pro Solar sans Wi-Fi ajoutées au manifeste
- [x] **50 tests unitaires exécutés dans le simulateur : 50 PASS, 0 fail,
      0 erreur** après les correctifs de revue
- [ ] Rendu des écrans dans le simulateur — **non vérifiable ici** : le pack de
      polices Garmin manque (téléchargement SDK Manager, compte Garmin requis).
      Ce n'est pas un défaut du code : l'exemple `RecordSample` livré par Garmin
      plante exactement de la même façon (`Invalid Font Specified`) dans cet
      environnement. À revérifier après une installation normale du SDK.
- [ ] Rejeu d'un FIT réel dans le simulateur (§10.2) — nécessite un FIT de journée DH
- [ ] Test terrain + calibration `Config.mc` (§10.3)

## Review

### Écarts assumés par rapport à la spec

1. **Réglages via `Application.Properties`, pas `Application.Storage`** (§7).
   `Storage` n'est pas éditable depuis Garmin Connect Mobile ; `Properties`,
   adossé à `resources/settings/settings.xml`, l'est. C'est le seul mécanisme qui
   rend les 5 réglages réellement modifiables par l'utilisateur.

2. **STOP porté par MENU (appui long UP)** (§6). Le fēnix 7 partage un bouton
   physique entre START et STOP, et l'API Connect IQ n'expose pas d'appui long
   dessus (`PRESS_TYPE_LONG` n'existe pas — seuls `PRESS_TYPE_ACTION/UP/DOWN`).
   START garde son double rôle (démarrage puis forçage manuel), MENU ouvre le
   menu Enregistrer / Reprendre / Supprimer.

3. **Dénivelé du run mesuré jusqu'au point le plus bas**, et non jusqu'à
   l'altitude à l'instant de la bascule d'état (§3.1). La condition LIFT exige
   10 m de gain mesurés sur une fenêtre de 20 s : la bascule arrive donc ~20 s
   après l'embarquement, quand le télésiège a déjà grimpé plusieurs dizaines de
   mètres. Prendre l'altitude à cet instant amputerait chaque descente de ce
   gain — de l'ordre de 40 m par run, soit >10 % sur une journée, ce qui ferait
   échouer le critère ±3 % du §11. Symétriquement, l'altitude de départ du run
   est relue une fenêtre de détection en arrière (`LiftDetector.altitudeBefore`)
   pour retrouver le vrai haut de piste.

4. **Sensibilité : le facteur s'applique en sens inverse au plafond
   accéléromètre** (§7). Multiplier un seuil « doit être inférieur à » par 1.5
   rendrait la remontée *plus* facile à détecter en sensibilité basse. Le
   facteur multiplie donc `ALT_DROP`, `ALT_GAIN` et `ACCEL_ROUGH`, et divise
   `ACCEL_SMOOTH`. Les seuils de vitesse ne sont pas mis à l'échelle : ce sont
   des garde-fous physiques, pas des réglages de sensibilité.

### Points d'attention pour le terrain

- **Trace GPS pendant les remontées — tranché par l'utilisateur.** Les deux
  exigences du §11 d'origine (« trace GPS complète » et « temps d'activité exclut
  les remontées ») sont mutuellement exclusives : Connect IQ n'a pas de « chrono
  en pause mais enregistrement continu », une session arrêtée n'écrit aucun point.
  La v1 avait retenu l'exclusion des remontées. L'utilisateur a arbitré en faveur
  de la trace continue (trace propre + dénivelé correct sur Strava), les §1/§8/§11
  ont été corrigés en conséquence, et le comportement d'origine reste accessible
  par le réglage « Enregistrement › Descentes seules ». Le temps de descente reste
  disponible via les laps, l'écran 2 et le champ dev `lift_time`.
- **Latence de détection.** La bascule LIFT arrive ~20 s après l'embarquement.
  En mode « journée complète » c'est sans effet sur le temps d'activité (qui
  couvre la journée), mais la frontière de lap descente/remontée est décalée
  d'autant, donc le split Strava d'une descente inclut ~20 s de remontée. En mode
  « descentes seules » ces 20 s comptent dans le temps d'activité et ne peuvent
  pas être antidatées (`session.stop()` n'accepte pas d'horodatage).
  `LIFT_WINDOW_SEC` est le paramètre à raccourcir si le terrain le confirme — au
  prix de faux positifs sur les liaisons montantes.
- **Seuils accéléromètre à calibrer.** `ACCEL_ROUGH_MG = 120` et
  `ACCEL_SMOOTH_MG = 60` (écart-type de la magnitude, milli-g) sont des valeurs
  de départ raisonnables mais non mesurées. C'est le premier réglage à ajuster.
- **Perte GPS au bas de piste.** Conformément au §4.4, `speed == null` est
  traité comme condition non satisfaite : le passage en IDLE ne peut donc pas se
  faire sans vitesse. Si le GPS décroche en bas, le chrono continue jusqu'à
  détection de la remontée (qui, elle, ne dépend que du baro). Comportement
  conforme à la spec, mais à surveiller sous couvert dense.
- **Accéléromètre indisponible.** Si `registerSensorDataListener` échoue ou que
  les données sont périmées (>4 s), la détection dégrade sur baro + vitesse
  plutôt que de ne plus rien détecter. Couvert par
  `testDetectionDegradesWithoutAccelerometer`.
- **Autonomie.** L'accéléromètre 25 Hz est le poste à surveiller (§11).
  `Config.ACCEL_SAMPLE_RATE` est prêt à passer à 10 Hz si besoin.
