import React from 'react';
import { MassNode, SpringEdge, DamperEdge, Force } from '../../types/mck/modelTypes';
interface PropertyEditorProps {
    selected: {
        type: 'mass';
        data: MassNode;
    } | {
        type: 'spring';
        data: SpringEdge;
    } | {
        type: 'damper';
        data: DamperEdge;
    } | {
        type: 'force';
        data: Force;
    } | null;
    onChange: (updated: any) => void;
}
declare const PropertyEditor: React.FC<PropertyEditorProps>;
export default PropertyEditor;
