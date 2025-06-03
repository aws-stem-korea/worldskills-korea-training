from pyspark.sql import SparkSession
from pyspark.sql.functions import col, count, sum, avg, stddev, min, max, when, desc
import os
import time
from datetime import datetime

# AWS 계정 ID 설정
AWS_ACCOUNT_ID = "your-account-id" 

# SparkSession 초기화
spark = SparkSession.builder \
    .appName("CreditCardFraudAnalysis") \
    .getOrCreate()

# 로깅 설정
log4jLogger = spark._jvm.org.apache.log4j
logger = log4jLogger.LogManager.getLogger("CreditCardAnalysis")
logger.info("신용카드 트랜잭션 분석 작업 시작")

try:
    # S3에서 신용카드 데이터 읽기
    s3_bucket_name = f"ws-cc-raw-data-{AWS_ACCOUNT_ID}"
    s3_path=f"s3://{s3_bucket_name}/data/creditcard.csv"
    logger.info(f"실제 사용되는 S3 경로: {s3_path}")  # 실제 경로 확인용

    logger.info("S3에서 데이터 읽기 시작")
    df = spark.read.csv(f"s3://{s3_bucket_name}/data/creditcard.csv", header=True, inferSchema=True)

    # 기본 정보 로깅
    total_rows = df.count()
    logger.info(f"데이터 로드 완료. 총 레코드 수: {total_rows}")
    
    # 1. 기본 통계 분석
    logger.info("기본 통계 분석 시작")
    
    # 금액(Amount) 컬럼에 대한 기본 통계
    amount_stats = df.select(
        min("Amount").alias("min_amount"),
        max("Amount").alias("max_amount"),
        avg("Amount").alias("avg_amount"),
        stddev("Amount").alias("stddev_amount")
    ).collect()[0]
    
    logger.info(f"금액 통계: 최소={amount_stats['min_amount']}, 최대={amount_stats['max_amount']}, 평균={amount_stats['avg_amount']}, 표준편차={amount_stats['stddev_amount']}")
    
    # 2. 사기 트랜잭션 분석
    fraud_count = df.filter(col("Class") == 1).count()
    normal_count = df.filter(col("Class") == 0).count()
    fraud_percentage = (fraud_count / total_rows) * 100
    
    logger.info(f"사기 트랜잭션: {fraud_count}건 ({fraud_percentage:.4f}%)")
    logger.info(f"정상 트랜잭션: {normal_count}건 ({100-fraud_percentage:.4f}%)")
    
    # 3. 금액 기준 이상치 탐지 (상위 1% 트랜잭션)
    percentile_threshold = df.stat.approxQuantile("Amount", [0.99], 0.01)[0]
    outliers_df = df.filter(col("Amount") > percentile_threshold)
    outliers_df.cache()
    outliers_count = outliers_df.count()
    
    logger.info(f"금액 기준 이상치(상위 1%): {outliers_count}건, 기준값: {percentile_threshold}")
    
    # 4. 사기 트랜잭션의 평균 금액 vs 정상 트랜잭션의 평균 금액
    fraud_avg = df.filter(col("Class") == 1).agg(avg("Amount").alias("avg_amount")).collect()[0]["avg_amount"]
    normal_avg = df.filter(col("Class") == 0).agg(avg("Amount").alias("avg_amount")).collect()[0]["avg_amount"]
    
    logger.info(f"사기 트랜잭션 평균 금액: {fraud_avg}")
    logger.info(f"정상 트랜잭션 평균 금액: {normal_avg}")
    
    # 5. 결과 데이터프레임 생성
    # 통계 요약 데이터프레임
    summary_data = [
        ("총 트랜잭션 수", float(total_rows)),
        ("사기 트랜잭션 수", float(fraud_count)),
        ("정상 트랜잭션 수", float(normal_count)),
        ("사기 트랜잭션 비율 (%)", float(fraud_percentage)),
        ("최소 금액", float(amount_stats["min_amount"])),
        ("최대 금액", float(amount_stats["max_amount"])),
        ("평균 금액", float(amount_stats["avg_amount"])),
        ("금액 표준편차", float(amount_stats["stddev_amount"])),
        ("사기 트랜잭션 평균 금액", float(fraud_avg)),
        ("정상 트랜잭션 평균 금액", float(normal_avg)),
        ("이상치 기준값 (상위 1%)", float(percentile_threshold)),
        ("이상치 트랜잭션 수", float(outliers_count))
    ]
    
    summary_df = spark.createDataFrame(summary_data, ["metric", "value"])
    summary_df.cache()
    # 6. 상위 10개 이상치 트랜잭션 추출
    top_outliers_df = df.orderBy(desc("Amount")).limit(10)
    top_outliers_df.cache()
# 7. 결과 저장
    # 환경 변수에서 S3 버킷 이름 가져오기 (기본값: ws-cc-raw-data)
    s3_bucket = os.environ.get('S3_BUCKET', s3_bucket_name)
    
    # 항상 지정된 버킷의 output 폴더에 저장하도록 경로 설정
    output_path = f"s3://{s3_bucket}/output/fraud_analysis_result"
    
    logger.info(f"분석 결과 S3에 저장 시작: {output_path}")
        
    # 요약 통계 저장
    summary_df.write.mode("overwrite").parquet(f"{output_path}/summary")
    summary_df.cache()
    # # 이상치 데이터 저장
    outliers_df.write.mode("overwrite").parquet(f"{output_path}/outliers")
    outliers_df.cache()
    # # 상위 10개 이상치 트랜잭션 저장
    top_outliers_df.write.mode("overwrite").parquet(f"{output_path}/top_outliers")
    top_outliers_df.cache()
    # 8. RDS에 결과 저장
    logger.info("분석 결과 RDS에 저장 시작")
    
    # 환경 변수에서 RDS 연결 정보 가져오기
    rds_host = os.environ.get('RDS_HOST') 
    rds_port = os.environ.get('RDS_PORT', '5433')
    rds_database = os.environ.get('RDS_DATABASE', 'fraud_detection')
    rds_user = os.environ.get('RDS_USER', 'wsadmin')
    rds_password = os.environ.get('RDS_PASSWORD')
    print("디버깅용 코드")
    
# JDBC URL 구성
    jdbc_url = f"jdbc:postgresql://{rds_host}:{rds_port}/{rds_database}"
    logger.info(f"RDS 연결 URL: {jdbc_url}")
    print(f"RDS 연결 URL: {jdbc_url}")
    # RDS 연결 정보
    connection_properties = {
        "user": rds_user,
        "password": rds_password,
        "driver": "org.postgresql.Driver"
    }
        
    try:
        # 요약 통계 RDS에 저장
        logger.info("요약 통계 RDS에 저장 중...")
        print("요약 통계 RDS에 저장 중...")
        summary_df.write \
                .format("jdbc") \
                .option("url", jdbc_url) \
                .option("dbtable", "fraud_summary") \
                .option("user", connection_properties["user"]) \
                .option("password", connection_properties["password"]) \
                .option("driver", connection_properties["driver"]) \
                .mode("overwrite") \
                .save()
            
            # 상위 10개 이상치 트랜잭션 RDS에 저장
        logger.info("상위 이상치 트랜잭션 RDS에 저장 중...")
        top_outliers_df.write \
            .format("jdbc") \
            .option("url", jdbc_url) \
            .option("dbtable", "fraud_top_outliers") \
            .option("user", connection_properties["user"]) \
            .option("password", connection_properties["password"]) \
            .option("driver", connection_properties["driver"]) \
            .mode("overwrite") \
            .save()
            
        logger.info("RDS 저장 완료")
    except Exception as rds_error:
        logger.error(f"RDS 저장 중 오류 발생: {str(rds_error)}")
        logger.info("S3 저장은 완료되었으나 RDS 저장은 실패했습니다.")

        logger.info("분석 작업 완료: 결과가 S3에 저장되었습니다.")
    
    
except Exception as e:
    logger.error(f"오류 발생: {str(e)}")
    raise e
    
# finally:
#     # SparkSession 종료
#     spark.stop()