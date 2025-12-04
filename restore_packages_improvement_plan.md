# restore_packages.sh 개선 계획

## 현재 문제점
현재 스크립트는 백업된 패키지를 무조건 설치하려고 시도하며, 이미 설치된 패키지와의 버전 충돌을 고려하지 않음

## 개선 목표

### 1. 설치 전 사전 점검 단계 추가
- 현재 시스템에 설치된 패키지 목록과 버전 수집
- 백업 저장소의 패키지 목록과 버전 수집
- 두 목록을 비교하여 상태 분석

### 2. 패키지 분류 로직
백업 패키지를 다음과 같이 분류:

#### A. 설치 가능 패키지
- 시스템에 설치되지 않은 패키지
- 설치해도 충돌이 없는 패키지

#### B. 건너뛸 패키지
- 이미 설치되어 있는 패키지 (버전 무관)
- 기존 시스템 패키지 우선 정책

#### C. 충돌 패키지
- 백업 패키지를 설치하려 할 때, 해당 패키지가 의존하는 다른 패키지의 버전이 현재 시스템 버전보다 낮은 경우
- 예: 백업 패키지 A가 libB (>= 1.0)을 요구하는데, 시스템에는 libB 2.0이 설치되어 있고, 백업에는 libB 0.9만 있는 경우

### 3. 충돌 해결 전략

#### 3-1. 충돌 감지
- dpkg-deb을 사용하여 각 .deb 파일의 의존성 정보 추출
- 의존성 패키지의 필요 버전과 현재 시스템 버전 비교
- 백업 저장소에 필요한 버전이 있는지 확인

#### 3-2. 누락 패키지 목록 생성
- 충돌이 발생하는 패키지들 중 백업 저장소에 없는 필요 버전 목록 생성
- `missing_packages.txt` 파일로 출력
  - 형식: `패키지명=버전` (apt-get install에 사용 가능한 형식)

#### 3-3. 온라인 PC용 다운로드 스크립트 생성
- `download_missing_packages.sh` 스크립트 자동 생성
- 인터넷이 연결된 PC에서 실행하면:
  1. `missing_packages.txt`에 있는 패키지들을 다운로드
  2. 의존성 패키지도 함께 다운로드
  3. 새로운 백업 tar.gz 파일 생성
  4. USB 등으로 오프라인 PC로 복사하여 사용

### 4. 설치 프로세스

```
[단계 1] 백업 파일 압축 해제
[단계 2] 패키지 분석 및 분류
  ├─ 현재 시스템 패키지 스캔
  ├─ 백업 패키지 스캔
  └─ 의존성 분석 및 충돌 감지

[단계 3] 분석 결과 출력
  ├─ 설치 가능: N개
  ├─ 건너뛸 항목: N개 (이미 설치됨)
  └─ 충돌 항목: N개

[단계 4-A] 충돌이 없는 경우
  └─ 설치 가능한 패키지만 설치 진행

[단계 4-B] 충돌이 있는 경우
  ├─ 충돌 상세 정보 출력
  ├─ missing_packages.txt 생성
  ├─ download_missing_packages.sh 생성
  └─ 사용자에게 안내
      - 온라인 PC에서 download_missing_packages.sh 실행
      - 다운로드된 패키지를 오프라인 PC로 복사
      - restore_packages.sh 재실행
```

### 5. 주요 기능 함수

#### `check_installed_packages()`
- dpkg -l로 현재 설치된 패키지 목록과 버전 가져오기
- 연관 배열에 저장: `installed_packages[패키지명]=버전`

#### `scan_backup_packages()`
- 백업 디렉토리의 .deb 파일들을 스캔
- dpkg-deb -f로 패키지명, 버전, 의존성 정보 추출
- 연관 배열에 저장

#### `analyze_dependencies()`
- 각 백업 패키지의 의존성을 파싱
- 필요한 패키지 버전과 현재 시스템/백업 저장소 비교
- 충돌 감지 및 누락 패키지 식별

#### `classify_packages()`
- 백업 패키지를 3가지 카테고리로 분류
- 설치 가능, 건너뛸, 충돌 리스트 생성

#### `generate_missing_list()`
- 누락된 패키지를 `missing_packages.txt`로 출력

#### `generate_download_script()`
- 온라인 PC용 다운로드 스크립트 생성
- apt-get download와 apt-rdepends 활용

#### `install_safe_packages()`
- 충돌 없는 패키지만 선택적으로 설치

### 6. 출력 파일

#### `missing_packages.txt`
```
libssl1.1=1.1.1f-1ubuntu2
libcurl4=7.68.0-1ubuntu2.7
python3-pip=20.0.2-5ubuntu1.6
```

#### `download_missing_packages.sh`
```bash
#!/bin/bash
# 온라인 PC에서 실행하여 누락 패키지 다운로드

mkdir -p missing_packages
cd missing_packages

# 패키지 다운로드 (의존성 포함)
apt-get download libssl1.1=1.1.1f-1ubuntu2
apt-get download libcurl4=7.68.0-1ubuntu2.7
...

# 의존성도 다운로드
apt-rdepends --print-uris libssl1.1 | grep -o "http://[^']*" | xargs wget

# 백업 생성
tar -czf missing-packages-$(date +%Y%m%d).tar.gz *.deb
```

## 사용자 시나리오

### 시나리오 1: 충돌 없음
```
$ ./restore_packages.sh
=== 패키지 분석 중 ===
✓ 설치 가능: 150개
✓ 이미 설치됨: 50개
✓ 충돌: 0개

설치를 진행하시겠습니까? (y/n)
```

### 시나리오 2: 충돌 있음
```
$ ./restore_packages.sh
=== 패키지 분석 중 ===
✓ 설치 가능: 140개
✓ 이미 설치됨: 50개
⚠ 충돌: 10개

충돌 상세:
  - package-a: 필요 libfoo >= 2.0, 시스템: 3.0, 백업: 1.5 ❌
  - package-b: 필요 libbar >= 1.2, 시스템: 1.5, 백업: 없음 ❌

📝 missing_packages.txt 생성 완료 (5개 패키지)
📝 download_missing_packages.sh 생성 완료

⚠ 다음 단계:
1. 온라인 PC에서 download_missing_packages.sh 실행
2. 생성된 tar.gz 파일을 이 PC로 복사
3. restore_packages.sh 재실행

충돌 없는 140개 패키지만 먼저 설치하시겠습니까? (y/n)
```

## 구현 우선순위

1. **Phase 1**: 기본 분석 기능
   - 설치된 패키지 체크
   - 백업 패키지 스캔
   - 간단한 비교 및 분류

2. **Phase 2**: 의존성 분석
   - 의존성 파싱
   - 버전 비교 로직
   - 충돌 감지

3. **Phase 3**: 자동화 도구 생성
   - missing_packages.txt 생성
   - download_missing_packages.sh 생성

4. **Phase 4**: 선택적 설치
   - 충돌 없는 패키지만 설치
   - 사용자 확인 절차

## 기술적 고려사항

### Bash 버전 호환성
- 연관 배열 사용 (Bash 4.0+)
- 대부분의 최신 우분투/데비안 시스템은 지원

### 의존성 파싱
- dpkg-deb -f로 Depends 필드 추출
- 버전 비교: dpkg --compare-versions 사용

### 성능
- 대량 패키지 처리 시 진행률 표시
- 파싱 결과 임시 캐싱

### 에러 처리
- 각 단계별 실패 시 복구 방안
- 명확한 에러 메시지
