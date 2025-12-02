import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import StatusTags from './StatusTags';
import { ALL_STATUSES } from '../utils/statusUtils';
const StatusLegend = () => (_jsxs("div", { children: [_jsx("strong", { children: "Status Legend:" }), " ", _jsx(StatusTags, { statuses: ALL_STATUSES })] }));
export default StatusLegend;
