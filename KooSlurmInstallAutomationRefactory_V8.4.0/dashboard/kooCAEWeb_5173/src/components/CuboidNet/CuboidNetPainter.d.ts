import React from "react";
export type FaceFileMap = {
    box_px: File;
    box_mx: File;
    box_py: File;
    box_my: File;
    box_pz: File;
    box_mz: File;
};
export type CuboidNetPainterHandle = {
    exportFaces: () => Promise<FaceFileMap>;
};
type Props = {
    onExportFaces?: (images: FaceFileMap) => void;
};
declare const _default: React.ForwardRefExoticComponent<Props & React.RefAttributes<CuboidNetPainterHandle>>;
export default _default;
