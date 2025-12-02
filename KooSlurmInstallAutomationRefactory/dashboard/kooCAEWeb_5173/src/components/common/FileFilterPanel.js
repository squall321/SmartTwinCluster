import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { Select, Input, Button, Space } from 'antd';
const FileFilterPanel = ({ selectedDate, selectedMode, prefix, onDateChange, onModeChange, onPrefixChange, onLoad, allDates, allModes, }) => {
    return (_jsxs(Space, { direction: "horizontal", style: { marginBottom: 16, flexWrap: 'wrap' }, children: [_jsx(Select, { placeholder: "\uB0A0\uC9DC", value: selectedDate, onChange: onDateChange, options: allDates.map(date => ({ value: date, label: date })), allowClear: true, style: { minWidth: 150 } }), _jsx(Select, { placeholder: "\uBAA8\uB4DC", value: selectedMode, onChange: onModeChange, options: allModes.map(mode => ({ value: mode, label: mode })), allowClear: true, style: { minWidth: 140 } }), _jsx(Input, { placeholder: "Prefix (\uC608: taylor_A)", value: prefix, onChange: e => onPrefixChange(e.target.value), style: { minWidth: 200 } }), _jsx(Button, { type: "primary", onClick: onLoad, children: "\uD83D\uDCC2 Load" })] }));
};
export default FileFilterPanel;
