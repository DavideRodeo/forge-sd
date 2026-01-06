#!/bin/bash
set -euo pipefail

source /venv/main/bin/activate
COMFYUI_DIR=${WORKSPACE}/ComfyUI

##############################################
# CONFIGURAZIONE UTENTE
##############################################

APT_PACKAGES=(
    jq
)

PIP_PACKAGES=(
)

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

# Repository HuggingFace da clonare come repo git
HF_REPOS=(
    "https://huggingface.co/google/gemma-3-12b-it-qat-q4_0-unquantized"
)

WORKFLOWS=()
INPUT=()

CHECKPOINT_MODELS=(
    "https://huggingface.co/Lightricks/LTX-2/resolve/main/ltx-2-19b-dev.safetensors"
)

TEXT_ENCODERS=(
    # Vuoto: gemma3 ora è gestito tramite HF_REPOS
)

DIFFUSION_MODELS=()
CLIP_MODELS=()
LATENT_UPSCALE_MODELS=(
    "https://huggingface.co/Lightricks/LTX-2/resolve/main/ltx-2-spatial-upscaler-x2-1.0.safetensors"
)
UNET_MODELS=()
LORA_MODELS=(
    "https://huggingface.co/Lightricks/LTX-2/resolve/main/ltx-2-19b-distilled-lora-384.safetensors"
)
VAE_MODELS=()
ESRGAN_MODELS=()
CONTROLNET_MODELS=()

##############################################
# LOGGING / UTILS
##############################################

LOG_PREFIX="[PROVISIONING]"

log_info() {
    echo "${LOG_PREFIX} [INFO]  $*"
}

log_warn() {
    echo "${LOG_PREFIX} [WARN]  $*" >&2
}

log_error() {
    echo "${LOG_PREFIX} [ERROR] $*" >&2
}

# Esegue un comando git con retry
git_with_retry() {
    local desc="$1"
    shift
    local max_retries=3
    local attempt=1

    while (( attempt <= max_retries )); do
        log_info "$desc (tentativo $attempt/$max_retries)"
        if "$@"; then
            return 0
        fi
        log_warn "$desc fallito, ritento..."
        sleep $((attempt * 2))
        ((attempt++))
    done

    log_error "$desc fallito dopo $max_retries tentativi"
    return 1
}

##############################################
# VALIDATORE FILE MODELLI
##############################################

provisioning_validate_model_file() {
    local file="$1"

    # File inesistente o vuoto
    if [[ ! -s "$file" ]]; then
        log_error "File corrotto o vuoto: $file"
        return 1
    fi

    # Pointer Git LFS
    if head -n 1 "$file" | grep -q "version https://git-lfs.github.com/spec"; then
        log_error "File LFS non scaricato correttamente (pointer): $file"
        return 1
    fi

    # HTML (download fallito)
    if head -n 1 "$file" | grep -qi "<!DOCTYPE html"; then
        log_error "File HTML ricevuto invece del modello (errore download): $file"
        return 1
    fi

    # JSON (errore API)
    if head -n 1 "$file" | grep -q "{"; then
        if jq empty "$file" 2>/dev/null; then
            log_error "File JSON ricevuto invece del modello (errore API): $file"
            return 1
        fi
    fi

    # Se arriva qui, il file sembra valido
    log_info "File valido: $file"
    return 0
}


##############################################
# VALIDAZIONE TOKEN
##############################################

function provisioning_has_valid_hf_token() {
    [[ -n "${HF_TOKEN:-}" ]] || return 1
    local url="https://huggingface.co/api/whoami-v2"

    local response
    response=$(curl -o /dev/null -s -w "%{http_code}" -X GET "$url" \
        -H "Authorization: Bearer $HF_TOKEN" \
        -H "Content-Type: application/json")

    [[ "$response" -eq 200 ]]
}

function provisioning_has_valid_civitai_token() {
    [[ -n "${CIVITAI_TOKEN:-}" ]] || return 1
    local url="https://civitai.com/api/v1/models?hidden=1&limit=1"

    local response
    response=$(curl -o /dev/null -s -w "%{http_code}" -X GET "$url" \
        -H "Authorization: Bearer $CIVITAI_TOKEN" \
        -H "Content-Type: application/json")

    [[ "$response" -eq 200 ]]
}

##############################################
# REPORT FINALE MODELLI
##############################################

provisioning_print_model_report() {
    log_info "=== REPORT MODELLI ==="

    local base="${COMFYUI_DIR}/models"
    local valid=()
    local invalid=()

    # Cerca tutti i file .safetensors
    while IFS= read -r file; do
        if provisioning_validate_model_file "$file" >/dev/null 2>&1; then
            valid+=("$file")
        else
            invalid+=("$file")
        fi
    done < <(find "$base" -type f -name "*.safetensors")

    echo ""
    log_info "Modelli validi:"
    for f in "${valid[@]}"; do
        echo " - ${f#$base/}"
    done

    echo ""
    log_info "Modelli NON validi:"
    if [[ ${#invalid[@]} -eq 0 ]]; then
        echo " - Nessuno 🎉"
    else
        for f in "${invalid[@]}"; do
            echo " - ${f#$base/}"
        done
    fi

    echo ""
}


##############################################
# FUNZIONI PRINCIPALI
##############################################

function provisioning_start() {
    provisioning_print_header

    # Log di stato token per debug
    if provisioning_has_valid_hf_token; then
        log_info "Token HuggingFace valido rilevato."
    else
        log_warn "Nessun token HuggingFace valido rilevato (o assente)."
    fi

    if provisioning_has_valid_civitai_token; then
        log_info "Token Civitai valido rilevato."
    else
        log_warn "Nessun token Civitai valido rilevato (o assente)."
    fi

    provisioning_get_apt_packages
    provisioning_update_comfyui
    provisioning_get_nodes
    provisioning_get_pip_packages

    local workflows_dir="${COMFYUI_DIR}/user/default/workflows"
    mkdir -p "${workflows_dir}"

    provisioning_get_files "${workflows_dir}" "${WORKFLOWS[@]}"
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

    # Repo HuggingFace come text_encoders
    provisioning_get_hf_repos "${COMFYUI_DIR}/models/text_encoders" "${HF_REPOS[@]}"
    provisioning_print_model_report
    provisioning_print_end
}

##############################################
# INSTALLAZIONE PACCHETTI
##############################################

function provisioning_get_apt_packages() {
    if [[ ${#APT_PACKAGES[@]} -gt 0 ]]; then
        log_info "Installazione pacchetti APT: ${APT_PACKAGES[*]}"
        sudo $APT_INSTALL "${APT_PACKAGES[@]}"
    else
        log_info "Nessun pacchetto APT da installare."
    fi
}

function provisioning_get_pip_packages() {
    if [[ ${#PIP_PACKAGES[@]} -gt 0 ]]; then
        log_info "Installazione pacchetti pip: ${PIP_PACKAGES[*]}"
        pip install --no-cache-dir "${PIP_PACKAGES[@]}"
    else
        log_info "Nessun pacchetto pip da installare."
    fi
}

##############################################
# UPDATE COMFYUI
##############################################

provisioning_update_comfyui() {
    cd "${COMFYUI_DIR}"

    log_info "Aggiornamento ComfyUI alla versione nightly (master)..."

    git_with_retry "git fetch --all" git fetch --all --prune
    git_with_retry "git checkout master" git checkout master
    git_with_retry "git pull origin master" git pull origin master

    log_info "Installazione requirements ComfyUI..."
    pip install --no-cache-dir -r requirements.txt

    log_info "ComfyUI aggiornato alla nightly."
}

##############################################
# NODI CUSTOM
##############################################

function provisioning_get_nodes() {
    for repo in "${NODES[@]}"; do
        local dir="${repo##*/}"
        local path="${COMFYUI_DIR}/custom_nodes/${dir}"
        local requirements="${path}/requirements.txt"

        if [[ -d $path ]]; then
            if [[ ${AUTO_UPDATE:-"",,} != "false" ]]; then
                log_info "Aggiornamento nodo: ${repo}"
                (
                    cd "$path"
                    git_with_retry "git pull per $dir" git pull --rebase --autostash
                )
                if [[ -e $requirements ]]; then
                    log_info "Installazione requirements per nodo $dir"
                    pip install --no-cache-dir -r "$requirements"
                fi
            else
                log_info "AUTO_UPDATE=false, salto update per nodo: ${repo}"
            fi
        else
            log_info "Clonazione nuovo nodo: ${repo}"
            git_with_retry "git clone nodo $dir" git clone "${repo}" "${path}" --recursive
            if [[ -e $requirements ]]; then
                log_info "Installazione requirements per nodo $dir"
                pip install --no-cache-dir -r "$requirements"
            fi
        fi
    done
}

##############################################
# REPO HUGGINGFACE (GIT)
##############################################

function provisioning_get_hf_repos() {
    local dest="$1"
    shift
    local repos=("$@")

    mkdir -p "$dest"

    if [[ ${#repos[@]} -eq 0 ]]; then
        log_info "Nessuna repo HuggingFace da clonare."
        return 0
    fi

    log_info "Gestione repository HuggingFace in $dest..."

    for repo in "${repos[@]}"; do
        local name="${repo##*/}"
        local path="${dest}/${name}"

        # Costruzione URL con token se disponibile
        local clone_url="$repo"
        if provisioning_has_valid_hf_token; then
            clone_url="${repo/https:\/\//https:\/\/user:${HF_TOKEN}@}"
            log_info "Uso token HF per clonare $name"
        else
            log_warn "Clonazione HF senza token valido: $repo"
        fi

        if [[ -d "$path/.git" ]]; then
            log_info "Aggiornamento repo HF: $name"
            (
                cd "$path"
                git_with_retry "git pull per HF repo $name" git pull --rebase --autostash
                git lfs pull

                # Validazione modelli scaricati
                for f in $(find . -type f -name "*.safetensors"); do
                    provisioning_validate_model_file "$f" \
                        || log_warn "Modello non valido in repo HF: $f"
                done
            )
        else
            log_info "Clonazione repo HF: $repo"
            (
                cd "$dest"
                git_with_retry "git clone HF repo $name" git clone "$clone_url" "$name"
                cd "$name"
                git lfs install
                git lfs pull

                # Validazione modelli scaricati
                for f in $(find . -type f -name "*.safetensors"); do
                    provisioning_validate_model_file "$f" \
                        || log_warn "Modello non valido in repo HF: $f"
                done
            )
        fi
    done
}


##############################################
# DOWNLOAD FILE SINGOLI
##############################################

function provisioning_get_files() {
    if [[ $# -lt 2 ]]; then
        return 0
    fi

    local dir="$1"
    shift
    local arr=("$@")

    if [[ ${#arr[@]} -eq 0 ]]; then
        log_info "Nessun file da scaricare per $dir."
        return 0
    fi

    mkdir -p "$dir"
    log_info "Download di ${#arr[@]} file in $dir..."

    for url in "${arr[@]}"; do
        log_info "Download file: $url"
        provisioning_download "$url" "$dir"
    done
}

##############################################
# DOWNLOAD GENERICO (wget + retry, HF/Civitai aware)
##############################################

function provisioning_download() {
    local url="$1"
    local dest="$2"

    mkdir -p "$dest"

    local auth_token=""
    local provider="generic"

    if [[ $url == https://huggingface.co/* ]]; then
        provider="huggingface"
        if provisioning_has_valid_hf_token; then
            auth_token="$HF_TOKEN"
        else
            log_warn "Scarico da HuggingFace senza token valido: $url"
        fi
    elif [[ $url == https://civitai.com/* ]]; then
        provider="civitai"
        if provisioning_has_valid_civitai_token; then
            auth_token="$CIVITAI_TOKEN"
        else
            log_warn "Scarico da Civitai senza token valido: $url"
        fi
    fi

    log_info "Inizio download ($provider): $url"

    local max_retries=3
    local attempt=1

    while (( attempt <= max_retries )); do
        log_info "Tentativo download $attempt/$max_retries per $url"

        if [[ -n "$auth_token" ]]; then
            if [[ $provider == "civitai" ]]; then
                wget --content-disposition \
                     -P "$dest" \
                     "${url}?token=${auth_token}" \
                     2>&1
            else
                wget --header="Authorization: Bearer $auth_token" \
                     --content-disposition \
                     -P "$dest" \
                     "$url" \
                     2>&1
            fi
        else
            wget --content-disposition \
                 -P "$dest" \
                 "$url" \
                 2>&1
        fi

        local status=$?

        if [[ $status -eq 0 ]]; then
    local downloaded_file
    downloaded_file=$(ls -t "$dest" | head -n 1)

if provisioning_validate_model_file "$dest/$downloaded_file"; then
        log_info "Download completato e valido: $url"
        return 0
    else
        log_warn "File non valido, ritento download: $url"
    fi
fi


        log_warn "Download fallito (exit $status) per $url, ritento..."
        sleep $((attempt * 2))
        ((attempt++))
    done

    log_error "Impossibile scaricare $url dopo $max_retries tentativi"
    return 1
}

##############################################
# PRINT
##############################################

function provisioning_print_header() {
    printf "\n##############################################\n#                                            #\n#          Provisioning container            #\n#                                            #\n#         This will take some time           #\n#                                            #\n# Your container will be ready on completion #\n#                                            #\n##############################################\n\n"
}

function provisioning_print_end() {
    printf "\nProvisioning complete: Application will start now\n\n"
}

##############################################
# START
##############################################

if [[ ! -f /.noprovisioning ]]; then
    provisioning_start
else
    log_warn "/.noprovisioning presente, salto provisioning."
fi
