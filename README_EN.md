
**English** | [中文](http://docs.google.com/README.md)

# **🚀 macOS Development Environment One-Click Setup Script**

An interactive and highly reliable one-click setup script for macOS development environments. It's designed to fully or semi-automatically complete all software installation, environment configuration, and health checks on a new Mac with a single command, significantly boosting your productivity.

## **✨ Key Features**

* **One-Click Remote Execution**: No need to download any scripts. Start the setup wizard on any new Mac with a single curl command.  
* **Interactive Menus**: Forget about editing code. Colorful, interactive menus guide you through all the necessary selections.  
* **Smart Configuration Loading**: Export your choices to a configuration file and load it on your next run to "clone" your setup with one click.  
* **Highly Customizable**: Easily customize SDK installation paths and freely choose your preferred JDK version.  
* **Robust & Reliable**:  
  * **Auto-Retry**: A built-in mechanism to retry on network failures, increasing the success rate on unstable connections.  
  * **Idempotent Design**: Running the script multiple times won't cause errors or duplicate installations.  
  * **Detailed Logging**: All operations are logged for easy troubleshooting.  
* **Automated Experience**:  
  * **Post-install Health Check**: Automatically tests if core components (Java, Git, Flutter, etc.) are working correctly.  
  * **Auto-Sourcing**: Automatically reloads your shell configuration, so you don't have to manually run source.

## **🚀 Quick Start**

On your brand new Mac, open the Terminal and execute the following command to start the setup wizard:

bash \-c "$(curl \-fsSL https://raw.githubusercontent.com/YuY-QK/one-click-mac-setup/main/setup.sh)"

**Note**: The command above is already configured for your repository.

## **🔧 Advanced Usage: One-Click Setup Replication**

After completing the configuration on one machine and exporting it, you will get two files: config\_export.sh and Brewfile\_export.

On another new machine, simply place the **main script (setup.sh)** and these two **configuration files** in the same directory. Then, run the main script:

./setup.sh

The script will automatically detect the configuration files and ask if you want to load them. Upon confirmation, it will skip all selection steps and directly install and configure an identical environment for you.

## **🛠️ Customization**

If you wish to add or modify the built-in software lists, simply edit the collect\_packages\_interactively function within the main setup.sh script.

## **📄 License**

This project is licensed under the [MIT License](https://opensource.org/licenses/MIT).
