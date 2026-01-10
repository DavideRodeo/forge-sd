#!/bin/bash

set -m
LOG_FILE="/provisioning.log"

source /venv/main/bin/activate
FORGE_DIR=${WORKSPACE}/stable-diffusion-webui-forge

APT_PACKAGES=()
PIP_PACKAGES=()

CHECKPOINT_MODELS=(
    "https://civitai.com/api/download/models/2518501"
)
EXTENSIONS=(
    "https://github.com/Haoming02/sd-forge-couple"
    "https://github.com/AlUlkesh/stable-diffusion-webui-images-browser.git"
    "https://github.com/Bing-su/adetailer.git"
    "https://github.com/Amadeus-AI/img2img-hires-fix.git"
    "https://github.com/MINENEMA/sd-webui-quickrecents.git"
    "https://github.com/altoiddealer/--sd-webui-ar-plusplus.git"
    "https://github.com/Physton/sd-webui-prompt-all-in-one"
)
UNET_MODELS=()
LORA_MODELS=()
VAE_MODELS=()
ESRGAN_MODELS=()
CONTROLNET_MODELS=()

##############################################
# TOKEN CHECK
##############################################

function provisioning_has_valid_civitai_token() {
    [[ -n "$CIVITAI_TOKEN" ]] || return 1

    response=$(curl -o /dev/null -s -w "%{http_code}" \
        -H "Authorization: Bearer $CIVITAI_TOKEN" \
        "https://civitai.com/api/v1/models?limit=1")

    [[ "$response" -eq 200 ]]
}

##############################################
# DOWNLOAD WITH RETRY + TOKEN + FILENAME FIX
##############################################

provisioning_download() {
    local url="$1"
    local dest="$2"

    mkdir -p "$dest"

    # Estrai nome file dall’URL
    local filename="${url##*/}"
    local outfile="${dest}/${filename}"

    local token=""
    local provider="generic"

    if [[ $url == https://huggingface.co/* ]]; then
        provider="huggingface"
        provisioning_has_valid_hf_token && token="$HF_TOKEN"
    elif [[ $url == https://civitai.com/* ]]; then
        provider="civitai"
        provisioning_has_valid_civitai_token && token="$CIVITAI_TOKEN"
    fi

    log_info "Download ($provider): $url → $outfile"

    local max=3 attempt=1
    while (( attempt <= max )); do
        log_info "Tentativo $attempt/$max"

        rm -f "$outfile"

        if [[ -n "$token" ]]; then
            if [[ $provider == "civitai" ]]; then
                wget --quiet --show-progress \
                     -O "$outfile" \
                     "${url}?token=${token}"
            else
                wget --quiet --show-progress \
                     --header="Authorization: Bearer $token" \
                     -O "$outfile" \
                     "$url"
            fi
        else
            wget --quiet --show-progress \
                 -O "$outfile" \
                 "$url"
        fi

        if provisioning_validate_model_file "$outfile"; then
            log_info "Download valido: $outfile"
            return 0
        fi

        log_warn "File non valido, ritento..."
        sleep $((attempt * 2))
        ((attempt++))
    done

    log_error "Download fallito: $url"
    return 1
}


function provisioning_get_extensions() {
    dir="${FORGE_DIR}/extensions"
    mkdir -p "$dir"

    for repo in "${EXTENSIONS[@]}"; do
        name=$(basename "$repo")
        path="${dir}/${name}"

        if [[ -d "$path" ]]; then
            echo "Aggiorno estensione: $name"
            (cd "$path" && git pull)
        else
            echo "Clono estensione: $name"
            git clone "$repo" "$path" --recursive
        fi
    done
}



##############################################
# GENERIC HELPERS
##############################################

function provisioning_get_files() {
    if [[ -z $2 ]]; then return 1; fi

    dir="$1"
    mkdir -p "$dir"
    shift
    arr=("$@")

    echo "Scarico ${#arr[@]} modelli in $dir" | tee -a "$LOG_FILE"

    for url in "${arr[@]}"; do
        provisioning_download "$url" "$dir"
    done
}

function provisioning_print_header() {
    printf "\n##############################################\n#                                            #\n#          Provisioning container            #\n#                                            #\n#         Questo richiederà un po' di tempo  #\n#                                            #\n# Il container sarà pronto al termine         #\n#                                            #\n##############################################\n\n"
}

function provisioning_print_end() {
    printf "\nProvisioning complete: Application will start now\n\n"
}
##############################################
# MAIN PROVISIONING
##############################################

function provisioning_start() {
    provisioning_print_header

    # Wait for workspace mount
    while [[ ! -d "${FORGE_DIR}" ]]; do
        echo "Attendo mount workspace..." | tee -a "$LOG_FILE"
        sleep 1
    done

    # Validate Civitai token
    if ! provisioning_has_valid_civitai_token; then
        echo "ERRORE: CIVITAI_TOKEN non valido o mancante!" | tee -a "$LOG_FILE"
        exit 1
    fi

    # Download models
    provisioning_get_files \
        "${FORGE_DIR}/models/Stable-diffusion" \
        "${CHECKPOINT_MODELS[@]}"

    provisioning_get_extensions

    echo "ATTENDO COMPLETAMENTO DOWNLOAD..." | tee -a "$LOG_FILE"
    wait
    sleep 3

    echo "Provisioning completato, avvio WebUI..." | tee -a "$LOG_FILE"
    sleep 2

    cd "${FORGE_DIR}"
    LD_PRELOAD=libtcmalloc_minimal.so.4 \
        python launch.py \
            --skip-python-version-check \
            --no-download-sd-model \
            --do-not-download-clip \
            --no-half \
            --port 11404 \
            --exit

    provisioning_print_end
}

##############################################
# ENTRYPOINT
##############################################

if [[ ! -f /.noprovisioning ]]; then
    provisioning_start
fi
