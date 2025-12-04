#!/bin/bash
#
# 프록시 설정 + VS Code 설치 통합 스크립트
#

set -e

# 프록시 설정
PROXY_HOST="168.219.61.252"
PROXY_PORT="8080"
PROXY_URL="http://${PROXY_HOST}:${PROXY_PORT}"

echo "=========================================="
echo "프록시 환경에서 VS Code 설치"
echo "=========================================="
echo "프록시: ${PROXY_URL}"
echo ""

# Step 1: 프록시 환경 변수 설정
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 1: 프록시 환경 변수 설정"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
export http_proxy="${PROXY_URL}"
export https_proxy="${PROXY_URL}"
export HTTP_PROXY="${PROXY_URL}"
export HTTPS_PROXY="${PROXY_URL}"
export no_proxy="localhost,127.0.0.1,::1"
export NO_PROXY="localhost,127.0.0.1,::1"
echo "✓ 환경 변수 설정 완료"
echo ""

# Step 2: apt 프록시 설정
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 2: apt 프록시 설정"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
sudo tee /etc/apt/apt.conf.d/95proxies > /dev/null <<EOF
Acquire::http::Proxy "${PROXY_URL}";
Acquire::https::Proxy "${PROXY_URL}";
EOF
echo "✓ apt 프록시 설정 완료"
echo ""

# Step 3: wget 프록시 설정
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 3: wget 프록시 설정"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
cat > ~/.wgetrc <<EOF
http_proxy = ${PROXY_URL}
https_proxy = ${PROXY_URL}
use_proxy = on
check_certificate = off
EOF
echo "✓ wget 프록시 설정 완료"
echo ""

# Step 4: 기존 VS Code 설정 정리
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 4: 기존 VS Code 설정 정리"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
sudo rm -f /etc/apt/sources.list.d/vscode.list 2>/dev/null || true
sudo rm -f /usr/share/keyrings/microsoft*.gpg 2>/dev/null || true
sudo rm -f /etc/apt/trusted.gpg.d/microsoft*.gpg 2>/dev/null || true
echo "✓ 정리 완료"
echo ""

# Step 5: 필수 패키지 설치
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 5: 필수 패키지 설치"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "apt update 실행 중..."
sudo -E apt-get update
echo ""
echo "필수 패키지 설치 중..."
sudo -E apt-get install -y wget curl gpg apt-transport-https ca-certificates
echo "✓ 필수 패키지 설치 완료"
echo ""

# Step 6: Microsoft GPG 키 다운로드
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 6: Microsoft GPG 키 다운로드 및 설치"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 방법 1: wget 사용
echo "wget으로 GPG 키 다운로드 시도..."
if wget --no-check-certificate -qO /tmp/microsoft.asc https://packages.microsoft.com/keys/microsoft.asc 2>/dev/null; then
    echo "✓ wget 다운로드 성공"
    cat /tmp/microsoft.asc | gpg --dearmor | sudo tee /usr/share/keyrings/microsoft-archive-keyring.gpg > /dev/null
    rm -f /tmp/microsoft.asc
else
    echo "wget 실패, curl로 재시도..."
    # 방법 2: curl 사용
    if curl -x "${PROXY_URL}" -fsSL https://packages.microsoft.com/keys/microsoft.asc 2>/dev/null | gpg --dearmor | sudo tee /usr/share/keyrings/microsoft-archive-keyring.gpg > /dev/null; then
        echo "✓ curl 다운로드 성공"
    else
        echo "❌ 오류: GPG 키를 다운로드할 수 없습니다."
        echo ""
        echo "수동 해결 방법:"
        echo "1. 웹 브라우저에서 다음 주소 접속:"
        echo "   https://packages.microsoft.com/keys/microsoft.asc"
        echo "2. 파일을 다운로드하여 /tmp/microsoft.asc 저장"
        echo "3. 다음 명령어 실행:"
        echo "   cat /tmp/microsoft.asc | gpg --dearmor | sudo tee /usr/share/keyrings/microsoft-archive-keyring.gpg > /dev/null"
        exit 1
    fi
fi

sudo chmod 644 /usr/share/keyrings/microsoft-archive-keyring.gpg
echo "✓ GPG 키 설치 완료"
echo ""

# Step 7: VS Code 저장소 추가
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 7: VS Code 저장소 추가"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "deb [arch=amd64,arm64,armhf signed-by=/usr/share/keyrings/microsoft-archive-keyring.gpg] https://packages.microsoft.com/repos/code stable main" | \
  sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null
echo "✓ 저장소 추가 완료"
echo ""

# Step 8: apt 업데이트
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 8: apt 업데이트"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
sudo -E apt-get update
echo "✓ 업데이트 완료"
echo ""

# Step 9: VS Code 설치
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 9: VS Code 설치"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
sudo -E apt-get install -y code
echo "✓ VS Code 설치 완료"
echo ""

# Step 10: VS Code 프록시 설정
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 10: VS Code 프록시 설정"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
mkdir -p ~/.config/Code/User
cat > ~/.config/Code/User/settings.json <<EOF
{
    "http.proxy": "${PROXY_URL}",
    "http.proxyStrictSSL": false,
    "http.proxySupport": "on"
}
EOF
echo "✓ VS Code 프록시 설정 완료"
echo ""

# Step 11: 프록시 영구 설정 (선택사항)
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 11: 프록시 영구 설정"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if ! grep -q "# Corporate Proxy Settings" ~/.bashrc 2>/dev/null; then
    cat >> ~/.bashrc <<EOF

# Corporate Proxy Settings
export http_proxy="${PROXY_URL}"
export https_proxy="${PROXY_URL}"
export HTTP_PROXY="${PROXY_URL}"
export HTTPS_PROXY="${PROXY_URL}"
export no_proxy="localhost,127.0.0.1,::1"
export NO_PROXY="localhost,127.0.0.1,::1"
EOF
    echo "✓ .bashrc에 프록시 설정 추가 완료"
else
    echo "✓ .bashrc에 이미 프록시 설정 존재"
fi
echo ""

# 설치 확인
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "설치 확인"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if command -v code &>/dev/null; then
    CODE_VERSION=$(code --version 2>/dev/null | head -1)
    echo "✓ VS Code 설치 성공!"
    echo "  버전: ${CODE_VERSION}"
else
    echo "❌ VS Code 설치 실패"
fi
echo ""

echo "=========================================="
echo "설치 완료!"
echo "=========================================="
echo ""
echo "VS Code 실행 방법:"
echo "  • 터미널: code"
echo "  • GUI: 애플리케이션 메뉴에서 'Visual Studio Code'"
echo ""
echo "프록시 설정 위치:"
echo "  • apt: /etc/apt/apt.conf.d/95proxies"
echo "  • wget: ~/.wgetrc"
echo "  • VS Code: ~/.config/Code/User/settings.json"
echo "  • Shell: ~/.bashrc"
echo ""
echo "프록시 테스트:"
echo "  wget --spider http://www.google.com"
echo "  curl -I http://www.google.com"
echo ""
echo "참고:"
echo "  • 새 터미널에서 프록시 적용: source ~/.bashrc"
echo "  • git 프록시 설정: git config --global http.proxy ${PROXY_URL}"
echo ""