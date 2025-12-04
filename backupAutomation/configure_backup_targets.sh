#!/bin/bash

# YAML 기반 백업 대상 설정 도구
# backup_targets.yaml을 읽어서 대화형으로 백업 대상 선택

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YAML_FILE="$SCRIPT_DIR/config/backup_targets.yaml"
OUTPUT_FILE="$SCRIPT_DIR/config/backup_paths.conf"

# 색상
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

print_header() { echo -e "\n${BLUE}${BOLD}=== $1 ===${NC}"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC}  $1"; }
print_error() { echo -e "${RED}❌${NC} $1"; }
print_info() { echo -e "${CYAN}ℹ${NC}  $1"; }

#############################################
# YAML 파일 파싱 (간단한 파서)
#############################################

declare -A CATEGORIES
declare -a CATEGORY_ORDER=()
declare -a ALL_PATHS=()
declare -a ALL_DESCRIPTIONS=()
declare -a ALL_SIZES=()
declare -a ALL_RISKS=()
declare -a ALL_ENABLED=()
declare -a ALL_FIXED=()
declare -a ALL_NOTES=()
declare -a ALL_CATEGORIES=()

parse_yaml() {
    if [ ! -f "$YAML_FILE" ]; then
        print_error "YAML 파일을 찾을 수 없습니다: $YAML_FILE"
        exit 1
    fi

    local current_category=""
    local current_path=""
    local current_desc=""
    local current_size=""
    local current_risk="low"
    local current_enabled="false"
    local current_fixed="false"
    local current_note=""

    while IFS= read -r line; do
        # 주석과 빈 줄 스킵
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$line" ]] && continue

        # 카테고리 감지
        if [[ "$line" =~ ^([a-z_]+):$ ]]; then
            current_category="${BASH_REMATCH[1]}"
            if [[ ! " ${CATEGORY_ORDER[@]} " =~ " ${current_category} " ]]; then
                CATEGORY_ORDER+=("$current_category")
            fi
            continue
        fi

        # path 감지
        if [[ "$line" =~ path:[[:space:]]*(.+) ]]; then
            # 이전 항목 저장
            if [ -n "$current_path" ]; then
                ALL_PATHS+=("$current_path")
                ALL_DESCRIPTIONS+=("$current_desc")
                ALL_SIZES+=("$current_size")
                ALL_RISKS+=("$current_risk")
                ALL_ENABLED+=("$current_enabled")
                ALL_FIXED+=("$current_fixed")
                ALL_NOTES+=("$current_note")
                ALL_CATEGORIES+=("$current_category")
            fi

            current_path="${BASH_REMATCH[1]}"
            current_desc=""
            current_size=""
            current_risk="low"
            current_enabled="false"
            current_fixed="false"
            current_note=""
        fi

        # 속성 파싱
        [[ "$line" =~ description:[[:space:]]*(.+) ]] && current_desc="${BASH_REMATCH[1]}"
        [[ "$line" =~ estimated_size:[[:space:]]*(.+) ]] && current_size="${BASH_REMATCH[1]}"
        [[ "$line" =~ risk:[[:space:]]*(.+) ]] && current_risk="${BASH_REMATCH[1]}"
        [[ "$line" =~ enabled:[[:space:]]*(true|false) ]] && current_enabled="${BASH_REMATCH[1]}"
        [[ "$line" =~ fixed:[[:space:]]*(true|false) ]] && current_fixed="${BASH_REMATCH[1]}"
        [[ "$line" =~ note:[[:space:]]*(.+) ]] && current_note="${BASH_REMATCH[1]}"

    done < "$YAML_FILE"

    # 마지막 항목 저장
    if [ -n "$current_path" ]; then
        ALL_PATHS+=("$current_path")
        ALL_DESCRIPTIONS+=("$current_desc")
        ALL_SIZES+=("$current_size")
        ALL_RISKS+=("$current_risk")
        ALL_ENABLED+=("$current_enabled")
        ALL_FIXED+=("$current_fixed")
        ALL_NOTES+=("$current_note")
        ALL_CATEGORIES+=("$current_category")
    fi
}

#############################################
# 카테고리 이름 변환
#############################################

get_category_name() {
    case "$1" in
        mandatory) echo "필수 백업 (변경 불가)" ;;
        system_config) echo "시스템 설정" ;;
        network) echo "네트워크 설정" ;;
        storage) echo "스토리지 & RAID" ;;
        database) echo "데이터베이스 설정" ;;
        webserver) echo "웹 서버 설정" ;;
        applications) echo "애플리케이션" ;;
        docker) echo "Docker" ;;
        user_data) echo "사용자 데이터" ;;
        web_data) echo "웹 & 서비스 데이터" ;;
        logs) echo "로그 파일" ;;
        custom) echo "사용자 정의" ;;
        *) echo "$1" ;;
    esac
}

#############################################
# 백업 대상 표시 및 선택
#############################################

display_and_select() {
    print_header "백업 대상 설정"

    echo ""
    echo "다음 항목을 백업할 수 있습니다."
    echo "번호를 입력하여 활성화/비활성화를 토글하세요."
    echo ""

    local current_category=""

    for i in "${!ALL_PATHS[@]}"; do
        local path="${ALL_PATHS[$i]}"
        local desc="${ALL_DESCRIPTIONS[$i]}"
        local size="${ALL_SIZES[$i]}"
        local risk="${ALL_RISKS[$i]}"
        local enabled="${ALL_ENABLED[$i]}"
        local fixed="${ALL_FIXED[$i]}"
        local note="${ALL_NOTES[$i]}"
        local category="${ALL_CATEGORIES[$i]}"

        # 카테고리 변경 시 헤더 출력
        if [ "$category" != "$current_category" ]; then
            current_category="$category"
            echo ""
            echo -e "${CYAN}${BOLD}[$(get_category_name "$category")]${NC}"
        fi

        # 상태 표시
        local status="[ ]"
        local status_color=""
        if [ "$fixed" = "true" ]; then
            status="[✓]"
            status_color="${GREEN}"
        elif [ "$enabled" = "true" ]; then
            status="[✓]"
            status_color="${GREEN}"
        else
            status="[ ]"
            status_color="${NC}"
        fi

        # 위험도 표시
        local risk_icon=""
        case "$risk" in
            low) risk_icon="" ;;
            medium) risk_icon="${YELLOW}⚠${NC} " ;;
            high) risk_icon="${RED}⚠⚠${NC} " ;;
        esac

        # 항목 출력
        printf "%s%2d) %s%-3s%s %s\n" "$status_color" "$((i+1))" "$status_color" "$status" "$NC" "$path"
        printf "     ${risk_icon}%s\n" "$desc"

        if [ -n "$size" ]; then
            printf "     크기: %s" "$size"
            [ -n "$note" ] && printf " | %s" "$note"
            echo ""
        fi

        # 고정 항목 표시
        if [ "$fixed" = "true" ]; then
            echo -e "     ${CYAN}(필수 항목 - 변경 불가)${NC}"
        fi
    done

    echo ""
    echo "---"
    echo ""
    echo "명령어:"
    echo "  숫자 입력    - 해당 항목 활성화/비활성화 토글"
    echo "  'all'        - 모든 항목 활성화"
    echo "  'none'       - 필수 제외 모두 비활성화"
    echo "  'recommend'  - 권장 설정 적용"
    echo "  'save'       - 저장하고 종료"
    echo "  'quit'       - 저장하지 않고 종료"
    echo ""
}

#############################################
# 항목 토글
#############################################

toggle_item() {
    local index=$1

    if [ $index -lt 1 ] || [ $index -gt ${#ALL_PATHS[@]} ]; then
        print_error "잘못된 번호입니다"
        return 1
    fi

    local idx=$((index - 1))

    # 고정 항목은 변경 불가
    if [ "${ALL_FIXED[$idx]}" = "true" ]; then
        print_warning "필수 항목은 변경할 수 없습니다"
        return 1
    fi

    # 토글
    if [ "${ALL_ENABLED[$idx]}" = "true" ]; then
        ALL_ENABLED[$idx]="false"
        print_info "${ALL_PATHS[$idx]} 비활성화"
    else
        ALL_ENABLED[$idx]="true"
        print_success "${ALL_PATHS[$idx]} 활성화"

        # 위험도 높은 항목 경고
        if [ "${ALL_RISKS[$idx]}" = "high" ]; then
            print_warning "이 항목은 용량이 매우 클 수 있습니다: ${ALL_SIZES[$idx]}"
        fi
    fi
}

#############################################
# 권장 설정 적용
#############################################

apply_recommended() {
    print_info "권장 설정 적용 중..."

    for i in "${!ALL_PATHS[@]}"; do
        local path="${ALL_PATHS[$i]}"
        local risk="${ALL_RISKS[$i]}"
        local fixed="${ALL_FIXED[$i]}"

        # 고정 항목은 유지
        if [ "$fixed" = "true" ]; then
            continue
        fi

        # 권장: 위험도 낮은 것만 활성화
        if [ "$risk" = "low" ]; then
            # 로그 파일만 활성화
            if [[ "$path" =~ /var/log ]]; then
                ALL_ENABLED[$i]="true"
            else
                ALL_ENABLED[$i]="false"
            fi
        else
            ALL_ENABLED[$i]="false"
        fi
    done

    print_success "권장 설정 적용 완료"
}

#############################################
# 설정 저장
#############################################

save_configuration() {
    print_header "설정 저장"

    # 백업 생성
    if [ -f "$OUTPUT_FILE" ]; then
        cp "$OUTPUT_FILE" "${OUTPUT_FILE}.backup_$(date +%Y%m%d_%H%M%S)"
        print_info "기존 설정 백업 완료"
    fi

    # 헤더 작성
    cat > "$OUTPUT_FILE" <<EOF
# 시스템 백업 경로 설정
# $(date '+%Y-%m-%d %H:%M:%S')에 자동 생성됨
# 수동 편집 가능하지만, configure_backup_targets.sh 사용 권장

# 필수 시스템 설정 디렉토리 (항상 백업)
BACKUP_PATHS=(
EOF

    # 활성화된 경로만 추가
    for i in "${!ALL_PATHS[@]}"; do
        if [ "${ALL_ENABLED[$i]}" = "true" ]; then
            local path="${ALL_PATHS[$i]}"
            local desc="${ALL_DESCRIPTIONS[$i]}"

            if [ -n "$desc" ]; then
                echo "    \"$path\"    # $desc" >> "$OUTPUT_FILE"
            else
                echo "    \"$path\"" >> "$OUTPUT_FILE"
            fi
        fi
    done

    echo ")" >> "$OUTPUT_FILE"

    # 제외 경로 추가
    cat >> "$OUTPUT_FILE" <<'EOF'

# 명시적 제외 경로 (사용자 데이터)
EXCLUDE_PATHS=(
    # 사용자 데이터 (선택하지 않은 경우)
    "/home"
    "/opt"

    # 대용량 데이터 디렉토리
    "/var/www"
    "/srv"
    "/var/lib/docker"
    "/var/lib/mysql"
    "/var/lib/postgresql"

    # 임시 및 캐시
    "/tmp"
    "/var/tmp"
    "/var/cache"
    "/var/backups"

    # 시스템 가상 파일시스템
    "/proc"
    "/sys"
    "/dev"
    "/run"

    # 마운트 포인트
    "/mnt"
    "/media"

    # 기타
    "/lost+found"
    "/swapfile"
    "*/.cache"
)

# 백업할 파일 패턴 제외
EXCLUDE_PATTERNS=(
    "*.log"
    "*.cache"
    "*.tmp"
    "*~"
    "*.bak"
    ".DS_Store"
    "*.sock"
    "*.pid"
    "*.lock"
)
EOF

    print_success "설정 파일 저장 완료: $OUTPUT_FILE"

    # 요약 출력
    echo ""
    print_header "백업 설정 요약"

    local enabled_count=0
    echo ""
    echo "활성화된 백업 경로:"
    for i in "${!ALL_PATHS[@]}"; do
        if [ "${ALL_ENABLED[$i]}" = "true" ]; then
            echo "  ✓ ${ALL_PATHS[$i]}"
            ((enabled_count++))
        fi
    done

    echo ""
    print_info "총 ${enabled_count}개 경로가 백업됩니다"

    # 예상 크기 계산
    estimate_total_size
}

#############################################
# 예상 크기 계산
#############################################

estimate_total_size() {
    echo ""
    print_info "예상 백업 크기 계산 중..."

    local total_kb=0
    local calc_success=false

    for i in "${!ALL_PATHS[@]}"; do
        if [ "${ALL_ENABLED[$i]}" = "true" ]; then
            local path="${ALL_PATHS[$i]}"

            if [ -e "$path" ]; then
                local size_kb=$(du -sk "$path" 2>/dev/null | awk '{print $1}' || echo 0)
                total_kb=$((total_kb + size_kb))
                calc_success=true
            fi
        fi
    done

    if [ "$calc_success" = true ]; then
        local total_mb=$((total_kb / 1024))
        local total_gb=$((total_mb / 1024))

        echo ""
        echo "예상 백업 크기:"
        echo "  압축 전: 약 ${total_mb}MB (${total_gb}GB)"
        echo "  압축 후: 약 $((total_mb * 70 / 100))MB (30% 압축 가정)"

        # 백업 시간 추정
        local est_minutes=$((total_gb + 1))
        if [ $est_minutes -lt 5 ]; then
            est_minutes=5
        fi
        echo "  예상 시간: 약 ${est_minutes}분"
    fi

    echo ""
}

#############################################
# 대화형 루프
#############################################

interactive_mode() {
    while true; do
        clear
        display_and_select

        read -p "명령 입력: " input

        case "$input" in
            [0-9]*)
                toggle_item "$input"
                sleep 1
                ;;
            all)
                for i in "${!ALL_ENABLED[@]}"; do
                    if [ "${ALL_FIXED[$i]}" != "true" ]; then
                        ALL_ENABLED[$i]="true"
                    fi
                done
                print_success "모든 항목 활성화"
                sleep 1
                ;;
            none)
                for i in "${!ALL_ENABLED[@]}"; do
                    if [ "${ALL_FIXED[$i]}" != "true" ]; then
                        ALL_ENABLED[$i]="false"
                    fi
                done
                print_info "필수 항목 제외 모두 비활성화"
                sleep 1
                ;;
            recommend)
                apply_recommended
                sleep 1
                ;;
            save)
                save_configuration
                echo ""
                print_success "백업 설정 완료!"
                print_info "이제 백업을 실행하세요: sudo ./backup_system.sh"
                echo ""
                break
                ;;
            quit)
                print_info "저장하지 않고 종료합니다"
                exit 0
                ;;
            *)
                print_error "알 수 없는 명령입니다"
                sleep 1
                ;;
        esac
    done
}

#############################################
# 메인
#############################################

main() {
    echo "=== 백업 대상 설정 도구 (YAML 기반) ==="
    echo ""

    # YAML 파일 파싱
    print_info "설정 파일 로드 중: $YAML_FILE"
    parse_yaml

    print_success "${#ALL_PATHS[@]}개 항목 로드 완료"
    sleep 1

    # 대화형 모드
    interactive_mode
}

main "$@"
