-- create_tables.sql

-- 사기 분석 요약 테이블
CREATE TABLE IF NOT EXISTS fraud_summary (
    metric VARCHAR(100) PRIMARY KEY,
    value FLOAT
);

-- 상위 이상치 트랜잭션 테이블
CREATE TABLE IF NOT EXISTS fraud_top_outliers (
    transaction_id SERIAL PRIMARY KEY,
    time FLOAT,
    v1 FLOAT, v2 FLOAT, v3 FLOAT, v4 FLOAT, v5 FLOAT,
    v6 FLOAT, v7 FLOAT, v8 FLOAT, v9 FLOAT, v10 FLOAT,
    v11 FLOAT, v12 FLOAT, v13 FLOAT, v14 FLOAT, v15 FLOAT,
    v16 FLOAT, v17 FLOAT, v18 FLOAT, v19 FLOAT, v20 FLOAT,
    v21 FLOAT, v22 FLOAT, v23 FLOAT, v24 FLOAT, v25 FLOAT,
    v26 FLOAT, v27 FLOAT, v28 FLOAT,
    amount FLOAT,
    class INT,
    imported_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 인덱스 생성
CREATE INDEX IF NOT EXISTS idx_fraud_top_outliers_amount ON fraud_top_outliers(amount);
CREATE INDEX IF NOT EXISTS idx_fraud_top_outliers_class ON fraud_top_outliers(class);