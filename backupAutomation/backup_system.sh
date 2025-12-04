#!/bin/bash

# 시스템 설정 백업 스크립트
# /home, /opt 제외, 시스템 운영에 필요한 설정만 백업

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"
BACKUP_ROOT="$SCRIPT_DIR/backups"
LOG_DIR="$SCRIPT_DIR/logs"

# 설정 파일 로드
if [ -f "$CONFIG_DIR/backup_paths.conf" ]; then
    source "$CONFIG_DIR/backup_paths.conf"
fi

if [ -f "$CONFIG_DIR/backup_policy.conf" ]; then
    source "$CONFIG_DIR/backup_policy.conf"
fi

# 전역 변수
BACKUP_ID=""
BACKUP_DIR=""
METADATA_FILE=""
LOG_FILE=""
SYSTEM_INFO_DIR=""
START_TIME=$(date +%s)

# 색상
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() { echo -e "\n${BLUE}=== $1 ===${NC}"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_error() { echo -e "${RED}❌${NC} $1"; }
print_info() { echo -e "${BLUE}ℹ${NC} $1"; }

#############################################
# 로깅 함수
#############################################

log() {
    local level="$1"
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_debug() { [ "${LOG_LEVEL:-INFO}" = "DEBUG" ] && log "DEBUG" "$@"; }
log_info() { log "INFO" "$@"; }
log_warning() { log "WARNING" "$@"; }
log_error() { log "ERROR" "$@"; }
log_critical() { log "CRITICAL" "$@"; }

#############################################
# 정리 함수
#############################################

cleanup() {
    local exit_code=$?

    if [ $exit_code -ne 0 ]; then
        log_error "백업이 오류와 함께 종료되었습니다 (코드: $exit_code)"

        # 불완전한 백업 정리
        if [ -n "$BACKUP_DIR" ] && [ -d "$BACKUP_DIR" ]; then
            print_warning "불완전한 백업을 정리합니다..."
            rm -rf "$BACKUP_DIR"
        fi
    fi
}

trap cleanup EXIT

#############################################
# 사전 검사
#############################################

check_requirements() {
    print_header "사전 요구사항 확인"

    # Bash 버전
    if ((BASH_VERSINFO[0] < 4)); then
        print_error "Bash 4.0 이상이 필요합니다 (현재: $BASH_VERSION)"
        exit 1
    fi
    print_success "Bash 버전: $BASH_VERSION"

    # Root 권한
    if [ "$EUID" -ne 0 ]; then
        print_error "이 스크립트는 root 권한이 필요합니다"
        print_info "다시 실행: sudo $0"
        exit 1
    fi

    # 필수 도구
    local required_tools=("rsync" "tar" "gzip")
    local missing_tools=()

    for tool in "${required_tools[@]}"; do
        if command -v "$tool" &>/dev/null; then
            print_success "$tool 사용 가능"
        else
            missing_tools+=("$tool")
        fi
    done

    # 선택적 도구
    if command -v "pigz" &>/dev/null; then
        print_success "pigz 사용 가능 (병렬 압축)"
        USE_PIGZ=true
    else
        print_warning "pigz 미설치 (일반 gzip 사용)"
        USE_PIGZ=false
    fi

    if command -v "pv" &>/dev/null; then
        print_success "pv 사용 가능 (진행률 표시)"
    else
        print_warning "pv 미설치 (진행률 표시 안 됨)"
    fi

    if [ ${#missing_tools[@]} -gt 0 ]; then
        print_error "다음 도구가 필요합니다: ${missing_tools[*]}"
        print_info "설치 방법: ./setup_backup_tools.sh --install"
        exit 1
    fi

    echo ""
}

check_disk_space() {
    print_header "디스크 공간 확인"

    local backup_root_dir="${BACKUP_ROOT}/snapshots"
    mkdir -p "$backup_root_dir"

    # 백업 위치의 여유 공간 (GB)
    local free_space_kb=$(df "$backup_root_dir" | tail -1 | awk '{print $4}')
    local free_space_gb=$((free_space_kb / 1024 / 1024))

    print_info "백업 위치: $backup_root_dir"
    print_info "여유 공간: ${free_space_gb}GB"

    # /etc 크기 추정
    local etc_size_kb=$(du -sk /etc 2>/dev/null | awk '{print $1}')
    local etc_size_mb=$((etc_size_kb / 1024))

    # /boot/grub 크기
    local boot_size_kb=0
    if [ -d "/boot/grub" ]; then
        boot_size_kb=$(du -sk /boot/grub 2>/dev/null | awk '{print $1}')
    fi

    # 시스템 정보 예상 크기 (약 50MB)
    local sysinfo_size_kb=51200

    # 총 예상 크기 (압축 전)
    local total_size_kb=$((etc_size_kb + boot_size_kb + sysinfo_size_kb))
    local total_size_mb=$((total_size_kb / 1024))

    # 압축 후 예상 크기 (약 30% 압축)
    local estimated_size_mb=$((total_size_mb * 70 / 100))

    print_info "예상 백업 크기: ${total_size_mb}MB (압축 전)"
    print_info "예상 압축 후 크기: ~${estimated_size_mb}MB"

    # 최소 여유 공간 확인 (예상 크기의 2배 + 설정된 최소 여유 공간)
    local required_space_mb=$((estimated_size_mb * 2 + MIN_FREE_SPACE_GB * 1024))
    local required_space_gb=$((required_space_mb / 1024))

    if [ $free_space_gb -lt $required_space_gb ]; then
        print_error "디스크 공간이 부족합니다"
        print_error "필요: ${required_space_gb}GB, 사용 가능: ${free_space_gb}GB"
        exit 1
    fi

    print_success "충분한 디스크 공간 (${free_space_gb}GB 사용 가능)"

    # 경고: 여유 공간이 매우 적은 경우
    if [ $free_space_gb -lt 20 ]; then
        print_warning "디스크 여유 공간이 20GB 미만입니다"
        read -p "계속하시겠습니까? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            print_info "백업을 취소했습니다"
            exit 0
        fi
    fi

    echo ""
}

#############################################
# 백업 준비
#############################################

prepare_backup() {
    print_header "백업 준비"

    # 백업 ID 생성
    BACKUP_ID="backup_$(date +%Y%m%d_%H%M%S)"
    BACKUP_DIR="$BACKUP_ROOT/snapshots/$BACKUP_ID"
    METADATA_FILE="$BACKUP_ROOT/metadata/${BACKUP_ID}.json"
    LOG_FILE="$LOG_DIR/${BACKUP_ID}.log"
    SYSTEM_INFO_DIR="$BACKUP_DIR/system_info"

    # 디렉토리 생성
    mkdir -p "$BACKUP_DIR"
    mkdir -p "$BACKUP_ROOT/metadata"
    mkdir -p "$LOG_DIR"
    mkdir -p "$SYSTEM_INFO_DIR"

    print_success "백업 ID: $BACKUP_ID"
    print_success "백업 경로: $BACKUP_DIR"

    log_info "백업 시작: $BACKUP_ID"
    log_info "호스트: $(hostname)"
    log_info "사용자: $(whoami)"

    echo ""
}

#############################################
# 시스템 정보 수집
#############################################

collect_system_info() {
    print_header "시스템 정보 수집"

    log_info "시스템 정보 수집 시작"

    # 기본 시스템 정보
    {
        echo "=== 시스템 정보 ==="
        echo "호스트명: $(hostname)"
        echo "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
        echo "커널: $(uname -r)"
        echo "아키텍처: $(uname -m)"
        echo "백업 시각: $(date)"
        echo ""
    } > "$SYSTEM_INFO_DIR/system_basic.txt"

    # 패키지 목록
    if [ "$BACKUP_PACKAGE_LIST" = true ]; then
        print_info "패키지 목록 저장 중..."
        dpkg -l > "$SYSTEM_INFO_DIR/packages.list" 2>/dev/null || true
        dpkg --get-selections > "$SYSTEM_INFO_DIR/package_selections.txt" 2>/dev/null || true
        print_success "패키지 목록 저장 완료"
    fi

    # 서비스 상태
    if [ "$BACKUP_SERVICE_STATE" = true ]; then
        print_info "서비스 상태 저장 중..."
        systemctl list-unit-files > "$SYSTEM_INFO_DIR/services.txt" 2>/dev/null || true
        systemctl list-units --type=service > "$SYSTEM_INFO_DIR/services_active.txt" 2>/dev/null || true
        print_success "서비스 상태 저장 완료"
    fi

    # 네트워크 설정
    if [ "$BACKUP_NETWORK_CONFIG" = true ]; then
        print_info "네트워크 설정 저장 중..."
        {
            echo "=== IP 주소 ==="
            ip addr show
            echo ""
            echo "=== 라우팅 테이블 ==="
            ip route show
            echo ""
            echo "=== DNS 설정 ==="
            cat /etc/resolv.conf 2>/dev/null || true
            echo ""
        } > "$SYSTEM_INFO_DIR/network.txt" 2>/dev/null || true
        print_success "네트워크 설정 저장 완료"
    fi

    # 방화벽 규칙
    if [ "$BACKUP_FIREWALL_RULES" = true ]; then
        print_info "방화벽 규칙 저장 중..."
        iptables-save > "$SYSTEM_INFO_DIR/iptables.rules" 2>/dev/null || true
        print_success "방화벽 규칙 저장 완료"
    fi

    # 디스크 정보
    print_info "디스크 정보 저장 중..."
    {
        echo "=== 디스크 사용량 ==="
        df -h
        echo ""
        echo "=== 마운트 포인트 ==="
        mount
        echo ""
        echo "=== fstab ==="
        cat /etc/fstab
        echo ""
        echo "=== 블록 디바이스 ==="
        lsblk -f
    } > "$SYSTEM_INFO_DIR/disk.txt" 2>/dev/null || true
    print_success "디스크 정보 저장 완료"

    # RAID 정보
    if [ "$BACKUP_RAID_CONFIG" = true ]; then
        if [ -f /proc/mdstat ] || command -v mdadm &>/dev/null; then
            print_info "RAID 정보 저장 중..."
            {
                echo "=== mdstat ==="
                cat /proc/mdstat 2>/dev/null || echo "소프트웨어 RAID 없음"
                echo ""
                if command -v mdadm &>/dev/null; then
                    echo "=== mdadm 설정 ==="
                    mdadm --detail --scan 2>/dev/null || true
                fi
            } > "$SYSTEM_INFO_DIR/raid.txt"
            print_success "RAID 정보 저장 완료"
        fi
    fi

    # LVM 정보
    if [ "$BACKUP_LVM_CONFIG" = true ]; then
        if command -v pvdisplay &>/dev/null; then
            print_info "LVM 정보 저장 중..."
            {
                echo "=== Physical Volumes ==="
                pvdisplay 2>/dev/null || true
                echo ""
                echo "=== Volume Groups ==="
                vgdisplay 2>/dev/null || true
                echo ""
                echo "=== Logical Volumes ==="
                lvdisplay 2>/dev/null || true
            } > "$SYSTEM_INFO_DIR/lvm.txt"
            print_success "LVM 정보 저장 완료"
        fi
    fi

    # 커널 모듈 및 파라미터
    print_info "커널 정보 저장 중..."
    {
        echo "=== 로드된 커널 모듈 ==="
        lsmod
        echo ""
        echo "=== 커널 파라미터 ==="
        sysctl -a 2>/dev/null || true
    } > "$SYSTEM_INFO_DIR/kernel.txt" 2>/dev/null || true
    print_success "커널 정보 저장 완료"

    # 하드웨어 정보
    print_info "하드웨어 정보 저장 중..."
    {
        echo "=== PCI 디바이스 ==="
        lspci 2>/dev/null || true
        echo ""
        echo "=== USB 디바이스 ==="
        lsusb 2>/dev/null || true
        echo ""
        echo "=== CPU 정보 ==="
        lscpu 2>/dev/null || true
        echo ""
        echo "=== 메모리 정보 ==="
        free -h
    } > "$SYSTEM_INFO_DIR/hardware.txt" 2>/dev/null || true
    print_success "하드웨어 정보 저장 완료"

    log_info "시스템 정보 수집 완료"
    echo ""
}

#############################################
# 파일 백업
#############################################

backup_files() {
    print_header "시스템 파일 백업"

    log_info "파일 백업 시작"

    # rsync 제외 옵션 생성
    local exclude_opts=()
    for exclude_path in "${EXCLUDE_PATHS[@]}"; do
        exclude_opts+=("--exclude=$exclude_path")
    done

    for exclude_pattern in "${EXCLUDE_PATTERNS[@]}"; do
        exclude_opts+=("--exclude=$exclude_pattern")
    done

    # /etc 백업 (가장 중요)
    print_info "백업 중: /etc ..."
    log_info "백업 시작: /etc"

    local files_dir="$BACKUP_DIR/files"
    mkdir -p "$files_dir"

    if rsync -aAX "${exclude_opts[@]}" /etc/ "$files_dir/etc/" 2>>"$LOG_FILE"; then
        print_success "/etc 백업 완료"
        log_info "/etc 백업 완료"
    else
        print_error "/etc 백업 실패"
        log_error "/etc 백업 실패"
        return 1
    fi

    # /boot/grub 백업
    if [ -d "/boot/grub" ]; then
        print_info "백업 중: /boot/grub ..."
        log_info "백업 시작: /boot/grub"

        if rsync -aAX /boot/grub/ "$files_dir/boot/grub/" 2>>"$LOG_FILE"; then
            print_success "/boot/grub 백업 완료"
            log_info "/boot/grub 백업 완료"
        else
            print_warning "/boot/grub 백업 실패 (선택적)"
            log_warning "/boot/grub 백업 실패"
        fi
    fi

    # /root 백업 (루트 사용자 설정)
    print_info "백업 중: /root (설정 파일만) ..."
    log_info "백업 시작: /root"

    # /root에서 설정 파일만 선택적으로 백업
    local root_config_files=(
        ".bashrc"
        ".profile"
        ".bash_aliases"
        ".bash_history"
        ".vimrc"
        ".ssh"
    )

    mkdir -p "$files_dir/root"
    for config_file in "${root_config_files[@]}"; do
        if [ -e "/root/$config_file" ]; then
            cp -a "/root/$config_file" "$files_dir/root/" 2>>"$LOG_FILE" || true
        fi
    done
    print_success "/root 설정 파일 백업 완료"
    log_info "/root 설정 파일 백업 완료"

    # /var/spool/cron 백업 (crontab)
    if [ -d "/var/spool/cron" ]; then
        print_info "백업 중: /var/spool/cron ..."
        log_info "백업 시작: /var/spool/cron"

        if rsync -aAX /var/spool/cron/ "$files_dir/var/spool/cron/" 2>>"$LOG_FILE"; then
            print_success "crontab 백업 완료"
            log_info "crontab 백업 완료"
        else
            print_warning "crontab 백업 실패 (선택적)"
            log_warning "crontab 백업 실패"
        fi
    fi

    # 추가 백업 경로 (설정에서 지정된 경우)
    for backup_path in "${BACKUP_PATHS[@]}"; do
        # 이미 백업한 경로는 스킵
        if [[ "$backup_path" =~ ^(/etc|/boot/grub|/root|/var/spool/cron) ]]; then
            continue
        fi

        # 제외 경로인지 확인
        local should_exclude=false
        for exclude in "${EXCLUDE_PATHS[@]}"; do
            if [[ "$backup_path" == "$exclude"* ]]; then
                should_exclude=true
                break
            fi
        done

        if [ "$should_exclude" = true ]; then
            continue
        fi

        # 경로가 존재하면 백업
        if [ -e "$backup_path" ]; then
            print_info "백업 중: $backup_path ..."
            local dest_path="$files_dir${backup_path}"
            mkdir -p "$(dirname "$dest_path")"

            if [ -d "$backup_path" ]; then
                rsync -aAX "${exclude_opts[@]}" "$backup_path/" "$dest_path/" 2>>"$LOG_FILE" || true
            else
                cp -a "$backup_path" "$dest_path" 2>>"$LOG_FILE" || true
            fi
            print_success "$backup_path 백업 완료"
        fi
    done

    log_info "파일 백업 완료"
    echo ""
}

#############################################
# 압축
#############################################

compress_backup() {
    if [ "$COMPRESSION_ENABLED" != true ]; then
        print_info "압축이 비활성화되어 있습니다"
        return 0
    fi

    print_header "백업 압축"

    log_info "압축 시작"

    local archive_name="${BACKUP_ID}.tar.gz"
    local archive_path="$BACKUP_ROOT/snapshots/$archive_name"

    print_info "압축 중: $archive_name"

    cd "$BACKUP_ROOT/snapshots"

    # 압축 명령 선택
    if [ "$USE_PIGZ" = true ] && command -v pigz &>/dev/null; then
        # 병렬 압축 (pigz)
        if command -v pv &>/dev/null; then
            # 진행률 표시
            tar -cf - "$BACKUP_ID" | pv -s $(du -sb "$BACKUP_ID" | awk '{print $1}') | \
                pigz -p $(nproc) -${COMPRESSION_LEVEL} > "$archive_name"
        else
            tar -cf - "$BACKUP_ID" | pigz -p $(nproc) -${COMPRESSION_LEVEL} > "$archive_name"
        fi
    else
        # 일반 gzip
        if command -v pv &>/dev/null; then
            tar -cf - "$BACKUP_ID" | pv -s $(du -sb "$BACKUP_ID" | awk '{print $1}') | \
                gzip -${COMPRESSION_LEVEL} > "$archive_name"
        else
            tar -czf "$archive_name" "$BACKUP_ID"
        fi
    fi

    if [ $? -eq 0 ]; then
        local original_size=$(du -sh "$BACKUP_ID" | awk '{print $1}')
        local compressed_size=$(du -sh "$archive_name" | awk '{print $1}')

        print_success "압축 완료"
        print_info "원본 크기: $original_size"
        print_info "압축 크기: $compressed_size"

        log_info "압축 완료: $archive_name (원본: $original_size, 압축: $compressed_size)"

        # 압축 후 원본 디렉토리 삭제 여부 확인
        if [ "${DELETE_AFTER_COMPRESS:-false}" = true ]; then
            print_info "원본 디렉토리 삭제 중..."
            rm -rf "$BACKUP_ID"
            log_info "원본 디렉토리 삭제 완료"
        fi
    else
        print_error "압축 실패"
        log_error "압축 실패"
        return 1
    fi

    echo ""
}

#############################################
# 무결성 검사
#############################################

verify_backup() {
    if [ "$VERIFY_AFTER_BACKUP" != true ]; then
        print_info "백업 검증이 비활성화되어 있습니다"
        return 0
    fi

    print_header "백업 무결성 검사"

    log_info "무결성 검사 시작"

    # 압축 파일이 있는지 확인
    local archive_name="${BACKUP_ID}.tar.gz"
    local archive_path="$BACKUP_ROOT/snapshots/$archive_name"

    if [ -f "$archive_path" ]; then
        print_info "압축 파일 검증 중..."

        # tar 파일 테스트
        if tar -tzf "$archive_path" >/dev/null 2>&1; then
            print_success "압축 파일 무결성 확인"
            log_info "압축 파일 무결성 확인"
        else
            print_error "압축 파일이 손상되었습니다"
            log_error "압축 파일 손상"
            return 1
        fi
    fi

    # 주요 파일 존재 확인
    print_info "주요 파일 확인 중..."

    local critical_files=(
        "files/etc/fstab"
        "files/etc/passwd"
        "files/etc/group"
        "files/etc/hostname"
        "files/etc/hosts"
        "system_info/system_basic.txt"
        "system_info/packages.list"
    )

    local check_dir="$BACKUP_DIR"
    if [ ! -d "$check_dir" ] && [ -f "$archive_path" ]; then
        # 압축된 경우 임시 압축 해제
        check_dir="/tmp/backup_verify_$$"
        mkdir -p "$check_dir"
        tar -xzf "$archive_path" -C "$check_dir" 2>/dev/null || true
        check_dir="$check_dir/$BACKUP_ID"
    fi

    local all_ok=true
    for critical_file in "${critical_files[@]}"; do
        if [ -f "$check_dir/$critical_file" ]; then
            echo -n "  ✓ $critical_file"
            echo ""
        else
            echo -n "  ⚠ $critical_file (없음)"
            echo ""
            all_ok=false
        fi
    done

    # 임시 디렉토리 정리
    if [ -d "/tmp/backup_verify_$$" ]; then
        rm -rf "/tmp/backup_verify_$$"
    fi

    if [ "$all_ok" = true ]; then
        print_success "주요 파일 확인 완료"
        log_info "주요 파일 확인 완료"
    else
        print_warning "일부 파일이 누락되었습니다"
        log_warning "일부 파일 누락"
    fi

    # 체크섬 생성
    if [ -f "$archive_path" ]; then
        print_info "체크섬 생성 중..."

        local checksum_file="${archive_path}.${CHECKSUM_ALGORITHM:-sha256}"
        ${CHECKSUM_ALGORITHM:-sha256}sum "$archive_path" > "$checksum_file"

        print_success "체크섬 생성 완료: $(basename "$checksum_file")"
        log_info "체크섬 생성: $(cat "$checksum_file")"
    fi

    echo ""
}

#############################################
# 메타데이터 생성
#############################################

create_metadata() {
    print_header "메타데이터 생성"

    log_info "메타데이터 생성 시작"

    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))

    # 백업 크기
    local backup_size=0
    local archive_name="${BACKUP_ID}.tar.gz"
    local archive_path="$BACKUP_ROOT/snapshots/$archive_name"

    if [ -f "$archive_path" ]; then
        backup_size=$(stat -f%z "$archive_path" 2>/dev/null || stat -c%s "$archive_path" 2>/dev/null || echo 0)
    elif [ -d "$BACKUP_DIR" ]; then
        backup_size=$(du -sb "$BACKUP_DIR" | awk '{print $1}')
    fi

    # 파일 개수
    local file_count=0
    if [ -d "$BACKUP_DIR" ]; then
        file_count=$(find "$BACKUP_DIR" -type f | wc -l)
    fi

    # 디스크 사용률
    local disk_usage_before="${DISK_USAGE_BEFORE:-unknown}"
    local disk_usage_after=$(df "$BACKUP_ROOT" | tail -1 | awk '{print $5}')

    # 패키지 개수
    local package_count=0
    if [ -f "$SYSTEM_INFO_DIR/packages.list" ]; then
        package_count=$(grep "^ii" "$SYSTEM_INFO_DIR/packages.list" | wc -l)
    fi

    # JSON 메타데이터 생성
    cat > "$METADATA_FILE" <<EOF
{
  "backup_id": "$BACKUP_ID",
  "timestamp": "$(date '+%Y-%m-%d %H:%M:%S')",
  "hostname": "$(hostname)",
  "os_version": "$(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)",
  "kernel": "$(uname -r)",
  "type": "system_config",
  "size_bytes": $backup_size,
  "duration_seconds": $duration,
  "file_count": $file_count,
  "compressed": $([ "$COMPRESSION_ENABLED" = true ] && echo "true" || echo "false"),
  "integrity": {
    "algorithm": "${CHECKSUM_ALGORITHM:-sha256}",
    "verified": true
  },
  "disk_usage": {
    "before": "$disk_usage_before",
    "after": "$disk_usage_after"
  },
  "packages": {
    "count": $package_count,
    "list_file": "system_info/packages.list"
  },
  "backup_paths": $(printf '%s\n' "${BACKUP_PATHS[@]}" | jq -R . | jq -s .),
  "exclude_paths": $(printf '%s\n' "${EXCLUDE_PATHS[@]}" | jq -R . | jq -s .)
}
EOF

    print_success "메타데이터 생성 완료: $METADATA_FILE"
    log_info "메타데이터 생성 완료"

    echo ""
}

#############################################
# 백업 요약
#############################################

print_summary() {
    print_header "백업 완료"

    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))

    local backup_size="unknown"
    local archive_name="${BACKUP_ID}.tar.gz"
    local archive_path="$BACKUP_ROOT/snapshots/$archive_name"

    if [ -f "$archive_path" ]; then
        backup_size=$(du -sh "$archive_path" | awk '{print $1}')
    elif [ -d "$BACKUP_DIR" ]; then
        backup_size=$(du -sh "$BACKUP_DIR" | awk '{print $1}')
    fi

    echo ""
    echo "백업 ID: $BACKUP_ID"
    echo "백업 크기: $backup_size"
    echo "소요 시간: ${minutes}분 ${seconds}초"
    echo "백업 위치: $BACKUP_ROOT/snapshots/"
    echo "로그 파일: $LOG_FILE"
    echo "메타데이터: $METADATA_FILE"
    echo ""

    log_info "백업 완료: $BACKUP_ID (크기: $backup_size, 시간: ${minutes}m ${seconds}s)"

    print_success "시스템 설정 백업이 완료되었습니다"
    echo ""
    print_info "복구 방법: ./restore_system.sh --backup $BACKUP_ID"
}

#############################################
# 메인
#############################################

main() {
    echo "=== 시스템 설정 백업 스크립트 ==="
    echo ""

    # 디스크 사용률 저장 (메타데이터용)
    DISK_USAGE_BEFORE=$(df "$BACKUP_ROOT" 2>/dev/null | tail -1 | awk '{print $5}' || echo "unknown")

    # 사전 검사
    check_requirements
    check_disk_space

    # 백업 준비
    prepare_backup

    # 백업 실행
    collect_system_info
    backup_files

    # 압축 및 검증
    compress_backup
    verify_backup

    # 메타데이터 생성
    create_metadata

    # 요약 출력
    print_summary

    exit 0
}

main "$@"
