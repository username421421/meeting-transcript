# Notices

## Speech Recognition Model

This app bundles publicly available Core ML speech recognition model artifacts for local transcription on Apple platforms.

- Base ASR model: NVIDIA Parakeet-TDT-0.6B-v3
- Base model creator: NVIDIA
- Base model source: https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3
- Upstream license/terms: CC BY 4.0, according to the NVIDIA model card
- Core ML artifacts: https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml
- Runtime format: Core ML `.mlmodelc` assets optimized for Apple platforms
- Use in this project: bundled under `Resources/Models` and loaded through FluidAudio for local, on-device speech recognition

Apple provides the Core ML runtime and Apple Neural Engine acceleration path used by compatible hardware. Apple did not train or publish the ASR model bundled here. This project did not train or create the speech recognition model. Model behavior, supported languages, performance, and limitations follow the upstream model cards. No endorsement by Apple, NVIDIA, FluidInference, or Hugging Face is implied.
