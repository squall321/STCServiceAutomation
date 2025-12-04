# 여러 디스크 환경에서 백업 관리 가이드

## 개요

서버에 여러 디스크가 있는 경우 백업 저장 위치를 선택하는 방법

## 현재 디스크 확인

```bash
# 디스크 목록 및 마운트 포인트 확인
df -h

# 출력 예시:
# Filesystem      Size  Used Avail Use% Mounted on
# /dev/sda1       100G   45G   50G  48% /
# /dev/sdb1       500G   10G  465G   3% /mnt/data1
# /dev/sdc1       1.0T   50G  924G   6% /mnt/data2
# /dev/sdd1       2.0T  100G  1.8T   6% /mnt/backup

# 블록 디바이스 확인
lsblk -f

# 마운트 포인트 상세 정보
mount | grep ^/dev
```

## 방법 1: 백업 경로 변경 (권장)

### config/backup_policy.conf 편집

```bash
cd /home/koopark/STCServiceAutomation/backupAutomation
nano config/backup_policy.conf
```

다음 라인을 수정:

```bash
# 기본값 (현재 디렉토리)
# BACKUP_ROOT="/home/koopark/STCServiceAutomation/backupAutomation/backups"

# 변경: 다른 디스크 사용 (예: /mnt/backup)
BACKUP_ROOT="/mnt/backup/system_backups"

# 또는 여러 위치 사용 (우선순위 순)
BACKUP_ROOT="/mnt/backup/system_backups"          # 메인
BACKUP_EXTERNAL="/mnt/data2/backup_mirror"        # 보조 (선택적)
```

### 백업 디렉토리 생성

```bash
# 선택한 디스크에 백업 디렉토리 생성
sudo mkdir -p /mnt/backup/system_backups/{snapshots,metadata}
sudo chown -R $USER:$USER /mnt/backup/system_backups
```

### 백업 실행

```bash
sudo ./backup_system.sh
```

## 방법 2: 심볼릭 링크 사용

기본 백업 경로를 유지하면서 다른 디스크로 링크:

```bash
# 기존 백업 디렉토리 제거 (또는 백업)
cd /home/koopark/STCServiceAutomation/backupAutomation
mv backups backups.old

# 다른 디스크에 실제 디렉토리 생성
sudo mkdir -p /mnt/backup/system_backups

# 심볼릭 링크 생성
ln -s /mnt/backup/system_backups backups

# 권한 설정
sudo chown -R $USER:$USER /mnt/backup/system_backups
```

이제 백업 스크립트를 실행하면 자동으로 `/mnt/backup/system_backups`에 저장됩니다.

## 방법 3: 명령줄에서 백업 경로 지정

백업 스크립트를 수정하여 명령줄 인수로 백업 경로를 받도록 할 수 있습니다.

### 임시 환경 변수 사용

```bash
# 일회성으로 다른 경로에 백업
BACKUP_ROOT="/mnt/backup/system_backups" sudo -E ./backup_system.sh
```

## 여러 디스크에 중복 백업 (미러링)

### 방법 A: 백업 후 복사

```bash
# 1. 메인 디스크에 백업
sudo ./backup_system.sh

# 2. 백업 ID 확인
BACKUP_ID=$(ls -t backups/snapshots/*.tar.gz | head -1 | xargs basename .tar.gz)

# 3. 다른 디스크로 복사
sudo cp backups/snapshots/${BACKUP_ID}.tar.gz /mnt/data2/backup_mirror/
sudo cp backups/snapshots/${BACKUP_ID}.tar.gz.sha256 /mnt/data2/backup_mirror/
sudo cp backups/metadata/${BACKUP_ID}.json /mnt/data2/backup_mirror/metadata/
```

### 방법 B: rsync로 동기화

```bash
# 전체 백업 디렉토리 동기화
sudo rsync -av --progress \
    backups/ \
    /mnt/data2/backup_mirror/
```

### 방법 C: 자동 미러링 스크립트 생성

```bash
#!/bin/bash
# mirror_backup.sh

BACKUP_ROOT="/home/koopark/STCServiceAutomation/backupAutomation/backups"
MIRROR_PATH="/mnt/data2/backup_mirror"

# 최신 백업 찾기
LATEST_BACKUP=$(ls -t $BACKUP_ROOT/snapshots/*.tar.gz | head -1)
BACKUP_ID=$(basename "$LATEST_BACKUP" .tar.gz)

# 미러 디렉토리 생성
mkdir -p "$MIRROR_PATH/snapshots"
mkdir -p "$MIRROR_PATH/metadata"

# 복사
echo "미러링 중: $BACKUP_ID"
cp "$BACKUP_ROOT/snapshots/${BACKUP_ID}.tar.gz" "$MIRROR_PATH/snapshots/"
cp "$BACKUP_ROOT/snapshots/${BACKUP_ID}.tar.gz.sha256" "$MIRROR_PATH/snapshots/"
cp "$BACKUP_ROOT/metadata/${BACKUP_ID}.json" "$MIRROR_PATH/metadata/"

echo "미러링 완료"
```

사용:
```bash
chmod +x mirror_backup.sh
sudo ./backup_system.sh && ./mirror_backup.sh
```

## 디스크 선택 기준

### 1. 속도 기준

**SSD (빠름)**:
- 백업 속도 빠름
- 자주 접근하는 최신 백업

**HDD (느림)**:
- 백업 속도 느림
- 장기 보관용 오래된 백업

### 2. 용량 기준

| 디스크 용량 | 권장 용도 | 예상 백업 개수 |
|------------|-----------|---------------|
| < 100GB    | 현재 디스크에 백업 | 50-100개 |
| 100-500GB  | 별도 파티션 | 200-500개 |
| > 500GB    | 전용 백업 디스크 | 1000+개 |

### 3. 신뢰성 기준

**중요도 높음**:
- RAID 미러 디스크 (RAID 1, RAID 10)
- 별도 물리 디스크에 중복 백업

**중요도 보통**:
- 단일 디스크 백업
- 정기적으로 외부 저장소에 복사

## 외부 저장소 사용 (USB, NAS 등)

### USB 디스크 마운트

```bash
# USB 디스크 연결 후 확인
lsblk

# 마운트 포인트 생성
sudo mkdir -p /mnt/usb_backup

# 마운트
sudo mount /dev/sde1 /mnt/usb_backup

# 백업 생성
BACKUP_ROOT="/mnt/usb_backup/system_backups" sudo -E ./backup_system.sh

# 언마운트
sudo umount /mnt/usb_backup
```

### NFS 공유 사용

```bash
# NFS 마운트
sudo mkdir -p /mnt/nfs_backup
sudo mount -t nfs 192.168.1.100:/backup /mnt/nfs_backup

# 백업
BACKUP_ROOT="/mnt/nfs_backup/system_backups" sudo -E ./backup_system.sh
```

### CIFS/SMB 공유 사용

```bash
# CIFS 마운트
sudo mkdir -p /mnt/smb_backup
sudo mount -t cifs //192.168.1.100/backup /mnt/smb_backup \
    -o username=user,password=pass

# 백업
BACKUP_ROOT="/mnt/smb_backup/system_backups" sudo -E ./backup_system.sh
```

## 디스크 공간 관리

### 각 디스크의 백업 공간 확인

```bash
# 메인 백업
du -sh /home/koopark/STCServiceAutomation/backupAutomation/backups

# 보조 백업
du -sh /mnt/backup/system_backups

# 미러 백업
du -sh /mnt/data2/backup_mirror
```

### 디스크별 오래된 백업 정리

```bash
# 메인 디스크: 최근 3개만 유지
./backup_manager.sh cleanup

# 보조 디스크: 수동 정리
cd /mnt/data2/backup_mirror/snapshots
ls -t *.tar.gz | tail -n +4 | xargs rm -f
```

## 자동화: 여러 디스크에 백업

### 스마트 백업 스크립트

```bash
#!/bin/bash
# smart_backup.sh - 여러 디스크에 자동 백업

# 사용 가능한 백업 위치 (우선순위 순)
BACKUP_LOCATIONS=(
    "/mnt/backup/system_backups"
    "/mnt/data2/backup_mirror"
    "/home/koopark/STCServiceAutomation/backupAutomation/backups"
)

# 충분한 공간이 있는 위치 찾기 (최소 10GB)
MIN_SPACE_GB=10

for location in "${BACKUP_LOCATIONS[@]}"; do
    if [ -d "$location" ]; then
        # 여유 공간 확인 (KB)
        free_space=$(df "$location" | tail -1 | awk '{print $4}')
        free_space_gb=$((free_space / 1024 / 1024))

        if [ $free_space_gb -ge $MIN_SPACE_GB ]; then
            echo "백업 위치: $location (여유 공간: ${free_space_gb}GB)"
            BACKUP_ROOT="$location" sudo -E ./backup_system.sh
            exit 0
        else
            echo "⚠ $location 공간 부족 (${free_space_gb}GB)"
        fi
    fi
done

echo "❌ 사용 가능한 백업 위치가 없습니다!"
exit 1
```

사용:
```bash
chmod +x smart_backup.sh
./smart_backup.sh
```

## 복구 시 백업 위치 지정

여러 디스크에 백업이 분산되어 있는 경우:

### 방법 1: BACKUP_ROOT 변경

```bash
# config/backup_policy.conf 편집
nano config/backup_policy.conf

# BACKUP_ROOT 변경
BACKUP_ROOT="/mnt/backup/system_backups"
```

### 방법 2: 심볼릭 링크 임시 변경

```bash
# 기존 링크 제거
rm backups

# 복구할 백업이 있는 디스크로 링크
ln -s /mnt/data2/backup_mirror backups

# 복구 실행
sudo ./restore_system.sh --backup backup_20231204_153045

# 원래대로 복원
rm backups
ln -s /mnt/backup/system_backups backups
```

### 방법 3: 백업 파일 임시 복사

```bash
# 다른 디스크의 백업을 현재 위치로 복사
cp /mnt/data2/backup_mirror/snapshots/backup_20231204_153045.tar.gz \
   backups/snapshots/

cp /mnt/data2/backup_mirror/metadata/backup_20231204_153045.json \
   backups/metadata/

# 복구 실행
sudo ./restore_system.sh --backup backup_20231204_153045
```

## 권장 구성

### 소규모 서버 (1-2 디스크)
```
Disk 1 (OS): /
  ├─ 시스템 파일
  └─ 백업 (backups/)

선택적으로 외부 USB에 주기적 복사
```

### 중규모 서버 (3-4 디스크)
```
Disk 1 (OS): /
  └─ 시스템 파일

Disk 2 (Data): /mnt/data
  └─ 사용자 데이터

Disk 3 (Backup): /mnt/backup
  └─ 시스템 백업 (메인)

Disk 4 (Mirror): /mnt/mirror
  └─ 백업 미러 (보조)
```

### 대규모 서버 (RAID)
```
RAID 1 (OS): /
  └─ 시스템 파일

RAID 5 (Data): /mnt/data
  └─ 사용자 데이터

RAID 1 (Backup): /mnt/backup
  ├─ 시스템 백업
  └─ 데이터 백업

외부 NAS: 원격 백업
```

## 체크리스트

### 백업 디스크 선택 시
- [ ] 충분한 여유 공간 (백업 크기의 10배 이상)
- [ ] 쓰기 권한 확인
- [ ] 마운트 자동화 (fstab)
- [ ] 디스크 건강 상태 확인 (SMART)
- [ ] 백업 정책 설정 (보관 기간)

### 복구 시
- [ ] 올바른 백업 위치 확인
- [ ] 백업 무결성 검증
- [ ] 충분한 여유 공간
- [ ] 백업 호스트명 확인

## 문제 해결

### Q: "디스크 공간 부족" 오류

**A1**: 다른 디스크로 백업 경로 변경
```bash
nano config/backup_policy.conf
# BACKUP_ROOT="/mnt/backup/system_backups"
```

**A2**: 오래된 백업 정리
```bash
./backup_manager.sh cleanup
```

### Q: 백업을 찾을 수 없음

**A**: 모든 디스크에서 백업 검색
```bash
# 백업 파일 찾기
sudo find /mnt -name "backup_*.tar.gz" 2>/dev/null

# 메타데이터 찾기
sudo find /mnt -name "*.json" -path "*/metadata/*" 2>/dev/null
```

### Q: 디스크가 마운트 안 됨

**A**: fstab에 자동 마운트 설정
```bash
# 디스크 UUID 확인
sudo blkid /dev/sdb1

# fstab 편집
sudo nano /etc/fstab

# 추가:
# UUID=xxx-xxx-xxx /mnt/backup ext4 defaults 0 2

# 마운트 테스트
sudo mount -a
```

## 베스트 프랙티스

1. **메인 백업**: 빠른 SSD 또는 별도 디스크
2. **미러 백업**: 다른 물리 디스크에 자동 복사
3. **원격 백업**: 주기적으로 NAS 또는 외부 저장소에 복사
4. **정리 정책**: 메인 디스크는 짧게 (7일), 미러는 길게 (30일)
5. **자동화**: cron으로 백업 + 미러링 + 정리 자동화
