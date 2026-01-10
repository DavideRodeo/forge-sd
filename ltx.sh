#!/bin/bash
set -euo pipefail

source /venv/main/bin/activate
COMFYUI_DIR="${WORKSPACE}/ComfyUI"

##############################################
# LOGGING AVANZATO
##############################################

LOG_PREFIX="[LTX]"
log_info()  { echo "${LOG_PREFIX} [INFO]  $*"; }
log_warn()  { echo "${LOG_PREFIX} [WARN]  $*" >&2; }
log_error() { echo "${LOG_PREFIX} [ERROR] $*" >&2; }

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
# NODI DA INSTALLARE
##############################################

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

##############################################
# MODELLI
##############################################

CHECKPOINT_MODELS=(
    "https://huggingface.co/Lightricks/LTX-2/resolve/main/ltx-2-19b-dev.safetensors"
)

LATENT_UPSCALE_MODELS=(
    "https://huggingface.co/Lightricks/LTX-2/resolve/main/ltx-2-spatial-upscaler-x2-1.0.safetensors"
)

TEXT_ENCODERS=(
    "https://civitai.com/api/download/models/2579572"
)
DIFFUSION_MODELS=()
UNET_MODELS=()
LORA_MODELS=(
    "https://huggingface.co/Lightricks/LTX-2/resolve/main/ltx-2-19b-distilled-lora-384.safetensors"
)
VAE_MODELS=()
ESRGAN_MODELS=()
CONTROLNET_MODELS=()
CLIP_MODELS=()

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
# DOWNLOAD FILE (stile default.txt)
##############################################

provisioning_download() {
    local url="$1"
    local dest="$2"

    mkdir -p "$dest"

    local auth_token=""
    if [[ -n $HF_TOKEN && $url =~ ^https://([a-zA-Z0-9_-]+\.)?huggingface\.co ]]; then
        auth_token="$HF_TOKEN"
    elif [[ -n $CIVITAI_TOKEN && $url =~ ^https://([a-zA-Z0-9_-]+\.)?civitai\.com ]]; then
        auth_token="$CIVITAI_TOKEN"
    fi

    log_info "Download: $url"

    if [[ -n $auth_token ]]; then
        wget --header="Authorization: Bearer $auth_token" \
             -qnc --content-disposition --show-progress \
             -P "$dest" "$url"
    else
        wget -qnc --content-disposition --show-progress \
             -P "$dest" "$url"
    fi
}

##############################################
# MULTI-FILE
##############################################

provisioning_get_files() {
    local dest="$1"; shift
    local arr=("$@")

    (( ${#arr[@]} == 0 )) && return

    mkdir -p "$dest"
    log_info "Scarico ${#arr[@]} file in $dest"

    for url in "${arr[@]}"; do
        log_info "Scarico: $url"
        provisioning_download "$url" "$dest"
    done
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

    log_info "Reinstallazione requirements..."
    pip install --no-cache-dir -r requirements.txt
}

##############################################
# DOWNLOAD + UPDATE NODI
##############################################

provisioning_get_nodes() {
    local nodes_dir="${COMFYUI_DIR}/custom_nodes"
    mkdir -p "$nodes_dir"

    log_info "Gestione nodi custom (${#NODES[@]} nodi)"

    for repo in "${NODES[@]}"; do
        local name="${repo##*/}"
        local path="${nodes_dir}/${name}"

        if [[ -d "$path/.git" ]]; then
            log_info "Aggiornamento nodo esistente: $name"
            (cd "$path" && git_with_retry "git pull $name" git pull --rebase --autostash)
        else
            log_info "Clonazione nuovo nodo: $repo"
            git_with_retry "git clone $name" git clone "$repo" "$path" --recursive
        fi

        if [[ -f "$path/requirements.txt" ]]; then
            log_info "Installazione requirements per nodo: $name"
            pip install --no-cache-dir -r "$path/requirements.txt"
        fi
    done
}

##############################################
# START
##############################################

provisioning_start() {

    log_info "=== INIZIO PROVISIONING LTX MINIMAL + UPDATE ==="

    provisioning_has_valid_hf_token && log_info "Token HF valido" || log_warn "Token HF assente"
    provisioning_has_valid_civitai_token && log_info "Token Civitai valido" || log_warn "Token Civitai assente"

    provisioning_update_comfyui
    provisioning_get_nodes

    provisioning_get_files "${COMFYUI_DIR}/models/checkpoints" "${CHECKPOINT_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/latent_upscale_models" "${LATENT_UPSCALE_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/text_encoders" "${TEXT_ENCODERS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/diffusion_models" "${DIFFUSION_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/unet" "${UNET_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/lora" "${LORA_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/controlnet" "${CONTROLNET_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/clip" "${CLIP_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/vae" "${VAE_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/esrgan" "${ESRGAN_MODELS[@]}"

    log_info "=== PROVISIONING COMPLETATO ==="
}

##############################################
# EXEC
##############################################

if [[ ! -f /.noprovisioning ]]; then
    provisioning_start
else
    log_warn "/.noprovisioning presente, provisioning saltato."
fi
