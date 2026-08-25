# PX5 Recorder Implementation Plan (sous-projet C)

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans.

**Goal:** Bouton ● REC dans la section Musique : enregistre la paire de canaux du device sélectionné en WAV 24-bit (au sample rate natif du device — AVAudioFile ne resample jamais) dans `~/Music/PX5/`.

**Faits vérifiés** : settings WAV int24 + `AVAudioFile(forWriting:settings:commonFormat:.pcmFormatFloat32,interleaved:false)` → conversion transparente float32→int24 (testé live) ; write hors du thread du tap via queue série + copie des buffers (garantie de lifetime) ; `close()` finalise le header (crash = header 0 bytes, données récupérables) ; pas de TCC pour ~/Music ; noms de fichiers sans `:`.

- [x] C `WaveKit.Recorder` (TDD) : `start(format:filePrefix:)` crée `~/Music/PX5/PX5 yyyy-MM-dd HH.mm.ss.wav` (répertoire injectable pour les tests) ; `append(from:left:right:)` extrait la paire en stéréo (copie) et écrit sur queue série ; `stop()` draine et `close()`. Test : buffers synthétiques → WAV relu (SR, 2 ch, int24, durée).
- [x] C `RecorderController` (app) : REC branché sur la source de sync si elle capte déjà le device, sinon source standalone dédiée ; durée affichée ; arrêt propre ; erreurs.
- [x] C UI : bouton ● REC + timer dans MusicSectionView (visible quand un device est sélectionné) ; build + install.

## Vérification finale
- [ ] `swift test` vert ; REC réel validé par l'utilisateur avec la PX5 en USB.
