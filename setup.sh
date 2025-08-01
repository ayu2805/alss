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
else
    true
fi

grep -qF "Include = /etc/pacman.d/custom" /etc/pacman.conf || echo "Include = /etc/pacman.d/custom" | sudo tee -a /etc/pacman.conf > /dev/null
echo -e "[options]\nColor\nParallelDownloads = 5\nILoveCandy\n" | sudo tee /etc/pacman.d/custom > /dev/null

echo ""
read -r -p "Do you want to run reflector? [y/N] " response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    sudo pacman -Sy --needed --noconfirm reflector
    echo -e "\nIt will take time to fetch the mirrors so please wait"
    sudo reflector --save /etc/pacman.d/mirrorlist -p https -c $(echo $LANG | awk -F [_,.] '{print $2}') -f 10
fi

echo ""
sudo pacman -Syu --needed --noconfirm pacman-contrib
if [ "$(pactree -r linux)" ]; then
    sudo pacman -S --needed --noconfirm linux-headers
fi

if [ "$(pactree -r linux-zen)" ]; then
    sudo pacman -S --needed --noconfirm linux-zen-headers
fi

echo ""
read -r -p "Do you want to install Intel drivers? [y/N] " response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    sudo pacman -S --needed --noconfirm libva-intel-driver intel-media-driver vulkan-intel
fi

echo ""
read -r -p "Do you want to install AMD drivers? [y/N] " response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    sudo pacman -S --needed --noconfirm libva-mesa-driver vulkan-radeon
fi

echo ""
read -r -p "Do you want to install NVIDIA open source drivers(Turing+)? [y/N] " response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    sudo pacman -S --needed --noconfirm nvidia-open-dkms nvidia-prime opencl-nvidia switcheroo-control
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
sudo pacman -S --needed --noconfirm - <common
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

echo "[global]
server string = Samba Server
" | sudo tee /etc/samba/smb.conf > /dev/null

echo ""
sudo smbpasswd -a $(whoami)
echo ""
sudo systemctl enable smb nmb

sudo ufw enable
sudo ufw allow IPP
sudo ufw allow CIFS
sudo ufw allow SSH
sudo ufw allow Bonjour
sudo cp /usr/share/doc/avahi/ssh.service /etc/avahi/services/
sudo chsh -s /usr/bin/fish $(whoami)
sudo chsh -s /usr/bin/fish

echo ""
read -r -p "Do you want to create a Samba Shared folder? [y/N] " response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    echo -e "[Samba Share]\ncomment = Samba Share\npath = /home/$(whoami)/Samba Share\nread only = no" | sudo tee -a /etc/samba/smb.conf > /dev/null
    rm -rf ~/Samba\ Share
    mkdir ~/Samba\ Share
    sudo systemctl restart smb nmb
fi

#sudo sed -i 's/Logo=1/Logo=0/' /etc/libreoffice/sofficerc
echo -e "VISUAL=nvim\nEDITOR=nvim" | sudo tee /etc/environment > /dev/null
grep -qF "set number" /etc/xdg/nvim/sysinit.vim || echo "set number" | sudo tee -a /etc/xdg/nvim/sysinit.vim > /dev/null
grep -qF "set wrap!" /etc/xdg/nvim/sysinit.vim || echo "set wrap!" | sudo tee -a /etc/xdg/nvim/sysinit.vim > /dev/null

echo ""
if [ "$(pactree -r bluez)" ]; then
    sudo sed -i 's/^#AutoEnable.*/AutoEnable=false/' /etc/bluetooth/main.conf
    sudo sed -i 's/^AutoEnable.*/AutoEnable=false/' /etc/bluetooth/main.conf
fi

echo ""
read -r -p "Do you want to configure git? [y/N] " response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    echo ""
    bash -c "$(curl -Ss https://gist.githubusercontent.com/ayu2805/72b96f02af0eca564af8dae62d30a5da/raw/git-config)"
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

kdeconnect="[KDE Connect]
title=Enabling communication between all your devices
description=Multi-platform app that allows your devices to communicate
ports=1716:1764/tcp|1716:1764/udp"

gsconnect="[GSConnect]
title=KDE Connect implementation for GNOME
description=GSConnect is a complete implementation of KDE Connect
ports=1716:1764/tcp|1716:1764/udp"

lgg="[greeter]
theme-name = Materia-dark
indicators = ~clock;~spacer;~session;~power
icon-theme-name = Papirus-Dark
clock-format = %A, %d %B %Y, %H:%M:%S"

setup_gnome(){
    echo ""
    echo "Installing WhiteSur Icon Theme..."
    echo ""
    git clone https://github.com/vinceliuice/WhiteSur-icon-theme.git --depth=1
    cd WhiteSur-icon-theme/
    sudo ./install.sh -a
    cd ..
    rm -rf WhiteSur-icon-theme/

    echo ""
    echo "Installing Gnome..."
    echo ""
    sudo pacman -S --needed --noconfirm - <gnome/gnome
    pacman -Sgq gnome | grep -vf gnome/remove | sudo pacman -S --needed --noconfirm -
    sudo systemctl enable gdm wsdd
    sudo -u gdm dbus-launch gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
    sudo -u gdm dbus-launch gsettings set org.gnome.desktop.interface icon-theme 'WhiteSur-dark'
    sudo -u gdm dbus-launch gsettings set org.gnome.desktop.interface show-battery-percentage true
    sudo -u gdm dbus-launch gsettings set org.gnome.desktop.peripherals.keyboard numlock-state true
    sudo -u gdm dbus-launch gsettings set org.gnome.desktop.peripherals.touchpad speed 0.5
    sudo -u gdm dbus-launch gsettings set org.gnome.desktop.peripherals.touchpad tap-to-click true
    #sudo -u gdm dbus-launch gsettings set org.gnome.desktop.peripherals.touchpad send-events disabled-on-external-mouse
    gsettings set org.gnome.desktop.a11y always-show-universal-access-status true
    gsettings set org.gnome.desktop.datetime automatic-timezone true
    gsettings set org.gnome.desktop.interface clock-format '24h'
    gsettings set org.gnome.desktop.interface clock-show-weekday true
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
    #gsettings set org.gnome.desktop.interface enable-hot-corners false
    gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark'
    gsettings set org.gnome.desktop.interface icon-theme 'WhiteSur-dark'
    gsettings set org.gnome.desktop.interface show-battery-percentage true
    gsettings set org.gnome.desktop.peripherals.keyboard numlock-state true
    #gsettings set org.gnome.desktop.peripherals.touchpad send-events disabled-on-external-mouse
    gsettings set org.gnome.desktop.peripherals.touchpad speed 0.5
    gsettings set org.gnome.desktop.peripherals.touchpad tap-to-click true
    gsettings set org.gnome.desktop.privacy old-files-age uint32\ 7
    gsettings set org.gnome.desktop.privacy remember-recent-files false
    gsettings set org.gnome.desktop.privacy remove-old-temp-files true
    gsettings set org.gnome.desktop.privacy remove-old-trash-files true
    #gsettings set org.gnome.desktop.sound allow-volume-above-100-percent true
    gsettings set org.gnome.desktop.wm.preferences button-layout ":minimize,maximize,close"
    gsettings set org.gtk.Settings.FileChooser sort-directories-first true
    gsettings set org.gtk.gtk4.Settings.FileChooser sort-directories-first true
    xdg-mime default org.gnome.Nautilus.desktop inode/directory

    echo ""
    sudo pacman -S --needed --noconfirm gnome-shell-extension-caffeine
    gnome-extensions enable caffeine@patapon.info
    gnome-extensions enable drive-menu@gnome-shell-extensions.gcampax.github.com
    gnome-extensions enable light-style@gnome-shell-extensions.gcampax.github.com
}

setup_kde(){
    #echo ""
    #echo "$kdeconnect" | sudo tee /etc/ufw/applications.d/kdeconnect > /dev/null
    #sudo ufw app update "KDE Connect"
    #sudo ufw allow "KDE Connect"

    echo ""
    echo "Installing KDE..."
    echo ""
    sudo pacman -S --needed --noconfirm - <kde
    sudo mkdir -p /etc/sddm.conf.d/
    echo -e "[General]\nNumlock=on\n\n[Theme]\nCurrent=breeze\nCursorTheme=breeze_cursors" | sudo tee /etc/sddm.conf.d/kde_settings.conf > /dev/null
    sudo sed -i 's/^background=.*/background=\/usr\/share\/wallpapers\/Next\/contents\/images_dark\/5120x2880.png/' /usr/share/sddm/themes/breeze/theme.conf
    echo -e "[Icon Theme]\nInherits=breeze_cursors" | sudo tee /usr/share/icons/default/index.theme > /dev/null
    sudo systemctl enable sddm
    echo "$touchpadConfig" | sudo tee /etc/X11/xorg.conf.d/30-touchpad.conf > /dev/null

    echo -e "[General]\nRememberOpenedTabs=false" | tee ~/.config/dolphinrc > /dev/null
    echo -e "[Keyboard]\nNumLock=0" | tee ~/.config/kcminputrc > /dev/null
    echo -e "[KDE]\nLookAndFeelPackage=org.kde.breezedark.desktop" | tee ~/.config/kdeglobals > /dev/null
    echo -e "[PlasmaViews][Panel 2]\nfloating=0\n\n[PlasmaViews][Panel 2][Defaults]\nthickness=40" | tee ~/.config/plasmashellrc > /dev/null
    echo -e "[General]\nconfirmLogout=false\nloginMode=emptySession" | tee ~/.config/ksmserverrc > /dev/null

    echo ""
    read -r -p "Do you want to Touchpad configuration? [y/N] " response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        touchpad_id=$(sudo libinput list-devices | grep "Touchpad" | awk '{$1=""; print substr($0, 2)}')
        vendor_id=$(echo $touchpad_id | awk '{print substr($2, 1, 4)}')
        product_id=$(echo $touchpad_id | awk '{print substr($2, 6, 9)}')
        vendor_id_dec=$(printf "%d" 0x$vendor_id)
        product_id_dec=$(printf "%d" 0x$product_id)
        echo -e "[Keyboard]\nNumLock=0" | tee ~/.config/kcminputrc > /dev/null
        echo -e "\n[Libinput][$vendor_id_dec][$product_id_dec][$touchpad_id]\nNaturalScroll=true" | tee -a ~/.config/kcminputrc > /dev/null
    fi
}

setup_xfce(){
    echo ""
    echo "Installing XFCE..."
    echo ""
    sudo pacman -S --needed --noconfirm - <xfce
    xfconf-query -c xfwm4 -p /general/button_layout -n -t string -s "|HMC"
    xfconf-query -c xfwm4 -p /general/raise_with_any_button -n -t bool -s false
    xfconf-query -c xfwm4 -p /general/mousewheel_rollup -n -t bool -s false
    xfconf-query -c xfwm4 -p /general/scroll_workspaces -n -t bool -s false
    xfconf-query -c xfwm4 -p /general/placement_ratio -n -t int -s 100
    xfconf-query -c xfwm4 -p /general/show_popup_shadow -n -t bool -s true
    xfconf-query -c xfwm4 -p /general/wrap_windows -n -t bool -s false
    xfconf-query -c xfce4-panel -p /panels/panel-1/size -n -t int -s 32
    xfconf-query -c xfce4-panel -p /panels/panel-1/icon-size -n -t int -s 16
    xfconf-query -c xfce4-panel -p /plugins/plugin-1/show-button-title -n -t bool -s false
    xfconf-query -c xfce4-panel -p /plugins/plugin-1/button-icon -n -t string -s "desktop-environment-xfce"
    #xfconf-query -c xfce4-panel -p /panels -n -t int -s 1 -a
    xfconf-query -c xfce4-desktop -p /desktop-icons/file-icons/show-filesystem -n -t bool -s false
    xfconf-query -c xfce4-notifyd -p /do-slideout -n -t bool -s true
    xfconf-query -c xfce4-notifyd -p /notify-location -n -t int -s 3
    xfconf-query -c xfce4-notifyd -p /expire-timeout -n -t int -s 5
    xfconf-query -c xfce4-notifyd -p /initial-opacity -n -t double -s 1
    xfconf-query -c xfce4-notifyd -p /notification-log -n -t bool -s true
    xfconf-query -c xfce4-notifyd -p /log-level -n -t int -s 1
    xfconf-query -c xfce4-notifyd -p /log-max-size -n -t int -s 0
    xfconf-query -c xsettings -p /Xft/DPI -n -t int -s 100
    xfconf-query -c xsettings -p /Net/IconThemeName -n -t string -s "Papirus-Dark"
    sudo sed -i 's/^#greeter-setup-script=.*/greeter-setup-script=\/usr\/bin\/numlockx on/' /etc/lightdm/lightdm.conf
    echo "$lgg" | sudo tee /etc/lightdm/lightdm-gtk-greeter.conf > /dev/null

    sudo systemctl enable lightdm
    echo "$touchpadConfig" | sudo tee /etc/X11/xorg.conf.d/30-touchpad.conf > /dev/null

    echo ""
    read -r -p "Do you want to install Colloid GTK Theme? [y/N] " response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        echo ""
        git clone https://github.com/vinceliuice/Colloid-gtk-theme.git --depth=1
        cd Colloid-gtk-theme/
        sudo ./install.sh
        cd ..
        rm -rf Colloid-gtk-theme/

        xfconf-query -c xsettings -p /Net/ThemeName -n -t string -s "Colloid-Dark"
        xfconf-query -c xfwm4 -p /general/theme -n -t string -s "Colloid-Dark"
    fi
}

while true; do
    echo -e "1) Gnome\n2) KDE\n3) XFCE"
    read -p "Select Desktop Environment(or press enter to skip): "
    case $REPLY in
        "1")
            setup_gnome;break;;
        "2")
            setup_kde;break;;
        "3")
            setup_xfce;break;;
        "")
            break;;
        *)
            echo -e "\nInvalid choice. Please try again...";;
    esac
done

if [ "$(pactree -r gtk4)" ]; then
    echo -e "GSK_RENDERER=gl" | sudo tee -a /etc/environment > /dev/null
fi

echo ""
read -r -p "Do you want to install Firefox? [y/N] " response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    sudo pacman -S --needed --noconfirm firefox firefox-ublock-origin
fi

echo ""
read -r -p "Do you want to install LibreOffice(Fresh)? [y/N] " response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    sudo pacman -S --needed --noconfirm libreoffice-fresh
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

        if [ "$(pactree -r yay)" ]; then
            true
        else
            sudo pacman -S --needed --noconfirm yay
        fi
    fi
fi

if [ "$(pactree -r yay)" ]; then
    true
else
    sudo pacman -S --needed --noconfirm git base-devel
    git clone https://aur.archlinux.org/yay.git --depth=1
    cd yay
    yes | makepkg -si
    cd ..
    rm -rf yay
fi

yay -S --answerclean A --answerdiff N --removemake --cleanafter --save
yay -Yc --noconfirm

echo ""
read -r -p "Do you want to install Code-OSS? [y/N] " response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    sudo pacman -S --needed --noconfirm code
    echo ""
    read -r -p "Do you want to install proprietary VSCode marketplace? [y/N] " response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        yay -S --needed --noconfirm code-marketplace
    fi
fi

echo ""
read -r -p "Do you want to install Cloudflare Warp? [y/N] " response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    echo ""
    bash -c "$(curl -Ss https://gist.githubusercontent.com/ayu2805/7ad8100b15699605fbf50291af8df16c/raw/warp-update)"
    echo "Waiting for warp-svc.service to start..."
    sleep 3
    warp-cli --accept-tos generate-completions fish | sudo tee /etc/fish/completions/warp-cli.fish > /dev/null
fi

echo "[FileDialog]
shortcuts=file:, file:///home/ap, file:///home/ap/Desktop, file:///home/ap/Documents, file:///home/ap/Downloads,  file:///home/ap/Music, file:///home/ap/Pictures, file:///home/ap/Videos
sidebarWidth=110
viewMode=Detail" sudo tee ~/.config/QtProject.conf > /dev/null

echo ""
echo "You can now reboot your system"
