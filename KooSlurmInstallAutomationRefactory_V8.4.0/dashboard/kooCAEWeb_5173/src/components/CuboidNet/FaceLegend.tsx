import React from "react";
import { Divider, Space, Tag, Typography } from "antd";
import { Face, FACE_COLOR } from "./types";
import { faceSizeMM } from "./utils/layout";
import { NetLayout } from "./types";

const { Text } = Typography;

type Props = {
  xMM: number; yMM: number; zMM: number;
  layout: NetLayout;
};

export default function FaceLegend({ xMM, yMM, zMM, layout }: Props) {
  return (
    <>
      {(["+X","-X","+Y","-Y","+Z","-Z"] as Face[]).map((f)=>{
        const mm = faceSizeMM(f, xMM, yMM, zMM);
        const r = layout.faceRects[f];
        return (
          <div key={f} style={{ display:"flex", alignItems:"center", justifyContent:"space-between", marginBottom:8 }}>
            <Space>
              <span style={{ display:"inline-block", width:16, height:16, background:FACE_COLOR[f], border:"1px solid rgba(0,0,0,0.35)", borderRadius:3, boxShadow:"0 0 0 1px rgba(255,255,255,0.6) inset" }} />
              <Text strong>{f}</Text>
            </Space>
            <Text type="secondary">{mm.w}×{mm.h} mm {r?`(${r.w}×${r.h}px)`:""}</Text>
          </div>
        );
      })}
      <Divider />
      <Space direction="vertical" size={2}>
        <Tag color="geekblue">Bold lines</Tag>
        <Text type="secondary">face seams</Text>
        <Tag color="default">Dashed</Tag>
        <Text type="secondary">hinges between faces</Text>
      </Space>
    </>
  );
}
