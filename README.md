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

- Docker & Docker Compose
- 최소 8GB RAM 권장
- bash 쉘 (Linux/macOS/WSL2)

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
1. Elasticsearch 시작 및 인증서 생성
2. Kibana 시작
3. `kibana_system` 사용자 비밀번호 설정
4. Fleet 초기화
5. Fleet Server 정책 생성
6. Fleet Server 시작 및 등록

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
docker-compose ps
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
docker-compose restart kibana
docker restart fleet-server
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
├── docker-compose.yml   # Elasticsearch, Kibana 컨테이너 정의
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
