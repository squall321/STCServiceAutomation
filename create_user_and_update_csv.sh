#!/bin/bash
#
# create_user_and_update_csv.sh
# CSV 파일의 각 서버에 새 사용자를 생성하고, CSV를 업데이트
#
# 사용법:
#   ./create_user_and_update_csv.sh <input.csv> <new_username> <new_password>
#
# 동작:
#   1. CSV의 각 서버에 SSH로 접속 (기존 계정 사용)
#   2. 새 사용자 계정 생성
#   3. CSV의 ssh_user, ssh_password를 새 계정 정보로 업데이트
#   4. <input>_modified.csv로 저장
#

# Removed 'set -e' for better error handling in loops
# Individual critical operations will be checked explicitly

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# sshpass 설치 확인
check_sshpass() {
    if ! command -v sshpass &> /dev/null; then
        echo -e "${RED}[ERROR]${NC} sshpass가 설치되어 있지 않습니다."
        echo "설치 명령어: sudo apt install sshpass"
        exit 1
    fi
}

# 사용법 출력
usage() {
    echo "사용법: $0 <input.csv> <new_username> <new_password>"
    echo ""
    echo "예제:"
    echo "  $0 servers.csv koopark MyPass123!"
    echo ""
    echo "CSV 형식:"
    echo "  ip,role,ssh_user,ssh_password"
    echo "  192.168.1.1,controller,root,oldpass123"
    echo "  192.168.1.2,compute,root,oldpass123"
    echo ""
    echo "동작:"
    echo "  1. CSV의 각 서버에 기존 계정으로 SSH 접속"
    echo "  2. 새 사용자 생성 (sudo 권한 부여)"
    echo "  3. CSV 업데이트 (ssh_user, ssh_password 변경)"
    echo "  4. <input>_modified.csv로 저장"
    exit 1
}

# 서버에 사용자 생성
create_user_on_server() {
    local ip="$1"
    local current_user="$2"
    local current_password="$3"
    local new_user="$4"
    local new_password="$5"
    local timeout=10

    # SSH 옵션
    local ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=$timeout -o LogLevel=ERROR"

    echo -e "  ${BLUE}[*]${NC} $ip - 사용자 생성 중..."

    # 사용자 존재 확인
    local user_exists
    user_exists=$(sshpass -p "$current_password" ssh $ssh_opts "${current_user}@${ip}" "id -u $new_user &>/dev/null && echo 'yes' || echo 'no'" 2>/dev/null)

    if [ "$user_exists" = "yes" ]; then
        echo -e "    └─ ${YELLOW}[WARN]${NC} 사용자 '$new_user'가 이미 존재함, 비밀번호만 변경"

        # 비밀번호 변경
        sshpass -p "$current_password" ssh $ssh_opts "${current_user}@${ip}" "echo '$new_user:$new_password' | sudo chpasswd" 2>/dev/null

        if [ $? -eq 0 ]; then
            echo -e "    └─ ${GREEN}[OK]${NC} 비밀번호 변경 완료"
        else
            echo -e "    └─ ${RED}[ERROR]${NC} 비밀번호 변경 실패"
            return 1
        fi
    else
        echo -e "    └─ 새 사용자 생성 중..."

        # 사용자 생성 스크립트
        local create_script="
# 사용자 생성
sudo useradd -m -s /bin/bash '$new_user' 2>/dev/null || true

# 비밀번호 설정
echo '$new_user:$new_password' | sudo chpasswd

# sudo 그룹에 추가
sudo usermod -aG sudo '$new_user'

# sudoers에 추가 (비밀번호 없이 sudo 가능 - 선택사항)
# echo '$new_user ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/$new_user > /dev/null

# SSH 디렉토리 생성
sudo mkdir -p /home/$new_user/.ssh
sudo chmod 700 /home/$new_user/.ssh
sudo chown $new_user:$new_user /home/$new_user/.ssh

echo 'SUCCESS'
"

        # 사용자 생성 실행
        local result
        result=$(sshpass -p "$current_password" ssh $ssh_opts "${current_user}@${ip}" "$create_script" 2>&1)

        if echo "$result" | grep -q "SUCCESS"; then
            echo -e "    └─ ${GREEN}[OK]${NC} 사용자 '$new_user' 생성 완료 (sudo 권한 부여됨)"

            # 생성된 사용자로 로그인 테스트
            if sshpass -p "$new_password" ssh $ssh_opts "${new_user}@${ip}" "echo 'test'" &>/dev/null; then
                echo -e "    └─ ${GREEN}[OK]${NC} SSH 로그인 테스트 성공"
            else
                echo -e "    └─ ${YELLOW}[WARN]${NC} SSH 로그인 테스트 실패 (SSH 설정 확인 필요)"
            fi
        else
            echo -e "    └─ ${RED}[ERROR]${NC} 사용자 생성 실패"
            echo -e "    └─ 상세: $result"
            return 1
        fi
    fi

    return 0
}

# CSV 업데이트
update_csv() {
    local input_csv="$1"
    local new_user="$2"
    local new_password="$3"
    local output_csv="$4"

    # 첫 줄(헤더) 읽기
    local header
    header=$(head -1 "$input_csv")

    # 출력 파일 생성
    echo "$header" > "$output_csv"

    local line_num=0

    # CSV 파일 읽기 및 업데이트
    while IFS=',' read -r ip role ssh_user ssh_password || [ -n "$ip" ]; do
        line_num=$((line_num + 1))

        # 헤더 라인 건너뛰기
        if [ $line_num -eq 1 ]; then
            if [[ "$ip" == "ip" ]] || [[ "$ip" == "IP" ]]; then
                continue
            fi
        fi

        # 빈 줄 건너뛰기
        [ -z "$ip" ] && continue

        # 공백 제거
        ip=$(echo "$ip" | tr -d '[:space:]')
        role=$(echo "$role" | tr -d '[:space:]')

        # 새 정보로 업데이트
        echo "$ip,$role,$new_user,$new_password" >> "$output_csv"

    done < "$input_csv"
}

# 메인 함수
main() {
    local input_csv="$1"
    local new_user="$2"
    local new_password="$3"

    # 입력 파일 확인
    if [ ! -f "$input_csv" ]; then
        echo -e "${RED}[ERROR]${NC} CSV 파일을 찾을 수 없습니다: $input_csv"
        exit 1
    fi

    check_sshpass

    # 출력 파일명 생성
    local basename="${input_csv%.csv}"
    local output_csv="${basename}_modified.csv"

    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}  서버 사용자 생성 및 CSV 업데이트${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo ""
    echo -e "입력 CSV: ${GREEN}$input_csv${NC}"
    echo -e "출력 CSV: ${GREEN}$output_csv${NC}"
    echo -e "새 사용자: ${GREEN}$new_user${NC}"
    echo -e "새 비밀번호: ${GREEN}${new_password//?/*}${NC}"
    echo ""

    # 확인 프롬프트
    read -p "계속하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "취소되었습니다."
        exit 0
    fi

    echo ""
    echo -e "${YELLOW}[1/2] 각 서버에 사용자 생성 중...${NC}"
    echo ""

    local success_count=0
    local fail_count=0
    local total_count=0
    local line_num=0

    # CSV 파일 읽기 및 사용자 생성
    while IFS=',' read -r ip role ssh_user ssh_password || [ -n "$ip" ]; do
        line_num=$((line_num + 1))

        echo -e "${BLUE}[DEBUG]${NC} Read line $line_num: ip=$ip" >&2

        # 헤더 라인 건너뛰기
        if [ $line_num -eq 1 ]; then
            if [[ "$ip" == "ip" ]] || [[ "$ip" == "IP" ]]; then
                echo -e "${BLUE}[DEBUG]${NC} Skipping header" >&2
                continue
            fi
        fi

        # 빈 줄 건너뛰기
        if [ -z "$ip" ]; then
            echo -e "${BLUE}[DEBUG]${NC} Skipping empty line" >&2
            continue
        fi

        # 공백 제거
        ip=$(echo "$ip" | tr -d '[:space:]')
        role=$(echo "$role" | tr -d '[:space:]')
        ssh_user=$(echo "$ssh_user" | tr -d '[:space:]')
        ssh_password=$(echo "$ssh_password" | tr -d '[:space:]')

        total_count=$((total_count + 1))
        echo -e "${BLUE}[DEBUG]${NC} Processing server #$total_count: $ip" >&2

        # 사용자 생성
        if create_user_on_server "$ip" "$ssh_user" "$ssh_password" "$new_user" "$new_password"; then
            success_count=$((success_count + 1))
        else
            fail_count=$((fail_count + 1))
        fi

        echo ""

    done < "$input_csv"

    echo -e "${YELLOW}[2/2] CSV 파일 업데이트 중...${NC}"
    echo ""

    # CSV 업데이트
    update_csv "$input_csv" "$new_user" "$new_password" "$output_csv"

    # 파일 권한 설정
    chmod 600 "$output_csv"

    echo -e "${GREEN}=================================================${NC}"
    echo -e "${GREEN}  완료!${NC}"
    echo -e "${GREEN}=================================================${NC}"
    echo ""
    echo -e "처리 결과:"
    echo -e "  총 서버: ${BLUE}$total_count${NC}개"
    echo -e "  성공: ${GREEN}$success_count${NC}개"
    echo -e "  실패: ${RED}$fail_count${NC}개"
    echo ""
    echo -e "업데이트된 CSV: ${BLUE}$output_csv${NC}"
    echo -e "파일 권한: ${BLUE}600 (소유자만 읽기/쓰기)${NC}"
    echo ""

    if [ $fail_count -gt 0 ]; then
        echo -e "${YELLOW}[경고]${NC} 일부 서버에서 사용자 생성에 실패했습니다."
        echo "실패한 서버는 기존 계정 정보가 그대로 CSV에 기록되었습니다."
        echo ""
    fi

    echo -e "${YELLOW}다음 단계:${NC}"
    echo "  1. $output_csv 파일을 확인하세요"
    echo "  2. ./generate_cluster_yaml.sh $output_csv cluster.yaml"
    echo ""
}

# 인자 확인
if [ $# -ne 3 ]; then
    usage
fi

main "$@"
