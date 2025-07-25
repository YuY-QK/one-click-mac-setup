[English](https://github.com/YuY-QK/one-click-mac-setup/blob/main/README_EN.md) | **中文**

# **🚀 macOS 开发环境一键配置脚手架**

一款交互式、高可靠性的 macOS 开发环境一键配置脚手架脚本。旨在通过一行命令，全自动或半自动地完成新 Mac 的所有软件安装、环境配置和健康检查，极大提升您的工作效率。

## **✨ 主要特性**

* **一键远程执行**: 无需下载脚本，通过一行 curl 命令即可在任何新 Mac 上启动。  
* **交互式菜单**: 告别修改代码，通过彩色的交互式菜单引导您完成所有选择。  
* **智能配置加载**: 可将您的选择导出为配置文件，在下次运行时一键加载，实现“配置复刻”。  
* **高度可定制**: 您可以轻松地自定义 SDK 的安装路径，并自由选择 JDK 版本。  
* **健壮可靠**:  
  * **自动重试**: 内置网络失败重试机制，提高在不稳定网络下的安装成功率。  
  * **幂等性设计**: 多次运行脚本不会产生错误或重复安装。  
  * **日志记录**: 所有操作均有详细日志，便于排错。  
* **自动化体验**:  
  * **安装后体检**: 自动测试核心组件（Java, Git, Flutter等）是否可用。  
  * **自动生效**: 自动重载 Shell 配置，无需手动执行 source 命令。

## **🚀 快速开始**

在您全新的 Mac 上打开终端，执行以下命令即可启动配置向导：

```
bash \-c "$(curl \-fsSL https://raw.githubusercontent.com/YuY-QK/one-click-mac-setup/main/setup.sh)"
```

**注意**: 上述命令已配置为您的仓库地址。

## **🔧 高级用法：一键复刻配置**

当您在一台电脑上完成配置并导出后，会得到 config\_export.sh 和 Brewfile\_export 两个文件。

在另一台新电脑上，只需将**主脚本 (**setup.sh**)** 和这两个**配置文件**放在同一个目录下，然后运行主脚本：

```
./setup.sh
```

脚本会自动检测到配置文件，并询问您是否加载。确认后，它将跳过所有选择步骤，直接为您安装和配置一个完全相同的环境。

## **🛠️ 自定义**

如果您想添加或修改内置的软件列表，非常简单！只需编辑脚本顶部的 **`--- 软件列表定义 ---`** 部分即可。

这些列表都是普通的 Bash 数组，格式为 `"包名:描述"`。

例如，要向“常用沟通工具”类别中添加 **飞书(Lark)**，您只需找到 `COMMUNICATION_CASKS` 这一行，并像下面这样添加指定包名即可：

```bash
# 修改前
declare -r -a COMMUNICATION_CASKS=("wechat:微信" "qq:QQ" "telegram-desktop:Telegram" "discord:游戏与社区语音聊天" "slack:团队协作与沟通平台")

# 修改后
declare -r -a COMMUNICATION_CASKS=("wechat:微信" "qq:QQ" "telegram-desktop:Telegram" "discord:游戏与社区语音聊天" "slack:团队协作与沟通平台" "lark:飞书 (Lark)")
```

## **📄 许可证**

本项目采用 [MIT](https://opensource.org/licenses/MIT) 许可证。
