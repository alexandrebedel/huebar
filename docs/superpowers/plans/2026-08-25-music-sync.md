# Music Sync Implementation Plan (sous-projet B)

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Section 🎵 Musique dans HueBar : source audio (système ou device/paire de canaux), analyse temps réel, modes Club/Chill, streaming Entertainment DTLS ~50 Hz vers la zone « HueBar Sync ».

**Architecture (nouveaux modules SwiftPM, tous testés par `swift test`) :**
- `WaveKit` : audio pur — `AudioSource` (protocol), `SystemAudioTap` (CoreAudio process tap), `DeviceInputSource` (AVAudioEngine, device + paire de canaux), `AudioDeviceCatalog` (énumération devices/canaux/noms), `AudioAnalyzer` (FFT vDSP, bandes, beat) → `AnalysisFrame`.
- `HueKit` (étendu) : `HueStreamEncoder` (frames binaires HueStream v2), extensions `HueClient` (fetch/start/stop entertainment_configuration), `DTLSStreamer` (NWConnection PSK), `HueConfig.clientKey`.
- `SyncKit` : `LightMapper` (Club/Chill : AnalysisFrame → couleurs RGB par channel), `MusicSyncEngine` (orchestration source→analyse→mapping→streaming, keepalive 5 s, erreurs).
- App : UI section Musique + wiring.

**Faits vérifiés clés (recherche 25/08)** : PSK = clientkey hex→16 bytes, identity = application key (fallback `hue-application-id` de GET /auth/v1) ; ciphersuite `tls_ciphersuite_t(rawValue: 0x00A8)!` à append explicitement ; min=max `.DTLSv12` ; UDP 2100 ; connect < 2 s après PUT start ; frame = "HueStream"+0x02 0x00+seq+0x0000+colorspace(0x00 RGB)+0x00+36-char UUID ASCII + 7 bytes/channel (id + 3×uint16 BE), TOUS les channels chaque frame ; keepalive ≤ 9,5 s ; PUT stop au teardown ; un seul streamer à la fois. Tap système : `CATapDescription(stereoGlobalTapButExcludeProcesses: [])` (ne pas toucher isExclusive), aggregate avec output par défaut en main sub-device + tap list, IOProc sur queue série, prompt TCC au premier `AudioDeviceStart`, refus = silence (pas d'erreur) ; clé `NSAudioCaptureUsageDescription` ; grant TCC keyé au cdhash (ad hoc → re-prompt possible après rebuild). Device input : `kAudioOutputUnitProperty_CurrentDevice` avant start, `installTap(format: nil)`, extraire la paire via `floatChannelData`, SR variable (44.1–96 k, ne jamais hardcoder), clé `NSMicrophoneUsageDescription` obligatoire, unplug → `AVAudioEngineConfigurationChange`, persister le device UID. PX5 : 20 ch USB, master = canaux 8/9 (USB 9/10, switch arrière MST), labels fallback si le descripteur ne nomme pas.

### Tasks

- [ ] B1 `HueConfig.clientKey` optionnel (TDD) — parse `HUE_CLIENTKEY`, + `clientKeyBytes: Data?` (hex→bytes, TDD).
- [ ] B2 `HueStreamEncoder` (TDD octet par octet : header 52 bytes, channels triés par id, uint16 BE).
- [ ] B3 `HueClient` + `EntertainmentConfig` modèle (id, name, channels[channel_id, position x/y/z], status) ; `fetchEntertainmentConfigurations()`, `startEntertainment(id:)`, `stopEntertainment(id:)`, `fetchApplicationID()` (GET /auth/v1, header `hue-application-id`) (TDD MockURLProtocol).
- [ ] B4 `DTLSStreamer` : connect(host, psk, identity) → état ; send(Data) ; close. Callbacks d'état. Pas de test unitaire (smoke réel).
- [ ] B5 `WaveKit.AudioAnalyzer` (TDD) : entrée buffers float mono-mixés, FFT 1024, sortie `AnalysisFrame {rms, bass, mid, high, beat: Bool, tempoEnergy}` ; beat = flux d'énergie basses vs moyenne glissante ; sinus 60 Hz pulsé → beats détectés ; silence → rien.
- [ ] B6 `AudioDeviceCatalog` + `DeviceInputSource` + `SystemAudioTap` (implémentations CoreAudio/AVAudioEngine des findings ; `AudioSource` protocol : start(onBuffer:), stop, format ; erreurs typées).
- [ ] B7 `SyncKit.LightMapper` (TDD) : `map(frame:channels:mode:time:) -> [ChannelColor]` ; Club : beat → flash + rotation teinte, bandes → canaux par position x ; Chill : dérive lente HSV, luminosité RMS lissé ; sorties bornées [0,1].
- [ ] B8 `MusicSyncEngine` (@MainActor, testable avec fakes) : states idle/starting/running(mode)/error ; start = REST start → DTLS connect → boucle 50 Hz (timer) : dernier AnalysisFrame → mapper → encoder → send ; keepalive (renvoyer dernière frame si pause) ; stop = stop timer → PUT stop → close ; hot-unplug → error propre.
- [ ] B9 UI : `MusicSectionView` (picker source+paire, Club/Chill, Start/Stop, VU, erreurs) intégrée au panneau ; plists : `NSAudioCaptureUsageDescription`, `NSMicrophoneUsageDescription`.
- [ ] B10 Intégration réelle : smoke DTLS (`HUE_INTEGRATION=1`, flash contrôlé 2 s puis restore), install, test utilisateur (permissions TCC).

## Vérification finale
- [ ] `swift test` tout vert ; smoke DTLS réel OK ; sync visible sur les lampes (validation utilisateur) ; review adversariale du code critique passée.
