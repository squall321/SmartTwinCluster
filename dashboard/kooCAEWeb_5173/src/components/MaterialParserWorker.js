// src/components/MaterialParserWorker.tsx
import { useEffect } from 'react';
export function parseMaterialTxt(content) {
    const lines = content.split(/\r?\n/);
    const result = {};
    let currentName = '';
    let currentId = '';
    let collecting = false;
    let buffer = [];
    const saveCurrentMaterial = () => {
        if (collecting && buffer.length > 0) {
            const matType = buffer[0] || '';
            const title = buffer[1] || '';
            const impl = buffer.join('\n');
            result[currentName] = {
                id: currentId,
                name: title,
                type: matType,
                impl
            };
        }
    };
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i].trim();
        if (line.startsWith('**Material,')) {
            // ✅ 이전 거 저장
            saveCurrentMaterial();
            const id = line.split(',')[1].trim();
            currentId = id.padStart(10, ' ');
            currentName = `Material_${id}`;
            collecting = false;
            buffer = [];
            continue;
        }
        if (line.startsWith('*MAT_')) {
            collecting = true;
            buffer = [line];
            continue;
        }
        if (line.startsWith('**')) {
            saveCurrentMaterial();
            collecting = false;
            buffer = [];
            continue;
        }
        if (collecting) {
            // ID 파싱
            if (buffer.length === 1) {
                const numbers = line.trim().split(/\s+/);
                const firstNum = numbers[0] ?? '';
                if (/^\d+$/.test(firstNum)) {
                    currentId = firstNum.padStart(10, ' ');
                }
            }
            // 이름 추정
            if (buffer.length === 1 && !line.includes('TITLE') && !line.startsWith('$')) {
                const maybeName = line.trim();
                if (maybeName && !maybeName.startsWith('*') && !maybeName.startsWith('$')) {
                    currentName = maybeName;
                }
            }
            buffer.push(line);
        }
    }
    // ✅ 마지막 재료도 저장
    saveCurrentMaterial();
    return result;
}
const MaterialParserWorker = ({ file, onParsed }) => {
    useEffect(() => {
        if (!file)
            return;
        const reader = new FileReader();
        reader.onload = (e) => {
            const content = e.target?.result;
            const parsed = parseMaterialTxt(content);
            onParsed(parsed);
        };
        reader.readAsText(file);
    }, [file, onParsed]);
    return null; // UI 없이 동작
};
export default MaterialParserWorker;
