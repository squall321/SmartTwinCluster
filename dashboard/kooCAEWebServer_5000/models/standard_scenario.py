"""
Standard Scenario Models
표준 규격 시나리오 데이터 모델
"""
from dataclasses import dataclass
from typing import List, Dict, Any, Optional
from datetime import datetime


@dataclass
class AngleDefinition:
    """각도 정의"""
    name: str
    phi: float
    theta: float
    psi: float

    def to_dict(self) -> Dict[str, Any]:
        return {
            'name': self.name,
            'phi': self.phi,
            'theta': self.theta,
            'psi': self.psi
        }


@dataclass
class ScenarioMetadata:
    """시나리오 메타데이터"""
    standardReference: Optional[str] = None
    testMethod: Optional[str] = None
    requiredEquipment: Optional[List[str]] = None
    safetyRequirements: Optional[List[str]] = None

    def to_dict(self) -> Dict[str, Any]:
        return {
            'standardReference': self.standardReference,
            'testMethod': self.testMethod,
            'requiredEquipment': self.requiredEquipment,
            'safetyRequirements': self.safetyRequirements
        }


@dataclass
class StandardScenario:
    """표준 규격 시나리오"""
    id: str
    name: str
    category: str
    description: str
    version: str
    created_at: str
    parameters: Dict[str, Any]
    angles: List[AngleDefinition]
    metadata: Optional[ScenarioMetadata] = None

    def to_dict(self) -> Dict[str, Any]:
        return {
            'id': self.id,
            'name': self.name,
            'category': self.category,
            'description': self.description,
            'version': self.version,
            'created_at': self.created_at,
            'parameters': self.parameters,
            'angles': [angle.to_dict() for angle in self.angles],
            'metadata': self.metadata.to_dict() if self.metadata else None
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'StandardScenario':
        """딕셔너리에서 StandardScenario 객체 생성"""
        angles = [AngleDefinition(**angle) for angle in data.get('angles', [])]

        metadata_data = data.get('metadata')
        metadata = ScenarioMetadata(**metadata_data) if metadata_data else None

        return cls(
            id=data['id'],
            name=data['name'],
            category=data['category'],
            description=data['description'],
            version=data['version'],
            created_at=data['created_at'],
            parameters=data['parameters'],
            angles=angles,
            metadata=metadata
        )


@dataclass
class StandardScenarioSummary:
    """표준 규격 시나리오 요약"""
    id: str
    name: str
    category: str
    description: str
    version: str
    angleCount: int

    def to_dict(self) -> Dict[str, Any]:
        return {
            'id': self.id,
            'name': self.name,
            'category': self.category,
            'description': self.description,
            'version': self.version,
            'angleCount': self.angleCount
        }
