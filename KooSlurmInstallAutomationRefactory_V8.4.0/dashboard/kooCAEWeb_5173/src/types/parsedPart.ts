// src/types/parsedPart.ts

/**
 * LS-DYNA .k 파일에서 추출된 Part 정보를 나타냅니다.
 * - `id`: Part ID (숫자지만 문자열로 처리해 일관성 유지)
 * - `name`: Part 이름 (재료나 기능 구분 등)
 */
export interface ParsedPart {
    id: string;
    name: string;
    boundaryBox?:{
      min_x: number;
      min_y: number;
      min_z: number;
      max_x: number;
      max_y: number;
      max_z: number;
    }
    modelThickness?: number;
  }

export interface ImpactAnalysisPart extends ParsedPart {
  impactPattern: "1x1" | "3x3" | "1x3" | "3x1" | "2x2" | "2x1" | "1x2";
  impactHeight: number; // mm
  impactVelocityVector: number[];
  impactorType: "cylinder" | "sphere";
  impactorDiameter: number; // mm
  impactorWeight: number;   // g
}