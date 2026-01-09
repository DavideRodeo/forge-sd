#!/bin/bash
set -euo pipefail

source /venv/main/bin/activate
COMFYUI_DIR="${WORKSPACE}/ComfyUI"

##############################################
# CONFIGURAZIONE UTENTE
##############################################

APT_INSTALL="apt-get install -y"
APT_PACKAGES=( jq )
PIP_PACKAGES=()

NODES=(
    "https://github.com/rgthree/rgthree-comfy"
    "https://github.com/yolain/ComfyUI-Easy-Use"
    "https://github.com/kijai/ComfyUI-KJNodes"
    "https://github.com/Fannovel16/ComfyUI-Frame-Interpolation"
    "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite"
    "https://github.com/Artificial-Sweetener/comfyui-WhiteRabbit"
    "https://github.com/city96/ComfyUI-GGUF"
    "https://github.com/kael558/ComfyUI-GGUF-FantasyTalking"
    "https://github.com/Lightricks/ComfyUI-LTXVideo"
    "https://github.com/ltdrdata/ComfyUI-Impact-Pack"
    "https://github.com/evanspearman/ComfyMath"
    "https://github.com/ClownsharkBatwing/RES4LYF"
)

HF_REPOS=()

WORKFLOWS=()
INPUT=()

CHECKPOINT_MODELS=(
    "https://huggingface.co/Lightricks/LTX-2/resolve/main/ltx-2-19b-dev.safetensors"
)

TEXT_ENCODERS=(
  # "https://civitai.com/api/download/models/2579572"
)

DIFFUSION_MODELS=()
CLIP_MODELS=()
LATENT_UPSCALE_MODELS=(
    "https://huggingface.co/Lightricks/LTX-2/resolve/main/ltx-2-spatial-upscaler-x2-1.0.safetensors"
)
UNET_MODELS=()
LORA_MODELS=(
    # "https://huggingface.co/Lightricks/LTX-2/resolve/main/ltx-2-19b-distilled-lora-384.safetensors"
)
VAE_MODELS=()
ESRGAN_MODELS=()
CONTROLNET_MODELS=()

##############################################
# LOGGING
##############################################

LOG_PREFIX="[PROVISIONING]"

log_info()  { echo "${LOG_PREFIX} [INFO]  $*"; }
log_warn()  { echo "${LOG_PREFIX} [WARN]  $*" >&2; }
log_error() { echo "${LOG_PREFIX} [ERROR] $*" >&2; }

##############################################
# UTILS
##############################################

git_with_retry() {
    local desc="$1"; shift
    local max=3 attempt=1

    while (( attempt <= max )); do
        log_info "$desc (tentativo $attempt/$max)"
        if "$@"; then return 0; fi
        log_warn "$desc fallito, ritento..."
        sleep $((attempt * 2))
        ((attempt++))
    done

    log_error "$desc fallito dopo $max tentativi"
    return 1
}

##############################################
# VALIDAZIONE FILE MODELLI
##############################################

provisioning_validate_model_file() {
    local file="$1"

    [[ -s "$file" ]] || { log_error "File vuoto/corrotto: $file"; return 1; }

    if head -n1 "$file" | grep -q "git-lfs.github.com"; then
        log_error "File LFS pointer: $file"
        return 1
    fi

    if head -n1 "$file" | grep -qi "<!DOCTYPE html"; then
        log_error "File HTML ricevuto: $file"
        return 1
    fi

    if head -n1 "$file" | grep -q "{" && jq empty "$file" 2>/dev/null; then
        log_error "File JSON ricevuto: $file"
        return 1
    fi

    log_info "File valido: $file"
    return 0
}

##############################################
# TOKEN CHECK
##############################################

provisioning_has_valid_hf_token() {
    [[ -n "${HF_TOKEN:-}" ]] || return 1
    local code
    code=$(curl -o /dev/null -s -w "%{http_code}" \
        -H "Authorization: Bearer $HF_TOKEN" \
        https://huggingface.co/api/whoami-v2)
    [[ "$code" -eq 200 ]]
}

provisioning_has_valid_civitai_token() {
    [[ -n "${CIVITAI_TOKEN:-}" ]] || return 1
    local code
    code=$(curl -o /dev/null -s -w "%{http_code}" \
        -H "Authorization: Bearer $CIVITAI_TOKEN" \
        "https://civitai.com/api/v1/models?hidden=1&limit=1")
    [[ "$code" -eq 200 ]]
}

##############################################
# APT
##############################################

provisioning_get_apt_packages() {
    if (( ${#APT_PACKAGES[@]} > 0 )); then
        log_info "Aggiornamento APT..."
        sudo apt-get update -y

        log_info "Installazione pacchetti: ${APT_PACKAGES[*]}"
        sudo $APT_INSTALL "${APT_PACKAGES[@]}"
    else
        log_info "Nessun pacchetto APT richiesto."
    fi
}

##############################################
# PIP
##############################################

provisioning_get_pip_packages() {
    if (( ${#PIP_PACKAGES[@]} > 0 )); then
        log_info "Installazione pacchetti pip..."
        pip install --no-cache-dir "${PIP_PACKAGES[@]}"
    else
        log_info "Nessun pacchetto pip richiesto."
    fi
}

##############################################
# UPDATE COMFYUI
##############################################

provisioning_update_comfyui() {
    cd "$COMFYUI_DIR"

    log_info "Aggiornamento ComfyUI..."
    git_with_retry "git fetch" git fetch --all --prune
    git_with_retry "git checkout master" git checkout master
    git_with_retry "git pull" git pull origin master

    log_info "Installazione requirements..."
    pip install --no-cache-dir -r requirements.txt
}

##############################################
# NODI CUSTOM
##############################################

provisioning_get_nodes() {
    for repo in "${NODES[@]}"; do
        local dir="${repo##*/}"
        local path="${COMFYUI_DIR}/custom_nodes/${dir}"

        if [[ -d "$path" ]]; then
            log_info "Aggiornamento nodo: $dir"
            (cd "$path" && git_with_retry "git pull $dir" git pull --rebase --autostash)
        else
            log_info "Clonazione nodo: $repo"
            git_with_retry "git clone $dir" git clone "$repo" "$path" --recursive
        fi

        if [[ -f "$path/requirements.txt" ]]; then
            pip install --no-cache-dir -r "$path/requirements.txt"
        fi
    done
}

##############################################
# DOWNLOAD FILE
##############################################

provisioning_download() {
    local url="$1"
    local dest="$2"

    mkdir -p "$dest"

    local token=""
    local provider="generic"

    if [[ $url == https://huggingface.co/* ]]; then
        provider="huggingface"
        provisioning_has_valid_hf_token && token="$HF_TOKEN"
    elif [[ $url == https://civitai.com/* ]]; then
        provider="civitai"
        provisioning_has_valid_civitai_token && token="$CIVITAI_TOKEN"
    fi

    log_info "Download ($provider): $url"

    local max=3 attempt=1
    while (( attempt <= max )); do
        log_info "Tentativo $attempt/$max"

        if [[ -n "$token" ]]; then
            if [[ $provider == "civitai" ]]; then
                wget --content-disposition -P "$dest" "${url}?token=${token}"
            else
                wget --header="Authorization: Bearer $token" --content-disposition -P "$dest" "$url"
            fi
        else
            wget --content-disposition -P "$dest" "$url"
        fi

        local file
        file=$(ls -t "$dest" | head -n1)

        if provisioning_validate_model_file "$dest/$file"; then
            log_info "Download valido: $url"
            return 0
        fi

        log_warn "File non valido, ritento..."
        sleep $((attempt * 2))
        ((attempt++))
    done

    log_error "Download fallito: $url"
    return 1
}

##############################################
# FILE MULTIPLI
##############################################

provisioning_get_files() {
    local dest="$1"; shift
    local arr=("$@")

    (( ${#arr[@]} == 0 )) && { log_info "Nessun file per $dest"; return; }

    mkdir -p "$dest"
    log_info "Scarico ${#arr[@]} file in $dest"

    for url in "${arr[@]}"; do
        provisioning_download "$url" "$dest"
    done
}

##############################################
# REPORT
##############################################

provisioning_print_model_report() {
    log_info "=== REPORT MODELLI ==="

    local base="${COMFYUI_DIR}/models"
    local valid=() invalid=()

    while IFS= read -r file; do
        if provisioning_validate_model_file "$file" >/dev/null; then
            valid+=("$file")
        else
            invalid+=("$file")
        fi
    done < <(find "$base" -type f -name "*.safetensors")

    echo ""
    log_info "Modelli validi:"
    for f in "${valid[@]}"; do echo " - ${f#$base/}"; done

    echo ""
    log_info "Modelli NON validi:"
    if (( ${#invalid[@]} == 0 )); then
        echo " - Nessuno 🎉"
    else
        for f in "${invalid[@]}"; do echo " - ${f#$base/}"; done
    fi
}

##############################################
# START
##############################################

provisioning_start() {
    provisioning_print_header

    provisioning_has_valid_hf_token && log_info "Token HF valido" || log_warn "Token HF assente"
    provisioning_has_valid_civitai_token && log_info "Token Civitai valido" || log_warn "Token Civitai assente"

    provisioning_get_apt_packages
    provisioning_update_comfyui
    provisioning_get_nodes
    provisioning_get_pip_packages

    local workflows_dir="${COMFYUI_DIR}/user/default/workflows"
    mkdir -p "$workflows_dir"

    provisioning_get_files "$workflows_dir" "${WORKFLOWS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/input" "${INPUT[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/checkpoints" "${CHECKPOINT_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/diffusion_models" "${DIFFUSION_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/unet" "${UNET_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/lora" "${LORA_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/controlnet" "${CONTROLNET_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/clip" "${CLIP_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/vae" "${VAE_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/esrgan" "${ESRGAN_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/latent_upscale_models" "${LATENT_UPSCALE_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/text_encoders" "${TEXT_ENCODERS[@]}"

    provisioning_print_model_report
    provisioning_print_end
}

##############################################
# HEADER / FOOTER
##############################################

provisioning_print_header() {
    printf "\n##############################################\n"
    printf "#          Provisioning container            #\n"
    printf "##############################################\n\n"
}

provisioning_print_end() {
    printf "\nProvisioning complete: Application will start now\n\n"
}

##############################################
# EXEC
##############################################

if [[ ! -f /.noprovisioning ]]; then
    provisioning_start
else
    log_warn "/.noprovisioning presente, salto provisioning."
fi
