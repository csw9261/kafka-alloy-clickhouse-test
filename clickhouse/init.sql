-- 1. 실제 로그 저장 테이블
CREATE TABLE IF NOT EXISTS otel.logs
(
    inserted_at DateTime DEFAULT now(),
    raw_message String
)
ENGINE = MergeTree
PARTITION BY toDate(inserted_at)
ORDER BY inserted_at
TTL inserted_at + INTERVAL 7 DAY;

-- 2. Kafka Engine 테이블 (Kafka 토픽을 직접 소비)
--    Alloy가 otlp_json 형식으로 전송하므로 JSONAsString으로 받아 raw 보관
CREATE TABLE IF NOT EXISTS otel.kafka_logs_queue
(
    message String
)
ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'kafka:9092',
    kafka_topic_list  = 'logs',
    kafka_group_name  = 'clickhouse_consumer',
    kafka_format      = 'JSONAsString',
    kafka_num_consumers = 1;

-- 3. Materialized View: Kafka 테이블 → 저장 테이블로 자동 이동
CREATE MATERIALIZED VIEW IF NOT EXISTS otel.logs_mv TO otel.logs AS
SELECT
    now()    AS inserted_at,
    message  AS raw_message
FROM otel.kafka_logs_queue;
