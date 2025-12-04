# 시스템 백업 및 복구 시스템

서버 설정 작업 전후 시스템 상태를 안전하게 백업하고 복구하는 도구

## 주요 특징

- ✅ **시스템 설정 전체 백업**: /etc, 네트워크 설정, RAID/LVM 설정 등
- ✅ **안전한 복구**: 3중 확인, 긴급 백업, 롤백 기능
- ✅ **오프라인 환경 지원**: 인터넷 연결 없이 완전 동작
- ✅ **사용자 데이터 제외**: /home, /opt 등 제외하여 빠른 백업/복구
- ✅ **압축 및 검증**: 자동 압축, 체크섬 검증
- ✅ **상세 로깅**: 모든 작업 기록

## 백업 대상

### 포함 (백업됨)
- `/etc/` - 모든 시스템 설정
- `/boot/grub` - 부트로더 설정
- `/root/` - 루트 사용자 설정 (SSH 키 포함)
- `/var/spool/cron` - crontab
- 시스템 정보 (패키지 목록, 서비스 상태, 네트워크 설정, RAID/LVM 설정 등)

### 제외 (백업 안 됨)
- `/home/` - 사용자 데이터
- `/opt/` - 애플리케이션
- `/var/www/`, `/srv/` - 웹/서비스 데이터
- `/tmp`, `/var/cache` - 임시 파일
- 데이터베이스 데이터

## 백업 설정 커스터마이징

### 백업 대상 선택 (무엇을 백업할지)

**YAML 기반 대화형 도구** (권장):

```bash
./configure_backup_targets.sh
```

이 도구는:
- ✅ YAML 파일에서 백업 가능한 모든 경로 로드
- ✅ 카테고리별로 그룹화 (필수, 시스템, 네트워크, 애플리케이션 등)
- ✅ 각 항목의 예상 크기와 위험도 표시
- ✅ 대화형으로 선택/해제 (번호 입력)
- ✅ 권장 설정 자동 적용
- ✅ 실시간 예상 크기 계산

**기본 설정**:
- 필수 (항상): `/etc`, `/boot/grub`, `/root`, crontab
- 선택 가능: `/opt`, `/home`, `/var/www`, `/usr/local` 등

**수동 편집**:
```bash
# YAML 파일 편집
nano config/backup_targets.yaml

# 또는 직접 설정 파일 편집
nano config/backup_paths.conf
```

### 백업 위치 선택 (어디에 백업할지)

여러 디스크가 있다면 백업 위치를 선택할 수 있습니다.

**자동 디스크 선택** (권장):

```bash
./select_backup_disk.sh
```

이 도구는:
1. 사용 가능한 모든 디스크 표시 (10GB 이상)
2. 디스크 크기, 사용량, 여유 공간 표시
3. 디스크 선택
4. 백업 경로 자동 생성
5. 설정 파일 자동 업데이트
6. 심볼릭 링크 생성 (선택)

**수동 변경**:
```bash
# config/backup_policy.conf 편집
nano config/backup_policy.conf

# BACKUP_ROOT 변경
BACKUP_ROOT="/mnt/backup/system_backups"
```

자세한 내용은 [MULTIPLE_DISKS_GUIDE.md](MULTIPLE_DISKS_GUIDE.md)를 참고하세요.

## 설치 및 준비

### 1. 백업 도구 설치

#### 온라인 PC에서 (인터넷 있는 환경)

```bash
cd /home/koopark/STCServiceAutomation/backupAutomation
./setup_backup_tools.sh --download
```

이 명령은 다음 패키지들을 다운로드합니다:
- rsync (파일 동기화)
- pigz (병렬 압축)
- pv (진행률 표시)
- attr, acl (권한 백업)
- jq (JSON 파싱)
- mdadm (RAID, 선택)
- lvm2 (LVM, 선택)

생성된 `backup_tools.tar.gz`를 오프라인 서버로 복사합니다.

#### 오프라인 서버에서

```bash
# backup_tools.tar.gz 파일을 복사한 후
sudo ./setup_backup_tools.sh --install
```

### 2. 설치 확인

```bash
./setup_backup_tools.sh --check
```

## 사용 방법

### 백업 생성

```bash
# root 권한으로 실행
sudo ./backup_system.sh
```

**백업 과정**:
1. 사전 검사 (디스크 공간, 필수 도구)
2. 시스템 정보 수집 (패키지, 서비스, 네트워크, RAID, LVM)
3. 파일 백업 (/etc, /boot/grub, /root, crontab)
4. 압축 (pigz 병렬 압축)
5. 무결성 검사 (sha256 체크섬)
6. 메타데이터 생성

**소요 시간**: 약 3-10분 (시스템 크기에 따라)
**백업 크기**: 약 50-200MB (압축 후)

### 백업 목록 확인

```bash
./backup_manager.sh list
```

출력 예시:
```
백업 ID                   날짜                  크기       소요 시간      상태
--------------------------------------------------------------------------------------
backup_20231204_153045   2023-12-04 15:30     118MB      2m 34s        ✓
backup_20231203_080000   2023-12-03 08:00     115MB      2m 18s        ✓
```

### 백업 상세 정보

```bash
./backup_manager.sh info backup_20231204_153045
```

### 백업 복구

⚠️ **중요**: 복구는 시스템 파일을 덮어쓰므로 매우 신중하게!

```bash
# 백업 목록 확인
sudo ./restore_system.sh --list

# 복구 실행 (안전 모드)
sudo ./restore_system.sh --backup backup_20231204_153045
```

**복구 과정**:
1. 백업 검증 (무결성, 호환성)
2. 긴급 백업 생성 (현재 상태 백업)
3. 3중 사용자 확인
4. 서비스 중지
5. 파일 복구
6. 권한 복구
7. 서비스 재시작
8. 복구 검증

**복구 모드**:
- `--mode safe`: 기존 파일 유지 (기본값, 권장)
- `--mode force`: 모든 파일 덮어쓰기

### 백업 관리

```bash
# 백업 검증
./backup_manager.sh verify backup_20231204_153045

# 백업 삭제
./backup_manager.sh delete backup_20231204_153045

# 오래된 백업 정리
./backup_manager.sh cleanup

# 디스크 사용량
./backup_manager.sh disk
```

## 사용 시나리오

### 시나리오 1: 서버 설정 변경 전 백업

```bash
# 1. 백업 생성
sudo ./backup_system.sh

# 출력:
# 백업 ID: backup_20231204_153045
# 백업 크기: 118MB (압축 후: 45MB)
# 소요 시간: 2분 34초

# 2. 서버 설정 변경 작업 수행
# ... (네트워크 설정, 방화벽 규칙, RAID 설정 등)

# 3. 문제가 없으면 완료!
```

### 시나리오 2: 설정 변경 후 문제 발생 - 복구

```bash
# 문제 발생! 이전 상태로 복구 필요

# 1. 백업 목록 확인
sudo ./restore_system.sh --list

# 2. 복구 실행
sudo ./restore_system.sh --backup backup_20231204_153045

# 3. 확인 절차
# - "yes" 입력
# - "YES" 입력
# - 백업 ID 입력

# 4. 복구 완료 후 재부팅 (권장)
sudo reboot
```

### 시나리오 3: 정기 백업 (cron)

```bash
# crontab 편집
sudo crontab -e

# 매일 새벽 2시에 백업
0 2 * * * /home/koopark/STCServiceAutomation/backupAutomation/backup_system.sh

# 매주 일요일 새벽 3시에 오래된 백업 정리
0 3 * * 0 /home/koopark/STCServiceAutomation/backupAutomation/backup_manager.sh cleanup
```

## 디렉토리 구조

```
backupAutomation/
├── backup_system.sh          # 백업 스크립트
├── restore_system.sh         # 복구 스크립트
├── setup_backup_tools.sh     # 도구 설치 스크립트
├── backup_manager.sh         # 백업 관리 스크립트
├── config/
│   ├── backup_paths.conf     # 백업 경로 설정
│   └── backup_policy.conf    # 백업 정책 설정
├── packages/                 # 백업 도구 패키지
│   └── *.deb
├── backups/
│   ├── snapshots/            # 백업 파일
│   │   ├── backup_YYYYMMDD_HHMMSS.tar.gz
│   │   └── backup_YYYYMMDD_HHMMSS/
│   └── metadata/             # 백업 메타데이터
│       └── backup_YYYYMMDD_HHMMSS.json
└── logs/                     # 로그 파일
    ├── backup_YYYYMMDD_HHMMSS.log
    └── restore_YYYYMMDD_HHMMSS.log
```

## 백업 메타데이터

각 백업마다 JSON 메타데이터가 생성됩니다:

```json
{
  "backup_id": "backup_20231204_153045",
  "timestamp": "2023-12-04 15:30:45",
  "hostname": "server01",
  "os_version": "Ubuntu 22.04.3 LTS",
  "kernel": "5.15.0-91-generic",
  "type": "system_config",
  "size_bytes": 123829120,
  "duration_seconds": 154,
  "file_count": 2847,
  "compressed": true,
  "packages": {
    "count": 1523
  }
}
```

## 안전 장치

### 백업 시
- ✅ Bash 버전 확인 (4.0+)
- ✅ Root 권한 확인
- ✅ 필수 도구 확인
- ✅ 디스크 공간 확인 (예상 크기의 2배 이상)
- ✅ 백업 후 무결성 검사
- ✅ 체크섬 생성 (sha256)

### 복구 시
- ✅ 백업 무결성 검사
- ✅ 호스트명 확인 (다른 서버 백업 복구 방지)
- ✅ OS/커널 버전 호환성 경고
- ✅ 긴급 백업 생성 (복구 전 현재 상태 백업)
- ✅ 3중 사용자 확인
- ✅ 복구 후 검증
- ✅ 롤백 기능

## 복구 실패 시 대처

만약 복구 중 문제가 발생하면:

### 1. 긴급 백업으로 롤백

```bash
# 복구 실패 시 자동 생성된 긴급 백업 확인
./backup_manager.sh list | grep emergency

# 긴급 백업으로 롤백
sudo ./restore_system.sh --backup emergency_20231204_155000 --force
```

### 2. 개별 파일 복구

```bash
# 백업에서 특정 파일만 추출
tar -xzf backups/snapshots/backup_20231204_153045.tar.gz \
    backup_20231204_153045/files/etc/network/interfaces

# 파일 복사
sudo cp backup_20231204_153045/files/etc/network/interfaces /etc/network/
```

### 3. 복구 로그 확인

```bash
# 복구 로그 확인
cat logs/restore_20231204_155000.log

# 오류 찾기
grep ERROR logs/restore_20231204_155000.log
```

## 설정 커스터마이징

### 백업 경로 변경

`config/backup_paths.conf` 편집:

```bash
# 추가 경로 백업
BACKUP_PATHS+=(
    "/etc/custom_app"
    "/usr/local/custom"
)

# 추가 제외 경로
EXCLUDE_PATHS+=(
    "/etc/large_cache"
)
```

### 백업 정책 변경

`config/backup_policy.conf` 편집:

```bash
# 보관 기간 변경
KEEP_MINIMUM=5              # 최소 5개 보관
MAX_BACKUP_AGE_DAYS=180     # 180일 후 삭제

# 압축 설정
COMPRESSION_LEVEL=9         # 최대 압축
```

## 문제 해결

### Q: "디스크 공간이 부족합니다" 오류

**A**: 오래된 백업을 정리하세요:
```bash
./backup_manager.sh cleanup
```

### Q: "pigz를 찾을 수 없습니다" 경고

**A**: pigz 없이도 동작하지만, 설치하면 더 빠릅니다:
```bash
sudo ./setup_backup_tools.sh --install
```

### Q: 복구 후 네트워크가 안 됩니다

**A**: 네트워크 설정을 확인하세요:
```bash
# 네트워크 인터페이스 확인
ip addr show

# 네트워크 재시작
sudo systemctl restart networking

# netplan 사용 시
sudo netplan apply
```

### Q: 복구 후 서비스가 시작 안 됩니다

**A**: 서비스 상태를 확인하세요:
```bash
# 서비스 상태 확인
sudo systemctl status nginx

# 로그 확인
sudo journalctl -u nginx -n 50

# 수동 시작
sudo systemctl start nginx
```

## 주의사항

### ⚠️ 반드시 지켜야 할 것

1. **백업 전에**:
   - 충분한 디스크 공간 확인
   - 중요한 작업 중이 아닌지 확인
   - 백업 소요 시간 고려 (약 5-10분)

2. **복구 전에**:
   - 반드시 root 권한으로 실행
   - 호스트명 확인 (다른 서버 백업 복구 주의)
   - 긴급 백업이 자동 생성되는지 확인
   - 복구 후 재부팅 권장

3. **복구 후에**:
   - 주요 서비스 동작 확인
   - 네트워크 연결 확인
   - 로그 확인
   - **시스템 재부팅 권장**

### ❌ 하지 말아야 할 것

1. 복구 중 중단하지 마세요 (Ctrl+C)
2. 다른 서버의 백업을 함부로 복구하지 마세요
3. 긴급 백업 없이 강제 복구하지 마세요
4. 백업 파일을 수동으로 수정하지 마세요

## 시스템 요구사항

- **OS**: Ubuntu 18.04+, Debian 10+, CentOS 8+ (systemd 기반)
- **Bash**: 4.0 이상
- **디스크 공간**: 백업 크기의 2배 + 10GB 이상
- **권한**: root (sudo)
- **필수 패키지**: rsync, tar, gzip
- **선택 패키지**: pigz, pv, jq, mdadm, lvm2

## 라이선스

이 도구는 서버 관리 자동화를 위해 제작되었습니다.

## 지원

문제가 발생하면:
1. 로그 파일 확인 (`logs/` 디렉토리)
2. 백업 무결성 검사 (`backup_manager.sh verify`)
3. 긴급 백업으로 롤백

## 변경 이력

### v1.0 (2023-12-04)
- 초기 릴리스
- 시스템 설정 백업/복구 기능
- 오프라인 환경 지원
- 안전 장치 구현 (3중 확인, 긴급 백업, 롤백)
