import React from 'react';
import { MaterialData } from '../components/MaterialParserWorker';
interface MaterialSelectorProps {
    onChange?: (materialName: string, materialData: MaterialData) => void;
    mode?: 'display' | 'all';
}
declare const MaterialSelectorComponent: React.FC<MaterialSelectorProps>;
export default MaterialSelectorComponent;
