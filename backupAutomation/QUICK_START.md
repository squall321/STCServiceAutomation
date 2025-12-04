# 빠른 시작 가이드

서버 설정 백업 및 복구를 5분 안에 시작하기

## 0단계: 백업 설정 (선택)

### 백업 대상 선택 (무엇을 백업할지)

```bash
./configure_backup_targets.sh
```

YAML 기반 대화형 도구로 백업 대상을 선택하세요:
- 필수 항목: /etc, /boot/grub, /root (고정)
- 선택 항목: /opt, /home, /var/www 등
- 위험도와 예상 크기 표시

### 백업 위치 선택 (어디에 백업할지)

여러 디스크가 있다면:

```bash
./select_backup_disk.sh
```

사용 가능한 모든 디스크를 표시하고 백업 위치를 선택하세요.

## 1단계: 도구 설치 (1회만)

### 온라인 PC에서 (인터넷 연결 있는 곳)

```bash
cd /home/koopark/STCServiceAutomation/backupAutomation
./setup_backup_tools.sh --download
```

생성된 `backup_tools.tar.gz`를 USB로 오프라인 서버에 복사

### 오프라인 서버에서

```bash
sudo ./setup_backup_tools.sh --install
```

## 2단계: 첫 백업 생성

```bash
sudo ./backup_system.sh
```

결과:
```
백업 ID: backup_20231204_153045
백업 크기: 118MB (압축 후: 45MB)
소요 시간: 2분 34초
```

## 3단계: 서버 작업 진행

네트워크 설정, 방화벽 규칙, RAID 설정 등 서버 작업을 진행합니다.

## 4단계: 문제 발생 시 복구

```bash
# 백업 목록 확인
sudo ./restore_system.sh --list

# 복구 실행
sudo ./restore_system.sh --backup backup_20231204_153045

# 재부팅 (권장)
sudo reboot
```

## 주요 명령어 치트시트

```bash
# 백업 생성
sudo ./backup_system.sh

# 백업 목록
./backup_manager.sh list

# 백업 정보
./backup_manager.sh info backup_20231204_153045

# 백업 검증
./backup_manager.sh verify backup_20231204_153045

# 복구 (안전 모드)
sudo ./restore_system.sh --backup backup_20231204_153045

# 복구 (강제 모드)
sudo ./restore_system.sh --backup backup_20231204_153045 --mode force

# 오래된 백업 정리
./backup_manager.sh cleanup

# 디스크 사용량
./backup_manager.sh disk
```

## 자주 사용하는 시나리오

### 서버 IP 변경 전 백업

```bash
# 1. 백업
sudo ./backup_system.sh

# 2. IP 변경
sudo nano /etc/network/interfaces
# 또는
sudo nano /etc/netplan/*.yaml

# 3. 네트워크 재시작
sudo systemctl restart networking
# 또는
sudo netplan apply

# 4. 문제 시 복구
sudo ./restore_system.sh --backup backup_YYYYMMDD_HHMMSS
```

### RAID 설정 전 백업

```bash
# 1. 백업
sudo ./backup_system.sh

# 2. RAID 설정
sudo mdadm --create /dev/md0 --level=1 --raid-devices=2 /dev/sda1 /dev/sdb1

# 3. 문제 시 복구
sudo ./restore_system.sh --backup backup_YYYYMMDD_HHMMSS
```

### 방화벽 규칙 변경 전 백업

```bash
# 1. 백업
sudo ./backup_system.sh

# 2. 방화벽 규칙 변경
sudo iptables -A INPUT -p tcp --dport 8080 -j ACCEPT
sudo iptables-save > /etc/iptables/rules.v4

# 3. 문제 시 복구
sudo ./restore_system.sh --backup backup_YYYYMMDD_HHMMSS
```

## 안전 수칙

### ✅ 해야 할 것
- 중요 작업 전 항상 백업
- 복구 전 긴급 백업 생성 (자동)
- 복구 후 재부팅
- 정기적으로 오래된 백업 정리

### ❌ 하지 말아야 할 것
- 복구 중 중단 (Ctrl+C)
- 다른 서버 백업 함부로 복구
- 백업 파일 수동 수정
- 디스크 공간 부족 상태에서 백업

## 문제 해결

### 백업 실패
```bash
# 디스크 공간 확인
df -h

# 오래된 백업 정리
./backup_manager.sh cleanup

# 로그 확인
cat logs/backup_*.log | tail -50
```

### 복구 실패
```bash
# 긴급 백업으로 롤백
sudo ./restore_system.sh --backup emergency_YYYYMMDD_HHMMSS --force

# 로그 확인
cat logs/restore_*.log | tail -50
```

### 네트워크 문제 (복구 후)
```bash
# 네트워크 재시작
sudo systemctl restart networking

# IP 확인
ip addr show

# 라우팅 확인
ip route show
```

## 더 자세한 정보

상세 설명은 [README.md](README.md)를 참고하세요.
