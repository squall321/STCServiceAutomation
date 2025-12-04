# 서버 백업 및 복구 시스템 설계 계획

## 프로젝트 개요

서버 설정 작업 중 문제 발생 시 이전 상태로 안전하게 복구할 수 있는 오프라인 백업/복구 시스템 구축

### 목표
- 서버 설정 작업 전 전체 시스템 스냅샷 생성
- 문제 발생 시 빠른 롤백
- 오프라인 환경에서 완전 동작
- 사용자 친화적 인터페이스

### 위험 요소
- 잘못된 복구는 시스템을 더 망가뜨릴 수 있음
- 부분 복구 시 의존성 문제 발생 가능
- 디스크 공간 부족으로 백업 실패 가능
- 복구 중 중단 시 시스템 불일치 상태

---

## 시스템 아키텍처

```
STCServiceAutomation/
├── backupAutomation/
│   ├── backup_system.sh           # 메인 백업 스크립트
│   ├── restore_system.sh          # 메인 복구 스크립트
│   ├── setup_backup_tools.sh      # 백업 도구 오프라인 설치
│   ├── backup_manager.sh          # 백업 관리 (목록, 삭제, 검증)
│   ├── config/
│   │   ├── backup_paths.conf     # 백업 대상 경로 설정
│   │   ├── exclude_patterns.conf # 제외 패턴
│   │   └── backup_policy.conf    # 백업 정책 (보관 기간 등)
│   ├── packages/
│   │   ├── rsync_*.deb           # rsync 패키지
│   │   ├── timeshift_*.deb       # timeshift 패키지 (선택)
│   │   ├── pigz_*.deb            # 병렬 압축 도구
│   │   └── pv_*.deb              # 진행률 표시 도구
│   ├── backups/                   # 백업 저장소 (기본 위치)
│   │   ├── snapshots/            # 전체 스냅샷
│   │   ├── configs/              # 설정 파일만
│   │   └── metadata/             # 백업 메타데이터
│   ├── logs/                      # 백업/복구 로그
│   └── scripts/
│       ├── pre_backup_check.sh   # 백업 전 점검
│       ├── post_backup_verify.sh # 백업 후 검증
│       ├── pre_restore_check.sh  # 복구 전 점검
│       └── integrity_check.sh    # 백업 무결성 검사
└── restore_packages.sh           # 기존 패키지 복원 (이미 완성)
```

---

## 백업 전략

### 백업 레벨 (3단계)

#### 레벨 1: 최소 백업 (빠름, 5-10분)
**대상**:
- /etc/ (전체 시스템 설정)
- /root/.bashrc, .profile 등
- /home/*/.bashrc, .ssh, .config (사용자 설정)
- /var/spool/cron/ (crontab)
- apt 패키지 목록
- 설치된 서비스 목록

**용도**: 설정 파일만 빠르게 백업/복구

#### 레벨 2: 중간 백업 (보통, 30분-1시간)
**레벨 1 +**:
- /opt/ (사용자 설치 소프트웨어)
- /usr/local/ (로컬 설치 프로그램)
- /var/www/ (웹 서버 데이터)
- /srv/ (서비스 데이터)
- 데이터베이스 덤프

**용도**: 애플리케이션 포함 백업

#### 레벨 3: 전체 백업 (느림, 몇 시간)
**레벨 2 +**:
- / 전체 (제외 목록 제외)
- rsync를 사용한 증분 백업

**제외 목록**:
- /proc, /sys, /dev, /run, /tmp
- /mnt, /media
- /lost+found
- 백업 저장 경로 자체
- /var/cache, /var/tmp

**용도**: 완전 복구 가능한 시스템 이미지

### 백업 방식 비교

| 방식 | 장점 | 단점 | 추천 용도 |
|------|------|------|-----------|
| **rsync** | 증분 백업, 빠름, 유연함 | 파일 시스템 메타데이터 일부 손실 가능 | 일반 백업 |
| **tar + pigz** | 압축률 높음, 이식성 좋음 | 전체 백업만 가능 | 레벨 1, 2 |
| **timeshift** | GUI 있음, 자동화 쉬움 | 설정 복잡, 의존성 많음 | 데스크톱 환경 |
| **dd + gzip** | 완벽한 복제 | 매우 느림, 용량 큼 | 전체 디스크 복제 |

**선택**: **rsync + tar** 조합 (유연성과 안정성)

---

## 백업 도구 패키지

### 필수 패키지
```
rsync               # 파일 동기화 및 증분 백업
tar                 # 아카이브 생성 (기본 설치되어 있음)
pigz                # 병렬 gzip (압축 속도 향상)
pv                  # 파이프 뷰어 (진행률 표시)
attr                # 확장 속성 백업
acl                 # ACL 권한 백업
lvm2                # LVM 스냅샷 (선택)
```

### 선택 패키지
```
timeshift           # GUI 백업 도구 (선택)
borgbackup          # 중복 제거 백업 (고급)
restic              # 암호화 백업 (고급)
```

**권장**: rsync + pigz + pv + attr + acl

---

## 백업 메타데이터

각 백업마다 메타데이터 저장:

```json
{
  "backup_id": "backup_20231204_153045",
  "timestamp": "2023-12-04 15:30:45",
  "hostname": "server01",
  "level": 1,
  "type": "config_only",
  "size_bytes": 125829120,
  "duration_seconds": 180,
  "file_count": 2847,
  "integrity": {
    "sha256": "abc123...",
    "verified": true
  },
  "disk_usage": {
    "before": "45%",
    "after": "48%"
  },
  "packages": {
    "count": 1523,
    "list_file": "packages.list"
  },
  "services": {
    "running": ["ssh", "nginx", "docker"],
    "enabled": ["ssh", "nginx", "docker", "postgresql"]
  },
  "git_info": {
    "branch": "main",
    "commit": "abc123...",
    "dirty": false
  },
  "notes": "Pre-deployment backup before updating nginx config"
}
```

---

## backup_system.sh 주요 기능

### 1. 백업 전 점검 (Pre-flight Check)

```bash
check_prerequisites() {
    # Bash 버전
    # 필요 도구 설치 여부
    # 백업 경로 쓰기 권한
    # 디스크 공간 (최소 예상 크기의 2배)
    # 현재 디스크 I/O 부하
    # 실행 중인 백업 프로세스 확인
}

check_disk_space() {
    # 예상 백업 크기 계산
    # 여유 공간 확인
    # 압축률 고려 (평균 30-50% 압축)
    # 경고: 디스크 사용률 90% 이상 시 중단
}

check_system_health() {
    # CPU 부하
    # 메모리 사용률
    # 디스크 I/O 대기
    # 경고 발행 (계속 진행 여부 확인)
}
```

### 2. 백업 실행

```bash
perform_backup() {
    # 백업 ID 생성
    # 메타데이터 초기화
    # 백업 디렉토리 생성

    # 서비스 일시 중지 (선택)
    # - 데이터베이스 쿼럼
    # - 웹 서버 (선택)

    # 백업 실행 (레벨별)
    case $BACKUP_LEVEL in
        1) backup_configs ;;
        2) backup_with_apps ;;
        3) backup_full_system ;;
    esac

    # 패키지 목록 저장
    # 서비스 상태 저장
    # 커널 정보 저장
    # 네트워크 설정 저장

    # 압축 (선택)
    # 무결성 검사 (sha256sum)
    # 메타데이터 완성

    # 서비스 재시작
}
```

### 3. 증분 백업 (rsync)

```bash
incremental_backup() {
    # 이전 백업 찾기
    # rsync --link-dest 사용
    # 변경된 파일만 복사
    # 변경되지 않은 파일은 하드링크

    # 장점:
    # - 디스크 공간 절약
    # - 빠른 백업
    # - 각 백업은 독립적으로 접근 가능
}
```

### 4. 백업 검증

```bash
verify_backup() {
    # 파일 개수 확인
    # 주요 파일 존재 확인 (/etc/passwd, /etc/fstab 등)
    # 압축 파일 무결성 검사
    # sha256 체크섬 비교
    # 메타데이터 일관성 검사
}
```

### 5. 백업 정리 (Retention Policy)

```bash
cleanup_old_backups() {
    # 정책:
    # - 최근 7일: 모든 백업 보관
    # - 최근 30일: 주간 백업만 보관
    # - 30일 이후: 월간 백업만 보관
    # - 90일 이후: 삭제 (설정 가능)

    # 최소 보관:
    # - 최신 3개는 항상 보관

    # 삭제 전 확인
}
```

---

## restore_system.sh 주요 기능

### 1. 복구 전 점검 (Critical!)

```bash
pre_restore_check() {
    # 경고 메시지 출력 (크고 무섭게!)
    # 현재 시스템 백업 권장
    # 백업 무결성 검사
    # 백업 메타데이터 읽기
    # 호스트명 확인 (다른 서버 백업 복구 방지)
    # 디스크 공간 확인

    # 사용자 확인 3회 (실수 방지)
    # "정말로 복구하시겠습니까? (yes 입력): "
}

check_backup_compatibility() {
    # OS 버전 확인
    # 커널 버전 확인
    # 파일 시스템 타입 확인
    # 경고: 다른 환경에서 복구 시도 시
}
```

### 2. 복구 모드 선택

```bash
# 모드 1: 안전 복구 (권장)
# - /etc/를 임시 위치로 백업
# - 파일별로 복구 (충돌 시 확인)
# - 실패 시 롤백 가능

# 모드 2: 선택적 복구
# - 복구할 디렉토리 선택
# - /etc, /home, /opt 등 개별 선택
# - 대화형 모드

# 모드 3: 강제 전체 복구 (위험!)
# - 모든 파일 덮어쓰기
# - 확인 절차 강화
# - 복구 불가능 경고
```

### 3. 복구 실행

```bash
perform_restore() {
    # 현재 상태 긴급 백업
    create_emergency_backup

    # 복구 로그 시작

    # 서비스 중지
    stop_services

    # 파일 복구 (우선순위별)
    # 1. /etc/fstab, /etc/network/ (시스템 필수)
    # 2. /etc/ 나머지
    # 3. /home/
    # 4. /opt/, /usr/local/
    # 5. 기타

    # 권한 및 소유권 복구
    restore_permissions

    # ACL 복구
    restore_acl

    # 패키지 확인 (선택)
    check_packages

    # 서비스 재시작
    restart_services

    # 검증
    verify_restore
}
```

### 4. 점진적 복구 (안전)

```bash
progressive_restore() {
    # 단계 1: 설정 파일만 복구
    restore_configs
    verify_step1
    read -p "계속하시겠습니까?"

    # 단계 2: 사용자 데이터 복구
    restore_user_data
    verify_step2
    read -p "계속하시겠습니까?"

    # 단계 3: 애플리케이션 데이터 복구
    restore_app_data
    verify_step3

    # 각 단계마다 확인 및 롤백 가능
}
```

### 5. 복구 실패 시 롤백

```bash
rollback_restore() {
    # 긴급 백업에서 복구
    # 서비스 재시작
    # 로그 저장
    # 실패 원인 분석 정보 제공
}
```

---

## setup_backup_tools.sh 설계

### 기능
1. 백업 도구 패키지 다운로드 (온라인 환경)
2. 오프라인 설치
3. 도구 검증

```bash
# 온라인 PC에서 실행
download_backup_tools() {
    PACKAGES=(
        rsync
        pigz
        pv
        attr
        acl
    )

    mkdir -p packages
    cd packages

    for pkg in "${PACKAGES[@]}"; do
        apt-get download $pkg
        # 의존성도 다운로드
        apt-cache depends $pkg | grep "Depends:" | \
            awk '{print $2}' | xargs apt-get download
    done

    tar -czf backup_tools.tar.gz *.deb
}

# 오프라인 PC에서 실행
install_backup_tools() {
    tar -xzf backup_tools.tar.gz
    sudo dpkg -i *.deb
    sudo apt-get install -f -y  # 의존성 해결
}
```

---

## backup_manager.sh 관리 기능

### 백업 목록 조회

```bash
list_backups() {
    echo "ID | 날짜 | 레벨 | 크기 | 상태"
    for backup in backups/metadata/*.json; do
        # 메타데이터 파싱
        # 테이블 형식 출력
    done
}
```

### 백업 상세 정보

```bash
show_backup_info() {
    # 메타데이터 전체 출력
    # 포함된 파일 목록
    # 복구 가능 여부
}
```

### 백업 삭제

```bash
delete_backup() {
    # 안전 확인
    # 증분 백업 체인 확인
    # 다른 백업이 의존하는지 확인
    # 삭제 실행
}
```

### 백업 무결성 검사

```bash
verify_backup_integrity() {
    # sha256 체크섬 검증
    # 압축 파일 테스트
    # 메타데이터 일관성
    # 주요 파일 존재 확인
}
```

### 백업 비교

```bash
compare_backups() {
    # 두 백업 간 차이점 표시
    # 변경된 파일 목록
    # 추가/삭제된 파일
    # 패키지 차이
}
```

---

## 설정 파일 상세

### backup_paths.conf

```bash
# 레벨 1: 필수 설정 파일
LEVEL1_PATHS=(
    "/etc"
    "/root"
    "/home/*/.ssh"
    "/home/*/.config"
    "/home/*/.bashrc"
    "/home/*/.profile"
    "/var/spool/cron"
)

# 레벨 2: 애플리케이션 포함
LEVEL2_PATHS=(
    "/opt"
    "/usr/local"
    "/var/www"
    "/srv"
)

# 레벨 3: 전체 (제외 목록 제외)
LEVEL3_PATHS=(
    "/"
)
```

### exclude_patterns.conf

```bash
# 제외할 경로
EXCLUDE_PATHS=(
    "/proc"
    "/sys"
    "/dev"
    "/run"
    "/tmp"
    "/var/tmp"
    "/var/cache"
    "/mnt"
    "/media"
    "/lost+found"
    "*.sock"
    "*.pid"
    "/swapfile"
)

# 제외할 파일 패턴
EXCLUDE_PATTERNS=(
    "*.log"
    "*.cache"
    "*.tmp"
    "*~"
    ".DS_Store"
)
```

### backup_policy.conf

```bash
# 백업 보관 정책
KEEP_DAILY=7        # 최근 7일간 일일 백업
KEEP_WEEKLY=4       # 최근 4주간 주간 백업
KEEP_MONTHLY=3      # 최근 3개월간 월간 백업
KEEP_MINIMUM=3      # 최소 보관 백업 개수

# 백업 경로
BACKUP_ROOT="/home/koopark/STCServiceAutomation/backupAutomation/backups"
BACKUP_EXTERNAL="/mnt/external/backups"  # 선택적 외부 저장소

# 압축 설정
COMPRESSION_ENABLED=true
COMPRESSION_LEVEL=6  # 1-9 (9가 최대 압축)
USE_PIGZ=true        # 병렬 압축

# 알림 설정
EMAIL_NOTIFICATION=false
EMAIL_ADDRESS="admin@example.com"

# 안전 설정
REQUIRE_CONFIRMATION=true     # 복구 시 확인 필수
EMERGENCY_BACKUP=true         # 복구 전 긴급 백업
MAX_BACKUP_AGE_DAYS=90        # 백업 최대 보관 기간
```

---

## 로깅 시스템

### 로그 레벨
```
DEBUG: 상세 디버그 정보
INFO: 일반 정보
WARNING: 경고 (계속 진행)
ERROR: 오류 (작업 실패)
CRITICAL: 치명적 오류 (시스템 위험)
```

### 로그 파일
```
logs/backup_YYYYMMDD_HHMMSS.log
logs/restore_YYYYMMDD_HHMMSS.log
logs/system.log  # 통합 로그
```

### 로그 형식
```
[2023-12-04 15:30:45] [INFO] [backup_system.sh:123] Starting backup level 1
[2023-12-04 15:30:46] [DEBUG] [backup_system.sh:145] Checking disk space: 150GB free
[2023-12-04 15:30:50] [INFO] [backup_system.sh:234] Backup completed: 1.2GB
[2023-12-04 15:30:51] [ERROR] [restore_system.sh:456] Integrity check failed: checksum mismatch
```

---

## 안전 장치 및 체크리스트

### 백업 실행 전
- [ ] 충분한 디스크 공간 (예상 크기의 2배 이상)
- [ ] 백업 경로 쓰기 권한
- [ ] 필수 도구 설치 확인
- [ ] 시스템 부하 확인 (선택)
- [ ] 기존 백업 프로세스 실행 여부

### 백업 실행 중
- [ ] 진행률 실시간 표시
- [ ] 오류 발생 시 즉시 알림
- [ ] Ctrl+C 인터럽트 처리 (정리 후 종료)
- [ ] 로그 실시간 기록

### 백업 완료 후
- [ ] 무결성 검사 (필수)
- [ ] 메타데이터 생성 확인
- [ ] 압축 파일 테스트
- [ ] 주요 파일 존재 확인
- [ ] 로그 저장

### 복구 실행 전 (중요!)
- [ ] 백업 무결성 검사
- [ ] 호스트명 일치 확인
- [ ] OS/커널 버전 호환성 확인
- [ ] 현재 상태 긴급 백업
- [ ] 사용자 확인 (3회)
- [ ] 복구 모드 선택 확인

### 복구 실행 중
- [ ] 단계별 진행률 표시
- [ ] 각 단계 검증
- [ ] 오류 시 즉시 중단 및 롤백 준비
- [ ] 로그 실시간 기록

### 복구 완료 후
- [ ] 파일 권한 확인
- [ ] 서비스 상태 확인
- [ ] 네트워크 연결 확인
- [ ] 주요 설정 파일 검증
- [ ] 재부팅 권장 (선택)

---

## 사용 시나리오

### 시나리오 1: 서버 설정 변경 전 백업

```bash
# 1. 빠른 설정 백업 (레벨 1)
cd /home/koopark/STCServiceAutomation/backupAutomation
./backup_system.sh --level 1 --note "Before nginx config change"

# 출력:
# === 백업 시작 ===
# 레벨: 1 (설정 파일만)
# 예상 크기: 120MB
# 예상 시간: 3분
#
# 디스크 공간: 150GB 사용 가능 ✓
# 필수 도구: rsync, pigz, pv ✓
#
# 백업을 시작하시겠습니까? (y/N): y
#
# [========================================] 100% (2847 files, 118MB)
#
# 백업 완료: backup_20231204_153045
# 크기: 118MB (압축 후: 45MB)
# 시간: 2분 34초
# 무결성: ✓ 검증 완료
```

### 시나리오 2: 설정 변경 후 문제 발생 - 복구

```bash
# 문제 발생! 설정 롤백 필요

./restore_system.sh --backup backup_20231204_153045 --mode safe

# 출력:
# === 복구 경고 ===
#
# ⚠⚠⚠ 경고 ⚠⚠⚠
#
# 현재 시스템 설정이 백업으로 대체됩니다.
# 이 작업은 되돌릴 수 없습니다.
#
# 백업 정보:
#   ID: backup_20231204_153045
#   날짜: 2023-12-04 15:30:45
#   레벨: 1 (설정 파일)
#   크기: 118MB
#   노트: Before nginx config change
#
# 복구 전 현재 상태를 긴급 백업합니다.
#
# 계속하시겠습니까? 'yes'를 입력하세요: yes
# 다시 한번 확인합니다. 정말 복구하시겠습니까? 'YES'를 입력하세요: YES
#
# [1/5] 긴급 백업 생성 중...
# [========================================] 100%
# 긴급 백업: emergency_20231204_155000
#
# [2/5] 백업 무결성 검사 중...
# ✓ 체크섬 일치
#
# [3/5] 서비스 중지 중...
# ✓ nginx, docker 중지
#
# [4/5] 파일 복구 중...
# [========================================] 100% (2847 files)
#
# [5/5] 서비스 재시작 중...
# ✓ nginx, docker 시작
#
# === 복구 완료 ===
#
# 복구된 백업: backup_20231204_153045
# 복구 시간: 1분 45초
#
# 시스템을 재부팅하시겠습니까? (권장) (y/N): y
```

### 시나리오 3: 주기적 전체 백업

```bash
# crontab 등록 예시
# 매주 일요일 새벽 2시에 레벨 2 백업

# crontab -e
0 2 * * 0 /home/koopark/STCServiceAutomation/backupAutomation/backup_system.sh --level 2 --auto --notify
```

### 시나리오 4: 백업 관리

```bash
# 백업 목록 확인
./backup_manager.sh --list

# 출력:
# ID                        날짜                레벨  크기      상태
# backup_20231204_153045    2023-12-04 15:30   L1    45MB      ✓
# backup_20231203_020000    2023-12-03 02:00   L2    1.2GB     ✓
# backup_20231126_020000    2023-11-26 02:00   L2    1.1GB     ✓
# backup_20231119_020000    2023-11-19 02:00   L2    1.0GB     ✓

# 백업 상세 정보
./backup_manager.sh --info backup_20231204_153045

# 백업 무결성 검사
./backup_manager.sh --verify backup_20231204_153045

# 오래된 백업 정리
./backup_manager.sh --cleanup --auto
```

---

## 성능 최적화

### 압축 최적화
```bash
# pigz 사용 (병렬 압축)
# CPU 코어 수만큼 스레드 사용
tar -cf - /etc | pigz -p $(nproc) > backup.tar.gz

# 압축 레벨 조절
# 레벨 1: 빠름, 낮은 압축률
# 레벨 6: 균형 (기본값)
# 레벨 9: 느림, 높은 압축률
```

### rsync 최적화
```bash
# 증분 백업 (하드링크)
rsync -aH --link-dest=/path/to/previous/backup \
    /source /dest

# 네트워크 최적화 (원격 백업 시)
rsync -avz --compress-level=9

# 대용량 파일 처리
rsync -aH --partial --inplace
```

### 진행률 표시
```bash
# pv 사용
tar -cf - /etc | pv -s $(du -sb /etc | awk '{print $1}') | \
    pigz > backup.tar.gz
```

---

## 재해 복구 (Disaster Recovery)

### 완전한 시스템 복구 시나리오

```bash
# 새 서버에 OS 설치 후

# 1. 백업 도구 설치
./setup_backup_tools.sh --install

# 2. 백업 파일 복사 (USB 등)
cp -r /media/usb/backups /tmp/

# 3. 전체 복구 (레벨 3)
./restore_system.sh --backup backup_XXXXXX --mode full --force

# 4. 패키지 복구 (필요 시)
cd ..
./restore_packages.sh

# 5. 재부팅
sudo reboot
```

---

## 보안 고려사항

### 백업 암호화 (선택)

```bash
# 암호화 백업 생성
tar -czf - /etc | openssl enc -aes-256-cbc -salt -out backup.tar.gz.enc

# 복호화
openssl enc -d -aes-256-cbc -in backup.tar.gz.enc | tar -xz
```

### 권한 보호

```bash
# 백업 파일 권한: 600 (소유자만)
chmod 600 backups/*

# 백업 디렉토리: 700
chmod 700 backups/
```

### 민감 정보 제외

```bash
# 제외할 민감 파일
EXCLUDE_SENSITIVE=(
    "/root/.bash_history"
    "/home/*/.bash_history"
    "/root/.mysql_history"
    "/etc/shadow-"
    "*.key"
    "*.pem"
    "*_rsa"
)
```

---

## 테스트 계획

### 백업 테스트
1. 빈 디렉토리 백업 (엣지 케이스)
2. 대용량 파일 백업 (1GB+)
3. 많은 파일 백업 (100,000+)
4. 특수 문자 파일명 백업
5. 디스크 공간 부족 시나리오
6. 중단 및 재개 테스트

### 복구 테스트
1. 파일 복구 검증
2. 권한 복구 검증
3. 심볼릭 링크 복구
4. 하드링크 복구
5. ACL 복구
6. 확장 속성 복구

### 통합 테스트
1. 백업 → 삭제 → 복구 → 검증
2. 증분 백업 체인 테스트
3. 다른 서버로 복구 (호환성)
4. 오래된 백업 복구 (시간 경과)

---

## 예상 개발 일정

### Phase 1: 기본 백업/복구 (2-3일)
- [ ] setup_backup_tools.sh
- [ ] backup_system.sh (레벨 1)
- [ ] restore_system.sh (안전 모드)
- [ ] 기본 테스트

### Phase 2: 고급 기능 (2-3일)
- [ ] 증분 백업 (rsync)
- [ ] 레벨 2, 3 백업
- [ ] 백업 검증 시스템
- [ ] 메타데이터 관리

### Phase 3: 관리 도구 (1-2일)
- [ ] backup_manager.sh
- [ ] 백업 정리 정책
- [ ] 로깅 시스템
- [ ] 사용자 인터페이스 개선

### Phase 4: 안전장치 및 테스트 (2-3일)
- [ ] 모든 안전장치 구현
- [ ] 포괄적인 에러 처리
- [ ] 통합 테스트
- [ ] 문서 작성

**총 예상 시간: 7-11일**

---

## 성공 기준

1. **안정성**: 복구 실패율 0%
2. **무결성**: 백업 검증 100% 통과
3. **성능**: 레벨 1 백업 5분 이내
4. **사용성**: 명확한 인터페이스 및 에러 메시지
5. **안전성**: 복구 전 3중 확인 절차

---

## 리스크 관리

| 리스크 | 영향 | 확률 | 대응 방안 |
|--------|------|------|-----------|
| 디스크 공간 부족 | 높음 | 중간 | 사전 체크, 압축, 경고 |
| 복구 중 중단 | 높음 | 낮음 | 긴급 백업, 롤백 |
| 백업 손상 | 높음 | 낮음 | 무결성 검사, 다중 백업 |
| 잘못된 백업 복구 | 높음 | 중간 | 호스트명 확인, 3중 확인 |
| 성능 저하 | 중간 | 중간 | 압축 최적화, 증분 백업 |

---

## 다음 단계

이 계획을 바탕으로 구현을 시작하시겠습니까?

권장 시작 순서:
1. backupAutomation 폴더 구조 생성
2. setup_backup_tools.sh 구현 (도구 준비)
3. backup_system.sh 레벨 1 구현 (최소 백업)
4. 테스트 및 검증
5. restore_system.sh 안전 모드 구현
6. 점진적으로 기능 확장
