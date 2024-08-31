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
if [ "$(pactree -r reflector)" ]; then
    true
else
    sudo pacman -Sy --needed --noconfirm reflector
    echo -e "\nIt will take time to fetch the mirrors so please wait"
    sudo reflector --save /etc/pacman.d/mirrorlist -p https -c $(echo $LANG | awk -F _ '{print $2}') -f 10
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
    sudo pacman -S --needed --noconfirm xf86-video-amdgpu libva-mesa-driver vulkan-radeon
fi

echo ""
read -r -p "Do you want to install NVIDIA open source drivers(Turing+)? [y/N] " response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    sudo pacman -S --needed --noconfirm nvidia-open-dkms nvidia-utils nvidia-settings nvidia-prime opencl-nvidia switcheroo-control
    echo -e options "nvidia-drm modeset=1 fbdev=1\noptions nvidia NVreg_UsePageAttributeTable=1" | sudo tee /etc/modprobe.d/nvidia.conf > /dev/null
    sudo sed -i 's/MODULES=\(.*\)/MODULES=\(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
    sudo mkinitcpio -P
    sudo systemctl enable nvidia-persistenced nvidia-hibernate nvidia-resume nvidia-suspend switcheroo-control

    echo ""
    read -r -p "Do you want to enable NVIDIA's Dynamic Boost(Ampere+)? [y/N] " response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        sudo systemctl enable nvidia-powerd
    fi
fi

echo ""
read -r -p "Do you want to install NVIDIA drivers(Maxwell+)? [y/N] " response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    sudo pacman -S --needed --noconfirm nvidia-dkms nvidia-utils nvidia-settings nvidia-prime opencl-nvidia switcheroo-control
    echo -e options "nvidia-drm modeset=1 fbdev=1\noptions nvidia NVreg_UsePageAttributeTable=1" | sudo tee /etc/modprobe.d/nvidia.conf > /dev/null
    sudo sed -i 's/MODULES=\(.*\)/MODULES=\(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
    sudo mkinitcpio -P
    sudo systemctl enable nvidia-persistenced nvidia-hibernate nvidia-resume nvidia-suspend switcheroo-control

    echo ""
    read -r -p "Do you want to enable NVIDIA's Dynamic Boost(Ampere+)? [y/N] " response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        sudo systemctl enable nvidia-powerd
    fi
fi

echo ""
sudo pacman -S --needed --noconfirm - <common
sudo systemctl disable systemd-resolved.service
sudo systemctl enable avahi-daemon.socket cups.socket power-profiles-daemon sshd ufw
sudo systemctl start ufw

sudo mkdir -p /etc/pacman.d/hooks/
echo "[global]
workgroup = WORKGROUP
server string = Samba Server
netbios name = $(hostname)

" | sudo tee /etc/samba/smb.conf > /dev/null

echo ""
sudo smbpasswd -a $(whoami)
echo ""
sudo systemctl enable smb nmb

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
sudo ufw allow CIFS
sudo ufw allow SSH
sudo cp /usr/share/doc/avahi/ssh.service /etc/avahi/services/
sudo chsh -s /usr/bin/fish $(whoami)
sudo chsh -s /usr/bin/fish
pipx ensurepath
echo -e "127.0.0.1\tlocalhost\n127.0.1.1\t$(hostname)\n\n# The following lines are desirable for IPv6 capable hosts\n::1     localhost ip6-localhost ip6-loopback\nff02::1 ip6-allnodes\nff02::2 ip6-allrouters" | sudo tee /etc/hosts > /dev/null
#register-python-argcomplete --shell fish pipx >~/.config/fish/completions/pipx.fish

echo ""
read -r -p "Do you want to create a Samba Shared folder? [y/N] " response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    echo -e "[global]\nworkgroup = WORKGROUP\nserver string = Samba Server\nnetbios name = $(hostname)\n\n" | sudo tee /etc/samba/smb.conf > /dev/null
    echo -e "[Samba Share]\ncomment = Samba Share\npath = /home/$(whoami)/Samba Share\nwritable = yes\nbrowsable = yes\nguest ok = no" | sudo tee -a /etc/samba/smb.conf > /dev/null
    rm -rf ~/Samba\ Share
    mkdir ~/Samba\ Share
    sudo systemctl restart smb nmb
fi

#sudo sed -i 's/Logo=1/Logo=0/' /etc/libreoffice/sofficerc
echo -e "VISUAL=nvim\nEDITOR=nvim" | sudo tee /etc/environment > /dev/null
grep -qF "set number" /etc/xdg/nvim/sysinit.vim || echo "set number" | sudo tee -a /etc/xdg/nvim/sysinit.vim > /dev/null
grep -qF "set wrap!" /etc/xdg/nvim/sysinit.vim || echo "set wrap!" | sudo tee -a /etc/xdg/nvim/sysinit.vim > /dev/null

echo ""
read -r -p "Do you want to configure git? [y/N] " response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    read -p "Enter your Git name: " git_name
    read -p "Enter your Git email: " git_email
    git config --global user.name "$git_name"
    git config --global user.email "$git_email"
    git config --global init.defaultBranch main
    ssh-keygen -C "$git_email"
    git config --global gpg.format ssh
    git config --global user.signingkey /home/$(whoami)/.ssh/id_ed25519.pub
    git config --global commit.gpgsign true
fi

setup_gnome(){
    echo ""
    sudo cp gnome/gsconnect /etc/ufw/applications.d/
    sudo ufw app update GSConnect
    sudo ufw allow GSConnect

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
    sudo systemctl enable gdm wsdd touchegg
    sudo -u gdm dbus-launch gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
    sudo -u gdm dbus-launch gsettings set org.gnome.desktop.interface icon-theme 'WhiteSur-dark'
    sudo -u gdm dbus-launch gsettings set org.gnome.desktop.interface show-battery-percentage true
    sudo -u gdm dbus-launch gsettings set org.gnome.desktop.peripherals.touchpad speed 0.4
    sudo -u gdm dbus-launch gsettings set org.gnome.desktop.peripherals.touchpad tap-to-click 'true'
    #sudo -u gdm dbus-launch gsettings set org.gnome.desktop.peripherals.touchpad send-events disabled-on-external-mouse
    gsettings set org.gnome.desktop.a11y always-show-universal-access-status true
    gsettings set org.gnome.desktop.datetime automatic-timezone true
    gsettings set org.gnome.desktop.interface clock-format '24h'
    gsettings set org.gnome.desktop.interface clock-show-seconds true
    gsettings set org.gnome.desktop.interface clock-show-weekday true
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
    #gsettings set org.gnome.desktop.interface enable-hot-corners false
    gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark'
    gsettings set org.gnome.desktop.interface icon-theme 'WhiteSur-dark'
    gsettings set org.gnome.desktop.interface show-battery-percentage true
    #gsettings set org.gnome.desktop.peripherals.touchpad send-events disabled-on-external-mouse
    gsettings set org.gnome.desktop.peripherals.touchpad speed 0.4
    gsettings set org.gnome.desktop.peripherals.touchpad tap-to-click 'true'
    gsettings set org.gnome.desktop.privacy old-files-age uint32\ 7
    gsettings set org.gnome.desktop.privacy remember-recent-files false
    gsettings set org.gnome.desktop.privacy remove-old-temp-files true
    gsettings set org.gnome.desktop.privacy remove-old-trash-files true
    gsettings set org.gnome.desktop.sound allow-volume-above-100-percent 'true'
    gsettings set org.gnome.desktop.wm.preferences button-layout ":minimize,maximize,close"
    gsettings set org.gnome.mutter center-new-windows true
    gsettings set org.gtk.Settings.FileChooser sort-directories-first true
    gsettings set org.gtk.gtk4.Settings.FileChooser sort-directories-first true
    xdg-mime default org.gnome.Nautilus.desktop inode/directory

    echo ""
    read -r -p "Do you want to install some extentions that can be necessary? [y/N] " response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        echo ""
        sudo pacman -S --needed --noconfirm gnome-shell-extension-caffeine
        gnome-extensions enable caffeine@patapon.info
        gnome-extensions enable drive-menu@gnome-shell-extensions.gcampax.github.com
        gnome-extensions enable light-style@gnome-shell-extensions.gcampax.github.com

        echo ""
        mkdir -p ~/.local/share/gnome-shell/extensions/
        
        curl -#OL https://github.com/stuarthayhurst/alphabetical-grid-extension/releases/latest/download/AlphabeticalAppGrid@stuarthayhurst.shell-extension.zip
        unzip -oq AlphabeticalAppGrid@stuarthayhurst.shell-extension.zip -d ~/.local/share/gnome-shell/extensions/AlphabeticalAppGrid@stuarthayhurst/
        rm AlphabeticalAppGrid@stuarthayhurst.shell-extension.zip
        glib-compile-schemas ~/.local/share/gnome-shell/extensions/AlphabeticalAppGrid@stuarthayhurst/schemas/
        gnome-extensions enable AlphabeticalAppGrid@stuarthayhurst
        
        curl -#OL https://github.com/GSConnect/gnome-shell-extension-gsconnect/releases/latest/download/gsconnect@andyholmes.github.io.zip
        unzip -oq gsconnect@andyholmes.github.io.zip -d ~/.local/share/gnome-shell/extensions/gsconnect@andyholmes.github.io/
        rm gsconnect@andyholmes.github.io.zip
        gnome-extensions enable gsconnect@andyholmes.github.io
        
        curl -#OL https://github.com/JoseExposito/gnome-shell-extension-x11gestures/releases/latest/download/x11gestures@joseexposito.github.io.zip
        unzip -oq x11gestures@joseexposito.github.io.zip -d ~/.local/share/gnome-shell/extensions/x11gestures@joseexposito.github.io/
        rm x11gestures@joseexposito.github.io.zip
        gnome-extensions enable x11gestures@joseexposito.github.io
    fi
}

setup_kde(){
    echo ""
    sudo cp kdeconnect /etc/ufw/applications.d/
    sudo ufw app update "KDE Connect"
    sudo ufw allow "KDE Connect"

    echo ""
    echo "Installing KDE..."
    echo ""
    sudo pacman -S --needed --noconfirm - < kde
    sudo mkdir -p /etc/sddm.conf.d/
    echo -e "[General]\nNumlock=on\nInputMethod=qtvirtualkeyboard\n\n[Theme]\nCurrent=breeze\nCursorTheme=breeze_cursors" | sudo tee /etc/sddm.conf.d/kde_settings.conf > /dev/null
    sudo sed -i 's/^background=.*/background=\/usr\/share\/wallpapers\/Next\/contents\/images_dark\/5120x2880.png/' /usr/share/sddm/themes/breeze/theme.conf
    echo -e "[Icon Theme]\nInherits=breeze_cursors" | sudo tee /usr/share/icons/default/index.theme > /dev/null
    sudo systemctl enable sddm

    echo -e "[General]\nRememberOpenedTabs=false" | tee ~/.config/dolphinrc > /dev/null
    echo -e "[Keyboard]\nNumLock=0" | tee ~/.config/kcminputrc > /dev/null
    echo -e "[KDE]\nLookAndFeelPackage=org.kde.breezedark.desktop" | tee ~/.config/kdeglobals > /dev/null
    echo -e "[PlasmaViews][Panel 2]\nfloating=0\n\n[PlasmaViews][Panel 2][Defaults]\nthickness=40\n\n" | tee ~/.config/plasmashellrc > /dev/null
    echo -e "[General]\nconfirmLogout=false\nloginMode=emptySession" | tee ~/.config/ksmserverrc > /dev/null

    echo ""
    read -r -p "Do you want to Touchpad configuration? [y/N] " response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        touchpad_id=$(sudo libinput list-devices | grep "Touchpad" | awk '{print substr($0, 19)}')
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
    sudo pacman -S --needed --noconfirm - <xfce/xfce
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
    sudo cp xfce/lightdm-gtk-greeter.conf /etc/lightdm/
    sudo systemctl enable lightdm

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
            setup_gnome
	        break;;
        "2")
            setup_kde
	        break;;
        "3")
            setup_xfce
	        break;;
        "")
	        break;;
	    *)
	    echo -e "\nInvalid choice. Please try again...";;
    esac
done

echo ""
read -r -p "Do you want to install Firefox? [y/N] " response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    sudo pacman -S --needed --noconfirm firefox firefox-ublock-origin
fi

echo ""
read -r -p "Do you want Bluetooth Service? [y/N] " response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    sudo pacman -S --needed --noconfirm bluez
    sudo sed -i 's/^#AutoEnable.*/AutoEnable=false/' /etc/bluetooth/main.conf
    sudo sed -i 's/^AutoEnable.*/AutoEnable=false/' /etc/bluetooth/main.conf
    sudo systemctl enable bluetooth
fi

echo ""
read -r -p "Do you want to install Telegram? [y/N] " response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    sudo pacman -S --needed --noconfirm telegram-desktop
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
        sudo pacman -U --needed --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'
        echo -e "[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist\n" | sudo tee -a /etc/pacman.d/custom > /dev/null
        sudo pacman -Syu

        if [ "$(pactree -r yay || pactree -r yay-bin)" ]; then
            true
        else
            sudo pacman -S --needed --noconfirm yay
        fi
    fi
fi

if [ "$(pactree -r yay || pactree -r yay-bin)" ]; then
    true
else
    sudo pacman -S --needed --noconfirm git base-devel
    git clone https://aur.archlinux.org/yay-bin.git --depth=1
    cd yay-bin
    yes | makepkg -si
    cd ..
    rm -rf yay-bin
fi

yay -S --answerclean A --answerdiff N --removemake --cleanafter --save

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
    warp-cli generate-completions fish | sudo tee /etc/fish/completions/warp-cli.fish > /dev/null
fi

echo ""
read -r -p "Do you want Gaming Stuff? [y/N] " response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    echo ""
    bash -c "$(curl -Ss https://gist.githubusercontent.com/ayu2805/37d0d1740cd7cc8e1a37b2a1c2ecf7a6/raw/archlinux-gaming-setup)"
fi

echo "[FileDialog]
shortcuts=file:, file:///home/ap, file:///home/ap/Desktop, file:///home/ap/Documents, file:///home/ap/Downloads,  file:///home/ap/Music, file:///home/ap/Pictures, file:///home/ap/Videos
sidebarWidth=110
viewMode=Detail" sudo tee ~/.config/QtProject.conf > /dev/null

echo ""
echo "You can now reboot your system"
