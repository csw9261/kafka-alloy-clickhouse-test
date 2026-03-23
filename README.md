# kafka-alloy-clickhouse-test

Kafka + Grafana Alloy + ClickHouse 로그 파이프라인 토이 프로젝트

---

## 파이프라인 구조

```
log-generator
    → ./logs/app.log (로컬 파일에 로그 기록)
        → Alloy (producer.alloy): 파일 감시 → Kafka "logs" 토픽으로 전송
            → Kafka: "logs" 토픽에 메시지 보관
                → ClickHouse Kafka Engine: "logs" 토픽 소비 → otel.logs 테이블 저장
```

Alloy와 ClickHouse는 서로 직접 연결되지 않음.
Kafka의 **"logs" 토픽을 중간에 두고 간접적으로 연결**된 구조임.

---

## 컴포넌트 역할

| 컴포넌트 | 역할 |
|---|---|
| log-generator | 1초마다 랜덤 로그를 파일에 기록 (실제 앱 역할) |
| alloy-producer | 로그 파일을 감시해서 Kafka로 전송 (에이전트 역할) |
| kafka | 메시지 브로커. "logs" 토픽으로 메시지 보관 (KRaft 모드) |
| clickhouse | "logs" 토픽을 직접 소비해서 저장 (Kafka Engine) |

---

## Alloy를 쓰는 이유

앱은 파일에 로그만 쓰고, 그 다음은 Alloy가 담당함.

```
Alloy 없을 때: 앱 코드에 Kafka producer 직접 구현
               Kafka 주소 바뀌면 수천 대 앱 코드 수정 + 재배포

Alloy 있을 때: 앱은 파일에만 로그를 씀
               Kafka 주소 바뀌면 producer.alloy 한 줄만 수정
```

실제 환경에서는 각 서버(Windows 에이전트 등)에 Alloy가 하나씩 설치되어 동작함.
앱이 많아질수록 이 분리의 가치가 커짐.

---

## 프로세스

### 1. log-generator (`app/generate_logs.py`)

매 1초마다 `./logs/app.log`에 로그 한 줄씩 추가.
`./logs` 디렉토리가 alloy-producer 컨테이너와 공유되어 있음.

```
2026-03-23T13:09:12Z [INFO]  user_id=3160 msg="user logout"
2026-03-23T13:09:13Z [WARN]  user_id=7263 msg="upstream service unavailable"
2026-03-23T13:09:14Z [ERROR] user_id=6867 msg="database query slow"
```

### 2. Alloy (`alloy/producer.alloy`)

`/logs/app.log` 파일을 실시간으로 감시하다가 새 줄이 추가되면 즉시 읽어서
OTLP JSON 형식으로 인코딩 후 Kafka `logs` 토픽으로 전송.

```
otelcol.receiver.filelog  → 파일 감시 및 읽기
        ↓
otelcol.exporter.kafka    → kafka:9092 의 "logs" 토픽으로 전송
```

어느 토픽으로 보낼지는 `producer.alloy` 에서 정의함:

```hcl
otelcol.exporter.kafka "default" {
  brokers = ["kafka:9092"]
  topic   = "logs"          ← 토픽 이름
}
```

### 3. Kafka

`logs` 토픽에 메시지를 쌓아두고 ClickHouse가 가져갈 때까지 보관.
ClickHouse가 느려지거나 다운되어도 메시지를 잃지 않고 들고 기다림 (버퍼 역할).

### 4. ClickHouse (`clickhouse/init.sql`)

`init.sql` 에서 만든 3개 오브젝트가 연동되어 자동으로 처리됨.

```
kafka_logs_queue (Kafka Engine)
└─ "logs" 토픽을 지속적으로 폴링
└─ Alloy의 producer.alloy 와 동일한 토픽 이름 "logs" 를 바라봄
        ↓
logs_mv (Materialized View)
└─ 메시지가 들어오는 즉시 자동 실행
        ↓
otel.logs (MergeTree)
└─ 실제 데이터 저장 (7일 TTL)
```

### 장애 시 동작

| 장애 상황 | 동작 |
|---|---|
| Kafka 다운 | Alloy가 로컬 디스크에 버퍼링 → 복구 후 자동 재전송 |
| ClickHouse 다운 | Kafka가 메시지 보관 → 복구 후 밀린 것 처리 |
| 서버 1대 네트워크 단절 | 해당 서버 Alloy만 버퍼링, 나머지는 정상 동작 |

---

## 실행

```bash
docker compose up -d
```

## 데이터 확인

```bash
# 적재 건수
docker compose exec clickhouse clickhouse-client \
  --query "SELECT count() FROM otel.logs"

# 최근 10건
docker compose exec clickhouse clickhouse-client \
  --query "SELECT * FROM otel.logs LIMIT 10"

# Kafka 토픽 실시간 확인
docker compose exec kafka /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic logs \
  --from-beginning
```

## 종료

```bash
# 컨테이너만 종료 (데이터 유지)
docker compose down

# 컨테이너 + 볼륨 전체 삭제
docker compose down -v
```
