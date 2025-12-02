/**
 * 시뮬레이션 분석 API 클라이언트
 * 백엔드 분석 API와 통신하는 서비스
 */

import { api } from '../../../api/axiosClient';

// 분석 결과 타입 정의
export interface ContactAnalysis {
  total_contacts: number;
  contact_types: Record<string, number>;
  area_stats: {
    total_area: number;
    average_area: number;
    median_area: number;
    max_area: number;
    min_area: number;
    std_deviation: number;
  };
  largest_contact: {
    id: string;
    label: string;
    type: string;
    total_area: number;
    areas: Record<string, number>;
  };
  smallest_contact: {
    id: string;
    label: string;
    type: string;
    total_area: number;
    areas: Record<string, number>;
  };
}

export interface PartsAnalysis {
  total_parts: number;
  part_categories: Record<string, number>;
  parts_with_contacts: number;
  isolated_parts: string[];
}

export interface SimulationAnalysisResult {
  case_id: string;
  analysis: {
    basic_info: {
      case_id: string;
      run_id: string;
      stage: string;
      model_name: string;
      scenario_mode: string;
      analysis_timestamp: string;
    };
    contact_analysis: ContactAnalysis;
    parts_analysis: PartsAnalysis;
  };
  raw_data?: any;
}

export interface BatchAnalysisResult {
  total_cases: number;
  successful_analyses: number;
  failed_cases: string[];
  analyses: SimulationAnalysisResult[];
  summary_report?: {
    summary: {
      total_cases: number;
      scenario_modes: Record<string, number>;
      stages: Record<string, number>;
      drop_height_stats: {
        average: number;
        median: number;
        max: number;
        min: number;
        unique_heights: number[];
      };
    };
    contact_analysis: {
      contact_stats: {
        average: number;
        median: number;
        max: number;
        min: number;
      };
      contact_type_distribution: Record<string, number>;
    };
    parts_analysis: {
      parts_stats: {
        average: number;
        median: number;
        max: number;
        min: number;
      };
    };
  };
}

export interface ContactTypeStats {
  contact_types: Record<string, {
    count: number;
    cases: string[];
    percentage: number;
  }>;
  total_contacts: number;
  total_cases: number;
}

export interface PartsCategoryStats {
  part_categories: Record<string, {
    count: number;
    cases: string[];
    percentage: number;
  }>;
  total_parts: number;
  total_cases: number;
}

class SimulationAnalysisService {
  private baseUrl = '/api/proxy/automation/api/simulation-automation/analysis';

  /**
   * 단일 케이스 분석
   */
  async analyzeSingleCase(caseId: string, includeRaw = false): Promise<SimulationAnalysisResult> {
    try {
      const params = includeRaw ? '?include_raw=true' : '';
      const response = await api.get(`${this.baseUrl}/case/${caseId}${params}`);
      return response.data;
    } catch (error) {
      console.error('[AnalysisService] Failed to analyze single case:', error);
      throw new Error(`Failed to analyze case ${caseId}: ${error}`);
    }
  }

  /**
   * 일괄 분석
   */
  async analyzeBatch(params: {
    case_ids: string[];
    project?: string;
    revision?: string;
    include_summary?: boolean;
  }): Promise<BatchAnalysisResult> {
    try {
      const response = await api.post(`${this.baseUrl}/batch`, params);
      return response.data;
    } catch (error) {
      console.error('[AnalysisService] Failed to perform batch analysis:', error);
      throw new Error(`Batch analysis failed: ${error}`);
    }
  }

  /**
   * 요약 리포트 생성
   */
  async generateSummary(params: {
    project?: string;
    revision?: string;
    modes?: string[];
  }): Promise<any> {
    try {
      const response = await api.post(`${this.baseUrl}/summary`, params);
      return response.data;
    } catch (error) {
      console.error('[AnalysisService] Failed to generate summary:', error);
      throw new Error(`Summary generation failed: ${error}`);
    }
  }

  /**
   * 접촉 타입 통계
   */
  async getContactTypeStats(project?: string, revision?: string): Promise<ContactTypeStats> {
    try {
      const params = new URLSearchParams();
      if (project) params.append('project', project);
      if (revision) params.append('revision', revision);
      
      const response = await api.get(`${this.baseUrl}/contact-types?${params.toString()}`);
      return response.data;
    } catch (error) {
      console.error('[AnalysisService] Failed to get contact type stats:', error);
      throw new Error(`Contact type stats failed: ${error}`);
    }
  }

  /**
   * 부품 카테고리 통계
   */
  async getPartsCategoryStats(project?: string, revision?: string): Promise<PartsCategoryStats> {
    try {
      const params = new URLSearchParams();
      if (project) params.append('project', project);
      if (revision) params.append('revision', revision);
      
      const response = await api.get(`${this.baseUrl}/parts-categories?${params.toString()}`);
      return response.data;
    } catch (error) {
      console.error('[AnalysisService] Failed to get parts category stats:', error);
      throw new Error(`Parts category stats failed: ${error}`);
    }
  }

  /**
   * 시스템 상태 확인
   */
  async checkSystemHealth(): Promise<{
    status: string;
    available_cases: number;
    analyzable_cases: number;
    sample_analysis?: any;
  }> {
    try {
      const response = await api.get(`${this.baseUrl}/health-check`);
      return response.data;
    } catch (error) {
      console.error('[AnalysisService] Health check failed:', error);
      throw new Error(`Health check failed: ${error}`);
    }
  }

  /**
   * 여러 케이스의 기본 정보만 가져오기 (빠른 프리뷰용)
   */
  async getQuickAnalysis(caseIds: string[]): Promise<Array<{
    case_id: string;
    total_contacts: number;
    total_parts: number;
    scenario_mode: string;
    status: 'success' | 'failed';
  }>> {
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
        status: 'success' as const
      }));
    } catch (error) {
      console.error('[AnalysisService] Quick analysis failed:', error);
      // 실패한 케이스들에 대한 기본 응답
      return caseIds.map(caseId => ({
        case_id: caseId,
        total_contacts: 0,
        total_parts: 0,
        scenario_mode: 'unknown',
        status: 'failed' as const
      }));
    }
  }
}

// 싱글톤 인스턴스
export const simulationAnalysisService = new SimulationAnalysisService();

// 편의 함수들
export const analyzeCase = (caseId: string) => simulationAnalysisService.analyzeSingleCase(caseId);
export const analyzeCases = (caseIds: string[]) => simulationAnalysisService.analyzeBatch({ case_ids: caseIds, include_summary: true });
export const getContactStats = (project?: string) => simulationAnalysisService.getContactTypeStats(project);
export const getPartsStats = (project?: string) => simulationAnalysisService.getPartsCategoryStats(project);
