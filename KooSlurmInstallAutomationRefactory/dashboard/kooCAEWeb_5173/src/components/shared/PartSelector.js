import { jsx as _jsx } from "react/jsx-runtime";
import { AutoComplete } from 'antd';
const PartSelector = ({ allParts, onSelect }) => {
    return (_jsx(AutoComplete, { style: { width: '100%' }, placeholder: "\uC608: 1001 \uB610\uB294 PI_LAYER", options: allParts.map(part => ({
            value: part.id,
            label: `${part.id} - ${part.name}`
        })), filterOption: (inputValue, option) => option?.label.toLowerCase().includes(inputValue.toLowerCase()) ?? false, onSelect: (value) => {
            const part = allParts.find(p => p.id === value || p.name === value);
            if (part)
                onSelect(part);
        } }));
};
export default PartSelector;
