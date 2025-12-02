import { jsx as _jsx } from "react/jsx-runtime";
import { useMemo } from 'react';
import BaseLayout from '../layouts/BaseLayout';
import { Typography } from 'antd';
const { Title, Paragraph } = Typography;
import ContactConnectivityGraph from '../components/ContactConnectivityGraph';
const data = {
    meta: {
        model: "Phone_v12",
        run_id: "2025-08-27T15:20:00+09:00",
        unit: { length: "mm", area: "mm^2", force: "N", energy: "J", time: "ms" },
    },
    nodes: [
        { id: 101, label: "P101\n(Al Cover)", group: "Metal", mass: 2.3 },
        { id: 202, label: "P202\n(PCB)", group: "FR4", mass: 18.5 },
        { id: 303, label: "P303\n(Glass)", group: "Glass", mass: 5.4 },
        { id: 404, label: "P404\n(Battery)", group: "EE", mass: 22.1 },
    ],
    edges: [
        // --- TIED examples (Slave -> Master) ---
        {
            id: "t-101-202-92",
            from: 101,
            to: 202,
            kind: "TIED",
            type: "CONTACT_TIED_SURFACE_TO_SURFACE_OFFSET_ID",
            cid: 92,
            area: 325.7,
            weight: 128,
            label: "TIED_OFFSET",
            title: "CID=92, area=325.7 mm², seg=128, SOFT=2",
            series: {
                t: [0, 0.1, 0.2, 0.3, 0.4],
                area: [300, 320, 340, 335, 330],
            },
        },
        {
            id: "t-303-202-93",
            from: 303,
            to: 202,
            kind: "TIED",
            type: "CONTACT_TIED_NODES_TO_SURFACE",
            cid: 93,
            area: 54.2,
            weight: 24,
            label: "TIED_N2S",
            title: "CID=93, area=54.2 mm², seg=24, SOFT=1",
        },
        // --- GENERAL examples (undirected visually) ---
        {
            id: "g-404-202-if12",
            from: 404,
            to: 202,
            kind: "GENERAL",
            type: "CONTACT_AUTOMATIC_SURFACE_TO_SURFACE",
            label: "AUTO S2S",
            title: "General contact between Battery and PCB",
            metrics: { tau_contact: 0.62, Fn_avg: 185.3, Fn_max: 920.1, W_fric: 0.84, p_avg: 0.73 },
            series: {
                t: [0, 0.1, 0.2, 0.3, 0.4],
                Fn: [0, 45, 210, 120, 30],
                Ft: [0, 12, 70, 40, 10],
                is_contact: [0, 1, 1, 1, 0],
            },
        },
        {
            id: "g-101-303-if21",
            from: 101,
            to: 303,
            kind: "GENERAL",
            type: "CONTACT_AUTOMATIC_NODES_TO_SURFACE",
            label: "AUTO N2S",
            title: "Cover-Glass intermittent contact",
            metrics: { tau_contact: 0.18, Fn_avg: 22.5, Fn_max: 210.0, W_fric: 0.05, p_avg: 0.12 },
            series: {
                t: [0, 0.1, 0.2, 0.3, 0.4],
                Fn: [0, 0, 35, 15, 0],
                Ft: [0, 0, 12, 5, 0],
                is_contact: [0, 0, 1, 1, 0],
            },
        },
    ],
};
const ComponentTestMetaDataPage = () => {
    const curData = useMemo(() => data, []);
    return (_jsx(BaseLayout, { isLoggedIn: true, children: _jsx("div", { style: { padding: 24, backgroundColor: '#fff', minHeight: '100vh', borderRadius: '24px' }, children: _jsx(ContactConnectivityGraph, { data: curData }) }) }));
};
export default ComponentTestMetaDataPage;
