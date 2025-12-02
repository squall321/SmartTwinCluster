import { ParsedPart } from '../../types/parsedPart';
interface PartSelectorProps {
    allParts: ParsedPart[];
    onSelect: (part: ParsedPart) => void;
}
declare const PartSelector: React.FC<PartSelectorProps>;
export default PartSelector;
