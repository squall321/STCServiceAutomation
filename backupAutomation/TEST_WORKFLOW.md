# 백업 시스템 워크플로우 테스트 가이드

## 0. 새 시스템 완전 초기 설정 (온라인 PC → 오프라인 PC)

이 섹션은 인터넷이 연결된 PC에서 도구를 다운로드하고, USB를 통해 새로운 오프라인 서버에 설치하는 전체 과정을 설명합니다.

### 단계 0-1: 온라인 PC에서 도구 다운로드

```bash
# 1. backupAutomation 디렉토리로 이동
cd /home/koopark/STCServiceAutomation/backupAutomation

# 2. 백업 도구 다운로드 (인터넷 필요)
./setup_backup_tools.sh --download

# 예상 결과:
# ✓ 패키지 다운로드 완료: rsync, pigz, pv, attr, acl, jq, bc, mdadm, lvm2, iproute2
# ✓ backup_tools.tar.gz 생성 완료 (약 5-10MB)
# 📦 생성된 파일: /home/koopark/STCServiceAutomation/backupAutomation/backup_tools.tar.gz
```

**다운로드되는 도구들**:
- `rsync` - 증분 백업 및 파일 동기화
- `pigz` - 병렬 gzip 압축 (빠른 압축)
- `pv` - 진행 상황 표시
- `attr`, `acl` - 파일 속성 및 권한 백업
- `jq` - JSON 파싱 (메타데이터 처리)
- `bc` - 계산기 (크기 계산)
- `mdadm` - RAID 관리
- `lvm2` - LVM 관리
- `iproute2` - 네트워크 설정 백업

### 단계 0-2: USB로 파일 전송

```bash
# 1. USB 마운트 확인
lsblk
# 예: /dev/sdb1 -> /media/usb

# 2. 전체 backupAutomation 디렉토리를 USB로 복사
cp -r /home/koopark/STCServiceAutomation/backupAutomation /media/usb/

# 또는 tar로 압축하여 복사 (권장)
cd /home/koopark/STCServiceAutomation
tar czf /media/usb/backupAutomation.tar.gz backupAutomation/

# 3. 복사 확인
ls -lh /media/usb/backupAutomation.tar.gz
# 예상: 약 10-20MB 파일
```

### 단계 0-3: 오프라인 서버에서 파일 복사

```bash
# 1. USB 마운트 (오프라인 서버에서)
lsblk
sudo mount /dev/sdb1 /mnt

# 2. backupAutomation 디렉토리 복사
cd /home/koopark/STCServiceAutomation
sudo tar xzf /mnt/backupAutomation.tar.gz

# 또는 디렉토리 직접 복사
sudo cp -r /mnt/backupAutomation .

# 3. 권한 설정
cd backupAutomation
chmod +x *.sh

# 4. USB 언마운트
sudo umount /mnt
```

### 단계 0-4: 오프라인 서버에서 도구 설치

```bash
# 1. 백업 도구 설치 (인터넷 없이)
cd /home/koopark/STCServiceAutomation/backupAutomation
sudo ./setup_backup_tools.sh --install

# 예상 결과:
# ✓ backup_tools.tar.gz 압축 해제
# ✓ 패키지 설치: rsync, pigz, pv, attr, acl, jq, bc, mdadm, lvm2, iproute2
# ✓ 모든 도구 설치 완료

# 2. 설치 확인
./setup_backup_tools.sh --check

# 예상 출력:
# ✓ rsync 설치됨: /usr/bin/rsync
# ✓ pigz 설치됨: /usr/bin/pigz
# ✓ pv 설치됨: /usr/bin/pv
# ... (모든 도구 확인)
```

### 단계 0-5: 첫 백업 설정 및 실행

```bash
# 1. 백업 대상 선택 (선택적)
./configure_backup_targets.sh
# 화면에서 백업할 경로 선택 후 'save'

# 2. 백업 위치 선택 (여러 디스크가 있는 경우)
./select_backup_disk.sh
# 여유 공간이 많은 디스크 선택

# 3. 첫 백업 생성
sudo ./backup_system.sh

# 예상 결과:
# 백업 ID: backup_20231204_153045
# 백업 크기: 118MB (압축 후: 45MB)
# 소요 시간: 2분 34초
# 저장 위치: backups/snapshots/backup_20231204_153045.tar.gz

# 4. 백업 확인
./backup_manager.sh list
./backup_manager.sh info backup_20231204_153045
```

### 완전 초기 설정 플로우 다이어그램

```
[온라인 PC]
    │
    ├─ 1. ./setup_backup_tools.sh --download
    │     └─ backup_tools.tar.gz 생성
    │
    ├─ 2. tar czf backupAutomation.tar.gz
    │
    └─ 3. USB로 복사
         │
         └─ backupAutomation.tar.gz → USB

[USB 전송]
    │
    └─ 물리적으로 오프라인 서버로 이동

[오프라인 서버]
    │
    ├─ 1. USB 마운트 및 파일 복사
    │     └─ tar xzf backupAutomation.tar.gz
    │
    ├─ 2. 실행 권한 부여
    │     └─ chmod +x *.sh
    │
    ├─ 3. 백업 도구 설치
    │     └─ sudo ./setup_backup_tools.sh --install
    │
    ├─ 4. 도구 확인
    │     └─ ./setup_backup_tools.sh --check
    │
    ├─ 5. 백업 대상 선택 (선택적)
    │     └─ ./configure_backup_targets.sh
    │
    ├─ 6. 백업 위치 선택 (선택적)
    │     └─ ./select_backup_disk.sh
    │
    └─ 7. 첫 백업 실행
          └─ sudo ./backup_system.sh
```

### 체크리스트: 새 시스템 설정 완료 확인

```bash
# ✅ 1. 모든 스크립트가 실행 가능한가?
ls -l *.sh | grep -c "^-rwxr"

# ✅ 2. 백업 도구가 모두 설치되었는가?
./setup_backup_tools.sh --check

# ✅ 3. 설정 파일이 존재하는가?
ls -la config/backup_paths.conf
ls -la config/backup_policy.conf
ls -la config/backup_targets.yaml

# ✅ 4. 백업 디렉토리가 생성되었는가?
ls -ld backups/

# ✅ 5. 첫 백업이 성공했는가?
./backup_manager.sh list | head -5

# ✅ 6. 백업을 검증할 수 있는가?
./backup_manager.sh verify backup_YYYYMMDD_HHMMSS
```

### 문제 해결: 초기 설정 단계

**문제 1: backup_tools.tar.gz를 찾을 수 없음**
```bash
# 온라인 PC에서 다시 다운로드
cd /home/koopark/STCServiceAutomation/backupAutomation
./setup_backup_tools.sh --download

# 파일 확인
ls -lh backup_tools.tar.gz
```

**문제 2: 패키지 설치 실패 (의존성 문제)**
```bash
# 개별 패키지 수동 설치
cd packages/
sudo dpkg -i *.deb

# 의존성 문제 해결
sudo apt-get -f install  # (인터넷 필요 - 온라인 PC에서 미리 해결)
```

**문제 3: 권한 부족 오류**
```bash
# 모든 스크립트에 실행 권한 부여
chmod +x *.sh

# sudo로 실행 (백업/복구 작업)
sudo ./backup_system.sh
```

---

## 전체 워크플로우 (설치 후)

```
┌─────────────────────────────────────────────────────────────┐
│ 1단계: 백업 대상 설정 (무엇을 백업할지)                      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ↓
              ┌──────────────────────────┐
              │ backup_targets.yaml      │  ← YAML 파일 (모든 가능한 경로 정의)
              └──────────────────────────┘
                              │
                              ↓
              ┌──────────────────────────┐
              │configure_backup_targets.sh│ ← 대화형 선택 도구
              └──────────────────────────┘
                              │
                              ↓
              ┌──────────────────────────┐
              │ backup_paths.conf        │  ← 생성된 설정 파일
              └──────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ 2단계: 백업 위치 설정 (어디에 백업할지)                      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ↓
              ┌──────────────────────────┐
              │ select_backup_disk.sh    │  ← 디스크 선택 도구
              └──────────────────────────┘
                              │
                              ↓
              ┌──────────────────────────┐
              │ backup_policy.conf       │  ← BACKUP_ROOT 업데이트
              └──────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ 3단계: 백업 실행                                             │
└─────────────────────────────────────────────────────────────┘
                              │
                              ↓
              ┌──────────────────────────┐
              │ backup_system.sh         │  ← 백업 스크립트
              └──────────────────────────┘
                              │
                ┌─────────────┴─────────────┐
                │                           │
    ┌───────────▼─────────┐    ┌───────────▼─────────┐
    │ backup_paths.conf  │    │ backup_policy.conf  │
    │ (백업 대상)        │    │ (백업 위치)         │
    └────────────────────┘    └────────────────────┘
                │
                ↓
    ┌────────────────────────┐
    │ backups/snapshots/     │  ← 백업 저장
    │ backup_YYYYMMDD.tar.gz │
    └────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ 4단계: 복구 (필요 시)                                        │
└─────────────────────────────────────────────────────────────┘
                              │
                              ↓
              ┌──────────────────────────┐
              │ restore_system.sh        │  ← 복구 스크립트
              └──────────────────────────┘
```

## 실제 테스트 순서

### 테스트 1: 기본 워크플로우 (최소 설정)

```bash
# 1. 현재 설정 확인
cat config/backup_paths.conf

# 예상 출력: 기본 경로들 (/etc, /boot/grub, /root, /var/spool/cron)

# 2. 백업 실행 (기본 설정으로)
sudo ./backup_system.sh

# 예상 결과:
# - /etc 백업됨
# - /boot/grub 백업됨
# - /root 백업됨
# - /var/spool/cron 백업됨
# - 백업 파일: backups/snapshots/backup_YYYYMMDD_HHMMSS.tar.gz
```

### 테스트 2: YAML 기반 대화형 선택

```bash
# 1. 대화형 도구 실행
./configure_backup_targets.sh

# 2. 화면에서 작업:
#    - 번호 9 입력 (/opt 활성화)
#    - 번호 10 입력 (/usr/local/bin 활성화)
#    - 'save' 입력

# 3. 생성된 설정 확인
cat config/backup_paths.conf

# 예상 출력:
# BACKUP_PATHS=(
#     "/etc"
#     "/boot/grub"
#     "/root"
#     "/var/spool/cron"
#     "/opt"                    # 추가됨
#     "/usr/local/bin"          # 추가됨
#     ...
# )

# 4. 백업 실행
sudo ./backup_system.sh

# 예상 결과: /opt와 /usr/local/bin도 백업됨
```

### 테스트 3: 백업 위치 변경

```bash
# 1. 디스크 확인
df -h

# 2. 디스크 선택 도구 실행
./select_backup_disk.sh

# 3. 화면에서 작업:
#    - 여유 공간 많은 디스크 번호 선택
#    - 경로 확인
#    - 심볼릭 링크 생성 (y)

# 4. 설정 확인
cat config/backup_policy.conf | grep BACKUP_ROOT

# 예상 출력: BACKUP_ROOT="/mnt/data2/system_backups"

# 5. 심볼릭 링크 확인
ls -la backups

# 예상 출력: backups -> /mnt/data2/system_backups

# 6. 백업 실행
sudo ./backup_system.sh

# 예상 결과: /mnt/data2/system_backups에 백업 생성됨
```

### 테스트 4: 복구

```bash
# 1. 백업 목록 확인
./backup_manager.sh list

# 2. 복구 실행
sudo ./restore_system.sh --backup backup_20231204_153045

# 3. 확인 절차:
#    - "yes" 입력
#    - "YES" 입력
#    - 백업 ID 입력

# 4. 재부팅 (권장)
sudo reboot
```

## 설정 파일 체인

```
backup_targets.yaml (YAML 정의)
        │
        ↓ (configure_backup_targets.sh로 파싱)
        │
backup_paths.conf (Bash 배열)
        │
        ↓ (backup_system.sh에서 source)
        │
backup_system.sh (실행)
```

## 각 파일의 역할

### 1. config/backup_targets.yaml
**역할**: 모든 백업 가능한 경로를 카테고리별로 정의
**형식**: YAML
**편집**: 사용자가 직접 편집 가능
**예시**:
```yaml
applications:
  - path: /opt
    description: 애플리케이션
    estimated_size: 100MB-10GB
    risk: medium
    enabled: false
```

### 2. config/backup_paths.conf
**역할**: 실제로 백업할 경로 목록 (Bash 배열)
**형식**: Bash script
**생성**: `configure_backup_targets.sh`가 YAML에서 자동 생성
**사용**: `backup_system.sh`가 source로 로드
**예시**:
```bash
BACKUP_PATHS=(
    "/etc"
    "/boot/grub"
    "/opt"
)
```

### 3. config/backup_policy.conf
**역할**: 백업 정책 (위치, 압축, 보관 기간 등)
**형식**: Bash script
**편집**: `select_backup_disk.sh` 또는 수동 편집
**사용**: `backup_system.sh`가 source로 로드
**예시**:
```bash
BACKUP_ROOT="/mnt/data2/system_backups"
COMPRESSION_ENABLED=true
```

### 4. configure_backup_targets.sh
**역할**: YAML 파싱 + 대화형 선택 + backup_paths.conf 생성
**입력**: backup_targets.yaml
**출력**: backup_paths.conf

### 5. backup_system.sh
**역할**: 실제 백업 실행
**입력**: backup_paths.conf, backup_policy.conf
**출력**: backups/snapshots/backup_*.tar.gz

## 검증 체크리스트

### 설정 체인 검증

```bash
# 1. YAML 파일이 존재하는가?
test -f config/backup_targets.yaml && echo "✓ YAML 존재" || echo "✗ YAML 없음"

# 2. 대화형 도구가 실행 가능한가?
test -x configure_backup_targets.sh && echo "✓ 도구 실행 가능" || echo "✗ 권한 없음"

# 3. backup_paths.conf가 생성되는가?
./configure_backup_targets.sh
# (save 입력)
test -f config/backup_paths.conf && echo "✓ 설정 생성" || echo "✗ 생성 실패"

# 4. backup_system.sh가 설정을 읽는가?
grep "source.*backup_paths.conf" backup_system.sh && echo "✓ 설정 로드" || echo "✗ 로드 안 함"

# 5. 백업이 실제로 생성되는가?
sudo ./backup_system.sh
ls -lh backups/snapshots/*.tar.gz && echo "✓ 백업 생성" || echo "✗ 백업 실패"
```

## 문제 해결

### 문제 1: configure_backup_targets.sh 실행 시 YAML 파일을 찾을 수 없음

**원인**: YAML 파일 경로 오류
**해결**:
```bash
ls -la config/backup_targets.yaml
# 없으면 git에서 복구 또는 재생성
```

### 문제 2: backup_system.sh가 경로를 백업하지 않음

**원인**: backup_paths.conf가 로드되지 않음
**해결**:
```bash
# 설정 파일 확인
cat config/backup_paths.conf

# 백업 스크립트에서 디버그
bash -x backup_system.sh 2>&1 | grep "BACKUP_PATHS"
```

### 문제 3: 선택한 경로가 백업되지 않음

**원인**: EXCLUDE_PATHS에 포함되어 있음
**해결**:
```bash
# 제외 경로 확인
grep EXCLUDE_PATHS config/backup_paths.conf

# 제외 목록에서 제거
nano config/backup_paths.conf
```

## 요약

✅ **올바른 사용 순서**:
1. `./configure_backup_targets.sh` (선택적 - 대상 선택)
2. `./select_backup_disk.sh` (선택적 - 위치 선택)
3. `sudo ./backup_system.sh` (백업 실행)
4. `sudo ./restore_system.sh` (복구 - 필요 시)

✅ **파일 흐름**:
```
YAML → 대화형 도구 → backup_paths.conf → backup_system.sh → 백업 파일
```

✅ **모든 도구가 통합되어 있음**:
- YAML로 정의
- 대화형으로 선택
- Bash로 실행
- 자동으로 백업
