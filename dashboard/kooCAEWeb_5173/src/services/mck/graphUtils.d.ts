import { MCKSystem, MassNode, SpringEdge, Force, DamperEdge } from '../../types/mck/modelTypes';
export declare const createEmptySystem: () => MCKSystem;
export declare const addMass: (system: MCKSystem, mass: MassNode) => MCKSystem;
export declare const addSpring: (system: MCKSystem, spring: SpringEdge) => MCKSystem;
export declare const addDamper: (system: MCKSystem, damper: DamperEdge) => MCKSystem;
export declare const addForce: (system: MCKSystem, force: Force) => MCKSystem;
