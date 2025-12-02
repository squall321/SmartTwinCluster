import { AutoComplete } from 'antd';
import { ParsedPart } from '../../types/parsedPart';

interface PartSelectorProps {
  allParts: ParsedPart[];
  onSelect: (part: ParsedPart) => void;
}

const PartSelector: React.FC<PartSelectorProps> = ({ allParts, onSelect }) => {
  return (
    <AutoComplete
      style={{ width: '100%' }}
      placeholder="예: 1001 또는 PI_LAYER"
      options={allParts.map(part => ({
        value: part.id,
        label: `${part.id} - ${part.name}`
      }))}
      filterOption={(inputValue, option) =>
        option?.label.toLowerCase().includes(inputValue.toLowerCase()) ?? false
      }
      onSelect={(value) => {
        const part = allParts.find(p => p.id === value || p.name === value);
        if (part) onSelect(part);
      }}
    />
  );
};

export default PartSelector;
