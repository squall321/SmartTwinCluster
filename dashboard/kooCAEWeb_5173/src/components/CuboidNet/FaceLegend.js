import { jsx as _jsx, jsxs as _jsxs, Fragment as _Fragment } from "react/jsx-runtime";
import { Divider, Space, Tag, Typography } from "antd";
import { FACE_COLOR } from "./types";
import { faceSizeMM } from "./utils/layout";
const { Text } = Typography;
export default function FaceLegend({ xMM, yMM, zMM, layout }) {
    return (_jsxs(_Fragment, { children: [["+X", "-X", "+Y", "-Y", "+Z", "-Z"].map((f) => {
                const mm = faceSizeMM(f, xMM, yMM, zMM);
                const r = layout.faceRects[f];
                return (_jsxs("div", { style: { display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 8 }, children: [_jsxs(Space, { children: [_jsx("span", { style: { display: "inline-block", width: 16, height: 16, background: FACE_COLOR[f], border: "1px solid rgba(0,0,0,0.35)", borderRadius: 3, boxShadow: "0 0 0 1px rgba(255,255,255,0.6) inset" } }), _jsx(Text, { strong: true, children: f })] }), _jsxs(Text, { type: "secondary", children: [mm.w, "\u00D7", mm.h, " mm ", r ? `(${r.w}×${r.h}px)` : ""] })] }, f));
            }), _jsx(Divider, {}), _jsxs(Space, { direction: "vertical", size: 2, children: [_jsx(Tag, { color: "geekblue", children: "Bold lines" }), _jsx(Text, { type: "secondary", children: "face seams" }), _jsx(Tag, { color: "default", children: "Dashed" }), _jsx(Text, { type: "secondary", children: "hinges between faces" })] })] }));
}
