#!/bin/bash

# 저 배점별로 점수를 획득하게끔 코드를 수정해
# 점수 초기화
TOTAL_SCORE=0
MAX_SCORE=31
PASSED_CHECKS=0  # 통과한 항목 수 초기화

# 결과 저장 함수
check_result() {
    local score=$1
    if [ "$2" == "PASS" ]; then
        TOTAL_SCORE=$((TOTAL_SCORE + score))
        PASSED_CHECKS=$((PASSED_CHECKS + 1))  # PASS일 때 통과 항목 수 증가
        echo "✅ $3 (${score}점)"
    else
        echo "❌ $3 (0/${score}점)"
    fi
}

echo "=== AWS 인프라 구성 채점 시작 ==="

# 1-1 VPC 및 IGW 확인  1점
VPC_CHECK=$(aws ec2 describe-vpcs --filters Name=tag:Name,Values=retail-vpc --query 'Vpcs[0].[CidrBlock,Tags[?Key==`Name`].Value]' --output text)
IGW_CHECK=$(aws ec2 describe-internet-gateways --filters Name=tag:Name,Values=retail-igw --query 'InternetGateways[0].Tags[?Key==`Name`].Value' --output text)
if [[ $VPC_CHECK == *"10.1.0.0/16"* && $VPC_CHECK == *"retail-vpc"* && $IGW_CHECK == "retail-igw" ]]; then
    check_result 1 "PASS" "VPC 및 IGW 구성"
else
    check_result 1 "FAIL" "VPC 및 IGW 구성"
fi

# 1-2. 서브넷 확인 2점

SUBNET_PUBLIC_CHECK=$(aws ec2 describe-subnets --filters Name=tag:Name,Values=retail-public-a --query 'Subnets[0].[CidrBlock]' --output text)
SUBNET_LOG_CHECK=$(aws ec2 describe-subnets --filters Name=tag:Name,Values=retail-log-a --query 'Subnets[0].[CidrBlock]' --output text)
if [[ $SUBNET_PUBLIC_CHECK == "10.1.2.0/24" && $SUBNET_LOG_CHECK == "10.1.1.0/24" ]]; then
    check_result 2 "PASS" "서브넷 구성"
else
    check_result 2 "FAIL" "서브넷 구성"
fi



# 1-3. NAT Gateway 확인 2점 
NATGW_CHECK=$(aws ec2 describe-nat-gateways --filter Name=tag:Name,Values=retail-natgw-a --query 'NatGateways[*].[State,Tags[?Key==`Name`].Value]' --output text)
if [[ $NATGW_CHECK == *"available"* ]]; then
    check_result 2 "PASS" "NAT Gateway 구성"
else
    check_result 2 "FAIL" "NAT Gateway 구성"
fi

# 2-1. Bastion 인스턴스 확인 1점
BASTION_CHECK=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=retail-bastion" --query 'Reservations[*].Instances[*].[InstanceType]' --output text)
if [[ $BASTION_CHECK == "t3.large" ]]; then
    check_result 1 "PASS" "Bastion 인스턴스 구성"
else
    check_result 1 "FAIL" "Bastion 인스턴스 구성"
fi

# 2-2. Bastion 보안그룹 확인 2점
SG_CHECK=$(aws ec2 describe-security-groups --filters Name=group-name,Values=retail-bastion-sg --query 'SecurityGroups[0].IpPermissions[?ToPort==`22`].[IpProtocol,FromPort,ToPort]' --output text)
ROLE_CHECK=$(aws iam get-role --role-name retail-app-role --query 'Role.RoleName' --output text 2>/dev/null)
ADMIN_POLICY=$(aws iam list-attached-role-policies --role-name retail-app-role --query 'AttachedPolicies[?PolicyName==`AdministratorAccess`].PolicyName' --output text)

if [[ $SG_CHECK == "tcp"*"22"*"22" && $ROLE_CHECK == "retail-app-role" && $ADMIN_POLICY == "AdministratorAccess" ]]; then
    check_result 2 "PASS" "보안 및 권한 설정"
else
    check_result 2 "FAIL" "보안 및 권한 설정"
fi


# 3-1 EC2 인스턴스 구성 (4점)
LOG_INSTANCE_CHECK=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=retail-log" --query 'Reservations[*].Instances[*].[InstanceType]' --output text)
LOG_SG_CHECK=$(aws ec2 describe-security-groups --filters Name=group-name,Values=retail-log-sg --query 'SecurityGroups[0].IpPermissions[*]' --output text)

if [[ $LOG_INSTANCE_CHECK == "t3.large" && ! -z "$LOG_SG_CHECK" ]]; then
    check_result 4 "PASS" "로그 인스턴스 구성"
else
    check_result 4 "FAIL" "로그 인스턴스 구성"
fi



# 4-1. Kinesis Data Stream 생성 및 설정 확인 3점
STREAM_ACCESS=$(aws kinesis describe-stream --stream-name retail-access-stream --query 'StreamDescription.StreamName' --output text 2>/dev/null)
STREAM_TRANS=$(aws kinesis describe-stream --stream-name retail-transaction-stream --query 'StreamDescription.StreamName' --output text 2>/dev/null)

if [[ $STREAM_ACCESS == "retail-access-stream" && $STREAM_TRANS == "retail-transaction-stream" ]]; then
    check_result 3 "PASS" "Kinesis Data Streams 구성"
else
    check_result 3 "FAIL" "Kinesis Data Streams 구성"
fi






# 5-1. Firehose 전송 스트림 생성 2점
FIREHOSE_ACCESS=$(aws firehose describe-delivery-stream --delivery-stream-name retail-access-delivery --query 'DeliveryStreamDescription.DeliveryStreamName' --output text 2>/dev/null)
FIREHOSE_TRANS=$(aws firehose describe-delivery-stream --delivery-stream-name retail-transaction-delivery --query 'DeliveryStreamDescription.DeliveryStreamName' --output text 2>/dev/null)

if [[ $FIREHOSE_ACCESS == "retail-access-delivery" && $FIREHOSE_TRANS == "retail-transaction-delivery" ]]; then
    check_result 2 "PASS" "Kinesis Firehose 구성"
else
    check_result 2 "FAIL" "Kinesis Firehose 구성"
fi


# 5-2. S3 버킷 연결 3점
ACCOUNT_PREFIX=$(aws sts get-caller-identity --query 'Account' --output text | cut -c1-6)
BUCKET_NAME="retail-data-lake-${ACCOUNT_PREFIX}"

# 버킷 존재 여부 및 리전 확인
BUCKET_CHECK=$(aws s3api get-bucket-location --bucket ${BUCKET_NAME} --query 'LocationConstraint' --output text 2>/dev/null)

if [[ $? -eq 0 && $BUCKET_CHECK == "ap-northeast-2" ]]; then
    check_result 3 "PASS" "S3 버킷 구성"
else
    check_result 3 "FAIL" "S3 버킷 구성"
fi


# 6-1. Glue 데이터베이스 확인 2점
DB_CHECK=$(aws glue get-database --name retail_analytics_db --query 'Database.Name' --output text 2>/dev/null)
if [[ $DB_CHECK == "retail_analytics_db" ]]; then
    check_result 2 "PASS" "Glue 데이터베이스 구성"
else
    check_result 2 "FAIL" "Glue 데이터베이스 구성"
fi

# 6-2. Glue 분류기 확인 3점
CLASSIFIER_CHECK=$(aws glue get-classifier --name access-log-classifier --query 'Classifier.GrokClassifier.[Name,Classification,GrokPattern]' --output text 2>/dev/null)
EXPECTED_PATTERN="%{TIMESTAMP_ISO8601:timestamp} %{IP:ip_address}:%{NUMBER:port} %{WORD:method} /%{DATA:path} %{NUMBER:status_code} %{USERNAME:customer_id}"

if [[ $CLASSIFIER_CHECK == *"access-log-classifier"*"grokLog"*"$EXPECTED_PATTERN"* ]]; then
    check_result 3 "PASS" "Glue 분류기 구성"
else
    check_result 3 "FAIL" "Glue 분류기 구성"
fi


# 6-3. Glue 크롤러 확인 5점
CRAWLER_TRANS_CHECK=$(aws glue get-crawler --name retail-transaction-crawler --query 'Crawler.[Name,DatabaseName,Targets.S3Targets[0].Path]' --output text 2>/dev/null)
CRAWLER_ACCESS_CHECK=$(aws glue get-crawler --name retail-access-crawler --query 'Crawler.[Name,DatabaseName,Targets.S3Targets[0].Path]' --output text 2>/dev/null)

if [[ $CRAWLER_TRANS_CHECK == *"retail-transaction-crawler"*"retail_analytics_db"*"s3://retail-data-lake-"*"/raw/transaction/"* && 
      $CRAWLER_ACCESS_CHECK == *"retail-access-crawler"*"retail_analytics_db"*"s3://retail-data-lake-"*"/raw/access/"* ]]; then
    check_result 5 "PASS" "Glue 크롤러 구성"
else
    check_result 5 "FAIL" "Glue 크롤러 구성"
fi



# 7-1. Athena 작업그룹 확인 1점
WORKGROUP_CHECK=$(aws athena get-work-group --work-group retail-analytics-workgroup --query 'WorkGroup.Name' --output text 2>/dev/null)
if [[ $WORKGROUP_CHECK == "retail-analytics-workgroup" ]]; then
    check_result 1 "PASS" "Athena 작업그룹 구성"
else
    check_result 1 "FAIL" "Athena 작업그룹 구성"
fi


# 최종 점수 계산
echo -e "\n=== 채점 결과 ==="
echo "총 확인 항목: $TOTAL_CHECKS"
echo "통과 항목: $PASSED_CHECKS"
echo "총점: $TOTAL_SCORE/$MAX_SCORE"
