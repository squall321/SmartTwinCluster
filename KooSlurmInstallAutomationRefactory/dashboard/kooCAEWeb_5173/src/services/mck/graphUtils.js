// src/services/mck/graphUtils.ts
export const createEmptySystem = () => ({
    masses: [],
    springs: [],
    dampers: [],
    forces: [],
    fixedPoints: [],
});
export const addMass = (system, mass) => ({
    ...system,
    masses: [...system.masses, mass],
});
export const addSpring = (system, spring) => ({
    ...system,
    springs: [...system.springs, spring],
});
export const addDamper = (system, damper) => ({
    ...system,
    dampers: [...system.dampers, damper],
});
export const addForce = (system, force) => ({
    ...system,
    forces: [...system.forces, force],
});
