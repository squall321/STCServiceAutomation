# GNOME VNC + GPU 가속 자동화 설정 가이드

## 개요
이 스크립트는 ubuntu-desktop-minimal 환경에서 GNOME 데스크톱을 VNC로 접속할 수 있도록 설정하고, VirtualGL을 통한 GPU 가속까지 자동으로 구성합니다.

## 주요 개선사항 (원본 대비)

### 1. 패키지 설치 강화
- `dbus-x11`: GNOME 세션에 필수적인 D-Bus 지원
- `tigervnc-xorg-extension`: X 서버 확장 지원
- `gnome-settings-daemon`, `gnome-control-center`: 완전한 GNOME 환경
- VirtualGL 자동 다운로드 (저장소에 없을 경우)

### 2. 향상된 xstartup 스크립트
```bash
# 주요 개선사항:
- dbus-launch 자동 처리
- VirtualGL 라이브러리 경로 설정
- metacity 대체 윈도우 매니저 (GNOME 실패 시)
- 올바른 환경 변수 설정
```

### 3. systemd 서비스 개선
- `Type=simple`로 변경 (더 안정적)
- 재시작 정책 추가 (`Restart=on-failure`)
- 깔끔한 시작/종료 처리

### 4. VirtualGL 자동 구성
- vglusers, video, render 그룹 자동 추가
- `vglserver_config` 자동 실행
- GPU 테스트용 헬퍼 스크립트 생성

### 5. 추가 기능
- 방화벽 자동 구성 (UFW)
- 데스크톱 바로가기 생성 (GPU 테스트용)
- 상세한 로깅 및 오류 처리
- 연결 테스트 자동 수행

## 사용 방법

### 기본 사용 (기본 비밀번호)
```bash
sudo ./setup_gnome_vnc_gpu_improved.sh username
```

### 커스텀 비밀번호 지정
```bash
sudo ./setup_gnome_vnc_gpu_improved.sh username "MySecurePassword123"
```

### SUDO_USER 자동 감지
```bash
sudo ./setup_gnome_vnc_gpu_improved.sh
```

## 설치 후 확인

### 1. VNC 서비스 상태 확인
```bash
systemctl status vncserver@1
```

### 2. 포트 확인
```bash
ss -tln | grep 5901
# 또는
netstat -tln | grep 5901
```

### 3. 로그 확인
```bash
# 시스템 로그
tail -f /var/log/setup_gnome_vnc_gpu.log

# VNC 서버 로그
tail -f ~/.vnc/$(hostname):1.log

# systemd 로그
journalctl -u vncserver@1 -f
```

### 4. GPU 가속 테스트
VNC에 접속한 후:
```bash
# GPU 정보 확인
vglrun glxinfo | grep OpenGL

# GPU 가속 테스트
vglrun glxgears

# 또는 헬퍼 스크립트 사용
~/bin/vgl glxgears
```

## VNC 클라이언트 연결

### 직접 연결
```
서버주소:5901
또는
서버주소::5901
```

### SSH 터널링 (권장)
```bash
# 로컬 머신에서
ssh -L 5901:localhost:5901 username@서버주소

# VNC 클라이언트에서
localhost:5901
```

## 문제 해결

### GNOME이 시작되지 않을 때

1. **xstartup 로그 확인**
   ```bash
   cat ~/.vnc/$(hostname):1.log
   ```

2. **dbus 문제**
   ```bash
   # xstartup에서 dbus가 제대로 시작되는지 확인
   ps aux | grep dbus-daemon
   ```

3. **수동으로 GNOME 시작 테스트**
   ```bash
   export DISPLAY=:1
   gnome-session --session=ubuntu &
   ```

### GPU 가속이 작동하지 않을 때

1. **그룹 확인**
   ```bash
   groups
   # video, vglusers, render이 있어야 함
   ```

2. **로그아웃 후 재로그인**
   ```bash
   # 그룹 변경사항 적용을 위해
   pkill -u username
   # 또는 재부팅
   sudo reboot
   ```

3. **VirtualGL 설치 확인**
   ```bash
   which vglrun
   vglrun glxinfo
   ```

4. **GPU 드라이버 확인**
   ```bash
   nvidia-smi  # NVIDIA GPU인 경우
   glxinfo | grep "direct rendering"
   ```

### VNC 서비스가 시작되지 않을 때

1. **기존 VNC 프로세스 종료**
   ```bash
   vncserver -kill :1
   pkill -u username Xvnc
   ```

2. **수동 시작 테스트**
   ```bash
   su - username
   vncserver :1 -localhost no -geometry 1920x1080
   ```

3. **권한 확인**
   ```bash
   ls -la ~/.vnc/
   # passwd 파일이 있고 읽기 가능해야 함
   ```

### 해상도 변경

1. **VNC config 수정**
   ```bash
   vim ~/.vnc/config
   # geometry=1920x1080 을 원하는 해상도로 변경
   ```

2. **서비스 재시작**
   ```bash
   sudo systemctl restart vncserver@1
   ```

### 여러 디스플레이 실행

다른 포트에 추가 VNC 서버 실행:
```bash
# :2 디스플레이 (포트 5902)
sudo systemctl enable vncserver@2
sudo systemctl start vncserver@2

# :3 디스플레이 (포트 5903)
sudo systemctl enable vncserver@3
sudo systemctl start vncserver@3
```

## 보안 권장사항

### 1. VNC 비밀번호 변경
```bash
vncpasswd
```

### 2. SSH 터널링 사용
직접 VNC 포트를 외부에 노출하지 말고 SSH 터널을 통해 연결

### 3. 방화벽 설정
```bash
# VNC 포트를 특정 IP에서만 허용
sudo ufw allow from 192.168.1.0/24 to any port 5901
```

### 4. localhost만 허용 (SSH 터널 전용)
`~/.vnc/config`에서:
```
localhost=yes
```

그리고 systemd 서비스의 `-localhost no`를 `-localhost yes`로 변경

## 성능 최적화

### 1. 압축 설정
VNC 클라이언트에서 압축 레벨 조정 (낮은 대역폭 환경)

### 2. 색상 깊이 조정
```bash
# ~/.vnc/config
depth=16  # 24에서 16으로 변경하면 대역폭 절약
```

### 3. JPEG 품질 조정
VNC 클라이언트의 JPEG 압축 품질 설정

## 제거 방법

완전히 제거하려면:
```bash
# 서비스 중지 및 비활성화
sudo systemctl stop vncserver@1
sudo systemctl disable vncserver@1

# 서비스 파일 삭제
sudo rm /etc/systemd/system/vncserver@.service
sudo systemctl daemon-reload

# VNC 설정 삭제
rm -rf ~/.vnc

# 패키지 제거 (선택사항)
sudo apt remove tigervnc-standalone-server tigervnc-common virtualgl
```

## 추가 정보

### VNC 포트 매핑
- Display :1 = Port 5901
- Display :2 = Port 5902
- Display :N = Port 5900+N

### 유용한 명령어
```bash
# 실행 중인 VNC 세션 확인
vncserver -list

# 특정 디스플레이 종료
vncserver -kill :1

# VNC 프로세스 확인
ps aux | grep Xvnc

# 네트워크 연결 확인
netstat -tlnp | grep vnc
```

## 알려진 제한사항

1. Wayland는 지원하지 않음 (X11만 지원)
2. 일부 GNOME 확장 기능이 VNC에서 작동하지 않을 수 있음
3. GPU 가속은 OpenGL 애플리케이션에만 적용됨
4. 3D 가속 성능은 네트워크 대역폭에 영향을 받음

## 라이선스
이 스크립트는 자유롭게 사용, 수정, 배포할 수 있습니다.

## 기여
개선사항이나 버그 리포트는 환영합니다!