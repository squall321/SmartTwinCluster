import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { useDrag } from 'react-dnd';
import { Card, Space, Button } from 'antd';
export const ItemTypes = {
    MASS: 'mass',
    SPRING: 'spring',
    DAMPER: 'damper',
    FORCE: 'force',
    FIXED: 'fixed', // ✅ Fixed 추가
};
const Block = ({ type, label, color, }) => {
    const [{ isDragging }, drag] = useDrag(() => ({
        type,
        item: { type },
        collect: (monitor) => ({
            isDragging: !!monitor.isDragging(),
        }),
    }));
    return (_jsx(Card, { ref: drag, style: {
            width: 60,
            height: 60,
            backgroundColor: color,
            color: 'white',
            textAlign: 'center',
            lineHeight: '60px',
            cursor: 'grab',
            opacity: isDragging ? 0.5 : 1,
        }, size: "small", children: label }));
};
const BlockPalette = ({ onSelectTool }) => {
    return (_jsxs(Space, { direction: "vertical", children: [_jsx(Block, { type: ItemTypes.MASS, label: "MASS", color: "#2980b9" }), _jsx(Button, { style: { width: 60 }, onClick: () => onSelectTool(ItemTypes.SPRING), type: "primary", children: "SPRING" }), _jsx(Button, { style: { width: 60, backgroundColor: '#e67e22', borderColor: '#e67e22' }, onClick: () => onSelectTool(ItemTypes.DAMPER), type: "primary", children: "DAMPER" }), _jsx(Block, { type: ItemTypes.FIXED, label: "FIXED", color: "#2c3e50" }), " "] }));
};
export default BlockPalette;
