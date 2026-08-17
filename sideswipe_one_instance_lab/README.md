# SideSwipe One-Instance Bot Lab

Lab Windows dédié à Rocket League Sideswipe **offline / Training > Exhibition uniquement**.
Objectif: un équivalent RLBot local avec une seule fenêtre Android, checkpoints PPO 72 observations / 16 actions, et deux policies custom quand le mapping runtime de la build installée est validé.

## Installation la plus simple

1. Double-cliquer `INSTALL.bat`.
   - installe uniquement les outils nécessaires dans ce dossier quand possible;
   - télécharge Android command-line tools + Emulator depuis Google;
   - crée l'AVD dédié `SideSwipeBotLab_API30` (6 Go RAM, 6 cores, GPU host, 1920x1080);
   - installe ADB, Frida, LIEF, CMake/VS Build Tools si absents;
   - télécharge LibTorch CPU et compile `sideswipe_policy_host.exe`;
   - ouvre/installe Epic Games Store depuis la source officielle, puis Sideswipe.
2. Le login/validation Epic est le seul passage qui peut demander une interaction humaine au premier setup.
3. Lancer `DIAGNOSE.bat`.

Aucun APK Sideswipe tiers n'est fourni ou téléchargé par ce projet.

## Launchers

- `START_EMULATOR.bat` — démarre uniquement l'AVD dédié.
- `GET_CHAMPION.bat` — récupère `sideswipe-pretrain-latest` quand la release existe; sinon utilise le checkpoint local de training si disponible.
- `DISCOVER_INTERNAL.bat` — discovery UE4 **read-only** dans une partie Exhibition; génère `logs/discovery.json` + `config/runtime_profile.suggested.json`.
- `VALIDATE_PROFILE.bat` — échantillonne le profil en lecture seule et vérifie valeurs finies, stabilité des voitures et mouvement réel.
- `START_BOTVBOT.bat` — deux policies custom dans **une seule instance**. Fail-closed: refuse tout write tant que `runtime_profile.json` n'est pas explicitement validé et `controls.enabled` reste faux.
- `START_POLICY_VS_NATIVE.bat` — fallback mono-instance: policy custom sur la voiture locale contre l'IA Exhibition native, via le bridge écran/ADB.
- `PREPARE_INTERNAL_GADGET.bat` — backend avancé/réversible si Frida-server x86 ne voit pas `libUE4.so` ARM traduit. Sauvegarde l'installation officielle, prépare une copie locale re-signée avec Frida Gadget ARM64, puis teste le transport avant de la garder.
- `RESTORE_OFFICIAL.bat` — restaure immédiatement les APK officiels sauvegardés + data locale.

## Pourquoi deux backends internes ?

Sideswipe Android est un jeu ARM64. Sur un PC Windows x86_64, l'Android Emulator performant exécute les binaires ARM via traduction. Selon la build/emulator, un Frida server x86 peut ne pas voir le module ARM traduit. Le lab essaie d'abord le backend non invasif. Si `DISCOVER_INTERNAL.bat` indique que `libUE4.so` est invisible, `PREPARE_INTERNAL_GADGET.bat` place Frida Gadget ARM64 directement dans une **copie locale offline** de l'installation déjà présente. Cette opération est réversible et n'est jamais faite silencieusement.

## Sécurité / fail-closed

- Le mode interne est réservé à Exhibition/offline.
- Avant les writes, le launcher coupe `wifi` et `data` Android.
- Si un backend Gadget est préparé, `Start-LabEmulator` réapplique automatiquement le kill-switch réseau après chaque boot.
- `runtime_profile.json` démarre avec `validated=false` et `controls.enabled=false`.
- L'auto-discovery ne marque jamais automatiquement un champ comme writable.
- Si les objets/fields disparaissent, le bridge arrête au lieu de continuer avec de vieux inputs.
- Le backend Gadget sauvegarde les APK officiels et tente une restauration automatique si le test de démarrage échoue.

## Contrat policy

`bridge/policy_host.cpp` reproduit le réseau du trainer:

- 72 observations;
- 16 actions discrètes;
- `Linear 72→512→512→256`, LayerNorm, SiLU, actor 16;
- team mirroring identique;
- action mask identique;
- **transfer-safe opponent observations** identiques au training actuel: orientation adversaire dérivée du mouvement, omega=0, boost=0.5, flip=0.5.

Ce dernier point est volontaire: le jeu réel ne doit pas fournir au modèle des variables privilégiées différentes de celles vues pendant PPO.

## Premier bring-up recommandé

1. `INSTALL.bat`
2. `DIAGNOSE.bat`
3. `GET_CHAMPION.bat`
4. Ouvrir Exhibition.
5. `DISCOVER_INTERNAL.bat`
6. Si le log dit que le module UE4 ARM n'est pas visible: `PREPARE_INTERNAL_GADGET.bat`, puis recommencer l'étape 5.
7. Examiner/valider le mapping proposé, puis `VALIDATE_PROFILE.bat`.
8. Seulement après validation de l'état + des champs de contrôle: `START_BOTVBOT.bat`.

La phase 5-7 dépend nécessairement de la build Sideswipe réellement installée. Le projet refuse donc de hardcoder de faux offsets historiques et de prétendre qu'ils sont compatibles.

## Arborescence importante

- `android-sdk/` — SDK/Emulator dédié, créé par INSTALL.
- `bridge/policy_host.cpp` — inférence exacte du checkpoint.
- `bridge/ue_agent.js` — introspection/mapping UE4 runtime.
- `bridge/orchestrator.py` — state → policy host → controls.
- `config/runtime_profile.json` — mapping actif, fail-closed par défaut.
- `logs/discovery.json` — résultat détaillé du scan runtime.
- `backup/official_apks/` — sauvegarde avant backend Gadget.
- `checkpoints/champion.pt` — checkpoint utilisé par défaut.

## Attribution

Le layout de réflexion UE4.27 de l'agent est dérivé des informations publiques du projet MIT `gmh5225/frida-ue4dump`. Frida/Gadget reste un projet tiers sous ses propres licences. Android SDK/Emulator est fourni par Google. PyTorch/LibTorch est fourni par PyTorch.
