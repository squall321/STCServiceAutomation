#!/bin/bash

# 오프라인 설치를 위한 apt 패키지 복원 스크립트 (개선 버전)
# 시스템 안전성을 고려한 충돌 감지 및 선택적 설치

set -o pipefail  # 파이프라인 에러 감지

# Bash 4.0+ 요구 (연관 배열 사용)
if ((BASH_VERSINFO[0] < 4)); then
    echo "❌ 이 스크립트는 Bash 4.0 이상이 필요합니다."
    echo "현재 버전: $BASH_VERSION"
    exit 1
fi

# 전역 변수
declare -A INSTALLED_PACKAGES  # 현재 설치된 패키지 [name]=version
declare -A BACKUP_PACKAGES     # 백업 패키지 [name]=version
declare -A BACKUP_PACKAGE_FILES # 백업 패키지 파일 [name]=filepath
declare -A PACKAGE_DEPENDENCIES # 패키지 의존성 [name]="dep1,dep2,..."
declare -a SAFE_TO_INSTALL     # 안전하게 설치 가능한 패키지
declare -a ALREADY_INSTALLED   # 이미 설치된 패키지
declare -a CONFLICT_PACKAGES   # 충돌 패키지
declare -A MISSING_DEPS        # 누락된 의존성 [name]=required_version

BACKUP_DIR=""
LOCAL_REPO="/var/local-apt-repo"
TEMP_ANALYSIS_DIR="/tmp/apt-restore-analysis-$$"

# 색상 코드
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#############################################
# 유틸리티 함수
#############################################

print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}❌${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# 정리 함수
cleanup() {
    if [ -d "$TEMP_ANALYSIS_DIR" ]; then
        rm -rf "$TEMP_ANALYSIS_DIR"
    fi
}

# 에러 시 정리
trap cleanup EXIT

#############################################
# 버전 비교 함수
#############################################

# dpkg --compare-versions를 사용한 버전 비교
# 반환값: 0 (같음), 1 (ver1 > ver2), 2 (ver1 < ver2)
compare_versions() {
    local ver1="$1"
    local ver2="$2"

    if dpkg --compare-versions "$ver1" eq "$ver2"; then
        return 0
    elif dpkg --compare-versions "$ver1" gt "$ver2"; then
        return 1
    else
        return 2
    fi
}

# 버전이 요구사항을 만족하는지 확인
# $1: 현재 버전, $2: 요구사항 (예: ">= 1.2.3", "= 2.0", "<< 3.0")
version_satisfies() {
    local current_ver="$1"
    local requirement="$2"

    # 요구사항 파싱
    if [[ "$requirement" =~ ^([>\<]=?|=)\ *(.+)$ ]]; then
        local op="${BASH_REMATCH[1]}"
        local req_ver="${BASH_REMATCH[2]}"

        case "$op" in
            ">=")
                dpkg --compare-versions "$current_ver" ge "$req_ver"
                return $?
                ;;
            ">>")
                dpkg --compare-versions "$current_ver" gt "$req_ver"
                return $?
                ;;
            "<=")
                dpkg --compare-versions "$current_ver" le "$req_ver"
                return $?
                ;;
            "<<")
                dpkg --compare-versions "$current_ver" lt "$req_ver"
                return $?
                ;;
            "=")
                dpkg --compare-versions "$current_ver" eq "$req_ver"
                return $?
                ;;
        esac
    fi

    # 요구사항이 없거나 파싱 실패 시 true 반환
    return 0
}

#############################################
# 패키지 정보 수집 함수
#############################################

# 현재 시스템에 설치된 패키지 정보 수집
check_installed_packages() {
    print_header "현재 시스템 패키지 분석 중"

    local count=0
    while IFS= read -r line; do
        # dpkg -l 출력 파싱: ii  package-name  version  architecture  description
        if [[ "$line" =~ ^ii\ +([^\ :]+)(:[^\ ]+)?\ +([^\ ]+) ]]; then
            local pkg_name="${BASH_REMATCH[1]}"
            local pkg_version="${BASH_REMATCH[3]}"
            INSTALLED_PACKAGES["$pkg_name"]="$pkg_version"
            ((count++))
        fi
    done < <(dpkg -l 2>/dev/null)

    print_success "시스템 패키지 ${count}개 분석 완료"
}

# 백업 패키지 정보 수집
scan_backup_packages() {
    print_header "백업 패키지 분석 중"

    local deb_files=("$PACKAGES_PATH"/*.deb)
    local total=${#deb_files[@]}
    local count=0

    if [ ! -f "${deb_files[0]}" ]; then
        print_error "백업 디렉토리에 .deb 파일을 찾을 수 없습니다: $PACKAGES_PATH"
        exit 1
    fi

    mkdir -p "$TEMP_ANALYSIS_DIR"

    print_info "총 ${total}개 패키지 분석 중..."

    for deb_file in "${deb_files[@]}"; do
        ((count++))

        # 진행률 표시 (10% 단위)
        if ((count % (total / 10 + 1) == 0)); then
            echo -n "."
        fi

        # 패키지 정보 추출
        local pkg_name=$(dpkg-deb -f "$deb_file" Package 2>/dev/null)
        local pkg_version=$(dpkg-deb -f "$deb_file" Version 2>/dev/null)
        local pkg_depends=$(dpkg-deb -f "$deb_file" Depends 2>/dev/null)
        local pkg_predepends=$(dpkg-deb -f "$deb_file" Pre-Depends 2>/dev/null)

        if [ -z "$pkg_name" ] || [ -z "$pkg_version" ]; then
            print_warning "패키지 정보를 읽을 수 없음: $(basename "$deb_file")"
            continue
        fi

        BACKUP_PACKAGES["$pkg_name"]="$pkg_version"
        BACKUP_PACKAGE_FILES["$pkg_name"]="$deb_file"

        # 의존성 정보 저장 (Pre-Depends와 Depends 합치기)
        local all_deps=""
        if [ -n "$pkg_predepends" ]; then
            all_deps="$pkg_predepends"
        fi
        if [ -n "$pkg_depends" ]; then
            if [ -n "$all_deps" ]; then
                all_deps="$all_deps, $pkg_depends"
            else
                all_deps="$pkg_depends"
            fi
        fi
        PACKAGE_DEPENDENCIES["$pkg_name"]="$all_deps"
    done

    echo ""
    print_success "백업 패키지 ${#BACKUP_PACKAGES[@]}개 분석 완료"
}

#############################################
# 의존성 분석 함수
#############################################

# 의존성 문자열 파싱 및 검증
# 반환: 0 (모두 만족), 1 (충돌 있음)
analyze_single_package_deps() {
    local pkg_name="$1"
    local deps_string="${PACKAGE_DEPENDENCIES[$pkg_name]}"
    local has_conflict=0

    if [ -z "$deps_string" ]; then
        return 0
    fi

    # 의존성 파싱: 쉼표로 구분, | (OR) 처리
    IFS=',' read -ra DEP_ARRAY <<< "$deps_string"

    for dep_item in "${DEP_ARRAY[@]}"; do
        # 공백 제거
        dep_item=$(echo "$dep_item" | xargs)

        # OR 의존성 (|) 처리 - 첫 번째 항목만 확인 (간소화)
        if [[ "$dep_item" =~ \| ]]; then
            dep_item=$(echo "$dep_item" | cut -d'|' -f1 | xargs)
        fi

        # 패키지명과 버전 요구사항 분리
        local dep_pkg=""
        local dep_ver_req=""

        if [[ "$dep_item" =~ ^([a-zA-Z0-9.+\-]+)\ *\((.+)\)$ ]]; then
            dep_pkg="${BASH_REMATCH[1]}"
            dep_ver_req="${BASH_REMATCH[2]}"
        elif [[ "$dep_item" =~ ^([a-zA-Z0-9.+\-]+)$ ]]; then
            dep_pkg="${BASH_REMATCH[1]}"
            dep_ver_req=""
        else
            continue
        fi

        # 가상 패키지나 특수 의존성 스킵
        # 1. 정확한 이름 매칭
        if [[ "$dep_pkg" =~ ^(debconf|perl|python3|awk|base-files|base-passwd)$ ]]; then
            continue
        fi

        # 2. ABI/API 가상 패키지 패턴
        if [[ "$dep_pkg" =~ -abi-[0-9] ]] || \
           [[ "$dep_pkg" =~ api-[0-9] ]] || \
           [[ "$dep_pkg" =~ ^perl-dbd ]] || \
           [[ "$dep_pkg" =~ ^perlapi- ]] || \
           [[ "$dep_pkg" =~ ^xorg-video-abi ]] || \
           [[ "$dep_pkg" =~ ^xorg-input-abi ]] || \
           [[ "$dep_pkg" =~ ^python[0-9.]+-.*-abi- ]] || \
           [[ "$dep_pkg" =~ -abi-[0-9]+$ ]] || \
           [[ "$dep_pkg" =~ ^default-dbus- ]] || \
           [[ "$dep_pkg" =~ ^lib.*-abi- ]]; then
            continue
        fi

        # 시스템에 설치된 버전 확인
        local installed_ver="${INSTALLED_PACKAGES[$dep_pkg]}"

        if [ -n "$installed_ver" ]; then
            # 시스템에 이미 설치되어 있음
            if [ -n "$dep_ver_req" ]; then
                # 버전 요구사항이 있는 경우 확인
                if ! version_satisfies "$installed_ver" "$dep_ver_req"; then
                    # 시스템 버전이 요구사항을 만족하지 않음
                    # 백업에 적절한 버전이 있는지 확인
                    local backup_ver="${BACKUP_PACKAGES[$dep_pkg]}"
                    if [ -n "$backup_ver" ] && version_satisfies "$backup_ver" "$dep_ver_req"; then
                        # 백업에 적절한 버전이 있음 - 문제없음
                        :
                    else
                        # 백업에도 적절한 버전이 없음 - 충돌!
                        MISSING_DEPS["$dep_pkg"]="$dep_ver_req"
                        has_conflict=1
                    fi
                fi
            fi
        else
            # 시스템에 설치되어 있지 않음
            # 백업에 있는지 확인
            local backup_ver="${BACKUP_PACKAGES[$dep_pkg]}"
            if [ -z "$backup_ver" ]; then
                # 백업에도 없음 - 누락!
                MISSING_DEPS["$dep_pkg"]="${dep_ver_req:-any}"
                has_conflict=1
            elif [ -n "$dep_ver_req" ]; then
                # 백업에 있지만 버전 확인 필요
                if ! version_satisfies "$backup_ver" "$dep_ver_req"; then
                    # 백업 버전이 요구사항을 만족하지 않음
                    MISSING_DEPS["$dep_pkg"]="$dep_ver_req"
                    has_conflict=1
                fi
            fi
        fi
    done

    return $has_conflict
}

#############################################
# 패키지 분류 함수
#############################################

classify_packages() {
    print_header "패키지 분류 중"

    local total=${#BACKUP_PACKAGES[@]}
    local count=0

    for pkg_name in "${!BACKUP_PACKAGES[@]}"; do
        ((count++))

        # 진행률 표시
        if ((count % (total / 20 + 1) == 0)); then
            printf "\r진행: %d/%d (%.0f%%)" "$count" "$total" "$((count * 100 / total))"
        fi

        local backup_ver="${BACKUP_PACKAGES[$pkg_name]}"
        local installed_ver="${INSTALLED_PACKAGES[$pkg_name]}"

        # 이미 설치된 패키지는 건너뛰기 (기존 버전 우선 정책)
        if [ -n "$installed_ver" ]; then
            ALREADY_INSTALLED+=("$pkg_name")
            continue
        fi

        # 의존성 분석
        if analyze_single_package_deps "$pkg_name"; then
            # 의존성 문제 없음
            SAFE_TO_INSTALL+=("$pkg_name")
        else
            # 의존성 충돌 있음
            CONFLICT_PACKAGES+=("$pkg_name")
        fi
    done

    echo ""
    print_success "패키지 분류 완료"
}

#############################################
# 결과 출력 함수
#############################################

display_analysis_results() {
    print_header "분석 결과"

    echo ""
    print_success "설치 가능: ${#SAFE_TO_INSTALL[@]}개"
    print_info "이미 설치됨 (건너뛸): ${#ALREADY_INSTALLED[@]}개"

    if [ ${#CONFLICT_PACKAGES[@]} -gt 0 ]; then
        print_warning "충돌 감지: ${#CONFLICT_PACKAGES[@]}개"
        print_warning "누락된 의존성: ${#MISSING_DEPS[@]}개"

        echo ""
        echo "충돌 패키지 상세:"
        for pkg in "${CONFLICT_PACKAGES[@]}"; do
            echo "  - $pkg (${BACKUP_PACKAGES[$pkg]})"
        done

        echo ""
        echo "누락된 의존성 패키지:"
        for dep_pkg in "${!MISSING_DEPS[@]}"; do
            local req="${MISSING_DEPS[$dep_pkg]}"
            local installed="${INSTALLED_PACKAGES[$dep_pkg]}"
            if [ -n "$installed" ]; then
                echo "  - $dep_pkg: 필요 [$req], 시스템 버전 [$installed] - 버전 불일치"
            else
                echo "  - $dep_pkg: 필요 [$req] - 시스템 및 백업에 없음"
            fi
        done
    else
        print_success "충돌: 0개"
    fi

    # 일부 이미 설치된 패키지 표시 (처음 10개)
    if [ ${#ALREADY_INSTALLED[@]} -gt 0 ]; then
        echo ""
        echo "이미 설치된 패키지 예시 (처음 10개):"
        local show_count=0
        for pkg in "${ALREADY_INSTALLED[@]}"; do
            if [ $show_count -ge 10 ]; then
                echo "  ... 외 $((${#ALREADY_INSTALLED[@]} - 10))개"
                break
            fi
            echo "  - $pkg (시스템: ${INSTALLED_PACKAGES[$pkg]}, 백업: ${BACKUP_PACKAGES[$pkg]})"
            ((show_count++))
        done
    fi
}

#############################################
# 누락 패키지 파일 생성
#############################################

generate_missing_packages_list() {
    local output_file="missing_packages.txt"

    print_header "누락 패키지 목록 생성"

    if [ ${#MISSING_DEPS[@]} -eq 0 ]; then
        print_info "누락된 패키지가 없습니다."
        return 0
    fi

    {
        echo "# 누락된 의존성 패키지 목록"
        echo "# 생성 시각: $(date)"
        echo "# 온라인 PC에서 다운로드가 필요한 패키지"
        echo ""

        for dep_pkg in "${!MISSING_DEPS[@]}"; do
            local req="${MISSING_DEPS[$dep_pkg]}"
            if [ "$req" = "any" ]; then
                echo "$dep_pkg"
            else
                # 버전 요구사항을 apt 형식으로 변환
                if [[ "$req" =~ ^([>\<]=?)\ *(.+)$ ]]; then
                    local op="${BASH_REMATCH[1]}"
                    local ver="${BASH_REMATCH[2]}"
                    # apt는 정확한 버전 지정만 지원하므로 요구 버전 기록
                    echo "$dep_pkg  # 필요: $op $ver"
                else
                    echo "$dep_pkg"
                fi
            fi
        done
    } > "$output_file"

    print_success "생성 완료: $output_file"
}

#############################################
# 다운로드 스크립트 생성
#############################################

generate_download_script() {
    local output_file="download_missing_packages.sh"

    print_header "다운로드 스크립트 생성"

    if [ ${#MISSING_DEPS[@]} -eq 0 ]; then
        print_info "누락된 패키지가 없어 스크립트 생성을 건너뜁니다."
        return 0
    fi

    {
        cat <<'SCRIPT_HEADER'
#!/bin/bash

# 온라인 PC에서 실행하여 누락 패키지 다운로드
# 생성된 백업 파일을 오프라인 PC로 복사하여 사용

set -e

DOWNLOAD_DIR="missing_packages_$(date +%Y%m%d_%H%M%S)"
BACKUP_FILE="missing-packages-$(date +%Y%m%d_%H%M%S).tar.gz"

echo "=== 누락 패키지 다운로드 스크립트 ==="
echo "다운로드 디렉토리: $DOWNLOAD_DIR"
echo ""

# 디렉토리 생성
mkdir -p "$DOWNLOAD_DIR"
cd "$DOWNLOAD_DIR"

# apt-get download는 의존성을 자동으로 다운로드하지 않으므로
# apt-rdepends 또는 apt-get install --download-only 사용

check_tools() {
    if ! command -v apt-rdepends &> /dev/null; then
        echo "⚠ apt-rdepends가 설치되지 않았습니다."
        echo "설치 중: sudo apt-get install -y apt-rdepends"
        sudo apt-get update
        sudo apt-get install -y apt-rdepends
    fi
}

check_tools

echo "패키지 다운로드 시작..."
echo ""

# 패키지 목록
PACKAGES=(
SCRIPT_HEADER

        # 패키지 목록 추가
        for dep_pkg in "${!MISSING_DEPS[@]}"; do
            echo "    \"$dep_pkg\""
        done

        cat <<'SCRIPT_FOOTER'
)

# 각 패키지와 의존성 다운로드
for pkg in "${PACKAGES[@]}"; do
    echo "다운로드 중: $pkg"

    # 패키지와 모든 의존성 다운로드
    # --download-only는 실제 설치하지 않고 다운로드만 수행
    sudo apt-get install --download-only -y "$pkg" 2>/dev/null || {
        echo "  ⚠ $pkg 다운로드 실패 (건너뜀)"
        continue
    }

    # /var/cache/apt/archives/에서 다운로드된 .deb 복사
    sudo cp /var/cache/apt/archives/*.deb . 2>/dev/null || true

    echo "  ✓ $pkg 완료"
done

# 중복 제거 및 소유권 변경
sudo chown $USER:$USER *.deb 2>/dev/null || true

# 다운로드된 패키지 개수
DEB_COUNT=$(ls *.deb 2>/dev/null | wc -l)
echo ""
echo "다운로드 완료: ${DEB_COUNT}개 패키지"

# 백업 생성
cd ..
echo ""
echo "백업 파일 생성 중..."
tar -czf "$BACKUP_FILE" "$DOWNLOAD_DIR"/*.deb
echo "✓ 백업 생성 완료: $BACKUP_FILE"

# 안내
echo ""
echo "=== 다음 단계 ==="
echo "1. $BACKUP_FILE 파일을 USB 등으로 오프라인 PC에 복사"
echo "2. 오프라인 PC에서 압축 해제:"
echo "   tar -xzf $BACKUP_FILE"
echo "3. 해제된 .deb 파일들을 패키지 디렉토리에 복사"
echo "   (restore_packages.sh 실행 시 표시되는 패키지 경로에 복사)"
echo "4. restore_packages.sh 재실행"
echo ""
echo "정리하려면: rm -rf $DOWNLOAD_DIR"

SCRIPT_FOOTER
    } > "$output_file"

    chmod +x "$output_file"

    print_success "생성 완료: $output_file"
    print_info "온라인 PC에서 실행: ./$output_file"
}

#############################################
# 안전한 설치 함수
#############################################

install_safe_packages() {
    print_header "패키지 설치"

    if [ ${#SAFE_TO_INSTALL[@]} -eq 0 ]; then
        print_warning "설치할 패키지가 없습니다."
        return 0
    fi

    echo ""
    echo "설치 가능 패키지: ${#SAFE_TO_INSTALL[@]}개"
    echo ""

    # 설치 확인
    read -p "설치를 진행하시겠습니까? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_info "설치를 취소했습니다."
        return 0
    fi

    # 로컬 저장소 생성
    print_info "로컬 APT 저장소 생성 중..."
    sudo mkdir -p "$LOCAL_REPO"

    # 설치할 패키지만 복사
    for pkg in "${SAFE_TO_INSTALL[@]}"; do
        local deb_file="${BACKUP_PACKAGE_FILES[$pkg]}"
        if [ -f "$deb_file" ]; then
            sudo cp "$deb_file" "$LOCAL_REPO/" 2>/dev/null
        fi
    done

    # Packages 인덱스 생성
    cd "$LOCAL_REPO"
    sudo dpkg-scanpackages . /dev/null 2>/dev/null | sudo tee Packages > /dev/null
    sudo gzip -f -c Packages | sudo tee Packages.gz > /dev/null
    cd - > /dev/null

    print_success "로컬 저장소 생성 완료"

    # sources.list에 추가
    print_info "로컬 저장소를 APT에 추가 중..."
    echo "deb [trusted=yes] file://$LOCAL_REPO ./" | sudo tee /etc/apt/sources.list.d/local-repo.list > /dev/null
    sudo apt-get update -o Dir::Etc::sourcelist="sources.list.d/local-repo.list" -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0" 2>/dev/null
    print_success "로컬 저장소 추가 완료"

    # 설치 방법 선택
    echo ""
    echo "설치 방법을 선택하세요:"
    echo "1) apt-get으로 설치 (권장 - 의존성 자동 처리)"
    echo "2) dpkg로 직접 설치"
    read -p "선택 (1-2): " install_choice

    case $install_choice in
        1)
            print_info "apt-get으로 설치 중..."
            # 패키지 이름 목록 생성
            local pkg_list=""
            for pkg in "${SAFE_TO_INSTALL[@]}"; do
                pkg_list="$pkg_list $pkg"
            done

            sudo apt-get install -y --allow-downgrades $pkg_list

            if [ $? -eq 0 ]; then
                print_success "설치 완료"
            else
                print_error "설치 중 일부 오류 발생"
                echo "의존성 문제 해결 시도 중..."
                sudo apt-get install -f -y
            fi
            ;;
        2)
            print_info "dpkg로 설치 중..."
            local deb_files=()
            for pkg in "${SAFE_TO_INSTALL[@]}"; do
                deb_files+=("${BACKUP_PACKAGE_FILES[$pkg]}")
            done

            sudo dpkg -i "${deb_files[@]}"

            # 의존성 문제 해결
            print_info "의존성 문제 해결 중..."
            sudo apt-get install -f -y

            print_success "설치 완료"
            ;;
        *)
            print_error "잘못된 선택입니다."
            return 1
            ;;
    esac

    # 설치 후 정리 옵션
    echo ""
    read -p "로컬 저장소를 제거하시겠습니까? (y/N): " cleanup_confirm
    if [[ "$cleanup_confirm" =~ ^[Yy]$ ]]; then
        sudo rm -f /etc/apt/sources.list.d/local-repo.list
        sudo apt-get update 2>/dev/null
        print_success "로컬 저장소 제거 완료"
    else
        print_info "로컬 저장소 유지: /etc/apt/sources.list.d/local-repo.list"
        print_info "나중에 제거하려면: sudo rm /etc/apt/sources.list.d/local-repo.list && sudo apt-get update"
    fi
}

#############################################
# 메인 프로세스
#############################################

main() {
    echo "=== APT 패키지 오프라인 복원 스크립트 (개선 버전) ==="
    echo "시스템 안전성을 위한 충돌 감지 및 선택적 설치"
    echo ""

    # Root 권한 확인
    if [ "$EUID" -ne 0 ]; then
        print_warning "일부 기능은 root 권한이 필요합니다."
        print_info "sudo 사용이 필요할 수 있습니다."
    fi

    # 명령줄 인자 처리
    local user_input="${1:-}"

    if [ -n "$user_input" ]; then
        # 인자가 제공된 경우
        if [ -f "$user_input" ] && [[ "$user_input" == *.tar.gz ]]; then
            # tar.gz 파일 경로가 제공됨
            print_header "백업 파일 사용"
            BACKUP_FILE="$user_input"
            print_success "백업 파일: $BACKUP_FILE"

            # 압축 해제
            print_header "백업 파일 압축 해제"
            BACKUP_DIR=$(basename "$BACKUP_FILE" .tar.gz)
            if [ ! -d "$BACKUP_DIR" ]; then
                tar -xzf "$BACKUP_FILE"
            fi
            print_success "압축 해제 완료: $BACKUP_DIR"

        elif [ -d "$user_input" ]; then
            # 디렉토리 경로가 제공됨
            print_header "패키지 디렉토리 사용"
            BACKUP_DIR="$user_input"
            print_success "패키지 디렉토리: $BACKUP_DIR"

        else
            print_error "유효하지 않은 경로: $user_input"
            echo ""
            echo "사용법:"
            echo "  $0                              # 현재 디렉토리에서 apt-backup-*.tar.gz 자동 검색"
            echo "  $0 /path/to/backup.tar.gz       # 특정 백업 파일 사용"
            echo "  $0 /path/to/packages/           # 특정 패키지 디렉토리 사용"
            exit 1
        fi
    else
        # 인자가 없으면 자동 검색
        print_header "백업 파일 검색"
        BACKUP_FILE=$(ls apt-backup-*.tar.gz 2>/dev/null | head -n 1)

        if [ -z "$BACKUP_FILE" ]; then
            print_error "백업 파일(apt-backup-*.tar.gz)을 찾을 수 없습니다."
            echo "현재 디렉토리에 백업 파일이 있는지 확인하세요."
            echo ""
            echo "사용법:"
            echo "  $0                              # 현재 디렉토리에서 apt-backup-*.tar.gz 자동 검색"
            echo "  $0 /path/to/backup.tar.gz       # 특정 백업 파일 사용"
            echo "  $0 /path/to/packages/           # 특정 패키지 디렉토리 사용"
            exit 1
        fi

        print_success "백업 파일 발견: $BACKUP_FILE"

        # 압축 해제
        print_header "백업 파일 압축 해제"
        if [ ! -d "$(basename "$BACKUP_FILE" .tar.gz)" ]; then
            tar -xzf "$BACKUP_FILE"
        fi
        BACKUP_DIR=$(basename "$BACKUP_FILE" .tar.gz)
        print_success "압축 해제 완료: $BACKUP_DIR"
    fi

    # 패키지 디렉토리 확인 및 설정
    if [ -d "$BACKUP_DIR/packages" ]; then
        # packages 서브디렉토리가 있는 경우 (표준 백업 구조)
        PACKAGES_PATH="$BACKUP_DIR/packages"
    elif [ -f "$BACKUP_DIR"/*.deb ] 2>/dev/null; then
        # 직접 .deb 파일이 있는 경우
        PACKAGES_PATH="$BACKUP_DIR"
    else
        print_error "패키지 파일을 찾을 수 없습니다."
        echo "확인할 경로: $BACKUP_DIR/packages/ 또는 $BACKUP_DIR/"
        exit 1
    fi

    # 패키지 개수 확인
    PACKAGE_COUNT=$(ls "$PACKAGES_PATH"/*.deb 2>/dev/null | wc -l)
    if [ "$PACKAGE_COUNT" -eq 0 ]; then
        print_error "패키지 디렉토리에 .deb 파일이 없습니다: $PACKAGES_PATH"
        exit 1
    fi
    print_info "발견된 패키지: $PACKAGE_COUNT 개 ($PACKAGES_PATH)"

    # 단계 1: 시스템 패키지 분석
    check_installed_packages

    # 단계 2: 백업 패키지 분석
    scan_backup_packages

    # 단계 3: 패키지 분류
    classify_packages

    # 단계 4: 결과 출력
    display_analysis_results

    # 단계 5: 충돌이 있는 경우 파일 생성
    if [ ${#CONFLICT_PACKAGES[@]} -gt 0 ]; then
        echo ""
        generate_missing_packages_list
        generate_download_script

        echo ""
        print_warning "충돌 패키지가 감지되었습니다."
        echo ""
        echo "다음 단계를 진행하세요:"
        echo "1. 온라인 PC에서 download_missing_packages.sh 실행"
        echo "2. 생성된 백업 파일을 이 PC로 복사"
        echo "3. 압축 해제 후 .deb 파일들을 $PACKAGES_PATH 에 추가"
        echo "4. 이 스크립트 재실행"
        echo ""

        if [ ${#SAFE_TO_INSTALL[@]} -gt 0 ]; then
            read -p "충돌 없는 ${#SAFE_TO_INSTALL[@]}개 패키지만 먼저 설치하시겠습니까? (y/N): " partial_install
            if [[ "$partial_install" =~ ^[Yy]$ ]]; then
                install_safe_packages
            else
                print_info "설치를 건너뜁니다."
            fi
        fi
    else
        # 충돌 없음 - 바로 설치 진행
        echo ""
        install_safe_packages
    fi

    echo ""
    print_success "=== 프로세스 완료 ==="
    print_info "설치된 패키지 확인: dpkg -l | grep '^ii'"
}

# 스크립트 실행
main "$@"
