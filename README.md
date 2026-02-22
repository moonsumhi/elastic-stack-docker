# Elastic Stack with Fleet Server

Docker 기반 Elasticsearch, Kibana, Fleet Server, Elastic Agent 통합 환경

## 구성 요소

| 서비스 | 설명 | 포트 |
|--------|------|------|
| Elasticsearch | 검색 및 분석 엔진 | 9200 |
| Kibana | 시각화 및 관리 UI | 5601 |
| Fleet Server | Agent 관리 서버 | 8220 |
| Elastic Agent | 로그/메트릭 수집 에이전트 | - |

## 사전 요구사항

- Docker & Docker Compose V2 (`docker compose` 플러그인 권장, V1 `docker-compose`도 지원)
- `curl`
- 최소 8GB RAM 권장
- bash 쉘 (Linux/macOS/WSL2)

> **Windows 사용자:** WSL2 환경에서 실행하세요. 스크립트는 `.gitattributes`로 LF 줄바꿈이 강제됩니다.

## 빠른 시작

### 1. 환경 설정

`.env` 파일에서 비밀번호를 설정하세요:

```bash
# .env 파일 편집
ELASTIC_PASSWORD=your_secure_password
```

### 2. 전체 스택 실행

```bash
chmod +x setup.sh add-agent.sh cleanup.sh
./setup.sh
```

이 스크립트가 자동으로 수행하는 작업:
1. Elasticsearch, Kibana, Fleet Server 시작 (Docker Compose)
2. `kibana_system` 사용자 비밀번호 설정
3. Fleet Server 헬스체크 대기

> Fleet 초기화, 정책 생성, 호스트 설정은 `KIBANA_FLEET_SETUP=1` 환경변수로 Fleet Server가 자동 처리합니다.

### 3. Elastic Agent 추가 (선택)

```bash
./add-agent.sh                    # 기본 이름으로 추가
./add-agent.sh my-agent           # 커스텀 이름으로 추가
```

## 접속 정보

| 서비스 | URL |
|--------|-----|
| Kibana | http://localhost:5601 |
| Elasticsearch | https://localhost:9200 |
| Fleet Server | https://localhost:8220 |

**로그인 정보:**
- Username: `elastic`
- Password: `.env`에 설정한 비밀번호

## 관리 명령어

### 상태 확인
```bash
docker compose ps
docker ps --format "table {{.Names}}\t{{.Status}}"
```

### 로그 확인
```bash
docker logs es01 --tail 50
docker logs kibana --tail 50
docker logs fleet-server --tail 50
```

### 서비스 재시작
```bash
docker compose restart kibana
docker compose restart fleet-server
```

### 전체 초기화
```bash
./cleanup.sh
./setup.sh
```

## 파일 구조

```
.
├── .env                 # 환경 변수 설정
├── .gitattributes       # LF 줄바꿈 강제 (Windows CRLF 방지)
├── docker-compose.yml   # Elasticsearch, Kibana, Fleet Server 컨테이너 정의
├── setup.sh            # 전체 스택 자동 설정 스크립트
├── add-agent.sh        # Elastic Agent 추가 스크립트
├── cleanup.sh          # 전체 환경 정리 스크립트
└── README.md           # 이 문서
```

## 데이터 수집 설정

### System Integration (기본)
`add-agent.sh`를 실행하면 자동으로 System Integration이 추가됩니다:
- CPU, 메모리, 디스크 메트릭
- 시스템 로그

### 추가 Integration
Kibana에서 설정:
1. **Management** → **Fleet** → **Agent policies**
2. 원하는 정책 선택 → **Add integration**
3. 사용 가능한 Integration:
   - **Docker** - 컨테이너 메트릭/로그
   - **Nginx** - 웹서버 로그
   - **MySQL** - 데이터베이스 메트릭
   - **Custom logs** - 커스텀 로그 파일

## 트러블슈팅

### Kibana가 시작되지 않음
`kibana_system` 비밀번호가 설정되지 않았을 수 있습니다:
```bash
docker exec es01 curl -s -X POST --cacert /usr/share/elasticsearch/config/certs/ca/ca.crt \
  -u "elastic:YOUR_PASSWORD" \
  -H "Content-Type: application/json" \
  https://localhost:9200/_security/user/kibana_system/_password \
  -d '{"password":"YOUR_PASSWORD"}'
```

### Fleet Server가 DEGRADED 상태
정상적인 부트스트랩 과정입니다. 1-2분 후 HEALTHY로 변경됩니다.

### 인증서 오류 (x509)
`FLEET_CA` 환경변수가 설정되지 않았을 수 있습니다. `setup.sh`를 다시 실행하세요.

### 메모리 부족
`.env`에서 메모리 제한 조정:
```bash
ES_MEM_LIMIT=1073741824      # 1GB로 줄이기
KIBANA_MEM_LIMIT=536870912   # 512MB로 줄이기
```

### 완전 초기화
```bash
./cleanup.sh
./setup.sh
```

### OS별 참고사항
- **Linux**: 모든 기능 완전 지원
- **macOS**: Elastic Agent의 호스트 파일시스템 마운트가 생략됩니다 (Docker Desktop VM 특성상 무의미)
- **Windows/WSL2**: WSL2 터미널에서 실행하세요. Git clone 시 `.gitattributes`가 LF 줄바꿈을 강제합니다

## 버전 변경

`.env` 파일에서 버전 수정:
```bash
STACK_VERSION=8.17.0
```

지원되는 버전 확인:
```bash
curl -s "https://registry.hub.docker.com/v2/repositories/elastic/elasticsearch/tags?page_size=10&ordering=last_updated" | grep -o '"name":"[0-9][^"]*"'
```

## 프로덕션 환경 주의사항

1. **비밀번호 변경**: 강력한 비밀번호 사용
2. **ENCRYPTION_KEY 변경**: 새로운 랜덤 키 생성
   ```bash
   openssl rand -hex 32
   ```
3. **메모리 설정**: 실제 워크로드에 맞게 조정
4. **볼륨 백업**: 정기적인 데이터 백업 구성
5. **네트워크 보안**: 필요한 포트만 외부에 노출
