/**
 * Standard Scenario Types
 * 표준 규격 시나리오 타입 정의
 */

export interface AngleDefinition {
  name: string;
  phi: number;
  theta: number;
  psi: number;
}

export interface ScenarioMetadata {
  standardReference?: string;
  testMethod?: string;
  requiredEquipment?: string[];
  safetyRequirements?: string[];
}

export interface StandardScenario {
  id: string;
  name: string;
  category: string;
  description: string;
  version: string;
  created_at: string;
  parameters: Record<string, any>;
  angles: AngleDefinition[];
  metadata?: ScenarioMetadata;
}

export interface StandardScenarioSummary {
  id: string;
  name: string;
  category: string;
  description: string;
  version: string;
  angleCount: number;
}

export interface CategoryInfo {
  id: string;
  name: string;
}
