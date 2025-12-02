export interface MassNode {
    id: string;
    m: number;
    x: number;
    y: number;
    width?: number;
}
export type NodeId = string;
export interface SpringEdge {
    id: string;
    type: 'spring';
    k: number;
    from: NodeId;
    to: NodeId;
}
export interface DamperEdge {
    id: string;
    type: 'damper';
    c: number;
    from: NodeId;
    to: NodeId;
}
export interface Force {
    id: string;
    targetMassId: string;
    magnitude: number;
    frequency: number;
    phase?: number;
}
export interface FixedPoint {
    id: string;
    x: number;
    y: number;
}
export interface MCKSystem {
    masses: MassNode[];
    springs: SpringEdge[];
    dampers: DamperEdge[];
    fixedPoints: FixedPoint[];
    forces: Force[];
}
