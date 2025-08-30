#!/bin/bash

if [ "$(id -u)" = 0 ]; then
    echo "######################################################################"
    echo "This script should NOT be run as root user as it may create unexpected"
    echo " problems and you may have to reinstall Arch. So run this script as a"
    echo "  normal user. You will be asked for a sudo password when necessary"
    echo "######################################################################"
    exit 1
fi

read -p "Enter your Full Name: " fn
if [ -n "$fn" ]; then
    sudo chfn -f "$fn" "$(whoami)"
fi

grep -qF "Include = /etc/pacman.d/custom" /etc/pacman.conf || echo "Include = /etc/pacman.d/custom" | sudo tee -a /etc/pacman.conf > /dev/null
echo -e "[options]\nColor\nParallelDownloads = 5\nILoveCandy\n" | sudo tee /etc/pacman.d/custom > /dev/null

# echo ""
# read -r -p "Do you want to run reflector? [y/N] " response
# if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
#     sudo pacman -Sy --disable-download-timeout --needed --noconfirm reflector
#     echo -e "\nIt will take time to fetch the mirrors so please wait"
#     sudo reflector --save /etc/pacman.d/mirrorlist -p https -c $(echo $LANG | awk -F [_,.] '{print $2}') -f 10
# fi

echo ""
sudo pacman -Syu --needed --noconfirm --disable-download-timeout pacman-contrib
if [ "$(pactree -r linux)" ]; then
    sudo pacman -S --needed --noconfirm --disable-download-timeout linux-headers
fi

if [ "$(pactree -r linux-zen)" ]; then
    sudo pacman -S --needed --noconfirm --disable-download-timeout linux-zen-headers
fi

CPU_VENDOR=$(lscpu | grep "Vendor ID" | awk '{print $3}')

if [ "$CPU_VENDOR" == "GenuineIntel" ]; then
    sudo pacman -S --needed --noconfirm --disable-download-timeout intel-media-driver vulkan-intel
elif [ "$CPU_VENDOR" == "AuthenticAMD" ]; then
    sudo pacman -S --needed --noconfirm --disable-download-timeout libva-mesa-driver vulkan-radeon
else
    echo "Unknown CPU vendor"
fi

echo ""
read -r -p "Do you want to install NVIDIA open source drivers(Turing+)? [y/N] " response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    sudo pacman -S --needed --noconfirm --disable-download-timeout nvidia-open-dkms nvidia-prime opencl-nvidia switcheroo-control
    echo -e "options nvidia NVreg_PreserveVideoMemoryAllocations=1 NVreg_UsePageAttributeTable=1" | sudo tee /etc/modprobe.d/nvidia.conf > /dev/null
    sudo systemctl enable nvidia-persistenced nvidia-hibernate nvidia-resume nvidia-suspend switcheroo-control

    echo ""
    read -r -p "Do you want to enable NVIDIA's Dynamic Boost(Ampere+)? [y/N] " response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    sudo systemctl enable nvidia-powerd
    fi
fi

if [ -z "$(swapon --show)" ]; then
    echo ""
    read -r -p "Do you want to have swap space(swapfile with hibernate)? [y/N] " response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        if [ "$(df -T / | awk 'NR==2{print $2}')" == "ext4" ]; then
            RAM_SIZE=$(free --giga | awk 'NR==2{print $2}')
            SWAP_SIZE=$((RAM_SIZE * 2))
            sudo mkswap -U clear --size ${SWAP_SIZE}G --file /swapfile
            sudo swapon /swapfile
            echo -e "[Swap]\nWhat=/swapfile\n\n[Install]\nWantedBy=swap.target" | sudo tee /etc/systemd/system/swapfile.swap > /dev/null
            sudo systemctl daemon-reload
            sudo systemctl enable swapfile.swap
            sudo sed -i '/^HOOKS=/ { /resume/ !s/filesystems/filesystems resume/ }' /etc/mkinitcpio.conf
            sudo mkinitcpio -P
            sudo sed -i '/^options/ { /mem_sleep_default=deep/! s/$/ mem_sleep_default=deep/ }' /boot/loader/entries/*
        else
            echo "The filesystem type is not ext4."
        fi
    fi
fi

echo ""
sudo pacman -S --needed --noconfirm --disable-download-timeout - <common
sudo sed -i '/^hosts: mymachines/ s/hosts: mymachines/hosts: mymachines mdns/' /etc/nsswitch.conf
sudo systemctl disable systemd-resolved.service
sudo systemctl enable avahi-daemon cups.socket power-profiles-daemon sshd ufw
sudo systemctl start ufw

sudo mkdir -p /etc/pacman.d/hooks/
echo "[Trigger]
Operation = Install
Operation = Upgrade
Operation = Remove
Type = Package
Target = gutenprint

[Action]
Depends = gutenprint
When = PostTransaction
Exec = /usr/bin/cups-genppdupdate" | sudo tee /etc/pacman.d/hooks/gutenprint.hook > /dev/null

sudo ufw enable
sudo ufw allow IPP
sudo ufw allow SSH
sudo ufw allow Bonjour
sudo cp /usr/share/doc/avahi/ssh.service /etc/avahi/services/
sudo chsh -s /usr/bin/fish $(whoami)
sudo chsh -s /usr/bin/fish

echo ""
read -r -p "Do you want to setup Samba? [y/N] " response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    sudo pacman -S --needed --noconfirm --disable-download-timeout samba
    echo -e "[global]\nserver string = Samba Server\n" | sudo tee /etc/samba/smb.conf > /dev/null
    sudo smbpasswd -a $(whoami)
    sudo ufw allow CIFS
    echo -e "[Samba Share]\ncomment = Samba Share\npath = /home/$(whoami)/Samba Share\nread only = no" | sudo tee -a /etc/samba/smb.conf > /dev/null
    rm -rf ~/Samba\ Share
    mkdir ~/Samba\ Share
    sudo systemctl enable smb
fi

#sudo sed -i 's/Logo=1/Logo=0/' /etc/libreoffice/sofficerc
echo -e "VISUAL=nano\nEDITOR=nano\nPAGER=more" | sudo tee /etc/environment > /dev/null

echo ""
read -r -p "Do you want to configure git? [y/N] " response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    ./git-config
fi

touchpadConfig='Section "InputClass"
    Identifier "libinput touchpad catchall"
    MatchIsTouchpad "on"
    MatchDevicePath "/dev/input/event*"
    Driver "libinput"

    Option "Tapping" "on"
    Option "NaturalScrolling" "on"
    Option "DisableWhileTyping" "on"
    Option "NaturalScrolling" "true"
EndSection'

# kdeconnect="[KDE Connect]
# title=Enabling communication between all your devices
# description=Multi-platform app that allows your devices to communicate
# ports=1716:1764/tcp|1716:1764/udp"

# gsconnect="[GSConnect]
# title=KDE Connect implementation for GNOME
# description=GSConnect is a complete implementation of KDE Connect
# ports=1716:1764/tcp|1716:1764/udp"

sddm="[General]
DisplayServer=wayland
GreeterEnvironment=QT_WAYLAND_SHELL_INTEGRATION=layer-shell

[Theme]
Current=breeze
CursorTheme=breeze_cursors

[Wayland]
CompositorCommand=kwin_wayland --drm --no-lockscreen --no-global-shortcuts --locale1 --inputmethod maliit-keyboard"

nano="include "/usr/share/nano/*.nanorc"
include "/usr/share/nano/extra/*.nanorc"

set autoindent
set constantshow
set minibar
set stateflags
set tabsize 4"

setup_gnome(){
    echo ""
    echo "Installing Gnome..."
    echo ""
    sudo pacman -S --needed --noconfirm --disable-download-timeout $(pacman -Sgq gnome | grep -vf gnome/remove) - <gnome/gnome
    sudo systemctl enable gdm
    gsettings set org.gnome.Console ignore-scrollback-limit true
    gsettings set org.gnome.desktop.a11y always-show-universal-access-status true
    gsettings set org.gnome.desktop.app-folders folder-children "['Office', 'System', 'Utilities']"
    gsettings set org.gnome.desktop.app-folders.folder:/org/gnome/desktop/app-folders/folders/Office/ categories "['Office']"
    gsettings set org.gnome.desktop.app-folders.folder:/org/gnome/desktop/app-folders/folders/Office/ name 'Office'
    gsettings set org.gnome.desktop.app-folders.folder:/org/gnome/desktop/app-folders/folders/Office/ translate true
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
    gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark'
    gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark'
    gsettings set org.gnome.desktop.interface show-battery-percentage true
    gsettings set org.gnome.desktop.notifications show-in-lock-screen false
    gsettings set org.gnome.desktop.peripherals.keyboard numlock-state true
    #gsettings set org.gnome.desktop.peripherals.touchpad send-events disabled-on-external-mouse
    gsettings set org.gnome.desktop.peripherals.touchpad speed 0.5
    gsettings set org.gnome.desktop.peripherals.touchpad tap-to-click true
    gsettings set org.gnome.desktop.privacy old-files-age 7
    gsettings set org.gnome.desktop.privacy remember-recent-files false
    gsettings set org.gnome.desktop.privacy remove-old-temp-files true
    gsettings set org.gnome.desktop.privacy remove-old-trash-files true
    gsettings set org.gnome.desktop.sound allow-volume-above-100-percent true
    gsettings set org.gnome.desktop.wm.preferences button-layout ":minimize,maximize,close"
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
    sudo -u gdm dbus-launch gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
    sudo -u gdm dbus-launch gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark'
    sudo -u gdm dbus-launch gsettings set org.gnome.desktop.interface show-battery-percentage true
    sudo -u gdm dbus-launch gsettings set org.gnome.desktop.peripherals.keyboard numlock-state true
    #sudo -u gdm dbus-launch gsettings set org.gnome.desktop.peripherals.touchpad send-events disabled-on-external-mouse
    sudo -u gdm dbus-launch gsettings set org.gnome.desktop.peripherals.touchpad speed 0.5
    sudo -u gdm dbus-launch gsettings set org.gnome.desktop.peripherals.touchpad tap-to-click true
    sudo -u gdm dbus-launch gsettings set org.gnome.SessionManager logout-prompt false
    xdg-mime default org.gnome.Nautilus.desktop inode/directory
    echo -e "$nano" | sudo tee /etc/nanorc > /dev/null
}

setup_kde(){
    echo ""
    echo "Installing KDE..."
    echo ""
    sudo pacman -S --needed --noconfirm --disable-download-timeout - <kde
    sudo mkdir -p /etc/sddm.conf.d/
    echo -e "$sddm" | sudo tee /usr/lib/sddm/sddm.conf.d/default.conf > /dev/null
    echo -e "[Keyboard]\nNumLock=0" | sudo tee /var/lib/sddm/.config/kcminputrc > /dev/null
    sudo sed -i 's/^background=.*/background=\/usr\/share\/wallpapers\/Next\/contents\/images_dark\/5120x2880.png/' /usr/share/sddm/themes/breeze/theme.conf
    echo -e "[Icon Theme]\nInherits=breeze_cursors" | sudo tee /usr/share/icons/default/index.theme > /dev/null
    sudo systemctl enable sddm

    mkdir -p ~/.config/
    echo -e "[General]\nRememberOpenedTabs=false" | tee ~/.config/dolphinrc > /dev/null
    echo -e "[Keyboard]\nNumLock=0" | tee ~/.config/kcminputrc > /dev/null
    echo -e "[KDE]\nLookAndFeelPackage=org.kde.breezedark.desktop" | tee ~/.config/kdeglobals > /dev/null
    echo -e "[General]\nconfirmLogout=false\nloginMode=emptySession" | tee ~/.config/ksmserverrc > /dev/null
    echo -e "[Keyboard]\nNumLock=0" | tee ~/.config/kcminputrc > /dev/null
    echo -e "[Plugins]\nshakecursorEnabled=false\nzoomEnabled=false" | tee ~/.config/kwinrc > /dev/null
    echo -e "$nano" | sudo tee /etc/nanorc > /dev/null
    
    if [ -n "$(sudo libinput list-devices | grep "Touchpad")" ]; then
        touchpad_id=$(sudo libinput list-devices | grep "Touchpad" | awk '{$1=""; print substr($0, 2)}')
        vendor_id=$(echo $touchpad_id | awk '{print substr($2, 1, 4)}')
        product_id=$(echo $touchpad_id | awk '{print substr($2, 6, 9)}')
        vendor_id_dec=$(printf "%d" 0x$vendor_id)
        product_id_dec=$(printf "%d" 0x$product_id)
        echo -e "\n[Libinput][$vendor_id_dec][$product_id_dec][$touchpad_id]\nNaturalScroll=true" | tee -a ~/.config/kcminputrc > /dev/null
    fi
}

while true; do
    echo -e "1) Gnome\n2) KDE"
    read -p "Select Desktop Environment(or press enter to skip): "
    case $REPLY in
        "1")
            setup_gnome;break;;
        "2")
            setup_kde;break;;
        "")
            break;;
        *)
            echo -e "\nInvalid choice. Please try again...";;
    esac
done

echo ""
if [ "$(pactree -r bluez)" ]; then
    sudo sed -i 's/^#AutoEnable.*/AutoEnable=false/' /etc/bluetooth/main.conf
    sudo sed -i 's/^AutoEnable.*/AutoEnable=false/' /etc/bluetooth/main.conf
    sudo systemctl enable bluetooth
fi

if [ "$(pactree -r gtk4)" ]; then
    echo -e "GSK_RENDERER=ngl" | sudo tee -a /etc/environment > /dev/null
fi

sudo sed -i "s/^PKGEXT.*/PKGEXT=\'.pkg.tar\'/" /etc/makepkg.conf
sudo sed -i 's/^#MAKEFLAGS.*/MAKEFLAGS="-j$(nproc)"/' /etc/makepkg.conf
sudo sed -i 's/^MAKEFLAGS.*/MAKEFLAGS="-j$(nproc)"/' /etc/makepkg.conf

echo ""
if [ "$(pactree -r chaotic-keyring && pactree -r chaotic-mirrorlist)" ]; then
    echo -e "[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist\n" | sudo tee -a /etc/pacman.d/custom > /dev/null
else
    echo ""
    read -r -p "Do you want Chaotic-AUR? [y/N] " response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
        sudo pacman-key --lsign-key 3056513887B78AEB
        sudo pacman -U --needed --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst'
        sudo pacman -U --needed --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'
        echo -e "[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist\n" | sudo tee -a /etc/pacman.d/custom > /dev/null
        sudo pacman -Syu
    fi
fi

echo ""
read -r -p "Do you want to install Cloudflare Warp? [y/N] " response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    echo ""
    # Dependencies: nspr nss
    bash -c "$(curl -Ss https://gist.githubusercontent.com/ayu2805/7ad8100b15699605fbf50291af8df16c/raw/warp-update)"
    echo "Waiting for warp-svc.service to start..."
    sleep 1
    warp-cli generate-completions fish | sudo tee /usr/share/fish/completions/warp-cli.fish > /dev/null
fi

echo "[FileDialog]
shortcuts=file:, file:///home/ap, file:///home/ap/Desktop, file:///home/ap/Documents, file:///home/ap/Downloads,  file:///home/ap/Music, file:///home/ap/Pictures, file:///home/ap/Videos
sidebarWidth=110
viewMode=Detail" sudo tee ~/.config/QtProject.conf > /dev/null

rm -f ~/.bash*
echo ""
echo "You can now reboot your system"
