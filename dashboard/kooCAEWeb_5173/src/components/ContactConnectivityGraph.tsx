import React, { useEffect, useMemo, useRef, useState } from "react";
import { Network, Data, Options } from "vis-network";   

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

// ---------- Types ----------
export type PartNode = {
  id: number | string;
  label: string; // e.g., "P202\n(PCB)"
  group?: string; // material/assembly cluster key
  mass?: number; // optional
  [k: string]: any;
};

export type TiedEdge = {
  id: string;
  from: number | string;
  to: number | string;
  kind: "TIED"; // discriminator
  type?: string; // e.g., CONTACT_TIED_SURFACE_TO_SURFACE_OFFSET_ID
  cid?: number;
  area?: number; // mm^2 (recommended)
  weight?: number; // seg count (optional)
  params?: Record<string, any>;
  label?: string; // will be shown on the edge
  title?: string; // tooltip
  color?: any;
  // optional time series for DR/step-n shape areas or forces if available
  series?: {
    t: number[]; // time in model units
    area?: number[]; // instantaneous contact area over time
  };
};

export type GeneralEdge = {
  id: string;
  from: number | string;
  to: number | string;
  kind: "GENERAL"; // discriminator
  type?: string; // e.g., CONTACT_AUTOMATIC_SURFACE_TO_SURFACE
  iface_id?: number; // internal contact interface id if any
  // Time-aggregated metrics (post-process summaries)
  metrics?: {
    tau_contact?: number; // 0~1 proportion of timesteps in contact
    Fn_avg?: number; // N
    Fn_max?: number; // N
    W_fric?: number; // J
    p_avg?: number; // MPa (optional, requires area)
  };
  // Optional raw series to drive slider/animation
  series?: {
    t: number[];
    Fn?: number[]; // N
    Ft?: number[]; // N
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

// ---------- Helpers ----------
const isTied = (e: TiedEdge | GeneralEdge): e is TiedEdge => e.kind === "TIED";

function clamp(n: number, a: number, b: number) {
  return Math.max(a, Math.min(b, n));
}

// width scaler presets
const widthFromLog = (x: number, k = 0.9, bias = 1) => (Number.isFinite(x) && x > 0 ? bias + Math.log1p(x) * k : 1);
const widthFromSqrt = (x: number, k = 0.2, bias = 1) => (Number.isFinite(x) && x > 0 ? bias + Math.sqrt(x) * k : 1);

// color alpha by stick ratio (for GENERAL); fallback to gray
function colorByStickRatio(stick: number | undefined) {
  const alpha = clamp(0.2 + (stick ?? 0) * 0.8, 0.2, 1.0);
  return { color: `rgba(80,80,80,${alpha})`, highlight: "#333" };
}

// ---------- Component ----------
export type WeightMode =
  | "tied-area" // TIED: use area
  | "tied-weight" // TIED: use segment count
  | "gen-tau" // GENERAL: tau_contact
  | "gen-Fn" // GENERAL: Fn_avg
  | "gen-Wfric" // GENERAL: W_fric
  | "gen-p"; // GENERAL: p_avg

export type ContactConnectivityGraphProps = {
  data: GraphData;
  initialWeightMode?: WeightMode;
  initialPhysics?: boolean;
  initialHierarchical?: boolean;
  height?: number | string;
};

const ContactConnectivityGraph: React.FC<ContactConnectivityGraphProps> = ({
  data,
  initialWeightMode = "tied-area",
  initialPhysics = true,
  initialHierarchical = false,
  height = 640,
}) => {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const networkRef = useRef<Network | null>(null);

  // UI state
  const [weightMode, setWeightMode] = useState<WeightMode>(initialWeightMode);
  const [physics, setPhysics] = useState<boolean>(initialPhysics);
  const [hierarchical, setHierarchical] = useState<boolean>(initialHierarchical);
  const [minEdgeThreshold, setMinEdgeThreshold] = useState<number>(0); // filter small edges by metric
  const [groupFilter, setGroupFilter] = useState<string>("ALL");
  const [searchTerm, setSearchTerm] = useState<string>("");
  const [timeIdx, setTimeIdx] = useState<number>(0); // slider idx for series preview
  const [useSeries, setUseSeries] = useState<boolean>(false); // toggle series-driven preview

  // collect group list from nodes
  const groups = useMemo(() => {
    const s = new Set<string>();
    data.nodes.forEach((n) => n.group && s.add(n.group));
    return ["ALL", ...Array.from(s).sort()];
  }, [data.nodes]);

  // find global time axis if any (first edge with series)
  const globalT = useMemo(() => {
    for (const e of data.edges) {
      const series = isTied(e) ? e.series : e.series;
      if (series?.t && series.t.length > 0) return series.t;
    }
    return [] as number[];
  }, [data.edges]);

  // Filter nodes by group and search term
  const filteredNodes = useMemo(() => {
    const term = searchTerm.trim().toLowerCase();
    return data.nodes.filter((n) => {
      const groupOk = groupFilter === "ALL" || n.group === groupFilter;
      if (!groupOk) return false;
      if (!term) return true;
      return `${n.id}`.toLowerCase().includes(term) || (n.label ?? "").toLowerCase().includes(term);
    });
  }, [data.nodes, groupFilter, searchTerm]);

  const nodeIdsSet = useMemo(() => new Set(filteredNodes.map((n) => n.id)), [filteredNodes]);

  // Compute displayed edges based on weight mode, thresholds, group filter, time slider
  const displayedEdges = useMemo(() => {
    const edges: any[] = [];
    for (const e of data.edges) {
      // node filter: only keep edges whose endpoints are both visible
      if (!nodeIdsSet.has(e.from) || !nodeIdsSet.has(e.to)) continue;

      let value = 0; // drives thickness via vis-network scaling
      let label = e.label;
      let color = e.color;

      if (isTied(e)) {
        if (weightMode === "tied-area") {
          let a = e.area ?? 0;
          if (useSeries && e.series?.area && e.series.area.length) {
            const idx = clamp(timeIdx, 0, e.series.area.length - 1);
            a = e.series.area[idx] ?? a;
          }
          value = widthFromLog(a);
          label = label ?? `${(a).toFixed(1)} mm²`;
        } else if (weightMode === "tied-weight") {
          const w = e.weight ?? 0;
          value = widthFromLog(w);
          label = label ?? `${w} seg`;
        } else {
          // in GENERAL modes, still show tied edges thinly
          value = 1;
        }
        color = color ?? { color: "#888", highlight: "#444" };
      } else {
        const m = e.metrics || {};
        if (weightMode === "gen-tau") {
          const x = m.tau_contact ?? 0;
          value = widthFromSqrt(x, 3.5); // amplify small 0~1
          label = label ?? `${(x * 100).toFixed(0)}%`;
          color = colorByStickRatio(m.tau_contact);
        } else if (weightMode === "gen-Fn") {
          const x = m.Fn_avg ?? 0;
          value = widthFromLog(x);
          label = label ?? `${x.toFixed(0)} N`;
          color = colorByStickRatio(m.tau_contact);
        } else if (weightMode === "gen-Wfric") {
          const x = m.W_fric ?? 0;
          value = widthFromLog(x);
          label = label ?? `${x.toFixed(2)} J`;
          color = colorByStickRatio(m.tau_contact);
        } else if (weightMode === "gen-p") {
          const x = m.p_avg ?? 0;
          value = widthFromLog(x);
          label = label ?? `${x.toFixed(2)} MPa`;
          color = colorByStickRatio(m.tau_contact);
        } else {
          value = 1;
        }
      }

      // threshold filtering based on raw metric instead of drawn width
      const rawMetric = (() => {
        if (isTied(e)) {
          if (weightMode === "tied-area") return e.area ?? 0;
          if (weightMode === "tied-weight") return e.weight ?? 0;
          return 0;
        } else {
          const m = e.metrics || {};
          switch (weightMode) {
            case "gen-tau":
              return m.tau_contact ?? 0;
            case "gen-Fn":
              return m.Fn_avg ?? 0;
            case "gen-Wfric":
              return m.W_fric ?? 0;
            case "gen-p":
              return m.p_avg ?? 0;
            default:
              return 0;
          }
        }
      })();

      if (rawMetric < minEdgeThreshold) continue;

      edges.push({
        id: e.id,
        from: e.from,
        to: e.to,
        arrows: isTied(e) ? "to" : undefined, // general contacts are usually undirected
        value,
        label,
        title: e.title,
        color,
        dynaType: e.type,
      });
    }
    return edges;
  }, [data.edges, nodeIdsSet, weightMode, minEdgeThreshold, timeIdx, useSeries]);

  const visData: Data = useMemo(
    () => ({ nodes: filteredNodes as any, edges: displayedEdges as any }),
    [filteredNodes, displayedEdges]
  );

  // Build/update Network
  useEffect(() => {
    if (!containerRef.current) return;

    const options: Options = {
      autoResize: true,
      height: typeof height === "number" ? `${height}px` : height,
      layout: hierarchical
        ? {
            hierarchical: {
              direction: "UD",
              nodeSpacing: 150,
              levelSeparation: 180,
              sortMethod: "directed",
            },
          }
        : { improvedLayout: true },
      physics: physics
        ? {
            enabled: true,
            solver: "forceAtlas2Based",
            forceAtlas2Based: { gravitationalConstant: -30, springLength: 150 },
            stabilization: { iterations: 400, updateInterval: 50 },
          }
        : { enabled: false },
      nodes: {
        shape: "box",
        margin: { top: 8, right: 8, bottom: 8, left: 8 },
        font: { face: "Inter, Roboto, Arial", size: 14, multi: "md", bold: { size: 14 } },
        borderWidth: 1,
        color: {
          background: "#fff",
          border: "#bbb",
          highlight: { background: "#fff", border: "#444" },
        },
      },
      edges: {
        // `value` controls thickness; we let vis scale automatically
        smooth: { enabled: true, type: "dynamic", roundness: 0.5 },
        selectionWidth: 2,
        font: { align: "horizontal", size: 11 },
        color: { color: "#999", highlight: "#333" },
      },
      interaction: {
        hover: true,
        multiselect: true,
        dragView: true,
        navigationButtons: true,
        tooltipDelay: 120,
        keyboard: { enabled: true, bindToWindow: true },
      },
      groups: {
        // You can theme by group name; override in your dataset if desired
      },
    };

    // Create or update
    if (!networkRef.current) {
      networkRef.current = new Network(containerRef.current, visData, options);

      // Interaction handlers
      networkRef.current.on("doubleClick", (params) => {
        if (params.nodes?.length) {
          networkRef.current?.focus(params.nodes[0], { scale: 1.1, animation: true });
        }
      });
    } else {
      // Only updating options that change frequently
      networkRef.current.setOptions({
        physics: options.physics,
        layout: options.layout,
      });
      networkRef.current.setData(visData);
    }

    return () => {
      // DO NOT destroy on every state change—only when unmounting
    };
  }, [visData, physics, hierarchical, height]);

  // Export helpers
  const exportPNG = () => {
    const canvas: HTMLCanvasElement | undefined = (containerRef.current?.getElementsByTagName("canvas")?.[0] as any) || undefined;
    if (!canvas) return;
    const link = document.createElement("a");
    link.download = `contact_graph.png`;
    link.href = canvas.toDataURL("image/png");
    link.click();
  };

  const exportFilteredJSON = () => {
    const blob = new Blob([JSON.stringify({ meta: data.meta, nodes: filteredNodes, edges: displayedEdges }, null, 2)], {
      type: "application/json",
    });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = "contact_graph_filtered.json";
    a.click();
    URL.revokeObjectURL(url);
  };

  // Focus first match of search term when pressing Enter
  const onSearchKeyDown: React.KeyboardEventHandler<HTMLInputElement> = (e) => {
    if (e.key !== "Enter") return;
    const term = searchTerm.trim().toLowerCase();
    if (!term) return;
    const node = filteredNodes.find((n) => `${n.id}`.toLowerCase() === term || (n.label ?? "").toLowerCase().includes(term));
    if (node) networkRef.current?.focus(node.id, { scale: 1.2, animation: true });
  };

  // UI Controls
  return (
    <div className="w-full">
      <div className="flex flex-wrap items-center gap-3 mb-3">
        <label className="text-sm font-medium">Weight</label>
        <select
          className="border rounded px-2 py-1"
          value={weightMode}
          onChange={(e) => setWeightMode(e.target.value as WeightMode)}
          title="Choose which metric controls edge thickness"
        >
          <optgroup label="TIED">
            <option value="tied-area">Area (mm²)</option>
            <option value="tied-weight">Segment Count</option>
          </optgroup>
          <optgroup label="GENERAL">
            <option value="gen-tau">Contact Ratio (τ)</option>
            <option value="gen-Fn">Avg Normal Force (N)</option>
            <option value="gen-Wfric">Friction Work (J)</option>
            <option value="gen-p">Avg Pressure (MPa)</option>
          </optgroup>
        </select>

        <label className="text-sm font-medium ml-4">Group</label>
        <select className="border rounded px-2 py-1" value={groupFilter} onChange={(e) => setGroupFilter(e.target.value)}>
          {groups.map((g) => (
            <option key={g} value={g}>
              {g}
            </option>
          ))}
        </select>

        <label className="text-sm font-medium ml-4">Min Threshold</label>
        <input
          type="number"
          step="any"
          className="border rounded px-2 py-1 w-28"
          value={minEdgeThreshold}
          onChange={(e) => setMinEdgeThreshold(parseFloat(e.target.value || "0"))}
          title="Hide edges smaller than this metric"
        />

        <label className="text-sm font-medium ml-4">Search</label>
        <input
          className="border rounded px-2 py-1 w-52"
          placeholder="Part ID or label contains..."
          value={searchTerm}
          onChange={(e) => setSearchTerm(e.target.value)}
          onKeyDown={onSearchKeyDown}
        />

        <label className="text-sm font-medium ml-4">Physics</label>
        <input type="checkbox" checked={physics} onChange={(e) => setPhysics(e.target.checked)} />

        <label className="text-sm font-medium ml-2">Hierarchical</label>
        <input type="checkbox" checked={hierarchical} onChange={(e) => setHierarchical(e.target.checked)} />

        <button className="ml-auto border rounded px-3 py-1" onClick={exportPNG} title="Export PNG">
          Export PNG
        </button>
        <button className="border rounded px-3 py-1" onClick={exportFilteredJSON} title="Export filtered JSON">
          Export JSON
        </button>
      </div>

      {/* Time slider */}
      <div className="flex items-center gap-3 mb-2">
        <label className="text-sm font-medium">Use Series</label>
        <input type="checkbox" checked={useSeries} onChange={(e) => setUseSeries(e.target.checked)} />
        <input
          type="range"
          className="flex-1"
          min={0}
          max={Math.max(0, (globalT?.length ?? 1) - 1)}
          value={timeIdx}
          onChange={(e) => setTimeIdx(parseInt(e.target.value))}
          disabled={!useSeries || (globalT?.length ?? 0) === 0}
        />
        <div className="text-xs w-28 text-right">
          {useSeries && globalT.length > 0 ? `t=${globalT[timeIdx].toFixed(4)}` : "t=—"}
        </div>
      </div>

      {/* Graph container */}
      <div ref={containerRef} style={{ width: "100%", height: typeof height === "number" ? `${height}px` : height }} />
    </div>
  );
};

export default ContactConnectivityGraph;
