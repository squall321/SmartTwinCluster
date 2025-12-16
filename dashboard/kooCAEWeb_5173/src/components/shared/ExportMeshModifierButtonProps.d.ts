interface ExportMeshModifierButtonProps {
    kFile: File | null;
    kFileName: string;
    optionFileGenerator: () => File;
    solver?: string;
    mode?: string;
    optionFileName?: string;
    buttonLabel?: string;
}
declare const ExportMeshModifierButton: React.FC<ExportMeshModifierButtonProps>;
export default ExportMeshModifierButton;
