#!/bin/bash

#================================================================
# SYNOPSIS (概要)
#   macOS 开发环境一键配置脚本 (v3.6 终极完善版)
#
# DESCRIPTION (描述)
#   此脚本专为 macOS 设计，采用“配置先行”模式，通过交互式菜单收集您的所有需求，
#   然后生成一份执行计划供您确认并导出。最后全自动地完成 Homebrew 的安装、软件配置、
#   环境变量设置、安装后健康检查和自动重载 Shell，旨在提供极致、可靠的新 Mac
#   初始化体验。
#
# NOTES (注意事项)
#   作者: Gemini & User
#   版本: 3.6
#
#   使用方法:
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

# --- 全局配置变量 ---
SHELL_PROFILE=""
USE_CHINA_MIRROR=false
ANDROID_SDK_PATH="$HOME/Library/Android/sdk"
GRADLE_HOME_PATH="$HOME/.gradle"
FVM_HOME_PATH="$HOME/.fvm"
SELECTED_JDK_PACKAGE_NAME="" 
LOG_FILE="" 

declare -a FORMULAS_TO_INSTALL
declare -a CASKS_TO_INSTALL
declare -a ALL_SELECTED_PACKAGES # (新) 所有用户意图安装的包，用于最终判断
declare -a PACKAGES_SUCCESS
declare -a PACKAGES_FAILURE

# --- 辅助函数 ---

# 打印带颜色的文本
print_color() {
    local COLOR=$1; local TEXT=$2
    case $COLOR in
        "green") echo -e "\033[0;32m${TEXT}\033[0m" ;; "yellow") echo -e "\033[0;33m${TEXT}\033[0m" ;;
        "cyan") echo -e "\033[0;36m${TEXT}\033[0m" ;; "red") echo -e "\033[0;31m${TEXT}\033[0m" ;;
        "magenta") echo -e "\033[0;35m${TEXT}\033[0m" ;; "blue") echo -e "\033[0;34m${TEXT}\033[0m" ;;
        *) echo "$TEXT" ;;
    esac
}

# 日志记录函数
log() {
    local message="$1"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $message" >> "$LOG_FILE"
}

# 设置日志文件
setup_logging() {
    local SCRIPT_DIR; SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
    LOG_FILE="$SCRIPT_DIR/mac软件安装-$(date +%Y-%m-%d).log"
    if [ ! -f "$LOG_FILE" ]; then touch "$LOG_FILE"; fi
    echo -e "\n\n==================== New Run at $(date +'%Y-%m-%d %H:%M:%S') ====================" >> "$LOG_FILE"
    log "macOS Setup Script Log Initialized."
    print_color "green" "✔ 日志文件位于脚本目录: $LOG_FILE"
}

# 带有加载动画和重试机制的命令执行器
run_with_spinner() {
    local title="$1"; local retries="$2"; shift 2; local cmd="$@"; local cmd_log_file="/tmp/setup_script_cmd.log"; local spinner_chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"; local exit_code=1
    for ((i=1; i<=retries; i++)); do
        log "Executing (Attempt $i/$retries): $title"; eval "$cmd" > "$cmd_log_file" 2>&1 &
        local pid=$!; echo -n "$(print_color 'cyan' "[  ] $title")"
        while ps -p $pid > /dev/null; do
            for (( j=0; j<${#spinner_chars}; j++ )); do echo -ne "\r$(print_color 'cyan' "[${spinner_chars:$j:1}] $title (尝试 $i/$retries)")"; sleep 0.1; done
        done
        wait $pid; exit_code=$?
        if [ $exit_code -eq 0 ]; then echo -e "\r$(print_color 'green' "[✔] $title")"; log "SUCCESS: $title"; break; fi
        log "FAILURE (Attempt $i/$retries): $title (Exit Code: $exit_code)"; if [ $i -lt $retries ]; then print_color "yellow" "\n操作失败, 正在准备重试 ($((i+1))/$retries)..."; sleep 3; fi
    done
    if [ $exit_code -ne 0 ]; then
        echo -e "\r$(print_color 'red' "[✘] $title (多次尝试后失败, 详情请查看 $LOG_FILE)")"; log "Command output from last attempt:"; cat "$cmd_log_file" >> "$LOG_FILE"
    fi; rm -f "$cmd_log_file"; return $exit_code
}

# 将环境变量配置写入 Shell 配置文件
add_to_profile() {
    local LINE_TO_ADD=$1
    if ! grep -qF -- "$LINE_TO_ADD" "$SHELL_PROFILE"; then
        log "Writing to $SHELL_PROFILE: $LINE_TO_ADD"
        print_color "cyan" "  ↳ 正在写入: $LINE_TO_ADD"
        if [[ "$LINE_TO_ADD" == \#* ]]; then echo -e "\n$LINE_TO_ADD" >> "$SHELL_PROFILE"; else echo "$LINE_TO_ADD" >> "$SHELL_PROFILE"; fi
    fi
}

# 确认继续操作
confirm_continue() {
    local prompt_message="$1"; read -p "$prompt_message" choice
    case "$choice" in
        s|S) export_configuration; return 0 ;;
        q|Q) return 1 ;;
        *) return 0 ;;
    esac
}

# --- 核心功能函数 ---

# 飞行前检查：确保核心依赖存在
preflight_check() {
    log "Performing preflight check for Xcode Command Line Tools."; print_color "yellow" "执行飞行前检查: 正在检查核心依赖 Xcode Command Line Tools..."
    if ! xcode-select -p &> /dev/null; then
        log "Xcode Command Line Tools not found. Prompting user to install."; print_color "red" "核心依赖缺失！"
        print_color "yellow" "正在启动 Xcode Command Line Tools 安装程序..."; xcode-select --install
        print_color "red" "安装完成后，请按任意键退出并重新运行脚本。"; read -n 1 -s; exit 1
    fi; log "Xcode Command Line Tools found."; print_color "green" "✔ 核心依赖已满足。"
}

# JDK 版本选择器
select_jdk_version() {
    log "Prompting for JDK version selection."; print_color "yellow" "\n请选择您想安装的 JDK 版本:"
    local jdk_options=( "OpenJDK 11 (LTS)" "OpenJDK 17 (LTS) (推荐)" "OpenJDK 21 (LTS)" "OpenJDK (最新稳定版)" "手动输入其他 Homebrew 版本" "返回上一级" )
    while true; do
        select opt in "${jdk_options[@]}"; do
            case $opt in
                "OpenJDK 11 (LTS)") SELECTED_JDK_PACKAGE_NAME="openjdk@11"; break;;
                "OpenJDK 17 (LTS) (推荐)") SELECTED_JDK_PACKAGE_NAME="openjdk@17"; break;;
                "OpenJDK 21 (LTS)") SELECTED_JDK_PACKAGE_NAME="openjdk@21"; break;;
                "OpenJDK (最新稳定版)") SELECTED_JDK_PACKAGE_NAME="openjdk"; break;;
                "手动输入其他 Homebrew 版本") read -p "请输入完整的 Homebrew 包名 (如: openjdk@18): " custom_jdk; if [ -n "$custom_jdk" ]; then SELECTED_JDK_PACKAGE_NAME="$custom_jdk"; fi; break;;
                "返回上一级") break;;
                *) print_color "red" "无效选项 '$REPLY'，请重新输入。";;
            esac
        done; break
    done
    if [ -n "$SELECTED_JDK_PACKAGE_NAME" ]; then FORMULAS_TO_INSTALL+=($SELECTED_JDK_PACKAGE_NAME); log "User selected JDK: $SELECTED_JDK_PACKAGE_NAME"; print_color "green" "已选择 JDK: $SELECTED_JDK_PACKAGE_NAME"; fi
}

# 配置自定义路径
configure_custom_paths() {
    log "Prompting for custom SDK paths."; print_color "cyan" "\n第零步: 配置 SDK 存放路径..."
    read -p "您是否要自定义 SDK 存放路径? (y/N) " choice
    if [[ ! "$choice" =~ ^[yY]$ ]]; then log "User chose default paths."; print_color "green" "将使用默认路径。"; return; fi
    log "User chose to customize paths."
    read -p "请输入新的 Android SDK 路径 (当前: $ANDROID_SDK_PATH): " new_path; if [ -n "$new_path" ]; then ANDROID_SDK_PATH=$(eval echo "$new_path"); fi
    read -p "请输入新的 Gradle Home 路径 (当前: $GRADLE_HOME_PATH): " new_path; if [ -n "$new_path" ]; then GRADLE_HOME_PATH=$(eval echo "$new_path"); fi
    read -p "请输入新的 FVM Home 路径 (当前: $FVM_HOME_PATH): " new_path; if [ -n "$new_path" ]; then FVM_HOME_PATH=$(eval echo "$new_path"); fi
    log "Custom paths configured: ANDROID_SDK_PATH=$ANDROID_SDK_PATH, GRADLE_HOME_PATH=$GRADLE_HOME_PATH, FVM_HOME_PATH=$FVM_HOME_PATH"; print_color "green" "路径配置完成！"
}

# 检测 Shell
detect_shell() {
    log "Detecting user shell."; print_color "cyan" "\n第一步: 检测您的 Shell 环境..."
    if [ -n "$ZSH_VERSION" ] || [ -f "$HOME/.zshrc" ]; then SHELL_PROFILE="$HOME/.zshrc"; else SHELL_PROFILE="$HOME/.bash_profile"; fi
    log "Shell profile set to: $SHELL_PROFILE"; print_color "green" "检测到将使用 $SHELL_PROFILE 文件进行配置。"; sleep 1
}

# 选择 Homebrew 安装源
select_homebrew_source() {
    log "Prompting for Homebrew source."; print_color "cyan" "\n第二步: 选择 Homebrew 安装源..."
    run_with_spinner "正在检测访问 GitHub 官方源..." 1 "curl -s --connect-timeout 5 https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh > /dev/null"
    if [ $? -eq 0 ]; then
        read -p "您可以流畅访问官方源, 是否依然要使用速度更快的国内镜像源? (y/N) " choice
        case "$choice" in y|Y ) USE_CHINA_MIRROR=true;; * ) USE_CHINA_MIRROR=false;; esac
    else
        read -p "访问官方源超时! 强烈建议您使用国内镜像源进行安装, 是否同意? (Y/n) " choice
        case "$choice" in n|N ) USE_CHINA_MIRROR=false;; * ) USE_CHINA_MIRROR=true;; esac
    fi
    log "Homebrew mirror selection: USE_CHINA_MIRROR=$USE_CHINA_MIRROR"
}

# 处理 Brewfile 文件
handle_brewfile_selection() {
    log "Checking for Brewfile."; print_color "cyan" "\n第三步: 检查外部 Brewfile 文件..."
    if [ -f "Brewfile" ]; then
        log "Brewfile found."; print_color "green" "检测到 Brewfile 文件！"
        local brewfile_formulas=($(grep "^brew " Brewfile | sed -e "s/brew '//g" -e "s/'//g")); local brewfile_casks=($(grep "^cask " Brewfile | sed -e "s/cask '//g" -e "s/'//g"))
        read -p "请选择如何处理此文件: [A]全部安装, [S]手动选择, [I]忽略此文件 (A/s/i): " choice
        case "$choice" in
            s|S)
                log "User chose to selectively install from Brewfile."
                local selected_formulas=($(prompt_for_package_selection "请选择要从 Brewfile 安装的命令行工具:" "${brewfile_formulas[@]}")); FORMULAS_TO_INSTALL+=(${selected_formulas[@]})
                local selected_casks=($(prompt_for_package_selection "请选择要从 Brewfile 安装的图形化应用:" "${brewfile_casks[@]}")); CASKS_TO_INSTALL+=(${selected_casks[@]})
                ;;
            i|I) log "User chose to ignore Brewfile."; print_color "yellow" "已忽略 Brewfile。";;
            *) log "User chose to install all from Brewfile."; FORMULAS_TO_INSTALL+=(${brewfile_formulas[@]}); CASKS_TO_INSTALL+=(${brewfile_casks[@]});;
        esac
    else
        log "Brewfile not found."; print_color "yellow" "未在当前目录找到 Brewfile, 跳过。"
    fi
}

# 交互式收集要安装的软件包
collect_packages_interactively() {
    log "Starting interactive package selection."; print_color "cyan" "\n第四步: 从内置列表中选择您想安装的软件..."
    local dev_tools_formulas=("git" "node" "java" "flutter" "fvm" "gradle"); local dev_tools_casks=("visual-studio-code" "android-studio" "docker" "sublime-text" "jetbrains-toolbox")
    local browsers=("google-chrome" "firefox" "microsoft-edge-dev" "arc"); local communication_casks=("wechat" "qq" "telegram-desktop" "discord" "slack")
    local office_design_casks=("wps-office" "figma" "obsidian"); local utils=("iterm2" "rectangle" "stats" "the-unarchiver" "raycast")
    declare -A categories; categories["选择 [基础开发工具] (命令行)"]='dev_tools_formulas:formula:cyan'; categories["选择 [图形化开发应用]"]='dev_tools_casks:cask:blue'
    categories["选择 [常用浏览器]"]='browsers:cask:magenta'; categories["选择 [常用沟通工具]"]='communication_casks:cask:cyan'; categories["选择 [设计与办公]"]='office_design_casks:cask:blue'
    categories["选择 [系统实用工具]"]='utils:cask:magenta'; categories["完成选择, 查看执行计划"]='done:done:red'; local options_keys=("${!categories[@]}")
    while true; do
        print_color "yellow" "\n请选择一个类别 (选择后可勾选具体软件):"; for i in "${!options_keys[@]}"; do local key="${options_keys[$i]}"; local color=$(echo "${categories[$key]}" | cut -d: -f3); print_color "$color" "  [$((i+1))] $key"; done
        local choice; while true; do read -p "请输入选项编号: " choice; if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#options_keys[@]}" ]; then break; else print_color "red" "无效输入，请输入列表中的有效数字 (1-${#options_keys[@]})。"; fi; done
        local selected_key="${options_keys[$((choice-1))]}"; local selected_value="${categories[$selected_key]}"; local package_list_name=$(echo "$selected_value" | cut -d: -f1); local package_type=$(echo "$selected_value" | cut -d: -f2)
        log "User selected category: $selected_key"; if [ "$package_type" == "done" ]; then
            FORMULAS_TO_INSTALL=($(echo "${FORMULAS_TO_INSTALL[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' ')); CASKS_TO_INSTALL=($(echo "${CASKS_TO_INSTALL[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' ')); break
        fi
        local -n package_list_ref=$package_list_name; local selected=($(prompt_for_package_selection "请选择要安装的 $(echo $selected_key | sed -e 's/选择 \[//' -e 's/\]//'):" "${package_list_ref[@]}"))
        if [[ " ${selected[*]} " =~ " java " ]]; then selected=("${selected[@]/java/}"); select_jdk_version; fi
        if [ "$package_type" == "formula" ]; then FORMULAS_TO_INSTALL+=(${selected[@]}); else CASKS_TO_INSTALL+=(${selected[@]}); fi
    done
}

# 提示用户从列表中选择指定的软件包 (子函数)
prompt_for_package_selection() {
    local title="$1"; shift; local packages_available=("$@"); local selected_packages=()
    if [ ${#packages_available[@]} -eq 0 ]; then return; fi
    print_color "yellow" "\n$title"; for i in "${!packages_available[@]}"; do echo "  [$((i+1))] ${packages_available[$i]}"; done
    local choices; while true; do read -p "请输入您想安装的软件编号 (可多选, 用空格隔开, 或直接回车跳过): " -a choices; if [ ${#choices[@]} -eq 0 ]; then break; fi
        local all_valid=true; for item in "${choices[@]}"; do if ! [[ "$item" =~ ^[0-9]+$ ]] || [ "$item" -lt 1 ] || [ "$item" -gt ${#packages_available[@]} ]; then print_color "red" "输入错误: '$item' 不是一个有效的选项编号。请重新输入。"; all_valid=false; break; fi; done
        if [ "$all_valid" = true ]; then break; fi
    done
    for choice in "${choices[@]}"; do selected_packages+=("${packages_available[$((choice-1))]}")
    done; log "User selected packages: ${selected_packages[*]}"; echo "${selected_packages[@]}"
}

# 导出配置
export_configuration() {
    log "Prompting for export format."; print_color "yellow" "\n请选择您想导出的格式:"
    local export_options=("Shell 脚本 (推荐, 便于复用)" "YAML (.yml)" ".env (键值对)"); select opt in "${export_options[@]}"; do
        case $opt in
            "Shell 脚本 (推荐, 便于复用)") export_to_shell; break;;
            "YAML (.yml)") export_to_yaml; break;;
            ".env (键值对)") export_to_dotenv; break;;
            *) print_color "red" "无效选项 $REPLY";;
        esac
    done
}
export_to_shell() {
    local SCRIPT_DIR; SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"; local config_file="$SCRIPT_DIR/config_export.sh"; local brewfile_export="$SCRIPT_DIR/Brewfile_export"
    log "Exporting configuration to Shell script."; print_color "cyan" "正在导出为 Shell 脚本..."
    { echo "#!/bin/bash"; echo "# Dev-Setup-Script Exported Config"; echo "USE_CHINA_MIRROR=$USE_CHINA_MIRROR"; echo "ANDROID_SDK_PATH='$ANDROID_SDK_PATH'"; echo "GRADLE_HOME_PATH='$GRADLE_HOME_PATH'"; echo "FVM_HOME_PATH='$FVM_HOME_PATH'"; } > "$config_file"
    { echo "# Exported Brewfile on $(date)"; for pkg in "${ALL_SELECTED_PACKAGES[@]}"; do if brew list --formula -1 | grep -q "^${pkg}$"; then echo "brew '$pkg'"; fi; done; for pkg in "${ALL_SELECTED_PACKAGES[@]}"; do if brew list --cask -1 | grep -q "^${pkg}$"; then echo "cask '$pkg'"; fi; done } > "$brewfile_export"
    print_color "green" "✔ 配置已成功导出到以下文件:"; echo "  - 变量配置: $config_file"; echo "  - 软件列表: $brewfile_export"
}
export_to_yaml() {
    local SCRIPT_DIR; SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"; local yml_file="$SCRIPT_DIR/config_export.yml"
    log "Exporting configuration to YAML."; print_color "cyan" "正在导出为 YAML..."
    { echo "# Dev-Setup-Script Exported Config"; echo "settings:"; echo "  use_china_mirror: $USE_CHINA_MIRROR"; echo "paths:"; echo "  android_sdk: \"$ANDROID_SDK_PATH\""; echo "  gradle_home: \"$GRADLE_HOME_PATH\""; echo "  fvm_home: \"$FVM_HOME_PATH\""; echo "packages:"; echo "  formulas:"; for pkg in "${ALL_SELECTED_PACKAGES[@]}"; do if brew list --formula -1 | grep -q "^${pkg}$"; then echo "    - $pkg"; fi; done; echo "  casks:"; for pkg in "${ALL_SELECTED_PACKAGES[@]}"; do if brew list --cask -1 | grep -q "^${pkg}$"; then echo "    - $pkg"; fi; done; } > "$yml_file"
    print_color "green" "✔ 配置已成功导出到: $yml_file"
}
export_to_dotenv() {
    local SCRIPT_DIR; SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"; local env_file="$SCRIPT_DIR/config_export.env"
    log "Exporting configuration to .env."; print_color "cyan" "正在导出为 .env..."
    { echo "# Dev-Setup-Script Exported Config"; echo "USE_CHINA_MIRROR=$USE_CHINA_MIRROR"; echo "ANDROID_SDK_PATH=\"$ANDROID_SDK_PATH\""; echo "GRADLE_HOME_PATH=\"$GRADLE_HOME_PATH\""; echo "FVM_HOME_PATH=\"$FVM_HOME_PATH\""; local formulas_str=""; local casks_str=""; for pkg in "${ALL_SELECTED_PACKAGES[@]}"; do if brew list --formula -1 | grep -q "^${pkg}$"; then formulas_str+=" $pkg"; fi; done; for pkg in "${ALL_SELECTED_PACKAGES[@]}"; do if brew list --cask -1 | grep -q "^${pkg}$"; then casks_str+=" $pkg"; fi; done; echo "FORMULAS=\"${formulas_str# }\""; echo "CASKS=\"${casks_str# }\""; } > "$env_file"
    print_color "green" "✔ 配置已成功导出到: $env_file"
}

# 预检查并过滤已安装的包
filter_already_installed() {
    log "Filtering out already installed packages from the installation list."; print_color "cyan" "\n执行中: 正在预检查软件包安装状态..."
    local -a final_formulas=(); for pkg in "${FORMULAS_TO_INSTALL[@]}"; do if brew list --formula | grep -q "^${pkg}$"; then print_color "yellow" "  - [已安装] $pkg (跳过)"; log "Skipping already installed formula: $pkg"; PACKAGES_SUCCESS+=("$pkg (已存在)"); else final_formulas+=("$pkg"); fi; done; FORMULAS_TO_INSTALL=("${final_formulas[@]}")
    local -a final_casks=(); for pkg in "${CASKS_TO_INSTALL[@]}"; do if brew list --cask | grep -q "^${pkg}$"; then print_color "yellow" "  - [已安装] $pkg (跳过)"; log "Skipping already installed cask: $pkg"; PACKAGES_SUCCESS+=("$pkg (已存在)"); else final_casks+=("$pkg"); fi; done; CASKS_TO_INSTALL=("${final_casks[@]}")
}

# 安装后健康检查
run_health_check() {
    log "Running post-install health checks."; print_color "yellow" "\n执行中: 正在进行安装后健康检查..."
    source "$SHELL_PROFILE"

    if [[ " ${ALL_SELECTED_PACKAGES[*]} " =~ " git " ]]; then run_with_spinner "正在测试 Git..." 1 "git --version"; fi
    if [ -n "$SELECTED_JDK_PACKAGE_NAME" ]; then run_with_spinner "正在测试 Java..." 1 "java -version"; fi
    if [[ " ${ALL_SELECTED_PACKAGES[*]} " =~ " fvm " ]]; then run_with_spinner "正在测试 FVM..." 1 "fvm --version"; run_with_spinner "正在测试 Flutter (via fvm)..." 1 "fvm flutter --version"
    elif [[ " ${ALL_SELECTED_PACKAGES[*]} " =~ " flutter " ]]; then run_with_spinner "正在测试 Flutter..." 1 "flutter --version"; fi
    if [[ " ${ALL_SELECTED_PACKAGES[*]} " =~ " gradle " ]]; then run_with_spinner "正在测试 Gradle..." 1 "gradle --version"; fi
    print_color "green" "✔ 健康检查完成。"
}


# 自动重载 Shell
reload_shell() {
    log "Prompting to reload shell."; print_color "yellow" "\n所有配置已写入 $SHELL_PROFILE。"
    read -p "是否要立即重载 Shell 以应用所有更改? (Y/n) " choice
    if [[ ! "$choice" =~ ^[nN]$ ]]; then
        log "User chose to reload shell. Executing 'exec $SHELL -l'."; print_color "green" "正在重载 Shell..."; exec "$SHELL" -l
    else
        log "User chose not to reload shell."; print_color "yellow" "请手动运行 'source $SHELL_PROFILE' 或重启终端以应用更改。"
    fi
}

# 加载导出的配置
load_from_config_if_exists() {
    local config_file="config_export.sh"; local brewfile_export="Brewfile_export"
    if [ -f "$config_file" ] && [ -f "$brewfile_export" ]; then
        print_color "green" "✔ 发现导出的配置文件！"
        read -p "是否要加载此配置并跳过所有手动选择? (Y/n) " choice
        if [[ ! "$choice" =~ ^[nN]$ ]]; then
            log "Loading configuration from exported files."; print_color "cyan" "正在加载配置..."
            source "./$config_file"
            FORMULAS_TO_INSTALL=($(grep "^brew " "$brewfile_export" | sed -e "s/brew '//g" -e "s/'//g"))
            CASKS_TO_INSTALL=($(grep "^cask " "$brewfile_export" | sed -e "s/cask '//g" -e "s/'//g"))
            for pkg in "${FORMULAS_TO_INSTALL[@]}"; do if [[ "$pkg" == openjdk* ]]; then SELECTED_JDK_PACKAGE_NAME="$pkg"; break; fi; done
            return 0 # Success
        fi
    fi
    return 1 # No config loaded
}

# --- 主程序入口 ---

main() {
    setup_logging; log "======== 脚本开始执行 v3.6 ========"
    print_color "yellow" "======== 欢迎使用开发环境一键配置脚本 v3.6 ========"
    if [ "$(uname)" != "Darwin" ]; then log "错误: 此脚本仅为 macOS 设计。"; print_color "red" "此脚本目前仅为 macOS 设计。正在退出。"; exit 1; fi

    preflight_check
    
    if ! load_from_config_if_exists; then
        configure_custom_paths
        detect_shell
        select_homebrew_source
        handle_brewfile_selection
        collect_packages_interactively
    fi

    ALL_SELECTED_PACKAGES=("${FORMULAS_TO_INSTALL[@]}" "${CASKS_TO_INSTALL[@]}")
    log "Displaying final execution plan and export option."
    print_color "green" "\n==================== 最终执行计划 ===================="
    if [ "$USE_CHINA_MIRROR" = true ]; then echo "  - Homebrew 源: 国内镜像"; else echo "  - Homebrew 源: 官方源"; fi
    if [ ${#ALL_SELECTED_PACKAGES[@]} -eq 0 ]; then log "No packages to install. Exiting."; print_color "yellow" "您没有选择任何要安装的软件。脚本即将退出。"; exit 0; fi
    if [ ${#FORMULAS_TO_INSTALL[@]} -gt 0 ]; then print_color "cyan" "  - 待安装命令行工具:"; printf "    - %s\n" "${FORMULAS_TO_INSTALL[@]}"; fi
    if [ ${#CASKS_TO_INSTALL[@]} -gt 0 ]; then print_color "cyan" "  - 待安装图形化应用:"; printf "    - %s\n" "${CASKS_TO_INSTALL[@]}"; fi
    print_color "green" "======================================================"
    
    if ! confirm_continue "请选择操作: [E]直接执行, [S]导出配置并执行, [Q]退出 (E/s/q): "; then
        log "User cancelled execution."; print_color "yellow" "操作已取消。"; exit 0;
    fi

    log "Starting execution phase."; print_color "yellow" "\n🚀 开始执行安装..."
    run_with_spinner "正在准备 Homebrew 环境..." 3 "if ! command -v brew &>/dev/null; then if [ '$USE_CHINA_MIRROR' = true ]; then /bin/bash -c \"\$(curl -fsSL https://gitee.com/cunkai/HomebrewCN/raw/master/Homebrew.sh)\"; else /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"; fi; fi && brew update"
    
    filter_already_installed
    
    # (已优化) 逐一安装并记录结果
    for pkg in "${FORMULAS_TO_INSTALL[@]}"; do
        if run_with_spinner "正在安装 $pkg" 3 "brew install $pkg"; then PACKAGES_SUCCESS+=("$pkg"); else PACKAGES_FAILURE+=("$pkg"); fi
    done
    for pkg in "${CASKS_TO_INSTALL[@]}"; do
        if run_with_spinner "正在安装 $pkg" 3 "brew install --cask $pkg"; then PACKAGES_SUCCESS+=("$pkg"); else PACKAGES_FAILURE+=("$pkg"); fi
    done

    log "Configuring environment variables."; print_color "cyan" "\n执行中: 配置环境变量..."
    if [[ " ${ALL_SELECTED_PACKAGES[*]} " =~ " openjdk" ]] || brew list | grep -q "openjdk"; then
        if [ -z "$SELECTED_JDK_PACKAGE_NAME" ]; then SELECTED_JDK_PACKAGE_NAME=$(brew --prefix --installed openjdk); fi
        add_to_profile "# Java"; add_to_profile "export JAVA_HOME=$(brew --prefix $SELECTED_JDK_PACKAGE_NAME)"; add_to_profile 'export PATH="$JAVA_HOME/bin:$PATH"'
    fi
    
    if [[ " ${ALL_SELECTED_PACKAGES[*]} " =~ " android-studio " ]] || brew list --cask android-studio &>/dev/null; then
        add_to_profile "# Android SDK"; add_to_profile "export ANDROID_HOME=$ANDROID_SDK_PATH"; add_to_profile 'export PATH=$PATH:$ANDROID_HOME/platform-tools'; add_to_profile 'export PATH=$PATH:$ANDROID_HOME/tools'; add_to_profile 'export PATH=$PATH:$ANDROID_HOME/tools/bin'
    fi
    
    if [[ " ${ALL_SELECTED_PACKAGES[*]} " =~ " gradle " ]] || brew list gradle &>/dev/null; then
        add_to_profile "# Gradle"; add_to_profile "export GRADLE_USER_HOME=$GRADLE_HOME_PATH"
    fi

    if [[ " ${ALL_SELECTED_PACKAGES[*]} " =~ " fvm " ]] || brew list fvm &>/dev/null; then
        add_to_profile "# FVM (Flutter Version Management)"; add_to_profile "export FVM_HOME=$FVM_HOME_PATH"; add_to_profile 'export PATH="$FVM_HOME/bin:$PATH"'; add_to_profile "alias flutter='fvm flutter'"
    fi
    
    run_with_spinner "正在清理 Homebrew 缓存..." 1 "brew cleanup"

    run_health_check

    # (新) 最终总结报告
    log "Displaying final summary report."; print_color "yellow" "\n==================== 安装总结报告 ===================="
    if [ ${#PACKAGES_SUCCESS[@]} -gt 0 ]; then print_color "green" "✔ 成功/已存在的软件包:"; for pkg in "${PACKAGES_SUCCESS[@]}"; do echo "  - $pkg"; done; fi
    if [ ${#PACKAGES_FAILURE[@]} -gt 0 ]; then print_color "red" "✘ 安装失败的软件包:"; for pkg in "${PACKAGES_FAILURE[@]}"; do echo "  - $pkg"; done; fi
    print_color "yellow" "======================================================"

    log "脚本执行完毕"; print_color "green" "\n==================== 🎉 全部流程已完成! 🎉 ===================="
    reload_shell
}

# 启动主函数
main
