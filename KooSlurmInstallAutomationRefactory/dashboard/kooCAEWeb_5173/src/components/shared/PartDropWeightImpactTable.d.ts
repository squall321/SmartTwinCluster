import { ImpactAnalysisPart } from '../../types/parsedPart';
interface PartDropWeightImpactTableProps {
    parts: ImpactAnalysisPart[];
    onRemove: (id: string) => void;
    onPatternChange: (id: string, pattern: ImpactAnalysisPart['impactPattern']) => void;
    onHeightChange: (id: string, height: number) => void;
    onImpactorChange: (id: string, field: 'impactorType' | 'impactorDiameter' | 'impactorWeight', value: any) => void;
    onVelocityVectorChange: (id: string, vector: number[]) => void;
}
declare const PartDropWeightImpactTable: React.FC<PartDropWeightImpactTableProps>;
export default PartDropWeightImpactTable;
