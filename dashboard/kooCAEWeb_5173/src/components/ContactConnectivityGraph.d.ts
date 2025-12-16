import React from "react";
/**
 * ContactConnectivityGraph.tsx
 * -----------------------------------------------------------
 * All-in-one vis-network component to visualize LS-DYNA part-to-part
 * connectivity for both TIED and non-TIED (general) contacts.
 *
 * Features
 * - Accepts unified JSON (nodes, edges) with optional meta
 * - Supports TIED edges (area-weighted) and general contacts (time-aggregated metrics)
 * - Toggle which weight metric drives edge thickness
 * - Time slider to preview series-based values (Fn/Ft/contact state)
 * - Group filter, edge thresholding, physics/hierarchical layout toggles
 * - Search/focus by Part ID or label substring
 * - Export current view to PNG & export filtered JSON
 *
 * External deps: `vis-network` and optional CSS reset in host app
 *
 * -----------------------------------------------------------
 */
export type PartNode = {
    id: number | string;
    label: string;
    group?: string;
    mass?: number;
    [k: string]: any;
};
export type TiedEdge = {
    id: string;
    from: number | string;
    to: number | string;
    kind: "TIED";
    type?: string;
    cid?: number;
    area?: number;
    weight?: number;
    params?: Record<string, any>;
    label?: string;
    title?: string;
    color?: any;
    series?: {
        t: number[];
        area?: number[];
    };
};
export type GeneralEdge = {
    id: string;
    from: number | string;
    to: number | string;
    kind: "GENERAL";
    type?: string;
    iface_id?: number;
    metrics?: {
        tau_contact?: number;
        Fn_avg?: number;
        Fn_max?: number;
        W_fric?: number;
        p_avg?: number;
    };
    series?: {
        t: number[];
        Fn?: number[];
        Ft?: number[];
        is_contact?: (0 | 1)[];
    };
    label?: string;
    title?: string;
    color?: any;
};
export type GraphData = {
    meta?: Record<string, any>;
    nodes: PartNode[];
    edges: Array<TiedEdge | GeneralEdge>;
};
export type WeightMode = "tied-area" | "tied-weight" | "gen-tau" | "gen-Fn" | "gen-Wfric" | "gen-p";
export type ContactConnectivityGraphProps = {
    data: GraphData;
    initialWeightMode?: WeightMode;
    initialPhysics?: boolean;
    initialHierarchical?: boolean;
    height?: number | string;
};
declare const ContactConnectivityGraph: React.FC<ContactConnectivityGraphProps>;
export default ContactConnectivityGraph;
