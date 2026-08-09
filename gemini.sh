#!/bin/bash

source /venv/main/bin/activate
COMFYUI_DIR=${WORKSPACE}/ComfyUI

APT_PACKAGES=(
    "aria2"
)

PIP_PACKAGES=(
    "diffusers"
    "einops"
    "huggingface_hub>=0.25.2"
    "ninja~=1.11.1.4"
    "transformers[timm]>=4.45.0"
)

NODES=(
    "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite"
)

WORKFLOWS=(
)

INPUT=(
)

# Modelli H3
CHECKPOINT_MODELS=(
    "http://95.110.181.79:8080/diffusion_models/minimax_h3_ref2va_pruned_int8_convrot.safetensors"
)

# Qwen Text Encoder
CLIP_MODELS=(
    "http://95.110.181.79:8080/text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors"
)

UNET_MODELS=(
)

LORA_MODELS=(
    "http://95.110.181.79:8080/loras/minimax_h3_turbo_v4_step600_ema.safetensors"
)

# VAE
VAE_MODELS=(
    "http://95.110.181.79:8080/vae/minimax_h3_audio_vae_fp32.safetensors"
    "http://95.110.181.79:8080/vae/minimax_h3_video_vae_fp16.safetensors"
)

ESRGAN_MODELS=(
)

CONTROLNET_MODELS=(
)

### DO NOT EDIT BELOW HERE UNLESS YOU KNOW WHAT YOU ARE DOING ###

function provisioning_start() {
    provisioning_print_header
    provisioning_get_apt_packages
    
    # 1. Aggiorna ComfyUI alla versione nightly (master)
    provisioning_update_comfyui
    
    # 2. Scarica i nodi specificati
    provisioning_get_nodes
    
    # 3. Aggiorna tutti i nodi esistenti
    provisioning_update_all_nodes
    
    # 4. Configura il ComfyUI-Manager
    provisioning_configure_manager
    
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
        "${COMFYUI_DIR}/models/diffusion_models" \
        "${CHECKPOINT_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/unet" \
        "${UNET_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/loras" \
        "${LORA_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/controlnet" \
        "${CONTROLNET_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/text_encoders" \
        "${CLIP_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/vae" \
        "${VAE_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/upscale_models" \
        "${ESRGAN_MODELS[@]}"
    provisioning_print_end
}

function provisioning_get_apt_packages() {
    if [[ -n $APT_PACKAGES ]]; then
            sudo apt-get update && sudo apt-get install -y ${APT_PACKAGES[@]}
    fi
}

function provisioning_get_pip_packages() {
    if [[ -n $PIP_PACKAGES ]]; then
            pip install --no-cache-dir ${PIP_PACKAGES[@]}
    fi
}

# Modificata per forzare sempre l'ultima versione disponibile (Nightly)
function provisioning_update_comfyui() {
    printf "Updating ComfyUI to latest (nightly)...\n"
    cd "${COMFYUI_DIR}"
    git fetch --all
    # Assicurati di essere sul ramo master e tira le ultime modifiche
    git checkout master || git checkout main
    git pull
    pip install --no-cache-dir -r requirements.txt
}

# Nuova funzione: Aggiorna tutti i nodi custom preesistenti
function provisioning_update_all_nodes() {
    printf "Updating all existing custom nodes to their latest versions...\n"
    for dir in "${COMFYUI_DIR}/custom_nodes"/*/; do
        if [ -d "${dir}.git" ]; then
            printf "Updating node: %s\n" "$(basename "${dir}")"
            ( cd "${dir}" && git pull )
            if [ -f "${dir}requirements.txt" ]; then
                pip install --no-cache-dir -r "${dir}requirements.txt"
            fi
        fi
    done
}

# Nuova funzione: Inserisce il config.ini di ComfyUI-Manager
function provisioning_configure_manager() {
    printf "Configuring ComfyUI-Manager...\n"
    local manager_dir="${COMFYUI_DIR}/user/__manager"
    mkdir -p "${manager_dir}"
    
    # Crea il config.ini
    cat << 'EOF' > "${manager_dir}/config.ini"
[default]
preview_method = none
git_exe = 
use_uv = False
channel_url = https://raw.githubusercontent.com/ltdrdata/ComfyUI-Manager/main
share_option = all
bypass_ssl = False
file_logging = True
component_policy = workflow
update_policy = nightly-comfyui
windows_selector_event_loop_policy = False
model_download_by_agent = False
downgrade_blacklist = 
security_level = weak
always_lazy_install = False
network_mode = public
db_mode = cache
allow_git_url_install = True
allow_pip_install = True
EOF
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
    
    if [ ${#arr[@]} -eq 0 ]; then
        return 0
    fi
    
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

function provisioning_download() {
    if [[ -n $HF_TOKEN && $1 =~ ^https://([a-zA-Z0-9_-]+\.)?huggingface\.co(/|$|\?) ]]; then
        auth_token="$HF_TOKEN"
    elif 
        [[ -n $CIVITAI_TOKEN && $1 =~ ^https://([a-zA-Z0-9_-]+\.)?civitai\.com(/|$|\?) ]]; then
        auth_token="$CIVITAI_TOKEN"
    fi
    
    filename=$(basename "$1")
    
    if [[ -n $auth_token ]];then
        aria2c --console-log-level=error -c -x 16 -s 16 -k 1M --header="Authorization: Bearer $auth_token" -d "$2" -o "$filename" "$1"
    else
        aria2c --console-log-level=error -c -x 16 -s 16 -k 1M -d "$2" -o "$filename" "$1"
    fi
}

if [[ ! -f /.noprovisioning ]]; then
    provisioning_start
fi
