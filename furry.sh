#!/bin/bash

set -m
LOG_FILE="/provisioning.log"

source /venv/main/bin/activate
FORGE_DIR=${WORKSPACE}/stable-diffusion-webui-forge

APT_PACKAGES=()
PIP_PACKAGES=()

CHECKPOINT_MODELS=(
    "https://civitai.com/api/download/models/1981743?type=Model&format=SafeTensor&size=pruned&fp=fp16"
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

function provisioning_download() {
    url="$1"
    dest="$2"

    mkdir -p "$dest"

    # Detect provider
    if [[ $url == https://huggingface.co/* || $url == https://*.huggingface.co/* ]]; then
        auth_token="$HF_TOKEN"
    elif [[ $url == https://civitai.com/* || $url == https://*.civitai.com/* ]]; then
        auth_token="$CIVITAI_TOKEN"
    else
        auth_token=""
    fi

    echo "Inizio download: $url" | tee -a "$LOG_FILE"

    # Extract a safe filename (avoid long AWS URLs)
    filename=$(basename "${url%%\?*}")
    outfile="$dest/$filename"

    max_retries=3
    attempt=1

    while (( attempt <= max_retries )); do
        echo "Tentativo $attempt di $max_retries..." | tee -a "$LOG_FILE"

        if [[ -n "$auth_token" ]]; then
            wget --header="Authorization: Bearer $auth_token" \
                 --trust-server-names \
                 -O "$outfile" \
                 "$url" 2>&1 | tee -a "$LOG_FILE"
        else
            wget --trust-server-names \
                 -O "$outfile" \
                 "$url" 2>&1 | tee -a "$LOG_FILE"
        fi

        if [[ $? -eq 0 ]]; then
            echo "Download completato!" | tee -a "$LOG_FILE"
            return 0
        fi

        echo "Download fallito, ritento..." | tee -a "$LOG_FILE"
        sleep $((attempt * 2))
        ((attempt++))
    done

    echo "ERRORE: impossibile scaricare $url dopo $max_retries tentativi" | tee -a "$LOG_FILE"
    return 1
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
