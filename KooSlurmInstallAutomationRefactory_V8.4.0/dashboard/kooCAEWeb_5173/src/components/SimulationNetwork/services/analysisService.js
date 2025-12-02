/**
 * 시뮬레이션 분석 API 클라이언트
 * 백엔드 분석 API와 통신하는 서비스
 */
import { api } from '../../../api/axiosClient';
class SimulationAnalysisService {
    baseUrl = '/api/proxy/automation/api/simulation-automation/analysis';
    /**
     * 단일 케이스 분석
     */
    async analyzeSingleCase(caseId, includeRaw = false) {
        try {
            const params = includeRaw ? '?include_raw=true' : '';
            const response = await api.get(`${this.baseUrl}/case/${caseId}${params}`);
            return response.data;
        }
        catch (error) {
            console.error('[AnalysisService] Failed to analyze single case:', error);
            throw new Error(`Failed to analyze case ${caseId}: ${error}`);
        }
    }
    /**
     * 일괄 분석
     */
    async analyzeBatch(params) {
        try {
            const response = await api.post(`${this.baseUrl}/batch`, params);
            return response.data;
        }
        catch (error) {
            console.error('[AnalysisService] Failed to perform batch analysis:', error);
            throw new Error(`Batch analysis failed: ${error}`);
        }
    }
    /**
     * 요약 리포트 생성
     */
    async generateSummary(params) {
        try {
            const response = await api.post(`${this.baseUrl}/summary`, params);
            return response.data;
        }
        catch (error) {
            console.error('[AnalysisService] Failed to generate summary:', error);
            throw new Error(`Summary generation failed: ${error}`);
        }
    }
    /**
     * 접촉 타입 통계
     */
    async getContactTypeStats(project, revision) {
        try {
            const params = new URLSearchParams();
            if (project)
                params.append('project', project);
            if (revision)
                params.append('revision', revision);
            const response = await api.get(`${this.baseUrl}/contact-types?${params.toString()}`);
            return response.data;
        }
        catch (error) {
            console.error('[AnalysisService] Failed to get contact type stats:', error);
            throw new Error(`Contact type stats failed: ${error}`);
        }
    }
    /**
     * 부품 카테고리 통계
     */
    async getPartsCategoryStats(project, revision) {
        try {
            const params = new URLSearchParams();
            if (project)
                params.append('project', project);
            if (revision)
                params.append('revision', revision);
            const response = await api.get(`${this.baseUrl}/parts-categories?${params.toString()}`);
            return response.data;
        }
        catch (error) {
            console.error('[AnalysisService] Failed to get parts category stats:', error);
            throw new Error(`Parts category stats failed: ${error}`);
        }
    }
    /**
     * 시스템 상태 확인
     */
    async checkSystemHealth() {
        try {
            const response = await api.get(`${this.baseUrl}/health-check`);
            return response.data;
        }
        catch (error) {
            console.error('[AnalysisService] Health check failed:', error);
            throw new Error(`Health check failed: ${error}`);
        }
    }
    /**
     * 여러 케이스의 기본 정보만 가져오기 (빠른 프리뷰용)
     */
    async getQuickAnalysis(caseIds) {
        try {
            // 일괄 분석을 사용하되 요약 정보만 요청
            const result = await this.analyzeBatch({
                case_ids: caseIds,
                include_summary: false
            });
            return result.analyses.map(analysis => ({
                case_id: analysis.case_id,
                total_contacts: analysis.analysis.contact_analysis.total_contacts,
                total_parts: analysis.analysis.parts_analysis.total_parts,
                scenario_mode: analysis.analysis.basic_info.scenario_mode,
                status: 'success'
            }));
        }
        catch (error) {
            console.error('[AnalysisService] Quick analysis failed:', error);
            // 실패한 케이스들에 대한 기본 응답
            return caseIds.map(caseId => ({
                case_id: caseId,
                total_contacts: 0,
                total_parts: 0,
                scenario_mode: 'unknown',
                status: 'failed'
            }));
        }
    }
}
// 싱글톤 인스턴스
export const simulationAnalysisService = new SimulationAnalysisService();
// 편의 함수들
export const analyzeCase = (caseId) => simulationAnalysisService.analyzeSingleCase(caseId);
export const analyzeCases = (caseIds) => simulationAnalysisService.analyzeBatch({ case_ids: caseIds, include_summary: true });
export const getContactStats = (project) => simulationAnalysisService.getContactTypeStats(project);
export const getPartsStats = (project) => simulationAnalysisService.getPartsCategoryStats(project);
