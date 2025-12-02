import React from 'react';
import { ParsedPart } from '../../types/parsedPart';
interface PartIdFinderUploaderProps {
    onParsed: (filename: string, parts: ParsedPart[], file?: File) => void;
}
declare const PartIdFinderUploader: React.FC<PartIdFinderUploaderProps>;
export default PartIdFinderUploader;
