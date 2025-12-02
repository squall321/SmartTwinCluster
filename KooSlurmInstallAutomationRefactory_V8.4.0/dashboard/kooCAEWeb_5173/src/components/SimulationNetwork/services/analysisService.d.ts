/**
 * 시뮬레이션 분석 API 클라이언트
 * 백엔드 분석 API와 통신하는 서비스
 */
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
declare class SimulationAnalysisService {
    private baseUrl;
    /**
     * 단일 케이스 분석
     */
    analyzeSingleCase(caseId: string, includeRaw?: boolean): Promise<SimulationAnalysisResult>;
    /**
     * 일괄 분석
     */
    analyzeBatch(params: {
        case_ids: string[];
        project?: string;
        revision?: string;
        include_summary?: boolean;
    }): Promise<BatchAnalysisResult>;
    /**
     * 요약 리포트 생성
     */
    generateSummary(params: {
        project?: string;
        revision?: string;
        modes?: string[];
    }): Promise<any>;
    /**
     * 접촉 타입 통계
     */
    getContactTypeStats(project?: string, revision?: string): Promise<ContactTypeStats>;
    /**
     * 부품 카테고리 통계
     */
    getPartsCategoryStats(project?: string, revision?: string): Promise<PartsCategoryStats>;
    /**
     * 시스템 상태 확인
     */
    checkSystemHealth(): Promise<{
        status: string;
        available_cases: number;
        analyzable_cases: number;
        sample_analysis?: any;
    }>;
    /**
     * 여러 케이스의 기본 정보만 가져오기 (빠른 프리뷰용)
     */
    getQuickAnalysis(caseIds: string[]): Promise<Array<{
        case_id: string;
        total_contacts: number;
        total_parts: number;
        scenario_mode: string;
        status: 'success' | 'failed';
    }>>;
}
export declare const simulationAnalysisService: SimulationAnalysisService;
export declare const analyzeCase: (caseId: string) => Promise<SimulationAnalysisResult>;
export declare const analyzeCases: (caseIds: string[]) => Promise<BatchAnalysisResult>;
export declare const getContactStats: (project?: string) => Promise<ContactTypeStats>;
export declare const getPartsStats: (project?: string) => Promise<PartsCategoryStats>;
export {};
