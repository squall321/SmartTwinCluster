// src/services/mck/historyUtils.ts
export const applyChange = (state, newPresent) => ({
    past: [...state.past, state.present],
    present: newPresent,
    future: [],
});
export const undo = (state) => {
    if (state.past.length === 0)
        return state;
    const previous = state.past[state.past.length - 1];
    const newPast = state.past.slice(0, -1);
    return {
        past: newPast,
        present: previous,
        future: [state.present, ...state.future],
    };
};
export const redo = (state) => {
    if (state.future.length === 0)
        return state;
    const next = state.future[0];
    const newFuture = state.future.slice(1);
    return {
        past: [...state.past, state.present],
        present: next,
        future: newFuture,
    };
};
