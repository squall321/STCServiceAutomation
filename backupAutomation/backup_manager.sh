#!/bin/bash

# 백업 관리 스크립트
# 백업 목록 조회, 정보 표시, 삭제, 검증 등

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_ROOT="$SCRIPT_DIR/backups"

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
# 백업 목록
#############################################

list_backups() {
    print_header "백업 목록"

    if [ ! -d "$BACKUP_ROOT/metadata" ]; then
        print_error "백업 디렉토리를 찾을 수 없습니다"
        return 1
    fi

    local metadata_files=("$BACKUP_ROOT/metadata"/*.json)

    if [ ! -f "${metadata_files[0]}" ]; then
        print_warning "백업이 없습니다"
        return 0
    fi

    echo ""
    printf "%-25s %-20s %-10s %-15s %-10s\n" "백업 ID" "날짜" "크기" "소요 시간" "상태"
    printf "%s\n" "--------------------------------------------------------------------------------------"

    for metadata_file in "${metadata_files[@]}"; do
        if [ ! -f "$metadata_file" ]; then
            continue
        fi

        # 메타데이터 파싱
        if command -v jq &>/dev/null; then
            local backup_id=$(jq -r '.backup_id' "$metadata_file")
            local timestamp=$(jq -r '.timestamp' "$metadata_file")
            local size_bytes=$(jq -r '.size_bytes' "$metadata_file")
            local duration=$(jq -r '.duration_seconds' "$metadata_file")
        else
            local backup_id=$(grep '"backup_id"' "$metadata_file" | cut -d'"' -f4)
            local timestamp=$(grep '"timestamp"' "$metadata_file" | cut -d'"' -f4)
            local size_bytes=$(grep '"size_bytes"' "$metadata_file" | cut -d':' -f2 | tr -d ' ,')
            local duration=$(grep '"duration_seconds"' "$metadata_file" | cut -d':' -f2 | tr -d ' ,')
        fi

        # 크기 변환
        local size_mb=$((size_bytes / 1024 / 1024))
        local size_display="${size_mb}MB"

        # 시간 변환
        local minutes=$((duration / 60))
        local seconds=$((duration % 60))
        local time_display="${minutes}m ${seconds}s"

        # 상태 확인
        local archive_path="$BACKUP_ROOT/snapshots/${backup_id}.tar.gz"
        local dir_path="$BACKUP_ROOT/snapshots/${backup_id}"

        local status="❌"
        if [ -f "$archive_path" ]; then
            status="✓"
        elif [ -d "$dir_path" ]; then
            status="✓"
        fi

        printf "%-25s %-20s %-10s %-15s %-10s\n" \
            "$backup_id" "$timestamp" "$size_display" "$time_display" "$status"
    done

    echo ""
}

#############################################
# 백업 상세 정보
#############################################

show_info() {
    local backup_id="$1"

    if [ -z "$backup_id" ]; then
        print_error "백업 ID가 지정되지 않았습니다"
        return 1
    fi

    print_header "백업 상세 정보: $backup_id"

    local metadata_file="$BACKUP_ROOT/metadata/${backup_id}.json"

    if [ ! -f "$metadata_file" ]; then
        print_error "백업을 찾을 수 없습니다: $backup_id"
        return 1
    fi

    # 메타데이터 출력
    echo ""
    if command -v jq &>/dev/null; then
        jq . "$metadata_file"
    else
        cat "$metadata_file"
    fi

    echo ""

    # 파일 위치
    local archive_path="$BACKUP_ROOT/snapshots/${backup_id}.tar.gz"
    local dir_path="$BACKUP_ROOT/snapshots/${backup_id}"

    echo "파일 위치:"
    if [ -f "$archive_path" ]; then
        echo "  압축 파일: $archive_path"
        ls -lh "$archive_path"
    fi
    if [ -d "$dir_path" ]; then
        echo "  디렉토리: $dir_path"
        du -sh "$dir_path"
    fi

    echo ""
}

#############################################
# 백업 검증
#############################################

verify_backup() {
    local backup_id="$1"

    if [ -z "$backup_id" ]; then
        print_error "백업 ID가 지정되지 않았습니다"
        return 1
    fi

    print_header "백업 무결성 검사: $backup_id"

    local archive_path="$BACKUP_ROOT/snapshots/${backup_id}.tar.gz"

    if [ ! -f "$archive_path" ]; then
        print_error "압축 파일을 찾을 수 없습니다: $archive_path"
        return 1
    fi

    # 체크섬 검증
    local checksum_file="${archive_path}.sha256"
    if [ -f "$checksum_file" ]; then
        print_info "체크섬 검증 중..."
        if sha256sum -c "$checksum_file"; then
            print_success "체크섬 일치"
        else
            print_error "체크섬 불일치"
            return 1
        fi
    else
        print_warning "체크섬 파일이 없습니다"
    fi

    # tar 파일 테스트
    print_info "압축 파일 테스트 중..."
    if tar -tzf "$archive_path" >/dev/null 2>&1; then
        print_success "압축 파일 정상"
    else
        print_error "압축 파일이 손상되었습니다"
        return 1
    fi

    print_success "백업 무결성 확인 완료"
    echo ""
}

#############################################
# 백업 삭제
#############################################

delete_backup() {
    local backup_id="$1"

    if [ -z "$backup_id" ]; then
        print_error "백업 ID가 지정되지 않았습니다"
        return 1
    fi

    print_header "백업 삭제: $backup_id"

    # 확인
    print_warning "이 백업을 삭제합니다: $backup_id"
    echo ""
    read -p "정말 삭제하시겠습니까? (yes 입력): " confirm

    if [ "$confirm" != "yes" ]; then
        print_info "삭제를 취소했습니다"
        return 0
    fi

    # 파일 삭제
    local metadata_file="$BACKUP_ROOT/metadata/${backup_id}.json"
    local archive_path="$BACKUP_ROOT/snapshots/${backup_id}.tar.gz"
    local dir_path="$BACKUP_ROOT/snapshots/${backup_id}"
    local checksum_file="${archive_path}.sha256"

    local deleted=false

    if [ -f "$metadata_file" ]; then
        rm -f "$metadata_file"
        print_success "메타데이터 삭제"
        deleted=true
    fi

    if [ -f "$archive_path" ]; then
        rm -f "$archive_path"
        print_success "압축 파일 삭제"
        deleted=true
    fi

    if [ -f "$checksum_file" ]; then
        rm -f "$checksum_file"
        print_success "체크섬 파일 삭제"
    fi

    if [ -d "$dir_path" ]; then
        rm -rf "$dir_path"
        print_success "백업 디렉토리 삭제"
        deleted=true
    fi

    if [ "$deleted" = true ]; then
        print_success "백업 삭제 완료"
    else
        print_warning "삭제할 파일을 찾을 수 없습니다"
    fi

    echo ""
}

#############################################
# 백업 정리 (보관 정책)
#############################################

cleanup_old_backups() {
    print_header "오래된 백업 정리"

    # 설정 로드
    if [ -f "$SCRIPT_DIR/config/backup_policy.conf" ]; then
        source "$SCRIPT_DIR/config/backup_policy.conf"
    fi

    local keep_minimum=${KEEP_MINIMUM:-3}
    local max_age_days=${MAX_BACKUP_AGE_DAYS:-90}

    print_info "정책: 최소 ${keep_minimum}개 보관, 최대 ${max_age_days}일"

    # 백업 목록 (날짜순 정렬)
    local metadata_files=($(ls -t "$BACKUP_ROOT/metadata"/*.json 2>/dev/null))
    local total_backups=${#metadata_files[@]}

    if [ $total_backups -eq 0 ]; then
        print_warning "백업이 없습니다"
        return 0
    fi

    print_info "총 백업 개수: $total_backups"

    # 최소 보관 개수 확인
    if [ $total_backups -le $keep_minimum ]; then
        print_info "모든 백업이 최소 보관 정책에 포함됩니다"
        return 0
    fi

    # 오래된 백업 찾기
    local now=$(date +%s)
    local to_delete=()

    local idx=0
    for metadata_file in "${metadata_files[@]}"; do
        ((idx++))

        # 최소 보관 개수는 유지
        if [ $idx -le $keep_minimum ]; then
            continue
        fi

        # 백업 ID 추출
        local backup_id=$(basename "$metadata_file" .json)

        # 백업 날짜 추출
        if command -v jq &>/dev/null; then
            local timestamp=$(jq -r '.timestamp' "$metadata_file")
        else
            local timestamp=$(grep '"timestamp"' "$metadata_file" | cut -d'"' -f4)
        fi

        # 날짜 변환
        local backup_date=$(date -d "$timestamp" +%s 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S" "$timestamp" +%s 2>/dev/null)

        if [ -z "$backup_date" ]; then
            continue
        fi

        # 나이 계산
        local age_seconds=$((now - backup_date))
        local age_days=$((age_seconds / 86400))

        if [ $age_days -gt $max_age_days ]; then
            to_delete+=("$backup_id")
            echo "  삭제 대상: $backup_id (${age_days}일 경과)"
        fi
    done

    if [ ${#to_delete[@]} -eq 0 ]; then
        print_info "삭제할 백업이 없습니다"
        return 0
    fi

    echo ""
    print_warning "${#to_delete[@]}개 백업을 삭제합니다"
    echo ""
    read -p "계속하시겠습니까? (y/N): " confirm

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_info "정리를 취소했습니다"
        return 0
    fi

    # 삭제 실행
    for backup_id in "${to_delete[@]}"; do
        delete_backup "$backup_id"
    done

    print_success "백업 정리 완료"
    echo ""
}

#############################################
# 디스크 사용량
#############################################

show_disk_usage() {
    print_header "백업 디스크 사용량"

    echo ""
    echo "백업 디렉토리: $BACKUP_ROOT"
    echo ""

    du -sh "$BACKUP_ROOT" 2>/dev/null || print_warning "백업 디렉토리를 찾을 수 없습니다"

    echo ""
    echo "세부 사용량:"
    du -sh "$BACKUP_ROOT"/* 2>/dev/null || true

    echo ""
}

#############################################
# 사용법
#############################################

usage() {
    cat <<EOF
백업 관리 스크립트

사용법:
  $0 [명령] [옵션]

명령:
  list                백업 목록 표시
  info BACKUP_ID      백업 상세 정보 표시
  verify BACKUP_ID    백업 무결성 검사
  delete BACKUP_ID    백업 삭제
  cleanup             오래된 백업 정리
  disk                디스크 사용량 표시
  help                이 도움말 표시

예시:
  # 백업 목록
  ./backup_manager.sh list

  # 백업 정보
  ./backup_manager.sh info backup_20231204_153045

  # 백업 검증
  ./backup_manager.sh verify backup_20231204_153045

  # 백업 삭제
  ./backup_manager.sh delete backup_20231204_153045

  # 오래된 백업 정리
  ./backup_manager.sh cleanup

EOF
}

#############################################
# 메인
#############################################

main() {
    local command="${1:-list}"

    case "$command" in
        list)
            list_backups
            ;;
        info)
            show_info "$2"
            ;;
        verify)
            verify_backup "$2"
            ;;
        delete)
            delete_backup "$2"
            ;;
        cleanup)
            cleanup_old_backups
            ;;
        disk)
            show_disk_usage
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            print_error "알 수 없는 명령: $command"
            usage
            exit 1
            ;;
    esac
}

main "$@"
