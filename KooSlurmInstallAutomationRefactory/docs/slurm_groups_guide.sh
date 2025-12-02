# Slurm 스케줄러 그룹 설정 완벽 가이드
# 128코어 / 1024코어 전용 그룹 만들기

## 이 파일의 사용법:
## 1. 섹션별로 복사하여 실행
## 2. 환경에 맞게 값 수정
## 3. slurmctld 재시작 필요 (slurm.conf 변경 시)

## =============================================================================
## 1. PARTITION 기반 그룹 (slurm.conf에 추가)
## =============================================================================

# 소규모 작업 전용 파티션 (최대 128코어)
PartitionName=small \
    Nodes=compute[01-16] \
    MaxNodes=1 \
    Default=YES \
    State=UP \
    AllowQOS=small_qos

# 중규모 작업 파티션 (최대 512코어)
PartitionName=medium \
    Nodes=compute[17-32] \
    MaxNodes=4 \
    Default=NO \
    State=UP \
    Priority=50 \
    AllowQOS=medium_qos

# 대규모 작업 전용 파티션 (최대 1024코어)
PartitionName=large \
    Nodes=compute[33-64] \
    MaxNodes=8 \
    Default=NO \
    State=UP \
    Priority=100 \
    AllowQOS=large_qos

## =============================================================================
## 2. QOS 생성 (sacctmgr 명령으로 실행)
## =============================================================================

# 소규모 작업 QoS (최대 128코어)
sacctmgr -i add qos small_qos \
    Description="Small jobs up to 128 cores" \
    MaxTRESPerJob=cpu=128 \
    MaxJobsPerUser=20 \
    MaxSubmitJobsPerUser=50 \
    MaxWall=1-00:00:00 \
    Priority=100 \
    Flags=DenyOnLimit

# 대규모 작업 QoS (최대 1024코어)
sacctmgr -i add qos large_qos \
    Description="Large jobs up to 1024 cores" \
    MaxTRESPerJob=cpu=1024 \
    MaxJobsPerUser=5 \
    MaxSubmitJobsPerUser=10 \
    MaxWall=7-00:00:00 \
    Priority=1000 \
    Flags=DenyOnLimit

## =============================================================================
## 3. 사용자에게 QOS 할당
## =============================================================================

# 일반 사용자 (small만 사용 가능)
sacctmgr -i add user user1 account=default \
    DefaultQOS=small_qos \
    QosLevel=small_qos

# 고급 사용자 (small, large 둘 다 사용 가능)
sacctmgr -i add user poweruser account=default \
    DefaultQOS=small_qos \
    QosLevel=small_qos,large_qos

## =============================================================================
## 4. 작업 제출 예시
## =============================================================================

# 128코어 작업
sbatch --qos=small_qos --ntasks=128 job.sh

# 1024코어 작업
sbatch --qos=large_qos --ntasks=1024 --nodes=8 job.sh

## =============================================================================
## 5. 확인 명령어
## =============================================================================

# QoS 목록 확인
sacctmgr show qos format=Name,Priority,MaxWall,MaxTRESPJ,MaxJobsPU

# 사용자 권한 확인
sacctmgr show user user1 withassoc

# 현재 작업 상태 (QoS별)
squeue -o "%.18i %.9P %.8j %.8u %.2t %.10M %.6D %Q"
