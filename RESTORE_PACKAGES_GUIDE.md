# restore_packages.sh 사용 가이드 (개선 버전)

## 개요

이 스크립트는 오프라인 환경에서 APT 패키지를 안전하게 복원하기 위한 도구입니다. 시스템 안전성을 최우선으로 하여 다음 기능을 제공합니다:

- 설치 전 패키지 충돌 감지
- 이미 설치된 패키지 보호 (기존 버전 우선)
- 의존성 분석 및 누락 패키지 식별
- 안전한 패키지만 선택적 설치
- 온라인 PC용 자동 다운로드 스크립트 생성

## 주요 안전 기능

### 1. Bash 버전 체크
- Bash 4.0 이상 필요 (연관 배열 사용)
- 버전 미달 시 자동 종료

### 2. 파이프라인 에러 감지
- `set -o pipefail`로 중간 명령 실패 감지

### 3. 임시 파일 자동 정리
- EXIT 트랩으로 임시 디렉토리 자동 삭제

### 4. 버전 비교
- `dpkg --compare-versions` 사용으로 정확한 버전 비교
- 의존성 요구사항 자동 검증

### 5. 기존 시스템 보호
- 이미 설치된 패키지는 절대 건드리지 않음
- 버전 다운그레이드 방지 (명시적 확인 시에만 허용)

## 사용 방법

### 기본 사용법

```bash
# 1. 백업 파일이 있는 디렉토리로 이동
cd /path/to/backup

# 2. 스크립트 실행
./restore_packages.sh
```

### 실행 흐름

```
[1단계] 백업 파일 검색 및 압축 해제
    ↓
[2단계] 시스템 패키지 분석
    ↓
[3단계] 백업 패키지 분석 (의존성 정보 포함)
    ↓
[4단계] 패키지 분류
    ├─ 설치 가능 (충돌 없음)
    ├─ 이미 설치됨 (건너뜀)
    └─ 충돌 패키지
    ↓
[5단계] 결과 출력 및 선택
```

## 시나리오별 대응

### 시나리오 1: 충돌 없음 (이상적 상황)

```
=== 분석 결과 ===
✓ 설치 가능: 150개
ℹ 이미 설치됨 (건너뛸): 50개
✓ 충돌: 0개

설치를 진행하시겠습니까? (y/N): y
```

**결과**: 150개 패키지가 안전하게 설치됨

---

### 시나리오 2: 일부 충돌 발생

```
=== 분석 결과 ===
✓ 설치 가능: 140개
ℹ 이미 설치됨 (건너뛸): 50개
⚠ 충돌 감지: 10개
⚠ 누락된 의존성: 5개

충돌 패키지 상세:
  - package-a (1.2.3)
  - package-b (2.4.5)
  ...

누락된 의존성 패키지:
  - libfoo: 필요 [>= 2.0], 시스템 버전 [3.0] - 버전 불일치
  - libbar: 필요 [>= 1.5] - 시스템 및 백업에 없음
  ...

누락 패키지 목록 생성
✓ 생성 완료: missing_packages.txt

다운로드 스크립트 생성
✓ 생성 완료: download_missing_packages.sh
ℹ 온라인 PC에서 실행: ./download_missing_packages.sh

⚠ 충돌 패키지가 감지되었습니다.

다음 단계를 진행하세요:
1. 온라인 PC에서 download_missing_packages.sh 실행
2. 생성된 백업 파일을 이 PC로 복사
3. 압축 해제 후 .deb 파일들을 apt-backup-XXXXXX/packages/ 에 추가
4. 이 스크립트 재실행

충돌 없는 140개 패키지만 먼저 설치하시겠습니까? (y/N):
```

**선택지**:

#### A. 충돌 없는 패키지만 먼저 설치 (y)
- 140개 패키지가 즉시 설치됨
- 나머지 10개는 온라인 PC에서 다운로드 후 처리

#### B. 모두 보류 (N)
- 온라인 PC에서 필요 패키지 다운로드 후 재실행

---

### 시나리오 3: 온라인 PC에서 누락 패키지 다운로드

**오프라인 PC에서 생성된 파일**:
- `missing_packages.txt`: 누락 패키지 목록
- `download_missing_packages.sh`: 자동 다운로드 스크립트

**온라인 PC에서 실행**:

```bash
# 1. 파일 복사 (USB 등)
# missing_packages.txt
# download_missing_packages.sh

# 2. 스크립트 실행
chmod +x download_missing_packages.sh
./download_missing_packages.sh
```

**다운로드 스크립트 동작**:
```
=== 누락 패키지 다운로드 스크립트 ===
다운로드 디렉토리: missing_packages_20231204_153045

패키지 다운로드 시작...

다운로드 중: libfoo
  ✓ libfoo 완료
다운로드 중: libbar
  ✓ libbar 완료
...

다운로드 완료: 15개 패키지 (의존성 포함)

백업 파일 생성 중...
✓ 백업 생성 완료: missing-packages-20231204_153045.tar.gz

=== 다음 단계 ===
1. missing-packages-20231204_153045.tar.gz 파일을 USB 등으로 오프라인 PC에 복사
2. 오프라인 PC에서 압축 해제:
   tar -xzf missing-packages-20231204_153045.tar.gz
3. 해제된 .deb 파일들을 기존 백업 디렉토리의 packages/ 폴더에 복사
4. restore_packages.sh 재실행
```

**오프라인 PC로 돌아와서**:

```bash
# 1. 다운로드된 백업 파일 압축 해제
tar -xzf missing-packages-20231204_153045.tar.gz

# 2. .deb 파일들을 기존 백업에 추가
cp missing_packages_20231204_153045/*.deb apt-backup-20231201/packages/

# 3. 스크립트 재실행
./restore_packages.sh
```

이번에는 모든 패키지가 설치 가능하게 됩니다!

---

## 생성되는 파일

### missing_packages.txt

누락된 의존성 패키지 목록:

```
# 누락된 의존성 패키지 목록
# 생성 시각: 2023-12-04 15:30:45
# 온라인 PC에서 다운로드가 필요한 패키지

libfoo  # 필요: >= 2.0
libbar  # 필요: >= 1.5
python3-setuptools
```

### download_missing_packages.sh

자동으로 생성되는 다운로드 스크립트:
- apt-get install --download-only 사용
- 의존성 자동 포함
- tar.gz 백업 파일 생성

---

## 설치 방법 선택

스크립트는 두 가지 설치 방법을 제공합니다:

### 방법 1: apt-get으로 설치 (권장)

```
설치 방법을 선택하세요:
1) apt-get으로 설치 (권장 - 의존성 자동 처리)
2) dpkg로 직접 설치
선택 (1-2): 1
```

**장점**:
- 의존성 자동 해결
- 패키지 관리자를 통한 정상적인 설치
- 설치 후 문제 발생 시 자동 복구 시도

**동작**:
1. 로컬 APT 저장소 생성
2. sources.list.d에 추가
3. apt-get install 실행

### 방법 2: dpkg로 직접 설치

```
선택 (1-2): 2
```

**장점**:
- APT 없이도 설치 가능
- 빠른 설치

**단점**:
- 의존성 문제 발생 가능 (자동 해결 시도함)

---

## 안전 장치 및 확인 절차

### 1. 설치 전 확인

```
설치 가능 패키지: 150개

설치를 진행하시겠습니까? (y/N):
```

사용자가 명시적으로 `y`를 입력해야만 설치 진행

### 2. 부분 설치 확인

```
충돌 없는 140개 패키지만 먼저 설치하시겠습니까? (y/N):
```

충돌이 있을 때 안전한 패키지만 먼저 설치할지 확인

### 3. 로컬 저장소 정리 확인

```
로컬 저장소를 제거하시겠습니까? (y/N):
```

설치 후 /etc/apt/sources.list.d/local-repo.list 제거 여부 확인

---

## 주요 보호 정책

### 기존 패키지 우선 정책

```python
# 이미 설치된 패키지는 건너뛰기 (기존 버전 우선 정책)
if [ -n "$installed_ver" ]; then
    ALREADY_INSTALLED+=("$pkg_name")
    continue
fi
```

**의미**:
- 백업에 새 버전이 있어도 시스템의 현재 버전을 유지
- 의도하지 않은 다운그레이드/업그레이드 방지
- 시스템 안정성 최우선

### 의존성 충돌 감지

```bash
# 시스템 버전이 요구사항을 만족하지 않음
if ! version_satisfies "$installed_ver" "$dep_ver_req"; then
    # 백업에 적절한 버전이 있는지 확인
    if [ -n "$backup_ver" ] && version_satisfies "$backup_ver" "$dep_ver_req"; then
        # 백업에 적절한 버전이 있음 - 문제없음
    else
        # 백업에도 적절한 버전이 없음 - 충돌!
        MISSING_DEPS["$dep_pkg"]="$dep_ver_req"
    fi
fi
```

**의미**:
- 패키지 설치 전에 의존성 문제를 미리 감지
- 시스템 파손 방지

---

## 에러 처리

### Bash 버전 체크

```
❌ 이 스크립트는 Bash 4.0 이상이 필요합니다.
현재 버전: 3.2.57
```

### 백업 파일 없음

```
❌ 백업 파일(apt-backup-*.tar.gz)을 찾을 수 없습니다.
현재 디렉토리에 백업 파일이 있는지 확인하세요.
```

### 패키지 없음

```
❌ 백업 디렉토리에 패키지가 없습니다.
```

### 권한 문제

```
⚠ 일부 기능은 root 권한이 필요합니다.
ℹ sudo 사용이 필요할 수 있습니다.
```

---

## 트러블슈팅

### Q1: "Bash 4.0 이상이 필요합니다" 에러

**해결**:
```bash
# Bash 버전 확인
bash --version

# Ubuntu/Debian에서 업데이트
sudo apt-get update
sudo apt-get install --only-upgrade bash
```

### Q2: 의존성 문제로 설치 실패

**해결**:
```bash
# apt-get으로 의존성 문제 해결
sudo apt-get install -f

# 또는 스크립트 재실행 (자동으로 해결 시도)
./restore_packages.sh
```

### Q3: 로컬 저장소 제거를 깜빡함

**해결**:
```bash
# 수동 제거
sudo rm /etc/apt/sources.list.d/local-repo.list
sudo apt-get update
```

### Q4: 다운로드 스크립트가 apt-rdepends 에러

**해결**:
```bash
# 온라인 PC에서
sudo apt-get update
sudo apt-get install apt-rdepends
```

---

## 성능 최적화

### 대량 패키지 처리

- 진행률 표시로 사용자 피드백
- 백업 패키지 분석: 10% 단위 `.` 출력
- 패키지 분류: 5% 단위 퍼센트 표시

### 메모리 효율

- 연관 배열로 O(1) 룩업
- 임시 파일 최소화
- 자동 정리로 디스크 공간 보호

---

## 보안 고려사항

### 1. trusted=yes 플래그

```bash
echo "deb [trusted=yes] file://$LOCAL_REPO ./" | sudo tee ...
```

**의미**: 로컬 저장소는 서명 검증 없이 신뢰
**이유**: 오프라인 환경에서 자체 백업한 패키지이므로 안전

### 2. sudo 사용 최소화

- 필수 작업(패키지 설치, 저장소 설정)에만 sudo 사용
- 분석 작업은 일반 권한으로 수행

---

## 백업/복원 워크플로우 전체 예시

### 온라인 환경 (백업 생성)

```bash
# backup_packages.sh 실행
./backup_packages.sh

# 생성된 파일: apt-backup-20231204.tar.gz
```

### 오프라인 환경 (복원 - 1차 시도)

```bash
# USB로 백업 파일 복사 후
./restore_packages.sh

# 결과: 충돌 5개 감지
# 생성: missing_packages.txt, download_missing_packages.sh
```

### 온라인 환경 (누락 패키지 다운로드)

```bash
# USB로 download_missing_packages.sh 복사 후
./download_missing_packages.sh

# 생성: missing-packages-20231204_153045.tar.gz
```

### 오프라인 환경 (복원 - 2차 시도)

```bash
# USB로 누락 패키지 백업 복사 후
tar -xzf missing-packages-20231204_153045.tar.gz
cp missing_packages_*/*.deb apt-backup-20231204/packages/

./restore_packages.sh

# 결과: 충돌 0개, 모든 패키지 설치 완료!
```

---

## 개선 버전의 주요 차이점

### 기존 버전
- 모든 패키지를 무조건 설치 시도
- 충돌 감지 없음
- 시스템 손상 위험

### 개선 버전
- 사전 분석 및 충돌 감지
- 기존 시스템 보호
- 선택적 설치
- 온라인 도움 스크립트 자동 생성
- 단계별 사용자 확인

---

## 로그 및 디버깅

### 설치 로그 확인

```bash
# APT 로그
cat /var/log/apt/history.log

# dpkg 로그
cat /var/log/dpkg.log
```

### 수동 디버깅

```bash
# 특정 패키지 의존성 확인
dpkg-deb -f package.deb Depends

# 패키지 버전 비교
dpkg --compare-versions "1.2.3" ge "1.2.0"
echo $?  # 0이면 true

# 현재 설치된 패키지 확인
dpkg -l | grep package-name
```

---

## 원복 방법 (롤백)

만약 설치 후 문제가 발생한 경우:

### 방법 1: 개별 패키지 제거

```bash
# 설치된 패키지 목록 확인
dpkg -l | grep '^ii'

# 특정 패키지 제거
sudo apt-get remove package-name

# 또는 완전 제거 (설정 파일 포함)
sudo apt-get purge package-name
```

### 방법 2: 시스템 스냅샷 복원

```bash
# 사전에 시스템 스냅샷을 생성했다면
# timeshift, snapper 등 사용
```

**권장**: 중요한 시스템에서는 복원 전에 시스템 스냅샷 생성

---

## FAQ

**Q: 스크립트를 중단하면 어떻게 되나요?**

A: Ctrl+C로 중단 시 EXIT 트랩이 임시 파일을 자동 정리합니다. 로컬 저장소가 추가된 상태라면 수동으로 제거하세요:
```bash
sudo rm /etc/apt/sources.list.d/local-repo.list
sudo apt-get update
```

**Q: 같은 패키지의 다른 버전을 강제로 설치하려면?**

A: 이 스크립트는 안전성을 위해 기존 버전을 우선합니다. 강제 설치가 필요하면:
1. 해당 패키지를 먼저 제거
2. 스크립트 재실행

**Q: 설치 중 인터넷 연결이 필요한가요?**

A: 아니요. 완전히 오프라인으로 동작합니다. APT 업데이트 시 로컬 저장소만 사용합니다.

**Q: 여러 백업 파일이 있으면?**

A: 스크립트는 첫 번째로 발견된 apt-backup-*.tar.gz 파일을 사용합니다. 특정 백업을 사용하려면 다른 백업 파일을 임시로 이동하세요.

---

## 요약

이 개선된 스크립트는:
1. 시스템 안전성을 최우선으로 설계
2. 설치 전 모든 충돌을 미리 감지
3. 기존 시스템을 절대 손상시키지 않음
4. 온라인 도움 없이도 최대한 많은 패키지를 설치
5. 필요 시 온라인 PC에서 쉽게 누락 패키지 다운로드 가능

**권장 사용 절차**:
1. 항상 중요한 시스템은 백업/스냅샷 생성
2. 테스트 환경에서 먼저 실행
3. 충돌이 없는지 확인 후 프로덕션 적용
