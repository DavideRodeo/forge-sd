#!/bin/bash

source /venv/main/bin/activate
COMFYUI_DIR=${WORKSPACE}/ComfyUI

##############################################
# CONFIGURAZIONE UTENTE
##############################################

APT_PACKAGES=(
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

# NUOVO: repository HuggingFace da clonare con git
HF_REPOS=(
    "https://huggingface.co/google/gemma-3-12b-it-qat-q4_0-unquantized"
)

WORKFLOWS=()
INPUT=()

CHECKPOINT_MODELS=(
    "https://huggingface.co/Lightricks/LTX-2/resolve/main/ltx-2-19b-dev.safetensors"
)

TEXT_ENCODERS=(
    # Vuoto: ora gestito da HF_REPOS
)

DIFFUSION_MODELS=()
CLIP_MODELS=()
LATENT_UPSCALE_MODELS=(
    "https://huggingface.co/Lightricks/LTX-2/resolve/main/ltx-2-spatial-upscaler-x2-1.0.safetensors"
)
UNET_MODELS=()
LORA_MODELS=()
VAE_MODELS=()
ESRGAN_MODELS=()
CONTROLNET_MODELS=()

##############################################
# FUNZIONI PRINCIPALI
##############################################

function provisioning_start() {
    provisioning_print_header
    provisioning_get_apt_packages
    provisioning_update_comfyui
    provisioning_get_nodes
    provisioning_get_pip_packages

    workflows_dir="${COMFYUI_DIR}/user/default/workflows"
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

    # NUOVO: clonazione repo HuggingFace
    provisioning_get_hf_repos "${COMFYUI_DIR}/models/text_encoders" "${HF_REPOS[@]}"

    provisioning_print_end
}

##############################################
# INSTALLAZIONE PACCHETTI
##############################################

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

##############################################
# UPDATE COMFYUI
##############################################

provisioning_update_comfyui() {
    cd ${COMFYUI_DIR}

    echo "Aggiornamento ComfyUI alla versione nightly (master)..."

    git fetch --all
    git checkout master
    git pull

    pip install --no-cache-dir -r requirements.txt

    echo "ComfyUI aggiornato alla nightly!"
}

##############################################
# NODI CUSTOM
##############################################

function provisioning_get_nodes() {
    for repo in "${NODES[@]}"; do
        dir="${repo##*/}"
        path="${COMFYUI_DIR}/custom_nodes/${dir}"
        requirements="${path}/requirements.txt"

        if [[ -d $path ]]; then
            if [[ ${AUTO_UPDATE,,} != "false" ]]; then
                echo "Updating node: ${repo}"
                ( cd "$path" && git pull )
                [[ -e $requirements ]] && pip install --no-cache-dir -r "$requirements"
            fi
        else
            echo "Downloading node: ${repo}"
            git clone "${repo}" "${path}" --recursive
            [[ -e $requirements ]] && pip install --no-cache-dir -r "$requirements"
        fi
    done
}

##############################################
# NUOVO: CLONAZIONE REPO HUGGINGFACE
##############################################

function provisioning_get_hf_repos() {
    dest="$1"
    shift
    repos=("$@")

    mkdir -p "$dest"

    echo "Clonazione repository HuggingFace in $dest..."

    for repo in "${repos[@]}"; do
        name="${repo##*/}"
        path="${dest}/${name}"

        if [[ -d "$path/.git" ]]; then
            echo "Aggiornamento repo HF: $name"
            (cd "$path" && git pull)
        else
            echo "Clonazione repo HF: $repo"
            GIT_LFS_SKIP_SMUDGE=1 git clone "$repo" "$path"
        fi
    done
}

##############################################
# DOWNLOAD FILE SINGOLI
##############################################

function provisioning_get_files() {
    if [[ -z $2 ]]; then return 1; fi

    dir="$1"
    mkdir -p "$dir"
    shift
    arr=("$@")

    echo "Downloading ${#arr[@]} file(s) in $dir..."

    for url in "${arr[@]}"; do
        echo "Downloading: $url"
        provisioning_download "$url" "$dir"
        echo
    done
}

##############################################
# DOWNLOAD GENERICO (wget)
##############################################

function provisioning_download() {
    url="$1"
    dest="$2"

    mkdir -p "$dest"

    if [[ $url == https://huggingface.co/* ]]; then
        auth_token="$HF_TOKEN"
    elif [[ $url == https://civitai.com/* ]]; then
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
                wget --content-disposition -P "$dest" "${url}?token=${auth_token}" 2>&1
            else
                wget --header="Authorization: Bearer $auth_token" --content-disposition -P "$dest" "$url" 2>&1
            fi
        else
            wget --content-disposition -P "$dest" "$url" 2>&1
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
fi
