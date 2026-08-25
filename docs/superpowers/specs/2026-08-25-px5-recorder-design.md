# HueBar — Enregistreur PX5 (sous-projet C)

**Date** : 2026-08-25
**Statut** : approuvé (design validé en conversation)

## Objectif

Enregistrer les mixes de l'utilisateur (Xone:PX5 en USB, ou tout autre device d'entrée) en **WAV 24-bit/48 kHz** depuis la section Musique de HueBar. Réutilise la brique de capture device du sous-projet B.

## Comportement

- Bouton **● REC** visible quand une source *périphérique d'entrée* est sélectionnée (pas pour « Audio du Mac » en v1).
- Fichiers : `~/Music/PX5/YYYY-MM-DD HHhmm.wav` (dossier créé au besoin), paire de canaux sélectionnée, stéréo.
- Timer d'enregistrement affiché ; arrêt par re-clic ; pas de limite de durée.
- **Indépendant de la sync** : on peut enregistrer sans lancer les lumières, et inversement ; les deux peuvent tourner ensemble sur la même source.
- Débranchement du device en cours → arrêt propre, fichier finalisé et conservé, message dans l'UI.

## Architecture

- `Recorder` dans HueKit (ou module app) : consomme les mêmes buffers que l'analyse (le pipeline audio a plusieurs consommateurs), écrit via `AVAudioFile` (conversion float32 → int24 WAV par AVAudioFile), écriture hors du thread temps réel (queue série + copies de buffers).
- Format tranché en conversation : **WAV 24-bit/48 kHz** (ALAC écarté pour la v1).

## Tests

- Unitaires : nommage/emplacement des fichiers, cycle start/stop du Recorder avec buffers synthétiques → fichier WAV valide (header, durée, format 24-bit vérifiés en le relisant avec AVAudioFile).
- Smoke test réel : enregistrer quelques secondes depuis un device réel, vérifier la lecture.

## Hors périmètre

Enregistrement de l'audio système, formats additionnels (ALAC/MP3), découpage automatique par piste.
