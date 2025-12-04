#!/bin/bash

# 오프라인 설치를 위한 apt 패키지 백업 스크립트

echo "=== APT 패키지 오프라인 백업 스크립트 ==="

# 백업 디렉토리 생성
BACKUP_DIR="apt-backup-$(date +%Y%m%d)"
mkdir -p "$BACKUP_DIR"/{packages,lists}

echo "백업 디렉토리: $BACKUP_DIR"

# 1. apt-clone으로 패키지 목록 백업
echo -e "\n[1/5] apt-clone으로 패키지 정보 백업 중..."
if command -v apt-clone &> /dev/null; then
    sudo apt-clone clone "$BACKUP_DIR/apt-clone-backup.tar.gz"
    echo "✓ apt-clone 백업 완료"
else
    echo "⚠ apt-clone이 설치되지 않았습니다. 설치: sudo apt-get install apt-clone"
fi

# 2. 설치된 패키지 목록 저장
echo -e "\n[2/5] 패키지 목록 저장 중..."
dpkg --get-selections > "$BACKUP_DIR/lists/package-selections.txt"
apt-mark showmanual > "$BACKUP_DIR/lists/manual-packages.txt"
dpkg -l > "$BACKUP_DIR/lists/package-full-list.txt"
echo "✓ 패키지 목록 저장 완료"

# 3. 현재 캐시된 .deb 파일 복사
echo -e "\n[3/5] 캐시된 패키지 파일 복사 중..."
sudo cp -v /var/cache/apt/archives/*.deb "$BACKUP_DIR/packages/" 2>/dev/null || echo "캐시된 패키지 없음"

# 4. 설치된 모든 패키지의 .deb 파일 다운로드
echo -e "\n[4/5] 설치된 패키지 .deb 파일 다운로드 중..."
echo "이 작업은 시간이 걸릴 수 있습니다..."

# 설치된 모든 패키지 다운로드 (재설치 없이, apt-get update 없이)
cd "$BACKUP_DIR/packages"
for pkg in $(dpkg --get-selections | grep -v deinstall | awk '{print $1}'); do
    echo "다운로드 중: $pkg"
    apt-get download "$pkg" 2>/dev/null
done
cd - > /dev/null

echo "✓ 패키지 다운로드 완료"

# 5. tar.gz로 압축
echo -e "\n[5/5] 백업 파일 압축 중..."
tar -czf "${BACKUP_DIR}.tar.gz" "$BACKUP_DIR"
echo "✓ 압축 완료: ${BACKUP_DIR}.tar.gz"

# 백업 크기 확인
BACKUP_SIZE=$(du -sh "${BACKUP_DIR}.tar.gz" | awk '{print $1}')
PACKAGE_COUNT=$(ls "$BACKUP_DIR/packages"/*.deb 2>/dev/null | wc -l)

echo -e "\n=== 백업 완료 ==="
echo "백업 파일: ${BACKUP_DIR}.tar.gz"
echo "백업 크기: $BACKUP_SIZE"
echo "패키지 개수: $PACKAGE_COUNT"
echo -e "\n이 파일을 새 시스템으로 옮겨서 restore-packages.sh를 실행하세요."