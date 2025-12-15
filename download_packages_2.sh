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

    "libjavascriptcoregtk-4.0-18"

    "perl-dbdabi-94"

    "python3-cffi-backend-api-min"

    "node-is-fullwidth-code-point"

    "libva-driver-abi-1.10"

    "libva-driver-abi-1.14"

    "dbus-bin"

    "perl-openssl-abi-3"

    "qtdeclarative-abi-5-15-3"

    "dbus-daemon"

    "automake-1.16"

    "libjs-html5shiv"

    "libtime-local-perl"

    "libwebkit2gtk-4.0-37"

    "python3.10-venv"

    "openjdk-11-jre-headless"

    "qtbase-abi-5-15-3"

    "libnet-perl"

    "perlapi-5.34.0"

    "default-logind"

    "node-emoji-regex"

    "libc-dev"

    "python3-acme-abi-1"

    "xorg-video-abi-25"

    "gir1.2-webkit2-4.0"

    "libgirepository-1.0-1-with-libffi8"

    "libpython3.10-dev"

    "xorg-input-abi-24"

    "openjdk-11-jre"

    "node-cli-table3"

    "node-color-support"

    "openjdk-8-jre"

    "default-dbus-session-bus"

    "openjdk-11-jdk-headless"

    "node-has"

    "python3.10-dev"

    "libgcc1"

    "openjdk-11-jdk"

    "python3-certbot-abi-1"

    "default-dbus-system-bus"

    "libboost-regex1.74.0-icu70"

    "update-manager-gnome"

    "python3-cffi-backend-api-max"

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