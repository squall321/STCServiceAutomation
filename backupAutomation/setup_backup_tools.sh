#!/bin/bash

# 백업 도구 설치 스크립트
# 온라인/오프라인 환경 모두 지원

set -eo pipefail

# 출력 버퍼링 비활성화
export PYTHONUNBUFFERED=1
# stdbuf 테스트 (입력 블로킹 방지)
echo -n "" | stdbuf -o0 -e0 cat > /dev/null 2>&1 || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_DIR="$SCRIPT_DIR/packages"
TOOLS_ARCHIVE="backup_tools.tar.gz"

# 색상 코드
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() { echo -e "\n${BLUE}=== $1 ===${NC}" >&2; }
print_success() { echo -e "${GREEN}✓${NC} $1" >&2; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1" >&2; }
print_error() { echo -e "${RED}❌${NC} $1" >&2; }
print_info() { echo -e "${BLUE}ℹ${NC} $1" >&2; }

# 필수 패키지 목록
REQUIRED_PACKAGES=(
    "rsync"           # 파일 동기화 및 백업
    "pigz"            # 병렬 gzip 압축
    "pv"              # 진행률 표시
    "attr"            # 확장 속성 지원
    "acl"             # ACL 권한 지원
    "jq"              # JSON 파싱
    "bc"              # 계산기
)

# RAID 도구 (선택적)
RAID_PACKAGES=(
    "mdadm"           # 소프트웨어 RAID
    "smartmontools"   # 디스크 건강 체크
)

# LVM 도구 (선택적)
LVM_PACKAGES=(
    "lvm2"            # LVM 관리
)

# 네트워크 도구
NETWORK_PACKAGES=(
    "iproute2"        # ip 명령
    "net-tools"       # ifconfig 등
    "iptables"        # 방화벽
)

#############################################
# 온라인 모드: 패키지 다운로드
#############################################

download_packages() {
    local auto_mode="${1:-}"

    print_header "백업 도구 패키지 다운로드 (온라인 모드)"

    print_info "패키지 다운로드를 시작합니다..."

    # 디렉토리 생성
    mkdir -p "$PACKAGES_DIR"
    cd "$PACKAGES_DIR"

    # 기존 파일 정리
    rm -f *.deb 2>/dev/null || true

    # 필수 패키지 다운로드
    print_info "필수 패키지 다운로드 중..."
    echo "" >&2
    local all_packages=("${REQUIRED_PACKAGES[@]}")

    # 선택적 패키지 추가 여부 확인 (비대화형 모드 지원)
    if [ "$auto_mode" = "auto" ]; then
        # 자동 모드 (네트워크 도구만 포함)
        print_info "자동 모드: 네트워크 도구 자동 포함 (RAID/LVM 제외)"
        all_packages+=("${NETWORK_PACKAGES[@]}")
    else
        # 대화형 모드 (터미널 입력 가능)
        read -p "RAID 도구를 포함하시겠습니까? (y/N): " include_raid
        if [[ "$include_raid" =~ ^[Yy]$ ]]; then
            all_packages+=("${RAID_PACKAGES[@]}")
        fi

        read -p "LVM 도구를 포함하시겠습니까? (y/N): " include_lvm
        if [[ "$include_lvm" =~ ^[Yy]$ ]]; then
            all_packages+=("${LVM_PACKAGES[@]}")
        fi

        read -p "네트워크 도구를 포함하시겠습니까? (권장) (Y/n): " include_network
        if [[ ! "$include_network" =~ ^[Nn]$ ]]; then
            all_packages+=("${NETWORK_PACKAGES[@]}")
        fi
    fi

    # 각 패키지와 의존성 다운로드
    for pkg in "${all_packages[@]}"; do
        echo -n "다운로드 중: $pkg ... " >&2

        # 패키지가 이미 설치되어 있는지 확인
        if dpkg -l | grep -q "^ii  $pkg "; then
            echo "이미 설치됨" >&2
            # 다운로드는 진행 (오프라인 PC용)
        fi

        # 패키지 다운로드 (의존성 포함)
        if apt-get download "$pkg" >/dev/null 2>&1; then
            echo "✓" >&2
        else
            echo "⚠ 실패 (건너뜀)" >&2
            continue
        fi

        # 의존성 다운로드
        local deps=$(apt-cache depends "$pkg" 2>/dev/null | \
                     grep "Depends:" | \
                     awk '{print $2}' | \
                     grep -v "^<" | \
                     tr '\n' ' ')

        for dep in $deps; do
            # 이미 다운로드했거나 시스템 필수 패키지는 스킵
            if [ -f "${dep}_"*.deb ] || [[ "$dep" =~ ^(libc6|libgcc|base-files)$ ]]; then
                continue
            fi

            apt-get download "$dep" &>/dev/null || true
        done
    done

    # 다운로드된 패키지 개수
    local deb_count=$(ls -1 *.deb 2>/dev/null | wc -l)
    echo "" >&2
    print_success "다운로드 완료: ${deb_count}개 패키지"

    # 아카이브 생성
    cd "$SCRIPT_DIR"
    print_info "백업 도구 아카이브 생성 중..."
    tar -czf "$TOOLS_ARCHIVE" -C packages .

    local archive_size=$(du -h "$TOOLS_ARCHIVE" | awk '{print $1}')
    print_success "아카이브 생성 완료: $TOOLS_ARCHIVE ($archive_size)"

    echo >&2 ""
    print_info "다음 단계:"
    echo >&2 "1. $TOOLS_ARCHIVE 파일을 오프라인 PC로 복사"
    echo >&2 "2. 오프라인 PC에서 실행: ./setup_backup_tools.sh --install"
}

#############################################
# 오프라인 모드: 패키지 설치
#############################################

install_packages() {
    print_header "백업 도구 설치 (오프라인 모드)"

    # Root 권한 확인
    if [ "$EUID" -ne 0 ]; then
        print_error "이 명령은 root 권한이 필요합니다."
        print_info "다시 실행: sudo ./setup_backup_tools.sh --install"
        exit 1
    fi

    # 아카이브 확인
    if [ ! -f "$SCRIPT_DIR/$TOOLS_ARCHIVE" ]; then
        print_error "백업 도구 아카이브를 찾을 수 없습니다: $TOOLS_ARCHIVE"
        print_info "온라인 PC에서 먼저 다운로드하세요: ./setup_backup_tools.sh --download"
        exit 1
    fi

    # 압축 해제
    print_info "아카이브 압축 해제 중..."
    mkdir -p "$PACKAGES_DIR"
    tar -xzf "$TOOLS_ARCHIVE" -C "$PACKAGES_DIR"

    local deb_count=$(ls -1 "$PACKAGES_DIR"/*.deb 2>/dev/null | wc -l)
    print_success "$deb_count 개 패키지 발견"

    # 패키지 설치
    print_info "패키지 설치 중..."
    cd "$PACKAGES_DIR"

    # dpkg로 설치 시도
    echo ""
    if dpkg -i *.deb 2>/dev/null; then
        print_success "모든 패키지 설치 완료"
    else
        print_warning "일부 의존성 문제 발생. 해결 시도 중..."
        # 의존성 문제 해결
        apt-get install -f -y 2>/dev/null || {
            print_error "의존성 해결 실패"
            print_info "수동으로 해결이 필요할 수 있습니다: sudo apt-get install -f"
        }
    fi

    cd "$SCRIPT_DIR"

    # 설치 검증
    echo ""
    verify_installation
}

#############################################
# 설치 검증
#############################################

verify_installation() {
    print_header "설치 검증"

    local all_ok=true

    for pkg in "${REQUIRED_PACKAGES[@]}"; do
        # acl 패키지는 getfacl 명령으로 확인
        local check_cmd="$pkg"
        if [ "$pkg" = "acl" ]; then
            check_cmd="getfacl"
        fi

        if command -v "$check_cmd" &>/dev/null || dpkg -l | grep -q "^ii  $pkg "; then
            print_success "$pkg 설치됨"
        else
            print_error "$pkg 설치 안 됨"
            all_ok=false
        fi
    done

    echo ""
    if [ "$all_ok" = true ]; then
        print_success "모든 필수 도구가 설치되었습니다."
        echo ""
        print_info "백업 시스템을 사용할 준비가 되었습니다."
        print_info "다음 명령으로 백업 실행: ./backup_system.sh"
        return 0
    else
        print_error "일부 도구가 설치되지 않았습니다."
        return 1
    fi
}

#############################################
# 도구 확인 (설치 없이 검증만)
#############################################

check_tools() {
    print_header "백업 도구 확인"

    local all_ok=true
    local missing_tools=()

    for pkg in "${REQUIRED_PACKAGES[@]}"; do
        # acl 패키지는 getfacl 명령으로 확인
        local check_cmd="$pkg"
        if [ "$pkg" = "acl" ]; then
            check_cmd="getfacl"
        fi

        if command -v "$check_cmd" &>/dev/null; then
            local version=$(dpkg -l "$pkg" 2>/dev/null | grep "^ii" | awk '{print $3}')
            print_success "$pkg (버전: ${version:-unknown})"
        else
            print_warning "$pkg 설치 안 됨"
            missing_tools+=("$pkg")
            all_ok=false
        fi
    done

    echo ""
    if [ "$all_ok" = true ]; then
        print_success "모든 도구가 준비되었습니다."
        return 0
    else
        print_warning "다음 도구가 설치되지 않았습니다:"
        for tool in "${missing_tools[@]}"; do
            echo "  - $tool"
        done
        echo ""
        print_info "설치 방법:"
        print_info "  온라인: sudo apt-get install ${missing_tools[*]}"
        print_info "  오프라인: ./setup_backup_tools.sh --download (온라인 PC)"
        print_info "           ./setup_backup_tools.sh --install (오프라인 PC)"
        return 1
    fi
}

#############################################
# 사용법
#############################################

usage() {
    cat <<EOF
백업 도구 설치 스크립트

사용법:
  $0 [옵션]

옵션:
  --download      온라인 PC에서 패키지 다운로드 (대화형)
  --download-auto 온라인 PC에서 패키지 다운로드 (자동: 네트워크 도구 포함, RAID/LVM 제외)
  --install       오프라인 PC에서 패키지 설치 (sudo 필요)
  --check         설치된 도구 확인
  --help          이 도움말 표시

예시:
  # 온라인 PC에서 다운로드 (대화형)
  ./setup_backup_tools.sh --download

  # 온라인 PC에서 다운로드 (자동)
  ./setup_backup_tools.sh --download-auto

  # 오프라인 PC에서 설치
  sudo ./setup_backup_tools.sh --install

  # 설치 확인
  ./setup_backup_tools.sh --check

EOF
}

#############################################
# 메인
#############################################

main() {
    echo "=== 백업 도구 설치 스크립트 ===" >&2
    echo "" >&2

    case "${1:-}" in
        --download)
            download_packages
            ;;
        --download-auto)
            # 자동 모드: auto 파라미터 전달
            download_packages "auto"
            ;;
        --install)
            install_packages
            ;;
        --check)
            check_tools
            ;;
        --help|-h)
            usage
            ;;
        "")
            # 인수 없이 실행 시 대화형 모드
            echo "모드를 선택하세요:"
            echo "1) 패키지 다운로드 (대화형)"
            echo "2) 패키지 다운로드 (자동)"
            echo "3) 패키지 설치 (오프라인)"
            echo "4) 도구 확인"
            echo "5) 종료"
            read -p "선택 (1-5): " choice

            case $choice in
                1) download_packages ;;
                2) download_packages "auto" ;;
                3) install_packages ;;
                4) check_tools ;;
                5) exit 0 ;;
                *) print_error "잘못된 선택"; exit 1 ;;
            esac
            ;;
        *)
            print_error "알 수 없는 옵션: $1"
            usage
            exit 1
            ;;
    esac
}

main "$@"
