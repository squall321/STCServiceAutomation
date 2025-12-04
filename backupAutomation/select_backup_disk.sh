#!/bin/bash

# 백업 디스크 선택 도구
# 여러 디스크가 있을 때 백업 위치를 선택

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config/backup_policy.conf"

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
# 현재 백업 위치 확인
#############################################

show_current_location() {
    print_header "현재 백업 설정"

    if [ -f "$CONFIG_FILE" ]; then
        local current_path=$(grep "^BACKUP_ROOT=" "$CONFIG_FILE" | cut -d'"' -f2)

        if [ -n "$current_path" ]; then
            echo "현재 백업 경로: $current_path"

            # 디스크 정보
            if [ -d "$current_path" ]; then
                local disk_info=$(df -h "$current_path" | tail -1)
                echo ""
                echo "디스크 정보:"
                echo "$disk_info"
            else
                print_warning "백업 경로가 존재하지 않습니다"
            fi
        else
            print_warning "백업 경로가 설정되지 않았습니다"
        fi
    else
        print_error "설정 파일을 찾을 수 없습니다: $CONFIG_FILE"
    fi

    echo ""
}

#############################################
# 사용 가능한 디스크 목록
#############################################

list_available_disks() {
    print_header "사용 가능한 디스크"

    echo ""
    printf "%-4s %-15s %-10s %-10s %-10s %-5s %-20s\n" \
        "번호" "디스크" "크기" "사용됨" "사용가능" "사용%" "마운트 위치"
    printf "%s\n" "-----------------------------------------------------------------------------------------"

    local idx=0
    local -a mount_points=()
    local -a free_spaces=()

    # /proc/mounts에서 실제 파일시스템만 추출
    while IFS= read -r line; do
        local device=$(echo "$line" | awk '{print $1}')
        local mount=$(echo "$line" | awk '{print $2}')

        # 가상 파일시스템 제외
        if [[ "$device" =~ ^/dev/ ]] && [[ ! "$mount" =~ ^/(proc|sys|dev|run)$ ]]; then
            # 디스크 정보
            local disk_info=$(df -h "$mount" | tail -1)
            local size=$(echo "$disk_info" | awk '{print $2}')
            local used=$(echo "$disk_info" | awk '{print $3}')
            local avail=$(echo "$disk_info" | awk '{print $4}')
            local use_pct=$(echo "$disk_info" | awk '{print $5}')

            # 사용 가능 공간 (GB 단위)
            local avail_gb=$(echo "$disk_info" | awk '{print $4}' | sed 's/G//')

            # 10GB 이상만 표시
            if [ "${avail_gb%.*}" -ge 10 ] 2>/dev/null || [[ "$avail_gb" =~ T ]]; then
                ((idx++))
                printf "%-4s %-15s %-10s %-10s %-10s %-5s %-20s\n" \
                    "$idx" "$device" "$size" "$used" "$avail" "$use_pct" "$mount"

                mount_points+=("$mount")
                free_spaces+=("$avail")
            fi
        fi
    done < /proc/mounts

    echo ""

    # 배열을 전역으로 export
    MOUNT_POINTS=("${mount_points[@]}")
    DISK_COUNT=${#MOUNT_POINTS[@]}

    return 0
}

#############################################
# 백업 경로 선택
#############################################

select_backup_location() {
    print_header "백업 위치 선택"

    if [ $DISK_COUNT -eq 0 ]; then
        print_error "사용 가능한 디스크가 없습니다"
        exit 1
    fi

    echo ""
    read -p "백업 디스크를 선택하세요 (1-$DISK_COUNT) 또는 0 (취소): " choice

    if [ "$choice" = "0" ]; then
        print_info "취소되었습니다"
        exit 0
    fi

    # 입력 검증
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt $DISK_COUNT ]; then
        print_error "잘못된 선택입니다"
        exit 1
    fi

    # 선택된 마운트 포인트
    local selected_mount="${MOUNT_POINTS[$((choice-1))]}"

    echo ""
    print_info "선택된 위치: $selected_mount"

    # 백업 경로 제안
    local backup_path="${selected_mount}/system_backups"

    echo ""
    echo "백업 경로 제안: $backup_path"
    read -p "이 경로를 사용하시겠습니까? (Y/n): " use_default

    if [[ "$use_default" =~ ^[Nn]$ ]]; then
        read -p "백업 경로를 입력하세요: " backup_path
    fi

    # 경로 생성 확인
    if [ ! -d "$backup_path" ]; then
        echo ""
        print_warning "백업 경로가 존재하지 않습니다: $backup_path"
        read -p "디렉토리를 생성하시겠습니까? (y/N): " create_dir

        if [[ "$create_dir" =~ ^[Yy]$ ]]; then
            mkdir -p "$backup_path"/{snapshots,metadata}
            print_success "백업 디렉토리 생성 완료"
        else
            print_error "백업 경로가 없습니다. 취소합니다."
            exit 1
        fi
    fi

    # 쓰기 권한 확인
    if [ ! -w "$backup_path" ]; then
        print_warning "백업 경로에 쓰기 권한이 없습니다"
        read -p "소유권을 변경하시겠습니까? (y/N): " fix_perm

        if [[ "$fix_perm" =~ ^[Yy]$ ]]; then
            sudo chown -R $USER:$USER "$backup_path"
            print_success "소유권 변경 완료"
        else
            print_warning "sudo로 백업 스크립트를 실행해야 할 수 있습니다"
        fi
    fi

    # 설정 파일 업데이트
    update_config "$backup_path"
}

#############################################
# 설정 파일 업데이트
#############################################

update_config() {
    local new_path="$1"

    print_header "설정 파일 업데이트"

    # 백업 생성
    if [ -f "$CONFIG_FILE" ]; then
        cp "$CONFIG_FILE" "${CONFIG_FILE}.backup"
        print_info "기존 설정 백업: ${CONFIG_FILE}.backup"
    fi

    # BACKUP_ROOT 라인 찾기 및 업데이트
    if grep -q "^BACKUP_ROOT=" "$CONFIG_FILE" 2>/dev/null; then
        # 기존 라인 주석 처리
        sed -i "s|^BACKUP_ROOT=|# BACKUP_ROOT=|g" "$CONFIG_FILE"

        # 새 라인 추가
        echo "" >> "$CONFIG_FILE"
        echo "# 백업 경로 ($(date '+%Y-%m-%d %H:%M:%S')에 업데이트됨)" >> "$CONFIG_FILE"
        echo "BACKUP_ROOT=\"$new_path\"" >> "$CONFIG_FILE"
    else
        # 파일 끝에 추가
        echo "" >> "$CONFIG_FILE"
        echo "# 백업 경로" >> "$CONFIG_FILE"
        echo "BACKUP_ROOT=\"$new_path\"" >> "$CONFIG_FILE"
    fi

    print_success "설정 파일 업데이트 완료"
    echo ""
    print_info "새 백업 경로: $new_path"
    echo ""
    print_info "이제 백업을 실행하세요: sudo ./backup_system.sh"
}

#############################################
# 심볼릭 링크 생성 옵션
#############################################

create_symlink_option() {
    echo ""
    read -p "기본 백업 폴더를 심볼릭 링크로 연결하시겠습니까? (권장) (y/N): " create_link

    if [[ "$create_link" =~ ^[Yy]$ ]]; then
        local default_backup="$SCRIPT_DIR/backups"

        # 기존 디렉토리 백업
        if [ -d "$default_backup" ] && [ ! -L "$default_backup" ]; then
            mv "$default_backup" "${default_backup}.old"
            print_info "기존 백업 폴더 이동: ${default_backup}.old"
        elif [ -L "$default_backup" ]; then
            rm "$default_backup"
        fi

        # 심볼릭 링크 생성
        ln -s "$1" "$default_backup"
        print_success "심볼릭 링크 생성 완료: $default_backup -> $1"

        echo ""
        print_info "이제 스크립트가 자동으로 새 위치를 사용합니다"
    fi
}

#############################################
# 메인
#############################################

main() {
    echo "=== 백업 디스크 선택 도구 ==="
    echo ""

    # 현재 설정 표시
    show_current_location

    # 사용 가능한 디스크 목록
    list_available_disks

    # 백업 위치 선택
    select_backup_location

    # 심볼릭 링크 옵션
    create_symlink_option "$backup_path"

    echo ""
    print_success "백업 디스크 설정 완료"
    echo ""
}

main "$@"
