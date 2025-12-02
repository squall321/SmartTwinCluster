import { ParsedPart } from '../../types/parsedPart';
interface PartTableProps {
    parts: ParsedPart[];
    editable?: boolean;
    onRemove?: (id: string) => void;
    title?: string;
}
declare const PartTable: React.FC<PartTableProps>;
export default PartTable;
