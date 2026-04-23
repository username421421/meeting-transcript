# Meeting Transcript

Meeting Transcript is a native macOS app for turning local audio files into searchable transcripts with speaker labels. The app target is named `Transcribe` and is built with SwiftUI, FluidAudio, and offline speech and diarization models.

## Features

- Import audio with drag and drop or the file picker.
- Run transcription and speaker diarization locally through FluidAudio.
- Optionally provide an expected people count before starting a run.
- Track recent transcript runs and resume completed results.
- Search across speaker-labeled and plain transcript views.
- Copy transcript text to the clipboard.
- Export generated artifacts:
  - Plain transcript text
  - Speaker transcript text with time ranges
  - Transcription JSON with token timing
  - Diarization JSON with speaker segments

## Requirements

- macOS 26.0 or newer.
- Xcode with the macOS 26 SDK.
- Git LFS, required for the bundled model weight files.
- Swift Package Manager access to `https://github.com/FluidInference/FluidAudio.git`.
- Offline model files are included under `Resources/Models`; large weight files are stored with Git LFS.

The project currently pins FluidAudio through `Package.resolved`.

## Build And Run

From the repository root:

```sh
./script/build_and_run.sh
```

The script builds `MeetingTranscriber.xcodeproj` with local DerivedData under `.build/` and opens the `Transcribe` app.

Other script modes:

```sh
./script/build_and_run.sh --verify
./script/build_and_run.sh --logs
./script/build_and_run.sh --telemetry
./script/build_and_run.sh --debug
```

You can also open `MeetingTranscriber.xcodeproj` in Xcode and run the `MeetingTranscriber` scheme.

## Models

The app uses bundled models from `Resources/Models`. Large model weight files are tracked with Git LFS, so clone with LFS enabled:

```sh
git lfs install
git clone https://github.com/username421421/meeting-transcript.git
```

For local fallback downloads, FluidAudio stores models under:

```text
~/Library/Application Support/MeetingTranscriber/Models
```

The build phase `script/stage_models.sh` stages bundled models into the app bundle from this structure:

```text
Models/
  parakeet-tdt-0.6b-v3/
    Preprocessor.mlmodelc
    Encoder.mlmodelc
    Decoder.mlmodelc
    JointDecision.mlmodelc
    parakeet_vocab.json
  speaker-diarization/
    Segmentation.mlmodelc
    FBank.mlmodelc
    Embedding.mlmodelc
    PldaRho.mlmodelc
    plda-parameters.json
```

If bundled models are not present, the app can still build. On first transcription, FluidAudio prepares models in the user's Application Support directory.

## Model Attribution

Speech recognition in this app uses publicly available ASR model artifacts derived from NVIDIA Parakeet-TDT-0.6B-v3, a multilingual automatic speech recognition model published by NVIDIA. The bundled Core ML assets are used through FluidAudio so transcription can run locally on macOS.

This project did not train or create the ASR model. The upstream NVIDIA model card lists Parakeet-TDT-0.6B-v3 under the CC BY 4.0 license, and the FluidInference Core ML model card identifies its base model as `nvidia/parakeet-tdt-0.6b-v3`. See [NOTICE.md](NOTICE.md) for attribution and upstream license links.

## Supported Audio

The app accepts common audio file types including:

```text
aac, aif, aiff, caf, flac, m4a, mp3, mp4, mpeg, mpga, ogg, wav
```

## Stored Data

Run metadata and cached transcript content are stored locally in:

```text
~/Library/Application Support/MeetingTranscriber/Runs
```

The app does not require a server for transcript storage.

## Tests

Run the test target with Xcode:

```sh
xcodebuild \
  -project MeetingTranscriber.xcodeproj \
  -scheme MeetingTranscriber \
  -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData \
  -clonedSourcePackagesDirPath .build/DerivedData/SourcePackages \
  -packageCachePath .build/PackageCache \
  -disablePackageRepositoryCache \
  -IDEPackageSupportDisableManifestSandbox=1 \
  -IDEPackageSupportDisablePackageSandbox=1 \
  CODE_SIGNING_ALLOWED=NO \
  test
```

## Repository Layout

```text
App/                       App entry point and settings
Scenes/                    Main window scene
Features/                  Import, transcript, and artifact views
Services/                  FluidAudio, model, pipeline, and artifact logic
Stores/                    App state and run repository
Models/                    Run and transcript data models
Support/                   File access, localization, and time formatting
Tests/                     XCTest coverage
script/                    Build, run, and model staging scripts
```
