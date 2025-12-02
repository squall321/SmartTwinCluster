import React, { useState } from 'react';
import { Card, Alert, Button, Space, Spin, Typography } from 'antd';
import { simulationAnalysisService } from '../../services/analysisService';

interface CaseAnalysisViewProps {
  selectedCases: string[];
  analysisMode: 'single' | 'batch';
}

const { Text } = Typography;

const CaseAnalysisView: React.FC<CaseAnalysisViewProps> = ({ selectedCases, analysisMode }) => {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<any>(null);

  const handleRunAnalysis = async () => {
    if (!selectedCases || selectedCases.length === 0) return;
    setLoading(true);
    setError(null);
    setResult(null);
    try {
      if (analysisMode === 'single') {
        const res = await simulationAnalysisService.analyzeSingleCase(selectedCases[0]);
        setResult(res);
      } else {
        const res = await simulationAnalysisService.analyzeBatch({ case_ids: selectedCases, include_summary: true });
        setResult(res);
      }
    } catch (e: any) {
      setError(e?.message || '분석에 실패했습니다.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <Card>
      {!selectedCases || selectedCases.length === 0 ? (
        <Alert type="info" message="케이스를 선택해주세요." showIcon />
      ) : (
        <Space direction="vertical" style={{ width: '100%' }}>
          <Text>
            선택된 케이스: {selectedCases.join(', ')} ({analysisMode === 'single' ? '단일' : '일괄'})
          </Text>
          <Button type="primary" onClick={handleRunAnalysis} loading={loading}>
            분석 실행
          </Button>
          {error && <Alert type="error" message={error} showIcon />}
          <Spin spinning={loading}>
            {result && (
              <Card size="small" title="분석 결과">
                <pre style={{ margin: 0, whiteSpace: 'pre-wrap' }}>{JSON.stringify(result, null, 2)}</pre>
              </Card>
            )}
          </Spin>
        </Space>
      )}
    </Card>
  );
};

export default CaseAnalysisView;
