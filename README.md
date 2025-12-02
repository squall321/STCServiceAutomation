# STC Service Automation

HPC 클러스터 자동 구성을 위한 도구 모음

## 📋 개요

이 프로젝트는 여러 서버로 구성된 HPC 클러스터를 자동으로 구성하기 위한 스크립트를 제공합니다.

## 🚀 주요 기능

### 1. 클러스터 YAML 생성 (`generate_cluster_yaml.sh`)

서버 목록 CSV 파일에서 각 서버의 정보를 자동으로 수집하여 클러스터 설정 YAML 파일을 생성합니다.

**기능:**
- SSH를 통한 서버 정보 자동 수집
  - Hostname
  - CPU (개수, 소켓, 코어, 스레드)
  - 메모리 (총 메모리에서 10GB 예약)
  - 디스크 용량
  - GPU 정보 (NVIDIA/AMD 자동 감지)
- 역할별 노드 분류 (controller, compute, viz)
- Multi-head controller 지원
- Slurm, MariaDB Galera, Redis Cluster 설정 포함

**사용법:**
```bash
./generate_cluster_yaml.sh servers.csv output.yaml
```

**CSV 형식:**
```csv
ip,role,ssh_user,ssh_password
192.168.1.1,controller,root,password123
192.168.1.2,compute,root,password456
192.168.1.3,viz,root,password789
```

### 2. 사용자 생성 및 CSV 업데이트 (`create_user_and_update_csv.sh`)

모든 서버에 새로운 사용자 계정을 생성하고, CSV 파일의 인증 정보를 업데이트합니다.

**기능:**
- SSH를 통한 원격 사용자 생성
- sudo 권한 자동 부여
- SSH 디렉토리 자동 설정
- 기존 사용자 존재 시 비밀번호만 변경
- CSV 파일 자동 업데이트 (ssh_user, ssh_password)

**사용법:**
```bash
./create_user_and_update_csv.sh servers.csv newuser newpassword
# → servers_modified.csv 생성
```

## 📦 요구사항

### 필수 패키지
```bash
sudo apt install sshpass
```

### Python (YAML 검증용)
```bash
sudo apt install python3 python3-yaml
```

## 🔧 전체 워크플로우

```bash
# 1. 서버 목록 CSV 작성
cat > my_servers.csv << EOF
ip,role,ssh_user,ssh_password
192.168.1.101,controller,root,rootpass
192.168.1.102,compute,root,rootpass
192.168.1.103,viz,root,rootpass
EOF

# 2. (선택) 새 사용자 생성 및 CSV 업데이트
./create_user_and_update_csv.sh my_servers.csv koopark MyPass123!
# → my_servers_modified.csv 생성됨

# 3. 클러스터 YAML 생성
./generate_cluster_yaml.sh my_servers_modified.csv my_cluster.yaml

# 4. 생성된 YAML 확인 및 편집
vim my_cluster.yaml

# 5. 클러스터 구성 실행 (별도 스크립트)
# sudo ./setup_cluster_full_multihead.sh
```

## 🗂️ 파일 구조

```
STCServiceAutomation/
├── generate_cluster_yaml.sh       # YAML 생성 스크립트
├── create_user_and_update_csv.sh  # 사용자 생성 스크립트
├── servers.csv.example             # CSV 예제 파일
├── README.md                       # 이 파일
└── .gitignore                      # Git 제외 파일 목록
```

## ⚙️ 생성되는 YAML 구조

생성된 YAML 파일은 다음을 포함합니다:

- **클러스터 정보**: 이름, 도메인, 타임존
- **노드 설정**:
  - Controllers (Multi-head 지원)
  - Compute nodes
  - Visualization nodes (GPU 지원)
- **네트워크 설정**: VIP, 방화벽 포트
- **스토리지**: GlusterFS 설정
- **데이터베이스**: MariaDB Galera Cluster
- **캐시**: Redis Cluster
- **스케줄러**: Slurm Multi-Master
- **HA**: Keepalived VIP
- **모니터링**: Prometheus, Grafana

## 📊 메모리 할당 정책

시스템 안정성을 위해 **총 메모리에서 10GB를 제외**한 값을 클러스터에 할당합니다.

예시:
- 총 메모리: 126,386 MB (123.4 GB)
- 시스템 예약: 10,240 MB (10 GB)
- 클러스터 할당: 116,146 MB (113.4 GB)

작은 메모리 시스템(< 11GB)의 경우 총 메모리의 90%를 할당합니다.

## 🔐 보안 주의사항

1. **CSV 파일 보호**
   ```bash
   chmod 600 *.csv
   ```

2. **생성된 YAML 파일 보호**
   ```bash
   chmod 600 *.yaml
   ```

3. **Git 커밋 주의**
   - `.gitignore`에 민감한 파일이 자동으로 제외됩니다
   - 커밋 전 반드시 `git status`로 확인하세요

4. **비밀번호 관리**
   - 프로덕션 환경에서는 강력한 비밀번호 사용
   - SSH 키 기반 인증 권장

## 🐛 문제 해결

### SSH 접속 실패
```bash
# SSH 서비스 확인
systemctl status ssh

# 비밀번호 인증 허용 확인
grep PasswordAuthentication /etc/ssh/sshd_config
```

### 메모리 값이 기본값으로 나옴
- `free -m` 명령어가 한글로 출력되는 경우 발생
- 스크립트는 자동으로 `LC_ALL=C`를 사용하여 해결

### GPU 감지 실패
- NVIDIA: `nvidia-smi` 설치 확인
- AMD: `lspci | grep -i vga` 확인

## 📝 라이선스

MIT License

## 👥 기여

버그 리포트 및 기능 제안은 Issues에 등록해 주세요.

## 📧 문의

문제가 있으시면 Issue를 등록해 주세요.
