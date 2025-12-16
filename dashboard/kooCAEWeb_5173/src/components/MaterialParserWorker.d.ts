export interface MaterialData {
    id: string;
    name: string;
    type: string;
    impl: string;
}
export interface MaterialParserWorkerProps {
    file: File | null;
    onParsed: (materials: Record<string, MaterialData>) => void;
}
export declare function parseMaterialTxt(content: string): Record<string, MaterialData>;
declare const MaterialParserWorker: React.FC<MaterialParserWorkerProps>;
export default MaterialParserWorker;
