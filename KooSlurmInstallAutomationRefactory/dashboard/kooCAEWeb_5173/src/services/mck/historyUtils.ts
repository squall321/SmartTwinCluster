// src/services/mck/historyUtils.ts

import { SystemHistoryState } from '../../types/mck/historyTypes';
import { MCKSystem } from '../../types/mck/modelTypes';

export const applyChange = (
  state: SystemHistoryState,
  newPresent: MCKSystem
): SystemHistoryState => ({
  past: [...state.past, state.present],
  present: newPresent,
  future: [],
});

export const undo = (state: SystemHistoryState): SystemHistoryState => {
  if (state.past.length === 0) return state;
  const previous = state.past[state.past.length - 1];
  const newPast = state.past.slice(0, -1);
  return {
    past: newPast,
    present: previous,
    future: [state.present, ...state.future],
  };
};

export const redo = (state: SystemHistoryState): SystemHistoryState => {
  if (state.future.length === 0) return state;
  const next = state.future[0];
  const newFuture = state.future.slice(1);
  return {
    past: [...state.past, state.present],
    present: next,
    future: newFuture,
  };
};
