#!/bin/bash

# Arch Linux Setup Script
# This script configures an Arch-based Linux system after installation
# with modular functions and proper error handling.

set -e  # Exit on error
set -u  # Exit on undefined variable

#######################################
# Utility Functions
#######################################

# Validate yes/no user input
# Arguments:
#   $1 - The response to validate
# Returns:
#   0 if yes, 1 if no
validate_yes_no() {
    local response="$1"
    [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]
}

# Prompt user with a yes/no question
# Arguments:
#   $1 - The prompt message
# Returns:
#   0 if yes, 1 if no
prompt_yes_no() {
    local prompt="$1"
    local response
    read -r -p "$prompt [y/N] " response
    validate_yes_no "$response"
}

#######################################
# Main Setup Functions
#######################################

# Check if script is run as root and exit if true
check_root() {
    if [ "$(id -u)" = 0 ]; then
        echo "######################################################################"
        echo "This script should NOT be run as root user as it may create unexpected"
        echo " problems and you may have to reinstall Arch. So run this script as a"
        echo "  normal user. You will be asked for a sudo password when necessary"
        echo "######################################################################"
        exit 1
    fi
}

# Set user's full name
setup_user_info() {
    local fn
    read -r -p "Enter your Full Name: " fn
    if [ -n "$fn" ]; then
        sudo chfn -f "$fn" "$(whoami)"
    fi
}

# Configure pacman with custom settings
setup_pacman() {
    grep -qF "Include = /etc/pacman.d/custom" /etc/pacman.conf || \
        echo "Include = /etc/pacman.d/custom" | sudo tee -a /etc/pacman.conf > /dev/null
    echo -e "[options]\nColor\nParallelDownloads = 5\nILoveCandy\n" | sudo tee /etc/pacman.d/custom > /dev/null
}

# Update system and install base packages
update_system() {
    echo ""
    sudo pacman -Syu --needed --noconfirm --disable-download-timeout pacman-contrib
    
    # Install kernel headers if respective kernel is installed
    if pactree -r linux &>/dev/null; then
        sudo pacman -S --needed --noconfirm --disable-download-timeout linux-headers
    fi

    if pactree -r linux-zen &>/dev/null; then
        sudo pacman -S --needed --noconfirm --disable-download-timeout linux-zen-headers
    fi
}

# Install CPU-specific drivers
install_cpu_drivers() {
    local cpu_vendor
    cpu_vendor=$(lscpu | grep "Vendor ID" | awk '{print $3}')

    case "$cpu_vendor" in
        GenuineIntel)
            sudo pacman -S --needed --noconfirm --disable-download-timeout intel-media-driver vulkan-intel
            ;;
        AuthenticAMD)
            sudo pacman -S --needed --noconfirm --disable-download-timeout libva-mesa-driver vulkan-radeon
            ;;
        *)
            echo "Unknown CPU vendor: $cpu_vendor"
            ;;
    esac
}

# Install NVIDIA drivers if requested
install_nvidia_drivers() {
    echo ""
    if prompt_yes_no "Do you want to install NVIDIA open source drivers(Turing+)?"; then
        sudo pacman -S --needed --noconfirm --disable-download-timeout \
            nvidia-open-dkms nvidia-prime opencl-nvidia switcheroo-control
        echo "options nvidia NVreg_PreserveVideoMemoryAllocations=1 NVreg_UsePageAttributeTable=1" | \
            sudo tee /etc/modprobe.d/nvidia.conf > /dev/null
        sudo systemctl enable nvidia-persistenced switcheroo-control

        echo ""
        if prompt_yes_no "Do you want to enable NVIDIA's Dynamic Boost(Ampere+)?"; then
            sudo systemctl enable nvidia-powerd
        fi
    fi
}

# Setup swap space with hibernate support
setup_swap() {
    if [ -z "$(swapon --show)" ]; then
        echo ""
        if prompt_yes_no "Do you want to have swap space(swapfile with hibernate)?"; then
            local filesystem
            filesystem=$(df -T / | awk 'NR==2{print $2}')
            
            if [ "$filesystem" = "ext4" ]; then
                local ram_size swap_size
                ram_size=$(free --giga | awk 'NR==2{print $2}')
                swap_size=$((ram_size * 2))
                
                sudo mkswap -U clear --size "${swap_size}G" --file /swapfile
                sudo swapon /swapfile
                echo -e "[Swap]\nWhat=/swapfile\n\n[Install]\nWantedBy=swap.target" | \
                    sudo tee /etc/systemd/system/swapfile.swap > /dev/null
                sudo systemctl daemon-reload
                sudo systemctl enable swapfile.swap
                sudo sed -i '/^HOOKS=/ { /resume/ !s/filesystems/filesystems resume/ }' /etc/mkinitcpio.conf
                sudo mkinitcpio -P
            else
                echo "The filesystem type is not ext4. Skipping swap setup."
            fi
        fi
    fi
}

# Helper function to install packages from a file
# Arguments:
#   $1 - Path to file containing package list
install_packages_from_file() {
    local file="$1"
    # Validate file exists and is readable
    if [ ! -r "$file" ]; then
        echo "Error: Cannot read file '$file'" >&2
        return 1
    fi
    # Use command substitution to safely pass file contents to sudo
    xargs -a "$file" sudo pacman -S --needed --noconfirm --disable-download-timeout
}

# Install common packages and configure services
install_common_packages() {
    echo ""
    # Install packages from file
    install_packages_from_file common
    
    sudo sed -i '/^hosts: mymachines/ s/hosts: mymachines/hosts: mymachines mdns/' /etc/nsswitch.conf
    sudo systemctl disable systemd-resolved.service
    sudo systemctl enable avahi-daemon cups.socket power-profiles-daemon sshd ufw
    sudo systemctl start ufw
}

# Configure CUPS gutenprint hook
setup_cups_hook() {
    local gutenprint
    gutenprint="[Trigger]
Operation = Install
Operation = Upgrade
Operation = Remove
Type = Package
Target = gutenprint

[Action]
Depends = gutenprint
When = PostTransaction
Exec = /usr/bin/cups-genppdupdate"
    
    sudo mkdir -p /etc/pacman.d/hooks/
    echo "$gutenprint" | sudo tee /etc/pacman.d/hooks/gutenprint.hook > /dev/null
}

# Configure firewall and shell
configure_system() {
    sudo ufw enable
    sudo ufw allow IPP
    sudo ufw allow SSH
    sudo ufw allow Bonjour
    sudo cp /usr/share/doc/avahi/ssh.service /etc/avahi/services/
    sudo chsh -s /usr/bin/fish "$(whoami)"
    sudo chsh -s /usr/bin/fish
}

# Setup Samba if requested
setup_samba() {
    echo ""
    if prompt_yes_no "Do you want to setup Samba?"; then
        sudo pacman -S --needed --noconfirm --disable-download-timeout samba
        echo -e "[global]\nserver string = Samba Server\n" | sudo tee /etc/samba/smb.conf > /dev/null
        sudo smbpasswd -a "$(whoami)"
        sudo ufw allow CIFS
        echo -e "[Samba Share]\ncomment = Samba Share\npath = /home/$(whoami)/Samba Share\nread only = no" | \
            sudo tee -a /etc/samba/smb.conf > /dev/null
        rm -rf ~/Samba\ Share
        mkdir ~/Samba\ Share
        sudo systemctl enable smb
    fi
}

# Setup user environment and VS Code settings
setup_user_environment() {
    echo -e "VISUAL=nano\nEDITOR=nano\nPAGER=more" | sudo tee /etc/environment > /dev/null
    mkdir -p "/home/$(whoami)/.config/Code - OSS/User/"
    curl -Ss https://gist.githubusercontent.com/ayu2805/7bae58a7e279199552f77e3ae577bd6c/raw/settings.json | \
        tee "/home/$(whoami)/.config/Code - OSS/User/settings.json" > /dev/null
}

# Configure git if requested
setup_git() {
    echo ""
    if prompt_yes_no "Do you want to configure git?"; then
        local git_name git_email
        read -r -p "Enter your Git name: " git_name
        read -r -p "Enter your Git email: " git_email
        
        git config --global user.name "$git_name"
        git config --global user.email "$git_email"
        git config --global init.defaultBranch main
        ssh-keygen -t ed25519 -C "$git_email"
        git config --global gpg.format ssh
        git config --global user.signingkey "/home/$(whoami)/.ssh/id_ed25519.pub"
        git config --global commit.gpgsign true
    fi
}

# Configuration templates for different components
get_gdm_config() {
    cat <<'EOF'
[org/gnome/desktop/interface]
color-scheme='prefer-dark'
font-name='Adwaita Sans 12'
icon-theme='Papirus-Dark'
show-battery-percentage=true

[org/gnome/desktop/peripherals/keyboard]
numlock-state=true

[org/gnome/desktop/peripherals/touchpad]
speed=0.3
tap-to-click=true

[org/gnome/gnome-session]
logout-prompt=false
EOF
}

get_sddm_config() {
    cat <<'EOF'
[General]
DisplayServer=wayland
GreeterEnvironment=QT_WAYLAND_SHELL_INTEGRATION=layer-shell

[Theme]
Current=breeze
CursorTheme=breeze_cursors

[Wayland]
CompositorCommand=kwin_wayland --no-global-shortcuts --no-lockscreen --inputmethod maliit-keyboard --locale1
EOF
}

get_nano_config() {
    cat <<'EOF'
include "/usr/share/nano/*.nanorc"
include "/usr/share/nano/extra/*.nanorc"

set autoindent
set constantshow
set minibar
set stateflags
set tabsize 4
EOF
}

# Setup GNOME desktop environment
setup_gnome() {
    echo ""
    echo "Installing Gnome..."
    echo ""
    
    # Build package list from gnome group excluding packages in gnome/remove, then install
    local gnome_packages
    gnome_packages=$(pacman -Sgq gnome | grep -vf gnome/remove)
    if [ -n "$gnome_packages" ]; then
        # shellcheck disable=SC2086
        sudo pacman -S --needed --noconfirm --disable-download-timeout $gnome_packages
    fi
    # Install additional packages from gnome/gnome file
    install_packages_from_file gnome/gnome
    
    sudo systemctl enable gdm
    
    # Configure GNOME settings
    gsettings set org.gnome.Console ignore-scrollback-limit true
    gsettings set org.gnome.Console restore-window-size false
    gsettings set org.gnome.desktop.a11y always-show-universal-access-status true
    gsettings set org.gnome.desktop.app-folders folder-children "['System', 'Utilities']"
    gsettings set org.gnome.desktop.app-folders.folder:/org/gnome/desktop/app-folders/folders/System/ categories "['System']"
    gsettings set org.gnome.desktop.app-folders.folder:/org/gnome/desktop/app-folders/folders/System/ name 'System'
    gsettings set org.gnome.desktop.app-folders.folder:/org/gnome/desktop/app-folders/folders/System/ translate true
    gsettings set org.gnome.desktop.app-folders.folder:/org/gnome/desktop/app-folders/folders/Utilities/ categories "['AudioVideo', 'Development', 'Graphics',  'Network',  'Utility']"
    gsettings set org.gnome.desktop.app-folders.folder:/org/gnome/desktop/app-folders/folders/Utilities/ name 'Utilities'
    gsettings set org.gnome.desktop.app-folders.folder:/org/gnome/desktop/app-folders/folders/Utilities/ translate true
    gsettings set org.gnome.desktop.datetime automatic-timezone true
    gsettings set org.gnome.desktop.interface clock-format '24h'
    gsettings set org.gnome.desktop.interface clock-show-weekday true
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
    gsettings set org.gnome.desktop.interface font-name 'Adwaita Sans 12'
    gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark'
    gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark'
    gsettings set org.gnome.desktop.interface monospace-font-name 'Adwaita Mono 12'
    gsettings set org.gnome.desktop.interface show-battery-percentage true
    gsettings set org.gnome.desktop.notifications show-in-lock-screen false
    gsettings set org.gnome.desktop.peripherals.keyboard numlock-state true
    gsettings set org.gnome.desktop.peripherals.touchpad speed 0.3
    gsettings set org.gnome.desktop.peripherals.touchpad tap-to-click true
    gsettings set org.gnome.desktop.privacy old-files-age 7
    gsettings set org.gnome.desktop.privacy remember-recent-files false
    gsettings set org.gnome.desktop.privacy remove-old-temp-files true
    gsettings set org.gnome.desktop.privacy remove-old-trash-files true
    gsettings set org.gnome.desktop.screensaver restart-enabled true
    gsettings set org.gnome.desktop.sound allow-volume-above-100-percent true
    gsettings set org.gnome.desktop.sound event-sounds false
    gsettings set org.gnome.desktop.wm.preferences button-layout ":minimize,maximize,close"
    gsettings set org.gnome.nautilus.icon-view default-zoom-level 'small-plus' 
    gsettings set org.gnome.SessionManager logout-prompt false
    gsettings set org.gnome.shell favorite-apps "['firefox.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.Console.desktop', 'code-oss.desktop']"
    gsettings set org.gnome.shell.keybindings show-screenshot-ui "['Print', '<Shift><Super>S']"
    gsettings set org.gnome.TextEditor discover-settings false
    gsettings set org.gnome.TextEditor highlight-current-line true
    gsettings set org.gnome.TextEditor indent-width 4
    gsettings set org.gnome.TextEditor restore-session false
    gsettings set org.gnome.TextEditor show-line-numbers true
    gsettings set org.gnome.TextEditor tab-width 4
    gsettings set org.gnome.TextEditor wrap-text false
    gsettings set org.gtk.gtk4.Settings.FileChooser sort-directories-first true
    gsettings set org.gtk.Settings.FileChooser sort-directories-first true
    
    # Configure GDM
    echo -e "user-db:user\nsystem-db:gdm\nfile-db:/usr/share/gdm/greeter-dconf-defaults" | \
        sudo tee /etc/dconf/profile/gdm > /dev/null
    sudo mkdir -p /etc/dconf/db/gdm.d/
    get_gdm_config | sudo tee /etc/dconf/db/gdm.d/gdm-config > /dev/null
    sudo dconf update
    
    # Set default applications
    xdg-mime default org.gnome.Nautilus.desktop inode/directory
    xdg-mime default org.gnome.TextEditor.desktop application/json
    
    # Configure nano
    get_nano_config | sudo tee /etc/nanorc > /dev/null
}

# Setup KDE desktop environment
setup_kde() {
    echo ""
    echo "Installing KDE..."
    echo ""
    
    # Install packages from file
    install_packages_from_file kde
    
    # Configure SDDM
    sudo mkdir -p /etc/sddm.conf.d/
    get_sddm_config | sudo tee /usr/lib/sddm/sddm.conf.d/default.conf > /dev/null
    sudo mkdir -p /var/lib/sddm/.config/
    echo -e "[Keyboard]\nNumLock=0" | sudo tee /var/lib/sddm/.config/kcminputrc > /dev/null
    echo -e "[Plugins]\nshakecursorEnabled=false" | sudo tee /var/lib/sddm/.config/kwinrc > /dev/null
    sudo sed -i 's/^background=.*/background=\/usr\/share\/wallpapers\/Next\/contents\/images_dark\/5120x2880.png/' \
        /usr/share/sddm/themes/breeze/theme.conf
    echo -e "[Icon Theme]\nInherits=breeze_cursors" | sudo tee /usr/share/icons/default/index.theme > /dev/null
    sudo systemctl enable sddm

    # Configure user KDE settings
    mkdir -p ~/.config/
    echo -e "[General]\nRememberOpenedTabs=false" | tee ~/.config/dolphinrc > /dev/null
    echo -e "[Keyboard]\nNumLock=0" | tee ~/.config/kcminputrc > /dev/null
    echo -e "[KDE]\nLookAndFeelPackage=org.kde.breezedark.desktop" | tee ~/.config/kdeglobals > /dev/null
    echo -e "[BusyCursorSettings]\nBouncing=false\n[FeedbackStyle]\nBusyCursor=false" | \
        tee ~/.config/klaunchrc > /dev/null
    echo -e "[General]\nconfirmLogout=false\nloginMode=emptySession" | tee ~/.config/ksmserverrc > /dev/null
    echo -e "[KSplash]\nEngine=none\nTheme=None" | tee ~/.config/ksplashrc > /dev/null
    echo -e "[Effect-overview]\nBorderActivate=9\n\n[Plugins]\nblurEnabled=false\ncontrastEnabled=true\nshakecursorEnabled=false" | \
        tee ~/.config/kwinrc > /dev/null
    echo -e "[General]\nShowWelcomeScreenOnStartup=false" | tee ~/.config/arkrc > /dev/null
    echo -e "[General]\nShow welcome view for new window=false" | tee ~/.config/katerc ~/.config/kwriterc > /dev/null
    echo -e "[PlasmaViews][Panel 2]\nfloating=0\npanelOpacity=1" | tee ~/.config/plasmashellrc > /dev/null
    echo -e "[Plugin-org.kde.ActivityManager.Resources.Scoring]\nwhat-to-remember=2" | \
        tee ~/.config/kactivitymanagerd-pluginsrc > /dev/null
    
    # Configure nano
    get_nano_config | sudo tee /etc/nanorc > /dev/null
    
    # Configure touchpad if present
    if sudo libinput list-devices | grep -q "Touchpad"; then
        local touchpad_id vendor_id product_id vendor_id_dec product_id_dec
        touchpad_id=$(sudo libinput list-devices | grep "Touchpad" | awk '{$1=""; print substr($0, 2)}')
        vendor_id=$(echo "$touchpad_id" | awk '{print substr($2, 1, 4)}')
        product_id=$(echo "$touchpad_id" | awk '{print substr($2, 6, 4)}')
        vendor_id_dec=$(printf "%d" "0x$vendor_id")
        product_id_dec=$(printf "%d" "0x$product_id")
        echo -e "\n[Libinput][$vendor_id_dec][$product_id_dec][$touchpad_id]\nNaturalScroll=true" | \
            tee -a ~/.config/kcminputrc > /dev/null
    fi
}

# Prompt user to select desktop environment
select_desktop_environment() {
    while true; do
        echo -e "1) Gnome\n2) KDE"
        read -r -p "Select Desktop Environment(or press enter to skip): " reply
        case "$reply" in
            "1")
                setup_gnome
                break
                ;;
            "2")
                setup_kde
                break
                ;;
            "")
                break
                ;;
            *)
                echo -e "\nInvalid choice. Please try again..."
                ;;
        esac
    done
}

# Configure post-desktop environment settings
configure_post_de() {
    echo ""
    
    # Configure bluetooth if installed
    if pactree -r bluez &>/dev/null; then
        sudo sed -i 's/^#AutoEnable.*/AutoEnable=false/' /etc/bluetooth/main.conf
        sudo sed -i 's/^AutoEnable.*/AutoEnable=false/' /etc/bluetooth/main.conf
        sudo systemctl enable bluetooth
    fi

    # Configure GTK4 renderer if installed
    if pactree -r gtk4 &>/dev/null; then
        echo "GSK_RENDERER=ngl" | sudo tee -a /etc/environment > /dev/null
    fi
}

# Configure makepkg settings
configure_makepkg() {
    sudo sed -i "s/^PKGEXT.*/PKGEXT='.pkg.tar'/" /etc/makepkg.conf
    sudo sed -i 's/^#MAKEFLAGS.*/MAKEFLAGS="-j$(nproc)"/' /etc/makepkg.conf
    sudo sed -i 's/^MAKEFLAGS.*/MAKEFLAGS="-j$(nproc)"/' /etc/makepkg.conf
}

# Setup Chaotic-AUR repository
setup_chaotic_aur() {
    echo ""
    
    # Check if already installed
    if pactree -r chaotic-keyring &>/dev/null && pactree -r chaotic-mirrorlist &>/dev/null; then
        echo -e "[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist\n" | \
            sudo tee -a /etc/pacman.d/custom > /dev/null
    else
        echo ""
        if prompt_yes_no "Do you want Chaotic-AUR?"; then
            sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
            sudo pacman-key --lsign-key 3056513887B78AEB
            sudo pacman -U --needed --noconfirm \
                'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst'
            sudo pacman -U --needed --noconfirm \
                'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'
            echo -e "[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist\n" | \
                sudo tee -a /etc/pacman.d/custom > /dev/null
            sudo pacman -Syu
        fi
    fi
}

# Setup BlackArch repository
setup_blackarch() {
    echo ""
    if prompt_yes_no "Do you want to install BlackArch Repository?"; then
        # Download and verify the script before execution
        local script_url="https://blackarch.org/strap.sh"
        local temp_script="/tmp/blackarch-strap.sh"
        
        echo "Downloading BlackArch setup script..."
        if curl -sS "$script_url" -o "$temp_script"; then
            echo "Downloaded. Please review the script at $temp_script before proceeding."
            read -r -p "Press Enter to continue with installation, or Ctrl+C to cancel..."
            sudo sh "$temp_script"
            rm -f "$temp_script"
        else
            echo "Failed to download BlackArch setup script" >&2
            return 1
        fi
    fi
}

# Configure Qt file dialog
configure_qt_dialog() {
    local username
    username="$(whoami)"
    
    # Ensure config directory exists
    mkdir -p ~/.config/
    
    cat <<EOF | tee ~/.config/QtProject.conf > /dev/null
[FileDialog]
shortcuts=file:, file:///home/$username, file:///home/$username/Desktop, file:///home/$username/Documents, file:///home/$username/Downloads, file:///home/$username/Music, file:///home/$username/Pictures, file:///home/$username/Videos
sidebarWidth=110
viewMode=Detail
EOF
}

# Cleanup and final message
cleanup() {
    rm -f ~/.bash*
    echo ""
    echo "You can now reboot your system"
}

#######################################
# Main Execution
#######################################

main() {
    # Initial checks and setup
    check_root
    setup_user_info
    
    # Package and system configuration
    setup_pacman
    update_system
    install_cpu_drivers
    install_nvidia_drivers
    
    # Storage and services
    setup_swap
    install_common_packages
    setup_cups_hook
    configure_system
    
    # Optional services
    setup_samba
    
    # User environment
    setup_user_environment
    setup_git
    
    # Desktop environment
    select_desktop_environment
    
    # Post-DE configuration
    configure_post_de
    configure_makepkg
    
    # Repository setup
    setup_chaotic_aur
    setup_blackarch
    
    # Final configuration
    configure_qt_dialog
    cleanup
}

# Run main function
main "$@"
