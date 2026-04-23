#!/usr/bin/env bash
set -euo pipefail

readonly ASR_DIR_NAME="parakeet-tdt-0.6b-v3"
readonly DIARIZER_DIR_NAME="speaker-diarization"
readonly APP_BUNDLE_DIR="${TARGET_BUILD_DIR:?}/${FULL_PRODUCT_NAME:?}"
readonly TARGET_MODELS_DIR="${TARGET_BUILD_DIR:?}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:?}/Models"
readonly TARGET_ASR_DIR="$TARGET_MODELS_DIR/$ASR_DIR_NAME"
readonly TARGET_DIARIZER_DIR="$TARGET_MODELS_DIR/$DIARIZER_DIR_NAME"

readonly -a REQUIRED_ASR_FILES=(
  "Preprocessor.mlmodelc"
  "Encoder.mlmodelc"
  "Decoder.mlmodelc"
  "JointDecision.mlmodelc"
  "parakeet_vocab.json"
)

readonly -a REQUIRED_DIARIZER_FILES=(
  "Segmentation.mlmodelc"
  "FBank.mlmodelc"
  "Embedding.mlmodelc"
  "PldaRho.mlmodelc"
  "plda-parameters.json"
)

has_required_models() {
  local candidate_root="$1"
  local asr_dir="$candidate_root/$ASR_DIR_NAME"
  local diarizer_dir="$candidate_root/$DIARIZER_DIR_NAME"

  [[ -d "$asr_dir" && -d "$diarizer_dir" ]] || return 1

  local path
  for path in "${REQUIRED_ASR_FILES[@]}"; do
    [[ -e "$asr_dir/$path" ]] || return 1
  done

  for path in "${REQUIRED_DIARIZER_FILES[@]}"; do
    [[ -e "$diarizer_dir/$path" ]] || return 1
  done

  return 0
}

append_support_candidates() {
  local user_home="$1"
  [[ -n "$user_home" ]] || return 0

  source_candidates+=(
    "$user_home/Library/Application Support/MeetingTranscriber/Models"
    "$user_home/Library/Application Support/FluidAudio/Models"
  )
}

declare -a source_candidates=()
source_candidates+=("$SRCROOT/Resources/Models")

if [[ -n "${CFFIXED_USER_HOME:-}" ]]; then
  append_support_candidates "$CFFIXED_USER_HOME"
fi

login_user="$(id -un 2>/dev/null || true)"
user_home=""
if [[ -n "$login_user" ]]; then
  user_home="$(
    dscl . -read "/Users/$login_user" NFSHomeDirectory 2>/dev/null \
      | awk '{print $2}'
  )"
fi

if [[ -z "$user_home" && -n "$login_user" ]]; then
  user_home="$(eval echo "~$login_user")"
fi

append_support_candidates "$user_home"
append_support_candidates "$HOME"

model_source=""
candidate_report=""

for candidate in "${source_candidates[@]}"; do
  if [[ -n "$candidate_report" ]]; then
    candidate_report+=", "
  fi
  candidate_report+="$candidate"

  if has_required_models "$candidate"; then
    model_source="$candidate"
    break
  fi
done

if [[ -z "$model_source" ]]; then
  echo "warning: No offline model source found for app bundling. Checked: $candidate_report" >&2
  exit 0
fi

mkdir -p "$TARGET_MODELS_DIR"
rm -rf "$TARGET_ASR_DIR" "$TARGET_DIARIZER_DIR"

ditto "$model_source/$ASR_DIR_NAME" "$TARGET_ASR_DIR"
ditto "$model_source/$DIARIZER_DIR_NAME" "$TARGET_DIARIZER_DIR"
xattr -cr "$APP_BUNDLE_DIR"

echo "Staged offline models from $model_source into $TARGET_MODELS_DIR"
