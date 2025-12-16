import React from 'react';
import { MassNode, SpringEdge, DamperEdge, FixedPoint, MCKSystem } from '../../types/mck/modelTypes';
interface EditorCanvasProps {
    selectedTool: string | null;
    onClearTool: () => void;
    onSelect: (element: {
        type: 'mass';
        data: MassNode;
    } | {
        type: 'spring';
        data: SpringEdge;
    } | {
        type: 'damper';
        data: DamperEdge;
    } | {
        type: 'fixed';
        data: FixedPoint;
    } | null) => void;
    system: MCKSystem;
    setSystem: React.Dispatch<React.SetStateAction<MCKSystem>>;
    massIdCounter: number;
    setMassIdCounter: React.Dispatch<React.SetStateAction<number>>;
    springIdCounter: number;
    setSpringIdCounter: React.Dispatch<React.SetStateAction<number>>;
    damperIdCounter: number;
    setDamperIdCounter: React.Dispatch<React.SetStateAction<number>>;
    fixedIdCounter: number;
    setFixedIdCounter: React.Dispatch<React.SetStateAction<number>>;
}
declare const EditorCanvas: React.FC<EditorCanvasProps>;
export default EditorCanvas;
