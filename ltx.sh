#!/bin/bash

source /venv/main/bin/activate
COMFYUI_DIR=${WORKSPACE}/ComfyUI

# Packages are installed after nodes so we can fix them...

APT_PACKAGES=(
    #"package-1"
    #"package-2"
)

PIP_PACKAGES=(
    #"package-1"
    #"package-2"
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
)

WORKFLOWS=(
)

INPUT=(
    
)

CHECKPOINT_MODELS=(
    "https://huggingface.co/Lightricks/LTX-2/resolve/main/ltx-2-19b-dev.safetensors"
)

TEXT_ENCODERS=(

    "https://huggingface.co/google/gemma-3-12b-it-qat-q4_0-unquantized"
)

DIFFUSION_MODELS=(
    

)

CLIP_MODELS=(
    
)

LATENT_UPSCALE_MODELS=(
    "https://huggingface.co/Lightricks/LTX-2/resolve/main/ltx-2-spatial-upscaler-x2-1.0.safetensors"
)
UNET_MODELS=(
)

LORA_MODELS=(
)

VAE_MODELS=(
)

ESRGAN_MODELS=(
)

CONTROLNET_MODELS=(
)

### DO NOT EDIT BELOW HERE UNLESS YOU KNOW WHAT YOU ARE DOING ###

function provisioning_start() {
    provisioning_print_header
    provisioning_get_apt_packages
    provisioning_update_comfyui
    provisioning_get_nodes
    provisioning_get_pip_packages
    workflows_dir="${COMFYUI_DIR}/user/default/workflows"
    mkdir -p "${workflows_dir}"
    provisioning_get_files \
        "${workflows_dir}" \
        "${WORKFLOWS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/input" \
        "${INPUT[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/checkpoints" \
        "${CHECKPOINT_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/diffusion_models" \
        "${DIFFUSION_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/unet" \
        "${UNET_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/lora" \
        "${LORA_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/controlnet" \
        "${CONTROLNET_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/clip" \
        "${CLIP_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/vae" \
        "${VAE_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/esrgan" \
        "${ESRGAN_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/latent_upscale_models" \
        "${LATENT_UPSCALE_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/text_encoders" \
        "${TEXT_ENCODERS[@]}"
    provisioning_print_end
}

function provisioning_get_apt_packages() {
    if [[ -n $APT_PACKAGES ]]; then
            sudo $APT_INSTALL ${APT_PACKAGES[@]}
    fi
}

function provisioning_get_pip_packages() {
    if [[ -n $PIP_PACKAGES ]]; then
            pip install --no-cache-dir ${PIP_PACKAGES[@]}
    fi
}

# We must be at release tag v0.3.34 or greater for fp8 support
provisioning_update_comfyui() {
    cd ${COMFYUI_DIR}

    echo "Aggiornamento ComfyUI alla versione nightly (master)..."

    # Recupera tutto dal repository
    git fetch --all

    # Passa al branch master (nightly)
    git checkout master

    # Aggiorna all'ultima commit
    git pull

    # Installa le dipendenze aggiornate
    pip install --no-cache-dir -r requirements.txt

    echo "ComfyUI aggiornato alla nightly!"
}


function provisioning_get_nodes() {
    for repo in "${NODES[@]}"; do
        dir="${repo##*/}"
        path="${COMFYUI_DIR}/custom_nodes/${dir}"
        requirements="${path}/requirements.txt"
        if [[ -d $path ]]; then
            if [[ ${AUTO_UPDATE,,} != "false" ]]; then
                printf "Updating node: %s...\n" "${repo}"
                ( cd "$path" && git pull )
                if [[ -e $requirements ]]; then
                   pip install --no-cache-dir -r "$requirements"
                fi
            fi
        else
            printf "Downloading node: %s...\n" "${repo}"
            git clone "${repo}" "${path}" --recursive
            if [[ -e $requirements ]]; then
                pip install --no-cache-dir -r "${requirements}"
            fi
        fi
    done
}

function provisioning_get_files() {
    if [[ -z $2 ]]; then return 1; fi
    
    dir="$1"
    mkdir -p "$dir"
    shift
    arr=("$@")
    printf "Downloading %s model(s) to %s...\n" "${#arr[@]}" "$dir"
    for url in "${arr[@]}"; do
        printf "Downloading: %s\n" "${url}"
        provisioning_download "${url}" "${dir}"
        printf "\n"
    done
}

function provisioning_print_header() {
    printf "\n##############################################\n#                                            #\n#          Provisioning container            #\n#                                            #\n#         This will take some time           #\n#                                            #\n# Your container will be ready on completion #\n#                                            #\n##############################################\n\n"
}

function provisioning_print_end() {
    printf "\nProvisioning complete:  Application will start now\n\n"
}

function provisioning_has_valid_hf_token() {
    [[ -n "$HF_TOKEN" ]] || return 1
    url="https://huggingface.co/api/whoami-v2"

    response=$(curl -o /dev/null -s -w "%{http_code}" -X GET "$url" \
        -H "Authorization: Bearer $HF_TOKEN" \
        -H "Content-Type: application/json")

    # Check if the token is valid
    if [ "$response" -eq 200 ]; then
        return 0
    else
        return 1
    fi
}

function provisioning_has_valid_civitai_token() {
    [[ -n "$CIVITAI_TOKEN" ]] || return 1
    url="https://civitai.com/api/v1/models?hidden=1&limit=1"

    response=$(curl -o /dev/null -s -w "%{http_code}" -X GET "$url" \
        -H "Authorization: Bearer $CIVITAI_TOKEN" \
        -H "Content-Type: application/json")

    # Check if the token is valid
    if [ "$response" -eq 200 ]; then
        return 0
    else
        return 1
    fi
}

# Download from $1 URL to $2 file path
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

    echo "Inizio download: $url"

    max_retries=3
    attempt=1

    while (( attempt <= max_retries )); do
        echo "Tentativo $attempt di $max_retries..."

        if [[ -n "$auth_token" ]]; then
            if [[ $url == https://civitai.com/* ]]; then
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

        if [[ $? -eq 0 ]]; then
            echo "Download completato!"
            return 0
        fi

        echo "Download fallito, ritento..."
        sleep $((attempt * 2))
        ((attempt++))
    done

    echo "ERRORE: impossibile scaricare $url dopo $max_retries tentativi"
    return 1
}



# Allow user to disable provisioning if they started with a script they didn't want
if [[ ! -f /.noprovisioning ]]; then
    provisioning_start
fi
