import React from 'react';
export declare const ItemTypes: {
    MASS: string;
    SPRING: string;
    DAMPER: string;
    FORCE: string;
    FIXED: string;
};
interface BlockPaletteProps {
    onSelectTool: (tool: string | null) => void;
}
declare const BlockPalette: React.FC<BlockPaletteProps>;
export default BlockPalette;
