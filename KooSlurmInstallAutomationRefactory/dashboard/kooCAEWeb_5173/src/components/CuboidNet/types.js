export const FACE_COLOR = {
    "+X": "#1677FF",
    "-X": "#FA8C16",
    "+Y": "#52C41A",
    "-Y": "#13C2C2",
    "+Z": "#722ED1",
    "-Z": "#EB2F96",
};
export const PRESETS = {
    "Compact 3×2": [
        ["+X", "-X", "+Y"],
        ["-Y", "+Z", "-Z"],
    ],
    "Vertical Cross 3×4": [
        [null, "+Y", null],
        ["-X", "+Z", "+X"],
        [null, "-Y", null],
        [null, "-Z", null],
    ],
    "Horizontal Cross 4×3": [
        [null, "+Y", null, null],
        ["-X", "+Z", "+X", "-Z"],
        [null, "-Y", null, null],
    ],
    "Strip 6×1": [["-X", "+Z", "+X", "-Z", "+Y", "-Y"]],
};
