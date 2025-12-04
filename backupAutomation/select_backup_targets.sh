#!/bin/bash

# 백업 대상 선택 도구
# 어떤 경로를 백업할지 대화형으로 선택

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config/backup_paths.conf"

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
# 현재 백업 설정 표시
#############################################

show_current_config() {
    print_header "현재 백업 설정"

    echo ""
    echo "기본 백업 대상 (항상 백업됨):"
    echo "  ✓ /etc - 시스템 설정"
    echo "  ✓ /boot/grub - 부트로더"
    echo "  ✓ /root - 루트 사용자 설정"
    echo "  ✓ /var/spool/cron - crontab"
    echo ""

    if [ -f "$CONFIG_FILE" ]; then
        echo "추가 백업 경로:"
        grep "^BACKUP_PATHS+=(" "$CONFIG_FILE" -A 20 | grep '    "/' | sed 's/    "//g' | sed 's/".*#/ -/g' || echo "  (없음)"
    fi

    echo ""
    echo "제외 경로:"
    echo "  ✗ /home - 사용자 데이터"
    echo "  ✗ /opt - 애플리케이션"
    echo "  ✗ /var/www - 웹 데이터"
    echo "  ✗ /srv - 서비스 데이터"
    echo "  ✗ 데이터베이스 디렉토리"
    echo ""
}

#############################################
# 선택 가능한 백업 대상
#############################################

show_backup_options() {
    print_header "추가 백업 대상 선택"

    cat <<EOF

다음 항목을 추가로 백업할 수 있습니다:

[시스템 설정]
1. /usr/local - 로컬 설치 프로그램 설정
2. /etc/systemd - systemd 서비스 설정 (이미 /etc에 포함)

[네트워크 설정]
3. /etc/network - 네트워크 설정 (이미 /etc에 포함)
4. /etc/netplan - Netplan 설정 (이미 /etc에 포함)

[데이터베이스 설정]
5. /etc/mysql - MySQL 설정만 (데이터 제외)
6. /etc/postgresql - PostgreSQL 설정만 (데이터 제외)

[웹서버 설정]
7. /etc/nginx - Nginx 설정 (이미 /etc에 포함)
8. /etc/apache2 - Apache 설정 (이미 /etc에 포함)

[애플리케이션] (주의: 용량이 클 수 있음)
9. /opt - 설치된 애플리케이션
10. /usr/local/bin - 로컬 실행 파일
11. /usr/local/lib - 로컬 라이브러리

[데이터] (주의: 용량이 매우 클 수 있음)
12. /home - 사용자 홈 디렉토리
13. /var/www - 웹 서버 데이터
14. /srv - 서비스 데이터

[기타]
15. 사용자 정의 경로 입력

0. 완료 (선택 마침)

EOF
}

#############################################
# 경로 유효성 검사
#############################################

validate_path() {
    local path="$1"

    # 절대 경로 확인
    if [[ ! "$path" =~ ^/ ]]; then
        print_error "절대 경로를 입력하세요 (/ 로 시작)"
        return 1
    fi

    # 경로 존재 확인
    if [ ! -e "$path" ]; then
        print_warning "경로가 존재하지 않습니다: $path"
        read -p "그래도 추가하시겠습니까? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi

    # 위험한 경로 경고
    local dangerous_paths=("/proc" "/sys" "/dev" "/run" "/tmp")
    for dangerous in "${dangerous_paths[@]}"; do
        if [[ "$path" == "$dangerous"* ]]; then
            print_error "이 경로는 백업하면 안 됩니다: $path"
            return 1
        fi
    done

    # 크기 확인
    if [ -d "$path" ]; then
        local size=$(du -sh "$path" 2>/dev/null | awk '{print $1}')
        echo "  경로 크기: $size"

        # 10GB 이상이면 경고
        local size_num=$(du -s "$path" 2>/dev/null | awk '{print $1}')
        local size_gb=$((size_num / 1024 / 1024))

        if [ $size_gb -ge 10 ]; then
            print_warning "경로 크기가 ${size_gb}GB입니다. 백업 시간이 오래 걸릴 수 있습니다."
            read -p "계속하시겠습니까? (y/N): " confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                return 1
            fi
        fi
    fi

    return 0
}

#############################################
# 백업 대상 추가
#############################################

declare -a SELECTED_PATHS=()
declare -a SELECTED_DESCRIPTIONS=()

add_backup_path() {
    local choice="$1"
    local path=""
    local description=""

    case $choice in
        1)
            path="/usr/local"
            description="로컬 프로그램 설정"
            ;;
        2)
            print_info "/etc/systemd는 이미 /etc에 포함됩니다"
            return 0
            ;;
        3)
            print_info "/etc/network는 이미 /etc에 포함됩니다"
            return 0
            ;;
        4)
            print_info "/etc/netplan는 이미 /etc에 포함됩니다"
            return 0
            ;;
        5)
            print_info "/etc/mysql는 이미 /etc에 포함됩니다"
            return 0
            ;;
        6)
            print_info "/etc/postgresql는 이미 /etc에 포함됩니다"
            return 0
            ;;
        7)
            print_info "/etc/nginx는 이미 /etc에 포함됩니다"
            return 0
            ;;
        8)
            print_info "/etc/apache2는 이미 /etc에 포함됩니다"
            return 0
            ;;
        9)
            path="/opt"
            description="애플리케이션"
            print_warning "⚠ 용량이 클 수 있습니다"
            ;;
        10)
            path="/usr/local/bin"
            description="로컬 실행 파일"
            ;;
        11)
            path="/usr/local/lib"
            description="로컬 라이브러리"
            ;;
        12)
            path="/home"
            description="사용자 홈 디렉토리"
            print_warning "⚠ 용량이 매우 클 수 있습니다"
            ;;
        13)
            path="/var/www"
            description="웹 서버 데이터"
            print_warning "⚠ 용량이 클 수 있습니다"
            ;;
        14)
            path="/srv"
            description="서비스 데이터"
            print_warning "⚠ 용량이 클 수 있습니다"
            ;;
        15)
            read -p "백업할 경로를 입력하세요: " path
            read -p "설명 (선택): " description
            ;;
        *)
            print_error "잘못된 선택입니다"
            return 1
            ;;
    esac

    if [ -n "$path" ]; then
        # 유효성 검사
        if validate_path "$path"; then
            # 중복 확인
            if [[ " ${SELECTED_PATHS[@]} " =~ " ${path} " ]]; then
                print_warning "이미 선택된 경로입니다"
            else
                SELECTED_PATHS+=("$path")
                SELECTED_DESCRIPTIONS+=("$description")
                print_success "추가됨: $path"
            fi
        fi
    fi
}

#############################################
# 설정 파일 업데이트
#############################################

update_config_file() {
    print_header "설정 파일 업데이트"

    if [ ${#SELECTED_PATHS[@]} -eq 0 ]; then
        print_info "추가할 경로가 없습니다"
        return 0
    fi

    # 백업 생성
    if [ -f "$CONFIG_FILE" ]; then
        cp "$CONFIG_FILE" "${CONFIG_FILE}.backup"
        print_info "기존 설정 백업: ${CONFIG_FILE}.backup"
    fi

    # 새 경로 추가
    echo "" >> "$CONFIG_FILE"
    echo "# 추가 백업 경로 ($(date '+%Y-%m-%d %H:%M:%S')에 추가됨)" >> "$CONFIG_FILE"
    echo "BACKUP_PATHS+=(" >> "$CONFIG_FILE"

    for i in "${!SELECTED_PATHS[@]}"; do
        local path="${SELECTED_PATHS[$i]}"
        local desc="${SELECTED_DESCRIPTIONS[$i]}"

        if [ -n "$desc" ]; then
            echo "    \"$path\"    # $desc" >> "$CONFIG_FILE"
        else
            echo "    \"$path\"" >> "$CONFIG_FILE"
        fi
    done

    echo ")" >> "$CONFIG_FILE"

    print_success "설정 파일 업데이트 완료"

    # 추가된 경로 표시
    echo ""
    echo "추가된 백업 경로:"
    for i in "${!SELECTED_PATHS[@]}"; do
        echo "  ✓ ${SELECTED_PATHS[$i]}"
    done

    echo ""
}

#############################################
# 예상 백업 크기 계산
#############################################

estimate_backup_size() {
    if [ ${#SELECTED_PATHS[@]} -eq 0 ]; then
        return 0
    fi

    print_header "예상 백업 크기 계산"

    echo ""
    local total_size=0

    # 기본 백업 크기 (대략)
    echo "기본 백업 (/etc, /boot/grub, /root):"
    local etc_size=$(du -s /etc 2>/dev/null | awk '{print $1}')
    local boot_size=$(du -s /boot/grub 2>/dev/null | awk '{print $1}' || echo 0)
    local root_size=$(du -s /root 2>/dev/null | awk '{print $1}')
    local base_total=$((etc_size + boot_size + root_size))
    local base_mb=$((base_total / 1024))

    echo "  약 ${base_mb}MB"
    total_size=$base_total

    # 추가 경로 크기
    if [ ${#SELECTED_PATHS[@]} -gt 0 ]; then
        echo ""
        echo "추가 경로:"
        for path in "${SELECTED_PATHS[@]}"; do
            if [ -e "$path" ]; then
                local path_size=$(du -s "$path" 2>/dev/null | awk '{print $1}')
                local path_mb=$((path_size / 1024))
                echo "  $path: 약 ${path_mb}MB"
                total_size=$((total_size + path_size))
            fi
        done
    fi

    # 총 크기
    local total_mb=$((total_size / 1024))
    local total_gb=$((total_mb / 1024))

    echo ""
    echo "예상 총 크기 (압축 전): 약 ${total_mb}MB (${total_gb}GB)"
    echo "예상 압축 후: 약 $((total_mb * 70 / 100))MB (30% 압축률 가정)"

    # 백업 시간 추정 (1GB당 1분 가정)
    local est_minutes=$((total_gb + 1))
    echo "예상 백업 시간: 약 ${est_minutes}분"

    echo ""
}

#############################################
# 메인
#############################################

main() {
    echo "=== 백업 대상 선택 도구 ==="

    # 현재 설정 표시
    show_current_config

    # 대화형 선택
    while true; do
        show_backup_options

        read -p "선택 (0-15): " choice

        if [ "$choice" = "0" ]; then
            break
        fi

        add_backup_path "$choice"

        echo ""
        read -p "계속 추가하시겠습니까? (Y/n): " continue_add
        if [[ "$continue_add" =~ ^[Nn]$ ]]; then
            break
        fi
    done

    # 선택 요약
    if [ ${#SELECTED_PATHS[@]} -gt 0 ]; then
        echo ""
        print_header "선택 요약"
        echo ""
        echo "추가할 백업 경로:"
        for i in "${!SELECTED_PATHS[@]}"; do
            local path="${SELECTED_PATHS[$i]}"
            local desc="${SELECTED_DESCRIPTIONS[$i]}"
            if [ -n "$desc" ]; then
                echo "  ✓ $path ($desc)"
            else
                echo "  ✓ $path"
            fi
        done

        # 예상 크기 계산
        estimate_backup_size

        # 확인
        echo ""
        read -p "이 설정을 저장하시겠습니까? (y/N): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            update_config_file

            echo ""
            print_success "백업 대상 설정 완료"
            echo ""
            print_info "이제 백업을 실행하세요: sudo ./backup_system.sh"
        else
            print_info "취소되었습니다"
        fi
    else
        echo ""
        print_info "추가할 경로가 없습니다"
        print_info "기본 백업 대상만 사용됩니다"
    fi

    echo ""
}

main "$@"
