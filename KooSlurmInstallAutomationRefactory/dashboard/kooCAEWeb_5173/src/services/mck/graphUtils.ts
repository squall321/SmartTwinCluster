// src/services/mck/graphUtils.ts

import { MCKSystem, MassNode, SpringEdge, Force, DamperEdge } from '../../types/mck/modelTypes';

export const createEmptySystem = (): MCKSystem => ({
  masses: [],
  springs: [],
  dampers: [],
  forces: [],
  fixedPoints: [],
});

export const addMass = (system: MCKSystem, mass: MassNode): MCKSystem => ({
  ...system,
  masses: [...system.masses, mass],
});

export const addSpring = (system: MCKSystem, spring: SpringEdge): MCKSystem => ({
  ...system,
  springs: [...system.springs, spring],
});

export const addDamper = (system: MCKSystem, damper: DamperEdge): MCKSystem => ({
  ...system,
  dampers: [...system.dampers, damper],
});

export const addForce = (system: MCKSystem, force: Force): MCKSystem => ({
  ...system,
  forces: [...system.forces, force],
});
