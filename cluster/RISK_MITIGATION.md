# 멀티헤드 오프라인 설치 리스크 대응 가이드

## 개요

이 문서는 멀티헤드 HPC 클러스터 오프라인 설치 과정에서 발생할 수 있는 주요 리스크와 그에 대한 대응 방안을 설명합니다.

---

## 1. Phase 검증 실패 시 설치 중단

### 문제점
이전에는 phase 검증이 실패해도 경고만 출력하고 다음 단계로 진행했습니다. 이로 인해 서비스가 제대로 시작되지 않은 상태에서 후속 phase가 실행되어 연쇄적인 오류가 발생할 수 있었습니다.

### 해결 방안
- **Auto-confirm 모드**: 검증 실패 시 즉시 설치 중단 (exit 1)
- **Interactive 모드**: 사용자에게 계속 진행 여부 확인

### 수정된 파일
`cluster/start_multihead.sh`

### 동작 방식
```
Phase 실행 → 검증 → 실패 시
  ├── Auto-confirm: 즉시 중단, 오류 원인 출력
  └── Interactive: 사용자 선택 (계속/중단)
```

---

## 2. SSH 연결 실패를 Critical 에러로 처리

### 문제점
SSH 연결 실패가 단순 경고로 처리되어, 일부 노드에 접근 불가한 상태에서 설치가 진행되었습니다.

### 해결 방안
- SSH 연결 실패를 Critical 에러로 상향
- 상세한 트러블슈팅 가이드 제공
- Auto-confirm 모드에서는 즉시 중단

### 수정된 파일
`cluster/start_multihead.sh`

### 트러블슈팅 가이드
1. 네트워크 연결 확인: `ping <node_ip>`
2. SSH 키 설정 확인: `ssh-copy-id user@<node_ip>`
3. sshd 서비스 상태 확인
4. 방화벽 규칙 확인 (포트 22)

---

## 3. GlusterFS Peer Probe 재시도 로직

### 문제점
GlusterFS peer probe가 일시적인 네트워크 지연이나 서비스 시작 타이밍으로 인해 실패할 수 있었습니다.

### 해결 방안
- 최대 5회 재시도
- Exponential backoff 적용 (2초, 4초, 8초, 16초)
- 실패 시 상세 트러블슈팅 정보 제공

### 수정된 파일
`cluster/setup/phase0_storage.sh`

### 재시도 패턴
```
시도 1 → 실패 → 2초 대기
시도 2 → 실패 → 4초 대기
시도 3 → 실패 → 8초 대기
시도 4 → 실패 → 16초 대기
시도 5 → 실패 → 에러 로그 출력
```

---

## 4. MariaDB Galera 자동 복구

### 문제점
비정상 종료 후 MariaDB Galera 클러스터가 `safe_to_bootstrap=0` 또는 `seqno=-1` 상태로 남아 수동 개입이 필요했습니다.

### 해결 방안
1. **wsrep_recover 실행**: 마지막 커밋 위치 자동 복구
2. **safe_to_bootstrap 자동 설정**: 복구된 seqno로 grastate.dat 업데이트
3. **단일 노드 복구**: 다른 노드 사용 불가 시 비상 부트스트랩

### 수정된 파일
`cluster/setup/phase1_database.sh`

### 복구 순서
```
seqno=-1 또는 safe_to_bootstrap=0 감지
    ↓
wsrep_recover 실행
    ↓
seqno 복구 성공?
    ├── 예: grastate.dat 업데이트
    └── 아니오: 다른 노드 확인
              ├── 있음: 클러스터 조인
              └── 없음: 비상 부트스트랩
```

---

## 5. Munge 키 동기화

### 문제점
각 노드에서 독립적으로 munge 키를 생성하여 노드 간 인증이 실패할 수 있었습니다.

### 해결 방안
- **첫 번째 컨트롤러**: 마스터 munge 키 생성 및 관리
- **다른 컨트롤러/노드**: 첫 번째 컨트롤러에서 키 동기화
- 재시도 로직 (3회) 및 검증

### 수정된 파일
`cluster/setup/phase3_slurm.sh`

### 동기화 흐름
```
첫 번째 컨트롤러 (Controller 1)
    │
    ├── munge.key 생성 (없는 경우)
    │
    └── 키 배포 ─→ Controller 2, 3
                  Compute Node 1, 2, ...
```

### 키 동기화 검증
- MD5 해시 비교로 키 동일성 확인
- 권한 설정 검증 (400, munge:munge)
- munge 서비스 재시작 및 상태 확인

---

## 요약

| 리스크 | 심각도 | 해결 방법 | 관련 파일 |
|--------|--------|-----------|-----------|
| Phase 검증 무시 | Critical | 검증 실패 시 중단 | start_multihead.sh |
| SSH 연결 실패 | Critical | 즉시 중단 + 가이드 | start_multihead.sh |
| GlusterFS Probe 실패 | High | 5회 재시도 | phase0_storage.sh |
| Galera 부트 실패 | High | wsrep_recover 자동화 | phase1_database.sh |
| Munge 키 불일치 | High | 중앙집중식 동기화 | phase3_slurm.sh |

---

## 관련 문서

- [설치 가이드](../README.md)
- [멀티헤드 설치 스크립트](start_multihead.sh)
- [Phase 0: 스토리지 설정](setup/phase0_storage.sh)
- [Phase 1: 데이터베이스 설정](setup/phase1_database.sh)
- [Phase 3: Slurm 설정](setup/phase3_slurm.sh)
