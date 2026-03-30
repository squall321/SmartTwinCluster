# Monitoring (Prometheus + Node Exporter) Debug Agent

Prometheus (9090) + Node Exporter (9100) 모니터링 시스템 디버깅 담당.

## Scope
- `dashboard/prometheus_9090/`
- `dashboard/node_exporter_9100/`

## Debug Toolkit
```bash
# Prometheus 상태
curl -s http://localhost:9090/-/healthy
curl -s http://localhost:9090/api/v1/targets | python3 -m json.tool

# Node Exporter 상태
curl -s http://localhost:9100/metrics | head -20

# 프로세스 확인
ps aux | grep prometheus
ps aux | grep node_exporter
lsof -i :9090 -i :9100
```

## Common Issues
1. **타겟 DOWN**: 스크랩 타겟 접근 불가, 방화벽
2. **메트릭 수집 안됨**: node_exporter 프로세스 확인
3. **디스크 사용량 증가**: Prometheus 데이터 보존 기간 설정
4. **쿼리 타임아웃**: 시계열 데이터 양, 쿼리 최적화
5. **PID 파일 잔존**: `.prometheus.pid`, `.node_exporter.pid` 정리

## Related Agents
- `monitoring-9090-9100-dev` — 개발/설정 담당
- `slurm-ops` — 클러스터 헬스 모니터링
- `backend-5010-debug` — prometheus_api.py 디버깅
