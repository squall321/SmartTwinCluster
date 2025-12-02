// src/services/mck/jsonUtils.ts

import { MCKSystem } from '../../types/mck/modelTypes';

export const saveSystemAsJSON = (system: MCKSystem) => {
  const dataStr =
    'data:text/json;charset=utf-8,' +
    encodeURIComponent(JSON.stringify(system, null, 2));
  const downloadAnchorNode = document.createElement('a');
  downloadAnchorNode.setAttribute('href', dataStr);
  downloadAnchorNode.setAttribute('download', 'mck_system_model.json');
  document.body.appendChild(downloadAnchorNode);
  downloadAnchorNode.click();
  downloadAnchorNode.remove();
};

export const loadSystemFromJSON = (
  file: File,
  onLoad: (data: MCKSystem) => void
) => {
  const reader = new FileReader();
  reader.onload = (event) => {
    try {
      const result = event.target?.result;
      if (typeof result === 'string') {
        const json = JSON.parse(result);
        onLoad(json);
      }
    } catch (e) {
      alert('Invalid JSON!');
    }
  };
  reader.readAsText(file);
};
