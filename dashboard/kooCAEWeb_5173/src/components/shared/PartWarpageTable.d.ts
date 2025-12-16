import { ParsedPart } from '../../types/parsedPart';
interface WarpageInfo {
    rawData: number[][];
    xLength: number;
    yLength: number;
    scaleFactor: number;
}
interface PartWarpageTableProps {
    parts: ParsedPart[];
    editable?: boolean;
    onRemove?: (id: string) => void;
    title?: string;
    onUploadDat?: (partId: string, file: File) => void;
    onViewPart?: (partId: string) => void;
    datStatusMap?: Record<string, boolean>;
    warpageMap: Record<string, WarpageInfo>;
    onParamChange: (partId: string, newParams: Partial<Pick<WarpageInfo, 'xLength' | 'yLength' | 'scaleFactor'>>) => void;
}
declare const PartWarpageTable: React.FC<PartWarpageTableProps>;
export default PartWarpageTable;
