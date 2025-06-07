#!/bin/bash

#================================================================
# SYNOPSIS (概要)
#   macOS 开发环境一键配置脚本
#
# DESCRIPTION (描述)
#   此脚本专为 macOS 设计，采用“配置先行”模式，通过交互式菜单收集您的所有需求，
#   然后生成一份执行计划供您确认并导出。最后全自动地完成 Homebrew 的安装、软件配置、
#   环境变量设置、安装后健康检查和自动重载 Shell，旨在提供极致、可靠的新 Mac 初始化体验。
#
# AUTHOR:  Yu
# VERSION: 1.0
# UPDATE:  2025/06/07
#
# USAGE (使用方法)
#   1. [可选] 创建外部软件列表 (Brewfile):
#      在脚本同级目录下创建 Brewfile 文件，可被自动检测并用于安装。
#
#   2. 运行脚本:
#      在终端中执行命令: bash setup_script.sh
#      首次运行时，按提示完成所有选择。您可以将配置导出，以便下次使用。
#
#   3. [可选] 使用导出的配置:
#      将导出的 `config_export.sh` 和 `Brewfile_export` 文件与主脚本放在同一目录。
#      再次运行主脚本时，它会自动检测并询问是否加载此配置，实现一键复刻。
#================================================================

set -euo pipefail

# --- 全局配置与常量 ---
readonly SCRIPT_VERSION="1.0"
readonly MAX_RETRIES=3
readonly RETRY_INTERVAL=3
readonly REQUIRED_DISK_SPACE_KB=10485760 # 10GB
readonly PROFILE_HEADER="# Added by macos-setup-script (v$SCRIPT_VERSION)"

# 脚本运行时变量
NO_COLOR=""
if ! [[ -t 1 ]]; then
    NO_COLOR="true"
fi

SHELL_PROFILE=""
USE_CHINA_MIRROR=false
ANDROID_SDK_PATH="$HOME/Library/Android/sdk"
GRADLE_HOME_PATH="$HOME/.gradle"
FVM_HOME_PATH="$HOME/.fvm"
SELECTED_JDK_PACKAGE_NAME=""
LOG_FILE=""

declare -a FORMULAS_TO_INSTALL
declare -a CASKS_TO_INSTALL
declare -a ALL_SELECTED_PACKAGES
declare -a PACKAGES_SUCCESS
declare -a PACKAGES_FAILURE
declare -a HEALTH_CHECK_RESULTS

# --- 软件列表定义 (兼容旧版 Bash, 格式 "key:description") ---
declare -r -a DEV_TOOLS_FORMULAS=("git:版本控制" "node:JS 运行环境" "java:Java 开发环境" "flutter:跨平台应用框架" "fvm:Flutter 版本管理器" "gradle:构建自动化工具")
declare -r -a DEV_TOOLS_CASKS=("visual-studio-code:代码编辑器" "android-studio:安卓官方 IDE" "docker:容器化平台" "sublime-text:轻量代码编辑器" "jetbrains-toolbox:JetBrains 全家桶")
declare -r -a BROWSERS_CASKS=("google-chrome:谷歌浏览器" "firefox:火狐浏览器" "microsoft-edge-dev:Edge 开发者版" "arc:Arc 浏览器")
declare -r -a COMMUNICATION_CASKS=("wechat:微信" "qq:QQ" "telegram-desktop:Telegram" "discord:Discord" "slack:Slack")
declare -r -a OFFICE_DESIGN_CASKS=("wps-office:WPS 办公套件" "figma:UI 设计工具" "obsidian:知识管理笔记")
declare -r -a UTILS_CASKS=("iterm2:强大的终端" "rectangle:窗口管理工具" "stats:菜单栏系统监控" "the-unarchiver:全能解压工具" "raycast:启动器与效率工具")


# --- 辅助函数 ---

# 打印带颜色的文本
print_color() {
    if [[ -n "$NO_COLOR" ]]; then
        echo "$2"
        return
    fi
    local color=$1; local text=$2
    case $color in
        "green") echo -e "\033[0;32m${text}\033[0m" ;; "yellow") echo -e "\033[0;33m${text}\033[0m" ;;
        "cyan") echo -e "\033[0;36m${text}\033[0m" ;; "red") echo -e "\033[0;31m${text}\033[0m" ;;
        "magenta") echo -e "\033[0;35m${text}\033[0m" ;; "blue") echo -e "\033[0;34m${text}\033[0m" ;;
        *) echo "$text" ;;
    esac
}

# 日志记录函数
log() {
    local message="$1"
    # 使用兼容性更好的 sed 命令清理 ANSI 颜色代码
    local clean_message; clean_message=$(echo "$message" | sed -E $'s/\x1B\\[[0-9;]*[a-zA-Z]//g')
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $clean_message" >> "$LOG_FILE"
}

# 获取脚本真实目录(处理符号链接, 兼容 macOS)
get_script_dir() {
    local SCRIPT_SOURCE="${BASH_SOURCE[0]}"
    while [ -h "$SCRIPT_SOURCE" ]; do
        local SCRIPT_DIR; SCRIPT_DIR="$( cd -P "$( dirname "$SCRIPT_SOURCE" )" >/dev/null 2>&1 && pwd )"
        SCRIPT_SOURCE="$(readlink "$SCRIPT_SOURCE")"
        [[ $SCRIPT_SOURCE != /* ]] && SCRIPT_SOURCE="$SCRIPT_DIR/$SCRIPT_SOURCE"
    done
    cd -P "$( dirname "$SCRIPT_SOURCE" )" >/dev/null 2>&1 && pwd
}


# 设置日志文件
setup_logging() {
    local SCRIPT_DIR; SCRIPT_DIR=$(get_script_dir)
    LOG_FILE="$SCRIPT_DIR/mac_setup_$(date +%Y-%m-%d).log"
    # shellcheck disable=SC2015
    [ -f "$LOG_FILE" ] || touch "$LOG_FILE" || { print_color "red" "无法创建日志文件: $LOG_FILE"; exit 1; }
    echo -e "\n\n==================== New Run at $(date +'%Y-%m-%d %H:%M:%S') (v$SCRIPT_VERSION) ====================" >> "$LOG_FILE"
    log "macOS Setup Script Log Initialized."
    print_color "green" "✔ 日志文件位于脚本目录: $LOG_FILE"
}

# 带有加载动画和重试机制的命令执行器
run_with_spinner() {
    local title="$1"; local retries="$2"; shift 2; local cmd=("$@"); local cmd_log_file="/tmp/setup_script_cmd.log"; local spinner_chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"; local exit_code=1
    for ((i=1; i<=retries; i++)); do
        log "Executing (Attempt $i/$retries): ${cmd[*]}"; "${cmd[@]}" > "$cmd_log_file" 2>&1 &
        local pid=$!; echo -n "$(print_color 'cyan' "[  ] $title")"
        while ps -p $pid > /dev/null; do
            for (( j=0; j<${#spinner_chars}; j++ )); do echo -ne "\r$(print_color 'cyan' "[${spinner_chars:$j:1}] $title (尝试 $i/$retries)")"; sleep 0.1; done
        done
        wait $pid; exit_code=$?
        if [ $exit_code -eq 0 ]; then echo -e "\r$(print_color 'green' "[✔] $title")"; log "SUCCESS: $title"; break; fi
        log "FAILURE (Attempt $i/$retries): $title (Exit Code: $exit_code)"; if [ $i -lt $retries ]; then print_color "yellow" "\n操作失败, 正在准备重试 ($((i+1))/$retries)..."; sleep "$RETRY_INTERVAL"; fi
    done
    if [ $exit_code -ne 0 ]; then
        echo -e "\r$(print_color 'red' "[✘] $title (多次尝试后失败, 详情请查看 $LOG_FILE)")"; log "Command output from last attempt:"; cat "$cmd_log_file" >> "$LOG_FILE"
    fi; rm -f "$cmd_log_file"; return $exit_code
}

# 安全地向 PATH 添加路径
add_path() {
    local path_to_add="$1"
    if [[ -d "$path_to_add" ]] && [[ ":$PATH:" != *":$path_to_add:"* ]]; then
        add_to_profile "export PATH=\"$path_to_add:\$PATH\""
    fi
}

# 将环境变量配置写入 Shell 配置文件
add_to_profile() {
    local line_to_add="$1"
    
    if [ -s "$SHELL_PROFILE" ] && [ -n "$(tail -c 1 "$SHELL_PROFILE")" ]; then
        echo "" >> "$SHELL_PROFILE"
    fi
    if ! grep -qF -- "$PROFILE_HEADER" "$SHELL_PROFILE"; then
        echo -e "\n$PROFILE_HEADER" >> "$SHELL_PROFILE"
    fi
    if ! grep -qF -- "$line_to_add" "$SHELL_PROFILE"; then
        log "Writing to $SHELL_PROFILE: $line_to_add"
        print_color "cyan" "  ↳ 正在写入: $line_to_add"
        echo "$line_to_add" >> "$SHELL_PROFILE"
    fi
}

# --- 核心功能函数 ---

# 飞行前检查：确保核心依赖存在
preflight_check() {
    print_color "yellow" "执行飞行前检查: 正在检查核心依赖..."
    if ! command -v curl &>/dev/null; then
        print_color "red" "核心依赖 curl 未找到！"
        xcode-select --install
        print_color "red" "安装完成后，请按任意键退出并重新运行脚本。"; read -n 1 -s; exit 1
    fi
    log "curl found."

    if ! xcode-select -p &>/dev/null; then
        log "Xcode Command Line Tools not found."; print_color "red" "核心依赖 Xcode Command Line Tools 未找到！"
        xcode-select --install
        print_color "red" "安装完成后，请按任意键退出并重新运行脚本。"; read -n 1 -s; exit 1
    fi; log "Xcode Command Line Tools found."
    print_color "green" "✔ 核心依赖已满足。"
}

# 网络连通性检查
check_network() {
    log "Checking network connectivity..."
    local endpoints=("https://www.github.com" "https://www.baidu.com")
    for endpoint in "${endpoints[@]}"; do
        if curl -s --connect-timeout 5 "$endpoint" &>/dev/null; then
            log "Network check passed: $endpoint"
            return 0
        fi
    done
    log "Network check failed."
    return 1
}

# 检查磁盘空间
check_disk_space() {
    log "Checking disk space..."; print_color "yellow" "执行飞行前检查: 正在检查磁盘空间..."
    local available_kb; available_kb=$(df -Pk . | tail -1 | awk '{print $4}')
    if (( available_kb < REQUIRED_DISK_SPACE_KB )); then
        local available_gb=$((available_kb / 1024 / 1024)); local required_gb=$((REQUIRED_DISK_SPACE_KB / 1024 / 1024))
        print_color "red" "警告: 磁盘可用空间 ($available_gb GB) 低于推荐值 ($required_gb GB)。"
        read -p "是否仍然继续? (y/N) " choice
        if [[ ! "$choice" =~ ^[yY]$ ]]; then log "Cancelled: low disk space."; print_color "yellow" "操作已取消。"; exit 0; fi
    fi; log "Disk space OK."; print_color "green" "✔ 磁盘空间充足。"
}

# JDK 版本选择器
select_jdk_version() {
    if /usr/libexec/java_home &>/dev/null; then
        local current_java_version; current_java_version=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}')
        print_color "yellow" "检测到系统已存在 JDK 版本: $current_java_version"
        read -p "是否仍要通过 Homebrew 安装新的 JDK 版本并覆盖配置？ (y/N) " choice
        if [[ ! "$choice" =~ ^[yY]$ ]]; then log "User skipped new JDK installation."; return; fi
    fi

    log "Prompting for JDK version."; print_color "yellow" "\n请选择您想安装的 JDK 版本:"
    local jdk_options=( "OpenJDK 11 (LTS)" "OpenJDK 17 (LTS) (推荐)" "OpenJDK 21 (LTS)" "OpenJDK (最新稳定版)" "手动输入其他版本" "返回" )
    select opt in "${jdk_options[@]}"; do
        case $opt in
            "OpenJDK 11 (LTS)") SELECTED_JDK_PACKAGE_NAME="openjdk@11"; break;;
            "OpenJDK 17 (LTS) (推荐)") SELECTED_JDK_PACKAGE_NAME="openjdk@17"; break;;
            "OpenJDK 21 (LTS)") SELECTED_JDK_PACKAGE_NAME="openjdk@21"; break;;
            "OpenJDK (最新稳定版)") SELECTED_JDK_PACKAGE_NAME="openjdk"; break;;
            "手动输入其他版本") read -p "请输入 Homebrew 包名 (如: openjdk@18): " custom_jdk; if [ -n "$custom_jdk" ]; then SELECTED_JDK_PACKAGE_NAME="$custom_jdk"; fi; break;;
            "返回") SELECTED_JDK_PACKAGE_NAME=""; break;;
            *) print_color "red" "无效选项 '$REPLY'。";;
        esac
    done
    if [ -n "$SELECTED_JDK_PACKAGE_NAME" ]; then FORMULAS_TO_INSTALL+=("$SELECTED_JDK_PACKAGE_NAME"); log "JDK selected: $SELECTED_JDK_PACKAGE_NAME"; print_color "green" "已选择 JDK: $SELECTED_JDK_PACKAGE_NAME"; fi
}

# 配置自定义路径
configure_custom_paths() {
    log "Configuring custom paths."; print_color "cyan" "\n第零步: 配置 SDK 存放路径..."
    read -p "您是否要自定义 SDK 存放路径? (y/N) " choice
    if [[ ! "$choice" =~ ^[yY]$ ]]; then log "Using default paths."; print_color "green" "将使用默认路径。"; return; fi
    
    local new_path
    read -p "请输入新的 Android SDK 路径 (当前: $ANDROID_SDK_PATH): " new_path
    if [ -n "$new_path" ]; then 
        new_path="${new_path/#\~/$HOME}"
        if [[ ! -d "$(dirname "$new_path")" ]]; then
            print_color "yellow" "警告: 父目录不存在，将自动创建: $(dirname "$new_path")"
            mkdir -p "$(dirname "$new_path")"
        fi
        ANDROID_SDK_PATH="$new_path"
    fi
    read -p "请输入新的 Gradle Home 路径 (当前: $GRADLE_HOME_PATH): " new_path; if [ -n "$new_path" ]; then GRADLE_HOME_PATH="${new_path/#\~/$HOME}"; fi
    read -p "请输入新的 FVM Home 路径 (当前: $FVM_HOME_PATH): " new_path; if [ -n "$new_path" ]; then FVM_HOME_PATH="${new_path/#\~/$HOME}"; fi
    log "Custom paths configured: ANDROID=$ANDROID_SDK_PATH, GRADLE=$GRADLE_HOME_PATH, FVM=$FVM_HOME_PATH"; print_color "green" "路径配置完成！"
}

# 检测 Shell
detect_shell() {
    log "Detecting shell..."; print_color "cyan" "\n第一步: 检测您的 Shell 环境..."
    local SHELL_TYPE; SHELL_TYPE=$(basename "$SHELL")
    if [[ "$SHELL_TYPE" == "zsh" ]]; then SHELL_PROFILE="$HOME/.zshrc"; else SHELL_PROFILE="$HOME/.bash_profile"; fi
    if [ ! -f "$SHELL_PROFILE" ]; then print_color "yellow" "未找到 $SHELL_PROFILE 文件，将自动创建。"; touch "$SHELL_PROFILE"; fi
    log "Shell: $SHELL_TYPE, Profile: $SHELL_PROFILE"; print_color "green" "检测到 Shell: $SHELL_TYPE, 将使用 $SHELL_PROFILE 配置。"; sleep 1
}

# 选择 Homebrew 安装源
select_homebrew_source() {
    log "Selecting Homebrew source."; print_color "cyan" "\n第二步: 选择 Homebrew 安装源..."
    if ! check_network; then
        print_color "red" "网络连接失败！"; read -p "强烈建议使用国内镜像源，是否同意？(Y/n)" choice
        case "$choice" in n|N ) USE_CHINA_MIRROR=false;; * ) USE_CHINA_MIRROR=true;; esac
    elif curl -s --head -m 5 "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh" | head -n 1 | grep "200 OK" > /dev/null; then
        read -p "您可以流畅访问官方源, 是否依然要使用国内镜像源? (y/N) " choice
        case "$choice" in y|Y ) USE_CHINA_MIRROR=true;; * ) USE_CHINA_MIRROR=false;; esac
    else
        read -p "访问官方源超时! 强烈建议使用国内镜像源, 是否同意? (Y/n) " choice
        case "$choice" in n|N ) USE_CHINA_MIRROR=false;; * ) USE_CHINA_MIRROR=true;; esac
    fi
    log "Use China mirror: $USE_CHINA_MIRROR"
}

# 处理 Brewfile 文件 (兼容旧版 Bash)
handle_brewfile_selection() {
    log "Handling Brewfile."; print_color "cyan" "\n第三步: 检查外部 Brewfile 文件..."
    if [ -f "Brewfile" ]; then
        log "Brewfile found."; print_color "green" "检测到 Brewfile 文件！"
        local brewfile_lines=(); while IFS= read -r line; do brewfile_lines+=("$line"); done < "Brewfile"
        local brewfile_formulas=(); local brewfile_casks=()
        for line in "${brewfile_lines[@]}"; do
            if [[ "$line" =~ ^brew[[:space:]]+'([^']*)'.* ]]; then brewfile_formulas+=("${BASH_REMATCH[1]}");
            elif [[ "$line" =~ ^cask[[:space:]]+'([^']*)'.* ]]; then brewfile_casks+=("${BASH_REMATCH[1]}"); fi
        done
        read -p "请选择如何处理此文件: [1]全部安装, [2]手动选择, [3]忽略: " choice
        case "$choice" in
            2) log "Selective install from Brewfile."
               FORMULAS_TO_INSTALL+=($(prompt_for_package_selection "从 Brewfile 中选择命令行工具:" "DEV_TOOLS_FORMULAS" "${brewfile_formulas[@]}"))
               CASKS_TO_INSTALL+=($(prompt_for_package_selection "从 Brewfile 中选择图形化应用:" "DEV_TOOLS_CASKS" "${brewfile_casks[@]}")) ;;
            3) log "Brewfile ignored."; print_color "yellow" "已忽略 Brewfile。" ;;
            *) log "Install all from Brewfile."; FORMULAS_TO_INSTALL+=("${brewfile_formulas[@]}"); CASKS_TO_INSTALL+=("${brewfile_casks[@]}") ;;
        esac
    else log "Brewfile not found."; print_color "yellow" "未在当前目录找到 Brewfile, 跳过。"; fi
}

# 交互式收集要安装的软件包
collect_packages_interactively() {
    while true; do
        log "Collecting packages interactively."; print_color "cyan" "\n第四步: 从内置列表中选择您想安装的软件..."
        
        local categories_map=(
            "选择 [基础开发工具] (命令行):DEV_TOOLS_FORMULAS:formula"
            "选择 [图形化开发应用]:DEV_TOOLS_CASKS:cask"
            "选择 [常用浏览器]:BROWSERS_CASKS:cask"
            "选择 [常用沟通工具]:COMMUNICATION_CASKS:cask"
            "选择 [设计与办公]:OFFICE_DESIGN_CASKS:cask"
            "选择 [系统实用工具]:UTILS_CASKS:cask"
        )
        local available_category_keys=(); for item in "${categories_map[@]}"; do available_category_keys+=("${item%%:*}"); done

        while true; do
            print_color "yellow" "\n请选择一个类别:"
            local menu_options=("${available_category_keys[@]}" "完成选择, 进入下一步")
            
            local choice; select opt in "${menu_options[@]}"; do choice=$opt; break; done
            if [[ "$choice" == "完成选择, 进入下一步" ]]; then break; fi

            local category_value; for item in "${categories_map[@]}"; do if [[ "$item" == "$choice"* ]]; then category_value="$item"; break; fi; done
            local package_array_name="${category_value#*:}"; package_array_name="${package_array_name%%:*}"
            local package_type="${category_value##*:}"
            
            local selected; selected=($(prompt_for_package_selection "$choice" "$package_array_name"))
            if [[ " ${selected[*]} " =~ " java " ]]; then
                print_color "yellow" "\n⚠️ 检测到选择 Java，将进入特定版本选择流程。"
                local new_selected=(); for item in "${selected[@]}"; do [[ "$item" != "java" ]] && new_selected+=("$item"); done
                selected=("${new_selected[@]}"); select_jdk_version
            fi

            if [ "$package_type" == "formula" ]; then FORMULAS_TO_INSTALL+=("${selected[@]}"); else CASKS_TO_INSTALL+=("${selected[@]}"); fi
            
            local temp_keys=(); for key in "${available_category_keys[@]}"; do if [[ "$key" != "$choice" ]]; then temp_keys+=("$key"); fi; done
            available_category_keys=("${temp_keys[@]}")
        done

        FORMULAS_TO_INSTALL=($(echo "${FORMULAS_TO_INSTALL[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
        CASKS_TO_INSTALL=($(echo "${CASKS_TO_INSTALL[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

        print_color "green" "\n您已选择以下软件:"
        if [ ${#FORMULAS_TO_INSTALL[@]} -gt 0 ]; then print_color "cyan" "  - 命令行工具:"; printf "    - %s\n" "${FORMULAS_TO_INSTALL[@]}"; fi
        if [ ${#CASKS_TO_INSTALL[@]} -gt 0 ]; then print_color "cyan" "  - 图形化应用:"; printf "    - %s\n" "${CASKS_TO_INSTALL[@]}"; fi
        
        read -p "是否还有遗漏, 需要返回重新选择? (y/N) " final_check
        if [[ ! "$final_check" =~ ^[yY]$ ]]; then break; fi
    done
}

# 提示用户从列表中选择指定的软件包 (子函数)
prompt_for_package_selection() {
    local title="$1" package_array_name="$2"
    local packages_available_ref="${package_array_name}[@]"
    local packages_available=("${!packages_available_ref}")
    local selected_packages=()
    if [ ${#packages_available[@]} -eq 0 ]; then return; fi
    
    local category_name; category_name=$(echo "$title" | sed -e 's/选择 \[//' -e 's/\].*//')
    print_color "yellow" "\n请为【$category_name】选择软件:"
    
    local display_keys=(); for item in "${packages_available[@]}"; do display_keys+=("${item%%:*}"); done

    for i in "${!packages_available[@]}"; do
        local key="${packages_available[$i]%%:*}"
        local desc="${packages_available[$i]#*:}"
        echo "  [$((i+1))] $key ($(print_color 'blue' "$desc"))"
    done

    local choices; while true; do read -p "请输入编号 (可多选, 用空格隔开): " -a choices; if [ ${#choices[@]} -eq 0 ]; then break; fi
        local all_valid=true; for item in "${choices[@]}"; do if ! [[ "$item" =~ ^[0-9]+$ ]] || [ "$item" -lt 1 ] || [ "$item" -gt ${#display_keys[@]} ]; then print_color "red" "输入错误: '$item'。"; all_valid=false; break; fi; done
        if [ "$all_valid" = true ]; then break; fi
    done
    for choice in "${choices[@]}"; do selected_packages+=("${display_keys[$((choice-1))]}")
    done; log "Selected for $category_name: ${selected_packages[*]}"; echo "${selected_packages[@]}"
}

# 收集并验证自定义软件
collect_custom_packages() {
    if ! command -v brew &>/dev/null; then print_color "yellow" "Homebrew 未安装，将跳过自定义包环节。"; return; fi
    print_color "cyan" "\n第五步: 安装其他软件..."; read -p "您是否要安装列表之外的其他 Homebrew 软件? (y/N) " choice
    if [[ ! "$choice" =~ ^[yY]$ ]]; then return; fi
    
    while true; do
        local pkg_name; read -p "请输入软件包名 (回车完成): " pkg_name
        if [ -z "$pkg_name" ]; then break; fi
        
        if run_with_spinner "正在验证 '$pkg_name'..." 1 "brew" "info" "$pkg_name"; then
            read -p "✔ '$pkg_name' 有效。是图形化应用(Cask)吗? (y/N) " is_cask
            if [[ "$is_cask" =~ ^[yY]$ ]]; then CASKS_TO_INSTALL+=("$pkg_name"); log "Custom Cask: $pkg_name"; else FORMULAS_TO_INSTALL+=("$pkg_name"); log "Custom Formula: $pkg_name"; fi
        else log "Invalid package: $pkg_name"; print_color "red" "✘ 未找到 '$pkg_name'。"; fi
    done
}

# 导出配置
export_configuration() {
    print_color "yellow" "\n请选择您想导出的格式:"; local opts=("Shell 脚本" "YAML" ".env"); select opt in "${opts[@]}"; do
        case $opt in
            "Shell 脚本") export_to_shell; break;;
            "YAML") export_to_yaml; break;;
            ".env") export_to_dotenv; break;;
            *) print_color "red" "无效选项 $REPLY";;
        esac
    done
}
export_to_shell() {
    local SCRIPT_DIR; SCRIPT_DIR=$(get_script_dir); local config_file="$SCRIPT_DIR/config_export.sh"; local brewfile_export="$SCRIPT_DIR/Brewfile_export"
    log "Exporting to Shell script..."; print_color "cyan" "正在导出为 Shell 脚本..."
    { printf "#!/bin/bash\n# Dev-Setup-Script Config (v%s)\n" "$SCRIPT_VERSION"; printf "USE_CHINA_MIRROR=%s\n" "$USE_CHINA_MIRROR"; printf "ANDROID_SDK_PATH=\"%s\"\n" "$ANDROID_SDK_PATH"; printf "GRADLE_HOME_PATH=\"%s\"\n" "$GRADLE_HOME_PATH"; printf "FVM_HOME_PATH=\"%s\"\n" "$FVM_HOME_PATH"; } > "$config_file"
    if [ ${#ALL_SELECTED_PACKAGES[@]} -gt 0 ]; then
        { printf "# Brewfile exported on %s\n" "$(date)"; for pkg in "${FORMULAS_TO_INSTALL[@]}"; do printf "brew '%s'\n" "$pkg"; done; for pkg in "${CASKS_TO_INSTALL[@]}"; do printf "cask '%s'\n" "$pkg"; done; } > "$brewfile_export"
    fi
    print_color "green" "✔ 配置已成功导出到:"; echo "  - $config_file"; if [ -f "$brewfile_export" ]; then echo "  - $brewfile_export"; fi
}
export_to_yaml() {
    local SCRIPT_DIR; SCRIPT_DIR=$(get_script_dir); local yml_file="$SCRIPT_DIR/config_export.yml"
    log "Exporting to YAML."; print_color "cyan" "正在导出为 YAML..."
    { printf "# Dev-Setup-Script Config (v%s)\n" "$SCRIPT_VERSION"; printf "settings:\n  use_china_mirror: %s\n" "$USE_CHINA_MIRROR"; printf "paths:\n  android_sdk: \"%s\"\n" "$ANDROID_SDK_PATH"; printf "  gradle_home: \"%s\"\n" "$GRADLE_HOME_PATH"; printf "  fvm_home: \"%s\"\n" "$FVM_HOME_PATH"; printf "packages:\n  formulas:\n"; for pkg in "${FORMULAS_TO_INSTALL[@]}"; do printf "    - %s\n" "$pkg"; done; printf "  casks:\n"; for pkg in "${CASKS_TO_INSTALL[@]}"; do printf "    - %s\n" "$pkg"; done; } > "$yml_file"
    print_color "green" "✔ 配置已成功导出到: $yml_file"
}
export_to_dotenv() {
    local SCRIPT_DIR; SCRIPT_DIR=$(get_script_dir); local env_file="$SCRIPT_DIR/config_export.env"
    log "Exporting to .env."; print_color "cyan" "正在导出为 .env..."
    local formulas_str; formulas_str=$(IFS=, ; echo "${FORMULAS_TO_INSTALL[*]}")
    local casks_str; casks_str=$(IFS=, ; echo "${CASKS_TO_INSTALL[*]}")
    { printf "# Dev-Setup-Script Config (v%s)\n" "$SCRIPT_VERSION"; printf "USE_CHINA_MIRROR=%s\n" "$USE_CHINA_MIRROR"; printf "ANDROID_SDK_PATH=\"%s\"\n" "$ANDROID_SDK_PATH"; printf "GRADLE_HOME_PATH=\"%s\"\n" "$GRADLE_HOME_PATH"; printf "FVM_HOME_PATH=\"%s\"\n" "$FVM_HOME_PATH"; printf "FORMULAS=\"%s\"\n" "$formulas_str"; printf "CASKS=\"%s\"\n" "$casks_str"; } > "$env_file"
    print_color "green" "✔ 配置已成功导出到: $env_file"
}

# 加载导出的配置
load_from_config_if_exists() {
    local config_file="config_export.sh"; local brewfile_export="Brewfile_export"
    if [ ! -f "$config_file" ] || [ ! -f "$brewfile_export" ]; then return 1; fi

    print_color "green" "✔ 发现导出的配置文件！"
    local config_version; config_version=$(grep 'v[0-9.]*)' "$config_file" | sed -n 's/.*(v\(.*\)).*/\1/p')
    if [[ "$config_version" != "$SCRIPT_VERSION" ]]; then print_color "yellow" "警告: 配置版本($config_version)与脚本版本($SCRIPT_VERSION)不匹配。"; fi

    read -p "是否加载此配置并跳过手动选择? (Y/n) " choice; if [[ "$choice" =~ ^[nN]$ ]]; then return 1; fi
    
    log "Loading from config files."; print_color "cyan" "正在加载配置..."
    while IFS= read -r line; do [[ "$line" =~ ^\s*# ]] || [[ -z "$line" ]] && continue; eval "$line"; done < "$config_file"

    local brew_lines=(); while IFS= read -r line; do brew_lines+=("$line"); done < "$brewfile_export"
    for line in "${brew_lines[@]}"; do
        if [[ "$line" =~ ^brew[[:space:]]+'([^']*)'.* ]]; then FORMULAS_TO_INSTALL+=("${BASH_REMATCH[1]}");
        elif [[ "$line" =~ ^cask[[:space:]]+'([^']*)'.* ]]; then CASKS_TO_INSTALL+=("${BASH_REMATCH[1]}"); fi
    done
    for pkg in "${FORMULAS_TO_INSTALL[@]}"; do if [[ "$pkg" == openjdk* ]]; then SELECTED_JDK_PACKAGE_NAME="$pkg"; break; fi; done
    return 0
}

# 预检查并过滤已安装的包
filter_already_installed() {
    log "Filtering installed packages."; print_color "cyan" "\n执行中: 正在预检查软件包安装状态..."
    local installed_formulas=(); while IFS= read -r line; do installed_formulas+=("$line"); done < <(brew list --formula)
    local installed_casks=(); while IFS= read -r line; do installed_casks+=("$line"); done < <(brew list --cask)

    local -a final_formulas=(); for pkg in "${FORMULAS_TO_INSTALL[@]}"; do if [[ " ${installed_formulas[*]} " =~ " ${pkg} " ]]; then print_color "yellow" "  - [已安装] $pkg (跳过)"; PACKAGES_SUCCESS+=("$pkg (已存在)"); else final_formulas+=("$pkg"); fi; done; FORMULAS_TO_INSTALL=("${final_formulas[@]}")
    local -a final_casks=(); for pkg in "${CASKS_TO_INSTALL[@]}"; do if [[ " ${installed_casks[*]} " =~ " ${pkg} " ]]; then print_color "yellow" "  - [已安装] $pkg (跳过)"; PACKAGES_SUCCESS+=("$pkg (已存在)"); else final_casks+=("$pkg"); fi; done; CASKS_TO_INSTALL=("${final_casks[@]}")
}

# 安装后健康检查
run_health_check() {
    log "Running health checks."; print_color "yellow" "\n执行中: 正在进行安装后健康检查..."
    local result_str version_output
    if command -v git &>/dev/null; then
        result_str="Git"; version_output=$(git --version); run_with_spinner "正在测试 $result_str..." 1 git --version &>/dev/null && HEALTH_CHECK_RESULTS+=("✔ $result_str: 可用 ($version_output)") || HEALTH_CHECK_RESULTS+=("✘ $result_str: 异常")
    fi
    if [ -n "$SELECTED_JDK_PACKAGE_NAME" ]; then
        result_str="Java ($SELECTED_JDK_PACKAGE_NAME)"; version_output=$(bash -c "source \"$SHELL_PROFILE\" &>/dev/null && java -version" 2>&1 | head -n 1); run_with_spinner "正在测试 $result_str..." 1 bash -c "source \"$SHELL_PROFILE\" &>/dev/null && java -version" &>/dev/null && HEALTH_CHECK_RESULTS+=("✔ $result_str: 可用 (${version_output})") || HEALTH_CHECK_RESULTS+=("✘ $result_str: 异常")
    fi
    if command -v node &>/dev/null; then
        result_str="Node.js"; version_output=$(node --version); run_with_spinner "正在测试 $result_str..." 1 node --version &>/dev/null && HEALTH_CHECK_RESULTS+=("✔ $result_str: 可用 ($version_output)") || HEALTH_CHECK_RESULTS+=("✘ $result_str: 异常")
    fi
    if command -v flutter &>/dev/null; then
        result_str="Flutter SDK"; version_output=$(bash -c "source \"$SHELL_PROFILE\" &>/dev/null && flutter --version" 2>&1 | head -n 1); run_with_spinner "正在测试 $result_str..." 1 bash -c "source \"$SHELL_PROFILE\" &>/dev/null && flutter --version" &>/dev/null && HEALTH_CHECK_RESULTS+=("✔ $result_str: 可用 ($version_output)") || HEALTH_CHECK_RESULTS+=("✘ $result_str: 异常")
    fi
    if command -v gradle &>/dev/null; then
        result_str="Gradle"; version_output=$(bash -c "source \"$SHELL_PROFILE\" &>/dev/null && gradle --version" 2>&1 | grep "Gradle"); run_with_spinner "正在测试 $result_str..." 1 bash -c "source \"$SHELL_PROFILE\" &>/dev/null && gradle --version" &>/dev/null && HEALTH_CHECK_RESULTS+=("✔ $result_str: 可用 ($version_output)") || HEALTH_CHECK_RESULTS+=("✘ $result_str: 异常")
    fi
    if brew list --cask android-studio &>/dev/null; then
        if [[ -d "$ANDROID_SDK_PATH/platform-tools" ]]; then HEALTH_CHECK_RESULTS+=("✔ Android SDK: 目录存在 (请在 IDE 中完成具体版本安装)"); else HEALTH_CHECK_RESULTS+=("✘ Android SDK: 未找到 (请在 IDE 中完成安装)"); fi
    fi
    print_color "green" "✔ 健康检查完成。"
}

# 清理函数
cleanup() {
    print_color "cyan" "\n执行中: 执行清理任务..."
    run_with_spinner "正在清理 Homebrew 下载缓存..." 1 brew cleanup -s
    log "Cleanup done."
}

# 重载 Shell
reload_shell() {
    log "Prompting to reload shell."; print_color "yellow" "\n所有配置已写入 $SHELL_PROFILE。"
    read -p "是否要立即重载 Shell 以应用所有更改? (Y/n) " choice
    if [[ ! "$choice" =~ ^[nN]$ ]]; then
        log "Reloading shell..."; print_color "green" "正在重载 Shell..."; exec "$SHELL" -l
    else
        log "User skipped shell reload."; print_color "yellow" "请手动运行 'source $SHELL_PROFILE' 或重启终端以应用更改。"
    fi
}


# --- 主程序入口 ---
main() {
    setup_logging; log "======== Script Start v$SCRIPT_VERSION ========"
    print_color "yellow" "======== 欢迎使用 macOS 配置脚本 v$SCRIPT_VERSION ========"
    if [ "$(uname)" != "Darwin" ]; then log "Error: Not macOS."; print_color "red" "此脚本仅为 macOS 设计。"; exit 1; fi

    preflight_check
    check_disk_space
    
    if ! load_from_config_if_exists; then
        configure_custom_paths
        detect_shell
        select_homebrew_source
        handle_brewfile_selection
        collect_packages_interactively
    fi

    if ! command -v brew &>/dev/null; then
        print_color "yellow" "\n开始安装 Homebrew..."
        if [ "$USE_CHINA_MIRROR" = true ]; then
            export HOMEBREW_BREW_GIT_REMOTE="https://mirrors.ustc.edu.cn/brew.git"
            export HOMEBREW_CORE_GIT_REMOTE="https://mirrors.ustc.edu.cn/homebrew-core.git"
            export HOMEBREW_BOTTLE_DOMAIN="https://mirrors.ustc.edu.cn/homebrew-bottles"
        fi
        local brew_install_cmd="NONINTERACTIVE=1 /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        run_with_spinner "正在安装 Homebrew..." "$MAX_RETRIES" "bash" "-c" "$brew_install_cmd" || { print_color "red" "✘ Homebrew 安装失败，脚本无法继续。"; exit 1; }
        if [ -x "/opt/homebrew/bin/brew" ]; then eval "$(/opt/homebrew/bin/brew shellenv)"; fi
    fi

    if [[ ! -v "config_loaded" ]]; then collect_custom_packages; fi

    ALL_SELECTED_PACKAGES=($(echo "${FORMULAS_TO_INSTALL[@]} ${CASKS_TO_INSTALL[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
    log "Displaying final plan."; print_color "green" "\n==================== 最终执行计划 ===================="
    if [ "$USE_CHINA_MIRROR" = true ]; then echo "  - Homebrew 源: 国内镜像"; else echo "  - Homebrew 源: 官方源"; fi
    if [ ${#ALL_SELECTED_PACKAGES[@]} -eq 0 ]; then log "No packages selected."; print_color "yellow" "未选择任何软件。即将退出。"; exit 0; fi
    if [ ${#FORMULAS_TO_INSTALL[@]} -gt 0 ]; then print_color "cyan" "  - 待安装命令行工具:"; printf "    - %s\n" "${FORMULAS_TO_INSTALL[@]}"; fi
    if [ ${#CASKS_TO_INSTALL[@]} -gt 0 ]; then print_color "cyan" "  - 待安装图形化应用:"; printf "    - %s\n" "${CASKS_TO_INSTALL[@]}"; fi
    print_color "green" "======================================================"
    
    local choice; print_color "yellow" "\n请选择操作:"; select opt in "直接执行" "导出配置并执行" "退出"; do choice=$opt; break; done
    case "$choice" in
        "导出配置并执行") export_configuration ;;
        "退出") log "User cancelled."; print_color "yellow" "操作已取消。"; exit 0 ;;
        *) ;;
    esac

    log "Starting execution."; print_color "yellow" "\n🚀 开始执行安装..."
    run_with_spinner "正在更新 Homebrew..." "$MAX_RETRIES" "brew" "update"
    filter_already_installed
    
    local total_packages=$(( ${#FORMULAS_TO_INSTALL[@]} + ${#CASKS_TO_INSTALL[@]} )); local current_package=0
    for pkg in "${FORMULAS_TO_INSTALL[@]}"; do
        ((current_package++)); run_with_spinner "($current_package/$total_packages) 正在安装 $pkg" "$MAX_RETRIES" "brew" "install" "$pkg" && PACKAGES_SUCCESS+=("$pkg") || PACKAGES_FAILURE+=("$pkg")
    done
    for pkg in "${CASKS_TO_INSTALL[@]}"; do
        ((current_package++)); run_with_spinner "($current_package/$total_packages) 正在安装 $pkg" "$MAX_RETRIES" "brew" "install" "--cask" "$pkg" && PACKAGES_SUCCESS+=("$pkg") || PACKAGES_FAILURE+=("$pkg")
    done

    if [ ${#PACKAGES_FAILURE[@]} -gt 0 ]; then
        print_color "yellow" "\n发现 ${#PACKAGES_FAILURE[@]} 个软件包安装失败。"; read -p "是否立即重试? (y/N) " retry_choice
        if [[ "$retry_choice" =~ ^[yY]$ ]]; then
            local failed_packages=("${PACKAGES_FAILURE[@]}"); PACKAGES_FAILURE=()
            for pkg in "${failed_packages[@]}"; do
                if brew info --cask "$pkg" &>/dev/null; then run_with_spinner "[重试] 安装 $pkg" "$MAX_RETRIES" "brew" "install" "--cask" "$pkg" && PACKAGES_SUCCESS+=("$pkg") || PACKAGES_FAILURE+=("$pkg");
                else run_with_spinner "[重试] 安装 $pkg" "$MAX_RETRIES" "brew" "install" "$pkg" && PACKAGES_SUCCESS+=("$pkg") || PACKAGES_FAILURE+=("$pkg"); fi
            done
        fi
    fi

    log "Configuring environment variables."; print_color "cyan" "\n执行中: 配置环境变量..."
    detect_shell
    if command -v brew >/dev/null; then
        if [ -n "$SELECTED_JDK_PACKAGE_NAME" ]; then add_to_profile "# Java"; add_to_profile "export JAVA_HOME=\"$(brew --prefix "$SELECTED_JDK_PACKAGE_NAME")\""; add_path "$(brew --prefix "$SELECTED_JDK_PACKAGE_NAME")/bin"; fi
        if brew list --cask android-studio &>/dev/null; then add_to_profile "# Android SDK"; add_to_profile "export ANDROID_HOME=\"$ANDROID_SDK_PATH\""; add_path "$ANDROID_SDK_PATH/platform-tools"; add_path "$ANDROID_SDK_PATH/tools"; fi
        if brew list gradle &>/dev/null; then add_to_profile "# Gradle"; add_to_profile "export GRADLE_USER_HOME=\"$GRADLE_HOME_PATH\""; fi
        if brew list fvm &>/dev/null; then add_to_profile "# FVM"; add_to_profile "export FVM_HOME=\"$FVM_HOME_PATH\""; add_path "$FVM_HOME_PATH/bin"; add_to_profile "alias flutter='fvm flutter'"; fi
        if [ -x "/opt/homebrew/bin/brew" ]; then add_to_profile "# Homebrew"; add_to_profile 'eval "$(/opt/homebrew/bin/brew shellenv)"'; fi
    fi

    cleanup
    run_health_check

    log "Displaying summary."; print_color "yellow" "\n==================== 安装总结报告 ===================="
    if [ ${#PACKAGES_SUCCESS[@]} -gt 0 ]; then print_color "green" "✔ 成功/已存在:"; for pkg in "${PACKAGES_SUCCESS[@]}"; do echo "  - $pkg"; done; fi
    if [ ${#PACKAGES_FAILURE[@]} -gt 0 ]; then print_color "red" "✘ 安装失败:"; for pkg in "${PACKAGES_FAILURE[@]}"; do echo "  - $pkg"; done; fi
    if [ ${#HEALTH_CHECK_RESULTS[@]} -gt 0 ]; then print_color "cyan" "\n--- 健康检查结果 ---"; for result in "${HEALTH_CHECK_RESULTS[@]}"; do if [[ $result == ✔* ]]; then print_color "green" "  $result"; else print_color "red" "  $result"; fi; done; fi
    print_color "yellow" "======================================================"

    log "Script finished."; print_color "green" "\n==================== 🎉 全部流程已完成! 🎉 ===================="
    reload_shell
}

main
