echo "=== graid 설치시 시스템 문제 발생 유발 해결 스크립트 ==="

echo "=== 화면 잠금 비활성화 ==="
gsettings set org.gnome.desktop.screensaver lock-enabled false
gsettings set org.gnome.desktop.screensaver idle-activation-enabled false
gsettings set org.gnome.desktop.session idle-delay 0

echo "=== GPU 설정 ==="
sudo nvidia-xconfig --query-gpu-info
sudo nvidia-xconfig --enable-all-gpus
sudo systemctl restart gdm3


echo "=== Wayland 비활성화 ==="

sudo sed -i 's/#WaylandEnable=false/WaylandEnable=false/' /etc/gdm3/custom.conf
sudo systemctl restart gdm3


echo "=== dconf 설정 ==="

sudo mkdir -p /etc/dconf/db/local.d

echo "
[org/gnome/desktop/lockdown]
disable-lock-screen=false
" | sudo tee /etc/dconf/db/local.d/00-remote

sudo dconf update

echo "=== gdm 설정 ==="
sudo -u gdm dbus-launch gsettings set org.gnome.desktop.lockdown disable-lock-screen false


echo "=== Device 입력 및 Video 출력 권한 수정 ==="

sudo usermod -aG input $USER
sudo usermod -aG video $USER
sudo usermod -aG tty $USER
sudo usermod -aG uinput $USER
sudo reboot