#!/bin/bash

# 시스템 설정 복구 스크립트
# 경고: 이 스크립트는 시스템 파일을 덮어씁니다!

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"
BACKUP_ROOT="$SCRIPT_DIR/backups"
LOG_DIR="$SCRIPT_DIR/logs"

# 색상
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

print_header() { echo -e "\n${BLUE}=== $1 ===${NC}"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC}  $1"; }
print_error() { echo -e "${RED}❌${NC} $1"; }
print_info() { echo -e "${BLUE}ℹ${NC}  $1"; }
print_critical() { echo -e "${RED}${BOLD}⚠⚠⚠  $1  ⚠⚠⚠${NC}"; }

# 전역 변수
BACKUP_ID=""
BACKUP_DIR=""
METADATA_FILE=""
LOG_FILE=""
EMERGENCY_BACKUP_ID=""
RESTORE_MODE="safe"  # safe, selective, force

#############################################
# 로깅
#############################################

log() {
    local level="$1"
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() { log "INFO" "$@"; }
log_warning() { log "WARNING" "$@"; }
log_error() { log "ERROR" "$@"; }
log_critical() { log "CRITICAL" "$@"; }

#############################################
# 정리 함수 (복구 실패 시 롤백)
#############################################

cleanup() {
    local exit_code=$?

    if [ $exit_code -ne 0 ]; then
        log_error "복구가 오류와 함께 종료되었습니다 (코드: $exit_code)"
        print_error "복구 중 오류가 발생했습니다"

        # 긴급 백업이 있으면 롤백 옵션 제공
        if [ -n "$EMERGENCY_BACKUP_ID" ] && [ -d "$BACKUP_ROOT/snapshots/$EMERGENCY_BACKUP_ID" ]; then
            echo ""
            print_critical "긴급 백업이 존재합니다"
            print_info "롤백하려면: ./restore_system.sh --backup $EMERGENCY_BACKUP_ID --force"
        fi
    fi
}

trap cleanup EXIT

#############################################
# 사전 검사
#############################################

check_requirements() {
    print_header "사전 요구사항 확인"

    # Root 권한
    if [ "$EUID" -ne 0 ]; then
        print_error "이 스크립트는 root 권한이 필요합니다"
        print_info "다시 실행: sudo $0"
        exit 1
    fi
    print_success "Root 권한 확인"

    # 필수 도구
    local required_tools=("rsync" "tar" "gzip")

    for tool in "${required_tools[@]}"; do
        if command -v "$tool" &>/dev/null; then
            print_success "$tool 사용 가능"
        else
            print_error "$tool 필요"
            exit 1
        fi
    done

    echo ""
}

#############################################
# 백업 선택 및 검증
#############################################

list_backups() {
    print_header "사용 가능한 백업 목록"

    if [ ! -d "$BACKUP_ROOT/metadata" ]; then
        print_error "백업을 찾을 수 없습니다"
        return 1
    fi

    local metadata_files=("$BACKUP_ROOT/metadata"/*.json)

    if [ ! -f "${metadata_files[0]}" ]; then
        print_error "백업이 없습니다"
        print_info "먼저 백업을 생성하세요: ./backup_system.sh"
        return 1
    fi

    echo ""
    printf "%-25s %-20s %-10s %-10s\n" "백업 ID" "날짜" "크기" "상태"
    printf "%s\n" "--------------------------------------------------------------------------------"

    for metadata_file in "${metadata_files[@]}"; do
        if [ ! -f "$metadata_file" ]; then
            continue
        fi

        # jq가 있으면 사용, 없으면 grep으로 파싱
        if command -v jq &>/dev/null; then
            local backup_id=$(jq -r '.backup_id' "$metadata_file")
            local timestamp=$(jq -r '.timestamp' "$metadata_file")
            local size_bytes=$(jq -r '.size_bytes' "$metadata_file")
        else
            local backup_id=$(grep '"backup_id"' "$metadata_file" | cut -d'"' -f4)
            local timestamp=$(grep '"timestamp"' "$metadata_file" | cut -d'"' -f4)
            local size_bytes=$(grep '"size_bytes"' "$metadata_file" | cut -d':' -f2 | tr -d ' ,')
        fi

        # 크기 변환 (bytes to MB)
        local size_mb=$((size_bytes / 1024 / 1024))
        local size_display="${size_mb}MB"

        # 백업 파일 존재 확인
        local status="✓"
        local archive_path="$BACKUP_ROOT/snapshots/${backup_id}.tar.gz"
        local dir_path="$BACKUP_ROOT/snapshots/${backup_id}"

        if [ -f "$archive_path" ]; then
            status="✓ (압축)"
        elif [ -d "$dir_path" ]; then
            status="✓ (폴더)"
        else
            status="❌ (누락)"
        fi

        printf "%-25s %-20s %-10s %-10s\n" "$backup_id" "$timestamp" "$size_display" "$status"
    done

    echo ""
}

select_backup() {
    # 명령줄 인수로 지정된 경우
    if [ -n "$BACKUP_ID" ]; then
        return 0
    fi

    # 백업 목록 표시
    list_backups

    # 백업 선택
    echo ""
    read -p "복구할 백업 ID를 입력하세요: " BACKUP_ID

    if [ -z "$BACKUP_ID" ]; then
        print_error "백업 ID가 지정되지 않았습니다"
        exit 1
    fi
}

verify_backup() {
    print_header "백업 검증"

    METADATA_FILE="$BACKUP_ROOT/metadata/${BACKUP_ID}.json"

    # 메타데이터 확인
    if [ ! -f "$METADATA_FILE" ]; then
        print_error "백업 메타데이터를 찾을 수 없습니다: $METADATA_FILE"
        exit 1
    fi
    print_success "메타데이터 발견"

    # 백업 파일/디렉토리 확인
    local archive_path="$BACKUP_ROOT/snapshots/${BACKUP_ID}.tar.gz"
    local dir_path="$BACKUP_ROOT/snapshots/${BACKUP_ID}"

    if [ -f "$archive_path" ]; then
        BACKUP_DIR="$dir_path"
        print_success "압축된 백업 발견: $archive_path"

        # 압축 해제
        print_info "백업 압축 해제 중..."
        mkdir -p "$BACKUP_DIR"
        tar -xzf "$archive_path" -C "$BACKUP_ROOT/snapshots/" 2>/dev/null

        if [ -d "$BACKUP_DIR" ]; then
            print_success "압축 해제 완료"
        else
            print_error "압축 해제 실패"
            exit 1
        fi
    elif [ -d "$dir_path" ]; then
        BACKUP_DIR="$dir_path"
        print_success "백업 디렉토리 발견: $dir_path"
    else
        print_error "백업 파일을 찾을 수 없습니다"
        exit 1
    fi

    # 체크섬 검증 (선택적)
    local checksum_file="${archive_path}.sha256"
    if [ -f "$checksum_file" ]; then
        print_info "체크섬 검증 중..."
        if sha256sum -c "$checksum_file" &>/dev/null; then
            print_success "체크섬 일치"
        else
            print_warning "체크섬 불일치"
            read -p "계속하시겠습니까? (y/N): " confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    fi

    # 주요 파일 확인
    print_info "주요 파일 확인 중..."
    local critical_files=(
        "files/etc/fstab"
        "files/etc/passwd"
        "files/etc/group"
        "files/etc/hostname"
    )

    local all_ok=true
    for file in "${critical_files[@]}"; do
        if [ -f "$BACKUP_DIR/$file" ]; then
            echo "  ✓ $file"
        else
            echo "  ❌ $file (누락)"
            all_ok=false
        fi
    done

    if [ "$all_ok" != true ]; then
        print_error "백업이 불완전합니다"
        exit 1
    fi

    print_success "백업 검증 완료"
    echo ""
}

#############################################
# 호환성 확인
#############################################

check_compatibility() {
    print_header "시스템 호환성 확인"

    # 메타데이터에서 정보 읽기
    if command -v jq &>/dev/null; then
        local backup_hostname=$(jq -r '.hostname' "$METADATA_FILE")
        local backup_os=$(jq -r '.os_version' "$METADATA_FILE")
        local backup_kernel=$(jq -r '.kernel' "$METADATA_FILE")
    else
        local backup_hostname=$(grep '"hostname"' "$METADATA_FILE" | cut -d'"' -f4)
        local backup_os=$(grep '"os_version"' "$METADATA_FILE" | cut -d'"' -f4)
        local backup_kernel=$(grep '"kernel"' "$METADATA_FILE" | cut -d'"' -f4)
    fi

    # 현재 시스템 정보
    local current_hostname=$(hostname)
    local current_os=$(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)
    local current_kernel=$(uname -r)

    echo "백업 시스템:"
    echo "  호스트: $backup_hostname"
    echo "  OS: $backup_os"
    echo "  커널: $backup_kernel"
    echo ""
    echo "현재 시스템:"
    echo "  호스트: $current_hostname"
    echo "  OS: $current_os"
    echo "  커널: $current_kernel"
    echo ""

    # 호스트명 확인
    if [ "$backup_hostname" != "$current_hostname" ]; then
        print_critical "호스트명이 다릅니다!"
        print_warning "백업: $backup_hostname, 현재: $current_hostname"
        echo ""
        print_warning "다른 서버의 백업을 복구하려는 것으로 보입니다."
        print_warning "이는 예상치 못한 문제를 일으킬 수 있습니다."
        echo ""
        read -p "정말로 계속하시겠습니까? (yes 입력): " confirm
        if [ "$confirm" != "yes" ]; then
            print_info "복구를 취소했습니다"
            exit 0
        fi
    else
        print_success "호스트명 일치"
    fi

    # OS 버전 경고
    if [ "$backup_os" != "$current_os" ]; then
        print_warning "OS 버전이 다릅니다"
        print_info "백업: $backup_os"
        print_info "현재: $current_os"
        echo ""
        read -p "계속하시겠습니까? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            exit 0
        fi
    fi

    echo ""
}

#############################################
# 긴급 백업 생성
#############################################

create_emergency_backup() {
    print_header "긴급 백업 생성"

    print_critical "복구 전 현재 상태를 백업합니다"
    print_info "복구 실패 시 이 백업으로 롤백할 수 있습니다"
    echo ""

    EMERGENCY_BACKUP_ID="emergency_$(date +%Y%m%d_%H%M%S)"
    local emergency_dir="$BACKUP_ROOT/snapshots/$EMERGENCY_BACKUP_ID"

    mkdir -p "$emergency_dir/files"

    print_info "긴급 백업 중: /etc ..."
    rsync -aAX /etc/ "$emergency_dir/files/etc/" 2>/dev/null || {
        print_warning "긴급 백업 실패"
        read -p "긴급 백업 없이 계속하시겠습니까? (매우 위험) (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            print_info "복구를 취소했습니다"
            exit 0
        fi
        EMERGENCY_BACKUP_ID=""
        return 1
    }

    print_success "긴급 백업 완료: $EMERGENCY_BACKUP_ID"
    log_critical "긴급 백업 생성: $EMERGENCY_BACKUP_ID"

    echo ""
}

#############################################
# 복구 확인
#############################################

confirm_restore() {
    print_header "복구 확인"

    print_critical "경고: 이 작업은 시스템 설정을 덮어씁니다!"
    echo ""
    echo "복구될 백업: $BACKUP_ID"
    echo "복구 모드: $RESTORE_MODE"
    echo ""

    if [ "$RESTORE_MODE" = "force" ]; then
        print_critical "강제 모드: 모든 파일을 덮어씁니다!"
    fi

    echo ""
    print_warning "이 작업은 되돌릴 수 없습니다"
    echo ""

    # 3중 확인
    read -p "정말로 복구하시겠습니까? 'yes'를 입력하세요: " confirm1
    if [ "$confirm1" != "yes" ]; then
        print_info "복구를 취소했습니다"
        exit 0
    fi

    read -p "다시 한번 확인합니다. 정말 복구하시겠습니까? 'YES'를 입력하세요: " confirm2
    if [ "$confirm2" != "YES" ]; then
        print_info "복구를 취소했습니다"
        exit 0
    fi

    read -p "마지막 확인입니다. 백업 ID를 입력하세요 ($BACKUP_ID): " confirm3
    if [ "$confirm3" != "$BACKUP_ID" ]; then
        print_error "백업 ID가 일치하지 않습니다"
        exit 1
    fi

    print_success "복구 확인 완료"
    echo ""
}

#############################################
# 서비스 중지
#############################################

stop_services() {
    print_header "서비스 중지"

    # 중지할 서비스 목록 (설정 복구 시 안전을 위해)
    local services_to_stop=(
        "nginx"
        "apache2"
        "docker"
        "mysql"
        "postgresql"
        "mongodb"
    )

    local stopped_services=()

    for service in "${services_to_stop[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            print_info "중지 중: $service"
            if systemctl stop "$service" 2>/dev/null; then
                stopped_services+=("$service")
                print_success "$service 중지 완료"
            else
                print_warning "$service 중지 실패"
            fi
        fi
    done

    # 중지된 서비스 저장 (나중에 재시작용)
    printf '%s\n' "${stopped_services[@]}" > "/tmp/restore_stopped_services_$$"

    echo ""
}

#############################################
# 파일 복구
#############################################

restore_files() {
    print_header "파일 복구"

    log_info "파일 복구 시작"

    local files_dir="$BACKUP_DIR/files"

    if [ ! -d "$files_dir" ]; then
        print_error "백업 파일 디렉토리를 찾을 수 없습니다: $files_dir"
        exit 1
    fi

    # /etc 복구 (가장 중요)
    if [ -d "$files_dir/etc" ]; then
        print_info "복구 중: /etc ..."
        log_info "복구 시작: /etc"

        # 안전 모드: 기존 파일과 비교 후 복구
        if [ "$RESTORE_MODE" = "safe" ]; then
            rsync -aAX --ignore-existing "$files_dir/etc/" /etc/ 2>>"$LOG_FILE"
            print_success "/etc 복구 완료 (기존 파일 유지)"
        else
            rsync -aAX "$files_dir/etc/" /etc/ 2>>"$LOG_FILE"
            print_success "/etc 복구 완료"
        fi

        log_info "/etc 복구 완료"
    else
        print_warning "/etc 백업이 없습니다"
    fi

    # /boot/grub 복구
    if [ -d "$files_dir/boot/grub" ]; then
        print_info "복구 중: /boot/grub ..."
        log_info "복구 시작: /boot/grub"

        if rsync -aAX "$files_dir/boot/grub/" /boot/grub/ 2>>"$LOG_FILE"; then
            print_success "/boot/grub 복구 완료"
            log_info "/boot/grub 복구 완료"

            # GRUB 업데이트
            print_info "GRUB 업데이트 중..."
            if update-grub &>/dev/null; then
                print_success "GRUB 업데이트 완료"
            else
                print_warning "GRUB 업데이트 실패 (수동 확인 필요)"
            fi
        else
            print_warning "/boot/grub 복구 실패"
        fi
    fi

    # /root 설정 파일 복구
    if [ -d "$files_dir/root" ]; then
        print_info "복구 중: /root ..."
        log_info "복구 시작: /root"

        if rsync -aAX "$files_dir/root/" /root/ 2>>"$LOG_FILE"; then
            print_success "/root 복구 완료"
            log_info "/root 복구 완료"
        else
            print_warning "/root 복구 실패"
        fi
    fi

    # crontab 복구
    if [ -d "$files_dir/var/spool/cron" ]; then
        print_info "복구 중: crontab ..."
        log_info "복구 시작: crontab"

        if rsync -aAX "$files_dir/var/spool/cron/" /var/spool/cron/ 2>>"$LOG_FILE"; then
            print_success "crontab 복구 완료"
            log_info "crontab 복구 완료"
        else
            print_warning "crontab 복구 실패"
        fi
    fi

    log_info "파일 복구 완료"
    echo ""
}

#############################################
# 권한 복구
#############################################

restore_permissions() {
    print_header "권한 및 소유권 복구"

    print_info "권한 복구 중..."

    # 주요 파일 권한 확인
    local critical_files=(
        "/etc/shadow:0:0:640"
        "/etc/gshadow:0:0:640"
        "/etc/passwd:0:0:644"
        "/etc/group:0:0:644"
        "/etc/sudoers:0:0:440"
        "/root/.ssh:0:0:700"
    )

    for entry in "${critical_files[@]}"; do
        IFS=':' read -r file owner group perms <<< "$entry"

        if [ -e "$file" ]; then
            chown "$owner:$group" "$file" 2>/dev/null || true
            chmod "$perms" "$file" 2>/dev/null || true
            echo "  ✓ $file"
        fi
    done

    print_success "권한 복구 완료"
    echo ""
}

#############################################
# 서비스 재시작
#############################################

restart_services() {
    print_header "서비스 재시작"

    local services_file="/tmp/restore_stopped_services_$$"

    if [ ! -f "$services_file" ]; then
        print_info "재시작할 서비스가 없습니다"
        return 0
    fi

    while IFS= read -r service; do
        print_info "시작 중: $service"
        if systemctl start "$service" 2>/dev/null; then
            print_success "$service 시작 완료"
        else
            print_warning "$service 시작 실패"
            log_warning "$service 시작 실패"
        fi
    done < "$services_file"

    rm -f "$services_file"

    echo ""
}

#############################################
# 복구 검증
#############################################

verify_restore() {
    print_header "복구 검증"

    print_info "주요 설정 파일 확인 중..."

    local critical_files=(
        "/etc/fstab"
        "/etc/passwd"
        "/etc/group"
        "/etc/hostname"
        "/etc/hosts"
        "/etc/network/interfaces"
    )

    local all_ok=true
    for file in "${critical_files[@]}"; do
        if [ -f "$file" ]; then
            echo "  ✓ $file"
        else
            echo "  ⚠ $file (없음)"
            all_ok=false
        fi
    done

    if [ "$all_ok" = true ]; then
        print_success "주요 파일 확인 완료"
    else
        print_warning "일부 파일이 없습니다"
    fi

    # 네트워크 연결 확인
    print_info "네트워크 연결 확인 중..."
    if ping -c 1 8.8.8.8 &>/dev/null; then
        print_success "네트워크 연결 정상"
    else
        print_warning "네트워크 연결 확인 실패"
        print_info "네트워크 설정을 확인하세요"
    fi

    echo ""
}

#############################################
# 복구 요약
#############################################

print_restore_summary() {
    print_header "복구 완료"

    echo ""
    echo "복구된 백업: $BACKUP_ID"

    if [ -n "$EMERGENCY_BACKUP_ID" ]; then
        echo "긴급 백업: $EMERGENCY_BACKUP_ID"
        print_info "문제 발생 시: ./restore_system.sh --backup $EMERGENCY_BACKUP_ID --force"
    fi

    echo ""
    print_success "시스템 설정 복구가 완료되었습니다"
    echo ""
    print_warning "시스템을 재부팅하는 것을 강력히 권장합니다"
    echo ""

    read -p "지금 재부팅하시겠습니까? (y/N): " reboot_confirm
    if [[ "$reboot_confirm" =~ ^[Yy]$ ]]; then
        print_info "5초 후 재부팅합니다..."
        sleep 5
        reboot
    else
        print_info "나중에 재부팅하세요: sudo reboot"
    fi
}

#############################################
# 사용법
#############################################

usage() {
    cat <<EOF
시스템 설정 복구 스크립트

사용법:
  $0 [옵션]

옵션:
  --backup ID         복구할 백업 ID 지정
  --list              사용 가능한 백업 목록 표시
  --mode MODE         복구 모드 (safe, selective, force)
                      safe: 기존 파일 유지 (기본값)
                      selective: 대화형 선택
                      force: 모든 파일 덮어쓰기
  --no-emergency      긴급 백업 생성 안 함 (권장하지 않음)
  --help              이 도움말 표시

예시:
  # 백업 목록 확인
  sudo ./restore_system.sh --list

  # 안전 모드로 복구
  sudo ./restore_system.sh --backup backup_20231204_153045

  # 강제 모드로 복구
  sudo ./restore_system.sh --backup backup_20231204_153045 --mode force

EOF
}

#############################################
# 메인
#############################################

main() {
    echo "=== 시스템 설정 복구 스크립트 ==="
    echo ""

    # 로그 파일 설정
    LOG_FILE="$LOG_DIR/restore_$(date +%Y%m%d_%H%M%S).log"
    mkdir -p "$LOG_DIR"

    # 사전 검사
    check_requirements

    # 백업 선택
    select_backup

    # 백업 검증
    verify_backup

    # 호환성 확인
    check_compatibility

    # 긴급 백업 생성
    if [ "${NO_EMERGENCY:-false}" != true ]; then
        create_emergency_backup
    fi

    # 복구 확인
    confirm_restore

    # 복구 실행
    stop_services
    restore_files
    restore_permissions
    restart_services

    # 검증
    verify_restore

    # 요약
    print_restore_summary

    log_info "복구 완료: $BACKUP_ID"

    exit 0
}

# 명령줄 인수 파싱
while [[ $# -gt 0 ]]; do
    case $1 in
        --backup)
            BACKUP_ID="$2"
            shift 2
            ;;
        --list)
            list_backups
            exit 0
            ;;
        --mode)
            RESTORE_MODE="$2"
            shift 2
            ;;
        --no-emergency)
            NO_EMERGENCY=true
            shift
            ;;
        --force)
            RESTORE_MODE="force"
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            print_error "알 수 없는 옵션: $1"
            usage
            exit 1
            ;;
    esac
done

main "$@"
